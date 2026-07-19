# frozen_string_literal: true

# The Bootstrap Grant (onboarding-interim-v1) plus the platform command ledger,
# audit registry and event registry that WF-001 RequestBootstrapGrant commits
# atomically. Every table is FORCE ROW LEVEL SECURITY, keyed to the proved
# context: bootstrap_principal_digest for principal-scoped rows, context_org for
# the org-scoped audit/event rows (which under OD-013 carry the principal's uuid
# for the two bootstrap event types). f1_web/f1_worker get exactly the DML they
# use; they never own a table and never bypass RLS.
class CreateBootstrapGrantsAndLedger < ActiveRecord::Migration[8.1]
  def up
    create_bootstrap_grants
    create_command_ledger
    create_idempotency_records
    create_pretenant_authorization_decisions
    create_audit_record_registry
    create_event_registry
  end

  def down
    %w[event_registry audit_record_registry pretenant_authorization_decisions
       idempotency_records command_results command_executions bootstrap_grants].each do |t|
      execute "DROP TABLE IF EXISTS #{t};"
    end
  end

  private

  def force_rls(table, using:, check: using, grant: "SELECT, INSERT, UPDATE")
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check});
      REVOKE ALL ON #{table} FROM PUBLIC;
      GRANT #{grant} ON #{table} TO f1_runtime;
    SQL
  end

  def create_bootstrap_grants
    execute <<~SQL
      CREATE TABLE bootstrap_grants (
        id                         uuid PRIMARY KEY,
        state_version              bigint NOT NULL DEFAULT 0,
        lock_version               bigint NOT NULL DEFAULT 0,
        created_at                 timestamptz(6) NOT NULL,
        updated_at                 timestamptz(6) NOT NULL,
        correlation_id             uuid NOT NULL,
        causation_id               uuid NOT NULL,
        command_id                 uuid,
        idempotency_key_digest     bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        content_sha256             bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),
        bootstrap_principal_digest bytea NOT NULL CHECK (octet_length(bootstrap_principal_digest) = 32),
        allowed_action             text NOT NULL CHECK (allowed_action = 'organization.bootstrap'),
        issuer_service_identity_id uuid NOT NULL,
        policy_version             text NOT NULL,
        issued_at                  timestamptz(6) NOT NULL,
        expires_at                 timestamptz(6) NOT NULL,
        state                      text NOT NULL CHECK (state IN ('issued','consumed','revoked','expired')),
        consuming_command_id       uuid,
        organization_id            uuid,
        reason_code                text,
        CONSTRAINT grant_lifetime_is_fifteen_minutes CHECK (expires_at = issued_at + interval '15 minutes')
      );
      -- At most one issued unexpired grant per principal, and at most one consumed
      -- self-service grant per principal (onboarding-interim-v1).
      CREATE UNIQUE INDEX one_issued_grant_per_principal ON bootstrap_grants (bootstrap_principal_digest)
        WHERE state = 'issued';
      CREATE UNIQUE INDEX one_consumed_grant_per_principal ON bootstrap_grants (bootstrap_principal_digest)
        WHERE state = 'consumed';
    SQL
    force_rls("bootstrap_grants",
              using: "bootstrap_principal_digest = f1_current_bootstrap_principal()")
  end

  def create_command_ledger
    execute <<~SQL
      CREATE TABLE command_executions (
        id                         uuid PRIMARY KEY,
        schema_version             text NOT NULL,
        created_at                 timestamptz(6) NOT NULL,
        correlation_id             uuid NOT NULL,
        causation_id               uuid NOT NULL,
        command_id                 uuid NOT NULL,
        idempotency_key_digest     bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        content_sha256             bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),
        command_type               text NOT NULL,
        command_schema_version     text NOT NULL,
        actor_id                   uuid,
        service_identity_id        uuid,
        organization_id            uuid,
        bootstrap_principal_digest bytea CHECK (bootstrap_principal_digest IS NULL OR octet_length(bootstrap_principal_digest) = 32),
        project_id                 uuid,
        target_type                text NOT NULL,
        target_id                  uuid,
        action                     text NOT NULL,
        expected_state_version     bigint,
        requested_at               timestamptz(6) NOT NULL,
        client_requested_at        timestamptz(6),
        authorization_check_at     timestamptz(6) NOT NULL,
        policy_versions            jsonb NOT NULL,
        canonical_payload          jsonb NOT NULL,
        request_sha256             bytea NOT NULL CHECK (octet_length(request_sha256) = 32),
        CONSTRAINT exactly_one_actor_or_service CHECK ((actor_id IS NULL) <> (service_identity_id IS NULL))
      );
    SQL
    force_rls("command_executions", grant: "SELECT, INSERT",
              using: "bootstrap_principal_digest = f1_current_bootstrap_principal() OR organization_id = f1_current_context_org()")

    execute <<~SQL
      CREATE TABLE command_results (
        id                        uuid PRIMARY KEY,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        causation_id              uuid NOT NULL,
        command_id                uuid NOT NULL,
        idempotency_key_digest    bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        content_sha256            bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),
        command_execution_id      uuid NOT NULL UNIQUE,
        result_schema_version     text NOT NULL,
        outcome                   text NOT NULL CHECK (outcome IN ('success','failure')),
        organization_id           uuid,
        project_id                uuid,
        actor_id                  uuid,
        service_identity_id       uuid,
        completed_at              timestamptz(6) NOT NULL,
        authorization_check_at    timestamptz(6) NOT NULL,
        target_refs               jsonb NOT NULL,
        resulting_state_version   bigint,
        governing_policy_versions jsonb NOT NULL,
        error_class               text,
        error_code                text,
        reason_code               text,
        severity                  text,
        retryable                 boolean,
        recovery_action           text,
        support_reference         text,
        authorized_payload        jsonb NOT NULL,
        audit_record_id           uuid NOT NULL,
        CONSTRAINT exactly_one_actor_or_service CHECK ((actor_id IS NULL) <> (service_identity_id IS NULL)),
        CONSTRAINT failure_tuple_present_only_on_failure CHECK (
          (outcome = 'success' AND error_class IS NULL AND error_code IS NULL AND reason_code IS NULL
             AND severity IS NULL AND retryable IS NULL AND recovery_action IS NULL) OR
          (outcome = 'failure' AND error_class IS NOT NULL AND error_code IS NOT NULL AND reason_code IS NOT NULL
             AND severity IS NOT NULL AND retryable IS NOT NULL AND recovery_action IS NOT NULL)
        )
      );
    SQL
    # command_results carries no principal column; it is visible exactly when its
    # parent execution is (same proved context), enforced through the RLS-filtered
    # subquery on command_executions.
    force_rls("command_results", grant: "SELECT, INSERT",
              using: "command_execution_id IN (SELECT id FROM command_executions)")
  end

  def create_idempotency_records
    execute <<~SQL
      CREATE TABLE idempotency_records (
        id                         uuid PRIMARY KEY,
        state_version              bigint NOT NULL DEFAULT 0,
        lock_version               bigint NOT NULL DEFAULT 0,
        created_at                 timestamptz(6) NOT NULL,
        updated_at                 timestamptz(6) NOT NULL,
        scope_kind                 text NOT NULL CHECK (scope_kind IN ('organization','bootstrap_principal')),
        organization_id            uuid,
        bootstrap_principal_digest bytea CHECK (bootstrap_principal_digest IS NULL OR octet_length(bootstrap_principal_digest) = 32),
        command_type               text NOT NULL,
        target_type                text NOT NULL,
        target_id                  uuid,
        key_digest                 bytea NOT NULL CHECK (octet_length(key_digest) = 32),
        request_sha256             bytea NOT NULL CHECK (octet_length(request_sha256) = 32),
        command_execution_id       uuid NOT NULL,
        command_result_id          uuid,
        retain_until               timestamptz(6) NOT NULL,
        CONSTRAINT idempotency_scope_shape CHECK (
          (scope_kind = 'bootstrap_principal' AND bootstrap_principal_digest IS NOT NULL AND organization_id IS NULL) OR
          (scope_kind = 'organization' AND organization_id IS NOT NULL AND bootstrap_principal_digest IS NULL)
        )
      );
      CREATE UNIQUE INDEX idempotency_scope_key ON idempotency_records (
        scope_kind, command_type, target_type, key_digest,
        coalesce(organization_id, '00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(bootstrap_principal_digest, ''::bytea),
        coalesce(target_id, '00000000-0000-0000-0000-000000000000'::uuid)
      );
    SQL
    force_rls("idempotency_records",
              using: "bootstrap_principal_digest = f1_current_bootstrap_principal() OR organization_id = f1_current_context_org()")
  end

  def create_pretenant_authorization_decisions
    execute <<~SQL
      CREATE TABLE pretenant_authorization_decisions (
        id                         uuid PRIMARY KEY,
        schema_version             text NOT NULL,
        created_at                 timestamptz(6) NOT NULL,
        correlation_id             uuid NOT NULL,
        causation_id               uuid NOT NULL,
        command_id                 uuid NOT NULL UNIQUE,
        idempotency_key_digest     bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        content_sha256             bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),
        bootstrap_principal_digest bytea NOT NULL CHECK (octet_length(bootstrap_principal_digest) = 32),
        receipt_id                 uuid NOT NULL,
        subject_service_identity_id uuid NOT NULL,
        action                     text NOT NULL,
        resource_type              text NOT NULL,
        resource_id                uuid,
        decision                   text NOT NULL CHECK (decision IN ('allow','deny')),
        reason_code                text NOT NULL,
        policy_versions            jsonb NOT NULL,
        policy_hash                bytea CHECK (policy_hash IS NULL OR octet_length(policy_hash) = 32),
        decided_at                 timestamptz(6) NOT NULL
      );
    SQL
    force_rls("pretenant_authorization_decisions", grant: "SELECT, INSERT",
              using: "bootstrap_principal_digest = f1_current_bootstrap_principal()")
  end

  def create_audit_record_registry
    execute <<~SQL
      CREATE TABLE audit_record_registry (
        id                       uuid PRIMARY KEY,
        schema_version           text NOT NULL,
        created_at               timestamptz(6) NOT NULL,
        occurred_at              timestamptz(6) NOT NULL,
        partition_month          date NOT NULL,
        organization_id          uuid NOT NULL,
        workflow_id              text NOT NULL CHECK (workflow_id ~ '^WF-[0-9]{3}$'),
        actor_id                 uuid,
        service_identity_id      uuid,
        correlation_id           uuid NOT NULL,
        causation_id             uuid NOT NULL,
        command_id               uuid,
        idempotency_key_digest   bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        entity_type              text NOT NULL,
        entity_id                uuid NOT NULL,
        from_state               text,
        to_state                 text,
        outcome                  text NOT NULL,
        reason_code              text,
        classification           text NOT NULL,
        payload                  jsonb NOT NULL,
        content_sha256           bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
        retention_class          text NOT NULL CHECK (retention_class = 'security_audit'),
        CONSTRAINT exactly_one_actor_or_service CHECK ((actor_id IS NULL) <> (service_identity_id IS NULL)),
        CONSTRAINT partition_month_is_first_of_month CHECK (partition_month = date_trunc('month', occurred_at AT TIME ZONE 'UTC')::date)
      );
    SQL
    force_rls("audit_record_registry", grant: "SELECT, INSERT",
              using: "organization_id = f1_current_context_org()")
  end

  def create_event_registry
    execute <<~SQL
      CREATE TABLE event_registry (
        id                 uuid PRIMARY KEY,
        schema_version     text NOT NULL,
        created_at         timestamptz(6) NOT NULL,
        event_type         text NOT NULL,
        event_schema_version text NOT NULL,
        workflow_id        text NOT NULL CHECK (workflow_id ~ '^WF-[0-9]{3}$'),
        event_profile      text NOT NULL CHECK (event_profile IN
          ('created','state_transition','attempt','decision','policy_activation','projection','failure','recovery')),
        occurred_at        timestamptz(6) NOT NULL,
        organization_id    uuid NOT NULL,
        project_id         uuid,
        aggregate_type     text NOT NULL,
        aggregate_id       uuid NOT NULL,
        aggregate_version  bigint NOT NULL,
        partition_month    date NOT NULL,
        correlation_id     uuid NOT NULL,
        causation_id       uuid NOT NULL,
        command_id         uuid,
        idempotency_key_digest bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        audit_record_id    uuid NOT NULL,
        event_bytes        bytea NOT NULL CHECK (octet_length(event_bytes) BETWEEN 2 AND 1048576),
        event_byte_count   bigint NOT NULL CHECK (event_byte_count = octet_length(event_bytes)),
        event_sha256       bytea NOT NULL CHECK (octet_length(event_sha256) = 32 AND event_sha256 = public.digest(event_bytes, 'sha256')),
        CONSTRAINT partition_month_is_first_of_month CHECK (partition_month = date_trunc('month', occurred_at AT TIME ZONE 'UTC')::date)
      );
    SQL
    force_rls("event_registry", grant: "SELECT, INSERT",
              using: "organization_id = f1_current_context_org()")
  end
end
