# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# OWNER RULING 2, HELD BY EXECUTION RATHER THAN BY A LIST (round 8, R8-2 and R8-3).
#
# "Once a Crawl becomes terminal, no new child fact may be inserted for that Crawl ... a stale or
# late worker must receive a CONTROLLED DOMAIN OUTCOME and must not append facts after
# terminalization."
#
# WHAT ROUND 8 FOUND, AND WHY THIS FILE IS SHAPED THE WAY IT IS. Round 6 repaired this at one
# producer. Round 7 found two more, repaired those, and wrote "there is one translation, every
# producer wraps its unit of work in it". Round 8 found a THIRD unrepaired producer —
# `FetchContent#settle`, on the one stretch of a pass that spends unbounded real time outside every
# lock — and found that PROOF 168, the proof that named the driver's gate creation, terminalized the
# Crawl BEFORE calling `advance`, so `authorize_run` refused at step zero and the branch it claimed
# to prove never executed. Both assertions passed anyway.
#
# So neither half is asserted from a list here:
#
#   * THE PRODUCER SET IS AN OBSERVATION. `GovernedWriteSentinel` watches every statement leaving
#     this process for the tables `f1_crawl_child_fact_closed` governs — the tables read from the
#     catalogue, not named here — and records which WF-005 line issued it and whether
#     `ClosedFactSet.translate` was on the stack at that moment. PROOF 173 asserts over what the
#     corpus DID, so a producer nobody remembered is in the census the first time it runs.
#
#   * EVERY PROOF PROVES IT REACHED THE CODE IT NAMES. Each one below asserts that the governed write
#     it is about was ATTEMPTED and REFUSED at the named source line. A proof that terminalizes too
#     early records no attempt at that line and fails, which is exactly what PROOF 168 would have
#     done had it been written this way.
RSpec.describe "WF-005 closed fact set", type: :acceptance,
                                          if: ENV["F1_ACCEPTANCE"] != "off" do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def requests = (@requests ||= [])

  def content_outbound(*outcomes)
    queue = outcomes.dup
    sink = requests
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **kwargs|
        sink << kwargs.merge(url:)
        result = queue.length > 1 ? queue.shift : queue.first
        result.respond_to?(:call) ? result.call(url, **kwargs) : result
      end
    end
  end

  def content_response(body: "<html><title>t</title></html>", byte_count: nil, truncated: false)
    Platform::Outbound::Outcome.response(
      status: 200, headers: { "content-type" => "text/html" }, body:,
      byte_count: byte_count || body.bytesize, truncated:, canonical_host: "shop.acme.example",
      port: 443, pinned_address: "198.51.100.7", final_url: "https://shop.acme.example/p1",
      redirect_count: 0, latency_ms: 5
    )
  end

  # A RESPONSE THAT CROSSES THE PER-URL BYTE CEILING, which is what makes `settle` write a governed
  # fact at all: `observe_fetch_limits` records a `crawl_limit_decisions` row only when a bound is
  # actually reached, so a small successful body would leave nothing for the closure to refuse and
  # the proof would be about a transaction that wrote nothing governed.
  def over_cap_response
    content_response(body: "x", byte_count: Workflows::Wf005::ByteAccounting::PER_URL_CEILING + 1,
                     truncated: true)
  end

  # The pass, through the REAL registered handler and a REAL action — the surface a `crawl_fetch_due`
  # delivery actually enters at. Nothing below drives `CrawlDriver` directly: R8-1 and R8-3 were both
  # findings about proofs that bypassed production entry points.
  def pass(ctx, outbound, at: start_now)
    action = DbInspector.one(<<~SQL, [ctx[:crawl_id]])
      SELECT sa.* FROM scheduled_actions sa
      JOIN crawl_frontier_entries e ON e.id = sa.target_id
      WHERE sa.action_kind = 'crawl_fetch_due' AND e.crawl_id = $1::uuid
        AND sa.status = 'pending'
      ORDER BY sa.due_at, sa.created_at LIMIT 1
    SQL
    raise "no crawl_fetch_due action exists" if action.nil?

    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: at
    )
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(at), outbound:, pacer: pacer_for(ctx)
    )
  end

  # DRIVE THE PASS CHAIN UNTIL THE CONTENT REQUEST, exactly as the scheduler does: a pass that is
  # host-paced or owed a retry decides nothing and re-enters against the same entry. The gate's rate
  # window is advanced between links because the harness cannot wait a real second per pass.
  def pass_until_request(ctx, outbound, limit: 6)
    results = []
    limit.times do
      results << pass(ctx, outbound)
      break if requests.any?

      advance_gate(ctx)
    end
    results
  end

  # The terminal checkpoint, through the REAL registered handler and a REAL action — the surface
  # `crawl_terminal_deadline` enters at. Included because CompleteCrawl is one of the two classified
  # untranslated producers, and a classification nothing exercises is a claim rather than a record.
  def checkpoint(ctx)
    row = DbInspector.one(<<~SQL, [ctx[:crawl_id]])
      SELECT * FROM scheduled_actions
      WHERE action_kind = 'crawl_terminal_deadline' AND target_id = $1::uuid AND status = 'pending'
      ORDER BY due_at LIMIT 1
    SQL
    return nil if row.nil?

    instant = Time.parse(row["due_at"]).getutc
    command = Workflows::Wf005::Commands::CompleteCrawl.new(
      command_id: SecureRandom.uuid_v7, schema_version: row["action_schema_version"],
      organization_id: row["organization_id"], target_type: row["target_type"],
      crawl_id: row["target_id"], due_at: instant, action_id: row["id"],
      action_identity_sha256: [row["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: instant
    )
    Workflows::Wf005::Handlers::CompleteCrawl.new.call(command:, request_context: executor_ctx(instant))
  end

  def terminalize(ctx)
    DbInspector.connection.exec_params(<<~SQL, [ctx[:crawl_id]])
      UPDATE crawls SET state='canceled', terminal_at=now(), completion_reason='canceled',
                        state_version = state_version + 1, updated_at = now()
      WHERE id = $1::uuid AND state = 'running'
    SQL
  end

  def fetchable(robots: "User-agent: *\nAllow: /\n")
    ctx = running_crawl
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: robots)))
    ctx[:gate_id] = gate_row(ctx[:crawl_id])["id"]
    ctx
  end

  # ROBOTS AND SITEMAPS ALREADY TERMINAL, so the ONE outbound call the pass makes is the content
  # request. Both are resolved through their own real surfaces, exactly as an earlier pass resolves
  # them; what this removes is the ambiguity of a stub that cannot tell which request it is serving.
  def ready_to_fetch
    ctx = fetchable
    resolve_sitemaps(ctx, outbound_returning(response(status: 404)))
    advance_gate(ctx)
    ctx
  end

  # Every governed write the block attempted at `file`, refused or not.
  def writes_at(attempts, file) = attempts.select { |a| a.site.to_s.start_with?(file) }

  # Every governed write whose EXECUTION PASSED THROUGH `file`, wherever the statement was issued.
  # The gate INSERT is issued by `HostGate` and reached through the driver's `ensure_gate`; what a
  # proof about `ensure_gate` must show is that the path ran, not which object holds the SQL.
  def writes_through(attempts, file)
    attempts.select { |a| a.stack.any? { |frame| frame.start_with?(file) } }
  end

  describe "a run that ends while a pass is in flight" do
    it "PROOF 171 — the content settle is REACHED, REFUSED, and reported as a controlled outcome" do
      # R8-2, END TO END AND THROUGH THE REAL HANDLER. `FetchContent#settle` opens after the content
      # request returns, which is the one stretch of a pass that spends unbounded real time outside
      # every lock — so this terminalizes the Crawl FROM INSIDE the outbound call, which is where a
      # cancellation genuinely lands. Before the repair this reached `ScheduledActions::Worker` as a
      # raw `PG::RaiseException` classified `scheduled_action_execution_failed`: the token meaning
      # DEFECT, for an ordinary and correctly-refused race.
      ctx = ready_to_fetch
      outbound = content_outbound(->(_url, **_kw) { terminalize(ctx); over_cap_response })

      results = nil
      attempts = GovernedWriteSentinel.record { results = pass_until_request(ctx, outbound) }
      result = results.last

      # THE PATH WAS REACHED. Not "the handler returned something acceptable": the governed write
      # inside `settle` was issued at `fetch_content.rb` and the database refused it. A proof that
      # terminalized too early — PROOF 168's defect — records nothing here and fails on this line.
      settle_writes = writes_through(attempts, "workflows/wf005/fetch_content.rb")
      expect(settle_writes).not_to be_empty,
                                  "no governed write was attempted from FetchContent; the proof did " \
                                  "not reach settle. Observed: #{attempts.map(&:site).uniq.inspect}"
      expect(settle_writes.map(&:table)).to include("crawl_limit_decisions")
      expect(settle_writes.select(&:refused?)).not_to be_empty
      # AND IT WAS TRANSLATED, by the one owner, at the moment of the write.
      expect(settle_writes.select(&:refused?)).to all(be_translated)

      # THE CONTROLLED OUTCOME. The request was made, so the bytes really did leave the platform; what
      # the contract requires is that the RECORD of them is refused and the worker is told a domain
      # outcome rather than handed a defect.
      expect(requests.length).to eq(1)
      expect(result).to be_success
      expect(result.payload[:pass_outcome]).to eq(Workflows::Wf005::CrawlDriver::HALTED)
      expect(result.payload[:reason_code]).to eq(Workflows::Wf005::ClosedFactSet::REASON)
      # NOTHING GOVERNED SURVIVED. The transaction aborted whole.
      expect(DbInspector.one("SELECT count(*) AS n FROM crawl_limit_decisions WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])["n"].to_i).to eq(0)
    end

    it "PROOF 172 — the driver's gate creation is REACHED after authorization and refused" do
      # THE REPLACEMENT FOR PROOF 168 (round 8, R8-3). The old proof terminalized the Crawl BEFORE
      # calling the driver, so `Admission#authorize_run` denied on `crawl["state"] != "running"` at
      # step zero and `ensure_gate` was never reached; removing the translation it named survived 2158
      # examples. The real window is the one this opens: RUNNING at authorization, terminal before the
      # first effect. `FetchAuthorization.host_of` is the last thing the pass does before the gate
      # insert, so terminalizing from there lands the cancellation exactly in that window — with no
      # sleep and no polling.
      ctx = running_crawl
      original = Workflows::Wf005::FetchAuthorization.method(:host_of)
      allow(Workflows::Wf005::FetchAuthorization).to receive(:host_of) do |url|
        terminalize(ctx)
        original.call(url)
      end

      result = nil
      attempts = GovernedWriteSentinel.record { result = pass(ctx, content_outbound(content_response)) }

      gate_writes = writes_through(attempts, "workflows/wf005/crawl_driver.rb")
      expect(gate_writes).not_to be_empty,
                                "the pass never attempted the gate INSERT, so it did not reach " \
                                "ensure_gate. Observed: #{attempts.map(&:site).uniq.inspect}"
      expect(gate_writes.map(&:table).uniq).to eq(["crawl_host_gates"])
      expect(gate_writes).to all(be_refused)
      expect(gate_writes).to all(be_translated)

      # AND THE AUTHORIZATION DID NOT REFUSE FIRST, which is the whole of R8-3: no request was made,
      # but the pass got past step zero to its first effect.
      expect(requests).to be_empty
      expect(result.payload[:pass_outcome]).to eq(Workflows::Wf005::CrawlDriver::HALTED)
      expect(result.payload[:reason_code]).to eq(Workflows::Wf005::ClosedFactSet::REASON)
      expect(DbInspector.one("SELECT count(*) AS n FROM crawl_host_gates WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])["n"].to_i).to eq(0)
    end

    it "PROOF 172b — the same pass with the run STILL RUNNING creates the gate and proceeds" do
      # THE OTHER HALF, so PROOF 172 cannot be satisfied by a pass that fails for any reason at all.
      # Identical fixture, identical seam, no terminalization: the gate is created and the write is
      # not refused.
      ctx = running_crawl
      attempts = GovernedWriteSentinel.record { pass(ctx, content_outbound(content_response)) }

      gate_writes = writes_through(attempts, "workflows/wf005/crawl_driver.rb")
      expect(gate_writes).not_to be_empty
      expect(gate_writes.select(&:refused?)).to be_empty
      expect(DbInspector.one("SELECT count(*) AS n FROM crawl_host_gates WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])["n"].to_i).to eq(1)
    end
  end

    it "PROOF 176 — FetchContent translates on its OWN entry point, not only under the pass" do
      # EACH PRODUCER IS CORRECT ON ITS OWN, AND THIS IS WHAT MAKES THAT CHECKABLE (round 8, R8-2).
      # PROOF 171 drives the real handler, so the PASS's translation covers `FetchContent` there and
      # removing this producer's own translation survives it — a proof that cannot fail for the defect
      # it is about is the failure class this round exists to close. So this drives `FetchContent#call`
      # DIRECTLY, which is a public production surface, and asserts the shape it hands its caller.
      #
      # NOT AN EARLIER BRANCH. The request is made (`requests.length == 1`) and the refused write is
      # observed inside `settle`, so the run was live through authorization, the slot claim and the
      # attempt claim, and went terminal in the window `settle` closes.
      ctx = ready_to_fetch
      outbound = content_outbound(->(_url, **_kw) { terminalize(ctx); over_cap_response })

      raised = nil
      attempts = GovernedWriteSentinel.record do
        begin
          Workflows::Wf005::FetchContent.new(outbound:).call(
            organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
            entry: DbInspector.one("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid " \
                                   "ORDER BY dequeue_key LIMIT 1", [ctx[:crawl_id]]),
            gate_id: ctx[:gate_id], now: start_now
          )
        rescue StandardError => e
          raised = e
        end
      end

      expect(requests.length).to eq(1)
      settle_writes = writes_through(attempts, "workflows/wf005/fetch_content.rb")
                      .select { |a| a.table == "crawl_limit_decisions" }
      expect(settle_writes).not_to be_empty,
                                  "the proof did not reach settle. Observed: " \
                                  "#{attempts.map { |a| [a.site, a.table] }.uniq.inspect}"
      expect(settle_writes).to all(be_refused)

      # THE CONTROLLED SHAPE, from this producer, to whatever calls it. A raw `PG::RaiseException` here
      # is what `ScheduledActions::Worker` classifies `scheduled_action_execution_failed`.
      expect(raised).to be_a(Workflows::Wf005::ClosedFactSet::CrawlWentTerminal)
      expect(raised).not_to be_a(PG::Error)
    end

  describe "the producer set" do
    it "PROOF 173 — every governed write production reached was translated or classified with a reason" do
      # THE COMPLETENESS CLAIM, MADE FROM EXECUTION. This example drives a full run through the real
      # entry points — StartCrawl seeds the frontier, a pass fetches, the checkpoint terminalizes —
      # and then asks the census what the corpus DID, rather than asserting a list of producers.
      ctx = ready_to_fetch
      attempts = GovernedWriteSentinel.record do
        pass_until_request(ctx, content_outbound(over_cap_response))
        checkpoint(ctx)
      end

      # NON-VACUITY FIRST. A census this proof did not fill would make every assertion below trivially
      # true, which is the failure class this whole file exists to close.
      reachable = attempts.select(&:reachable_in_production?)
      sites = reachable.map { |a| [a.site.split(":").first, a.table] }.uniq
      expect(reachable.length).to be >= 6
      expect(sites.length).to be >= 4
      # THREE DIFFERENT GOVERNED TABLES, WRITTEN FROM FOUR DIFFERENT PRODUCERS in one run: the host
      # gate, the per-URL limit decision `FetchContent#settle` makes, and the pass's own terminal
      # outcome. A census that lost its instrumentation would fail here before it could report
      # "no violations" for a run that observed nothing.
      expect(sites.map(&:last).uniq)
        .to include("crawl_host_gates", "crawl_limit_decisions", "crawl_terminal_outcomes")
      expect(sites.map(&:first).uniq.length).to be >= 4

      untranslated = reachable.reject(&:translated?)
      unclassified = untranslated.reject do |a|
        GovernedWriteSentinel::CLASSIFIED_UNTRANSLATED.key?(
          [a.site.split(":").first, a.stack.reverse.find { |f| f.start_with?("workflows/wf005/") }&.split(":")&.first,
           a.table]
        )
      end
      expect(unclassified).to be_empty, <<~MESSAGE
        A governed child fact was written from a WF-005 production path with no
        Wf005::ClosedFactSet.translate frame on the stack and no recorded reason:
        #{unclassified.map { |a| "#{a.table} at #{a.site}" }.uniq.join("\n")}
      MESSAGE
    end

    it "PROOF 174 — the instrument itself detects an untranslated governed write" do
      # THE SENTINEL IS NOT VACUOUS. Every assertion above is worth exactly what this one is: a real
      # WF-005 object is driven to write a governed table with no translation anywhere on the stack,
      # and the census records it as untranslated. Without this, an instrument that silently observed
      # nothing would make PROOF 171-173 pass forever.
      ctx = running_crawl
      attempts = GovernedWriteSentinel.record do
        in_gate(ctx[:g][:organization_id]) do |_store, gate|
          gate.ensure_gate(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
                           crawl_id: ctx[:crawl_id], canonical_host: "sentinel.example", now: start_now)
        end
      end

      observed = writes_at(attempts, "workflows/wf005/host_gate.rb")
      expect(observed).not_to be_empty
      expect(observed).to all(satisfy { |a| !a.translated? })
      # And it is correctly excluded from the RULE, because no production entry point is on its stack:
      # an example driving an internal directly says nothing about what production can reach.
      expect(observed.select(&:reachable_in_production?)).to be_empty
    end

    it "PROOF 175 — the completeness mechanism is RUNTIME, and it carries no exceptions" do
      # WHAT REPLACED THE EXCEPTION LIST, AND WHY IT IS NOT ANOTHER STATIC RULE (round 9, R9-1).
      #
      # Round 9 classified two producers as exceptions with careful reasoning, and the review found a
      # third — under one of those same handlers, in the same transaction — that the list did not
      # contain. So the list is empty and stays empty by construction: every WF-005 unit of work runs
      # beneath a `ClosedFactSet.translate` frame, including both command handlers that used to be the
      # exceptions.
      #
      # A LEXICAL RULE WAS TRIED AND REJECTED AS DISHONEST. Translation is applied at an ENTRY POINT
      # (`CrawlDriver#advance` wraps the whole pass; `StartCrawl#attempt` wraps its unit), and the
      # units themselves open in methods further down the call chain — so "the unit is lexically
      # inside a translate block" is false for most of them while the property they need is true.
      # Asserting the lexical form would have meant either rewriting the architecture to suit the
      # check or writing a check that reports what it can see rather than what matters.
      #
      # SO THE MECHANISM IS THE ONE THAT OBSERVES THE REAL THING: `GovernedWriteSentinel` watches every
      # statement reaching PostgreSQL through EVERY execution API `PG::Connection` exposes, derives the
      # governed tables from the catalogue, and fails the whole run — in an `after(:suite)` hook,
      # outside any example — on a governed write that production can reach with no translation frame
      # on its stack. It needs no list of producers, no list of exceptions and no list of forms.
      expect(GovernedWriteSentinel::CLASSIFIED_UNTRANSLATED).to be_empty

      # NON-VACUITY: the census this rests on observed real governed writes in this very example.
      ctx = ready_to_fetch
      attempts = GovernedWriteSentinel.record { pass_until_request(ctx, content_outbound(over_cap_response)) }
      reachable = attempts.select(&:reachable_in_production?)
      expect(reachable).not_to be_empty
      expect(reachable.reject(&:translated?)).to be_empty
    end
  end
end
