# frozen_string_literal: true

require "nokogiri"
require "json"

module Workflows
  module Wf006
    # The mandatory normalized schema `parsed-observation-v1`
    # (WORKFLOW_SPECIFICATIONS.md :476), built from one Document's bytes.
    #
    # Pure and total: given bytes, a canonical URL, whether the Document is its Source root,
    # and the frozen scope policies, it returns one payload or raises nothing — a document
    # that cannot be understood produces recorded `malformed` items, never a gap. The
    # validator below is separate and is what a caller must pass before an Artifact is
    # written, because :476 ends with an exhaustive list of what makes a payload INVALID and
    # a normalizer that also judged itself would be marking its own work.
    #
    # IT CONSUMES ATTACKER-CONTROLLED BYTES. Every parse disables DTDs and external entities
    # (NOENT is never set, NONET is), and JSON-LD `@context` is read as data and never
    # dereferenced — :476 and the S-08 tenant_boundary row both say so, and the reason is
    # that a remote context fetch would be an unguarded egress path from inside the parser.
    module ParsedObservation
      module_function

      SCHEMA_VERSION = "parsed-observation-v1"
      PARSER_DEFINITION_VERSION = "html-parser-interim-v1"

      HTML = "html"
      XHTML = "xhtml"
      HTML_MEDIA = "text/html"
      XHTML_MEDIA = "application/xhtml+xml"

      # :480 "`text/html` and `application/xhtml+xml`, before media-type parameters, are the
      # only baseline supported inputs."
      SUPPORTED_MEDIA_TYPES = [HTML_MEDIA, XHTML_MEDIA].freeze

      # :476's exhaustive link-target rejection vocabulary.
      REJECT_EMPTY = "empty"
      REJECT_SCHEME = "unsupported_scheme"
      REJECT_INVALID = "invalid_url"
      REJECT_OUT_OF_SCOPE = "outside_source_scope"

      VALID = "valid"
      MALFORMED = "malformed"

      # :476 admits a JSON-LD node whose `@type` set "includes exact `Organization` or a
      # subtype declared by `structured-identity-v1`". THAT ARTIFACT DECLARES NO SUBTYPES
      # ANYWHERE IN THIS REPOSITORY — it is named and never defined — so the admitted set is
      # exactly `Organization`. Guessing schema.org's subtype tree here would be inventing
      # the artifact's content, which is precisely what an implementation must not do; when
      # the artifact exists its tokens join this constant.
      ORGANIZATION_TYPES = ["Organization"].freeze

      # A BCP-47 tag, shape-checked only: the registry is not ours to carry, and :476 asks
      # for a lower-case tag rather than a validated one.
      BCP47 = /\A[A-Za-z]{1,8}(-[A-Za-z0-9]{1,8})*\z/

      # The Source-root terminal-outcome map's exhaustive vocabulary (:476).
      TERMINAL_OUTCOMES = %w[document_valid content_absent content_fetch_failed policy_excluded].freeze

      # Build the payload. `terminal_outcomes` is the frozen Crawl map and is REQUIRED for a
      # Source root and forbidden otherwise, which the validator enforces rather than this.
      def build(bytes:, canonical_document_url:, media_type:, source_root:, scope_policies:,
                terminal_outcomes: nil)
        document = parse(bytes, media_type)
        payload = {
          "schema_version" => SCHEMA_VERSION,
          "canonical_document_url" => canonical_document_url,
          "document_kind" => kind_for(media_type),
          "document_language" => language_of(document),
          "title_nodes" => title_nodes(document),
          "link_edges" => link_edges(document, canonical_document_url, scope_policies),
          "organization_nodes" => organization_nodes(document)
        }
        payload["crawl_terminal_outcomes"] = terminal_outcomes if source_root
        payload
      end

      def supported_media_type?(media_type) = SUPPORTED_MEDIA_TYPES.include?(bare_media_type(media_type))

      # Media-type parameters are stripped before the comparison, per :480's "before
      # media-type parameters".
      def bare_media_type(media_type) = media_type.to_s.split(";").first.to_s.strip.downcase

      def kind_for(media_type) = bare_media_type(media_type) == XHTML_MEDIA ? XHTML : HTML

      # ---- parsing ---------------------------------------------------------------

      # NONET forbids any network access from libxml2 and NOENT is deliberately NOT set, so
      # entities are left unexpanded rather than substituted. DTDLOAD/DTDVALID are absent for
      # the same reason: an external DTD is a fetch and an expansion primitive.
      def parse(bytes, media_type)
        text = bytes.to_s.dup.force_encoding("UTF-8")
        text = text.encode("UTF-8", invalid: :replace, undef: :replace) unless text.valid_encoding?
        options = Nokogiri::XML::ParseOptions.new.nononet.nonoent
        if kind_for(media_type) == XHTML
          Nokogiri::XML(text) { |config| config.options = options.options }
        else
          Nokogiri::HTML5(text, max_errors: 0)
        end
      rescue StandardError
        # A document the parser cannot open at all still yields a payload: empty node lists
        # are a truthful observation ("this served nothing we could read"), and losing the
        # Document entirely would silently shrink the manifest.
        Nokogiri::HTML5("")
      end

      # :476 "nullable lower-case BCP-47 tag". Taken from the root element's `lang`, then
      # `xml:lang`; anything that is not tag-shaped is nil rather than a guess.
      def language_of(document)
        root = document.root
        return nil if root.nil?

        raw = (root["lang"] || root["xml:lang"]).to_s.strip
        return nil if raw.empty? || !raw.match?(BCP47)

        raw.downcase
      end

      # ---- title nodes -----------------------------------------------------------

      # :476 "ordered by document position ... zero-based `position`, `text` with HTML
      # character references decoded, and a stable `locator` of `head/title[n]`; blank text
      # is RETAINED". Nokogiri decodes character references when it exposes `text`, and the
      # blank case is the one worth naming: a `<title></title>` is a real observation that a
      # Check about titles must be able to see.
      def title_nodes(document)
        document.css("title").each_with_index.map do |node, index|
          { "position" => index, "text" => normalize(node.text.to_s), "locator" => "head/title[#{index}]" }
        end
      end

      # ---- link edges ------------------------------------------------------------

      # :476 "ordered by document position ... zero-based `position`, decoded `href`, stable
      # `locator`, `relation_tokens` as sorted distinct lower-case ASCII tokens, and EITHER
      # `target_canonical_url` OR `target_rejection_reason`".
      def link_edges(document, base_url, scope_policies)
        document.css("a[href], link[href]").each_with_index.map do |node, index|
          href = node["href"].to_s
          target = resolve_target(href, base_url, scope_policies)
          {
            "position" => index,
            "href" => normalize(href),
            "locator" => "#{node.name}[#{index}]",
            "relation_tokens" => relation_tokens(node),
            "target_canonical_url" => target[:url],
            "target_rejection_reason" => target[:reason]
          }
        end
      end

      def relation_tokens(node)
        node["rel"].to_s.split(/\s+/).map { |t| t.downcase.gsub(/[^a-z0-9\-]/, "") }
                   .reject(&:empty?).uniq.sort
      end

      # Exactly one of URL or reason, never both and never neither. The canonicalization and
      # the scope test are the FROZEN Crawl ones: `SourceScopePredicate` is the same module
      # the frontier admitted URLs with, so a link the crawl would have followed and a link
      # the parser calls in-scope cannot disagree.
      def resolve_target(href, base_url, scope_policies)
        trimmed = href.strip
        return { url: nil, reason: REJECT_EMPTY } if trimmed.empty?

        absolute = absolutize(trimmed, base_url)
        return { url: nil, reason: REJECT_INVALID } if absolute.nil?
        return { url: nil, reason: REJECT_SCHEME } unless absolute.start_with?("http://", "https://")

        decision = Workflows::Wf004::SourceScopePredicate.evaluate(url: absolute, policies: scope_policies)
        return { url: decision.canonical_url, reason: nil } if decision.allowed?

        # Every scope denial — wrong host, wrong scheme, wrong port, excluded or not included
        # path — collapses to the one reason :476 admits for it. A malformed URL is the
        # separate `invalid_url` above, so the two are not conflated.
        return { url: nil, reason: REJECT_INVALID } if decision.reason_code == "url_malformed"

        { url: nil, reason: REJECT_OUT_OF_SCOPE }
      end

      # Resolution against the Document's own canonical URL. A fragment-only or
      # scheme-relative reference resolves the way a browser resolves it; anything URI
      # cannot join is `invalid_url` rather than an exception.
      def absolutize(href, base_url)
        return href if href.match?(%r{\A[A-Za-z][A-Za-z0-9+.\-]*:})

        URI.join(base_url, href).to_s
      rescue StandardError
        nil
      end

      # ---- organization nodes ----------------------------------------------------

      # :476 "only JSON-LD objects whose `@type` token set includes exact `Organization` or a
      # subtype declared by `structured-identity-v1`; items are ordered by script document
      # position then object traversal path ... Duplicate nodes remain distinct. JSON-LD
      # remote contexts are NEVER fetched; DTDs and external entities are disabled; malformed
      # JSON-LD produces one malformed item with null name/url RATHER THAN DISAPPEARING."
      def organization_nodes(document)
        scripts = document.css('script[type="application/ld+json"]')
        scripts.each_with_index.flat_map do |script, script_index|
          parsed = safe_json(script.text.to_s)
          if parsed.nil?
            [malformed_node("script[#{script_index}]")]
          else
            walk_json_ld(parsed, "script[#{script_index}]")
          end
        end
      end

      def safe_json(text)
        JSON.parse(text)
      rescue JSON::ParserError, TypeError
        nil
      end

      # Depth-first in traversal order, so "ordered by script document position then object
      # traversal path" holds. Every admitted object becomes its own item even when two are
      # byte-identical, because :476 keeps duplicates distinct.
      def walk_json_ld(node, path)
        case node
        when Array
          node.each_with_index.flat_map { |child, index| walk_json_ld(child, "#{path}/#{index}") }
        when Hash
          own = organization?(node) ? [node_for(node, path)] : []
          own + node.reject { |key, _| key == "@context" }
                    .flat_map { |key, value| walk_json_ld(value, "#{path}/#{key}") }
        else
          []
        end
      end

      def organization?(node) = (type_tokens(node) & ORGANIZATION_TYPES).any?

      def type_tokens(node) = Array(node["@type"]).map(&:to_s).reject(&:empty?)

      def node_for(node, path)
        {
          "locator" => path,
          "type_tokens" => type_tokens(node).uniq.sort,
          "name" => optional_string(node["name"]),
          "url" => optional_string(node["url"]),
          "parse_status" => VALID
        }
      end

      def malformed_node(path)
        { "locator" => path, "type_tokens" => [], "name" => nil, "url" => nil, "parse_status" => MALFORMED }
      end

      def optional_string(value)
        return nil unless value.is_a?(::String)

        normalized = normalize(value)
        normalized.empty? ? nil : normalized
      end

      # :476 "Strings are decoded Unicode, normalized to NFC, and retain internal whitespace
      # unless a field rule says otherwise." Only the outer edges are trimmed; the inside of
      # a title is exactly what a Check about titles is measuring.
      def normalize(text) = text.to_s.unicode_normalize(:nfc).strip
    end
  end
end
