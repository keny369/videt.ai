# frozen_string_literal: true

require "rails_helper"

# The canonical creation point of an Invitation's expiry timer: the activation
# transaction (WORKFLOW_SPECIFICATIONS.md :240,:242 — `expires_at_utc =
# activated_at_utc + 7 days`, set when the Invitation becomes active;
# BACKGROUND_PROCESSING.md :90 — `scheduled_actions` is the sole physical timer
# authority and a domain column MUST NOT be independently polled; :106 — one row
# per complete action identity, exact creation replay returns it).
RSpec.describe IdentityAccess::Domain::InvitationExpirySchedule, type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:invitation_id) { SecureRandom.uuid_v7 }
  let(:activated_at) { Time.utc(2026, 7, 18, 10, 0, 0) }
  let(:expires_at) { activated_at + (7 * 24 * 3600) }

  # Schedule inside the proved Organization context, as the activation
  # transaction does.
  def schedule(**overrides)
    ScheduledActionHarness.in_context(org) do |store, correlation_id|
      described_class.schedule(store:, organization_id: org, invitation_id:, expires_at:,
                               now: activated_at, correlation_id:, **overrides)
    end
  end

  it "creates exactly one pending invitation_expire action due at the Invitation's expiry instant" do
    result = schedule
    row = ScheduledActionHarness.row(result[:id])

    expect(result[:replayed]).to be(false)
    expect(ScheduledActionHarness.count).to eq(1)
    expect(row["action_kind"]).to eq("invitation_expire")
    expect(row["action_schema_version"]).to eq("1.0")
    expect(row["status"]).to eq("pending")
    expect(row["target_type"]).to eq("invitation")
    expect(row["target_id"]).to eq(invitation_id)
    expect(row["organization_id"]).to eq(org)
    expect(Time.parse(row["due_at"]).getutc).to eq(expires_at)
    expect(row["executing_service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
  end

  it "is scheduled exactly once: a duplicate activation attempt is an exact creation replay" do
    first = schedule
    second = schedule

    expect(second[:id]).to eq(first[:id])
    expect(second[:replayed]).to be(true)
    expect(ScheduledActionHarness.count).to eq(1)
  end

  it "commits or rolls back with the activation transaction" do
    expect do
      ScheduledActionHarness.in_context(org) do |store, correlation_id|
        described_class.schedule(store:, organization_id: org, invitation_id:, expires_at:,
                                 now: activated_at, correlation_id:)
        raise ActiveRecord::Rollback.new("the activation transaction failed after scheduling")
      end
    end.not_to change { ScheduledActionHarness.count }.from(0)
  end

  it "expresses a changed expiry boundary as a new schedule generation, never a mutated timer" do
    first = schedule
    later = schedule(schedule_generation: 2)
    # A different boundary at the same generation is likewise a distinct action.
    other_boundary = ScheduledActionHarness.in_context(org) do |store, correlation_id|
      described_class.schedule(store:, organization_id: org, invitation_id:, expires_at: expires_at + 3600,
                               now: activated_at, correlation_id:, schedule_generation: 3)
    end

    expect([first[:id], later[:id], other_boundary[:id]].uniq.size).to eq(3)
    expect(ScheduledActionHarness.row(first[:id])["due_at"]).to eq(ScheduledActionHarness.row(later[:id])["due_at"])
    expect(ScheduledActionHarness.rows.map { |r| r["status"] }).to all(eq("pending"))
  end

  it "keeps the action associated with its Invitation and Organization, and invisible to another Organization" do
    schedule
    other_org = TenantSeeder.create_organization

    visible = ScheduledActionHarness.in_context(other_org) do |store, _|
      store.find_by_identity(action_kind: "invitation_expire",
                             identity_sha256: Platform::ScheduledActions::Identity.digest(
                               Platform::ScheduledActions::Identity.preimage(
                                 action_kind: "invitation_expire", action_schema_version: "1.0",
                                 organization_id: org, project_id: nil, target_type: "invitation",
                                 target_id: invitation_id, product_generation: 0,
                                 schedule_generation: 1, due_at: expires_at
                               )
                             ))
    end
    expect(visible).to be_nil
  end

  it "carries the Invitation's activation state version as the timer's product generation" do
    result = schedule(state_version: 3)
    expect(ScheduledActionHarness.row(result[:id])["product_generation"].to_i).to eq(3)
  end

  describe "the seeded activation precondition" do
    it "gives every activated Invitation a timer whose due instant is its stored expiry" do
      inv = TenantSeeder.create_invitation(organization_id: org, activated_at:)
      row = ScheduledActionHarness.row(inv[:scheduled_action_id])

      expect(row["target_id"]).to eq(inv[:invitation_id])
      expect(Time.parse(row["due_at"]).getutc).to eq(inv[:expires_at])
      expect(Time.parse(DbInspector.one("SELECT expires_at FROM invitations")["expires_at"]).getutc)
        .to eq(inv[:expires_at])
    end

    it "creates no timer for an Invitation that was never activated" do
      TenantSeeder.create_invitation(organization_id: org, state: "pending_approval")
      expect(ScheduledActionHarness.count).to eq(0)
    end

    # The product invariant this operation exists to hold: an Invitation that has
    # ever been activated has an expiry timer, because activation and scheduling
    # are the same commit. Asserted across every state an activated Invitation can
    # reach, so a future activation path that forgets to schedule fails here.
    it "holds the invariant that every activated Invitation has exactly one expiry timer" do
      %w[active accepted declined revoked expired].each do |state|
        TenantSeeder.create_invitation(organization_id: org, activated_at:, state:)
      end
      TenantSeeder.create_invitation(organization_id: org, state: "pending_approval")

      orphans = DbInspector.all(<<~SQL)
        SELECT i.id FROM invitations i
        WHERE i.activated_at IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM scheduled_actions a
            WHERE a.action_kind = 'invitation_expire' AND a.target_type = 'invitation'
              AND a.target_id = i.id AND a.organization_id = i.organization_id
              AND a.due_at = i.expires_at
          )
      SQL
      expect(orphans).to be_empty
      expect(ScheduledActionHarness.count).to eq(5)
    end
  end

  # REACHABILITY, now closed. `Workflows::Wf013::Handlers::CreateInvitation` is a
  # production path that creates Invitations, and its nonprotected branch activates
  # them in the same transaction. The previous tranche's guard — "no production
  # path may create an Invitation without scheduling expiry" — has therefore done
  # its job and is replaced by the direct assertion it was standing in for: every
  # production creator reaches activation through this operation.
  describe "production reachability" do
    it "is reached by the production activation path, and by no other route to activation" do
      creators = Dir.glob("app/**/*.rb").select { |f| File.read(f).match?(/INSERT INTO invitations\b/) }
      expect(creators).to eq(["app/contexts/identity_access/infrastructure/invitation_admin_store.rb"])

      # Activation is one routine, and it is the only place the expiry boundary is
      # computed or a timer created.
      schedulers = Dir.glob("app/**/*.rb").grep_v(%r{invitation_expiry_schedule\.rb\z})
                      .select { |f| File.read(f).include?("InvitationExpirySchedule") }
      expect(schedulers).to eq(["app/workflows/wf013/invitation_activation.rb"])

      activators = Dir.glob("app/**/*.rb").grep_v(%r{invitation_activation\.rb\z})
                      .select { |f| File.read(f).include?("InvitationActivation.schedule_expiry") }
      expect(activators).to contain_exactly("app/workflows/wf013/handlers/create_invitation.rb")
    end
  end
end
