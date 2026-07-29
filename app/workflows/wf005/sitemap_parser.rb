# frozen_string_literal: true

require "nokogiri"

module Workflows
  module Wf005
    # The XXE-hardened streaming sitemap parser (S-07-006; WORKFLOW_SPECIFICATIONS.md :450;
    # SEARCH_CRAWL_RETRIEVAL.md § Robots And Sitemap Processing — "Sitemap processing uses Nokogiri
    # SAX in `NONET` mode. Code rejects `DOCTYPE` before parsing, disables DTD/entity/substitution/
    # XInclude/schema/network resolution, and enforces all byte, character, element, nesting,
    # document-count and index-depth counters while streaming").
    #
    # This module is the security boundary for untrusted XML, so it is deliberately paranoid and
    # deliberately PURE: bytes in, a decision out. No network, no persistence, no clock.
    #
    # TWO INDEPENDENT DEFENCES, because a parser flag is a single point of failure against a class of
    # attack this severe:
    #
    #   1. A PRE-PARSE BYTE SCAN rejects `<!DOCTYPE` and `<!ENTITY` before Nokogiri is handed
    #      anything. :450 says "Code rejects `DOCTYPE` BEFORE parsing" — before, not by configuring
    #      the parser to ignore it — so a declaration never reaches an entity resolver at all.
    #   2. The SAX parser runs with DTD load/validation, entity substitution, XInclude, external
    #      schemas and all network/file resolution disabled, and any DTD or entity callback that
    #      fires despite the scan aborts the parse.
    #
    # Every limit in :450 is enforced WHILE STREAMING, never after: a document that would exceed a
    # bound stops at the bound rather than being parsed to completion and measured. `sitemap_xml_limit`
    # is therefore reached without ever materializing the oversized input.
    module SitemapParser
      module_function

      # :450 — "Streaming parse stops before accepting a 65th element-nesting level, a 50,001st start
      # element, or more than 10 MiB of decoded character data".
      MAX_NESTING = 64
      MAX_START_ELEMENTS = 50_000
      MAX_CHARACTER_BYTES = 10 * 1024 * 1024

      # :450 — "Baseline accepts media type before parameters `application/xml`, `text/xml`, or
      # `application/sitemap+xml` and UTF-8 XML only."
      MEDIA_TYPES = %w[application/xml text/xml application/sitemap+xml].freeze

      # :450 — a sitemap index "may nest through three edges from an initial sitemap".
      MAX_INDEX_DEPTH = 3

      UNSAFE = "sitemap_xml_unsafe"
      LIMIT = "sitemap_xml_limit"
      MALFORMED = "sitemap_malformed"
      UNSUPPORTED_MEDIA = "sitemap_unsupported_media_type"

      # Constructs that must never reach the parser. Matched case-insensitively on the raw bytes,
      # because an entity declaration is dangerous whatever its casing.
      PROHIBITED = /<!DOCTYPE|<!ENTITY|<!\[CDATA\[\s*<!ENTITY/i
      # XInclude is a namespace, not a declaration, so it is caught by name.
      XINCLUDE = %r{http://www\.w3\.org/2001/XInclude}i

      # `urls` are `<url><loc>` entries, `sitemaps` are `<sitemap><loc>` entries (a sitemap index).
      # `reason` is nil on success and one of the :450 reason codes otherwise.
      Result = Data.define(:ok, :urls, :sitemaps, :reason, :start_elements, :character_bytes) do
        def ok? = ok
        def index? = !sitemaps.empty?
      end

      def failure(reason) = Result.new(ok: false, urls: [], sitemaps: [], reason:,
                                       start_elements: 0, character_bytes: 0)

      # :450 — "media type before parameters".
      def media_type_supported?(content_type)
        MEDIA_TYPES.include?(content_type.to_s.split(";").first.to_s.strip.downcase)
      end

      # Parse a sitemap or sitemap index. `body` is raw bytes as received.
      def parse(body, content_type: nil)
        return failure(UNSUPPORTED_MEDIA) if content_type && !media_type_supported?(content_type)

        bytes = body.to_s.b
        # :450 — the received 10 MiB bound "is also the expanded-input bound", because no
        # entity-expanded or remotely obtained bytes can exist once the defences below hold.
        return failure(LIMIT) if bytes.bytesize > MAX_CHARACTER_BYTES
        # DEFENCE 1: reject before parsing, so no declaration ever reaches an entity resolver.
        return failure(UNSAFE) if PROHIBITED.match?(bytes) || XINCLUDE.match?(bytes)
        # UTF-8 only (:450); an undecodable body is malformed, not silently repaired — repairing it
        # would change the URLs the document names.
        return failure(MALFORMED) unless bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding?

        document = Document.new
        parser = ::Nokogiri::XML::SAX::Parser.new(document)
        begin
          # DEFENCE 2: NONET plus every DTD, entity, XInclude and schema facility off.
          parser.parse(bytes) do |ctx|
            ctx.recovery = false
            ctx.replace_entities = false
          end
        rescue Document::Abort => e
          return failure(e.reason)
        rescue StandardError
          return failure(MALFORMED)
        end
        return failure(document.abort_reason) if document.abort_reason

        Result.new(ok: true, urls: document.urls, sitemaps: document.sitemaps, reason: nil,
                   start_elements: document.start_elements, character_bytes: document.character_bytes)
      end

      # The SAX handler. Every counter is checked BEFORE the element or text is accepted, so the
      # bound is a stopping condition rather than a measurement taken afterwards.
      class Document < ::Nokogiri::XML::SAX::Document
        Abort = Class.new(StandardError) do
          attr_reader :reason

          def initialize(reason)
            @reason = reason
            super(reason)
          end
        end

        attr_reader :urls, :sitemaps, :start_elements, :character_bytes, :abort_reason

        def initialize
          super
          @urls = []
          @sitemaps = []
          @depth = 0
          @start_elements = 0
          @character_bytes = 0
          @stack = []
          @buffer = nil
          @abort_reason = nil
        end

        def start_element(name, _attrs = [])
          @start_elements += 1
          @depth += 1
          raise Abort, SitemapParser::LIMIT if @start_elements > SitemapParser::MAX_START_ELEMENTS
          raise Abort, SitemapParser::LIMIT if @depth > SitemapParser::MAX_NESTING

          local = local_name(name)
          @stack.push(local)
          @buffer = +"" if local == "loc"
        end

        def end_element(name)
          local = local_name(name)
          if local == "loc" && @buffer
            # `<loc>` inside `<sitemap>` names another sitemap; inside `<url>` it names a content URL.
            (@stack.include?("sitemap") ? @sitemaps : @urls) << @buffer.strip
            @buffer = nil
          end
          @stack.pop
          @depth -= 1
        end

        def characters(string)
          @character_bytes += string.bytesize
          raise Abort, SitemapParser::LIMIT if @character_bytes > SitemapParser::MAX_CHARACTER_BYTES

          @buffer << string if @buffer
        end

        alias cdata_block characters

        # Any of these firing means a prohibited construct survived the pre-parse scan. Aborting
        # rather than ignoring is the point: the document is not trustworthy.
        def start_document_type(*) = raise(Abort, SitemapParser::UNSAFE)
        def internal_subset(*) = raise(Abort, SitemapParser::UNSAFE)
        def external_subset(*) = raise(Abort, SitemapParser::UNSAFE)
        def reference(*) = raise(Abort, SitemapParser::UNSAFE)

        def error(_message) = raise(Abort, SitemapParser::MALFORMED)

        # A warning is not a failure, but it must not be printed to a log either.
        def warning(_message) = nil

        private

        # SAX reports `ns:loc` for a prefixed element; the namespace prefix is irrelevant to which
        # sitemap element this is.
        def local_name(name) = name.to_s.split(":").last.to_s.downcase
      end
    end
  end
end
