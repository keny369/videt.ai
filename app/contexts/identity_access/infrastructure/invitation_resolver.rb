# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Resolves an opaque invitation reference to its (Organization, Invitation)
    # binding via the SECURITY DEFINER f1_resolve_invitation_reference, which reads
    # the global invitation_reference_registry as the owner (bypassing the tenant
    # RLS the caller cannot yet satisfy) and returns a binding ONLY for an active,
    # unexpired locator. Every miss, terminal row, or expiry returns nil — the
    # single non-disclosing outcome the handler renders as the generic
    # invitation_not_active (WORKFLOW_SPECIFICATIONS.md § invitation;
    # schemas/POSTGRESQL_SCHEMA.md § the invitation reference resolver).
    #
    # It sets no context; the caller enters the resolved Organization afterwards
    # with f1_enter_context.
    class InvitationResolver
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Returns { organization_id:, invitation_id: } or nil.
      def resolve(reference_digest:, now:)
        sql = "SELECT organization_id, invitation_id FROM f1_resolve_invitation_reference($1, $2::timestamptz)"
        row = @pg.exec_params(sql, [{ value: reference_digest, format: 1 }, now.getutc.iso8601(6)]).to_a.first
        return nil if row.nil?

        { organization_id: row["organization_id"], invitation_id: row["invitation_id"] }
      end

      # Any-state (Organization, Invitation) binding, used ONLY by the restricted
      # exact-replay path to bootstrap context for a possibly-terminal reference. It
      # does not gate acceptance and is not the public resolver above.
      def resolve_org(reference_digest:)
        sql = "SELECT organization_id, invitation_id FROM f1_resolve_invitation_org($1)"
        row = @pg.exec_params(sql, [{ value: reference_digest, format: 1 }]).to_a.first
        return nil if row.nil?

        { organization_id: row["organization_id"], invitation_id: row["invitation_id"] }
      end
    end
  end
end
