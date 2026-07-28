# frozen_string_literal: true

# F-05 Entitlement reservation subsystem (entitlement-interim-v1) — owner D2, DECISIONS ADR-069.
# The shared reserve/commit/release/heartbeat surface for high-cost operations (crawl.start,
# reassessment.start, ai.generate, export.generate), built as a foundation BEFORE S-07-003
# StartCrawl consumes it. Contract: WORKFLOW_SPECIFICATIONS.md § Interim Entitlement Contract
# :513-554; schemas/POSTGRESQL_SCHEMA.md :418-424.
#
# Five FORCE-RLS tenant tables:
#   entitlement_counter_windows  T-MUT — the per-(org,counter_group,UTC-day) accumulator; guard
#                                freezes identity + limits, refuses DELETE, permits only the
#                                counter columns to move.
#   entitlement_decisions        T-IMM — the immutable Allow/AllowWithWarning/Block record.
#   entitlement_reservations     T-MUT — the lease-bearing reservation aggregate; F-05 OWNS the
#                                reserved->executing->committed/released/expired state machine.
#   entitlement_lease_heartbeats T-IMM — one immutable row per accepted lease renewal.
#   entitlement_commit_intents   T-MUT — pending->committed/released durable-commit record.
#
# The operative soft/hard limits are the fixed entitlement-interim-v1 constant (WORKFLOW :527),
# NOT the non-operative placeholder numbers in the genesis entitlement_policies bytes (ADR-069).
class CreateEntitlementReservationSubsystem < ActiveRecord::Migration[8.1]
  def up
    create_counter_windows
    create_decisions
    create_reservations
    create_lease_heartbeats
    create_commit_intents

    %w[entitlement_counter_windows entitlement_decisions entitlement_reservations
       entitlement_lease_heartbeats entitlement_commit_intents].each do |t|
      force_rls(t, using: "organization_id = f1_current_context_org()")
    end

    create_counter_windows_guard
    create_decisions_guard
    create_reservations_guard
    create_lease_heartbeats_guard
    create_commit_intents_guard
  end

  def down
    %w[entitlement_commit_intents entitlement_lease_heartbeats entitlement_reservations
       entitlement_decisions entitlement_counter_windows].each do |t|
      execute "DROP TRIGGER IF EXISTS #{t}_guard ON #{t};"
    end
    %w[f1_entitlement_commit_intents_guard f1_entitlement_lease_heartbeats_guard
       f1_entitlement_reservations_guard f1_entitlement_decisions_guard
       f1_entitlement_counter_windows_guard].each do |f|
      execute "DROP FUNCTION IF EXISTS #{f}();"
    end
    %w[entitlement_commit_intents entitlement_lease_heartbeats entitlement_reservations
       entitlement_decisions entitlement_counter_windows].each do |t|
      execute "DROP TABLE IF EXISTS #{t};"
    end
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

  # ---- tables -------------------------------------------------------------

  # The authoritative per-(Organization, counter_group, UTC-day) counter. `reserved_units` accrues
  # on reserve and moves to `committed_units` on commit (or decrements on release); `low_cost_units`
  # is reserved for the deferred baseline_reads path (S-22). Limits + policy_version are pinned at
  # window creation from the active entitlement-interim-v1 policy.
  def create_counter_windows
    execute <<~SQL
      CREATE TABLE entitlement_counter_windows (
        id                 uuid PRIMARY KEY,
        state_version      bigint NOT NULL DEFAULT 0,
        created_at         timestamptz(6) NOT NULL,
        updated_at         timestamptz(6) NOT NULL,
        correlation_id     uuid NOT NULL,
        organization_id    uuid NOT NULL,
        counter_group      text NOT NULL,
        window_start       timestamptz(6) NOT NULL,
        window_end         timestamptz(6) NOT NULL,
        soft_limit         bigint NOT NULL,
        hard_limit         bigint NOT NULL,
        reserved_units     bigint NOT NULL DEFAULT 0,
        committed_units    bigint NOT NULL DEFAULT 0,
        low_cost_units     bigint NOT NULL DEFAULT 0,
        policy_version     text NOT NULL,
        reconciliation_state text NOT NULL DEFAULT 'authoritative'
          CHECK (reconciliation_state IN ('authoritative','reconciling')),
        CONSTRAINT entitlement_counter_windows_limits_ordered CHECK (soft_limit < hard_limit),
        CONSTRAINT entitlement_counter_windows_window_ordered CHECK (window_end > window_start),
        CONSTRAINT entitlement_counter_windows_units_nonneg CHECK (
          reserved_units >= 0 AND committed_units >= 0 AND low_cost_units >= 0),
        CONSTRAINT entitlement_counter_windows_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT entitlement_counter_windows_org_fk FOREIGN KEY (organization_id)
          REFERENCES organizations (id)
      );
      CREATE UNIQUE INDEX entitlement_counter_windows_slot_unique
        ON entitlement_counter_windows (organization_id, counter_group, window_start, window_end);
    SQL
  end

  # The immutable Entitlement Decision (WORKFLOW :539). Exactly one of the human Account or the
  # service identity is the subject (XOR). `reservation_id` is set only for an allowed high-cost
  # action; `counter_window_id` is null only for a pre-window short-circuit (e.g. counter_unavailable).
  def create_decisions
    execute <<~SQL
      CREATE TABLE entitlement_decisions (
        id                       uuid PRIMARY KEY,
        created_at               timestamptz(6) NOT NULL,
        decided_at               timestamptz(6) NOT NULL,
        correlation_id           uuid NOT NULL,
        organization_id          uuid NOT NULL,
        account_id               uuid,
        service_identity_id      uuid,
        operation                text NOT NULL,
        usage_unit               text NOT NULL,
        requested_units          bigint NOT NULL,
        counter_window_id        uuid,
        window_start             timestamptz(6),
        window_end               timestamptz(6),
        policy_version           text NOT NULL,
        plan_version             text NOT NULL,
        soft_limit               bigint,
        hard_limit               bigint,
        committed_before         bigint,
        committed_after          bigint,
        active_reserved_before   bigint,
        active_reserved_after    bigint,
        reservation_id           uuid,
        cached_snapshot_id       uuid,
        cached_snapshot_age      bigint,
        idempotency_key_digest   bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        retry_of_decision_id     uuid,
        decision                 text NOT NULL CHECK (decision IN ('allow','allow_with_warning','block')),
        reason_code              text NOT NULL CHECK (reason_code IN (
                                   'within_limit','soft_limit_reached','hard_limit_exceeded',
                                   'organization_inactive','actor_inactive','service_unauthorized',
                                   'entitlement_inactive','policy_unavailable','counter_unavailable',
                                   'cached_policy_snapshot_used','cached_counter_snapshot_used',
                                   'operation_unknown','reservation_conflict')),
        recovery_action          text NOT NULL CHECK (recovery_action IN (
                                   'none','wait_for_window','upgrade_plan','reactivate_organization',
                                   'reactivate_actor','restore_policy','restore_counter',
                                   'submit_new_attempt','contact_support')),
        CONSTRAINT entitlement_decisions_subject_xor CHECK (
          (account_id IS NOT NULL) <> (service_identity_id IS NOT NULL)),
        CONSTRAINT entitlement_decisions_reservation_iff_allowed CHECK (
          reservation_id IS NULL OR decision IN ('allow','allow_with_warning')),
        CONSTRAINT entitlement_decisions_requested_positive CHECK (requested_units > 0),
        CONSTRAINT entitlement_decisions_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT entitlement_decisions_org_fk FOREIGN KEY (organization_id)
          REFERENCES organizations (id),
        CONSTRAINT entitlement_decisions_window_fk FOREIGN KEY (organization_id, counter_window_id)
          REFERENCES entitlement_counter_windows (organization_id, id)
      );
      CREATE INDEX entitlement_decisions_org_operation ON entitlement_decisions (organization_id, operation, decided_at);
    SQL
  end

  # The lease-bearing reservation. One per Decision. F-05 owns the state machine:
  # reserved -> executing | released | expired ; executing -> committed | released.
  def create_reservations
    execute <<~SQL
      CREATE TABLE entitlement_reservations (
        id                 uuid PRIMARY KEY,
        state_version      bigint NOT NULL DEFAULT 0,
        created_at         timestamptz(6) NOT NULL,
        updated_at         timestamptz(6) NOT NULL,
        correlation_id     uuid NOT NULL,
        organization_id    uuid NOT NULL,
        decision_id        uuid NOT NULL,
        counter_window_id  uuid NOT NULL,
        units              bigint NOT NULL,
        lease_generation   bigint NOT NULL DEFAULT 0,
        lease_due          timestamptz(6) NOT NULL,
        last_heartbeat_at  timestamptz(6),
        started_at         timestamptz(6),
        state              text NOT NULL CHECK (state IN ('reserved','executing','committed','released','expired')),
        terminal_at        timestamptz(6),
        terminal_reason    text,
        CONSTRAINT entitlement_reservations_units_positive CHECK (units > 0),
        CONSTRAINT entitlement_reservations_terminal_shape CHECK (
          (state IN ('reserved','executing') AND terminal_at IS NULL) OR
          (state IN ('committed','released','expired') AND terminal_at IS NOT NULL)),
        CONSTRAINT entitlement_reservations_executing_started CHECK (
          (state = 'reserved' AND started_at IS NULL) OR state <> 'reserved'),
        CONSTRAINT entitlement_reservations_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT entitlement_reservations_decision_unique UNIQUE (decision_id),
        CONSTRAINT entitlement_reservations_org_fk FOREIGN KEY (organization_id)
          REFERENCES organizations (id),
        CONSTRAINT entitlement_reservations_decision_fk FOREIGN KEY (organization_id, decision_id)
          REFERENCES entitlement_decisions (organization_id, id),
        CONSTRAINT entitlement_reservations_window_fk FOREIGN KEY (organization_id, counter_window_id)
          REFERENCES entitlement_counter_windows (organization_id, id)
      );
      CREATE INDEX entitlement_reservations_window_state ON entitlement_reservations (organization_id, counter_window_id, state);
    SQL
  end

  # One immutable row per accepted lease renewal (schema :421). Advances the parent reservation's
  # lease to renewed_lease_expires_at in the same parent-row-lock transaction.
  def create_lease_heartbeats
    execute <<~SQL
      CREATE TABLE entitlement_lease_heartbeats (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        entitlement_reservation_id uuid NOT NULL,
        heartbeat_generation      bigint NOT NULL CHECK (heartbeat_generation > 0),
        prior_lease_expires_at    timestamptz(6) NOT NULL,
        renewed_lease_expires_at  timestamptz(6) NOT NULL,
        renewed_at                timestamptz(6) NOT NULL,
        worker_process_identity   text NOT NULL,
        worker_service_identity_id uuid NOT NULL,
        status                    text NOT NULL CHECK (status = 'renewed'),
        input_sha256              bytea CHECK (input_sha256 IS NULL OR octet_length(input_sha256) = 32),
        output_sha256             bytea CHECK (output_sha256 IS NULL OR octet_length(output_sha256) = 32),
        CONSTRAINT entitlement_lease_heartbeats_advances CHECK (renewed_lease_expires_at > prior_lease_expires_at),
        CONSTRAINT entitlement_lease_heartbeats_reservation_fk FOREIGN KEY (organization_id, entitlement_reservation_id)
          REFERENCES entitlement_reservations (organization_id, id)
      );
      CREATE UNIQUE INDEX entitlement_lease_heartbeats_generation_unique
        ON entitlement_lease_heartbeats (entitlement_reservation_id, heartbeat_generation);
      CREATE UNIQUE INDEX entitlement_lease_heartbeats_generation_time_unique
        ON entitlement_lease_heartbeats (entitlement_reservation_id, heartbeat_generation, renewed_at);
    SQL
  end

  # The durable-commit record binding a reservation to its operation's durable output (schema :424).
  def create_commit_intents
    execute <<~SQL
      CREATE TABLE entitlement_commit_intents (
        id                   uuid PRIMARY KEY,
        state_version        bigint NOT NULL DEFAULT 0,
        created_at           timestamptz(6) NOT NULL,
        updated_at           timestamptz(6) NOT NULL,
        correlation_id       uuid NOT NULL,
        organization_id      uuid NOT NULL,
        reservation_id       uuid NOT NULL,
        durable_output_type  text NOT NULL,
        durable_output_id    uuid NOT NULL,
        durable_output_sha256 bytea CHECK (durable_output_sha256 IS NULL OR octet_length(durable_output_sha256) = 32),
        state                text NOT NULL CHECK (state IN ('pending','committed','released')),
        terminal_at          timestamptz(6),
        terminal_reason      text,
        CONSTRAINT entitlement_commit_intents_terminal_shape CHECK (
          (state = 'pending' AND terminal_at IS NULL) OR
          (state IN ('committed','released') AND terminal_at IS NOT NULL)),
        CONSTRAINT entitlement_commit_intents_org_fk FOREIGN KEY (organization_id)
          REFERENCES organizations (id),
        CONSTRAINT entitlement_commit_intents_reservation_fk FOREIGN KEY (organization_id, reservation_id)
          REFERENCES entitlement_reservations (organization_id, id)
      );
      CREATE UNIQUE INDEX entitlement_commit_intents_reservation_output_unique
        ON entitlement_commit_intents (reservation_id, durable_output_type, durable_output_id);
    SQL
  end

  # ---- guards -------------------------------------------------------------

  # counter_windows: freeze identity + pinned limits + policy_version; permit only the three counter
  # columns and reconciliation_state to move; refuse DELETE.
  def create_counter_windows_guard
    execute <<~SQL
      CREATE FUNCTION f1_entitlement_counter_windows_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'entitlement_counter_window_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.counter_group IS DISTINCT FROM OLD.counter_group
           OR NEW.window_start IS DISTINCT FROM OLD.window_start
           OR NEW.window_end IS DISTINCT FROM OLD.window_end
           OR NEW.soft_limit IS DISTINCT FROM OLD.soft_limit
           OR NEW.hard_limit IS DISTINCT FROM OLD.hard_limit
           OR NEW.policy_version IS DISTINCT FROM OLD.policy_version
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id THEN
          RAISE EXCEPTION 'entitlement_counter_window_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER entitlement_counter_windows_guard BEFORE UPDATE OR DELETE ON entitlement_counter_windows
        FOR EACH ROW EXECUTE FUNCTION f1_entitlement_counter_windows_guard();
    SQL
  end

  # decisions: fully immutable (T-IMM).
  def create_decisions_guard
    execute <<~SQL
      CREATE FUNCTION f1_entitlement_decisions_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'entitlement_decision_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER entitlement_decisions_guard BEFORE UPDATE OR DELETE ON entitlement_decisions
        FOR EACH ROW EXECUTE FUNCTION f1_entitlement_decisions_guard();
    SQL
  end

  # reservations: F-05 owns the lifecycle. Freeze identity/lineage; refuse DELETE; permit exactly
  # reserved->executing, reserved->released, reserved->expired, executing->committed, executing->released.
  def create_reservations_guard
    execute <<~SQL
      CREATE FUNCTION f1_entitlement_reservations_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'entitlement_reservation_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.decision_id IS DISTINCT FROM OLD.decision_id
           OR NEW.counter_window_id IS DISTINCT FROM OLD.counter_window_id
           OR NEW.units IS DISTINCT FROM OLD.units
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id THEN
          RAISE EXCEPTION 'entitlement_reservation_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state
           AND NOT (
             (OLD.state = 'reserved'  AND NEW.state IN ('executing','released','expired')) OR
             (OLD.state = 'executing' AND NEW.state IN ('committed','released'))
           ) THEN
          RAISE EXCEPTION 'entitlement_reservation_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER entitlement_reservations_guard BEFORE UPDATE OR DELETE ON entitlement_reservations
        FOR EACH ROW EXECUTE FUNCTION f1_entitlement_reservations_guard();
    SQL
  end

  # lease_heartbeats: fully immutable (T-IMM).
  def create_lease_heartbeats_guard
    execute <<~SQL
      CREATE FUNCTION f1_entitlement_lease_heartbeats_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'entitlement_lease_heartbeat_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER entitlement_lease_heartbeats_guard BEFORE UPDATE OR DELETE ON entitlement_lease_heartbeats
        FOR EACH ROW EXECUTE FUNCTION f1_entitlement_lease_heartbeats_guard();
    SQL
  end

  # commit_intents: freeze identity + durable-output binding; refuse DELETE; permit only
  # pending->committed and pending->released.
  def create_commit_intents_guard
    execute <<~SQL
      CREATE FUNCTION f1_entitlement_commit_intents_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'entitlement_commit_intent_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.reservation_id IS DISTINCT FROM OLD.reservation_id
           OR NEW.durable_output_type IS DISTINCT FROM OLD.durable_output_type
           OR NEW.durable_output_id IS DISTINCT FROM OLD.durable_output_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id THEN
          RAISE EXCEPTION 'entitlement_commit_intent_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state
           AND NOT (OLD.state = 'pending' AND NEW.state IN ('committed','released')) THEN
          RAISE EXCEPTION 'entitlement_commit_intent_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER entitlement_commit_intents_guard BEFORE UPDATE OR DELETE ON entitlement_commit_intents
        FOR EACH ROW EXECUTE FUNCTION f1_entitlement_commit_intents_guard();
    SQL
  end
end
