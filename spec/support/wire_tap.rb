# frozen_string_literal: true

# EVERY STATEMENT THIS PROCESS SENDS TO POSTGRESQL, IN ONE PLACE (round 9).
#
# Round 9's audit recorded that a sentinel observing ONE database execution API is a sentinel a
# future producer walks past: `GovernedWriteSentinel` hooked `exec_params` alone, which is complete
# today only because nothing in `app/` happens to use `exec`, `exec_prepared` or the async forms.
# "Complete because nobody has used the other doors yet" is the shape of every finding this tranche
# has produced, so the tap covers all of them and a proof asserts the set is the whole surface
# `PG::Connection` exposes.
#
# Subscribers receive `(sql, error)` for every statement, successful or refused. A refused statement
# is often the interesting one — the closure refusal is precisely what the governed-write rule exists
# to observe — so failures are reported before being re-raised.
module WireTap
  # Everything `PG::Connection` offers for sending a statement. Derived below and asserted against
  # the live class by `spec/architecture/wire_tap_spec.rb`, so a libpq upgrade that adds a door fails
  # the build rather than opening one silently.
  EXECUTION_METHODS = %i[
    exec exec_params exec_prepared
    async_exec async_exec_params async_exec_prepared
    sync_exec sync_exec_params sync_exec_prepared
    query async_query send_query send_query_params send_query_prepared
  ].freeze

  class << self
    def subscribers = (@subscribers ||= [])
    def armed? = @armed ||= false

    def subscribe(&block)
      arm!
      subscribers << block
      block
    end

    def unsubscribe(block) = subscribers.delete(block)

    def arm!
      return if armed?

      PG::Connection.prepend(Instrumentation)
      @armed = true
    end

    # The methods actually intercepted: the intersection of the declared set with what this libpq
    # build defines. Reported so a proof can assert the two agree rather than assuming they do.
    def intercepted = EXECUTION_METHODS.select { |m| PG::Connection.method_defined?(m) }

    def publish(sql, error)
      return if subscribers.empty? || @publishing

      @publishing = true
      begin
        subscribers.each { |s| s.call(sql.to_s, error) }
      ensure
        @publishing = false
      end
    end
  end

  module Instrumentation
    WireTap::EXECUTION_METHODS.each do |method_name|
      define_method(method_name) do |*args, **kwargs, &block|
        result = super(*args, **kwargs, &block)
        WireTap.publish(args.first, nil)
        result
      rescue StandardError => e
        WireTap.publish(args.first, e)
        raise
      end
    end
  end
end
