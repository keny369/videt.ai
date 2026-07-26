# frozen_string_literal: true

require "rails_helper"

# WF-003 ReserveVerificationAttempt (APPLICATION_LAYER.md § WF-003; CAP-005 MTX-028;
# SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence; contracts/S-05.json).
#
# The on-demand reservation limb of S-05: an authorized Organization actor requests one
# on-demand observation of a pending Verification Request, and the accepted command
# reserves the next attempt slot atomically — assigning the attempt ID, incrementing
# the total and on-demand attempt counts and storing the in-progress marker — before
# any provider call. The principal reaches the command through real genesis, a real
# registered Source and a real issued challenge, never through fixtured authority.
#
# This limb only RESERVES: it runs no DNS/HTTP observation, produces no Evidence, emits
# no SourceVerificationObserved, and transitions neither the Request nor the Source —
# proved unreachable here. Where a later limb's state (a full count, a cleared marker,
# a prior completion instant) is a precondition, the test seeds it directly, because
# CompleteVerificationAttempt (the marker-clearing, count-completing limb) is S-05-005.
RSpec.describe "WF-003 reserve verification attempt", type: :acceptance,
               acceptance_ids: ["AC-CAP-005", "AC-WF-003"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def act_now = fixed_now + 60
  def bc = Platform::BaselineContent
  def conn = DbInspector.connection

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
    conn.exec_params(<<~SQL, [id, org])
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

  def issue(session_id:, organization_id:, project_id:, source_id:)
    Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(
      command: Workflows::Wf003::Commands::IssueVerificationChallenge.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "vc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id:, organization_id:, project_id:, source_id:, method: "dns_txt",
        expected_state_version: 0, requested_at_utc: act_now
      ), request_context: act_ctx
    ).payload[:verification_request_id]
  end

  def reserve(session_id:, organization_id:, project_id:, verification_request_id:,
              expected_state_version: 0, idempotency_key: "rv-#{SecureRandom.hex(6)}",
              schema_version: "1.0", ctx: act_ctx)
    Workflows::Wf003::Handlers::ReserveVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::ReserveVerificationAttempt.new(
        command_id: SecureRandom.uuid_v7, idempotency_key:, schema_version:,
        session_id:, organization_id:, project_id:, verification_request_id:,
        expected_state_version:, requested_at_utc: act_now
      ), request_context: ctx
    )
  end

  # Genesis + a registered proposed Source + one issued pending Verification Request:
  # the common precondition for reserving an attempt.
  def genesis_with_request(uri: "https://shop.acme.example")
    g = genesis
    sid = register_source(session_id: g[:session_id], organization_id: g[:organization_id],
                          project_id: g[:project_id], uri:)
    vid = issue(session_id: g[:session_id], organization_id: g[:organization_id],
                project_id: g[:project_id], source_id: sid)
    [g, sid, vid]
  end

  # Seed the on-demand counters/marker/last-completion on a pending Request, simulating
  # the state a later CompleteVerificationAttempt (S-05-005) would leave — the guard on
  # verification_requests permits a counter/marker update while pending. state_version is
  # left unchanged so the expected version stays 0.
  def set_ondemand(id, count:, attempt: count, marker: nil, last_completed: nil)
    conn.exec_params(<<~SQL, [id, count, attempt, marker, last_completed])
      UPDATE verification_requests
      SET on_demand_observation_count = $2, attempt_count = $3,
          on_demand_in_progress_attempt_id = $4::uuid,
          last_on_demand_completed_at_utc = $5::timestamptz
      WHERE id = $1::uuid
    SQL
  end

  def vr(id) = DbInspector.one("SELECT * FROM verification_requests WHERE id = $1::uuid", [id])
  def attempts(vid) = DbInspector.all("SELECT * FROM verification_attempts WHERE verification_request_id = $1::uuid ORDER BY attempt_number", [vid])
  def observed_events = DbInspector.all("SELECT * FROM event_registry WHERE event_type = 'SourceVerificationObserved'")

  # ------------------------------------------------------------------------

  describe "successful on-demand reservation" do
    it "reserves attempt 1 atomically: the attempt row, the counts and the marker" do
      g, sid, vid = genesis_with_request
      result = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid)

      expect(result).to be_success
      expect(result.payload[:attempt_number]).to eq(1)
      expect(result.payload[:origin]).to eq("on_demand")
      expect(result.payload[:request_status]).to eq("pending")
      expect(result.payload[:state_version]).to eq(1)

      rows = attempts(vid)
      expect(rows.size).to eq(1)
      a = rows.first
      expect(a["state"]).to eq("reserved")
      expect(a["origin"]).to eq("on_demand")
      expect(a["attempt_number"].to_i).to eq(1)
      expect(a["source_id"]).to eq(sid)
      expect(a["automated_slot_offset_minutes"]).to be_nil
      # A reserved attempt carries no observation outcome.
      expect(a["started_at_utc"]).to be_nil
      expect(a["network_outcome"]).to be_nil
      expect(a["match_decision"]).to be_nil

      row = vr(vid)
      expect(row["attempt_count"].to_i).to eq(1)
      expect(row["on_demand_observation_count"].to_i).to eq(1)
      expect(row["on_demand_in_progress_attempt_id"]).to eq(a["id"])
      expect(row["state_version"].to_i).to eq(1)
    end

    it "records actor-attributed WF-003 execution, audit and idempotency evidence and NO observation event" do
      g, _sid, vid = genesis_with_request
      result = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid)

      execution = DbInspector.one("SELECT * FROM command_executions WHERE command_type = 'wf003.reserve_verification_attempt'")
      expect(execution["actor_id"]).to eq(g[:account_id])
      expect(execution["service_identity_id"]).to be_nil
      audit = DbInspector.one("SELECT * FROM audit_record_registry WHERE command_id = $1::uuid AND entity_id = $2::uuid",
                              [execution["command_id"], vid])
      expect(audit["workflow_id"]).to eq("WF-003")
      expect(audit["classification"]).to eq("restricted")
      idem = DbInspector.one("SELECT * FROM idempotency_records WHERE command_type = 'wf003.reserve_verification_attempt'")
      expect(idem["target_id"]).to eq(vid)
      # Reservation is not an observation: no Evidence and no SourceVerificationObserved.
      expect(observed_events).to be_empty
      expect(result.payload).not_to have_key(:evidence_id)
    end

    it "leaves the Source proposed and emits no SourceVerified event" do
      g, sid, vid = genesis_with_request
      reserve(session_id: g[:session_id], organization_id: g[:organization_id],
              project_id: g[:project_id], verification_request_id: vid)
      expect(DbInspector.one("SELECT state FROM sources WHERE id = $1::uuid", [sid])["state"]).to eq("proposed")
      expect(DbInspector.all("SELECT id FROM event_registry WHERE event_type = 'SourceVerified'")).to be_empty
    end
  end

  describe "the on-demand denials hold at their exact boundaries and never increment attempt_count" do
    it "rejects a second reservation while an observation is in progress" do
      g, _sid, vid = genesis_with_request
      first = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                      project_id: g[:project_id], verification_request_id: vid)
      expect(first).to be_success

      # The marker is still set (Complete is S-05-005); the version is now 1.
      second = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid, expected_state_version: 1)
      expect(second.reason_code).to eq("on_demand_observation_in_progress")
      expect(attempts(vid).size).to eq(1)
      expect(vr(vid)["attempt_count"].to_i).to eq(1)
    end

    it "accepts the 10th on-demand observation and rejects the 11th as on_demand_limit_reached" do
      g, _sid, vid = genesis_with_request
      # Nine completed on-demand observations already, marker clear.
      set_ondemand(vid, count: 9, attempt: 9)
      tenth = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                      project_id: g[:project_id], verification_request_id: vid)
      expect(tenth).to be_success
      expect(tenth.payload[:attempt_number]).to eq(10)
      expect(vr(vid)["on_demand_observation_count"].to_i).to eq(10)

      # At the limit, with the marker clear again. The 10th reserve advanced the
      # version to 1, so the 11th carries the current expected version.
      set_ondemand(vid, count: 10, attempt: 10)
      eleventh = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                         project_id: g[:project_id], verification_request_id: vid, expected_state_version: 1)
      expect(eleventh.reason_code).to eq("on_demand_limit_reached")
      expect(vr(vid)["on_demand_observation_count"].to_i).to eq(10)
      expect(vr(vid)["attempt_count"].to_i).to eq(10)
    end

    it "rate-limits within 5 minutes of the last completion but allows it at exactly 5 minutes" do
      g, _sid, vid = genesis_with_request
      # 4 minutes since the last on-demand completion: rejected.
      set_ondemand(vid, count: 1, attempt: 1, last_completed: (act_now - (4 * 60)).iso8601(6))
      within = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid)
      expect(within.reason_code).to eq("on_demand_rate_limited")
      expect(vr(vid)["attempt_count"].to_i).to eq(1)

      # Exactly 5 minutes: equality at the boundary is allowed.
      set_ondemand(vid, count: 1, attempt: 1, last_completed: (act_now - (5 * 60)).iso8601(6))
      at_boundary = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                            project_id: g[:project_id], verification_request_id: vid)
      expect(at_boundary).to be_success
      expect(at_boundary.payload[:attempt_number]).to eq(2)
    end

    it "rejects a reservation on a terminal Request as verification_request_not_pending" do
      g, _sid, vid = genesis_with_request
      # Expire the Request through the one guard-legal edge (pending -> expired).
      conn.exec_params(<<~SQL, [vid])
        UPDATE verification_requests
        SET request_status = 'expired', decision_reason_code = 'challenge_expired',
            challenge_ciphertext_reference = NULL, challenge_key_id = NULL
        WHERE id = $1::uuid
      SQL
      result = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid)
      expect(result.reason_code).to eq("verification_request_not_pending")
      expect(attempts(vid)).to be_empty
    end
  end

  describe "concurrency and idempotency" do
    it "requires the expected Request state version" do
      g, _sid, vid = genesis_with_request
      result = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid, expected_state_version: 7)
      expect(result.reason_code).to eq("stale_state_version")
      expect(attempts(vid)).to be_empty
    end

    it "returns the same reserved attempt on exact replay, reserving no second slot" do
      g, _sid, vid = genesis_with_request
      first = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                      project_id: g[:project_id], verification_request_id: vid, idempotency_key: "same")
      # The exact replay carries the same expected version even though the reserve
      # advanced it — idempotency, not staleness, decides the outcome.
      replay = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid, idempotency_key: "same")
      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(replay.payload[:verification_attempt_id]).to eq(first.payload[:verification_attempt_id])
      expect(attempts(vid).size).to eq(1)
      expect(vr(vid)["attempt_count"].to_i).to eq(1)
    end

    it "rejects the same idempotency key reused with different content as idempotency_conflict" do
      g, _sid, vid = genesis_with_request
      reserve(session_id: g[:session_id], organization_id: g[:organization_id],
              project_id: g[:project_id], verification_request_id: vid, idempotency_key: "k")
      # Simulate the first observation completing: clear the marker (version now 1).
      set_ondemand(vid, count: 1, attempt: 1, marker: nil)
      conflict = reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                         project_id: g[:project_id], verification_request_id: vid,
                         idempotency_key: "k", expected_state_version: 1)
      expect(conflict.reason_code).to eq("idempotency_conflict")
      expect(attempts(vid).size).to eq(1)
    end
  end

  describe "authorization and tenant isolation" do
    it "allows an Organization Administrator and a Technical Implementer holding source.verify" do
      g, _sid, vid = genesis_with_request
      expect(reserve(session_id: g[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], verification_request_id: vid)).to be_success

      # A different actor in the SAME Organization, also holding source.verify, may
      # reserve on the same Request (authority is source.verify, not the initiator).
      # Its reservation must carry the now-current version and finds the marker clear.
      set_ondemand(vid, count: 1, attempt: 1, marker: nil)
      ti = TenantSeeder.seed_authorized_admin(organization_id: g[:organization_id],
                                              canonical_role: "TechnicalImplementer", with_policy: false)
      expect(reserve(session_id: ti[:session_id], organization_id: g[:organization_id],
                     project_id: g[:project_id], verification_request_id: vid,
                     expected_state_version: 1)).to be_success
    end

    it "denies a Marketing Operator (may register, may not verify) as source_verify_unauthorized" do
      g, _sid, vid = genesis_with_request
      mo = TenantSeeder.seed_authorized_admin(organization_id: g[:organization_id],
                                              canonical_role: "MarketingOperator", with_policy: false)
      result = reserve(session_id: mo[:session_id], organization_id: g[:organization_id],
                       project_id: g[:project_id], verification_request_id: vid)
      expect(result.reason_code).to eq("source_verify_unauthorized")
      expect(attempts(vid)).to be_empty
    end

    it "refuses a Request in another Organization without disclosure (tenant_mismatch)" do
      _g, _sid, _vid = genesis_with_request
      other = TenantSeeder.seed_authorized_admin(canonical_role: "TechnicalImplementer")
      other_project = seed_draft_project(other[:organization_id])
      other_source = register_source(session_id: other[:session_id], organization_id: other[:organization_id],
                                     project_id: other_project, uri: "https://other.example")
      other_vid = issue(session_id: other[:session_id], organization_id: other[:organization_id],
                        project_id: other_project, source_id: other_source)

      g2 = genesis_with_request(uri: "https://second.example") # a fresh caller in a different org
      result = reserve(session_id: g2[0][:session_id], organization_id: g2[0][:organization_id],
                       project_id: g2[0][:project_id], verification_request_id: other_vid)
      expect(result.reason_code).to eq("tenant_mismatch")
      expect(attempts(other_vid)).to be_empty
    end

    it "refuses an invalid Session with session_invalid, writing nothing" do
      _g, _sid, vid = genesis_with_request
      result = reserve(session_id: SecureRandom.uuid_v7, organization_id: SecureRandom.uuid_v7,
                       project_id: SecureRandom.uuid_v7, verification_request_id: vid)
      expect(result.reason_code).to eq("session_invalid")
      expect(attempts(vid)).to be_empty
    end
  end
end
