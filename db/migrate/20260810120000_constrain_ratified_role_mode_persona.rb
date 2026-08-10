# frozen_string_literal: true

# FU-76 (measured while resolving FU-62, ADR-149). FU-62 was fixed AT THE DECISION
# and not AT THE ROW: every authorization decision now reads both baseline cells
# through `PermissionBaseline.assignment_permits?`, so a `read_only`
# OrganizationAdmin is refused whatever the row says. What was NOT true is that the
# row is impossible.
#
# MEASURED AGAINST THE RUNNING DATABASE, BEFORE THIS MIGRATION EXISTED:
# `role_assignments_permission_mode_check` constrains `permission_mode` to the
# DOMAIN {standard, read_only} and says nothing about its pairing with
# `canonical_role`; `f1_role_assignments_insert_guard` checks only the protected
# allowlist; `one_active_assignment_per_tuple` is a uniqueness index, not a
# validity one; and `canonical_role` carries no CHECK on either table at all. So
# `OrganizationAdmin` + `read_only` INSERTED CLEANLY into `role_assignments`, and
# `BillingOperator` + `read_only` + `executive_buyer` — a role the ratified set
# never pairs with a persona — INSERTED CLEANLY into `invitations`.
#
# BOTH TABLES, BECAUSE THE RATIFIED SET GOVERNS BOTH AND THE TWO ARE CHAINED.
# `Wf001::Handlers::AcceptInvitation` copies `canonical_role`, `permission_mode`
# and `persona` STRAIGHT OUT OF THE INVITATION ROW into the Role Assignment it
# creates, and re-validates none of them: an illegal Invitation tuple becomes an
# illegal grant. Constraining only `role_assignments` would leave the Invitation
# able to hold the tuple and fail later, at acceptance, on the invitee.
#
# IT IS A CHECK, AND ESTABLISHING THAT WAS THE FIRST QUESTION FU-59 LEFT. FU-59's
# repair HAD to be a trigger because "a CHECK cannot distinguish INSERT from
# UPDATE, so a CHECK strong enough to close this would also forbid the ratified
# activation" — its subject, `protected_permission_allowlist`, legitimately CHANGES
# on the `pending -> active` edge. These three columns do not:
#
#   role_assignments  `f1_role_assignments_lifecycle_guard` already raises
#                     `role_assignment_grant_content_immutable` if `canonical_role`,
#                     `permission_mode` or `persona` is DISTINCT FROM its old value,
#                     so no UPDATE may move this tuple at all.
#   invitations       carries no trigger, and no `UPDATE invitations` statement in
#                     the repository sets any of the three — measured across all
#                     seven of them in `invitation_store`, `invitation_admin_store`,
#                     `revoke_invitation_store` and `expire_invitation_store`; every
#                     one sets `state` and its timestamps.
#
# A row that was legal when inserted therefore stays legal, and a CHECK forbids no
# ratified transition. Where FU-59 needed the operation distinguished, this needs
# only the value constrained, and a CHECK is the weaker instrument that suffices.
#
# THE TUPLES ARE `:314` AS `Platform::BaselineContent::ALLOWED_ROLE_MODE_PERSONA`
# transcribes them, and `spec/architecture/ratified_tuple_constraint_spec.rb`
# DERIVES both sides — the constant and `pg_get_constraintdef` — so a tuple added
# to the ratified set and not to the database fails a gate rather than passing
# quietly. `persona` is compared through `COALESCE(persona, '')` because a NULL
# persona is a RATIFIED value for seven of the nine tuples and a comparison
# against NULL yields NULL, not false — a constraint that admitted every NULL
# persona would be the "conjunct that does nothing" shape this repository has
# already caught twice.
#
# IT IS A JOINED KEY AGAINST `= ANY (ARRAY[...])`, AND THE FIRST DRAFT WAS NOT.
#
# That draft wrote the natural thing, `(canonical_role, permission_mode,
# COALESCE(persona,'')) IN ((...),(...))`, and `bin/f1-db-bootstrap-gate` FAILED on
# the `constraints` fingerprint alone — 837 constraints on both sides, every
# definition identical except this one. The row-constructor `IN` builds a LEFT-DEEP
# OR TREE, which `pg_get_constraintdef` prints with deep nesting; loading that
# printed form back FLATTENS the tree, because PostgreSQL flattens nested `OR`s at
# parse time. So `load(dump(x))` was not textually `x`, the gate builds one database
# from the migrations and one from `db/structure.sql`, and it compares TEXT. The
# constraint was semantically identical and structurally unstable.
#
# `= ANY (ARRAY[...])` is a single `ScalarArrayOpExpr` with no boolean tree to
# flatten, so it is a fixed point of dump-and-load. It is also the idiom the
# neighbouring `permission_mode = ANY (ARRAY['standard','read_only'])` constraints
# already use, which is the evidence that this shape survives the gate rather than a
# hope that it will.
#
# THE DELIMITER CANNOT COLLIDE: every canonical role, permission mode and persona in
# the ratified set matches `[A-Za-z_]+`, so no value can contain the separator and
# no two distinct tuples can join to the same string. Both `canonical_role` and
# `permission_mode` are NOT NULL on both tables, so the joined key is never NULL —
# which matters, because a NULL key would make `= ANY` yield NULL and the CHECK
# would PASS. That is the same "silently never false" shape as the persona note
# above, one operand over.
class ConstrainRatifiedRoleModePersona < ActiveRecord::Migration[8.1]
  TUPLES = [
    %w[BillingOperator standard],
    %w[MarketingOperator read_only executive_buyer],
    %w[MarketingOperator standard],
    %w[MarketingOperator standard consultant],
    %w[OrganizationAdmin standard],
    %w[OrganizationAdmin standard consultant],
    %w[SecurityOperator standard],
    %w[TechnicalImplementer standard],
    %w[TechnicalImplementer standard consultant]
  ].freeze

  TABLES = { role_assignments: "role_assignments_ratified_role_mode_persona",
             invitations: "invitations_ratified_role_mode_persona" }.freeze

  # The separator is the one character no ratified value contains; see the note above.
  SEPARATOR = "|"

  def up
    values = TUPLES.map { |role, mode, persona| quote([role, mode, persona.to_s].join(SEPARATOR)) }
                   .join(",\n            ")

    TABLES.each do |table, name|
      execute <<~SQL
        ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (
          canonical_role || '#{SEPARATOR}' || permission_mode || '#{SEPARATOR}' ||
            COALESCE(persona, '') = ANY (ARRAY[
            #{values}
          ])
        );
      SQL
    end
  end

  def down
    TABLES.each { |table, name| execute "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{name};" }
  end

  private

  def quote(value) = ActiveRecord::Base.connection.quote(value)
end
