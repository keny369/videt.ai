# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # All persistence for the WF-001 self-service BootstrapOrganization commit,
    # written inside the caller's unit of work on the combined
    # principal+Organization context f1_enter_self_service_context established. The
    # Bootstrap Grant is read and consumed in the principal limb of that context;
    # every tenant root and the org-scoped ledger are written in the Organization
    # limb. No method here calls a billing provider.
    #
    # Service-attributed throughout: the approved bootstrap service is the only
    # actor, so service_identity_id is set and actor_id stays null across the whole
    # genesis (:238; MTX-002 bootstrap-service-only exception).
    class OrganizationGenesisStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Resolve the self-service receipt as owner and enter the combined
      # principal+real-Organization context. Returns the receipt fields, or nil.
      def enter_self_service_context(receipt_digest:, organization_id:, correlation_id:)
        sql = <<~SQL
          SELECT receipt_id, purpose, validated_at, expires_at, email_verified, mfa_satisfied,
                 issuer_key, issuer_subject, receipt_schema_version, assurance_version,
                 encode(bootstrap_principal_digest,'hex') AS principal_hex, organization_id,
                 normalized_email
          FROM f1_enter_self_service_context($1, $2::uuid, $3::uuid)
        SQL
        exec(sql, [bytea(receipt_digest), organization_id, correlation_id]).to_a.first
      end

      # Tier-zero serialization on the not-yet-existing bootstrap principal, so two
      # concurrent self-service commits for one principal are decided one at a time.
      def lock_principal(principal_hex)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["bootstrap-principal:#{principal_hex}"])
      end

      # The single issued grant for this principal (RLS-scoped to the principal).
      def issued_grant
        exec(<<~SQL, []).to_a.first
          SELECT id, state_version, encode(bootstrap_principal_digest,'hex') AS principal_hex,
                 issued_at, expires_at, state
          FROM bootstrap_grants WHERE state = 'issued' LIMIT 1
        SQL
      end

      def consumed_grant_exists?
        !exec("SELECT 1 FROM bootstrap_grants WHERE state = 'consumed' LIMIT 1", []).values.empty?
      end

      def find_idempotency(principal_hex:, command_type:, key_digest:)
        sql = <<~SQL
          SELECT encode(request_sha256,'hex') AS request_hex, command_result_id
          FROM idempotency_records
          WHERE scope_kind = 'bootstrap_principal' AND bootstrap_principal_digest = $1
            AND command_type = $2 AND target_type = 'organization' AND key_digest = $3
          LIMIT 1
        SQL
        exec(sql, [bytea(hex(principal_hex)), command_type, bytea(key_digest)]).to_a.first
      end

      def load_command_result(id)
        sql = <<~SQL
          SELECT id, outcome, authorized_payload, audit_record_id, correlation_id,
                 error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference
          FROM command_results WHERE id = $1::uuid
        SQL
        exec(sql, [id]).to_a.first
      end

      # ---- genesis roots -------------------------------------------------------

      def insert_organization(row)
        exec(<<~SQL, org_params(row))
          INSERT INTO organizations
            (id, state_version, lock_version, created_at, updated_at, correlation_id, status,
             authorization_epoch, display_name, profile, default_locale, reporting_time_zone,
             profile_schema_version)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,'pending',0,$4,$5::jsonb,$6,$7,$8)
        SQL
      end

      def activate_organization(row)
        params = [row[:id], iso(row[:now]), row[:creator_account_id], row[:access_policy_id],
                  row[:entitlement_policy_id], row[:plan_assignment_id], row[:billing_entity_id]]
        # Activation is the tenant's first effective-access instant, so it advances
        # the authorization epoch 0 -> 1 atomically with the status change, exactly
        # as the Organization lifecycle guard requires of every status transition.
        exec(<<~SQL, params)
          UPDATE organizations
          SET status = 'active', activated_at = $2::timestamptz, updated_at = $2::timestamptz,
              state_version = state_version + 1, authorization_epoch = authorization_epoch + 1,
              creator_account_id = $3::uuid, current_access_policy_id = $4::uuid,
              current_entitlement_policy_id = $5::uuid, current_plan_assignment_id = $6::uuid,
              current_billing_entity_id = $7::uuid
          WHERE id = $1::uuid AND status = 'pending'
        SQL
      end

      def insert_account(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:issuer_key], row[:issuer_subject], row[:normalized_email],
                  bytea(row[:normalized_email_sha256]), row[:display_name], bytea(row[:receipt_digest])]
        exec(<<~SQL, params)
          INSERT INTO accounts
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             identity_issuer_key, identity_subject, normalized_email, normalized_email_sha256, display_name,
             status, identity_receipt_digest)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5,$6,$7,$8,$9,'pending',$10)
        SQL
      end

      def activate_account(id, now)
        exec(<<~SQL, [id, iso(now)])
          UPDATE accounts SET status = 'active', activated_at = $2::timestamptz,
                 updated_at = $2::timestamptz, state_version = state_version + 1
          WHERE id = $1::uuid AND status = 'pending'
        SQL
      end

      def insert_billing_entity(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:internal_contract_reference]]
        exec(<<~SQL, params)
          INSERT INTO billing_entities
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             internal_contract_reference, state, effective_at)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5,'pending',$2::timestamptz)
        SQL
      end

      def activate_billing_entity(id, plan_assignment_id, now)
        exec(<<~SQL, [id, plan_assignment_id, iso(now)])
          UPDATE billing_entities
          SET state = 'active', active_plan_assignment_id = $2::uuid, activated_at = $3::timestamptz,
              updated_at = $3::timestamptz, state_version = state_version + 1
          WHERE id = $1::uuid AND state = 'pending'
        SQL
      end

      # The null-expiry first OrganizationAdmin Assignment, marked as the bootstrap
      # exception, created pending then activated in the same commit under the
      # bootstrap exception (:641). Its approved protected allowlist is the full
      # OrganizationAdmin preview, because this Assignment IS the tenant's protected
      # authority root.
      def insert_admin_assignment(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:account_id],
                  bytea(row[:scope_sha256])]
        exec(<<~SQL, params)
          INSERT INTO role_assignments
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             account_id, canonical_role, permission_mode, persona, status, scope_sha256,
             requester_account_id, requested_at, protected_permission_allowlist, bootstrap_admin_exception)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,'OrganizationAdmin',
                  'standard',NULL,'pending',$6,$5::uuid,$2::timestamptz,'[]'::jsonb,true)
        SQL
        exec(<<~SQL, [row[:id], iso(row[:now]), JSON.generate(row[:allowlist])])
          UPDATE role_assignments
          SET status = 'active', effective_at = $2::timestamptz, updated_at = $2::timestamptz,
              protected_permission_allowlist = $3::jsonb, state_version = state_version + 1
          WHERE id = $1::uuid AND status = 'pending'
        SQL
      end

      def insert_access_policy(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:semantic_version], bytea(row[:content_sha256]), row[:plan_scope]]
        exec(<<~SQL, params)
          INSERT INTO access_policies
            (id, state_version, created_at, updated_at, correlation_id, organization_id,
             policy_type, semantic_version, status, content_sha256, effective_at, plan_scope)
          VALUES ($1,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,'access',$5,'active',$6,$2::timestamptz,$7)
        SQL
      end

      def insert_entitlement_policy(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:semantic_version], row[:plan_version], bytea(row[:content_sha256])]
        exec(<<~SQL, params)
          INSERT INTO entitlement_policies
            (id, state_version, created_at, updated_at, correlation_id, organization_id,
             policy_type, semantic_version, plan_version, status, content_sha256, effective_at)
          VALUES ($1,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,'entitlement',$5,$6,'active',$7,$2::timestamptz)
        SQL
      end

      def insert_plan_assignment(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:billing_entity_id],
                  row[:plan_version], row[:approval_version], row[:policy_version], bytea(row[:content_sha256]),
                  row[:service_identity_id]]
        exec(<<~SQL, params)
          INSERT INTO plan_assignments
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             billing_entity_id, plan_version, approval_version, policy_version, content_sha256,
             assigned_by_service_identity_id, effective_at, state)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8,$9,$10::uuid,
                  $2::timestamptz,'active')
        SQL
      end

      def insert_project(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:display_name], row[:locale], row[:time_zone], row[:objective]]
        exec(<<~SQL, params)
          INSERT INTO projects
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             display_name, locale, time_zone, objective, state, source_set_version)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5,$6,$7,$8,'draft',0)
        SQL
      end

      def insert_session(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:account_id],
                  bytea(row[:identity_receipt_digest]), row[:authorization_context_version], row[:creation_reason],
                  iso(row[:issued_at]), iso(row[:last_activity_at]), iso(row[:idle_expires_at]),
                  iso(row[:absolute_expires_at]), bytea(row[:token_sha256])]
        exec(<<~SQL, params)
          INSERT INTO sessions
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, account_id,
             identity_receipt_digest, authorization_context_version, creation_reason,
             issued_at, last_activity_at, idle_expires_at, absolute_expires_at, status, token_sha256)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8,
                  $9::timestamptz,$10::timestamptz,$11::timestamptz,$12::timestamptz,'active',$13)
        SQL
      end

      # ":238 consume the grant" — issued -> consumed, now bound to the real
      # Organization id (the OD-013 substitution never appears past this point).
      def consume_grant(id, expected_version, organization_id, consuming_command_id, now)
        exec(<<~SQL, [id, expected_version, organization_id, consuming_command_id, iso(now)]).cmd_tuples
          UPDATE bootstrap_grants
          SET state = 'consumed', organization_id = $3::uuid, consuming_command_id = $4::uuid,
              updated_at = $5::timestamptz, state_version = state_version + 1
          WHERE id = $1::uuid AND state = 'issued' AND state_version = $2
        SQL
      end

      def consume_nonce(row)
        params = [row[:id], iso(row[:now]), row[:receipt_id], bytea(row[:receipt_digest]),
                  row[:command_execution_id], iso(row[:now]), row[:outcome], row[:reason_code]]
        exec(<<~SQL, params).values.dig(0, 0)
          SELECT f1_consume_receipt_nonce($1::uuid,$2::timestamptz,$3::uuid,$4,$5::uuid,$6::timestamptz,$7,$8)
        SQL
      end

      # ---- service-attributed ledger ------------------------------------------

      def insert_command_execution(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:correlation_id], row[:command_id],
          bytea(row[:key_digest]), row[:command_type], row[:command_schema_version], row[:service_identity_id],
          row[:organization_id], bytea(hex(row[:principal_hex])), row[:action], iso(row[:requested_at]),
          iso(row[:now]), row[:policy_versions], row[:canonical_payload], bytea(row[:request_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO command_executions
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             idempotency_key_digest, content_sha256, command_type, command_schema_version,
             service_identity_id, organization_id, bootstrap_principal_digest, target_type, target_id, action,
             requested_at, authorization_check_at, policy_versions, canonical_payload, request_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,NULL,$7,$8,$9::uuid,$10::uuid,$11,
                  'organization',$10::uuid,$12,$13::timestamptz,$14::timestamptz,$15::jsonb,$16::jsonb,$17)
        SQL
      end

      def insert_audit(row)
        params = [
          row[:id], iso(row[:now]), month(row[:now]), row[:organization_id], row[:service_identity_id],
          row[:correlation_id], row[:command_id], row[:entity_type], row[:entity_id], row[:to_state],
          row[:outcome], row[:reason_code], row[:payload], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO audit_record_registry
            (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
             service_identity_id, correlation_id, causation_id, command_id, entity_type, entity_id,
             to_state, outcome, reason_code, classification, payload, content_sha256, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-001',
                  $5::uuid,$6::uuid,$6::uuid,$7::uuid,$8,$9::uuid,$10,$11,$12,'restricted',$13::jsonb,$14,'security_audit')
        SQL
      end

      def insert_event(row)
        params = [
          row[:id], iso(row[:now]), row[:event_type], row[:event_profile], iso(row[:now]),
          row[:organization_id], row[:aggregate_type], row[:aggregate_id], row[:aggregate_version],
          month(row[:now]), row[:correlation_id], row[:command_id], row[:audit_record_id],
          bytea(row[:event_bytes]), row[:event_bytes].bytesize, bytea(row[:event_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO event_registry
            (id, schema_version, created_at, event_type, event_schema_version, workflow_id, event_profile,
             occurred_at, organization_id, aggregate_type, aggregate_id, aggregate_version, partition_month,
             correlation_id, causation_id, command_id, audit_record_id, event_bytes, event_byte_count, event_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-001',$4,
                  $5::timestamptz,$6::uuid,$7,$8::uuid,$9,$10::date,
                  $11::uuid,$11::uuid,$12::uuid,$13::uuid,$14,$15,$16)
        SQL
      end

      def insert_command_result(row)
        failure = row[:failure]
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:command_id], row[:command_execution_id],
          row[:outcome], row[:organization_id], row[:service_identity_id], iso(row[:now]),
          row[:target_refs], row[:governing_policy_versions],
          failure&.error_class, failure&.error_code, failure&.reason_code, failure&.severity,
          failure&.retryable, failure&.recovery_action, failure&.support_reference,
          row[:authorized_payload], row[:audit_record_id]
        ]
        exec(<<~SQL, params)
          INSERT INTO command_results
            (id, schema_version, created_at, correlation_id, causation_id, command_id, command_execution_id,
             result_schema_version, outcome, organization_id, service_identity_id, completed_at,
             authorization_check_at, target_refs, governing_policy_versions,
             error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference,
             authorized_payload, audit_record_id)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$3::uuid,$4::uuid,$5::uuid,'1.0',$6,$7::uuid,$8::uuid,
                  $9::timestamptz,$9::timestamptz,$10::jsonb,$11::jsonb,
                  $12,$13,$14,$15,$16,$17,$18,$19::jsonb,$20::uuid)
        SQL
      end

      def insert_idempotency(row)
        params = [row[:id], iso(row[:now]), bytea(hex(row[:principal_hex])), row[:command_type],
                  bytea(row[:key_digest]), bytea(row[:request_sha256]), row[:command_execution_id],
                  row[:command_result_id], iso(row[:retain_until])]
        exec(<<~SQL, params)
          INSERT INTO idempotency_records
            (id, state_version, lock_version, created_at, updated_at, scope_kind, bootstrap_principal_digest,
             command_type, target_type, target_id, key_digest, request_sha256,
             command_execution_id, command_result_id, retain_until)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,'bootstrap_principal',$3,
                  $4,'organization',NULL,$5,$6,$7::uuid,$8::uuid,$9::timestamptz)
        SQL
      end

      private

      def org_params(row)
        [row[:id], iso(row[:now]), row[:correlation_id], row[:display_name], JSON.generate(row[:profile]),
         row[:default_locale], row[:reporting_time_zone], row[:profile_schema_version]]
      end

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def hex(hex_string) = [hex_string].pack("H*")
      def iso(time) = time&.getutc&.iso8601(6)
      def month(time) = Date.new(time.year, time.month, 1).iso8601

      class Consumed < StandardError; end
    end
  end
end
