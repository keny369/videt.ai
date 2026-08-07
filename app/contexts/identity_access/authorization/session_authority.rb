# frozen_string_literal: true

module IdentityAccess
  module Authorization
    # The IdentityAccess side of Platform::AuthenticatedRequest's authority port.
    #
    # Platform is the kernel: IdentityAccess depends on it and it depends on no context
    # (`app/contexts/identity_access/package.yml`). An authenticated request nevertheless
    # has to authenticate a Session and evaluate a capability, both of which are
    # IdentityAccess's to decide. Resolving that by having Platform reference
    # `IdentityAccess::Infrastructure::AuthorizationStore` directly inverts the dependency
    # and is exactly what Packwerk rejected.
    #
    # So Platform declares the operations it needs and this object provides them, wired at
    # the composition root (`config/initializers/f1_session_authority.rb`). Platform keeps
    # the transaction, lock ordering and step sequence; IdentityAccess keeps every
    # decision about who the actor is and what they may do. Neither imports the other.
    class SessionAuthority
      def initialize(pg_connection)
        @store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg_connection)
        @authorizer = CommandAuthorizer.new(@store)
      end

      def authenticate_by_token(token_sha256:, now:, correlation_id:)
        @authorizer.authenticate_by_token(token_sha256:, now:, correlation_id:)
      end

      def authorize(actor:, capability:, now:) = @authorizer.authorize(actor:, capability:, now:)

      def lock_session(session_id) = @store.lock_session(session_id)

      def record_session_activity(session_id:, now:, idle_seconds:)
        @store.record_session_activity(session_id:, now:, idle_seconds:)
      end

      def record_authorization_decision(row) = @store.insert_authorization_decision(row)
    end
  end
end
