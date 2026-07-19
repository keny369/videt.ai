# frozen_string_literal: true

module IdentityAccess
  module Domain
    # A Bootstrap Grant (onboarding-interim-v1). This slice issues it; consumption
    # and expiry are separate WF-001 operations. Pure value: the issue instant is
    # supplied, and the 15-minute expiry is derived from it.
    class BootstrapGrant
      ALLOWED_ACTION = "organization.bootstrap"
      LIFETIME_SECONDS = 15 * 60

      attr_reader :id, :bootstrap_principal_digest, :allowed_action, :issuer_service_identity_id,
                  :policy_version, :issued_at, :expires_at, :state, :state_version,
                  :correlation_id, :causation_id, :command_id

      def self.issue(id:, bootstrap_principal_digest:, issuer_service_identity_id:, policy_version:,
                     issued_at:, correlation_id:, causation_id:, command_id:)
        new(
          id:, bootstrap_principal_digest:, allowed_action: ALLOWED_ACTION,
          issuer_service_identity_id:, policy_version:, issued_at:,
          expires_at: issued_at + LIFETIME_SECONDS, state: "issued", state_version: 0,
          correlation_id:, causation_id:, command_id:
        )
      end

      def initialize(id:, bootstrap_principal_digest:, allowed_action:, issuer_service_identity_id:,
                     policy_version:, issued_at:, expires_at:, state:, state_version:,
                     correlation_id:, causation_id:, command_id:)
        @id = id
        @bootstrap_principal_digest = bootstrap_principal_digest
        @allowed_action = allowed_action
        @issuer_service_identity_id = issuer_service_identity_id
        @policy_version = policy_version
        @issued_at = issued_at
        @expires_at = expires_at
        @state = state
        @state_version = state_version
        @correlation_id = correlation_id
        @causation_id = causation_id
        @command_id = command_id
        freeze
      end
    end
  end
end
