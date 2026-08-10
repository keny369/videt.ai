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
# `wf005_capability_write_authority_spec.rb`).
#
# AND THE THIRD IS NOW ENFORCED (FU-61). `WRITES` is still WRITTEN by hand — a driver cannot be
# derived — but it is no longer BELIEVED by hand. It has moved to `spec/support/protected_writes.rb`
# so that something other than its own consumer can see it, and
# `spec/architecture/protected_write_completeness_spec.rb` derives the protected-write set from the
# repository — every statement carrying a `capability_authority` CTE — and fails when it is not
# exactly what the registry enumerates. A fourth protected write now fails that gate until it is
# registered, and fails this battery until it is drivable. `crawl.recover` is ratified in WF-005's
# Recovery Path and is not yet materialized, so that fourth write is scheduled work, not a
# hypothesis.
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

  # THE REGISTRY, NOT A LITERAL (FU-61). `ProtectedWrites::WRITES` carries each write's identity,
  # capability, production `required_role` and drivers; this file supplies the driver METHODS. It
  # lives outside this spec so `protected_write_completeness_spec.rb` can compare it against the
  # repository, which is the whole point: a list only its own consumer can see is a list nothing can
  # check.
  #
  # `ActivateCrawlPolicy` derives `required_role` from `SCOPE_ROLE[scope]`, and `valid_scope_shape?`
  # admits exactly `organization` and `project`, so BOTH policy rows in the registry are production
  # configurations and there is no third one. That totality is asserted, not assumed — see "the two
  # policy configurations are the whole of `SCOPE_ROLE`" at the foot of this file.
  WRITES = ProtectedWrites::WRITES

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
  # `scope_sha256` is a parameter for FU-2's containment case, which needs a grant whose SCOPE is the
  # only thing wrong with it. It cannot be moved either — the lifecycle guard freezes `scope_sha256`
  # after insert alongside the role and mode — so seeding is again the only way to build the row in
  # the shape production holds it. `one_active_assignment_per_tuple` includes the scope digest, so a
  # second active grant at the same role and mode with a DIFFERENT scope is a legal row.
  def seed_actor_grant(env, canonical_role:, permission_mode: "standard", persona: nil,
                       status: "active", effective_at: Time.utc(2026, 1, 1), expires_at: nil,
                       scope_sha256: nil)
    id = TenantSeeder.create_role_assignment(organization_id: env[:org], account_id: actor_account(env),
                                             canonical_role:, permission_mode:, persona:,
                                             status:, effective_at:, expires_at:, scope_sha256:)
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
  # `required_scope_hex` IS THREADED THROUGH FOR THE SAME REASON (FU-2, sited by FU-49). It is the
  # scope an Assignment must hold to contain the write's target, it differs between the two policy
  # configurations exactly as `required_role` does, and passing `nil` here would drive the production
  # builder at a configuration production never uses — which is precisely how R20-2's
  # `read_only_permitted` derivation stayed unbound at Project scope.
  def production_authority(env, capability, grant, required_role: nil, required_scope_hex: nil)
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
      IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:, capability:, required_role:,
                                                        required_scope_hex:)
    end
  end

  # The values `role_assignments.status` can hold, READ FROM THE DATABASE rather than listed here
  # (FU-63 part 6). A status added to the CHECK constraint joins the sweep below by itself; a
  # hand-written list would leave the new one untested and green.
  # The character class is `[a-z_]+` rather than `[a-z]+`: a status named `auto_expired` would not
  # match the narrower one, and the sweep would skip it SILENTLY — a derived population that quietly
  # drops a member is worse than a hand-written list, because it reads as complete.
  def assignment_statuses
    definition = DbInspector.one(<<~SQL)["def"]
      SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint
      WHERE conname = 'role_assignments_status_check'
    SQL
    parsed = definition.scan(/'([a-z_]+)'::text/).flatten.uniq
    # The parse is checked against the raw definition, so a regex that stopped matching a member
    # fails here instead of shrinking the sweep.
    expect(parsed.length).to eq(definition.scan(/'[^']+'::text/).length),
                             "the status vocabulary parsed to #{parsed.inspect} from #{definition}"
    parsed
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
                                                  required_role: spec.fetch(:required_role),
                                                  required_scope_hex: spec.fetch(:required_scope_hex))
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
    # THE ROLE A READ-ONLY GRANT CAN ACTUALLY BE HELD AT (FU-76's fixture consequence, disclosed).
    #
    # This case used to seed `acting_role(spec)` + `read_only` + `executive_buyer`, and at three of
    # the four configurations `acting_role` is `OrganizationAdmin` — a tuple
    # `ALLOWED_ROLE_MODE_PERSONA` DOES NOT CONTAIN. FU-76 added
    # `role_assignments_ratified_role_mode_persona`, so that row can no longer be inserted at all,
    # and the fixture that wrote it was writing a grant the ratified access policy forbids.
    #
    # THE REPAIR IS THE RATIFIED TUPLE, NOT A WEAKER CONSTRAINT. The policy defines exactly one
    # read-only tuple — `MarketingOperator` + `read_only` + `executive_buyer` — and it is DERIVED
    # here rather than written down, so a second read-only tuple entering the policy joins this case
    # by itself. The grant this now drives is one production could really produce, which is a
    # stronger fixture than the one it replaces.
    read_only_role =
      Platform::BaselineContent::ALLOWED_ROLE_MODE_PERSONA
      .select { |tuple| tuple["permission_mode"] == "read_only" }
      .map { |tuple| tuple["canonical_role"] }
      .find do |candidate|
        Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)).include?(candidate) &&
          [nil, candidate].include?(spec.fetch(:required_role))
      end

    if read_only_role
      it "refuses a READ-ONLY grant when the authority comes from the PRODUCTION BUILDER (R-ADV-2)" do
        # `MarketingOperator` is inside every one of the three ratified cells, so the ROLE qual passes
        # and the sixth column is the only thing that can refuse it. If `read_only_permitted` were
        # derived permissively for THIS capability, the write would authorise.
        #
        # AND IT IS SEEDED AT A ROLE THIS WRITE'S OWN CONFIGURATION ADMITS (FU-63 part 2, closing
        # R20-2's second survivor). `read_only_permitted` derived as `!required_role.nil?` is FALSE at
        # every organization-scope configuration and TRUE at Project scope, so the corpus stayed green
        # while A READ-ONLY EXECUTIVE BUYER ACTIVATED AN IMMUTABLE PROJECT-SCOPE CRAWL POLICY. At the
        # Project configuration the admitted role IS `MarketingOperator`, so the cell conjunct and the
        # scope rule both pass and the sixth column is the only thing that can refuse.
        grant = seed_actor_grant(env, canonical_role: read_only_role,
                                      permission_mode: "read_only", persona: "executive_buyer")
        expect(Platform::PermissionBaseline::CAPABILITIES.fetch(spec.fetch(:capability)))
          .to include(read_only_role),
              "the seeded role is outside this capability's cell, so the ROLE qual would refuse first " \
              "and this case would not bind the read-only derivation"
        expect([nil, read_only_role]).to include(spec.fetch(:required_role)),
                                         "the seeded role is not the one this scope demands, so " \
                                         "`required_role` would refuse first and the read-only " \
                                         "derivation would again be unbound"

        outcome = drive(spec, env, production_authority(env, spec.fetch(:capability), grant,
                                                        required_role: spec.fetch(:required_role),
                                                        required_scope_hex: spec.fetch(:required_scope_hex)))

        expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
        expect(outcome[:capability_authorized]).to be(false),
                                                   "a read-only grant spent this capability through the " \
                                                   "production builder, so the sixth column is not what " \
                                                   "`WriteAuthority.for` derives for it"
        expect(spec.fetch(:applied).call(outcome)).to eq(0)
        expect(send(spec.fetch(:untouched), env)).to be(true)
      end
    else
      # UNREACHABLE BY CONSTRUCTION, AND DERIVED RATHER THAN ASSERTED BY HAND (FU-76).
      #
      # This is the ORGANIZATION-scope policy configuration, whose `required_role` is
      # `OrganizationAdmin`, and the ratified policy pairs `read_only` with `MarketingOperator`
      # ALONE. So no read-only grant can hold the role this configuration demands, and the case
      # above has no legal row to drive: it is absent because the STATE IS IMPOSSIBLE, not because
      # anybody chose to skip it.
      #
      # That distinction is the whole point of writing this, and it is the same disclosure FU-59's
      # repair made when its guard rendered a `rejected` Assignment carrying protected authority
      # unreachable. If a future policy pairs `read_only` with this configuration's role, the branch
      # above takes over automatically and this example disappears.
      it "cannot hold a read-only grant at this configuration at all, which is why that case is absent" do
        read_only_roles = Platform::BaselineContent::ALLOWED_ROLE_MODE_PERSONA
                          .select { |tuple| tuple["permission_mode"] == "read_only" }
                          .map { |tuple| tuple["canonical_role"] }

        expect(read_only_roles).not_to be_empty,
                                       "the ratified policy defines NO read-only tuple at all, so the " \
                                       "sixth-column conjunct is unbound everywhere and the absence " \
                                       "above is hiding that rather than explaining it"
        expect(read_only_roles).not_to include(spec.fetch(:required_role)),
                                       "a read-only grant CAN hold #{spec.fetch(:required_role)}, so " \
                                       "the read-only case is being skipped at a configuration that " \
                                       "could drive it"

        # And the database agrees, rather than only the constant: the row this configuration would
        # need cannot be inserted.
        expect do
          seed_actor_grant(env, canonical_role: spec.fetch(:required_role),
                                permission_mode: "read_only", persona: "executive_buyer")
        end.to raise_error(PG::CheckViolation, /ratified_role_mode_persona/)
      end
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
                                         required_role: spec.fetch(:required_role),
                                         required_scope_hex: spec.fetch(:required_scope_hex))

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
                                         required_role: spec.fetch(:required_role),
                                         required_scope_hex: spec.fetch(:required_scope_hex))

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

  # ---- FU-2: THE ASSIGNMENT'S SCOPE MUST CONTAIN THE TARGET ------------------------------------
  #
  # WHY THIS IS NOT A SHARED EXAMPLE. Every case above is written once and run at all four
  # configurations, and that is right for a conjunct every configuration binds. THIS conjunct is
  # decisive at exactly ONE of them: `SCOPE_DIGEST` names a containment scope for an
  # ORGANIZATION-scope policy and `nil` everywhere else, because `role_assignments` stores the
  # grant's `GrantScope` only as a one-way digest and a Project-scope target has no single scope an
  # Assignment must hold. Run as a shared example it would pass at three configurations for the
  # reason it asserts nothing there — the vacuity this file exists to refuse — so it is written where
  # it discriminates, and what it does NOT cover is stated rather than implied by a green run.
  #
  # WHAT WAS EXPLOITABLE, MEASURED. `required_role` binds the ratified rule that an Organization-
  # scope policy demands an OrganizationAdmin. It says nothing about the scope that Admin's OWN
  # Assignment carries. An OrganizationAdmin whose grant is scoped to one Project satisfied every
  # limb of this CTE and activated an immutable ORGANIZATION-WIDE crawl policy, which ":732 affects
  # queued work immediately and running work at the next checkpoint".
  describe "the granting Assignment's scope contains the target (FU-2, sited by FU-49)" do
    let(:env) { setup_policy }
    let(:organization_scope) { IdentityAccess::Authorization::GrantAuthority::ORGANIZATION_SCOPE_HEX }
    # A digest that is a well-formed 32-byte scope and is NOT Organization scope: exactly what a
    # Project-scoped `GrantScope` hashes to as far as this statement can tell, since the statement
    # can read the digest and never the structure behind it.
    let(:project_scope_bytes) { Digest::SHA256.digest("scope:project:#{SecureRandom.uuid_v7}") }

    # The grant the exploit needs: the role the Organization scope demands, held at a scope that
    # does not contain an Organization-wide target. It is otherwise flawless — active, effective,
    # unexpired, the actor's own, inside the capability's cell, standard mode.
    def narrowly_scoped_admin
      grant = seed_actor_grant(env, canonical_role: "OrganizationAdmin",
                                    scope_sha256: project_scope_bytes)
      expect(grant["scope_hex"]).to eq(project_scope_bytes.unpack1("H*")),
                                    "the grant was not seeded at the narrow scope, so the case below " \
                                    "would be discriminated by something else"
      expect(grant["scope_hex"]).not_to eq(organization_scope),
                                        "the 'narrow' scope IS Organization scope, so the refusal " \
                                        "asserted below could not be about containment"
      grant
    end

    it "refuses an OrganizationAdmin whose own Assignment is scoped NARROWER than the target" do
      authority = production_authority(env, "policy.crawl.manage", narrowly_scoped_admin,
                                       required_role: "OrganizationAdmin",
                                       required_scope_hex: organization_scope)

      outcome = invoke_policy(env, authority)

      expect(outcome[:epoch_authorized]).to be(true), "the epoch was current; only the capability failed"
      expect(outcome[:capability_authorized]).to be(false),
                                                 "an Assignment scoped to one Project activated an " \
                                                 "immutable ORGANIZATION-wide crawl policy: the " \
                                                 "containment predicate is not a conjunct of this write"
      expect(outcome[:inserted]).to eq(0)
      expect(policy_untouched?(env)).to be(true)
    end

    # THE DISCRIMINATION, WHICH IS WHAT MAKES THE CASE ABOVE ABOUT CONTAINMENT AND NOTHING ELSE.
    # Same write, same grant, same `required_role`, same everything — only the containment operand
    # differs, and the outcome flips. This is deliberately a configuration production never passes
    # (`SCOPE_DIGEST` gives Organization scope wherever `SCOPE_ROLE` gives OrganizationAdmin); its
    # purpose is to hold the refusal above to ONE cause, and it is exactly the pre-FU-2 behaviour, so
    # it also records what was reachable before this conjunct existed.
    it "COMMITS the same grant at the same write when no containment scope is carried" do
      authority = production_authority(env, "policy.crawl.manage", narrowly_scoped_admin,
                                       required_role: "OrganizationAdmin", required_scope_hex: nil)

      outcome = invoke_policy(env, authority)

      expect(outcome[:capability_authorized]).to be(true),
                                                 "the grant is refused even with no containment claim, " \
                                                 "so the case above is discriminated by some OTHER " \
                                                 "conjunct and proves nothing about FU-2"
      expect(outcome[:inserted]).to eq(1)
    end

    # ORGANIZATION SCOPE CONTAINS AN ORGANIZATION-SCOPE TARGET, IN BOTH REPRESENTATIONS. The platform
    # spells Organization scope two ways — `GrantAuthority#contains_scope?` treats a NULL
    # `scope_hex` and `ORGANIZATION_SCOPE_HEX` alike, `TenantSeeder` writes NULL and WF-001's genesis
    # writes the digest — so a predicate agreeing with only one of them would refuse half the
    # platform's real grants while passing every case above. Each is driven at its own write.
    it "admits an Assignment carrying the Organization scope DIGEST" do
      # WF-001's genesis grant IS this representation — `BootstrapOrganization::ORG_SCOPE` writes the
      # digest — so the case reads the real production row rather than seeding a second copy of it.
      # It cannot seed one anyway: `one_active_assignment_per_tuple` includes the scope digest, and
      # measured here, a duplicate raises `PG::UniqueViolation`. That collision is itself the
      # evidence that this is the genesis representation and not a fixture's invention.
      grant = grant_row(DbInspector.one(<<~SQL, [env[:org], actor_account(env)])["id"])
        SELECT id FROM role_assignments
        WHERE organization_id = $1::uuid AND account_id = $2::uuid AND status = 'active'
          AND canonical_role = 'OrganizationAdmin' AND scope_sha256 IS NOT NULL
        ORDER BY id LIMIT 1
      SQL
      expect(grant["scope_hex"]).to eq(organization_scope)

      outcome = invoke_policy(env, production_authority(env, "policy.crawl.manage", grant,
                                                        required_role: "OrganizationAdmin",
                                                        required_scope_hex: organization_scope))

      expect(outcome[:capability_authorized]).to be(true),
                                                 "an Organization-scope grant was refused an " \
                                                 "Organization-scope target"
      expect(outcome[:inserted]).to eq(1)
    end

    it "admits an Assignment carrying a NULL scope, which is Organization scope spelled the other way" do
      grant = seed_actor_grant(env, canonical_role: "MarketingOperator", scope_sha256: nil)
      expect(grant["scope_hex"]).to eq(""),
                                    "the grant was seeded with a scope, so the NULL branch is untested"

      # MarketingOperator at PROJECT scope, whose `SCOPE_DIGEST` entry is `nil` — so this drives the
      # NULL-scope grant at the configuration that carries no containment claim AND at one that does,
      # below, rather than at only whichever happens to pass.
      outcome = invoke_policy(env, production_authority(env, "policy.crawl.manage", grant,
                                                        required_role: "MarketingOperator",
                                                        required_scope_hex: organization_scope))

      expect(outcome[:capability_authorized]).to be(true),
                                                 "a NULL-scope Assignment was refused: the predicate " \
                                                 "reads NULL as 'no scope' rather than as Organization " \
                                                 "scope, which would refuse most real grants"
      expect(outcome[:inserted]).to eq(1)
    end

    # WHAT THIS CONJUNCT DOES NOT DECIDE, ASSERTED RATHER THAN LEFT TO THE PROSE. FU-2's resource
    # limb stays open because a digest cannot answer "does this scope contain that project", and the
    # honest consequence is that a narrowly-scoped grant reaches a PROJECT-scope target unrefused by
    # this predicate. Asserting it means the day someone can name a Project target's scope, this
    # example fails and is deleted deliberately — rather than the gap surviving as a green suite.
    it "does NOT refuse a narrowly-scoped grant at a target whose scope the write cannot name" do
      env = setup_policy_project
      grant = TenantSeeder.create_role_assignment(
        organization_id: env[:org], account_id: actor_account(env),
        canonical_role: "MarketingOperator", scope_sha256: Digest::SHA256.digest("scope:elsewhere")
      ).then { |id| grant_row(id) }

      outcome = invoke_policy_project(env, production_authority(
        env, "policy.crawl.manage", grant,
        required_role: "MarketingOperator",
        required_scope_hex: ProtectedWrites::WRITES.fetch(
          "the policy activation at PROJECT scope (CrawlPolicyStore#activate_version)"
        ).fetch(:required_scope_hex)
      ))

      expect(outcome[:capability_authorized]).to be(true),
                                                 "the Project-scope configuration now refuses on " \
                                                 "containment, so FU-2's resource limb has been " \
                                                 "closed and this example must be replaced by the " \
                                                 "proof that closes it"
      expect(outcome[:inserted]).to eq(1)
    end
  end

  # THE OTHER DIRECTION OF FU-61'S GATE. `protected_write_completeness_spec.rb` fails when the
  # repository holds a protected write the registry does not name. This fails when the registry
  # names one THIS BATTERY CANNOT DRIVE — a registration whose drivers are missing or misspelled.
  #
  # Without it the two halves would not meet: a fourth write could be added to the registry to
  # silence the architecture gate while inheriting none of the twelve shared examples, which is
  # precisely the round-20 demonstration this follow-up exists to close. `send` on a missing symbol
  # raises inside a shared example at the first case that drives it, naming a `NoMethodError` rather
  # than an incomplete registration; this names it.
  it "can drive every write the registry enumerates, so registering one is not enough to satisfy the gate" do
    ProtectedWrites::WRITES.each do |name, spec|
      missing = ProtectedWrites::REQUIRED_MEMBERS.reject { |member| spec.key?(member) }
      expect(missing).to be_empty, "#{name} is registered without #{missing.join(', ')}"

      %i[setup invoke untouched].each do |role|
        expect(self).to respond_to(spec.fetch(role)),
                        "#{name} names `#{spec.fetch(role)}` as its #{role}, and this battery has no " \
                        "such method — the write is registered but undriven"
      end
      expect(spec.fetch(:applied)).to respond_to(:call)
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

      # AND THE SUBSUMPTION ITSELF, WHICH THE EQUIVALENCE ABOVE RESTS ON. `required_role` is stronger
      # than `allowed_roles` only while the role it pins is INSIDE the capability's cell: if
      # `SCOPE_ROLE` ever named a role the cell excludes, the two conjuncts would refuse different
      # sets and the cell would have an independent job at this write again. An equivalence resting
      # on an unasserted premise is the false-record class ADR-124 was opened for.
      expect(scope_role.values)
        .to all(be_in(Platform::PermissionBaseline::CAPABILITIES.fetch("policy.crawl.manage"))),
            "`SCOPE_ROLE` pins a role outside `policy.crawl.manage`'s ratified cell, so `allowed_roles` " \
            "is no longer subsumed by `required_role` at this write"
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
