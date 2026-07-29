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
    # THREE DEFENCES, in the order they run. They are layered rather than redundant, because the
    # S-07-006 review proved the previous two-defence design had ONE live defence: three of its four
    # abort callbacks (`start_document_type`, `internal_subset`, `external_subset`) are not part of
    # `Nokogiri::XML::SAX::Document`'s callback surface at all — libxml2 never invokes them, in any
    # encoding — so a `<!DOCTYPE>` that got past the byte scan was parsed silently.
    #
    #   1. AN ENCODING GATE. :450 accepts "UTF-8 XML only", and that is enforced here as a security
    #      control, not a formality. libxml2 auto-detects UTF-16/UTF-32 from the leading bytes with
    #      NO byte-order mark, and the NUL-interleaved result is itself valid UTF-8 — so a raw-byte
    #      scan for `<!DOCTYPE` sees nothing while the parser happily decodes and processes it. That
    #      is an encoding-confusion bypass of defence 2, and pinning the encoding closes the whole
    #      class at the door rather than chasing each spelling downstream.
    #   2. A PRE-PARSE BYTE SCAN rejects `<!DOCTYPE` and `<!ENTITY` before Nokogiri is handed
    #      anything. :450 says "Code rejects `DOCTYPE` BEFORE parsing" — before, not by configuring
    #      the parser to ignore it — so a declaration never reaches an entity resolver at all. It is
    #      authoritative only because defence 1 guarantees the bytes it scans are the bytes libxml2
    #      will interpret.
    #   3. A PROLOG INSPECTION using libxml2's OWN lexer, via `Nokogiri::XML::Reader` in `NONET`
    #      mode with DTD loading, DTD attribute defaulting, entity substitution and XInclude all
    #      off. The reader is pulled only as far as the root element, so it costs a prolog rather
    #      than a document, and it reports a `TYPE_DOCUMENT_TYPE` node for any DOCTYPE — including
    #      one written in a way the byte scan does not anticipate. This is the independent mechanism
    #      the dead callbacks were supposed to be: it is driven by the same parser that would do the
    #      resolving, so it cannot disagree with it about what the document says.
    #
    # The SAX pass then runs with recovery and entity substitution off, and `reference` — the one
    # abort callback that IS real — aborts on any entity reference that survives all three.
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

      UNSAFE = "sitemap_xml_unsafe"
      LIMIT = "sitemap_xml_limit"
      MALFORMED = "sitemap_malformed"
      UNSUPPORTED_MEDIA = "sitemap_unsupported_media_type"

      # Constructs that must never reach the parser. Matched case-insensitively on the raw bytes,
      # because an entity declaration is dangerous whatever its casing.
      PROHIBITED = /<!DOCTYPE|<!ENTITY/i
      # XInclude is a namespace, not a declaration, so it is caught by name.
      XINCLUDE = %r{http://www\.w3\.org/2001/XInclude}i

      # A UTF-8 byte-order mark is legal and is stripped; every other BOM names an encoding :450 does
      # not accept, and is refused rather than transcoded.
      UTF8_BOM = "\xEF\xBB\xBF"
      FOREIGN_BOMS = ["\xFF\xFE", "\xFE\xFF", "\x00\x00\xFE\xFF", "\xFF\xFE\x00\x00"].freeze

      # An XML declaration may name its own encoding. Only UTF-8 and its ASCII subset are accepted;
      # anything else is refused even when the bytes happen to decode, because the declaration is
      # what libxml2 would act on.
      XML_DECL = /\A<\?xml[^>]*?encoding\s*=\s*["']([^"']+)["']/i
      ACCEPTED_ENCODINGS = %w[utf-8 utf8 us-ascii ascii].freeze

      # `NONET` forbids network access; the remaining defaults are asserted explicitly rather than
      # assumed, so a future libxml2 that changes a default cannot silently widen this boundary.
      READER_OPTIONS = ::Nokogiri::XML::ParseOptions::NONET

      # `urls` are `<url><loc>` entries, `sitemaps` are `<sitemap><loc>` entries (a sitemap index).
      # `reason` is nil on success and one of the :450 reason codes otherwise.
      Result = Data.define(:ok, :urls, :sitemaps, :reason, :start_elements, :character_bytes) do
        def ok? = ok
      end

      def failure(reason) = Result.new(ok: false, urls: [], sitemaps: [], reason:,
                                       start_elements: 0, character_bytes: 0)

      # :450 — "media type before parameters".
      def media_type_supported?(content_type)
        MEDIA_TYPES.include?(content_type.to_s.split(";").first.to_s.strip.downcase)
      end

      # Parse a sitemap or sitemap index. `body` is raw bytes as received.
      def parse(body, content_type: nil)
        # FAIL CLOSED on the media type. An ABSENT `Content-Type` is not one of the three :450 names
        # any more than `text/html` is, and the header is attacker-controlled — so treating "missing"
        # as "acceptable" let a response opt out of the allowlist simply by omitting it.
        return failure(UNSUPPORTED_MEDIA) unless media_type_supported?(content_type)

        bytes = body.to_s.b
        # :450 — the received 10 MiB bound "is also the expanded-input bound", because no
        # entity-expanded or remotely obtained bytes can exist once the defences below hold.
        return failure(LIMIT) if bytes.bytesize > MAX_CHARACTER_BYTES

        # DEFENCE 1: pin the encoding, so defences 2 and 3 read what libxml2 will read.
        bytes = utf8_or_nil(bytes)
        return failure(MALFORMED) if bytes.nil?
        # DEFENCE 2: reject before parsing, so no declaration ever reaches an entity resolver.
        return failure(UNSAFE) if PROHIBITED.match?(bytes) || XINCLUDE.match?(bytes)
        # DEFENCE 3: ask libxml2 itself whether the prolog declares a document type.
        prolog = prolog_verdict(bytes)
        return failure(prolog) if prolog

        stream(bytes)
      end

      # :450 accepts "UTF-8 XML only". Returns the body with any UTF-8 BOM removed, or nil when the
      # bytes are not UTF-8 — which covers a foreign BOM, a foreign declared encoding, an invalid
      # UTF-8 sequence, and a NUL byte.
      def utf8_or_nil(bytes)
        return nil if FOREIGN_BOMS.any? { |bom| bytes.start_with?(bom.b) }

        body = bytes.start_with?(UTF8_BOM.b) ? bytes.byteslice(3, bytes.bytesize - 3) : bytes
        # A NUL byte is illegal in XML 1.0 at every position, and it is exactly what BOM-less UTF-16
        # and UTF-32 look like as raw bytes — the encoding-confusion vector defence 1 exists to stop.
        return nil if body.include?("\x00")
        return nil unless body.dup.force_encoding(Encoding::UTF_8).valid_encoding?

        declared = XML_DECL.match(body)&.captures&.first
        return nil if declared && !ACCEPTED_ENCODINGS.include?(declared.strip.downcase)

        body
      end

      # Pull libxml2's own reader across the prolog only, stopping at the root element. Returns a
      # reason code when the document declares a type, and nil when the prolog is clean. A reader
      # error here is NOT treated as malformed: the SAX pass below is the authority on well-formedness
      # and produces the precise reason, so a disagreement must not pre-empt it.
      def prolog_verdict(bytes)
        reader = ::Nokogiri::XML::Reader.from_memory(bytes, nil, "UTF-8", READER_OPTIONS)
        reader.each do |node|
          return UNSAFE if node.node_type == ::Nokogiri::XML::Reader::TYPE_DOCUMENT_TYPE
          break if node.node_type == ::Nokogiri::XML::Reader::TYPE_ELEMENT
        end
        nil
      rescue StandardError
        nil
      end

      def stream(bytes)
        document = Document.new
        parser = ::Nokogiri::XML::SAX::Parser.new(document)
        begin
          # Entity substitution off, and no error recovery — a malformed document is refused rather
          # than guessed at, because guessing changes which URLs it names.
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
            # `<loc>` names another sitemap only when its IMMEDIATE parent is `<sitemap>`, and a
            # content URL otherwise. Testing the whole stack instead let a document nest `<url>`
            # inside `<sitemap>` and thereby choose which of two code paths its URLs entered — an
            # attacker-controlled document does not get to make that choice.
            (@stack[-2] == "sitemap" ? @sitemaps : @urls) << @buffer.strip
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

        # The one abort callback libxml2 actually invokes. An entity reference reaching here means a
        # declaration survived all three defences; aborting rather than ignoring is the point.
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
