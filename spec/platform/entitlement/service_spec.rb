# frozen_string_literal: true

require "rails_helper"

# F-05 entitlement reservation service (entitlement-interim-v1) — the reserve/commit/release/heartbeat
# surface exercised over the REAL runtime path (f1_web inside a proved Organization context, under
# FORCE RLS), the way StartCrawl (S-07-003) will consume it. Time is caller-supplied (the consuming
# operation's clock), so lifecycle instants are deterministic.
RSpec.describe Platform::Entitlement::Service, type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  let(:t0) { Time.utc(2026, 7, 27, 10, 0, 0) }

  before { seed_active_policy(org) }

  def seed_active_policy(organization_id, semantic: "entitlement-interim-v1", plan: "interim-baseline-plan-v1")
    DbInspector.connection.exec_params(<<~SQL, [SecureRandom.uuid_v7, organization_id, semantic, plan, { value: Digest::SHA256.digest("interim"), format: 1 }])
      INSERT INTO entitlement_policies
        (id, state_version, created_at, updated_at, correlation_id, organization_id, policy_type,
         semantic_version, plan_version, status, content_sha256, effective_at)
      VALUES ($1::uuid,0,now(),now(),gen_random_uuid(),$2::uuid,'entitlement',$3,$4,'active',$5,now())
    SQL
  end

  def run(organization_id = org)
    result = nil
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [organization_id, SecureRandom.uuid_v7])
      result = yield(described_class.new(pg))
    end
    result
  end

  def reserve(now: t0, requested: 1, operation: "crawl.start", organization_id: org,
              subject: { account_id: SecureRandom.uuid_v7, service_identity_id: nil }, reservation_id: SecureRandom.uuid_v7)
    run(organization_id) do |svc|
      svc.reserve(operation:, organization_id:, subject:, requested_units: requested,
                  correlation_id: SecureRandom.uuid_v7, now:, idempotency_key_digest: Digest::SHA256.digest(SecureRandom.hex(8)),
                  ids: { decision: SecureRandom.uuid_v7, reservation: reservation_id, window: SecureRandom.uuid_v7 })
    end
  end

  def reservation(id) = DbInspector.one("SELECT * FROM entitlement_reservations WHERE id = $1::uuid", [id])
  def decision(id) = DbInspector.one("SELECT * FROM entitlement_decisions WHERE id = $1::uuid", [id])
  def only_window = DbInspector.one("SELECT * FROM entitlement_counter_windows LIMIT 1")

  describe "reserve — the atomic high-cost decision (WORKFLOW :519, :550)" do
    it "allows within the limit, writing a Decision + a reserved reservation and accruing the units" do
      d = reserve
      expect(d.decision).to eq("allow")
      expect(d.reason_code).to eq("within_limit")
      expect(d.reservation_id).to be_present
      expect(reservation(d.reservation_id)["state"]).to eq("reserved")
      expect(reservation(d.reservation_id)["units"]).to eq("1")
      win = only_window
      expect(win["reserved_units"]).to eq("1")
      expect(win["committed_units"]).to eq("0")
      expect([win["soft_limit"], win["hard_limit"]]).to eq(%w[3 4])
      expect(win["counter_group"]).to eq("crawl.start")
      # The immutable Decision pins before/after counters and the resolved limits.
      dec = decision(d.decision_id)
      expect(dec["decision"]).to eq("allow")
      expect([dec["active_reserved_before"], dec["active_reserved_after"]]).to eq(%w[0 1])
    end

    it "accumulates reserved units across reserves, warning at soft and blocking above hard" do
      results = 5.times.map { |i| reserve(now: t0 + i) } # each accrues one reserved unit
      expect(results.map(&:reason_code)).to eq(
        %w[within_limit within_limit soft_limit_reached soft_limit_reached hard_limit_exceeded])
      expect(results.map(&:decision)).to eq(
        %w[allow allow allow_with_warning allow_with_warning block])
      # The blocked 5th created no reservation and accrued nothing beyond the 4 held units.
      expect(results.last.reservation_id).to be_nil
      expect(only_window["reserved_units"]).to eq("4")
      expect(DbInspector.count("entitlement_reservations")).to eq(4)
    end

    it "blocks an unknown operation and an org with no active policy, with no window or reservation" do
      unknown = reserve(operation: "teleport")
      expect([unknown.decision, unknown.reason_code]).to eq(["block", "operation_unknown"])
      other = TenantSeeder.create_organization
      inactive = reserve(organization_id: other)
      expect([inactive.decision, inactive.reason_code]).to eq(["block", "entitlement_inactive"])
      expect(DbInspector.count("entitlement_counter_windows")).to eq(0)
      expect(DbInspector.count("entitlement_reservations")).to eq(0)
    end
  end

  describe "the reservation lifecycle (WORKFLOW :551, state machine :1012)" do
    it "reserve -> execute -> heartbeat -> commit moves the units from reserved to committed" do
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      expect(run { |s| s.start_execution(organization_id: org, reservation_id: rid, now: t0 + 60) }).to eq(:executing)
      hb = run { |s| s.heartbeat(organization_id: org, reservation_id: rid, worker_process_identity: "worker-1",
                                 worker_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor, now: t0 + 360,
                                 ids: { heartbeat: SecureRandom.uuid_v7 }) }
      expect(hb[:heartbeat_generation]).to eq(1)
      expect(reservation(rid)["lease_generation"]).to eq("1")
      out = { type: "crawl", id: SecureRandom.uuid_v7, sha256: nil }
      expect(run { |s| s.commit(organization_id: org, reservation_id: rid, durable_output: out, now: t0 + 600,
                                ids: { commit_intent: SecureRandom.uuid_v7 }) }).to eq(:committed)
      expect(reservation(rid)["state"]).to eq("committed")
      win = only_window
      expect([win["reserved_units"], win["committed_units"]]).to eq(%w[0 1])
      intent = DbInspector.one("SELECT * FROM entitlement_commit_intents WHERE reservation_id = $1::uuid", [rid])
      expect(intent["state"]).to eq("committed")
      expect(intent["durable_output_type"]).to eq("crawl")
    end

    it "release returns the held units without committing" do
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      run { |s| s.start_execution(organization_id: org, reservation_id: rid, now: t0 + 60) }
      expect(run { |s| s.release(organization_id: org, reservation_id: rid, reason: "crawl_failed", now: t0 + 90) }).to eq(:released)
      expect(reservation(rid)["state"]).to eq("released")
      expect([only_window["reserved_units"], only_window["committed_units"]]).to eq(%w[0 0])
    end

    it "expires a prestart reservation past its lease and releases its units" do
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      # Not yet due.
      expect(run { |s| s.expire(organization_id: org, reservation_id: rid, now: t0 + 60) }).to be_nil
      # 15 minutes + 1s past reserve -> prestart expiry.
      expect(run { |s| s.expire(organization_id: org, reservation_id: rid, now: t0 + (15 * 60) + 1) }).to eq(:expired)
      expect(reservation(rid)["state"]).to eq("expired")
      expect(only_window["reserved_units"]).to eq("0")
    end

    it "expires an executing reservation past its lease by releasing it" do
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      run { |s| s.start_execution(organization_id: org, reservation_id: rid, now: t0 + 60) } # lease_due = t0+60+15m
      expect(run { |s| s.expire(organization_id: org, reservation_id: rid, now: t0 + 60 + (15 * 60) + 1) }).to eq(:released)
      expect(reservation(rid)["state"]).to eq("released")
      expect(reservation(rid)["terminal_reason"]).to eq("lease_expired")
    end

    it "RELEASES (does not commit) when the durable point is reached past the lease deadline (WORKFLOW :551)" do
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      run { |s| s.start_execution(organization_id: org, reservation_id: rid, now: t0 + 60) } # lease_due = t0+60+15m
      # Commit 30 min in — past the 15-min heartbeat lease. Must release, not commit; the unit is NOT charged.
      out = { type: "crawl", id: SecureRandom.uuid_v7, sha256: nil }
      expect(run { |s| s.commit(organization_id: org, reservation_id: rid, durable_output: out, now: t0 + (30 * 60),
                                ids: { commit_intent: SecureRandom.uuid_v7 }) }).to eq(:released)
      expect(reservation(rid)["state"]).to eq("released")
      expect(reservation(rid)["terminal_reason"]).to eq("lease_expired_at_commit")
      expect([only_window["reserved_units"], only_window["committed_units"]]).to eq(%w[0 0])
    end

    it "AT EXACTLY the effective deadline, expiry wins and the reservation RELEASES (WORKFLOW :551)" do
      # :551 — "commits exactly once ONLY IF the durable commit point committed STRICTLY BEFORE that
      # instant", and expiry wins at equality. `commit` implements it as `now >= effective_deadline`.
      #
      # NOTHING PINNED THE EQUALITY UNTIL NOW (round 7, mutation-gap review). Weakening `>=` to `>`
      # survived the whole entitlement suite and the terminal-checkpoint spec — 50 examples, 0
      # failures — because every existing example sits a second or half an hour clear of the boundary.
      # `CompleteCrawl` settles on this rule, so it is a live S-07-009 invariant rather than an
      # abstract one.
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      run { |s| s.start_execution(organization_id: org, reservation_id: rid, now: t0 + 60) }
      # READ THE STORED DEADLINE, do not recompute it. A recomputed instant differs from the persisted
      # one by whatever rounding the column applies, and an "equality" proof that is not exactly equal
      # proves nothing — the first version of this example passed under its own target mutation for
      # precisely that reason.
      deadline = Platform::PgInstant.utc(reservation(rid)["lease_due"])

      out = { type: "crawl", id: SecureRandom.uuid_v7, sha256: nil }
      expect(run { |s| s.commit(organization_id: org, reservation_id: rid, durable_output: out, now: deadline,
                                ids: { commit_intent: SecureRandom.uuid_v7 }) }).to eq(:released)
      expect(reservation(rid)["state"]).to eq("released")
      expect(reservation(rid)["terminal_reason"]).to eq("lease_expired_at_commit")
      # And the microsecond BEFORE it still commits, so the rule is a boundary rather than a bar.
      other = SecureRandom.uuid_v7
      reserve(reservation_id: other)
      run { |s| s.start_execution(organization_id: org, reservation_id: other, now: t0 + 60) }
      other_deadline = Platform::PgInstant.utc(reservation(other)["lease_due"])
      expect(run { |s| s.commit(organization_id: org, reservation_id: other, durable_output: out,
                                now: other_deadline - Rational(1, 1_000_000),
                                ids: { commit_intent: SecureRandom.uuid_v7 }) }).to eq(:committed)
    end

    it "AT EXACTLY the prestart deadline, start_execution loses to expiry (WORKFLOW :551)" do
      # THE SURVIVOR FU-44 SHOULD HAVE NAMED (round 9, re-derived from clean evidence).
      #
      # FU-44 recorded that the boundary example above "DOES NOT kill the `>=` -> `>` mutation" at
      # `Entitlement::Service#commit`. Round 8 refuted that three times out of three, and this round
      # confirmed it a fourth: with the mutation VERIFIED APPLIED at :150 by diff, the example fails
      # deterministically. The premise was false because the substitution was never confirmed to have
      # landed — `if now >= effective_deadline(r)` appears THREE times in this file, and an unscoped
      # replacement lands on the FIRST of them, which is `start_execution` at :113 and not the site
      # FU-44 names.
      #
      # AND THAT FIRST SITE IS A REAL SURVIVOR. Weakening `start_execution`'s `>=` to `>` passes the
      # entire entitlement suite, because every example starts execution a minute into a fifteen-minute
      # prestart lease. It is the same sentence as the commit boundary — ":551, expiry wins at
      # equality" — at the other end of the reservation's life: at exactly the prestart deadline a
      # reservation must NOT begin executing, or a run starts against a lease that is already over.
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      # READ THE STORED DEADLINE, do not recompute it — the lesson the commit boundary above records.
      deadline = Platform::PgInstant.utc(reservation(rid)["lease_due"])

      expect(run { |s| s.start_execution(organization_id: org, reservation_id: rid, now: deadline) })
        .to eq(:expired)
      expect(reservation(rid)["state"]).to eq("reserved")

      # And the microsecond BEFORE it still starts, so this is a boundary rather than a bar.
      other = SecureRandom.uuid_v7
      reserve(reservation_id: other)
      other_deadline = Platform::PgInstant.utc(reservation(other)["lease_due"])
      expect(run do |s|
        s.start_execution(organization_id: org, reservation_id: other,
                          now: other_deadline - Rational(1, 1_000_000))
      end).to eq(:executing)
      expect(reservation(other)["state"]).to eq("executing")
    end

    it "caps a faithfully-heartbeating lease at the maximum-execution instant (CB-1: 65-min ceiling)" do
      rid = SecureRandom.uuid_v7
      reserve(reservation_id: rid)
      run { |s| s.start_execution(organization_id: org, reservation_id: rid, now: t0 + 60) } # max-execution at t0+60+3900s
      # Heartbeat every 5 minutes while under the 65-min ceiling — each is accepted.
      (1..12).each do |i|
        hb = run { |s| s.heartbeat(organization_id: org, reservation_id: rid, worker_process_identity: "w",
                                   worker_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor, now: t0 + 60 + (i * 300),
                                   ids: { heartbeat: SecureRandom.uuid_v7 }) }
        expect(hb).to be_a(Hash), "heartbeat #{i} at #{i * 5}min should be accepted, got #{hb.inspect}"
      end
      # A heartbeat AT the 65-min max-execution instant loses to expiry even though the 15-min lease is open.
      expect(run { |s| s.heartbeat(organization_id: org, reservation_id: rid, worker_process_identity: "w",
                                   worker_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor, now: t0 + 60 + 3900,
                                   ids: { heartbeat: SecureRandom.uuid_v7 }) }).to eq(:lease_expired)
      # And expire() at that instant releases it.
      expect(run { |s| s.expire(organization_id: org, reservation_id: rid, now: t0 + 60 + 3900) }).to eq(:released)
    end
  end
end
