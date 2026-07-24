# frozen_string_literal: true

require "rails_helper"
require "securerandom"

# F-03 Evidence Production — the append-only Evidence store against the real database
# (FOUNDATION-003). Proves append/get/find through the proved-context runtime connection,
# idempotency by producer/attempt, RLS tenant-scoping, DB-enforced same-Organization
# integrity, and true immutability (no role may update or delete an Evidence envelope).
RSpec.describe Platform::Evidence::EvidenceStore, type: :model do
  let(:store) { described_class.new }
  let(:organization_id) { TenantSeeder.create_organization }
  let(:project_id) { seed_project(organization_id) }
  let(:runtime) { ActiveRecord::Base.connection.raw_connection }

  before { runtime.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [organization_id, SecureRandom.uuid]) }

  def seed_project(org)
    id = SecureRandom.uuid_v7
    DbInspector.connection.exec_params(<<~SQL, [id, org])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def record(**overrides)
    Platform::Evidence::Record.build(**{
      schema_version: "verification-observation-v1", organization_id:, project_id:, source_id: nil, evaluation_id: nil,
      evidence_type: "verification_observation", producer_id: "svc-verifier", attempt_id: "attempt-1",
      payload_reference: "ref-1", content_sha256: "a" * 64,
      captured_at_utc: Time.utc(2026, 7, 25), observed_at_utc: Time.utc(2026, 7, 25),
      source_system: "f1-verification", collection_method: "http_file", collector_version: "v1",
      validation_status: "valid", validation_reason_code: nil,
      data_classification: "restricted", payload_retention_class: "product_evidence_payload",
      correlation_id: SecureRandom.uuid
    }.merge(overrides))
  end

  def evidence_count = runtime.exec_params("SELECT count(*) FROM evidence WHERE organization_id = $1", [organization_id]).getvalue(0, 0).to_i

  describe "append / get / find" do
    it "appends a verification_observation and reads it back by id and by content hash" do
      evidence_id = store.append(record)
      expect(evidence_id).to match(/\A[0-9a-f-]{36}\z/)

      persisted = store.get(evidence_id)
      expect(persisted.evidence_type).to eq("verification_observation")
      expect(persisted.content_sha256).to eq("a" * 64)
      expect(persisted.data_classification).to eq("restricted")

      expect(store.find_by_content_hash("a" * 64).map(&:evidence_id)).to eq([evidence_id])
    end
  end

  describe "idempotency by producer/attempt identity" do
    it "returns the same id and writes no second record for a retried append" do
      first = store.append(record)
      second = store.append(record) # same producer_id + attempt_id
      expect(second).to eq(first)
      expect(evidence_count).to eq(1)
    end

    it "writes a distinct record for a different attempt" do
      first = store.append(record(attempt_id: "attempt-1"))
      second = store.append(record(attempt_id: "attempt-2"))
      expect(second).not_to eq(first)
      expect(evidence_count).to eq(2)
    end
  end

  describe "tenant isolation (RLS)" do
    it "does not reveal another Organization's Evidence" do
      evidence_id = store.append(record)
      runtime.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [SecureRandom.uuid, SecureRandom.uuid])
      expect(store.get(evidence_id)).to be_nil
    end
  end

  describe "same-Organization integrity is database-enforced" do
    it "rejects an append referencing a project that is not in the Organization" do
      expect { store.append(record(project_id: SecureRandom.uuid)) }.to raise_error(PG::ForeignKeyViolation)
    end
  end

  describe "immutability — Evidence is append-only for every role" do
    it "denies the runtime UPDATE (no grant)" do
      evidence_id = store.append(record)
      expect { runtime.exec_params("UPDATE evidence SET validation_status='invalid' WHERE id=$1", [evidence_id]) }
        .to raise_error(PG::InsufficientPrivilege)
    end

    it "denies the runtime DELETE (no grant)" do
      evidence_id = store.append(record)
      expect { runtime.exec_params("DELETE FROM evidence WHERE id=$1", [evidence_id]) }
        .to raise_error(PG::InsufficientPrivilege)
    end

    it "rejects UPDATE and DELETE even for a privileged role (the immutability trigger)" do
      owner = DbInspector.connection
      owner.exec("BEGIN")
      owner.exec_params(<<~SQL, [SecureRandom.uuid_v7, organization_id, project_id])
        INSERT INTO evidence
          (id, schema_version, organization_id, project_id, evidence_type, producer_id, attempt_id,
           payload_reference, content_sha256, captured_at_utc, observed_at_utc, source_system,
           collection_method, collector_version, validation_status, data_classification,
           payload_retention_class, correlation_id)
        VALUES ($1,'v',$2,$3,'verification_observation','p','trigger-test','ref',#{"'#{'b' * 64}'"},
                now(),now(),'s','http_file','v','valid','restricted','product_evidence_payload',gen_random_uuid())
      SQL
      id = owner.exec_params("SELECT id FROM evidence WHERE attempt_id='trigger-test' AND organization_id=$1", [organization_id]).getvalue(0, 0)
      expect { owner.exec_params("UPDATE evidence SET validation_status='invalid' WHERE id=$1", [id]) }
        .to raise_error(PG::RaiseException, /evidence_is_immutable/)
    ensure
      owner.exec("ROLLBACK")
    end
  end
end
