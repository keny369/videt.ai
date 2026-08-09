# frozen_string_literal: true

# The local-presence half of both Project-creation forms: WEB-003
# `/start/bootstrap-organization` (FRONTEND_ARCHITECTURE.md :51) and WEB-012
# `/app/projects/new` (:63). Shared for the same reason the two paths share
# `Workflows::Wf002::ProjectCreation` — two screens that ask the same ratified
# question must not drift into asking it two ways.
#
# WORKFLOW_SPECIFICATIONS.md :657 gives `local_presence_applicable` two branches.
# Until now neither screen offered the true one, so a business that does trade from
# premises could register only by declaring, in its own words, that it does not.
# Both branches are offered here.
#
# Three things this deliberately does not do, because SCORE_EVIDENCE_MODEL.md :587
# reserves the decision to an OrganizationAdmin or MarketingOperator:
#
#   * applicability is never derived from whether an address was typed. The control
#     has NO default and NO preselection, so an unanswered form carries applicability
#     `nil` — which the workflow refuses as `project_local_applicability_invalid`.
#     Silence is not a `false`, at the form layer as well as below it.
#   * the reason text is never composed, defaulted or suggested. It is quoted back to
#     the registrant on redisplay and otherwise passes through untouched.
#   * `Applicability#local_presence_entry` is not relaxed. A Project with no profile
#     or no reason still reads as no decision rather than as a false one.
#
# The business name is not a control. :657 requires it to equal the exact normalized
# Organization display name and the handler cross-checks it, so the screen supplies
# that name; asking for it again could only manufacture a refusal.
module LocalPresenceForm
  APPLICABILITY_MESSAGE = "Choose whether this project has a local presence."
  ADDRESS_MESSAGE = "Enter the address customers visit, 1 to 500 characters."
  TELEPHONE_MESSAGE = "Enter the telephone number in international format, such as +61390000000."
  SERVICE_AREAS_MESSAGE = "Enter 1 to 50 distinct service areas, one per line, each 1 to 120 characters."

  private

  def creation = Workflows::Wf002::ProjectCreation

  # Reads the controls into instance variables so a rejected submission redisplays
  # exactly what was typed. `local_presence_applicable` maps only the two exact
  # strings the radio group emits; every other value — including its absence — is
  # `nil`, meaning unanswered.
  def assign_local_presence_form
    @local_presence_applicable =
      case params[:local_presence_applicable].to_s
      when "true" then true
      when "false" then false
      end
    @local_presence_reason = params[:local_presence_reason].to_s.strip
    @local_presence_address = params[:local_presence_address].to_s.strip
    @local_presence_telephone = params[:local_presence_telephone].to_s.strip
    @local_presence_service_areas = params[:local_presence_service_areas].to_s
  end

  # Field-level validation before a command is built. The workflow validates all of
  # this again and remains the authority; checking here is only so the form can point
  # at the offending control instead of showing a committed failure. Each predicate
  # delegates to the shared validator rather than restating its rule.
  def local_presence_field_errors
    return { local_presence_applicable: APPLICABILITY_MESSAGE } if @local_presence_applicable.nil?
    return local_presence_profile_errors if @local_presence_applicable

    return {} unless creation.normalized_reason(@local_presence_reason).nil?

    { local_presence_reason: "Enter a reason of #{creation::REASON_MIN} to #{creation::REASON_MAX} characters." }
  end

  def local_presence_profile_errors
    errors = {}
    errors[:local_presence_address] = ADDRESS_MESSAGE if creation.normalized_address(@local_presence_address).nil?
    errors[:local_presence_telephone] = TELEPHONE_MESSAGE unless
      @local_presence_telephone.match?(creation::TELEPHONE_E164)
    errors[:local_presence_service_areas] = SERVICE_AREAS_MESSAGE if
      creation.normalized_service_areas(local_presence_service_area_list).nil?
    errors
  end

  # The three `project-profile-v1` members that carry the decision, for the given
  # exact Organization display name.
  #
  # An unanswered applicability is passed through as `nil`, not silently rendered as
  # `false`. That is the structural guarantee: even a caller that forgot to check
  # `local_presence_field_errors` cannot turn silence into a declared inapplicability
  # — the workflow refuses the command instead.
  def local_presence_profile_fields(business_name)
    return local_presence_fields_for_profile(business_name) if @local_presence_applicable == true

    {
      "local_presence_applicable" => @local_presence_applicable,
      "local_presence_reason" => (@local_presence_reason if @local_presence_applicable == false),
      "local_business_profile" => nil
    }
  end

  def local_presence_fields_for_profile(business_name)
    {
      "local_presence_applicable" => true,
      # ":657 When true, the reason is null".
      "local_presence_reason" => nil,
      "local_business_profile" => {
        "schema_version" => creation::LOCAL_BUSINESS_PROFILE_SCHEMA_VERSION,
        "business_name" => business_name,
        "address_text" => @local_presence_address,
        "telephone_e164" => @local_presence_telephone,
        "service_areas" => local_presence_service_area_list
      }
    }
  end

  # One service area per line, in whatever order the registrant thought of them.
  #
  # :657 requires the array to arrive sorted by UTF-8 bytes, which no human types
  # unaided, so the screen sorts it. Sorting is transport normalization of the same
  # kind as NFC and trimming: it adds no area and removes none, and the set remains
  # exactly the one that was entered. A duplicate or an oversized member is NOT
  # quietly dropped — the list is handed to the shared validator as typed and comes
  # back as a field error.
  def local_presence_service_area_list
    entered = @local_presence_service_areas.to_s.split("\n").map(&:strip).reject(&:empty?)
    normalized = entered.map { |area| creation.normalized_name(area) }
    return entered if normalized.any?(&:nil?)

    normalized.sort_by(&:b)
  end
end
