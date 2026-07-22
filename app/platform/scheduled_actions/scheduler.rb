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
    # `claim_owner` is a random process-instance UUID per WORK-CLAIM (:281).
    class Scheduler
      # The ratified poll bound and claim lease (:114 "at most 100 eligible rows",
      # :115 "a 30-second claim lease").
      BATCH_LIMIT = 100
      CLAIM_LEASE_SECONDS = 30

      attr_reader :owner

      def initialize(owner: SecureRandom.uuid_v7)
        @owner = owner
      end

      # Claim at most `limit` due actions and return them. `now` is nil in
      # production, where PostgreSQL transaction time decides due-time equality
      # (:110; verification gate 7 :519).
      def claim_due(limit: BATCH_LIMIT, lease_seconds: CLAIM_LEASE_SECONDS, now: nil)
        Platform::UnitOfWork.run do |conn|
          Store.new(conn.raw_connection)
               .claim_due(owner:, limit: [limit, BATCH_LIMIT].min, lease_seconds:, now:)
        end
      end

      # Return expired claims to `pending` so the same action identity is
      # recomputed (:297). This is what makes worker loss non-stranding: a process
      # that dies between claim and completion loses only its lease.
      def recover_expired_leases(limit: BATCH_LIMIT, now: nil)
        Platform::UnitOfWork.run do |conn|
          Store.new(conn.raw_connection).release_expired_leases(limit: [limit, BATCH_LIMIT].min, now:)
        end
      end
    end
  end
end
