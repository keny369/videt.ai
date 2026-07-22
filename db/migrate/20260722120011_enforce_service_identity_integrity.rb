# frozen_string_literal: true

# Referential integrity for every Service Identity attribution in the shared
# ledger.
#
# schemas/POSTGRESQL_SCHEMA.md:43 classes `service_identity_id` "and their
# qualified F1-row variants" as F1 row identities and requires that "every
# discriminator arm has the named FK/existence check". `scheduled_actions` was
# bound in 20260722120010; the five remaining columns are bound here:
#
#   command_executions.service_identity_id            (nullable, XOR with actor_id)
#   command_results.service_identity_id               (nullable, XOR with actor_id)
#   audit_record_registry.service_identity_id         (nullable, XOR with actor_id)
#   bootstrap_grants.issuer_service_identity_id       (NOT NULL)
#   pretenant_authorization_decisions.subject_service_identity_id (NOT NULL)
#
# Existence, not status. A foreign key guarantees the identity was registered;
# it deliberately says nothing about whether that identity is still active,
# because `command_executions`, `command_results`, `audit_record_registry` and
# `pretenant_authorization_decisions` are immutable ledgers (G-IMM) and a record
# of what a service did must not become invalid, unreadable or unjoinable merely
# because the service was later suspended or revoked. Status is an EXECUTION
# predicate and is enforced where execution happens — the ScheduledAction claim
# already refuses work for a non-active executor — never on history.
#
# The nullable columns keep their XOR with `actor_id` untouched: a human
# actor-attributed command has `service_identity_id IS NULL` and is unaffected by
# a foreign key, which constrains only non-null values.
#
# The approved identity/bootstrap service is registered here as a reserved
# identity. WF-001 assigns grant issuance, invitation response and existing-account
# sign-in to "the approved identity/bootstrap service" as the command service
# identity (WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1, § existing-account
# sign-in), so that service is a real registered principal, not a per-request
# random UUID. Rows are seeded by `f1:db:ensure_service_identities`, for the same
# reason the ScheduledAction executor is: db/structure.sql carries no data.
class EnforceServiceIdentityIntegrity < ActiveRecord::Migration[8.1]
  # table => [column, constraint name]. Names are given explicitly and kept
  # inside PostgreSQL's 63-byte identifier limit, so a violation names its exact
  # constraint rather than a silently truncated one.
  FOREIGN_KEYS = {
    "command_executions" => %w[service_identity_id command_executions_service_identity_fkey],
    "command_results" => %w[service_identity_id command_results_service_identity_fkey],
    "audit_record_registry" => %w[service_identity_id audit_records_service_identity_fkey],
    "bootstrap_grants" => %w[issuer_service_identity_id bootstrap_grants_issuer_service_identity_fkey],
    "pretenant_authorization_decisions" => %w[subject_service_identity_id pretenant_decisions_subject_service_identity_fkey]
  }.freeze

  def up
    FOREIGN_KEYS.each do |table, (column, name)|
      raise "constraint name #{name} exceeds the PostgreSQL identifier limit" if name.bytesize > 63

      execute <<~SQL
        ALTER TABLE #{table}
          ADD CONSTRAINT #{name} FOREIGN KEY (#{column}) REFERENCES service_identities (id);
      SQL
    end
    create_active_predicate
  end

  def down
    FOREIGN_KEYS.each do |table, (_column, name)|
      execute "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{name};"
    end
    execute "DROP FUNCTION IF EXISTS f1_service_identity_active(uuid);"
  end

  private

  # The execution-boundary predicate, separate from the ledger constraint above.
  # `service_identities` is platform control with no runtime grant
  # (POSTGRESQL_SCHEMA.md :166), so a command that must confirm its acting service
  # is still permitted asks through this fixed, minimal projection rather than
  # reading the register. It returns a boolean and nothing else — no subject, no
  # scope, no display name — so it cannot be used to enumerate identities.
  def create_active_predicate
    execute <<~SQL
      CREATE FUNCTION f1_service_identity_active(p_service_identity_id uuid)
      RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT EXISTS (
          SELECT 1 FROM service_identities s
          WHERE s.id = p_service_identity_id AND s.status = 'active'
        );
      $$;
      REVOKE ALL ON FUNCTION f1_service_identity_active(uuid) FROM PUBLIC;
    SQL
  end
end
