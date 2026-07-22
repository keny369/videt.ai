# frozen_string_literal: true

require "rails_helper"

# Referential integrity for Service Identity attribution across the shared
# ledger (schemas/POSTGRESQL_SCHEMA.md:43 "every discriminator arm has the named
# FK/existence check"; :202 the `service_identities` record; :166 platform-control
# scope).
#
# Two separate questions, deliberately answered in two separate places:
#
#   EXISTENCE is a constraint. Every non-null Service Identity attribution names
#   a registered row, enforced by foreign key, forever — including on immutable
#   historical ledger rows.
#
#   STATUS is an execution predicate. Whether an identity may still act is asked
#   at the moment work is executed, never of history: `command_executions`,
#   `command_results`, `audit_record_registry` and
#   `pretenant_authorization_decisions` are immutable records of what a service
#   did, and suspending that service must not retroactively invalidate them.
RSpec.describe "Service Identity integrity", type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:unknown) { SecureRandom.uuid_v7 }
  let(:service) { Platform::ServiceIdentity.identity_service }

  def owner = DbInspector.connection

  LEDGER_COLUMNS = {
    "command_executions" => "service_identity_id",
    "command_results" => "service_identity_id",
    "audit_record_registry" => "service_identity_id",
    "bootstrap_grants" => "issuer_service_identity_id",
    "pretenant_authorization_decisions" => "subject_service_identity_id"
  }.freeze

  describe "every Service Identity attribution names a registered identity" do
    it "declares a foreign key on all five shared-ledger columns" do
      bound = DbInspector.all(<<~SQL).to_h { |r| [r["table_name"], r["column_name"]] }
        SELECT c.conrelid::regclass::text AS table_name, a.attname AS column_name
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.contype = 'f' AND c.confrelid = 'service_identities'::regclass
      SQL
      expect(bound).to eq(LEDGER_COLUMNS.merge("scheduled_actions" => "executing_service_identity_id"))
    end

    it "rejects an unknown Service Identity in command_executions" do
      expect { insert_execution(service_identity_id: unknown) }
        .to raise_error(PG::ForeignKeyViolation, /command_executions_service_identity_fkey/)
      expect(DbInspector.count("command_executions")).to eq(0)
    end

    it "rejects an unknown Service Identity in command_results" do
      execution = insert_execution(service_identity_id: service)
      audit = insert_audit(service_identity_id: service)
      expect { insert_result(execution, service_identity_id: unknown, audit_record_id: audit) }
        .to raise_error(PG::ForeignKeyViolation, /command_results_service_identity_fkey/)
      expect(DbInspector.count("command_results")).to eq(0)
    end

    it "rejects an unknown Service Identity in audit_record_registry" do
      expect { insert_audit(service_identity_id: unknown) }
        .to raise_error(PG::ForeignKeyViolation, /audit_records_service_identity_fkey/)
      expect(DbInspector.count("audit_record_registry")).to eq(0)
    end

    it "rejects an unknown issuing Service Identity in bootstrap_grants" do
      expect { insert_bootstrap_grant(issuer: unknown) }
        .to raise_error(PG::ForeignKeyViolation, /bootstrap_grants_issuer_service_identity_fkey/)
      expect(DbInspector.count("bootstrap_grants")).to eq(0)
    end

    it "rejects an unknown subject Service Identity in pretenant_authorization_decisions" do
      expect { insert_pretenant_decision(subject: unknown) }
        .to raise_error(PG::ForeignKeyViolation, /pretenant_decisions_subject_service_identity_fkey/)
      expect(DbInspector.count("pretenant_authorization_decisions")).to eq(0)
    end
  end

  describe "human actor attribution is untouched" do
    it "accepts an actor-attributed execution with no Service Identity at all" do
      account = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                            subject: "actor-#{SecureRandom.hex(6)}")
      expect { insert_execution(actor_id: account) }.not_to raise_error
      row = DbInspector.one("SELECT actor_id, service_identity_id FROM command_executions")
      expect(row["actor_id"]).to eq(account)
      expect(row["service_identity_id"]).to be_nil
    end

    it "still refuses a row carrying both, or neither, attribution" do
      account = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                            subject: "actor-#{SecureRandom.hex(6)}")
      expect { insert_execution(actor_id: account, service_identity_id: service) }
        .to raise_error(PG::CheckViolation, /exactly_one_actor_or_service/)
      expect { insert_execution }
        .to raise_error(PG::CheckViolation, /exactly_one_actor_or_service/)
    end
  end

  describe "status is an execution predicate, never a property of history" do
    it "keeps historical ledger rows valid and joinable after the identity is suspended or revoked" do
      execution = insert_execution(service_identity_id: service)
      insert_audit(id: audit_id = SecureRandom.uuid_v7, service_identity_id: service)
      insert_result(execution, service_identity_id: service, audit_record_id: audit_id)

      %w[suspended revoked].each do |status|
        set_status(service, status)
        joined = DbInspector.one(<<~SQL)
          SELECT e.id, s.status
          FROM command_executions e
          JOIN service_identities s ON s.id = e.service_identity_id
        SQL
        expect(joined["id"]).to eq(execution), "history became unjoinable while #{status}"
        expect(joined["status"]).to eq(status)
        expect(DbInspector.count("command_results")).to eq(1)
        expect(DbInspector.count("audit_record_registry")).to eq(1)
      end
    ensure
      set_status(service, "active")
    end

    it "answers the execution-boundary question separately, and only for an active identity" do
      pg = ActiveRecord::Base.connection.raw_connection
      expect(Platform::ServiceIdentity.active?(service, pg)).to be(true)
      expect(Platform::ServiceIdentity.active?(unknown, pg)).to be(false)

      set_status(service, "revoked")
      expect(Platform::ServiceIdentity.active?(service, pg)).to be(false)
    ensure
      set_status(service, "active")
    end

    it "exposes the predicate as a fixed boolean that cannot enumerate the register" do
      fn = DbInspector.one(<<~SQL)
        SELECT p.prosecdef, array_to_string(p.proconfig, ';') AS config,
               pg_get_function_result(p.oid) AS result,
               has_function_privilege('public', p.oid, 'EXECUTE') AS public_exec,
               has_function_privilege('f1_web', p.oid, 'EXECUTE') AS web_exec
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'f1_service_identity_active'
      SQL
      expect(fn["result"]).to eq("boolean")
      expect(fn["prosecdef"]).to eq("t")
      expect(fn["config"]).to eq("search_path=pg_catalog, public")
      expect(fn["public_exec"]).to eq("f")
      expect(fn["web_exec"]).to eq("t")
    end
  end

  describe "the reserved identities" do
    it "registers exactly the reserved rows, all active" do
      rows = DbInspector.all("SELECT id, subject, status FROM service_identities ORDER BY subject")
      expect(rows.map { |r| r["subject"] })
        .to eq(Platform::ServiceIdentity::RESERVED.map { |_, subject, *| subject }.sort)
      expect(rows.map { |r| r["status"] }).to all(eq("active"))
    end
  end

  # ---- fixtures (owner connection: these are integrity assertions, not workflows)

  def insert_execution(id: SecureRandom.uuid_v7, actor_id: nil, service_identity_id: nil)
    owner.exec_params(<<~SQL, [id, actor_id, service_identity_id, org])
      INSERT INTO command_executions
        (id, schema_version, created_at, correlation_id, causation_id, command_id, command_type,
         command_schema_version, actor_id, service_identity_id, organization_id, target_type, target_id,
         action, requested_at, authorization_check_at, policy_versions, canonical_payload, request_sha256)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'spec.integrity','1.0',
              $2::uuid,$3::uuid,$4::uuid,'invitation',gen_random_uuid(),'spec.integrity',
              now(),now(),'{}'::jsonb,'{}'::jsonb,decode(repeat('ab',32),'hex'))
    SQL
    id
  end

  def insert_result(execution_id, service_identity_id:, audit_record_id: nil)
    audit_record_id ||= insert_audit(service_identity_id:)
    owner.exec_params(<<~SQL, [SecureRandom.uuid_v7, execution_id, service_identity_id, org, audit_record_id])
      INSERT INTO command_results
        (id, schema_version, created_at, correlation_id, causation_id, command_id, command_execution_id,
         result_schema_version, outcome, organization_id, service_identity_id, completed_at,
         authorization_check_at, target_refs, governing_policy_versions, authorized_payload, audit_record_id)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),$2::uuid,'1.0','success',
              $4::uuid,$3::uuid,now(),now(),'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,$5::uuid)
    SQL
  end

  def insert_audit(id: SecureRandom.uuid_v7, service_identity_id:)
    owner.exec_params(<<~SQL, [id, service_identity_id, org])
      INSERT INTO audit_record_registry
        (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
         service_identity_id, correlation_id, causation_id, command_id, entity_type, entity_id,
         outcome, classification, payload, content_sha256, retention_class)
      VALUES ($1,'1.0',now(),now(),date_trunc('month', now())::date,$3::uuid,'WF-001',
              $2::uuid,gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'invitation',gen_random_uuid(),
              'success','restricted','{}'::jsonb,decode(repeat('cd',32),'hex'),'security_audit')
    SQL
    id
  end

  def insert_bootstrap_grant(issuer:)
    owner.exec_params(<<~SQL, [SecureRandom.uuid_v7, issuer])
      INSERT INTO bootstrap_grants
        (id, state_version, lock_version, created_at, updated_at, correlation_id, causation_id,
         bootstrap_principal_digest, allowed_action, issuer_service_identity_id, policy_version,
         issued_at, expires_at, state)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),gen_random_uuid(),
              decode(repeat('ef',32),'hex'),'organization.bootstrap',$2::uuid,'onboarding-interim-v1',
              now(),now()+interval '15 minutes','issued')
    SQL
  end

  def insert_pretenant_decision(subject:)
    owner.exec_params(<<~SQL, [SecureRandom.uuid_v7, subject])
      INSERT INTO pretenant_authorization_decisions
        (id, schema_version, created_at, correlation_id, causation_id, command_id,
         bootstrap_principal_digest, receipt_id, subject_service_identity_id, action, resource_type,
         decision, reason_code, policy_versions, decided_at)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
              decode(repeat('ef',32),'hex'),gen_random_uuid(),$2::uuid,'spec.integrity','bootstrap_grant',
              'allow','spec','{}'::jsonb,now())
    SQL
  end

  def set_status(id, status)
    owner.exec_params(<<~SQL, [id, status])
      UPDATE service_identities
      SET status = $2,
          activated_at = CASE WHEN $2 = 'active' THEN now() END,
          revoked_at = CASE WHEN $2 = 'revoked' THEN now() END
      WHERE id = $1::uuid
    SQL
  end
end
