# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# PROOF 264, RUN AT EVERY PROTECTED WRITE INSTEAD OF ONE (FU-57).
#
# WHAT WAS OPEN. The global lock order is `organizations` before `role_assignments`, and the WF-013
# side of it is derived from the WF-005 side holding. PROOF 264 measured the WF-005 side at
# `QueueCrawl` alone, and `blocks_on_held_grant?` drives only `CrawlStore#insert_crawl`. The order at
# `CrawlStartStore#cancel` and `CrawlPolicyStore#activate_version` was ASSUMED — this block's own
# declared defect class, a control proved at one instance and inherited at the others.
#
# WHY ASSUMING IT IS NOT SAFE EVEN THOUGH IT HOLDS. Both locks are taken inside ONE statement, so the
# order is a property of the PLAN rather than of anything Ruby sequences, and in
# `CrawlPolicyStore#activate_version` the two `EXISTS` sit in one CTE where `order_qual_clauses` sorts
# by estimated cost. A row-count change, a new conjunct or an ANALYZE could reorder them with nothing
# to notice. This tranche has just added a conjunct to that very CTE (FU-58), which is exactly the
# kind of change the record warned would move the estimate.
#
# THE SUBJECT IS THE REGISTRY, NOT A LIST OF THREE. `ProtectedWrites::WRITES` is what
# `protected_write_completeness_spec.rb` proves complete against the repository, so a fourth protected
# write is measured here the moment it is registered rather than inheriting this proof by assumption —
# which is the failure mode being repaired.
#
# THE MEASUREMENT IS PROOF 264's, WITH ITS SCAFFOLDING REMOVED. That proof needed an advisory gate to
# get the HANDLER blocked at a known point. Driving the STORE directly, as the battery does, needs
# none: hold the grant row, start the write, wait until it is blocked behind the holder, then ask a
# third connection whether the Organization row is still free. If it is not, the statement was already
# holding it when it stopped at its second lock, which is the order.
RSpec.describe "every protected write holds `organizations` before it blocks on `role_assignments`",
               type: :acceptance, acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
               test_types: %w[TYP-SEC TYP-DATA] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # A METHOD, NOT A TOP-LEVEL CONSTANT. A constant assigned inside `RSpec.describe` lands on
  # `Object`, and `wf005_authority_lock_concurrency_spec.rb` already writes this name — measured,
  # `spec_constant_scope_spec` failed on the collision the moment this file was added.
  def lock_timeout = "2000ms"

  # THE WRITE RUNS ON ITS OWN CONNECTION, NOT ON ONE CHECKED OUT OF THE ActiveRecord POOL.
  #
  # MEASURED, NOT PREFERRED. The first version spawned `Platform::UnitOfWork.run` in a thread. Alone
  # it passed; inside the full acceptance run the `cancel` case timed out, and the diagnostic showed
  # the spawned backend WAS NOT PRESENT IN `pg_stat_activity` AT ALL — the thread was still waiting
  # for a pool connection, so the statement had never reached PostgreSQL and "did not block" meant
  # "did not run". A lock-order measurement that cannot tell those apart measures nothing.
  def with_org_connection(org, name)
    conn = tagged_connection(name)
    conn.exec("BEGIN")
    conn.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, SecureRandom.uuid_v7])
    yield conn
  ensure
    begin
      conn&.exec("COMMIT")
    rescue PG::Error
      nil
    end
    conn&.close
  end

  def tagged_connection(name)
    conn = RaceHarness.open_connection
    conn.exec("SET application_name = '#{name}'")
    conn
  end

  def pid_of(conn) = conn.exec("SELECT pg_backend_pid()").getvalue(0, 0).to_i

  # Every non-idle backend, what it is waiting on, and what it is running — enough to tell "never
  # started" from "blocked somewhere else".
  def cluster_state(holder_pid)
    rows = DbInspector.all(<<~SQL)
      SELECT pid, application_name, state, wait_event_type, wait_event,
             pg_blocking_pids(pid)::text AS blockers, left(query, 90) AS q
      FROM pg_stat_activity WHERE datname = current_database() AND state <> 'idle'
    SQL
    ["holder pid=#{holder_pid}", *rows.map(&:inspect)].join("\n  ")
  end

  def blocked_behind?(pid)
    DbInspector.one(<<~SQL, [pid])["n"].to_i.positive?
      SELECT count(*) AS n FROM pg_stat_activity WHERE $1::int = ANY (pg_blocking_pids(pid))
    SQL
  end

  # ---- the three writes, driven at the store with a chosen authority ------------------------------

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://lockorder.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  # THE VERSION IS READ HERE, ON THE MAIN THREAD, AND THAT IS THE WHOLE OF THE BUG THIS FILE COST.
  #
  # `DbInspector.connection` is ONE process-wide `PG::Connection`, and a `PG::Connection` is not
  # thread-safe. `invoke_cancel` used to read `state_version` through it INSIDE the spawned thread,
  # while the main thread polled `blocked_behind?` through the same connection — so the two
  # interleaved, the thread's read came back nil, the operation died before issuing its statement, and
  # the wait timed out with "did not block". It is timing-dependent, which is why it passed alone and
  # failed inside the full acceptance run, and why ONLY this configuration failed: the other two
  # invokes touch `DbInspector` not at all.
  def setup_cancel
    ctx = running_crawl
    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [ctx[:crawl_id]])["state_version"].to_i
    { org: ctx[:g][:organization_id], session: ctx[:g][:session_id], ctx:, version: }
  end

  def invoke_cancel(pg, env, authority)
    IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
                                                   .cancel(env[:ctx][:crawl_id], env[:version], start_now,
                                                           authority:)
  end

  def setup_queue
    g = queueable_org
    { org: g[:organization_id], session: g[:session_id], project: g[:project_id] }
  end

  def invoke_queue(pg, env, authority)
    IdentityAccess::Infrastructure::CrawlStore.new(pg).insert_crawl(
        id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
        organization_id: env[:org], authority:, project_id: env[:project], kind: "root",
        requested_crawl_policy_id: nil, requested_crawl_policy_version: nil,
        requested_entitlement_policy_id: SecureRandom.uuid_v7,
        requested_entitlement_policy_version: "entitlement-interim-v1",
      trigger_kind: "manual", triggered_by_account_id: nil, idempotency_key_digest: "\x00" * 32
    )
  end

  def setup_policy
    g = bootstrap
    { org: g[:organization_id], session: g[:session_id] }
  end

  def invoke_policy(pg, env, authority)
    IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
        id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
        organization_id: env[:org], authority:, project_id: nil, scope: "organization",
        policy_version: "crawl-policy-organization-v1", supersedes_id: nil,
        expected_state_version: nil, activated_by_account_id: authority.account_id,
      normalized_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING, content_sha256: "\x00" * 32
    )
  end

  # The registry, minus the second policy configuration: this measures the STATEMENT's lock order,
  # and both policy rows are the same statement. `covered` is what the completeness gate proves,
  # so the coverage claim below is against the repository rather than against this list.
  configurations = [
    ["IdentityAccess::Infrastructure::CrawlStartStore#cancel", "crawl.cancel", nil,
     :setup_cancel, :invoke_cancel],
    ["IdentityAccess::Infrastructure::CrawlStore#insert_crawl", "crawl.trigger", nil,
     :setup_queue, :invoke_queue],
    ["IdentityAccess::Infrastructure::CrawlPolicyStore#activate_version", "policy.crawl.manage",
     "OrganizationAdmin", :setup_policy, :invoke_policy]
  ].freeze

  it "measures every DISTINCT protected write the repository has, not a list this file keeps" do
    # If a fourth write is registered and not added here, this fails rather than the file silently
    # measuring three of four — the exact shape FU-57 records at one of three.
    expect(configurations.map(&:first).sort).to eq(ProtectedWrites.covered)
  end

  configurations.each do |identity, capability, required_role, setup, invoke|
    it "#{identity} holds the Organization row while it blocks on the grant" do
      env = send(setup)
      authority = AuthorityFixture.for_session(env[:session], capability:, required_role:)

      # THE HELD ROW IS THE ONE THE STATEMENT RE-READS, not "the organization's first active grant".
      # The capability CTE joins `unnest(...)` against `role_assignments`, so holding a row the
      # carried grant set does not name blocks NOTHING: the write runs straight through, never stops
      # at its second lock, and `wait_until` times out. Measured — the first draft picked by
      # `ORDER BY id LIMIT 1` and timed out inside the full acceptance run while passing alone.
      grant_id = authority.grant_ids.first
      expect(grant_id).not_to be_nil, "the authority carries no grant, so the CTE joins nothing and " \
                                      "this measurement would be about an unblocked statement"
      holder = tagged_connection("lock_order_holder")
      prober = tagged_connection("lock_order_prober")
      held = nil
      op = nil

      begin
        # Hold the grant row so the write's statement must stop at its SECOND lock.
        holder.exec("BEGIN")
        holder.exec_params("SELECT 1 FROM role_assignments WHERE id = $1::uuid FOR UPDATE", [grant_id])

        op = RaceHarness.spawn_operation(lambda {
          with_org_connection(env[:org], "lock_order_write") { |pg| send(invoke, pg, env, authority) }
        })
        begin
          RaceHarness.wait_until("#{identity} blocked behind the grant-row holder") do
            blocked_behind?(pid_of(holder))
          end
        rescue RuntimeError => e
          # WHAT THE WRITE IS ACTUALLY DOING, rather than "it did not block". A statement waiting on
          # a DIFFERENT lock, or one that never started, produces the same timeout and a message that
          # names neither.
          raise "#{e.message}\n#{cluster_state(pid_of(holder))}"
        end

        prober.exec("SET lock_timeout = '#{lock_timeout}'")
        held = begin
          prober.exec("BEGIN")
          prober.exec_params("SELECT 1 FROM organizations WHERE id = $1::uuid FOR NO KEY UPDATE", [env[:org]])
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
          holder.exec("ROLLBACK")
        rescue PG::Error
          nil
        end
        [holder, prober].each(&:close)
      end

      expect(held).to be(true),
                      "#{identity} was blocked on `role_assignments` WITHOUT holding `organizations`, " \
                      "so the two halves of the global lock order do not meet at this write and the " \
                      "WF-013 order cannot be derived from it (FU-57)"
    end
  end
end
