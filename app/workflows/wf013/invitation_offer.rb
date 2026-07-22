# frozen_string_literal: true

require "digest"

module Workflows
  module Wf013
    # The offer an Invitation carries, and the two derived values the ratified
    # contract requires from it.
    #
    # PROTECTED-PERMISSION PREVIEW (:240 "exact protected-permission preview",
    # :242 "A nonprotected invitation is created directly active; a protected
    # invitation starts pending approval"). The preview is derived from the
    # offered canonical role through the ratified protected-grant enumeration in
    # `Platform::PermissionBaseline`; the caller never states whether its offer is
    # protected, so it cannot choose the branch.
    #
    # OPEN-INVITATION UNIQUENESS PREIMAGE (:244 "Organization, target-email
    # digest, target identity when bound, canonical role, permission mode/persona,
    # normalized scope, protected-permission preview, and intended Assignment
    # expiry. At most one pending-approval or active Invitation exists for that
    # full preimage."). Exactly those eight fields, canonically encoded, and
    # nothing else — no clock, no requester, no correlation id — so the same offer
    # always produces the same digest and the partial unique index can enforce the
    # rule at the database boundary.
    module InvitationOffer
      module_function

      # ":314 `standard` permits a null persona for any canonical role or persona
      # `consultant` only with OrganizationAdmin, MarketingOperator, or
      # TechnicalImplementer. `read_only` permits only MarketingOperator with
      # persona `executive_buyer`. Every other role/mode/persona tuple is
      # `role_mode_invalid`."
      CANONICAL_ROLES = %w[OrganizationAdmin MarketingOperator TechnicalImplementer
                           SecurityOperator BillingOperator].freeze
      CONSULTANT_ROLES = %w[OrganizationAdmin MarketingOperator TechnicalImplementer].freeze

      def valid_tuple?(canonical_role:, permission_mode:, persona:)
        return false unless CANONICAL_ROLES.include?(canonical_role)

        case permission_mode
        when "standard"
          persona.nil? || (persona == "consultant" && CONSULTANT_ROLES.include?(canonical_role))
        when "read_only"
          canonical_role == "MarketingOperator" && persona == "executive_buyer"
        else
          false
        end
      end

      def protected_permission_preview(canonical_role)
        Platform::PermissionBaseline.protected_permission_preview(canonical_role)
      end

      def protected?(canonical_role) = Platform::PermissionBaseline.protected_role?(canonical_role)

      # The 32-byte open-invitation uniqueness digest.
      def uniqueness_digest(organization_id:, target_email_sha256:, target_identity_issuer_key:,
                            target_identity_subject:, canonical_role:, permission_mode:, persona:,
                            scope_sha256:, intended_assignment_expires_at:)
        Platform::CanonicalJson.digest(
          "canonical_role" => canonical_role,
          "intended_assignment_expires_at" => instant(intended_assignment_expires_at),
          "organization_id" => organization_id,
          "permission_mode" => permission_mode,
          "persona" => persona,
          "protected_permission_preview" => protected_permission_preview(canonical_role),
          "scope_sha256" => hex(scope_sha256),
          "target_email_sha256" => hex(target_email_sha256),
          "target_identity_issuer_key" => target_identity_issuer_key,
          "target_identity_subject" => target_identity_subject
        )
      end

      # ":240 normalized target email and its SHA-256 digest". Normalization is
      # trim plus Unicode NFC plus lowercase; anything without a single `@`
      # between non-empty parts is an input-shape failure.
      def normalize_email(raw)
        return nil if raw.nil?

        value = raw.to_s.strip.unicode_normalize(:nfc).downcase
        local, domain, extra = value.split("@", 3)
        return nil if extra || local.nil? || domain.nil? || local.empty? || domain.empty?
        return nil unless domain.include?(".")

        value
      end

      def hex(bytes) = bytes && bytes.unpack1("H*")
      def instant(time) = time && time.getutc.floor(6).iso8601(6)
    end
  end
end
