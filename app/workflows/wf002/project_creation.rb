# frozen_string_literal: true

module Workflows
  module Wf002
    # Shared, bounded Project-creation support for WF-002 (WORKFLOW_SPECIFICATIONS.md
    # :657; API_CONTRACTS.md `ProjectProfile`/`LocalBusinessProfile` :371-372;
    # contracts/S-03.json MTX-027, MTX-054). It owns the exact normalization and
    # the first-match validation of the `project-profile-v1` body and its immutable
    # `local-business-profile-v1`, plus the SHA-256 of the canonical profile
    # content. It performs NO authorization, NO persistence and NO Source read; the
    # handler runs it before it opens or commits its transaction.
    #
    # The Organization-display-name cross-check — the Local Business Profile's
    # business name must equal the exact normalized Organization display name — is
    # intrinsically Organization-dependent and so is applied by the handler after
    # authentication via `business_name_matches?`; every other predicate here is
    # decided from the caller's input alone, which is what lets the eight profile
    # reasons precede the authentication/authorization reasons in the first-match
    # order without reading any tenant state.
    module ProjectCreation
      module_function

      SCHEMA_MAJOR = "1"
      PROFILE_SCHEMA_VERSION = "project-profile-v1"
      LOCAL_BUSINESS_PROFILE_SCHEMA_VERSION = "local-business-profile-v1"
      # WF-002 fixes these three; they are independent of the frozen
      # `organization-profile-v1` values that happen to coincide.
      DEFAULT_LOCALE = "en-AU"
      REPORTING_TIME_ZONE = "UTC"
      OBJECTIVE = "discoverability_assessment"
      DISPLAY_NAME_MAX = 120
      REASON_MIN = 20
      REASON_MAX = 500
      ADDRESS_MAX = 500
      SERVICE_AREA_MAX = 120
      SERVICE_AREAS_MAX = 50
      TELEPHONE_E164 = /\A\+[1-9][0-9]{7,14}\z/
      WHITESPACE = /\p{White_Space}/

      Outcome = Data.define(:reason, :profile) do
        def ok? = reason.nil?
      end

      def ok(profile) = Outcome.new(reason: nil, profile:)
      def bad(reason) = Outcome.new(reason:, profile: nil)

      def supported_schema?(version) = version.to_s.split(".").first == SCHEMA_MAJOR

      # First-match validation and normalization of the caller's ProjectProfile,
      # decided from the input alone, in the exact WF-002 creation order. Returns
      # an Outcome carrying either the first-match reason or the fully normalized
      # profile ready for persistence.
      def validate(raw)
        return bad("project_schema_unsupported") unless raw.is_a?(::Hash)
        return bad("project_schema_unsupported") unless raw["project_profile_schema_version"] == PROFILE_SCHEMA_VERSION

        display_name = normalized_name(raw["display_name"])
        return bad("project_display_name_invalid") if display_name.nil?
        return bad("project_locale_unsupported") unless raw["default_locale"] == DEFAULT_LOCALE
        return bad("project_time_zone_unsupported") unless raw["reporting_time_zone"] == REPORTING_TIME_ZONE

        applicable = raw["local_presence_applicable"]
        return bad("project_local_applicability_invalid") unless [true, false].include?(applicable)

        reason_text = nil
        profile_lbp = nil
        if applicable
          # ":657 When true, the reason is null and local_business_profile is required".
          return bad("project_local_reason_invalid") unless raw["local_presence_reason"].nil?

          profile_lbp = normalized_local_business_profile(raw["local_business_profile"])
          return bad("project_local_profile_invalid") if profile_lbp.nil?
        else
          # ":657 When local presence is false, local_presence_reason is 20-500 ...
          # and local_business_profile is null."
          reason_text = normalized_reason(raw["local_presence_reason"])
          return bad("project_local_reason_invalid") if reason_text.nil?
          return bad("project_local_profile_invalid") unless raw["local_business_profile"].nil?
        end

        return bad("project_objective_unsupported") unless raw["objective"] == OBJECTIVE

        ok(
          "project_profile_schema_version" => PROFILE_SCHEMA_VERSION,
          "display_name" => display_name,
          "default_locale" => DEFAULT_LOCALE,
          "reporting_time_zone" => REPORTING_TIME_ZONE,
          "objective" => OBJECTIVE,
          "local_presence_applicable" => applicable,
          "local_presence_reason" => reason_text,
          "local_business_profile" => profile_lbp
        )
      end

      # The 32-byte SHA-256 of the canonical `local-business-profile-v1` content,
      # or nil when the profile carries a local-presence reason instead.
      def content_sha256(normalized)
        lbp = normalized["local_business_profile"]
        lbp && Platform::CanonicalJson.digest(lbp)
      end

      # Organization-dependent: the business name must equal the exact normalized
      # Organization display name. Vacuously true when there is no Local Business
      # Profile (the local-presence-reason branch).
      def business_name_matches?(normalized, organization_display_name)
        lbp = normalized["local_business_profile"]
        return true if lbp.nil?

        expected = normalized_name(organization_display_name)
        !expected.nil? && lbp["business_name"] == expected
      end

      # Display-name rule: Unicode NFC, leading/trailing Unicode whitespace trimmed,
      # 1..120 Unicode scalar values. Returns the normalized value or nil.
      def normalized_name(value)
        return nil unless value.is_a?(::String)

        name = trim(value.unicode_normalize(:nfc))
        return nil unless name.length.between?(1, DISPLAY_NAME_MAX)

        name
      end

      # Local-presence reason: Unicode NFC, trimmed, 20..500 scalar values.
      def normalized_reason(value)
        return nil unless value.is_a?(::String)

        reason = trim(value.unicode_normalize(:nfc))
        return nil unless reason.length.between?(REASON_MIN, REASON_MAX)

        reason
      end

      # address_text: Unicode NFC, internal Unicode whitespace collapsed to one
      # ASCII space, trimmed, 1..500 scalar values.
      def normalized_address(value)
        return nil unless value.is_a?(::String)

        address = trim(value.unicode_normalize(:nfc)).gsub(WHITESPACE, " ").squeeze(" ")
        return nil unless address.length.between?(1, ADDRESS_MAX)

        address
      end

      # service_areas: 1..50 distinct strings, each normalized by the display-name
      # rule to 1..120 scalar values, and already sorted by UTF-8 bytes. A
      # duplicate, an over-count, an out-of-order set or an invalid member is
      # rejected (returns nil).
      def normalized_service_areas(value)
        return nil unless value.is_a?(::Array)
        return nil unless value.length.between?(1, SERVICE_AREAS_MAX)

        areas = value.map { |a| normalized_name(a) }
        return nil if areas.any?(&:nil?) || areas.any? { |a| a.length > SERVICE_AREA_MAX }
        return nil unless areas.uniq.length == areas.length
        return nil unless areas == areas.sort_by(&:b)

        areas
      end

      def normalized_local_business_profile(raw)
        return nil unless raw.is_a?(::Hash)
        return nil unless raw["schema_version"] == LOCAL_BUSINESS_PROFILE_SCHEMA_VERSION

        business_name = normalized_name(raw["business_name"])
        address_text = normalized_address(raw["address_text"])
        telephone = raw["telephone_e164"]
        service_areas = normalized_service_areas(raw["service_areas"])
        return nil if business_name.nil? || address_text.nil? || service_areas.nil?
        return nil unless telephone.is_a?(::String) && telephone.match?(TELEPHONE_E164)

        {
          "schema_version" => LOCAL_BUSINESS_PROFILE_SCHEMA_VERSION,
          "business_name" => business_name, "address_text" => address_text,
          "telephone_e164" => telephone, "service_areas" => service_areas
        }
      end

      def trim(string) = string.sub(/\A\p{White_Space}+/, "").sub(/\p{White_Space}+\z/, "")
    end
  end
end
