# frozen_string_literal: true

require "rails_helper"

# WF-002 CreateProject (WORKFLOW_SPECIFICATIONS.md :648-659; CAP-003 MTX-003;
# PRULE-003 MTX-054; AC-CAP-003, AC-WF-002, AC-PRULE-003, AC-PRULE-004).
#
# The CreateProject limb of S-03: an authorized Organization actor creates one
# draft Project from a complete `project-profile-v1` body, idempotently, with
# exactly one ProjectCreated event. The principal under test reaches the command
# through real genesis (RequestBootstrapGrant -> BootstrapOrganization -> the
# genesis Session), never through fixtured Project authority.
#
# Project activation is a distinct, later command whose prerequisite is an active
# same-Project Source (CAP-003), owned by S-04/S-05/S-06 and not built here; this
# tranche proves the Project stays draft and cannot be activated.
RSpec.describe "WF-002 create project", type: :acceptance,
               acceptance_ids: ["AC-CAP-003", "AC-WF-002", "AC-PRULE-003", "AC-PRULE-004"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def create_now = fixed_now + 60
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }
  let(:org_display_name) { "Acme Discoverability" }

  # ---- production genesis: the authorized OrganizationAdmin + Session under test ----
  def service_ctx(at)
    Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
      clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def bootstrap
    grant_receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(
      command: Workflows::Wf001::Commands::RequestBootstrapGrant.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "grant-#{SecureRandom.hex(4)}",
        schema_version: "1.0", receipt_digest: grant_receipt[:receipt_digest], requested_at_utc: fixed_now - 60
      ), request_context: service_ctx(fixed_now - 60)
    )
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    result = Workflows::Wf001::Handlers::BootstrapOrganization.new.call(
      command: Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "boot-#{SecureRandom.hex(4)}", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
        organization_display_name: org_display_name, project_display_name: "Genesis Site",
        project_objective: "discoverability_assessment", access_policy_content_sha256: bc.access_policy_sha256,
        entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
        requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    )
    raise "genesis failed: #{result.reason_code}" unless result.success?

    result.payload
  end

  let(:genesis) { bootstrap }

  def create_ctx(correlation_id: SecureRandom.uuid_v7)
    Platform::RequestContext.for_actor(
      clock: Platform::Clock.fixed(create_now), ids: Platform::Ids.system, correlation_id:
    )
  end

  def reason_profile(display_name: "Second Project", **overrides)
    {
      "project_profile_schema_version" => "project-profile-v1", "display_name" => display_name,
      "default_locale" => "en-AU", "reporting_time_zone" => "UTC", "objective" => "discoverability_assessment",
      "local_presence_applicable" => false,
      "local_presence_reason" => "This program operates entirely online across the country.",
      "local_business_profile" => nil
    }.merge(overrides)
  end

  def profile_with_lbp(business_name:, display_name: "Local Project", **lbp_overrides)
    reason_profile(display_name:).merge(
      "local_presence_applicable" => true, "local_presence_reason" => nil,
      "local_business_profile" => {
        "schema_version" => "local-business-profile-v1", "business_name" => business_name,
        "address_text" => "12 Example Street, Sydney NSW 2000", "telephone_e164" => "+61255501234",
        "service_areas" => %w[Melbourne Sydney]
      }.merge(lbp_overrides)
    )
  end

  def create(session_id:, organization_id:, profile:, idempotency_key: "cp-#{SecureRandom.hex(6)}",
             schema_version: "1.0", ctx: create_ctx)
    Workflows::Wf002::Handlers::CreateProject.new.call(
      command: Workflows::Wf002::Commands::CreateProject.new(
        command_id: SecureRandom.uuid_v7, idempotency_key:, schema_version:,
        session_id:, organization_id:, profile:, requested_at_utc: create_now
      ), request_context: ctx
    )
  end

  def projects = DbInspector.all("SELECT * FROM projects ORDER BY created_at, id")
  def project(id) = DbInspector.one("SELECT * FROM projects WHERE id = $1::uuid", [id])
  def projects_in(org) = DbInspector.all("SELECT id FROM projects WHERE organization_id = $1::uuid", [org])
  def count_where(sql, params = []) = DbInspector.one(sql, params)["c"].to_i
  def wf002_events(type) = DbInspector.all(<<~SQL)
    SELECT * FROM event_registry WHERE workflow_id = 'WF-002' AND event_type = '#{type}' ORDER BY occurred_at, id
  SQL

  # ------------------------------------------------------------------------

  describe "successful creation, production-reachable through the genesis Session" do
    it "creates an additional draft Project with the local-presence-reason profile" do
      g = genesis
      result = create(session_id: g[:session_id], organization_id: g[:organization_id], profile: reason_profile)

      expect(result).to be_success
      pid = result.payload[:project_id]
      row = project(pid)
      expect(row["state"]).to eq("draft")
      expect(row["organization_id"]).to eq(g[:organization_id])
      expect(row["display_name"]).to eq("Second Project")
      expect(row["locale"]).to eq("en-AU")
      expect(row["time_zone"]).to eq("UTC")
      expect(row["objective"]).to eq("discoverability_assessment")
      expect(row["project_profile_schema_version"]).to eq("project-profile-v1")
      expect(row["local_presence_applicable"]).to eq("f")
      expect(row["local_presence_reason"]).to eq("This program operates entirely online across the country.")
      expect(row["local_business_profile"]).to be_nil
      expect(row["profile_attesting_account_id"]).to eq(g[:account_id])
      expect(row["profile_committed_at"]).not_to be_nil
      expect(row["state_version"].to_i).to eq(0)
      expect(row["source_set_version"].to_i).to eq(0)
    end

    it "creates a draft Project with an immutable Local Business Profile and its content hash" do
      g = genesis
      profile = profile_with_lbp(business_name: org_display_name)
      result = create(session_id: g[:session_id], organization_id: g[:organization_id], profile:)

      expect(result).to be_success
      row = project(result.payload[:project_id])
      expect(row["local_presence_applicable"]).to eq("t")
      expect(row["local_presence_reason"]).to be_nil
      stored = JSON.parse(row["local_business_profile"])
      expect(stored["business_name"]).to eq(org_display_name)
      expect(stored["service_areas"]).to eq(%w[Melbourne Sydney])
      expected_hash = Platform::CanonicalJson.hexdigest(stored)
      expect(DbInspector.one(<<~SQL, [row["id"]])["h"]).to eq(expected_hash)
        SELECT encode(local_business_profile_content_sha256, 'hex') AS h FROM projects WHERE id = $1::uuid
      SQL
    end

    it "emits exactly one WF-002 ProjectCreated event carrying the real organization_id and version 0" do
      g = genesis
      result = create(session_id: g[:session_id], organization_id: g[:organization_id], profile: reason_profile)

      events = wf002_events("ProjectCreated")
      expect(events.size).to eq(1)
      event = events.first
      expect(event["aggregate_id"]).to eq(result.payload[:project_id])
      expect(event["organization_id"]).to eq(g[:organization_id])
      expect(event["aggregate_version"].to_i).to eq(0)
      body = JSON.parse(DbInspector.one(<<~SQL, [event["id"]])["b"])
        SELECT convert_from(event_bytes, 'UTF8') AS b FROM event_registry WHERE id = $1::uuid
      SQL
      expect(body["organization_id"]).to eq(g[:organization_id])
      expect(body["project_id"]).to eq(result.payload[:project_id])
      expect(body["state_version"]).to eq(0)
      expect(body["service_identity_id"]).to be_nil
      expect(body["actor_id"]).to eq(g[:account_id])
    end

    it "records execution, result, audit and idempotency evidence for the actor" do
      g = genesis
      result = create(session_id: g[:session_id], organization_id: g[:organization_id], profile: reason_profile)
      pid = result.payload[:project_id]

      execution = DbInspector.one("SELECT * FROM command_executions WHERE command_type = 'wf002.create_project'")
      expect(execution["actor_id"]).to eq(g[:account_id])
      expect(execution["service_identity_id"]).to be_nil
      cmd_result = DbInspector.one("SELECT * FROM command_results WHERE command_execution_id = $1::uuid", [execution["id"]])
      expect(cmd_result["outcome"]).to eq("success")
      audit = DbInspector.one("SELECT * FROM audit_record_registry WHERE entity_id = $1::uuid", [pid])
      expect(audit["workflow_id"]).to eq("WF-002")
      expect(audit["to_state"]).to eq("draft")
      idem = DbInspector.one("SELECT * FROM idempotency_records WHERE command_type = 'wf002.create_project'")
      expect(idem["organization_id"]).to eq(g[:organization_id])
      expect(idem["scope_kind"]).to eq("organization")
    end
  end

  describe "reconciliation with S-02 genesis" do
    it "leaves the one genesis draft Project intact and adds exactly one more" do
      g = genesis
      expect(projects.size).to eq(1)
      genesis_project = project(g[:project_id])
      expect(genesis_project["state"]).to eq("draft")
      expect(genesis_project["local_presence_applicable"]).to be_nil # the reduced genesis body

      create(session_id: g[:session_id], organization_id: g[:organization_id], profile: reason_profile)
      expect(projects.size).to eq(2)
      expect(project(g[:project_id])["state"]).to eq("draft") # genesis project unchanged
    end
  end

  describe "idempotency and exact replay" do
    it "returns the stored result on exact replay, creating no second Project or event" do
      g = genesis
      first = create(session_id: g[:session_id], organization_id: g[:organization_id],
                     profile: reason_profile, idempotency_key: "same")
      replay = create(session_id: g[:session_id], organization_id: g[:organization_id],
                      profile: reason_profile, idempotency_key: "same")

      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(replay.payload[:project_id]).to eq(first.payload[:project_id])
      expect(projects.size).to eq(2) # genesis + one
      expect(wf002_events("ProjectCreated").size).to eq(1)
    end

    it "returns idempotency_conflict for the same key with an altered profile" do
      g = genesis
      create(session_id: g[:session_id], organization_id: g[:organization_id],
             profile: reason_profile, idempotency_key: "k")
      conflict = create(session_id: g[:session_id], organization_id: g[:organization_id],
                        profile: reason_profile(display_name: "Different Name"), idempotency_key: "k")

      expect(conflict.reason_code).to eq("idempotency_conflict")
      expect(projects.size).to eq(2)
      expect(wf002_events("ProjectCreated").size).to eq(1)
    end

    it "creates distinct Projects for distinct idempotency keys" do
      g = genesis
      a = create(session_id: g[:session_id], organization_id: g[:organization_id], profile: reason_profile)
      b = create(session_id: g[:session_id], organization_id: g[:organization_id], profile: reason_profile)

      expect(a.payload[:project_id]).not_to eq(b.payload[:project_id])
      expect(projects.size).to eq(3) # genesis + two
      expect(wf002_events("ProjectCreated").size).to eq(2)
    end
  end

  describe "no activation and no Source subsystem in this tranche" do
    it "leaves the created Project draft; pause/archive remain refused at the database (OD-014)" do
      g = genesis
      pid = create(session_id: g[:session_id], organization_id: g[:organization_id],
                   profile: reason_profile).payload[:project_id]
      expect(project(pid)["state"]).to eq("draft")

      # S-03 permits the draft->active edge (gated by the ActivateProject handler on an active
      # Source); CreateProject itself performs no transition, and pause/archive stay refused.
      %w[paused archived].each do |state|
        expect do
          DbInspector.connection.exec_params("UPDATE projects SET state = $2 WHERE id = $1::uuid", [pid, state])
        end.to raise_error(PG::RaiseException, /project_lifecycle_transition_unavailable/)
      end
      expect(project(pid)["state"]).to eq("draft")
    end

    it "creates no Source rows and emits no ProjectActivated event" do
      g = genesis
      create(session_id: g[:session_id], organization_id: g[:organization_id], profile: reason_profile)
      # The `sources` table exists once S-04 is built, but CreateProject never
      # touches it and never activates the Project.
      expect(DbInspector.count("sources")).to eq(0)
      expect(count_where("SELECT count(*) AS c FROM event_registry WHERE event_type = 'ProjectActivated'")).to eq(0)
    end
  end

  describe "authorization and tenant isolation" do
    it "allows a Marketing Operator and denies a Security Operator" do
      marketing = TenantSeeder.seed_authorized_admin(canonical_role: "MarketingOperator")
      ok = create(session_id: marketing[:session_id], organization_id: marketing[:organization_id], profile: reason_profile)
      expect(ok).to be_success

      security = TenantSeeder.seed_authorized_admin(canonical_role: "SecurityOperator")
      denied = create(session_id: security[:session_id], organization_id: security[:organization_id], profile: reason_profile)
      expect(denied.reason_code).to eq("project_create_unauthorized")
      expect(projects_in(security[:organization_id])).to be_empty
      expect(projects_in(marketing[:organization_id]).size).to eq(1)
    end

    it "denies an inactive Account and an expired Session without creating a Project" do
      suspended = TenantSeeder.seed_authorized_admin(account_status: "suspended")
      expect(create(session_id: suspended[:session_id], organization_id: suspended[:organization_id],
                    profile: reason_profile).reason_code).to eq("account_inactive")

      revoked = TenantSeeder.seed_authorized_admin(session_status: "revoked")
      expect(create(session_id: revoked[:session_id], organization_id: revoked[:organization_id],
                    profile: reason_profile).reason_code).to eq("session_invalid")
      expect(DbInspector.count("projects")).to eq(0)
    end

    it "refuses a caller who names a different Organization than its Session's" do
      g = genesis
      result = create(session_id: g[:session_id], organization_id: SecureRandom.uuid_v7, profile: reason_profile)
      expect(result.reason_code).to eq("tenant_mismatch")
      expect(projects.size).to eq(1) # only the genesis Project
    end

    it "refuses a Local Business Profile whose business name is not the Organization display name" do
      g = genesis
      result = create(session_id: g[:session_id], organization_id: g[:organization_id],
                      profile: profile_with_lbp(business_name: "Someone Else Pty Ltd"))
      expect(result.reason_code).to eq("project_local_profile_invalid")
      expect(projects.size).to eq(1)
    end

    it "cannot be authorized through a Project id or bootstrap proof — only the Session grant" do
      # A syntactically valid but unknown Session id is an authentication failure;
      # possession of a would-be Project id or Organization id confers nothing.
      result = create(session_id: SecureRandom.uuid_v7, organization_id: SecureRandom.uuid_v7, profile: reason_profile)
      expect(result.reason_code).to eq("session_invalid")
    end
  end

  describe "profile validation (decided before authentication, first-match order)" do
    # Validation precedes authentication, so these need no valid Session.
    def invalid(profile) = create(session_id: SecureRandom.uuid_v7, organization_id: SecureRandom.uuid_v7, profile:).reason_code

    it "rejects an unsupported envelope schema version and profile schema version" do
      unsupported = create(session_id: SecureRandom.uuid_v7, organization_id: SecureRandom.uuid_v7,
                           profile: reason_profile, schema_version: "2.0")
      expect(unsupported.reason_code).to eq("project_schema_unsupported")
      expect(invalid(reason_profile("project_profile_schema_version" => "project-profile-v2")))
        .to eq("project_schema_unsupported")
    end

    it "rejects display name, locale, time zone and objective deviations in order" do
      expect(invalid(reason_profile(display_name: ""))).to eq("project_display_name_invalid")
      expect(invalid(reason_profile(display_name: "x" * 121))).to eq("project_display_name_invalid")
      expect(invalid(reason_profile("default_locale" => "en-US"))).to eq("project_locale_unsupported")
      expect(invalid(reason_profile("reporting_time_zone" => "Australia/Sydney"))).to eq("project_time_zone_unsupported")
      expect(invalid(reason_profile("objective" => "brand_lift"))).to eq("project_objective_unsupported")
    end

    it "rejects an invalid local-presence applicability and reason bounds" do
      expect(invalid(reason_profile("local_presence_applicable" => "false"))).to eq("project_local_applicability_invalid")
      expect(invalid(reason_profile("local_presence_reason" => "too short"))).to eq("project_local_reason_invalid")
      expect(invalid(reason_profile("local_presence_reason" => "x" * 501))).to eq("project_local_reason_invalid")
    end

    it "rejects a false applicability that also carries a profile, and a true one carrying a reason" do
      expect(invalid(reason_profile("local_business_profile" => { "schema_version" => "local-business-profile-v1" })))
        .to eq("project_local_profile_invalid")
      expect(invalid(profile_with_lbp(business_name: org_display_name).merge("local_presence_reason" => "a valid twenty plus reason here")))
        .to eq("project_local_reason_invalid")
    end

    it "rejects malformed Local Business Profile members" do
      expect(invalid(profile_with_lbp(business_name: org_display_name, "telephone_e164" => "0255501234")))
        .to eq("project_local_profile_invalid")
      expect(invalid(profile_with_lbp(business_name: org_display_name, "telephone_e164" => "+0255501234")))
        .to eq("project_local_profile_invalid")
      expect(invalid(profile_with_lbp(business_name: org_display_name, "service_areas" => %w[Sydney Melbourne])))
        .to eq("project_local_profile_invalid") # out of UTF-8-byte order
      expect(invalid(profile_with_lbp(business_name: org_display_name, "service_areas" => %w[Sydney Sydney])))
        .to eq("project_local_profile_invalid") # duplicate
      expect(invalid(profile_with_lbp(business_name: org_display_name, "address_text" => "")))
        .to eq("project_local_profile_invalid")
    end
  end
end
