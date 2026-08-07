# frozen_string_literal: true

require "digest"
require "securerandom"
require "time"
require "pg"

module F1
  # Stands in for the approved managed identity service, in LOCAL environments only.
  #
  # WHY THIS EXISTS. INTEGRATION_CONTRACTS.md :250 fixes exactly one browser handshake,
  # `f1-managed-identity-redirect-v1`: a signed release artifact pins an external
  # `authorization_endpoint`, `client_id`, receipt issuer/audience and JWKS URL, and
  # `POST /auth/callback` validates the provider's signature before creating a
  # server-side Identity Validation Receipt. F1 has no first-party identity provider by
  # design. Until that provider is provisioned — it needs credentials and an account
  # this build does not have — nothing can mint a receipt, and without a receipt no
  # WF-001 branch will run, so the product is unreachable end to end.
  #
  # This mints the same receipt row the callback would, skipping only the part that
  # requires the external provider: the proof that someone actually controls the email
  # address. That is the whole security value of the managed flow, which is why this is
  # confined to development and test and refuses to load anywhere else.
  #
  # WHY IT CONNECTS AS THE SCHEMA OWNER. `identity_receipt_nonces` is deliberately
  # absent from F1::RuntimeGrants::TABLE_PRIVILEGES and present in REVOKE_PUBLIC_TABLES:
  # the runtime role cannot write receipts, on purpose. If f1_web could mint a receipt
  # for an arbitrary email, the receipt requirement guarding every WF-001 branch would
  # be worth nothing, and a compromised web process could sign in as anyone. Granting
  # the runtime that power — or adding a SECURITY DEFINER function that hands it over —
  # would weaken production to make local development convenient. So this takes a
  # separate owner connection instead, and production keeps the posture it has.
  #
  # The seam to production is exactly one step: `/auth/callback` verifies the provider's
  # signed assertion and then writes the same row. Nothing else in the stack changes.
  class LocalIdentityIssuer
    # The issuer key the WF-001 handlers accept (`APPROVED_ISSUERS`). Keeping the local
    # issuer on the same key means the receipt this mints is the receipt the handlers
    # already validate, rather than a second code path that only development exercises.
    ISSUER_KEY = "https://id.example/oidc"
    RECEIPT_SCHEMA_VERSION = "onboarding-interim-v1"
    # ":263 ten-minute freshness", identical for every purpose.
    FRESHNESS_SECONDS = 600

    # The five ratified purposes. A purpose outside this set is a caller defect, not a
    # runtime condition: the handlers match on it exactly.
    PURPOSES = %w[
      bootstrap_grant_request self_service_bootstrap existing_account_sign_in
      invitation_response organization_reactivation
    ].freeze

    class NotAvailable < StandardError; end

    class << self
      def available? = Rails.env.local?

      # Mints one receipt and returns the fields a caller needs to drive a WF-001
      # command: the digest it quotes, and the identity it now stands for.
      #
      # `mfa_satisfied`/`assurance_version` are carried only by the purposes whose
      # handlers read them; supplying them elsewhere would make a receipt that fails
      # validation for a reason unrelated to what the caller did wrong.
      def mint(email:, purpose:, subject: nil, display_name: nil, now: Time.now.utc)
        raise NotAvailable, "the local identity issuer is development-only" unless available?
        raise ArgumentError, "unknown receipt purpose #{purpose.inspect}" unless PURPOSES.include?(purpose)

        normalized_email = normalize(email)
        subject ||= derived_subject(normalized_email)
        validated = now.getutc.floor(6)
        receipt = build(normalized_email:, subject:, display_name: display_name || normalized_email,
                        purpose:, validated:)
        insert(receipt)
        receipt
      end

      # Development convenience: the same subject for the same address every time, so
      # signing in twice locally is the same principal rather than two.
      def derived_subject(normalized_email) = "local-#{Digest::SHA256.hexdigest(normalized_email)[0, 32]}"

      # THERE IS DELIBERATELY NO `organizations_for(email)` DIRECTORY LOOKUP.
      #
      # An earlier draft had one, so the sign-in form could offer the Organizations an
      # address belongs to. It cannot work without breaking something worth more than the
      # convenience: `accounts` and `organizations` are FORCE ROW LEVEL SECURITY, so the
      # policies apply to the schema owner too, and only a BYPASSRLS superuser can read
      # across tenants. The options were to connect a request path as a superuser, or to
      # relax `accounts` to NO FORCE the way `sessions` is relaxed for pre-context
      # authentication. `sessions` is one narrow, non-secret, owner-only authenticator;
      # `accounts` is the tenant membership table, and opening it to satisfy a form would
      # trade real isolation for a convenience.
      #
      # So the Organization is submitted explicitly, which is what SignInExistingAccount
      # requires anyway: it "is supplied explicitly and never selected implicitly". In
      # production the identity flow carries it; locally the person pastes it, and the
      # bootstrap screen hands it over after creating the tenant.

      def normalize(email) = email.to_s.unicode_normalize(:nfc).strip.downcase

      # A dedicated owner connection, opened and closed around each write. It is never the
      # Rails connection pool: nothing in a request should be able to reach owner
      # privileges by borrowing the ambient connection.
      #
      # Deliberately NOT pooled or kept open. An owner session that outlives its statement
      # is a session the suite's `TRUNCATE` over 26 tables can end up waiting behind, and
      # `spec/support/pg_test_connection.rb` documents what that costs. A connect per
      # receipt is a few milliseconds on a development-only path, which is not worth one
      # long-lived connection holding anything.
      def with_connection
        connection = PG.connect(**owner_connection_params)
        begin
          yield connection
        ensure
          connection.close
        end
      end

      # Retained so callers that tidy up explicitly keep working; there is no longer a
      # persistent connection for it to close.
      def reset! = nil

      private

      def owner_connection_params
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        { host: config[:host], port: config[:port], dbname: config[:database],
          user: "f1_schema_owner", password: config[:password].to_s }.compact
      end

      def build(normalized_email:, subject:, display_name:, purpose:, validated:)
        principal_digest = Digest::SHA256.digest("#{ISSUER_KEY}\n#{subject}")
        {
          receipt_id: SecureRandom.uuid_v7,
          receipt_digest: Digest::SHA256.digest("jws:#{SecureRandom.hex(24)}"),
          nonce_sha256: Digest::SHA256.digest("nonce:#{SecureRandom.hex(24)}"),
          principal_digest:,
          # Only the two bootstrap purposes carry a bootstrap principal; sign-in and
          # invitation response deliberately do not (ReceiptMinter, :112 and :158).
          bootstrap_principal_digest: bootstrap_purpose?(purpose) ? principal_digest : nil,
          issuer_key: ISSUER_KEY, subject:, normalized_email:, display_name:, purpose:,
          normalized_email_sha256: Digest::SHA256.digest(normalized_email),
          validated_at: validated, expires_at: validated + FRESHNESS_SECONDS,
          assurance_version: assurance_purpose?(purpose) ? "assurance-v1" : nil,
          mfa_satisfied: assurance_purpose?(purpose) ? "true" : nil
        }
      end

      def bootstrap_purpose?(purpose) = %w[bootstrap_grant_request self_service_bootstrap].include?(purpose)
      def assurance_purpose?(purpose) = %w[existing_account_sign_in organization_reactivation].include?(purpose)

      def insert(receipt)
        params = [
          receipt[:receipt_id], "1.0", iso(receipt[:validated_at]), bytea(receipt[:receipt_digest]),
          RECEIPT_SCHEMA_VERSION, receipt[:issuer_key], receipt[:subject], receipt[:normalized_email],
          bytea(receipt[:normalized_email_sha256]), receipt[:display_name], true, receipt[:purpose],
          iso(receipt[:validated_at]), iso(receipt[:expires_at]), bytea(receipt[:nonce_sha256]),
          bytea(receipt[:principal_digest]), bytea(receipt[:bootstrap_principal_digest]),
          receipt[:assurance_version], receipt[:mfa_satisfied], "security_audit"
        ]
        with_connection do |connection|
          connection.exec_params(<<~SQL, params)
            INSERT INTO identity_receipt_nonces
              (id, schema_version, created_at, receipt_digest, receipt_schema_version,
               issuer_key, issuer_subject, normalized_email, normalized_email_sha256, display_name,
               email_verified, purpose, validated_at, expires_at, nonce_sha256,
               identity_principal_digest, bootstrap_principal_digest, assurance_version, mfa_satisfied,
               retention_class)
            VALUES ($1,$2,$3::timestamptz,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::timestamptz,$14::timestamptz,
                    $15,$16,$17,$18,$19,$20)
          SQL
        end
      end

      def bytea(bytes) = bytes.nil? ? nil : { value: bytes, format: 1 }
      def iso(time) = time.getutc.iso8601(6)
    end
  end
end
