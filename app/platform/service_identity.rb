# frozen_string_literal: true

module Platform
  # Service identities that execute service-only work.
  #
  # A ScheduledAction is executed by a verified service identity, never by a
  # human Session actor (API_CONTRACTS.md :356 "Timers and internal event
  # reactions ... enter the same registered commands ... with a verified service
  # identity and a persisted ScheduledAction or Domain Event cause";
  # APPLICATION_LAYER.md :371 "service-only ScheduledAction transitions").
  # `command_executions`, `command_results` and `audit_record_registry` each
  # enforce `exactly_one_actor_or_service`, so the executing identity is written
  # to `service_identity_id` and `actor_id` stays null.
  #
  # The canonical `service_identities` table (schemas/POSTGRESQL_SCHEMA.md :202)
  # belongs to a later slice. Until it exists, the executor is this reserved,
  # stable, documented constant rather than a per-process random UUID: a
  # scheduled action created today must still name the same executing identity
  # when a different process runs it tomorrow. It is overridable by deployment so
  # a managed environment can bind the real registered row without a code change.
  module ServiceIdentity
    module_function

    # Reserved identity of the ScheduledAction executor (the `scheduler`/worker
    # service of BACKGROUND_PROCESSING.md § Process And Queue Catalogue).
    SCHEDULED_ACTION_EXECUTOR = "0192f100-0000-7000-8000-00005c8ed010"

    def scheduled_action_executor
      ENV.fetch("F1_SCHEDULED_ACTION_SERVICE_IDENTITY_ID", SCHEDULED_ACTION_EXECUTOR)
    end
  end
end
