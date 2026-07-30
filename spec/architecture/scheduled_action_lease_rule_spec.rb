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

  # Every function that assigns a lease. A fourth would have to be added here deliberately, which is the
  # point: the original defect was a third writer nobody remembered to change.
  LEASE_WRITERS = %w[
    f1_claim_due_scheduled_actions
    f1_dispatch_scheduled_action
    f1_heartbeat_scheduled_action
  ].freeze

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

  def lease_expression(function_name)
    body = DbInspector.one(
      "SELECT pg_get_functiondef(p.oid) AS def FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = $1", [function_name]
    )&.fetch("def")
    raise "#{function_name} does not exist" if body.nil?

    match = body.match(/lease_expires_at = v_now \+ (?<expr>.*?interval '15 minutes'\))/m)
    raise "#{function_name} does not assign a capped lease" if match.nil?

    match[:expr].gsub(/\s+/, " ")
  end

  it "is implemented identically by every function that assigns a lease" do
    expressions = LEASE_WRITERS.map { |name| lease_expression(name) }

    expect(expressions.uniq.length).to eq(1),
                                       "lease writers disagree:\n#{LEASE_WRITERS.zip(expressions).map { |n, e| "#{n}: #{e}" }.join("\n")}"
  end

  it "carries the floor, the grace and the cap the document ratifies" do
    expression = lease_expression(LEASE_WRITERS.first)

    expect(expression).to include("interval '#{ratified[:floor]} seconds'")
    expect(expression).to include("+ interval '#{ratified[:grace]} seconds'")
    expect(expression).to include("interval '#{ratified[:cap_minutes]} minutes'")
    expect(expression).to include("a.product_attempt_deadline - v_now")
  end

  it "applies the cap as the OUTER bound, so no caller request can escape it" do
    # The defect this pins: the cap was first written `greatest(interval '15 minutes', <caller request>)`,
    # which raises the ceiling to whatever the caller asked for. :288 now says the cap is absolute.
    expression = lease_expression(LEASE_WRITERS.first)

    expect(expression).to match(/\Aleast\(.*interval '#{ratified[:cap_minutes]} minutes'\)\z/)
    expect(expression).not_to include("greatest(interval '#{ratified[:cap_minutes]} minutes'")
    expect(ratified[:sentence]).to include("The cap is absolute")
  end

  it "derives ONLY from database time and the stored deadline, never from a caller instant" do
    # :114 makes PostgreSQL transaction time the sole lease authority. The expression may read `v_now` and
    # the immutable stored column, and nothing else that carries an instant.
    LEASE_WRITERS.each do |name|
      expression = lease_expression(name)
      expect(expression).not_to match(/\bnow\(\)|clock_timestamp|statement_timestamp/),
                                "#{name} derives its lease from something other than transaction time"
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
