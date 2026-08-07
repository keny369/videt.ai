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
      @project_objective = ""
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
      @project_objective = params[:project_objective].to_s.strip
    end

    # Field validation before a command is built. WF-001 validates these too and is the
    # authority; checking here is only so the form can point at the offending control
    # instead of showing a committed failure.
    def form_invalid?
      @field_errors = {}
      @field_errors[:organization_display_name] = "Enter a name of 1 to 120 characters." unless
        display_name_ok?(@organization_display_name)
      @field_errors[:project_display_name] = "Enter a name of 1 to 120 characters." unless
        display_name_ok?(@project_display_name)
      @field_errors.any?
    end

    def display_name_ok?(value)
      length = value.to_s.unicode_normalize(:nfc).strip.length
      length.between?(1, Platform::BaselineContent::DISPLAY_NAME_MAX)
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
        project_display_name: @project_display_name,
        project_objective: @project_objective.presence,
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
