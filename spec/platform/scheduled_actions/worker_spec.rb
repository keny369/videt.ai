# frozen_string_literal: true

require "rails_helper"

# The service worker path (BACKGROUND_PROCESSING.md :119 handoff; Job Catalogue
# `scheduled_action_dispatch` "execute one claimed due action"; :245 and :421
# fail-closed mapping; :297 recovery for a pure deterministic computation).
#
# The handler here is a stand-in, deliberately: this spec proves the transport
# mechanism — one execution per action however it is delivered, fail-closed
# dispatch, service-identity execution context and non-stranding recovery —
# independently of any product workflow.
RSpec.describe Platform::ScheduledActions::Worker, type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  SpyHandler = ScheduledActionSpies::Handler
  SpyCommand = ScheduledActionSpies::Command

  let(:org) { TenantSeeder.create_organization }
  let(:due) { Time.utc(2026, 7, 25, 10, 0, 0) }
  let(:registry) { Platform::ScheduledActions::Registry.new }
  let(:scheduler) { Platform::ScheduledActions::Scheduler.new }
  let(:worker) do
    described_class.new(registry:, scheduler:, clock: Platform::Clock.fixed(due), ids: Platform::Ids.system)
  end

  def ok_result(reason = nil)
    if reason
      Platform::CommandResult.failure(result_id: SecureRandom.uuid_v7, command_type: "ExpireInvitation",
                                      failure: Platform::Failure.new(error_class: "domain", error_code: "F1-DOMAIN-409",
                                                                     reason_code: reason, severity: "warning", retryable: false,
                                                                     recovery_action: "reread_current_state_and_submit_new_command",
                                                                     support_reference: SecureRandom.uuid_v7),
                                      audit_record_id: SecureRandom.uuid_v7, correlation_id: SecureRandom.uuid_v7)
    else
      Platform::CommandResult.success(result_id: SecureRandom.uuid_v7, command_type: "ExpireInvitation",
                                      payload: { state: "expired" }, audit_record_id: SecureRandom.uuid_v7,
                                      correlation_id: SecureRandom.uuid_v7)
    end
  end

  def register(action_schema_version: "1.0")
    registry.register(action_kind: "invitation_expire", action_schema_version:,
                      operation: "ExpireInvitation", handler: SpyHandler, command: SpyCommand)
  end

  def create(**overrides)
    ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7, due_at: due, **overrides)[:id]
  end

  def row(id) = ScheduledActionHarness.row(id)

  before { SpyHandler.reset! { |_, _| ok_result } }

  describe "ordinary execution" do
    it "claims, transfers, executes once and completes the action" do
      register
      id = create

      outcomes = worker.run_due_batch(now: due)

      expect(outcomes.map(&:disposition)).to eq([:completed])
      expect(SpyHandler.calls.size).to eq(1)
      completed = row(id)
      expect(completed["status"]).to eq("completed")
      expect(completed["completed_at"]).not_to be_nil
      expect(completed.values_at("claim_owner", "lease_expires_at", "claim_phase")).to all(be_nil)
    end

    it "executes under a service RequestContext bearing the action's executing Service Identity and no actor" do
      register
      create

      worker.run_due_batch(now: due)
      ctx = SpyHandler.calls.first[:request_context]

      expect(ctx.service_identity_id).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(ctx).to be_a(Platform::RequestContext)
      expect(ctx.now_utc).to eq(due)
      expect(SpyHandler.calls.first[:command].action.organization_id).to eq(org)
    end

    it "completes the action on a terminal product denial, because re-execution would change nothing" do
      register
      SpyHandler.reset! { |_, _| ok_result("invitation_not_active") }
      id = create

      outcomes = worker.run_due_batch(now: due)

      expect(outcomes.map(&:disposition)).to eq([:completed])
      expect(row(id)["status"]).to eq("completed")
      expect(row(id)["reason"]).to eq("invitation_not_active")
    end
  end

  describe "duplicate delivery" do
    it "executes exactly once when the same claimed action is delivered twice" do
      register
      id = create
      action = scheduler.claim_due(now: due).first

      first = worker.execute(action, now: due)
      second = worker.execute(action, now: due)

      expect(first.disposition).to eq(:completed)
      expect(second.disposition).to eq(:skipped)
      expect(SpyHandler.calls.size).to eq(1)
      expect(row(id)["status"]).to eq("completed")
    end

    it "executes exactly once when two workers race the same due batch" do
      register
      id = create
      workers = 2.times.map do
        described_class.new(registry:, scheduler: Platform::ScheduledActions::Scheduler.new,
                            clock: Platform::Clock.fixed(due), ids: Platform::Ids.system)
      end

      outcomes = workers.map do |w|
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { w.run_due_batch(now: due) } }
      end.map(&:value).flatten

      expect(outcomes.map(&:disposition)).to eq([:completed])
      expect(SpyHandler.calls.size).to eq(1)
      expect(row(id)["status"]).to eq("completed")
    end
  end

  describe "fail-closed dispatch" do
    it "quarantines an action whose kind has no registered handler and performs no product work" do
      id = create
      outcomes = worker.run_due_batch(now: due)

      expect(outcomes.map(&:disposition)).to eq([:quarantined])
      expect(outcomes.first.reason).to eq("scheduled_work_mapping_mismatch")
      expect(SpyHandler.calls).to be_empty
      expect(row(id).values_at("status", "reason")).to eq(%w[quarantined scheduled_work_mapping_mismatch])
    end

    it "quarantines an action whose schema version no registered handler declares" do
      register(action_schema_version: "2.0")
      id = create(action_schema_version: "1.0")

      outcomes = worker.run_due_batch(now: due)

      expect(outcomes.first.reason).to eq("scheduled_action_schema_unsupported")
      expect(SpyHandler.calls).to be_empty
      expect(row(id)["status"]).to eq("quarantined")
    end

    it "quarantines a transport-integrity deviation reported by the handler" do
      register
      SpyHandler.reset! { |_, _| ok_result("scheduled_action_target_mismatch") }
      id = create

      expect(worker.run_due_batch(now: due).map(&:disposition)).to eq([:quarantined])
      expect(row(id).values_at("status", "reason")).to eq(%w[quarantined scheduled_action_target_mismatch])
    end

    it "never recovers a quarantined action through the lease sweep" do
      id = create
      worker.run_due_batch(now: due)

      expect(scheduler.recover_expired_leases(now: due + 3600)).to eq(0)
      expect(row(id)["status"]).to eq("quarantined")
    end
  end

  describe "recovery" do
    it "releases the claim with a bounded classification when the handler raises, and re-executes later" do
      register
      failures = 0
      SpyHandler.reset! do |_, _|
        failures += 1
        raise "dependency unavailable" if failures == 1

        ok_result
      end
      id = create

      first = worker.run_due_batch(now: due)
      expect(first.map(&:disposition)).to eq([:released])
      released = row(id)
      expect(released["status"]).to eq("pending")
      expect(released["reason"]).to eq("scheduled_action_execution_failed")
      expect(released["claim_generation"].to_i).to eq(1)

      second = worker.run_due_batch(now: due)
      expect(second.map(&:disposition)).to eq([:completed])
      expect(SpyHandler.calls.size).to eq(2)
      expect(row(id)["claim_generation"].to_i).to eq(2)
    end

    it "never persists an exception message or backtrace" do
      register
      SpyHandler.reset! { |_, _| raise "PG::UndefinedTable: relation \"secrets\" does not exist at /app/x.rb:9" }
      id = create

      worker.run_due_batch(now: due)
      expect(row(id)["reason"]).to eq("scheduled_action_execution_failed")
    end

    it "recovers a worker lost after claiming but before dispatching" do
      register
      id = create
      scheduler.claim_due(now: due) # the process dies here

      expect(scheduler.recover_expired_leases(now: due + 31)).to eq(1)
      expect(worker.run_due_batch(now: due + 31).map(&:disposition)).to eq([:completed])
      expect(SpyHandler.calls.size).to eq(1)
      expect(row(id)["status"]).to eq("completed")
    end

    it "recovers a worker lost after a committed execution, and the re-execution is a duplicate no-op" do
      register
      id = create
      action = scheduler.claim_due(now: due).first
      # Dispatch and run the handler, then lose the process before the settle
      # transaction — the product effect is committed, the action is not.
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(action_id: id, expected_owner: scheduler.owner,
                       expected_generation: action.claim_generation,
                       worker_owner: worker.owner, now: due)
      end
      SpyHandler.calls << :committed_but_unrecorded
      expect(row(id)["status"]).to eq("dispatched")

      expect(scheduler.recover_expired_leases(now: due + 31)).to eq(1)
      # The idempotent handler reports the already-terminal result on replay.
      SpyHandler.reset! { |_, _| ok_result("invitation_not_active") }
      expect(worker.run_due_batch(now: due + 31).map(&:disposition)).to eq([:completed])
      expect(row(id).values_at("status", "reason")).to eq(%w[completed invitation_not_active])
    end
  end
end
