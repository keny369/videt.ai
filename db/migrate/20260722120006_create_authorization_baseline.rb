# frozen_string_literal: true

# Foundation for Permission Baseline authorization + Session-based organization
# actors (WORKFLOW_SPECIFICATIONS.md § effective authorization :322-329; § Session
# :254; SECURITY_PERFORMANCE.md PRULE-044; schemas/POSTGRESQL_SCHEMA.md
# authorization_decisions). Enables the first WF-013/S-23 authenticated
# administrator command (RevokeInvitation).
#
# 1. authorization_decisions — the durable, immutable tenant authorization-decision
#    record (T-IMM, FORCE ROW LEVEL SECURITY by real organization_id). Written in
#    the same transaction as the mutation it authorizes, on allow AND deny
#    (PRULE-044). Insert/read only (immutable): no UPDATE/DELETE grant.
#
# 2. sessions relaxed FORCE -> ENABLE row level security. A Session must be
#    authenticated BEFORE any Organization context exists (the actor's org is
#    derived FROM the Session, not caller-supplied), so the SECURITY DEFINER
#    f1_authenticate_session reads it as the owner — the same ENABLE posture the
#    receipt store and invitation reference registry use. The runtime (f1_web) is a
#    non-owner and remains fully RLS-scoped: it still sees no Session outside its
#    proved context. Only the controlled authenticator reads a Session pre-context,
#    returning minimal non-secret fields.
#
# 3. f1_authenticate_session(session_id) — derives (account, organization) and the
#    validity fields from the Session record, so the command never trusts a
#    caller-supplied account or organization id.
#
# 4. invitations.requester_account_id — the stored requester (schemas §
#    invitations "requester/approver IDs"), for the InvitationRevoked event's
#    requester reference and the (deferred) requester revoke branch.
class CreateAuthorizationBaseline < ActiveRecord::Migration[8.1]
  def up
    create_authorization_decisions
    relax_sessions_to_enable_rls
    create_session_authenticator
    create_org_context_enter
    execute "ALTER TABLE invitations ADD COLUMN requester_account_id uuid;"
  end

  def down
    execute "ALTER TABLE invitations DROP COLUMN IF EXISTS requester_account_id;"
    execute "DROP FUNCTION IF EXISTS f1_enter_org_context(uuid, uuid);"
    execute "DROP FUNCTION IF EXISTS f1_authenticate_session(uuid);"
    execute "ALTER TABLE sessions FORCE ROW LEVEL SECURITY;"
    execute "DROP TABLE IF EXISTS authorization_decisions;"
  end

  private

  def create_authorization_decisions
    execute <<~SQL
      CREATE TABLE authorization_decisions (
        id                       uuid PRIMARY KEY,
        schema_version           text NOT NULL,
        created_at               timestamptz(6) NOT NULL,
        organization_id          uuid NOT NULL,
        correlation_id           uuid NOT NULL,
        causation_id             uuid NOT NULL,
        command_id               uuid,
        subject_type             text NOT NULL CHECK (subject_type IN ('account','service_identity')),
        subject_id               uuid NOT NULL,
        action                   text NOT NULL,
        resource_type            text NOT NULL,
        resource_id              uuid,
        decision                 text NOT NULL CHECK (decision IN ('allow','deny')),
        reason_code              text NOT NULL,
        organization_epoch       bigint NOT NULL,
        membership_snapshot      jsonb NOT NULL,
        role_assignment_versions jsonb NOT NULL,
        policy_snapshot_id       uuid,
        support_session_id       uuid,
        classification_ceiling   text,
        decided_at               timestamptz(6) NOT NULL,
        retention_class          text NOT NULL CHECK (retention_class = 'security_audit')
      );
    SQL
    # An authorization decision is readable/writable only inside its proved
    # Organization context; grants (SELECT, INSERT only — immutable) come from
    # F1::RuntimeGrants.
    execute <<~SQL
      ALTER TABLE authorization_decisions ENABLE ROW LEVEL SECURITY;
      ALTER TABLE authorization_decisions FORCE ROW LEVEL SECURITY;
      CREATE POLICY authorization_decisions_context ON authorization_decisions
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON authorization_decisions FROM PUBLIC;
    SQL
  end

  def relax_sessions_to_enable_rls
    # Keep ENABLE + the org policy; drop FORCE so the SECURITY DEFINER authenticator
    # (owner) can read a Session before its Organization context is established. The
    # non-owner runtime stays RLS-scoped.
    execute "ALTER TABLE sessions NO FORCE ROW LEVEL SECURITY;"
  end

  # Pre-context Session authentication: resolve the Session as the owner and return
  # the authority-derivation fields. The caller validates active/expiry and derives
  # the actor Account + Organization from these values (never from caller input).
  def create_session_authenticator
    execute <<~SQL
      CREATE FUNCTION f1_authenticate_session(p_session_id uuid)
      RETURNS TABLE (
        account_id          uuid,
        organization_id     uuid,
        status              text,
        idle_expires_at     timestamptz(6),
        absolute_expires_at timestamptz(6),
        authorization_context_version bigint
      )
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT s.account_id, s.organization_id, s.status, s.idle_expires_at,
               s.absolute_expires_at, s.authorization_context_version
        FROM sessions s
        WHERE s.id = p_session_id;
      $$;
      REVOKE ALL ON FUNCTION f1_authenticate_session(uuid) FROM PUBLIC;
    SQL
  end

  # Enter a proved tenant context for an already-authenticated Organization actor
  # (no receipt): the analog of f1_enter_context for Session-authenticated WF-013
  # commands. Sets the same proof GUCs with NO bootstrap principal, so
  # f1_current_context_org() returns the Organization the Session was authenticated
  # into. Entering context is data-scoping, not authorization — the capability
  # decision is separate.
  def create_org_context_enter
    execute <<~SQL
      CREATE FUNCTION f1_enter_org_context(p_org uuid, p_correlation_id uuid)
      RETURNS uuid
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_proof text;
      BEGIN
        v_proof := f1_context_proof('', p_org::text);
        PERFORM set_config('app.bootstrap_principal_digest', '', true);
        PERFORM set_config('app.context_org', p_org::text, true);
        PERFORM set_config('app.f1_proof', v_proof, true);
        RETURN p_org;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_enter_org_context(uuid, uuid) FROM PUBLIC;
    SQL
  end
end
