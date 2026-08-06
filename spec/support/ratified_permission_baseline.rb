# frozen_string_literal: true

# THE RATIFIED PERMISSION BASELINE TABLE, PARSED ONCE (FU-63 part 1).
#
# WHY THIS EXISTS. `spec/architecture/permission_baseline_transcription_spec.rb` already reads
# WORKFLOW_SPECIFICATIONS.md § Permission Baseline (:135) and compares `Platform::PermissionBaseline`
# against it, in the shape `scheduled_action_catalogue_spec.rb` established. FU-63 needs the SAME
# table for a different question — not "does the Ruby transcribe the cells" but "which roles does a
# cell DENY", so the negative population of the write battery is DERIVED from the ratified document
# instead of hand-picked one role at a time.
#
# Two questions, ONE parser. A second copy of the parse is the defect class this tranche exists to
# remove: the round-19 repair carried its own copies of two derivations (FU-60) and the round-20
# review found both unbound. So the transcription spec and the battery read this module, and a
# regex that silently stopped matching fails `parsed!` for both rather than making one of them
# vacuously green.
#
# IT IS A MODULE, NOT A CONSTANT. A constant assigned inside an `RSpec.describe` block lands on
# Object, so two spec files can silently read each other's document — FU-42, reproduced and still
# open. Nothing here is assigned at spec level.
module RatifiedPermissionBaseline
  module_function

  DOC = "specification/volume-i/WORKFLOW_SPECIFICATIONS.md"

  # The column headings, in order, of the § Permission Baseline table.
  def role_columns
    ["OrganizationAdmin", "MarketingOperator", "TechnicalImplementer", "SecurityOperator",
     "BillingOperator", "Read-Only Executive Buyer", "Service Identity"].freeze
  end

  # The columns that ARE canonical roles. "Read-Only Executive Buyer" is the tuple
  # `MarketingOperator` + `read_only` + `executive_buyer` (:314) and "Service Identity" names the
  # service path that executes the command; neither is a role an Assignment can hold, so neither is
  # a candidate for a `canonical_role` case.
  def canonical_role_columns
    role_columns - ["Read-Only Executive Buyer", "Service Identity"]
  end

  # Every row of the table as { capability => [cell, ...] }. A row names one or more backticked
  # capabilities in its first cell and shares its cells between them, which is how
  # `crawl.trigger`, `crawl.cancel` come to be one row.
  def rows
    @rows ||= parse
  end

  # The guard on the parser itself, asserted before any derived population is used. A regex that
  # matched nothing would make every derived case vacuously true, which is the failure mode this
  # module exists to prevent.
  def parsed!
    raise "the Permission Baseline table parsed to #{rows.size} rows" if rows.size < 20

    rows
  end

  def cells(capability)
    parsed!.fetch(capability) { raise "#{capability} is not a row of the ratified Permission Baseline" }
  end

  def cell(capability, role)
    index = role_columns.index(role) or raise "#{role} is not a column of the ratified table"
    cells(capability)[index]
  end

  # EVERY CANONICAL ROLE WHOSE RATIFIED CELL READS `deny`, for one capability.
  #
  # This is the battery's negative population. Hand-picking one role — `TechnicalImplementer`, as
  # round 19 did — binds the role conjunct against one value and leaves the rest assumed, which is
  # precisely R20-2: widening `allowed_roles` by `SecurityOperator` survived the full corpus and,
  # driven, cancelled a Crawl. A role the table later starts allowing drops out of this set by
  # itself, and a newly denied one joins it, so the population cannot drift from the document.
  def denied_roles(capability)
    row = cells(capability)
    canonical_role_columns.select { |role| row[role_columns.index(role)] == "deny" }
  end

  # THE RATIFIED PROTECTED-GRANT ENUMERATION (`:333`), which `:335` calls "the authority for which
  # grants are protected" (FU-54).
  #
  # It is one sentence of prose ending "are protected.", and every permission it names is backticked
  # — including the `organization.close` arm, which it names as "a SecurityOperator `organization.close`
  # approval grant". So the enumeration is the backticked tokens of that sentence, and nothing else in
  # the document is read for it.
  def protected_permissions
    @protected_permissions ||= begin
      sentence = Rails.root.join(DOC).read[/Grants containing (.*?) are protected\./m, 1]
      raise "the :333 protected-grant enumeration was not found in #{DOC}" if sentence.nil?

      names = sentence.scan(/`([a-z][a-z._]*)`/).flatten.uniq
      raise "the :333 enumeration parsed to #{names.length} permissions" if names.length < 15

      names
    end
  end

  # `:333` NAMES ONE ARM OF ONE ROW RATHER THAN THE WHOLE ROW, AND SAYS SO IN WORDS.
  #
  # "A SecurityOperator `organization.close` grant authorizes only closure approval or rejection; the
  # OrganizationAdmin baseline cell permitting a closure request for the actor's own Organization is
  # not a protected grant and is unchanged." Every other named permission takes its whole non-deny
  # row. The exception is recorded here, as data, so that ADDING one is a visible act — the shape
  # `permission_baseline_transcription_spec.rb`'s `deferred_cells` already establishes.
  def protected_role_exceptions
    { "organization.close" => %w[OrganizationAdmin] }.freeze
  end

  # The roles each ratified protected permission is protected FOR: every canonical role whose `:135`
  # cell is not `deny`, minus the recorded exception above. This is the derivation
  # `Platform::PermissionBaseline::PROTECTED` must equal.
  def protected_transcription
    protected_permissions.to_h do |permission|
      allowed = canonical_role_columns.reject { |role| cell(permission, role) == "deny" }
      [permission, allowed - protected_role_exceptions.fetch(permission, [])]
    end
  end

  # Every canonical role that holds at least one ratified protected permission — the population a
  # protected-grant refusal must cover.
  def protected_canonical_roles
    protected_transcription.values.flatten.uniq.sort
  end

  def parse
    section = Rails.root.join(DOC).read.split(/^### /).find { |s| s.start_with?("Permission Baseline") }
    raise "the Permission Baseline section was not found in #{DOC}" if section.nil?

    lines = section.lines.select { |l| l.start_with?("| `") }
    raise "the Permission Baseline table parsed to no rows" if lines.empty?

    lines.each_with_object({}) do |line, acc|
      cells = line.split("|").map(&:strip)[1..]
      next if cells.nil? || cells.size < role_columns.size + 1

      cells[0].scan(/`([a-z][a-z._]*)`/).flatten.each { |capability| acc[capability] = cells[1, role_columns.size] }
    end
  end
end
