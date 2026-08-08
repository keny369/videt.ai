# frozen_string_literal: true

require "rails_helper"
require "digest"

# WF-003 ObserveAutomatedSlot — the automated observation slot schedule (S-05-007)
# (SCORE_EVIDENCE_MODEL.md :151-160; contracts/S-05.json MTX-028 background_job/
# retry_policy; WORKFLOW_SPECIFICATIONS.md § WF-003). The final Observation sub-tranche:
# the verification lifecycle service, driven by a `verification_observation_slot`
# ScheduledAction due in its half-open window, reserves and completes ONE automated
# attempt through the S-05-005/006 engine; a slot whose window has closed is recorded
# once as `observation_slot_skipped` and never runs late; a terminal Request voids its
# remaining slots without a skipped event. The chain is production-real: genesis, a
# registered Source and an issued challenge (which itself schedules the ten slots).
RSpec.describe "WF-003 automated observation slot", type: :acceptance,
               acceptance_ids: ["AC-CAP-005", "AC-WF-003"], test_types: %w[TYP-E2E TYP-INT TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def act_now = fixed_now + 60           # the issuance instant (issued_at_utc)
  def bc = Platform::BaselineContent
  def conn = DbInspector.connection

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system,
                                         correlation_id: SecureRandom.uuid_v7)
  end

  def act_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system,
                                                   correlation_id: SecureRandom.uuid_v7)

  # The verification lifecycle service running a due slot (a null human actor), clocked
  # at the instant the slot job runs.
  def slot_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system,
                                         correlation_id: SecureRandom.uuid_v7)
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
        organization_display_name: "Acme", first_project: GenesisProjectProfile.body("Genesis"),
        access_policy_content_sha256: bc.access_policy_sha256, entitlement_policy_content_sha256: bc.entitlement_policy_sha256,
        plan_content_sha256: bc.plan_sha256, requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    ).payload
  end

  def register_source(g, uri = "https://shop.acme.example")
    Workflows::Wf004::Handlers::RegisterSource.new.call(
      command: Workflows::Wf004::Commands::RegisterSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "rs-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        registration_schema_version: "source-registration-v1", submitted_root_uri: uri,
        expected_state_version: 0, requested_at_utc: fixed_now
      ), request_context: act_ctx
    ).payload[:source_id]
  end

  def issue(g, sid)
    Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(
      command: Workflows::Wf003::Commands::IssueVerificationChallenge.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "vc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        source_id: sid, method: "dns_txt", expected_state_version: 0, requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  # A registered proposed Source and an issued pending Request (which scheduled the ten
  # slots) — the precondition for an automated observation.
  def issued
    g = bootstrap
    sid = register_source(g)
    r = issue(g, sid)
    { g:, org: g[:organization_id], source_id: sid, vid: r.payload[:verification_request_id], token: r.payload[:challenge_token] }
  end

  # Run the automated slot for `offset`, clocked at `at` (default: exactly its due
  # instant). The command is byte-for-byte what the F-04 worker would build from the
  # scheduled action: due_at = issued_at + offset, a stable action identity per
  # (Request, offset) so a retry replays. The handler reads only the Request, never the
  # action row, so the action id/identity are constructed here.
  def observe_slot(s, offset:, outbound:, at: nil)
    due_at = act_now + (offset * 60)
    run_at = at || due_at
    cmd = Workflows::Wf003::Commands::ObserveAutomatedSlot.new(
      command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: s[:org],
      target_type: "verification_request", verification_request_id: s[:vid], due_at:,
      action_id: SecureRandom.uuid_v7,
      action_identity_sha256: Digest::SHA256.digest("slot-#{s[:vid]}-#{offset}"),
      requested_at_utc: run_at
    )
    Workflows::Wf003::Handlers::ObserveAutomatedSlot.new.call(
      command: cmd, request_context: slot_ctx(run_at), outbound:
    )
  end

  # ---- injected F-01 observation outcomes (duck-typed; never the real network) ----
  def obj(**methods)
    o = Object.new
    methods.each { |name, value| o.define_singleton_method(name) { value } }
    o
  end

  def outbound_dns(answer)
    fake = Object.new
    fake.define_singleton_method(:fetch_dns_txt) { |*_a, **_k| answer }
    fake
  end

  def matched(token) = outbound_dns(obj(refused?: false, records: [["f1-verification=#{token}"]]))
  def mismatch = outbound_dns(obj(refused?: false, records: [["f1-verification=not-the-token"]]))

  # An outbound that fails the test if any provider call is attempted — proves a
  # skipped or voided slot never observes.
  def outbound_forbidden
    fake = Object.new
    fake.define_singleton_method(:fetch_dns_txt) { |*_a, **_k| raise "provider must not be called for this slot" }
    fake.define_singleton_method(:fetch_http) { |*_a, **_k| raise "provider must not be called for this slot" }
    fake
  end

  # ---- inspectors ----
  def vr(id) = DbInspector.one("SELECT * FROM verification_requests WHERE id = $1::uuid", [id])
  def source_state(id) = DbInspector.one("SELECT state FROM sources WHERE id = $1::uuid", [id])["state"]
  def automated_attempts(vid) = DbInspector.all(<<~SQL, [vid])
    SELECT * FROM verification_attempts WHERE verification_request_id = $1::uuid AND origin = 'automated' ORDER BY attempt_number
  SQL
  def evidence_count(vid) = DbInspector.all("SELECT id FROM evidence WHERE producer_id = 'wf003.verification_observation' AND source_id = (SELECT source_id FROM verification_requests WHERE id = $1::uuid)", [vid]).size
  def observed_events(vid) = DbInspector.all("SELECT id FROM event_registry WHERE event_type = 'SourceVerificationObserved' AND aggregate_id = $1::uuid", [vid])
  def skip_audits(vid) = DbInspector.all("SELECT * FROM audit_record_registry WHERE entity_id = $1::uuid AND reason_code = 'observation_slot_skipped'", [vid])

  # ------------------------------------------------------------------------

  describe "a slot that starts in its window reserves and completes ONE automated attempt" do
    it "reserves an automated attempt with its slot offset, records the observation and verifies on a match" do
      s = issued
      result = observe_slot(s, offset: 0, outbound: matched(s[:token]))

      expect(result).to be_success
      expect(result.payload[:match_decision]).to eq("matched")
      expect(result.payload[:request_status]).to eq("verified")

      attempts = automated_attempts(s[:vid])
      expect(attempts.size).to eq(1)
      expect(attempts.first["origin"]).to eq("automated")
      expect(attempts.first["automated_slot_offset_minutes"].to_i).to eq(0)
      expect(attempts.first["state"]).to eq("completed")
      expect(attempts.first["match_decision"]).to eq("matched")

      expect(evidence_count(s[:vid])).to eq(1)
      expect(observed_events(s[:vid]).size).to eq(1)
      expect(vr(s[:vid])["request_status"]).to eq("verified")
      expect(source_state(s[:source_id])).to eq("verified")
    end

    it "increments attempt_count only, never the on-demand counter or marker" do
      s = issued
      observe_slot(s, offset: 0, outbound: mismatch)

      row = vr(s[:vid])
      expect(row["attempt_count"].to_i).to eq(1)
      expect(row["on_demand_observation_count"].to_i).to eq(0)
      expect(row["on_demand_in_progress_attempt_id"]).to be_nil
      expect(row["last_on_demand_completed_at_utc"]).to be_nil
      expect(row["last_observed_at_utc"]).not_to be_nil
      # A non-match records only and leaves the Source proposed.
      expect(row["request_status"]).to eq("pending")
      expect(source_state(s[:source_id])).to eq("proposed")
    end

    it "is idempotent: a redelivered started slot resumes its attempt, never a second one" do
      s = issued
      first = observe_slot(s, offset: 0, outbound: matched(s[:token]))
      replay = observe_slot(s, offset: 0, outbound: matched(s[:token]))

      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(automated_attempts(s[:vid]).size).to eq(1)
      expect(evidence_count(s[:vid])).to eq(1)
      expect(observed_events(s[:vid]).size).to eq(1)
      expect(vr(s[:vid])["attempt_count"].to_i).to eq(1)
    end
  end

  describe "a slot whose half-open window has closed is skipped once and never runs late" do
    it "records observation_slot_skipped, reserves no attempt and never observes" do
      s = issued
      # Slot 0's window is [0, 5) minutes; at exactly +5 it is closed.
      result = observe_slot(s, offset: 0, at: act_now + (5 * 60), outbound: outbound_forbidden)

      expect(result).to be_success
      expect(result.payload[:reason_code]).to eq("observation_slot_skipped")
      expect(automated_attempts(s[:vid])).to be_empty
      expect(evidence_count(s[:vid])).to eq(0)
      expect(skip_audits(s[:vid]).size).to eq(1)
      # attempt_count untouched: a skipped slot does not increment it.
      expect(vr(s[:vid])["attempt_count"].to_i).to eq(0)
      expect(vr(s[:vid])["request_status"]).to eq("pending")
    end

    it "records the skip exactly once under redelivery" do
      s = issued
      first = observe_slot(s, offset: 0, at: act_now + (5 * 60), outbound: outbound_forbidden)
      replay = observe_slot(s, offset: 0, at: act_now + (6 * 60), outbound: outbound_forbidden)

      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(skip_audits(s[:vid]).size).to eq(1)
      expect(automated_attempts(s[:vid])).to be_empty
    end
  end

  describe "the exact-boundary rule: earlier slot skipped, later slot eligible" do
    it "skips slot 0 and starts slot 1 when both are evaluated at the +5-minute boundary" do
      s = issued
      boundary = act_now + (5 * 60)
      earlier = observe_slot(s, offset: 0, at: boundary, outbound: outbound_forbidden)
      later = observe_slot(s, offset: 5, at: boundary, outbound: matched(s[:token]))

      expect(earlier.payload[:reason_code]).to eq("observation_slot_skipped")
      expect(later).to be_success
      expect(later.payload[:request_status]).to eq("verified")
      attempts = automated_attempts(s[:vid])
      expect(attempts.map { |a| a["automated_slot_offset_minutes"].to_i }).to eq([5])
    end
  end

  describe "a terminal Request voids its remaining slots WITHOUT a skipped event" do
    it "records nothing when the Request is already verified — no attempt, no observation, no skip" do
      s = issued
      observe_slot(s, offset: 0, outbound: matched(s[:token]))       # verifies via slot 0
      expect(vr(s[:vid])["request_status"]).to eq("verified")

      later = observe_slot(s, offset: 5, at: act_now + (5 * 60), outbound: outbound_forbidden)

      expect(later).to be_success
      expect(later.payload[:observation]).to eq("voided")
      # Only slot 0's attempt exists; slot 5 reserved nothing.
      expect(automated_attempts(s[:vid]).map { |a| a["automated_slot_offset_minutes"].to_i }).to eq([0])
      expect(skip_audits(s[:vid])).to be_empty
      expect(vr(s[:vid])["attempt_count"].to_i).to eq(1)
    end

    it "voids remaining slots after an expiry too, still without a skipped event" do
      s = issued
      # Expire the Request through the one guard-legal edge (pending -> expired).
      conn.exec_params(<<~SQL, [s[:vid]])
        UPDATE verification_requests
        SET request_status = 'expired', decision_reason_code = 'challenge_expired',
            challenge_ciphertext_reference = NULL, challenge_key_id = NULL
        WHERE id = $1::uuid
      SQL
      result = observe_slot(s, offset: 5, at: act_now + (5 * 60), outbound: outbound_forbidden)

      expect(result).to be_success
      expect(result.payload[:observation]).to eq("voided")
      expect(automated_attempts(s[:vid])).to be_empty
      expect(skip_audits(s[:vid])).to be_empty
    end
  end

  describe "a malformed action is quarantine-reasoned" do
    it "rejects a due time that is not one of the ten ratified slot offsets as scheduled_action_target_mismatch" do
      s = issued
      due_at = act_now + (7 * 60)   # 7 minutes is not a slot offset
      cmd = Workflows::Wf003::Commands::ObserveAutomatedSlot.new(
        command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: s[:org],
        target_type: "verification_request", verification_request_id: s[:vid], due_at:,
        action_id: SecureRandom.uuid_v7, action_identity_sha256: Digest::SHA256.digest("bad-slot"),
        requested_at_utc: due_at
      )
      result = Workflows::Wf003::Handlers::ObserveAutomatedSlot.new.call(
        command: cmd, request_context: slot_ctx(due_at), outbound: outbound_forbidden
      )
      expect(result.reason_code).to eq("scheduled_action_target_mismatch")
      expect(automated_attempts(s[:vid])).to be_empty
    end
  end
end
