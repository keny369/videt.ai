# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 admission (S-07-008; WORKFLOW_SPECIFICATIONS.md :442/:456).
#
# :456 — "Selection under every finite bound is DETERMINISTIC" and "All run-wide byte, page, and
# queue admission accounting is also applied in dequeue sequence."
#
# S-07-007 enforced the SUM and not the ORDER: it claimed the frontier entry in one transaction and
# reserved bytes in another, so two workers claiming adjacent entries could reserve in either order
# and which URL received the last of the run's budget depended on thread scheduling. The ADR-026
# contract lens demonstrated a different pair winning on each run. These assert the repair.
RSpec.describe "WF-005 admission", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def admission = Workflows::Wf005::Admission.new

  def claim(ctx) = admission.claim_next(organization_id: ctx[:g][:organization_id],
                                        crawl_id: ctx[:crawl_id], now: start_now)

  def counters(cid) = DbInspector.one("SELECT * FROM crawl_budget_counters WHERE crawl_id=$1::uuid", [cid])

  def set_remaining(ctx, bytes)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      store.ensure_counters(id: Platform::Ids.system.generate, now: start_now,
                            correlation_id: SecureRandom.uuid_v7,
                            organization_id: ctx[:g][:organization_id],
                            project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id])
    end
    DbInspector.connection.exec_params(
      "UPDATE crawl_budget_counters
       SET reserved_response_bytes = $2, committed_response_bytes = $2, state_version = state_version + 1
       WHERE crawl_id = $1::uuid",
      [ctx[:crawl_id], Workflows::Wf005::ByteAccounting::RUN_CEILING - bytes])
  end

  describe "claiming and reserving are one decision" do
    it "admits the entry and its reservation together" do
      ctx = running_crawl
      decision = claim(ctx)

      expect(decision.admitted?).to be(true)
      expect(decision.entry["state"]).to eq("in_progress")
      expect(decision.reserved_bytes).to eq(Workflows::Wf005::ByteAccounting::PER_URL_CEILING)
      # The reservation is visible the moment the entry is claimed — not one transaction later,
      # where another worker could have taken the budget in between.
      expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i).to eq(decision.reserved_bytes)
    end

    it "carries the :456 ordering tuple, so accounting can be replayed in dequeue order" do
      ctx = running_crawl
      expect(claim(ctx).entry["dequeue_key"]).not_to be_nil
    end

    it "returns IDLE when the frontier is empty, without touching the budget" do
      ctx = running_crawl
      claim(ctx)                       # take the only root entry
      decision = claim(ctx)

      expect(decision.idle?).to be(true)
      expect(decision.admitted?).to be(false)
      expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i)
        .to eq(Workflows::Wf005::ByteAccounting::PER_URL_CEILING)
    end
  end

  describe "the run-wide byte bound (:442)" do
    it "reserves only what REMAINS when the run is nearly spent" do
      ctx = running_crawl
      set_remaining(ctx, 4096)
      expect(claim(ctx).reserved_bytes).to eq(4096)
    end

    it "refuses admission when the budget is spent, and says WHY" do
      ctx = running_crawl
      set_remaining(ctx, 0)
      decision = claim(ctx)

      expect(decision.admitted?).to be(false)
      expect(decision.limited?).to be(true)
      expect(decision.reason_code).to eq("run_byte_budget_exhausted")
      # The entry was claimed and is reported, so the caller can record it as a limit discard
      # rather than losing it — :452 keeps a candidate discarded by a Crawl limit in the denominator.
      expect(decision.entry).not_to be_nil
    end

    it "never lets concurrent admissions sum above the run-wide maximum" do
      # The property :442 states directly: "concurrent reservations MUST NOT sum above the run-wide
      # maximum". The frontier lock serialises them, so this also fixes the ORDER (below).
      ctx = running_crawl
      set_remaining(ctx, Workflows::Wf005::ByteAccounting::PER_URL_CEILING * 2)

      3.times { claim(ctx) }
      row = counters(ctx[:crawl_id])
      expect(row["reserved_response_bytes"].to_i)
        .to be <= Workflows::Wf005::ByteAccounting::RUN_CEILING
    end
  end

  describe "admission order IS dequeue order (:456)" do
    # Seed extra queued entries at the same depth so several are admissible at once.
    def seed_entries(ctx, count)
      root = DbInspector.one("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid", [ctx[:crawl_id]])
      (1..count).each do |i|
        url = format("https://shop.acme.example/p%02d", i)
        DbInspector.connection.exec_params(
          "INSERT INTO crawl_frontier_entries
             (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
              crawl_id, source_id, canonical_url, canonical_url_preimage, canonical_url_sha256, collision_ordinal,
              origin, depth, discovering_document_url, link_position, dequeue_key, state,
              scope_policy_id, scope_policy_version, enqueue_order, canonicalization_version)
           SELECT gen_random_uuid(), 0, now(), now(), gen_random_uuid(), e.organization_id,
                  e.project_id, e.crawl_id, e.source_id, $2, convert_to($2,'UTF8'),
                  sha256(convert_to($2,'UTF8')), 0, 'link', e.depth, '', 0,
                  -- A key that sorts by the index, so dequeue order is known independently of the
                  -- production encoder.
                  ('\\x00' || lpad(to_hex($3::int), 8, '0'))::bytea,
                  'queued', e.scope_policy_id, e.scope_policy_version, $3, e.canonicalization_version
           FROM crawl_frontier_entries e WHERE e.id = $1::uuid",
          [root["id"], url, i])
      end
    end

    it "admits in increasing dequeue key when several workers claim CONCURRENTLY" do
      # :456 — "Selection under every finite bound is deterministic." Claiming and reserving were
      # separate transactions, so which entry got the budget depended on scheduling. The frontier
      # advisory lock now spans both, so concurrent claimers serialise into dequeue order.
      ctx = running_crawl
      seed_entries(ctx, 6)

      all_keys = DbInspector.all(
        "SELECT dequeue_key FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key",
        [ctx[:crawl_id]]).map { |r| r["dequeue_key"] }

      admitted = 4.times.map { Thread.new { claim(ctx) } }.map(&:value).select(&:admitted?)
      keys = admitted.map { |d| d.entry["dequeue_key"] }

      # The property is WHICH ENTRIES were admitted, not which thread got which. `map(&:value)`
      # returns in thread-creation order, so asserting the returned sequence is sorted would be
      # asserting the scheduler, not the specification. What :456 requires is that the admitted SET
      # is the lowest-ordered prefix of the frontier — no worker may skip ahead of a lower key.
      expect(keys.size).to eq(4)
      expect(keys.uniq.size).to eq(4)
      expect(keys.sort).to eq(all_keys.first(4))
    end

    it "takes the FRONTIER LOCK across the reservation, so admission cannot interleave" do
      # Asserted directly rather than by racing: a race that only sometimes interleaves is a test
      # that only sometimes fails. Holding the same advisory key from another connection must BLOCK
      # admission — that is what makes the reservation happen in dequeue order, because the lock
      # already serialises the dequeue.
      ctx = running_crawl
      holder = DbInspector.connection
      holder.exec_params("SELECT pg_advisory_lock(hashtextextended($1, 0))",
                         ["crawl-frontier:#{ctx[:crawl_id]}"])

      begin
        done = false
        worker = Thread.new { d = claim(ctx); done = true; d }
        worker.join(1.5)
        expect(done).to be(false), "admission proceeded without the frontier lock"
      ensure
        holder.exec_params("SELECT pg_advisory_unlock(hashtextextended($1, 0))",
                           ["crawl-frontier:#{ctx[:crawl_id]}"])
      end

      expect(worker.value).to be_a(Workflows::Wf005::Admission::Decision)
      expect(done).to be(true)
    end

    it "gives the LAST of the budget to the lowest key, not to the fastest worker" do
      # The determinism that matters: at the boundary, which URL is admitted must be decided by the
      # ratified tuple. With one reservation's worth of budget left and several workers racing, the
      # winner must be the lowest-ordered entry every time.
      ctx = running_crawl
      seed_entries(ctx, 5)
      set_remaining(ctx, Workflows::Wf005::ByteAccounting::PER_URL_CEILING)

      results = 4.times.map { Thread.new { claim(ctx) } }.map(&:value)
      winners = results.select(&:admitted?)
      expect(winners.size).to eq(1)

      lowest = DbInspector.all(
        "SELECT dequeue_key FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key LIMIT 1",
        [ctx[:crawl_id]]).first["dequeue_key"]
      expect(winners.first.entry["dequeue_key"]).to eq(lowest)
      expect(results.count(&:limited?)).to be >= 1
    end
  end

  describe "the wall clock (:442 — 'At 60 elapsed minutes, no new request starts')" do
    it "refuses admission once the run's deadline has passed" do
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1
         WHERE id = $1::uuid", [ctx[:crawl_id], start_now - 1])

      decision = claim(ctx)
      expect(decision.limited?).to be(true)
      expect(decision.reason_code).to eq("wall_clock_exhausted")
      # Checked BEFORE the claim: an expired run does not take work out of the frontier only to
      # refuse it, which would leave the entry `in_progress` with nobody fetching it.
      expect(decision.entry).to be_nil
      expect(DbInspector.all("SELECT state FROM crawl_frontier_entries WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]]).map { |r| r["state"] }).to all(eq("queued"))
    end

    it "admits while the deadline is still ahead" do
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1
         WHERE id = $1::uuid", [ctx[:crawl_id], start_now + 600])
      expect(claim(ctx).admitted?).to be(true)
    end
  end
end
