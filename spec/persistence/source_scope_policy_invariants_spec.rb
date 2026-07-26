# frozen_string_literal: true

require "rails_helper"

# S-05-006 database invariants — the minimal, canonical-shaped source_scope_policies
# table (schemas/POSTGRESQL_SCHEMA.md; contracts/S-06.json MTX-029). Modelled so the
# S-06 Source Scope sub-system extends it: forced tenant RLS, the least-privilege
# runtime matrix (SELECT/INSERT only — a T-IMM version table), full immutability, the
# scope/source agreement, the array and digest CHECKs, the per-(Source,version) unique,
# and the composite Source foreign key.
RSpec.describe "Source scope policy invariants", type: :model do
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
              sha256('k'::bytea), gen_random_uuid(), now(), 'proposed')
    SQL
    id
  end

  def insert_policy(organization_id: org, project_id: project, source_id: source, scope: "source",
                    version: "source-scope-interim-v1", schemes: "{https}", ports: "{443}",
                    includes: "{/}", excludes: "{}", query: "retain_all", digest: :ok)
    id = SecureRandom.uuid_v7
    content = digest == :ok ? "sha256('c'::bytea)" : "sha256('c'::bytea) || '\\x00'::bytea"
    conn.exec_params(<<~SQL, [id, organization_id, project_id, source_id, version, scope, "shop.example", schemes, ports, includes, excludes, query])
      INSERT INTO source_scope_policies
        (id, created_at, correlation_id, schema_version, organization_id, project_id, source_id,
         policy_version, scope, canonical_host, allowed_schemes, allowed_ports, include_prefixes,
         exclude_prefixes, query_handling, content_sha256)
      VALUES ($1, now(), gen_random_uuid(), 'source-scope-policy-v1', $2, $3, $4, $5, $6, $7,
              $8::text[], $9::integer[], $10::text[], $11::text[], $12, #{content})
    SQL
    id
  end

  describe "tenancy and least privilege" do
    it "forces row level security with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = 'source_scope_policies'")
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
    end

    it "grants the runtime role SELECT and INSERT only — never UPDATE or DELETE (T-IMM)" do
      privs = DbInspector.all(<<~SQL).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = 'source_scope_policies' AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT])
    end
  end

  describe "immutability (T-IMM) and shape" do
    it "accepts a valid source-scoped interim policy" do
      expect { insert_policy }.not_to raise_error
    end

    it "refuses any UPDATE or DELETE" do
      id = insert_policy
      expect { conn.exec_params("UPDATE source_scope_policies SET query_handling = 'x' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_scope_policy_immutable/)
      expect { conn.exec_params("DELETE FROM source_scope_policies WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_scope_policy_immutable/)
    end

    it "requires a source_id for a source-scoped policy and forbids one for org/project scope" do
      expect { insert_policy(scope: "source", source_id: nil) }
        .to raise_error(PG::CheckViolation, /scope_source_agreement/)
      expect { insert_policy(scope: "organization", source_id: source) }
        .to raise_error(PG::CheckViolation, /scope_source_agreement/)
    end

    it "requires non-empty scheme/port/include arrays and a 32-byte digest" do
      expect { insert_policy(schemes: "{}") }.to raise_error(PG::CheckViolation, /allowed_schemes/)
      expect { insert_policy(ports: "{}") }.to raise_error(PG::CheckViolation, /allowed_ports/)
      expect { insert_policy(includes: "{}") }.to raise_error(PG::CheckViolation, /include_prefixes/)
      expect { insert_policy(digest: :bad) }.to raise_error(PG::CheckViolation, /content_sha256/)
    end
  end

  describe "identity and the composite Source foreign key" do
    it "rejects a second policy of the same version for a Source" do
      insert_policy
      expect { insert_policy }.to raise_error(PG::UniqueViolation, /source_version_unique/)
    end

    it "refuses a policy whose (organization, project, source) is not a Source" do
      expect { insert_policy(source_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::ForeignKeyViolation, /source_scope_policies_source_fk/)
    end
  end
end
