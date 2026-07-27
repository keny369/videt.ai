# frozen_string_literal: true

module Workflows
  module Wf004
    # The shared, none-without-the-others Source Scope Policy activation used by the
    # atomic-contraction fast-path on ProposeSourceScopeChange and by DecideSourceScopeChange
    # approval (S-06-004; WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :420;
    # contracts/S-06.json MTX-029 aggregate_boundary/transaction_boundary/concurrency).
    #
    # In the caller's single transaction it inserts one new immutable source_scope_policies
    # version (the S-05-006 shape) and repoints the Source's current_scope_policy_id to it,
    # guarded on the expected current pointer so a concurrent activation cannot apply twice.
    # It changes no Source state. The new version string is a monotonic per-Source ordinal
    # (`source-scope-v{N}`; the interim source-scope-interim-v1 is ordinal 1), unique-enforced
    # by the (organization, project, source, policy_version) constraint (autonomous naming,
    # DECISIONS ADR-062: the exact string is not behaviourally material — any unique
    # deterministic token serves identically as the expected-active-policy-version concurrency
    # value; it is read under the per-Source lock the caller already holds).
    module SourceScopePolicyActivation
      module_function

      class LostRace < StandardError; end

      # `proposed` is a hash: canonical_host, allowed_schemes, allowed_ports, include_prefixes,
      # exclude_prefixes, query_handling, content_sha256 (raw 32 bytes). `current_policy_id` is
      # the id of the active policy the change was decided against (the repoint guard).
      def activate(store:, ctx:, org:, project_id:, source_id:, proposed:, current_policy_id:, now:)
        version = "source-scope-v#{store.policy_count(source_id) + 1}"
        policy_id = ctx.generate_id
        store.insert_source_scope_policy(
          id: policy_id, now:, correlation_id: ctx.correlation_id, organization_id: org,
          project_id:, source_id:, policy_version: version, canonical_host: proposed[:canonical_host],
          allowed_schemes: proposed[:allowed_schemes], allowed_ports: proposed[:allowed_ports],
          include_prefixes: proposed[:include_prefixes], exclude_prefixes: proposed[:exclude_prefixes],
          query_handling: proposed[:query_handling], content_sha256: proposed[:content_sha256]
        )
        raise LostRace if store.repoint_source(source_id, policy_id, current_policy_id, now).to_i.zero?

        { policy_id:, policy_version: version }
      end
    end
  end
end
