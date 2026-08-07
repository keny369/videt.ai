# frozen_string_literal: true

module Platform
  module ScheduledActions
    # A claimed scheduled action as the transport hands it to a handler: scalar
    # identifiers only (BACKGROUND_PROCESSING.md :42 — no Active Record objects,
    # domain payloads, provider bodies, secret references, tokens, email
    # addresses, URLs or customer text). Everything else the handler needs it
    # reloads from PostgreSQL under the action's Organization context (:84).
    Action = Data.define(
      :id, :action_kind, :action_schema_version, :organization_id, :project_id,
      :target_type, :target_id, :product_generation, :schedule_generation,
      :due_at, :claim_generation, :correlation_id, :causation_id,
      :executing_service_identity_id, :identity_sha256, :work_id
    ) do
      # The fixed Redis queue and the catalogue work-type for this kind; the
      # Dispatcher stamps `work_type` into the scalar envelope (:77).
      #
      # One kind has no literal cell: `evaluation_stage_advance` "selects its work type
      # only from the exact stage registry" (:245), so its catalogue value is nil and the
      # registry answers instead. Every other kind is unchanged.
      def queue = Platform::ScheduledActions::Catalogue.queue_for(action_kind)

      def work_type
        Platform::ScheduledActions::Catalogue.work_type_for(action_kind) ||
          Platform::ScheduledActions::Catalogue.stage_work_type_for(action_kind)
      end
    end
  end
end
