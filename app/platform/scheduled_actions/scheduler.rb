# frozen_string_literal: true

require "securerandom"

module Platform
  module ScheduledActions
    # The due-action poll and the expired-lease recovery sweep
    # (BACKGROUND_PROCESSING.md § Due-time claim :108-117; § Sweepers "due-action
    # poll ... claim at most 100 due actions"; § Work Claims And Leases :292).
    #
    # Both are single restricted statements over `FOR UPDATE SKIP LOCKED`, so any
    # number of concurrent schedulers take disjoint batches and no action is ever
    # claimed twice at the same generation. That is the whole correctness control:
    # the singleton scheduler lease of :67 exists to stop duplicate *enqueue* to
    # Redis, and this slice has no Redis hop to duplicate.
    #
    # Both run on the platform-worker transport connection, never the
    # request-serving one, and neither accepts a caller-supplied instant:
    # due-ness and lease expiry are decided by PostgreSQL transaction time alone
    # (BACKGROUND_PROCESSING.md :114, verification gate 7 :519).
    #
    # `claim_owner` is a random process-instance UUID per WORK-CLAIM (:281).
    class Scheduler
      # The ratified poll bound (:114 "at most 100 eligible rows") and the claim
      # lease this scheduler REQUESTS (:115 "a 30-second claim lease").
      #
      # CORRECTED BY ADR-095: the request is a FLOOR, not the lease. :288 derives
      # the actual duration in the transport function from the row's immutable
      # `product_attempt_deadline`, under a 60-second floor and an absolute
      # 15-minute cap, so this constant can only raise a lease and never lower or
      # extend one past the cap. Today it is dominated by the floor and therefore
      # inert; it is kept so the contract does not silently narrow.
      BATCH_LIMIT = 100
      CLAIM_LEASE_SECONDS = 30

      attr_reader :owner

      def initialize(owner: SecureRandom.uuid_v7)
        @owner = owner
      end

      # Claim at most `limit` actions that PostgreSQL says are due.
      def claim_due(limit: BATCH_LIMIT, lease_seconds: CLAIM_LEASE_SECONDS)
        TransportConnection.with do |pg|
          Store.new(pg).claim_due(owner:, limit: [limit, BATCH_LIMIT].min, lease_seconds:)
        end
      end

      # Return expired claims to `pending` so the same action identity is
      # recomputed (:297). This is what makes worker loss non-stranding: a process
      # that dies between claim and completion loses only its lease.
      def recover_expired_leases(limit: BATCH_LIMIT)
        TransportConnection.with do |pg|
          Store.new(pg).release_expired_leases(limit: [limit, BATCH_LIMIT].min)
        end
      end

      # Record a failed Redis enqueue for a claim this scheduler owner still holds
      # (:313); the Store applies the 1/5/30/120/600s schedule or the sixth-failure
      # `redis_dispatch_exhausted` quarantine. Returns 'rescheduled'|'quarantined'|'noop'.
      def fail_dispatch(action_id:, generation:)
        TransportConnection.with do |pg|
          Store.new(pg).fail_dispatch(action_id:, owner:, generation:)
        end
      end

      # Quarantine a claim this scheduler owner still holds before it is enqueued — used when an
      # action maps to no enqueueable work type (a nil catalogue work_type), so it is never
      # emitted as an unparseable envelope that would churn forever (:245).
      def quarantine(action_id:, generation:, reason:)
        TransportConnection.with do |pg|
          Store.new(pg).settle(action_id:, owner:, generation:, status: "quarantined", reason:)
        end
      end
    end
  end
end
