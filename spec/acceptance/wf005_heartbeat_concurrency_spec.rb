# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# TWO DELIVERIES OF ONE `crawl_fetch_due` RACING THE ENTITLEMENT HEARTBEAT (S-07-009; DECISIONS ADR-106).
#
# Two deliveries of one action are ordinary, not exotic: `CrawlStartStore` says so in its own words —
# "the transport recovers an expired worker lease and re-dispatches". Before ADR-106 both read the
# reservation with a plain SELECT, both decided the cadence from the same stale row, and
# `Service#heartbeat` — which locks and re-reads but never re-checks the CADENCE — renewed for whichever
# arrived. The loser then either violated `entitlement_lease_heartbeats_advances`
# (`renewed_lease_expires_at > prior_lease_expires_at`) as an unhandled `PG::CheckViolation` out of the
# workflow, or wrote a third heartbeat inside one five-minute window.
#
# The race is FORCED against the reservation row, using the harness's own `pg_locks` observation.
RSpec.describe "WF-005 entitlement heartbeat under two deliveries", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-DATA TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  HEARTBEAT_GATE = "f1-test-heartbeat-window"

  def action_row(id) = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [id])

  def reservation(ctx)
    DbInspector.one(<<~SQL, [ctx[:crawl_id]])
      SELECT r.* FROM entitlement_reservations r
      JOIN crawls c ON c.entitlement_reservation_id = r.id WHERE c.id = $1::uuid
    SQL
  end

  def heartbeats(ctx)
    DbInspector.all(<<~SQL, [ctx[:crawl_id]])
      SELECT h.* FROM entitlement_lease_heartbeats h
      JOIN crawls c ON c.entitlement_reservation_id = h.entitlement_reservation_id
      WHERE c.id = $1::uuid ORDER BY h.heartbeat_generation
    SQL
  end

  def fetchable
    ctx = running_crawl
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: "User-agent: *\nAllow: /\n")))
    resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
    clear_rate_window_for_crawl(ctx[:crawl_id])
    ctx
  end

  def first_action(ctx)
    link = Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                        .enter_org_context(org: ctx[:g][:organization_id],
                                                                          correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlFetchDueSchedule.link_next(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], now: start_now, correlation_id: SecureRandom.uuid_v7
      )
    end
    action_row(link[:action_id])
  end

  # The outbound facade permits nothing: these deliveries must not reach a request for the example to be
  # about the heartbeat. Each pass halts or defers after its renewal, which is all this needs.
  def deliver(ctx, action, at:)
    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: at
    )
    outbound = Object.new.tap do |o|
      o.define_singleton_method(:fetch) { |url, **_k| raise "unexpected outbound fetch: #{url}" }
    end
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(at), outbound:, pacer: pacer_for(ctx)
    )
  end

  # Suspend the winner INSIDE its heartbeat, holding the reservation row lock, so the loser is
  # demonstrably contending for it rather than merely running afterwards.
  def gate_heartbeat(key)
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION f1_test_gate_heartbeat() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        PERFORM pg_advisory_xact_lock(#{key});
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER f1_test_gate_heartbeat BEFORE INSERT ON entitlement_lease_heartbeats
        FOR EACH ROW EXECUTE FUNCTION f1_test_gate_heartbeat();
    SQL
    yield
  ensure
    conn.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_gate_heartbeat ON entitlement_lease_heartbeats;
      DROP FUNCTION IF EXISTS f1_test_gate_heartbeat();
    SQL
  end

  it "PROOF 92 — the loser re-reads the winner's cadence and renews nothing" do
    ctx = fetchable
    action = first_action(ctx)
    # Past :551's five-minute cadence, so both deliveries would decide "due" from the same stale row.
    at = start_now + Platform::Entitlement::InterimPolicy::HEARTBEAT_CADENCE_SECONDS + 60
    gate_key = RaceHarness.key_for(HEARTBEAT_GATE)

    controller = RaceHarness.open_connection
    winner_result = nil
    loser_result = nil
    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [gate_key])

      gate_heartbeat(gate_key) do
        winner = RaceHarness.spawn_operation(-> { deliver(ctx, action, at:) })
        RaceHarness.wait_until("the winner blocked inside its heartbeat") do
          RaceHarness.blocked_on(gate_key) >= 1
        end

        # The loser's clock is EARLIER than the winner's, which is the interleaving that produced the
        # unhandled `PG::CheckViolation`: its renewed expiry would not advance the winner's.
        loser = RaceHarness.spawn_operation(-> { deliver(ctx, action, at: at - 30) })
        # Observably contending for the reservation ROW THE WINNER HOLDS — not merely running later, and
        # not merely "something on this cluster is waiting". `blocked_on_row_behind` asserts the causal
        # edge: an ungranted row waiter in THIS database whose blocker is the backend queued on
        # `gate_key`. The unscoped `pg_locks` count this replaced was satisfiable by any transaction in
        # any database, which made PROOF 92 pass 10/10 with `lock_reservation` deleted (round 3, R3-5).
        RaceHarness.wait_until("the loser blocked on the reservation row behind the winner") do
          RaceHarness.blocked_on_row_behind(gate_key) >= 1
        end

        controller.exec_params("SELECT pg_advisory_unlock($1)", [gate_key])
        winner_result = winner.value
        loser_result = loser.value
      end
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      controller.close
    end

    # NEITHER DELIVERY RAISED. Before the repair the loser surfaced
    # `PG::CheckViolation … entitlement_lease_heartbeats_advances` out of the workflow.
    [winner_result, loser_result].each do |r|
      expect(r).to be_a(Platform::CommandResult), "a delivery raised instead of returning: #{r.inspect}"
    end

    # EXACTLY ONE RENEWAL. :551 asks for a heartbeat "at least every 5 minutes"; two deliveries of one
    # action are one occasion, not two.
    rows = heartbeats(ctx)
    expect(rows.size).to eq(1)
    expect(rows.first["heartbeat_generation"].to_i).to eq(1)
    expect(Time.parse(reservation(ctx)["last_heartbeat_at"]).getutc).to eq(at)
    expect(Time.parse(reservation(ctx)["lease_due"]).getutc)
      .to eq(at + Platform::Entitlement::InterimPolicy::LEASE_RENEWAL_SECONDS)
    expect(reservation(ctx)["state"]).to eq("executing")
  end
end
