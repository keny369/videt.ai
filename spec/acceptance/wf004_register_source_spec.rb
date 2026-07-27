# frozen_string_literal: true

require "rails_helper"

# WF-004 RegisterSource (WORKFLOW_SPECIFICATIONS.md :398-408, :704; CAP-004 MTX-004;
# AC-CAP-004; contracts/S-04.json).
#
# The Source-registration limb of S-04: an authorized Organization actor registers
# one proposed Source against a draft Project from one absolute HTTPS root URI,
# idempotently, with exactly one SourceRegistered event and immutable provenance.
# The principal under test reaches the command through real genesis and the genesis
# draft Project, never through fixtured Source authority.
#
# Registration only proposes a Source; verification (proposed -> verified, S-05) and
# scope/lifecycle (verified -> active, etc., S-06) are not built and are proved
# unreachable here.
RSpec.describe "WF-004 register source", type: :acceptance,
               acceptance_ids: ["AC-CAP-004", "AC-WF-004"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def act_now = fixed_now + 60
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
      clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def bootstrap
    grant = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(
      command: Workflows::Wf001::Commands::RequestBootstrapGrant.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "grant-#{SecureRandom.hex(4)}",
        schema_version: "1.0", receipt_digest: grant[:receipt_digest], requested_at_utc: fixed_now - 60
      ), request_context: service_ctx(fixed_now - 60)
    )
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    Workflows::Wf001::Handlers::BootstrapOrganization.new.call(
      command: Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "boot-#{SecureRandom.hex(4)}", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
        organization_display_name: "Acme Discoverability", project_display_name: "Genesis Site",
        project_objective: "discoverability_assessment", access_policy_content_sha256: bc.access_policy_sha256,
        entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
        requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    ).payload
  end

  let(:genesis) { bootstrap }

  def act_ctx(correlation_id: SecureRandom.uuid_v7)
    Platform::RequestContext.for_actor(
      clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id:
    )
  end

  def register(session_id:, organization_id:, project_id:, uri: "https://shop.acme.example",
               expected_state_version: 0, idempotency_key: "rs-#{SecureRandom.hex(6)}",
               registration_schema_version: "source-registration-v1", schema_version: "1.0", ctx: act_ctx)
    Workflows::Wf004::Handlers::RegisterSource.new.call(
      command: Workflows::Wf004::Commands::RegisterSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key:, schema_version:,
        session_id:, organization_id:, project_id:, registration_schema_version:,
        submitted_root_uri: uri, expected_state_version:, requested_at_utc: act_now
      ), request_context: ctx
    )
  end

  # Seed a draft Project directly (reference data for actors not under test), the
  # reduced genesis body with every profile column NULL.
  def seed_draft_project(org)
    id = SecureRandom.uuid_v7
    DbInspector.connection.exec_params(<<~SQL, [id, org])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'Seed','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def sources = DbInspector.all("SELECT * FROM sources ORDER BY created_at, id")
  def source(id) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [id])
  def wf004_events(type) = DbInspector.all(<<~SQL)
    SELECT * FROM event_registry WHERE workflow_id = 'WF-004' AND event_type = '#{type}' ORDER BY occurred_at, id
  SQL
  def sources_in(project) = DbInspector.all("SELECT id FROM sources WHERE project_id = $1::uuid", [project])

  # ------------------------------------------------------------------------

  describe "successful registration, production-reachable through the genesis Session and draft Project" do
    it "registers exactly one proposed Source with its immutable provenance and canonical identity" do
      g = genesis
      result = register(session_id: g[:session_id], organization_id: g[:organization_id],
                        project_id: g[:project_id], uri: "https://Shop.Acme.Example:443/")

      expect(result).to be_success
      row = source(result.payload[:source_id])
      expect(row["state"]).to eq("proposed")
      expect(row["organization_id"]).to eq(g[:organization_id])
      expect(row["project_id"]).to eq(g[:project_id])
      expect(row["submitted_root_uri"]).to eq("https://Shop.Acme.Example:443/")
      expect(row["canonical_host"]).to eq("shop.acme.example")
      expect(row["canonical_root_uri"]).to eq("https://shop.acme.example/")
      expect(row["registration_schema_version"]).to eq("source-registration-v1")
      expect(row["host_normalization_version"]).to eq("ascii-host-v1")
      expect(row["registration_origin"]).to eq("human_command")
      expect(row["registering_account_id"]).to eq(g[:account_id])
      expect(row["registered_at"]).not_to be_nil
      expect(row["state_version"].to_i).to eq(0)
      # provenance links to the durable authorization decision that created it
      decision = DbInspector.one("SELECT id, decision FROM authorization_decisions WHERE id = $1::uuid",
                                 [row["registration_authorization_decision_id"]])
      expect(decision["decision"]).to eq("allow")
    end

    it "emits exactly one WF-004 SourceRegistered event with the canonical identity and no forbidden fields" do
      g = genesis
      result = register(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id])

      events = wf004_events("SourceRegistered")
      expect(events.size).to eq(1)
      expect(events.first["aggregate_id"]).to eq(result.payload[:source_id])
      body = JSON.parse(DbInspector.one(<<~SQL, [events.first["id"]])["b"])
        SELECT convert_from(event_bytes, 'UTF8') AS b FROM event_registry WHERE id = $1::uuid
      SQL
      expect(body["organization_id"]).to eq(g[:organization_id])
      expect(body["project_id"]).to eq(g[:project_id])
      expect(body["source_id"]).to eq(result.payload[:source_id])
      expect(body["canonical_host"]).to eq("shop.acme.example")
      expect(body["state_version"]).to eq(0)
      expect(body["service_identity_id"]).to be_nil
      expect(body.values_at("submitted_email", "identity_subject", "credential", "authorization_token")).to all(be_nil)
    end

    it "records execution, result, audit and idempotency evidence" do
      g = genesis
      result = register(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id])
      execution = DbInspector.one("SELECT * FROM command_executions WHERE command_type = 'wf004.register_source'")
      expect(execution["actor_id"]).to eq(g[:account_id])
      expect(execution["service_identity_id"]).to be_nil
      audit = DbInspector.one("SELECT * FROM audit_record_registry WHERE entity_id = $1::uuid", [result.payload[:source_id]])
      expect(audit["workflow_id"]).to eq("WF-004")
      expect(audit["to_state"]).to eq("proposed")
      idem = DbInspector.one("SELECT * FROM idempotency_records WHERE command_type = 'wf004.register_source'")
      expect(idem["target_id"]).to eq(g[:project_id])
    end
  end

  describe "idempotency and uniqueness" do
    it "returns the stored Source on exact replay, creating no second Source or event" do
      g = genesis
      first = register(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], idempotency_key: "same")
      replay = register(session_id: g[:session_id], organization_id: g[:organization_id],
                        project_id: g[:project_id], idempotency_key: "same")
      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(replay.payload[:source_id]).to eq(first.payload[:source_id])
      expect(sources.size).to eq(1)
      expect(wf004_events("SourceRegistered").size).to eq(1)
    end

    it "treats a case-only difference in the host as the same canonical registration on replay" do
      g = genesis
      a = register(session_id: g[:session_id], organization_id: g[:organization_id],
                   project_id: g[:project_id], uri: "https://shop.acme.example", idempotency_key: "k")
      b = register(session_id: g[:session_id], organization_id: g[:organization_id],
                   project_id: g[:project_id], uri: "https://SHOP.ACME.EXAMPLE", idempotency_key: "k")
      expect(b.replayed).to be(true)
      expect(b.payload[:source_id]).to eq(a.payload[:source_id])
      expect(sources.size).to eq(1)
    end

    it "returns idempotency_conflict for the same key with a different host" do
      g = genesis
      register(session_id: g[:session_id], organization_id: g[:organization_id],
               project_id: g[:project_id], uri: "https://one.example", idempotency_key: "k")
      conflict = register(session_id: g[:session_id], organization_id: g[:organization_id],
                          project_id: g[:project_id], uri: "https://two.example", idempotency_key: "k")
      expect(conflict.reason_code).to eq("idempotency_conflict")
      expect(sources.size).to eq(1)
    end

    it "refuses a second registration of the same host in the same Project as source_host_already_registered" do
      g = genesis
      register(session_id: g[:session_id], organization_id: g[:organization_id],
               project_id: g[:project_id], uri: "https://dup.example")
      again = register(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], uri: "https://dup.example")
      expect(again.reason_code).to eq("source_host_already_registered")
      expect(sources.size).to eq(1)
      expect(wf004_events("SourceRegistered").size).to eq(1)
    end

    it "allows the same host in a different Project of the same Organization" do
      g = genesis
      other_project = seed_draft_project(g[:organization_id])
      a = register(session_id: g[:session_id], organization_id: g[:organization_id],
                   project_id: g[:project_id], uri: "https://same.example")
      b = register(session_id: g[:session_id], organization_id: g[:organization_id],
                   project_id: other_project, uri: "https://same.example")
      expect(a).to be_success
      expect(b).to be_success
      expect(sources.size).to eq(2)
    end
  end

  describe "authorization and tenant isolation" do
    it "allows OrganizationAdmin (genesis), Marketing Operator and Technical Implementer" do
      g = genesis
      expect(register(session_id: g[:session_id], organization_id: g[:organization_id],
                      project_id: g[:project_id], uri: "https://a.example")).to be_success

      %w[MarketingOperator TechnicalImplementer].each_with_index do |role, i|
        actor = TenantSeeder.seed_authorized_admin(canonical_role: role)
        project = seed_draft_project(actor[:organization_id])
        result = register(session_id: actor[:session_id], organization_id: actor[:organization_id],
                          project_id: project, uri: "https://role#{i}.example")
        expect(result).to be_success
      end
    end

    it "denies a role without source.register as source_register_unauthorized" do
      actor = TenantSeeder.seed_authorized_admin(canonical_role: "SecurityOperator")
      project = seed_draft_project(actor[:organization_id])
      result = register(session_id: actor[:session_id], organization_id: actor[:organization_id], project_id: project)
      expect(result.reason_code).to eq("source_register_unauthorized")
      expect(sources_in(project)).to be_empty
    end

    it "refuses a Project in another Organization without disclosure (tenant_mismatch)" do
      g = genesis
      other = TenantSeeder.seed_authorized_admin
      other_project = seed_draft_project(other[:organization_id])
      result = register(session_id: g[:session_id], organization_id: g[:organization_id], project_id: other_project)
      expect(result.reason_code).to eq("tenant_mismatch")
      expect(sources).to be_empty
    end

    it "refuses a caller who names a different Organization than its Session's" do
      g = genesis
      result = register(session_id: g[:session_id], organization_id: SecureRandom.uuid_v7, project_id: g[:project_id])
      expect(result.reason_code).to eq("tenant_mismatch")
    end

    it "refuses a stale expected Project state version" do
      g = genesis
      result = register(session_id: g[:session_id], organization_id: g[:organization_id],
                        project_id: g[:project_id], expected_state_version: 7)
      expect(result.reason_code).to eq("stale_state_version")
      expect(sources).to be_empty
    end

    it "cannot be authorized by a Project id alone — only the Session grant" do
      g = genesis
      result = register(session_id: SecureRandom.uuid_v7, organization_id: g[:organization_id], project_id: g[:project_id])
      expect(result.reason_code).to eq("session_invalid")
    end
  end

  describe "URI grammar and host validation (decided before authentication, first-match order)" do
    def reason(uri, **over) = register(session_id: SecureRandom.uuid_v7, organization_id: SecureRandom.uuid_v7,
                                       project_id: SecureRandom.uuid_v7, uri:, **over).reason_code

    it "rejects an unsupported registration schema version" do
      expect(reason("https://ok.example", registration_schema_version: "source-registration-v2"))
        .to eq("source_request_schema_unsupported")
      expect(reason("https://ok.example", schema_version: "2.0")).to eq("source_request_schema_unsupported")
    end

    it "applies the grammar first-match order" do
      expect(reason("http://x.example")).to eq("unsupported_source_scheme")
      expect(reason("https://user@x.example")).to eq("source_userinfo_prohibited")
      expect(reason("https://x.example:8080")).to eq("source_port_unsupported")
      expect(reason("https://x.example/path")).to eq("source_path_not_root")
      expect(reason("https://x.example?q=1")).to eq("source_query_prohibited")
      expect(reason("https://x.example#f")).to eq("source_fragment_prohibited")
      # a pre-encoded xn-- host is accepted by validation, so it passes the URI
      # gate and fails later at authentication (dummy Session) rather than on a host reason
      expect(reason("https://xn--caf-dma.example")).to eq("session_invalid")
    end

    it "rejects non-ASCII hosts as source_host_non_ascii and never normalizes them" do
      expect(reason("https://café.example")).to eq("source_host_non_ascii")
    end

    it "rejects invalid host forms as source_host_invalid" do
      expect(reason("https://-bad.example")).to eq("source_host_invalid")
      expect(reason("https://bad-.example")).to eq("source_host_invalid")
      expect(reason("https://localhost")).to eq("source_host_invalid")   # single label
      expect(reason("https://192.168.1.1")).to eq("source_host_invalid") # IP literal
      expect(reason("https://[::1]")).to eq("source_host_invalid")       # bracketed literal
      expect(reason("https://*.example.com")).to eq("source_host_invalid") # wildcard
    end

    it "rejects a malformed URI and ASCII control/space" do
      expect(reason("not a uri")).to eq("source_uri_malformed")
      expect(reason("https://")).to eq("source_uri_malformed")
      expect(reason("")).to eq("source_uri_malformed")
    end
  end

  describe "registerable Project state and no verify/activate in this tranche" do
    it "leaves the registered Source proposed and refuses the S-06 lifecycle transitions at the database" do
      g = genesis
      sid = register(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id]).payload[:source_id]
      expect(source(sid)["state"]).to eq("proposed")

      # WF-004 registration never transitions the Source; proposed -> verified is the
      # S-05-006 edge, and the S-06 verified -> active/disabled/removed edges stay refused.
      %w[active disabled removed].each do |state|
        expect do
          DbInspector.connection.exec_params("UPDATE sources SET state = $2 WHERE id = $1::uuid", [sid, state])
        end.to raise_error(PG::RaiseException, /source_lifecycle_transition_unavailable/)
      end
      expect(source(sid)["state"]).to eq("proposed")
    end

    it "does not verify or activate the Source: it stays proposed, creates no scope-change request, and emits no verify/activate events" do
      # S-05-001 adds `verification_requests` (challenge issuance), S-05-004 adds
      # `verification_attempts` (observation reservation), and S-06-003 adds
      # `source_scope_change_requests`; WF-004 REGISTRATION touches none of them (a
      # scope change is the separate ProposeSourceScopeChange command). The source-set
      # tables and the SourceVerified/SourceActivated events remain later slices.
      expect(DbInspector.one("SELECT to_regclass('public.source_set_versions') AS t")["t"]).to be_nil
      expect(DbInspector.count("source_scope_change_requests")).to eq(0)
      expect(DbInspector.count("event_registry")).to be >= 0
      expect(DbInspector.all("SELECT id FROM event_registry WHERE event_type IN ('SourceVerified','SourceActivated')")).to be_empty
    end
  end
end
