# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# THE AUTHORITY READ IS LOCK-BASED, AND THE LOCK IS THE RIGHT ONE (D7).
#
# WHAT THE CONCURRENCY LENS FOUND, AND WHY THE FIRST REPAIR DID NOT FIX IT. The lens committed a
# revocation while each guarded statement was observably blocked MID-FLIGHT, and both commands still
# committed: the authority predicate came from the snapshot the statement opened with. The round-two
# repair added `FOR KEY SHARE` to all three authority reads and recorded that this "makes an epoch
# advance conflict with them, so the claim is unconditional rather than conditional on an enumeration
# nobody wrote down".
#
# THAT CLAIM IS FALSE, AND IT IS FALSE FOR A REASON THE REPAIR COULD HAVE CHECKED. `authorization_epoch`
# belongs to no key, so advancing it is a NON-KEY update, and a non-key update takes `FOR NO KEY
# UPDATE` — which DOES NOT CONFLICT with `FOR KEY SHARE`. The repair restated the very premise it was
# written to remove, and nothing in the suite could tell, because nothing measured the conflict.
#
# SO THIS FILE MEASURES IT, on the real `organizations` row and with the real revocation statement,
# and then drives each guarded statement into a genuine mid-flight block and shows that a revocation
# CANNOT land inside the window. Nothing here enumerates who else might hold a lock: the property is
# demonstrated as behaviour, and the causal edge — this revocation is waiting on THIS command — is
# read out of `pg_blocking_pids` rather than argued.
RSpec.describe "WF-005 authority lock strength", type: :acceptance,
                                                  acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
                                                  test_types: %w[TYP-SEC TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  REVOKE_SQL = "UPDATE organizations SET authorization_epoch = authorization_epoch + 1 WHERE id = $1::uuid"
  # Long enough that a genuinely free lock is always taken, short enough that a genuinely held one
  # reports rather than hangs. The suite's own bound on unbounded waits.
  LOCK_TIMEOUT = "2000ms"

  def tagged_connection(name)
    conn = RaceHarness.open_connection
    conn.exec("SET application_name = '#{name}'")
    conn
  end

  def pid_of(conn) = conn.exec("SELECT pg_backend_pid()").getvalue(0, 0).to_i

  # Attempt the revocation with a bounded wait. `:committed` means it landed; `:blocked` means the
  # reader's lock conflicts with it, which is the property under test.
  def attempt_revocation(org)
    revoker = tagged_connection("d7_revoker")
    begin
      revoker.exec("BEGIN")
      revoker.exec("SET lock_timeout = '#{LOCK_TIMEOUT}'")
      begin
        revoker.exec_params(REVOKE_SQL, [org])
        revoker.exec("COMMIT")
        :committed
      rescue PG::LockNotAvailable, PG::QueryCanceled
        revoker.exec("ROLLBACK")
        :blocked
      end
    ensure
      revoker.close
    end
  end

  # ---- the lock matrix, on the real row and the real statement -----------------

  describe "PROOF 239 — which reader lock actually conflicts with a revocation" do
    # THE MEASUREMENT THE ROUND-TWO REPAIR DID NOT MAKE. If this had existed, `FOR KEY SHARE` would
    # never have been written down as the fix.
    %w[KEY\ SHARE SHARE UPDATE].each do |strength|
      it "a reader holding FOR #{strength} #{strength == 'KEY SHARE' ? 'does NOT block' : 'BLOCKS'} the epoch advance" do
        g = bootstrap
        reader = tagged_connection("d7_reader")
        begin
          reader.exec("BEGIN")
          reader.exec_params("SELECT 1 FROM organizations WHERE id = $1::uuid FOR #{strength}",
                             [g[:organization_id]])

          outcome = attempt_revocation(g[:organization_id])

          if strength == "KEY SHARE"
            expect(outcome).to eq(:committed),
                               "FOR KEY SHARE blocked the epoch advance, so the D7 finding is wrong and " \
                               "the round-two repair was sound after all"
          else
            expect(outcome).to eq(:blocked),
                               "FOR #{strength} did not conflict with the epoch advance; the authority " \
                               "read cannot be made lock-based with it"
          end
        ensure
          reader.exec("ROLLBACK")
          reader.close
        end
      end
    end

    it "and two concurrent FOR SHARE readers do NOT block each other" do
      # WHY `FOR SHARE` AND NOT `FOR UPDATE`. The authority read runs in every human-authorized WF-005
      # command; a strength that serialized them would turn one Organization's commands into a queue.
      # `FOR SHARE` conflicts with the revocation and not with a second authorized command.
      g = bootstrap
      first = tagged_connection("d7_reader_a")
      second = tagged_connection("d7_reader_b")
      begin
        first.exec("BEGIN")
        first.exec_params("SELECT 1 FROM organizations WHERE id = $1::uuid FOR SHARE", [g[:organization_id]])
        second.exec("BEGIN")
        second.exec("SET lock_timeout = '#{LOCK_TIMEOUT}'")
        outcome = begin
          second.exec_params("SELECT 1 FROM organizations WHERE id = $1::uuid FOR SHARE", [g[:organization_id]])
          :proceeded
        rescue PG::LockNotAvailable, PG::QueryCanceled
          :blocked
        end

        expect(outcome).to eq(:proceeded), "two authorized commands serialized against each other"
      ensure
        [first, second].each do |c|
          begin
            c.exec("ROLLBACK")
          rescue StandardError
            nil
          end
          c.close
        end
      end
    end
  end

  # ---- each guarded statement, blocked mid-flight ------------------------------

  describe "a revocation committed while the guarded statement is blocked mid-flight" do
    # THE INTERLEAVING, WITH THE BLOCK OBSERVED RATHER THAN ASSUMED. A blocker transaction takes a row
    # lock on the row the guarded statement is about to write. The statement therefore evaluates its
    # authority CTEs — taking `FOR SHARE` on the Organization — and then BLOCKS inside itself on that
    # row. The revocation is attempted at exactly that moment.
    #
    # NOTHING SLEEPS TO ESTABLISH ORDER. The harness polls `pg_blocking_pids` until the command's own
    # backend is observably waiting behind the blocker, and the revocation is attempted only then.
    def under_midflight_block(org:, blocker_sql:, blocker_params:, &operation)
      blocker = tagged_connection("d7_blocker")
      blocker.exec("BEGIN")
      blocker.exec_params(blocker_sql, blocker_params)
      blocker_pid = pid_of(blocker)
      result = nil
      revocation = nil
      op = nil

      begin
        op = RaceHarness.spawn_operation(operation)
        RaceHarness.wait_until("the guarded statement blocked behind #{blocker_pid}") do
          waiters_behind(blocker_pid).positive?
        end
        # STILL BLOCKED AT THE MOMENT THE REVOCATION IS ATTEMPTED, not merely at some point earlier.
        expect(waiters_behind(blocker_pid)).to be >= 1
        revocation = attempt_revocation(org)
      ensure
        begin
          blocker.exec("ROLLBACK")
        rescue StandardError
          nil
        end
        blocker.close
        result = op&.value
      end

      raise result if result.is_a?(StandardError)

      [result, revocation]
    end

    def waiters_behind(pid)
      RaceHarness.observer.exec_params(<<~SQL, [pid]).getvalue(0, 0).to_i
        SELECT count(*) FROM pg_locks l
        JOIN pg_stat_activity a ON a.pid = l.pid
        WHERE NOT l.granted AND a.datname = current_database()
          AND $1::int = ANY (pg_blocking_pids(l.pid))
      SQL
    end

    def epoch_of(org)
      DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                      [org])["authorization_epoch"].to_i
    end

    it "PROOF 240 — cannot land while the CANCELLATION write is blocked, and the run is cancelled once" do
      ctx = running_crawl
      org = ctx[:g][:organization_id]
      before = epoch_of(org)
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i
      authority = AuthorityFixture.for_session(ctx[:g][:session_id], capability: "crawl.cancel")

      outcome, revocation = under_midflight_block(
        org:, blocker_sql: "SELECT id FROM crawls WHERE id = $1::uuid FOR UPDATE",
        blocker_params: [ctx[:crawl_id]]
      ) do
        Platform::UnitOfWork.run do |conn|
          pg = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
          store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
          store.cancel(ctx[:crawl_id], version, start_now, authority:)
        end
      end

      expect(revocation).to eq(:blocked),
                            "the revocation committed while the guarded statement was in flight; the " \
                            "authority read is not lock-based and the write can be authorised by a " \
                            "predicate that is already stale"
      expect(epoch_of(org)).to eq(before), "the epoch moved inside the window"
      expect(outcome[:authorized]).to be(true)
      expect(outcome[:moved]).to eq(1)
      expect(DbInspector.one("SELECT state FROM crawls WHERE id = $1::uuid",
                             [ctx[:crawl_id]])["state"]).to eq("canceled")
    end

    it "PROOF 241 — cannot land while the QUEUE insert is blocked on its foreign-key check" do
      # The queue INSERT waits on the `projects` foreign-key check, which is the block the D6 comment
      # named as the reason a lock clause is needed at all.
      g = queueable_org
      org = g[:organization_id]
      before = epoch_of(org)
      authority = AuthorityFixture.for_session(g[:session_id], capability: "crawl.trigger")

      outcome, revocation = under_midflight_block(
        org:, blocker_sql: "SELECT id FROM projects WHERE id = $1::uuid FOR UPDATE",
        blocker_params: [g[:project_id]]
      ) do
        Platform::UnitOfWork.run do |conn|
          pg = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlStore.new(pg)
          pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, SecureRandom.uuid_v7])
          store.insert_crawl(
            id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
            organization_id: org, authority:, project_id: g[:project_id], kind: "root",
            requested_crawl_policy_id: nil, requested_crawl_policy_version: nil,
            requested_entitlement_policy_id: SecureRandom.uuid_v7,
            requested_entitlement_policy_version: "entitlement-interim-v1",
            trigger_kind: "manual", triggered_by_account_id: nil, idempotency_key_digest: "\x00" * 32
          )
        end
      end

      expect(revocation).to eq(:blocked)
      expect(epoch_of(org)).to eq(before)
      expect(outcome[:authorized]).to be(true)
      expect(outcome[:inserted]).to eq(1)
    end

    it "PROOF 242 — cannot land while the POLICY activation is blocked on the row it supersedes" do
      g = bootstrap
      org = g[:organization_id]
      expect(activate_policy(g).success?).to be(true)
      current = DbInspector.one("SELECT id, state_version FROM crawl_policies " \
                                "WHERE organization_id = $1::uuid AND state = 'active'", [org])
      before = epoch_of(org)
      authority = AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage")

      outcome, revocation = under_midflight_block(
        org:, blocker_sql: "SELECT id FROM crawl_policies WHERE id = $1::uuid FOR UPDATE",
        blocker_params: [current["id"]]
      ) do
        Platform::UnitOfWork.run do |conn|
          pg = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg)
          pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, SecureRandom.uuid_v7])
          store.activate_version(
            id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
            organization_id: org, authority:, project_id: nil, scope: "organization",
            policy_version: "crawl-policy-organization-v2", supersedes_id: current["id"],
            expected_state_version: current["state_version"].to_i,
            activated_by_account_id: authority.account_id,
            normalized_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING, content_sha256: "\x00" * 32
          )
        end
      end

      expect(revocation).to eq(:blocked)
      expect(epoch_of(org)).to eq(before)
      expect(outcome[:authorized]).to be(true)
      expect(outcome[:superseded]).to eq(1)
      expect(outcome[:inserted]).to eq(1)
    end
  end

  # ---- helpers ---------------------------------------------------------------

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://d7.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  def activate_policy(g)
    ceiling = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
    bounds = ceiling.to_h { |d, v| [d, v.dup] }
    bounds["accepted_pages"] = bounds["accepted_pages"].merge("soft" => 5_000, "hard" => 6_000)
    Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
      command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "acp-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        scope: "organization", project_id: nil, expected_current_policy_version: nil,
        expected_parent_policy_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
        expected_global_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
        proposed_bounds: bounds, requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end
end
