# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# ONE BATTERY, DRIVEN AGAINST ALL THREE PROTECTED WRITES (round-15 architecture finding A15-1).
#
# WHAT WAS OPEN. The capability predicate is written three times — once in each protected write — and
# the proofs enumerated which (write, conjunct) PAIRS were exercised. PROOF 243-248/252 drove the
# CANCELLATION only; PROOF 253/254 drove the queue and policy writes with an EMPTY grant set, the
# shallowest case there is. Measured by the round-15 architecture lens: TEN conjuncts could be deleted
# — the queue and policy `status`, `state_version`, `scope` and `FOR SHARE OF ra` limbs, the queue
# expiry limb, the cancellation `effective_at` limb — with the whole suite green but for a byte-digest
# staleness check that fires for a comment-only edit too.
#
# That is this tranche's own defect class: a control proved at one instance and assumed at the others.
# The authors had already met it here and repaired ONE instance — `wf005_capability_write_authority_spec.rb`
# records "measured: deleting `AND ra.status = 'active'` SURVIVED it" and then added PROOF 244b for the
# cancellation alone.
#
# WHAT THIS FILE IS. The battery is written ONCE and run against EVERY protected write, so a conjunct
# cannot be proved at one write and untested at another. Adding a fourth protected write means adding
# it to `WRITES` and inheriting every case, rather than remembering which of seven properties to
# re-prove.
#
# EVERY CASE IS THE SAME SHAPE: build the authority the DECISION saw, then move the grant underneath
# it exactly as another transaction would, then drive the write. The control at the end commits, so a
# battery that refused everything for an unrelated reason fails rather than passing.
RSpec.describe "WF-005 protected writes re-read their grants", type: :acceptance,
                                                              acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
                                                              test_types: %w[TYP-SEC TYP-DATA] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def in_org(org)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, SecureRandom.uuid_v7])
      yield pg
    end
  end

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://battery.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  # Each write: how to reach it, what capability it spends, how to drive it with a chosen authority,
  # how many rows it applied, and what the aggregate looks like when it applied none.
  WRITES = {
    "the cancellation (CrawlStartStore#cancel)" => {
      capability: "crawl.cancel",
      setup: :setup_cancel,
      invoke: :invoke_cancel,
      applied: ->(outcome) { outcome[:moved] },
      untouched: :cancel_untouched?
    },
    "the queue insert (CrawlStore#insert_crawl)" => {
      capability: "crawl.trigger",
      setup: :setup_queue,
      invoke: :invoke_queue,
      applied: ->(outcome) { outcome[:inserted] },
      untouched: :queue_untouched?
    },
    "the policy activation (CrawlPolicyStore#activate_version)" => {
      capability: "policy.crawl.manage",
      setup: :setup_policy,
      invoke: :invoke_policy,
      applied: ->(outcome) { outcome[:inserted] },
      untouched: :policy_untouched?
    }
  }.freeze

  # ---- the three writes -------------------------------------------------------

  def setup_cancel
    ctx = running_crawl
    { org: ctx[:g][:organization_id], session: ctx[:g][:session_id], ctx: }
  end

  def invoke_cancel(env, authority)
    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [env[:ctx][:crawl_id]])["state_version"].to_i
    in_org(env[:org]) do |pg|
      IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
                                                     .cancel(env[:ctx][:crawl_id], version, start_now, authority:)
    end
  end

  def cancel_untouched?(env)
    DbInspector.one("SELECT state FROM crawls WHERE id = $1::uuid", [env[:ctx][:crawl_id]])["state"] == "running"
  end

  def setup_queue
    g = queueable_org
    { org: g[:organization_id], session: g[:session_id], project: g[:project_id] }
  end

  def invoke_queue(env, authority)
    in_org(env[:org]) do |pg|
      IdentityAccess::Infrastructure::CrawlStore.new(pg).insert_crawl(
        id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
        organization_id: env[:org], authority:, project_id: env[:project], kind: "root",
        requested_crawl_policy_id: nil, requested_crawl_policy_version: nil,
        requested_entitlement_policy_id: SecureRandom.uuid_v7,
        requested_entitlement_policy_version: "entitlement-interim-v1",
        trigger_kind: "manual", triggered_by_account_id: nil, idempotency_key_digest: "\x00" * 32
      )
    end
  end

  def queue_untouched?(env)
    DbInspector.all("SELECT id FROM crawls WHERE organization_id = $1::uuid AND state = 'queued'",
                    [env[:org]]).empty?
  end

  def setup_policy
    g = bootstrap
    { org: g[:organization_id], session: g[:session_id] }
  end

  def invoke_policy(env, authority)
    in_org(env[:org]) do |pg|
      IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
        id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
        organization_id: env[:org], authority:, project_id: nil, scope: "organization",
        policy_version: "crawl-policy-organization-v1", supersedes_id: nil,
        expected_state_version: nil, activated_by_account_id: authority.account_id,
        normalized_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING, content_sha256: "\x00" * 32
      )
    end
  end

  def policy_untouched?(env)
    DbInspector.all("SELECT id FROM crawl_policies WHERE organization_id = $1::uuid", [env[:org]]).empty?
  end

  # ---- moving the grant underneath a decision that already read it ------------

  def grant_ids(org)
    DbInspector.all("SELECT id FROM role_assignments WHERE organization_id = $1::uuid AND status = 'active'",
                    [org]).map { |r| r["id"] }
  end

  # Seed one further Role Assignment for the ACTOR'S OWN account and return it in the shape the
  # decision carries. Seeded rather than moved, because `f1_role_assignments_lifecycle_guard` freezes
  # `canonical_role`, `permission_mode` and `persona` after insert — which is itself why neither axis
  # can be reached by moving a row underneath a decision.
  def seed_actor_grant(env, canonical_role:, permission_mode: "standard", persona: nil)
    account = DbInspector.one("SELECT account_id FROM sessions WHERE id = $1::uuid",
                              [env[:session]])["account_id"]
    TenantSeeder.create_role_assignment(organization_id: env[:org], account_id: account,
                                        canonical_role:, permission_mode:, persona:)
    row = DbInspector.one(<<~SQL, [env[:org], account, canonical_role, permission_mode])
      SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
      FROM role_assignments
      WHERE organization_id = $1::uuid AND account_id = $2::uuid AND status = 'active'
        AND canonical_role = $3 AND permission_mode = $4
    SQL
    raise "the #{canonical_role}/#{permission_mode} grant was not seeded" if row.nil?

    row
  end

  # THE AUTHORITY AS PRODUCTION BUILDS IT, for a decision carrying exactly `grant`. `confers?` filters
  # a denied grant out of `decision.granting` upstream, so the decision is constructed here holding it:
  # that is precisely the state a deleted or wrong `confers?` produces, and it is what the write-level
  # counterpart exists to survive. The DERIVATIONS are the real ones — this is the half no fixture can
  # bind, because `AuthorityFixture` carries its own copy of them.
  def production_authority(env, capability, grant)
    in_org(env[:org]) do |pg|
      auth = IdentityAccess::Authorization::CommandAuthorizer.new(
        IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
      )
      actor = auth.authenticate(session_id: env[:session], now: start_now,
                                correlation_id: SecureRandom.uuid_v7)
      decision = IdentityAccess::Authorization::Decision.new(
        allowed: true, reason: "authorized", organization_epoch: actor.authorization_epoch,
        policy_snapshot_id: nil, role_assignment_versions: [], granting_assignments: [grant]
      )
      IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:, capability:)
    end
  end

  def move_grants(org, set, params = [])
    DbInspector.connection.exec_params(<<~SQL, [org, *params])
      UPDATE role_assignments SET #{set}
      WHERE organization_id = $1::uuid AND status = 'active'
    SQL
  end

  shared_examples "a protected write that re-reads the grants its decision relied on" do |spec|
    let(:env) { send(spec.fetch(:setup)) }
    let(:authority) { AuthorityFixture.for_session(env[:session], capability: spec.fetch(:capability)) }

    def drive(spec, env, authority) = send(spec.fetch(:invoke), env, authority)

    it "refuses when the granting Assignment has been REVOKED" do
      authority
      move_grants(env[:org], "status = 'revoked'")

      outcome = drive(spec, env, authority)

      expect(outcome[:capability_authorized]).to be(false)
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses when the granting Assignment's STATE VERSION has moved" do
      authority
      move_grants(env[:org], "state_version = state_version + 1")

      outcome = drive(spec, env, authority)

      expect(outcome[:capability_authorized]).to be(false)
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses when the grant's SCOPE is not the one the decision evaluated" do
      # `scope_sha256` is frozen by `f1_role_assignments_lifecycle_guard`, so the divergence is built
      # on the decision's side — which is the real shape: a decision that evaluated one scope cannot
      # spend a grant carrying another.
      grants = AuthorityFixture.active_grants(env[:org], authority.account_id)
                               .map { |g| g.merge("scope_hex" => "00" * 32) }
      mis_scoped = AuthorityFixture.for_session(env[:session], capability: spec.fetch(:capability),
                                                               grants:)

      outcome = drive(spec, env, mis_scoped)

      expect(outcome[:capability_authorized]).to be(false)
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses when the grant has EXPIRED at the instant the write judges it" do
      authority
      move_grants(env[:org], "expires_at = $2::timestamptz", [(act_now - 60).iso8601(6)])

      outcome = drive(spec, env, authority)

      expect(outcome[:capability_authorized]).to be(false)
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses when the grant is NOT YET EFFECTIVE at that instant" do
      authority
      move_grants(env[:org], "effective_at = $2::timestamptz", [(start_now + 3600).iso8601(6)])

      outcome = drive(spec, env, authority)

      expect(outcome[:capability_authorized]).to be(false)
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses when the actor carries NO granting Assignment at all" do
      empty = AuthorityFixture.for_session(env[:session], capability: spec.fetch(:capability), grants: [])

      outcome = drive(spec, env, empty)

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false)
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses when the grant is LIVE but its role confers nothing (round-17 finding R17-SEC-1)" do
      # THE CASE TEN ROUNDS DID NOT ASK. Every other case moves the grant — revoked, version, scope,
      # expiry, effectiveness — so all of them are about LIVENESS. None asked what the grant CONFERS.
      # Measured before the repair: an account whose only active Assignment is a role the ratified
      # baseline denies this capability outright was AUTHORISED by the write at two of the three
      # sites, and so was a capability string that does not exist in the baseline at all. The write
      # asked "is this grant still the grant the decision named", never "does it confer this".
      #
      # The predicate is the baseline CELL carried as a parameter, so this drives it by handing the
      # write the real grant with a cell that excludes its role — which is exactly the state a
      # deleted or wrong `confers?` produces upstream.
      denied = AuthorityFixture.for_session(env[:session], capability: spec.fetch(:capability),
                                                           allowed_roles: %w[NoSuchRole])

      outcome = drive(spec, env, denied)

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "a grant whose role the baseline denies this capability " \
                                                 "authorised a protected write"
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses a READ-ONLY grant whose capability the baseline does not survive read-only (round-18 CB-1)" do
      # THE SIXTH COLUMN. `CAPABILITIES` is keyed by `canonical_role` alone, so the role predicate
      # admits a Read-Only Executive Buyer whose ratified cell at `:147` reads `deny` — measured, that
      # tuple cancelled a running Crawl through the write. `permission_mode` is NOT NULL with a
      # two-value CHECK, so the statement can bind it, and `READ_ONLY_CAPABILITIES` is the ratified
      # list of what survives read-only (empty for everything this build materializes).
      #
      # THE GRANT IS SEEDED READ-ONLY RATHER THAN MOVED. `f1_role_assignments_lifecycle_guard` freezes
      # `permission_mode` after insert, which is itself the reason this axis cannot be reached by
      # moving a row underneath a decision: the only way a read-only grant reaches a write is by being
      # one, which is exactly what a deleted `mode_permits?` upstream would let through.
      account = TenantSeeder.create_account(organization_id: env[:org],
                                            issuer_key: "https://id.example/oidc",
                                            subject: "ro-#{SecureRandom.hex(6)}")
      TenantSeeder.create_role_assignment(organization_id: env[:org], account_id: account,
                                          canonical_role: "MarketingOperator",
                                          permission_mode: "read_only", persona: "executive_buyer")
      grant = DbInspector.one(<<~SQL, [env[:org], account])
        SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
        FROM role_assignments WHERE organization_id = $1::uuid AND account_id = $2::uuid
      SQL
      expect(grant).not_to be_nil, "the read-only grant was not seeded, so this case is vacuous"
      read_only = AuthorityFixture.build(organization_id: env[:org], account_id: account,
                                         capability: spec.fetch(:capability), grants: [grant])

      outcome = drive(spec, env, read_only)

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "a read-only grant spent a capability the ratified table " \
                                                 "denies it"
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses a grant that belongs to ANOTHER ACCOUNT in the same Organization (round-19 finding R19-CTR-2)" do
      # THE CONJUNCT NINETEEN ROUNDS NEVER BOUND. Every case above moves the GRANT — revoked, version,
      # scope, expiry, effectiveness, role, mode — so each binds a qual about the grant's own state.
      # None asked whether the grant belongs to the PRINCIPAL the authority names. Measured at round 19:
      # replacing `ra.account_id = $n` with a tautology of the same arity left all 27 battery examples
      # green, and the only thing in the whole 2464-example suite that reacted was
      # `repository_truth_spec`'s byte-digest staleness check — which fires identically for a
      # comment-only edit, so it cannot tell deleting an authorization qual from adding a comment.
      #
      # FU-50's recorded basis was that "any drift fails seven cases at the drifting write". That is
      # refuted for this qual, and the copies agree only in SQL TEXT: `crawl_store`/`crawl_policy_store`
      # bind the organization slot to the ROW's id while `crawl_start_store` binds it to the
      # AUTHORITY's, which a textual comparison cannot see (round-19 finding R19-ARCH-3).
      #
      # THE GRANT IS REAL AND FULLY LIVE — same Organization, active, effective, unexpired, and a role
      # the ratified cell admits — so every OTHER qual passes and this one is the only thing that can
      # refuse it. That is the state a `confers?` that selected another principal's Assignments would
      # produce upstream.
      other = TenantSeeder.create_account(organization_id: env[:org],
                                          issuer_key: "https://id.example/oidc",
                                          subject: "other-#{SecureRandom.hex(6)}")
      TenantSeeder.create_role_assignment(organization_id: env[:org], account_id: other,
                                          canonical_role: "MarketingOperator")
      foreign = DbInspector.one(<<~SQL, [env[:org], other])
        SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
        FROM role_assignments
        WHERE organization_id = $1::uuid AND account_id = $2::uuid AND status = 'active'
      SQL
      expect(foreign).not_to be_nil, "the second account's grant was not seeded, so this case is vacuous"
      expect(Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)))
        .to include("MarketingOperator"),
            "the foreign grant's role is outside this capability's cell, so the role qual would refuse " \
            "it and this case would not bind the account qual"

      borrowed = AuthorityFixture.build(organization_id: env[:org], account_id: authority.account_id,
                                        capability: spec.fetch(:capability), grants: [foreign])

      outcome = drive(spec, env, borrowed)

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "a grant belonging to another Account authorised this " \
                                                 "principal's protected write"
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    # THE DERIVATIONS, BOUND AT EVERY CAPABILITY RATHER THAN AT ONE (round-19 finding R-ADV-2).
    #
    # PROOF 265 and PROOF 266 each drive ONE write, so each binds its derivation for ONE capability.
    # `WriteAuthority.for` reads the ratified cell PER CAPABILITY, and every other read-only or
    # denied-role case in the suite builds its authority through `AuthorityFixture`, which carries its
    # OWN copy of both expressions. Measured: breaking `read_only_permitted` for `crawl.trigger` ALONE,
    # or for `policy.crawl.manage` ALONE, or breaking `allowed_roles` for `crawl.trigger` ALONE, leaves
    # ALL 1185 acceptance examples green — and a Read-Only Executive Buyer then QUEUES A CRAWL
    # (`capability_authorized=true inserted=1`). That is round-18 CB-1 one capability over, inside the
    # round-19 repair for it, and it is this tranche's signature shape: a control proved at one
    # instance and assumed at the others.
    #
    # These two cases live in the shared examples so they run at EVERY write BY CONSTRUCTION, which is
    # the same structural answer the principal-conjunct case above uses. Each seeds a grant for the
    # ACTOR'S OWN account — so the principal qual passes — and builds the authority through the
    # PRODUCTION BUILDER for THIS write's real capability.
    it "refuses a READ-ONLY grant when the authority comes from the PRODUCTION BUILDER (R-ADV-2)" do
      # `MarketingOperator` is inside every one of the three ratified cells, so the ROLE qual passes and
      # the sixth column is the only thing that can refuse it. If `read_only_permitted` were derived
      # permissively for THIS capability, the write would authorise.
      grant = seed_actor_grant(env, canonical_role: "MarketingOperator",
                                    permission_mode: "read_only", persona: "executive_buyer")
      expect(Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)))
        .to include("MarketingOperator"),
            "the seeded role is outside this capability's cell, so the ROLE qual would refuse first " \
            "and this case would not bind the read-only derivation"

      outcome = drive(spec, env, production_authority(env, spec.fetch(:capability), grant))

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "a read-only grant spent this capability through the " \
                                                 "production builder, so the sixth column is not what " \
                                                 "`WriteAuthority.for` derives for it"
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "refuses a grant whose role the cell EXCLUDES, from the PRODUCTION BUILDER (R-ADV-2)" do
      # `TechnicalImplementer` is denied all three capabilities by the ratified table, and the battery
      # passes no `required_role`, so `allowed_roles` is the only thing that can refuse it. If the cell
      # were derived as a union — R17-SEC-1 one layer up — the write would authorise.
      grant = seed_actor_grant(env, canonical_role: "TechnicalImplementer")
      expect(Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)))
        .not_to include("TechnicalImplementer"),
                "the ratified cell now admits this role, so the case proves nothing"

      outcome = drive(spec, env, production_authority(env, spec.fetch(:capability), grant))

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "a role the ratified cell denies spent this capability " \
                                                 "through the production builder"
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    it "COMMITS when the grant is exactly the one the decision relied on, so the battery is not vacuous" do
      outcome = drive(spec, env, authority)

      expect(outcome[:capability_authorized]).to be(true)
      expect(outcome[:epoch_authorized]).to be(true)
      expect(spec.fetch(:applied).call(outcome)).to eq(1)
    end
  end

  WRITES.each do |name, spec|
    describe name do
      include_examples "a protected write that re-reads the grants its decision relied on", spec
    end
  end
end
