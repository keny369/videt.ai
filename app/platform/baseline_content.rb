# frozen_string_literal: true

module Platform
  # The immutable baseline policy and plan artifacts the WF-001 self-service
  # commit materializes (WORKFLOW_SPECIFICATIONS.md :320 access-policy-v1, :515
  # entitlement-interim-v1, :517 interim-baseline-plan-v1). This is the single
  # canonical source of their bytes: the genesis writes them, and the command
  # verifies the caller approved exactly these bytes by comparing the caller's
  # supplied content hash against the digest computed here.
  #
  # Representation decision, this slice owns it (exactly as [[od-013]] owns the
  # bootstrap-principal uuid byte form): Volume I fixes the STRUCTURE of these
  # artifacts — every field named below is enumerated in the frozen text — but
  # does not publish reproducible bytes, so the canonical byte form is defined
  # here. The genesis only creates and hashes these documents; the entitlement
  # DECISION engine that interprets the numeric limits is CAP-024 / S-22 and is
  # not built in this slice, so no operative behaviour is invented here. S-22
  # consumes these bytes rather than redefining them.
  module BaselineContent
    module_function

    ACCESS_POLICY_VERSION = "access-policy-v1"
    ENTITLEMENT_POLICY_VERSION = "entitlement-interim-v1"
    PLAN_VERSION = "interim-baseline-plan-v1"
    PLAN_APPROVAL_VERSION = "plan-approval-interim-baseline-v1"
    PERMISSION_PROFILE_VERSION = "permission-baseline-v1"

    # ":314 the allowed role/mode/persona tuples": `standard` permits a null
    # persona for any canonical role, or `consultant` only with OrganizationAdmin,
    # MarketingOperator, or TechnicalImplementer; `read_only` permits only
    # MarketingOperator with `executive_buyer`. Sorted for a stable canonical form.
    ALLOWED_ROLE_MODE_PERSONA = [
      { "canonical_role" => "BillingOperator", "permission_mode" => "standard", "persona" => nil },
      { "canonical_role" => "MarketingOperator", "permission_mode" => "read_only", "persona" => "executive_buyer" },
      { "canonical_role" => "MarketingOperator", "permission_mode" => "standard", "persona" => nil },
      { "canonical_role" => "MarketingOperator", "permission_mode" => "standard", "persona" => "consultant" },
      { "canonical_role" => "OrganizationAdmin", "permission_mode" => "standard", "persona" => nil },
      { "canonical_role" => "OrganizationAdmin", "permission_mode" => "standard", "persona" => "consultant" },
      { "canonical_role" => "SecurityOperator", "permission_mode" => "standard", "persona" => nil },
      { "canonical_role" => "TechnicalImplementer", "permission_mode" => "standard", "persona" => nil },
      { "canonical_role" => "TechnicalImplementer", "permission_mode" => "standard", "persona" => "consultant" }
    ].freeze

    # ":320 Its normalized payload contains exactly permission_profile_version …
    # classification_profile_version … protected_permission_profile_version … the
    # allowed role/mode/persona tuples above, an Organization scope, and empty
    # sorted denied_permissions and denied_resource_scopes arrays."
    ACCESS_POLICY = {
      "semantic_version" => ACCESS_POLICY_VERSION,
      "permission_profile_version" => PERMISSION_PROFILE_VERSION,
      "classification_profile_version" => "score-visibility-v1",
      "protected_permission_profile_version" => "protected-permissions-v1",
      "allowed_role_mode_persona" => ALLOWED_ROLE_MODE_PERSONA,
      "scope" => "organization",
      "denied_permissions" => [],
      "denied_resource_scopes" => []
    }.freeze

    # ":519 High-cost operations are crawl.start, reassessment.start, ai.generate,
    # export.generate. Low-cost operations are report.view, history.view,
    # issue.read, recommendation.read, score.read." ":523 the five low-cost
    # operations use the shared counter group baseline_reads; high-cost operations
    # each use their named operation as counter group." ":551 Under
    # entitlement-interim-v1 the high-cost prestart reservation lifetime is exactly
    # 15 minutes." The soft/hard limit numbers are this slice's baseline
    # representation; S-22 owns their operative interpretation under OD-006.
    HIGH_COST_OPERATIONS = %w[ai.generate crawl.start export.generate reassessment.start].freeze
    LOW_COST_OPERATIONS = %w[history.view issue.read recommendation.read report.view score.read].freeze

    def high_cost_rule(operation)
      { "usage_unit" => "operation", "counter_group" => operation, "window" => "utc_calendar_day",
        "soft_limit" => 80, "hard_limit" => 100, "grace_behavior" => "block_over_hard",
        "reservation_lifetime_minutes" => 15, "max_execution_minutes" => 60,
        "durable_commit_point" => "protected_execution_checkpoint" }
    end

    def low_cost_rule(operation)
      { "usage_unit" => "read", "counter_group" => "baseline_reads", "window" => "utc_calendar_day",
        "soft_limit" => 8000, "hard_limit" => 10_000, "grace_behavior" => "warn_over_hard",
        "reservation_lifetime_minutes" => nil, "max_execution_minutes" => nil,
        "durable_commit_point" => "authorized_response_checkpoint" }
    end

    # ":515 An Entitlement Policy contains policy and plan versions, Organization,
    # effective time, and a required operation_rules map keyed by operation class."
    ENTITLEMENT_POLICY = {
      "semantic_version" => ENTITLEMENT_POLICY_VERSION,
      "plan_version" => PLAN_VERSION,
      "operation_rules" => (HIGH_COST_OPERATIONS.to_h { |op| [op, high_cost_rule(op)] })
                             .merge(LOW_COST_OPERATIONS.to_h { |op| [op, low_cost_rule(op)] })
    }.freeze

    # ":517 The only bootstrap plan is interim-baseline-plan-v1. Its immutable
    # provisional approval artifact is plan-approval-interim-baseline-v1 … contains
    # approval ID/schema version, exact plan/policy content hashes, all operation
    # rules below, issuer release-service identity, issued time, null expiry,
    # status active, and signature/key version."
    PLAN = {
      "plan_version" => PLAN_VERSION,
      "approval_version" => PLAN_APPROVAL_VERSION,
      "entitlement_policy_version" => ENTITLEMENT_POLICY_VERSION,
      "operation_rules" => ENTITLEMENT_POLICY["operation_rules"],
      "status" => "active",
      "expires_at_utc" => nil
    }.freeze

    def access_policy_sha256 = Platform::CanonicalJson.digest(ACCESS_POLICY)
    def entitlement_policy_sha256 = Platform::CanonicalJson.digest(ENTITLEMENT_POLICY)
    def plan_sha256 = Platform::CanonicalJson.digest(PLAN)

    # The frozen organization-profile-v1 constants (:230): a self-service profile
    # is a display name plus these fixed values.
    PROFILE_SCHEMA_VERSION = "organization-profile-v1"
    DEFAULT_LOCALE = "en-AU"
    REPORTING_TIME_ZONE = "UTC"
    DISPLAY_NAME_MAX = 120
  end
end
