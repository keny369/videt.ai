# frozen_string_literal: true

require "rails_helper"
require "securerandom"
require "sidekiq/testing"
require "sidekiq/api"

# F-04 Background Execution — the end-to-end acceptance proof through REAL PostgreSQL + Redis +
# Sidekiq (FOUNDATION-004 AC-1/AC-2/AC-3/AC-5, property 9; ratified G3 proof bar). Sidekiq runs
# in `disable!` mode, so `perform_async` truly enqueues to Redis and jobs are delivered by
# running the REAL ExecutionJob against the REAL Redis-persisted arguments — there is no fake or
# inline production execution pathway (property 9). Requires Redis (frozen baseline: Valkey/Redis 8).
#
# The guarantee proven: TRANSPORT DELIVERY IS AT-LEAST-ONCE; THE AUTHORISED DOMAIN EFFECT IS
# AT-MOST-ONCE. The remaining boundaries of the ratified matrix are proven in real-PostgreSQL
# sibling specs (all same transport, no sleeps): the exact 1/5/30/120/600 s dispatch schedule,
# the sixth-failure `redis_dispatch_exhausted` quarantine and its high alert in
# spec/platform/scheduled_actions/dispatch_retry_spec.rb; the crash-after-committed-effect
# recovery in spec/platform/scheduled_actions/worker_spec.rb and wf001_expire_invitation_lifecycle.
RSpec.describe "F-04 Background Execution — real PostgreSQL + Redis + Sidekiq acceptance", type: :model do
  self.use_transactional_tests = false

  SPY = ScheduledActionSpies::Handler
  SPY_COMMAND = ScheduledActionSpies::Command

  let(:org) { TenantSeeder.create_organization }

  before do
    Sidekiq::Testing.disable! # real Redis round-trip, never fake/inline
    Sidekiq::Queue.new("control").clear
    Sidekiq::Queue.new("lifecycle").clear
    registry = Platform::ScheduledActions::Registry.new.register(
      action_kind: "invitation_expire", action_schema_version: "1.0",
      operation: "ExpireInvitation", handler: SPY, command: SPY_COMMAND
    )
    Platform::ScheduledActions::ExecutionJob.registry = registry
    SPY.reset! { |_, _| ok_result }
  end

  after do
    Platform::ScheduledActions::ExecutionJob.registry = nil
    Sidekiq::Queue.new("control").clear
    Sidekiq::Queue.new("lifecycle").clear
    ReceiptMinter.truncate_all
  end

  def ok_result(reason = nil)
    if reason
      Platform::CommandResult.failure(
        result_id: SecureRandom.uuid_v7, command_type: "ExpireInvitation",
        failure: Platform::Failure.new(error_class: "domain", error_code: "F1-DOMAIN-409", reason_code: reason,
                                       severity: "warning", retryable: false,
                                       recovery_action: "reread_current_state_and_submit_new_command",
                                       support_reference: SecureRandom.uuid_v7),
        audit_record_id: SecureRandom.uuid_v7, correlation_id: SecureRandom.uuid_v7
      )
    else
      Platform::CommandResult.success(result_id: SecureRandom.uuid_v7, command_type: "ExpireInvitation",
                                      payload: { state: "expired" }, audit_record_id: SecureRandom.uuid_v7,
                                      correlation_id: SecureRandom.uuid_v7)
    end
  end

  def create_due(kind: "invitation_expire", target_type: "invitation", due_at: ScheduledActionHarness.past)
    ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7,
                                  action_kind: kind, target_type:, due_at:)[:id]
  end

  def row(id) = ScheduledActionHarness.row(id)
  def queued(name = "control") = Sidekiq::Queue.new(name).map { |job| job.args.first }

  # Deliver each queued job through the REAL ExecutionJob, with the REAL args Redis persisted
  # (JSON round-trip -> string keys). Returns the number delivered.
  def deliver_all(name = "control")
    jobs = Sidekiq::Queue.new(name).to_a
    jobs.each { |job| Platform::ScheduledActions::ExecutionJob.new.perform(*job.args); job.delete }
    jobs.size
  end

  it "dispatches through real Redis and executes exactly once end-to-end, under the envelope's lineage" do
    id = create_due
    correlation = row(id)["correlation_id"]
    causation = row(id)["causation_id"]

    dispatched = Platform::ScheduledActions::Dispatcher.new.dispatch_due
    expect(dispatched.map(&:outcome)).to eq([:enqueued])

    # Real Redis: the job is genuinely persisted (proves this is not a fake/inline pathway).
    persisted = queued("control")
    expect(persisted.size).to eq(1)
    expect(persisted.first["work_id"]).to eq(dispatched.first.work_id)
    expect(persisted.first.keys.sort).to eq(Platform::ScheduledActions::Envelope::FIELDS.sort)

    expect(deliver_all("control")).to eq(1)
    expect(SPY.calls.size).to eq(1)

    # G7: correlation reaches the handler THROUGH the envelope; causation via the reloaded action,
    # which is byte-identical to the envelope value.
    ctx = SPY.calls.first[:request_context]
    expect(ctx.correlation_id).to eq(correlation)
    expect(SPY.calls.first[:command].action.causation_id).to eq(causation)
    expect(ctx.service_identity_id).to eq(Platform::ServiceIdentity.scheduled_action_executor)

    expect(row(id)["status"]).to eq("completed")
  end

  it "applies the domain effect at-most-once when the same envelope is delivered twice" do
    id = create_due
    Platform::ScheduledActions::Dispatcher.new.dispatch_due
    args = queued("control").first

    Platform::ScheduledActions::ExecutionJob.new.perform(args)
    expect(SPY.calls.size).to eq(1)
    expect(row(id)["status"]).to eq("completed")

    # Sidekiq is at-least-once: a redelivery of the exact same envelope must do no product work.
    Platform::ScheduledActions::ExecutionJob.new.perform(args)
    expect(SPY.calls.size).to eq(1)
    expect(row(id)["status"]).to eq("completed")
  end

  it "executes exactly once when the same delivery is processed by two workers concurrently" do
    id = create_due
    Platform::ScheduledActions::Dispatcher.new.dispatch_due
    args = queued("control").first

    2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Platform::ScheduledActions::ExecutionJob.new.perform(args)
        end
      end
    end.each(&:join)

    expect(SPY.calls.size).to eq(1)
    expect(row(id)["status"]).to eq("completed")
  end

  it "re-enqueues the SAME identity after lease expiry; a stale delivery is a no-op" do
    id = create_due
    Platform::ScheduledActions::Dispatcher.new.dispatch_due
    stale = queued("control").first
    expect(stale["claim_generation"]).to eq(1)
    Sidekiq::Queue.new("control").clear # the stale delivery is still "in flight"; we keep its args

    # The worker was lost after claiming: the lease expires and recovery returns the SAME identity.
    ScheduledActionHarness.elapse_lease!(id)
    expect(Platform::ScheduledActions::Scheduler.new.recover_expired_leases).to eq(1)

    d2 = Platform::ScheduledActions::Dispatcher.new.dispatch_due
    fresh = queued("control").first
    expect(d2.first.action_id).to eq(id)              # same action identity
    expect(fresh["claim_generation"]).to eq(2)         # only the claim generation advanced
    expect(fresh["work_id"]).not_to eq(stale["work_id"])

    # The stale delivery (generation-1 binding) no longer matches the action's generation -> no-op.
    # The action stays claimed by the fresh dispatch, awaiting the fresh delivery.
    Platform::ScheduledActions::ExecutionJob.new.perform(stale)
    expect(SPY.calls).to be_empty
    expect(row(id)["status"]).to eq("claimed")

    # The fresh delivery executes exactly once.
    Platform::ScheduledActions::ExecutionJob.new.perform(fresh)
    expect(SPY.calls.size).to eq(1)
    expect(row(id)["status"]).to eq("completed")
  end

  it "enqueues NOTHING to Redis when the enqueue fails, and records the dispatch failure" do
    id = create_due
    failing_job = Class.new do
      def self.set(**) = self
      def self.perform_async(*) = raise(RuntimeError, "redis unreachable")
    end

    dispatched = Platform::ScheduledActions::Dispatcher.new(job: failing_job).dispatch_due
    expect(dispatched.map(&:outcome)).to eq([:rescheduled])
    expect(queued("control")).to be_empty
    expect(row(id).values_at("status", "dispatch_attempt_count")).to eq(["pending", "1"])
  end

  it "enqueues nothing for a scheduling transaction that rolled back (no row, no enqueue)" do
    ScheduledActionHarness.in_context(org) do |store, correlation|
      store.create(
        id: SecureRandom.uuid_v7, action_kind: "invitation_expire", action_schema_version: "1.0",
        organization_id: org, target_type: "invitation", target_id: SecureRandom.uuid_v7,
        due_at: ScheduledActionHarness.past, now: ScheduledActionHarness.past(7200),
        correlation_id: correlation, causation_id: correlation,
        executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
      )
      raise ActiveRecord::Rollback
    end

    expect(Platform::ScheduledActions::Dispatcher.new.dispatch_due).to be_empty
    expect(queued("control")).to be_empty
  end

  it "quarantines a delivery whose kind has no registered handler; no arbitrary dispatch, no product work" do
    id = create_due(kind: "session_expire", target_type: "session")
    Platform::ScheduledActions::Dispatcher.new.dispatch_due
    deliver_all("control")

    expect(SPY.calls).to be_empty
    expect(row(id).values_at("status", "reason")).to eq(%w[quarantined scheduled_work_mapping_mismatch])
  end
end
