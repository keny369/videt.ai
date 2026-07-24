# frozen_string_literal: true

require "rails_helper"
require "ipaddr"

# F-01 Shared Outbound Transport — the guarded HTTP client (FOUNDATION-001).
#
# Both seams are injected — the DNS resolver and the socket/TLS connector — so every
# safety property is proven with no live network: address pinning flows to the socket,
# the byte cap is enforced on the decoded body, redirects do a fresh resolution and
# re-validation, and every failure maps to exactly one typed Outcome.
module GuardedHttpClientSpecSupport
  Client = Platform::Outbound::GuardedHttpClient
  Resolver = Platform::Outbound::GuardedResolver

  # A resolver double. Every host resolves to a public pin unless explicitly refused.
  class FakeResolver
    DEFAULT_PIN = IPAddr.new("93.184.216.34")

    attr_reader :calls

    def initialize
      @pins = {}
      @refusals = {}
      @calls = []
    end

    def allow(host, address) = (@pins[host] = IPAddr.new(address))
    def refuse(host, reason, retryable: false) = (@refusals[host] = [reason, retryable])

    def resolve(host, timeout_s:)
      @calls << [host, timeout_s]
      if (refusal = @refusals[host])
        return Resolver::Refusal.new(reason: refusal[0], retryable: refusal[1])
      end

      address = @pins.fetch(host, DEFAULT_PIN)
      Resolver::Pin.new(address:, candidates: [address])
    end

    def hosts = calls.map(&:first)
  end

  # A connector double. `respond` enqueues one or more scripted responses per host
  # (successive opens dequeue; the last one repeats), or a connect-phase error is
  # raised. It records every open and keeps the connections for request-byte assertions.
  class FakeConnector
    DEFAULT_RESPONSE = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"

    attr_reader :opens

    def initialize
      @scripts = Hash.new { |h, k| h[k] = [] }
      @errors = {}
      @opens = []
      @connections = Hash.new { |h, k| h[k] = [] }
    end

    def respond(host, bytes) = @scripts[host] << bytes
    def fail_connect(host, error) = (@errors[host] = error)
    def read_times_out(host) = @scripts[host] << :read_timeout

    def open(pinned:, host:, port:, deadline:)
      @opens << { pinned:, host:, port: }
      raise @errors[host] if @errors[host]

      body = next_script(host)
      connection = body == :read_timeout ? TimingOutConnection.new : FakeConnection.new(body)
      @connections[host] << connection
      connection
    end

    def last_connection(host) = @connections[host].last

    private

    def next_script(host)
      queue = @scripts[host]
      return DEFAULT_RESPONSE if queue.empty?
      return queue.first if queue.length == 1

      queue.shift
    end
  end

  # A connection backed by a byte buffer. `read` yields slices then nil at EOF and
  # records the request bytes written.
  class FakeConnection
    attr_reader :written

    def initialize(bytes)
      @bytes = bytes.b
      @pos = 0
      @written = +""
    end

    def write(bytes) = (@written << bytes)

    def read(max, _deadline)
      return nil if @pos >= @bytes.bytesize

      slice = @bytes.byteslice(@pos, max)
      @pos += slice.bytesize
      slice
    end

    def close = nil
  end

  # A connection whose first read blows the deadline.
  class TimingOutConnection
    def write(_bytes) = nil
    def read(_max, _deadline) = raise(Client::TimeoutError, "deadline exceeded")
    def close = nil
  end

  module_function

  def raw_response(status: 200, reason: "OK", headers: {}, body: "", framing: :content_length)
    header = headers.dup
    case framing
    when :content_length then header["Content-Length"] ||= body.bytesize.to_s
    when :chunked then header["Transfer-Encoding"] = "chunked"
    when :close then nil # no length header; rely on EOF
    end
    lines = ["HTTP/1.1 #{status} #{reason}"] + header.map { |k, v| "#{k}: #{v}" }
    encoded = framing == :chunked ? chunk_encode(body) : body
    "#{lines.join("\r\n")}\r\n\r\n#{encoded}".b
  end

  def chunk_encode(body, size: 5)
    out = +""
    body.b.bytes.each_slice(size) do |slice|
      part = slice.pack("C*")
      out << "#{part.bytesize.to_s(16)}\r\n#{part}\r\n"
    end
    "#{out}0\r\n\r\n"
  end
