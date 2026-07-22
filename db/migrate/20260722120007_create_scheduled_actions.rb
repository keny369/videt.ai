# frozen_string_literal: true

# The durable timer authority (BACKGROUND_PROCESSING.md § Durable Scheduling :88;
# schemas/POSTGRESQL_SCHEMA.md `scheduled_actions` :222 plus the G-MUT :115,
# LINEAGE :121 and WORK-CLAIM :122 base classes).
#
# `scheduled_actions` is the SOLE physical timer authority: PostgreSQL — not
# Redis, Sidekiq, cron or a domain column — decides whether work exists, is due,
# is claimed, is terminal or is recoverable (:40). Nothing here is
# invitation-specific: the row carries an opaque `(target_type, target_id)`
# reference and an action kind drawn from the ratified 53-literal catalogue, and a
# new ratified kind needs only a registered handler, never new scheduler
# semantics.
#
# Posture, mirroring the reference registry and the Session authenticator:
#   * ENABLE (not FORCE) ROW LEVEL SECURITY with the ordinary Organization policy,
#     so the runtime (a non-owner) sees only its own Organization's actions and a
#     global/service-owned action (`organization_id IS NULL`) is invisible to it
#     entirely, while the owner-side SECURITY DEFINER transport functions below
#     scan every Organization to find due work. No existing table's FORCE RLS is
#     relaxed.
#   * The runtime may SELECT and INSERT (creation happens inside the proved
#     Organization context of the activating command) but holds NO UPDATE or
#     DELETE. Every state transition goes through one of the restricted transport
#     functions, and `f1_scheduled_actions_guard` enforces the state machine and
#     the immutable identity columns even against those functions.
#   * Grants live only in F1::RuntimeGrants (S-00A), never inline.
#
# Deferred with the Redis/Sidekiq transport, which this slice does not build:
# `dispatch_attempt_count`, `transport_recovery_generation`, the reassessment
# schedule-decision columns, cadence slot/coalescing columns, policy id/version/
# digest, `work_dispatch_bindings`, `work_executions`, `outbox_messages` and
# `scheduler_leases`. Their absence changes no product result: transport carries
# identifiers only (:41) and correctness is entirely PostgreSQL's.
class CreateScheduledActions < ActiveRecord::Migration[8.1]
  # The exhaustive accepted-baseline catalogue (BACKGROUND_PROCESSING.md
  # § Action-kind catalogue :125-181). `credential_rotation_retry` is deliberately
  # absent (:423). An architecture spec re-extracts this list from the document.
  ACTION_KINDS = %w[
    bootstrap_grant_expire session_expire invitation_expire role_assignment_expire
    source_scope_request_expire verification_observation_slot verification_request_expire
    verification_material_destroy crawl_dispatch crawl_fetch_due crawl_terminal_deadline
    ingestion_attempt_due parsing_attempt_due indexing_attempt_due check_attempt_due
    evaluation_stage_advance evaluation_deadline score_recalculation_due adjudication_due
    ai_generation_deadline ai_validation_deadline ai_publication_expire reassessment_slot
    notification_delivery_attempt_due notification_reconciliation_due notification_escalation_due
    credential_initialization_retry credential_expire entitlement_lease_expire export_generate
    export_expire export_policy_reevaluate closure_request_expire organization_closure_execute
    support_session_expire incident_restoration_observe investigation_input_collect
    provider_event_consume projection_repair_due transport_lease_sweep_due running_work_sweep_due
    entitlement_invariant_sweep_due staged_object_invariant_sweep_due export_invariant_sweep_due
    mailgun_uncertainty_sweep_due deletion_tombstone_invariant_sweep_due evidence_retention_warning
    lifecycle_deletion_start lifecycle_deletion_attempt_due lifecycle_deletion_deadline
    backup_tombstone_verify restore_drill_due partition_maintenance_due
  ].freeze

  STATUSES = %w[pending claimed dispatched canceled completed quarantined].freeze

  def up
    create_scheduled_actions
    create_guard_trigger
    create_claim_function
    create_dispatch_function
    create_settle_function
    create_release_function
    create_expired_lease_sweep_function
    create_cancel_function
  end

  def down
    %w[
      f1_cancel_scheduled_action(uuid,text,timestamptz)
      f1_release_expired_scheduled_action_leases(integer,timestamptz)
      f1_release_scheduled_action_claim(uuid,uuid,bigint,text,timestamptz)
      f1_settle_scheduled_action(uuid,uuid,bigint,text,text,timestamptz)
      f1_dispatch_scheduled_action(uuid,uuid,bigint,uuid,integer,timestamptz)
      f1_claim_due_scheduled_actions(uuid,integer,integer,timestamptz)
    ].each { |sig| execute "DROP FUNCTION IF EXISTS #{sig};" }
    execute "DROP TABLE IF EXISTS scheduled_actions;"
    execute "DROP FUNCTION IF EXISTS f1_scheduled_actions_guard();"
  end

  private

  def literals(values) = values.map { |v| "'#{v}'" }.join(", ")

  def create_scheduled_actions
    execute <<~SQL
      CREATE TABLE scheduled_actions (
        -- G-MUT
        id                            uuid PRIMARY KEY,
        schema_version                text NOT NULL,
        state_version                 bigint NOT NULL DEFAULT 0,
        lock_version                  bigint NOT NULL DEFAULT 0,
        created_at                    timestamptz(6) NOT NULL,
        updated_at                    timestamptz(6) NOT NULL,
        -- LINEAGE
        correlation_id                uuid NOT NULL,
        causation_id                  uuid NOT NULL,
        command_id                    uuid,
        -- WORK-CLAIM: nonnull exactly while the row is claimed or dispatched
        claim_owner                   uuid,
        claim_generation              bigint NOT NULL DEFAULT 0 CHECK (claim_generation >= 0),
        claimed_at                    timestamptz(6),
        lease_expires_at              timestamptz(6),
        last_heartbeat_at             timestamptz(6),
        claim_phase                   text CHECK (claim_phase IN ('scheduler','worker')),
        -- Ownership: Organization-scoped, or global/service-owned when null
        -- (BACKGROUND_PROCESSING.md :92-104 "Organization and nullable Project").
        organization_id               uuid,
        project_id                    uuid,
        executing_service_identity_id uuid NOT NULL,
        -- Action identity
        action_kind                   text NOT NULL CHECK (action_kind IN (#{literals(ACTION_KINDS)})),
        action_schema_version         text NOT NULL,
        target_type                   text NOT NULL,
        target_id                     uuid NOT NULL,
        product_generation            bigint NOT NULL DEFAULT 0 CHECK (product_generation >= 0),
        schedule_generation           bigint NOT NULL DEFAULT 1 CHECK (schedule_generation >= 1),
        due_at                        timestamptz(6) NOT NULL,
        not_before_at                 timestamptz(6),
        identity_preimage             bytea NOT NULL CHECK (octet_length(identity_preimage) > 0),
        identity_sha256               bytea NOT NULL CHECK (octet_length(identity_sha256) = 32),
        collision_ordinal             integer NOT NULL DEFAULT 0 CHECK (collision_ordinal >= 0),
        payload_refs                  jsonb NOT NULL DEFAULT '{}'::jsonb,
        -- Execution state
        status                        text NOT NULL CHECK (status IN (#{literals(STATUSES)})),
        dispatched_at                 timestamptz(6),
        completed_at                  timestamptz(6),
        canceled_at                   timestamptz(6),
        quarantined_at                timestamptz(6),
        -- Bounded classification token only: never an exception dump, message or
        -- customer text (API_CONTRACTS.md `EventReasonCode` :717).
        reason                        text CHECK (reason IS NULL OR reason ~ '^[a-z][a-z0-9_]{0,119}$'),

        CONSTRAINT scheduled_action_claim_fields_match_status CHECK (
          (status IN ('claimed','dispatched')) =
          (claim_owner IS NOT NULL AND claimed_at IS NOT NULL AND lease_expires_at IS NOT NULL
           AND claim_phase IS NOT NULL AND claim_generation > 0)
        ),
        CONSTRAINT scheduled_action_dispatch_time_required CHECK (
          status NOT IN ('dispatched','completed') OR dispatched_at IS NOT NULL
        ),
        CONSTRAINT scheduled_action_completed_has_time CHECK (
          (status = 'completed') = (completed_at IS NOT NULL)
        ),
        CONSTRAINT scheduled_action_canceled_has_time CHECK (
          (status = 'canceled') = (canceled_at IS NOT NULL)
        ),
        CONSTRAINT scheduled_action_quarantined_has_time_and_reason CHECK (
          (status = 'quarantined') = (quarantined_at IS NOT NULL AND reason IS NOT NULL)
        ),
        CONSTRAINT scheduled_action_heartbeat_requires_claim CHECK (
          last_heartbeat_at IS NULL OR claim_owner IS NOT NULL
        )
      );
      -- One row per complete action identity (BACKGROUND_PROCESSING.md :106);
      -- exact creation replay returns it and a same digest with a different
      -- retained preimage takes the next ordinal rather than merging.
      CREATE UNIQUE INDEX scheduled_actions_identity
        ON scheduled_actions (action_kind, identity_sha256, collision_ordinal);
      -- The due-time claim scan (:114 ORDER BY due_at, id).
      CREATE INDEX scheduled_actions_due
        ON scheduled_actions (due_at, id) WHERE status = 'pending';
      -- The expired-lease recovery sweep (:292).
      CREATE INDEX scheduled_actions_leases
        ON scheduled_actions (lease_expires_at) WHERE status IN ('claimed','dispatched');
    SQL
    execute <<~SQL
      ALTER TABLE scheduled_actions ENABLE ROW LEVEL SECURITY;
      CREATE POLICY scheduled_actions_context ON scheduled_actions
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON scheduled_actions FROM PUBLIC;
    SQL
  end

  # The state machine and the immutable identity, enforced at the database
  # boundary so no code path — including the restricted transport functions —
  # can reopen a terminal action, rewrite its identity or move its due time.
  def create_guard_trigger
    execute <<~SQL
      CREATE FUNCTION f1_scheduled_actions_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE allowed text[];
      BEGIN
        IF NEW.id <> OLD.id
           OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
           OR NEW.causation_id IS DISTINCT FROM OLD.causation_id
           OR NEW.command_id IS DISTINCT FROM OLD.command_id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.executing_service_identity_id IS DISTINCT FROM OLD.executing_service_identity_id
           OR NEW.action_kind IS DISTINCT FROM OLD.action_kind
           OR NEW.action_schema_version IS DISTINCT FROM OLD.action_schema_version
           OR NEW.target_type IS DISTINCT FROM OLD.target_type
           OR NEW.target_id IS DISTINCT FROM OLD.target_id
           OR NEW.product_generation IS DISTINCT FROM OLD.product_generation
           OR NEW.schedule_generation IS DISTINCT FROM OLD.schedule_generation
           OR NEW.due_at IS DISTINCT FROM OLD.due_at
           OR NEW.not_before_at IS DISTINCT FROM OLD.not_before_at
           OR NEW.identity_preimage IS DISTINCT FROM OLD.identity_preimage
           OR NEW.identity_sha256 IS DISTINCT FROM OLD.identity_sha256
           OR NEW.collision_ordinal IS DISTINCT FROM OLD.collision_ordinal
           OR NEW.payload_refs IS DISTINCT FROM OLD.payload_refs THEN
          RAISE EXCEPTION 'scheduled_action_immutable_field_changed' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.claim_generation < OLD.claim_generation THEN
          RAISE EXCEPTION 'scheduled_action_claim_generation_regressed' USING ERRCODE = 'raise_exception';
        END IF;

        IF (OLD.completed_at IS NOT NULL AND NEW.completed_at IS DISTINCT FROM OLD.completed_at)
           OR (OLD.canceled_at IS NOT NULL AND NEW.canceled_at IS DISTINCT FROM OLD.canceled_at)
           OR (OLD.quarantined_at IS NOT NULL AND NEW.quarantined_at IS DISTINCT FROM OLD.quarantined_at)
           OR (OLD.dispatched_at IS NOT NULL AND NEW.dispatched_at IS DISTINCT FROM OLD.dispatched_at) THEN
          RAISE EXCEPTION 'scheduled_action_terminal_timestamp_rewritten' USING ERRCODE = 'raise_exception';
        END IF;

        allowed := CASE OLD.status
                     WHEN 'pending'    THEN ARRAY['pending','claimed','canceled','quarantined']
                     WHEN 'claimed'    THEN ARRAY['claimed','dispatched','pending','canceled','quarantined']
                     WHEN 'dispatched' THEN ARRAY['dispatched','completed','pending','quarantined']
                     ELSE ARRAY[OLD.status]
                   END;
        IF NOT (NEW.status = ANY (allowed)) THEN
          RAISE EXCEPTION 'scheduled_action_illegal_transition % -> %', OLD.status, NEW.status
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER scheduled_actions_guard BEFORE UPDATE ON scheduled_actions
        FOR EACH ROW EXECUTE FUNCTION f1_scheduled_actions_guard();
    SQL
  end

  # Step 3-4 of the ratified due-time claim (BACKGROUND_PROCESSING.md :110-115):
  # at most `p_limit` eligible rows in (due_at, id) order under FOR UPDATE SKIP
  # LOCKED, each moved to `claimed` with an incremented claim generation and a
  # fresh lease. Concurrent claimers therefore take disjoint batches and one
  # action can be claimed by exactly one caller.
  #
  # `p_now` defaults to PostgreSQL transaction time, which is the ratified
  # due-time authority (:110, verification gate 7 :519). Production never passes
  # it; the deterministic test harness pins the boundary instant with it, in place
  # of sleeping (TESTING_ARCHITECTURE controlled clock).
  def create_claim_function
    execute <<~SQL
      CREATE FUNCTION f1_claim_due_scheduled_actions(
        p_owner uuid, p_limit integer, p_lease_seconds integer, p_now timestamptz(6) DEFAULT NULL
      )
      RETURNS TABLE (
        id uuid, action_kind text, action_schema_version text, organization_id uuid, project_id uuid,
        target_type text, target_id uuid, product_generation bigint, schedule_generation bigint,
        due_at timestamptz(6), claim_generation bigint, correlation_id uuid, causation_id uuid,
        executing_service_identity_id uuid, payload_refs jsonb
      )
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      #variable_conflict use_column
      DECLARE v_now timestamptz(6) := coalesce(p_now, transaction_timestamp());
      BEGIN
        RETURN QUERY
        WITH due AS (
          SELECT a.id FROM scheduled_actions a
          WHERE a.status = 'pending'
            AND a.due_at <= v_now
            AND (a.not_before_at IS NULL OR a.not_before_at <= v_now)
          ORDER BY a.due_at, a.id
          FOR UPDATE SKIP LOCKED
          LIMIT greatest(p_limit, 0)
        )
        UPDATE scheduled_actions a
        SET status = 'claimed', claim_owner = p_owner, claim_generation = a.claim_generation + 1,
            claimed_at = v_now, lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
            claim_phase = 'scheduler', last_heartbeat_at = NULL, updated_at = v_now,
            state_version = a.state_version + 1
        FROM due
        WHERE a.id = due.id
        RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
                  a.target_type, a.target_id, a.product_generation, a.schedule_generation,
                  a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
                  a.executing_service_identity_id, a.payload_refs;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_claim_due_scheduled_actions(uuid, integer, integer, timestamptz) FROM PUBLIC;
    SQL
  end

  # The scheduler-to-worker compare-and-swap handoff (BACKGROUND_PROCESSING.md
  # :119). Only the exact claim owner and generation may transfer; a duplicate
  # invocation that already owns the row resumes the same claim, and any other
  # owner, generation, pending state, terminal state or expired-and-reclaimed
  # generation returns no row and performs no product work.
  def create_dispatch_function
    execute <<~SQL
      CREATE FUNCTION f1_dispatch_scheduled_action(
        p_action_id uuid, p_expected_owner uuid, p_expected_generation bigint,
        p_worker_owner uuid, p_lease_seconds integer, p_now timestamptz(6) DEFAULT NULL
      )
      RETURNS TABLE (
        id uuid, action_kind text, action_schema_version text, organization_id uuid, project_id uuid,
        target_type text, target_id uuid, product_generation bigint, schedule_generation bigint,
        due_at timestamptz(6), claim_generation bigint, correlation_id uuid, causation_id uuid,
        executing_service_identity_id uuid, payload_refs jsonb, identity_sha256 bytea
      )
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      #variable_conflict use_column
      DECLARE v_now timestamptz(6) := coalesce(p_now, transaction_timestamp());
      BEGIN
        RETURN QUERY
        UPDATE scheduled_actions a
        SET status = 'dispatched',
            dispatched_at = coalesce(a.dispatched_at, v_now),
            claim_owner = p_worker_owner, claim_phase = 'worker',
            lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
            updated_at = v_now, state_version = a.state_version + 1
        WHERE a.id = p_action_id
          AND a.status IN ('claimed','dispatched')
          AND a.claim_generation = p_expected_generation
          AND a.claim_owner IN (p_expected_owner, p_worker_owner)
        RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
                  a.target_type, a.target_id, a.product_generation, a.schedule_generation,
                  a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
                  a.executing_service_identity_id, a.payload_refs, a.identity_sha256;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_dispatch_scheduled_action(uuid, uuid, bigint, uuid, integer, timestamptz) FROM PUBLIC;
    SQL
  end

  # Terminalize a dispatched action the caller still owns: `completed` for a
  # committed or harmlessly-terminal execution, `quarantined` for a fail-closed
  # mapping/identity deviation that must never be replayed
  # (BACKGROUND_PROCESSING.md :245, :329). Returns true iff this call terminalized.
  def create_settle_function
    execute <<~SQL
      CREATE FUNCTION f1_settle_scheduled_action(
        p_action_id uuid, p_owner uuid, p_generation bigint, p_status text, p_reason text,
        p_now timestamptz(6) DEFAULT NULL
      )
      RETURNS boolean
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := coalesce(p_now, transaction_timestamp()); v_changed integer;
      BEGIN
        IF p_status NOT IN ('completed','quarantined') THEN
          RAISE EXCEPTION 'scheduled_action_settle_status_invalid' USING ERRCODE = 'raise_exception';
        END IF;
        UPDATE scheduled_actions a
        SET status = p_status,
            completed_at = CASE WHEN p_status = 'completed' THEN v_now ELSE a.completed_at END,
            quarantined_at = CASE WHEN p_status = 'quarantined' THEN v_now ELSE a.quarantined_at END,
            reason = coalesce(p_reason, a.reason),
            claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
            claim_phase = NULL, last_heartbeat_at = NULL,
            updated_at = v_now, state_version = a.state_version + 1
        WHERE a.id = p_action_id
          AND a.claim_owner = p_owner
          AND a.claim_generation = p_generation
          -- `completed` only from `dispatched` (the guard trigger's transition
          -- table); a fail-closed quarantine may terminalize either claim phase.
          AND (a.status = 'dispatched' OR (a.status = 'claimed' AND p_status = 'quarantined'));
        GET DIAGNOSTICS v_changed = ROW_COUNT;
        RETURN v_changed > 0;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_settle_scheduled_action(uuid, uuid, bigint, text, text, timestamptz) FROM PUBLIC;
    SQL
  end

  # Release the transport claim of an action the caller still owns and return it
  # to `pending` with a bounded failure classification. This is the ratified
  # recovery for a pure deterministic computation with no committed terminal
  # result: "release the transport claim and recompute the same product attempt
  # identity" (BACKGROUND_PROCESSING.md :297). It increments no product attempt
  # and never decreases the claim generation (:301).
  def create_release_function
    execute <<~SQL
      CREATE FUNCTION f1_release_scheduled_action_claim(
        p_action_id uuid, p_owner uuid, p_generation bigint, p_reason text,
        p_now timestamptz(6) DEFAULT NULL
      )
      RETURNS boolean
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := coalesce(p_now, transaction_timestamp()); v_changed integer;
      BEGIN
        UPDATE scheduled_actions a
        SET status = 'pending', claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
            claim_phase = NULL, last_heartbeat_at = NULL, reason = coalesce(p_reason, a.reason),
            updated_at = v_now, state_version = a.state_version + 1
        WHERE a.id = p_action_id
          AND a.claim_owner = p_owner
          AND a.claim_generation = p_generation
          AND a.status IN ('claimed','dispatched');
        GET DIAGNOSTICS v_changed = ROW_COUNT;
        RETURN v_changed > 0;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_release_scheduled_action_claim(uuid, uuid, bigint, text, timestamptz) FROM PUBLIC;
    SQL
  end

  # Lease-expiry recovery (BACKGROUND_PROCESSING.md :292-301). A worker lost
  # before its completion transaction leaves an expired claim; the sweep returns
  # at most `p_limit` such rows to `pending` under FOR UPDATE SKIP LOCKED so the
  # same action identity is recomputed. No action can be stranded by process loss.
  def create_expired_lease_sweep_function
    execute <<~SQL
      CREATE FUNCTION f1_release_expired_scheduled_action_leases(
        p_limit integer, p_now timestamptz(6) DEFAULT NULL
      )
      RETURNS integer
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := coalesce(p_now, transaction_timestamp()); v_changed integer;
      BEGIN
        WITH expired AS (
          SELECT a.id FROM scheduled_actions a
          WHERE a.status IN ('claimed','dispatched') AND a.lease_expires_at <= v_now
          ORDER BY a.lease_expires_at, a.id
          FOR UPDATE SKIP LOCKED
          LIMIT greatest(p_limit, 0)
        )
        UPDATE scheduled_actions a
        SET status = 'pending', claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
            claim_phase = NULL, last_heartbeat_at = NULL, reason = 'transport_lease_expired',
            updated_at = v_now, state_version = a.state_version + 1
        FROM expired
        WHERE a.id = expired.id;
        GET DIAGNOSTICS v_changed = ROW_COUNT;
        RETURN v_changed;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_release_expired_scheduled_action_leases(integer, timestamptz) FROM PUBLIC;
    SQL
  end

  # Cancel a not-yet-executing action. `canceled` is one of the six ratified
  # statuses; no accepted Invitation transition cancels its expiry action (the
  # ratified behaviour for a lost race is harmless terminal execution), so this
  # exists as the generic mechanism and is not wired into a product command.
  def create_cancel_function
    execute <<~SQL
      CREATE FUNCTION f1_cancel_scheduled_action(
        p_action_id uuid, p_reason text, p_now timestamptz(6) DEFAULT NULL
      )
      RETURNS boolean
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := coalesce(p_now, transaction_timestamp()); v_changed integer;
      BEGIN
        UPDATE scheduled_actions a
        SET status = 'canceled', canceled_at = v_now, reason = coalesce(p_reason, a.reason),
            claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
            claim_phase = NULL, last_heartbeat_at = NULL,
            updated_at = v_now, state_version = a.state_version + 1
        WHERE a.id = p_action_id AND a.status IN ('pending','claimed');
        GET DIAGNOSTICS v_changed = ROW_COUNT;
        RETURN v_changed > 0;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_cancel_scheduled_action(uuid, text, timestamptz) FROM PUBLIC;
    SQL
  end
end
