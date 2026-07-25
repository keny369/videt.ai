# frozen_string_literal: true

require "rails_helper"
require "securerandom"

# F-04 Background Execution — the scalar Sidekiq envelope (BACKGROUND_PROCESSING.md :69-84).
# Exactly the eight ratified identifier fields, fail-closed on any malformed transport message.
RSpec.describe Platform::ScheduledActions::Envelope, type: :model do
  def valid_args(**overrides)
    {
      "schema_version" => "1.0", "organization_id" => SecureRandom.uuid_v7,
      "work_type" => "scheduled_action_dispatch", "work_id" => SecureRandom.uuid_v7,
      "product_generation" => 0, "claim_generation" => 3,
      "correlation_id" => SecureRandom.uuid_v7, "causation_id" => SecureRandom.uuid_v7
    }.merge(overrides)
  end

  it "round-trips a valid envelope through to_args/parse" do
    args = valid_args
    parsed = described_class.parse(args)
    expect(parsed).to be_a(described_class)
    expect(parsed.claim_generation).to eq(3)
    expect(parsed.work_id).to eq(args["work_id"])
    expect(parsed.to_args).to eq(args)
    expect(parsed.to_args.keys.sort).to eq(described_class::FIELDS.sort)
  end

  it "accepts symbol keys (Sidekiq JSON round-trips to strings, but be lenient on input)" do
    expect(described_class.parse(valid_args.transform_keys(&:to_sym))).to be_a(described_class)
  end

  describe "fail-closed parsing" do
    it "rejects a non-hash" do
      expect(described_class.parse("nope")).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end

    it "rejects a wrong schema version" do
      expect(described_class.parse(valid_args.merge("schema_version" => "2.0"))).to be_nil
    end

    it "rejects a missing field" do
      expect(described_class.parse(valid_args.except("work_id"))).to be_nil
      expect(described_class.parse(valid_args.except("correlation_id"))).to be_nil
    end

    it "rejects an unknown/extra field (including the retired 6-field shape)" do
      expect(described_class.parse(valid_args.merge("extra" => "x"))).to be_nil
      expect(described_class.parse(valid_args.merge("action_id" => SecureRandom.uuid_v7))).to be_nil
    end

    it "rejects an empty or non-string identifier" do
      expect(described_class.parse(valid_args.merge("work_id" => ""))).to be_nil
      expect(described_class.parse(valid_args.merge("organization_id" => 5))).to be_nil
      expect(described_class.parse(valid_args.merge("causation_id" => nil))).to be_nil
    end

    it "rejects a shape-valid but non-UUID identifier (clean no-op, never a ::uuid cast failure)" do
      expect(described_class.parse(valid_args.merge("work_id" => "not-a-uuid"))).to be_nil
      expect(described_class.parse(valid_args.merge("organization_id" => "12345"))).to be_nil
      # work_type is a catalogue token, not a UUID, and stays free-form.
      expect(described_class.parse(valid_args.merge("work_type" => "scheduled_action_dispatch"))).to be_a(described_class)
    end

    it "rejects a non-positive or non-integer claim generation" do
      expect(described_class.parse(valid_args.merge("claim_generation" => 0))).to be_nil
      expect(described_class.parse(valid_args.merge("claim_generation" => -1))).to be_nil
      expect(described_class.parse(valid_args.merge("claim_generation" => "3"))).to be_nil
    end

    it "rejects a negative or non-integer product generation" do
      expect(described_class.parse(valid_args.merge("product_generation" => -1))).to be_nil
      expect(described_class.parse(valid_args.merge("product_generation" => "0"))).to be_nil
    end
  end

  it "builds the enqueue envelope from a claimed Action — identifiers only, lineage carried" do
    action = Platform::ScheduledActions::Action.new(
      id: SecureRandom.uuid_v7, action_kind: "invitation_expire", action_schema_version: "1.0",
      organization_id: SecureRandom.uuid_v7, project_id: nil, target_type: "invitation",
      target_id: SecureRandom.uuid_v7, product_generation: 0, schedule_generation: 1,
      due_at: Time.now.utc, claim_generation: 2, correlation_id: SecureRandom.uuid_v7,
      causation_id: SecureRandom.uuid_v7, executing_service_identity_id: SecureRandom.uuid_v7,
      identity_sha256: nil, work_id: SecureRandom.uuid_v7
    )
    envelope = described_class.for(action)

    expect(envelope.work_id).to eq(action.work_id)
    expect(envelope.work_type).to eq("scheduled_action_dispatch") # invitation_expire -> generic (Catalogue)
    expect(envelope.correlation_id).to eq(action.correlation_id)
    expect(envelope.causation_id).to eq(action.causation_id)
    expect(described_class.parse(envelope.to_args)).to eq(envelope)
  end
end
