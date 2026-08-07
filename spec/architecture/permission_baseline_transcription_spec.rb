# frozen_string_literal: true

require "rails_helper"

# THE PERMISSION BASELINE, CHECKED AGAINST THE TABLE IT CLAIMS TO TRANSCRIBE (R3-10).
#
# `Platform::PermissionBaseline` is a hand transcription of ONE ratified table,
# WORKFLOW_SPECIFICATIONS.md § Permission Baseline (:135). R3-10 is what a hand
# transcription costs: the table's rows have SEVEN cells, `CAPABILITIES` is keyed by
# canonical role alone, and the sixth column — **Read-Only Executive Buyer** — was
# dropped silently. A deliberately read-only actor could irreversibly cancel a running
# Crawl, and every existing test agreed with the transcription because every existing
# test was written from the same reading of it.
#
# So this compares the Ruby against the DOCUMENT rather than against a second literal,
# in the shape `spec/architecture/scheduled_action_catalogue_spec.rb` already
# establishes for the action-kind catalogue. A capability whose ratified cell changes,
# or a newly materialized capability whose read-only cell is not `deny`, fails here
# instead of being discovered by a reviewer three rounds later.
#
# IT CHECKS ONLY WHAT IS MATERIALIZED. `CAPABILITIES` deliberately carries only the rows
# this build consumes, so the table is filtered to those keys rather than asserted whole;
# an unmaterialized row is not drift.
RSpec.describe "Permission Baseline transcription", type: :model do
  # NO TOP-LEVEL CONSTANTS. A constant assigned inside an `RSpec.describe` block lands on
  # Object, not on the example group, so `spec/architecture/scheduled_action_catalogue_spec.rb`
  # already owns a `DOC` and this file's first draft silently READ THAT DOCUMENT INSTEAD —
  # green alone, failing in the suite, and green-or-not by load order. That is the defect
  # R3-9's repair called out in as many words ("a proof must not depend on which files RSpec
  # loaded first"), so these are methods.
  #
  # THE PARSE LIVES IN `RatifiedPermissionBaseline` (FU-63 part 1). It used to live here, and the
  # write battery now derives its NEGATIVE ROLE POPULATION from the same table — every canonical
  # role whose cell reads `deny` — rather than hand-picking one role. Two readers of one document
  # must not be two parsers of it: a second copy is the defect class R20-2 found, where the
  # round-19 repair's own copies of two derivations were bound by nothing.
  def role_columns = RatifiedPermissionBaseline.role_columns

  let(:rows) { RatifiedPermissionBaseline.rows }
  let(:materialized) { Platform::PermissionBaseline::CAPABILITIES.keys }

  # The guard on the parser itself. A regex that silently matched nothing would make every
  # example below vacuously true, which is the failure mode this whole file exists to
  # prevent, so the parse is asserted before it is used.
  it "parses the ratified table, and finds every materialized capability in it" do
    expect(rows.size).to be >= 20
    expect(rows["crawl.cancel"]).to eq(["allow", "allow", "deny", "deny", "deny", "deny", "scheduler only"])
    expect(materialized - rows.keys).to be_empty
  end

  # THE DERIVED NEGATIVE POPULATION IS NON-EMPTY AND IS REALLY A COMPLEMENT (FU-63 part 1). The
  # battery drives one refusal case per denied role, so a `denied_roles` that silently returned
  # `[]` would delete that whole dimension of the battery while leaving it green. This asserts the
  # derivation against the transcription it is the complement of: a canonical role is in exactly one
  # of the two sets, for every materialized capability.
  # The one ratified row that denies NO canonical role: :154 reads `allow for own
  # Organization` in all six actor columns, with SecurityOperator reachable only through a
  # Support Session. Its empty denied-set is a fact about the table, not a derivation that
  # silently collapsed, so it is named here — and named narrowly, so any OTHER capability
  # dropping to an empty negative population still fails the example below.
  def universally_allowed = ["organization.read"].freeze

  it "derives each capability's DENIED canonical roles as the exact complement of its allowed cell" do
    materialized.each do |capability|
      denied = RatifiedPermissionBaseline.denied_roles(capability)
      allowed = Platform::PermissionBaseline::CAPABILITIES.fetch(capability)
      deferred = deferred_cells.fetch(capability, {}).keys

      if universally_allowed.include?(capability)
        expect(denied).to be_empty, "#{capability}: recorded as denying no canonical role, but the " \
                                    "table now denies #{denied.inspect}"
      else
        expect(denied).not_to be_empty, "#{capability}: no canonical role is denied, so the battery's " \
                                        "negative population would be empty"
      end
      expect(denied & allowed).to be_empty, "#{capability}: a role is both allowed and denied"
      expect((denied + allowed + deferred).sort)
        .to eq(RatifiedPermissionBaseline.canonical_role_columns.sort),
            "#{capability}: allowed + denied + deferred is not every canonical role column"
    end
  end

  # A ratified non-deny cell that is deliberately NOT transcribed, because the mechanism the
  # cell is conditional on does not exist in this build. Each entry is a recorded deferral,
  # not drift, and it is listed here so that ADDING one is a visible act rather than a silent
  # narrowing of somebody's authority.
  #
  # `support-session only` is the whole list today: Support Sessions are a later slice, so the
  # SecurityOperator arm of the two Organization lifecycle rows is unreachable and
  # `Platform::PermissionBaseline` says so in place. It is a DEFERRED ALLOW — the safe
  # direction — and the moment Support Sessions land, the cell must be transcribed and this
  # entry removed, which this example is what forces.
  def deferred_cells
    {
      "organization.suspend" => { "SecurityOperator" => "support-session only" },
      "organization.reactivate" => { "SecurityOperator" => "support-session only" },
      # The customer-facing reads (OD-020). `organization.read` defers on the same
      # support-session mechanism as the two rows above. The four-capability :155 row
      # defers on a different one: its SecurityOperator cell is conditional on an
      # authorized incident/adjudication scope, and neither Incidents nor Adjudication
      # Cases are reachable in this build, so there is no scope to evaluate the cell
      # against. Both are DEFERRED ALLOWS, the safe direction.
      "organization.read" => { "SecurityOperator" => "support-session only" },
      "project.read" => { "SecurityOperator" => "authorized incident/adjudication scope only" },
      "source.read" => { "SecurityOperator" => "authorized incident/adjudication scope only" },
      "crawl.read" => { "SecurityOperator" => "authorized incident/adjudication scope only" }
    }.freeze
  end

  # Dimension 1 — the role cells. A role is transcribed into the allow-list exactly when its
  # ratified cell is anything other than `deny`, minus the recorded deferrals above.
  it "transcribes each materialized capability's ALLOW roles exactly as the table states them" do
    materialized.each do |capability|
      cells = rows.fetch(capability)
      deferred = deferred_cells.fetch(capability, {})
      ratified = role_columns.each_with_index.filter_map do |role, i|
        # The Service Identity column is not a canonical role and is never an assignment; it
        # names the service path that executes the command, so it is out of scope here. The
        # Read-Only Executive Buyer is not a canonical role either and is dimension 2's.
        next if ["Read-Only Executive Buyer", "Service Identity"].include?(role)
        next if cells[i] == "deny"

        # A deferral is honoured only if the cell STILL reads what it read when the deferral
        # was recorded. If the table is amended, the deferral stops applying and this fails.
        next if deferred[role] == cells[i]

        role
      end
      expect(Platform::PermissionBaseline::CAPABILITIES.fetch(capability)).to eq(ratified),
                                                                             "#{capability}: transcription disagrees with :135's role cells"
    end
  end

  # The deferral list is itself checked, so it cannot silently outlive the cell it excuses or
  # quietly suppress a capability that was never deferred in the first place.
  it "records a deferral only for a cell that is really there and really non-deny" do
    deferred_cells.each do |capability, cells|
      expect(materialized).to include(capability)
      cells.each do |role, expected_cell|
        actual = rows.fetch(capability)[role_columns.index(role)]
        expect(actual).to eq(expected_cell), "#{capability}/#{role}: the deferred cell has been amended"
        expect(actual).not_to eq("deny")
      end
    end
  end

  # Dimension 2 — THE CELL R3-10 FOUND MISSING. The Read-Only Executive Buyer is the tuple
  # `MarketingOperator` + `read_only` + `executive_buyer` (:314), not a canonical role, so
  # this column cannot live in a role-keyed map and has its own set.
  it "confers a capability on a read_only assignment exactly when the sixth cell is not `deny`" do
    index = role_columns.index("Read-Only Executive Buyer")

    materialized.each do |capability|
      ratified_allows = rows.fetch(capability)[index] != "deny"
      expect(Platform::PermissionBaseline.mode_permits?(capability, "read_only")).to eq(ratified_allows),
                                                                                     "#{capability}: read_only mode disagrees with :135's Read-Only Executive Buyer cell"
    end
  end

  # `standard` is unconstrained by the mode dimension — :314's meaning of the word — so the
  # mode check must not become a second, accidental deny for ordinary actors. Without this,
  # `mode_permits?` returning false for everything would satisfy the example above for as
  # long as every materialized cell reads `deny`.
  it "leaves `standard` assignments answering to the role cell alone" do
    materialized.each do |capability|
      expect(Platform::PermissionBaseline.mode_permits?(capability, "standard")).to be(true)
    end
  end

  # Dimension 3 — `PROTECTED` AGAINST `:333`, THE DIMENSION THAT DID NOT EXIST (FU-54 / R19-SEC-2).
  #
  # Dimensions 1 and 2 check `CAPABILITIES` against `:135`. `PROTECTED` is a transcription of a
  # DIFFERENT ratified statement — `:333`, which `:335` calls "the authority for which grants are
  # protected" — and nothing compared the two. It was THREE ENTRIES SHORT, deleting a ratified entry
  # left the entire suite green, and one omission was a live defect: BillingOperator's only protected
  # permission is `policy.entitlement.manage`, so omitting it made `protected_role?("BillingOperator")`
  # false and let a lone OrganizationAdmin mint an immediately-active never-expiring grant carrying
  # protected authority.
  #
  # The subject is DERIVED from the document, not restated beside it, so a permission added to or
  # removed from `:333` fails here rather than being found by a reviewer several rounds later.
  it "transcribes the ratified `:333` protected-grant enumeration exactly, and nothing more" do
    ratified = RatifiedPermissionBaseline.protected_transcription

    expect(ratified.keys.length).to be >= 18, "the :333 enumeration parsed to #{ratified.keys.length} " \
                                              "permissions, so this check is not reading it"
    expect(Platform::PermissionBaseline::PROTECTED).to eq(ratified),
                                                       "`PROTECTED` disagrees with :333 + :135; missing " \
                                                       "#{(ratified.keys - Platform::PermissionBaseline::PROTECTED.keys).inspect}, " \
                                                       "extra #{(Platform::PermissionBaseline::PROTECTED.keys - ratified.keys).inspect}"
  end

  # The `:333` exception list is itself checked, exactly as `deferred_cells` is for dimension 1: it
  # may not silently outlive the sentence that authorises it, and it may not quietly suppress an arm
  # the document never excepted.
  it "records a protected-role exception only where `:333` states one in words" do
    RatifiedPermissionBaseline.protected_role_exceptions.each do |permission, roles|
      expect(RatifiedPermissionBaseline.protected_permissions).to include(permission)
      roles.each do |role|
        expect(RatifiedPermissionBaseline.cell(permission, role)).not_to eq("deny"),
                                                                        "#{permission}/#{role} is excepted from " \
                                                                        "the protected transcription, but its " \
                                                                        "ratified cell already denies it"
      end
    end

    # The one exception the document states, quoted so the check fails if the sentence is amended.
    doc = Rails.root.join("specification/volume-i/WORKFLOW_SPECIFICATIONS.md").read
    expect(doc).to include("the OrganizationAdmin baseline cell permitting a closure request for the " \
                           "actor's own Organization is not a protected grant")
  end
end
