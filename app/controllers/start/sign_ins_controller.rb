# frozen_string_literal: true

module Start
  # WEB-001 `/start/sign-in` (FRONTEND_ARCHITECTURE.md :49): initiate managed-identity
  # validation for an existing Account.
  #
  # The Organization is submitted explicitly. WF-001 "is supplied explicitly and never
  # selected implicitly", and there is no directory lookup behind this form to soften
  # that: reading which tenants an address belongs to would mean reading across tenants,
  # which row level security correctly forbids. See F1::LocalIdentityIssuer for why that
  # is the right trade rather than an inconvenience worked around.
  class SignInsController < BaseController
    def new
      @email = remembered_email.to_s
      @organization_id = remembered_organization_id.to_s
    end

    def create
      @email = params[:email].to_s.strip
      @organization_id = params[:organization_id].to_s.strip
      return render(:new, status: :unprocessable_content) unless validate

      result = sign_in
      result.success? ? complete(result) : refuse(result)
    end

    private

    def validate
      unless valid_email?(@email)
        @error = "Enter a valid email address."
        return false
      end
      # Rejected here rather than passed to the handler, which would refuse it as a
      # schema failure and say less about what to fix.
      unless @organization_id.match?(/\A[0-9a-fA-F-]{36}\z/)
        @error = "Enter the organization identifier you were given when the organization was created."
        return false
      end
      true
    end

    def sign_in
      receipt = mint_receipt(email: @email, purpose: "existing_account_sign_in")
      command = Workflows::Wf001::Commands::SignInExistingAccount.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        organization_id: @organization_id, receipt_digest: receipt[:receipt_digest],
        requested_at_utc: Time.now.utc
      )
      Workflows::Wf001::Handlers::SignInExistingAccount.new.call(command:, request_context: service_context)
    end

    def complete(result)
      token = result.session_token
      if token.nil?
        @error = "That sign-in could not be completed. Try again."
        return render(:new, status: :unprocessable_content)
      end

      establish_session(token.raw)
      forget_email
      # ":55 an access_unavailable sign-in result overrides every requested target."
      destination = result.payload[:destination] || result.payload["destination"]
      if destination.to_s == "access_unavailable"
        redirect_to app_access_unavailable_path, status: :see_other
      else
        redirect_to app_home_path, status: :see_other
      end
    end

    def refuse(result)
      @error = failure_message(result)
      render :new, status: :unprocessable_content
    end
  end
end
