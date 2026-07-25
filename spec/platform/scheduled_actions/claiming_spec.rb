# frozen_string_literal: true

require "rails_helper"

# Due-action claiming, the scheduler-to-worker handoff and lease recovery
# (BACKGROUND_PROCESSING.md § Due-time claim :108-121; § Work Claims And Leases
# :278-301; verification gates 2, 3 and 7 :514-519).
#
# Time here is PostgreSQL's, not the test's: no transport function accepts an
# instant. Due-ness is arranged by writing `due_at` at creation, lease expiry by
# writing `lease_expires_at`, and exact due-time equality by inserting and
# claiming inside one transaction, where `transaction_timestamp()` is by
# definition constant. Nothing sleeps.
#
# Every assertion is about the transport mechanism alone — no product workflow is
# involved — because the mechanism must be reusable by any ratified action kind.
RSpec.describe Platform::ScheduledActions::Scheduler, type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:scheduler) { described_class.new }

  def create(due_at: ScheduledActionHarness.past, target_id: SecureRandom.uuid_v7, **overrides)
    ScheduledActionHarness.create(organization_id: org, target_id:, due_at:, **overrides)[:id]
  end

  def row(id) = ScheduledActionHarness.row(id)

  describe "due-time selection under PostgreSQL time" do
    it "claims what PostgreSQL says is due and leaves what it says is not" do
      overdue = create(due_at: ScheduledActionHarness.past)
      later = create(due_at: ScheduledActionHarness.future)

      expect(scheduler.claim_due.map(&:id)).to eq([overdue])
      expect(row(overdue)["status"]).to eq("claimed")
      expect(row(later)["status"]).to eq("pending")
    end

    # `due_at <= transaction_timestamp()` at exact equality, proved by making the
    # two values the same value: inside one transaction `transaction_timestamp()`
    # is constant, so an action created at it is due at it and one a microsecond
    # later is not.
    it "claims at exact due-time equality and not a microsecond before it" do
      owner = SecureRandom.uuid_v7
      conn = DbInspector.connection
      conn.exec("BEGIN")
      begin
        at_boundary = insert_at(conn, org, "transaction_timestamp()")
        one_early = insert_at(conn, org, "transaction_timestamp() + interval '1 microsecond'")
        claimed = conn.exec_params(
          "SELECT id FROM f1_claim_due_scheduled_actions($1::uuid, 10, 30)", [owner]
        ).to_a.map { |r| r["id"] }

        expect(claimed).to eq([at_boundary])
        expect(claimed).not_to include(one_early)
      ensure
        conn.exec("ROLLBACK")
      end
    end

    it "does not claim an action whose not_before_at has not arrived" do
      held = create(not_before_at: ScheduledActionHarness.future)
      expect(scheduler.claim_due.map(&:id)).to be_empty
      expect(row(held)["status"]).to eq("pending")
    end

    it "claims in (due_at, id) order and honours the batch bound" do
      ids = 3.times.map { |i| create(due_at: ScheduledActionHarness.past(3600 - (i * 60))) }
      first = scheduler.claim_due(limit: 2)

      expect(first.map(&:id)).to eq(ids.first(2))
      expect(row(ids.last)["status"]).to eq("pending")
    end

    it "sets the claim owner, phase and a positive generation" do
      id = create
      action = scheduler.claim_due.first
      claimed = row(id)

      expect(action.claim_generation).to eq(1)
      expect(claimed["claim_owner"]).to eq(scheduler.owner)
      expect(claimed["claim_phase"]).to eq("scheduler")
      expect(claimed["lease_expires_at"]).not_to be_nil
    end
  end

  describe "two claimers cannot both take one action" do
    it "gives concurrent schedulers disjoint batches over the same due set (FOR UPDATE SKIP LOCKED)" do
      ids = 4.times.map { create }
      a = described_class.new
      b = described_class.new

      batches = [a, b].map { |claimer| Thread.new { claimer.claim_due } }.map(&:value)

      claimed = batches.flatten.map(&:id)
      expect(claimed.sort).to eq(ids.sort)
      expect(claimed.uniq.size).to eq(claimed.size)
      expect(ScheduledActionHarness.rows.map { |r| r["status"] }).to all(eq("claimed"))
    end

    it "never returns the same action twice across sequential polls" do
      id = create
      expect(scheduler.claim_due.map(&:id)).to eq([id])
      expect(scheduler.claim_due.map(&:id)).to be_empty
      expect(described_class.new.claim_due.map(&:id)).to be_empty
    end
  end

  describe "the scheduler-to-worker compare-and-swap handoff" do
    let(:worker_owner) { SecureRandom.uuid_v7 }

    # Dispatch is resolved THROUGH the Work Dispatch Binding named by the envelope
    # `work_id` (:243); the envelope's claim generation must match the binding's.
    def dispatch(work_id, generation, worker: worker_owner)
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(work_id:, expected_generation: generation, worker_owner: worker)
      end
    end

    it "transfers ownership to the worker and marks the action dispatched" do
      id = create
      action = scheduler.claim_due.first

      expect(dispatch(action.work_id, action.claim_generation)).not_to be_nil
      transferred = row(id)
      expect(transferred["status"]).to eq("dispatched")
      expect(transferred["claim_owner"]).to eq(worker_owner)
      expect(transferred["claim_phase"]).to eq("worker")
      expect(transferred["dispatched_at"]).not_to be_nil
    end

    it "resumes the same claim for a duplicate delivery to the same worker" do
      id = create
      action = scheduler.claim_due.first
      first = dispatch(action.work_id, action.claim_generation)
      dispatched_at = row(id)["dispatched_at"]
      second = dispatch(action.work_id, action.claim_generation)

      expect(second).not_to be_nil
      expect(second.claim_generation).to eq(first.claim_generation)
      expect(row(id)["dispatched_at"]).to eq(dispatched_at)
    end

    it "refuses a mismatched generation, another worker, and a reclaimed action" do
      id = create
      action = scheduler.claim_due.first

      # A binding generation that does not match the envelope's is not transferable.
      expect(dispatch(action.work_id, action.claim_generation + 1)).to be_nil
      # The legitimate first transfer succeeds; a different worker then cannot steal it.
      expect(dispatch(action.work_id, action.claim_generation)).not_to be_nil
      expect(dispatch(action.work_id, action.claim_generation, worker: SecureRandom.uuid_v7)).to be_nil

      # After lease expiry, recovery and a re-claim at a new generation and NEW binding,
      # the old binding's generation no longer matches the action's current generation.
      ScheduledActionHarness.elapse_lease!(id)
      scheduler.recover_expired_leases
      reclaimed = described_class.new.claim_due.first
      expect(reclaimed.claim_generation).to eq(2)
      expect(dispatch(action.work_id, action.claim_generation)).to be_nil
    end
  end

  describe "lease recovery after worker loss" do
    it "returns an expired scheduler claim to pending without decreasing the claim generation" do
      id = create
      scheduler.claim_due
      ScheduledActionHarness.elapse_lease!(id)

      expect(scheduler.recover_expired_leases).to eq(1)
      recovered = row(id)
      expect(recovered["status"]).to eq("pending")
      expect(recovered["claim_generation"].to_i).to eq(1)
      expect(recovered["reason"]).to eq("transport_lease_expired")
      expect(recovered.values_at("claim_owner", "claimed_at", "lease_expires_at", "claim_phase")).to all(be_nil)
    end

    it "returns an expired worker claim to pending so the same action identity is recomputed" do
      id = create
      action = scheduler.claim_due.first
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(work_id: action.work_id, expected_generation: action.claim_generation,
                       worker_owner: SecureRandom.uuid_v7)
      end
      ScheduledActionHarness.elapse_lease!(id)

      expect(scheduler.recover_expired_leases).to eq(1)
      expect(row(id)["status"]).to eq("pending")
      expect(described_class.new.claim_due.map(&:id)).to eq([id])
    end

    it "leaves an unexpired lease alone" do
      create
      scheduler.claim_due
      expect(scheduler.recover_expired_leases).to eq(0)
    end

    it "never recovers a terminal action" do
      id = create
      action = scheduler.claim_due.first
      worker = SecureRandom.uuid_v7
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(work_id: action.work_id, expected_generation: action.claim_generation,
                       worker_owner: worker)
        store.settle(action_id: id, owner: worker, generation: action.claim_generation, status: "completed")
      end

      expect(scheduler.recover_expired_leases).to eq(0)
      expect(row(id)["status"]).to eq("completed")
    end
  end

  # Insert one pending action whose due_at is the given SQL time expression,
  # inside the caller's open transaction.
  def insert_at(conn, organization_id, due_expression)
    id = SecureRandom.uuid_v7
    target = SecureRandom.uuid_v7
    preimage = Platform::ScheduledActions::Identity.preimage(
      action_kind: "invitation_expire", action_schema_version: "1.0", organization_id:, project_id: nil,
      target_type: "invitation", target_id: target, product_generation: 0, schedule_generation: 1,
      due_at: Time.now.utc
    )
    params = [id, organization_id, target, { value: preimage, format: 1 },
              { value: Digest::SHA256.digest(preimage + id), format: 1 },
              Platform::ServiceIdentity.scheduled_action_executor]
    conn.exec_params(<<~SQL, params)
      INSERT INTO scheduled_actions
        (id, schema_version, created_at, updated_at, correlation_id, causation_id,
         organization_id, executing_service_identity_id, action_kind, action_schema_version,
         target_type, target_id, due_at, identity_preimage, identity_sha256, status)
      VALUES ($1,'1.0',transaction_timestamp(),transaction_timestamp(),gen_random_uuid(),gen_random_uuid(),
              $2::uuid,$6::uuid,'invitation_expire','1.0','invitation',$3::uuid,
              #{due_expression},$4,$5,'pending')
    SQL
    id
  end
end