end

RSpec.describe Platform::Outbound::GuardedHttpClient, type: :model do
  let(:resolver) { GuardedHttpClientSpecSupport::FakeResolver.new }
  let(:connector) { GuardedHttpClientSpecSupport::FakeConnector.new }
  subject(:client) { described_class.new(resolver:, connector:) }

  def raw_response(**kwargs) = GuardedHttpClientSpecSupport.raw_response(**kwargs)

  def policy(byte_cap: 4096, max_redirects: 0, timeout_s: 10, allowed_ports: nil)
    Platform::Outbound::RequestPolicy.build(timeout_s:, byte_cap:, max_redirects:, allowed_ports:)
  end

  def get(url, **policy_opts) = client.get(url, policy: policy(**policy_opts))

  describe "a guarded GET connects to the pinned address and sends the canonical host" do
    before do
      resolver.allow("example.com", "93.184.216.34")
      connector.respond("example.com", raw_response(body: "hello"))
    end

    it "returns a typed response outcome with the raw body" do
      out = get("https://example.com/.well-known/f1-verification.txt")
      expect(out).to be_response
      expect(out.status).to eq(200)
      expect(out.body).to eq("hello")
      expect(out.byte_count).to eq(5)
      expect(out.truncated).to be(false)
      expect(out.pinned_address).to eq(IPAddr.new("93.184.216.34"))
    end

    it "opens exactly one connection to the pinned address, port 443, canonical host" do
      get("https://EXAMPLE.com/.well-known/f1-verification.txt")
      expect(connector.opens.length).to eq(1)
      expect(connector.opens.first).to eq(pinned: IPAddr.new("93.184.216.34"), host: "example.com", port: 443)
    end

    it "sends the canonical Host, the identity Accept-Encoding, and a close connection" do
      get("https://example.com/.well-known/f1-verification.txt")
      written = connector.last_connection("example.com").written
      expect(written).to include("GET /.well-known/f1-verification.txt HTTP/1.1\r\n")
      expect(written).to include("Host: example.com\r\n")
      expect(written).to include("Accept-Encoding: identity\r\n")
      expect(written).to include("Connection: close\r\n")
    end
  end

  describe "body framing" do
    it "reads a chunked body, decoding to the entity bytes" do
      connector.respond("c.example", raw_response(body: "abcdefghij", framing: :chunked))
      out = get("https://c.example/x")
      expect(out.body).to eq("abcdefghij")
      expect(out.byte_count).to eq(10)
    end

    it "reads a length-free body until EOF" do
      connector.respond("e.example", raw_response(body: "streamed", framing: :close))
      expect(get("https://e.example/x").body).to eq("streamed")
    end

    it "counts the actual bytes, not a lying Content-Length" do
      connector.respond("l.example", "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nabc")
      out = get("https://l.example/x")
      expect(out.body).to eq("abc")
      expect(out.byte_count).to eq(3)
      expect(out.truncated).to be(false)
    end
  end

  describe "the byte cap stops the read at cap+1 and proves oversize" do
    it "truncates an oversized body to cap+1 and flags it" do
      connector.respond("big.example", raw_response(body: "x" * 100))
      out = get("https://big.example/x", byte_cap: 8)
      expect(out.byte_count).to eq(9)
      expect(out.body).to eq("x" * 9)
      expect(out.truncated).to be(true)
    end

    it "does not flag a body exactly at the cap" do
      connector.respond("edge.example", raw_response(body: "x" * 8))
      out = get("https://edge.example/x", byte_cap: 8)
      expect(out.byte_count).to eq(8)
      expect(out.truncated).to be(false)
    end

    it "flags a body exactly one over the cap" do
      connector.respond("over.example", raw_response(body: "x" * 9))
      expect(get("https://over.example/x", byte_cap: 8).truncated).to be(true)
    end

    it "caps a chunked body on the decoded bytes, not the framing" do
      connector.respond("cbig.example", raw_response(body: "y" * 100, framing: :chunked))
      out = get("https://cbig.example/x", byte_cap: 8)
      expect(out.byte_count).to eq(9)
      expect(out.truncated).to be(true)
    end
  end

  describe "redirects are revalidated, never inherited" do
    def redirect(location, status: 302) = raw_response(status:, headers: { "Location" => location })

    it "rejects any 3xx when the caller permits no redirects (S-05)" do
      connector.respond("r.example", redirect("https://r.example/next"))
      out = get("https://r.example/x", max_redirects: 0)
      expect(out).to be_rejected
      expect(out.reason).to eq(:redirect_rejected)
      expect(connector.opens.length).to eq(1)
    end

    it "follows a permitted redirect with a fresh resolution of the new host" do
      connector.respond("a.example", redirect("https://b.example/final"))
      connector.respond("b.example", raw_response(body: "arrived"))
      out = get("https://a.example/start", max_redirects: 2)
      expect(out).to be_response
      expect(out.body).to eq("arrived")
      expect(out.redirect_count).to eq(1)
      expect(out.final_url).to eq("https://b.example/final")
      expect(resolver.hosts).to eq(%w[a.example b.example])
    end

    it "re-runs the SSRF check on the redirect target and rejects a prohibited one" do
      connector.respond("a.example", redirect("https://blocked.example/y"))
      resolver.refuse("blocked.example", :destination_address_prohibited)
      out = get("https://a.example/x", max_redirects: 3)
      expect(out).to be_rejected
      expect(out.reason).to eq(:destination_address_prohibited)
    end

    it "rejects a redirect to a non-HTTPS target" do
      connector.respond("a.example", redirect("http://a.example/y", status: 301))
      expect(get("https://a.example/x", max_redirects: 3).reason).to eq(:redirect_rejected)
    end

    it "resolves a relative Location against the current URL and follows it" do
      connector.respond("a.example", redirect("/y"))
      connector.respond("a.example", raw_response(body: "at-y"))
      out = get("https://a.example/x", max_redirects: 2)
      expect(out).to be_response
      expect(out.body).to eq("at-y")
      expect(out.final_url).to eq("https://a.example/y")
    end

    it "detects a redirect loop back to a visited target" do
      connector.respond("loop.example", redirect("https://loop.example/x"))
      expect(get("https://loop.example/x", max_redirects: 5).reason).to eq(:redirect_rejected)
    end

    it "stops when the redirect budget is exhausted" do
      connector.respond("h1.example", redirect("https://h2.example/x"))
      connector.respond("h2.example", redirect("https://h3.example/x"))
      out = get("https://h1.example/x", max_redirects: 1)
      expect(out.reason).to eq(:redirect_rejected)
      expect(resolver.hosts).to eq(%w[h1.example h2.example])
    end

    it "treats a 3xx without a Location as an ordinary response" do
      connector.respond("nl.example", raw_response(status: 302, body: ""))
      out = get("https://nl.example/x", max_redirects: 2)
      expect(out).to be_response
      expect(out.status).to eq(302)
    end
  end

  describe "resolver refusals map to typed outcomes" do
    it "maps a prohibited address to a nonretryable rejection and never connects" do
      resolver.refuse("bad.example", :destination_address_prohibited)
      out = get("https://bad.example/x")
      expect(out).to be_rejected
      expect(out.reason).to eq(:destination_address_prohibited)
      expect(out.retryable).to be(false)
      expect(connector.opens).to be_empty
    end

    it "maps an invalid host to a nonretryable rejection" do
      resolver.refuse("weird.example", :destination_host_invalid)
      expect(get("https://weird.example/x").reason).to eq(:destination_host_invalid)
    end

    it "maps a transient resolver failure to a retryable resolver_failure" do
      resolver.refuse("slow.example", :resolver_failure, retryable: true)
      out = get("https://slow.example/x")
      expect(out.kind).to eq(:resolver_failure)
      expect(out.retryable).to be(true)
    end
  end

  describe "connect and read failures map to typed outcomes" do
    it "maps a connect refusal to connection_failure" do
      connector.fail_connect("down.example", described_class::ConnectionError.new("refused"))
      out = get("https://down.example/x")
      expect(out.kind).to eq(:connection_failure)
      expect(out.retryable).to be(true)
    end

    it "maps a TLS failure to tls_failure (nonretryable)" do
      connector.fail_connect("tls.example", described_class::TlsError.new("bad cert"))
      out = get("https://tls.example/x")
      expect(out.kind).to eq(:tls_failure)
      expect(out.retryable).to be(false)
    end

    it "maps a connect timeout to timeout" do
      connector.fail_connect("t.example", described_class::TimeoutError.new("connect"))
      expect(get("https://t.example/x").kind).to eq(:timeout)
    end

    it "maps a peer mismatch to connection_failure (defence in depth)" do
      connector.fail_connect("mismatch.example", described_class::PeerMismatchError.new("peer != pin"))
      expect(get("https://mismatch.example/x").kind).to eq(:connection_failure)
    end

    it "maps a read-phase timeout to timeout" do
      connector.read_times_out("rt.example")
      expect(get("https://rt.example/x").kind).to eq(:timeout)
    end

    it "maps a malformed response to connection_failure" do
      connector.respond("garbage.example", "not http at all\r\n\r\n".b)
      expect(get("https://garbage.example/x").kind).to eq(:connection_failure)
    end

    it "refuses a request-smuggling response (Transfer-Encoding with Content-Length)" do
      connector.respond("smuggle.example",
                        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n0\r\n\r\n".b)
      expect(get("https://smuggle.example/x").kind).to eq(:connection_failure)
    end

    it "refuses a response with conflicting Content-Length headers" do
      connector.respond("dup.example", "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Length: 9\r\n\r\nabc".b)
      expect(get("https://dup.example/x").kind).to eq(:connection_failure)
    end
  end

  describe "URL validation happens before any lookup" do
    it "rejects a non-HTTPS scheme without resolving" do
      out = get("http://example.com/x")
      expect(out.reason).to eq(:unsupported_scheme)
      expect(resolver.calls).to be_empty
    end

    it "rejects a non-HTTP(S) scheme" do
      expect(get("ftp://example.com/x").reason).to eq(:unsupported_scheme)
    end

    it "rejects embedded userinfo" do
      expect(get("https://user:pw@example.com/x").reason).to eq(:destination_host_invalid)
    end

    it "rejects a disallowed port" do
      expect(get("https://example.com:8080/x").reason).to eq(:unsupported_port)
    end

    it "rejects a malformed URL" do
      expect(get("https://exa mple.com/x").reason).to eq(:destination_host_invalid)
    end
  end

  describe "the loggable shape redacts secrets" do
    it "exposes only enums/counts, never body, header values, or the raw address" do
      connector.respond("example.com",
                        raw_response(headers: { "Set-Cookie" => "s=secret" }, body: "hello"))
      redacted = get("https://example.com/x").redacted
      expect(redacted).to include(outcome: :response, status: 200, byte_count: 5, canonical_host: "example.com")
      joined = redacted.values.map(&:to_s).join
      expect(joined).not_to include("hello")
      expect(joined).not_to include("secret")
      expect(joined).not_to include("93.184.216.34")
    end
  end
end
