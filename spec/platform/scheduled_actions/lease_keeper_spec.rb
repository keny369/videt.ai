# frozen_string_literal: true

require "rails_helper"

# F-04 (FU-24, DECISIONS ADR-091) — THE FENCED SCHEDULED-ACTION LEASE HEARTBEAT.
#
# `WORKER_LEASE_SECONDS` is 30 so a dead worker is recovered promptly, and legitimate work can exceed it:
# one content attempt is bounded PER HOP (11 connections at the 15-second timeout) and sitemap discovery
# paces :444's 30 and 120 seconds. Without renewal the lease expired under a LIVE worker and the ordinary
# path executed twice. A permanently longer lease would hide that by making every real recovery slower.
#
# These exercise the REAL transport function against the real `scheduled_actions` row, through the same
# restricted connection the worker uses. Nothing here is a double.
RSpec.describe Platform::ScheduledActions::LeaseKeeper, type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  LEASE = Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS

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
    it "PROOF 3 — when heartbeats cease the action is recoverable at the ORDINARY lease, not a worst case" do
      action = dispatched_action
      row = action_row(action[:id])
      # The lease a live worker holds is the ordinary one; renewal never lengthens it beyond that, so a
      # dead worker's action is recoverable within `WORKER_LEASE_SECONDS` and never within 300.
      expect(Time.parse(row["lease_expires_at"]) - Time.parse(row["claimed_at"]))
        .to be_within(1).of(LEASE)
      keeper_for(action).renew
      renewed = action_row(action[:id])
      expect(Time.parse(renewed["lease_expires_at"]) - Time.now.utc).to be <= LEASE + 1

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
