# frozen_string_literal: true

require "rails_helper"

# WF-003 IssueVerificationChallenge (APPLICATION_LAYER.md § WF-003; CAP-005 MTX-028;
# SCORE_EVIDENCE_MODEL.md § Ownership-Verification Evidence Contract; AC-CAP-005,
# AC-WF-003, AC-PRULE-020; contracts/S-05.json).
#
# The challenge-issuance limb of S-05: an authorized Organization actor opens
# ownership verification for a proposed Source, creating exactly one pending
# Verification Request and issuing one challenge token, idempotently, with exactly
# one SourceVerificationRequested event, the challenge protected behind F-02 and the
# 24-hour expiry scheduled through F-04. The principal under test reaches the command
# through real genesis, a real registered Source, and never through fixtured
# verification authority.
#
# This is issuance only: no DNS/HTTP observation, no Source transition and no
# SourceVerified event exist, and are proved unreachable here.
RSpec.describe "WF-003 issue verification challenge", type: :acceptance,
               acceptance_ids: ["AC-CAP-005", "AC-WF-003", "AC-PRULE-020"],
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

  def act_ctx(correlation_id: SecureRandom.uuid_v7)
    Platform::RequestContext.for_actor(
      clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id:
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

  def register_source(session_id:, organization_id:, project_id:, uri: "https://shop.acme.example")
    Workflows::Wf004::Handlers::RegisterSource.new.call(
      command: Workflows::Wf004::Commands::RegisterSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "rs-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id:, organization_id:, project_id:, registration_schema_version: "source-registration-v1",
        submitted_root_uri: uri, expected_state_version: 0, requested_at_utc: fixed_now
      ), request_context: act_ctx
    ).payload[:source_id]
  end

  def issue(session_id:, organization_id:, project_id:, source_id:, method: "dns_txt",
            expected_state_version: 0, idempotency_key: "vc-#{SecureRandom.hex(6)}",
            schema_version: "1.0", ctx: act_ctx)
    Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(
      command: Workflows::Wf003::Commands::IssueVerificationChallenge.new(
        command_id: SecureRandom.uuid_v7, idempotency_key:, schema_version:,
        session_id:, organization_id:, project_id:, source_id:, method:,
        expected_state_version:, requested_at_utc: act_now
      ), request_context: ctx
    )
  end

  # Genesis + one registered proposed Source, the common precondition.
  def genesis_with_source(uri: "https://shop.acme.example")
    g = genesis
    sid = register_source(session_id: g[:session_id], organization_id: g[:organization_id],
                          project_id: g[:project_id], uri:)
    [g, sid]
  end

  def vrs = DbInspector.all("SELECT * FROM verification_requests ORDER BY created_at, id")
  def vr(id) = DbInspector.one("SELECT * FROM verification_requests WHERE id = $1::uuid", [id])
  def wf003_events(type) = DbInspector.all(<<~SQL)
    SELECT * FROM event_registry WHERE workflow_id = 'WF-003' AND event_type = '#{type}' ORDER BY occurred_at, id
  SQL
  def expiry_actions(target) = DbInspector.all(<<~SQL, [target])
    SELECT * FROM scheduled_actions WHERE action_kind = 'verification_request_expire' AND target_id = $1::uuid
  SQL

  # ------------------------------------------------------------------------

  describe "successful issuance, production-reachable through genesis and a registered Source" do
    it "creates exactly one pending Verification Request with immutable issuance provenance" do
      g, sid = genesis_with_source(uri: "https://Shop.Acme.Example:443/")
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid, method: "dns_txt")

      expect(result).to be_success
      row = vr(result.payload[:verification_request_id])
      expect(row["request_status"]).to eq("pending")
      expect(row["organization_id"]).to eq(g[:organization_id])
      expect(row["project_id"]).to eq(g[:project_id])
      expect(row["source_id"]).to eq(sid)
      expect(row["request_initiator_account_id"]).to eq(g[:account_id])
      expect(row["method"]).to eq("dns_txt")
      expect(row["canonical_host"]).to eq("shop.acme.example")
      expect(row["schema_version"]).to eq("verification-request-v1")
      expect(row["challenge_key_id"]).to eq("challenge-token-envelope-v1")
      expect(row["challenge_ciphertext_reference"]).not_to be_nil
      expect(row["decision_reason_code"]).to be_nil
      expect(row["attempt_count"].to_i).to eq(0)
      expect(row["on_demand_observation_count"].to_i).to eq(0)
    end

    it "returns the plaintext token and the 24-hour expiry through the authorized response" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid)

      token = result.payload[:challenge_token]
      expect(token).to be_a(String)
      # >= 128 bits of entropy, exact ASCII (URL-safe Base64 of 32 bytes).
      expect(token).to match(/\A[A-Za-z0-9_-]+\z/)
      expect(token.length).to be >= 22
      expect(result.payload[:issued_at_utc]).to eq(act_now.iso8601(6))
      expect(Time.parse(result.payload[:expires_at_utc])).to eq(act_now + (24 * 3600))
    end

    it "records execution, result, audit and idempotency evidence stamped WF-003" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid)
      execution = DbInspector.one("SELECT * FROM command_executions WHERE command_type = 'wf003.issue_verification_challenge'")
      expect(execution["actor_id"]).to eq(g[:account_id])
      expect(execution["service_identity_id"]).to be_nil
      audit = DbInspector.one("SELECT * FROM audit_record_registry WHERE entity_id = $1::uuid", [result.payload[:verification_request_id]])
      expect(audit["workflow_id"]).to eq("WF-003")
      expect(audit["to_state"]).to eq("pending")
      expect(audit["classification"]).to eq("restricted")
      idem = DbInspector.one("SELECT * FROM idempotency_records WHERE command_type = 'wf003.issue_verification_challenge'")
      expect(idem["target_id"]).to eq(sid)
    end
  end

  describe "the challenge token is a secret: protected behind F-02, never at rest in plaintext" do
    it "stores the token digest and an F-02 ciphertext reference, with no plaintext column" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid)
      token = result.payload[:challenge_token]
      row = vr(result.payload[:verification_request_id])

      digest = DbInspector.one("SELECT encode(challenge_token_sha256,'hex') AS h FROM verification_requests WHERE id = $1::uuid",
                               [row["id"]])["h"]
      expect(digest).to eq(Digest::SHA256.hexdigest(token))
      # The plaintext token must not appear in any persisted verification_requests text.
      row_text = row.values.compact.map(&:to_s).join(" ")
      expect(row_text).not_to include(token)
    end

    it "re-decrypts the same token under the correct F-02 AAD binding and yields nothing under a wrong binding" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid)
      token = result.payload[:challenge_token]
      row = vr(result.payload[:verification_request_id])

      good = Platform::Encryption::Aad.for(application: "verification", record_type: "verification_request",
                                           record_id: row["id"], purpose: "challenge_token", tenant: g[:organization_id])
      expect(Platform::Encryption.reveal(row["challenge_ciphertext_reference"], aad: good)).to eq(token)

      # Relocating the binding to another Organization fails authentication.
      wrong = Platform::Encryption::Aad.for(application: "verification", record_type: "verification_request",
                                            record_id: row["id"], purpose: "challenge_token", tenant: SecureRandom.uuid_v7)
      expect { Platform::Encryption.reveal(row["challenge_ciphertext_reference"], aad: wrong) }
        .to raise_error(Platform::Encryption::Error)
    end

    it "cannot reveal one Request's challenge under another Request's record binding" do
      g = genesis
      a_source = register_source(session_id: g[:session_id], organization_id: g[:organization_id],
                                 project_id: g[:project_id], uri: "https://a.example")
      b_source = register_source(session_id: g[:session_id], organization_id: g[:organization_id],
                                 project_id: g[:project_id], uri: "https://b.example")
      a = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                project_id: g[:project_id], source_id: a_source, idempotency_key: "a")
      b = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                project_id: g[:project_id], source_id: b_source, idempotency_key: "b")
      ref_a = vr(a.payload[:verification_request_id])["challenge_ciphertext_reference"]

      # The AAD binds record_id (the Request id), so A's ciphertext under B's Request
      # binding fails authentication — a ciphertext cannot be relocated between Requests.
      wrong = Platform::Encryption::Aad.for(application: "verification", record_type: "verification_request",
                                            record_id: b.payload[:verification_request_id],
                                            purpose: "challenge_token", tenant: g[:organization_id])
      expect { Platform::Encryption.reveal(ref_a, aad: wrong) }.to raise_error(Platform::Encryption::Error)
    end

    it "keeps the plaintext token out of the event, audit and result payloads" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid)
      token = result.payload[:challenge_token]
      vid = result.payload[:verification_request_id]

      event_bytes = DbInspector.one(<<~SQL, [vid])["b"]
        SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE aggregate_id = $1::uuid
      SQL
      audit_payload = DbInspector.one("SELECT payload::text AS p FROM audit_record_registry WHERE entity_id = $1::uuid", [vid])["p"]
      result_payload = DbInspector.one(<<~SQL, [vid])["p"]
        SELECT authorized_payload::text AS p FROM command_results
        WHERE target_refs->>'verification_request' = $1
      SQL
      [event_bytes, audit_payload, result_payload].each { |blob| expect(blob).not_to include(token) }
    end
  end

  describe "emits exactly one WF-003 SourceVerificationRequested event" do
    it "carries the canonical identity and no challenge material" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid)
      events = wf003_events("SourceVerificationRequested")
      expect(events.size).to eq(1)
      body = JSON.parse(DbInspector.one(<<~SQL, [events.first["id"]])["b"])
        SELECT convert_from(event_bytes, 'UTF8') AS b FROM event_registry WHERE id = $1::uuid
      SQL
      expect(body["organization_id"]).to eq(g[:organization_id])
      expect(body["project_id"]).to eq(g[:project_id])
      expect(body["source_id"]).to eq(sid)
      expect(body["verification_request_id"]).to eq(result.payload[:verification_request_id])
      expect(body["method"]).to eq("dns_txt")
      expect(body["canonical_host"]).to eq("shop.acme.example")
      expect(body["service_identity_id"]).to be_nil
      expect(body.values_at("challenge_token", "token", "challenge")).to all(be_nil)
    end
  end

  describe "schedules the 24-hour expiry through F-04" do
    it "creates exactly one verification_request_expire action due at the expiry instant" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid)
      actions = expiry_actions(result.payload[:verification_request_id])
      expect(actions.size).to eq(1)
      expect(actions.first["organization_id"]).to eq(g[:organization_id])
      expect(Time.parse(actions.first["due_at"])).to eq(act_now + (24 * 3600))
    end
  end

  describe "method-set rule (PRULE-020): unsupported methods are rejected before any token is issued" do
    it "rejects meta_tag, email, manual_review, an unknown and an empty value as unsupported_method" do
      g, sid = genesis_with_source
      ["meta_tag", "email", "manual_review", "somethingelse", ""].each do |m|
        result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], source_id: sid, method: m)
        expect(result.reason_code).to eq("unsupported_method")
      end
      expect(vrs).to be_empty
      expect(wf003_events("SourceVerificationRequested")).to be_empty
    end

    it "rejects an unsupported command schema before issuance" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid, schema_version: "2.0")
      expect(result.reason_code).to eq("verification_request_schema_unsupported")
      expect(vrs).to be_empty
    end
  end

  describe "idempotency and the single pending slot" do
    it "returns the same Request and the same token on exact replay, creating no second Request or event" do
      g, sid = genesis_with_source
      first = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                    project_id: g[:project_id], source_id: sid, idempotency_key: "same")
      replay = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid, idempotency_key: "same")
      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(replay.payload[:verification_request_id]).to eq(first.payload[:verification_request_id])
      expect(replay.payload[:challenge_token]).to eq(first.payload[:challenge_token])
      expect(vrs.size).to eq(1)
      expect(wf003_events("SourceVerificationRequested").size).to eq(1)
    end

    it "does not disclose the token to a different same-organization actor reusing the idempotency key" do
      g, sid = genesis_with_source
      first = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                    project_id: g[:project_id], source_id: sid, idempotency_key: "shared-key")
      expect(first).to be_success

      # A different actor in the SAME Organization, also holding source.verify. The
      # idempotency key is bound to the original actor (its account is in the request
      # hash), so this is a different request while one is pending — never an
      # exact-replay token redisclosure.
      other = TenantSeeder.seed_authorized_admin(organization_id: g[:organization_id],
                                                 canonical_role: "TechnicalImplementer", with_policy: false)
      attempt = issue(session_id: other[:session_id], organization_id: g[:organization_id],
                      project_id: g[:project_id], source_id: sid, idempotency_key: "shared-key")
      expect(attempt.reason_code).to eq("verification_in_progress")
    end

    it "refuses a different request for the same Source while one is pending as verification_in_progress" do
      g, sid = genesis_with_source
      issue(session_id: g[:session_id], organization_id: g[:organization_id],
            project_id: g[:project_id], source_id: sid, idempotency_key: "a")
      second = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid, idempotency_key: "b")
      expect(second.reason_code).to eq("verification_in_progress")
      expect(vrs.size).to eq(1)
      expect(wf003_events("SourceVerificationRequested").size).to eq(1)
    end

    it "returns challenge_redelivery_unavailable when the challenge material has been cryptographically erased" do
      g, sid = genesis_with_source
      first = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                    project_id: g[:project_id], source_id: sid, idempotency_key: "erase")
      reference = vr(first.payload[:verification_request_id])["challenge_ciphertext_reference"]
      expect(Platform::Encryption.erase(reference)).to eq(:destroyed)

      replay = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid, idempotency_key: "erase")
      expect(replay.reason_code).to eq("challenge_redelivery_unavailable")
      # The Request is unchanged and still pending.
      expect(vr(first.payload[:verification_request_id])["request_status"]).to eq("pending")
      # The failed redelivery is access-logged, and the returned audit id resolves to it.
      failure_log = DbInspector.one("SELECT * FROM audit_record_registry WHERE id = $1::uuid", [replay.audit_record_id])
      expect(failure_log["reason_code"]).to eq("challenge_redelivery_unavailable")
      expect(failure_log["outcome"]).to eq("failure")
    end

    it "access-logs a redelivery as a restricted WF-003 security audit that never contains the token" do
      g, sid = genesis_with_source
      first = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                    project_id: g[:project_id], source_id: sid, idempotency_key: "audit")
      token = first.payload[:challenge_token]
      vid = first.payload[:verification_request_id]
      issue(session_id: g[:session_id], organization_id: g[:organization_id],
            project_id: g[:project_id], source_id: sid, idempotency_key: "audit") # exact replay

      logs = DbInspector.all(<<~SQL, [vid])
        SELECT * FROM audit_record_registry WHERE entity_id = $1::uuid AND workflow_id = 'WF-003'
          AND reason_code = 'challenge_redelivered'
      SQL
      expect(logs.size).to eq(1)
      expect(logs.first["classification"]).to eq("restricted")
      expect(logs.first["retention_class"]).to eq("security_audit")
      expect(logs.first["payload"]).not_to include(token)
    end
  end

  describe "authorization and tenant isolation" do
    it "allows an Organization Administrator (genesis) and a Technical Implementer" do
      g, sid = genesis_with_source
      expect(issue(session_id: g[:session_id], organization_id: g[:organization_id],
                   project_id: g[:project_id], source_id: sid)).to be_success

      ti = TenantSeeder.seed_authorized_admin(canonical_role: "TechnicalImplementer")
      project = seed_draft_project(ti[:organization_id])
      ti_source = register_source(session_id: ti[:session_id], organization_id: ti[:organization_id],
                                  project_id: project, uri: "https://ti.example")
      expect(issue(session_id: ti[:session_id], organization_id: ti[:organization_id],
                   project_id: project, source_id: ti_source)).to be_success
    end

    it "denies a Marketing Operator (may register, may not verify) as source_verify_unauthorized" do
      mo = TenantSeeder.seed_authorized_admin(canonical_role: "MarketingOperator")
      project = seed_draft_project(mo[:organization_id])
      mo_source = register_source(session_id: mo[:session_id], organization_id: mo[:organization_id],
                                  project_id: project, uri: "https://mo.example")
      result = issue(session_id: mo[:session_id], organization_id: mo[:organization_id],
                     project_id: project, source_id: mo_source)
      expect(result.reason_code).to eq("source_verify_unauthorized")
      expect(vrs).to be_empty
    end

    it "refuses a Source in another Organization without disclosure (tenant_mismatch)" do
      g, = genesis_with_source
      other = TenantSeeder.seed_authorized_admin(canonical_role: "TechnicalImplementer")
      other_project = seed_draft_project(other[:organization_id])
      other_source = register_source(session_id: other[:session_id], organization_id: other[:organization_id],
                                     project_id: other_project, uri: "https://other.example")
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: other_source)
      expect(result.reason_code).to eq("tenant_mismatch")
    end

    it "refuses a caller who names a different Organization than its Session's" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: SecureRandom.uuid_v7,
                     project_id: g[:project_id], source_id: sid)
      expect(result.reason_code).to eq("tenant_mismatch")
    end

    it "refuses an invalid Session with session_invalid, writing nothing" do
      _g, sid = genesis_with_source
      result = issue(session_id: SecureRandom.uuid_v7, organization_id: SecureRandom.uuid_v7,
                     project_id: SecureRandom.uuid_v7, source_id: sid)
      expect(result.reason_code).to eq("session_invalid")
      expect(vrs).to be_empty
    end

    it "refuses a stale expected Source state version" do
      g, sid = genesis_with_source
      result = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], source_id: sid, expected_state_version: 7)
      expect(result.reason_code).to eq("stale_state_version")
      expect(vrs).to be_empty
    end
  end

  describe "issuance does not verify or transition the Source" do
    it "leaves the Source proposed and emits no SourceVerified event" do
      g, sid = genesis_with_source
      issue(session_id: g[:session_id], organization_id: g[:organization_id],
            project_id: g[:project_id], source_id: sid)
      expect(DbInspector.one("SELECT state FROM sources WHERE id = $1::uuid", [sid])["state"]).to eq("proposed")
      expect(DbInspector.all("SELECT id FROM event_registry WHERE event_type = 'SourceVerified'")).to be_empty
    end
  end
end
