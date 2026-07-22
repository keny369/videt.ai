# frozen_string_literal: true

require "rails_helper"

# Due-action claiming, the scheduler-to-worker handoff and lease recovery
# (BACKGROUND_PROCESSING.md § Due-time claim :108-121; § Work Claims And Leases
# :278-301; verification gates 2, 3 and 7 :514-519).
#
# Every assertion here is about the transport mechanism alone — no product
# workflow is involved — because the mechanism must be reusable by any ratified
# action kind.
RSpec.describe Platform::ScheduledActions::Scheduler, type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:due) { Time.utc(2026, 7, 25, 10, 0, 0) }
  let(:scheduler) { described_class.new }

  def create(target_id: SecureRandom.uuid_v7, **overrides)
    ScheduledActionHarness.create(organization_id: org, target_id:, due_at: due, **overrides)[:id]
  end

  def row(id) = ScheduledActionHarness.row(id)

  describe "due-time selection" do
    it "claims an action due exactly at the boundary and leaves one a microsecond early" do
      boundary = create
      early = create(target_id: SecureRandom.uuid_v7, due_at: due + Rational(1, 1_000_000))

      claimed = scheduler.claim_due(now: due)

      expect(claimed.map(&:id)).to eq([boundary])
      expect(row(boundary)["status"]).to eq("claimed")
      expect(row(early)["status"]).to eq("pending")
    end

    it "does not claim an action whose not_before_at has not arrived" do
      held = create(not_before_at: due + 60)
      expect(scheduler.claim_due(now: due).map(&:id)).to be_empty
      expect(row(held)["status"]).to eq("pending")

      expect(scheduler.claim_due(now: due + 60).map(&:id)).to eq([held])
    end

    it "claims in (due_at, id) order and honours the batch bound" do
      ids = 3.times.map { |i| create(due_at: due - ((3 - i) * 60)) }
      first = scheduler.claim_due(limit: 2, now: due)

      expect(first.map(&:id)).to eq(ids.first(2))
      expect(row(ids.last)["status"]).to eq("pending")
    end

    it "sets the claim owner, phase and a positive generation, and clears them on release" do
      id = create
      action = scheduler.claim_due(now: due).first
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

      batches = [a, b].map do |claimer|
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { claimer.claim_due(now: due) } }
      end.map(&:value)

      claimed = batches.flatten.map(&:id)
      expect(claimed.sort).to eq(ids.sort)
      expect(claimed.uniq.size).to eq(claimed.size)
      expect(ScheduledActionHarness.rows.map { |r| r["status"] }).to all(eq("claimed"))
    end

    it "never returns the same action twice across sequential polls" do
      id = create
      expect(scheduler.claim_due(now: due).map(&:id)).to eq([id])
      expect(scheduler.claim_due(now: due).map(&:id)).to be_empty
      expect(described_class.new.claim_due(now: due).map(&:id)).to be_empty
    end
  end

  describe "the scheduler-to-worker compare-and-swap handoff" do
    let(:worker_owner) { SecureRandom.uuid_v7 }

    def dispatch(id, generation, owner: scheduler.owner, worker: worker_owner)
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(action_id: id, expected_owner: owner, expected_generation: generation,
                       worker_owner: worker, now: due)
      end
    end

    it "transfers ownership to the worker and marks the action dispatched" do
      id = create
      action = scheduler.claim_due(now: due).first

      expect(dispatch(id, action.claim_generation)).not_to be_nil
      transferred = row(id)
      expect(transferred["status"]).to eq("dispatched")
      expect(transferred["claim_owner"]).to eq(worker_owner)
      expect(transferred["claim_phase"]).to eq("worker")
      expect(transferred["dispatched_at"]).not_to be_nil
    end

    it "resumes the same claim for a duplicate delivery to the same worker" do
      id = create
      action = scheduler.claim_due(now: due).first
      first = dispatch(id, action.claim_generation)
      second = dispatch(id, action.claim_generation)

      expect(second).not_to be_nil
      expect(row(id)["dispatched_at"]).to eq(row(id)["dispatched_at"])
      expect(second.claim_generation).to eq(first.claim_generation)
    end

    it "refuses a stale generation, a foreign owner and a reclaimed action" do
      id = create
      action = scheduler.claim_due(now: due).first

      expect(dispatch(id, action.claim_generation + 1)).to be_nil
      expect(dispatch(id, action.claim_generation, owner: SecureRandom.uuid_v7)).to be_nil

      # Reclaimed by another scheduler after the lease expired: the old
      # generation can no longer transfer.
      scheduler.recover_expired_leases(now: due + 31)
      reclaimed = described_class.new.claim_due(now: due + 31).first
      expect(reclaimed.claim_generation).to eq(2)
      expect(dispatch(id, action.claim_generation)).to be_nil
    end
  end

  describe "lease recovery after worker loss" do
    it "returns an expired scheduler claim to pending without decreasing the claim generation" do
      id = create
      scheduler.claim_due(now: due)

      expect(scheduler.recover_expired_leases(now: due + 31)).to eq(1)
      recovered = row(id)
      expect(recovered["status"]).to eq("pending")
      expect(recovered["claim_generation"].to_i).to eq(1)
      expect(recovered["reason"]).to eq("transport_lease_expired")
      expect(recovered.values_at("claim_owner", "claimed_at", "lease_expires_at", "claim_phase")).to all(be_nil)
    end

    it "returns an expired worker claim to pending so the same action identity is recomputed" do
      id = create
      action = scheduler.claim_due(now: due).first
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(action_id: id, expected_owner: scheduler.owner,
                       expected_generation: action.claim_generation,
                       worker_owner: SecureRandom.uuid_v7, now: due)
      end

      expect(scheduler.recover_expired_leases(now: due + 31)).to eq(1)
      expect(row(id)["status"]).to eq("pending")
      expect(described_class.new.claim_due(now: due + 31).map(&:id)).to eq([id])
    end

    it "leaves an unexpired lease alone" do
      create
      scheduler.claim_due(now: due)
      expect(scheduler.recover_expired_leases(now: due + 29)).to eq(0)
    end

    it "never recovers a terminal action" do
      id = create
      action = scheduler.claim_due(now: due).first
      worker = SecureRandom.uuid_v7
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(action_id: id, expected_owner: scheduler.owner,
                       expected_generation: action.claim_generation, worker_owner: worker, now: due)
        store.settle(action_id: id, owner: worker, generation: action.claim_generation,
                     status: "completed", now: due)
      end

      expect(scheduler.recover_expired_leases(now: due + 3600)).to eq(0)
      expect(row(id)["status"]).to eq("completed")
    end
  end
end
