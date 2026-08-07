# frozen_string_literal: true

module Platform
  module ScheduledActions
    # The exhaustive accepted-baseline action-kind catalogue and its fixed
    # queue/work-type mapping (BACKGROUND_PROCESSING.md § Action-kind catalogue
    # :125-181 and § Action-to-work dispatch registry :183-241).
    #
    # This module is a transcription of ratified literals, not a policy: every
    # kind maps to exactly one queue and one work type, `credential_rotation_retry`
    # is deliberately absent (:423), and adding a kind is an
    # implementation-architecture change (:247). An architecture spec re-extracts
    # both tables from the document and fails on any missing, extra or differently
    # mapped value, and on any drift against the database CHECK vocabulary.
    #
    # Being in the catalogue is NOT permission to execute: execution requires a
    # handler registered in Registry for the exact kind and schema version, and an
    # unregistered kind fails closed as `scheduled_work_mapping_mismatch` (:421).
    module Catalogue
      module_function

      # action_kind => [queue, enqueued work_type]
      KINDS = {
        "bootstrap_grant_expire" => %w[control scheduled_action_dispatch],
        "session_expire" => %w[control scheduled_action_dispatch],
        "invitation_expire" => %w[control scheduled_action_dispatch],
        "role_assignment_expire" => %w[control scheduled_action_dispatch],
        "source_scope_request_expire" => %w[control scheduled_action_dispatch],
        "verification_observation_slot" => %w[control verification_observe],
        "verification_request_expire" => %w[control scheduled_action_dispatch],
        "verification_material_destroy" => %w[lifecycle object_destroy],
        "crawl_dispatch" => %w[crawl crawl_orchestrate],
        "crawl_fetch_due" => %w[crawl crawl_fetch],
        "crawl_terminal_deadline" => %w[crawl crawl_orchestrate],
        "ingestion_attempt_due" => %w[pipeline ingest],
        "parsing_attempt_due" => %w[pipeline parse],
        "indexing_attempt_due" => %w[projection index],
        "check_attempt_due" => %w[pipeline check_execute],
        "evaluation_stage_advance" => ["pipeline", nil],
        "evaluation_deadline" => %w[pipeline evaluation_advance],
        "score_recalculation_due" => %w[pipeline score_publish],
        "adjudication_due" => %w[control scheduled_action_dispatch],
        "ai_generation_deadline" => %w[pipeline recommendation_generate],
        "ai_validation_deadline" => %w[pipeline recommendation_generate],
        "ai_publication_expire" => %w[control scheduled_action_dispatch],
        "reassessment_slot" => %w[control scheduled_action_dispatch],
        "notification_delivery_attempt_due" => %w[delivery delivery_execute],
        "notification_reconciliation_due" => %w[delivery delivery_reconcile],
        "notification_escalation_due" => %w[delivery scheduled_action_dispatch],
        "credential_initialization_retry" => %w[delivery delivery_execute],
        "credential_expire" => %w[control scheduled_action_dispatch],
        "entitlement_lease_expire" => %w[control entitlement_reconcile],
        "export_generate" => %w[pipeline export_generate],
        "export_expire" => %w[control scheduled_action_dispatch],
        "export_policy_reevaluate" => %w[control scheduled_action_dispatch],
        "closure_request_expire" => %w[control scheduled_action_dispatch],
        "organization_closure_execute" => %w[lifecycle scheduled_action_dispatch],
        "support_session_expire" => %w[control scheduled_action_dispatch],
        "incident_restoration_observe" => %w[control incident_observe],
        "investigation_input_collect" => %w[control investigation_collect],
        "provider_event_consume" => %w[delivery provider_event_consume],
        "projection_repair_due" => %w[projection projection_build],
        "transport_lease_sweep_due" => %w[maintenance invariant_sweep],
        "running_work_sweep_due" => %w[maintenance invariant_sweep],
        "entitlement_invariant_sweep_due" => %w[maintenance invariant_sweep],
        "staged_object_invariant_sweep_due" => %w[maintenance invariant_sweep],
        "export_invariant_sweep_due" => %w[maintenance invariant_sweep],
        "mailgun_uncertainty_sweep_due" => %w[maintenance invariant_sweep],
        "deletion_tombstone_invariant_sweep_due" => %w[maintenance invariant_sweep],
        "evidence_retention_warning" => %w[lifecycle scheduled_action_dispatch],
        "lifecycle_deletion_start" => %w[lifecycle lifecycle_delete],
        "lifecycle_deletion_attempt_due" => %w[lifecycle lifecycle_delete],
        "lifecycle_deletion_deadline" => %w[lifecycle lifecycle_delete],
        "backup_tombstone_verify" => %w[lifecycle lifecycle_delete],
        "restore_drill_due" => %w[lifecycle invariant_sweep],
        "partition_maintenance_due" => %w[maintenance partition_maintain]
      }.freeze

      # The generic `scheduled_action_dispatch` action-kind => Application
      # operation mapping (:399-419). An action mapped to a specialized work type
      # cannot enter this table, and a generic action absent from it is
      # `scheduled_work_mapping_mismatch`; it is never dispatched by method-name
      # reflection.
      GENERIC_OPERATIONS = {
        "bootstrap_grant_expire" => "ExpireBootstrapGrant",
        "session_expire" => "ExpireSession",
        "invitation_expire" => "ExpireInvitation",
        "role_assignment_expire" => "ExpireRoleAssignment",
        "source_scope_request_expire" => "ExpireSourceScopeChange",
        "verification_request_expire" => "ExpireVerificationRequest",
        "adjudication_due" => "MarkAdjudicationOverdue",
        "ai_publication_expire" => "ExpireAiResponse",
        "reassessment_slot" => "EvaluateReassessmentSlot",
        "notification_escalation_due" => "EscalateNotification",
        "credential_expire" => "ExpireCredential",
        "export_expire" => "ExpireExport",
        "export_policy_reevaluate" => "ReevaluateExportPolicy",
        "closure_request_expire" => "ExpireOrganizationClosure",
        "organization_closure_execute" => "ExecuteOrganizationClosure",
        "support_session_expire" => "ExpireSupportSession",
        "evidence_retention_warning" => "RecordEvidenceRetentionWarning"
      }.freeze

      # The Evaluation stage registry (:439-444). `evaluation_stage_advance` is the one
      # kind whose KINDS cell is blank, because ":245 it selects its work type only from
      # the exact stage registry below"; this is that registry, transcribed.
      #
      # Every row maps to the same work type, so the selection is determinate WITHOUT
      # knowing which stage an action is at — which is why `stage_work_type_for` needs no
      # stage argument and no per-action payload. `STAGE_WORK_TYPE` proves that premise
      # rather than assuming it: if a later stage is registered with a different work
      # type the constant raises at load, and the resolution must then be given the stage.
      EVALUATION_STAGES = {
        "seal_input_snapshot" => "evaluation_advance",
        "materialize_applicability" => "evaluation_advance",
        "materialize_check_result_keys" => "evaluation_advance",
        "seal_issue_set" => "evaluation_advance",
        "resolve_adjudication_gate" => "evaluation_advance"
      }.freeze

      STAGE_WORK_TYPE = EVALUATION_STAGES.values.uniq.then do |types|
        if types.length != 1
          raise "the Evaluation stage registry maps to #{types.length} work types; " \
                "stage_work_type_for must be given the stage"
        end
        types.first
      end

      STAGE_SELECTED_KINDS = ["evaluation_stage_advance"].freeze

      def kinds = KINDS.keys
      def kind?(action_kind) = KINDS.key?(action_kind)
      def queue_for(action_kind) = KINDS.fetch(action_kind).first
      def work_type_for(action_kind) = KINDS.fetch(action_kind).last

      # The stage registry's answer for a stage-selected kind, and nil for every other —
      # so a kind with a genuinely absent work type still fails closed at the dispatcher
      # rather than borrowing this one.
      def stage_work_type_for(action_kind)
        STAGE_WORK_TYPE if STAGE_SELECTED_KINDS.include?(action_kind)
      end
    end
  end
end
