# frozen_string_literal: true

# The immutable RoleExpiryBlockDecision record (WORKFLOW_SPECIFICATIONS.md :343
# "Identity and ownership: `role_expiry_block_decision_id`, owned by the Tenant
# Governance Context. It records exactly one `organization_id`, one
# `role_assignment_id`, the Assignment's `expires_at_utc`, the Organization
# authorization epoch evaluated, the block reason `expiry_blocked_last_admin`,
# the evaluated last-administrator predicate result, `decided_at_utc`, and the
# correlation ID. Its retention owner is `security_audit`"; :344 the predicate;
# :350 "idempotent on `(role_assignment_id, authorization_epoch)`"; :351 the
# concurrency rule).
#
# It is a decision record, not a flag: :348 makes it the affected entity of the
# `RoleExpiryBlocked` event under the `decision` profile, so it must exist
# durably before the event that references it. A transient boolean could not
# carry the evaluated epoch, and re-evaluation after an epoch advance would have
# nothing to be idempotent against.
class CreateRoleExpiryBlockDecisions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE role_expiry_block_decisions (
        id                        uuid PRIMARY KEY,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        role_assignment_id        uuid NOT NULL,
        assignment_expires_at     timestamptz(6) NOT NULL,
        authorization_epoch       bigint NOT NULL,
        block_reason              text NOT NULL CHECK (block_reason = 'expiry_blocked_last_admin'),
        predicate_result          jsonb NOT NULL,
        decided_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        retention_class           text NOT NULL CHECK (retention_class = 'security_audit'),
        -- ":350 The decision is idempotent on `(role_assignment_id,
        -- authorization_epoch)`. Re-evaluating the same Assignment within an
        -- unchanged epoch writes no second decision."
        CONSTRAINT one_decision_per_assignment_epoch UNIQUE (role_assignment_id, authorization_epoch)
      );
      ALTER TABLE role_expiry_block_decisions ENABLE ROW LEVEL SECURITY;
      ALTER TABLE role_expiry_block_decisions FORCE ROW LEVEL SECURITY;
      CREATE POLICY role_expiry_block_decisions_context ON role_expiry_block_decisions
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON role_expiry_block_decisions FROM PUBLIC;
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS role_expiry_block_decisions;"
  end
end
