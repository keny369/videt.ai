# frozen_string_literal: true

module Start
  # Shared plumbing for the receipt-entry screens (WEB-001..WEB-004). No Session exists
  # on these routes, so nothing here authenticates or authorizes; what it does is obtain
  # the Identity Validation Receipt a WF-001 command requires, and remember which
  # identity the flow is for between the grant step and the bootstrap step.
  class BaseController < ApplicationController
    # The identity being onboarded, carried across the two-step bootstrap. Signed, so
    # the browser cannot substitute another address and land on someone else's grant.
    # It holds an email and nothing else: no permission, no tenant record, no receipt.
    IDENTITY_COOKIE = :f1_start_identity
    # The Organization this browser last created, so signing in again on the same machine
    # can prefill the identifier the form requires. It is a convenience only: it confers
    # nothing, and the sign-in command still names its Organization and is refused unless
    # the receipt resolves an active Account inside it.
    ORGANIZATION_COOKIE = :f1_start_organization

    # The managed identity provider is not provisioned in this build
    # (INTEGRATION_CONTRACTS.md :250 fixes it to an external signed-artifact flow), so
    # locally the receipt comes from the development issuer. Outside a local
    # environment there is no substitute and the screen says so rather than pretending.
    before_action :require_identity_issuer

    private

    def require_identity_issuer
      return if F1::LocalIdentityIssuer.available?

      render "start/identity_unavailable", status: :service_unavailable
    end

    def mint_receipt(email:, purpose:)
      F1::LocalIdentityIssuer.mint(email:, purpose:)
    end

    def remembered_email = cookies.signed[IDENTITY_COOKIE].presence

    def remember_email(email)
      cookies.signed[IDENTITY_COOKIE] = {
        value: email, secure: true, httponly: true, same_site: :lax, path: "/"
      }
    end

    def forget_email = cookies.delete(IDENTITY_COOKIE, path: "/")

    def remembered_organization_id = cookies.signed[ORGANIZATION_COOKIE].presence

    def remember_organization(organization_id)
      cookies.signed[ORGANIZATION_COOKIE] = {
        value: organization_id, secure: true, httponly: true, same_site: :lax, path: "/"
      }
    end

    # WF-001 grant and bootstrap run as the approved identity/bootstrap service: there
    # is no tenant actor yet to attribute them to.
    def service_context
      Platform::RequestContext.for_service(
        service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
        correlation_id: correlation_id
      )
    end

    def valid_email?(value) = value.to_s.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)

    # Turn a committed failure into something the screen can say. The reason code is the
    # workflow's, never one the controller invents: APPLICATION_LAYER.md :98 forbids a
    # controller rescuing its way to a reason of its own.
    def failure_message(result)
      Start::FAILURE_MESSAGES.fetch(result.reason_code, nil) ||
        "That could not be completed (#{result.reason_code}). Support reference #{correlation_id}."
    end
  end

  # Deterministic, human-authored text for the reason codes this flow can actually
  # produce. Anything unmapped falls back to the raw code plus a support reference,
  # which is honest rather than reassuring.
  FAILURE_MESSAGES = {
    "bootstrap_grant_already_issued" => "A bootstrap grant is already open for this address. Continue below.",
    "bootstrap_grant_unavailable" => "No open bootstrap grant for this address. Start again.",
    "bootstrap_grant_consumed" => "This address has already created an organization. Sign in instead.",
    "bootstrap_grant_expired" => "That bootstrap grant expired. Start again.",
    "identity_receipt_expired" => "That took too long to confirm. Start again.",
    "identity_email_unverified" => "That address is not verified.",
    "organization_profile_invalid" => "Enter an organization name between 1 and 120 characters.",
    "project_body_invalid" => "Enter a project name between 1 and 120 characters.",
    "account_not_found" => "No account for that address. Create an organization instead.",
    "organization_inactive" => "That organization is not active.",
    "account_inactive" => "That account is not active."
  }.freeze
end
