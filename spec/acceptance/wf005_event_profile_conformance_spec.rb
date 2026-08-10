# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# THE EMITTED CRAWL EVENTS ARE COMPARED TO THE CLOSED PROFILES, BY EXECUTION (FU-33, FU-67).
#
# WHAT WAS OPEN. API_CONTRACTS.md :933 says a selected profile has "the exact base members below,
# followed by exactly the members in its catalogue-selected extra schema" and that "there is no
# free-form `details`, `metadata`, `attributes` or extension object". Four of WF-005's Crawl-aggregate
# events disagreed with that, in BOTH directions at once — `CrawlQueued` carried seven members and not
# one of them belonged to its profile — and the whole acceptance corpus stayed green, because nothing
# in it read an event payload against the contract. That is the evidence gap, and it is why FU-33 and
# FU-67 sat open for two tranches while the delta was re-measured by hand each time.
#
# THE SUBJECT IS THE EMITTED BYTES, NOT THE SOURCE. `event_registry.event_bytes` is what a consumer
# receives and what `event_sha256` is computed over. A source-reading check would pass on a payload
# the ledger then reshaped.
#
# THE EXPECTATION IS DERIVED FROM THE RATIFIED DOCUMENT, NOT TRANSCRIBED. The root member set comes
# from API_CONTRACTS.md's "The root object has exactly ..." sentence; the profile base members and the
# extra-schema members come from the two "Closed profile payloads" tables. A member added to any of
# them in the contract becomes required here with no edit to this file, which is the whole reason the
# hand-maintained delta in FU-33 kept going stale.
#
# ---------------------------------------------------------------------------------------------
# WHAT THIS FILE DELIBERATELY DOES NOT ASSERT, AND THE FOLLOW-UP THAT CARRIES IT.
#
# API_CONTRACTS.md :703 makes `event_payload` a NESTED object on the event root and enumerates the
# root's exact members. NO EMITTER IN THIS REPOSITORY NESTS IT: every one of the twenty-odd envelope
# builders across WF-001 to WF-013 flattens its profile members into the root and adds root members
# :703 does not admit — `account_id`, `requester_account_id`, `organization_epoch`, `state_version`,
# `scheduled_action_id` — while omitting `related_entities`, `governing_versions` and `output_hash`.
# That is a platform-wide envelope question, not the profile question FU-33 and FU-67 describe, and it
# is NOT decided or repaired here. `ENVELOPE_SURPLUS` below names exactly the five surplus root members
# that exist today so that a SIXTH fails this gate, and FU-74 carries the envelope shape itself.
#
# It also corrects FU-33's control claim: the S-07-010 events conform at the PROFILE-MEMBER level,
# which is what that note measured, and not at the envelope level, where nothing in the repository
# does.
RSpec.describe "WF-005 Crawl events carry exactly their closed profile's members",
               type: :acceptance, acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
               test_types: %w[TYP-DATA] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  CONTRACT = Rails.root.join("specification/volume-ii/API_CONTRACTS.md")

  # A `name: type` pair inside backticks. The contract's prose also backticks BARE member names when
  # it refers back to one ("committed version equals root `aggregate_version`"), and those are not
  # declarations — requiring the colon is what separates a declaration from a reference.
  DECLARATION = /`([a-z_][a-z0-9_]*): [^`]+`/

  # The five root members the implementation adds and :703 does not admit. Named, not tolerated
  # silently: a sixth fails the gate. FU-74.
  ENVELOPE_SURPLUS = %w[account_id requester_account_id organization_epoch state_version
                        scheduled_action_id].freeze

  def contract = @contract ||= CONTRACT.read

  # ":703 — The root object has exactly ..." up to the sentence that closes the enumeration.
  def root_members
    @root_members ||= begin
      sentence = contract[/The root object has exactly (.*?)Optional `notification_context_v1`/m, 1]
      raise "the root-object enumeration did not parse" if sentence.nil?

      sentence.scan(DECLARATION).flatten.uniq
    end
  end

  # A row of either "Closed profile payloads" table, keyed by the name in its first cell.
  def schema_row(name)
    row = contract[/^\| `#{Regexp.escape(name)}` \| (.*)$/, 1]
    raise "no closed-profile row for #{name.inspect}" if row.nil?

    row.scan(DECLARATION).flatten.uniq
  end

  def profile_members(profile, extra_schema)
    (schema_row(profile) + (extra_schema == "none" ? [] : schema_row(extra_schema))).uniq
  end

  # Every event this chain wrote against the Crawl aggregate, newest last, decoded from the bytes a
  # consumer would receive.
  def crawl_events(org)
    DbInspector.all(<<~SQL, [org]).map { |r| [r["event_type"], r["event_profile"], JSON.parse(r["body"])] }
      SELECT event_type, event_profile, convert_from(event_bytes,'UTF8') AS body
      FROM event_registry
      WHERE organization_id = $1::uuid AND aggregate_type = 'crawl'
      ORDER BY created_at, id
    SQL
  end

  # Every Crawl event carries the `crawl_terminal` extra schema (API_CONTRACTS.md :801-808).
  EXTRA_SCHEMA = "crawl_terminal"

  def assert_conformant(type, profile, body)
    required = profile_members(profile, EXTRA_SCHEMA)
    missing = required - body.keys
    expect(missing).to be_empty,
                       "#{type} (#{profile} + #{EXTRA_SCHEMA}) omits #{missing.join(', ')}. " \
                       "API_CONTRACTS.md :933 requires the exact base members followed by exactly " \
                       "the extra schema's members; :938's consumer rule REJECTS a missing required " \
                       "member and DEFINES a null one, so absent and null are different bytes."

    surplus = body.keys - required - root_members - ENVELOPE_SURPLUS
    expect(surplus).to be_empty,
                       "#{type} (#{profile} + #{EXTRA_SCHEMA}) carries #{surplus.join(', ')}, which " \
                       "is neither a root member nor a member of its closed profile. :933 admits no " \
                       "free-form extension object, so there is nowhere for these to live."
  end

  # ---- the parse itself, before anything depends on it -------------------------------------------
  #
  # A spec that derives its expectation from a document must assert the derivation, or a format change
  # empties the expectation and every check below passes vacuously. This is the R3-8/R3-9 class.
  it "parses a non-trivial root member set and profile schemas out of the ratified contract" do
    expect(root_members).to include("event_id", "event_type", "event_profile", "organization_id",
                                    "project_id", "affected_entity_id", "aggregate_version",
                                    "reason_code", "outcome", "audit_record_id", "event_payload")
    expect(root_members.length).to be >= 20, "the root enumeration parsed #{root_members.length} members"

    expect(schema_row("created")).to contain_exactly("from_state", "to_state", "prior_aggregate_version",
                                                     "committed_aggregate_version")
    expect(schema_row("state_transition")).to contain_exactly("from_state", "to_state",
                                                              "prior_aggregate_version",
                                                              "committed_aggregate_version",
                                                              "transition_reason_code")
    expect(schema_row(EXTRA_SCHEMA)).to contain_exactly("coverage_status", "completion_reason",
                                                        "accepted_document_count")
  end

  it "emits a conformant CrawlQueued and CrawlStarted, and nothing the profile does not admit" do
    ctx = running_crawl
    events = crawl_events(ctx[:g][:organization_id])

    expect(events.map(&:first)).to eq(%w[CrawlQueued CrawlStarted])
    events.each { |type, profile, body| assert_conformant(type, profile, body) }

    queued = events.first.last
    expect(queued["from_state"]).to be_nil
    expect(queued["prior_aggregate_version"]).to be_nil
    expect(queued["to_state"]).to eq("queued")
    expect(queued["committed_aggregate_version"]).to eq(queued["aggregate_version"])

    started = events.last.last
    # :938 — "committed version equals root aggregate version and prior is lower".
    expect(started["committed_aggregate_version"]).to eq(started["aggregate_version"])
    expect(started["prior_aggregate_version"]).to be < started["committed_aggregate_version"]
    # :956 — "values are null/zero before terminal derivation".
    expect(started["coverage_status"]).to be_nil
    expect(started["completion_reason"]).to be_nil
    expect(started["accepted_document_count"]).to eq(0)
  end

  it "keeps the two CAP-007 per-Source counts in the audit record they were re-homed to, not deleted" do
    # THE OWNER'S DECISION IS RE-HOMED, NOT DELETED. `frontier_root_count` and
    # `excluded_inactive_source_count` were added to `CrawlStarted` deliberately, because CAP-007
    # observability requires them and they "make a queue-time/execution-time Source-set divergence
    # visible". They leave the closed event payload, which cannot hold them, and this requires them to
    # still be readable where WF-005's own Audit and Observability obligation puts "per-Source root
    # status" — the audit record.
    ctx = running_crawl
    audit = DbInspector.one(<<~SQL, [ctx[:crawl_id]])
      SELECT payload FROM audit_record_registry
      WHERE entity_id = $1::uuid AND to_state = 'running' ORDER BY occurred_at DESC LIMIT 1
    SQL
    payload = JSON.parse(audit["payload"])

    expect(payload).to include("frontier_root_count", "excluded_inactive_source_count",
                               "pinned_source_count")
    expect(payload["frontier_root_count"]).to eq(1)

    # And gone from the event, which is the half the contract requires.
    started = crawl_events(ctx[:g][:organization_id]).last.last
    expect(started).not_to include("frontier_root_count", "excluded_inactive_source_count")
  end

  it "emits a conformant CrawlCanceled" do
    ctx = running_crawl
    result = Workflows::Wf005::Handlers::CancelCrawl.new.call(
      command: Workflows::Wf005::Commands::CancelCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "conf-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: ctx[:g][:session_id],
        organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id],
        expected_state_version: DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                                [ctx[:crawl_id]])["state_version"].to_i,
        requested_at_utc: start_now + 60
      ), request_context: act_ctx
    )
    expect(result.success?).to be(true)

    # SELECTED BY TYPE, NOT BY POSITION. `CancelCrawl` runs on the actor clock (`act_now`) and
    # `StartCrawl` on the executor clock 30 seconds later, so the cancellation's `occurred_at` is
    # EARLIER than the start it terminated and "the last event" is not the one just written.
    type, profile, body = crawl_events(ctx[:g][:organization_id]).find { |t, _, _| t == "CrawlCanceled" }
    expect(type).to eq("CrawlCanceled")
    assert_conformant(type, profile, body)
    expect(body["committed_aggregate_version"]).to eq(body["aggregate_version"])
    expect(body["prior_aggregate_version"]).to be < body["committed_aggregate_version"]
    # :808 gives `CrawlCanceled` the reason source `transition`, so :938 requires root `reason_code`
    # to equal `transition_reason_code` exactly.
    expect(body["reason_code"]).to eq(body["transition_reason_code"])
    expect(body["accepted_document_count"]).to eq(0)
  end

  # THE TERMINAL CHECKPOINT'S OWN ENVELOPE, WHICH IS THE HALF FU-67 NAMED EXPLICITLY. A run with no
  # accepted Document terminalizes as `CrawlFailed`; the envelope builder is shared with
  # `CrawlCompleted`, so one drive covers both shapes.
  it "emits a conformant terminal envelope from the checkpoint" do
    ctx = running_crawl
    action = DbInspector.all(<<~SQL, [ctx[:crawl_id]]).min_by { |a| Time.parse(a["due_at"]) }
      SELECT * FROM scheduled_actions
      WHERE action_kind = 'crawl_terminal_deadline' AND target_id = $1::uuid ORDER BY due_at
    SQL
    expect(action).not_to be_nil, "the start committed no terminal checkpoint to drive"

    at = Time.parse(action["due_at"]).getutc
    result = Workflows::Wf005::Handlers::CompleteCrawl.new.call(
      command: Workflows::Wf005::Commands::CompleteCrawl.new(
        command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
        organization_id: action["organization_id"], target_type: action["target_type"],
        crawl_id: action["target_id"], due_at: at, action_id: action["id"],
        action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
        requested_at_utc: at
      ), request_context: executor_ctx(at)
    )
    expect(result.success?).to be(true)

    type, profile, body = crawl_events(ctx[:g][:organization_id])
                          .find { |t, _, _| %w[CrawlCompleted CrawlFailed].include?(t) }
    expect(type).not_to be_nil, "the checkpoint emitted no terminal event"
    assert_conformant(type, profile, body)
    expect(body["committed_aggregate_version"]).to eq(body["aggregate_version"])
    expect(body["prior_aggregate_version"]).to be < body["committed_aggregate_version"]
    expect(body["from_state"]).to eq("running")
  end

  it "compares against a real, non-empty member set, so conformance is not conformance with nothing" do
    # NON-VACUITY OF THE COMPARISON ITSELF, distinct from the parse check above: if `crawl_events`
    # returned nothing, or a body decoded to an empty hash, every assertion above would hold.
    ctx = running_crawl
    events = crawl_events(ctx[:g][:organization_id])

    expect(events.length).to be >= 2
    events.each do |type, profile, body|
      expect(body.keys.length).to be >= 15, "#{type} decoded to #{body.keys.length} members"
      expect(profile_members(profile, EXTRA_SCHEMA).length).to be >= 7,
                                                               "#{type}'s profile resolved to fewer " \
                                                               "than seven members"
    end
  end
end
