# frozen_string_literal: true

require "pg"

module Platform
  module ScheduledActions
    # The platform-control connection the ScheduledAction transport runs on.
    #
    # The ratified role model separates request-serving authority from scheduler
    # authority: `f1_web` holds "registered browser/API tables and functions only"
    # (schemas/POSTGRESQL_SCHEMA.md:136), while scheduler leadership and dispatch
    # belong to `f1_platform_worker` registered functions (:166, :175 "granted only
    # to `f1_platform_worker`"). Claiming, dispatching, settling, releasing,
    # sweeping and cancelling scheduled work are therefore NOT reachable from the
    # application's ordinary connection, and this module is the only place the
    # transport role is used.
    #
    # Deliberately not an Active Record connection. Each transport function is a
    # single statement and therefore its own transaction, so there is nothing for
    # a unit of work to wrap; keeping it off the Active Record pool also makes it
    # structurally impossible for a request-path transaction to enclose a
    # transport mutation.
    #
    # The product command a claimed action executes is a different thing entirely:
    # it runs on the ordinary runtime connection inside Platform::UnitOfWork,
    # under row level security in its Organization's context.
    module TransportConnection
      module_function

      ROLE = "f1_platform_worker"
      THREAD_KEY = :f1_scheduled_action_transport_connection
      PINNED_KEY = :f1_scheduled_action_transport_pinned

      # Raised when a PINNED transport connection is lost, so the caller (the scheduler holding
      # the singleton lease) fails closed instead of silently reconnecting lease-less.
      class ConnectionLost < StandardError; end

      # Yield a live transport connection. One per thread: libpq connections are not thread-safe
      # and the worker runs a bounded number of threads. In pinned mode a lost connection is NOT
      # silently reconnected — it raises ConnectionLost, so a scheduler that lost its lease-holding
      # connection stops dispatching rather than continuing on a connection that holds no lease.
      def with
        conn = Thread.current[THREAD_KEY]
        if conn.nil? || conn.finished?
          raise ConnectionLost, "pinned transport connection lost" if Thread.current[PINNED_KEY]

          conn = Thread.current[THREAD_KEY] = connect
        end
        yield conn
      end

      # Run the block on a single, dedicated, PINNED transport connection that is never silently
      # reconnected (a lost connection raises ConnectionLost). The scheduler uses this so the lease
      # and every dispatch statement share one session, and losing it fails closed. Restores the
      # prior thread connection state and closes the dedicated connection afterwards.
      def pinned
        previous_conn = Thread.current[THREAD_KEY]
        previous_pinned = Thread.current[PINNED_KEY]
        conn = connect
        Thread.current[THREAD_KEY] = conn
        Thread.current[PINNED_KEY] = true
        begin
          yield conn
        ensure
          Thread.current[PINNED_KEY] = previous_pinned
          Thread.current[THREAD_KEY] = previous_conn
          conn.close unless conn.finished?
        end
      end

      def connect
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        PG.connect(
          host: config[:host], port: config[:port], dbname: config[:database],
          user: ENV.fetch("F1_TRANSPORT_DATABASE_USER", ROLE),
          password: ENV.fetch("F1_TRANSPORT_DATABASE_PASSWORD", config[:password])
        )
      end

      # Release this thread's connection (process shutdown, or a test that has
      # finished with the transport).
      def disconnect!
        conn = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = nil
        conn.close if conn && !conn.finished?
      end
    end
  end
end
