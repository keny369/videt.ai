# frozen_string_literal: true

require "rails_helper"
require "securerandom"
require "sidekiq/testing"

# F-04 Background Execution — the singleton dispatcher (BACKGROUND_PROCESSING.md :67, :116).
# It claims committed due actions, mints one Work Dispatch Binding per action, and enqueues ONE
# scalar 8-field envelope (work_id = that binding) per action to its fixed queue. Enqueue is
# asserted in Sidekiq fake mode; the full execute path and the failure boundaries run against
# real Redis in the acceptance spec (dispatch retry is proved deterministically in
# dispatch_retry_spec.rb).
RSpec.describe Platform::ScheduledActions::Dispatcher, type: :model do
  self.use_transactional_tests = false

  after do
    Platform::ScheduledActions::ExecutionJob.clear
    ReceiptMinter.truncate_all
  end

  around { |example| Sidekiq::Testing.fake! { example.run } }

  let(:org) { TenantSeeder.create_organization }
  subject(:dispatcher) { described_class.new }

  def create_due(due_at:, action_kind: "invitation_expire", target_type: "invitation")
    ScheduledActionHarness.create(
      organization_id: org, target_id: SecureRandom.uuid_v7, action_kind:, target_type:, due_at:
    )[:id]
  end

  it "claims a due action, mints a binding, and enqueues a scalar 8-field envelope to its fixed queue" do
    id = create_due(due_at: ScheduledActionHarness.past)

    dispatched = dispatcher.dispatch_due
    expect(dispatched.map(&:action_id)).to eq([id])
    expect(dispatched.map(&:outcome)).to eq([:enqueued])
    work_id = dispatched.first.work_id
    expect(work_id).not_to be_nil

    jobs = Platform::ScheduledActions::ExecutionJob.jobs
    expect(jobs.size).to eq(1)
    expect(jobs.first["queue"]).to eq("control") # invitation_expire -> control (Catalogue)
    args = jobs.first["args"].first
    expect(args.keys.sort).to eq(Platform::ScheduledActions::Envelope::FIELDS.sort)
    expect(args["schema_version"]).to eq("1.0")
    expect(args["work_id"]).to eq(work_id)
    expect(args["work_type"]).to eq("scheduled_action_dispatch")
    expect(args["organization_id"]).to eq(org)
    expect(args["claim_generation"]).to be_positive
    expect(args["correlation_id"]).not_to be_nil
    expect(args["causation_id"]).not_to be_nil
  end

  it "makes work_id a durable Work Dispatch Binding bound to the claimed action (:243)" do
    id = create_due(due_at: ScheduledActionHarness.past)
    work_id = dispatcher.dispatch_due.first.work_id

    binding = DbInspector.one("SELECT * FROM work_dispatch_bindings WHERE id = $1::uuid", [work_id])
    expect(binding["source_action_id"]).to eq(id)
    expect(binding["target_type"]).to eq("scheduled_action") # generic: action is both source and target
    expect(binding["target_id"]).to eq(id)
    expect(binding["source_claim_generation"].to_i).to eq(1)
  end

  it "enqueues a lifecycle-queue action to the lifecycle queue" do
    create_due(due_at: ScheduledActionHarness.past, action_kind: "verification_material_destroy",
               target_type: "verification_request")
    dispatcher.dispatch_due
    expect(Platform::ScheduledActions::ExecutionJob.jobs.first["queue"]).to eq("lifecycle")
  end

  it "enqueues nothing when no action is due (transaction-safe: no row, no enqueue)" do
    create_due(due_at: ScheduledActionHarness.future)
    expect(dispatcher.dispatch_due).to be_empty
    expect(Platform::ScheduledActions::ExecutionJob.jobs).to be_empty
  end

  it "quarantines an action with no enqueueable work type rather than emit an unparseable envelope" do
    id = create_due(due_at: ScheduledActionHarness.past, action_kind: "evaluation_stage_advance",
                    target_type: "evaluation_stage")
    dispatched = dispatcher.dispatch_due

    expect(dispatched.map(&:outcome)).to eq([:unmappable])           # evaluation_stage_advance -> work_type nil
    expect(Platform::ScheduledActions::ExecutionJob.jobs).to be_empty
    expect(ScheduledActionHarness.row(id).values_at("status", "reason"))
      .to eq(%w[quarantined scheduled_work_mapping_mismatch])
  end

  it "applies the dispatch-failure path (no fire-and-forget) when Redis enqueue raises" do
    id = create_due(due_at: ScheduledActionHarness.past)
    failing_job = Class.new do
      def self.set(**) = self
      def self.perform_async(*) = raise(RuntimeError, "redis unreachable")
    end
    dispatcher = described_class.new(job: failing_job)

    dispatched = dispatcher.dispatch_due
    expect(dispatched.map(&:outcome)).to eq([:rescheduled])
    expect(Platform::ScheduledActions::ExecutionJob.jobs).to be_empty

    row = ScheduledActionHarness.row(id)
    expect(row["status"]).to eq("pending")                       # returned to pending, identity intact
    expect(row["dispatch_attempt_count"].to_i).to eq(1)
    expect(row["next_dispatch_at"]).not_to be_nil                # backoff gate set
    expect(row["reason"]).to eq("redis_dispatch_retry_scheduled")
  end
end
