# frozen_string_literal: true

require "json"
require "time"

module Platform
  module ScheduledActions
    # All `scheduled_actions` persistence, on a caller-supplied PG connection
    # inside the caller's transaction.
    #
    # Two distinct privilege paths, deliberately:
    #
    #   * Creation and reads use the ordinary runtime SELECT/INSERT grant under
    #     row level security, so an action is created inside the proved
    #     Organization context of the command that schedules it and is visible
    #     only to that Organization.
    #   * Every state transition goes through a restricted SECURITY DEFINER
    #     transport function. The runtime holds no UPDATE or DELETE on the table,
    #     so claiming, dispatching, settling, releasing and cancelling are the
    #     only reachable mutations, they are the same functions the scheduler and
    #     worker use, and the `scheduled_actions_guard` trigger validates each one
    #     against the state machine and the immutable identity columns.
    class Store
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Create the action, or return the existing row for an exact creation
      # replay (BACKGROUND_PROCESSING.md :106). Returns
      # { id:, replayed: bool, collision_ordinal: }.
      #
      # A conflicting row whose retained preimage is byte-equal IS this action:
      # return it and write nothing. A conflicting row with a different retained
      # preimage would be a SHA-256 collision; the contract forbids merging them,
      # so the new action takes the next `collision_ordinal` instead.
      def create(id:, action_kind:, action_schema_version:, organization_id:, project_id: nil,
                 target_type:, target_id:, due_at:, now:, correlation_id:, causation_id:,
                 executing_service_identity_id:, product_generation: 0, schedule_generation: 1,
                 not_before_at: nil, command_id: nil, payload_refs: {}, schema_version: "1.0")
        preimage = Identity.preimage(
          action_kind:, action_schema_version:, organization_id:, project_id:,
          target_type:, target_id:, product_generation:, schedule_generation:, due_at:
        )
        digest = Identity.digest(preimage)

        ordinal = 0
        loop do
          inserted = insert_row(
            id:, schema_version:, action_kind:, action_schema_version:, organization_id:, project_id:,
            target_type:, target_id:, due_at:, now:, correlation_id:, causation_id:, command_id:,
            executing_service_identity_id:, product_generation:, schedule_generation:, not_before_at:,
            payload_refs:, preimage:, digest:, ordinal:
          )
          return { id: inserted, replayed: false, collision_ordinal: ordinal } if inserted

          existing = find_by_identity(action_kind:, identity_sha256: digest, collision_ordinal: ordinal)
          raise Platform::InvariantViolation, "scheduled action identity conflict is not visible" if existing.nil?
          return { id: existing["id"], replayed: true, collision_ordinal: ordinal } if existing["preimage_hex"] == hex(preimage)

          ordinal += 1
        end
      end

      def find_by_identity(action_kind:, identity_sha256:, collision_ordinal: 0)
        sql = <<~SQL
          SELECT id, status, due_at, encode(identity_preimage,'hex') AS preimage_hex
          FROM scheduled_actions
          WHERE action_kind = $1 AND identity_sha256 = $2 AND collision_ordinal = $3
        SQL
        exec(sql, [action_kind, bytea(identity_sha256), collision_ordinal]).to_a.first
      end

      # ---- restricted transport functions --------------------------------------

      # Step 3-4 of the ratified due-time claim: at most `limit` due, pending,
      # not-before-satisfied actions in (due_at, id) order under FOR UPDATE SKIP
      # LOCKED. `now` is nil in production, where PostgreSQL transaction time is
      # the due-time authority.
      def claim_due(owner:, limit: 100, lease_seconds: 30, now: nil)
        sql = "SELECT * FROM f1_claim_due_scheduled_actions($1::uuid, $2, $3, $4::timestamptz)"
        exec(sql, [owner, limit, lease_seconds, iso_or_nil(now)]).to_a.map { |row| to_action(row) }
      end

      # The scheduler-to-worker compare-and-swap handoff. Returns the Action, or
      # nil when this caller does not own the exact claim generation — a duplicate
      # delivery, a reclaimed lease or a terminal action, each of which exits
      # without product work.
      def dispatch(action_id:, expected_owner:, expected_generation:, worker_owner:, lease_seconds: 30, now: nil)
        sql = "SELECT * FROM f1_dispatch_scheduled_action($1::uuid,$2::uuid,$3,$4::uuid,$5,$6::timestamptz)"
        row = exec(sql, [action_id, expected_owner, expected_generation, worker_owner,
                         lease_seconds, iso_or_nil(now)]).to_a.first
        row && to_action(row)
      end

      def settle(action_id:, owner:, generation:, status:, reason: nil, now: nil)
        sql = "SELECT f1_settle_scheduled_action($1::uuid,$2::uuid,$3,$4,$5,$6::timestamptz)"
        truthy(exec(sql, [action_id, owner, generation, status, reason, iso_or_nil(now)]).values.dig(0, 0))
      end

      def release_claim(action_id:, owner:, generation:, reason: nil, now: nil)
        sql = "SELECT f1_release_scheduled_action_claim($1::uuid,$2::uuid,$3,$4,$5::timestamptz)"
        truthy(exec(sql, [action_id, owner, generation, reason, iso_or_nil(now)]).values.dig(0, 0))
      end

      def release_expired_leases(limit: 100, now: nil)
        sql = "SELECT f1_release_expired_scheduled_action_leases($1,$2::timestamptz)"
        exec(sql, [limit, iso_or_nil(now)]).values.dig(0, 0).to_i
      end

      def cancel(action_id:, reason: nil, now: nil)
        sql = "SELECT f1_cancel_scheduled_action($1::uuid,$2,$3::timestamptz)"
        truthy(exec(sql, [action_id, reason, iso_or_nil(now)]).values.dig(0, 0))
      end

      private

      def insert_row(id:, schema_version:, action_kind:, action_schema_version:, organization_id:, project_id:,
                     target_type:, target_id:, due_at:, now:, correlation_id:, causation_id:, command_id:,
                     executing_service_identity_id:, product_generation:, schedule_generation:, not_before_at:,
                     payload_refs:, preimage:, digest:, ordinal:)
        params = [
          id, schema_version, iso(now), correlation_id, causation_id, command_id, organization_id, project_id,
          executing_service_identity_id, action_kind, action_schema_version, target_type, target_id,
          product_generation, schedule_generation, iso(due_at), iso_or_nil(not_before_at),
          bytea(preimage), bytea(digest), ordinal, JSON.generate(payload_refs)
        ]
        exec(<<~SQL, params).values.dig(0, 0)
          INSERT INTO scheduled_actions
            (id, schema_version, state_version, lock_version, created_at, updated_at,
             correlation_id, causation_id, command_id, claim_generation,
             organization_id, project_id, executing_service_identity_id,
             action_kind, action_schema_version, target_type, target_id,
             product_generation, schedule_generation, due_at, not_before_at,
             identity_preimage, identity_sha256, collision_ordinal, payload_refs, status)
          VALUES ($1,$2,0,0,$3::timestamptz,$3::timestamptz,
                  $4::uuid,$5::uuid,$6::uuid,0,
                  $7::uuid,$8::uuid,$9::uuid,
                  $10,$11,$12,$13::uuid,
                  $14,$15,$16::timestamptz,$17::timestamptz,
                  $18,$19,$20,$21::jsonb,'pending')
          ON CONFLICT (action_kind, identity_sha256, collision_ordinal) DO NOTHING
          RETURNING id
        SQL
      end

      def to_action(row)
        Action.new(
          id: row["id"], action_kind: row["action_kind"], action_schema_version: row["action_schema_version"],
          organization_id: row["organization_id"], project_id: row["project_id"],
          target_type: row["target_type"], target_id: row["target_id"],
          product_generation: row["product_generation"].to_i, schedule_generation: row["schedule_generation"].to_i,
          due_at: to_time(row["due_at"]), claim_generation: row["claim_generation"].to_i,
          correlation_id: row["correlation_id"], causation_id: row["causation_id"],
          executing_service_identity_id: row["executing_service_identity_id"],
          identity_sha256: row["identity_sha256"] && to_bytes(row["identity_sha256"])
        )
      end

      # A pooled Rails connection decodes timestamps and bytea for us; a bare
      # libpq connection returns text. Accept either.
      def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc
      def to_bytes(value) = value.start_with?("\\x") ? [value.delete_prefix("\\x")].pack("H*") : value

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = { value: bytes, format: 1 }
      def hex(bytes) = bytes.unpack1("H*")
      def truthy(value) = value == "t" || value == true
      def iso(time) = time.getutc.floor(6).iso8601(6)
      def iso_or_nil(time) = time && iso(time)
    end
  end
end
