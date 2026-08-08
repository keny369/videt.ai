# frozen_string_literal: true

module Start
  # WEB-003 `/start/bootstrap-organization` (FRONTEND_ARCHITECTURE.md :51): render and
  # submit the Organization plus first-Project body.
  #
  # Step two of the bootstrap. The whole tenant genesis commits atomically inside
  # WF-001 — Organization, Account, BillingEntity, the first OrganizationAdmin
  # Assignment, both baseline policies, the Plan Assignment, the draft Project and the
  # Session — so this controller submits one command and does nothing else. On success
  # a Session exists, and the only thing left for the transport to do is put its bearer
  # token in the cookie.
  class OrganizationsController < BaseController
    before_action :require_remembered_identity

    def new
      @organization_display_name = ""
      @project_display_name = ""
      @local_presence_reason = ""
    end

    def create
      assign_form
      return render(:new, status: :unprocessable_content) if form_invalid?

      receipt = mint_receipt(email: @email, purpose: "self_service_bootstrap")
      result = bootstrap(receipt)

      if result.success?
        complete(result)
      else
        @error = failure_message(result)
        render :new, status: :unprocessable_content
      end
    end

    private

    def require_remembered_identity
      @email = remembered_email
      return if @email.present?

      redirect_to start_bootstrap_grant_path, status: :see_other,
                  alert: "Confirm your email address first."
    end

    def assign_form
      @organization_display_name = params[:organization_display_name].to_s.strip
      @project_display_name = params[:project_display_name].to_s.strip
      @local_presence_reason = params[:local_presence_reason].to_s.strip
    end

    # Field validation before a command is built. WF-001 validates these too and is the
    # authority; checking here is only so the form can point at the offending control
    # instead of showing a committed failure.
    def form_invalid?
      creation = Workflows::Wf002::ProjectCreation
      @field_errors = {}
      @field_errors[:organization_display_name] = "Enter a name of 1 to 120 characters." unless
        display_name_ok?(@organization_display_name)
      @field_errors[:project_display_name] = "Enter a name of 1 to 120 characters." unless
        display_name_ok?(@project_display_name)
      @field_errors[:local_presence_reason] =
        "Enter a reason of #{creation::REASON_MIN} to #{creation::REASON_MAX} characters." if
        creation.normalized_reason(@local_presence_reason).nil?
      @field_errors.any?
    end

    def display_name_ok?(value)
      length = value.to_s.unicode_normalize(:nfc).strip.length
      length.between?(1, Platform::BaselineContent::DISPLAY_NAME_MAX)
    end

    # The complete `project-profile-v1` body :621 requires of the self-service branch.
    # The locale, time zone and objective are fixed by the ratified profile rather than
    # offered as choices, so the form asks only for what the schema leaves open.
    #
    # As on the WF-002 screen, this slice creates the genesis Project without a
    # local-presence claim: the branch that asserts one requires a complete
    # local-business-profile body, which has no form yet on either path. Declaring false
    # with a stated reason is the honest half, and it is the half that lets `CHK-LP-001`
    # reach `not_applicable` instead of erroring on an absent profile. The reason is the
    # registrant's own words; nothing here derives it.
    def first_project
      creation = Workflows::Wf002::ProjectCreation
      {
        "project_profile_schema_version" => creation::PROFILE_SCHEMA_VERSION,
        "display_name" => @project_display_name,
        "default_locale" => creation::DEFAULT_LOCALE,
        "reporting_time_zone" => creation::REPORTING_TIME_ZONE,
        "objective" => creation::OBJECTIVE,
        "local_presence_applicable" => false,
        "local_presence_reason" => @local_presence_reason,
        "local_business_profile" => nil
      }
    end

    def bootstrap(receipt)
      baseline = Platform::BaselineContent
      command = Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest],
        # A freshly issued grant is at version 0. A mismatch is reported as
        # `stale_state_version` rather than guessed at, which is the correct outcome:
        # the grant moved under us and the caller must re-read it.
        expected_grant_version: 0,
        organization_display_name: @organization_display_name,
        first_project: first_project,
        # The caller states which baseline content it approves; it never chooses the
        # content. A mismatch is a refusal, not a silent substitution.
        access_policy_content_sha256: baseline.access_policy_sha256,
        entitlement_policy_content_sha256: baseline.entitlement_policy_sha256,
        plan_content_sha256: baseline.plan_sha256,
        requested_at_utc: Time.now.utc
      )
      Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command:, request_context: service_context)
    end

    def complete(result)
      token = result.session_token
      # A replayed result carries no plaintext token by design, so there is nothing to
      # put in the cookie and the honest move is to sign in rather than pretend.
      if token.nil?
        forget_email
        return redirect_to(start_sign_in_path, status: :see_other,
                           notice: "That organization already exists. Sign in to continue.")
      end

      establish_session(token.raw)
      forget_email
      # Remembered so a later sign-in on this machine can prefill the identifier the form
      # requires; it grants nothing on its own.
      remember_organization(result.payload[:organization_id])
      redirect_to app_home_path, status: :see_other
    end
  end
end
