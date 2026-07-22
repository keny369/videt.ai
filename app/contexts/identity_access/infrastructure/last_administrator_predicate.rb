# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # The ONE last-active-administrator predicate.
    #
    # ":344 the expiry is blocked when committing it would leave the Organization
    # with no other Account holding an active, in-scope Role Assignment conferring
    # effective OrganizationAdmin authority, evaluated against the current
    # Organization authorization epoch. This is the same last-admin invariant that
    # WF-013 already applies to Role Assignment revoke, reject, and scope change,
    # and to Account suspension, revocation, and deletion; OD-026 adds no second
    # predicate."
    #
    # "No second predicate" is the whole reason this is a shared module rather
    # than a copy in each store. Revoke and timed expiry ask the identical
    # question and differ only in what they do with the answer: a human-commanded
    # revoke is REJECTED as `last_organization_admin` (:948), while a timed expiry
    # is BLOCKED and writes an immutable `RoleExpiryBlockDecision` (:339). If the
    # two predicates could drift, one path would strand a tenant the other
    # protects.
    #
    # Evaluated in the database at transaction time, under the Organization
    # advisory lock the caller already holds, never from cached application state.
    module LastAdministratorPredicate
      # The count of OTHER Accounts holding an effective OrganizationAdmin
      # Assignment right now: "another active Account already has an active,
      # in-scope, unexpired OrganizationAdmin Assignment" (:948). Zero means
      # removing this Assignment would strand the Organization.
      #
      # Effectiveness is the ratified resolution rule (:316): `effective_at <=
      # now` and either null expiry or `now < expires_at`, equality belonging to
      # expiry.
      def other_effective_admins(role_assignment_id:, account_id:, now:)
        sql = <<~SQL
          SELECT count(*) FROM role_assignments
          WHERE canonical_role = 'OrganizationAdmin' AND status = 'active'
            AND id <> $1::uuid AND account_id <> $2::uuid
            AND effective_at IS NOT NULL AND effective_at <= $3::timestamptz
            AND (expires_at IS NULL OR $3::timestamptz < expires_at)
        SQL
        exec(sql, [role_assignment_id, account_id, iso(now)]).values.dig(0, 0).to_i
      end
    end
  end
end
