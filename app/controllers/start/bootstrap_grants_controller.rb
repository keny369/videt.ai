# frozen_string_literal: true

module Start
  # WEB-002 `/start/bootstrap-grant` (FRONTEND_ARCHITECTURE.md :50): request or replay a
  # Bootstrap Grant using a fresh purpose-bound receipt.
  #
  # This is step one of two. It proves an identity and opens a grant; it creates no
  # tenant record at all. The Organization is created by WEB-003, under a second,
  # separately minted receipt, which is why an interrupted flow leaves nothing behind.
  class BootstrapGrantsController < BaseController
    def new
      @email = remembered_email
    end

    def create
      @email = params[:email].to_s.strip
      return render(:new, status: :unprocessable_content) unless validate_email

      receipt = mint_receipt(email: @email, purpose: "bootstrap_grant_request")
      result = issue_grant(receipt)

      # An already-open grant is not a failure to the person in front of us: it is the
      # state step two needs. Replaying into the same place is the whole point of an
      # idempotent grant.
      if result.success? || result.reason_code == "bootstrap_grant_already_issued"
        remember_email(@email)
        redirect_to start_bootstrap_organization_path, status: :see_other
      else
        @error = failure_message(result)
        render :new, status: :unprocessable_content
      end
    end

    private

    def validate_email
      return true if valid_email?(@email)

      @error = "Enter a valid email address."
      false
    end

    def issue_grant(receipt)
      command = Workflows::Wf001::Commands::RequestBootstrapGrant.new(
        command_id: SecureRandom.uuid_v7,
        # New identity per attempt: a fresh grant request is a new product attempt, not
        # a retry of the previous one.
        idempotency_key: SecureRandom.uuid_v7,
        schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest],
        requested_at_utc: Time.now.utc
      )
      Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(command:, request_context: service_context)
    end
  end
end
