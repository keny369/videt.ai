# frozen_string_literal: true

require "rails_helper"

# THE LEASE RULE, READ FROM THE RATIFIED DOCUMENT AND ASSERTED AGAINST THE LIVE DATABASE.
#
# BACKGROUND_PROCESSING.md :288 is the authority for lease duration. Until ADR-095 the implementation
# disagreed with it in three ways at once and every behavioural example still passed, because each example
# restated the implementation's own numbers back to itself. THREE FUNCTIONS assign `lease_expires_at`, and
# the defect that survived a full review round was that one of them silently disagreed with the other two.
#
# This spec exists so the document and the database cannot drift apart again. It parses :288's own
# sentence for the floor, the grace and the cap, and fails if any of the three lease writers does not carry
# exactly those values — or if the cap is ever expressed as anything other than the OUTER bound.
RSpec.describe "ScheduledAction lease duration rule", type: :model do
  LEASE_RULE_DOC = Rails.root.join("specification/volume-ii/BACKGROUND_PROCESSING.md")

  # The three writers as they stand. This list is an EXPECTATION, not the input: `lease_writers` below
  # discovers them from the catalogue, and the two are cross-checked. An earlier draft of this spec
  # hardcoded the list and claimed in a comment that "a fourth would have to be added here deliberately" —
  # which was itself a false claim of the kind this file exists to catch, because nothing enforced it and a
  # fourth writer would simply have gone unchecked. That is the original defect one level up.
  EXPECTED_LEASE_WRITERS = %w[
    f1_claim_due_scheduled_actions
    f1_dispatch_scheduled_action
    f1_heartbeat_scheduled_action
  ].freeze

  # A lease ASSIGNMENT is `lease_expires_at = <expr>`. Clearing it to NULL is a release, not a lease, and
  # the five release/settle/cancel/sweep functions legitimately do exactly that.
  def lease_writers
    # MATERIALIZED so the namespace/kind filter is applied BEFORE `pg_get_functiondef`, which raises on an
    # aggregate and would otherwise fail on `pg_catalog`'s own entries if the planner inlined the CTE.
    rows = DbInspector.all(
      "WITH candidates AS MATERIALIZED (
         SELECT p.oid, p.proname FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.prokind = 'f'
       )
       SELECT proname AS name, pg_get_functiondef(oid) AS def
         FROM candidates
        WHERE pg_get_functiondef(oid) LIKE '%lease_expires_at =%'
        ORDER BY proname"
    )

    rows.filter_map do |row|
      assignments = assigned_expressions(row.fetch("def")).reject { |e| e.casecmp?("null") }
      next if assignments.empty?

      [row.fetch("name"), assignments]
    end.to_h
  end

  # Every right-hand side of `lease_expires_at = ...`, taken by BALANCING PARENTHESES rather than by
  # stopping at the first comma or newline — the expression is multi-line and full of both, and a regex
  # that guesses its shape would silently truncate it and then assert against the fragment.
  def assigned_expressions(body)
    body.to_enum(:scan, /lease_expires_at = /).map { Regexp.last_match.end(0) }.map do |start|
      depth = 0
      finish = start
      while finish < body.length
        char = body[finish]
        depth += 1 if char == "("
        depth -= 1 if char == ")"
        break if depth.zero? && (char == "," || char == "\n")

        finish += 1
      end
      body[start...finish].strip.gsub(/\s+/, " ")
    end
  end

  # :288's sentence, parsed rather than restated:
  #   "Lease duration is `max(60 seconds, product_attempt_deadline - claim_time + 30 seconds)` capped at
  #    15 minutes."
  let(:ratified) do
    sentence = LEASE_RULE_DOC.read[/^Lease duration is .*$/]
    raise "the :288 lease-duration sentence is not present" if sentence.nil?

    match = sentence.match(
      /max\((?<floor>\d+) seconds, product_attempt_deadline - claim_time \+ (?<grace>\d+) seconds\)` capped at (?<cap>\d+) minutes/
    )
    raise "the :288 lease-duration sentence has changed shape: #{sentence}" if match.nil?

    { floor: match[:floor].to_i, grace: match[:grace].to_i, cap_minutes: match[:cap].to_i, sentence: }
  end

  it "is written by exactly the functions we think write it" do
    # DISCOVERED FROM THE CATALOGUE, then compared. A new lease writer added later and not thought about
    # fails HERE, which is the check the original defect needed and did not have.
    expect(lease_writers.keys).to match_array(EXPECTED_LEASE_WRITERS)
  end

  it "is implemented identically by every function that assigns a lease" do
    writers = lease_writers
    expressions = writers.values.flatten.uniq

    expect(expressions.length).to eq(1),
                                  "lease writers disagree:\n#{writers.map { |n, e| "#{n}: #{e.join(' | ')}" }.join("\n")}"
  end

  it "carries the floor, the grace and the cap the document ratifies" do
    lease_writers.each_value do |expressions|
      expressions.each do |expression|
        expect(expression).to include("interval '#{ratified[:floor]} seconds'")
        expect(expression).to include("+ interval '#{ratified[:grace]} seconds'")
        expect(expression).to include("interval '#{ratified[:cap_minutes]} minutes'")
        expect(expression).to include("a.product_attempt_deadline - v_now")
      end
    end
  end

  it "applies the cap as the OUTER bound, so no caller request can escape it" do
    # The defect this pins: the cap was first written `greatest(interval '15 minutes', <caller request>)`,
    # which raises the ceiling to whatever the caller asked for. :288 now says the cap is absolute.
    lease_writers.each do |name, expressions|
      expressions.each do |expression|
        expect(expression).to match(/\Av_now \+ least\(.*interval '#{ratified[:cap_minutes]} minutes'\)\z/),
                              "#{name} does not apply the cap as the outer bound: #{expression}"
        expect(expression).not_to include("greatest(interval '#{ratified[:cap_minutes]} minutes'")
      end
    end
    expect(ratified[:sentence]).to include("The cap is absolute")
  end

  it "derives ONLY from database time and the stored deadline, never from a caller instant" do
    # :114 makes PostgreSQL transaction time the sole lease authority. The expression may read `v_now` and
    # the immutable stored column, and nothing else that carries an instant.
    lease_writers.each do |name, expressions|
      expressions.each do |expression|
        expect(expression).to start_with("v_now +"),
                              "#{name} does not derive its lease from transaction time"
        expect(expression).not_to match(/\bnow\(\)|clock_timestamp|statement_timestamp/),
                                  "#{name} derives its lease from something other than transaction time"
      end
    end
  end

  it "satisfies lease > interval + max_hop at the floor, which the superseded 30 did not" do
    # The arithmetic :288's correction turns on, computed from the ratified ceilings rather than written
    # as a literal. `max_hop` is the resolver timeout, taken OUTSIDE the per-hop deadline, plus the hard
    # request timeout.
    max_hop = Platform::Outbound::Ceilings::DNS_TIMEOUT_MAX_S +
              Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING.fetch("request_timeout_seconds").fetch("hard")

    interval_at = lambda do |lease|
      Platform::ScheduledActions::LeaseKeeper.new(
        action_id: SecureRandom.uuid_v7, owner: SecureRandom.uuid_v7, generation: 1, lease_seconds: lease
      ).interval
    end

    expect(ratified[:floor]).to be > interval_at.call(ratified[:floor]) + max_hop
    expect(30).not_to be > interval_at.call(30) + max_hop
  end
end
