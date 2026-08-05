# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# THE CAPABILITY AXIS IS ENFORCED AT THE WRITE (FU-48, taken in D7).
#
# WHAT WAS OPEN. Until D7 the only authority a protected write evaluated for itself was the
# Organization's `authorization_epoch`, and `QueueCrawl`'s own comment said what that leaves out: the
# epoch conjunct "detects a CHANGE in authority since authentication. It does not detect the ABSENCE
# of a capability: `decision.allowed?` above is the only thing that refuses an actor who never held
# `crawl.trigger`, and deleting it lets such an actor queue a Crawl that this write will happily
# insert." One Ruby branch stood between an unauthorised actor and an irreversible transition, and
# the tranche's headline mechanism could not see it, because the mechanism only watches whether
# authority was RE-READ.
#
# WHAT THE OWNER DECIDED. The capability/scope axis must have a write-level counterpart and must be
# observable by the same proof system.
#
# WHAT THE COUNTERPART IS. The write carries the GRANTS the decision relied on —
# `Decision#granting_assignments` — and PostgreSQL re-reads them in the same statement as the
# transition, under `FOR SHARE`: active, effective, unexpired, at the state version and scope digest
# the decision saw. An actor who never held the capability has no granting Assignment, so the array
# is empty and the predicate is false.
#
# WHAT IT IS NOT, STATED SO NOBODY LATER READS MORE INTO IT. This does NOT implement Assignment-scope
# CONTAINMENT against the target. That is FU-2, a PRE-EXISTING platform-wide deferral recorded in
# DECISIONS.md for every resource capability and not an S-07-009 question; inventing it here would be
# new authorization semantics under a repair. The scope digest is BOUND, so a write refuses when the
# grant's scope is not the one the decision evaluated, and the containment predicate has an obvious
# home the day FU-2 is taken.
RSpec.describe "WF-005 write-level capability authority", type: :acceptance,
                                                          acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
                                                          test_types: %w[TYP-SEC TYP-DATA] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def cancel_with(ctx, authority)
    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [ctx[:crawl_id]])["state_version"].to_i
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      store.cancel(ctx[:crawl_id], version, start_now, authority:)
    end
  end

  def authority_for(ctx, **overrides)
    AuthorityFixture.for_session(ctx[:g][:session_id], capability: "crawl.cancel", **overrides)
  end

  def crawl_state(ctx)
    DbInspector.one("SELECT state FROM crawls WHERE id = $1::uuid", [ctx[:crawl_id]])["state"]
  end

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://cap.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  describe "the grant the decision relied on is re-read by the write" do
    it "PROOF 243 — an actor carrying NO granting Assignment cannot move the run" do
      # THE AXIS FU-48 IS ABOUT. This is what a deleted `decision.allowed?` produces: a caller reaching
      # the write with an allowed-looking epoch and no capability behind it. Before D7 the write
      # inserted happily.
      ctx = running_crawl

      outcome = cancel_with(ctx, authority_for(ctx, grants: []))

      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:authorized]).to be(false)
      expect(outcome[:moved]).to eq(0)
      expect(crawl_state(ctx)).to eq("running")
    end

    it "PROOF 244 — a grant REVOKED between the decision and the write cannot move the run" do
      ctx = running_crawl
      authority = authority_for(ctx)
      DbInspector.one(<<~SQL, [ctx[:g][:organization_id]])
        UPDATE role_assignments SET status = 'revoked', state_version = state_version + 1,
               updated_at = now(), terminated_at = now(),
               transition_reason_code = 'role_assignment_revoked'
        WHERE organization_id = $1::uuid AND status = 'active' RETURNING id
      SQL

      outcome = cancel_with(ctx, authority)

      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:moved]).to eq(0)
      expect(crawl_state(ctx)).to eq("running")
    end

    it "PROOF 244b — a grant that is no longer ACTIVE cannot move the run, version held" do
      # WHY THIS IS SEPARATE FROM PROOF 244. Production advances `state_version` when it revokes, so
      # PROOF 244's revocation is refused by the VERSION binding and says nothing about the status
      # predicate — measured: deleting `AND ra.status = 'active'` SURVIVED it. The status is set here
      # with the version HELD, so the only thing that can refuse the write is the predicate under test.
      ctx = running_crawl
      authority = authority_for(ctx)
      DbInspector.one(<<~SQL, [ctx[:g][:organization_id]])
        UPDATE role_assignments SET status = 'revoked', terminated_at = now(),
               transition_reason_code = 'role_assignment_revoked'
        WHERE organization_id = $1::uuid AND status = 'active' RETURNING id
      SQL

      outcome = cancel_with(ctx, authority)

      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:moved]).to eq(0)
      expect(crawl_state(ctx)).to eq("running")
    end

    it "PROOF 245 — a grant whose STATE VERSION has moved cannot move the run" do
      # The decision named a version of the Assignment. Anything that changes the Assignment advances
      # it, so the write refuses a decision taken against a grant that is no longer that grant.
      ctx = running_crawl
      authority = authority_for(ctx)
      stale = IdentityAccess::Authorization::WriteAuthority.new(
        **authority.to_h.merge(grant_versions: authority.grant_versions.map { |v| v + 1 })
      )

      outcome = cancel_with(ctx, stale)

      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:moved]).to eq(0)
    end

    it "PROOF 246 — a grant whose SCOPE is not the one the decision evaluated cannot move the run" do
      # FU-2 leaves scope CONTAINMENT unimplemented platform-wide; what this proves is the axis being
      # BOUND at the write, which is what FU-48 asked for and what containment will attach to.
      ctx = running_crawl
      authority = authority_for(ctx)
      elsewhere = IdentityAccess::Authorization::WriteAuthority.new(
        **authority.to_h.merge(grant_scopes: authority.grant_scopes.map { "f" * 64 })
      )

      outcome = cancel_with(ctx, elsewhere)

      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:moved]).to eq(0)
    end

    it "PROOF 247 — the two authority limbs are reported SEPARATELY, because they are different events" do
      # A capability that was never held and an authority that moved are different facts about the
      # caller. Collapsing them would make one indistinguishable from the other in the ledger, and
      # would make either limb's removal invisible to the other's proof.
      ctx = running_crawl

      capability_gone = cancel_with(ctx, authority_for(ctx, grants: []))
      expect(capability_gone[:epoch_authorized]).to be(true), "the epoch was current; only capability failed"
      expect(capability_gone[:capability_authorized]).to be(false)

      epoch_moved = cancel_with(ctx, authority_for(ctx, epoch: -1))
      expect(epoch_moved[:epoch_authorized]).to be(false)
      expect(epoch_moved[:capability_authorized]).to be(true), "the grant was intact; only the epoch moved"
    end

    it "PROOF 248 — and with both limbs current the write APPLIES, so neither is a blanket refusal" do
      # NON-VACUITY. A conjunct that never matched would satisfy every proof above forever while
      # breaking every cancellation in the product.
      ctx = running_crawl

      outcome = cancel_with(ctx, authority_for(ctx))

      expect(outcome[:epoch_authorized]).to be(true)
      expect(outcome[:capability_authorized]).to be(true)
      expect(outcome[:authorized]).to be(true)
      expect(outcome[:moved]).to eq(1)
      expect(crawl_state(ctx)).to eq("canceled")
    end
  end

  describe "the SCOPE rule is a predicate of the write, not a Ruby operand" do
    # THE AXIS THE ROUND-TWO SECURITY LENS DEMONSTRATED. `:732`/`:738` bind a crawl-policy scope to a
    # canonical role — Organization scope to OrganizationAdmin, Project scope to MarketingOperator —
    # and `authorized_for_scope?` was the ONLY place that said so. Removing its single operand let a
    # MarketingOperator commit an ORGANIZATION-scope policy, surviving 2364 examples but for two
    # hand-written ones. That is this tranche's own standard applied to a different axis: a
    # completeness mechanism whose only enumeration is the set of examples someone remembered to write.
    #
    # The role the SCOPE demands is now derived from the scope and carried into the statement, so the
    # write refuses a grant that does not hold it WHATEVER the Ruby predicate does.
    it "PROOF 258 — a MarketingOperator grant cannot activate an ORGANIZATION-scope policy" do
      g = bootstrap
      marketing = TenantSeeder.seed_authorized_admin(
        organization_id: g[:organization_id], canonical_role: "MarketingOperator",
        with_policy: false, issued_at: fixed_now - 300
      )
      authority = AuthorityFixture.for_session(
        marketing[:session_id], capability: "policy.crawl.manage",
        required_role: Workflows::Wf005::Handlers::ActivateCrawlPolicy::SCOPE_ROLE.fetch("organization")
      )
      expect(authority.grant_ids).not_to be_empty, "the fixture confers nothing, so this proves nothing"

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id], authority:, project_id: nil, scope: "organization",
          policy_version: "crawl-policy-organization-v1", supersedes_id: nil,
          expected_state_version: nil, activated_by_account_id: authority.account_id,
          normalized_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING, content_sha256: "\x00" * 32
        )
      end

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the scope rule failed"
      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:inserted]).to eq(0)
      expect(DbInspector.all("SELECT id FROM crawl_policies WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end

    it "PROOF 258b — and the OrganizationAdmin grant the scope DOES demand activates it" do
      # NON-VACUITY. A predicate that refused every role would satisfy PROOF 258 forever while
      # breaking every activation in the product.
      g = bootstrap
      authority = AuthorityFixture.for_session(
        g[:session_id], capability: "policy.crawl.manage",
        required_role: Workflows::Wf005::Handlers::ActivateCrawlPolicy::SCOPE_ROLE.fetch("organization")
      )

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id], authority:, project_id: nil, scope: "organization",
          policy_version: "crawl-policy-organization-v1", supersedes_id: nil,
          expected_state_version: nil, activated_by_account_id: authority.account_id,
          normalized_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING, content_sha256: "\x00" * 32
        )
      end

      expect(outcome[:capability_authorized]).to be(true)
      expect(outcome[:inserted]).to eq(1)
    end

    it "PROOF 258c — the Ruby guard and the write read ONE transcription of the rule" do
      # A rule stated twice is a rule that drifts. `authorized_for_scope?` and the value handed to the
      # write both read `SCOPE_ROLE`, so they cannot disagree about what a scope demands.
      roles = Workflows::Wf005::Handlers::ActivateCrawlPolicy::SCOPE_ROLE
      expect(roles).to eq({ "organization" => "OrganizationAdmin", "project" => "MarketingOperator" })
      expect(roles).to be_frozen
    end
  end

  describe "the same limb, at the other two protected writes" do
    # THE INVARIANT BELONGS TO EACH WRITE, so it is proved at each write rather than at the one
    # handler a spec happens to drive. `CrawlStore#insert_crawl` and `CrawlPolicyStore#activate_version`
    # each carry their own copy and each is driven here with a grant set that confers nothing.
    it "PROOF 253 — the QUEUE insert refuses an actor carrying no granting Assignment" do
      g = queueable_org
      authority = AuthorityFixture.for_session(g[:session_id], capability: "crawl.trigger", grants: [])

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
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

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only capability failed"
      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:inserted]).to eq(0)
      expect(DbInspector.all("SELECT id FROM crawls WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end

    it "PROOF 254 — the POLICY activation refuses an actor carrying no granting Assignment" do
      g = bootstrap
      authority = AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage", grants: [])

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id], authority:, project_id: nil, scope: "organization",
          policy_version: "crawl-policy-organization-v1", supersedes_id: nil,
          expected_state_version: nil, activated_by_account_id: authority.account_id,
          normalized_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING, content_sha256: "\x00" * 32
        )
      end

      expect(outcome[:epoch_authorized]).to be(true)
      expect(outcome[:capability_authorized]).to be(false)
      expect(outcome[:inserted]).to eq(0)
      expect(DbInspector.all("SELECT id FROM crawl_policies WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end
  end

  describe "the handler still refuses BEFORE its blocking wait" do
    # WHY THIS IS A SEPARATE PROPERTY FROM THE WRITE'S. FU-48 makes the write the backstop, so
    # deleting a handler's `decision.allowed?` no longer produces an unauthorised transition — which
    # means the OUTCOME alone can no longer tell the two apart, and a proof that only checks the
    # outcome would let the check be deleted silently.
    #
    # `PRULE-039`/SEC-REQ-005: "a check performed AFTER a side effect, or anywhere but the server, is
    # a bypass regardless of its arithmetic." An actor with no authority must be refused before the
    # command takes a lock other tenants' commands queue behind, so the handler's own check has a
    # property of its own and this is it, observed by INVOCATION rather than by a source line.
    def unauthorized_session(org)
      # A real Account in the Organization with an active Session and NO Role Assignment: it
      # authenticates and confers nothing.
      TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: nil,
                                         with_policy: false, issued_at: fixed_now - 300)[:session_id]
    end

    it "PROOF 255 — QueueCrawl denies without taking the per-Project lock" do
      g = queueable_org
      lock = ExecutionProbe.calls("IdentityAccess::Infrastructure::CrawlStore#lock_project").first
      session = unauthorized_session(g[:organization_id])

      result = nil
      seen = ExecutionProbe.watch([lock]) do
        result = Workflows::Wf005::Handlers::QueueCrawl.new.call(
          command: Workflows::Wf005::Commands::QueueCrawl.new(
            command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}",
            schema_version: "1.0", session_id: session, organization_id: g[:organization_id],
            project_id: g[:project_id], requested_at_utc: act_now
          ), request_context: act_ctx
        )
      end

      expect(result).not_to be_success
      expect(result.reason_code).to eq("crawl_trigger_unauthorized")
      expect(seen).not_to have_evaluated(lock),
                          "the handler took its blocking lock for an actor holding no authority"
      expect(DbInspector.all("SELECT id FROM crawls WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end

    it "PROOF 256 — CancelCrawl denies without taking the frontier lock" do
      ctx = running_crawl
      lock = ExecutionProbe.calls("IdentityAccess::Infrastructure::CrawlFrontierStore#lock_frontier").first
      session = unauthorized_session(ctx[:g][:organization_id])
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i

      result = nil
      seen = ExecutionProbe.watch([lock]) do
        result = Workflows::Wf005::Handlers::CancelCrawl.new.call(
          command: Workflows::Wf005::Commands::CancelCrawl.new(
            command_id: SecureRandom.uuid_v7, idempotency_key: "cx-#{SecureRandom.hex(6)}",
            schema_version: "1.0", session_id: session, organization_id: ctx[:g][:organization_id],
            project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
            expected_state_version: version, requested_at_utc: start_now
          ),
          request_context: Platform::RequestContext.for_actor(
            clock: Platform::Clock.fixed(start_now), ids: Platform::Ids.system,
            correlation_id: SecureRandom.uuid_v7
          )
        )
      end

      expect(result).not_to be_success
      expect(result.reason_code).to eq("crawl_cancel_unauthorized")
      expect(seen).not_to have_evaluated(lock)
      expect(crawl_state(ctx)).to eq("running")
    end

    it "PROOF 257 — ActivateCrawlPolicy denies without taking the per-Organization lock" do
      g = bootstrap
      lock = ExecutionProbe.calls("IdentityAccess::Infrastructure::CrawlPolicyStore#lock_organization").first
      session = unauthorized_session(g[:organization_id])
      ceiling = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
      bounds = ceiling.to_h { |d, v| [d, v.dup] }
      bounds["accepted_pages"] = bounds["accepted_pages"].merge("soft" => 5_000, "hard" => 6_000)

      result = nil
      seen = ExecutionProbe.watch([lock]) do
        result = Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
          command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(
            command_id: SecureRandom.uuid_v7, idempotency_key: "acp-#{SecureRandom.hex(6)}",
            schema_version: "1.0", session_id: session, organization_id: g[:organization_id],
            scope: "organization", project_id: nil, expected_current_policy_version: nil,
            expected_parent_policy_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
            expected_global_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
            proposed_bounds: bounds, requested_at_utc: act_now
          ), request_context: act_ctx
        )
      end

      expect(result).not_to be_success
      expect(result.reason_code).to eq("crawl_policy_unauthorized")
      expect(seen).not_to have_evaluated(lock)
      expect(DbInspector.all("SELECT id FROM crawl_policies WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end

    it "PROOF 257b — a MIS-SCOPED actor is denied before the lock too, not merely refused at the write" do
      # WHAT THIS CLOSES (round-15 contract finding R15-CTR-1). PROOF 255/256/257 all drive an actor
      # holding NO authority at all, so they exercise only the FIRST operand of
      # `unless decision.allowed? && authorized_for_scope?(command.scope, decision)`. The scope
      # operand — the ratified `:732`/`:738` rule, and the very limb FU-48 exists to enforce — had no
      # proof of its own: deleting it left 1136 acceptance examples green, because the WRITE still
      # refuses, so the OUTCOME alone cannot tell the two apart.
      #
      # `PRULE-039`/SEC-REQ-005 supplies the property that can: a check performed AFTER a side effect
      # is a bypass regardless of its arithmetic. A MarketingOperator asking for an ORGANIZATION-scope
      # activation must be refused BEFORE this command takes the per-Organization lock that every
      # other policy command in the tenant queues behind. The bounds are deliberately VALID and
      # NARROWING, so nothing upstream can refuse this command for any other reason: with the operand
      # deleted, the handler proceeds, takes the lock, and this example fails on the lock rather than
      # on the reason code.
      g = bootstrap
      lock = ExecutionProbe.calls("IdentityAccess::Infrastructure::CrawlPolicyStore#lock_organization").first
      operator = TenantSeeder.seed_authorized_admin(organization_id: g[:organization_id],
                                                    canonical_role: "MarketingOperator",
                                                    with_policy: false, issued_at: fixed_now - 300)
      ceiling = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
      bounds = ceiling.to_h { |d, v| [d, v.dup] }

      result = nil
      seen = ExecutionProbe.watch([lock]) do
        result = Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
          command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(
            command_id: SecureRandom.uuid_v7, idempotency_key: "acp-#{SecureRandom.hex(6)}",
            schema_version: "1.0", session_id: operator[:session_id],
            organization_id: g[:organization_id], scope: "organization", project_id: nil,
            expected_current_policy_version: nil,
            expected_parent_policy_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
            expected_global_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
            proposed_bounds: bounds, requested_at_utc: act_now
          ), request_context: act_ctx
        )
      end

      expect(result).not_to be_success
      expect(result.reason_code).to eq("crawl_policy_unauthorized"),
                                    "a mis-scoped actor was refused for a reason other than authority: " \
                                    "#{result.reason_code}"
      expect(seen).not_to have_evaluated(lock),
                          "the mis-scoped actor reached the per-Organization lock before being refused; " \
                          ":329 requires F1-AUTH-403 with NO product side effect, and PRULE-039 makes a " \
                          "check performed after one a bypass whatever its arithmetic"
      expect(DbInspector.all("SELECT id FROM crawl_policies WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end
  end

  describe "the attestation carries the same authority the write does" do
    def attest(pg, actor:, decision:, capability: "crawl.cancel")
      auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
      Workflows::Wf005::AuthorityAttestation.attest(pg, auth_store:, actor:, decision:, capability:)
    end

    def actor_for(g, pg)
      auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
      IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
                                                      .authenticate(session_id: g[:session_id], now: start_now,
                                                                    correlation_id: SecureRandom.uuid_v7)
    end

    it "PROOF 249 — no attestation is minted for a decision that did not allow, EVEN WITH GRANTS" do
      # The mint is the only source of an attestation and the commit demands one, so refusing here is
      # what makes an unauthorised caller unable to reach a protected write at all.
      #
      # THE DECISION CARRIES ITS GRANTS, AND THAT IS THE POINT. A denial with an empty grant set is
      # refused by the grant check one line below, so a proof using one cannot tell whether the
      # `allowed?` guard exists at all — measured: deleting it SURVIVED that proof. `:329` is explicit
      # that a policy deny can subtract a permission an Assignment grants ("subtract every applicable
      # Access Policy deny. Policy deny has precedence over every Role allow"), so a denial that still
      # names granting Assignments is the shape this guard is for, and it is the shape driven here.
      ctx = running_crawl
      Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
        auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
        actor = auth.authenticate(session_id: ctx[:g][:session_id], now: start_now,
                                  correlation_id: SecureRandom.uuid_v7)
        allowed = auth.authorize(actor:, capability: "crawl.cancel", now: start_now)
        expect(allowed.granting).not_to be_empty, "the fixture confers nothing, so this proves nothing"

        denied = IdentityAccess::Authorization::Decision.new(
          allowed: false, reason: "policy_denied", organization_epoch: actor.authorization_epoch,
          policy_snapshot_id: allowed.policy_snapshot_id,
          role_assignment_versions: allowed.role_assignment_versions,
          granting_assignments: allowed.granting
        )

        expect(attest(pg, actor:, decision: denied)).to be_nil
      end
    end

    it "PROOF 250 — nor for an allowed decision that confers no grant" do
      ctx = running_crawl
      Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        actor = actor_for(ctx[:g], pg)
        empty = IdentityAccess::Authorization::Decision.new(
          allowed: true, reason: "authorized", organization_epoch: actor.authorization_epoch,
          policy_snapshot_id: nil, role_assignment_versions: [], granting_assignments: []
        )

        expect(attest(pg, actor:, decision: empty)).to be_nil
      end
    end

    it "PROOF 251 — an attestation minted for one capability is refused at another's write" do
      # It names the actor, the epoch, the capability and the grants. A write carrying different
      # authority than the attestation was minted for is a handler defect, and raises.
      ctx = running_crawl
      Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
        auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
        actor = auth.authenticate(session_id: ctx[:g][:session_id], now: start_now,
                                  correlation_id: SecureRandom.uuid_v7)
        decision = auth.authorize(actor:, capability: "crawl.cancel", now: start_now)
        attestation = attest(pg, actor:, decision:, capability: "crawl.cancel")
        expect(attestation).not_to be_nil

        other = IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:,
                                                                  capability: "crawl.trigger")

        expect do
          Workflows::Wf005::AuthorityAttestation.require!(attestation, connection: pg, authority: other)
        end.to raise_error(Workflows::Wf005::AuthorityAttestation::Missing, /different actor, epoch, capability/)
      end
    end
  end

  describe "the cell the write is handed is the one the ratified baseline names" do
    it "PROOF 265 — `WriteAuthority.for` carries THIS capability's cell, not a union of every cell" do
      # THE HALF THE BATTERY CANNOT BIND (round-18 finding CB-2). Every battery case supplies
      # `allowed_roles` explicitly or through the fixture, so all of them prove what the STATEMENT does
      # with a cell — none proves that the right cell is derived. Measured: replacing the derivation
      # with `CAPABILITIES.values.flatten.uniq` — R17-SEC-1 reinstated one layer up, in Ruby — left 50
      # examples green.
      #
      # So this drives the store with an authority built by `WriteAuthority.for` itself, for a
      # capability whose ratified cell EXCLUDES the actor's role. The actor is a real
      # OrganizationAdmin with a real allowed decision; only the capability differs, and the write must
      # refuse. A union cell would admit it.
      ctx = running_crawl
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i

      outcomes = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
        auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
        actor = auth.authenticate(session_id: ctx[:g][:session_id], now: start_now,
                                  correlation_id: SecureRandom.uuid_v7)
        decision = auth.authorize(actor:, capability: "crawl.cancel", now: start_now)
        expect(decision).to be_allowed
        expect(Platform::PermissionBaseline::CAPABILITIES.fetch("invitation.approve"))
          .not_to include("OrganizationAdmin"),
                  "the foil capability's cell admits this actor's role, so the proof is vacuous"

        store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        foil = IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:,
                                                                 capability: "invitation.approve")
        real = IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:,
                                                                 capability: "crawl.cancel")
        [store.cancel(ctx[:crawl_id], version, start_now, authority: foil),
         store.cancel(ctx[:crawl_id], version, start_now, authority: real)]
      end

      expect(outcomes.first[:capability_authorized]).to be(false),
                                                        "the write accepted a cell that does not name this " \
                                                        "capability, so the derivation is not what is carried"
      expect(outcomes.first[:moved]).to eq(0)
      expect(outcomes.last[:capability_authorized]).to be(true), "the control refused, so PROOF 265 is vacuous"
      expect(outcomes.last[:moved]).to eq(1)
    end
  end

  describe "the capability limb is lock-based too" do
    it "PROOF 252 — a grant revocation cannot land while the guarded statement is blocked mid-flight" do
      # THE SAME PROPERTY THE EPOCH LIMB HAS, AND FOR THE SAME REASON. Revoking a Role Assignment is a
      # non-key UPDATE, so it takes `FOR NO KEY UPDATE`, which conflicts with `FOR SHARE` and not with
      # `FOR KEY SHARE`. Without the measurement this limb would have inherited the round-two mistake.
      ctx = running_crawl
      org = ctx[:g][:organization_id]
      authority = authority_for(ctx)
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i

      blocker = RaceHarness.open_connection
      blocker.exec("BEGIN")
      blocker.exec_params("SELECT id FROM crawls WHERE id = $1::uuid FOR UPDATE", [ctx[:crawl_id]])
      blocker_pid = blocker.exec("SELECT pg_backend_pid()").getvalue(0, 0).to_i
      revocation = nil
      op = nil

      begin
        op = RaceHarness.spawn_operation(-> { cancel_with(ctx, authority) })
        RaceHarness.wait_until("the cancellation blocked behind #{blocker_pid}") do
          RaceHarness.observer.exec_params(<<~SQL, [blocker_pid]).getvalue(0, 0).to_i.positive?
            SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
            WHERE NOT l.granted AND a.datname = current_database()
              AND $1::int = ANY (pg_blocking_pids(l.pid))
          SQL
        end

        revoker = RaceHarness.open_connection
        begin
          revoker.exec("BEGIN")
          revoker.exec("SET lock_timeout = '2000ms'")
          revocation = begin
            revoker.exec_params(<<~SQL, [org])
              UPDATE role_assignments SET status = 'revoked', state_version = state_version + 1,
                     updated_at = now(), terminated_at = now(),
                     transition_reason_code = 'role_assignment_revoked'
              WHERE organization_id = $1::uuid AND status = 'active'
            SQL
            revoker.exec("COMMIT")
            :committed
          rescue PG::LockNotAvailable, PG::QueryCanceled
            revoker.exec("ROLLBACK")
            :blocked
          end
        ensure
          revoker.close
        end
      ensure
        begin
          blocker.exec("ROLLBACK")
        rescue StandardError
          nil
        end
        blocker.close
      end

      outcome = op.value
      raise outcome if outcome.is_a?(StandardError)

      expect(revocation).to eq(:blocked),
                            "the grant was revoked while the guarded statement was in flight, so the " \
                            "capability predicate was decided from a snapshot that had already expired"
      expect(outcome[:capability_authorized]).to be(true)
      expect(outcome[:moved]).to eq(1)
    end
  end
end
