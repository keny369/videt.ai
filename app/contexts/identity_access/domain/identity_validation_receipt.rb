# frozen_string_literal: true

module IdentityAccess
  module Domain
    # The Identity Validation Receipt as WF-001 sees it after the identity service
    # has cryptographically validated it (onboarding-interim-v1). A pure value: it
    # reads no repository, clock or global state — the current instant is passed
    # in — so its first-match validation is deterministically testable.
    class IdentityValidationReceipt
      SUPPORTED_SCHEMA = "onboarding-interim-v1"
      # Interim approved managed-identity issuer set. A receipt from any other
      # issuer is unsupported (the identity service itself is upstream of F1).
      APPROVED_ISSUERS = ["https://id.example/oidc"].freeze

      attr_reader :receipt_id, :purpose, :validated_at, :expires_at, :email_verified,
                  :issuer_key, :schema_version, :bootstrap_principal_digest, :context_org

      def initialize(receipt_id:, purpose:, validated_at:, expires_at:, email_verified:,
                     issuer_key:, schema_version:, bootstrap_principal_digest:, context_org:)
        @receipt_id = receipt_id
        @purpose = purpose
        @validated_at = validated_at
        @expires_at = expires_at
        @email_verified = email_verified
        @issuer_key = issuer_key
        @schema_version = schema_version
        @bootstrap_principal_digest = bootstrap_principal_digest
        @context_org = context_org
        freeze
      end

      # First-match onboarding-interim-v1 reason, or nil when acceptable. Order is
      # the contract's: unsupported issuer/schema, wrong purpose, unverified email,
      # expiry. Signature and changed-digest are the identity service's / the
      # lookup's concern (an unresolved digest is identity_receipt_invalid).
      # At expiry equality, expiry wins: acceptance must commit strictly before.
      def grant_request_reason(now_utc:)
        return "identity_issuer_unsupported" unless APPROVED_ISSUERS.include?(issuer_key)
        return "identity_schema_unsupported" unless schema_version == SUPPORTED_SCHEMA
        return "identity_receipt_purpose_mismatch" unless purpose == "bootstrap_grant_request"
        return "identity_email_unverified" unless email_verified
        return "identity_receipt_expired" if now_utc >= expires_at

        nil
      end
    end
  end
end
