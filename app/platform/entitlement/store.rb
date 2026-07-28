# frozen_string_literal: true

require "json"

module Platform
  module Entitlement
    # Persistence for the F-05 entitlement reservation subsystem (entitlement-interim-v1), run inside
    # the consuming operation's unit of work under its proved Organization context. It owns the durable
    # entitlement STATE — counter windows, immutable Decisions, reservations, lease heartbeats and
    # commit intents — and the counter accounting. It writes NO event_registry envelopes: per S-22 the
    # entitlement checkpoints are "internal to the operation being gated", so the domain events
    # (EntitlementReserved/Committed/Released/LeaseRenewed/...) are emitted by the consuming workflow's
    # ledger (workflow_id = the consumer's, e.g. WF-005 for crawl.start) from the data these rows carry.
    class Store
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize concurrent decisions against one counter window (WORKFLOW :549) before the
      # get-or-create read-modify-write of its counters.
      def lock_window(organization_id, counter_group, window_start)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
             ["entitlement-window:#{organization_id}:#{counter_group}:#{iso(window_start)}"])
      end

      def active_entitlement_policy(organization_id)
        exec(<<~SQL, [organization_id]).to_a.first
          SELECT id, semantic_version, plan_version FROM entitlement_policies
          WHERE organization_id = $1::uuid AND status = 'active' LIMIT 1
        SQL
      end

      # The current window row for (org, counter_group, day), or nil.
      def window(organization_id, counter_group, window_start, window_end)
        exec(<<~SQL, [organization_id, counter_group, iso(window_start), iso(window_end)]).to_a.first
          SELECT * FROM entitlement_counter_windows
          WHERE organization_id = $1::uuid AND counter_group = $2
            AND window_start = $3::timestamptz AND window_end = $4::timestamptz
        SQL
      end

      def insert_window(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:counter_group],
                  iso(row[:window_start]), iso(row[:window_end]), row[:soft_limit], row[:hard_limit], row[:policy_version]]
        exec(<<~SQL, params)
          INSERT INTO entitlement_counter_windows
            (id, state_version, created_at, updated_at, correlation_id, organization_id, counter_group,
             window_start, window_end, soft_limit, hard_limit, reserved_units, committed_units, low_cost_units,
             policy_version, reconciliation_state)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5,$6::timestamptz,$7::timestamptz,
                  $8,$9,0,0,0,$10,'authoritative')
        SQL
      end

      # Move counter units on a window. `reserved` and `committed` are signed deltas applied atomically.
      def adjust_window(id, reserved_delta:, committed_delta:, now:)
        exec(<<~SQL, [id, reserved_delta, committed_delta, iso(now)])
          UPDATE entitlement_counter_windows
          SET reserved_units = reserved_units + $2, committed_units = committed_units + $3,
              state_version = state_version + 1, updated_at = $4::timestamptz
          WHERE id = $1::uuid
        SQL
      end

      def insert_decision(row)
        cols = %i[id created_at decided_at correlation_id organization_id account_id service_identity_id
                  operation usage_unit requested_units counter_window_id window_start window_end policy_version
                  plan_version soft_limit hard_limit committed_before committed_after active_reserved_before
                  active_reserved_after reservation_id idempotency_key_digest retry_of_decision_id decision
                  reason_code recovery_action]
        params = [row[:id], iso(row[:now]), iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:account_id], row[:service_identity_id], row[:operation], row[:usage_unit], row[:requested_units],
                  row[:counter_window_id], iso(row[:window_start]), iso(row[:window_end]), row[:policy_version],
                  row[:plan_version], row[:soft_limit], row[:hard_limit], row[:committed_before], row[:committed_after],
                  row[:active_reserved_before], row[:active_reserved_after], row[:reservation_id],
                  bytea(row[:idempotency_key_digest]), row[:retry_of_decision_id], row[:decision], row[:reason_code],
                  row[:recovery_action]]
        exec(<<~SQL, params)
          INSERT INTO entitlement_decisions
            (#{cols.join(', ')})
          VALUES ($1::uuid,$2::timestamptz,$3::timestamptz,$4::uuid,$5::uuid,$6::uuid,$7::uuid,$8,$9,$10,
                  $11::uuid,$12::timestamptz,$13::timestamptz,$14,$15,$16,$17,$18,$19,$20,$21,$22::uuid,$23,$24::uuid,
                  $25,$26,$27)
        SQL
      end

      def insert_reservation(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:decision_id],
                  row[:counter_window_id], row[:units], iso(row[:lease_due])]
        exec(<<~SQL, params)
          INSERT INTO entitlement_reservations
            (id, state_version, created_at, updated_at, correlation_id, organization_id, decision_id,
             counter_window_id, units, lease_generation, lease_due, last_heartbeat_at, started_at, state,
             terminal_at, terminal_reason)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,0,
                  $8::timestamptz,NULL,NULL,'reserved',NULL,NULL)
        SQL
      end

      def reservation(organization_id, id)
        exec("SELECT * FROM entitlement_reservations WHERE organization_id = $1::uuid AND id = $2::uuid",
             [organization_id, id]).to_a.first
      end

      def lock_reservation(organization_id, id)
        exec("SELECT id FROM entitlement_reservations WHERE organization_id = $1::uuid AND id = $2::uuid FOR UPDATE",
             [organization_id, id]).to_a.first
      end

      # Guarded reservation transition (compare-and-swap on state + expected version). The lease/lifecycle
      # columns are COALESCE-kept: a nil argument leaves the current value (these columns only move
      # forward), so the SQL is fully static and parameterized. Returns rows affected.
      def transition_reservation(id, from_state:, to_state:, expected_version:, now:, started_at: nil,
                                 last_heartbeat_at: nil, lease_due: nil, lease_generation: nil,
                                 terminal_at: nil, terminal_reason: nil)
        params = [id, from_state, expected_version, to_state, iso(now), iso(terminal_at), terminal_reason,
                  iso(started_at), iso(last_heartbeat_at), iso(lease_due), lease_generation]
        exec(<<~SQL, params).cmd_tuples
          UPDATE entitlement_reservations
          SET state = $4, state_version = state_version + 1, updated_at = $5::timestamptz,
              terminal_at = $6::timestamptz, terminal_reason = $7,
              started_at = COALESCE($8::timestamptz, started_at),
              last_heartbeat_at = COALESCE($9::timestamptz, last_heartbeat_at),
              lease_due = COALESCE($10::timestamptz, lease_due),
              lease_generation = COALESCE($11, lease_generation)
          WHERE id = $1::uuid AND state = $2 AND state_version = $3
        SQL
      end

      def insert_lease_heartbeat(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:reservation_id],
                  row[:heartbeat_generation], iso(row[:prior_lease_expires_at]), iso(row[:renewed_lease_expires_at]),
                  row[:worker_process_identity], row[:worker_service_identity_id],
                  bytea(row[:input_sha256]), bytea(row[:output_sha256])]
        exec(<<~SQL, params)
          INSERT INTO entitlement_lease_heartbeats
            (id, created_at, correlation_id, organization_id, entitlement_reservation_id, heartbeat_generation,
             prior_lease_expires_at, renewed_lease_expires_at, renewed_at, worker_process_identity,
             worker_service_identity_id, status, input_sha256, output_sha256)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7::timestamptz,$8::timestamptz,$2::timestamptz,
                  $9,$10::uuid,'renewed',$11,$12)
        SQL
      end

      def insert_commit_intent(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:reservation_id],
                  row[:durable_output_type], row[:durable_output_id], bytea(row[:durable_output_sha256]),
                  row[:state], iso(row[:terminal_at]), row[:terminal_reason]]
        exec(<<~SQL, params)
          INSERT INTO entitlement_commit_intents
            (id, state_version, created_at, updated_at, correlation_id, organization_id, reservation_id,
             durable_output_type, durable_output_id, durable_output_sha256, state, terminal_at, terminal_reason)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7::uuid,$8,$9,
                  $10::timestamptz,$11)
        SQL
      end

      private

      def exec(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
