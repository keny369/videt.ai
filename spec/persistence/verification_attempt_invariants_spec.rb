# frozen_string_literal: true

require "rails_helper"

# S-05 Ownership Verification database invariants — the verification_attempts table
# (schemas/POSTGRESQL_SCHEMA.md :288; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And
# Evidence; contracts/S-05.json MTX-028).
#
# The properties that must hold in the database itself: forced tenant RLS, the
# least-privilege runtime matrix (no DELETE), the reservation lineage CHECKs (positive
# attempt number, the origin/slot-offset agreement, the reserved-has-no-outcome
# invariant, the enum sets), the unique attempt sequence per Request, the composite
# Request and Source foreign keys that prevent a cross-Project or cross-Organization
# link, and the lifecycle guard that freezes the reservation and withholds every state
# transition until the completion limb lands.
RSpec.describe "Verification attempt invariants", type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:project) { seed_draft_project(org) }
  let(:source) { insert_source }
  let(:request) { insert_vr }
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

  def insert_vr(organization_id: org, project_id: project, source_id: source, host: "shop.example")
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, project_id, source_id, host])
      INSERT INTO verification_requests
        (id, state_version, lock_version, created_at, updated_at, correlation_id, schema_version,
         organization_id, project_id, source_id, request_initiator_account_id, method, canonical_host,
         challenge_token_sha256, challenge_ciphertext_reference, challenge_key_id,
         initial_challenge_delivered_at_utc, issued_at_utc, expires_at_utc, idempotency_key_digest,
         request_status, attempt_count, on_demand_observation_count)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),'verification-request-v1',
              $2,$3,$4,gen_random_uuid(),'dns_txt',$5,
              sha256('token'::bytea),gen_random_uuid(),'challenge-token-envelope-v1',
              '2026-07-25T10:00:00Z','2026-07-25T10:00:00Z','2026-07-26T10:00:00Z',sha256('idem'::bytea),
              'pending',0,0)
    SQL
    id
  end

  # Insert a Verification Attempt directly (superuser, RLS-bypassing), so the row
  # exercises the table constraints rather than the application path. Defaults to a
  # valid reserved on-demand attempt.
  def insert_va(organization_id: org, project_id: project, verification_request_id: request, source_id: source,
                attempt_number: 1, origin: "on_demand", offset_minutes: nil, state: "reserved",
                network_outcome: nil, schema: "verification-attempt-v1")
    id = SecureRandom.uuid_v7
    params = [id, schema, organization_id, project_id, verification_request_id, source_id,
              attempt_number, origin, offset_minutes, network_outcome, state]
    conn.exec_params(<<~SQL, params)
      INSERT INTO verification_attempts
        (id, state_version, lock_version, created_at, updated_at, correlation_id, schema_version,
         organization_id, project_id, verification_request_id, source_id, attempt_number, origin,
         automated_slot_offset_minutes, reserved_at_utc, network_outcome, state)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,
              $3,$4,$5,$6,$7,$8,$9,now(),$10,$11)
    SQL
    id
  end

  describe "tenancy and least privilege" do
    it "forces row level security with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = 'verification_attempts'")
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
      policy = DbInspector.one("SELECT qual FROM pg_policies WHERE tablename = 'verification_attempts' AND policyname = 'verification_attempts_context'")
      expect(policy["qual"]).to include("f1_current_context_org")
    end

    it "grants the runtime role SELECT, INSERT and UPDATE but never DELETE" do
      privs = DbInspector.all(<<~SQL).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = 'verification_attempts' AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT UPDATE])
      expect(privs).not_to include("DELETE")
    end
  end

  describe "reservation constraints" do
    it "accepts a valid reserved on-demand attempt" do
      expect { insert_va }.not_to raise_error
    end

    it "requires a positive attempt number and a known origin, state and schema" do
      expect { insert_va(attempt_number: 0) }.to raise_error(PG::CheckViolation, /attempt_number/)
      expect { insert_va(origin: "sideways") }.to raise_error(PG::CheckViolation, /origin/)
      expect { insert_va(state: "aborted") }.to raise_error(PG::CheckViolation, /state/)
      expect { insert_va(schema: "verification-attempt-v2") }.to raise_error(PG::CheckViolation, /schema_version/)
    end

    it "ties the slot offset to the origin: on_demand has none, automated has one" do
      expect { insert_va(origin: "on_demand", offset_minutes: 5) }
        .to raise_error(PG::CheckViolation, /slot_offset_matches_origin/)
      # An automated attempt without a slot offset is equally invalid.
      expect { insert_va(origin: "automated", offset_minutes: nil, attempt_number: 2) }
        .to raise_error(PG::CheckViolation, /slot_offset_matches_origin/)
      expect { insert_va(origin: "automated", offset_minutes: 0, attempt_number: 3) }.not_to raise_error
    end

    it "forbids any observation outcome on a reserved attempt" do
      expect { insert_va(network_outcome: "response") }
        .to raise_error(PG::CheckViolation, /reserved_has_no_outcome/)
    end
  end

  describe "the attempt sequence and composite foreign keys" do
    it "rejects a duplicate attempt_number within a Request" do
      insert_va(attempt_number: 1)
      expect { insert_va(attempt_number: 1) }
        .to raise_error(PG::UniqueViolation, /verification_attempts_request_attempt_unique/)
    end

    it "refuses an attempt whose (organization, request) is not a Verification Request" do
      expect { insert_va(verification_request_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::ForeignKeyViolation, /verification_attempts_request_fk/)
    end

    it "refuses an attempt whose (organization, project, source) is not a Source" do
      expect { insert_va(source_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::ForeignKeyViolation, /verification_attempts_source_fk/)
    end
  end

  describe "the verification_attempts lifecycle guard" do
    it "allows exactly the reserved -> completed edge (S-05-005) and withholds the others" do
      id = insert_va
      # running and quarantined remain unavailable until their slices land.
      %w[running quarantined].each do |state|
        expect { conn.exec_params("UPDATE verification_attempts SET state = $2 WHERE id = $1::uuid", [id, state]) }
          .to raise_error(PG::RaiseException, /verification_attempt_transition_unavailable/)
      end
      # reserved -> completed (observation recording) is the one relaxed edge.
      expect { conn.exec_params("UPDATE verification_attempts SET state = 'completed' WHERE id = $1::uuid", [id]) }
        .not_to raise_error
      expect(DbInspector.one("SELECT state FROM verification_attempts WHERE id = $1::uuid", [id])["state"]).to eq("completed")
      # completed is terminal here: no further transition.
      expect { conn.exec_params("UPDATE verification_attempts SET state = 'quarantined' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_attempt_transition_unavailable/)
    end

    it "keeps the tenant/Project/Request/Source identity and the reservation facts immutable" do
      id = insert_va
      expect { conn.exec_params("UPDATE verification_attempts SET source_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_attempt_tenant_identity_immutable/)
      expect { conn.exec_params("UPDATE verification_attempts SET verification_request_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_attempt_tenant_identity_immutable/)
      expect { conn.exec_params("UPDATE verification_attempts SET attempt_number = 9 WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_attempt_reservation_immutable/)
      expect { conn.exec_params("UPDATE verification_attempts SET origin = 'automated' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /verification_attempt_reservation_immutable/)
    end
  end
end
