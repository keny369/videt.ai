# frozen_string_literal: true

require "rails_helper"
require "securerandom"

# F-04 Background Execution — the Sidekiq worker job's fail-closed guards
# (BACKGROUND_PROCESSING.md :84, :119). A malformed transport message or a vanished row
# performs no product work and raises nothing. Sidekiq retry/dead are disabled.
RSpec.describe Platform::ScheduledActions::ExecutionJob, type: :model do
  it "disables Sidekiq retry and the Dead set" do
    expect(described_class.sidekiq_options["retry"]).to be(false)
    expect(described_class.sidekiq_options["dead"]).to be(false)
  end

  it "no-ops on a malformed envelope (missing/extra field) without raising" do
    expect { described_class.new.perform({ "action_id" => "only-this" }) }.not_to raise_error
  end

  it "no-ops when the binding is unknown (nothing to resolve), without raising" do
    envelope = Platform::ScheduledActions::Envelope.new(
      schema_version: "1.0", organization_id: SecureRandom.uuid_v7,
      work_type: "scheduled_action_dispatch", work_id: SecureRandom.uuid_v7,
      product_generation: 0, claim_generation: 1,
      correlation_id: SecureRandom.uuid_v7, causation_id: SecureRandom.uuid_v7
    )
    expect { described_class.new.perform(envelope.to_args) }.not_to raise_error
  end

  it "resolves its registry from the singleton by default and is overridable" do
    expect(described_class.registry).to eq(Platform::ScheduledActions::Registry.default)
    fresh = Platform::ScheduledActions::Registry.new
    described_class.registry = fresh
    expect(described_class.registry).to eq(fresh)
  ensure
    described_class.registry = nil
  end
end
