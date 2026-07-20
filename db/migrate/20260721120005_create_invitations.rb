# frozen_string_literal: true

# Invitation persistence for the WF-001 invitation-acceptance branch
# (WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1, invitation paragraphs;
# schemas/POSTGRESQL_SCHEMA.md tenant `invitations` and global
# `invitation_reference_registry`).
#
# Two tables by design. `invitations` is the tenant aggregate, FORCE ROW LEVEL
# SECURITY by real organization_id like every other tenant table — so it can only
# be read or written inside the proved Organization context. But an acceptance
# arrives with only the opaque reference and does not yet know its Organization,
# and a forced-RLS table cannot be read without context (even by the owner).
# `invitation_reference_registry` is the global locator that resolves an opaque
# reference digest to its Organization and internal Invitation surrogate; it is
# ENABLE (not FORCE) RLS, so the SECURITY DEFINER resolver reads it as the owner
# to establish context, while the runtime sees only its own Organization's rows.
#
# f1_resolve_invitation_reference is the invitation analog of the receipt read in
# f1_enter_context: it performs one fixed unique-index lookup and returns the
# (organization, invitation) binding ONLY for an active, unexpired locator; every
# miss, terminal row, or expiry returns no row, so the route emits the same
# generic invitation_not_active and discloses nothing (POSTGRESQL_SCHEMA.md § the
# invitation reference resolver). It sets no context; the caller then enters the
# resolved Organization with the existing f1_enter_context (which also reads the
# acceptance receipt).
#
# role_assignments gains scope_sha256 and the active-tuple unique index so the
# "exact offered tuple" reuse and the one-active-Assignment-per-tuple invariant
# hold. Runtime grants for all of these live in the single source F1::RuntimeGrants
# (S-00A), not inline here.
class CreateInvitations < ActiveRecord::Migration[8.1]
  INVITATION_STATES = %w[pending_approval active accepted declined rejected revoked expired].freeze

  def up
    create_invitations
    create_invitation_reference_registry
    extend_role_assignments
    create_resolver_function
    create_org_resolver_function
    redefine_enter_context(with_email_digest: true)
  end

  def down
    redefine_enter_context(with_email_digest: false)
    execute "DROP FUNCTION IF EXISTS f1_resolve_invitation_org(bytea);"
    execute "DROP FUNCTION IF EXISTS f1_resolve_invitation_reference(bytea, timestamptz);"
    execute "DROP INDEX IF EXISTS one_active_assignment_per_tuple;"
    execute "ALTER TABLE role_assignments DROP COLUMN IF EXISTS scope_sha256;"
    execute "DROP TABLE IF EXISTS invitation_reference_registry;"
    execute "DROP TABLE IF EXISTS invitations;"
  end

  private

  def states_check(col) = "#{col} IN (#{INVITATION_STATES.map { |s| "'#{s}'" }.join(',')})"

  def create_invitations
    execute <<~SQL
      CREATE TABLE invitations (
        id                          uuid PRIMARY KEY,
        state_version               bigint NOT NULL DEFAULT 0,
        lock_version                bigint NOT NULL DEFAULT 0,
        created_at                  timestamptz(6) NOT NULL,
        updated_at                  timestamptz(6) NOT NULL,
        correlation_id              uuid NOT NULL,
        organization_id             uuid NOT NULL,
        opaque_reference_sha256     bytea NOT NULL UNIQUE CHECK (octet_length(opaque_reference_sha256) = 32),
        target_email                text NOT NULL,
        target_email_sha256         bytea NOT NULL CHECK (octet_length(target_email_sha256) = 32),
        target_identity_issuer_key  text,
        target_identity_subject     text,
        canonical_role              text NOT NULL,
        permission_mode             text NOT NULL CHECK (permission_mode IN ('standard','read_only')),
        persona                     text,
        scope_sha256                bytea CHECK (scope_sha256 IS NULL OR octet_length(scope_sha256) = 32),
        protected_permission_preview jsonb,
        activated_at                timestamptz(6),
        expires_at                  timestamptz(6),
        accepted_at                 timestamptz(6),
        declined_at                 timestamptz(6),
        terminated_at               timestamptz(6),
        fulfilled_by_role_assignment_id uuid,
        state                       text NOT NULL CHECK (#{states_check('state')}),
        reason                      text,
        -- Active expiry is exactly seven days after activation (WF-001 § invitation).
        CONSTRAINT invitation_active_expiry_is_seven_days CHECK (
          activated_at IS NULL OR expires_at = activated_at + interval '7 days'
        ),
        -- Both bound-identity columns are present together or neither.
        CONSTRAINT invitation_bound_identity_pairwise CHECK (
          (target_identity_issuer_key IS NULL) = (target_identity_subject IS NULL)
        )
      );
    SQL
    force_rls("invitations", using: "organization_id = f1_current_context_org()")
  end

  def create_invitation_reference_registry
    execute <<~SQL
      CREATE TABLE invitation_reference_registry (
        opaque_reference_sha256 bytea PRIMARY KEY CHECK (octet_length(opaque_reference_sha256) = 32),
        created_at              timestamptz(6) NOT NULL,
        updated_at              timestamptz(6) NOT NULL,
        organization_id         uuid NOT NULL,
        invitation_id           uuid NOT NULL UNIQUE,
        invitation_state        text NOT NULL CHECK (#{states_check('invitation_state')}),
        activated_at            timestamptz(6),
        expires_at              timestamptz(6),
        terminal_at             timestamptz(6),
        locator_sha256          bytea CHECK (locator_sha256 IS NULL OR octet_length(locator_sha256) = 32),
        retention_class         text NOT NULL CHECK (retention_class = 'identity_commercial')
      );
    SQL
    # ENABLE (not FORCE) RLS: the SECURITY DEFINER resolver reads this as the owner
    # to establish context; the runtime sees only its own Organization's rows.
    execute <<~SQL
      ALTER TABLE invitation_reference_registry ENABLE ROW LEVEL SECURITY;
      CREATE POLICY invitation_reference_registry_context ON invitation_reference_registry
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON invitation_reference_registry FROM PUBLIC;
    SQL
  end

  def extend_role_assignments
    execute <<~SQL
      ALTER TABLE role_assignments
        ADD COLUMN scope_sha256 bytea CHECK (scope_sha256 IS NULL OR octet_length(scope_sha256) = 32);
      -- One active Role Assignment per Account/role/mode/persona/scope tuple
      -- (schemas/POSTGRESQL_SCHEMA.md invariant); the concurrency backstop for
      -- invitation acceptance reuse.
      CREATE UNIQUE INDEX one_active_assignment_per_tuple ON role_assignments (
        organization_id, account_id, canonical_role, permission_mode,
        coalesce(persona, ''), coalesce(scope_sha256, ''::bytea)
      ) WHERE status = 'active';
    SQL
  end

  # Fixed-projection resolver: returns the (organization, invitation) binding only
  # for an active, unexpired locator. Every miss/terminal/expiry returns no row, so
  # the caller emits the same generic invitation_not_active. Sets no context.
  def create_resolver_function
    execute <<~SQL
      CREATE FUNCTION f1_resolve_invitation_reference(p_reference_digest bytea, p_now timestamptz(6))
      RETURNS TABLE (organization_id uuid, invitation_id uuid)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT r.organization_id, r.invitation_id
        FROM invitation_reference_registry r
        WHERE r.opaque_reference_sha256 = p_reference_digest
          AND r.invitation_state = 'active'
          AND (r.expires_at IS NULL OR p_now < r.expires_at);
      $$;
      REVOKE ALL ON FUNCTION f1_resolve_invitation_reference(bytea, timestamptz) FROM PUBLIC;
    SQL
  end

  # Recognizing an exact replay must NOT go through the non-disclosing reference
  # resolver, because a successful acceptance leaves the Invitation terminal and
  # the resolver correctly refuses to resolve it (WORKFLOW_SPECIFICATIONS.md :248
  # exact replay must still return the stored identifiers; POSTGRESQL_SCHEMA.md :179
  # keeps hiding terminal references from ordinary resolution). This SECURITY
  # DEFINER function recovers the (Organization, Invitation) binding for ANY
  # registry state, reading the ENABLE-RLS reference registry as the owner — the
  # minimal context bootstrap the replay path needs. It resolves nothing else; the
  # caller then enters that context and reads the restricted command/result ledger
  # in-context to require exact command-digest equality, reauthorize, and redact.
  # It is separate from and does not weaken f1_resolve_invitation_reference.
  def create_org_resolver_function
    execute <<~SQL
      CREATE FUNCTION f1_resolve_invitation_org(p_reference_digest bytea)
      RETURNS TABLE (organization_id uuid, invitation_id uuid)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT r.organization_id, r.invitation_id
        FROM invitation_reference_registry r
        WHERE r.opaque_reference_sha256 = p_reference_digest;
      $$;
      REVOKE ALL ON FUNCTION f1_resolve_invitation_org(bytea) FROM PUBLIC;
    SQL
  end

  # Extend f1_enter_context (created in 20260721120004) to also return the receipt's
  # normalized_email_sha256 (to match the Invitation target), and normalized_email
  # and display_name (to materialize a newly created Account) — the identity fields
  # invitation acceptance needs (WF-001 § invitation acceptance; Account §). Sign-in
  # selects columns by name and is unaffected. Recreated (not CREATE OR REPLACE)
  # because the RETURNS TABLE shape changes. REVOKE stays here; the EXECUTE grant is
  # central (F1::RuntimeGrants).
  def redefine_enter_context(with_email_digest:)
    email_col = with_email_digest ? "normalized_email_sha256    bytea,\n        normalized_email          text,\n        display_name              text,\n        " : ""
    email_hit = with_email_digest ? "r.normalized_email_sha256, r.normalized_email, r.display_name, " : ""
    email_miss = with_email_digest ? "NULL::bytea, NULL::text, NULL::text, " : ""
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_enter_context(bytea, uuid, uuid);
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
        #{email_col}context_org               uuid
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
                              r.assurance_version, r.mfa_satisfied, r.identity_principal_digest, #{email_hit}p_org;
        ELSE
          RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::timestamptz(6), NULL::timestamptz(6),
                              NULL::boolean, NULL::text, NULL::text, NULL::text, NULL::text, NULL::boolean,
                              NULL::bytea, #{email_miss}p_org;
        END IF;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_enter_context(bytea, uuid, uuid) FROM PUBLIC;
    SQL
  end

  # Structure, RLS and PUBLIC revoke only; runtime grants come from F1::RuntimeGrants.
  def force_rls(table, using:, check: nil)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check || using});
      REVOKE ALL ON #{table} FROM PUBLIC;
    SQL
  end
end
