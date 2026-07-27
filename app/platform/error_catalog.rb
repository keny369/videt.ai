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
      # S-02 self-service genesis (AC-CAP-002). Profile/body shape and the three
      # baseline content-hash mismatches are input-shape -> F1-VALIDATION-400; a
      # missing/expired grant is a domain-state failure -> F1-DOMAIN-409.
      "organization_profile_invalid"      => "F1-VALIDATION-400",
      "project_body_invalid"              => "F1-VALIDATION-400",
      "access_policy_hash_mismatch"       => "F1-VALIDATION-400",
      "entitlement_policy_hash_mismatch"  => "F1-VALIDATION-400",
      "plan_hash_mismatch"                => "F1-VALIDATION-400",
      "bootstrap_grant_unavailable"       => "F1-DOMAIN-409",
      "bootstrap_grant_expired"           => "F1-DOMAIN-409",
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
      "invitation_reason_invalid"         => "F1-VALIDATION-400",
      # WF-013 Session-actor authorization (effective-permission checkpoint,
      # WORKFLOW_SPECIFICATIONS.md :324,:329,:200; MTX-038 :1897). Invalid Session is
      # an authentication failure; an inactive Account/Organization or insufficient
      # capability denies before/at the checkpoint with F1-AUTH-403.
      "session_invalid"                   => "F1-AUTHN-401",
      "account_inactive"                  => "F1-AUTH-403",
      "missing_authority"                 => "F1-AUTH-403",
      # WF-001 ExpireInvitation transport-integrity deviations. A claimed
      # ScheduledAction whose due instant is not its target's expiry instant, or
      # which arrives before that instant, must not expire anything: it is a
      # state conflict between the persisted action and its target
      # (WORKFLOW_SPECIFICATIONS.md :252 state conflicts -> F1-DOMAIN-409), and
      # the worker quarantines the action rather than replaying it
      # (BACKGROUND_PROCESSING.md :245).
      "scheduled_action_target_mismatch"  => "F1-DOMAIN-409",
      "scheduled_action_not_due"          => "F1-DOMAIN-409",
      # WF-013 invitation creation and approval (WORKFLOW_SPECIFICATIONS.md :244
      # creation reasons; :252 input-shape -> F1-VALIDATION-400, state/uniqueness
      # conflicts -> F1-DOMAIN-409; :314 `role_mode_invalid`).
      "identity_email_invalid"            => "F1-VALIDATION-400",
      "role_mode_invalid"                 => "F1-VALIDATION-400",
      "invitation_duplicate_open"         => "F1-DOMAIN-409",
      "invitation_grant_already_active"   => "F1-DOMAIN-409",
      "invitation_approval_required"      => "F1-DOMAIN-409",
      "invitation_approver_conflict"      => "F1-AUTH-403",
      # WF-013 Organization lifecycle (016 STATE_MODEL.md :97; contracts/S-23.json
      # MTX-038; the ratified `reactivation-proof-v1` first-match failure order
      # `access_policy_unavailable`, `organization_admin_unavailable`,
      # `identity_assurance_failed`, `stale_state_version`,
      # `stale_authorization_epoch`).
      "organization_state_invalid"        => "F1-DOMAIN-409",
      "stale_authorization_epoch"         => "F1-DOMAIN-409",
      "access_policy_unavailable"         => "F1-DOMAIN-409",
      "organization_admin_unavailable"    => "F1-AUTH-403",
      "organization_reason_invalid"       => "F1-VALIDATION-400",
      # ":244 the requester can offer only a role/scope/permission set it may
      # grant under the effective-permission algorithm" — missing authority to
      # grant is an authorization failure, not a validation one.
      "grant_scope_exceeded"              => "F1-AUTH-403",
      # ":316 Its active expiry is mandatory and no later than 30 days after
      # effectiveness" for a protected Assignment; input-shape -> F1-VALIDATION-400.
      "role_expiry_required"              => "F1-VALIDATION-400",
      "role_expiry_invalid"               => "F1-VALIDATION-400",
      "role_assignment_not_pending"       => "F1-DOMAIN-409",
      "role_approver_conflict"            => "F1-AUTH-403",
      # ":316 Before an expiry that would remove the last effective
      # OrganizationAdmin … leaves the Assignment active with
      # `expiry_blocked_last_admin`"; ":344 the same last-admin invariant WF-013
      # already applies to revoke."
      "expiry_blocked_last_admin"         => "F1-DOMAIN-409",
      "role_assignment_not_active"        => "F1-DOMAIN-409",
      "last_organization_admin"           => "F1-DOMAIN-409",
      "role_reason_invalid"               => "F1-VALIDATION-400",
      # ":967 OrganizationAdmin may manage non-protected tenant grants …;
      # SecurityOperator may manage … protected grants" — revoking a protected
      # Assignment is outside the OrganizationAdmin cell limb, an authorization
      # failure rather than a validation one.
      "role_protected_authority_required" => "F1-AUTH-403",
      # S-03 Project creation (WF-002, contracts/S-03.json MTX-027 error_contract;
      # class mapping "validation -> F1-VALIDATION-400, authority -> F1-AUTH-403,
      # state/race -> F1-DOMAIN-409"). The creation first-match order is the eight
      # profile/shape reasons, then organization_inactive, project_create_unauthorized,
      # tenant_mismatch, stale_state_version, idempotency_conflict. organization_inactive,
      # stale_state_version and idempotency_conflict are reused from above (identical
      # semantics), so only the Project-specific reasons are added here.
      "project_schema_unsupported"        => "F1-VALIDATION-400",
      "project_display_name_invalid"      => "F1-VALIDATION-400",
      "project_locale_unsupported"        => "F1-VALIDATION-400",
      "project_time_zone_unsupported"     => "F1-VALIDATION-400",
      "project_local_applicability_invalid" => "F1-VALIDATION-400",
      "project_local_reason_invalid"      => "F1-VALIDATION-400",
      "project_local_profile_invalid"     => "F1-VALIDATION-400",
      "project_objective_unsupported"     => "F1-VALIDATION-400",
      "project_create_unauthorized"       => "F1-AUTH-403",
      "tenant_mismatch"                   => "F1-AUTH-403",
      # S-04 Source registration (WF-004 / CAP-004, contracts/S-04.json MTX-004
      # error_contract). Class mapping: schema/URI/host reasons -> F1-VALIDATION-400;
      # duplicate/state -> F1-DOMAIN-409; permission -> F1-AUTH-403. `tenant_mismatch`
      # and `stale_state_version` and `idempotency_conflict` are reused from above.
      #
      # DEVIATION, ratified by owner (2026-07-24): S-04.json/WF-004 :406 classify
      # `organization_inactive` as F1-DOMAIN-409, but S-01 existing-account sign-in
      # and WF-013 ratified it as F1-AUTH-403 and ship tests asserting 403. A shared
      # reason_code has exactly one class; changing it would rewrite previously
      # ratified slices. Per the owner decision, `organization_inactive` remains
      # F1-AUTH-403 (its existing mapping above) and the conflicting S-04.json/WF-004
      # requirement is recorded as a Volume I specification defect for reconciliation.
      "source_request_schema_unsupported" => "F1-VALIDATION-400",
      "source_uri_malformed"              => "F1-VALIDATION-400",
      "unsupported_source_scheme"         => "F1-VALIDATION-400",
      "source_userinfo_prohibited"        => "F1-VALIDATION-400",
      "source_port_unsupported"           => "F1-VALIDATION-400",
      "source_path_not_root"              => "F1-VALIDATION-400",
      "source_query_prohibited"           => "F1-VALIDATION-400",
      "source_fragment_prohibited"        => "F1-VALIDATION-400",
      "source_host_non_ascii"             => "F1-VALIDATION-400",
      "source_host_invalid"               => "F1-VALIDATION-400",
      "project_not_registerable"          => "F1-DOMAIN-409",
      "source_host_already_registered"    => "F1-DOMAIN-409",
      "source_register_unauthorized"      => "F1-AUTH-403",
      # S-05 Ownership Verification, IssueVerificationChallenge limb (WF-003 / CAP-005,
      # contracts/S-05.json MTX-028/MTX-071 error_contract). Class mapping: method-set
      # and request-shape rejections -> F1-VALIDATION-400; state/uniqueness/redelivery
      # conflicts -> F1-DOMAIN-409; permission -> F1-AUTH-403. `tenant_mismatch`,
      # `stale_state_version` and `idempotency_conflict` are reused from above with
      # identical semantics. `unsupported_method` (PRULE-020) and the envelope-schema
      # gate are rejected before any token is issued.
      "verification_request_schema_unsupported" => "F1-VALIDATION-400",
      "unsupported_method"                => "F1-VALIDATION-400",
      "verification_in_progress"          => "F1-DOMAIN-409",
      "source_not_proposed"               => "F1-DOMAIN-409",
      # A pending Request whose challenge material cannot be decrypted on an
      # authorized redelivery: it changes no Request or Source state and permits
      # authorized cancellation followed by a new Request (a domain-state outcome,
      # not a transient dependency failure to retry).
      "challenge_redelivery_unavailable"  => "F1-DOMAIN-409",
      "source_verify_unauthorized"        => "F1-AUTH-403",
      # S-05-002 ExpireVerificationRequest (WF-003 expiry limb). A timer arriving for
      # a Request that is no longer pending is a harmless state conflict between the
      # persisted action and its target (:252 state conflicts -> F1-DOMAIN-409);
      # scheduled_action_target_mismatch / scheduled_action_not_due are reused from
      # the WF-001/WF-013 expiry handlers above.
      "verification_request_not_pending"  => "F1-DOMAIN-409",
      # S-05-004 ReserveVerificationAttempt (WF-003 on-demand observation reservation,
      # contracts/S-05.json MTX-028 error_contract). The three on-demand denials are
      # state conflicts on the Verification Request (a full count, an observation
      # already in progress, or a request within the 5-minute cool-down): none verifies
      # or disables the Source and none increments attempt_count. `stale_state_version`
      # is reused from above (on-demand requires the expected Request state version).
      "on_demand_limit_reached"           => "F1-DOMAIN-409",
      "on_demand_observation_in_progress" => "F1-DOMAIN-409",
      "on_demand_rate_limited"            => "F1-DOMAIN-409",
      # S-06-003 ProposeSourceScopeChange (WF-004 / CAP-006, contracts/S-06.json MTX-029
      # error_contract). Class mapping: request-shape and boundary rejections ->
      # F1-VALIDATION-400; state/precondition/version conflicts -> F1-DOMAIN-409; permission
      # -> F1-AUTH-403. `tenant_mismatch`, `idempotency_conflict` and `unsupported_source_scheme`
      # are reused from above with identical semantics. `cross_host_expansion` is unreachable
      # via this command (the host is the Source's verified host, never a command input) but
      # is mapped for completeness.
      "source_scope_reason_invalid"       => "F1-VALIDATION-400",
      "source_scope_proposal_invalid"     => "F1-VALIDATION-400",
      "source_scope_boundary_violation"   => "F1-VALIDATION-400",
      "cross_host_expansion"              => "F1-VALIDATION-400",
      "source_not_verified"               => "F1-DOMAIN-409",
      "stale_active_policy_version"       => "F1-DOMAIN-409",
      "source_scope_unauthorized"         => "F1-AUTH-403",
      # S-05-005 CompleteVerificationAttempt (WF-003 observation recording). A completion
      # whose attempt/Request do not name each other (a wiring error) and a completion for
      # an attempt that is no longer reserved are harmless state conflicts between the
      # service-built command and its target (:252 state conflicts -> F1-DOMAIN-409);
      # verification_request_not_pending / challenge_redelivery_unavailable are reused from
      # the issuance/expiry limbs above.
      "verification_attempt_target_mismatch" => "F1-DOMAIN-409",
      "verification_attempt_not_reserved"    => "F1-DOMAIN-409"
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
