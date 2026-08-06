# frozen_string_literal: true

require "rails_helper"
require "ipaddr"

# THE TOTAL REQUEST DEADLINE (FU-43, ADR-141) — F-01's ratified evolution.
#
# WHAT WAS WRONG, AND WHY NO CALLER COULD FIX IT. `RequestPolicy#timeout_s` was documented as "the
# connect-plus-response deadline for ONE connection attempt (each redirect hop is a fresh attempt
# with its own budget)", and `GuardedHttpClient#attempt` re-armed it per hop for BOTH the resolver
# call and the connect/read deadline. At the `max_redirects` ceiling of 10, one `Outbound.fetch`
# bounded at N seconds could run (10 + 1) x (dns + response) — the acceptance review measured 11.1x,
# and up to 22x with DNS timing. So a request the run's wall clock was supposed to end could still be
# reading a customer's site minutes after `deadline_at`. The façade accepted only a PER-ATTEMPT
# number, so there was no caller-side fix and the only lever was `max_redirects`.
#
# WHAT THESE PROVE. Not that a policy field exists — that a MAXIMUM-LENGTH REDIRECT CHAIN CANNOT
# CONTINUE PAST THE DEADLINE, measured on the wall clock, with a control that must still complete.
# The seams burn real time because the property IS a duration: a double that returned instantly
# would make every example below pass whether or not the budget is enforced.
module TotalDeadlineSpecSupport
  Client = Platform::Outbound::GuardedHttpClient
  Resolver = Platform::Outbound::GuardedResolver

  PIN = IPAddr.new("93.184.216.34")

  # Records the timeout it was handed on every call, so the SUBORDINATE-CEILING rule can be read
  # off the resolver rather than asserted about the code.
  class RecordingResolver
    attr_reader :calls

    def initialize(delay_s)
      @delay_s = delay_s
      @calls = []
    end

    def resolve(host, timeout_s:)
      @calls << { host:, timeout_s: }
      sleep(@delay_s)
      Resolver::Pin.new(address: PIN, candidates: [PIN])
    end
  end

  # Every host 302s to the next; the terminal host answers 200. Each open burns time, which is what
  # makes the chain cost something the budget can run out of.
  class ChainConnector
    attr_reader :opens, :deadlines

    def initialize(delay_s, terminal:)
      @delay_s = delay_s
      @terminal = terminal
      @opens = []
      @deadlines = []
    end

    def open(pinned:, host:, port:, deadline:)
      @opens << host
      # The ABSOLUTE monotonic deadline the client handed this connection. It is recorded because
      # the connect/read bound is a separate conjunct from the resolver bound, and a harness that
      # only measures where it burns time cannot tell whether this one is capped at all.
      @deadlines << deadline
      sleep(@delay_s)
      Connection.new(host == @terminal ? ok_bytes : redirect_bytes(host))
    end

    private

    def ok_bytes = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok".b

    def redirect_bytes(host)
      nxt = "hop#{host[/\d+/].to_i + 1}.example"
      "HTTP/1.1 302 Found\r\nLocation: https://#{nxt}/\r\nContent-Length: 0\r\n\r\n".b
    end
  end

  class Connection
    def initialize(bytes)
      @bytes = bytes
      @pos = 0
    end

    def write(_bytes) = nil

    def read(max, _deadline)
      return nil if @pos >= @bytes.bytesize

      slice = @bytes.byteslice(@pos, max)
      @pos += slice.bytesize
      slice
    end

    def close = nil
  end
end

