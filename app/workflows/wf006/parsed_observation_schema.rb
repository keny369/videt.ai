# frozen_string_literal: true

module Workflows
  module Wf006
    # The `parsed-observation-v1` validator (WORKFLOW_SPECIFICATIONS.md :476).
    #
    # It exists separately from the normalizer because :476 ends with an exhaustive list of
    # what makes a payload INVALID, and a producer that also judged its own output would
    # never fail. :475 makes this load-bearing: "The normalized payload MUST validate against
    # its named immutable schema" before an Artifact is written, so this is the gate between
    # a parse and a Parsed Artifact, and its refusal is `normalized_output_invalid`.
    #
    # The invalid conditions, verbatim: "The payload is invalid if positions repeat, ordering
    # is wrong, a locator is blank, a target has both or neither canonical URL/rejection
    # reason, the root map is absent on a Source root, or any referenced outcome contradicts
    # the sealed Crawl snapshot" — plus the top-level "unknown top-level fields are rejected".
    module ParsedObservationSchema
      module_function

      TOP_LEVEL = %w[schema_version canonical_document_url document_kind document_language
                     title_nodes link_edges organization_nodes].freeze
      ROOT_ONLY = "crawl_terminal_outcomes"

      TITLE_KEYS = %w[position text locator].freeze
      LINK_KEYS = %w[position href locator relation_tokens target_canonical_url target_rejection_reason].freeze
      NODE_KEYS = %w[locator type_tokens name url parse_status].freeze

      Result = Data.define(:errors) do
        def valid? = errors.empty?
        def reason = errors.first
      end

      def valid(payload, source_root:, sealed_outcomes: nil)
        errors = []
        errors.concat(top_level_errors(payload, source_root:))
        errors.concat(title_errors(Array(payload["title_nodes"])))
        errors.concat(link_errors(Array(payload["link_edges"])))
        errors.concat(node_errors(Array(payload["organization_nodes"])))
        errors.concat(outcome_errors(payload, source_root:, sealed_outcomes:))
        Result.new(errors: errors)
      end

      def top_level_errors(payload, source_root:)
        allowed = source_root ? TOP_LEVEL + [ROOT_ONLY] : TOP_LEVEL
        errors = []
        unknown = payload.keys - allowed
        errors << "unknown_top_level_field:#{unknown.sort.join(",")}" if unknown.any?
        missing = TOP_LEVEL - payload.keys
        errors << "missing_top_level_field:#{missing.sort.join(",")}" if missing.any?
        errors << "schema_version_mismatch" unless payload["schema_version"] == ParsedObservation::SCHEMA_VERSION
        unless [ParsedObservation::HTML, ParsedObservation::XHTML].include?(payload["document_kind"])
          errors << "document_kind_invalid"
        end
        language = payload["document_language"]
        errors << "document_language_invalid" unless language.nil? || (language.is_a?(String) && language == language.downcase)
        # ":476 the root map is ABSENT on a Source root" — and, symmetrically, "non-root
        # payloads OMIT that map", which the allowed-key check above already refuses.
        errors << "root_terminal_outcomes_absent" if source_root && !payload.key?(ROOT_ONLY)
        errors
      end

      def title_errors(items)
        ordering_errors(items, TITLE_KEYS, "title_nodes") do |item, index|
          next ["title_text_missing:#{index}"] unless item["text"].is_a?(String)

          []
        end
      end

      def link_errors(items)
        ordering_errors(items, LINK_KEYS, "link_edges") do |item, index|
          errors = []
          url = item["target_canonical_url"]
          reason = item["target_rejection_reason"]
          # ":476 a target has BOTH or NEITHER" — the exclusive-or is the whole rule, and it
          # is the one an implementation is most likely to get wrong by defaulting both.
          errors << "link_target_both:#{index}" if url && reason
          errors << "link_target_neither:#{index}" if url.nil? && reason.nil?
          if reason && !%w[empty unsupported_scheme invalid_url outside_source_scope].include?(reason)
            errors << "link_rejection_reason_unknown:#{index}"
          end
          tokens = item["relation_tokens"]
          unless tokens.is_a?(Array) && tokens == tokens.uniq.sort && tokens.all? { |t| t.is_a?(String) && t == t.downcase }
            errors << "link_relation_tokens_unordered:#{index}"
          end
          errors
        end
      end

      def node_errors(items)
        items.each_with_index.flat_map do |item, index|
          errors = []
          errors << "organization_node_keys:#{index}" unless item.keys.sort == NODE_KEYS.sort
          errors << "organization_node_locator_blank:#{index}" if item["locator"].to_s.strip.empty?
          unless [ParsedObservation::VALID, ParsedObservation::MALFORMED].include?(item["parse_status"])
            errors << "organization_node_parse_status:#{index}"
          end
          # ":476 malformed JSON-LD produces one malformed item with NULL name/url."
          if item["parse_status"] == ParsedObservation::MALFORMED && (item["name"] || item["url"])
            errors << "organization_node_malformed_carries_values:#{index}"
          end
          errors
        end
      end

      # The three rules every positional collection shares: keys exactly as declared,
      # positions that neither repeat nor run out of order, and no blank locator.
      def ordering_errors(items, keys, label)
        errors = []
        positions = items.map { |item| item["position"] }
        errors << "#{label}_position_repeats" if positions.length != positions.uniq.length
        errors << "#{label}_ordering_wrong" unless positions == (0...items.length).to_a
        items.each_with_index do |item, index|
          errors << "#{label}_keys:#{index}" unless item.keys.sort == keys.sort
          errors << "#{label}_locator_blank:#{index}" if item["locator"].to_s.strip.empty?
          errors.concat(yield(item, index)) if block_given?
        end
        errors
      end

      # ":476 or any referenced outcome CONTRADICTS the sealed Crawl snapshot". The map is
      # checked against the Crawl's own terminal outcomes, so a payload cannot claim a URL
      # was covered when the run recorded otherwise.
      def outcome_errors(payload, source_root:, sealed_outcomes:)
        return [] unless source_root

        map = payload[ROOT_ONLY]
        return ["root_terminal_outcomes_invalid"] unless map.is_a?(Hash)

        errors = []
        map.each do |url, outcome|
          errors << "terminal_outcome_unknown:#{url}" unless ParsedObservation::TERMINAL_OUTCOMES.include?(outcome)
          next if sealed_outcomes.nil?

          sealed = sealed_outcomes[url]
          errors << "terminal_outcome_contradicts_crawl:#{url}" if sealed && sealed != outcome
        end
        errors
      end
    end
  end
end
