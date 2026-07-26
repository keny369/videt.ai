# frozen_string_literal: true

module Workflows
  module Wf003
    # The fixed automated observation slot schedule (SCORE_EVIDENCE_MODEL.md :151;
    # contracts/S-05.json MTX-028 background_job/retry_policy). Ten slots at due offsets
    # 0, 5, 15, 30, 60, 120, 240, 480, 960 and 1,380 minutes after issuance. Each slot's
    # half-open window runs from its due offset up to the next offset; the final window
    # ends at expiry (1,440 minutes — the 24-hour challenge lifetime), so the ten windows
    # tile the whole lifetime with no gap and no overlap.
    #
    # A slot may START only inside its window: at or after its due offset and STRICTLY
    # before the window end. At an exact boundary the earlier slot's window is closed and
    # the later slot's is open (half-open, upper bound exclusive), so the earlier slot is
    # skipped and the later slot is eligible. A slot that has not started when its window
    # closes is recorded once as `observation_slot_skipped` and never runs late.
    #
    # This is a pure value module: it maps offsets to windows and validates a due offset.
    # It holds no clock and no persistence; the handler supplies `now` and the Request's
    # issuance instant.
    module AutomatedObservationSlots
      module_function

      # The ten due offsets in minutes, ascending.
      OFFSETS_MINUTES = [0, 5, 15, 30, 60, 120, 240, 480, 960, 1380].freeze
      # The challenge lifetime; the exclusive upper bound of the final slot's window.
      EXPIRY_OFFSET_MINUTES = 1440

      def offsets_minutes = OFFSETS_MINUTES

      # Is `offset_minutes` one of the ten ratified due offsets?
      def slot?(offset_minutes) = OFFSETS_MINUTES.include?(offset_minutes)

      # The exclusive upper bound (minutes after issuance) of the window belonging to the
      # slot due at `offset_minutes`: the next offset, or expiry for the last slot.
      # Raises for a value that is not a due offset.
      def window_end_minutes(offset_minutes)
        i = OFFSETS_MINUTES.index(offset_minutes)
        raise ArgumentError, "not an automated slot offset: #{offset_minutes.inspect}" if i.nil?

        OFFSETS_MINUTES[i + 1] || EXPIRY_OFFSET_MINUTES
      end
    end
  end
end
