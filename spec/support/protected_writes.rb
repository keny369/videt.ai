# frozen_string_literal: true

# THE PROTECTED WRITES, IN ONE PLACE, SO THE SET ITSELF CAN BE ENFORCED (FU-61).
#
# WHAT WAS OPEN. This map used to live inside `wf005_grant_battery_spec.rb` as a hand-maintained
# literal referenced by the `WRITES.each` at the foot of that file and by nothing else. The round-19
# repair's claim to be STRUCTURAL rather than three more proofs rests entirely on inheritance —
# twelve shared examples run at every entry — so A FOURTH PROTECTED WRITE WOULD INHERIT NONE OF
# THEM and no gate would say so. Round 20 demonstrated exactly that: it built a fourth protected
# write that inherited nothing while the suite stayed green.
#
# Completeness was established that round by planning all 391 SQL statements in `app/` and `lib/`
# through `EXPLAIN (GENERIC_PLAN)` and collecting `ModifyTable` nodes. That was a REVIEW ACTIVITY,
# not a gate, and it does not run again. `spec/architecture/protected_write_completeness_spec.rb`
# is the gate: it derives the protected-write set FROM THE REPOSITORY and fails when it is not
# exactly what this file enumerates.
#
# THIS FILE IS THE SUBJECT OF THAT GATE, WHICH IS WHY IT IS NOT IN THE BATTERY. A list that only
# the thing consuming it can see is a list nothing can check. Here, one derivation reads the
# repository, one reads this file, and the gate compares them.
#
# PRIORITY, MEASURED. `crawl.recover` is ratified in WORKFLOW_SPECIFICATIONS.md's WF-005 Recovery
# Path and is NOT in `PermissionBaseline::CAPABILITIES`, so a fourth protected write is SCHEDULED
# WORK rather than a hypothesis. The gate exists before it lands.
module ProtectedWrites
  # Each entry: WHICH write it is, how to reach it, what capability it spends, THE `required_role`
  # ITS PRODUCTION CALLER PASSES, how to drive it with a chosen authority, how many rows it applied,
  # and what the aggregate looks like when it applied none.
  #
  # `write:` IS THE IDENTITY THE GATE COMPARES — the fully qualified receiver and method of the
  # statement carrying the `capability_authority` CTE. Two entries may name the SAME write at
  # different configurations (the policy activation appears at both of its ratified scopes), so the
  # gate compares the DISTINCT set rather than the row count.
  #
  # `required_role` IS PART OF THE CONFIGURATION, NOT AN OPTIONAL EXTRA (FU-63 part 2). It is the
  # ratified `:732`/`:738` scope rule carried to the write, and it is the ONLY axis on which the two
  # policy configurations differ. Every driver before round 20 passed `nil` — the value the
  # cancellation and the queue insert really use — so the policy write was exercised at a value its
  # production caller can never pass.
  #
  # `required_scope_hex` IS PART OF IT FOR THE SAME REASON (FU-2, sited by FU-49). It is the scope an
  # Assignment must hold to CONTAIN the write's target, and the two policy configurations differ on
  # it exactly as they differ on `required_role`: `ActivateCrawlPolicy::SCOPE_DIGEST` names
  # Organization scope at Organization scope and `nil` at Project scope, where `role_assignments`
  # holds only a one-way digest of the grant's `GrantScope` and no single scope answers containment.
  # A registry that omitted it would drive the policy write with no containment claim while
  # production carries one — R20-2's shape, on the axis FU-2 opened.
  WRITES = {
    "the cancellation (CrawlStartStore#cancel)" => {
      write: "IdentityAccess::Infrastructure::CrawlStartStore#cancel",
      capability: "crawl.cancel",
      required_role: nil,
      required_scope_hex: nil,
      setup: :setup_cancel,
      invoke: :invoke_cancel,
      applied: ->(outcome) { outcome[:moved] },
      untouched: :cancel_untouched?
    },
    "the queue insert (CrawlStore#insert_crawl)" => {
      write: "IdentityAccess::Infrastructure::CrawlStore#insert_crawl",
      capability: "crawl.trigger",
      required_role: nil,
      required_scope_hex: nil,
      setup: :setup_queue,
      invoke: :invoke_queue,
      applied: ->(outcome) { outcome[:inserted] },
      untouched: :queue_untouched?
    },
    "the policy activation at ORGANIZATION scope (CrawlPolicyStore#activate_version)" => {
      write: "IdentityAccess::Infrastructure::CrawlPolicyStore#activate_version",
      capability: "policy.crawl.manage",
      required_role: "OrganizationAdmin",
      required_scope_hex: Workflows::Wf005::Handlers::ActivateCrawlPolicy::SCOPE_DIGEST
        .fetch("organization"),
      setup: :setup_policy,
      invoke: :invoke_policy,
      applied: ->(outcome) { outcome[:inserted] },
      untouched: :policy_untouched?
    },
    # THE CONFIGURATION R20-2 FOUND UNPROVED. `:173` gives the MarketingOperator a Project-scope
    # cell, `SCOPE_ROLE["project"]` transcribes it, and no driver in twenty rounds had ever passed
    # it. A `read_only_permitted` derived as `!required_role.nil?` is FALSE in every organization-
    # scope case that existed and TRUE here, which is exactly why the corpus stayed green while a
    # Read-Only Executive Buyer activated an immutable Project policy.
    "the policy activation at PROJECT scope (CrawlPolicyStore#activate_version)" => {
      write: "IdentityAccess::Infrastructure::CrawlPolicyStore#activate_version",
      capability: "policy.crawl.manage",
      required_role: "MarketingOperator",
      required_scope_hex: Workflows::Wf005::Handlers::ActivateCrawlPolicy::SCOPE_DIGEST
        .fetch("project"),
      setup: :setup_policy_project,
      invoke: :invoke_policy_project,
      applied: ->(outcome) { outcome[:inserted] },
      untouched: :policy_untouched?
    }
  }.freeze

  # The DISTINCT writes this registry covers, which is what the repository is compared against.
  def self.covered = WRITES.values.map { |spec| spec.fetch(:write) }.uniq.sort

  # Every member a configuration must carry for the battery to be able to drive it. A registry entry
  # added without one of these would produce a `KeyError` deep inside a shared example, naming a
  # missing hash key rather than an incomplete registration.
  REQUIRED_MEMBERS = %i[write capability required_role required_scope_hex setup invoke applied
                        untouched].freeze
end
