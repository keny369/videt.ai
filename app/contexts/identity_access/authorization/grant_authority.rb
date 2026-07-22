# frozen_string_literal: true

require "digest"

module IdentityAccess
  module Authorization
    # ":244 the requester can offer only a role/scope/permission set it may grant
    # under the effective-permission algorithm and cannot use invitation creation
    # to bypass protected approval."
    #
    # This replaces the structural approximation the invitation blocks deferred.
    # It is evaluated through `CommandAuthorizer` — the same machinery every other
    # decision uses, including step 4's protected-allowlist gate — rather than by
    # bespoke handler logic, and it answers three separate questions:
    #
    #   ROLE   the requester holds `role.manage`. The Permission Baseline cell is
    #          "allow for non-protected tenant grants" for OrganizationAdmin and
    #          "allow" for SecurityOperator (:140).
    #   SCOPE  the offered scope is contained by a scope the requester's own
    #          granting Assignment covers (:327 "Organization scope contains all
    #          same-Organization resources"; "Resource containment requires exact
    #          type/ID membership").
    #   SET    a DIRECT grant may not confer protected authority. An
    #          OrganizationAdmin's cell is expressly limited to non-protected
    #          tenant grants, so protected authority is reachable only through the
    #          ratified approval path — which is precisely the "cannot bypass
    #          protected approval" clause.
    #
    # A protected offer is therefore not refused: it is refused as a DIRECT grant,
    # and remains available through approval. `direct:` distinguishes the two.
    module GrantAuthority
      module_function

      CAPABILITY = "role.manage"
      # The digest of Organization-wide scope, which contains every same-Organization
      # resource. A granting Assignment with this scope (or none) contains any offer.
      ORGANIZATION_SCOPE_HEX = Digest::SHA256.hexdigest("scope:organization")

      Result = Data.define(:allowed, :reason, :decision) do
        def allowed? = allowed
      end

      # `authorizer` is a CommandAuthorizer, `actor` an AuthenticatedActor.
      def evaluate(authorizer:, actor:, now:, canonical_role:, scope_hex:, direct: true)
        decision = authorizer.authorize(actor:, capability: CAPABILITY, now:)
        return Result.new(allowed: false, reason: decision.reason, decision:) unless decision.allowed?

        unless contains_scope?(decision.granting, scope_hex)
          return Result.new(allowed: false, reason: "grant_scope_exceeded", decision:)
        end

        if direct && Platform::PermissionBaseline.protected_role?(canonical_role)
          return Result.new(allowed: false, reason: "invitation_approval_required", decision:)
        end

        Result.new(allowed: true, reason: "authorized", decision:)
      end

      # Does any granting Assignment's scope contain the offered scope?
      def contains_scope?(granting, scope_hex)
        granting.any? do |assignment|
          own = assignment["scope_hex"]
          own.nil? || own == ORGANIZATION_SCOPE_HEX || own == scope_hex
        end
      end
    end
  end
end
