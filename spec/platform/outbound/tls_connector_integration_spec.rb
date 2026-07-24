# frozen_string_literal: true

require "rails_helper"
require "socket"
require "openssl"
require "ipaddr"

# F-01 Shared Outbound Transport — the real socket/TLS layer, end to end
# (FOUNDATION-001 properties 3/8; acceptance "deterministic tests use fixtures/local
# doubles; no live internet calls in the suite").
#
# This is the one place the transport touches a real socket and a real TLS handshake.
# It runs against a loopback TLS server with a test CA, so nothing leaves the machine.
# The SSRF address classification is proven in the resolver spec; here we pin 127.0.0.1
# directly (which AddressPolicy would rightly refuse for a real request) to isolate and
# prove the transport-level guarantees: connect to the pinned address, verify the peer
# equals it, present the canonical host as SNI, validate the certificate and hostname,
# and read a real response through the byte cap.
RSpec.describe Platform::Outbound::TlsConnector, type: :model do
  before(:all) do
    @cert, @key = build_self_signed_ca(cert_host)
  end

  after { stop_servers }

  let(:trusting_context) { client_context(trust: @cert) }
  let(:loopback) { IPAddr.new("127.0.0.1") }

  def cert_host = "verify.test"
  def reader = Platform::Outbound::HttpResponseReader
  def client_error(name) = Platform::Outbound::GuardedHttpClient.const_get(name)
  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  def deadline(seconds = 5) = monotonic + seconds

  describe "#open against a loopback TLS server" do
    it "connects to the pinned peer, verifies SNI/certificate, and reads the response" do
      port = start_tls_server(response: http_response(body: "verified"))
      connector = described_class.new(ssl_context: trusting_context)

      connection = connector.open(pinned: loopback, host: cert_host, port:, deadline: deadline)
      connection.write("GET /.well-known/f1-verification.txt HTTP/1.1\r\nHost: #{cert_host}\r\nConnection: close\r\n\r\n")
      raw = reader.read(connection, deadline: deadline, read_limit: 4097)
      connection.close

      expect(raw.status).to eq(200)
      expect(raw.body).to eq("verified")
      expect(raw.truncated).to be(false)
    end

    it "enforces the byte cap on the real response stream" do
      port = start_tls_server(response: http_response(body: "z" * 5000))
      connector = described_class.new(ssl_context: trusting_context)

      connection = connector.open(pinned: loopback, host: cert_host, port:, deadline: deadline)
      connection.write("GET /x HTTP/1.1\r\nHost: #{cert_host}\r\nConnection: close\r\n\r\n")
      raw = reader.read(connection, deadline: deadline, read_limit: 4097)
      connection.close

      expect(raw.byte_count).to eq(4097)
      expect(raw.truncated).to be(true)
    end

    it "raises TlsError when the certificate is not trusted" do
      port = start_tls_server(response: http_response(body: "x"))
      connector = described_class.new(ssl_context: client_context(trust: nil))

      expect do
        connector.open(pinned: loopback, host: cert_host, port:, deadline: deadline)
      end.to raise_error(client_error(:TlsError))
    end

    it "raises TlsError when the certificate hostname does not match the SNI host" do
      port = start_tls_server(response: http_response(body: "x"))
      connector = described_class.new(ssl_context: trusting_context)

      expect do
        connector.open(pinned: loopback, host: "wrong.test", port:, deadline: deadline)
      end.to raise_error(client_error(:TlsError))
    end

    it "raises ConnectionError when nothing is listening on the pinned peer" do
      port = closed_port
      connector = described_class.new(ssl_context: trusting_context)

      expect do
        connector.open(pinned: loopback, host: cert_host, port:, deadline: deadline)
      end.to raise_error(client_error(:ConnectionError))
    end
  end

  describe ".peer_matches?" do
    it "accepts the pinned address and its IPv4-mapped form" do
      expect(described_class.peer_matches?("127.0.0.1", IPAddr.new("127.0.0.1"))).to be(true)
      expect(described_class.peer_matches?("::ffff:93.184.216.34", IPAddr.new("93.184.216.34"))).to be(true)
    end

    it "rejects any other address (the DNS-rebinding backstop)" do
      expect(described_class.peer_matches?("127.0.0.2", IPAddr.new("127.0.0.1"))).to be(false)
      expect(described_class.peer_matches?("not-an-ip", IPAddr.new("127.0.0.1"))).to be(false)
    end
  end

  # --- test infrastructure: a loopback TLS server and a test CA, all in-process ---

  def http_response(status: 200, body: "")
    "HTTP/1.1 #{status} OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}".b
  end

  def start_tls_server(response:)
    tcp = TCPServer.new("127.0.0.1", 0)
    port = tcp.addr[1]
    context = OpenSSL::SSL::SSLContext.new
    context.cert = @cert
    context.key = @key
    server = OpenSSL::SSL::SSLServer.new(tcp, context)
    (@servers ||= []) << server
    (@threads ||= []) << Thread.new { serve_one(server, response) }
    port
  end

  def serve_one(server, response)
    socket = server.accept
    request = +""
    request << socket.readpartial(4096) until request.include?("\r\n\r\n")
    socket.write(response)
    socket.close
  rescue StandardError
    nil
  end

  def closed_port
    tcp = TCPServer.new("127.0.0.1", 0)
    port = tcp.addr[1]
    tcp.close
    port
  end

  def stop_servers
    Array(@threads).each { |t| t.join(2) }
    Array(@servers).each { |s| s.close rescue nil }
    @threads = @servers = nil
  end

  def client_context(trust:)
    context = OpenSSL::SSL::SSLContext.new
    store = OpenSSL::X509::Store.new
    store.add_cert(trust) if trust
    context.cert_store = store
    context.verify_mode = OpenSSL::SSL::VERIFY_PEER
    context.verify_hostname = true
    context.min_version = OpenSSL::SSL::TLS1_2_VERSION
    context
  end

  def build_self_signed_ca(host)
    key = OpenSSL::PKey::RSA.new(2048)
    name = OpenSSL::X509::Name.parse("/CN=#{host}")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = cert
    factory.issuer_certificate = cert
    cert.add_extension(factory.create_extension("subjectAltName", "DNS:#{host}", false))
    cert.add_extension(factory.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    [cert, key]
  end
end
