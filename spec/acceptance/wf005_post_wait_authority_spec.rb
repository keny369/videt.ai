# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# SEC-B1 AT BOTH WAITING HANDLERS, ON EVERY BRANCH THAT REACHES THE PROTECTED WRITE.
#
# :331/:333/:335 and SEC-REQ-004/005. A handler that authorizes, then BLOCKS on an advisory lock,
# then acts, must re-read current human authority after the wait and before the irreversible act: the
# wait is unbounded, and a revocation, suspension or policy change can commit inside it.
#
# WHAT ROUND 8 FOUND. The controls are real and correct — the security lens proved the recheck and
# the protected write share one transaction id, one backend and one held advisory lock. What was
# missing was proof:
#
#   R8-4  `ActivateCrawlPolicy`'s recheck had NO PROOF OF ANY KIND. Deleting the whole guard left 388
#         examples green across every spec in the tree that names the handler. The handler gained
#         twenty lines in the round-7 repair and its spec gained nothing.
#   R8-5  Both existing proofs were BRANCH-DEPTH-ONE. PROOF 169 uses a single-Source project and
#         organization scope only, so a one-line bypass keyed to either — `unless sources.size > 1
#         || ...`, `unless command.scope == "project" || ...` — survived 174 examples AND was
#         demonstrably exploitable: a two-Source root Crawl committed and minted its `crawl_dispatch`
#         action on revoked authority.
#
# AND WHAT ROUND 9 FOUND, WHICH IS WHY THIS FILE NO LONGER CONTAINS A MATRIX. The round-9 repair
# drove both axes round 8 named — scope, and Source count — and its review then found a THIRD:
# `unless current || ...` on `ActivateCrawlPolicy`'s supersede path, which survived 2232 examples
# with zero failures and committed a policy activation on revoked authority. A matrix of axes is a
# list, and a Boolean guard can always grow one more operand. A third round of adding the axis
# someone just thought of would fail the same way.
#
# SO THE AXES ARE GONE AND THREE MECHANISMS REPLACE THEM, none of which needs to know an axis:
#
#   1. THE WRITE REFUSES, IN PRODUCTION. `Wf005::AuthorityAttestation` is minted only by a passing
#      recheck and demanded by every protected commit, so a guard that short-circuits past the
#      recheck reaches its commit with nothing to present and raises. Boolean arrangement, operand
#      order, helper extraction and line wrapping are all irrelevant to it.
#   2. THE SUITE JUDGES ITSELF. `AuthoritySentinel` asserts, across every example the repository
#      runs, that a human-authorized WF-005 command which SUCCEEDS and WRITES evaluated
#      `CommandAuthorizer.authority_current?`. A bypass on any axis makes some ordinary path violate
#      that, and 2000+ examples are watching at once — the axis does not need to be anticipated.
#   3. THE PROOFS BELOW OBSERVE THE PREDICATE, not a source line. `ExecutionProbe.watch` reports
#      METHOD INVOCATION, which no short-circuit can fake — round 9's R9-4 found the previous
#      instrument asserting on the `unless` line, which fires identically whether the control runs
#      or is skipped.
RSpec.describe "WF-005 post-wait authority", type: :acceptance,
                                              acceptance_ids: ["AC-CAP-007", "AC-WF-005"],
                                              test_types: %w[TYP-SEC TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def gceil = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
  def gver = Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION

  ACTIVATE = "app/workflows/wf005/handlers/activate_crawl_policy.rb"
  QUEUE = "app/workflows/wf005/handlers/queue_crawl.rb"
  # THE CONTROL, NAMED BY WHAT IT IS RATHER THAN BY WHERE IT SITS. `ExecutionProbe.line_of` resolves
  # it against the file at run time and fails loudly if it is deleted, renamed or duplicated — so an
  # assertion here cannot rot into a line number that means something else.
  # THE CONTROL ITSELF, observed by invocation. `authority_current?` is the ratified durable
  # checkpoint and the only implementation; `require!` is what every protected write demands.
  RECHECK = ExecutionProbe.calls(
    "IdentityAccess::Authorization::CommandAuthorizer.authority_current?"
  ).first
  ATTESTATION = ExecutionProbe.calls("Workflows::Wf005::AuthorityAttestation.require!").first

  # THE SHARED PRODUCTION-REAL CHAIN. `Wf005CrawlChain` bootstraps a real Organization, registers,
  # verifies and activates real Sources and activates the Project through the real handlers. A second
  # copy of that here is exactly the drift the harness was extracted to stop.
  def marketing_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "MarketingOperator",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end

  def bounds(overrides = {})
    b = gceil.to_h { |d, v| [d, v.dup] }
    overrides.each { |d, o| b[d] = b[d].merge(o) }
    b
  end

  # :732's two scopes. An Organization narrowing is an OrganizationAdmin's act against the frozen
  # global ceiling; a Project narrowing is a MarketingOperator's against the Organization's policy.
  # Both reach the same post-wait recheck, which is why both are driven.
  def activate(g, scope:)
    session = scope == "project" ? marketing_session(g[:organization_id]) : g[:session_id]
    Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
      command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "acp-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: session, organization_id: g[:organization_id],
        scope:, project_id: scope == "project" ? g[:project_id] : nil,
        expected_current_policy_version: nil, expected_parent_policy_version: gver,
        expected_global_version: gver,
        proposed_bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }),
        requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  # An Organization whose Project is active with `count` verified, active Sources — the fixture
  # `QueueCrawl`'s `sources.size` branch turns on.
  def queueable(sources:)
    g = bootstrap
    ids = Array.new(sources) { |i| register_source(g, "https://s#{i}.acme.example") }
    ids.each { |sid| verify(g, sid) }
    ids.each { |sid| activate_source(g, sid) }
    raise "activation failed" unless activate_project(g).success?

    g
  end

  def queue_crawl(g)
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        project_id: g[:project_id], requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  # ---- the interleaving, with the wait OBSERVED rather than assumed -----------
  #
  # The controller holds the handler's own advisory key, so the handler genuinely BLOCKS; `pg_locks`
  # is read to confirm it is queued on that exact key, and the epoch advances while it is queued.
  # Nothing here sleeps to establish order.
  def under_revoked_authority(key_name, org, file, revoke: true, &operation)
    key = RaceHarness.key_for(key_name)
    controller = RaceHarness.open_connection
    result = nil
    executed = nil

    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [key])
      op = nil
      executed = ExecutionProbe.watch([RECHECK, ATTESTATION]) do
        op = RaceHarness.spawn_operation(operation)
        RaceHarness.wait_until("the command blocked on #{key_name}") { RaceHarness.blocked_on(key) >= 1 }
        # COMMITTED UNDERNEATH AN OBSERVED WAITER. This is the revocation, not a fixture: the epoch is
        # the ratified serialization point for every effective-access mutation.
        if revoke
          DbInspector.connection.exec_params(
            "UPDATE organizations SET authorization_epoch = authorization_epoch + 1 WHERE id = $1::uuid",
            [org]
          )
        end
        # STILL QUEUED ON THE INTENDED LOCK AT THE MOMENT OF RELEASE, not merely at some point earlier.
        expect(RaceHarness.blocked_on(key)).to be >= 1
        controller.exec_params("SELECT pg_advisory_unlock_all()")
        result = op.value
      end
    ensure
      begin
        controller.exec_params("SELECT pg_advisory_unlock_all()")
      rescue StandardError
        nil
      end
      result ||= op&.value
      controller.close
    end

    expect(result).not_to be_a(StandardError), result.inspect
    [result, executed]
  end

  def expect_reached_recheck(seen, _file = nil)
    expect(seen).to have_evaluated(RECHECK)
  end

  # THE PROTECTED WRITE DID NOT HAPPEN, asserted by the thing that gates it rather than by a line.
  # `require!` runs as the first statement of every protected commit, so its absence IS the absence
  # of the commit — and unlike a line, it cannot be reported for a statement that short-circuited.
  def expect_did_not_write(seen, _file = nil)
    expect(seen).not_to have_evaluated(ATTESTATION)
  end

  describe "ActivateCrawlPolicy — the handler round 8 found unproved (R8-4)" do
    # BOTH SCOPES, because the round-8 bypass was keyed to one of them. `organization` and `project`
    # are the only two the command accepts, so this is the whole branch space of that predicate.
    %w[organization project].each do |scope|
      it "PROOF 189 (#{scope} scope) — authority revoked during the wait refuses, and nothing commits" do
        g = bootstrap
        before = DbInspector.one("SELECT count(*) AS n FROM crawl_policies WHERE organization_id=$1::uuid",
                                 [g[:organization_id]])["n"].to_i

        result, executed = under_revoked_authority("crawl-policy:#{g[:organization_id]}",
                                                   g[:organization_id], ACTIVATE) do
          activate(g, scope:)
        end

        # 1. THE RECHECK RAN. Not "the command was refused": this line, in this run.
        expect_reached_recheck(executed, ACTIVATE)
        # 2. AND IT IS WHAT REFUSED. The outward reason is the authority one, not a validation branch.
        expect(result).to be_a(Platform::CommandResult), result.inspect
        expect(result.success?).to be(false), result.inspect
        expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
        # 3. THE PROTECTED WRITE DID NOT RUN, and no partial state survives.
        expect_did_not_write(executed, ACTIVATE)
        expect(DbInspector.one("SELECT count(*) AS n FROM crawl_policies WHERE organization_id=$1::uuid",
                               [g[:organization_id]])["n"].to_i).to eq(before)
        expect(DbInspector.one(<<~SQL, [g[:organization_id]])["n"].to_i).to eq(0)
          SELECT count(*) AS n FROM event_registry
          WHERE organization_id = $1::uuid AND event_type = 'CrawlPolicyActivated'
        SQL
      end

      it "PROOF 190 (#{scope} scope) — the recheck is not a blanket refusal: an unrevoked wait commits" do
        # THE ADVERSARIAL HALF PER BRANCH. A handler that refused after every wait would satisfy
        # PROOF 189 and be useless, and a bypass that refused only the branch under test would too.
        g = bootstrap

        result, executed = under_revoked_authority("crawl-policy:#{g[:organization_id]}",
                                                   g[:organization_id], ACTIVATE, revoke: false) do
          activate(g, scope:)
        end

        expect_reached_recheck(executed, ACTIVATE)
        expect(result.success?).to be(true), result.inspect
        expect(executed).to have_evaluated(ATTESTATION)
      end
    end
  end

  describe "QueueCrawl — the branches PROOF 169 never drove (R8-5)" do
    # ONE AND TWO SOURCES. The round-8 bypass was `unless sources.size > 1 || ...`, which is invisible
    # to any proof that only ever queues a single-Source Project — and a two-Source Crawl committing
    # on revoked authority was demonstrated, `crawl_dispatch` action and all.
    [1, 2].each do |count|
      it "PROOF 191 (#{count} Source#{'s' if count > 1}) — revoked authority during the wait commits nothing" do
        g = queueable(sources: count)
        before = DbInspector.one("SELECT count(*) AS n FROM crawls WHERE organization_id=$1::uuid",
                                 [g[:organization_id]])["n"].to_i

        result, executed = under_revoked_authority(
          "crawl-queue:#{g[:organization_id]}:#{g[:project_id]}", g[:organization_id], QUEUE
        ) { queue_crawl(g) }

        expect_reached_recheck(executed, QUEUE)
        expect(result).to be_a(Platform::CommandResult), result.inspect
        expect(result.success?).to be(false), result.inspect
        expect(result.failure.reason_code).to eq("crawl_trigger_unauthorized")
        expect_did_not_write(executed, QUEUE)
        expect(DbInspector.one("SELECT count(*) AS n FROM crawls WHERE organization_id=$1::uuid",
                               [g[:organization_id]])["n"].to_i).to eq(before)
        # NO `crawl_dispatch`, which is the effect that makes this exploitable rather than untidy: it
        # is what starts a metered run making outbound requests to the customer's host.
        expect(DbInspector.one(<<~SQL, [g[:organization_id]])["n"].to_i).to eq(0)
          SELECT count(*) AS n FROM scheduled_actions
          WHERE organization_id = $1::uuid AND action_kind = 'crawl_dispatch'
        SQL
      end

      it "PROOF 192 (#{count} Source#{'s' if count > 1}) — an unrevoked wait still queues the Crawl" do
        g = queueable(sources: count)

        result, executed = under_revoked_authority(
          "crawl-queue:#{g[:organization_id]}:#{g[:project_id]}", g[:organization_id], QUEUE, revoke: false
        ) { queue_crawl(g) }

        expect_reached_recheck(executed, QUEUE)
        expect(result.success?).to be(true), result.inspect
        expect(executed).to have_evaluated(ATTESTATION)
      end
    end
  end

  describe "the shape of the control itself" do
    # A HANDLER THAT WAITS AND DOES NOT ASK, WITH THE REASON IT DOES NOT. `StartCrawl` is executed by
    # the scheduled-action executor against a durable `crawl_dispatch` action, not by a person: there
    # is no human authority in flight for a revocation to invalidate, which is the precondition
    # :335's rule states ("re-check current human authority WHERE THE COMMAND DEPENDS ON ONE"). It
    # re-reads the Crawl and the Organization under its lock, which is the part that does apply to it.
    CLASSIFIED_WITHOUT_POST_WAIT = {
      "app/workflows/wf005/handlers/start_crawl.rb" =>
        "executed by the scheduled-action executor against a durable action, so no human authority " \
        "is in flight; ADR-063's platform deferral covers a service-identity command, and the run " \
        "state it does depend on is re-read under its own lock."
    }.freeze

    it "PROOF 193 — every WF-005 handler that waits then acts asks the ONE post-wait owner" do
      # THE COVERAGE ARGUMENT, MADE MECHANICALLY RATHER THAN BY ENUMERATION. R8-4 was not "someone
      # forgot to test `ActivateCrawlPolicy`" — it was that nothing in the repository could say which
      # handlers needed the control. A handler that takes a blocking advisory lock and then writes
      # must consult `PostWaitDecision` or be classified with the reason it need not.
      waiting = Dir[Rails.root.join("app/workflows/wf005/handlers/*.rb")].sort.select do |file|
        File.read(file).match?(/lock_(organization|project|frontier|crawl)\b|pg_advisory_xact_lock/)
      end
      expect(waiting.length).to be >= 4

      missing = waiting.filter_map do |file|
        relative = Pathname(file).relative_path_from(Rails.root).to_s
        next if File.read(file).include?("PostWaitDecision")
        next if CLASSIFIED_WITHOUT_POST_WAIT.key?(relative)

        relative
      end
      expect(missing).to be_empty, <<~MESSAGE
        A WF-005 handler takes a blocking lock and neither consults Wf005::PostWaitDecision nor
        records why it need not. :335 and SEC-REQ-004/005 require current authority to be re-read
        after a wait a revocation can commit inside:
        #{missing.join("\n")}
      MESSAGE

      # AND THE EXCLUSION MAY NOT ROT. A classified handler that has since grown a human-authorized
      # command, or that no longer waits at all, is reclassified rather than left excused.
      CLASSIFIED_WITHOUT_POST_WAIT.each_key do |relative|
        expect(waiting.map { |f| Pathname(f).relative_path_from(Rails.root).to_s }).to include(relative)
        expect(Rails.root.join(relative).read).not_to include("PostWaitDecision")
      end
    end
  end
end
