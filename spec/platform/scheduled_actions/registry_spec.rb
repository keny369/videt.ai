# frozen_string_literal: true

require "rails_helper"

# The closed action-kind dispatch registry (BACKGROUND_PROCESSING.md :375, :421).
# Dispatch is a validated table lookup: an action never names a class, method or
# discriminator, and anything the table does not contain fails closed.
RSpec.describe Platform::ScheduledActions::Registry, type: :model do
  let(:handler) { Class.new }
  let(:command) { Class.new }
  let(:registry) { described_class.new }

  def register(action_kind: "invitation_expire", action_schema_version: "1.0", operation: "ExpireInvitation")
    registry.register(action_kind:, action_schema_version:, operation:, handler:, command:)
  end

  it "resolves only the exact registered action kind and schema version" do
    register
    entry = registry.resolve(action_kind: "invitation_expire", action_schema_version: "1.0")

    expect(entry.operation).to eq("ExpireInvitation")
    expect(entry.handler).to eq(handler)
    expect(registry.resolve(action_kind: "invitation_expire", action_schema_version: "2.0")).to be_nil
    expect(registry.resolve(action_kind: "session_expire", action_schema_version: "1.0")).to be_nil
  end

  it "distinguishes an unmapped kind from an unsupported schema version, so each fails closed separately" do
    register
    expect(registry.kind_registered?("invitation_expire")).to be(true)
    expect(registry.kind_registered?("session_expire")).to be(false)
  end

  it "refuses a kind outside the ratified catalogue" do
    expect { register(action_kind: "invitation_expire_v2") }
      .to raise_error(described_class::UnknownActionKind)
  end

  it "refuses an operation the ratified generic-dispatch table does not assign to that kind" do
    expect { register(operation: "RevokeInvitation") }
      .to raise_error(described_class::OperationMismatch, /invitation_expire maps to ExpireInvitation/)
  end

  it "starts empty, so an unregistered process executes nothing" do
    expect(registry.size).to eq(0)
    expect(registry.resolve(action_kind: "invitation_expire", action_schema_version: "1.0")).to be_nil
  end
end
