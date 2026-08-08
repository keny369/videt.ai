# frozen_string_literal: true

# The vocabulary the findings screen uses, in one place.
#
# THE FIVE STATES ARE NOT INTERCHANGEABLE, and presenting any of them as another is the
# defect this module exists to prevent:
#
#   * PASSED — the check ran and the site met it.
#   * FINDING — the check ran and the site did not meet it. This is the only one that
#     becomes an Issue.
#   * NOT MEASURED — the check ran and its evidence was missing, stale, indeterminate or
#     invalid. Nothing is wrong with the site and nothing is broken in the product: under
#     the RATIFIED OD-010 baseline, `external-measurement-v1` bundles no query, intent,
#     listing, provider or adapter set, so the four measurement checks deterministically
#     select no evidence and say so.
#   * NOT APPLICABLE — the check does not apply to this project at all. Valid for local
#     presence only, and only from a project profile that validly records it.
#   * UNAVAILABLE — the overall score, when a pillar has no sufficient evidence.
#
# "Unavailable" is not "broken" and must never be rendered as an error. It is the approved
# baseline outcome of a measurement set that has not been activated, and the sentence says
# so plainly rather than apologising for it.
module FindingsHelper
  STATUS_LABELS = {
    "passed" => "Passed",
    "failed" => "Finding",
    "error" => "Not measured",
    "not_applicable" => "Not applicable"
  }.freeze

  # The human name of each ratified check, so the screen reads as a report rather than as a
  # list of identifiers. The identifier is still shown beside it, because it is what an
  # operator quotes.
  CHECK_NAMES = {
    "CHK-TI-001" => "Internal links resolve",
    "CHK-CQ-001" => "Page title present and single",
    "CHK-TR-001" => "Organization identity published",
    "CHK-SP-001" => "Search index presence",
    "CHK-AIP-001" => "AI answer presence",
    "CHK-AS-001" => "Attributable authority references",
    "CHK-LP-001" => "Local profile consistency"
  }.freeze

  PILLAR_NAMES = {
    "technical_integrity" => "Technical integrity",
    "content_quality" => "Content quality",
    "trust_signals" => "Trust signals",
    "search_presence" => "Search presence",
    "ai_presence" => "AI presence",
    "authority_signals" => "Authority signals",
    "local_presence" => "Local presence"
  }.freeze

  # Why a check could not be measured, in the reader's terms. The reason codes are the
  # contract's, and each maps to one sentence that says whose problem it is — because the
  # difference between "we have not collected this yet" and "your site returned something we
  # could not read" is the whole value of showing the reason at all.
  # Why each check matters, in the customer's terms. One sentence, no hedging, and no promise the
  # check does not actually make — CHK-AIP-001 measures whether a business is NAMED AND CITED, not
  # whether what was said about it is true, and the sentence says exactly that.
  WHY_IT_MATTERS = {
    "CHK-TI-001" => "A link that goes nowhere costs a visitor the page they wanted and tells a " \
                    "search engine the site is not maintained.",
    "CHK-CQ-001" => "The title is the line a person reads in a result list before deciding " \
                    "whether to click. One per page, and it has to say something.",
    "CHK-TR-001" => "Published Organization data is how a machine confirms the business is who " \
                    "it says it is. Without it, a machine has only prose to go on.",
    "CHK-SP-001" => "If the business is not in the index for the questions its buyers ask, it " \
                    "cannot be found by asking them.",
    "CHK-AIP-001" => "When a buyer asks an assistant for a recommendation, this measures whether " \
                     "the business is named and its own site cited. It does not measure whether " \
                     "what was said about it is accurate.",
    "CHK-AS-001" => "An attributable reference from somewhere else is the difference between a " \
                    "business asserting its reputation and something corroborating it.",
    "CHK-LP-001" => "Inconsistent local listings split a business's identity across directories " \
                    "and make it harder to place."
  }.freeze

  NOT_MEASURED_REASONS = {
    "input_evidence_missing" =>
      "No measurement has been collected for this check yet. External measurement is not " \
      "switched on for this project, so there is nothing to compare against. Nothing is wrong " \
      "with your site.",
    "input_evidence_stale" =>
      "The measurement behind this check had expired by the time the crawl was sealed.",
    "input_evidence_indeterminate" =>
      "The crawl did not observe everything this check needs, so it will not report a pass or " \
      "a failure over a set it did not see.",
    "input_evidence_invalid" =>
      "The evidence for this check did not match its expected shape, so it was not used.",
    "normalized_input_invalid" =>
      "The parsed content behind this check could not be normalized, so it was not used.",
    "output_schema_invalid" =>
      "This check produced a result that did not match its declared shape, so it was discarded.",
    "check_dependency_unavailable" => "A dependency this check needs was unavailable.",
    "check_internal_timeout" => "This check did not finish inside its time limit."
  }.freeze

  def check_name(definition_id) = CHECK_NAMES.fetch(definition_id, definition_id)
  def why_it_matters(definition_id) = WHY_IT_MATTERS[definition_id]
  def pillar_name(pillar_id) = PILLAR_NAMES.fetch(pillar_id, pillar_id.to_s.tr("_", " "))
  def finding_status_label(status) = STATUS_LABELS.fetch(status, status)

  def not_measured_reason(code)
    NOT_MEASURED_REASONS[code] || "This check could not be measured (#{code})."
  end

  # The subject a result is about, in the form a reader recognizes. A `url` subject IS the
  # address; a `source` or `project` subject is an opaque identifier, and showing a raw UUID
  # to a person is worse than naming what it refers to.
  def finding_subject(result)
    case result["canonical_subject_type"]
    when "url" then result["canonical_subject_key"]
    when "source" then "This source"
    else "This project"
    end
  end

  # THE OBSERVED VALUE, in the Definition's own terms. This is what the check actually measured,
  # rendered from the normalized observation the Result froze — never recomputed, because the
  # Result is the authority for its own history and a second derivation could disagree with it.
  #
  # `nil` when there is nothing to state: an unmeasured check observed nothing, and inventing a
  # "0 of 5" for it would report a measurement that was never taken.
  def observed_value(result)
    return nil unless %w[passed failed].include?(result["execution_status"])

    observation = JSON.parse(result["normalized_observation"].to_s.presence || "{}")
    case result["check_definition_id"]
    when "CHK-TI-001"
      "#{observation['absent_count']} of #{observation['total_target_count']} linked pages missing"
    when "CHK-CQ-001"
      "#{observation['nonblank_title_count']} usable #{'title'.pluralize(observation['nonblank_title_count'].to_i)}"
    when "CHK-TR-001"
      "#{observation['matching_node_count']} of #{observation['node_count']} Organization records match"
    when "CHK-SP-001"
      "present for #{rate_as_fraction(observation['present_count'], observation['expected_count'])} queries"
    when "CHK-AIP-001"
      "named and cited for #{rate_as_fraction(observation['qualified_count'], observation['expected_count'])} intents"
    when "CHK-AS-001"
      "#{observation['attributable_count']} attributable of #{observation['total_count']} references"
    when "CHK-LP-001"
      "#{observation['qualified_count']} of #{observation['required_count']} listings consistent"
    end
  rescue JSON::ParserError
    nil
  end

  def rate_as_fraction(part, whole) = "#{part.to_i} of #{whole.to_i}"

  # The per-intent detail an external check produces: which questions were asked, whether the
  # business was named, and whether its own site was cited. Empty for a check that measured
  # nothing, which is the common case at the ratified baseline.
  def measured_items(result)
    observation = JSON.parse(result["normalized_observation"].to_s.presence || "{}")
    observation["unqualified_intent_keys"] || observation["absent_query_keys"] ||
      observation["nonqualified_listing_keys"] || []
  rescue JSON::ParserError
    []
  end

  # Observation freshness, stated as its own fact. A stale observation is NOT a missing one, and
  # the two must never read the same: one says the measurement expired, the other says it was
  # never taken.
  def freshness_label(result)
    return nil unless result["error_reason_code"] == "input_evidence_stale"

    "Measurement expired"
  end

  # One group per Definition, because a per-Document check produces one Result per page and a
  # 226-row table is not a report anyone can read. The group states the counts and the page lists
  # the FAILING subjects; a reader who needs every passing URL has the Documents table below.
  #
  # Grouping never merges outcomes: a Definition whose Results disagree shows the worst one, and
  # the counts say how many landed where, so "225 passed, 1 failed" cannot be rounded to "passed".
  CheckGroup = Data.define(:definition_id, :pillar_id, :results, :worst) do
    def count = results.length
    def failures = results.select { |r| r["execution_status"] == "failed" }
    def by_status = results.group_by { |r| r["execution_status"] }.transform_values(&:length)
  end

  # Worst-first, so the thing a reader must act on is the thing they see.
  STATUS_SEVERITY = { "failed" => 0, "error" => 1, "not_applicable" => 2, "passed" => 3 }.freeze

  def check_groups(results)
    results.group_by { |r| r["check_definition_id"] }.map do |definition_id, group|
      worst = group.min_by { |r| STATUS_SEVERITY.fetch(r["execution_status"], 9) }
      CheckGroup.new(definition_id:, pillar_id: worst["pillar_id"], results: group, worst:)
    end.sort_by { |g| [STATUS_SEVERITY.fetch(g.worst["execution_status"], 9), g.definition_id] }
  end

  # What the group observed, across every subject it ran against. A single-subject check states
  # its own observed value; a per-page check states the tally, which is the only summary that
  # does not lose the failing page.
  def group_observed(group)
    return observed_value(group.worst) || "—" if group.count == 1

    counts = group.by_status
    parts = []
    parts << "#{counts['passed']} of #{group.count} pages pass" if counts["passed"]
    parts << "#{counts['failed']} #{'page'.pluralize(counts['failed'])} #{counts['failed'] == 1 ? 'fails' : 'fail'}" if counts["failed"]
    parts << "#{counts['error']} not measured" if counts["error"]
    parts.join(", ")
  end

  # The one sentence about the overall score. It is derived from the pillars that have
  # insufficient evidence, so it explains the state rather than asserting it.
  def score_unavailable_sentence(results)
    insufficient = results.select { |r| r["execution_status"] == "error" }
                          .map { |r| pillar_name(r["pillar_id"]) }.uniq.sort
    return "A score is available for this evaluation." if insufficient.empty?

    "No overall score is shown, because #{to_sentence_list(insufficient.map(&:downcase))} " \
      "#{insufficient.one? ? 'has' : 'have'} no sufficient evidence yet. This is expected: " \
      "external measurement is not switched on, and the platform will not publish a number it " \
      "cannot support."
  end

  def to_sentence_list(items)
    return items.first.to_s if items.length <= 1

    "#{items[0..-2].join(', ')} and #{items.last}"
  end
end
