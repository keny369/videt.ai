# frozen_string_literal: true

# F-04 Background Execution — the reliability substrate the Jul-22 create migration
# (20260722120007 :29-34) deliberately deferred to "the Redis/Sidekiq transport" slice:
# the Work Dispatch Binding, the infrastructure dispatch-retry counter/backoff, and the
# transport-function changes that make `work_id` a real binding identity rather than a
# throwaway locator. Ratified scope: F-04_COMPLETION_MATRIX.md + F-04_TRANSPORT_DESIGN.md.
#
# 1. `dispatch_attempt_count` + `next_dispatch_at` on scheduled_actions — the exact
#    1/5/30/120/600s enqueue-failure schedule and its attempt-6 `redis_dispatch_exhausted`
#    quarantine (BACKGROUND_PROCESSING.md :313), gated in the claim scan.
# 2. `work_dispatch_bindings` — the durable, insert-only, immutable binding created in the
#    claim transaction (:115, :243). Its UUID is the envelope `work_id`; the receiver
#    resolves the authorised target THROUGH it, never from an envelope string. Reached only
#    through the SECURITY DEFINER transport functions, so it carries no runtime grant.
# 3. The claim function now creates the binding and returns its `work_id`, and gates on
#    `next_dispatch_at`; the dispatch function resolves the binding and CAS-transfers the
#    action, resetting the dispatch counter; and `f1_fail_scheduled_action_dispatch` applies
#    the retry schedule / terminal quarantine. Generic `scheduled_action_dispatch` binds the
#    action as both source and target (target_type = 'scheduled_action'); specialised targets
#    are a later, backwards-compatible extension (no S-05 aggregate is invented here).
class AddBackgroundExecutionTransport < ActiveRecord::Migration[8.1]
  def up
    add_dispatch_retry_columns
    create_work_dispatch_bindings
    drop_previous_transport_functions
    create_claim_function
    create_dispatch_function
    create_dispatch_failure_function
  end

  # Reverses the additions only (the prior claim/dispatch functions are recreated by `up`,
  # whose drop-if-exists tolerates their absence). Reverting in a running deployment would
  # reopen a movable-work_id and unbounded-enqueue-retry posture; this exists for local schema
  # regeneration (db:migrate:redo), never as an operational rollback.
  def down
    execute "DROP FUNCTION IF EXISTS f1_fail_scheduled_action_dispatch(uuid, uuid, bigint);"
    execute "DROP FUNCTION IF EXISTS f1_dispatch_scheduled_action(uuid, bigint, uuid, integer);"
    execute "DROP FUNCTION IF EXISTS f1_claim_due_scheduled_actions(uuid, integer, integer);"
    execute "DROP TABLE IF EXISTS work_dispatch_bindings;"
    execute "DROP FUNCTION IF EXISTS f1_work_dispatch_bindings_immutable();"
    execute <<~SQL
      ALTER TABLE scheduled_actions
        DROP COLUMN IF EXISTS dispatch_attempt_count,
        DROP COLUMN IF EXISTS next_dispatch_at;
    SQL
  end

  private

  def add_dispatch_retry_columns
    execute <<~SQL
      ALTER TABLE scheduled_actions
        ADD COLUMN dispatch_attempt_count bigint NOT NULL DEFAULT 0
          CHECK (dispatch_attempt_count >= 0),
        ADD COLUMN next_dispatch_at timestamptz(6);
    SQL
  end

  # The direct claim-owner row for a generic job is the ScheduledAction itself
  # (:243). The column set retains source ScheduledAction id/generation and a
  # target (type, id, generation); F-04 populates only the generic case. Insert-only
  # and immutable: a trigger refuses UPDATE and DELETE from every role, so a binding,
  # once minted in the claim transaction, is a durable, unforgeable dispatch authority.
  def create_work_dispatch_bindings
    execute <<~SQL
      CREATE TABLE work_dispatch_bindings (
        id                      uuid PRIMARY KEY,
        created_at              timestamptz(6) NOT NULL,
        organization_id         uuid,
        source_action_id        uuid NOT NULL,
        source_claim_generation bigint NOT NULL CHECK (source_claim_generation > 0),
        action_kind             text NOT NULL,
        -- Closed target vocabulary; F-04 mints only the generic action-as-target.
        -- Specialised target types widen this set backwards-compatibly in a later slice.
        target_type             text NOT NULL CHECK (target_type IN ('scheduled_action')),
        target_id               uuid NOT NULL,
        target_generation       bigint CHECK (target_generation IS NULL OR target_generation > 0),
        CONSTRAINT work_dispatch_bindings_identity UNIQUE (source_action_id, source_claim_generation)
      );
      CREATE INDEX work_dispatch_bindings_source
        ON work_dispatch_bindings (source_action_id, source_claim_generation);

      CREATE FUNCTION f1_work_dispatch_bindings_immutable() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'work_dispatch_binding_is_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER work_dispatch_bindings_no_update BEFORE UPDATE OR DELETE ON work_dispatch_bindings
        FOR EACH ROW EXECUTE FUNCTION f1_work_dispatch_bindings_immutable();

      ALTER TABLE work_dispatch_bindings ENABLE ROW LEVEL SECURITY;
      CREATE POLICY work_dispatch_bindings_context ON work_dispatch_bindings
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON work_dispatch_bindings FROM PUBLIC;
    SQL
  end

  # The restrict migration (20260722120009) created these exact signatures.
  def drop_previous_transport_functions
    execute "DROP FUNCTION IF EXISTS f1_claim_due_scheduled_actions(uuid,integer,integer);"
    execute "DROP FUNCTION IF EXISTS f1_dispatch_scheduled_action(uuid,uuid,bigint,uuid,integer);"
  end

  # Claim (:110-115): at most p_limit due, pending, not-before- AND next-dispatch-eligible
  # rows in (due_at,id) order under FOR UPDATE SKIP LOCKED, each moved to `claimed` with an
  # incremented claim generation, a fresh lease, cleared backoff gate, and a freshly minted
  # Work Dispatch Binding. Returns the action fields plus the binding `work_id`.
  def create_claim_function
    execute <<~SQL
      CREATE FUNCTION f1_claim_due_scheduled_actions(
        p_owner uuid, p_limit integer, p_lease_seconds integer
      )
      RETURNS TABLE (
        id uuid, action_kind text, action_schema_version text, organization_id uuid, project_id uuid,
        target_type text, target_id uuid, product_generation bigint, schedule_generation bigint,
        due_at timestamptz(6), claim_generation bigint, correlation_id uuid, causation_id uuid,
        executing_service_identity_id uuid, payload_refs jsonb, work_id uuid
      )
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      #variable_conflict use_column
      DECLARE v_now timestamptz(6) := transaction_timestamp();
      BEGIN
        RETURN QUERY
        WITH due AS (
          SELECT a.id FROM scheduled_actions a
          JOIN service_identities s ON s.id = a.executing_service_identity_id
          WHERE a.status = 'pending'
            AND a.due_at <= v_now
            AND (a.not_before_at IS NULL OR a.not_before_at <= v_now)
            AND (a.next_dispatch_at IS NULL OR a.next_dispatch_at <= v_now)
            AND s.status = 'active'
          ORDER BY a.due_at, a.id
          FOR UPDATE OF a SKIP LOCKED
          LIMIT greatest(p_limit, 0)
        ),
        claimed AS (
          UPDATE scheduled_actions a
          SET status = 'claimed', claim_owner = p_owner, claim_generation = a.claim_generation + 1,
              claimed_at = v_now, lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
              claim_phase = 'scheduler', last_heartbeat_at = NULL, next_dispatch_at = NULL,
              updated_at = v_now, state_version = a.state_version + 1
          FROM due
          WHERE a.id = due.id
          RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
                    a.target_type, a.target_id, a.product_generation, a.schedule_generation,
                    a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
                    a.executing_service_identity_id, a.payload_refs
        ),
        bound AS (
          INSERT INTO work_dispatch_bindings
            (id, created_at, organization_id, source_action_id, source_claim_generation,
             action_kind, target_type, target_id, target_generation)
          SELECT gen_random_uuid(), v_now, c.organization_id, c.id, c.claim_generation,
                 c.action_kind, 'scheduled_action', c.id, c.claim_generation
          FROM claimed c
          RETURNING id AS work_id, source_action_id
        )
        SELECT c.id, c.action_kind, c.action_schema_version, c.organization_id, c.project_id,
               c.target_type, c.target_id, c.product_generation, c.schedule_generation,
               c.due_at, c.claim_generation, c.correlation_id, c.causation_id,
               c.executing_service_identity_id, c.payload_refs, b.work_id
        FROM claimed c JOIN bound b ON b.source_action_id = c.id;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_claim_due_scheduled_actions(uuid, integer, integer) FROM PUBLIC;
    SQL
  end

  # Dispatch (:119, :243): resolve the binding by work_id (a keyed lookup — no
  # constantisation, no method dispatch), require the envelope's claim generation to equal
  # the binding's, then CAS-transfer the source action to this worker. A first transfer moves
  # claim_phase scheduler->worker; a duplicate with the same worker resumes idempotently; any
  # other owner/generation/terminal/reclaimed state returns no row and performs no product
  # work. A successful transfer resets the dispatch-retry counter/gate.
  def create_dispatch_function
    execute <<~SQL
      CREATE FUNCTION f1_dispatch_scheduled_action(
        p_work_id uuid, p_expected_generation bigint, p_worker_owner uuid, p_lease_seconds integer
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
      DECLARE
        v_now timestamptz(6) := transaction_timestamp();
        v_action_id uuid;
        v_generation bigint;
      BEGIN
        SELECT b.source_action_id, b.source_claim_generation
          INTO v_action_id, v_generation
          FROM work_dispatch_bindings b WHERE b.id = p_work_id;
        IF v_action_id IS NULL OR v_generation <> p_expected_generation THEN
          RETURN;
        END IF;

        RETURN QUERY
        UPDATE scheduled_actions a
        SET status = 'dispatched',
            dispatched_at = coalesce(a.dispatched_at, v_now),
            claim_owner = p_worker_owner, claim_phase = 'worker',
            lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
            dispatch_attempt_count = 0, next_dispatch_at = NULL,
            updated_at = v_now, state_version = a.state_version + 1
        WHERE a.id = v_action_id
          AND a.claim_generation = v_generation
          AND a.status IN ('claimed','dispatched')
          AND (a.claim_phase = 'scheduler'
               OR (a.claim_phase = 'worker' AND a.claim_owner = p_worker_owner))
        RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
                  a.target_type, a.target_id, a.product_generation, a.schedule_generation,
                  a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
                  a.executing_service_identity_id, a.payload_refs, a.identity_sha256;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_dispatch_scheduled_action(uuid, bigint, uuid, integer) FROM PUBLIC;
    SQL
  end

  # Infrastructure dispatch retry (:313). Called only when Redis enqueue fails for a row this
  # scheduler owner still holds at this generation, before any worker transfer (dispatched_at
  # null). Attempts elapse at 1, 5, 30, 120, 600 s; the sixth failure quarantines the row with
  # `redis_dispatch_exhausted` (the caller raises a high alert). Non-terminal failures return
  # the row to `pending` with the backoff gate set and the identity unchanged; the counter
  # persists across re-claims until a successful transfer (or, later, G5 recovery) resets it.
  # Returns 'quarantined', 'rescheduled', or 'noop'.
  def create_dispatch_failure_function
    execute <<~SQL
      CREATE FUNCTION f1_fail_scheduled_action_dispatch(
        p_action_id uuid, p_owner uuid, p_generation bigint
      )
      RETURNS text
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE
        v_now timestamptz(6) := transaction_timestamp();
        v_count bigint;
        v_intervals integer[] := ARRAY[1, 5, 30, 120, 600];
      BEGIN
        SELECT dispatch_attempt_count INTO v_count
          FROM scheduled_actions
          WHERE id = p_action_id AND claim_owner = p_owner AND claim_generation = p_generation
            AND status = 'claimed' AND claim_phase = 'scheduler' AND dispatched_at IS NULL
          FOR UPDATE;
        IF NOT FOUND THEN
          RETURN 'noop';
        END IF;

        v_count := v_count + 1;
        IF v_count >= 6 THEN
          UPDATE scheduled_actions
          SET status = 'quarantined', quarantined_at = v_now, reason = 'redis_dispatch_exhausted',
              dispatch_attempt_count = v_count,
              claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
              claim_phase = NULL, last_heartbeat_at = NULL,
              updated_at = v_now, state_version = state_version + 1
          WHERE id = p_action_id;
          RETURN 'quarantined';
        END IF;

        UPDATE scheduled_actions
        SET status = 'pending', dispatch_attempt_count = v_count,
            next_dispatch_at = v_now + make_interval(secs => v_intervals[v_count]),
            reason = 'redis_dispatch_retry_scheduled',
            claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
            claim_phase = NULL, last_heartbeat_at = NULL,
            updated_at = v_now, state_version = state_version + 1
        WHERE id = p_action_id;
        RETURN 'rescheduled';
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_fail_scheduled_action_dispatch(uuid, uuid, bigint) FROM PUBLIC;
    SQL
  end
end
