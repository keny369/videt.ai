# frozen_string_literal: true

# The transport base. It owns exactly two things: the browser-facing security posture
# that every response must carry, and the cookie mechanics for the Session bearer
# token. It deliberately owns no notion of "the current user" — that is
# Platform::AuthenticatedRequest's, and a controller that could answer it independently
# would be a second authentication path.
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  # ":38 __Host-f1_session", ":41 SameSite=Lax". The `__Host-` prefix is not decoration:
  # it makes the browser refuse the cookie unless it is Secure, host-only (no Domain)
  # and Path=/, which is what stops a sibling subdomain from setting a Session for us.
  SESSION_COOKIE = "__Host-f1_session"

  # ":235 Protected HTML, Turbo and JSON responses use `Cache-Control: private, no-store`."
  # A shared cache or a restored history entry must never serve one tenant's page to the
  # next reader.
  before_action :set_security_headers

  private

  def set_security_headers
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "same-origin"
  end

  def session_token = cookies[SESSION_COOKIE]

  # Set once, when a WF-001 branch has committed a Session. `secure: true` holds in
  # development too: browsers treat localhost as a trustworthy origin, so the
  # `__Host-` prefix works over http://localhost without relaxing the attribute.
  def establish_session(raw_token)
    cookies[SESSION_COOKIE] = {
      value: raw_token, secure: true, httponly: true, same_site: :lax, path: "/"
    }
  end

  def clear_session_cookie = cookies.delete(SESSION_COOKIE, path: "/")

  # The single way a protected action reaches the domain. `capability` is the exact
  # permission the route declares. On refusal this renders and halts, so a caller that
  # forgets to check the return value still cannot proceed unauthorized.
  def authorize!(capability, resource: nil, &block)
    outcome = Platform::AuthenticatedRequest.call(
      token: session_token, capability:, correlation_id: correlation_id, resource:, &block
    )
    return outcome if outcome.authorized?

    deny(outcome)
    nil
  end

  def deny(outcome)
    if outcome.unauthenticated?
      clear_session_cookie
      redirect_to start_sign_in_path, status: :see_other,
                  alert: "Please sign in to continue."
    else
      render "shared/forbidden", status: :forbidden,
             locals: { reason: outcome.reason, support_reference: correlation_id }
    end
  end

  # One correlation id per request, tying the command, result, audit record, events and
  # authorization decision together, and shown to the user as the support reference.
  def correlation_id
    @correlation_id ||= request.request_id.presence || SecureRandom.uuid_v7
  end
end
