# frozen_string_literal: true

require "rails_helper"
require "ipaddr"

# F-04 (FU-24, DECISIONS ADR-091) — THE FENCED SCHEDULED-ACTION LEASE HEARTBEAT.
#
# `WORKER_LEASE_SECONDS` is the worker's requested FLOOR, and legitimate work can exceed it: one content
# attempt is bounded PER HOP (11 connections at the 15-second timeout) and sitemap discovery paces :444's
# 30 and 120 seconds. Without renewal the lease expired under a LIVE worker and the ordinary path executed
# twice.
#
# CORRECTED BY ADR-095. This header used to say "`WORKER_LEASE_SECONDS` is 30 so a dead worker is recovered
# promptly... a permanently longer lease would hide that by making every real recovery slower." That is no
# longer the built system and stating it here would be a false claim in the file that is supposed to prove
# the opposite: for a kind that stamps `product_attempt_deadline`, the lease is DERIVED from that deadline
# and recovery of a dead worker takes up to the 15-minute cap. The trade was made knowingly — see ADR-095
# and the note carried on ADR-091 — and `WORKER_LEASE_SECONDS` now only floors the request.
#
# These exercise the REAL transport function against the real `scheduled_actions` row, through the same
# restricted connection the worker uses. Nothing here is a double.
RSpec.describe Platform::ScheduledActions::LeaseKeeper, type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  LEASE = Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS
  # :288's floor and cap as corrected by ADR-095. Restated here rather than derived from the document,
  # which is why `spec/architecture/` pins the same two numbers against
  # `specification/volume-ii/BACKGROUND_PROCESSING.md` — a spec agreeing with itself proves nothing.
  FLOOR_SECONDS = 60
  CAP_SECONDS = 900

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }

  # A real pending action, claimed by a scheduler owner and dispatched to a worker owner, which is the
  # state a handler actually runs in.
  def dispatched_action(worker_owner: SecureRandom.uuid_v7)
    scheduler_owner = SecureRandom.uuid_v7
    # Creation goes through the RUNTIME path under RLS — the transport role owns no table privileges — and
    # only the claim/dispatch/renew steps use the restricted transport connection. That split is the
    # ratified posture and this exercises both halves of it.
    created = ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7,
                                            due_at: Time.now.utc - 60, now: Time.now.utc)
    Platform::ScheduledActions::TransportConnection.with do |pg|
      store = Platform::ScheduledActions::Store.new(pg)
      claimed = store.claim_due(owner: scheduler_owner, limit: 10, lease_seconds: LEASE)
                     .find { |a| a.id == created[:id] }
      raise "action was not claimed" if claimed.nil?

      dispatched = store.dispatch(work_id: claimed.work_id,
                                  expected_generation: claimed.claim_generation,
                                  worker_owner:, lease_seconds: LEASE)
      raise "action was not dispatched" if dispatched.nil?

      { id: dispatched.id, owner: worker_owner, generation: dispatched.claim_generation }
    end
  end

  def action_row(id)
    DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [id])
  end

  def keeper_for(action, **overrides)
    described_class.new(action_id: action[:id], owner: action[:owner], generation: action[:generation],
                        lease_seconds: LEASE, **overrides)
  end

  def expire_lease(id)
    DbInspector.connection.exec_params(
      "UPDATE scheduled_actions SET lease_expires_at = now() - interval '1 second',
         state_version = state_version + 1 WHERE id = $1::uuid", [id])
  end

  describe "a live worker keeps its lease" do
    it "renews the lease it owns and records the heartbeat" do
      action = dispatched_action
      before = action_row(action[:id])
      expect(before["last_heartbeat_at"]).to be_nil

      expect(keeper_for(action).renew).to eq(described_class::HELD)

      after = action_row(action[:id])
      expect(after["last_heartbeat_at"]).not_to be_nil
      expect(Time.parse(after["lease_expires_at"])).to be > Time.parse(before["lease_expires_at"])
      expect(after["status"]).to eq("dispatched")
      expect(after["claim_owner"]).to eq(action[:owner])
      # Renewal extends ownership; it does not advance the claim generation, which is what a TRANSFER does.
      expect(after["claim_generation"]).to eq(before["claim_generation"])
    end

    it "PROOF 1 — work exceeding the lease stays owned, and each renewal is a bounded interval" do
      # The redirect-chain case: 11 hops at the 15-second bound is 165 s against a 30-second lease. Time is
      # simulated by renewing at the cadence rather than by spending 165 seconds.
      action = dispatched_action
      keeper = keeper_for(action)
      expect(keeper.interval).to eq(LEASE / 3.0)

      elapsed = 0
      6.times do
        elapsed += keeper.interval
        expect(keeper.renew).to eq(described_class::HELD)
      end

      expect(elapsed).to be > LEASE
      row = action_row(action[:id])
      expect(row["status"]).to eq("dispatched")
      expect(Time.parse(row["lease_expires_at"])).to be > Time.now.utc
      # No sweep can take it: the lease is live at every point.
      expect(Platform::ScheduledActions::TransportConnection.with { |pg|
        Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
      }).to eq(0)
    end
  end

  describe "bounded cadence" do
    it "PROOF 6 — renewal follows ELAPSED TIME, not the number of times it is asked" do
      # A heartbeat per redirect, per sitemap candidate or per loop iteration would trade a lease problem
      # for write amplification proportional to crawler activity. `renew_if_due` is safe to call anywhere
      # precisely because calling it more often does not write more often.
      action = dispatched_action
      keeper = keeper_for(action)
      before = action_row(action[:id])["state_version"].to_i

      500.times { keeper.renew_if_due }

      # The keeper renewed at construction time, so nothing is due yet: 500 calls, ZERO writes.
      expect(action_row(action[:id])["state_version"].to_i).to eq(before)
      expect(keeper.owned?).to be(true)
    end

    it "renews exactly once when the interval has elapsed, however many times it is asked" do
      action = dispatched_action
      # A keeper whose last renewal is already older than the interval.
      keeper = keeper_for(action)
      keeper.instance_variable_set(:@renewed_at, keeper.send(:monotonic) - (keeper.interval * 2))
      before = action_row(action[:id])["state_version"].to_i

      10.times { keeper.renew_if_due }

      expect(action_row(action[:id])["state_version"].to_i).to eq(before + 1)
    end
  end

  describe "fencing" do
    it "PROOF 4 — a stale worker cannot renew after ownership has transferred" do
      action = dispatched_action
      stale = keeper_for(action)
      # The lease lapses and the sweep hands the action back; a second worker then claims it, which
      # increments the claim generation and replaces the owner.
      expire_lease(action[:id])
      recovered = Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
      end
      expect(recovered).to eq(1)
      second = SecureRandom.uuid_v7
      Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg).claim_due(owner: second, limit: 10, lease_seconds: LEASE)
      end
      taken = action_row(action[:id])
      expect(taken["claim_owner"]).to eq(second)
      expect(taken["claim_generation"].to_i).to be > action[:generation].to_i

      expect(stale.renew).to eq(described_class::LOST)
      expect(stale.owned?).to be(false)

      # AND IT CHANGED NOTHING: the new owner's lease is untouched by the stale renewal.
      after = action_row(action[:id])
      expect(after["claim_owner"]).to eq(second)
      expect(after["lease_expires_at"]).to eq(taken["lease_expires_at"])
      expect(after["state_version"]).to eq(taken["state_version"])
    end

    it "refuses a renewal whose lease has ALREADY lapsed, because the sweep may take it at any moment" do
      action = dispatched_action
      keeper = keeper_for(action)
      expire_lease(action[:id])

      expect(keeper.renew).to eq(described_class::LOST)
      # An expired lease is the transport's to recover; resurrecting it would keep alive an action the
      # transport has given up on, which is the race an unconditional timestamp update would create.
      expect(action_row(action[:id])["status"]).to eq("dispatched")
    end

    it "refuses a renewal for the wrong owner, the wrong generation, or a settled action" do
      action = dispatched_action
      expect(keeper_for(action.merge(owner: SecureRandom.uuid_v7)).renew).to eq(described_class::LOST)
      expect(keeper_for(action.merge(generation: action[:generation].to_i + 5)).renew).to eq(described_class::LOST)

      Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg).settle(
          action_id: action[:id], owner: action[:owner], generation: action[:generation],
          status: "completed", reason: nil
        )
      end
      expect(keeper_for(action).renew).to eq(described_class::LOST)
    end

    it "PROOF 5 — renewal and lease recovery serialize; exactly one owner emerges" do
      action = dispatched_action
      keeper = keeper_for(action)
      expire_lease(action[:id])

      # Both run against the same row. The sweep takes it because the lease has lapsed; the renewal is
      # refused for exactly the same reason, so they cannot both succeed.
      recovered = Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
      end
      renewed = keeper.renew

      expect([recovered, renewed]).to eq([1, described_class::LOST])
      row = action_row(action[:id])
      expect(row["status"]).to eq("pending")
      expect(row["claim_owner"]).to be_nil
      # The lease was not shortened or extended by the losing party.
      expect(row["lease_expires_at"]).to be_nil
    end
  end

  describe "worker death" do
    it "PROOF 3 — when heartbeats cease the action is recoverable at ITS OWN lease, not a worst case" do
      # CORRECTED BY ADR-095. This used to assert recovery "within `WORKER_LEASE_SECONDS`" against a flat
      # 30. That is no longer true and asserting it would be a false proof: an action carrying no
      # `product_attempt_deadline` takes :288's 60-second FLOOR, and one that carries an hour-out deadline
      # is recoverable in up to the 15-minute cap. What remains true, and is what this proves, is that a
      # renewal never lengthens the lease BEYOND the rule — recovery is bounded by the action's own derived
      # lease and never by the 300-second product horizons.
      action = dispatched_action
      row = action_row(action[:id])
      expect(Time.parse(row["lease_expires_at"]) - Time.parse(row["claimed_at"]))
        .to be_within(1).of(FLOOR_SECONDS)
      keeper_for(action).renew
      renewed = action_row(action[:id])
      expect(Time.parse(renewed["lease_expires_at"]) - Time.now.utc).to be <= FLOOR_SECONDS + 1
      expect(FLOOR_SECONDS).to be < 300

      # Heartbeats cease; after the lease elapses the sweep recovers it for another worker.
      expire_lease(action[:id])
      expect(Platform::ScheduledActions::TransportConnection.with { |pg|
        Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
      }).to eq(1)
      expect(action_row(action[:id])["status"]).to eq("pending")
    end
  end

  describe "waiting without holding anything" do
    it "PROOF 2 — a product wait is divided at heartbeat deadlines and its TOTAL is unchanged" do
      action = dispatched_action
      slept = []
      elapsed = 0.0
      # The sleeper ADVANCES a simulated monotonic source instead of spending 120 seconds, so the wait's own
      # deadline arithmetic is what is under test rather than the machine's timer.
      keeper = keeper_for(action, monotonic: -> { elapsed },
                          sleeper: ->(s) { slept << s; elapsed += s })

      # A 120-second :444 wait, with the sleeper recording rather than spending it. The keeper's own
      # monotonic deadline is what ends the wait, so the divisions cannot shorten or lengthen the interval.
      keeper.wait(120_000)

      expect(slept.sum).to be_within(0.5).of(120.0)
      # Divided, not one uninterruptible sleep: no single division exceeds the renewal interval.
      expect(slept.max).to be <= keeper.interval
      expect(slept.size).to be >= 120 / keeper.interval
      # And it renewed across the wait rather than letting the lease lapse.
      expect(action_row(action[:id])["last_heartbeat_at"]).not_to be_nil
      expect(keeper.owned?).to be(true)
    end

    it "PROOF 6b — no database connection is held while waiting" do
      action = dispatched_action
      elapsed = 0.0
      keeper = keeper_for(action, monotonic: -> { elapsed }, sleeper: lambda { |s|
        # Inside the wait, an unrelated caller must be able to use the pool freely.
        expect(DbInspector.one("SELECT 1 AS n")["n"].to_i).to eq(1)
        elapsed += s
      })

      keeper.wait(5_000)

      expect(keeper.owned?).to be(true)
    end

    it "ends the wait early on a CONFIRMED transfer, and not on a transport failure" do
      action = dispatched_action
      elapsed = 0.0
      keeper = keeper_for(action, monotonic: -> { elapsed }, sleeper: ->(s) { elapsed += s })
      expire_lease(action[:id])

      expect(keeper.wait(120_000)).to eq(described_class::LOST)
      expect(keeper.owned?).to be(false)
    end
  end

  describe "transport failure is not an answer about ownership" do
    it "keeps the lease held, counts the failure, and leaves expiry as the backstop" do
      # Inferring ownership loss from an unreachable database would abandon work the worker still owns;
      # inferring success would ignore a real transfer. It is neither.
      action = dispatched_action
      keeper = keeper_for(action)
      allow(Platform::ScheduledActions::TransportConnection)
        .to receive(:with).and_raise(PG::ConnectionBad, "gone")

      expect(keeper.renew).to eq(described_class::HELD)
      expect(keeper.owned?).to be(true)
      expect(keeper.transport_failures).to eq(1)
    end
  end

  describe "the guard ASKS, and a lost lease releases rather than completes" do
    it "PROOF 9 — `Lease.owned?` is authoritative: a swept action is reported lost, not remembered as held" do
      # THE DEFECT THIS CLOSES. `owned?` read a cached flag, so a pass whose lease had already lapsed and
      # been swept saw `true` at every guard because nothing had asked the database. Found by review, which
      # demonstrated a delivery fetching and writing after the sweep had taken its action.
      action = dispatched_action
      keeper = keeper_for(action)
      # The cadence must be due, or an authoritative guard would still be answering from its last renewal.
      keeper.instance_variable_set(:@renewed_at, keeper.send(:monotonic) - (keeper.interval * 2))
      expire_lease(action[:id])
      expect(Platform::ScheduledActions::TransportConnection.with { |pg|
        Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
      }).to eq(1)

      Platform::ScheduledActions::Lease.with(keeper) do
        expect(Platform::ScheduledActions::Lease.owned?).to be(false)
      end
    end

    it "asks at most once per interval, so an authoritative guard is still not a poll" do
      action = dispatched_action
      keeper = keeper_for(action)
      before = action_row(action[:id])["state_version"].to_i

      Platform::ScheduledActions::Lease.with(keeper) do
        200.times { expect(Platform::ScheduledActions::Lease.owned?).to be(true) }
      end

      expect(action_row(action[:id])["state_version"].to_i).to eq(before)
    end

    it "PROOF 10 — a lease-lost delivery RELEASES the claim; it never completes the action" do
      # `f1_settle_scheduled_action` carries NO lease predicate, so in the window between a lease lapsing
      # and the sweep running the row is still `dispatched` under this owner and a settle MATCHES. ADR-091
      # asserted the opposite. A relinquished delivery therefore completed an action having done nothing,
      # with no attempt, no ledger and no successor.
      action = dispatched_action
      # The settle a stale worker WOULD have issued does match, which is why the Worker must not issue it.
      settled = Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg).settle(
          action_id: action[:id], owner: action[:owner], generation: action[:generation],
          status: "completed", reason: nil
        )
      end
      expect(settled).to be(true)

      # The release the Worker now issues instead returns the action to `pending` for recomputation (:297).
      other = dispatched_action
      released = Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg).release_claim(
          action_id: other[:id], owner: other[:owner], generation: other[:generation],
          reason: Platform::ScheduledActions::Worker::LEASE_LOST_REASON
        )
      end
      expect(released).to be(true)
      row = action_row(other[:id])
      expect(row["status"]).to eq("pending")
      expect(row["claim_owner"]).to be_nil
      expect(row["reason"]).to eq("scheduled_action_lease_lost")
    end
  end

  describe "the Worker's disposition for a lease-lost delivery" do
    it "PROOF 11 — releases the claim, and never settles the action completed" do
      # The action, the transport and the release are REAL; only the handler is stood in for, because the
      # property under test is the Worker's branch on a lease-lost result rather than any product logic.
      #
      # This is the defect ADR-091 recorded as impossible: it claimed "a stale worker's settle matches zero
      # rows". `f1_settle_scheduled_action` has NO lease predicate, so in the window between a lease lapsing
      # and the sweep running the row is still `dispatched` under this owner and the settle MATCHES — the
      # action was completed having done nothing, with no attempt, no ledger and no successor.
      action = dispatched_action
      failure = Platform::CommandResult.failure(
        result_id: SecureRandom.uuid_v7, command_type: "wf005.record_fetch_attempt",
        failure: Platform::Failure.new(
          error_class: "conflict", error_code: Platform::ScheduledActions::Worker::LEASE_LOST_REASON,
          reason_code: Platform::ScheduledActions::Worker::LEASE_LOST_REASON, severity: "warning",
          retryable: true, recovery_action: "retry", support_reference: SecureRandom.uuid_v7
        ),
        audit_record_id: SecureRandom.uuid_v7, correlation_id: SecureRandom.uuid_v7
      )
      handler = Class.new { define_method(:call) { |**| failure } }
      handler.define_method(:call) { |**| failure }
      entry = Struct.new(:handler, :command).new(handler, Struct.new(:x).new(nil))
      worker = Platform::ScheduledActions::Worker.new(owner: action[:owner])
      allow(worker).to receive(:invoke).and_return(failure)
      claimed = Struct.new(:id, :action_kind, :claim_generation, :executing_service_identity_id)
                      .new(action[:id], "session_expire", action[:generation],
                           Platform::ServiceIdentity.scheduled_action_executor)

      outcome = worker.send(:run_handler, claimed, entry, correlation_id: SecureRandom.uuid_v7,
                                                          causation_id: SecureRandom.uuid_v7)

      expect(outcome.disposition).to eq(:released)
      row = action_row(action[:id])
      # :297's recovery — the same product attempt identity is recomputed — not a terminal completion.
      expect(row["status"]).to eq("pending")
      expect(row["completed_at"]).to be_nil
      expect(row["claim_owner"]).to be_nil
      expect(row["reason"]).to eq("scheduled_action_lease_lost")
    end
  end

  describe ":288's ratified interval" do
    it "is a third of the lease, floored to whole seconds and bounded from 5 through 30" do
      # Ratified, not invented: ":288 Heartbeat interval is one third of the lease duration, rounded down to
      # whole seconds and bounded from 5 through 30 seconds." The first implementation had the fraction and
      # neither bound, which reads as compliance without being it.
      action = dispatched_action
      expect(keeper_for(action).interval).to eq(10)
      { 3 => 5, 30 => 10, 90 => 30, 900 => 30, 20 => 6 }.each do |lease, expected|
        keeper = described_class.new(action_id: action[:id], owner: action[:owner],
                                     generation: action[:generation], lease_seconds: lease)
        expect(keeper.interval).to eq(expected), "lease #{lease} gave #{keeper.interval}"
        expect(keeper.interval).to eq(keeper.interval.floor)
      end
    end
  end

  # ONE `Outbound.fetch` IS NOT ONE BOUNDED REQUEST — the defect the second review demonstrated.
  #
  # F-01 follows up to `redirects_per_url` hard = 10, and takes a FRESH deadline per hop, so a call is up
  # to eleven connections at the 15-second timeout. A renewal placed only before the call covered the first
  # hop and nothing else: measured at 165 seconds of request time with ZERO heartbeat writes, under a
  # 30-second lease, after which the sweep reclaimed the action underneath a live worker.
  #
  # THE CLIENT HERE IS THE REAL ONE. Only the two ratified seams are injected — the DNS resolver and the
  # socket — so the redirect loop, the per-hop deadline and the point at which `redirect_guard` is consulted
  # are production code, not a restatement of it in a double.
  describe "the boundary INSIDE one fetch" do
    # A chain of `hops` redirects ending in a 200, each open advancing simulated time by the hard timeout.
    def redirect_connector(hops, elapsed_by:, on_open: nil)
      opens = []
      Object.new.tap do |c|
        c.define_singleton_method(:opens) { opens }
        c.define_singleton_method(:open) do |pinned:, host:, port:, deadline:| # rubocop:disable Lint/UnusedBlockArgument
          opens << host
          elapsed_by.call
          on_open&.call(opens.length)
          body = opens.length > hops ? "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok" :
                   "HTTP/1.1 302 Found\r\nLocation: https://hop#{opens.length}.example/robots.txt\r\n" \
                   "Content-Length: 0\r\n\r\n"
          Class.new do
            def initialize(bytes) = (@bytes = bytes.b; @pos = 0)
            def write(_bytes) = nil
            def close = nil

            def read(max, _deadline)
              return nil if @pos >= @bytes.bytesize

              slice = @bytes.byteslice(@pos, max)
              @pos += slice.bytesize
              slice
            end
          end.new(body)
        end
      end
    end

    def pinning_resolver
      Object.new.tap do |r|
        r.define_singleton_method(:resolve) do |host, timeout_s:| # rubocop:disable Lint/UnusedBlockArgument
          Platform::Outbound::GuardedResolver::Pin.new(address: IPAddr.new("93.184.216.34"),
                                                       candidates: [IPAddr.new("93.184.216.34")])
        end
      end
    end

    # Exactly what `Platform::Outbound.fetch` does, with the two seams injected.
    def guarded_get(url, connector, guard)
      policy = Platform::Outbound::RequestPolicy.build(
        timeout_s: 15, byte_cap: 1024, max_redirects: 10, allowed_ports: nil,
        user_agent: "F1CrawlerBot", redirect_guard: guard
      )
      Platform::Outbound::GuardedHttpClient.new(resolver: pinning_resolver, connector:).get(url, policy:)
    end

    it "PROOF 12 — a redirect chain renews ONCE PER HOP, not once per call" do
      action = dispatched_action
      elapsed = 0.0
      keeper = keeper_for(action, monotonic: -> { elapsed })
      before = action_row(action[:id])["state_version"].to_i
      # Each hop costs the hard request timeout, which is what makes four hops outlast a 30-second lease.
      connector = redirect_connector(3, elapsed_by: -> { elapsed += 15 })

      outcome = Platform::ScheduledActions::Lease.with(keeper) do
        guarded_get("https://start.example/robots.txt", connector, Platform::ScheduledActions::Lease.redirect_guard)
      end

      expect(outcome.status).to eq(200)
      expect(connector.opens.length).to eq(4)
      # 60 seconds of request time; interval is 10, and the guard sits between hops — so three renewals.
      # Without a per-hop boundary this delta is ZERO and the lease is gone by the second hop.
      expect(action_row(action[:id])["state_version"].to_i - before).to eq(3)
      expect(action_row(action[:id])["last_heartbeat_at"]).not_to be_nil
      expect(keeper.owned?).to be(true)
    end

    it "PROOF 13 — a CONFIRMED transfer refuses the next hop, so the platform stops requesting" do
      action = dispatched_action
      elapsed = 0.0
      keeper = keeper_for(action, monotonic: -> { elapsed })
      # The action is genuinely taken away, by the real sweep, while the chain is in flight.
      steal = lambda do |open_count|
        next unless open_count == 1

        expire_lease(action[:id])
        Platform::ScheduledActions::TransportConnection.with do |pg|
          Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
        end
      end
      connector = redirect_connector(5, elapsed_by: -> { elapsed += 15 }, on_open: steal)

      outcome = Platform::ScheduledActions::Lease.with(keeper) do
        guarded_get("https://start.example/robots.txt", connector, Platform::ScheduledActions::Lease.redirect_guard)
      end

      # ONE connection, then nothing: the hop after the transfer was never attempted.
      expect(connector.opens.length).to eq(1)
      expect(outcome.reason).to eq(:redirect_policy_denied)
      expect(keeper.lost?).to be(true)
    end

    it "composes a caller's own per-hop policy rather than replacing it" do
      action = dispatched_action
      seen = []
      guard = Platform::ScheduledActions::Lease.redirect_guard { |uri| seen << uri.to_s; true }
      connector = redirect_connector(2, elapsed_by: -> {})

      Platform::ScheduledActions::Lease.with(keeper_for(action)) do
        guarded_get("https://start.example/robots.txt", connector, guard)
      end

      expect(seen.length).to eq(2)
      expect(seen.first).to eq("https://hop1.example/robots.txt")
    end
  end

  # :288's LEASE DURATION RULE, as corrected by DECISIONS ADR-095.
  #
  #   "Lease duration is max(60 seconds, product_attempt_deadline - claim_time + 30 seconds) capped at
  #    15 minutes."
  #
  # THREE THINGS WERE WRONG AND ARE REPAIRED TOGETHER; each of the last two would otherwise have been left
  # standing as a knowingly false invariant.
  #
  #   * THE HEARTBEAT DID NOT DERIVE. `20260727120320` changed the claim and dispatch functions and left
  #     `f1_heartbeat_scheduled_action` writing the flat caller value, which the live worker supplies as
  #     `WORKER_LEASE_SECONDS` = 30. A `crawl_fetch_due` dispatched with a 900-second lease had it rewritten
  #     to 30 at the first renewal boundary, ten seconds into the handler, restoring the exact defect the
  #     derivation was introduced to close. PROOF 23.
  #   * THE CAP WAS NOT A CAP. It was `greatest(interval '15 minutes', <caller floor>)`, so a caller passing
  #     3600 received 3600. Sound only by accident of today's two literal 30s. PROOF 24.
  #   * THE 30-SECOND FLOOR COULD NOT SURVIVE ONE RATIFIED HOP. F-01 takes the resolver timeout (15 s,
  #     `Ceilings::DNS_TIMEOUT_MAX_S`) OUTSIDE the per-hop `deadline = monotonic + timeout_s` (15 s), so one
  #     hop is up to 30 seconds, and `30 > 10 + 30` is false. Reachable near the run deadline and for every
  #     kind that stamps no deadline. The floor is 60: `60 > 20 + 30`. PROOF 20.
  describe ":288's derived lease duration" do
    def lease_span(row) = Time.parse(row["lease_expires_at"].to_s) - Time.parse(row["claimed_at"].to_s)

    def claim_with_deadline(deadline, lease_seconds: LEASE)
      created = ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7,
                                              due_at: Time.now.utc - 60, now: Time.now.utc,
                                              product_attempt_deadline: deadline)
      Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg)
                                         .claim_due(owner: SecureRandom.uuid_v7, limit: 50, lease_seconds:)
      end
      action_row(created[:id])
    end

    # The state a handler actually runs in: claimed, then dispatched to a worker owner, carrying a product
    # deadline. PROOF 23 needs this because the defect lived between dispatch and the first renewal.
    def dispatched_with_deadline(deadline, lease_seconds: LEASE)
      worker_owner = SecureRandom.uuid_v7
      created = ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7,
                                              due_at: Time.now.utc - 60, now: Time.now.utc,
                                              product_attempt_deadline: deadline)
      Platform::ScheduledActions::TransportConnection.with do |pg|
        store = Platform::ScheduledActions::Store.new(pg)
        claimed = store.claim_due(owner: SecureRandom.uuid_v7, limit: 50, lease_seconds:)
                       .find { |a| a.id == created[:id] }
        raise "action was not claimed" if claimed.nil?

        dispatched = store.dispatch(work_id: claimed.work_id, expected_generation: claimed.claim_generation,
                                    worker_owner:, lease_seconds:)
        raise "action was not dispatched" if dispatched.nil?

        { id: dispatched.id, owner: worker_owner, generation: dispatched.claim_generation }
      end
    end

    it "PROOF 19 — the lease is derived from the product attempt deadline, floored and capped" do
      # A crawl run deadline an hour out takes the CAP, not the flat 30 seconds it used to get.
      expect(lease_span(claim_with_deadline(Time.now.utc + 3600))).to be_within(2).of(CAP_SECONDS)

      # Inside the cap the rule is deadline - claim + 30s.
      expect(lease_span(claim_with_deadline(Time.now.utc + 120))).to be_within(2).of(150)

      # Past its deadline, and with no deadline at all, the FLOOR holds — so every action kind that does
      # not stamp one gets the floor and nothing else. It is 60, not 30: see PROOF 20.
      expect(lease_span(claim_with_deadline(Time.now.utc - 600))).to be_within(2).of(FLOOR_SECONDS)
      expect(lease_span(claim_with_deadline(nil))).to be_within(2).of(FLOOR_SECONDS)

      # NEAR THE RUN DEADLINE the derived term is below the floor and the floor wins. This is the region
      # that made the 30-second floor a live defect rather than a theoretical one.
      expect(lease_span(claim_with_deadline(Time.now.utc + 5))).to be_within(2).of(FLOOR_SECONDS)
    end

    it "PROOF 20 — every lease the rule can produce outlasts one ratified redirect hop" do
      # THE INVARIANT: lease > interval + max_hop, where max_hop is F-01's 15-second resolver timeout plus
      # its 15-second per-hop deadline, and interval is :288's own cadence for that lease.
      max_hop = Platform::Outbound::Ceilings::DNS_TIMEOUT_MAX_S +
                Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING.fetch("request_timeout_seconds").fetch("hard")
      expect(max_hop).to eq(30)

      interval_for = lambda do |seconds|
        described_class.new(action_id: SecureRandom.uuid_v7, owner: SecureRandom.uuid_v7,
                            generation: 1, lease_seconds: seconds).interval
      end

      # ACROSS THE WHOLE RANGE, not at one convenient point. The rule can produce any value from the floor
      # to the cap, so the invariant is asserted over all of it.
      (FLOOR_SECONDS..CAP_SECONDS).each do |lease|
        expect(lease).to be > interval_for.call(lease) + max_hop,
                         "lease #{lease}s fails lease > interval + max_hop"
      end

      # THE SUPERSEDED FLOOR FAILS THE SAME INVARIANT, which is why 30 was a defective constant and not a
      # tuning choice. Asserted against the constant the specification used to carry, so this fails if the
      # floor is ever put back.
      superseded_floor = 30
      expect(superseded_floor).not_to be > interval_for.call(superseded_floor) + max_hop
      expect(FLOOR_SECONDS).to be > superseded_floor
    end

    it "PROOF 21 — the deadline is immutable, so ownership cannot be widened after the fact" do
      # A lease that could be extended by rewriting the deadline would be a way for a worker to extend its
      # own ownership, which is the whole thing the fence exists to prevent.
      created = ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7,
                                              due_at: Time.now.utc - 60, now: Time.now.utc,
                                              product_attempt_deadline: Time.now.utc + 120)
      expect do
        DbInspector.connection.exec_params(
          "UPDATE scheduled_actions SET product_attempt_deadline = now() + interval '1 hour',
             state_version = state_version + 1 WHERE id = $1::uuid", [created[:id]])
      end.to raise_error(/scheduled_action_immutable_field_changed/)
    end

    it "PROOF 23 — the heartbeat DERIVES too: it cannot collapse a 900-second lease to the worker constant" do
      # THE DEFECT THIS CLOSES, exactly as it was demonstrated. `Worker#lease_keeper_for` passes
      # `WORKER_LEASE_SECONDS` (30) to the heartbeat, and the heartbeat used to write it flat — so ten
      # seconds into the handler the derived lease was gone and one 30-second hop lapsed it under a live
      # worker. The renewal now re-derives from the SAME immutable deadline, so the worker's constant
      # cannot shorten a lease the specification says it still legitimately owns.
      action = dispatched_with_deadline(Time.now.utc + 3600)
      expect(lease_span(action_row(action[:id]))).to be_within(2).of(CAP_SECONDS)

      keeper = keeper_for(action)
      expect(keeper.renew).to eq(described_class::HELD)

      renewed = action_row(action[:id])
      # Measured from the heartbeat instant the function itself wrote, which is `transaction_timestamp()`.
      span = Time.parse(renewed["lease_expires_at"].to_s) - Time.parse(renewed["last_heartbeat_at"].to_s)
      expect(span).to be_within(2).of(CAP_SECONDS)
      expect(span).to be > LEASE
      expect(span).to be > FLOOR_SECONDS
    end

    it "PROOF 24 — the cap is ABSOLUTE in all three writers; a caller cannot buy a longer lease" do
      # It was `greatest(15 minutes, caller_floor)`, which is not a cap above 900 at all: a caller passing
      # 3600 received 3600 and held the row for an hour before the sweep could recover it. Both production
      # callers pass 30, so this was sound only by accident of today's values.
      greedy = 3600

      claimed = claim_with_deadline(Time.now.utc + 3600, lease_seconds: greedy)
      expect(lease_span(claimed)).to be_within(2).of(CAP_SECONDS)

      # And with NO product deadline, so the caller argument is the only term that could escape.
      expect(lease_span(claim_with_deadline(nil, lease_seconds: greedy))).to be_within(2).of(CAP_SECONDS)

      action = dispatched_with_deadline(nil, lease_seconds: greedy)
      expect(lease_span(action_row(action[:id]))).to be_within(2).of(CAP_SECONDS)

      expect(keeper_for(action, lease_seconds: greedy).renew).to eq(described_class::HELD)
      renewed = action_row(action[:id])
      span = Time.parse(renewed["lease_expires_at"].to_s) - Time.parse(renewed["last_heartbeat_at"].to_s)
      expect(span).to be_within(2).of(CAP_SECONDS)
    end

    it "PROOF 25 — all three lease writers carry ONE expression, byte for byte" do
      # THIS IS THE STRUCTURAL PROOF, and it is the one that would have caught the original defect. Three
      # functions assign `lease_expires_at`; the repaired migration writes all three from a single string.
      # Drift between them is precisely how the heartbeat came to disagree with the other two, and no
      # behavioural example noticed for a whole review round.
      writers = %w[f1_claim_due_scheduled_actions f1_dispatch_scheduled_action
                   f1_heartbeat_scheduled_action]

      expressions = writers.map do |name|
        body = DbInspector.one(
          "SELECT pg_get_functiondef(p.oid) AS def FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = $1", [name]
        ).fetch("def")
        match = body.match(/lease_expires_at = v_now \+ (least\(.*?interval '15 minutes'\))/m)
        raise "#{name} does not assign a capped lease" if match.nil?

        match[1].gsub(/\s+/, " ")
      end

      expect(expressions.uniq.length).to eq(1)
      # And the one expression is the ratified rule: the caller floor, :288's floor, the deadline term with
      # its grace, and the cap as the OUTER `least`.
      expect(expressions.first).to include("interval '#{FLOOR_SECONDS} seconds'")
      expect(expressions.first).to include("a.product_attempt_deadline - v_now")
      expect(expressions.first).to match(/\Aleast\(.*interval '15 minutes'\)\z/m)
      expect(expressions.first).not_to include("greatest(interval '15 minutes'")
    end
  end

  describe "the lease-aware execution context" do
    it "is absent outside a worker delivery, so a direct caller is never blocked by it" do
      expect(Platform::ScheduledActions::Lease.current).to be_nil
      expect(Platform::ScheduledActions::Lease.owned?).to be(true)
      expect(Platform::ScheduledActions::Lease.renew_if_due).to be_nil
    end

    it "scopes the keeper to one delivery and restores what was there before" do
      action = dispatched_action
      keeper = keeper_for(action)
      Platform::ScheduledActions::Lease.with(keeper) do
        expect(Platform::ScheduledActions::Lease.current).to be(keeper)
      end
      expect(Platform::ScheduledActions::Lease.current).to be_nil
    end

    it "reports a confirmed transfer through `owned?`, which is what product code branches on" do
      action = dispatched_action
      keeper = keeper_for(action)
      expire_lease(action[:id])
      keeper.renew

      Platform::ScheduledActions::Lease.with(keeper) do
        expect(Platform::ScheduledActions::Lease.owned?).to be(false)
      end
    end

    it "PROOF 8 — the pacer sleeps plainly without a lease and heartbeats with one" do
      action = dispatched_action
      elapsed = 0.0
      keeper = keeper_for(action, monotonic: -> { elapsed }, sleeper: ->(s) { elapsed += s })

      Platform::ScheduledActions::Lease.with(keeper) do
        expect(Platform::ScheduledActions::Lease.pacer.call(60_000)).to eq(described_class::HELD)
      end
      expect(action_row(action[:id])["last_heartbeat_at"]).not_to be_nil
    end
  end
end
