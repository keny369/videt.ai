# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

RSpec.describe "WF-005 record fetch attempt", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def content_response(status: 200, body: "<html><title>t</title></html>", type: "text/html")
    headers = type.nil? ? {} : { "content-type" => type }
    Platform::Outbound::Outcome.response(
      status:, headers:, body:, byte_count: body.bytesize, truncated: false,
      canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: "https://shop.acme.example/p1", redirect_count: 0, latency_ms: 5
    )
  end

  def fetchable
    ctx = running_crawl
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: "User-agent: *\nAllow: /\n")))
    ctx[:gate_id] = gate_row(ctx[:crawl_id])["id"]
    ctx
  end

  def prepare_attempt(ctx, now: start_now)
    decision = Workflows::Wf005::Admission.new.claim_next(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], now:
    )
    raise "expected an admitted entry" unless decision.admitted?

    prepared = Platform::UnitOfWork.run do |conn|
      Workflows::Wf005::FetchAttemptDueSchedule.prepare(
        pg: conn.raw_connection, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], gate_id: ctx[:gate_id], entry: decision.entry,
        reserved_bytes: decision.reserved_bytes, now:, due_at: now, correlation_id: SecureRandom.uuid_v7
      )
    end
    attempt = DbInspector.one("SELECT * FROM fetch_attempts WHERE id = $1::uuid", [prepared[:attempt_id]])
    action = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [prepared[:action_id]])
    [decision, attempt, action]
  end

  def execute(action, outbound, at: start_now)
    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      attempt_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc, action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: at
    )
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(at), outbound:
    )
  end

  def counters(crawl_id)
    DbInspector.one("SELECT * FROM crawl_budget_counters WHERE crawl_id = $1::uuid", [crawl_id])
  end

  it "registers RecordFetchAttempt as the crawl_fetch_due handler at schema version 1.0" do
    entry = Platform::ScheduledActions::Registry.default.resolve(action_kind: "crawl_fetch_due", action_schema_version: "1.0")
    expect(entry.operation).to eq("RecordFetchAttempt")
    expect(entry.handler).to eq(Workflows::Wf005::Handlers::RecordFetchAttempt)
    expect(entry.command).to eq(Workflows::Wf005::Commands::RecordFetchAttempt)
  end

  it "consumes a prepared persisted attempt and marks submission_started before the outbound call" do
    ctx = fetchable
    decision, attempt, action = prepare_attempt(ctx)
    seen = nil
    response = content_response
    outbound = Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |_url, **_kwargs|
        seen = DbInspector.one("SELECT submission_started_at, claim_owner FROM fetch_attempts WHERE id = $1::uuid",
                               [attempt["id"]])
        response
      end
    end

    result = execute(action, outbound)

    expect(result.success?).to be(true)
    expect(result.payload[:outcome]).to eq("document_created")
    expect(seen["submission_started_at"]).not_to be_nil
    expect(seen["claim_owner"]).not_to be_nil

    final = DbInspector.one("SELECT * FROM fetch_attempts WHERE id = $1::uuid", [attempt["id"]])
    expect(final["outcome"]).to eq("document_created")
    expect(final["accounted_response_bytes"].to_i).to eq(response.body.bytesize)
    expect(final["claim_owner"]).to be_nil
    expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i).to eq(response.body.bytesize)
    expect(counters(ctx[:crawl_id])["committed_response_bytes"].to_i).to eq(response.body.bytesize)
    expect(decision.reserved_bytes).to eq(final["reserved_bytes"].to_i)
  end

  it "schedules the next persisted attempt 30 seconds later on a retryable timeout without reserving twice" do
    ctx = fetchable
    decision, attempt, action = prepare_attempt(ctx)
    timeout = Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")

    result = execute(action, Object.new.tap { |o| o.define_singleton_method(:fetch) { |_url, **_kwargs| timeout } })

    expect(result.success?).to be(true)
    expect(result.payload[:outcome]).to eq("content_fetch_failed")
    expect(result.payload[:retryable]).to be(true)
    expect(result.payload[:scheduled_retry_action_id]).not_to be_nil

    next_attempt = DbInspector.one(
      "SELECT * FROM fetch_attempts WHERE crawl_id = $1::uuid AND attempt_number = 2",
      [ctx[:crawl_id]]
    )
    next_action = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid",
                                  [result.payload[:scheduled_retry_action_id]])

    expect(next_attempt["reserved_bytes"].to_i).to eq(decision.reserved_bytes)
    expect(next_attempt["claim_owner"]).to be_nil
    expect(next_action["action_kind"]).to eq("crawl_fetch_due")
    expect(next_action["target_type"]).to eq("fetch_attempt")
    expect(next_action["target_id"]).to eq(next_attempt["id"])
    expect(Time.parse(next_action["due_at"]).getutc).to eq(start_now + 30)

    row = counters(ctx[:crawl_id])
    expect(row["reserved_response_bytes"].to_i).to eq(decision.reserved_bytes)
    expect(row["committed_response_bytes"].to_i).to eq(0)
  end
end
