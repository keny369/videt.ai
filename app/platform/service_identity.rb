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

    # Reserved identity of the OWNER-APPROVAL RELEASE SERVICE, the one principal the ratified
    # Permission Baseline names for `measurement_set.activate`
    # (WORKFLOW_SPECIFICATIONS.md § Permission Baseline :168 "deny | deny | deny | deny | deny |
    # deny | owner-approval release service only"; IMPLEMENTATION_MATRIX.md :1579 and
    # contracts/S-08.json "`measurement_set.activate` for the owner-approval release service").
    #
    # IT IS A SEPARATE ROW BECAUSE IT IS A SEPARATE AUTHORITY. Reusing the ScheduledAction
    # executor would let anything the scheduler runs activate a release artifact, and reusing the
    # identity service would put activation behind the principal that issues sign-in grants. The
    # baseline's whole statement about this permission is WHO holds it, so the holder is one
    # registered row whose `permission_scope` names that permission and nothing else — a
    # suspension of this identity stops activation without touching any other service path.
    #
    # Its scope carries `measurement_set.activate` ALONE. :4485 pairs it with
    # `integration.policy.activate`, and that limb is deliberately absent: no Integration
    # policy artifact exists in this build, so granting the scope now would name authority over
    # a mechanism that cannot be exercised or observed.
    RELEASE_SERVICE = "0192f100-0000-7000-8000-00002e1ea5e0"
    RELEASE_SERVICE_SUBJECT = "f1.release_service"

    # Reserved rows, seeded by `f1:db:ensure_service_identities` after every
    # schema materialization. Shape: [id, subject, display name, key id, scope].
    RESERVED = [
      [SCHEDULED_ACTION_EXECUTOR, SCHEDULED_ACTION_EXECUTOR_SUBJECT,
       "F1 ScheduledAction executor", "f1-scheduled-action-executor-v1",
       '{"scheduled_action":["execute"]}'],
      [IDENTITY_SERVICE, IDENTITY_SERVICE_SUBJECT,
       "F1 approved identity and bootstrap service", "f1-identity-service-v1",
       '{"identity":["issue_grant","respond_to_invitation","sign_in"]}'],
      [RELEASE_SERVICE, RELEASE_SERVICE_SUBJECT,
       "F1 owner-approval release service", "f1-release-service-v1",
       '{"measurement_set":["activate"]}']
    ].freeze

    def scheduled_action_executor = SCHEDULED_ACTION_EXECUTOR
    def identity_service = IDENTITY_SERVICE
    def release_service = RELEASE_SERVICE

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
