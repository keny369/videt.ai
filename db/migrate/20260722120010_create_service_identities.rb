# frozen_string_literal: true

# A durable, revocable Service Identity for service-only execution.
#
# schemas/POSTGRESQL_SCHEMA.md:43 classes `service_identity_id` as an F1 row
# identity and requires that "every discriminator arm has the named FK/existence
# check": a bare UUID constant is therefore not a Service Identity, it is an
# unvalidated string that happens to be shaped like one. :202 fixes the record —
# `subject text NOT NULL UNIQUE`, `display_name`, `status CHECK
# ('active','suspended','revoked')`, `key_id`, `permission_scope jsonb`,
# `activated_at`, `revoked_at` — and :166 places global service identities in
# platform-control scope, reachable through `f1_platform_worker` registered
# functions and never through an arbitrary tenant query.
#
# This migration adds only what ScheduledAction execution needs to be sound:
#
#   * the canonical table, with no runtime grant at all;
#   * one seeded row for the reserved ScheduledAction executor, so the identity
#     the transport names actually exists and can be suspended or revoked;
#   * a foreign key from `scheduled_actions.executing_service_identity_id`, so an
#     arbitrary deployment-supplied UUID cannot enter the timer table; and
#   * an active-identity predicate inside the claim function, so a suspended or
#     revoked executor stops being able to execute anything — the XOR check on
#     the ledger proves only that exactly one attribution column is populated,
#     never that the identity is real or currently permitted.
#
# It deliberately builds no credential, JWT-binding or transport authentication:
# `service_jwt_bindings` (:203) and `f1_enter_tenant_service_context` belong to
# the slice that authenticates an inbound service caller. Nothing here
# authenticates anybody; it makes the executing identity referentially real,
# revocable and checked at the moment work is claimed.
class CreateServiceIdentities < ActiveRecord::Migration[8.1]
  # The reserved ScheduledAction executor. Its UUID is fixed so that an action
  # scheduled by one release still names the same executing identity when a later
  # release runs it.
  EXECUTOR_ID = "0192f100-0000-7000-8000-00005c8ed010"
  EXECUTOR_SUBJECT = "f1.scheduled_action_executor"

  def up
    create_table_and_policy
    seed_scheduled_action_executor
    bind_scheduled_actions
    require_active_identity_to_claim
  end

  def down
    execute "ALTER TABLE scheduled_actions DROP CONSTRAINT IF EXISTS scheduled_actions_executing_service_identity_fkey;"
    execute "DROP TABLE IF EXISTS service_identities;"
  end

  private

  def create_table_and_policy
    execute <<~SQL
      CREATE TABLE service_identities (
        id                uuid PRIMARY KEY,
        state_version     bigint NOT NULL DEFAULT 0,
        lock_version      bigint NOT NULL DEFAULT 0,
        created_at        timestamptz(6) NOT NULL,
        updated_at        timestamptz(6) NOT NULL,
        organization_id   uuid,
        project_id        uuid,
        subject           text NOT NULL UNIQUE,
        display_name      text NOT NULL,
        status            text NOT NULL CHECK (status IN ('active','suspended','revoked')),
        key_id            text NOT NULL,
        permission_scope  jsonb NOT NULL,
        activated_at      timestamptz(6),
        revoked_at        timestamptz(6),
        CONSTRAINT service_identity_status_times CHECK (
          (status = 'active') = (activated_at IS NOT NULL AND revoked_at IS NULL)
        )
      );
      -- Platform control (POSTGRESQL_SCHEMA.md :166 "global service identities
      -- ... `f1_platform_worker` registered functions ... no tenant payload and
      -- no arbitrary tenant query"). This is a global restricted table, not a
      -- tenant table, so it takes the same posture as the receipt store and the
      -- reference registry: ENABLE (not FORCE) row level security with no
      -- policy, so every non-owner sees nothing at all, plus PUBLIC revoked and
      -- no runtime grant of any kind. It is read only by the owner-side
      -- SECURITY DEFINER claim function.
      ALTER TABLE service_identities ENABLE ROW LEVEL SECURITY;
      REVOKE ALL ON service_identities FROM PUBLIC;
    SQL
  end

  def seed_scheduled_action_executor
    execute <<~SQL
      INSERT INTO service_identities
        (id, created_at, updated_at, subject, display_name, status, key_id, permission_scope, activated_at)
      VALUES ('#{EXECUTOR_ID}', now(), now(), '#{EXECUTOR_SUBJECT}',
              'F1 ScheduledAction executor', 'active', 'f1-scheduled-action-executor-v1',
              '{"scheduled_action":["execute"]}'::jsonb, now())
      ON CONFLICT (id) DO NOTHING;
    SQL
  end

  def bind_scheduled_actions
    execute <<~SQL
      ALTER TABLE scheduled_actions
        ADD CONSTRAINT scheduled_actions_executing_service_identity_fkey
        FOREIGN KEY (executing_service_identity_id) REFERENCES service_identities (id);
    SQL
  end

  # An identity that has been suspended or revoked must stop executing work. The
  # check belongs in the claim, not in the handler: it is the earliest point, it
  # covers every action kind at once, and an unclaimable action simply stays
  # `pending` with no product effect and no partial execution to unwind.
  def require_active_identity_to_claim
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_claim_due_scheduled_actions(
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
          JOIN service_identities s ON s.id = a.executing_service_identity_id
          WHERE a.status = 'pending'
            AND a.due_at <= v_now
            AND (a.not_before_at IS NULL OR a.not_before_at <= v_now)
            AND s.status = 'active'
          ORDER BY a.due_at, a.id
          FOR UPDATE OF a SKIP LOCKED
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
end
