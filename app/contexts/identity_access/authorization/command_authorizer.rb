# frozen_string_literal: true

require "time"

module IdentityAccess
  module Authorization
    # The authenticated Session actor: the Account and Organization derived FROM the
    # Session record (never from caller input), plus the Organization authorization
    # epoch resolved at command time.
    AuthenticatedActor = Data.define(:account_id, :organization_id, :authorization_epoch)

    # The capability decision plus the fields the durable authorization_decisions
    # record must carry (WORKFLOW_SPECIFICATIONS.md § authorization decision :331).
    Decision = Data.define(:allowed, :reason, :organization_epoch, :policy_snapshot_id,
                           :role_assignment_versions) do
      def allowed? = allowed
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

      # Evaluate `capability` for an authenticated actor. Resolves exactly one active
      # Access Policy (policy_unavailable if missing/conflicting), selects the actor's
      # active effective Role Assignments, and reads the Permission Baseline cell. The
      # baseline access-policy-v1 carries empty denies, so no deny subtraction applies
      # in this slice; invitation.revoke is unprotected, so no protected-allowlist gate.
      def authorize(actor:, capability:, now:)
        policy = @store.active_access_policy(actor.organization_id)
        return deny("policy_unavailable", actor, nil, []) if policy.nil?

        assignments = @store.effective_role_assignments(account_id: actor.account_id, now:)
        versions = assignments.map { |a| { "id" => a["id"], "state_version" => a["state_version"].to_i } }
        roles = assignments.map { |a| a["canonical_role"] }

        if Platform::PermissionBaseline.permits?(capability, roles)
          Decision.new(allowed: true, reason: "authorized", organization_epoch: actor.authorization_epoch,
                       policy_snapshot_id: policy["id"], role_assignment_versions: versions)
        else
          deny("missing_authority", actor, policy["id"], versions)
        end
      end

      private

      def deny(reason, actor, policy_id, versions)
        Decision.new(allowed: false, reason:, organization_epoch: actor.authorization_epoch,
                     policy_snapshot_id: policy_id, role_assignment_versions: versions)
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
