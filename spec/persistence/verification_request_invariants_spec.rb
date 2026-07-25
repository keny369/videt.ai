# frozen_string_literal: true

require "rails_helper"

# S-05 Ownership Verification database invariants — the IssueVerificationChallenge
# aggregate (schemas/POSTGRESQL_SCHEMA.md :287; SCORE_EVIDENCE_MODEL.md § Verification
# Request; contracts/S-05.json MTX-028/MTX-051/MTX-071).
#
# The properties that must hold in the database itself: forced tenant RLS, the
# least-privilege runtime matrix (no DELETE), the unrepresentable unsupported method
# (PRULE-020/MTX-071), the exact 24-hour expiry, the immutable issuance facts, the
# withheld status transition, the at-most-one-pending-Request-per-Source partial
# unique index, the composite Source foreign key that prevents a cross-Project or
# cross-Organization link, and the pending-Request challenge-material invariant.
RSpec.describe "Verification request invariants", type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:project) { seed_draft_project(org) }
  let(:source) { insert_source }
  def conn = DbInspector.connection

  def seed_draft_project(organization_id)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def insert_source(organization_id: org, project_id: project, host: "shop.example", state: "proposed")
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, project_id, host, state])
      INSERT INTO sources
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, project_id,
         submitted_root_uri, canonical_root_uri, canonical_host,
         registration_schema_version, host_normalization_version, registration_origin,
         registering_account_id, registration_command_id, registration_idempotency_key_digest,
         registration_authorization_decision_id, registered_at, state)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,
              'https://' || $4 || '/', 'https://' || $4 || '/', $4,
              'source-registration-v1','ascii-host-v1','human_command',
              gen_random_uuid(), gen_random_uuid(), sha256('k'::bytea),
              gen_random_uuid(), now(), $5)
    SQL
    id
  end

  # Insert a Verification Request directly (superuser, RLS-bypassing), so the row
  # exercises the table constraints rather than the application path.
  def insert_vr(organization_id: org, project_id: project, source_id: source, method: "dns_txt",
                status: "pending", host: "shop.example", issued: "2026-07-25T10:00:00Z",
                expires: "2026-07-26T10:00:00Z", reason: nil, ciphertext: :set, key_id: "challenge-token-envelope-v1")
    id = SecureRandom.uuid_v7
    ct = ciphertext == :set ? SecureRandom.uuid_v7 : nil
    conn.exec_params(<<~SQL, [id, organization_id, project_id, source_id, method, status, host, issued, expires, reason, ct, key_id])
      INSERT INTO verification_requests
        (id, state_version, lock_version, created_at, updated_at, correlation_id, schema_version,
         organization_id, project_id, source_id, request_initiator_account_id, method, canonical_host,
         challenge_token_sha256, challenge_ciphertext_reference, challenge_key_id,
         initial_challenge_delivered_at_utc, issued_at_utc, expires_at_utc, idempotency_key_digest,
         decision_reason_code, request_status, attempt_count, on_demand_observation_count)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),'verification-request-v1',
              $2,$3,$4,gen_random_uuid(),$5,$7,
              sha256('token'::bytea),$11::uuid,$12,
              $8::timestamptz,$8::timestamptz,$9::timestamptz,sha256('idem'::bytea),
              $10::text,$6,0,0)
    SQL
    id
  end

  describe "tenancy and least privilege" do
    it "forces row level security with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = 'verification_requests'")
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
      policy = DbInspector.one("SELECT qual FROM pg_policies WHERE tablename = 'verification_requests' AND policyname = 'verification_requests_context'")
      expect(policy["qual"]).to include("f1_current_context_org")
    end

    it "grants the runtime role SELECT, INSERT and UPDATE but never DELETE" do
      privs = DbInspector.all(<<~SQL).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = 'verification_requests' AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT UPDATE])
      expect(privs).not_to include("DELETE")
    end
  end

  describe "the method set is unrepresentable outside dns_txt/http_file (PRULE-020)" do
    it "accepts dns_txt and http_file and rejects any other method" do
      expect { insert_vr(method: "dns_txt") }.not_to raise_error
      expect { insert_vr(source_id: insert_source(host: "b.example"), method: "http_file") }.not_to raise_error
      %w[meta_tag email manual_review].each do |m|
        expect { insert_vr(source_id: insert_source(host: "#{m}.example"), method: m) }
          .to raise_error(PG::CheckViolation, /verification_requests_method_check/)
      end
    end
  end

  describe "issuance constraints" do
    it "requires expires_at to be exactly 24 hours after issued_at" do
      expect { insert_vr(issued: "2026-07-25T10:00:00Z", expires: "2026-07-26T09:59:59Z") }
        .to raise_error(PG::CheckViolation, /expires_at_utc/)
    end

    it "requires a pending Request to carry recoverable challenge material and no decision reason" do
      expect { insert_vr(ciphertext: :null) }
        .to raise_error(PG::CheckViolation, /verification_requests_pending_has_challenge/)
      expect { insert_vr(reason: "matched") }
        .to raise_error(PG::CheckViolation, /verification_requests_pending_reason_null/)
    end
  end

  describe "at most one pending Request per Source" do
    it "rejects a second pending Request for the same Source" do
      insert_vr
      expect { insert_vr }.to raise_error(PG::UniqueViolation, /verification_requests_one_pending_per_source/)
    end
  end

  describe "the composite Source foreign key" do
    it "refuses a Request whose (organization, project, source) is not a Source" do
      expect { insert_vr(source_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::ForeignKeyViolation, /verification_requests_source_fk/)
      other_org = TenantSeeder.create_organization
      other_project = seed_draft_project(other_org)
      other_source = insert_source(organization_id: other_org, project_id: other_project, host: "x.example")
      expect { insert_vr(source_id: other_source) }
        .to raise_error(PG::ForeignKeyViolation, /verification_requests_source_fk/)
    end
  end

  describe "the verification_requests lifecycle guard" do
    it "refuses every status transition while the observation/expiry limbs are unavailable" do
      id = insert_vr
      %w[verified expired canceled failed].each do |status|
        expect { conn.exec_params("UPDATE verification_requests SET request_status = $2 WHERE id = $1::uuid", [id, status]) }
          .to raise_error(PG::RaiseException, /verification_request_transition_unavailable/)
      end
      expect(DbInspector.one("SELECT request_status FROM verification_requests WHERE id = $1::uuid", [id])["request_status"]).to eq("pending")
    end

    it "keeps the tenant/Project/Source identity and the issuance facts immutable" do
      id = insert_vr
      expect { conn.exec_params("UPDATE verification_requests SET source_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_request_tenant_identity_immutable/)
      expect { conn.exec_params("UPDATE verification_requests SET method = 'http_file' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_request_issuance_immutable/)
      expect { conn.exec_params("UPDATE verification_requests SET challenge_token_sha256 = sha256('x'::bytea) WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_request_issuance_immutable/)
    end
  end
end
