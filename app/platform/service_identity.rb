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
  # This is a pointer to a persisted row, not an identifier in its own right.
  # POSTGRESQL_SCHEMA.md:43 classes `service_identity_id` as an F1 row identity
  # requiring a "named FK/existence check", and :202 defines `service_identities`
  # with a `status CHECK ('active','suspended','revoked')`. The reserved executor
  # below is seeded by migration, referenced by a foreign key from
  # `scheduled_actions`, and re-checked for `active` status every time work is
  # claimed — so an unknown UUID cannot be scheduled and a suspended or revoked
  # executor stops executing.
  #
  # The UUID is a fixed constant rather than a per-process value because an action
  # scheduled by one release must still name the same executing identity when a
  # later release runs it. There is deliberately no environment override: a
  # deployment that needs a different executor registers the row and changes this
  # constant under review, because an override could only ever name a row that
  # the foreign key already requires to exist.
  module ServiceIdentity
    module_function

    # Reserved identity of the ScheduledAction executor (the `scheduler`/worker
    # service of BACKGROUND_PROCESSING.md § Process And Queue Catalogue), seeded
    # by db/migrate/20260722120010_create_service_identities.rb.
    SCHEDULED_ACTION_EXECUTOR = "0192f100-0000-7000-8000-00005c8ed010"
    SCHEDULED_ACTION_EXECUTOR_SUBJECT = "f1.scheduled_action_executor"

    def scheduled_action_executor = SCHEDULED_ACTION_EXECUTOR
  end
end
