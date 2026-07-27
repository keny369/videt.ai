# frozen_string_literal: true

require "rails_helper"

# S-06-003 database invariants — the source_scope_change_requests aggregate table
# (schemas/POSTGRESQL_SCHEMA.md :289; WORKFLOW_SPECIFICATIONS.md § Source Scope Change
# Contract :414): forced tenant RLS, the least-privilege runtime matrix (SELECT/INSERT
# only in this tranche — no transition is built yet), terminal-row immutability and the
# frozen-facts / refused-transition guard, the state and reason CHECKs, the 32-byte digest
# CHECKs, the array cardinality CHECKs, and the composite Source foreign key.
RSpec.describe "Source scope change request invariants", type: :model do
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

  def insert_source(organization_id: org, project_id: project, host: "shop.example")
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, project_id, host])
      INSERT INTO sources
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, project_id,
         submitted_root_uri, canonical_root_uri, canonical_host, registration_schema_version, host_normalization_version,
         registration_origin, registering_account_id, registration_command_id, registration_idempotency_key_digest,
         registration_authorization_decision_id, registered_at, state)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,'https://' || $4 || '/', 'https://' || $4 || '/', $4,
              'source-registration-v1','ascii-host-v1','human_command', gen_random_uuid(), gen_random_uuid(),
              sha256('k'::bytea), gen_random_uuid(), now(), 'verified')
    SQL
    id
  end

  def insert_request(organization_id: org, project_id: project, source_id: source,
                     reason: "narrow the crawl scope to /shop only", state: "pending",
                     current_digest: :ok, proposed_digest: :ok, schemes: "{https}", ports: "{443}",
                     includes: "{/shop}", excludes: "{}", query: "retain_all")
    id = SecureRandom.uuid_v7
    cur = current_digest == :ok ? "sha256('a'::bytea)" : "sha256('a'::bytea) || '\\x00'::bytea"
    prop = proposed_digest == :ok ? "sha256('b'::bytea)" : "sha256('b'::bytea) || '\\x00'::bytea"
    conn.exec_params(<<~SQL, [id, organization_id, project_id, source_id, reason, state, schemes, ports, includes, excludes, query])
      INSERT INTO source_scope_change_requests
        (id, state_version, created_at, updated_at, correlation_id, schema_version, organization_id, project_id,
         source_id, requester_account_id, expected_active_policy_version, current_content_sha256,
         proposed_canonical_host, proposed_allowed_schemes, proposed_allowed_ports, proposed_include_prefixes,
         proposed_exclude_prefixes, proposed_query_handling, proposed_content_sha256, request_reason,
         requested_at_utc, due_at_utc, state, idempotency_key_digest)
      VALUES ($1,0,now(),now(),gen_random_uuid(),'source-scope-change-request-v1',$2,$3,
              $4, gen_random_uuid(), 'source-scope-interim-v1', #{cur},
              'shop.example', $7::text[], $8::integer[], $9::text[],
              $10::text[], $11, #{prop}, $5,
              now(), now() + interval '24 hours', $6, sha256('i'::bytea))
    SQL
    id
  end

  describe "tenancy and least privilege" do
    it "forces row level security with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = 'source_scope_change_requests'")
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
    end

    it "grants the runtime role SELECT, INSERT and UPDATE (UPDATE added by S-06-004 for the decision edges)" do
      privs = DbInspector.all(<<~SQL).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = 'source_scope_change_requests' AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT UPDATE])
    end
  end

  describe "shape CHECKs" do
    it "accepts a valid pending request" do
      expect { insert_request }.not_to raise_error
    end

    it "enforces the reason 20-2,000 character bound" do
      expect { insert_request(reason: "a" * 19) }.to raise_error(PG::CheckViolation, /request_reason/)
      expect { insert_request(reason: "a" * 20) }.not_to raise_error
      expect { insert_request(reason: "a" * 2001) }.to raise_error(PG::CheckViolation, /request_reason/)
    end

    it "restricts state to the canonical set" do
      expect { insert_request(state: "acknowledged") }.to raise_error(PG::CheckViolation, /source_scope_change_requests_state_check/)
    end

    it "requires 32-byte current and proposed digests" do
      expect { insert_request(current_digest: :bad) }.to raise_error(PG::CheckViolation, /current_content_sha256/)
      expect { insert_request(proposed_digest: :bad) }.to raise_error(PG::CheckViolation, /proposed_content_sha256/)
    end

    it "requires non-empty scheme/port/include arrays" do
      expect { insert_request(schemes: "{}") }.to raise_error(PG::CheckViolation, /proposed_allowed_schemes/)
      expect { insert_request(ports: "{}") }.to raise_error(PG::CheckViolation, /proposed_allowed_ports/)
      expect { insert_request(includes: "{}") }.to raise_error(PG::CheckViolation, /proposed_include_prefixes/)
    end
  end

  describe "terminal-row immutability and refused transitions" do
    it "permits the terminal edges pending -> approved/rejected/canceled (S-06-004) and expired (S-06-005)" do
      %w[approved rejected canceled expired].each do |to|
        rid = insert_request
        expect { conn.exec_params("UPDATE source_scope_change_requests SET state = $2 WHERE id = $1::uuid", [rid, to]) }
          .not_to raise_error
      end
    end

    it "refuses a pending -> pending UPDATE that mutates decision facts (ADR-063 hardening)" do
      id = insert_request
      expect { conn.exec_params("UPDATE source_scope_change_requests SET decision_actor_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_scope_change_request_transition_unavailable/)
      expect { conn.exec_params("UPDATE source_scope_change_requests SET activated_policy_version = 'source-scope-v99' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_scope_change_request_transition_unavailable/)
    end

    it "freezes created_at and correlation_id provenance on a pending row (ADR-063 hardening)" do
      id = insert_request
      expect { conn.exec_params("UPDATE source_scope_change_requests SET correlation_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /facts_immutable/)
    end

    it "makes a terminal request fully immutable" do
      id = insert_request
      conn.exec_params("UPDATE source_scope_change_requests SET state = 'approved' WHERE id = $1::uuid", [id])
      expect { conn.exec_params("UPDATE source_scope_change_requests SET decision_reason = 'anything at all here' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_scope_change_request_immutable/)
    end

    it "freezes the tenant identity and the proposed facts" do
      id = insert_request
      expect { conn.exec_params("UPDATE source_scope_change_requests SET source_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /tenant_identity_immutable/)
      expect { conn.exec_params("UPDATE source_scope_change_requests SET request_reason = 'a totally different reason here' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /facts_immutable/)
    end

    it "refuses DELETE" do
      id = insert_request
      expect { conn.exec_params("DELETE FROM source_scope_change_requests WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_scope_change_request_immutable/)
    end
  end

  describe "the composite Source foreign key" do
    it "refuses a request whose (organization, project, source) is not a Source" do
      expect { insert_request(source_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::ForeignKeyViolation, /source_scope_change_requests_source_fk/)
    end
  end
end
