# frozen_string_literal: true

require "json"
require "securerandom"

module Platform
  # The single entry every protected HTML, Turbo and first-party JSON request runs
  # through (APPLICATION_LAYER.md § Authenticated Request Transaction).
  #
  # It exists so that no controller ever decides who the actor is. A controller hands
  # over an opaque cookie value and the exact capability its route declares; it gets
  # back either a denial with a stable reason, or an authorized actor plus whatever the
  # block materialized. It cannot ask for "the current account", cannot skip the
  # capability, and cannot see a record that the proved Organization context excludes.
  #
  # The ordered steps, and why each is where it is:
  #
  #   1. The token is validated in shape and hashed BEFORE the unit of work opens, so a
  #      hostile or absent cookie costs no transaction.
  #   2. The unit of work opens; everything after this is one transaction, so an
  #      authorization decision and the work it authorized commit together or not at all.
  #   3. The Session is resolved pre-context by digest, the proved Organization context
  #      is entered, and Account/Organization status is checked (`resolve`, shared with
  #      the command path).
  #   4. The Session row is locked at tier two. A revocation committed before this point
  #      is observed; one racing it waits behind the lock. Activity is recorded only
  #      after the lock, so a revoked Session cannot have its idle window extended.
  #   5. The capability is resolved through the authorization facade, and the decision
  #      is persisted on allow AND on deny — a denial is evidence, not silence.
  #   6. The block runs last, inside the same transaction, with the actor proved.
  #
  # `GET` requests reach this too: a read is authorized and audited exactly like a write.
  # What a read must not do is invoke a command, which is the caller's contract, not this
  # wrapper's.
  class AuthenticatedRequest
    # ":263 idle 30 minutes." The window slides on each accepted protected request and
    # is capped at the Session's absolute deadline by the store.
    IDLE_SECONDS = 30 * 60

    # A denial that is the actor's fault in a way we can name, versus one we must not
    # explain. `unauthenticated` maps to 401 and `forbidden` to 403; the reason is for
    # the audit trail and the support reference, never for a message that tells an
    # unauthenticated caller which Organization exists.
    Denied = Data.define(:kind, :reason) do
      def authorized? = false
      def unauthenticated? = kind == :unauthenticated
      def forbidden? = kind == :forbidden
    end

    Authorized = Data.define(:actor, :decision, :value) do
      def authorized? = true
    end

    class << self
      # The authority port. Platform is the kernel and depends on no bounded context, so
      # it does not name the object that authenticates a Session or evaluates a
      # capability — those are IdentityAccess's decisions. The composition root
      # (`config/initializers/f1_session_authority.rb`) supplies a builder taking a raw
      # PostgreSQL connection and returning something answering the five calls below.
      attr_writer :authority_builder

      def authority_builder
        @authority_builder ||
          raise(Platform::InvariantViolation, "no session authority is configured for AuthenticatedRequest")
      end

      # `token` is the raw cookie value. `capability` is the exact permission the route
      # declares; it is never inferred from the controller or action name.
      def call(token:, capability:, correlation_id:, clock: Platform::Clock.system, resource: nil, &block)
        return Denied.new(kind: :unauthenticated, reason: "session_absent") unless Platform::SessionToken.plausible?(token)

        digest = Platform::SessionToken.digest_of(token)
        Platform::UnitOfWork.run do |conn|
          authenticate_and_authorize(conn:, digest:, capability:, correlation_id:, clock:, resource:, &block)
        end
      end

      private

      def authenticate_and_authorize(conn:, digest:, capability:, correlation_id:, clock:, resource:, &block)
        now = clock.now_utc
        authority = authority_builder.call(conn.raw_connection)

        actor = authority.authenticate_by_token(token_sha256: digest, now:, correlation_id:)
        return denial_for(actor) if actor.is_a?(Symbol)

        # Tier two. Re-read under the lock: a revocation that committed between the
        # pre-context resolve and here is only visible from this side of it.
        locked = authority.lock_session(actor.session_id)
        return Denied.new(kind: :unauthenticated, reason: "session_invalid") if locked.nil? || locked["status"] != "active"

        decision = authority.authorize(actor:, capability:, now:)
        record_decision(authority:, actor:, decision:, capability:, correlation_id:, now:, resource:)
        return Denied.new(kind: :forbidden, reason: decision.reason) unless decision.allowed?

        authority.record_session_activity(session_id: actor.session_id, now: iso(now), idle_seconds: IDLE_SECONDS)
        Authorized.new(actor:, decision:, value: block&.call(actor, conn))
      end

      # An unknown, expired or revoked Session is unauthenticated: there is no proved
      # actor to forbid. An inactive Account or Organization authenticated fine and is
      # refused on status, which is a denial the actor may legitimately be told about.
      def denial_for(reason)
        kind = reason == :session_invalid ? :unauthenticated : :forbidden
        Denied.new(kind:, reason: reason.to_s)
      end

      # PRULE-044: the immutable authorization_decisions row is written on allow and on
      # deny, inside the same transaction as the work it governs.
      #
      # `resource_type` is NOT NULL by design — a decision that cannot say what it was
      # about is not evidence. A route that governs a specific entity passes it; one
      # that is Organization-wide (a collection read, a create form) resolves to the
      # Organization the Session proved, which is the thing actually being acted on.
      def record_decision(authority:, actor:, decision:, capability:, correlation_id:, now:, resource:)
        type = resource&.[](:type) || "organization"
        id = resource&.[](:id) || actor.organization_id
        authority.record_authorization_decision(
          id: SecureRandom.uuid_v7, created_at: iso(now), organization_id: actor.organization_id,
          correlation_id:, causation_id: correlation_id, command_id: nil,
          subject_id: actor.account_id, action: capability,
          resource_type: type, resource_id: id,
          decision: decision.allowed? ? "allow" : "deny", reason_code: decision.reason,
          organization_epoch: decision.organization_epoch,
          membership_snapshot: JSON.generate({ "account_id" => actor.account_id }),
          role_assignment_versions: JSON.generate(decision.role_assignment_versions),
          policy_snapshot_id: decision.policy_snapshot_id, decided_at: iso(now)
        )
      end

      def iso(time) = time.getutc.iso8601(6)
    end
  end
end
