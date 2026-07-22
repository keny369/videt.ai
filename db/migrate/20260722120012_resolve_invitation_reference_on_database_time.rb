# frozen_string_literal: true

# PostgreSQL is the authoritative clock for public invitation-reference
# resolution.
#
# `f1_resolve_invitation_reference(bytea, timestamptz)` took the effective
# current instant from its caller and was granted to `f1_web`
# (schemas/POSTGRESQL_SCHEMA.md:179 grants the resolver to `f1_web` and, notably,
# describes its second argument as `correlation_id`, not a time). Its expiry
# predicate was `p_now < r.expires_at`, so a caller supplying a HISTORICAL
# instant could resolve a reference that PostgreSQL already considers expired —
# reviving an expired Invitation for acceptance or decline. That contradicts
# WORKFLOW_SPECIFICATIONS.md:242 ("Active expiry is exactly seven days after
# activation, and at equality expiry wins over acceptance or decline") and the
# same PostgreSQL-time authority the background contract states for every other
# deadline (BACKGROUND_PROCESSING.md :110, :114; verification gate 7 :519).
#
# The old signature is DROPPED, not overloaded: leaving it callable would leave
# the defect reachable. The replacement takes only the reference digest and
# evaluates expiry against `transaction_timestamp()`, so equality behaves exactly
# as ratified — at `now >= expires_at` the reference no longer resolves and
# expiry wins.
#
# Everything else about the resolver is unchanged and deliberately so: the same
# single fixed unique-index lookup, the same active-only state filter, the same
# fixed projection for hit and miss, the same non-disclosing empty result for
# every miss, terminal row, wrong-Organization reference and expiry, and the same
# absence of any Organization argument or tenant-table scan.
#
# `f1_resolve_invitation_org(bytea)` is untouched: it takes no time, gates
# nothing, and exists only so the restricted exact-replay path can bootstrap
# context for an already-terminal reference.
class ResolveInvitationReferenceOnDatabaseTime < ActiveRecord::Migration[8.1]
  def up
    execute "DROP FUNCTION IF EXISTS f1_resolve_invitation_reference(bytea, timestamptz);"
    execute <<~SQL
      CREATE FUNCTION f1_resolve_invitation_reference(p_reference_digest bytea)
      RETURNS TABLE (organization_id uuid, invitation_id uuid)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT r.organization_id, r.invitation_id
        FROM invitation_reference_registry r
        WHERE r.opaque_reference_sha256 = p_reference_digest
          AND r.invitation_state = 'active'
          AND (r.expires_at IS NULL OR transaction_timestamp() < r.expires_at);
      $$;
      REVOKE ALL ON FUNCTION f1_resolve_invitation_reference(bytea) FROM PUBLIC;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "restoring a caller-supplied resolution clock would reopen an expired-reference revival defect"
  end
end
