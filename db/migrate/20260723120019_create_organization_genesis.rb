# frozen_string_literal: true

# The S-02 Organization Setup genesis schema (WORKFLOW_SPECIFICATIONS.md :230
# organization-profile-v1, :238 the self-service commit, :515-517 the interim
# entitlement/plan contracts; PRODUCT_RULES.md PRULE-002; ACCEPTANCE_AND_TEST_MAPPING.md
# AC-CAP-002, AC-PRULE-002; schemas/POSTGRESQL_SCHEMA.md :413-415, :283).
#
# The earlier tenant migration built a "thin, sign-in-scoped foundation" and
# deferred everything sign-in did not read. S-02 is the slice that needs the rest
# of the tenant genesis, so this adds the four roots WF-001 self-service creates
# alongside the Organization — BillingEntity, Plan Assignment, Entitlement Policy
# and the draft Project — plus the Organization's own genesis columns, and the
# one new context mechanism the genesis requires.
#
# The context problem this solves: the pre-tenant Bootstrap Grant lives in the
# bootstrap-principal context, but the genesis rows are org-keyed and must carry a
# real Organization id that is deliberately NOT the OD-013 principal uuid. A
# single proof binds BOTH principal and org, so `f1_enter_self_service_context`
# resolves the second self-service receipt as owner and enters a context in which
# `f1_current_bootstrap_principal()` returns the principal (the Grant is readable)
# AND `f1_current_context_org()` returns the freshly minted real Organization (the
# tenant roots are writable) at the same time.
class CreateOrganizationGenesis < ActiveRecord::Migration[8.1]
  def up
    extend_organizations
    extend_access_policies
    create_billing_entities
    create_plan_assignments
    create_entitlement_policies
    create_projects
    create_self_service_context
  end

  def down
    execute "DROP FUNCTION IF EXISTS f1_enter_self_service_context(bytea, uuid, uuid);"
    execute "DROP TRIGGER IF EXISTS billing_entities_guard ON billing_entities;"
    execute "DROP FUNCTION IF EXISTS f1_billing_entities_guard();"
    %w[projects entitlement_policies plan_assignments billing_entities].each do |t|
      execute "DROP TABLE IF EXISTS #{t};"
    end
    %w[creator_account_id default_locale reporting_time_zone profile_schema_version
       current_access_policy_id current_entitlement_policy_id current_plan_assignment_id
       current_billing_entity_id].each do |c|
      execute "ALTER TABLE organizations DROP COLUMN IF EXISTS #{c};"
    end
    execute "ALTER TABLE access_policies DROP COLUMN IF EXISTS plan_scope;"
  end

  private

  def force_rls(table, using:, check: nil)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check || using});
      REVOKE ALL ON #{table} FROM PUBLIC;
    SQL
  end

  # ":230 An Organization contains … frozen creation profile … active Access
  # Policy ID/version, active Entitlement Policy ID/version, active Plan
  # Assignment ID/version, active BillingEntity ID/version, creator Account ID
  # after commit". These are the genesis columns the thin foundation omitted.
  def extend_organizations
    execute <<~SQL
      ALTER TABLE organizations
        ADD COLUMN creator_account_id            uuid,
        ADD COLUMN default_locale                text,
        ADD COLUMN reporting_time_zone           text,
        ADD COLUMN profile_schema_version        text,
        ADD COLUMN current_access_policy_id      uuid,
        ADD COLUMN current_entitlement_policy_id uuid,
        ADD COLUMN current_plan_assignment_id    uuid,
        ADD COLUMN current_billing_entity_id     uuid;
    SQL
  end

  # The genesis Access Policy is a full artifact rather than the sign-in stub, so
  # it carries its plan scope alongside the content hash the tenant migration
  # already gave it.
  def extend_access_policies
    execute "ALTER TABLE access_policies ADD COLUMN plan_scope text;"
  end

  # ":413 billing_entities … active Plan Assignment ID NULL only while pending,
  # state CHECK ('pending','active','past_due','suspended','closed'), lifecycle
  # times/reason … partial unique nonclosed per Organization; insert authority
  # exists only inside the WF-001 bootstrap transaction and performs no provider
  # call."
  #
  # The reserved `past_due` and `suspended` values are in the canonical vocabulary
  # but MUST be unreachable in the baseline (AC-CAP-002), so the guard trigger
  # refuses any write that lands on them — the vocabulary stays canonical while
  # the states stay structurally unreachable.
  def create_billing_entities
    execute <<~SQL
      CREATE TABLE billing_entities (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        lock_version              bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        internal_contract_reference text NOT NULL,
        active_plan_assignment_id uuid,
        state                     text NOT NULL
          CHECK (state IN ('pending','active','past_due','suspended','closed')),
        effective_at              timestamptz(6),
        activated_at              timestamptz(6),
        closed_at                 timestamptz(6),
        lifecycle_reason          text,
        last_billing_event_id     uuid,
        -- A pending BillingEntity has no active Plan Assignment yet; an active one
        -- always does (:413).
        CONSTRAINT billing_pending_has_no_plan CHECK (
          state <> 'pending' OR active_plan_assignment_id IS NULL
        ),
        CONSTRAINT billing_active_has_plan CHECK (
          state <> 'active' OR active_plan_assignment_id IS NOT NULL
        ),
        -- The composite key the Plan Assignment's same-Organization FK targets.
        CONSTRAINT billing_entities_org_id_unique UNIQUE (organization_id, id)
      );
      -- ":413 partial unique nonclosed per Organization": one live BillingEntity.
      CREATE UNIQUE INDEX one_nonclosed_billing_entity_per_org
        ON billing_entities (organization_id) WHERE state <> 'closed';
    SQL
    force_rls("billing_entities", using: "organization_id = f1_current_context_org()")
    create_billing_guard
  end

  def create_billing_guard
    execute <<~SQL
      CREATE FUNCTION f1_billing_entities_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        -- ":413 reserved `past_due`/`suspended` … MUST be unreachable" in the
        -- accepted baseline: no path may land on them.
        IF NEW.state IN ('past_due','suspended') THEN
          RAISE EXCEPTION 'billing_entity_reserved_state_unreachable %', NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        IF TG_OP = 'UPDATE' THEN
          -- Genesis identity is immutable.
          IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
             OR NEW.internal_contract_reference IS DISTINCT FROM OLD.internal_contract_reference THEN
            RAISE EXCEPTION 'billing_entity_genesis_immutable' USING ERRCODE = 'raise_exception';
          END IF;
          -- Baseline transitions only: pending -> active, active/pending -> closed.
          IF NOT (
               (OLD.state = 'pending'  AND NEW.state IN ('pending','active','closed')) OR
               (OLD.state = 'active'   AND NEW.state IN ('active','closed')) OR
               (OLD.state = 'closed'   AND NEW.state = 'closed')
             ) THEN
            RAISE EXCEPTION 'billing_entity_illegal_transition % -> %', OLD.state, NEW.state
              USING ERRCODE = 'raise_exception';
          END IF;
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER billing_entities_guard BEFORE INSERT OR UPDATE ON billing_entities
        FOR EACH ROW EXECUTE FUNCTION f1_billing_entities_guard();
    SQL
  end

  # ":415 plan_assignments … BillingEntity ID NOT NULL with composite
  # same-Organization FK, plan approval/version/hash, assigned by, effective/ended
  # times, state CHECK ('active','superseded','revoked'); partial unique active
  # per Organization." ":517 its BillingEntity MUST be that Organization's one
  # nonclosed BillingEntity."
  def create_plan_assignments
    execute <<~SQL
      CREATE TABLE plan_assignments (
        id                          uuid PRIMARY KEY,
        state_version               bigint NOT NULL DEFAULT 0,
        lock_version                bigint NOT NULL DEFAULT 0,
        created_at                  timestamptz(6) NOT NULL,
        updated_at                  timestamptz(6) NOT NULL,
        correlation_id              uuid NOT NULL,
        organization_id             uuid NOT NULL,
        billing_entity_id           uuid NOT NULL,
        plan_version                text NOT NULL,
        approval_version            text NOT NULL,
        policy_version              text NOT NULL,
        content_sha256              bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
        assigned_by_service_identity_id uuid,
        effective_at                timestamptz(6) NOT NULL,
        ended_at                    timestamptz(6),
        superseded_at               timestamptz(6),
        revoked_at                  timestamptz(6),
        revoked_reason              text,
        state                       text NOT NULL CHECK (state IN ('active','superseded','revoked')),
        -- ":415 composite same-Organization FK" to the BillingEntity: a
        -- cross-Organization link cannot exist (PRULE-002).
        CONSTRAINT plan_assignment_billing_same_org
          FOREIGN KEY (organization_id, billing_entity_id)
          REFERENCES billing_entities (organization_id, id)
      );
      -- ":517 Exactly one is active per Organization."
      CREATE UNIQUE INDEX one_active_plan_assignment_per_org
        ON plan_assignments (organization_id) WHERE state = 'active';
    SQL
    force_rls("plan_assignments", using: "organization_id = f1_current_context_org()")
  end

  # ":515 entitlement-interim-v1 … policy and plan versions, Organization,
  # effective time, and a required `operation_rules` map." The full metering
  # engine (CAP-024) is S-22; genesis materializes the baseline policy artifact
  # and its content hash, the same shape access_policies carries.
  def create_entitlement_policies
    execute <<~SQL
      CREATE TABLE entitlement_policies (
        id              uuid PRIMARY KEY,
        state_version   bigint NOT NULL DEFAULT 0,
        created_at      timestamptz(6) NOT NULL,
        updated_at      timestamptz(6) NOT NULL,
        correlation_id  uuid NOT NULL,
        organization_id uuid NOT NULL,
        policy_type     text NOT NULL CHECK (policy_type = 'entitlement'),
        semantic_version text NOT NULL,
        plan_version    text NOT NULL,
        status          text NOT NULL CHECK (status IN ('draft','active','superseded','retired')),
        content_sha256  bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),
        effective_at    timestamptz(6),
        expires_at      timestamptz(6)
      );
      CREATE UNIQUE INDEX one_active_entitlement_policy_per_org
        ON entitlement_policies (organization_id, policy_type) WHERE status = 'active';
    SQL
    force_rls("entitlement_policies", using: "organization_id = f1_current_context_org()")
  end

  # ":283 projects … state CHECK ('draft','active','paused','archived') … unique
  # (organization_id,id)." WF-001 creates the first Project draft; activation and
  # management are WF-002 (S-03), so this is the draft-capable minimum.
  def create_projects
    execute <<~SQL
      CREATE TABLE projects (
        id                 uuid PRIMARY KEY,
        state_version      bigint NOT NULL DEFAULT 0,
        lock_version       bigint NOT NULL DEFAULT 0,
        created_at         timestamptz(6) NOT NULL,
        updated_at         timestamptz(6) NOT NULL,
        correlation_id     uuid NOT NULL,
        organization_id    uuid NOT NULL,
        display_name       text NOT NULL,
        locale             text NOT NULL,
        time_zone          text NOT NULL,
        objective          text,
        state              text NOT NULL CHECK (state IN ('draft','active','paused','archived')),
        source_set_version bigint NOT NULL DEFAULT 0,
        activated_at       timestamptz(6),
        paused_at          timestamptz(6),
        archived_at        timestamptz(6),
        lifecycle_reason   text,
        CONSTRAINT projects_org_id_unique UNIQUE (organization_id, id)
      );
    SQL
    force_rls("projects", using: "organization_id = f1_current_context_org()")
  end

  # The genesis context. It resolves the self-service receipt as owner (before any
  # context exists) and enters a context carrying BOTH the bootstrap principal AND
  # the caller-minted real Organization id, so the Bootstrap Grant (principal-keyed)
  # and the tenant roots (org-keyed) are both reachable in one transaction. Sets no
  # context and returns no rows when the receipt digest does not resolve.
  def create_self_service_context
    execute <<~SQL
      CREATE FUNCTION f1_enter_self_service_context(p_receipt_digest bytea, p_org_id uuid, p_correlation_id uuid)
      RETURNS TABLE (
        receipt_id                 uuid,
        purpose                    text,
        validated_at               timestamptz(6),
        expires_at                 timestamptz(6),
        email_verified             boolean,
        mfa_satisfied              boolean,
        issuer_key                 text,
        issuer_subject             text,
        receipt_schema_version     text,
        assurance_version          text,
        bootstrap_principal_digest bytea,
        organization_id            uuid
      )
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE r identity_receipt_nonces%ROWTYPE; v_principal bytea; v_hex text; v_proof text;
      BEGIN
        SELECT * INTO r FROM identity_receipt_nonces WHERE receipt_digest = p_receipt_digest;
        IF NOT FOUND THEN RETURN; END IF;

        v_principal := coalesce(r.bootstrap_principal_digest, r.identity_principal_digest);
        v_hex := encode(v_principal, 'hex');
        v_proof := f1_context_proof(v_hex, p_org_id::text);
        PERFORM set_config('app.bootstrap_principal_digest', v_hex, true);
        PERFORM set_config('app.context_org', p_org_id::text, true);
        PERFORM set_config('app.f1_proof', v_proof, true);

        RETURN QUERY SELECT r.id, r.purpose, r.validated_at, r.expires_at, r.email_verified,
                            r.mfa_satisfied, r.issuer_key, r.issuer_subject, r.receipt_schema_version,
                            r.assurance_version, v_principal, p_org_id;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_enter_self_service_context(bytea, uuid, uuid) FROM PUBLIC;
    SQL
  end
end
