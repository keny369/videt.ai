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
# WHAT THIS FILE IS. The battery is written ONCE and run against every protected write LISTED IN
# `WRITES`, so a conjunct cannot be proved at one listed write and untested at another. Adding a
# further protected write means adding it to `WRITES` and inheriting every case, rather than
# remembering which of seven properties to re-prove — but the ADDING is a human act that nothing
# enforces, which round 20 demonstrated and FU-61 records.
#
# EVERY CASE IS THE SAME SHAPE: build the authority the DECISION saw, then move the grant underneath
# it exactly as another transaction would, then drive the write. The control at the end commits, so a
# battery that refused everything for an unrelated reason fails rather than passing.
#
# ---------------------------------------------------------------------------------------------
# FU-63 — THE SAME DEFECT CLASS, ONE LEVEL DOWN: PROVED AT ONE CONFIGURATION, ASSUMED AT THE OTHERS.
#
# A15-1 made the battery run at every WRITE. Round 20 measured what it still ran at only ONE VALUE:
# 78 narrowly-scoped mutations, 48 survivors, 5 confirmed against the full 1191-example acceptance
# corpus. None was a reachable product defect — 12 probes against the real stores and handlers pass
# at HEAD — and all five were EVIDENCE gaps of one shape.
#
#   R20-1  `g.id = ra.id` was bound by NOTHING at all three writes. Unbinding it at the queue write
#          left the battery at 36 examples / 0 failures, and driven at the store it QUEUED A CRAWL
#          ON A REVOKED GRANT. The round-19 foreign-account case does not bind it: `TenantSeeder`
#          inserts state_version 0 with a NULL scope while the bootstrap grant is state_version 1
#          with a scope digest, so that case is discriminated by the VERSION and SCOPE conjuncts and
#          never reaches identity.
#   R20-2  Every driver used ORGANIZATION scope with `required_role: nil`, so THE ENTIRE
#          PROJECT-SCOPE CONFIGURATION OF `ActivateCrawlPolicy` had no write-level negative proof.
#          Deriving `read_only_permitted` as `!required_role.nil?` survived the corpus and, driven,
#          A READ-ONLY EXECUTIVE BUYER ACTIVATED AN IMMUTABLE PROJECT-SCOPE CRAWL POLICY.
#   R20-4  "Refused BEFORE the lock" was proved only for an actor holding NO Assignment (see
#          `wf005_capability_write_authority_spec.rb`).
#   R20-5  `ra.status = 'active'` was bound only against `revoked`.
#
# SO THE BATTERY IS PARAMETERISED BY CONFIGURATION, NOT ONLY BY WRITE. `WRITES` now carries each
# write's PRODUCTION `required_role`, the policy write appears at BOTH of its ratified scopes, and
# the negative role population is DERIVED FROM THE RATIFIED `:135` TABLE — every canonical role whose
# cell reads `deny` — rather than hand-picked one role at a time.
#
# WHAT IS DERIVED AND WHAT IS STILL A LIST, STATED PLAINLY. Round 20 refuted ADR-138's "by
# construction" inheritance claim by building a fourth protected write that inherited nothing while
# the suite stayed green, so this file will not repeat that claim in a wider form. Two of the three
# populations here ARE derived and cannot drift: the denied ROLES come from the ratified document,
# and `same_principal?`'s members come from the `Data` class itself (see
# `wf005_capability_write_authority_spec.rb`). `WRITES` IS STILL A HAND-MAINTAINED LIST. A fifth
# protected write, or a third policy scope, joins it only when somebody adds it — and the SCOPE
# totality check at the foot of this file closes that hole for the policy write alone. Enforcing the
# completeness of `WRITES` itself is FU-61 and remains open.
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

  # Each write: how to reach it, what capability it spends, THE `required_role` ITS PRODUCTION
  # CALLER PASSES, how to drive it with a chosen authority, how many rows it applied, and what the
  # aggregate looks like when it applied none.
  #
  # `required_role` IS PART OF THE CONFIGURATION, NOT AN OPTIONAL EXTRA (FU-63 part 2). It is the
  # ratified `:732`/`:738` scope rule carried to the write, and it is the ONLY axis on which the two
  # policy configurations differ. Every driver before this round passed `nil` — the value the
  # cancellation and the queue insert really use — so the policy write was exercised at a value its
  # production caller can never pass. `ActivateCrawlPolicy` derives it from `SCOPE_ROLE[scope]`, and
  # `valid_scope_shape?` admits exactly `organization` and `project`, so BOTH rows below are
  # production configurations and there is no third one. That totality is asserted, not assumed —
  # see "the two policy configurations are the whole of `SCOPE_ROLE`" at the foot of this file.
  WRITES = {
    "the cancellation (CrawlStartStore#cancel)" => {
      capability: "crawl.cancel",
      required_role: nil,
      setup: :setup_cancel,
      invoke: :invoke_cancel,
      applied: ->(outcome) { outcome[:moved] },
      untouched: :cancel_untouched?
    },
    "the queue insert (CrawlStore#insert_crawl)" => {
      capability: "crawl.trigger",
      required_role: nil,
      setup: :setup_queue,
      invoke: :invoke_queue,
      applied: ->(outcome) { outcome[:inserted] },
      untouched: :queue_untouched?
    },
    "the policy activation at ORGANIZATION scope (CrawlPolicyStore#activate_version)" => {
      capability: "policy.crawl.manage",
      required_role: "OrganizationAdmin",
      setup: :setup_policy,
      invoke: :invoke_policy,
      applied: ->(outcome) { outcome[:inserted] },
      untouched: :policy_untouched?
    },
    # THE CONFIGURATION R20-2 FOUND UNPROVED. `:173` gives the MarketingOperator a Project-scope
    # cell, `SCOPE_ROLE["project"]` transcribes it, and no driver in twenty rounds had ever passed
    # it. A `read_only_permitted` derived as `!required_role.nil?` is FALSE in every organization-
    # scope case that existed and TRUE here, which is exactly why the corpus stayed green while a
    # Read-Only Executive Buyer activated an immutable Project policy.
    "the policy activation at PROJECT scope (CrawlPolicyStore#activate_version)" => {
      capability: "policy.crawl.manage",
      required_role: "MarketingOperator",
      setup: :setup_policy_project,
      invoke: :invoke_policy_project,
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

  # PROJECT SCOPE, WHICH THE RATIFIED TABLE GIVES TO THE MARKETING OPERATOR (`:173`).
  #
  # The bootstrapped actor is an OrganizationAdmin, so this seeds the actor its OWN standard
  # MarketingOperator Assignment — the grant `SCOPE_ROLE["project"]` demands — before the authority
  # is built. Without it the control case could not commit and every negative case here would pass
  # for the wrong reason, which is the vacuity this file guards against everywhere else.
  def setup_policy_project
    g = bootstrap
    env = { org: g[:organization_id], session: g[:session_id], project: g[:project_id] }
    seed_actor_grant(env, canonical_role: "MarketingOperator")
    env
  end

  def invoke_policy_project(env, authority)
    in_org(env[:org]) do |pg|
      IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
        id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
        organization_id: env[:org], authority:, project_id: env[:project], scope: "project",
        policy_version: "crawl-policy-project-v1", supersedes_id: nil,
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

  def actor_account(env)
    DbInspector.one("SELECT account_id FROM sessions WHERE id = $1::uuid", [env[:session]])["account_id"]
  end

  # An ACTIVE, unscoped, standard grant of `canonical_role` already held by the actor, or nil. The
  # seeder inserts `state_version 0` with a NULL scope, so a row this finds is interchangeable with
  # one it would seed — which is what the grant-identity case needs of its live sibling.
  def existing_actor_grant(env, canonical_role)
    DbInspector.one(<<~SQL, [env[:org], actor_account(env), canonical_role])
      SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
      FROM role_assignments
      WHERE organization_id = $1::uuid AND account_id = $2::uuid AND status = 'active'
        AND canonical_role = $3 AND permission_mode = 'standard' AND persona IS NULL
        AND scope_sha256 IS NULL AND state_version = 0
      ORDER BY id LIMIT 1
    SQL
  end

  # One Role Assignment row in the shape the decision carries it: id, state version, hex scope.
  def grant_row(id)
    DbInspector.one(<<~SQL, [id])
      SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
      FROM role_assignments WHERE id = $1::uuid
    SQL
  end

  # Seed one further Role Assignment for the ACTOR'S OWN account and return it in the shape the
  # decision carries. Seeded rather than moved, because `f1_role_assignments_lifecycle_guard` freezes
  # `canonical_role`, `permission_mode` and `persona` after insert — which is itself why neither axis
  # can be reached by moving a row underneath a decision.
  #
  # `status`, `effective_at` and `expires_at` are parameters because the STATUS SWEEP (FU-63 part 6)
  # needs rows the guard's transition table cannot produce from `active`: `pending` and `rejected`
  # are reachable in production only before a grant was ever effective, and the guard admits
  # `active -> {revoked, expired}` alone. INSERT is not guarded, so the seeder is the only way to
  # build each status in the shape production really holds it.
  def seed_actor_grant(env, canonical_role:, permission_mode: "standard", persona: nil,
                       status: "active", effective_at: Time.utc(2026, 1, 1), expires_at: nil)
    id = TenantSeeder.create_role_assignment(organization_id: env[:org], account_id: actor_account(env),
                                             canonical_role:, permission_mode:, persona:,
                                             status:, effective_at:, expires_at:)
    row = grant_row(id)
    raise "the #{canonical_role}/#{permission_mode}/#{status} grant was not seeded" if row.nil?

    row
  end

  # THE AUTHORITY AS PRODUCTION BUILDS IT, for a decision carrying exactly `grant`. `confers?` filters
  # a denied grant out of `decision.granting` upstream, so the decision is constructed here holding it:
  # that is precisely the state a deleted or wrong `confers?` produces, and it is what the write-level
  # counterpart exists to survive. The DERIVATIONS are the real ones — this is the half no fixture can
  # bind, because `AuthorityFixture` carries its own copy of them.
  #
  # `required_role` IS THREADED THROUGH (FU-63 part 2). `WriteAuthority.for` takes it, every
  # production caller of the policy write passes it, and passing `nil` here would drive the
  # production BUILDER at a configuration production never uses — which is how R20-2's
  # `read_only_permitted` derivation stayed unbound at Project scope.
  def production_authority(env, capability, grant, required_role: nil)
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
      IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:, capability:, required_role:)
    end
  end

  # The values `role_assignments.status` can hold, READ FROM THE DATABASE rather than listed here
  # (FU-63 part 6). A status added to the CHECK constraint joins the sweep below by itself; a
  # hand-written list would leave the new one untested and green.
  def assignment_statuses
    DbInspector.one(<<~SQL)["def"].scan(/'([a-z]+)'::text/).flatten.uniq
      SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint
      WHERE conname = 'role_assignments_status_check'
    SQL
  end

  # Each non-active status in THE SHAPE PRODUCTION HOLDS IT, which is what decides whether the
  # status conjunct is the only thing refusing the row:
  #
  #   revoked  `active -> revoked` keeps `effective_at` and needs no expiry, so `ra.status =
  #            'active'` is the ONLY conjunct that refuses it. This is the discriminating case.
  #   expired  `active -> expired` is timer-driven off `expires_at`, so a production `expired` row
  #            also has an elapsed `expires_at`: refusal is over-determined by the expiry limb.
  #   pending  `role_assignment_pending_is_not_effective` FORBIDS an effective pending row, so
  #            refusal is over-determined by `ra.effective_at IS NOT NULL`. This is why R20-5's
  #            "admit pending" mutation survives: under that CHECK it is an EQUIVALENT mutation, not
  #            an unbound control. The CHECK is asserted below so the equivalence cannot outlive it.
  #   rejected reachable only from `pending` (the guard's transition table), so likewise never
  #            effective, and over-determined for the same reason.
  #
  # The sweep proves the whole vocabulary is refused — which is ADR-133's R15-CONC-1 premise, that a
  # `pending` target "is filtered out before asking for a lock", tested rather than assumed — while
  # `revoked` carries the independent discrimination of the status conjunct itself.
  def seed_status_grant(env, status, canonical_role:)
    case status
    when "revoked"  then seed_actor_grant(env, canonical_role:, status:, effective_at: start_now - 86_400)
    when "expired"  then seed_actor_grant(env, canonical_role:, status:, effective_at: start_now - 86_400,
                                                                        expires_at: start_now - 3_600)
    else seed_actor_grant(env, canonical_role:, status:, effective_at: nil)
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
    let(:authority) do
      AuthorityFixture.for_session(env[:session], capability: spec.fetch(:capability),
                                                  required_role: spec.fetch(:required_role))
    end

    def drive(spec, env, authority) = send(spec.fetch(:invoke), env, authority)

    # The role this write's own production configuration admits: the one `required_role` names, or —
    # where the ratified rule imposes none — any role inside the capability's cell.
    def acting_role(spec)
      spec.fetch(:required_role) ||
        Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)).first
    end

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
                                         capability: spec.fetch(:capability), grants: [grant],
                                         required_role: spec.fetch(:required_role))

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
      #
      # THE FOREIGN GRANT HOLDS THIS WRITE'S OWN ACTING ROLE (FU-63 part 2). It used to be a
      # hard-coded `MarketingOperator`, which at a configuration demanding `OrganizationAdmin` would
      # be refused by the scope rule before the principal conjunct was ever reached.
      role = acting_role(spec)
      other = TenantSeeder.create_account(organization_id: env[:org],
                                          issuer_key: "https://id.example/oidc",
                                          subject: "other-#{SecureRandom.hex(6)}")
      foreign_id = TenantSeeder.create_role_assignment(organization_id: env[:org], account_id: other,
                                                       canonical_role: role)
      foreign = grant_row(foreign_id)
      expect(foreign).not_to be_nil, "the second account's grant was not seeded, so this case is vacuous"
      expect(Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)))
        .to include(role),
            "the foreign grant's role is outside this capability's cell, so the role qual would refuse " \
            "it and this case would not bind the account qual"

      borrowed = AuthorityFixture.build(organization_id: env[:org], account_id: authority.account_id,
                                        capability: spec.fetch(:capability), grants: [foreign],
                                        required_role: spec.fetch(:required_role))

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
      #
      # AND IT IS SEEDED AT THIS WRITE'S OWN ACTING ROLE (FU-63 part 2, closing R20-2's second
      # survivor). `read_only_permitted` derived as `!required_role.nil?` is FALSE at every
      # organization-scope configuration and TRUE at Project scope, so the corpus stayed green while
      # A READ-ONLY EXECUTIVE BUYER ACTIVATED AN IMMUTABLE PROJECT-SCOPE CRAWL POLICY. At the
      # Project configuration the acting role IS `MarketingOperator`, so the cell conjunct and the
      # scope rule both pass and the sixth column is the only thing that can refuse.
      role = acting_role(spec)
      grant = seed_actor_grant(env, canonical_role: role,
                                    permission_mode: "read_only", persona: "executive_buyer")
      expect(Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)))
        .to include(role),
            "the seeded role is outside this capability's cell, so the ROLE qual would refuse first " \
            "and this case would not bind the read-only derivation"

      outcome = drive(spec, env, production_authority(env, spec.fetch(:capability), grant,
                                                      required_role: spec.fetch(:required_role)))

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "a read-only grant spent this capability through the " \
                                                 "production builder, so the sixth column is not what " \
                                                 "`WriteAuthority.for` derives for it"
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    # EVERY DENIED ROLE, DERIVED FROM THE RATIFIED TABLE (FU-63 part 1, closing R20-2).
    #
    # This case used to hand-pick `TechnicalImplementer`. One role is one value, and the round-20
    # measurement is what that costs: widening `allowed_roles` by `SecurityOperator` survived the
    # full 1191-example corpus, and driven at the store IT CANCELLED A CRAWL. A hand-picked negative
    # binds the conjunct against the one role somebody thought of.
    #
    # So the population comes from `:135` itself — every canonical role whose cell for THIS
    # capability reads `deny` — through the one parser `permission_baseline_transcription_spec.rb`
    # also reads. A role the table later starts allowing leaves this set by itself; a newly denied
    # one joins it and is proved without anybody remembering to add a case.
    RatifiedPermissionBaseline.denied_roles(spec.fetch(:capability)).each do |denied_role|
      it "refuses a grant held as #{denied_role}, whose ratified cell DENIES this capability" do
        expect(Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)))
          .not_to include(denied_role),
                  "the transcription admits a role the ratified cell denies, which is drift"

        grant = seed_actor_grant(env, canonical_role: denied_role)
        authority = production_authority(env, spec.fetch(:capability), grant,
                                         required_role: spec.fetch(:required_role))

        outcome = drive(spec, env, authority)

        expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
        expect(outcome[:capability_authorized]).to be(false),
                                                   "a role the ratified cell denies spent this capability " \
                                                   "through the production builder"
        expect(spec.fetch(:applied).call(outcome)).to eq(0)
        expect(send(spec.fetch(:untouched), env)).to be(true)
      end
    end

    # THE SCOPE RULE, AT THE CONFIGURATION THAT HAS ONE (FU-63 part 2, closing R20-2's third
    # survivor: "dropping `required_role` for PROJECT scope alone").
    #
    # `allowed_roles` and `required_role` are different conjuncts and this is the only case that can
    # tell them apart: the grant's role is INSIDE the capability's ratified cell — so the cell
    # conjunct passes — and is not the role THIS SCOPE demands. Nothing but `required_role` can
    # refuse it. Round 19's PROOF 258 proved this for the ORGANIZATION configuration at the handler;
    # the write had it proved at no configuration at all, because every driver passed `nil`.
    if spec.fetch(:required_role)
      it "refuses a grant whose role is in the cell but is NOT the role this scope demands" do
        foil = (Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)) -
                [spec.fetch(:required_role)]).first
        expect(foil).not_to be_nil,
                            "the cell holds only the required role, so `required_role` adds nothing here " \
                            "and this case cannot bind it"

        grant = seed_actor_grant(env, canonical_role: foil)
        authority = production_authority(env, spec.fetch(:capability), grant,
                                         required_role: spec.fetch(:required_role))

        outcome = drive(spec, env, authority)

        expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
        expect(outcome[:capability_authorized]).to be(false),
                                                   "a #{foil} grant activated a #{spec.fetch(:required_role)}-" \
                                                   "scoped policy: the ratified `:732`/`:738` scope rule is " \
                                                   "not a conjunct of this write"
        expect(spec.fetch(:applied).call(outcome)).to eq(0)
        expect(send(spec.fetch(:untouched), env)).to be(true)
      end
    end

    # GRANT IDENTITY, WHICH TWENTY ROUNDS BOUND WITH NOTHING (FU-63 part 3, closing R20-1).
    #
    # `g.id = ra.id` is the join between the tuple the decision carried and the row the write
    # re-reads. Unbinding it at the queue write left this battery at 36 examples / 0 failures, and
    # driven at the store it QUEUED A CRAWL ON A REVOKED GRANT.
    #
    # WHY THE FOREIGN-ACCOUNT CASE ABOVE DOES NOT BIND IT. That grant belongs to another Account, so
    # it is refused by the principal conjunct; and its tuple differs from the actor's live grants in
    # VERSION and SCOPE anyway — `TenantSeeder` inserts state_version 0 with a NULL scope while the
    # bootstrap grant is state_version 1 with a scope digest — so with identity unbound the join
    # still finds no row. It discriminates the conjuncts it was written for and never reaches this
    # one.
    #
    # WHAT BINDS IT IS A COLLISION. The carried tuple names a REVOKED Assignment, and a LIVE sibling
    # of the SAME principal exists AT THE SAME VERSION AND THE SAME SCOPE. Every non-identity
    # conjunct is satisfied by the sibling, so identity is the only thing left that can refuse: with
    # `g.id = ra.id` the join reaches the revoked row and stops, without it the join reaches the
    # live one and the write applies. Two active grants at the same version is a PRODUCTION shape —
    # `invitation_store.rb:113` creates active grants at state_version 0.
    it "refuses a carried grant id that names a REVOKED Assignment, with a live sibling alongside it" do
      # BOTH SIBLINGS ARE ORDINARY STANDARD GRANTS OF THE ACTING ROLE. `one_active_assignment_per_tuple`
      # is a PARTIAL index over `status = 'active'`, so a revoked row may share the whole tuple with a
      # live one — which is what lets the pair differ in NOTHING but identity. The live sibling is
      # reused when the write's own setup already seeded one, because a second active row with that
      # tuple is exactly what the index forbids.
      role = acting_role(spec)
      live = existing_actor_grant(env, role) || seed_actor_grant(env, canonical_role: role)
      revoked = seed_actor_grant(env, canonical_role: role, status: "revoked",
                                      effective_at: start_now - 86_400)

      # NON-VACUITY, STATED AS THE CASE'S OWN PRECONDITION. The two rows must be indistinguishable
      # to every conjunct EXCEPT identity, or this proves something else.
      expect(revoked["id"]).not_to eq(live["id"])
      expect(revoked["state_version"]).to eq(live["state_version"]),
                                          "the siblings differ in VERSION, so the version conjunct would " \
                                          "refuse and identity would stay unbound"
      expect(revoked["scope_hex"]).to eq(live["scope_hex"]),
                                      "the siblings differ in SCOPE, so the scope conjunct would refuse " \
                                      "and identity would stay unbound"
      expect(grant_row(live["id"])).to be_present
      expect(DbInspector.one("SELECT status FROM role_assignments WHERE id = $1::uuid",
                             [live["id"]])["status"]).to eq("active")

      carried = AuthorityFixture.build(organization_id: env[:org], account_id: actor_account(env),
                                       capability: spec.fetch(:capability), grants: [revoked],
                                       required_role: spec.fetch(:required_role))

      outcome = drive(spec, env, carried)

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "the write authorised on a revoked grant because a live " \
                                                 "sibling satisfied the other conjuncts: `g.id = ra.id` is " \
                                                 "not binding the carried identity"
      expect(spec.fetch(:applied).call(outcome)).to eq(0)
      expect(send(spec.fetch(:untouched), env)).to be(true)
    end

    # THE WHOLE STATUS VOCABULARY, NOT ONE VALUE OF IT (FU-63 part 6, closing R20-5).
    #
    # `ra.status = 'active'` was bound against `revoked` alone. The sweep drives EVERY status the
    # column's CHECK constraint admits, each in the shape production really holds it, and the
    # statuses come from the database rather than from a list here — so a status added to the
    # constraint is covered without anybody remembering.
    #
    # ADR-133's R15-CONC-1 deadlock-freedom exemption rests on `DecideRoleAssignment`'s target being
    # `pending` and "filtered out before asking for a lock". That premise is now driven rather than
    # asserted in prose.
    it "refuses a grant held at ANY status the column admits other than `active`" do
      role = acting_role(spec)
      statuses = assignment_statuses
      expect(statuses).to include("active", "pending", "revoked"),
                          "the status vocabulary parsed to #{statuses.inspect}, so this sweep is not " \
                          "reading the real CHECK constraint"

      (statuses - ["active"]).each do |status|
        grant = seed_status_grant(env, status, canonical_role: role)
        carried = AuthorityFixture.build(organization_id: env[:org], account_id: actor_account(env),
                                         capability: spec.fetch(:capability), grants: [grant],
                                         required_role: spec.fetch(:required_role))

        outcome = drive(spec, env, carried)

        expect(outcome[:capability_authorized]).to be(false), "a `#{status}` grant authorised this write"
        expect(spec.fetch(:applied).call(outcome)).to eq(0)
        expect(send(spec.fetch(:untouched), env)).to be(true)
      end
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

  # ---- what the parameterisation makes equivalent, defended rather than assumed ----------------
  #
  # FU-63 part 2 puts each write in `WRITES` at its PRODUCTION `required_role`. Two mutation
  # survivors become EQUIVALENT under that parameterisation rather than unbound, and an equivalence
  # that rests on an unasserted premise is the false-record class ADR-124 was opened for. Each is
  # tied here to the exact repository fact that makes it equivalent, so it fails the moment that
  # fact changes.
  describe "the premises that classify the remaining survivors as equivalent" do
    # WHY WIDENING `allowed_roles` FOR `policy.crawl.manage` ALONE IS EQUIVALENT. At both policy
    # configurations `required_role` pins the grant to ONE canonical role, which is strictly
    # stronger than membership of the cell — so the cell conjunct cannot decide a case the scope
    # rule has not already decided. That holds only while EVERY production configuration carries a
    # non-nil `required_role`. `valid_scope_shape?` admits exactly `organization` and `project`, and
    # `SCOPE_ROLE` maps both; a third scope, or a nil value, restores the cell conjunct's
    # independent job at this write and this example is what says so.
    it "the two policy configurations are the whole of `SCOPE_ROLE`, and none of them is nil" do
      scope_role = Workflows::Wf005::Handlers::ActivateCrawlPolicy::SCOPE_ROLE

      expect(scope_role.keys).to match_array(%w[organization project])
      expect(scope_role.values).to all(be_a(String))
      expect(WRITES.values.select { |s| s[:capability] == "policy.crawl.manage" }
                          .map { |s| s.fetch(:required_role) })
        .to match_array(scope_role.values),
            "a production crawl-policy scope is not driven by this battery"
    end

    # WHY ADMITTING `pending` AT THE WRITE IS EQUIVALENT (R20-5). `ra.status = 'active'` and
    # `ra.effective_at IS NOT NULL` both refuse a pending row, because the database forbids a
    # pending row from being effective at all. The status sweep drives the case; this names the
    # constraint the equivalence rests on. Drop the CHECK and the survivor becomes a real gap.
    it "the database forbids an EFFECTIVE `pending` Assignment, which is what makes admitting it inert" do
      definition = DbInspector.one(<<~SQL)
        SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint
        WHERE conname = 'role_assignment_pending_is_not_effective'
      SQL

      expect(definition).not_to be_nil,
                                "`role_assignment_pending_is_not_effective` is gone, so a pending " \
                                "Assignment can now be effective and `ra.status = 'active'` is the " \
                                "only conjunct refusing it — the R20-5 survivor is no longer equivalent"
      expect(definition["def"]).to include("pending")
    end
  end
end
