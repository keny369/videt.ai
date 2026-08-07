# frozen_string_literal: true

require "base64"
require "digest"
require "json"

module Workflows
  module Wf006
    # One ParsingJob attempt: read the ingested bytes, normalize them to
    # `parsed-observation-v1`, validate, and return either the payload or exactly one of the
    # ratified reason codes (WORKFLOW_SPECIFICATIONS.md :480).
    #
    # The reason precedence is the contract's, first match wins, and the pre-execution set is
    # evaluated BEFORE the parser is entered so a job that could never succeed does not spend
    # an attempt inside the parser:
    #
    #   tenant_mismatch, input_quarantined, input_bytes_missing, input_digest_mismatch,
    #   unsupported_media_type, parser_policy_unavailable
    #
    # and during execution only `parser_timeout`, `parser_dependency_unavailable` or
    # `normalized_output_invalid`. ":480 Unknown reasons map to `normalized_output_invalid`
    # with restricted diagnostics and NEVER become a successful artifact" — which is why the
    # rescue below returns a reason instead of re-raising.
    #
    # WHERE THE BYTES COME FROM. Not the ingestion job's staging: :466 destroys that within
    # 24 hours and it is already null by the time parsing runs. The retained copy is the
    # `source_document` Evidence payload, whose `body_base64` member is the fetched body, and
    # the digest check below is what proves the decoded bytes are the ones the crawl fetched.
    module ParsingExecution
      module_function

      # The F-02 binding ingestion protected the payload under. Reproduced exactly: a
      # different application/record/purpose or tenant fails authentication rather than
      # decrypting, which is the property that stops one tenant's parser reading another's.
      EVIDENCE_AAD = { application: "wf005", record_type: "ingestion_job",
                       purpose: "product_evidence_payload" }.freeze

      TIMEOUT_SECONDS = 30

      Outcome = Data.define(:payload, :reason_code) do
        def success? = reason_code.nil?
      end

      def failure(reason) = Outcome.new(payload: nil, reason_code: reason)

      # `job` is the persisted row; `evidence` its input Evidence row; `sealed_outcomes` the
      # Crawl's terminal map; `policies` the frozen scope policies for the Source.
      def run(job:, evidence:, scope_policies:, sealed_outcomes:, clock: Platform::Clock.system)
        pre = pre_execution_reason(job, evidence, scope_policies)
        return failure(pre) if pre

        body = reveal_body(job, evidence)
        return failure("input_bytes_missing") if body.nil?
        # :480 `input_digest_mismatch` — the retained bytes must be the fetched bytes.
        return failure("input_digest_mismatch") unless digest_matches?(body, job["content_digest"])

        execute(job, body, scope_policies, sealed_outcomes, clock)
      end

      # First match wins, in the contract's order.
      def pre_execution_reason(job, evidence, scope_policies)
        return "tenant_mismatch" if evidence.nil? || evidence["id"] != job["input_evidence_id"]
        # :495 "quarantined or invalid Evidence cannot produce a Parsed Artifact".
        return "input_quarantined" unless evidence["validation_status"] == "valid"
        return "unsupported_media_type" unless ParsedObservation.supported_media_type?(job["media_type"])
        return "parser_policy_unavailable" unless ParserPolicy.available?
        # Without the frozen scope policy a link target cannot be canonicalized, and guessing
        # scope is exactly the thing :476 forbids by pinning the FROZEN versions.
        return "parser_policy_unavailable" if Array(scope_policies).empty?

        nil
      end

      def execute(job, body, scope_policies, sealed_outcomes, clock)
        started = clock.now_utc
        source_root = truthy(job["source_root"])
        payload = ParsedObservation.build(
          bytes: body, canonical_document_url: job["canonical_url"], media_type: job["media_type"],
          source_root:, scope_policies: policies_for(scope_policies),
          terminal_outcomes: (source_root ? sealed_outcomes : nil)
        )
        # :481 "at exactly 30 seconds the timeout transition wins over parser completion" —
        # elapsed, not wall-clock scheduled, and equality belongs to the timeout.
        return failure("parser_timeout") if (clock.now_utc - started) >= TIMEOUT_SECONDS

        result = ParsedObservationSchema.valid(payload, source_root:, sealed_outcomes:)
        return failure("normalized_output_invalid") unless result.valid?

        Outcome.new(payload:, reason_code: nil)
      rescue StandardError
        # An unknown parser diagnostic is `normalized_output_invalid` with the detail
        # discarded: :480 keeps diagnostics restricted, and an exception message from a
        # library fed attacker-controlled bytes is not a product reason code.
        failure("normalized_output_invalid")
      end

      # The stored rows are the `source-scope-interim-v1` shape; the predicate wants its own
      # value object, and building it here keeps the predicate decoupled from persistence.
      def policies_for(rows)
        Array(rows).map do |row|
          Workflows::Wf004::SourceScopePredicate::Policy.new(
            canonical_host: row["canonical_host"],
            allowed_schemes: pg_array(row["allowed_schemes"]),
            allowed_ports: pg_array(row["allowed_ports"]).map(&:to_i),
            include_prefixes: pg_array(row["include_prefixes"]),
            exclude_prefixes: pg_array(row["exclude_prefixes"]),
            query_handling: row["query_handling"]
          )
        end
      end

      def pg_array(value) = value.is_a?(Array) ? value : Platform::PgArray.parse(value.to_s)

      def reveal_body(job, evidence)
        aad = Platform::Encryption::Aad.for(**EVIDENCE_AAD, record_id: job["ingestion_job_id"],
                                            tenant: job["organization_id"])
        plaintext = Platform::Encryption.reveal(evidence["payload_reference"], aad:)
        return nil if plaintext.nil?

        encoded = JSON.parse(plaintext)["body_base64"]
        return nil if encoded.nil?

        Base64.strict_decode64(encoded)
      rescue Platform::Encryption::Error, JSON::ParserError, ArgumentError
        nil
      end

      def digest_matches?(body, expected_hex)
        return false if expected_hex.nil?

        Digest::SHA256.hexdigest(body) == normalize_hex(expected_hex)
      end

      def normalize_hex(value) = value.to_s.sub(/\A\\x/, "").downcase

      def truthy(value) = value == true || value == "t" || value == "true"
    end
  end
end
