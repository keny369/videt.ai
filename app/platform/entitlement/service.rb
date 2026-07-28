# frozen_string_literal: true

require "time"
require "securerandom"

module Platform
  module Entitlement
    # The F-05 reserve/commit/release/heartbeat surface (entitlement-interim-v1; owner D2 / ADR-069),
    # invoked in-transaction by the consuming operation (crawl.start is the first consumer, S-07-003).
    # It writes the durable entitlement state and returns the data the consumer emits its events from.
    #
    # Contract: WORKFLOW_SPECIFICATIONS.md § Interim Entitlement Contract :513-554. The high-cost
    # allow/warn/block decision is `Platform::Entitlement::InterimPolicy.classify`; concurrent decisions
    # serialize on the counter window (:549); a reservation lives reserved -> executing ->
    # committed/released, or reserved -> expired at prestart, or executing -> released at lease expiry.
    class Service
      # Immutable result of a decision: whether the action is allowed, the reason/recovery, and the
      # durable Decision/reservation/window ids + post-decision counters the consumer records/emits.
      Decision = Data.define(:decision, :reason_code, :recovery_action, :decision_id, :reservation_id,
                             :counter_window_id, :soft_limit, :hard_limit, :committed_after,
                             :active_reserved_after, :lease_due) do
        def allowed? = %w[allow allow_with_warning].include?(decision)
        def blocked? = decision == "block"
        def warning? = decision == "allow_with_warning"
      end

      def initialize(pg_connection)
        @store = Store.new(pg_connection)
      end

      # Reserve at the protected execution checkpoint (WORKFLOW :550): resolve the active policy, pin
      # the UTC-day counter window, and — serialized on that window — classify the request and, when
      # allowed, create the immutable Decision + a reserved reservation accruing its units.
      # `subject` is {account_id:} XOR {service_identity_id:}. `ids` supplies :decision, :reservation.
      # `idempotency_key_digest` is required and recorded on the Decision (WORKFLOW :543 "always
      # nonnull"). reserve does NOT itself dedup replays: command-level idempotency is the consuming
      # operation's layer (its idempotency_records), so an exact replay is resolved by the consumer
      # before it re-enters reserve; `retry_of_decision_id` is recorded for lineage only.
      def reserve(operation:, organization_id:, subject:, requested_units:, correlation_id:, now:, ids:,
                  idempotency_key_digest:, retry_of_decision_id: nil)
        rule = InterimPolicy.rule(operation)
        # Reason precedence (WORKFLOW :541): entitlement_inactive outranks operation_unknown.
        policy = @store.active_entitlement_policy(organization_id)
        if policy.nil?
          return short_circuit(operation:, organization_id:, subject:, requested_units:, correlation_id:, now:,
                               ids:, idempotency_key_digest:, retry_of_decision_id:,
                               usage_unit: rule ? rule[:usage_unit] : "unknown",
                               reason: "entitlement_inactive", recovery: "restore_policy")
        end
        if rule.nil?
          return short_circuit(operation:, organization_id:, subject:, requested_units:, correlation_id:, now:,
                               ids:, idempotency_key_digest:, retry_of_decision_id:, usage_unit: "unknown",
                               reason: "operation_unknown", recovery: "contact_support")
        end

        window_start, window_end = InterimPolicy.counter_window(now)
        @store.lock_window(organization_id, rule[:counter_group], window_start)
        win = @store.window(organization_id, rule[:counter_group], window_start, window_end) ||
              create_window(organization_id, rule, window_start, window_end, policy, correlation_id, now, ids)

        committed = win["committed_units"].to_i
        reserved = win["reserved_units"].to_i
        decision, reason, recovery = InterimPolicy.classify(
          committed:, active_reserved: reserved, requested: requested_units, soft: rule[:soft], hard: rule[:hard])
        allowed = decision != :block
        reservation_id = allowed ? ids[:reservation] : nil
        lease_due = now + InterimPolicy::PRESTART_LIFETIME_SECONDS

        @store.insert_decision(
          id: ids[:decision], now:, correlation_id:, organization_id:, **subject_columns(subject),
          operation:, usage_unit: rule[:usage_unit], requested_units:, counter_window_id: win["id"],
          window_start:, window_end:, policy_version: policy["semantic_version"], plan_version: policy["plan_version"],
          soft_limit: rule[:soft], hard_limit: rule[:hard], committed_before: committed, committed_after: committed,
          active_reserved_before: reserved, active_reserved_after: allowed ? reserved + requested_units : reserved,
          reservation_id:, idempotency_key_digest:, retry_of_decision_id:,
          decision: decision.to_s, reason_code: reason, recovery_action: recovery)

        if allowed
          @store.insert_reservation(id: reservation_id, now:, correlation_id:, organization_id:,
                                    decision_id: ids[:decision], counter_window_id: win["id"],
                                    units: requested_units, lease_due:)
          @store.adjust_window(win["id"], reserved_delta: requested_units, committed_delta: 0, now:)
        end

        Decision.new(decision: decision.to_s, reason_code: reason, recovery_action: recovery,
                     decision_id: ids[:decision], reservation_id:, counter_window_id: win["id"],
                     soft_limit: rule[:soft], hard_limit: rule[:hard], committed_after: committed,
                     active_reserved_after: allowed ? reserved + requested_units : reserved,
                     lease_due: allowed ? lease_due : nil)
      end

      # reserved -> executing at the first side effect. At/after prestart expiry, start loses to expiry.
      def start_execution(organization_id:, reservation_id:, now:)
        r = locked(organization_id, reservation_id)
        return :not_reserved unless r && r["state"] == "reserved"
        return :expired if now >= effective_deadline(r) # prestart lease for a reserved reservation
        moved = @store.transition_reservation(reservation_id, from_state: "reserved", to_state: "executing",
                                              expected_version: r["state_version"].to_i, now:, started_at: now,
                                              last_heartbeat_at: now, lease_due: now + InterimPolicy::LEASE_RENEWAL_SECONDS)
        raise Platform::InvariantViolation, "reservation transition lost" unless moved == 1
        :executing
      end

      # Renew the executing lease (WORKFLOW :551; schema :421 parent-row-lock procedure). Inserts the
      # immutable heartbeat and advances the parent lease to the strictly-later renewed expiry.
      # `ids` supplies :heartbeat. Returns the renewed lease data (for EntitlementLeaseRenewed) or a symbol.
      def heartbeat(organization_id:, reservation_id:, worker_process_identity:, worker_service_identity_id:,
                    now:, ids:, input_sha256: nil, output_sha256: nil)
        r = locked(organization_id, reservation_id)
        return :not_executing unless r && r["state"] == "executing"
        prior = as_time(r["lease_due"])
        # Lease-expiry wins at 15 min since the last heartbeat OR the maximum-execution instant (:551).
        return :lease_expired if now >= effective_deadline(r)
        renewed = now + InterimPolicy::LEASE_RENEWAL_SECONDS
        generation = r["lease_generation"].to_i + 1
        @store.insert_lease_heartbeat(id: ids[:heartbeat], now:, correlation_id: r["correlation_id"],
                                      organization_id:, reservation_id:, heartbeat_generation: generation,
                                      prior_lease_expires_at: prior, renewed_lease_expires_at: renewed,
                                      worker_process_identity:, worker_service_identity_id:, input_sha256:, output_sha256:)
        moved = @store.transition_reservation(reservation_id, from_state: "executing", to_state: "executing",
                                              expected_version: r["state_version"].to_i, now:, last_heartbeat_at: now,
                                              lease_due: renewed, lease_generation: generation)
        raise Platform::InvariantViolation, "reservation transition lost" unless moved == 1
        { heartbeat_generation: generation, renewed_lease_expires_at: renewed, prior_lease_expires_at: prior }
      end

      # executing -> committed at the durable commit point: move the units from reserved to committed
      # and bind the reservation to its durable output. `durable_output` is {type:, id:, sha256:}. A
      # commit reached at or after the lease-expiry/max-execution instant RELEASES instead (WORKFLOW :551).
      def commit(organization_id:, reservation_id:, durable_output:, now:, ids:, reason: "durable_commit_point_reached")
        r = locked(organization_id, reservation_id)
        return :not_executing unless r && r["state"] == "executing"
        return release_reservation(r, reservation_id, "lease_expired_at_commit", now) if now >= effective_deadline(r)
        moved = @store.transition_reservation(reservation_id, from_state: "executing", to_state: "committed",
                                              expected_version: r["state_version"].to_i, now:, terminal_at: now,
                                              terminal_reason: reason)
        raise Platform::InvariantViolation, "reservation transition lost" unless moved == 1
        @store.adjust_window(r["counter_window_id"], reserved_delta: -r["units"].to_i,
                             committed_delta: r["units"].to_i, now:)
        @store.insert_commit_intent(id: ids[:commit_intent], now:, correlation_id: r["correlation_id"],
                                    organization_id:, reservation_id:, durable_output_type: durable_output[:type],
                                    durable_output_id: durable_output[:id], durable_output_sha256: durable_output[:sha256],
                                    state: "committed", terminal_at: now, terminal_reason: reason)
        :committed
      end

      # reserved|executing -> released: release the held units without committing (cancellation,
      # terminal failure before the commit point, or lease expiry with no committed durable point).
      def release(organization_id:, reservation_id:, reason:, now:)
        r = locked(organization_id, reservation_id)
        return :already_terminal unless r && %w[reserved executing].include?(r["state"])
        release_reservation(r, reservation_id, reason, now)
      end

      # The lease-expiry / prestart-expiry reclaim (WORKFLOW :551). A reserved reservation past its
      # prestart lease expires; an executing reservation past its lease (or max-execution instant)
      # releases (commit already won if it committed strictly before). Returns the terminal state or nil.
      def expire(organization_id:, reservation_id:, now:)
        r = locked(organization_id, reservation_id)
        return nil unless r && %w[reserved executing].include?(r["state"])
        return nil if now < effective_deadline(r)
        return release_reservation(r, reservation_id, "lease_expired", now) if r["state"] == "executing"
        moved = @store.transition_reservation(reservation_id, from_state: "reserved", to_state: "expired",
                                              expected_version: r["state_version"].to_i, now:, terminal_at: now,
                                              terminal_reason: "prestart_expired")
        raise Platform::InvariantViolation, "reservation transition lost" unless moved == 1
        @store.adjust_window(r["counter_window_id"], reserved_delta: -r["units"].to_i, committed_delta: 0, now:)
        :expired
      end

      private

      def locked(organization_id, reservation_id)
        @store.lock_reservation(organization_id, reservation_id)
        @store.reservation(organization_id, reservation_id)
      end

      # timestamptz values come back as Time (raw-connection type map) or String (plain reads).
      def as_time(value) = value.is_a?(Time) ? value : Time.parse(value)

      # The instant the lease-expiry handler wins (WORKFLOW :551): the renewable heartbeat lease, capped
      # for an executing reservation by the operation's maximum-execution instant (started_at + max_exec).
      # A reserved reservation has only its prestart lease.
      def effective_deadline(r)
        lease = as_time(r["lease_due"])
        return lease if r["started_at"].nil?
        max_exec = InterimPolicy.rule(r["operation"])[:max_execution_seconds]
        [lease, as_time(r["started_at"]) + max_exec].min
      end

      # reserved|executing -> released, decrementing the held units. Shared by release() and a
      # past-deadline commit(); the CAS is verified so a lost transition never double-adjusts the counter.
      def release_reservation(r, reservation_id, reason, now)
        moved = @store.transition_reservation(reservation_id, from_state: r["state"], to_state: "released",
                                              expected_version: r["state_version"].to_i, now:, terminal_at: now,
                                              terminal_reason: reason)
        raise Platform::InvariantViolation, "reservation transition lost" unless moved == 1
        @store.adjust_window(r["counter_window_id"], reserved_delta: -r["units"].to_i, committed_delta: 0, now:)
        :released
      end

      def create_window(organization_id, rule, window_start, window_end, policy, correlation_id, now, ids)
        @store.insert_window(id: ids[:window] || SecureRandom.uuid_v7, now:, correlation_id:, organization_id:,
                             counter_group: rule[:counter_group], window_start:, window_end:,
                             soft_limit: rule[:soft], hard_limit: rule[:hard], policy_version: policy["semantic_version"])
        @store.window(organization_id, rule[:counter_group], window_start, window_end)
      end

      def subject_columns(subject)
        { account_id: subject[:account_id], service_identity_id: subject[:service_identity_id] }
      end

      # A Block Decision with no counter window and no reservation (operation_unknown / entitlement_inactive).
      def short_circuit(operation:, organization_id:, subject:, requested_units:, correlation_id:, now:, ids:,
                        idempotency_key_digest:, retry_of_decision_id:, usage_unit:, reason:, recovery:)
        @store.insert_decision(
          id: ids[:decision], now:, correlation_id:, organization_id:, **subject_columns(subject),
          operation:, usage_unit:, requested_units:, counter_window_id: nil, window_start: nil, window_end: nil,
          policy_version: InterimPolicy::VERSION, plan_version: InterimPolicy::PLAN_VERSION, soft_limit: nil,
          hard_limit: nil, committed_before: nil, committed_after: nil, active_reserved_before: nil,
          active_reserved_after: nil, reservation_id: nil, idempotency_key_digest:, retry_of_decision_id:,
          decision: "block", reason_code: reason, recovery_action: recovery)
        Decision.new(decision: "block", reason_code: reason, recovery_action: recovery, decision_id: ids[:decision],
                     reservation_id: nil, counter_window_id: nil, soft_limit: nil, hard_limit: nil,
                     committed_after: nil, active_reserved_after: nil, lease_due: nil)
      end
    end
  end
end
