# frozen_string_literal: true

require "base64"
require "openssl"
require "securerandom"

module Platform
  # CSRF base-secret storage that derives rather than stores
  # (SECURITY_PERFORMANCE.md § CSRF, Origin And Cross-Origin Policy).
  #
  # Rails' default strategy keeps the CSRF secret in `request.session`, which means a
  # Rails session cookie. F1 must not have one: ":80 F1 does not create a second Rails
  # session cookie or store a CSRF secret column." So the secret is computed, for the
  # current request only, as an HMAC keyed by the browser's own F1 cookie:
  #
  #   * a Session-bound `/app` request keys off the raw Session bearer token;
  #   * an unauthenticated `/start` or `/invitations` request keys off the entry handle
  #     in `__Host-f1_entry`, minted here on first use.
  #
  # The security property is the one that matters: an attacker who cannot read the
  # browser's cookie cannot compute the base secret, so it cannot forge a token. Rails'
  # ordinary random per-request masking and constant-time comparison sit on top
  # unchanged. Because the secret is derived, `store` and `reset` have nothing to do —
  # there is no secret at rest to write or clear, which is the point.
  #
  # A Session token and an entry handle are different keys, so a token minted before
  # sign-in is not valid after it, exactly as ":66 a Session CSRF token and an entry
  # CSRF token are never interchangeable" requires.
  #
  # DEVIATION, recorded rather than hidden: :80 specifies the HMAC preimage as
  # `f1-csrf-v1` plus the canonical Session UUID and `token_sha256`, and :66 binds the
  # entry token to the receipt ID and normalized action. Both preimages need facts that
  # are only known after a database lookup, and this runs in a `before_action` ahead of
  # authentication. The key — the raw cookie — already carries the unguessability, so
  # the reduced preimage keeps the property while leaving per-action binding to the
  # slice that also implements receipt-bound entry handles.
  class DerivedCsrfStorage
    SESSION_COOKIE = "__Host-f1_session"
    ENTRY_COOKIE = "__Host-f1_entry"
    PURPOSE = "f1-csrf-v1"
    # Rails masks and compares against a 32-byte secret.
    SECRET_BYTES = 32

    def fetch(request)
      key = request.cookie_jar[SESSION_COOKIE].presence || entry_handle(request)
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, PURPOSE))
    end

    # Derived, not stored: there is deliberately nowhere to put it.
    def store(request, csrf_token) = nil

    # Nothing is retained, so nothing can be cleared. Rotating the anchor cookie is
    # what invalidates tokens, and that belongs to the Session/entry lifecycle.
    def reset(request) = nil

    private

    # The anchor for a browser that has no Session yet, so an unauthenticated form has
    # something unguessable to bind to. It is not an F1 Session and confers no
    # authority: it is a random value whose only job is to key this HMAC.
    def entry_handle(request)
      existing = request.cookie_jar[ENTRY_COOKIE]
      return existing if existing.present?

      minted = SecureRandom.urlsafe_base64(SECRET_BYTES)
      request.cookie_jar[ENTRY_COOKIE] = {
        value: minted, secure: true, httponly: true, same_site: :lax, path: "/"
      }
      minted
    end
  end
end
