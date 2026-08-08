# frozen_string_literal: true

require "digest"

module Workflows
  module Wf006
    # `measurement-set-package-v1` — the owner-approval package OD-010 requires, and the
    # validator that decides whether a submitted one is what the register describes
    # (OD-010 § Required Owner Approval Package; WORKFLOW_SPECIFICATIONS.md :480-482).
    #
    # THE REGISTER LISTS SEVEN THINGS AND OMISSION IS FATAL: "OD-010 approval is valid only for
    # one immutable Measurement Set package whose owner-supplied content includes ALL of the
    # following; OMISSION LEAVES THE NO-SET SAFE INTERIM ACTIVE AND AUTHORIZES NO INFERRED VALUE."
    # So this validator's refusals are the product behaviour, not defensive programming: a package
    # missing its pinning rule is not a package with a gap to fill in, it is a package that
    # authorizes nothing, and the correct response is to keep returning `input_evidence_missing`.
    #
    # THE DIGEST EXCLUDES THE SIGNATURES, AND THAT IS THE WHOLE MECHANISM. Both owners sign the
    # SAME SHA-256, so the bytes they sign cannot contain the signatures themselves. `digest`
    # therefore canonicalizes every field EXCEPT `signatures`, and activation checks two
    # signatures against that value — "one signature or signatures over different bytes do not
    # authorize activation".
    #
    # NOTHING HERE INVENTS A KEY. The intent keys, their exact text, the provider identities and
    # the adapter digest all arrive in the package. If a package omits them it is refused; no
    # default is supplied, because supplying one would be the exact act OD-010 forbids.
    module MeasurementPackage
      module_function

      SCHEMA_VERSION = "measurement-set-package-v1"
      OBSERVATION_SCHEMA = "external-observation-v1"
      MEASUREMENT_POLICY_VERSION = "external-measurement-interim-v1"
      LOCALE = "en-AU"
      TIME_ZONE = "UTC"
      # `fresh_until_utc` is exactly 24 elapsed hours after `observed_at_utc`. A package may not
      # widen it, so this is an equality and not a ceiling.
      FRESHNESS_SECONDS = 86_400

      KINDS = %w[search_index_presence ai_answer_presence authority_reference_set
                 local_profile_consistency].freeze

      # Every field the register enumerates, as the exact key the package must carry.
      REQUIRED = %w[package_schema_version measurement_set_id measurement_set_version
                    measurement_kind package_created_at proposed_effective_at organization_id
                    provider_identities collector_adapter expected_keys key_content locale
                    time_zone max_evidence_age_seconds binding retention_location
                    owner_approval_reference observations].freeze
      REQUIRED_ADAPTER = %w[id version sha256].freeze
      REQUIRED_BINDING = %w[catalog_version catalog_sha256 definition_id definition_version
                            definition_sha256].freeze
      SIGNERS = %w[chief_product chief_architect].freeze
      REQUIRED_SIGNATURE = %w[signer_identity authority signed_at decision package_sha256].freeze

      Verdict = Data.define(:failures) do
        def valid? = failures.empty?
        def reason = failures.first
      end

      # The bytes both owners sign: canonical JSON over every field EXCEPT `signatures`.
      def canonical_bytes(package)
        Platform::CanonicalJson.encode(package.reject { |k, _| k == "signatures" }).b
      end

      def digest(package) = Digest::SHA256.digest(canonical_bytes(package))

      # ---- validation -------------------------------------------------------------------

      def validate(package, organization_id:, catalog_version:, catalog_sha256:)
        return Verdict.new(failures: ["package_not_an_object"]) unless package.is_a?(Hash)

        failures = []
        failures.concat(structural_failures(package))
        return Verdict.new(failures:) if failures.any?

        failures.concat(binding_failures(package, catalog_version, catalog_sha256))
        failures.concat(tenancy_failures(package, organization_id))
        failures.concat(key_failures(package))
        failures.concat(observation_failures(package))
        Verdict.new(failures:)
      end

      def structural_failures(package)
        failures = []
        missing = REQUIRED - package.keys
        failures << "package_field_missing:#{missing.sort.join(',')}" if missing.any?
        return failures if failures.any?

        failures << "package_schema_unsupported" unless package["package_schema_version"] == SCHEMA_VERSION
        failures << "measurement_kind_unknown" unless KINDS.include?(package["measurement_kind"])
        failures << "locale_invalid" unless package["locale"] == LOCALE
        failures << "time_zone_invalid" unless package["time_zone"] == TIME_ZONE
        # A package that widened the freshness bound would let a Check consume an observation the
        # ratified schema calls stale. It is refused rather than clamped, because clamping would
        # accept a package the owner did not approve and quietly change its meaning.
        failures << "evidence_age_invalid" unless package["max_evidence_age_seconds"] == FRESHNESS_SECONDS
        unless package["measurement_set_version"].to_s.match?(/\A[0-9]+\.[0-9]+\.[0-9]+\z/)
          failures << "measurement_set_version_invalid"
        end
        adapter = package["collector_adapter"]
        if !adapter.is_a?(Hash) || (REQUIRED_ADAPTER - adapter.keys).any?
          failures << "collector_adapter_incomplete"
        elsif !adapter["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
          failures << "collector_adapter_digest_invalid"
        end
        failures << "provider_identities_empty" unless package["provider_identities"].is_a?(Array) &&
                                                       package["provider_identities"].any?
        failures << "retention_location_blank" if package["retention_location"].to_s.strip.empty?
        # The owner-approval reference is part of the artifact the owners sign, so it belongs to
        # the digest. Adding it AT signing time would change the bytes the signatures cover and
        # make the proposed row unfindable by its own digest — which is exactly what happened the
        # first time this was written.
        failures << "owner_approval_reference_blank" if package["owner_approval_reference"].to_s.strip.empty?
        failures
      end

      # "either by BINDING UNCHANGED IMMUTABLE Check Definition/Catalog digests or by supplying an
      # immutable successor definition package". This build binds unchanged digests, so a package
      # naming a Catalog or Definition digest that is not the active one is refused — that is what
      # makes the pinning rule enforceable rather than decorative.
      def binding_failures(package, catalog_version, catalog_sha256)
        binding = package["binding"]
        return ["binding_incomplete"] if !binding.is_a?(Hash) || (REQUIRED_BINDING - binding.keys).any?

        failures = []
        failures << "binding_catalog_mismatch" unless binding["catalog_version"] == catalog_version &&
                                                      binding["catalog_sha256"] == catalog_sha256
        definition = definition_for(package["measurement_kind"])
        if definition.nil?
          failures << "binding_definition_unknown"
        else
          expected = Wf007::CheckCatalog.hex(Wf007::CheckCatalog.definition_digest(definition))
          unless binding["definition_id"] == definition["check_definition_id"] &&
                 binding["definition_version"] == definition["semantic_version"] &&
                 binding["definition_sha256"] == expected
            failures << "binding_definition_mismatch"
          end
        end
        failures
      end

      # The Definition each measurement kind feeds, resolved from the ratified catalogue rather
      # than from a table in this file, so the two can never drift apart.
      def definition_for(kind)
        Wf007::CheckCatalog::DEFINITIONS.find { |d| d["measurement_kind"] == kind }
      end

      def tenancy_failures(package, organization_id)
        return [] if package["organization_id"] == organization_id

        ["tenant_mismatch"]
      end

      # "the COMPLETE ORDERED search-query keys and exact query text, AI-intent keys and exact
      # intent content". Ordered by UTF-8 bytes, nonempty, unique, and every key carries its text.
      def key_failures(package)
        keys = package["expected_keys"]
        content = package["key_content"]
        return ["expected_keys_empty"] unless keys.is_a?(Array) && keys.any?
        return ["key_content_invalid"] unless content.is_a?(Hash)

        failures = []
        failures << "expected_keys_duplicated" unless keys.uniq.length == keys.length
        failures << "expected_keys_unordered" unless keys.map(&:b) == keys.map(&:b).sort
        missing = keys.reject { |k| content[k].to_s.strip.length.positive? }
        failures << "key_content_missing:#{missing.sort.join(',')}" if missing.any?
        extra = content.keys - keys
        failures << "key_content_unbound:#{extra.sort.join(',')}" if extra.any?
        failures
      end

      # Each observation must be an exact `external-observation-v1` payload for the package's own
      # kind and key set. A key-set mismatch is refused HERE rather than left for the Check,
      # because the Check would report `input_evidence_indeterminate` — a truthful statement about
      # the evidence, but the wrong place to discover that the package and its own observations
      # disagree.
      def observation_failures(package)
        observations = package["observations"]
        return ["observations_empty"] unless observations.is_a?(Array) && observations.any?

        observations.each_with_index.flat_map do |payload, index|
          payload_failures(payload, package).map { |f| "observation_#{index}:#{f}" }
        end
      end

      def payload_failures(payload, package)
        return ["not_an_object"] unless payload.is_a?(Hash)

        failures = []
        failures << "schema_mismatch" unless payload["schema_version"] == OBSERVATION_SCHEMA
        failures << "policy_version_mismatch" unless payload["measurement_policy_version"] == MEASUREMENT_POLICY_VERSION
        failures << "kind_mismatch" unless payload["measurement_kind"] == package["measurement_kind"]
        failures << "locale_mismatch" unless payload["locale"] == LOCALE
        failures << "time_zone_mismatch" unless payload["time_zone"] == TIME_ZONE
        failures << "adapter_mismatch" unless payload["collector_adapter_id"] == package.dig("collector_adapter", "id") &&
                                              payload["collector_adapter_version"] == package.dig("collector_adapter", "version")
        failures << "set_version_mismatch" unless payload["measurement_set_version"] == package["measurement_set_version"]
        unless %w[complete partial indeterminate].include?(payload["coverage_status"])
          failures << "coverage_status_invalid"
        end
        failures.concat(time_failures(payload))
        failures.concat(body_failures(payload, package))
        failures
      end

      def time_failures(payload)
        observed = parse_time(payload["observed_at_utc"])
        fresh_until = parse_time(payload["fresh_until_utc"])
        captured = parse_time(payload["captured_at_utc"])
        return ["observation_times_invalid"] if observed.nil? || fresh_until.nil? || captured.nil?

        failures = []
        # EXACTLY 24 elapsed hours. Not "about", and not a value the payload gets to choose.
        failures << "freshness_window_invalid" unless (fresh_until - observed).round == FRESHNESS_SECONDS
        failures << "capture_window_invalid" unless captured >= observed && captured < fresh_until
        failures
      end

      # The kind-specific body, exactly as `external-observation-v1` defines it. Only the two
      # kinds this build can actually receive are checked in full; a package for a kind whose body
      # rules are not implemented is refused rather than accepted unchecked, because an unchecked
      # body would reach a Check that trusts the schema was enforced upstream.
      def body_failures(payload, package)
        body = payload["body"]
        return ["body_missing"] unless body.is_a?(Hash)

        case payload["measurement_kind"]
        when "ai_answer_presence" then ai_answer_body_failures(body, package)
        when "search_index_presence" then search_body_failures(body, package)
        else ["body_kind_unsupported"]
        end
      end

      # "nonempty `expected_intent_keys` sorted by UTF-8 bytes and exactly one item per key IN
      # THAT ORDER. An item contains intent key, `presence_status`, `citation_status`, and sorted
      # unique matching canonical entity keys. `absent` requires `not_cited` and no entity key; a
      # qualified observation requires `present`, `cited`, and at least one entity key."
      def ai_answer_body_failures(body, package)
        keys = body["expected_intent_keys"]
        items = body["items"]
        return ["intent_keys_empty"] unless keys.is_a?(Array) && keys.any?
        return ["items_invalid"] unless items.is_a?(Array)

        failures = []
        failures << "intent_keys_unbound" unless keys == package["expected_keys"]
        failures << "items_not_one_per_key" unless items.map { |i| i["intent_key"] } == keys
        items.each_with_index do |item, index|
          presence = item["presence_status"]
          citation = item["citation_status"]
          entities = item["entity_keys"]
          failures << "item_#{index}_presence_invalid" unless %w[present absent indeterminate].include?(presence)
          failures << "item_#{index}_citation_invalid" unless %w[cited not_cited indeterminate].include?(citation)
          failures << "item_#{index}_entities_invalid" unless entities.is_a?(Array) &&
                                                              entities == entities.uniq.sort
          # The one cross-field rule the schema states outright, and the one an implementation
          # is most likely to violate by recording a citation for a business the answer never named.
          if presence == "absent" && (citation != "not_cited" || Array(entities).any?)
            failures << "item_#{index}_absent_requires_not_cited_and_no_entity"
          end
        end
        failures
      end

      # "nonempty `expected_query_keys` sorted by UTF-8 bytes and exactly one item per key in that
      # order. An item contains query key, `presence_status`, and sorted unique matching canonical
      # in-scope URLs; `present` requiring at least one URL and `absent` requiring none."
      def search_body_failures(body, package)
        keys = body["expected_query_keys"]
        items = body["items"]
        return ["query_keys_empty"] unless keys.is_a?(Array) && keys.any?
        return ["items_invalid"] unless items.is_a?(Array)

        failures = []
        failures << "query_keys_unbound" unless keys == package["expected_keys"]
        failures << "items_not_one_per_key" unless items.map { |i| i["query_key"] } == keys
        items.each_with_index do |item, index|
          urls = item["urls"]
          failures << "item_#{index}_presence_invalid" unless %w[present absent indeterminate].include?(item["presence_status"])
          failures << "item_#{index}_urls_invalid" unless urls.is_a?(Array) && urls == urls.uniq.sort
          failures << "item_#{index}_present_requires_url" if item["presence_status"] == "present" && Array(urls).empty?
          failures << "item_#{index}_absent_requires_no_url" if item["presence_status"] == "absent" && Array(urls).any?
        end
        failures
      end

      # ---- signatures --------------------------------------------------------------------

      # Both signatures, over the SAME digest, each complete. Anything else authorizes nothing.
      def signature_failures(package, digest_hex)
        signatures = package["signatures"]
        return ["signatures_absent"] unless signatures.is_a?(Hash)

        SIGNERS.flat_map do |signer|
          signature = signatures[signer]
          next ["signature_missing:#{signer}"] unless signature.is_a?(Hash)

          missing = REQUIRED_SIGNATURE - signature.keys
          next ["signature_incomplete:#{signer}:#{missing.sort.join(',')}"] if missing.any?

          failures = []
          # "signatures over DIFFERENT BYTES do not authorize activation."
          failures << "signature_over_other_bytes:#{signer}" unless signature["package_sha256"] == digest_hex
          failures << "signature_not_approved:#{signer}" unless signature["decision"] == "approved"
          failures
        end
      end

      # A malformed instant is `nil` rather than an exception: an unparseable time is invalid
      # package content, and the caller turns that into a refusal reason. Written as a full method
      # because an endless method cannot carry a `rescue` — as an endless one it parsed, attached
      # the rescue to the module body, and silently caught nothing.
      def parse_time(value)
        return nil if value.nil?

        Time.parse(value.to_s).getutc
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