RSpec.describe "F-01 total request deadline", type: :model do
  # 10 redirects is the ratified `Ceilings::REDIRECTS_MAX`, so this is the longest chain the
  # platform will ever follow — the exact configuration that produced the 11.1x overrun.
  def max_redirects = Platform::Outbound::Ceilings::REDIRECTS_MAX
  def terminal_host = "hop#{max_redirects}.example"
  def hop_delay_s = 0.03

  def resolver = @resolver ||= TotalDeadlineSpecSupport::RecordingResolver.new(hop_delay_s)
  def connector = @connector ||= TotalDeadlineSpecSupport::ChainConnector.new(hop_delay_s, terminal: terminal_host)

  # Every hop the CALLER's guard was consulted for. `redirect_guard` is :448's robots and Source
  # Scope recheck, and in production it takes a per-gate lock and writes an authorization decision —
  # so consulting it for a hop that can never be made is a real side effect, not a wasted call.
  def guard_calls = @guard_calls ||= []
  def recording_guard = ->(uri) { guard_calls << uri.to_s; true }

  def run(total_timeout_s:, timeout_s: 5.0)
    policy = Platform::Outbound::RequestPolicy.build(
      timeout_s:, total_timeout_s:, byte_cap: 4096, max_redirects:, redirect_guard: recording_guard
    )
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = Platform::Outbound::GuardedHttpClient.new(resolver:, connector:)
                                                   .get("https://hop0.example/", policy:)
    { outcome:, started:, elapsed_s: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
  end

  # NON-VACUITY FIRST. The chain must really be long, must really cost time, and must really
  # complete when the budget allows it — otherwise the negative example below proves only that
  # something went wrong.
  it "follows the whole maximum-length chain and returns the response when the budget allows it" do
    result = run(total_timeout_s: 15.0)

    expect(result[:outcome].kind).to eq(:response)
    expect(result[:outcome].status).to eq(200)
    expect(result[:outcome].redirect_count).to eq(max_redirects)
    expect(connector.opens.length).to eq(max_redirects + 1)
    expect(connector.opens.last).to eq(terminal_host)
    # The chain is genuinely expensive: 11 hops x (resolve + open) x 30ms.
    expect(result[:elapsed_s]).to be > (max_redirects + 1) * hop_delay_s
  end

  # THE PROPERTY THE OWNER RATIFIED. Same chain, same per-attempt ceiling, a total budget smaller
  # than the chain costs. Before this repair the per-attempt timeout was re-armed at every hop, so
  # this ran the WHOLE chain and returned 200; the wall clock bounded nothing.
  it "stops a maximum-length redirect chain dead when the total budget is exhausted" do
    budget = 0.12
    result = run(total_timeout_s: budget)

    expect(result[:outcome].kind).to eq(:timeout),
                                     "a chain costing #{(max_redirects + 1) * hop_delay_s * 2}s ran " \
                                     "to #{result[:outcome].kind} under a #{budget}s total budget"

    # IT STOPPED EARLY RATHER THAN REPORTING LATE. A client that ran every hop and then said
    # "timeout" would satisfy the assertion above while still reading the customer's site for the
    # full chain, which is the defect itself.
    expect(connector.opens.length).to be < max_redirects + 1
    expect(connector.opens).not_to include(terminal_host)

    # AND THE WALL CLOCK IS THE BOUNDARY, NOT AN AVERAGE. One hop may be in flight when the budget
    # expires, so the bound is the budget plus at most one hop, never a multiple of the budget.
    expect(result[:elapsed_s]).to be < budget + (3 * hop_delay_s)
  end

  # THE CONNECT/READ DEADLINE IS CAPPED TOO, AND IT IS A SEPARATE CONJUNCT (found by mutation).
  #
  # The first draft of this file burned its time in the resolver and the connector's `open`, so the
  # RESOLVER limb stopped the chain and the connect/read limb was bound by nothing: reverting
  # `deadline = monotonic + policy.effective_timeout_s(left)` to `monotonic + policy.timeout_s`
  # survived all six examples. That is this repository's signature defect — a control proved at one
  # instance and assumed at the others — inside the repair for a different instance of it.
  #
  # The connector records the ABSOLUTE deadline it is handed, so the cap is observed directly rather
  # than inferred from where the harness happens to spend time.
  it "never hands a connection a deadline beyond the total boundary" do
    budget = 0.12
    result = run(total_timeout_s: budget, timeout_s: 5.0)

    expect(connector.deadlines).not_to be_empty
    # The client's own `started` is at or after ours, so its total boundary is at or after
    # `started + budget`; one scheduling quantum of slack keeps this from being a timing flake
    # while staying far below the 5s per-attempt ceiling the mutation restores.
    bound = result[:started] + budget + 0.05
    expect(connector.deadlines).to all(be <= bound),
                                   "a connection was given a deadline past the total boundary: " \
                                   "#{connector.deadlines.map { |d| (d - result[:started]).round(3) }.inspect} " \
                                   "seconds after start, against a #{budget}s budget"
  end

  # THE PRE-HOP CHECK PREVENTS A CALLER SIDE EFFECT, WHICH IS NOT VISIBLE IN THE OUTCOME (found by
  # mutation). Deleting it left every example green, because the check at the top of `attempt`
  # catches the exhausted budget one step later and the OUTCOME is identical either way. What
  # differs is that the caller's `redirect_guard` — :448's robots and Source Scope recheck, which in
  # production takes a lock and writes an authorization decision — is consulted for a hop that can
  # never be made. PRULE-039's reasoning exactly: a check after a side effect is a bypass whatever
  # its arithmetic.
  it "does not consult the caller's redirect guard once the budget is exhausted" do
    run(total_timeout_s: 0.12)

    expect(guard_calls.length).to be >= 1, "the guard was never consulted, so this proves nothing"
    expect(guard_calls.length).to eq(connector.opens.length - 1),
                                  "the guard was consulted #{guard_calls.length} times for " \
                                  "#{connector.opens.length} connections: a hop was authorized " \
                                  "against the customer's policy and then never made"
  end

  # THE SUBORDINATE-CEILING RULE, READ OFF THE OPERATIONS THEMSELVES (owner requirement 2).
  # "The effective timeout for every operation must be the lesser of the configured per-attempt
  # timeout and the remaining total deadline budget." The resolver records what it was handed.
  it "hands every operation the LESSER of the per-attempt ceiling and the remaining budget" do
    run(total_timeout_s: 0.12, timeout_s: 5.0)

    handed = resolver.calls.map { |c| c[:timeout_s] }
    expect(handed.length).to be >= 2, "only one resolver call was made, so no hop can be compared"
    expect(handed).to all(be <= 0.12), "an operation was handed more than the whole total budget"
    expect(handed).to all(be < 5.0), "an operation was handed the un-narrowed per-attempt ceiling"
    # The budget really is being spent: each hop gets strictly less than the one before it.
    expect(handed.each_cons(2).all? { |a, b| b < a }).to be(true),
                                                        "the remaining budget did not shrink across " \
                                                        "hops: #{handed.inspect}"
  end

  # THE PER-ATTEMPT CEILING STILL BINDS WHEN IT IS THE TIGHTER OF THE TWO, so the change did not
  # simply replace one number with another.
  it "keeps the per-attempt ceiling as the bound when it is tighter than the remaining budget" do
    run(total_timeout_s: 15.0, timeout_s: 0.25)

    expect(resolver.calls.map { |c| c[:timeout_s] }).to all(be <= 0.25)
  end

  # A CALLER CANNOT ACCIDENTALLY BYPASS THE TOTAL DEADLINE (owner requirement 6). Omitting
  # `total_timeout_s` yields the TIGHTEST form — the per-attempt number as the whole budget — not an
  # unbounded one. There is no shape of this call that has no total.
  it "defaults the total budget to the per-attempt timeout, so omission cannot widen anything" do
    policy = Platform::Outbound::RequestPolicy.build(timeout_s: 7.0, byte_cap: 1024)

    expect(policy.total_timeout_s).to eq(7.0)
    expect(policy.effective_timeout_s(3.0)).to eq(3.0)
    expect(policy.effective_timeout_s(99.0)).to eq(7.0)
  end

  # AND THE PLATFORM CEILING BOUNDS THE TOTAL TOO, so the 11.1x overrun is arithmetically
  # impossible rather than merely discouraged: no `fetch` can exceed the ratified hard bound however
  # many hops it follows.
  it "clamps the total budget to the platform hard ceiling, whatever the caller asks for" do
    policy = Platform::Outbound::RequestPolicy.build(timeout_s: 15.0, total_timeout_s: 600.0, byte_cap: 1024,
                                                     max_redirects: 10)

    expect(policy.total_timeout_s).to eq(Platform::Outbound::Ceilings::TOTAL_REQUEST_TIMEOUT_MAX_S)
    expect(policy.total_timeout_s).to be <= Platform::Outbound::Ceilings::CONNECT_RESPONSE_TIMEOUT_MAX_S
  end
end
