# frozen_string_literal: true

require "rails_helper"
require "securerandom"

# F-04 Background Execution — the infrastructure dispatch-retry ceiling
# (BACKGROUND_PROCESSING.md :313; FOUNDATION-004 AC-6 "the retry schedule and quarantine are
# exact"). Failure to ENQUEUE an already-persisted identity backs off at exactly
# 1/5/30/120/600 s; the sixth failure quarantines the transport record with
# `redis_dispatch_exhausted` and raises a high alert.
#
# Deterministic: PostgreSQL transaction time computes the backoff, so the exact gap is read
# back from the row (next_dispatch_at - updated_at) rather than measured by sleeping. The
# backoff gate is advanced to the past to re-claim, in place of waiting for it to elapse.
RSpec.describe "F-04 infrastructure dispatch retry", type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:scheduler) { Platform::ScheduledActions::Scheduler.new }

  def create_due
    ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7,
                                  due_at: ScheduledActionHarness.past)[:id]
  end

  def claim = scheduler.claim_due.first
  def fail_dispatch(action) = scheduler.fail_dispatch(action_id: action.id, generation: action.claim_generation)
  def row(id) = ScheduledActionHarness.row(id)

  # Advance the backoff gate into the past so the row is re-claimable now (no sleep).
  def clear_backoff!(id)
    ScheduledActionHarness.owner_exec(
      "UPDATE scheduled_actions SET next_dispatch_at = transaction_timestamp() - interval '1 second' " \
      "WHERE id = $1::uuid", [id]
    )
  end

  it "backs off at exactly 1, 5, 30, 120, 600 s, then quarantines on the sixth failure" do
    id = create_due

    [1, 5, 30, 120, 600].each_with_index do |secs, i|
      action = claim
      expect(fail_dispatch(action)).to eq("rescheduled")
      r = row(id)
      expect(r["status"]).to eq("pending")
      expect(r["dispatch_attempt_count"].to_i).to eq(i + 1)
      expect(r["reason"]).to eq("redis_dispatch_retry_scheduled")
      # PostgreSQL set next_dispatch_at = fail-time + interval; the gap is the exact schedule.
      gap = (Time.parse(r["next_dispatch_at"]) - Time.parse(r["updated_at"])).round
      expect(gap).to eq(secs), "attempt #{i + 1} backed off #{gap}s, expected #{secs}s"
      clear_backoff!(id)
    end

    action = claim
    expect(fail_dispatch(action)).to eq("quarantined")
    r = row(id)
    expect(r["status"]).to eq("quarantined")
    expect(r["reason"]).to eq("redis_dispatch_exhausted")
    expect(r["dispatch_attempt_count"].to_i).to eq(6)
    expect(r["quarantined_at"]).not_to be_nil
    expect(r.values_at("claim_owner", "lease_expires_at", "claim_phase")).to all(be_nil)
    # A `redis_dispatch_exhausted` record is NOT recovered by the ordinary lease sweep
    # (its automatic recovery is the deferred G5 queue-health gate).
    expect(scheduler.recover_expired_leases).to eq(0)
  end

  it "is a no-op for a foreign owner, a wrong generation, or an already-dispatched claim" do
    id = create_due
    action = claim

    expect(Platform::ScheduledActions::Scheduler.new.fail_dispatch(
      action_id: id, generation: action.claim_generation
    )).to eq("noop")
    expect(scheduler.fail_dispatch(action_id: id, generation: action.claim_generation + 9)).to eq("noop")

    ScheduledActionHarness.transport_store do |store|
      store.dispatch(work_id: action.work_id, expected_generation: action.claim_generation,
                     worker_owner: SecureRandom.uuid_v7)
    end
    expect(fail_dispatch(action)).to eq("noop") # dispatched_at is set: not a pre-transfer enqueue failure
    expect(row(id)["status"]).to eq("dispatched")
  end

  it "resets the dispatch-attempt counter once a worker transfer succeeds" do
    id = create_due
    action = claim
    fail_dispatch(action)
    expect(row(id)["dispatch_attempt_count"].to_i).to eq(1)

    clear_backoff!(id)
    reclaimed = claim
    ScheduledActionHarness.transport_store do |store|
      store.dispatch(work_id: reclaimed.work_id, expected_generation: reclaimed.claim_generation,
                     worker_owner: SecureRandom.uuid_v7)
    end
    expect(row(id).values_at("dispatch_attempt_count", "next_dispatch_at")).to eq(["0", nil])
  end

  it "raises a single redacted high alert when the ceiling is exhausted, via the Dispatcher" do
    id = create_due
    spy = Class.new do
      attr_reader :alerts
      def initialize = @alerts = []
      def high(**kwargs) = @alerts << kwargs
    end.new
    failing_job = Class.new do
      def self.set(**) = self
      def self.perform_async(*) = raise(RuntimeError, "redis unreachable")
    end
    dispatcher = Platform::ScheduledActions::Dispatcher.new(job: failing_job, alerter: spy)

    6.times do
      dispatcher.dispatch_due
      clear_backoff!(id)
    end

    expect(spy.alerts.size).to eq(1)
    alert = spy.alerts.first
    expect(alert[:reason]).to eq("redis_dispatch_exhausted")
    expect(alert[:action_id]).to eq(id)
    expect(alert[:attempts]).to eq(Platform::ScheduledActions::Dispatcher::RETRY_CEILING)
    expect(alert[:error_class]).to eq("RuntimeError")
    expect(row(id)["status"]).to eq("quarantined")
  end
end
