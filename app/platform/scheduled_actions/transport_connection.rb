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

      # Yield a live transport connection. One per thread: libpq connections are
      # not thread-safe and the worker runs a bounded number of threads.
      def with
        conn = Thread.current[THREAD_KEY]
        conn = Thread.current[THREAD_KEY] = connect if conn.nil? || conn.finished?
        yield conn
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
