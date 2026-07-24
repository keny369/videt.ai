# frozen_string_literal: true

require "rails_helper"

# F-03 Evidence Production — the immutable Evidence envelope (FOUNDATION-003;
# SCORE_EVIDENCE_MODEL.md). Pure validation: the producer's envelope is accepted only when
# structurally complete, and every rejection is typed. No interpretation here.
RSpec.describe Platform::Evidence::Record, type: :model do
  def digest = "a" * 64

  def valid_attrs(**overrides)
    {
      schema_version: "verification-observation-v1",
      organization_id: "org-1", project_id: "proj-1", source_id: "src-1", evaluation_id: nil,
      evidence_type: "verification_observation", producer_id: "svc-verifier", attempt_id: "attempt-1",
      payload_reference: "ref-1", content_sha256: digest,
      captured_at_utc: Time.utc(2026, 7, 25), observed_at_utc: Time.utc(2026, 7, 25),
      source_system: "f1-verification", collection_method: "http_file", collector_version: "verification-observer-v1",
      validation_status: "valid", validation_reason_code: nil,
      data_classification: "restricted", payload_retention_class: "product_evidence_payload",
      correlation_id: "corr-1"
    }.merge(overrides)
  end

  def build(**overrides) = described_class.build(**valid_attrs(**overrides))
  def reason(sym, &block) = raise_error(Platform::Evidence::InvalidEvidence) { |e| expect(e.reason).to eq(sym) }

  it "builds a complete verification_observation envelope" do
    record = build
    expect(record.evidence_type).to eq("verification_observation")
    expect(record).to be_restricted
    expect(record).to be_frozen
  end

  describe "evidence_type" do
    it "accepts every producer-enabled type" do
      described_class::PRODUCER_TYPES.each { |type| expect { build(evidence_type: type) }.not_to raise_error }
    end

    it "rejects operator_attestation as unavailable" do
      expect { build(evidence_type: "operator_attestation") }.to reason(:evidence_type_unavailable)
    end

    it "rejects an unknown type or legacy alias as invalid" do
      expect { build(evidence_type: "operator_submission") }.to reason(:evidence_type_invalid)
      expect { build(evidence_type: "made_up") }.to reason(:evidence_type_invalid)
    end
  end

  describe "content digest" do
    it "requires a lowercase 64-hex SHA-256" do
      expect { build(content_sha256: digest.upcase) }.to reason(:content_digest_invalid)
      expect { build(content_sha256: "abc") }.to reason(:content_digest_invalid)
      expect { build(content_sha256: "z" * 64) }.to reason(:content_digest_invalid)
    end
  end

  describe "required identity and provenance" do
    it "requires organization and project (subject)" do
      expect { build(organization_id: nil) }.to reason(:subject_incomplete)
      expect { build(project_id: "") }.to reason(:subject_incomplete)
    end

    it "requires producer identity and provenance" do
      %i[producer_id attempt_id source_system collection_method collector_version].each do |field|
        expect { build(field => nil) }.to reason(:provenance_incomplete)
      end
    end

    it "requires a payload reference and observation times" do
      expect { build(payload_reference: nil) }.to reason(:payload_reference_missing)
      expect { build(captured_at_utc: nil) }.to reason(:observed_time_missing)
      expect { build(observed_at_utc: nil) }.to reason(:observed_time_missing)
    end

    it "allows a nil source_id / evaluation_id (project-level / pre-evaluation)" do
      expect { build(source_id: nil, evaluation_id: nil) }.not_to raise_error
    end
  end

  describe "retention and validation status" do
    it "accepts only the producer retention class" do
      expect { build(payload_retention_class: "ephemeral_secret") }.to reason(:retention_class_invalid)
    end

    it "rejects an unknown validation status" do
      expect { build(validation_status: "pending") }.to reason(:validation_status_invalid)
    end

    it "requires a reason unless valid, and forbids one when valid" do
      expect { build(validation_status: "valid", validation_reason_code: "x") }.to reason(:validation_reason_forbidden)
      expect { build(validation_status: "quarantined", validation_reason_code: nil) }.to reason(:validation_reason_required)
      expect { build(validation_status: "quarantined", validation_reason_code: "security_restriction") }.not_to raise_error
    end
  end

  describe "classification fails safe" do
    it "preserves a known classification" do
      expect(build(data_classification: "public").data_classification).to eq("public")
    end

    it "treats an unknown classification as restricted" do
      expect(build(data_classification: "weird").data_classification).to eq("restricted")
      expect(build(data_classification: nil).data_classification).to eq("restricted")
    end
  end

  it "requires a schema version" do
    expect { build(schema_version: nil) }.to reason(:schema_version_invalid)
  end
end
