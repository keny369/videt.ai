# frozen_string_literal: true

require "digest"

module Platform
  module ScheduledActions
    # The immutable action identity (BACKGROUND_PROCESSING.md :99 "immutable
    # identity preimage and SHA-256", :106 "One unique row exists for the
    # complete action identity. Exact creation replay returns it. A same digest
    # with a different retained preimage does not merge.").
    #
    # The preimage is canonical JSON (RFC 8785) over exactly the fields that make
    # the action unique: what kind of work, under which schema, for which
    # Organization/Project, against which target, at which product and schedule
    # generation, due at which instant. Nothing else — no payload, no secret, no
    # correlation id, no wall-clock creation time — enters it, so re-running the
    # creating command produces byte-identical bytes and therefore an exact replay.
    #
    # The digest is what the executing worker uses as the command idempotency key,
    # which is why re-delivery of the same action can never produce a second
    # product effect however many times the transport delivers it.
    module Identity
      module_function

      # `due_at` is normalized to microsecond UTC ISO-8601, matching the
      # timestamptz(6) column, so a Ruby Time and a value read back from
      # PostgreSQL hash identically.
      def preimage(action_kind:, action_schema_version:, organization_id:, project_id:,
                   target_type:, target_id:, product_generation:, schedule_generation:, due_at:)
        Platform::CanonicalJson.encode(
          "action_kind" => action_kind,
          "action_schema_version" => action_schema_version,
          "due_at" => instant(due_at),
          "organization_id" => organization_id,
          "product_generation" => Integer(product_generation),
          "project_id" => project_id,
          "schedule_generation" => Integer(schedule_generation),
          "target_id" => target_id,
          "target_type" => target_type
        )
      end

      def digest(preimage_bytes) = Digest::SHA256.digest(preimage_bytes)

      def instant(value)
        return value.getutc.floor(6).iso8601(6) if value.respond_to?(:getutc)

        Time.parse(value.to_s).getutc.floor(6).iso8601(6)
      end
    end
  end
end
