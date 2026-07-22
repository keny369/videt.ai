# frozen_string_literal: true

# Two corrections to the ScheduledAction transport, both required by the ratified
# security model rather than by preference.
#
# 1. PostgreSQL is the due-time authority, not the caller.
#
#    BACKGROUND_PROCESSING.md :114 fixes the predicate as `due_at <=
#    transaction_timestamp()`, and verification gate 7 (:519) states "Due-time
#    equality is decided using PostgreSQL time after job arrival". The previous
#    signatures carried a `p_now timestamptz DEFAULT NULL` override for
#    deterministic tests. Because those functions were runtime-executable, a
#    caller could supply a future instant and claim — and therefore expire — an
#    action before its due time. A production convention is not a security
#    boundary, so the parameter is removed outright: every function below reads
#    `transaction_timestamp()` and accepts no time from anyone.
#
#    Deterministic tests no longer need it. Due-ness is arranged by writing
#    `due_at`, lease expiry by writing `lease_expires_at`, and exact due-time
#    equality by inserting and claiming inside one transaction, where
#    `transaction_timestamp()` is by definition constant.
#
# 2. The transport is platform-control authority, not ordinary runtime authority.
#
#    schemas/POSTGRESQL_SCHEMA.md:175 requires the scheduler's dispatch function
#    to be "revoked from `PUBLIC`, granted only to `f1_platform_worker`"; :166
#    scopes scheduler leadership to `f1_platform_worker` registered functions;
#    :136 limits `f1_web` to "registered browser/API tables and functions only";
#    and :143 states that every reviewed restricted function is "granted only to
#    its named runtime role". Granting these to the `f1_runtime` group put them in
#    reach of the request-serving role. The grant change itself lives in
#    F1::RuntimeGrants (the single grant source); this migration only redefines
#    the functions and re-asserts the PUBLIC revoke.
class RestrictScheduledActionTransport < ActiveRecord::Migration[8.1]
  def up
    drop_previous
    create_claim_function
    create_dispatch_function
    create_settle_function
    create_release_function
    create_expired_lease_sweep_function
    create_cancel_function
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "reinstating a caller-supplied due-time override would reopen a premature-expiry defect"
  end

  private

  # The previous signatures carried the trailing `timestamptz` override.
  def drop_previous
    %w[
      f1_claim_due_scheduled_actions(uuid,integer,integer,timestamptz)
      f1_dispatch_scheduled_action(uuid,uuid,bigint,uuid,integer,timestamptz)
      f1_settle_scheduled_action(uuid,uuid,bigint,text,text,timestamptz)
      f1_release_scheduled_action_claim(uuid,uuid,bigint,text,timestamptz)
      f1_release_expired_scheduled_action_leases(integer,timestamptz)
      f1_cancel_scheduled_action(uuid,text,timestamptz)
    ].each { |sig| execute "DROP FUNCTION IF EXISTS #{sig};" }
  end

  def create_claim_function
    execute <<~SQL
      CREATE FUNCTION f1_claim_due_scheduled_actions(
        p_owner uuid, p_limit integer, p_lease_seconds integer
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
      DECLARE v_now timestamptz(6) := transaction_timestamp();
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
      REVOKE ALL ON FUNCTION f1_claim_due_scheduled_actions(uuid, integer, integer) FROM PUBLIC;
    SQL
  end

  def create_dispatch_function
    execute <<~SQL
      CREATE FUNCTION f1_dispatch_scheduled_action(
        p_action_id uuid, p_expected_owner uuid, p_expected_generation bigint,
        p_worker_owner uuid, p_lease_seconds integer
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
      DECLARE v_now timestamptz(6) := transaction_timestamp();
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
      REVOKE ALL ON FUNCTION f1_dispatch_scheduled_action(uuid, uuid, bigint, uuid, integer) FROM PUBLIC;
    SQL
  end

  def create_settle_function
    execute <<~SQL
      CREATE FUNCTION f1_settle_scheduled_action(
        p_action_id uuid, p_owner uuid, p_generation bigint, p_status text, p_reason text
      )
      RETURNS boolean
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
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
          AND (a.status = 'dispatched' OR (a.status = 'claimed' AND p_status = 'quarantined'));
        GET DIAGNOSTICS v_changed = ROW_COUNT;
        RETURN v_changed > 0;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_settle_scheduled_action(uuid, uuid, bigint, text, text) FROM PUBLIC;
    SQL
  end

  def create_release_function
    execute <<~SQL
      CREATE FUNCTION f1_release_scheduled_action_claim(
        p_action_id uuid, p_owner uuid, p_generation bigint, p_reason text
      )
      RETURNS boolean
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
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
      REVOKE ALL ON FUNCTION f1_release_scheduled_action_claim(uuid, uuid, bigint, text) FROM PUBLIC;
    SQL
  end

  def create_expired_lease_sweep_function
    execute <<~SQL
      CREATE FUNCTION f1_release_expired_scheduled_action_leases(p_limit integer)
      RETURNS integer
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
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
      REVOKE ALL ON FUNCTION f1_release_expired_scheduled_action_leases(integer) FROM PUBLIC;
    SQL
  end

  def create_cancel_function
    execute <<~SQL
      CREATE FUNCTION f1_cancel_scheduled_action(p_action_id uuid, p_reason text)
      RETURNS boolean
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
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
      REVOKE ALL ON FUNCTION f1_cancel_scheduled_action(uuid, text) FROM PUBLIC;
    SQL
  end
end
