# frozen_string_literal: true

module Workflows
  module Wf005
    # The persisted `crawl_fetch_due` surface named by BACKGROUND_PROCESSING.md :138/:198. It
    # materializes a Fetch Attempt row first, then schedules the durable action that will execute
    # exactly that row.
    module FetchAttemptDueSchedule
      module_function

      ACTION_KIND = "crawl_fetch_due"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "fetch_attempt"

      def prepare(pg:, organization_id:, project_id:, crawl_id:, gate_id:, entry:, reserved_bytes:,
                  now:, correlation_id:, causation_id: nil, command_id: nil, due_at: now,
                  attempt_number: 1, ids: Platform::Ids.system, schedule_generation: 1)
        attempt = persist_attempt(
          pg:, organization_id:, project_id:, crawl_id:, gate_id:, reserved_bytes:,
          canonical_url: entry["canonical_url"], canonical_host: FetchAuthorization.host_of(entry["canonical_url"]),
          source_id: entry["source_id"], frontier_entry_id: entry["id"], depth: entry["depth"].to_i,
          dequeue_key: decode(entry["dequeue_key"]), scope_policy_id: entry["scope_policy_id"],
          scope_policy_version: entry["scope_policy_version"], now:, correlation_id:,
          causation_id:, command_id:, due_at:, attempt_number:, ids:
        )
        action_id = schedule(
          pg:, organization_id:, project_id:, attempt_id: attempt["id"], due_at:, now:,
          correlation_id:, causation_id:, command_id:, schedule_generation:
        )
        { attempt_id: attempt["id"], action_id: }
      end

      def retry(pg:, attempt:, reserved_bytes:, due_at:, now:, correlation_id:, causation_id: nil,
                command_id: nil, ids: Platform::Ids.system, schedule_generation: 1)
        prepared = persist_attempt(
          pg:, organization_id: attempt["organization_id"], project_id: attempt["project_id"],
          crawl_id: attempt["crawl_id"], gate_id: attempt["crawl_host_gate_id"], reserved_bytes:,
          canonical_url: attempt["canonical_url"], canonical_host: attempt["canonical_host"],
          source_id: attempt["source_id"], frontier_entry_id: attempt["crawl_frontier_entry_id"],
          depth: attempt["depth"].to_i, dequeue_key: decode(attempt["dequeue_key"]),
          scope_policy_id: attempt["scope_policy_id"], scope_policy_version: attempt["scope_policy_version"],
          now:, correlation_id:, causation_id:, command_id:, due_at:,
          attempt_number: attempt["attempt_number"].to_i + 1, ids:
        )
        action_id = schedule(
          pg:, organization_id: attempt["organization_id"], project_id: attempt["project_id"],
          attempt_id: prepared["id"], due_at:, now:, correlation_id:, causation_id:, command_id:,
          schedule_generation:
        )
        { attempt_id: prepared["id"], action_id: }
      end

      def schedule(pg:, organization_id:, project_id:, attempt_id:, due_at:, now:, correlation_id:,
                   causation_id: nil, command_id: nil, product_generation: 0, schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: attempt_id,
          product_generation:, schedule_generation:,
          due_at:, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end

      def persist_attempt(pg:, organization_id:, project_id:, crawl_id:, gate_id:, reserved_bytes:,
                          canonical_url:, canonical_host:, source_id:, frontier_entry_id:, depth:,
                          dequeue_key:, scope_policy_id:, scope_policy_version:, now:, correlation_id:,
                          causation_id:, command_id:, due_at:, attempt_number:, ids:)
        attempts = IdentityAccess::Infrastructure::FetchAttemptStore.new(pg)
        attempts.enter_org_context(org: organization_id, correlation_id:)
        existing = attempts.find_by_identity(
          organization_id:, crawl_host_gate_id: gate_id, frontier_entry_id:, kind: "content", attempt_number:
        )
        return existing if existing

        gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
        gates.enter_org_context(org: organization_id, correlation_id:)
        bounds = EffectiveLimits.resolve(gates.active_crawl_policies(organization_id, project_id)).byte_bounds
        inserted = attempts.prepare(
          id: ids.generate, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, organization_id:, project_id:, crawl_id:, crawl_host_gate_id: gate_id,
          source_id:, frontier_entry_id:, kind: "content", attempt_number: attempt_number.to_i,
          canonical_url:, canonical_host:, depth: depth.to_i, dequeue_key:, scope_policy_id:,
          scope_policy_version:, crawl_policy_id: nil, crawl_policy_version: nil,
          reserved_bytes: reserved_bytes.to_i, deadline_at: due_at + bounds.timeout_s
        )
        return attempts.attempt(organization_id, inserted["id"]) if inserted

        attempts.find_by_identity(
          organization_id:, crawl_host_gate_id: gate_id, frontier_entry_id:, kind: "content", attempt_number:
        ) || raise(Platform::InvariantViolation, "prepared fetch attempt disappeared")
      end

      def decode(value) = value && [value.to_s.sub(/\A\\x/, "")].pack("H*")
    end
  end
end
