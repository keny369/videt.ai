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
    # invitation.revoke is NOT a protected permission (:333 omits it), so no
    # protected-allowlist or dual-control gate applies.
    CAPABILITIES = {
      "invitation.revoke" => %w[OrganizationAdmin].freeze
    }.freeze

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
