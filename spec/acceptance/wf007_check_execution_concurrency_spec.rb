# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf006_parse_chain"

# THE DEFECT A LIVE RUN FOUND AND THE SUITE DID NOT.
#
# The seven Check attempts of one Evaluation are seven independent `check_attempt_due`
# actions on the `pipeline` queue, and that queue runs a five-worker process. So several
# attempts commit AT ONCE — and the last one to terminalize is the one that schedules the
# `seal_issue_set` stage.
#
# Executed serially, as every other example in this suite executes them, that works. Executed
# concurrently it did not: each transaction read a snapshot in which its siblings'
# terminalizations were still uncommitted, every attempt counted an outstanding sibling, and
# NOBODY scheduled the seal. The first real crawl of a real site reached seven terminal Check
# Results, sealed no Issue Set, and left the Evaluation `running` for ever behind the OD-018
# guard — the exact latch the whole chain exists to release, reached from a new direction.
#
# The fix is an advisory lock on the EVALUATION around the is-this-the-last decision, and this
# example is built so that removing it fails: the harness holds that very lock, and the two
# attempts can only both block on it if they both take it.
RSpec.describe "WF-007 concurrent check execution", type: :acceptance,
               acceptance_ids: %w[AC-WF-007 AC-PRULE-010], test_types: %w[TYP-CONC TYP-E2E] do
  include Wf006ParseChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def root_page = "<html><head><title>Acme Supplies</title></head><body>hello</body></html>"

  # An Evaluation whose applicability is sealed and whose slots are all still pending, with
  # its `check_attempt_due` actions created and undriven.
  def materialized_evaluation
    ctx = crawlable
    run_to_parsed(ctx, outbound_pages("/" => { body: root_page }))
    advance_wf007(ctx)
    ctx
  end

  def pending_attempt_actions(evaluation_id)
    DbInspector.all(<<~SQL, [evaluation_id])
      SELECT a.* FROM scheduled_actions a
      JOIN check_result_slots s ON s.id = a.target_id
      WHERE a.action_kind = 'check_attempt_due' AND s.evaluation_id = $1::uuid
      ORDER BY s.ordering
    SQL
  end

  # One attempt, on its own connection, exactly as a worker runs it.
  def attempt_operation(action)
    at = Time.parse(action["due_at"]).getutc
    lambda do
      command = Workflows::Wf007::Commands::ExecuteCheckAttempt.new(
        command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
        organization_id: action["organization_id"], target_type: action["target_type"],
        slot_id: action["target_id"], attempt_number: action["product_generation"].to_i,
        due_at: at, action_id: action["id"],
        action_identity_sha256: sha_bytes(action["identity_sha256"]), requested_at_utc: at
      )
      Workflows::Wf007::Handlers::ExecuteCheckAttempt.new.call(command:, request_context: executor_ctx(at))
    end
  end

  def seal_actions(evaluation_id)
    DbInspector.all(<<~SQL, [evaluation_id])
      SELECT * FROM scheduled_actions
      WHERE action_kind = 'evaluation_stage_advance' AND target_type = 'evaluation'
        AND target_id = $1::uuid AND product_generation = 5
    SQL
  end

  it "serializes the is-this-the-last decision, so exactly one seal is scheduled" do
    ctx = materialized_evaluation
    eid = evaluation_for(ctx[:crawl_id])["id"]
    actions = pending_attempt_actions(eid)
    expect(actions.length).to eq(7)

    # THE GATE IS THE PRODUCTION LOCK ITSELF. `contend` holds `evaluation:<id>` and waits
    # until every gated operation is blocked on it before releasing — which can only happen
    # if each attempt really takes that lock. An implementation that dropped the lock would
    # never block here, and the harness would fail with "0 of 2 operations blocked" rather
    # than passing by luck.
    key = RaceHarness.key_for("evaluation:#{eid}")
    results = RaceHarness.contend(key, attempt_operation(actions[0]), attempt_operation(actions[1]))

    expect(results.map(&:success?)).to eq([true, true])
    # Two of seven are terminal, so neither of these two is last and neither seals.
    expect(seal_actions(eid)).to be_empty
  end

  it "schedules the seal exactly once when the last two attempts race" do
    ctx = materialized_evaluation
    eid = evaluation_for(ctx[:crawl_id])["id"]
    actions = pending_attempt_actions(eid)

    # Drive the first five serially, so the race is genuinely over the LAST two — which is
    # the case that decides whether the Evaluation ever gets sealed at all.
    actions[0..4].each { |action| attempt_operation(action).call }

    key = RaceHarness.key_for("evaluation:#{eid}")
    results = RaceHarness.contend(key, attempt_operation(actions[5]), attempt_operation(actions[6]))
    expect(results.map(&:success?)).to eq([true, true])

    # EXACTLY ONE. Zero was the live defect; two would schedule the seal twice and seal the
    # Issue Set twice, which the unique index on `issue_sets.evaluation_id` would then refuse
    # — a different failure, equally not what the contract says.
    expect(seal_actions(eid).length).to eq(1)
    expect(DbInspector.all("SELECT * FROM check_result_slots WHERE evaluation_id=$1::uuid", [eid])
                      .map { |s| s["state"] }.uniq).to eq(["terminal"])
  end

  it "completes the Evaluation when the seal that race scheduled is driven" do
    ctx = materialized_evaluation
    eid = evaluation_for(ctx[:crawl_id])["id"]
    actions = pending_attempt_actions(eid)
    actions[0..4].each { |action| attempt_operation(action).call }

    key = RaceHarness.key_for("evaluation:#{eid}")
    RaceHarness.contend(key, attempt_operation(actions[5]), attempt_operation(actions[6]))
    advance_wf007(ctx)

    expect(evaluation_row(eid)["state"]).to eq("completed")
    expect(issue_set_of(eid)).not_to be_nil
    expect(check_results(eid).length).to eq(7)
  end
end
