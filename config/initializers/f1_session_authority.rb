# frozen_string_literal: true

# The composition root for Platform::AuthenticatedRequest's authority port.
#
# Platform is the kernel and depends on no bounded context, so it cannot name the object
# that authenticates a Session and evaluates a capability. IdentityAccess owns those
# decisions and cannot be reached from Platform without inverting the dependency the
# package boundaries declare. Wiring them here, outside both packages, is what keeps the
# arrow pointing one way.
Rails.application.config.to_prepare do
  Platform::AuthenticatedRequest.authority_builder =
    ->(pg_connection) { IdentityAccess::Authorization::SessionAuthority.new(pg_connection) }
end
