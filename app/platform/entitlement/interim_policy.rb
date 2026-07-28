# frozen_string_literal: true

module Platform
  module Entitlement
    # The frozen `entitlement-interim-v1` policy (WORKFLOW_SPECIFICATIONS.md § Interim Entitlement
    # Contract :513-554; owner D2 / DECISIONS ADR-069). Pure functions only — the operative soft/hard
    # limits, counter groups, reservation lifetime, and the allow/warn/block classification.
    #
    # F-05 RECONCILIATION (ADR-069): these are the operative limits, sourced from a FIXED interim
    # constant matching WORKFLOW :527 — NOT from the genesis `entitlement_policies` bytes, whose
    # soft/hard numbers are a non-operative placeholder representation the genesis author explicitly
    # deferred ("no operative behaviour is invented here"; app/platform/baseline_content.rb). A later
    # OD-006 replacement supersedes this constant; changing it is a Change-Boundary action.
    module InterimPolicy
      module_function

      VERSION = "entitlement-interim-v1"
      PLAN_VERSION = "interim-baseline-plan-v1"

      # Under entitlement-interim-v1 the prestart reservation lifetime is exactly 15 minutes for every
      # high-cost operation (WORKFLOW :551); the executing lease renews on a heartbeat and expires 15
      # minutes after the last accepted heartbeat, capped by the operation's maximum-execution instant.
      # WORKFLOW :551 also permits an Organization policy to SHORTEN the prestart lifetime to a whole
      # 1-15 minutes; the mandatory byte-equivalent interim policy fixes 15 for every org, so that
      # configurable shortening is an OD-006-replacement-era feature, deferred here (not implemented).
      PRESTART_LIFETIME_SECONDS = 15 * 60
      LEASE_RENEWAL_SECONDS = 15 * 60
      HEARTBEAT_CADENCE_SECONDS = 5 * 60

      # The four high-cost operations and their ratified interim rules (WORKFLOW :527). Each uses its
      # own operation name as the counter group; every usage costs one unit.
      HIGH_COST_RULES = {
        "crawl.start" => {
          counter_group: "crawl.start", usage_unit: "crawl_run", soft: 3, hard: 4,
          max_execution_seconds: 65 * 60, durable_commit_point: "crawl_completed_with_valid_document"
        },
        "reassessment.start" => {
          counter_group: "reassessment.start", usage_unit: "reassessment_run", soft: 1, hard: 2,
          max_execution_seconds: 120 * 60, durable_commit_point: "issue_set_and_score_promoted"
        },
        "ai.generate" => {
          counter_group: "ai.generate", usage_unit: "validated_ai_response", soft: 20, hard: 25,
          max_execution_seconds: 2 * 60, durable_commit_point: "validated_ai_response_persisted"
        },
        "export.generate" => {
          counter_group: "export.generate", usage_unit: "export_package", soft: 8, hard: 10,
          max_execution_seconds: 15 * 60, durable_commit_point: "export_available"
        }
      }.freeze

      def high_cost?(operation) = HIGH_COST_RULES.key?(operation)
      def rule(operation) = HIGH_COST_RULES[operation]

      # The half-open UTC calendar day [00:00:00Z, next 00:00:00Z) containing `at` (WORKFLOW :523).
      # UTC days are always 86_400s, so the exclusive end is a fixed offset (no DST).
      def counter_window(at)
        utc = at.getutc
        start = Time.utc(utc.year, utc.month, utc.day)
        [start, start + 86_400]
      end

      # The interim classification (WORKFLOW :519): a high-cost operation is allowed only when
      # committed + active_reserved + requested <= hard (equality allowed; a strictly greater result
      # is blocked); a resulting value >= soft returns allow-with-warning. Returns
      # [decision, reason_code, recovery_action] where decision is one of :allow / :allow_with_warning
      # / :block. `soft`/`hard` come from the operation rule.
      def classify(committed:, active_reserved:, requested:, soft:, hard:)
        resulting = committed + active_reserved + requested
        if resulting > hard
          [:block, "hard_limit_exceeded", "wait_for_window"]
        elsif resulting >= soft
          [:allow_with_warning, "soft_limit_reached", "none"]
        else
          [:allow, "within_limit", "none"]
        end
      end
    end
  end
end
