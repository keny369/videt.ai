# frozen_string_literal: true

module Platform
  # The ratified Permission Baseline (`permission-baseline-v1`,
  # WORKFLOW_SPECIFICATIONS.md § Permission Baseline table :135-141, referenced by
  # the mandatory `access-policy-v1` at :320). It is a fixed data table mapping a
  # canonical capability to the canonical roles the baseline ALLOWS; every other
  # role denies. Only ratified rows this build actually consumes are present —
  # adding a further ratified capability is a data addition here and requires no
  # change to the evaluator's semantics. It is not a policy engine: Access Policy
  # deny-subtraction and protected-permission approval live in the caller and the
  # (deferred) full effective-permission engine.
  module PermissionBaseline
    module_function

    VERSION = "permission-baseline-v1"

    # capability => the canonical roles the baseline allows (WORKFLOW_SPECIFICATIONS.md:140).
    # `invitation.create` and `invitation.revoke` share one baseline row —
    # "allow within the actor's grant authority" for OrganizationAdmin, deny for
    # every other role — and neither is a protected permission (:333 omits both),
    # so no protected-allowlist or dual-control gate applies to them.
    # `invitation.approve` reads "protected explicit grant" for SecurityOperator,
    # so the baseline allow is necessary but not sufficient: see PROTECTED below.
    CAPABILITIES = {
      "invitation.create" => %w[OrganizationAdmin].freeze,
      "invitation.revoke" => %w[OrganizationAdmin].freeze,
      "invitation.approve" => %w[SecurityOperator].freeze,
      # ":138 `organization.suspend`, `organization.reactivate` | allow for own
      # Organization | … | support-session only | …". The SecurityOperator arm is
      # support-session-only and Support Sessions are a later slice, so only the
      # OrganizationAdmin arm is reachable here; neither is a protected permission
      # (:333 omits both), so no protected-allowlist gate applies.
      "organization.suspend" => %w[OrganizationAdmin].freeze,
      "organization.reactivate" => %w[OrganizationAdmin].freeze
    }.freeze

    # The ratified protected-grant enumeration (:331-333 "Grants containing … are
    # protected. … This enumeration is the authority for which grants are
    # protected"), restricted to the permissions that appear in the Permission
    # Baseline table, each mapped to the canonical roles whose baseline cell is
    # anything other than `deny`.
    #
    # This is a transcription of ratified cells, not a policy. It answers exactly
    # one question the Invitation record requires (:240 "exact protected-permission
    # preview"): which protected permissions does a grant of this canonical role
    # contain? A permission is in a role's preview when the enumeration names it
    # AND the baseline cell for that role is not `deny`.
    PROTECTED = {
      "account.delete" => %w[OrganizationAdmin SecurityOperator].freeze,
      "account.revoke" => %w[OrganizationAdmin SecurityOperator].freeze,
      "account.suspend" => %w[OrganizationAdmin SecurityOperator].freeze,
      "credential.revoke" => %w[SecurityOperator].freeze,
      "credential.rotate" => %w[SecurityOperator].freeze,
      "evidence.restricted.read" => %w[OrganizationAdmin SecurityOperator].freeze,
      "evidence.validation.manage" => %w[SecurityOperator].freeze,
      "invitation.approve" => %w[SecurityOperator].freeze,
      "issue.adjudicate" => %w[SecurityOperator].freeze,
      "legal_hold.manage" => %w[SecurityOperator].freeze,
      "policy.access.manage" => %w[OrganizationAdmin SecurityOperator].freeze,
      "policy.export.manage" => %w[OrganizationAdmin SecurityOperator].freeze,
      "role.manage" => %w[OrganizationAdmin SecurityOperator].freeze,
      "security.investigate" => %w[SecurityOperator].freeze,
      "support.session.approve" => %w[SecurityOperator].freeze
    }.freeze

    # The exact protected-permission preview for a grant of `canonical_role`:
    # sorted, and empty for a role that contains none. An Invitation offering a
    # role with a non-empty preview is a protected invitation (:242).
    def protected_permission_preview(canonical_role)
      PROTECTED.select { |_, roles| roles.include?(canonical_role) }.keys.sort.freeze
    end

    def protected_role?(canonical_role) = protected_permission_preview(canonical_role).any?

    # Does this Role Assignment's approved allowlist carry `capability`? Required
    # in addition to the baseline allow when the baseline cell reads "protected
    # explicit grant" (:314 "sorted explicit protected-permission allowlist").
    def protected_grant?(capability, allowlist)
      PROTECTED.key?(capability) && Array(allowlist).include?(capability)
    end

    def known?(capability) = CAPABILITIES.key?(capability)

    # Does the baseline allow `capability` to an actor holding any of `roles`?
    def permits?(capability, roles)
      allowed = CAPABILITIES.fetch(capability) do
        raise Platform::InvariantViolation, "unmapped Permission Baseline capability #{capability.inspect}"
      end
      roles.any? { |role| allowed.include?(role) }
    end
  end
end
