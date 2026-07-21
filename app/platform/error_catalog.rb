# frozen_string_literal: true

module Platform
  # The fixed Volume I logical error-code mapping (WORKFLOW_SPECIFICATIONS.md §
  # Logical Result And Error Contract) plus the reason-code -> error-code binding
  # for the reasons this slice can return. A handler names a reason_code; the
  # catalog supplies the exact class, code, severity, default retryability and
  # recovery action. An implementation MUST NOT expose an invented reason code.
  module ErrorCatalog
    module_function

    # error_code => [error_class, severity, retryable_default, recovery_action]
    CODES = {
      "F1-VALIDATION-400" => ["validation", "warning", false, "correct_request_and_submit_new_command"],
      "F1-DOMAIN-409"     => ["domain", "warning", false, "reread_current_state_and_submit_new_command"],
      "F1-AUTHN-401"      => ["authentication", "warning", false, "reauthenticate_and_submit_new_command"],
      "F1-AUTH-403"       => ["authorization", "warning", false, "obtain_required_authority_or_use_authorized_actor"],
      "F1-DEPENDENCY-503" => ["dependency", "error", true, "restore_dependency_or_wait_for_declared_retry"],
      "F1-TIMEOUT-504"    => ["timeout", "error", true, "wait_for_declared_retry_or_submit_linked_recovery"]
    }.freeze

    # onboarding-interim-v1 reason_code => error_code. This is the exhaustive set
    # RequestBootstrapGrant can return; every mapping is stated by the onboarding
    # contract's reason/HTTP paragraph.
    REASONS = {
      # invalid/expired identity proof -> F1-AUTHN-401
      "identity_receipt_invalid"          => "F1-AUTHN-401",
      "identity_issuer_unsupported"       => "F1-AUTHN-401",
      "identity_schema_unsupported"       => "F1-AUTHN-401",
      "identity_receipt_purpose_mismatch" => "F1-AUTHN-401",
      "identity_email_unverified"         => "F1-AUTHN-401",
      "identity_receipt_changed"          => "F1-AUTHN-401",
      "identity_receipt_consumed"         => "F1-AUTHN-401",
      "identity_receipt_expired"          => "F1-AUTHN-401",
      # missing authority -> F1-AUTH-403
      "bootstrap_authority_required"      => "F1-AUTH-403",
      # request shape -> F1-VALIDATION-400
      "command_schema_unsupported"        => "F1-VALIDATION-400",
      # state / uniqueness / replay conflict -> F1-DOMAIN-409
      "bootstrap_grant_already_issued"    => "F1-DOMAIN-409",
      "bootstrap_already_completed"       => "F1-DOMAIN-409",
      "bootstrap_grant_consumed"          => "F1-DOMAIN-409",
      "idempotency_conflict"              => "F1-DOMAIN-409",
      # transient exhaustion -> F1-DEPENDENCY-503
      "onboarding_transaction_unavailable" => "F1-DEPENDENCY-503",
      # existing-account sign-in outward reasons (WORKFLOW_SPECIFICATIONS.md §
      # existing-account sign-in): the seven exhaustive outward failures. Every
      # invalid-receipt reason is normalized to authentication_failed outward; the
      # exact internal reason is retained only in the restricted audit.
      "authentication_failed"             => "F1-AUTHN-401",
      "account_suspended"                 => "F1-AUTH-403",
      "organization_inactive"             => "F1-AUTH-403",
      "identity_assurance_failed"         => "F1-AUTHN-401",
      "policy_unavailable"                => "F1-DOMAIN-409",
      "sign_in_timeout"                   => "F1-TIMEOUT-504",
      # WF-001 invitation-acceptance outward reasons (WORKFLOW_SPECIFICATIONS.md
      # § invitation; class mapping at that paragraph). State/uniqueness/expiry
      # conflicts are F1-DOMAIN-409; cross-tenant Account selection is F1-AUTH-403.
      # Expiry via the opaque reference resolves to the generic invitation_not_active
      # (POSTGRESQL_SCHEMA.md § resolver: "expiry equality ... invitation_not_active
      # representation"), so acceptance never emits a distinct invitation_expired.
      "invitation_not_active"             => "F1-DOMAIN-409",
      "invitation_target_mismatch"        => "F1-DOMAIN-409",
      "invitation_account_ineligible"     => "F1-DOMAIN-409",
      "invitation_role_scope_changed"     => "F1-DOMAIN-409",
      "account_identity_conflict"         => "F1-AUTH-403",
      # Exact-replay reauthorization denial (APPLICATION_LAYER.md § replay:
      # "denial returns F1-AUTH-403 with no retained payload").
      "reauthorization_denied"            => "F1-AUTH-403",
      # DeclineInvitation: expected-state-version mismatch and reason-bounds
      # (WORKFLOW_SPECIFICATIONS.md § invitation decline; :252 state conflicts ->
      # F1-DOMAIN-409; input-shape -> F1-VALIDATION-400).
      "stale_state_version"               => "F1-DOMAIN-409",
      "invitation_reason_invalid"         => "F1-VALIDATION-400"
    }.freeze

    def failure(reason_code, support_reference:)
      error_code = REASONS.fetch(reason_code) do
        raise Platform::InvariantViolation, "unmapped reason_code #{reason_code.inspect}"
      end
      error_class, severity, retryable, recovery = CODES.fetch(error_code)
      # onboarding-interim-v1: none of these is automatically retried at the
      # product level; dependency exhaustion is terminal (retryable=false at
      # exhaustion) even though its class default is true.
      retryable = false if error_code == "F1-DEPENDENCY-503"
      Platform::Failure.new(
        error_class: error_class, error_code: error_code, reason_code: reason_code,
        severity: severity, retryable: retryable, recovery_action: recovery,
        support_reference: support_reference
      )
    end
  end
end
