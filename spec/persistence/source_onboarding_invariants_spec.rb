# frozen_string_literal: true

require "rails_helper"

# S-04 Source onboarding database invariants (schemas/POSTGRESQL_SCHEMA.md :128,
# :284; WORKFLOW_SPECIFICATIONS.md :402-408; contracts/S-04.json).
#
# The properties that must hold in the database itself: forced tenant RLS, the
# least-privilege runtime matrix (no DELETE), the immutable registration facts,
# the withheld state transition, the ratified (organization, project, host)
# uniqueness over non-removed Sources including post-removal re-registration, the
# composite Project foreign key that prevents a cross-Project or cross-Organization
# link, and the deliberate absence of any verification/scope schema in this tranche.
RSpec.describe "Source onboarding invariants", type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:project) { seed_draft_project(org) }
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
    digest = { value: Digest::SHA256.digest("k-#{id}"), format: 1 }
    conn.exec_params(<<~SQL, [id, organization_id, project_id, host, state, digest])
      INSERT INTO sources
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, project_id,
         submitted_root_uri, canonical_root_uri, canonical_host,
         registration_schema_version, host_normalization_version, registration_origin,
         registering_account_id, registration_command_id, registration_idempotency_key_digest,
         registration_authorization_decision_id, registered_at, state)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,
              'https://' || $4 || '/', 'https://' || $4 || '/', $4,
              'source-registration-v1','ascii-host-v1','human_command',
              gen_random_uuid(), gen_random_uuid(), $6,
              gen_random_uuid(), now(), $5)
    SQL
    id
  end

  describe "tenancy and least privilege" do
    it "forces row level security on sources with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = 'sources'")
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
      policy = DbInspector.one("SELECT qual FROM pg_policies WHERE tablename = 'sources' AND policyname = 'sources_context'")
      expect(policy["qual"]).to include("f1_current_context_org")
    end

    it "grants the runtime role SELECT, INSERT and UPDATE on sources but never DELETE" do
      privs = DbInspector.all(<<~SQL).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = 'sources' AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT UPDATE])
      expect(privs).not_to include("DELETE")
    end
  end

  describe "the sources lifecycle guard" do
    it "refuses every state transition while verification/scope are unavailable" do
      id = insert_source
      %w[verified active disabled removed].each do |state|
        expect { conn.exec_params("UPDATE sources SET state = $2 WHERE id = $1::uuid", [id, state]) }
          .to raise_error(PG::RaiseException, /source_lifecycle_transition_unavailable/)
      end
      expect(DbInspector.one("SELECT state FROM sources WHERE id = $1::uuid", [id])["state"]).to eq("proposed")
    end

    it "keeps the tenant/Project identity and the registration provenance immutable" do
      id = insert_source
      expect { conn.exec_params("UPDATE sources SET project_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_tenant_identity_immutable/)
      expect { conn.exec_params("UPDATE sources SET canonical_host = 'other.example' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_registration_immutable/)
      expect { conn.exec_params("UPDATE sources SET submitted_root_uri = 'https://x.example/' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /source_registration_immutable/)
    end
  end

  describe "uniqueness over non-removed Sources" do
    it "rejects a second non-removed Source with the same (organization, project, host)" do
      insert_source(host: "dup.example")
      expect { insert_source(host: "dup.example") }
        .to raise_error(PG::UniqueViolation, /sources_nonremoved_host_unique/)
    end

    it "does not let a committed removed Source block re-registration of the same host" do
      insert_source(host: "gone.example", state: "removed")
      expect { insert_source(host: "gone.example", state: "proposed") }.not_to raise_error
      expect(DbInspector.all("SELECT id FROM sources WHERE canonical_host = 'gone.example'").size).to eq(2)
    end

    it "allows the same host in a different Project" do
      insert_source(host: "shared.example")
      other_project = seed_draft_project(org)
      expect { insert_source(project_id: other_project, host: "shared.example") }.not_to raise_error
    end
  end

  describe "the composite Project foreign key" do
    it "refuses a Source whose (organization, project) pair is not a Project" do
      other_org = TenantSeeder.create_organization
      foreign_project = seed_draft_project(other_org)
      # A Source claiming this Organization but another Organization's Project has
      # no matching (organization_id, project_id) row in projects.
      expect { insert_source(organization_id: org, project_id: foreign_project, host: "x.example") }
        .to raise_error(PG::ForeignKeyViolation, /sources_project_fk/)
      expect { insert_source(organization_id: org, project_id: SecureRandom.uuid_v7, host: "y.example") }
        .to raise_error(PG::ForeignKeyViolation, /sources_project_fk/)
    end
  end

  describe "no observation or scope subsystem beyond challenge issuance" do
    # S-05-001 (IssueVerificationChallenge) adds `verification_requests`; the
    # observation, source-set and scope-change tables remain later slices.
    it "has no attempt, source-set or scope-change tables" do
      %w[verification_attempts source_set_versions source_set_memberships
         source_scope_change_requests].each do |table|
        expect(DbInspector.one("SELECT to_regclass('public.#{table}') AS t")["t"]).to be_nil
      end
    end
  end
end
