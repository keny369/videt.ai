# frozen_string_literal: true

module Platform
  module ScheduledActions
    # The high-severity alert sink for terminal transport quarantine
    # (BACKGROUND_PROCESSING.md :313 "Attempt six quarantines the transport record with
    # `redis_dispatch_exhausted` and raises a high alert").
    #
    # The default emits ONE structured, REDACTED line — identifiers, reason, attempt count
    # and the error CLASS only, never an exception message, backtrace, payload or customer
    # text. The paging / on-call pipeline is wired at the observability layer; this module is
    # the single emission point the transport guarantees, and it is injectable so a test can
    # assert the alert fired without a real pager.
    module DispatchAlert
      module_function

      def high(reason:, action_id:, work_id:, attempts:, error_class: nil)
        Rails.logger.error(
          "[f1.transport.high_alert] reason=#{reason} action_id=#{action_id} " \
          "work_id=#{work_id} dispatch_attempts=#{attempts} error_class=#{error_class}"
        )
      end
    end
  end
end
