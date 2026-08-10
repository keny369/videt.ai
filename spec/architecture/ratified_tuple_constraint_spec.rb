# frozen_string_literal: true

require "rails_helper"

# THE RATIFIED ROLE/MODE/PERSONA SET, ENFORCED BY THE DATABASE AND HELD TO THE CONSTANT (FU-76).
#
# WHAT WAS OPEN, MEASURED AGAINST THE RUNNING DATABASE. FU-62 was fixed AT THE DECISION and not AT
# THE ROW: `PermissionBaseline.assignment_permits?` refuses a `read_only` OrganizationAdmin whatever
# the row says, but the ROW WAS STILL POSSIBLE. `role_assignments_permission_mode_check` constrains
# `permission_mode` to a DOMAIN and says nothing about its pairing with `canonical_role`;
# `f1_role_assignments_insert_guard` checks only the protected allowlist;
# `one_active_assignment_per_tuple` is a uniqueness index, not a validity one; and `canonical_role`
# carried no CHECK on either table at all. Driven against `f1_test`, `OrganizationAdmin` +
# `read_only` inserted cleanly into `role_assignments`, and `BillingOperator` + `read_only` +
# `executive_buyer` inserted cleanly into `invitations`.
#
# THAT IS FU-59'S OBSERVATION FROM A THIRD DIRECTION: an invariant implemented in Ruby at the paths
# somebody enumerated, with the database admitting anything. And the enumeration was wrong in the
# recording of it — `permission_baseline.rb` said `InvitationOffer#valid_tuple?` guards "the three
# creation paths"; the tree holds TWO production callers, `create_invitation.rb:48` and
# `request_role_assignment.rb:38`. Neither `AcceptInvitation` — which copies the tuple straight out
# of the Invitation row — nor WF-001's genesis calls it at all.
#
# WHAT THIS FILE IS FOR, AND WHAT IT IS NOT. The constraint's EFFECT is proved by execution in
# `spec/acceptance/wf013_role_assignment_invariants_spec.rb`, which drives real INSERTs and is
# verified by dropping the constraint. This is the TRANSCRIPTION gate, in the shape
# `permission_baseline_transcription_spec.rb` already establishes: both sides are DERIVED — one from
# `Platform::BaselineContent::ALLOWED_ROLE_MODE_PERSONA`, one from `pg_get_constraintdef` — so a
# tuple added to the ratified set and not to the database, or admitted by the database and not
# ratified, fails here rather than being found by a reviewer three rounds on.
RSpec.describe "the ratified role/mode/persona set is enforced by the database", type: :architecture do
  # NO TOP-LEVEL CONSTANTS, for the reason `permission_baseline_transcription_spec.rb` records: a
  # constant assigned inside an `RSpec.describe` block lands on Object, where another spec file's
  # constant of the same name can be read instead depending on load order.
  def constrained_tables
    { "role_assignments" => "role_assignments_ratified_role_mode_persona",
      "invitations" => "invitations_ratified_role_mode_persona" }
  end

  def constraint_definition(name)
    row = DbInspector.one("SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname = $1",
                          [name])
    row && row["def"]
  end

  # The constraint joins the three columns with `|` and compares against `ANY (ARRAY[...])`, so each
  # admitted tuple is one array element and comes back out of the catalogue in the shape it went in.
  # The joined form is not cosmetic: a row-constructor `IN` builds a left-deep OR tree that
  # PostgreSQL FLATTENS when `db/structure.sql` is loaded back, so the printed text of the migration's
  # constraint and the printed text of the loaded one differed — and `bin/f1-db-bootstrap-gate`
  # compares exactly that text across a database built from migrations and one built from the
  # structure file. See the migration for the measurement.
  TUPLE_PATTERN = /'(?<role>[A-Za-z]+)\|(?<mode>[a-z_]+)\|(?<persona>[a-z_]*)'::text/

  def tuples_in(definition)
    definition.to_s.scan(TUPLE_PATTERN).map do |role, mode, persona|
      { "canonical_role" => role, "permission_mode" => mode,
        "persona" => (persona.empty? ? nil : persona) }
    end
  end

  def key(tuple) = [tuple["canonical_role"], tuple["permission_mode"], tuple["persona"].to_s]

  let(:ratified) { Platform::BaselineContent::ALLOWED_ROLE_MODE_PERSONA }

  %w[role_assignments invitations].each do |table|
    describe table do
      let(:constraint) { constrained_tables.fetch(table) }

      it "carries the constraint at all, so the tuple is not enforced in Ruby alone" do
        expect(constraint_definition(constraint)).not_to be_nil,
                                                         "`#{constraint}` is not on `#{table}`: the " \
                                                         "ratified tuple set is back to being enforced " \
                                                         "only by `InvitationOffer#valid_tuple?`, at the " \
                                                         "two creation paths that call it (FU-76)"
      end

      it "admits EXACTLY the ratified tuples, derived from both sides" do
        definition = constraint_definition(constraint)
        parsed = tuples_in(definition)

        # NON-VACUITY. If the pattern stopped matching, `parsed` would shrink and could still agree
        # with a shrunken expectation. The count is taken from the raw definition independently of
        # the parse that produces the tuples, so a deriving check cannot quietly become vacuous.
        expect(parsed.length).to eq(definition.scan(/'[^']*\|[^']*\|[^']*'::text/).length),
                                 "the parse recovered #{parsed.length} tuple(s) from a definition " \
                                 "naming #{definition.scan(/'[^']*\|[^']*\|[^']*'::text/).length}, so every " \
                                 "comparison below reads a fragment"
        expect(parsed.length).to be >= 9,
                                 "fewer tuples than the ratified set has members (#{ratified.length})"

        expect(parsed.map { |t| key(t) }.sort).to eq(ratified.map { |t| key(t) }.sort),
                                                  "the database admits a different set from " \
                                                  "`ALLOWED_ROLE_MODE_PERSONA`:\n" \
                                                  "  only in the database: " \
                                                  "#{(parsed.map { |t| key(t) } - ratified.map { |t| key(t) }).inspect}\n" \
                                                  "  only in the constant: " \
                                                  "#{(ratified.map { |t| key(t) } - parsed.map { |t| key(t) }).inspect}"
      end
    end
  end

  # THE TUPLE COLUMNS MUST BE IMMUTABLE, WHICH IS WHY A CHECK IS THE RIGHT INSTRUMENT HERE AND WAS
  # THE WRONG ONE FOR FU-59.
  #
  # FU-59's repair had to be a trigger because a CHECK cannot distinguish INSERT from UPDATE, and its
  # subject legitimately CHANGES on the `pending -> active` edge. This subject does not — and that is
  # a property of the LIFECYCLE GUARD, not of this constraint, so it is asserted rather than assumed.
  # If someone later relaxes the guard to let a grant be re-roled, this CHECK silently becomes an
  # INSERT-time-only rule while still reading as an invariant, and this example is what says so.
  it "holds the role_assignments tuple columns immutable, so no ratified UPDATE can be forbidden" do
    guard = DbInspector.one(<<~SQL)["def"]
      SELECT pg_get_functiondef(oid) AS def FROM pg_proc
      WHERE proname = 'f1_role_assignments_lifecycle_guard'
    SQL

    %w[canonical_role permission_mode persona].each do |column|
      expect(guard).to include("NEW.#{column} IS DISTINCT FROM OLD.#{column}"),
                       "`f1_role_assignments_lifecycle_guard` no longer freezes `#{column}`, so an " \
                       "UPDATE can now move the tuple and this CHECK constrains only the INSERT " \
                       "while reading as an invariant (FU-76 / FU-59's instrument question)"
    end
    expect(guard).to include("role_assignment_grant_content_immutable")
  end

  # THE OTHER TABLE HAS NO GUARD AT ALL, so its immutability is a property of the REPOSITORY: no
  # `UPDATE invitations` statement sets any of the three columns. That was measured across all seven
  # of them, and it is asserted here because it is the whole basis for a CHECK being sufficient on
  # this table. A future writer that re-roles an Invitation fails here rather than discovering at
  # runtime that the CHECK refuses its UPDATE.
  it "writes no UPDATE that moves an Invitation's tuple, which is what makes a CHECK sufficient there" do
    statements = Dir.glob(Rails.root.join("app/**/*.rb")).flat_map do |path|
      File.read(path).scan(/UPDATE invitations\b(.*?)(?=\n\s*(?:SQL|WHERE|RETURNING))/m).flatten
    end

    expect(statements).not_to be_empty,
                              "no `UPDATE invitations` statement was found at all, so this scan is " \
                              "reading nothing and the assertion below is vacuous"
    statements.each do |body|
      %w[canonical_role permission_mode persona].each do |column|
        expect(body).not_to match(/\b#{column}\s*=/),
                            "an `UPDATE invitations` now sets `#{column}`. The ratified tuple set is " \
                            "enforced there by a CHECK, which cannot distinguish INSERT from UPDATE, " \
                            "so that transition needs FU-59's instrument (a trigger) rather than this " \
                            "one:\n#{body.strip}"
      end
    end
  end
end
