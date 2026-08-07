# frozen_string_literal: true

require "rails_helper"
require "ipaddr"

# F-01 Shared Outbound Transport — connecting to a host whose FIRST address is unreachable.
#
# WHY THIS EXISTS. `GuardedResolver` pins one address out of the classified answer, ordered
# by network-byte value, which puts IPv6 ahead of IPv4 for every dual-stack host. On a
# network with no route to that family the connect returns EHOSTUNREACH, and the client
# used to give up there: the host became permanently unfetchable through the platform, so
# every crawl of it failed closed at robots.txt with `connection_failure` while a browser
# on the same machine loaded it. Measured live against a real dual-stack host before the
# fix.
#
# The fallback must not become a way around the safety properties, so the cases that must
# NOT fall through are pinned as carefully as the case that must.
RSpec.describe "Outbound connect candidate fallback", type: :model do
  Client = Platform::Outbound::GuardedHttpClient unless defined?(Client)
  Resolver = Platform::Outbound::GuardedResolver unless defined?(Resolver)

  let(:first) { IPAddr.new("2606:4700:10::6814:179a") }
  let(:second) { IPAddr.new("104.20.23.154") }
  let(:third) { IPAddr.new("104.20.23.155") }

  # A resolver returning ONE answer with several classified candidates — which is what a
  # dual-stack host produces. `resolve` is called once per attempt and never re-resolved
  # by the fallback, which is the DNS-rebinding property this must not break.
  def resolver_for(*addresses, &on_call)
    double = Object.new
    double.define_singleton_method(:resolve) do |host, timeout_s:|
      on_call&.call(host)
      Resolver::Pin.new(address: addresses.first, candidates: addresses)
    end
    double
  end

  # A connector that fails for named addresses and serves a canned response otherwise.
  class ScriptedConnector
    attr_reader :attempted

    def initialize(failures)
      @failures = failures
      @attempted = []
    end

    def open(pinned:, host:, port:, deadline:)
      @attempted << pinned.to_s
      error = @failures[pinned.to_s]
      raise error, "scripted" if error

      Connection.new("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
    end

    class Connection
      def initialize(bytes) = (@bytes = bytes.dup.b)
      def write(_bytes) = nil
      def close = nil

      def read(max_bytes, _deadline)
        return nil if @bytes.empty?

        @bytes.slice!(0, max_bytes)
      end
    end
  end

  def policy = Platform::Outbound::RequestPolicy.build(timeout_s: 5, byte_cap: 4096, max_redirects: 0)

  def fetch(connector, resolver)
    Client.new(resolver:, connector:).get("https://shop.example/x", policy:)
  end

  it "falls through to the next classified address when the pinned one is unreachable" do
    connector = ScriptedConnector.new(first.to_s => Client::ConnectionError)

    outcome = fetch(connector, resolver_for(first, second))

    expect(outcome.kind).to eq(:response)
    expect(outcome.status).to eq(200)
    # Pinned address first, then the next candidate — in the resolver's own order.
    expect(connector.attempted).to eq([first.to_s, second.to_s])
  end

  it "resolves ONCE — the fallback never performs a second lookup" do
    lookups = []
    connector = ScriptedConnector.new(first.to_s => Client::ConnectionError)

    fetch(connector, resolver_for(first, second) { |host| lookups << host })

    expect(lookups).to eq(["shop.example"])
  end

  it "reports connection_failure when every candidate is unreachable" do
    connector = ScriptedConnector.new(first.to_s => Client::ConnectionError,
                                      second.to_s => Client::ConnectionError)

    outcome = fetch(connector, resolver_for(first, second))

    expect(outcome.kind).to eq(:connection_failure)
    expect(connector.attempted).to eq([first.to_s, second.to_s])
  end

  it "does NOT fall through on a TLS failure — that is the destination, not the route" do
    connector = ScriptedConnector.new(first.to_s => Client::TlsError)

    outcome = fetch(connector, resolver_for(first, second))

    expect(outcome.kind).to eq(:tls_failure)
    expect(connector.attempted).to eq([first.to_s])
  end

  it "does NOT fall through on a peer mismatch — that is the rebinding backstop firing" do
    connector = ScriptedConnector.new(first.to_s => Client::PeerMismatchError)

    outcome = fetch(connector, resolver_for(first, second))

    expect(outcome.kind).to eq(:connection_failure)
    expect(connector.attempted).to eq([first.to_s])
  end

  it "does NOT fall through on a timeout — retrying would spend the budget twice" do
    connector = ScriptedConnector.new(first.to_s => Client::TimeoutError)

    outcome = fetch(connector, resolver_for(first, second))

    expect(outcome.kind).to eq(:timeout)
    expect(connector.attempted).to eq([first.to_s])
  end

  it "bounds the attempts, so a host with many records is still one bounded request" do
    many = (1..10).map { |n| IPAddr.new("104.20.23.#{n}") }
    connector = ScriptedConnector.new(many.to_h { |a| [a.to_s, Client::ConnectionError] })

    fetch(connector, resolver_for(*many))

    expect(connector.attempted.length).to eq(Client::CONNECT_CANDIDATE_LIMIT)
  end

  it "attempts exactly once when the answer holds a single address" do
    connector = ScriptedConnector.new({})

    fetch(connector, resolver_for(second))

    expect(connector.attempted).to eq([second.to_s])
  end
end
