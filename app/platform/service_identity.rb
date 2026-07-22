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
    # service of BACKGROUND_PROCESSING.md § Process And Queue Catalogue).
    SCHEDULED_ACTION_EXECUTOR = "0192f100-0000-7000-8000-00005c8ed010"
    SCHEDULED_ACTION_EXECUTOR_SUBJECT = "f1.scheduled_action_executor"

    # Reserved identity of the approved identity/bootstrap service. WF-001 names
    # it as the command service identity for grant issuance, invitation response
    # and existing-account sign-in (WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1;
    # § existing-account sign-in "the approved identity service as the command
    # service identity"), so it is one registered principal, not a value each
    # caller invents.
    IDENTITY_SERVICE = "0192f100-0000-7000-8000-00001de77001"
    IDENTITY_SERVICE_SUBJECT = "f1.identity_service"

    # Reserved rows, seeded by `f1:db:ensure_service_identities` after every
    # schema materialization. Shape: [id, subject, display name, key id, scope].
    RESERVED = [
      [SCHEDULED_ACTION_EXECUTOR, SCHEDULED_ACTION_EXECUTOR_SUBJECT,
       "F1 ScheduledAction executor", "f1-scheduled-action-executor-v1",
       '{"scheduled_action":["execute"]}'],
      [IDENTITY_SERVICE, IDENTITY_SERVICE_SUBJECT,
       "F1 approved identity and bootstrap service", "f1-identity-service-v1",
       '{"identity":["issue_grant","respond_to_invitation","sign_in"]}']
    ].freeze

    def scheduled_action_executor = SCHEDULED_ACTION_EXECUTOR
    def identity_service = IDENTITY_SERVICE

    # The execution-boundary status check. Existence is guaranteed by the ledger
    # foreign keys; this answers the separate question of whether the identity is
    # still permitted to act, and is deliberately NOT applied to historical rows.
    def active?(service_identity_id, pg_connection)
      result = pg_connection.exec_params(
        "SELECT f1_service_identity_active($1::uuid)", [service_identity_id]
      ).values.dig(0, 0)
      result == "t" || result == true
    end
  end
end
