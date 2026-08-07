# frozen_string_literal: true

module Platform
  # Resolves a bearer token to the Session id a command should be run against.
  #
  # APPLICATION_LAYER.md :72 describes exactly this step: the transport "performs a
  # nonlocking digest lookup only to discover the candidate Session/tenant identities".
  # The word that matters is CANDIDATE. This grants no authority, takes no lock, checks
  # no expiry and changes no activity. It answers one question — which Session id is this
  # cookie talking about — and the command handler then authenticates that id properly
  # inside its own unit of work, where the Organization is locked at tier one and the
  # Session at tier two.
  #
  # Reads go through Platform::AuthenticatedRequest instead, because a query has no
  # handler of its own to do the authenticating. A command must NOT be wrapped in
  # AuthenticatedRequest: the handler owns the sole unit of work (:69), and nesting one
  # inside another is refused by Platform::UnitOfWork by design.
  module SessionLocator
    module_function

    # The Session id, or nil when the cookie is absent, malformed or unknown. A nil here
    # means "there is nothing to authenticate", not "authentication failed" — the caller
    # treats both as unauthenticated, but only the handler can tell them apart.
    def resolve(token, connection: ActiveRecord::Base.connection)
      return nil unless Platform::SessionToken.plausible?(token)

      row = connection.raw_connection.exec_params(
        "SELECT id FROM f1_authenticate_session_by_token($1)",
        [{ value: Platform::SessionToken.digest_of(token), format: 1 }]
      ).to_a.first
      row && row["id"]
    end
  end
end
