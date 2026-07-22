# frozen_string_literal: true

require "json"
require "time"

module IdentityAccess
  module Authorization
    # The authenticated Session actor: the Account and Organization derived FROM the
    # Session record (never from caller input), plus the Organization authorization
    # epoch resolved at command time.
    AuthenticatedActor = Data.define(:account_id, :organization_id, :authorization_epoch)

    # The capability decision plus the fields the durable authorization_decisions
    # record must carry (WORKFLOW_SPECIFICATIONS.md § authorization decision :331).
    # `granting_assignments` carries the Assignments that actually conferred the
    # capability, so a caller that must reason about the actor's own authority —
    # grant authority, scope containment — reads it from the decision rather than
    # re-deriving it.
    Decision = Data.define(:allowed, :reason, :organization_epoch, :policy_snapshot_id,
                           :role_assignment_versions, :granting_assignments) do
      def allowed? = allowed

      def granting = granting_assignments || []
    end

    # The narrow authorization facade for Session-authenticated organization-actor
    # commands (the effective-permission checkpoint, WORKFLOW_SPECIFICATIONS.md
    # :322-329). Three conceptually separate concerns share this plumbing:
    #   authenticate  — validate the Session and derive the actor+Organization;
    #   (actor context — the resolved Account/Organization membership);
    #   authorize     — evaluate a capability against the Permission Baseline.
    # It resolves nothing from caller-supplied account/organization ids.
    class CommandAuthorizer
      def initialize(store)
        @store = store
      end

      # Authenticate the Session and resolve the actor context, ENTERING the proved
      # Organization context on success. Returns an AuthenticatedActor, or a symbol
      # reason: :session_invalid (authentication — unknown/inactive/expired Session);
      # :account_inactive / :organization_inactive (which deny before Assignment
      # evaluation, :324).
      def authenticate(session_id:, now:, correlation_id:)
        row = @store.authenticate_session(session_id)
        return :session_invalid if row.nil? || row["status"] != "active"
        return :session_invalid if now >= session_deadline(row)

        org = row["organization_id"]
        @store.enter_org_context(org, correlation_id)

        account = @store.account(row["account_id"])
        return :account_inactive if account.nil? || account["status"] != "active"

        org_row = @store.organization(org)
        return :organization_inactive if org_row.nil? || org_row["status"] != "active"

        AuthenticatedActor.new(account_id: row["account_id"], organization_id: org,
                               authorization_epoch: org_row["authorization_epoch"].to_i)
      end

      # Evaluate `capability` for an authenticated actor, following the ratified
      # effective-permission order (:322-329):
      #
      #   2. resolve exactly one active Access Policy (`policy_unavailable` when
      #      missing or conflicting);
      #   3. select the actor's active effective Role Assignments;
      #   4. read the role/action cell from `permission-baseline-v1` AND "require
      #      any protected permission to appear in the Assignment's approved
      #      protected allowlist";
      #   5-6. union the allowed permissions and return allow.
      #
      # Step 4's protected-allowlist gate lives here rather than in each handler:
      # a baseline allow is necessary but not sufficient for a protected
      # capability, and that rule is identical for every consumer.
      #
      # The baseline `access-policy-v1` carries empty denies, so step 5's deny
      # subtraction is a no-op for it; a narrower Organization policy that adds
      # denies is a later slice and is deliberately not approximated here.
      def authorize(actor:, capability:, now:)
        policy = @store.active_access_policy(actor.organization_id)
        return deny("policy_unavailable", actor, nil, [], []) if policy.nil?

        assignments = @store.effective_role_assignments(account_id: actor.account_id, now:)
        versions = assignments.map { |a| { "id" => a["id"], "state_version" => a["state_version"].to_i } }

        granting = assignments.select { |a| confers?(capability, a) }
        return deny("missing_authority", actor, policy["id"], versions, []) if granting.empty?

        Decision.new(allowed: true, reason: "authorized", organization_epoch: actor.authorization_epoch,
                     policy_snapshot_id: policy["id"], role_assignment_versions: versions,
                     granting_assignments: granting)
      end

      private

      # Step 4 for one Assignment: the baseline cell allows the capability to this
      # Assignment's canonical role, and — when the capability is protected — the
      # Assignment's own approved allowlist carries it.
      def confers?(capability, assignment)
        return false unless Platform::PermissionBaseline.permits?(capability, [assignment["canonical_role"]])
        return true unless Platform::PermissionBaseline::PROTECTED.key?(capability)
        # ":329 … or in the expressly defined first-admin/bootstrap exception."
        return true if truthy(assignment["bootstrap_admin_exception"])

        Platform::PermissionBaseline.protected_grant?(capability, allowlist(assignment))
      end

      def truthy(value) = value == true || value == "t"

      def allowlist(assignment)
        raw = assignment["protected_permission_allowlist"]
        raw.is_a?(::String) ? JSON.parse(raw) : Array(raw)
      end

      def deny(reason, actor, policy_id, versions, granting = [])
        Decision.new(allowed: false, reason:, organization_epoch: actor.authorization_epoch,
                     policy_snapshot_id: policy_id, role_assignment_versions: versions,
                     granting_assignments: granting)
      end

      def session_deadline(row)
        [to_time(row["idle_expires_at"]), to_time(row["absolute_expires_at"])].min
      end

      def to_time(value)
        return value.getutc if value.respond_to?(:getutc)

        Time.parse(value).getutc
      end
    end
  end
end
