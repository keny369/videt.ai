# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# :442's BOUNDARY, DEFENDED BY CALLER-BOUND INVOCATION (D5 family 1, R10-17/R10-18).
#
# WHAT THIS REPLACED. PROOF 185 was a per-line text scan for a raw deadline read, carrying one
# exception. PROOF 186 was an eight-name denylist of comparison methods. Both are deleted. On THIS
# branch, inverting `Admission#wall_clock_expired?` to compare through `instant_for_transport` — an
# accessor 186 does not name and 185 skips by construction — left `spec/platform/pg_instant_spec.rb`,
# `spec/architecture/wf005_time_single_surface_spec.rb` and `spec/acceptance/wf005_pass_anchor_spec.rb`
# at 82 examples, 0 failures. That reproduction is what authorises deleting them rather than widening
# them for a sixth time.
#
# WHY THIS SHAPE. "No other implementation exists" is a claim about every expression anyone could
# write, and Ruby has unbounded ways to write one. This asserts the opposite thing, which is bounded
# and observable: THE GATE UNDER TEST CONSULTED THE OWNER, on this thread, as part of its own
# execution. A reimplementation behind a helper, through `instant_for_transport`, through an alias,
# through a spelling nobody has invented yet, does not invoke `RunDeadline#expired?` FROM THAT GATE
# and fails here.
#
# THE CALLER BINDING IS LOAD-BEARING AND WAS LEARNED THE HARD WAY. Round 11's first attempt asserted
# only that the owner ran somewhere in the block, and the inverted-gate mutation SURVIVED it, because
# a pass consults the deadline again through `RunBoundedOutbound` on every request. `spec/architecture/
# execution_probe_spec.rb` PROOF 209b-209i hold that lesson as executable self-tests.
RSpec.describe "WF-005 :442 deadline gates", type: :acceptance,
                                              acceptance_ids: ["AC-CAP-007", "AC-WF-005"],
                                              test_types: %w[TYP-INT TYP-SEC] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:expired) { ExecutionProbe.calls("Platform::RunDeadline#expired?").first }

  it "PROOF 216 — admission's wall-clock decision CONSULTS the owner, not a reimplementation" do
    # `Admission#wall_clock_expired?` is :442's only observation point for the run's clock, and it is
    # the gate the round-10 review inverted through `instant_for_transport` with the whole suite
    # green. The gate is invoked directly on a real `Admission` against a REAL crawl row, because the
    # claim under test is precisely "this gate consults the owner" — nothing is stubbed, and the row
    # comes from the database rather than a literal.
    ctx = running_crawl
    crawl = DbInspector.one("SELECT * FROM crawls WHERE id=$1::uuid", [ctx[:crawl_id]])
    admission = Workflows::Wf005::Admission.new

    seen = ExecutionProbe.watch([expired]) do
      admission.send(:wall_clock_expired?, crawl, Platform::PgInstant.utc(crawl["deadline_at"]))
    end

    expect(seen).to have_evaluated(expired).from("Admission#wall_clock_expired?")
    # AND IT ANSWERS THE BOUNDARY THE CONTRACT STATES: at the deadline, the run is expired.
    expect(admission.send(:wall_clock_expired?, crawl, Platform::PgInstant.utc(crawl["deadline_at"]))).to be(true)
  end

  it "PROOF 216b — the pass's own wall-clock gate CONSULTS the owner" do
    ctx = running_crawl
    crawl = DbInspector.one("SELECT * FROM crawls WHERE id=$1::uuid", [ctx[:crawl_id]])
    driver = Workflows::Wf005::CrawlDriver.allocate

    seen = ExecutionProbe.watch([expired]) do
      driver.send(:within_wall_clock?, crawl, Platform::PgInstant.utc(crawl["deadline_at"]) - 60)
    end

    expect(seen).to have_evaluated(expired).from("CrawlDriver#within_wall_clock?")
  end

  it "PROOF 217 — the request-start bound CONSULTS the owner, at the instant of each request" do
    # The gate that stops a request starting after the run's clock has stopped. It must consult the
    # owner per REQUEST rather than once per pass, so the probe is armed around a request rather than
    # around the decorator's construction.
    requests = []
    outbound = Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **|
        requests << url
        Platform::Outbound::Outcome.response(
          status: 200, headers: { "content-type" => "text/plain" }, body: "User-agent: *\nAllow: /\n",
          byte_count: 26, truncated: false, canonical_host: "shop.acme.example", port: 443,
          pinned_address: "198.51.100.7", final_url: url, redirect_count: 0, latency_ms: 5
        )
      end
    end
    deadline = Platform::RunDeadline.of("deadline_at" => Time.utc(2026, 8, 4, 12, 0, 0))
    at = Time.utc(2026, 8, 4, 11, 59, 0)
    bounded = Workflows::Wf005::RunBoundedOutbound.new(outbound, deadline:, clock: -> { at })

    seen = ExecutionProbe.watch([expired]) { bounded.fetch("https://shop.acme.example/robots.txt") }

    expect(seen).to have_evaluated(expired).from("RunBoundedOutbound#refuse_if_expired!")
    expect(requests).to eq(["https://shop.acme.example/robots.txt"])
  end

  it "PROOF 218 — a sibling consultation does NOT satisfy a gate's proof" do
    # THE NON-VACUITY THAT MATTERS HERE, driven against production rather than a fixture: consulting
    # the owner from somewhere else in the same block leaves the gate's own assertion false. Without
    # this, PROOF 216 and 217 would be satisfied by any other deadline read in the workflow.
    deadline = Platform::RunDeadline.of("deadline_at" => Time.utc(2026, 8, 4, 12, 0, 0))

    seen = ExecutionProbe.watch([expired]) { deadline.expired?(at: Time.utc(2026, 8, 4, 11, 0, 0)) }

    expect(seen).to have_evaluated(expired), "the owner did run"
    expect(seen).not_to have_evaluated(expired).from("Admission#wall_clock_expired?")
    expect(seen).not_to have_evaluated(expired).from("RunBoundedOutbound#refuse_if_expired!")
  end
end
