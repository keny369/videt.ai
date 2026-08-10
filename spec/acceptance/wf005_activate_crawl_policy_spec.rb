# frozen_string_literal: true

require "rails_helper"

# WF-005 ActivateCrawlPolicy (S-07-001; contracts/S-07.json MTX-030 policy limb, MTX-059
# PRULE-008; WORKFLOW_SPECIFICATIONS.md § Interim Crawl Policy crawl-policy-v1 / policy subflow
# :732; DECISIONS ADR-068 owner D1 — dedicated crawl_policies table, frozen global ceiling).
#
# Narrowing-only crawl policy activation: an OrganizationAdmin narrows the Organization scope
# (parent = the frozen global ceiling), a MarketingOperator narrows a Project scope (parent =
# the active Organization policy, or global). Every value at or below parent AND global,
# soft <= hard, all twelve dimensions; a stale/broader/incomplete/unauthorized/mis-scoped
# activation changes nothing; activation supersedes the prior version; idempotent by key.
RSpec.describe "WF-005 activate crawl policy", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC] do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 27, 10, 0, 0)
  def act_now = fixed_now + 60
  def bc = Platform::BaselineContent
  def gceil = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
  def gver = Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  end
  def act_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def bootstrap
    grant = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(
      command: Workflows::Wf001::Commands::RequestBootstrapGrant.new(command_id: SecureRandom.uuid_v7, idempotency_key: "grant-#{SecureRandom.hex(4)}",
        schema_version: "1.0", receipt_digest: grant[:receipt_digest], requested_at_utc: fixed_now - 60), request_context: service_ctx(fixed_now - 60))
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    Workflows::Wf001::Handlers::BootstrapOrganization.new.call(
      command: Workflows::Wf001::Commands::BootstrapOrganization.new(command_id: SecureRandom.uuid_v7, idempotency_key: "boot-#{SecureRandom.hex(4)}", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0, organization_display_name: "Acme", first_project: GenesisProjectProfile.body("Genesis"), access_policy_content_sha256: bc.access_policy_sha256, entitlement_policy_content_sha256: bc.entitlement_policy_sha256,
        plan_content_sha256: bc.plan_sha256, requested_at_utc: fixed_now), request_context: service_ctx(fixed_now)).payload
  end

  def marketing_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "MarketingOperator",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end
  def ti_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "TechnicalImplementer",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end

  # The global ceiling as a plain string-keyed hash, deep-copied, with optional per-dimension
  # overrides (each override merges into that dimension's {soft,hard}).
  def bounds(overrides = {})
    b = gceil.to_h { |d, v| [d, v.dup] }
    overrides.each { |d, o| b[d] = b[d].merge(o) }
    b
  end

  def activate(session:, org:, scope:, bounds:, project_id: nil, expected_current: nil,
               expected_parent: gver, expected_global: gver, key: "acp-#{SecureRandom.hex(6)}")
    Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
      command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id: session,
        organization_id: org, scope:, project_id:, expected_current_policy_version: expected_current,
        expected_parent_policy_version: expected_parent, expected_global_version: expected_global,
        proposed_bounds: bounds, requested_at_utc: act_now), request_context: act_ctx)
  end

  def policies(org) = DbInspector.all("SELECT * FROM crawl_policies WHERE organization_id = $1::uuid ORDER BY created_at", [org])
  def events(type) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1", [type])

  describe "Organization-scope narrowing by an OrganizationAdmin" do
    it "activates a more restrictive version at or below the global ceiling and emits CrawlPolicyActivated" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))
      expect(result.success?).to be(true)
      expect(result.payload[:scope]).to eq("organization")
      expect(result.payload[:policy_version]).to eq("crawl-policy-organization-v1")

      rows = policies(g[:organization_id])
      expect(rows.size).to eq(1)
      expect(rows.first["state"]).to eq("active")
      expect(rows.first["project_id"]).to be_nil
      expect(JSON.parse(rows.first["normalized_bounds"])["accepted_pages"]).to eq("soft" => 5_000, "hard" => 6_000)
      expect(events("CrawlPolicyActivated").size).to eq(1)
    end

    it "supersedes the prior active version on a second activation (guarded by expected current version)" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
               bounds: bounds("crawl_depth" => { "soft" => 6, "hard" => 8 }))
      second = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("crawl_depth" => { "soft" => 4, "hard" => 5 }),
                        expected_current: "crawl-policy-organization-v1")
      expect(second.success?).to be(true)
      expect(second.payload[:policy_version]).to eq("crawl-policy-organization-v2")
      expect(second.payload[:superseded_policy_version]).to eq("crawl-policy-organization-v1")

      states = policies(g[:organization_id]).to_h { |r| [r["policy_version"], r["state"]] }
      expect(states).to eq("crawl-policy-organization-v1" => "superseded", "crawl-policy-organization-v2" => "active")
    end
  end

  describe "Project-scope narrowing by a MarketingOperator" do
    it "narrows the active Organization policy (parent)" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
               bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))
      result = activate(session: marketing_session(g[:organization_id]), org: g[:organization_id], scope: "project",
                        project_id: g[:project_id], bounds: bounds("accepted_pages" => { "soft" => 1_000, "hard" => 2_000 }),
                        expected_parent: "crawl-policy-organization-v1")
      expect(result.success?).to be(true)
      expect(result.payload[:scope]).to eq("project")
      expect(result.payload[:policy_version]).to eq("crawl-policy-project-v1")
    end

    it "rejects a project value broader than the active Organization parent" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
               bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))
      result = activate(session: marketing_session(g[:organization_id]), org: g[:organization_id], scope: "project",
                        project_id: g[:project_id], bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 8_000 }),
                        expected_parent: "crawl-policy-organization-v1")
      expect(result.failure.reason_code).to eq("crawl_policy_not_narrowing")
    end
  end

  describe "narrowing, completeness and version rejections change nothing" do
    it "rejects a value above the global hard ceiling as not narrowing" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("accepted_pages" => { "soft" => 8_000, "hard" => 11_000 }))
      expect(result.failure.reason_code).to eq("crawl_policy_not_narrowing")
      expect(policies(g[:organization_id])).to be_empty
    end

    it "rejects soft above hard" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("crawl_depth" => { "soft" => 9, "hard" => 8 }))
      expect(result.failure.reason_code).to eq("crawl_policy_soft_exceeds_hard")
    end

    it "rejects an incomplete proposal (a missing dimension)" do
      g = bootstrap
      b = bounds
      b.delete("sitemap_documents")
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: b)
      expect(result.failure.reason_code).to eq("crawl_policy_incomplete")
    end

    it "rejects a stale expected current version" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: bounds)
      stale = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                       bounds: bounds("crawl_depth" => { "soft" => 4, "hard" => 5 }), expected_current: nil)
      expect(stale.failure.reason_code).to eq("crawl_policy_stale_version")
      expect(policies(g[:organization_id]).count { |r| r["state"] == "active" }).to eq(1)
    end

    it "rejects a stale expected global version" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds, expected_global: "crawl-policy-v0-global")
      expect(result.failure.reason_code).to eq("crawl_policy_unavailable")
    end
  end

  describe "authorization and scope" do
    it "denies a TechnicalImplementer (no policy.crawl.manage)" do
      g = bootstrap
      result = activate(session: ti_session(g[:organization_id]), org: g[:organization_id], scope: "organization", bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
    end

    it "denies a MarketingOperator at Organization scope (Marketing narrows Project only)" do
      g = bootstrap
      result = activate(session: marketing_session(g[:organization_id]), org: g[:organization_id], scope: "organization", bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
    end

    it "denies an OrganizationAdmin at Project scope (Admin narrows Organization only)" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "project",
                        project_id: g[:project_id], bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
    end

    # FU-2, THROUGH THE PRODUCT RATHER THAN AT THE STORE (sited by FU-49).
    #
    # The three cases above all turn on the ROLE. This one turns on the SCOPE THE ROLE IS HELD AT,
    # which nothing checked: `SCOPE_ROLE["organization"]` demands an OrganizationAdmin and this actor
    # IS one. Measured before the repair, through this same handler: the activation SUCCEEDED and
    # `crawl_policies` gained an active Organization-wide row, which ":732 affects queued work
    # immediately and running work at the next checkpoint" and which `f1_crawl_policies_guard` makes
    # terminal once superseded.
    #
    # `wf005_grant_battery_spec.rb` proves the WRITE refuses whatever the caller does; this proves the
    # refusal is reachable in production, which is the difference between a defect and a property.
    it "denies an OrganizationAdmin whose own Assignment is scoped NARROWER than the target (FU-2)" do
      g = bootstrap
      # An actor whose ONLY grant is a Project-scoped OrganizationAdmin. The genesis Admin holds
      # Organization scope, so a narrowly-scoped principal has to be its own account for the decision
      # to carry the narrow grant and nothing else.
      narrow = TenantSeeder.seed_authorized_admin(organization_id: g[:organization_id],
                                                  canonical_role: nil, with_policy: false,
                                                  issued_at: fixed_now - 300)
      TenantSeeder.create_role_assignment(organization_id: g[:organization_id],
                                          account_id: narrow[:account_id],
                                          canonical_role: "OrganizationAdmin",
                                          scope_sha256: Digest::SHA256.digest("scope:project:#{g[:project_id]}"))

      result = activate(session: narrow[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds)

      # THE DECIDING VALUE FIRST, so a regression fails on this assertion rather than on a
      # `NoMethodError` from reading `failure` off a success — which would be weaker evidence about
      # a repair that is precisely about whether this activation happens.
      expect(result.success?).to be(false),
                                 "a Project-scoped OrganizationAdmin activated an immutable " \
                                 "Organization-wide crawl policy through the production handler"
      expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
      expect(policies(g[:organization_id])).to be_empty
    end
  end

  describe "idempotency and tenant isolation" do
    it "replays an exact activation by its key and creates no second version" do
      g = bootstrap
      first = activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: bounds, key: "same")
      second = activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: bounds, key: "same")
      expect(second.replayed).to be(true)
      expect(second.payload[:policy_version]).to eq(first.payload[:policy_version])
      expect(policies(g[:organization_id]).size).to eq(1)
    end

    it "refuses a command whose organization_id is not the actor's" do
      g = bootstrap
      result = activate(session: g[:session_id], org: SecureRandom.uuid_v7, scope: "organization", bounds: bounds)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
    end

    it "refuses (and audits) a scope/project_id mismatch as crawl_policy_scope_invalid" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        project_id: g[:project_id], bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_scope_invalid")
      audited = DbInspector.all("SELECT id FROM audit_record_registry WHERE reason_code='crawl_policy_scope_invalid' AND outcome='failure'")
      expect(audited).not_to be_empty
    end
  end

  # AUTHORITY IS A CONJUNCT OF THE ACTIVATION STATEMENT (D6; supersedes PROOF 193 for this handler).
  #
  # The transition is two writes — supersede the prior active version, insert the new one — and the
  # one-active-per-scope index makes a half-applied transition a corrupt scope. They are now data-
  # modifying CTEs in ONE statement sharing ONE evaluation of the authority predicate, so PostgreSQL
  # applies both or neither and a revocation landing between them is not expressible.
  describe "write-level authority" do
    def revoke!(org)
      DbInspector.one("UPDATE organizations SET authorization_epoch = authorization_epoch + 1 " \
                      "WHERE id = $1::uuid RETURNING authorization_epoch", [org])
    end

    def active_rows(org) = policies(org).select { |r| r["state"] == "active" }

    # A REAL RACER: the revocation lands after the handler has taken its per-scope lock and before the
    # activation statement runs — the interleaving the invariant exists for.
    def revoke_during_wait(org)
      fired = false
      hook = Module.new do
        define_method(:activate_version) do |row|
          unless fired
            fired = true
            DbInspector.one("UPDATE organizations SET authorization_epoch = authorization_epoch + 1 " \
                            "WHERE id = $1::uuid RETURNING authorization_epoch", [row[:organization_id]])
          end
          super(row)
        end
      end
      IdentityAccess::Infrastructure::CrawlPolicyStore.prepend(hook)
      yield
    ensure
      fired = true
    end

    it "PROOF 226 — authority current and state eligible: the version activates" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))

      expect(result.success?).to be(true)
      expect(active_rows(g[:organization_id]).length).to eq(1)
    end

    it "PROOF 227 — revoked while the handler waits: NEITHER write applies" do
      # THE PARTIAL-TRANSITION CASE, which is why this is one statement. If the supersede could commit
      # while the insert was denied, the scope would be left with nothing active — a corrupt state no
      # domain outcome describes.
      g = bootstrap
      first = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                       bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))
      expect(first.success?).to be(true)
      before = policies(g[:organization_id]).map { |r| [r["id"], r["state"]] }.to_h
      def orphan_executions(org)
        # A `command_executions` row naming a `crawl_policy` that does not exist. The denial's own
        # row legitimately names the scope resource (the organization or project), so those are not
        # orphans — the defect is a row pointing at a POLICY id for a policy that was never created.
        DbInspector.all(<<~SQL, [org]).map { |r| r["target_id"] }
          SELECT e.target_id FROM command_executions e
          WHERE e.organization_id = $1::uuid AND e.target_id IS NOT NULL
            AND e.target_id <> $1::uuid
            AND NOT EXISTS (SELECT 1 FROM projects p WHERE p.id = e.target_id)
            AND NOT EXISTS (SELECT 1 FROM crawl_policies p WHERE p.id = e.target_id)
        SQL
      end
      orphans_before = orphan_executions(g[:organization_id])

      result = revoke_during_wait(g[:organization_id]) do
        activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                 bounds: bounds("accepted_pages" => { "soft" => 4_000, "hard" => 5_000 }),
                 expected_current: "crawl-policy-organization-v1")
      end

      expect(result).not_to be_success
      after = policies(g[:organization_id]).map { |r| [r["id"], r["state"]] }.to_h
      expect(after).to eq(before), "the activation partly applied: #{before.inspect} -> #{after.inspect}"
      expect(active_rows(g[:organization_id]).length).to eq(1),
             "the scope was left without exactly one active version"

      # AND THE DURABLE SECURITY LEDGER RECORDS NOTHING ABOUT A TRANSITION THAT DID NOT HAPPEN.
      # The ledger writes used to precede the guarded write, and this branch returns rather than
      # raising, so a revocation during the wait committed a `command_executions` row pointing at a
      # `crawl_policy` id that does not exist and an immutable `authorization_decisions` row recording
      # `allow`/`authorized` about it.
      expect(orphan_executions(g[:organization_id]) - orphans_before).to be_empty,
             "the refused activation committed a command_execution naming a crawl_policy that was " \
             "never created; the durable security ledger records a transition that did not happen"
    end

    it "PROOF 228 — the store refuses a stale epoch when invoked DIRECTLY by another caller" do
      g = bootstrap
      current = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id=$1::uuid",
                                [g[:organization_id]])["authorization_epoch"].to_i
      revoke!(g[:organization_id])

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id], project_id: nil,
          authority: AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage",
                                                  epoch: current),
          scope: "organization", policy_version: "crawl-policy-organization-v9",
          supersedes_id: nil, expected_state_version: nil,
          activated_by_account_id: nil, normalized_bounds: gceil, content_sha256: "\x00" * 32
        )
      end

      expect(outcome[:authorized]).to be(false)
      expect(outcome[:epoch_authorized]).to be(false)
      expect(outcome[:capability_authorized]).to be(true)
      expect(outcome[:inserted]).to eq(0)
      expect(outcome[:superseded]).to eq(0)
      expect(policies(g[:organization_id])).to be_empty
    end

    it "PROOF 229 — a lost serialized transition is raised, not reported as a denial" do
      # The two zero-row cases are opposite events. Authority that moved is a domain denial; a prior
      # version that would not supersede is corruption the handler must raise on. Collapsing them
      # would swallow a lost race as a polite refusal.
      g = bootstrap
      expect(activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                      bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 })).success?).to be(true)
      current = policies(g[:organization_id]).find { |r| r["state"] == "active" }

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id=$1::uuid",
                                [g[:organization_id]])["authorization_epoch"].to_i
        IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id], project_id: nil,
          authority: AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage",
                                                  epoch:),
          scope: "organization", policy_version: "crawl-policy-organization-v2",
          supersedes_id: current["id"], expected_state_version: 9999,
          activated_by_account_id: nil, normalized_bounds: gceil, content_sha256: "\x00" * 32
        )
      end

      expect(outcome[:authorized]).to be(true), "authority was current; this is not a denial"
      expect(outcome[:superseded]).to eq(0), "the stale version did not supersede"
      expect(outcome[:inserted]).to eq(0), "and the insert did not apply without it"
      expect(active_rows(g[:organization_id]).length).to eq(1), "the scope still has exactly one active"
    end

    it "PROOF 231 — a supersedes_id from ANOTHER SCOPE supersedes nothing" do
      # THE CORRUPTION PATH THE CONCURRENCY LENS FOUND. The supersede CTE matched on `id` alone, so a
      # `supersedes_id` naming another scope's active version superseded THAT scope while activating
      # this one — reporting {authorized: true, superseded: 1, inserted: 1}, a fully successful
      # transition by every signal the caller has, and leaving the other scope with ZERO active
      # versions. `f1_crawl_policies_guard` makes a superseded row terminal, so it cannot be restored.
      #
      # RLS barred the cross-TENANT case; nothing barred the cross-SCOPE one. The store must hold its
      # own contract rather than depend on the single caller that happens to derive the id correctly —
      # which is the whole point of moving the invariant into the write.
      g = bootstrap
      expect(activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                      bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 })).success?).to be(true)
      org_active = policies(g[:organization_id]).find { |r| r["state"] == "active" }

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id=$1::uuid",
                                [g[:organization_id]])["authorization_epoch"].to_i
        IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id],
          authority: AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage",
                                                  epoch:),
          project_id: g[:project_id], scope: "project",
          policy_version: "crawl-policy-project-v1",
          supersedes_id: org_active["id"], expected_state_version: org_active["state_version"].to_i,
          activated_by_account_id: nil, normalized_bounds: gceil, content_sha256: "\x00" * 32
        )
      end

      expect(outcome[:superseded]).to eq(0), "another scope's active version was superseded"
      expect(outcome[:inserted]).to eq(0), "the insert applied without its supersede"
      still_active = policies(g[:organization_id]).select { |r| r["state"] == "active" }
      expect(still_active.map { |r| r["scope"] }).to eq(["organization"]),
             "the organization scope was left without an active version"
    end

    it "PROOF 230 — a retry after a committed activation follows the idempotency contract" do
      g = bootstrap
      key = "acp-retry-#{SecureRandom.hex(4)}"
      args = { session: g[:session_id], org: g[:organization_id], scope: "organization",
               bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }), key: key }

      first = activate(**args)
      second = activate(**args)

      expect(first.success?).to be(true)
      expect(second.success?).to be(true), "a retry of a committed activation must replay"
      expect(policies(g[:organization_id]).length).to eq(1), "the retry activated a second version"
    end
  end
end
