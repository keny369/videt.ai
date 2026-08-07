# frozen_string_literal: true

require "digest"
require "securerandom"

module Platform
  # The Session bearer token (SECURITY_PERFORMANCE.md :38, schemas :263).
  #
  # A Session id is not a credential: it is returned in command payloads and written
  # into audit, event and result rows. The credential is this separate opaque token.
  # Only its SHA-256 digest is stored, so reading `sessions` yields nothing that can
  # be presented as a live Session.
  #
  # The raw token exists in exactly two places and nowhere else: the value handed
  # back to the transport that sets the cookie, and the cookie itself. It is never a
  # column, a command field, a log line, an audit payload or an event body. In
  # particular it is deliberately NOT part of the logical command: command identity
  # is hashed into `request_sha256`, so a token in the command would make an ordinary
  # retry with a fresh token look like an idempotency conflict.
  module SessionToken
    # 256 bits from the operating-system CSPRNG. urlsafe_base64 keeps the value
    # cookie-safe without encoding, and drops padding, giving 43 characters.
    ENTROPY_BYTES = 32
    DIGEST_BYTES = 32

    module_function

    # A fresh token and the digest to persist. The caller stores `digest` and returns
    # `raw` to the browser exactly once.
    def mint
      raw = SecureRandom.urlsafe_base64(ENTROPY_BYTES)
      Minted.new(raw:, digest: digest_of(raw))
    end

    # The stored form of a presented token. Lookup is by this digest against a UNIQUE
    # index, so there is no candidate set to compare and no timing side channel to
    # close: the database either resolves exactly one Session or none.
    def digest_of(raw) = Digest::SHA256.digest(raw.to_s)

    # A presented cookie value is only worth hashing if it could be one of ours.
    # This rejects absent, truncated and oversized values before they reach the
    # database, and keeps a hostile cookie from becoming a query parameter.
    def plausible?(raw)
      value = raw.to_s
      value.length == expected_length && value.match?(/\A[A-Za-z0-9_-]+\z/)
    end

    def expected_length = SecureRandom.urlsafe_base64(ENTROPY_BYTES).length

    # The minted pair. `inspect`/`to_s` are overridden so the raw token cannot be
    # printed into a log, an exception message or a test failure diff by accident.
    Minted = Data.define(:raw, :digest) do
      def inspect = "#<Platform::SessionToken::Minted [redacted]>"
      def to_s = inspect
    end
  end
end
