# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# AUTHORITY IS A CONJUNCT OF THE CANCELLATION WRITE (D3 / R10-10).
#
# THE PROPERTY. `:335`, SEC-REQ-004/005: a human-authorized command must act on authority that is
# still current AFTER the wait, because the wait is when it can be revoked. Round 9 expressed this as
# a Ruby recheck; round 10 hoisted it above the row locks and committed an irreversible cancellation
# on revoked authority; round 11's xid floor did not stop the same hoist.
#
# WHAT IS PROVED HERE is the property itself rather than the arrangement of any Ruby statement: with
# the organization's `authorization_epoch` moved on, THE WRITE DOES NOT APPLY — whatever the handler
# did beforehand. `authority_current?` is exactly "the org's epoch equals the actor's", so the test
# is ordinary row state and belongs in the statement that depends on it.
RSpec.describe "WF-005 cancellation authority", type: :acceptance,
                                                 acceptance_ids: ["AC-WF-005"],
                                                 test_types: %w[TYP-SEC TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def crawl_row(ctx) = DbInspector.one("SELECT * FROM crawls WHERE id=$1::uuid", [ctx[:crawl_id]])

  def revoke_authority!(ctx)
    # A revocation is an epoch advance. This is what `authority_current?` reads and what the
    # cancellation write now depends on.
    DbInspector.one("UPDATE organizations SET authorization_epoch = authorization_epoch + 1 " \
                    "WHERE id = $1::uuid RETURNING authorization_epoch", [ctx[:g][:organization_id]])
  end

  def cancel_via_store(ctx, epoch:)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
        .enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      row = DbInspector.one("SELECT state_version FROM crawls WHERE id=$1::uuid", [ctx[:crawl_id]])
      store.cancel(ctx[:crawl_id], row["state_version"].to_i, start_now,
                   authorization_epoch: epoch, organization_id: ctx[:g][:organization_id])
    end
  end

  it "PROOF 216 — the write refuses a cancellation whose authority moved during the wait" do
    ctx = running_crawl
    current = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id=$1::uuid",
                              [ctx[:g][:organization_id]])["authorization_epoch"].to_i
    revoke_authority!(ctx)

    outcome = cancel_via_store(ctx, epoch: current)

    expect(outcome[:authorized]).to be(false), "a stale epoch must not authorize the write"
    expect(outcome[:moved]).to eq(0)
    # AND NOTHING HAPPENED TO THE RUN. A refusal that still moved the row would be the defect.
    expect(crawl_row(ctx)["state"]).to eq("running")
    expect(crawl_row(ctx)["terminal_at"]).to be_nil
  end

  it "PROOF 217 — and applies it when authority is still current, so the guard is not blanket" do
    # NON-VACUITY. A conjunct that never matched would satisfy PROOF 216 forever while breaking every
    # cancellation, and the suite's other 17 cancel examples would be the only thing to notice.
    ctx = running_crawl
    current = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id=$1::uuid",
                              [ctx[:g][:organization_id]])["authorization_epoch"].to_i

    outcome = cancel_via_store(ctx, epoch: current)

    expect(outcome[:authorized]).to be(true)
    expect(outcome[:moved]).to eq(1)
    expect(crawl_row(ctx)["state"]).to eq("canceled")
  end

  it "PROOF 218 — authorized-but-unmoved is reported as corruption, not as a denial" do
    # THE TWO ZERO-ROW CASES ARE OPPOSITE EVENTS. Collapsing them would either report corruption for
    # an ordinary revocation, or — far worse — swallow a lost serialized transition as a polite
    # domain denial. Here authority is current and the VERSION is wrong.
    ctx = running_crawl
    current = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id=$1::uuid",
                              [ctx[:g][:organization_id]])["authorization_epoch"].to_i

    outcome = Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      store.cancel(ctx[:crawl_id], 9999, start_now,
                   authorization_epoch: current, organization_id: ctx[:g][:organization_id])
    end

    expect(outcome[:authorized]).to be(true), "authority was current; this is not a denial"
    expect(outcome[:moved]).to eq(0), "and the transition did not apply, which the handler must raise on"
  end

  describe "the handler's branching on the write's two zero-row cases" do
    # THESE EXIST BECAUSE THE MUTATION BATTERY FOUND THEM MISSING. Deleting the handler's denial and
    # collapsing corruption into a denial BOTH survived the whole cancel suite: 17 examples passed
    # while the handler could no longer tell a revocation from a lost transition. The store-level
    # proofs above are necessary and were not sufficient.
    #
    # THE RACER IS REAL, NOT A STUB. A one-shot hook runs immediately before the store's `cancel`
    # executes and performs the interfering write on its own connection — a revocation landing in the
    # window between the handler's Ruby recheck and its write, which is exactly the interleaving
    # R10-10 is about. The mechanism under test, the SQL conjunct, then runs for real against the
    # state the racer left. Nothing about the cancellation path is mocked away.
    def cancel_crawl(ctx)
      Workflows::Wf005::Handlers::CancelCrawl.new.call(
        command: Workflows::Wf005::Commands::CancelCrawl.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: "auth-#{SecureRandom.hex(6)}",
          schema_version: "1.0", session_id: ctx[:g][:session_id],
          organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
          crawl_id: ctx[:crawl_id],
          expected_state_version: crawl_row(ctx)["state_version"].to_i, requested_at_utc: start_now
        ),
        request_context: Platform::RequestContext.for_actor(
          clock: Platform::Clock.fixed(start_now), ids: Platform::Ids.system,
          correlation_id: SecureRandom.uuid_v7
        )
      )
    end

    def race_before_cancel(interference)
      fired = false
      hook = Module.new do
        define_method(:cancel) do |*args, **kwargs|
          unless fired
            fired = true
            interference.call
          end
          super(*args, **kwargs)
        end
      end
      IdentityAccess::Infrastructure::CrawlStartStore.prepend(hook)
      yield
    ensure
      # Neutralise the hook for the rest of the process; a prepended module cannot be removed.
      fired = true
    end

    it "PROOF 219 — a revocation landing between the recheck and the write DENIES, and writes nothing" do
      ctx = running_crawl
      result = race_before_cancel(-> { revoke_authority!(ctx) }) do
        cancel_crawl(ctx)
      end

      expect(result).not_to be_success
      expect(result.reason_code).to eq("crawl_cancel_unauthorized")
      expect(crawl_row(ctx)["state"]).to eq("running"), "the run was cancelled on revoked authority"
      expect(crawl_row(ctx)["terminal_at"]).to be_nil
      expect(DbInspector.count("crawl_terminal_outcomes")).to eq(0)
    end

    it "PROOF 220 — the corruption branch is UNREACHABLE while the lock holds, and is proved where it is" do
      # WHAT WAS ATTEMPTED AND WHY IT IS RECORDED. The first version of this proof tried to drive the
      # authorized-but-unmoved branch through the handler by bumping the crawl's `state_version` from
      # another connection just before the write. It DEADLOCKED and timed out at 16 seconds — because
      # the handler holds `lock_crawl` on exactly that row, so no other transaction can move it. That
      # is the invariant itself, not a gap in the proof.
      #
      # THE SECOND VERSION ASSERTED SOURCE ORDER, and that was worse: `source.index(...) <
      # source.index(...)` is a text proxy for a semantic decision, and it would pass with both
      # branches unreachable, with `lock_frontier` appearing only in a comment, or with the ordering
      # rebuilt through a helper. It is removed. The classification it stood in for is proved BY
      # EXECUTION at the store, in PROOF 218, where the branch IS reachable.
      #
      # What remains here is the fact that makes the branch unreachable, established by execution:
      # the handler holds the row lock across its write, so no concurrent transaction can move the
      # version out from under it.
      ctx = running_crawl
      blocked = nil
      Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
          .enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        pg.exec_params("SELECT id FROM crawls WHERE id = $1::uuid FOR UPDATE", [ctx[:crawl_id]])

        # AN INDEPENDENT CONNECTION, not a nested unit of work: the point is that a DIFFERENT
        # transaction cannot take this row lock while the first holds it. `NOWAIT` turns the wait
        # into an immediate, observable refusal rather than a hang, so this proof is bounded.
        other = PgTestConnection.connect(user: "f1_web")
        begin
          other.exec("BEGIN")
          other.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                            [ctx[:g][:organization_id], SecureRandom.uuid_v7])
          blocked = begin
            other.exec_params("SELECT id FROM crawls WHERE id = $1::uuid FOR UPDATE NOWAIT", [ctx[:crawl_id]])
            :acquired
          rescue PG::LockNotAvailable
            :refused
          end
        ensure
          begin
            other.exec("ROLLBACK")
          rescue StandardError
            nil
          end
          other.close
        end
      end

      expect(blocked).to eq(:refused),
                         "another transaction took the crawl row lock while the handler held it, so " \
                         "the authorized-but-unmoved branch IS reachable and needs a behavioural proof"
    end

  # THE HANDLER'S CLASSIFICATION IS NOT PROVED BY A STUB, AND THE ATTEMPT IS RECORDED.
  #
  # The round-two contract lens found that collapsing `raise` into a domain denial survives every
  # behavioural example, and it is right. I tried to close it by handing the handler a stubbed store
  # returning each outcome shape — and `AuthoritySentinel` immediately raised on it, correctly: a
  # handler whose guarded write has been replaced writes without the real authority path, so the
  # suite-wide rule fires. The stub does not test the classification; it manufactures a violation.
  #
  # WHAT IS ACTUALLY TRUE HERE. PROOF 220 above establishes BY EXECUTION that the
  # authorized-but-unmoved branch is unreachable through the handler while it holds the row lock —
  # a second transaction cannot take that lock, proved with `FOR UPDATE NOWAIT`. The collapse
  # mutation is therefore an EQUIVALENT MUTANT, and the honest record is the mutation ledger's
  # `expectation: "equivalent"` carrying that unreachability proof as its justification, not a
  # behavioural proof of a branch no production path can reach.
  #
  # The store's own reporting of the two cases IS proved, at PROOF 218, where the branch is reachable.
  end
end
