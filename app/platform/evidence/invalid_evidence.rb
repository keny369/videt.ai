# frozen_string_literal: true

module Platform
  module Evidence
    # A typed rejection of an attempted Evidence creation (FOUNDATION-003; SCORE_EVIDENCE_MODEL.md).
    # The reason maps to a Volume I error contract at the producer boundary (e.g.
    # :evidence_type_unavailable -> F1-DOMAIN-409, :evidence_type_invalid -> F1-VALIDATION-400).
    # The loggable form is the reason alone — never a payload, token, or raw observation.
    class InvalidEvidence < StandardError
      REASONS = %i[
        schema_version_invalid
        subject_incomplete
        evidence_type_unavailable
        evidence_type_invalid
        content_digest_invalid
        payload_reference_missing
        provenance_incomplete
        observed_time_missing
        retention_class_invalid
        validation_status_invalid
        validation_reason_required
        validation_reason_forbidden
      ].freeze

      attr_reader :reason

      def initialize(reason, detail = nil)
        raise ArgumentError, "unknown evidence rejection #{reason.inspect}" unless REASONS.include?(reason)

        @reason = reason
        super(detail ? "#{reason}: #{detail}" : reason.to_s)
      end

      def redacted = { error: "invalid_evidence", reason: }
    end
  end
end
