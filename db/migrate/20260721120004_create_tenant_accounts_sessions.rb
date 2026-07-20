# frozen_string_literal: true

# The first tenant tables (schemas/POSTGRESQL_SCHEMA.md § tenant-scoped locators;
# WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1). WF-001 existing-account
# sign-in resolves the exact (organization, issuer, subject) Account inside its
# Organization and creates exactly one Session, changing no Account or
# Organization state. Every table is FORCE ROW LEVEL SECURITY keyed to the proved
# tenant context (a real organization_id), the mirror of the pretenant grant
# path. f1_enter_context is the tenant analog of f1_enter_bootstrap_context: it
# reads the sign-in receipt as owner and enters the command's Organization
# context, with no bootstrap principal.
#
# This is the thin, sign-in-scoped foundation. role_assignments and
# access_policies carry only the columns sign-in gates on — admin-role-capable
# detection for the MFA gate, effective-assignment presence for the
# organization_home/access_unavailable destination, and one-active-policy-per-org
# for policy_unavailable. The full permission-baseline-v1 effective-permission
# engine, Access Policy intersection/narrowing, and authorized-target destination
# resolution are deferred to the slice that needs them.
class CreateTenantAccountsSessions < ActiveRecord::Migration[8.1]
  def up
    create_organizations
    create_accounts
    create_role_assignments
    create_access_policies
    create_sessions
    create_enter_context_function
  end

  def down
    execute "DROP FUNCTION IF EXISTS f1_enter_context(bytea, uuid, uuid);"
    %w[sessions access_policies role_assignments accounts organizations].each do |t|
      execute "DROP TABLE IF EXISTS #{t};"
    end
  end

  private

  def force_rls(table, using:, grant:, check: nil)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check || using});
      REVOKE ALL ON #{table} FROM PUBLIC;
      GRANT #{grant} ON #{table} TO f1_runtime;
    SQL
  end

  def create_organizations
    execute <<~SQL
      CREATE TABLE organizations (
        id                  uuid PRIMARY KEY,
        state_version       bigint NOT NULL DEFAULT 0,
        lock_version        bigint NOT NULL DEFAULT 0,
        created_at          timestamptz(6) NOT NULL,
        updated_at          timestamptz(6) NOT NULL,
        correlation_id      uuid NOT NULL,
        status              text NOT NULL CHECK (status IN ('pending','active','suspended','closed')),
        authorization_epoch bigint NOT NULL DEFAULT 0 CHECK (authorization_epoch >= 0),
        display_name        text NOT NULL,
        profile             jsonb,
        activated_at        timestamptz(6),
        suspended_at        timestamptz(6),
        closed_at           timestamptz(6),
        lifecycle_reason    text
      );
    SQL
    # An Organization row is readable only inside its own proved tenant context.
    force_rls("organizations", using: "id = f1_current_context_org()", grant: "SELECT")
  end

  def create_accounts
    execute <<~SQL
      CREATE TABLE accounts (
        id                      uuid PRIMARY KEY,
        state_version           bigint NOT NULL DEFAULT 0,
        lock_version            bigint NOT NULL DEFAULT 0,
        created_at              timestamptz(6) NOT NULL,
        updated_at              timestamptz(6) NOT NULL,
        correlation_id          uuid NOT NULL,
        organization_id         uuid NOT NULL,
        identity_issuer_key     text NOT NULL,
        identity_subject        text NOT NULL,
        normalized_email        text NOT NULL,
        normalized_email_sha256 bytea NOT NULL CHECK (octet_length(normalized_email_sha256) = 32),
        display_name            text NOT NULL,
        status                  text NOT NULL CHECK (status IN ('pending','active','suspended','revoked')),
        identity_receipt_digest bytea CHECK (identity_receipt_digest IS NULL OR octet_length(identity_receipt_digest) = 32),
        activated_at            timestamptz(6),
        suspended_at            timestamptz(6),
        revoked_at              timestamptz(6),
        terminal_reason         text,
        -- The Account uniqueness key (WORKFLOW_SPECIFICATIONS.md § onboarding): one
        -- human identity may hold separate tenant-scoped Accounts without cross-
        -- Organization authority.
        CONSTRAINT accounts_identity_unique UNIQUE (organization_id, identity_issuer_key, identity_subject)
      );
    SQL
    force_rls("accounts", using: "organization_id = f1_current_context_org()", grant: "SELECT")
  end

  def create_role_assignments
    execute <<~SQL
      CREATE TABLE role_assignments (
        id              uuid PRIMARY KEY,
        state_version   bigint NOT NULL DEFAULT 0,
        lock_version    bigint NOT NULL DEFAULT 0,
        created_at      timestamptz(6) NOT NULL,
        updated_at      timestamptz(6) NOT NULL,
        correlation_id  uuid NOT NULL,
        organization_id uuid NOT NULL,
        account_id      uuid NOT NULL,
        canonical_role  text NOT NULL,
        permission_mode text NOT NULL CHECK (permission_mode IN ('standard','read_only')),
        persona         text,
        status          text NOT NULL CHECK (status IN ('pending','active','rejected','revoked','expired')),
        effective_at    timestamptz(6),
        expires_at      timestamptz(6)
      );
    SQL
    force_rls("role_assignments", using: "organization_id = f1_current_context_org()", grant: "SELECT")
  end

  def create_access_policies
    execute <<~SQL
      CREATE TABLE access_policies (
        id              uuid PRIMARY KEY,
        state_version   bigint NOT NULL DEFAULT 0,
        created_at      timestamptz(6) NOT NULL,
        updated_at      timestamptz(6) NOT NULL,
        correlation_id  uuid NOT NULL,
        organization_id uuid NOT NULL,
        policy_type     text NOT NULL CHECK (policy_type = 'access'),
        semantic_version text NOT NULL,
        status          text NOT NULL CHECK (status IN ('draft','active','superseded','retired')),
        content_sha256  bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),
        effective_at    timestamptz(6),
        expires_at      timestamptz(6)
      );
      -- At most one active Access Policy per Organization/type (the sign-in path
      -- resolves exactly one; missing or conflicting is policy_unavailable).
      CREATE UNIQUE INDEX one_active_access_policy_per_org
        ON access_policies (organization_id, policy_type) WHERE status = 'active';
    SQL
    force_rls("access_policies", using: "organization_id = f1_current_context_org()", grant: "SELECT")
  end

  def create_sessions
    execute <<~SQL
      CREATE TABLE sessions (
        id                            uuid PRIMARY KEY,
        state_version                 bigint NOT NULL DEFAULT 0,
        lock_version                  bigint NOT NULL DEFAULT 0,
        created_at                    timestamptz(6) NOT NULL,
        updated_at                    timestamptz(6) NOT NULL,
        correlation_id                uuid NOT NULL,
        organization_id               uuid NOT NULL,
        account_id                    uuid NOT NULL,
        identity_receipt_digest       bytea NOT NULL CHECK (octet_length(identity_receipt_digest) = 32),
        authorization_context_version bigint NOT NULL,
        creation_reason               text NOT NULL,
        issued_at                     timestamptz(6) NOT NULL,
        last_activity_at              timestamptz(6) NOT NULL,
        idle_expires_at               timestamptz(6) NOT NULL,
        absolute_expires_at           timestamptz(6) NOT NULL,
        status                        text NOT NULL CHECK (status IN ('active','revoked','expired')),
        revoke_reason                 text,
        expiry_reason                 text,
        terminated_at                 timestamptz(6),
        -- Session lifetimes (WORKFLOW_SPECIFICATIONS.md § Session): idle is 30
        -- minutes from last activity; absolute is 12 hours from issue and never
        -- advances. No refresh is baseline behaviour.
        CONSTRAINT session_idle_is_thirty_minutes CHECK (idle_expires_at = last_activity_at + interval '30 minutes'),
        CONSTRAINT session_absolute_is_twelve_hours CHECK (absolute_expires_at = issued_at + interval '12 hours')
      );
    SQL
    force_rls("sessions", using: "organization_id = f1_current_context_org()", grant: "SELECT, INSERT")
  end

  # Tenant context establishment, the analog of f1_enter_bootstrap_context. It
  # reads the sign-in receipt as the owner (bypassing the bootstrap-only receipt
  # RLS) and enters the command's Organization context with NO bootstrap
  # principal, so f1_current_context_org() returns the real Organization and
  # f1_current_bootstrap_principal() returns NULL. The Organization context is set
  # whether or not the receipt resolves, so every denial — including an
  # unresolved-digest denial — can write its restricted audit in that
  # Organization (WORKFLOW_SPECIFICATIONS.md § existing-account sign-in).
  def create_enter_context_function
    execute <<~SQL
      CREATE FUNCTION f1_enter_context(p_receipt_digest bytea, p_org uuid, p_correlation_id uuid)
      RETURNS TABLE (
        receipt_found             boolean,
        receipt_id                uuid,
        purpose                   text,
        validated_at              timestamptz(6),
        expires_at                timestamptz(6),
        email_verified            boolean,
        issuer_key                text,
        issuer_subject            text,
        receipt_schema_version    text,
        assurance_version         text,
        mfa_satisfied             boolean,
        identity_principal_digest bytea,
        context_org               uuid
      )
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE r identity_receipt_nonces%ROWTYPE; v_found boolean; v_proof text;
      BEGIN
        SELECT * INTO r FROM identity_receipt_nonces WHERE receipt_digest = p_receipt_digest;
        v_found := FOUND;

        v_proof := f1_context_proof('', p_org::text);
        PERFORM set_config('app.bootstrap_principal_digest', '', true);
        PERFORM set_config('app.context_org', p_org::text, true);
        PERFORM set_config('app.f1_proof', v_proof, true);

        IF v_found THEN
          RETURN QUERY SELECT true, r.id, r.purpose, r.validated_at, r.expires_at, r.email_verified,
                              r.issuer_key, r.issuer_subject, r.receipt_schema_version,
                              r.assurance_version, r.mfa_satisfied, r.identity_principal_digest, p_org;
        ELSE
          RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::timestamptz(6), NULL::timestamptz(6),
                              NULL::boolean, NULL::text, NULL::text, NULL::text, NULL::text, NULL::boolean,
                              NULL::bytea, p_org;
        END IF;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_enter_context(bytea, uuid, uuid) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION f1_enter_context(bytea, uuid, uuid) TO f1_runtime;
    SQL
  end
end
