# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# ONE LOCK ORDER FOR THE TWO AUTHORITY ROWS, ACROSS EVERY WORKFLOW THAT TOUCHES BOTH
# (round-15 concurrency finding R15-CONC-1).
#
# WHAT FU-48 ADDED, AND WHAT IT COST. Before D7 each protected WF-005 write locked ONE row: the
# Organization's, for the epoch. FU-48 added a second locked relation — the granting Role Assignments,
# under `FOR SHARE OF ra` — and the statement takes them in the order its conjuncts are written:
# `organizations` first, then `role_assignments`.
#
# THE THREE WF-013 HANDLERS THAT REMOVE OR CHANGE AN ACTIVE GRANT WROTE THEM THE OTHER WAY ROUND —
# `role_assignments` first, then the epoch advance on `organizations` — in one transaction, with an
# ordinary inter-statement gap between the two. That is a cycle, and PostgreSQL resolves a cycle by
# aborting one side with SQLSTATE 40P01. Nothing on either path rescues it:
#
#   * when the customer's command is the victim, `QueueCrawl` / `CancelCrawl` / `ActivateCrawlPolicy`
#     raises `PG::TRDeadlockDetected` out of `#call` instead of returning the `Platform::CommandResult`
#     ADR-103 exists to guarantee;
#   * when the revocation is the victim, `RevokeRoleAssignment` raises, the grant stays `active` and
#     the epoch is not advanced — a security-critical revocation that did not land.
#
# WHICH SIDE DIES IS THE DEADLOCK DETECTOR'S CHOICE, i.e. arrival order. `start_crawl.rb` already
# records this exact failure mode as a blocker, in the abstract, for a different pair of rows.
#
# THE REPAIR IS ONE GLOBAL ORDER: `organizations` BEFORE `role_assignments`, everywhere. The WF-005
# side already had it and cannot easily be reordered (both locks are taken inside one statement), so
# the three WF-013 handlers advance the epoch FIRST. Both writes stay in the same transaction, both
# keep their guards and both still raise `LostRace` on zero rows, so no product semantics change: what
# changes is which of the two rows this transaction holds first.
#
# HOW THESE PROOFS AVOID ASSERTING THE ORDER THEY ARE TESTING. A probe that hard-codes "epoch first"
# would pass whatever the handlers do. So PROOF 262 READS THE ORDER OUT OF THE RUNNING HANDLER — the
# real command, observed at the connection — and PROOF 263 replays THAT observed order against a real
# WF-005 protected write driven into a genuine mid-flight block. Reverse the handler and the observed
# order reverses with it, and PROOF 263's control shows that the reversed order really does deadlock,
# so a green result is never the absence of a cycle-capable interleaving.
RSpec.describe "WF-005/WF-013 authority lock order", type: :acceptance,
                                                     acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
                                                     test_types: %w[TYP-INT TYP-SEC] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # SCOPED TO THIS FILE (round-16 architecture observation O-2). A top-level constant of the same
  # name lives in `wf005_authority_lock_concurrency_spec.rb`, and two proof files sharing a global
  # that decides `:blocked` vs `:committed` are coupled in the one place that must not be.
  def lock_timeout = "2000ms"
  # `RevokeRoleAssignment` requires a free-text reason of at least 20 characters.
  REVOCATION_REASON = "the round-15 lock-order proof revokes this grant deliberately"

  def tagged_connection(name)
    conn = RaceHarness.open_connection
    conn.exec("SET application_name = '#{name}'")
    conn
  end

  def pid_of(conn) = conn.exec("SELECT pg_backend_pid()").getvalue(0, 0).to_i

  def blocked_behind?(pid)
    DbInspector.one(<<~SQL, [pid])["n"].to_i.positive?
      SELECT count(*) AS n FROM pg_stat_activity WHERE $1::int = ANY (pg_blocking_pids(pid))
    SQL
  end

  def active_grant(org)
    DbInspector.one(<<~SQL, [org])
      SELECT id, state_version, account_id FROM role_assignments
      WHERE organization_id = $1::uuid AND status = 'active' ORDER BY id LIMIT 1
    SQL
  end

  def epoch_of(org)
    DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                    [org])["authorization_epoch"].to_i
  end

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://lockorder.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  def queue(g)
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "lo-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        project_id: g[:project_id], requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  # The two production statements a revocation issues, driven in a CHOSEN order on one connection so
  # the interleaving is deterministic. They are the real store methods, not transcriptions.
  def revocation_steps(conn, org, grant)
    store = IdentityAccess::Infrastructure::RoleAssignmentStore.new(conn)
    epoch = epoch_of(org)
    {
      organizations: -> { store.advance_authorization_epoch(org, epoch, act_now) },
      role_assignments: lambda {
        store.revoke(grant["id"], grant["state_version"].to_i, act_now, REVOCATION_REASON, epoch + 1)
      }
    }
  end

  # Drive the WF-005 command into a genuine mid-flight block against a revocation that has already
  # taken its first row lock, then let the revocation take its second. Returns both outcomes.
  #
  # Nothing is ordered by `Kernel.sleep`: the command is released onto its advisory key only once the
  # revoker holds its first row, and the revoker's second statement is issued only once PostgreSQL
  # reports the command's backend as blocked behind the revoker's.
  def interleave(g, order)
    org = g[:organization_id]
    grant = active_grant(org)
    gate_key = RaceHarness.key_for("crawl-queue:#{org}:#{g[:project_id]}")
    gate = tagged_connection("lock_order_gate")
    revoker = tagged_connection("lock_order_revoker")
    steps = revocation_steps(revoker, org, grant)
    command = nil
    revocation = nil

    begin
      gate.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
      op = RaceHarness.spawn_operation(-> { queue(g) })
      RaceHarness.wait_until("the command blocked on crawl-queue:#{org}:#{g[:project_id]}") do
        RaceHarness.blocked_on(gate_key) >= 1
      end

      revoker.exec("BEGIN")
      revoker.exec("SET lock_timeout = '#{lock_timeout}'")
      steps.fetch(order.first).call

      gate.exec_params("SELECT pg_advisory_unlock_all()")
      RaceHarness.wait_until("the command reached its protected write and blocked behind the revoker") do
        blocked_behind?(pid_of(revoker))
      end

      revocation = begin
        steps.fetch(order.last).call
        revoker.exec("COMMIT")
        :committed
      rescue PG::Error => e
        begin
          revoker.exec("ROLLBACK")
        rescue PG::Error
          nil
        end
        e
      end
      command = op.value
    ensure
      begin
        gate.exec_params("SELECT pg_advisory_unlock_all()")
      rescue PG::Error
        nil
      end
      [gate, revoker].each(&:close)
    end

    { command:, revocation: }
  end

  def deadlock?(value) = value.is_a?(PG::TRDeadlockDetected)

  # A second, non-protected grant for the same Account, so a revocation can be driven without meeting
  # the last-administrator invariant — which is a different rule and not what these proofs are about.
  def revocable_grant(g)
    account = DbInspector.one("SELECT account_id FROM sessions WHERE id = $1::uuid",
                              [g[:session_id]])["account_id"]
    result = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(
      command: Workflows::Wf013::Commands::RequestRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "lo-req-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], account_id: account,
        canonical_role: "MarketingOperator", permission_mode: "standard", persona: nil,
        scope_sha256: Digest::SHA256.digest("scope:organization"), expires_at: nil,
        expected_authorization_epoch: epoch_of(g[:organization_id]), reason: nil,
        requested_at_utc: act_now
      ), request_context: act_ctx
    )
    raise "grant request failed: #{result.reason_code}" unless result.success?

    DbInspector.one(<<~SQL, [g[:organization_id]])
      SELECT id, state_version FROM role_assignments
      WHERE organization_id = $1::uuid AND canonical_role = 'MarketingOperator' AND status = 'active'
    SQL
  end

  include LockOrderProbe

  def revoke_through_handler(g, grant)
    result = Workflows::Wf013::Handlers::RevokeRoleAssignment.new.call(
      command: Workflows::Wf013::Commands::RevokeRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "lo-rv-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id],
        role_assignment_id: grant["id"], expected_state_version: grant["state_version"].to_i,
        expected_authorization_epoch: epoch_of(g[:organization_id]),
        reason: REVOCATION_REASON, requested_at_utc: act_now
      ), request_context: act_ctx
    )
    raise "revocation failed: #{result.reason_code}" unless result.success?
  end

  # THE TIMED EXPIRY, DRIVEN THE ONLY WAY PRODUCTION DRIVES IT — through the ScheduledAction worker.
  # It needs its own Organization because the grant must carry an `expires_at` already in the past, so
  # PostgreSQL considers the timer due; the crawl chain's principal is unrelated to that.
  def expire_through_worker
    granted_at = fixed_now - (30 * 24 * 3600)
    expires_at = granted_at + (24 * 3600)
    admin = TenantSeeder.seed_authorized_admin(issued_at: granted_at - 900)
    target = TenantSeeder.create_account(organization_id: admin[:organization_id],
                                         issuer_key: "https://id.example/oidc",
                                         subject: "lo-target-#{SecureRandom.hex(6)}")
    granted = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(
      command: Workflows::Wf013::Commands::RequestRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "lo-g-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: admin[:session_id], account_id: target,
        canonical_role: "MarketingOperator", permission_mode: "standard", persona: nil,
        scope_sha256: Digest::SHA256.digest("scope:organization"), expires_at:,
        expected_authorization_epoch: epoch_of(admin[:organization_id]), reason: nil,
        requested_at_utc: granted_at
      ), request_context: Platform::RequestContext.for_actor(
        clock: Platform::Clock.fixed(granted_at), ids: Platform::Ids.system,
        correlation_id: SecureRandom.uuid_v7
      )
    )
    raise "grant failed: #{granted.reason_code}" unless granted.success?

    worker = Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(expires_at), ids: Platform::Ids.system
    )
    outcomes = worker.run_due_batch
    raise "expiry did not run: #{outcomes.map(&:disposition).inspect}" unless
      outcomes.map(&:disposition) == [:completed]
  end

  # Every WF-013 handler that can be holding an ACTIVE grant row when a WF-005 protected write asks
  # for it. `DecideRoleAssignment` is not one of them and is proved so at PROOF 262b rather than
  # excused in prose.
  REORDERED_HANDLERS = {
    "RevokeRoleAssignment" => :revoke_first_lock,
    "ExpireRoleAssignment" => :expire_first_lock
  }.freeze

  def revoke_first_lock
    g = bootstrap
    grant = revocable_grant(g)
    measure_first_lock { revoke_through_handler(g, grant) }
  end

  def expire_first_lock
    measure_first_lock { expire_through_worker }
  end

  # Hold one `role_assignments` row `FOR UPDATE` on a second connection and ask whether a real
  # protected write blocks on it. `true` means the statement asked for that row's lock; `false` means
  # its plan filtered the row out before `LockRows`.
  def blocks_on_held_grant?(g, row)
    holder = tagged_connection("lock_order_grant_holder")
    authority = AuthorityFixture.build(organization_id: g[:organization_id],
                                       account_id: DbInspector.one(
                                         "SELECT account_id FROM sessions WHERE id = $1::uuid",
                                         [g[:session_id]]
                                       )["account_id"],
                                       capability: "crawl.trigger", grants: [row])
    begin
      holder.exec("BEGIN")
      holder.exec_params("SELECT 1 FROM role_assignments WHERE id = $1::uuid FOR UPDATE", [row["id"]])
      Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec("SET LOCAL lock_timeout = '#{lock_timeout}'")
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        IdentityAccess::Infrastructure::CrawlStore.new(pg).insert_crawl(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id], authority:, project_id: g[:project_id], kind: "root",
          requested_crawl_policy_id: nil, requested_crawl_policy_version: nil,
          requested_entitlement_policy_id: SecureRandom.uuid_v7,
          requested_entitlement_policy_version: "entitlement-interim-v1",
          trigger_kind: "manual", triggered_by_account_id: nil, idempotency_key_digest: "\x00" * 32
        )
      end
      false
    rescue PG::LockNotAvailable, PG::QueryCanceled, ActiveRecord::LockWaitTimeout, ActiveRecord::StatementInvalid
      true
    ensure
      begin
        holder.exec("ROLLBACK")
      rescue PG::Error
        nil
      end
      holder.close
    end
  end

  def production_write_order(first)
    first == :organizations ? %i[organizations role_assignments] : %i[role_assignments organizations]
  end

  describe "PROOF 262 — the order is read out of each running handler, not written down here" do
    # ROUND 16 FOUND THIS PROOF COVERING ONE HANDLER OF THE THREE THE REPAIR CHANGED, and reverting
    # either of the other two left every proof green while reintroducing a live 40P01 through the
    # timed expiry. That is the defect class this tranche exists to remove — a control proved at one
    # instance and assumed at the others — so the measurement is written once and run at each site.
    REORDERED_HANDLERS.each do |name, driver|
      it "#{name} takes the Organization row before the grant row" do
        first = send(driver)

        expect(first).to eq(:organizations),
                         "#{name} took #{first} first; every WF-005 protected write locks " \
                         "organizations before role_assignments, so this order closes a cycle"
      end
    end

    it "PROOF 262b — DecideRoleAssignment is exempt BY CONSTRUCTION, and the LOCK is what is measured" do
      # WHY IT CANNOT FORM THE CYCLE. Its target is a PENDING Assignment, and every protected write's
      # capability CTE excludes such a row at the scan, strictly below `LockRows`, by TWO independent
      # quals: `ra.status = 'active'`, and `ra.effective_at IS NOT NULL` — which CHECK
      # `role_assignment_pending_is_not_effective` makes NULL for a pending row BY CONSTRUCTION. So the
      # row is filtered out before any lock is asked for, and it takes the removal of BOTH to change
      # that (measured: either alone still excludes it; both together make this example fail). Each
      # limb is separately bound by the battery, so this proof binds the CONSEQUENCE — the row is not
      # locked — rather than restating either qual.
      #
      # THE GRANT'S ROLE MUST BE ONE THE CAPABILITY'S CELL ADMITS (round-18 finding R18-SEC-3). With a
      # `SecurityOperator` grant the capability conjunct excluded the row on its own, so the example
      # passed no matter what the pending-row limbs did. No concurrent protected write can be holding
      # the row this handler is about to write, whatever order it takes.
      #
      # ROUND 17 REJECTED THE FIRST VERSION OF THIS PROOF AND WAS RIGHT TO. It asserted
      # `capability_authorized == false` and called that "the same fact as the row was never locked".
      # It is not: a qual applied ABOVE `LockRows` would take the lock and still yield nothing, so the
      # outcome is consistent with the row having been locked. Worse, the assertion was insensitive to
      # the qual it named — deleting `AND ra.status = 'active'` left it green, because a pending grant
      # has `effective_at IS NULL` and a different limb refused it.
      #
      # SO THE LOCK IS MEASURED DIRECTLY. A second connection holds the pending row `FOR UPDATE`; the
      # protected write must NOT block on it. The control is the same write against an ACTIVE grant,
      # which must block — otherwise this example would pass against a statement that locks nothing.
      g = bootstrap
      account = DbInspector.one("SELECT account_id FROM sessions WHERE id = $1::uuid",
                                [g[:session_id]])["account_id"]
      pending = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(
        command: Workflows::Wf013::Commands::RequestRoleAssignment.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: "lo-p-#{SecureRandom.hex(6)}",
          schema_version: "1.0", session_id: g[:session_id], account_id: account,
          canonical_role: "OrganizationAdmin", permission_mode: "standard", persona: nil,
          scope_sha256: Digest::SHA256.digest("scope:organization"), expires_at: act_now + 86_400,
          expected_authorization_epoch: epoch_of(g[:organization_id]), reason: nil,
          requested_at_utc: act_now
        ), request_context: act_ctx
      )
      raise "protected request failed: #{pending.reason_code}" unless pending.success?

      pending_row = DbInspector.one(<<~SQL, [g[:organization_id]])
        SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
        FROM role_assignments WHERE organization_id = $1::uuid AND status = 'pending'
      SQL
      active_row = DbInspector.one(<<~SQL, [g[:organization_id]])
        SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
        FROM role_assignments WHERE organization_id = $1::uuid AND status = 'active' ORDER BY id LIMIT 1
      SQL
      expect(pending_row).not_to be_nil, "the protected grant did not land pending, so this proof is vacuous"
      expect(active_row).not_to be_nil

      expect(blocks_on_held_grant?(g, pending_row)).to be(false),
                                                      "a protected write BLOCKED on a PENDING grant row, so " \
                                                      "DecideRoleAssignment's target CAN be held by a " \
                                                      "concurrent write and its exemption does not hold"
      expect(blocks_on_held_grant?(g, active_row)).to be(true),
                                                     "the control did not block on an ACTIVE grant either, so " \
                                                     "this example would pass against a statement that locks " \
                                                     "nothing and proves nothing about pending rows"
    end

    it "PROOF 262d — the probe can report the OTHER answer, so a green PROOF 262 is a measurement" do
      # THE CONTROL THE INSTRUMENT ITSELF LACKED (round-17 architecture observation O-1). Blinding the
      # probe's predicate to a constant left every example in this file green — including with BOTH
      # production handlers reverted to the cycle-forming order. A reader that cannot report the wrong
      # answer is not reading anything, and PROOF 262 is only a measurement if this passes.
      #
      # The reversed order is driven through the REAL store methods on one connection, so what the
      # probe observes is a genuine transaction that took the grant row first.
      g = bootstrap
      grant = revocable_grant(g)
      # THE CONNECTION IS CLOSED INSIDE THE MEASURED BLOCK. `measure_first_lock`'s cleanup needs
      # ACCESS EXCLUSIVE on `role_assignments` to drop its trigger, and a second connection still
      # holding that relation — even an already-committed one that has not been closed — deadlocks
      # against it. The probe is an instrument; it must not fight itself.
      first = measure_first_lock do
        conn = tagged_connection("lock_order_reverse")
        begin
          steps = revocation_steps(conn, g[:organization_id], grant)
          conn.exec("BEGIN")
          steps.fetch(:role_assignments).call
          steps.fetch(:organizations).call
          conn.exec("COMMIT")
        ensure
          begin
            conn.exec("ROLLBACK")
          rescue PG::Error
            nil
          end
          conn.close
        end
      end

      expect(first).to eq(:role_assignments),
                       "the probe reported #{first} for a transaction that demonstrably took the grant " \
                       "row first, so it cannot distinguish the two orders and PROOF 262 measures nothing"
    end

    it "PROOF 262c — and DecideRoleAssignment only ever writes a PENDING row, measured at the store" do
      # THE SECOND PREMISE. PROOF 262b establishes that a protected write never locks a pending row;
      # the exemption also needs that this handler never writes a NON-pending one.
      #
      # ROUND 18 REJECTED THE FIRST VERSION AND WAS RIGHT TO. It read the store's SOURCE with
      # `source_location` and asserted the text `status = 'pending'` appeared in it — so deleting the
      # guard from the SQL and leaving the words in a Ruby comment left it green. This tranche's own
      # rule is that no source scan is load-bearing; the guard is now driven.
      g = bootstrap
      grant = revocable_grant(g)
      # ITS OWN CONNECTION, NOT THE INSPECTOR'S. `DbInspector.connection` is the one the probe runs its
      # DDL on; taking row locks on `role_assignments` through it deadlocks against the next
      # `DROP TRIGGER` (round-18: measured, 3 of 10 examples).
      conn = tagged_connection("lock_order_guard_probe")
      store = IdentityAccess::Infrastructure::RoleAssignmentStore.new(conn)
      version = grant["state_version"].to_i

      # The seeded grant is ACTIVE, so both transitions must refuse it: they are for pending rows.
      expect(store.activate(grant["id"], version, act_now, nil, epoch_of(g[:organization_id]) + 1, []).to_i)
        .to eq(0), "RoleAssignmentStore#activate wrote a non-pending row, so DecideRoleAssignment can " \
                   "hold a row a concurrent protected write may also hold"
      expect(store.reject(grant["id"], version, act_now, "no", epoch_of(g[:organization_id])).to_i)
        .to eq(0), "RoleAssignmentStore#reject wrote a non-pending row"
      expect(DbInspector.one("SELECT status FROM role_assignments WHERE id = $1::uuid",
                             [grant["id"]])["status"]).to eq("active")
    ensure
      conn&.close
    end

    it "PROOF 262d — the probe can report the OTHER answer, so a green PROOF 262 is a measurement" do
      # THE CONTROL THE INSTRUMENT ITSELF LACKED (round-17 architecture observation O-1). Blinding the
      # probe's predicate to a constant left every example in this file green — including with BOTH
      # production handlers reverted to the cycle-forming order. A reader that cannot report the wrong
      # answer is not reading anything, and PROOF 262 is only a measurement if this passes.
      #
      # The reversed order is driven through the REAL store methods on one connection, so what the
      # probe observes is a genuine transaction that took the grant row first.
      g = bootstrap
      grant = revocable_grant(g)
      # THE CONNECTION IS CLOSED INSIDE THE MEASURED BLOCK. `measure_first_lock`'s cleanup needs
      # ACCESS EXCLUSIVE on `role_assignments` to drop its trigger, and a second connection still
      # holding that relation — even an already-committed one that has not been closed — deadlocks
      # against it. The probe is an instrument; it must not fight itself.
      first = measure_first_lock do
        conn = tagged_connection("lock_order_reverse")
        begin
          steps = revocation_steps(conn, g[:organization_id], grant)
          conn.exec("BEGIN")
          steps.fetch(:role_assignments).call
          steps.fetch(:organizations).call
          conn.exec("COMMIT")
        ensure
          begin
            conn.exec("ROLLBACK")
          rescue PG::Error
            nil
          end
          conn.close
        end
      end

      expect(first).to eq(:role_assignments),
                       "the probe reported #{first} for a transaction that demonstrably took the grant " \
                       "row first, so it cannot distinguish the two orders and PROOF 262 measures nothing"
    end

    it "PROOF 262c — and DecideRoleAssignment only ever writes a PENDING row, which is the exemption's other half" do
      # THE SECOND PREMISE (round-17 architecture observation O-3). PROOF 262b establishes that a
      # protected write never locks a pending row; the exemption also needs that this handler never
      # writes a NON-pending one. Both of its store methods carry the guard, and widening either
      # silently would end the exemption while 262b stayed green.
      %i[activate reject].each do |method|
        sql = IdentityAccess::Infrastructure::RoleAssignmentStore.instance_method(method).source_location
        body = File.read(sql.first)[/def #{method}\b.*?\n      end/m]
        expect(body).to include("status = 'pending'"),
                        "RoleAssignmentStore##{method} no longer restricts itself to a pending row, so " \
                        "DecideRoleAssignment can hold a row a protected write may also hold"
      end
    end
  end

  describe "PROOF 263 — with that order there is no cycle, and the reverse order proves there could be" do
    it "the observed order lets both sides finish, and the command is refused rather than crashing" do
      # THE ORDER IS THE HANDLER'S, TAKEN FRESH. If a future change puts the grant write first, this
      # example replays THAT and deadlocks, which is the binding PROOF 262 alone cannot provide.
      # ONE Organization for both halves: `identity` is memoized per example, so a second bootstrap
      # in the same example would collide on the principal.
      g = queueable_org
      grant = revocable_grant(g)
      order = production_write_order(measure_first_lock { revoke_through_handler(g, grant) })

      outcome = interleave(g, order)

      expect(deadlock?(outcome[:command])).to be(false),
                                              "the customer's command died with 40P01: #{outcome[:command].inspect}"
      expect(deadlock?(outcome[:revocation])).to be(false),
                                                 "the revocation died with 40P01: #{outcome[:revocation].inspect}"
      expect(outcome[:revocation]).to eq(:committed)
      expect(outcome[:command]).to be_a(Platform::CommandResult)
      expect(outcome[:command].success?).to be(false)
      expect(outcome[:command].reason_code).to eq("crawl_trigger_unauthorized")
      expect(DbInspector.all("SELECT id FROM crawls WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end

    it "PROOF 263b — the SAME interleaving with the two writes reversed deadlocks, so the pass is not vacuous" do
      # THE CONTROL. Without this, a green PROOF 263 would be indistinguishable from an interleaving
      # that never had a cycle available to it. This is the pre-repair order, driven identically.
      g = queueable_org

      outcome = interleave(g, %i[role_assignments organizations])

      expect(deadlock?(outcome[:command]) || deadlock?(outcome[:revocation])).to be(true),
                                                                                "the reversed order did not " \
                                                                                "deadlock, so PROOF 263 proves " \
                                                                                "nothing about lock order: " \
                                                                                "#{outcome.inspect}"
    end
  end

  describe "PROOF 264 — the WF-005 side's half of the order, measured" do
    it "a protected write blocked on role_assignments is already holding the organizations row" do
      # THE PREMISE THE GLOBAL ORDER RESTS ON. The two locks are taken inside ONE statement, so the
      # order is a property of the statement rather than of Ruby. It is measured here — while the
      # command is blocked on the grant row, a third connection cannot take the Organization row —
      # rather than read off the plan.
      g = queueable_org
      org = g[:organization_id]
      grant = active_grant(org)
      gate_key = RaceHarness.key_for("crawl-queue:#{org}:#{g[:project_id]}")
      gate = tagged_connection("lock_order_gate2")
      holder = tagged_connection("lock_order_holder")
      prober = tagged_connection("lock_order_prober")
      held = nil

      begin
        gate.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
        op = RaceHarness.spawn_operation(-> { queue(g) })
        RaceHarness.wait_until("the command blocked on its queue key") { RaceHarness.blocked_on(gate_key) >= 1 }

        # Hold the grant row so the command's statement must stop at its SECOND lock.
        holder.exec("BEGIN")
        holder.exec_params("SELECT 1 FROM role_assignments WHERE id = $1::uuid FOR UPDATE", [grant["id"]])

        gate.exec_params("SELECT pg_advisory_unlock_all()")
        RaceHarness.wait_until("the command blocked behind the grant-row holder") { blocked_behind?(pid_of(holder)) }

        prober.exec("SET lock_timeout = '#{lock_timeout}'")
        held = begin
          prober.exec("BEGIN")
          prober.exec_params("SELECT 1 FROM organizations WHERE id = $1::uuid FOR NO KEY UPDATE", [org])
          prober.exec("COMMIT")
          false
        rescue PG::LockNotAvailable, PG::QueryCanceled
          prober.exec("ROLLBACK")
          true
        end

        holder.exec("ROLLBACK")
        op.value
      ensure
        begin
          gate.exec_params("SELECT pg_advisory_unlock_all()")
        rescue PG::Error
          nil
        end
        [gate, holder, prober].each(&:close)
      end

      expect(held).to be(true),
                      "the command was blocked on role_assignments without holding organizations, so the " \
                      "two halves of the global lock order do not meet and the WF-013 order cannot be " \
                      "derived from this one"
    end
  end
end
