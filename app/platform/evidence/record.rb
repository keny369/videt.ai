# frozen_string_literal: true

module Platform
  module Evidence
    # The immutable Evidence envelope (FOUNDATION-003; SCORE_EVIDENCE_MODEL.md :43-67).
    # A producer constructs and validates one; the store assigns its evidence_id and
    # appends it. It is a FACT: once written it never changes — a correction is a NEW
    # record, never an edit. This value object carries no interpretation (no score,
    # meaning, or post-creation validity); that is the evaluation layer (CAP-013/S-09).
    #
    # `producer_id` + `attempt_id` are the producer/attempt identity F-03 mandates: the
    # append is idempotent on (organization_id, producer_id, attempt_id), so a retried
    # completion writes no second record.
    class Record < Data.define(
      :schema_version, :organization_id, :project_id, :source_id, :evaluation_id,
      :evidence_type, :producer_id, :attempt_id, :payload_reference, :content_sha256,
      :captured_at_utc, :observed_at_utc, :source_system, :collection_method, :collector_version,
      :validation_status, :validation_reason_code, :data_classification, :payload_retention_class,
      :correlation_id
    )
      # Producer-enabled evidence types (SCORE_EVIDENCE_MODEL.md :67). operator_attestation
      # is reserved but unavailable; anything else is an invalid alias.
      PRODUCER_TYPES = %w[source_document crawl_observation parsed_content external_measurement verification_observation].freeze
      RESERVED_UNAVAILABLE = "operator_attestation"
      CLASSIFICATIONS = %w[public internal confidential restricted].freeze
      VALIDATION_STATUSES = %w[valid invalid quarantined].freeze
      PRODUCER_RETENTION_CLASS = "product_evidence_payload"
      SHA256_HEX = /\A[0-9a-f]{64}\z/

      # Validate and normalise an attempted Evidence envelope. Returns a Record or raises
      # InvalidEvidence. Unknown data_classification fails safe to `restricted`
      # (SCORE_EVIDENCE_MODEL.md :78).
      def self.build(**attrs)
        reject!(:schema_version_invalid) if blank?(attrs[:schema_version])
        reject!(:subject_incomplete) if blank?(attrs[:organization_id]) || blank?(attrs[:project_id])
        reject!(:provenance_incomplete) if %i[producer_id attempt_id source_system collection_method collector_version].any? { |k| blank?(attrs[k]) }
        validate_type!(attrs[:evidence_type])
        reject!(:payload_reference_missing) if blank?(attrs[:payload_reference])
        reject!(:content_digest_invalid) unless attrs[:content_sha256].is_a?(String) && attrs[:content_sha256].match?(SHA256_HEX)
        reject!(:observed_time_missing) if attrs[:captured_at_utc].nil? || attrs[:observed_at_utc].nil?
        reject!(:retention_class_invalid) unless attrs[:payload_retention_class] == PRODUCER_RETENTION_CLASS
        validate_status!(attrs[:validation_status], attrs[:validation_reason_code])

        new(**attrs.merge(data_classification: classify(attrs[:data_classification])))
      end

      def restricted? = data_classification == "restricted"

      def self.validate_type!(type)
        return if PRODUCER_TYPES.include?(type)

        reject!(:evidence_type_unavailable) if type == RESERVED_UNAVAILABLE
        reject!(:evidence_type_invalid)
      end

      def self.validate_status!(status, reason)
        reject!(:validation_status_invalid) unless VALIDATION_STATUSES.include?(status)
        reject!(:validation_reason_forbidden) if status == "valid" && !reason.nil?
        reject!(:validation_reason_required) if status != "valid" && blank?(reason)
      end

      # Unknown classification is treated as restricted (deny by default), never lowered.
      def self.classify(value) = CLASSIFICATIONS.include?(value) ? value : "restricted"

      def self.blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?)
      def self.reject!(reason, detail = nil) = raise(InvalidEvidence.new(reason, detail))

      private_class_method :validate_type!, :validate_status!, :classify, :blank?, :reject!
    end
  end
end
