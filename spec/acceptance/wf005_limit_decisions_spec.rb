# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 limit decisions and the events derived from them (S-07-008;
# WORKFLOW_SPECIFICATIONS.md :442; API_CONTRACTS.md `crawl_limit_decision`).
#
# :442 — "Soft-limit crossing emits `CrawlSoftLimitApproaching` ONCE PER DIMENSION AND RUN. … At any
# other hard limit … emit `CrawlLimitReached` EXACTLY ONCE PER DIMENSION AND RUN."
#
# What these assert is not "an event was published" but the SHAPE OF THE CAUSALITY: the decision row
# is inserted first and its unique key decides whether anything is emitted at all, so the event is a
# consequence of a durable record rather than of runtime state that a retry or a crash can repeat.
RSpec.describe "WF-005 limit decisions", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-OBS] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  BYTES = "accounted_response_body_bytes_per_run"
  WALL_CLOCK = "wall_clock_run_duration"

  def admission = Workflows::Wf005::Admission.new
  def claim(ctx) = admission.claim_next(organization_id: ctx[:g][:organization_id],
                                        crawl_id: ctx[:crawl_id], now: start_now)

  def decisions(cid) = DbInspector.all(
    "SELECT * FROM crawl_limit_decisions WHERE crawl_id=$1::uuid ORDER BY limit_dimension, threshold_kind", [cid]
  )

  def events(cid) = DbInspector.all(
    "SELECT * FROM event_registry WHERE aggregate_id=$1::uuid
       AND event_type IN ('CrawlSoftLimitApproaching','CrawlLimitReached') ORDER BY created_at", [cid]
  )

  def envelope(event) = JSON.parse([event["event_bytes"].sub(/\A\\x/, "")].pack("H*"))

  # Drive one observation through the production surface, on a real connection.
  def observe(ctx, dimension:, threshold:, observed:, service: Workflows::Wf005::LimitDecisions.new)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      store = IdentityAccess::Infrastructure::CrawlLimitDecisionStore.new(pg)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      service.observe(pg, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
                      crawl_id: ctx[:crawl_id], dimension:, threshold:, observed:,
                      limits: Workflows::Wf005::EffectiveLimits.resolve([]), now: start_now)
    end
  end

  # ---- independent connections, for the concurrency proofs ---------------------
  #
  # The AR pool is five, and the racing observers must be genuinely simultaneous rather than queued
  # behind it — so each gets its own login as the RUNTIME role, which is subject to FORCE RLS
  # exactly as production is. `LimitDecisions#observe` takes the connection it is to use, so this
  # needs no production seam.

  def runtime_connection
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database],
               user: cfg[:username], password: cfg[:password].presence)
  end

  def enter(conn, ctx)
    IdentityAccess::Infrastructure::CrawlLimitDecisionStore.new(conn)
                                                          .enter_org_context(org: ctx[:g][:organization_id],
                                                                             correlation_id: SecureRandom.uuid_v7)
  end

  def observe_on(conn, ctx, threshold:, observed:, dimension: BYTES)
    Workflows::Wf005::LimitDecisions.new.observe(
      conn, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
      crawl_id: ctx[:crawl_id], dimension:, threshold:, observed:,
      limits: Workflows::Wf005::EffectiveLimits.resolve([]), now: start_now)
  end

  # Observed, not timed: the release happens because the wait was SEEN in `pg_stat_activity`.
  def waiting?(pid)
    DbInspector.one("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [pid])
               &.fetch("wait_event_type") == "Lock"
  end

  def wait_until(description, seconds: 10.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield
      raise "timed out waiting for: #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      Kernel.sleep(0.002)
    end
  end

  # Set the run's reserved bytes so the next admission sees exactly `bytes` of headroom.
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

  describe "the decision row is what emits (the transactional outbox)" do
    it "writes the decision and exactly one event derived FROM IT" do
      ctx = running_crawl
      outcome = observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      row = decisions(ctx[:crawl_id]).sole
      event = events(ctx[:crawl_id]).sole
      env = envelope(event)

      expect(outcome.emitted?).to be(true)
      expect(outcome.decision_id).to eq(row["id"])
      # Every customer-visible token is a COLUMN of the row, not an argument the caller passed.
      expect(env["decision_id"]).to eq(row["id"])
      expect(env["decision_type"]).to eq(row["decision_type"])
      expect(env["decision_value"]).to eq(row["decision_value"])
      expect(env["decision_status"]).to eq(row["decision_status"])
      expect(env["decision_reason_code"]).to eq(row["decision_reason_code"])
      expect(env["configured_value"]).to eq(row["configured_value"].to_i)
      expect(env["observed_value"]).to eq(row["observed_value"].to_i)
      expect(env["input_hash"]).to eq(row["input_sha256"].sub(/\A\\x/, ""))
      expect(env["output_hash"]).to eq(row["output_sha256"].sub(/\A\\x/, ""))
    end

    it "emits `CrawlLimitReached` with `limit_reached` for a hard threshold" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      event = events(ctx[:crawl_id]).sole
      expect(event["event_type"]).to eq("CrawlLimitReached")
      expect(event["event_profile"]).to eq("decision")
      env = envelope(event)
      expect(env["decision_value"]).to eq("hard_reached")
      expect(env["decision_reason_code"]).to eq("limit_reached")
      # ":773 — root reason equals `decision_reason_code` for catalogue source `decision`."
      expect(env["reason_code"]).to eq("limit_reached")
    end

    it "emits `CrawlSoftLimitApproaching` with a NULL reason for a soft threshold" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "soft", observed: 1_048_576_000)

      env = envelope(events(ctx[:crawl_id]).sole)
      expect(env["event_type"]).to eq("CrawlSoftLimitApproaching")
      expect(env["decision_value"]).to eq("soft_reached")
      expect(env["decision_reason_code"]).to be_nil
      expect(env["reason_code"]).to be_nil
    end

    it "names the Crawl as both root affected entity and decision subject" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      env = envelope(events(ctx[:crawl_id]).sole)
      expect(env["affected_entity_type"]).to eq("crawl")
      expect(env["affected_entity_id"]).to eq(ctx[:crawl_id])
      expect(env["subject"]).to eq({ "entity_type" => "crawl", "identity_kind" => "uuid",
                                     "entity_id" => ctx[:crawl_id] })
    end

    it "carries the governing Crawl Policy set and exactly one authority" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      env = envelope(events(ctx[:crawl_id]).sole)
      expect(env["definition_versions"]).to eq([Workflows::Wf005::EffectiveLimits::GLOBAL_VERSION])
      expect(env["authority_actor_id"]).to be_nil
      expect(env["authority_service_identity_id"]).not_to be_nil
      expect(env["actor_id"]).to be_nil
    end

    it "writes the audit record the event names" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      env = envelope(events(ctx[:crawl_id]).sole)
      audit = DbInspector.one("SELECT * FROM audit_record_registry WHERE id=$1::uuid", [env["audit_record_id"]])
      expect(audit).not_to be_nil
      expect(audit["entity_id"]).to eq(ctx[:crawl_id])
      expect(audit["reason_code"]).to eq("limit_reached")
    end
  end

  describe "exactly once per dimension and run (:442)" do
    it "REPLAYS without emitting a second event" do
      ctx = running_crawl
      first = observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)
      second = observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      expect(first.emitted?).to be(true)
      expect(second.emitted?).to be(false)
      # The replay learns the ORIGINAL decision's identity rather than minting a second one.
      expect(second.decision_id).to eq(first.decision_id)
      expect(decisions(ctx[:crawl_id]).size).to eq(1)
      expect(events(ctx[:crawl_id]).size).to eq(1)
    end

    it "keeps the FIRST observation even when a later one reports a different value" do
      # T-IMM: a limit observation is a fact about a moment, and it does not become untrue when the
      # run continues. A second crossing must not rewrite what the first one told the customer.
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 9_999_999_999)

      expect(decisions(ctx[:crawl_id]).sole["observed_value"].to_i).to eq(1_310_720_000)
    end

    it "BLOCKS a second observer on the unique key until the first commits" do
      # The once-ness is asserted DIRECTLY, not inferred from a race that happened to interleave.
      # An uncommitted decision must make a concurrent observer WAIT on the index — that is what
      # makes "exactly once" a property of the schema rather than of scheduling. Mutation-checked:
      # drop `crawl_limit_decisions_once` and the second observer sails through and emits.
      ctx = running_crawl
      first = runtime_connection
      second = runtime_connection

      begin
        # The org context is TRANSACTION-LOCAL (`set_config(..., true)`), so it is established
        # inside the transaction it protects — which is also how the production unit of work does it.
        first.exec("BEGIN")
        enter(first, ctx)
        observe_on(first, ctx, threshold: "hard", observed: 1_310_720_000)

        second.exec("BEGIN")
        blocked = Thread.new do
          enter(second, ctx)
          observe_on(second, ctx, threshold: "hard", observed: 1_310_720_000)
        end

        wait_until("the second observer is waiting on the index") { waiting?(second.backend_pid) }
        expect(blocked.join(0.2)).to be_nil, "the second observer did not wait for the first"

        first.exec("COMMIT")
        outcome = blocked.value
        second.exec("COMMIT")

        # It waited, then learned it had lost — and emitted nothing.
        expect(outcome.emitted?).to be(false)
        expect(decisions(ctx[:crawl_id]).size).to eq(1)
        expect(events(ctx[:crawl_id]).size).to eq(1)
      ensure
        [first, second].each { |c| c.close if c }
      end
    end

    it "elects ONE winner among eight simultaneous observers" do
      # The blocking proof above is the load-bearing one; this is the same property under real
      # concurrency. Each observer gets its OWN connection rather than a pooled one, so eight
      # transactions are genuinely in flight instead of five queueing behind a pool of that size.
      ctx = running_crawl
      connections = Array.new(8) { runtime_connection }

      begin
        outcomes = connections.map do |c|
          Thread.new do
            c.exec("BEGIN")
            enter(c, ctx)
            result = observe_on(c, ctx, threshold: "hard", observed: 1_310_720_000)
            c.exec("COMMIT")
            result
          end
        end.map(&:value)

        expect(outcomes.count(&:emitted?)).to eq(1)
        expect(decisions(ctx[:crawl_id]).size).to eq(1)
        expect(events(ctx[:crawl_id]).size).to eq(1)
        # Every loser still learns WHICH decision won, so no caller is left without an identity to
        # record against its own work.
        expect(outcomes.map(&:decision_id).uniq.size).to eq(1)
      ensure
        connections.each(&:close)
      end
    end

    it "separates the dimensions and the thresholds — one claim does not consume another" do
      ctx = running_crawl
      a = observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)
      b = observe(ctx, dimension: BYTES, threshold: "soft", observed: 1_048_576_000)
      c = observe(ctx, dimension: WALL_CLOCK, threshold: "hard", observed: 60)

      expect([a, b, c].map(&:emitted?)).to all(be(true))
      expect(decisions(ctx[:crawl_id]).size).to eq(3)
      expect(events(ctx[:crawl_id]).map { |e| e["event_type"] })
        .to contain_exactly("CrawlLimitReached", "CrawlSoftLimitApproaching", "CrawlLimitReached")
    end
  end

  describe ":442's recorded facts" do
    it "records configured and observed value in the SAME units" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      row = decisions(ctx[:crawl_id]).sole
      # 1,250 MiB expressed as bytes, beside an observed byte count — recording `1250` here would
      # make the pair incomparable, which is the whole point of the MiB scaling.
      expect(row["configured_value"].to_i).to eq(1_250 * 1024 * 1024)
      expect(row["observed_value"].to_i).to eq(1_310_720_000)
    end

    it "records the affected Source and URL counts for a HARD limit" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "hard", observed: 1_310_720_000)

      row = decisions(ctx[:crawl_id]).sole
      # The seeded Source root is still awaiting selection, so it is exactly what the limit costs.
      expect(row["affected_url_count"].to_i).to eq(1)
      expect(row["affected_source_count"].to_i).to eq(1)
    end

    it "records ZERO affected work for a SOFT crossing, which stops nothing" do
      ctx = running_crawl
      observe(ctx, dimension: BYTES, threshold: "soft", observed: 1_048_576_000)

      row = decisions(ctx[:crawl_id]).sole
      expect(row["affected_url_count"].to_i).to eq(0)
      expect(row["affected_source_count"].to_i).to eq(0)
    end

    it "refuses a dimension the event contract does not admit" do
      ctx = running_crawl
      expect { observe(ctx, dimension: "accepted_pages", threshold: "hard", observed: 1) }
        .to raise_error(ArgumentError, /unknown limit dimension/)
    end
  end

  describe "the scheduler's own observation points" do
    it "emits the run-byte HARD limit from admission, before anything is fetched on it" do
      ctx = running_crawl
      set_remaining(ctx, 0)

      decision = claim(ctx)
      expect(decision.reason_code).to eq("run_byte_budget_exhausted")

      row = decisions(ctx[:crawl_id]).find { |d| d["limit_dimension"] == BYTES && d["threshold_kind"] == "hard" }
      expect(row).not_to be_nil
      expect(row["observed_value"].to_i).to eq(Workflows::Wf005::ByteAccounting::RUN_CEILING)
      expect(events(ctx[:crawl_id]).map { |e| e["event_type"] }).to include("CrawlLimitReached")
    end

    it "emits the run-byte SOFT limit from the RESERVED peak, not from committed bytes" do
      # ":442 — a soft event fires when the observed OR RESERVED value first equals the soft limit."
      # A reservation that is later released is invisible in the stored row, so the peak has to be
      # taken at the statement that produced it.
      ctx = running_crawl
      set_remaining(ctx, Workflows::Wf005::ByteAccounting::PER_URL_CEILING)

      claim(ctx)
      row = decisions(ctx[:crawl_id]).find { |d| d["limit_dimension"] == BYTES && d["threshold_kind"] == "soft" }
      expect(row).not_to be_nil
      expect(row["observed_value"].to_i).to eq(Workflows::Wf005::ByteAccounting::RUN_CEILING)
    end

    it "emits NO byte decision while the run is comfortably inside its budget" do
      ctx = running_crawl
      expect(claim(ctx).admitted?).to be(true)
      expect(decisions(ctx[:crawl_id])).to be_empty
      expect(events(ctx[:crawl_id])).to be_empty
    end

    it "emits the wall-clock HARD limit when the deadline has passed" do
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1
         WHERE id = $1::uuid", [ctx[:crawl_id], start_now - 1])

      expect(claim(ctx).reason_code).to eq("wall_clock_exhausted")
      row = decisions(ctx[:crawl_id]).sole
      expect(row["limit_dimension"]).to eq(WALL_CLOCK)
      expect(row["threshold_kind"]).to eq("hard")
      expect(row["configured_value"].to_i).to eq(60)
    end

    it "emits BOTH wall-clock crossings on the first admission past the deadline" do
      # The soft limb used to be `elsif expired`, so a run whose first admission after 45 minutes
      # landed past 60 never emitted `CrawlSoftLimitApproaching` at all — and `claim_next` returns
      # early on every later call, so the branch was never re-entered.
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE crawls SET started_at = $2::timestamptz, deadline_at = $3::timestamptz,
           state_version = state_version + 1 WHERE id = $1::uuid",
        [ctx[:crawl_id], start_now - (61 * 60), start_now - 60])

      expect(claim(ctx).reason_code).to eq("wall_clock_exhausted")

      rows = decisions(ctx[:crawl_id]).select { |d| d["limit_dimension"] == WALL_CLOCK }
      expect(rows.map { |d| d["threshold_kind"] }.sort).to eq(%w[hard soft])
      expect(rows.map { |d| d["observed_value"].to_i }.uniq).to eq([61])
      expect(events(ctx[:crawl_id]).map { |e| e["event_type"] }.sort)
        .to eq(%w[CrawlLimitReached CrawlSoftLimitApproaching])
    end

    it "emits the wall-clock SOFT limit at the soft bound while the run is still admitting" do
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE crawls SET started_at = $2::timestamptz, deadline_at = $3::timestamptz,
           state_version = state_version + 1 WHERE id = $1::uuid",
        [ctx[:crawl_id], start_now - (46 * 60), start_now + 600])

      expect(claim(ctx).admitted?).to be(true)
      row = decisions(ctx[:crawl_id]).sole
      expect(row["limit_dimension"]).to eq(WALL_CLOCK)
      expect(row["threshold_kind"]).to eq("soft")
      expect(row["observed_value"].to_i).to eq(46)
      expect(events(ctx[:crawl_id]).sole["event_type"]).to eq("CrawlSoftLimitApproaching")
    end

    it "does not emit a wall-clock decision on a run that has only just started" do
      ctx = running_crawl
      expect(claim(ctx).admitted?).to be(true)
      expect(decisions(ctx[:crawl_id]).map { |d| d["limit_dimension"] }).not_to include(WALL_CLOCK)
    end

    it "keeps the decision and its cause on ONE transaction" do
      # If the observation could commit without the event, or the event without the observation, the
      # "derive the event from the row" discipline would buy nothing. The decision is written on the
      # caller's connection inside the caller's unit of work, so a rollback takes both.
      ctx = running_crawl
      expect do
        Platform::UnitOfWork.run do |conn|
          pg = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlLimitDecisionStore.new(pg)
          store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
          Workflows::Wf005::LimitDecisions.new.observe(
            pg, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
            crawl_id: ctx[:crawl_id], dimension: BYTES, threshold: "hard", observed: 1_310_720_000,
            limits: Workflows::Wf005::EffectiveLimits.resolve([]), now: start_now)
          raise "caller failed after observing"
        end
      end.to raise_error(/caller failed after observing/)

      expect(decisions(ctx[:crawl_id])).to be_empty
      expect(events(ctx[:crawl_id])).to be_empty
    end
  end
end
