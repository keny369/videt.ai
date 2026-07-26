# frozen_string_literal: true

require "rails_helper"
require "digest"

# The ownership-verification observation engine (SCORE_EVIDENCE_MODEL.md § DNS TXT /
# HTTP File Method; contracts/S-05.json MTX-028). Pure: the frozen F-01 façade is injected
# so every DNS/HTTP predicate, the observed_value_sha256 hashing, the 4096/4097 boundary and
# the 14 reason codes are proven deterministically with no live network. It retains no
# plaintext token and no raw content.
RSpec.describe Workflows::Wf003::VerificationObservation, type: :model do
  def token = "Xy_9-abcDEF0123456789abcdef012345"
  def expected = "f1-verification=#{token}".b
  def host = "shop.acme.example"

  # ---- fake F-01 results (duck-typed; never the internal transport classes) -----
  def obj(**methods)
    o = Object.new
    methods.each { |name, value| o.define_singleton_method(name) { value } }
    o
  end

  def txt(records) = obj(refused?: false, records: records)
  def refusal(reason) = obj(refused?: true, reason: reason)
  def resp(status:, body:, truncated: false)
    obj(response?: true, rejected?: false, kind: :response, reason: nil,
        status:, body: body.b, byte_count: body.b.bytesize, truncated:)
  end
  def transport(kind:, reason: nil, rejected: false) = obj(response?: false, rejected?: rejected, kind:, reason:)

  def outbound(method_name, answer, capture: nil)
    fake = Object.new
    fake.define_singleton_method(method_name) { |*a, **k| capture&.call(a, k); answer }
    fake
  end

  def observe_dns(answer, capture: nil, tk: token)
    described_class.observe(method: "dns_txt", canonical_host: host, token: tk, outbound: outbound(:fetch_dns_txt, answer, capture:))
  end

  def observe_http(outcome, capture: nil, tk: token)
    described_class.observe(method: "http_file", canonical_host: host, token: tk, outbound: outbound(:fetch, outcome, capture:))
  end

  # ------------------------------------------------------------------------

  describe "location construction and budgets (consumes only F-01)" do
    it "queries _f1-verify.<host> for DNS with a 10s timeout" do
      seen = {}
      observe_dns(txt([["f1-verification=#{token}"]]), capture: ->(a, k) { seen[:host] = a.first; seen[:kw] = k })
      expect(seen[:host]).to eq("_f1-verify.shop.acme.example")
      expect(seen[:kw]).to eq(timeout_s: 10)
    end

    it "fetches https://<host>/.well-known/f1-verification.txt with 10s / 4096 / no redirects" do
      seen = {}
      observe_http(resp(status: 200, body: expected), capture: ->(a, k) { seen[:url] = a.first; seen[:kw] = k })
      expect(seen[:url]).to eq("https://shop.acme.example/.well-known/f1-verification.txt")
      expect(seen[:kw]).to eq(timeout_s: 10, byte_cap: 4096, max_redirects: 0)
    end

    it "raises on an unsupported method" do
      expect { described_class.observe(method: "meta_tag", canonical_host: host, token:) }.to raise_error(ArgumentError)
    end
  end

  describe "DNS TXT predicate" do
    it "matches an exact single TXT value" do
      r = observe_dns(txt([["f1-verification=#{token}"]]))
      expect(r.reason_code).to eq("matched")
      expect(r.match_decision).to eq("matched")
      expect(r.network_outcome).to eq("response")
    end

    it "matches when ANY complete value among multiple records matches" do
      expect(observe_dns(txt([["some-other-record"], ["f1-verification=#{token}"]])).reason_code).to eq("matched")
    end

    it "concatenates character-string segments within a record before comparison" do
      expect(observe_dns(txt([["f1-verif", "ication=", token]])).reason_code).to eq("matched")
    end

    it "fails on case / whitespace / prefix / suffix differences" do
      ["F1-VERIFICATION=#{token}", "f1-verification= #{token}", "x f1-verification=#{token}",
       "f1-verification=#{token} ", "f1-verification=#{token}x"].each do |value|
        r = observe_dns(txt([[value]]))
        expect(r.reason_code).to eq("dns_value_mismatch"), value
        expect(r.match_decision).to eq("not_matched")
      end
    end

    it "computes observed_value_sha256 by joining segments then LF-joining records" do
      r = observe_dns(txt([["f1-verif", "ication=", token], ["second"]]))
      expected_digest = Digest::SHA256.digest("f1-verification=#{token}".b + "\n".b + "second".b)
      expect(r.observed_value_sha256).to eq(expected_digest)
    end

    it "maps an absent response to dns_nxdomain with a null hash" do
      r = observe_dns(refusal(:absent))
      expect(r.reason_code).to eq("dns_nxdomain")
      expect(r.match_decision).to eq("not_matched")
      expect(r.observed_value_sha256).to be_nil
    end

    it "maps resolver timeout / temporary failure / host-invalid to retryable indeterminate reasons" do
      expect(observe_dns(refusal(:resolver_timeout)).reason_code).to eq("dns_timeout")
      expect(observe_dns(refusal(:resolver_timeout)).network_outcome).to eq("timeout")
      expect(observe_dns(refusal(:resolver_temporary_failure)).reason_code).to eq("dns_temporary_failure")
      expect(observe_dns(refusal(:destination_host_invalid)).reason_code).to eq("dns_temporary_failure")
      %i[resolver_timeout resolver_temporary_failure destination_host_invalid].each do |reason|
        expect(observe_dns(refusal(reason)).match_decision).to eq("indeterminate")
      end
    end
  end

  describe "HTTP file predicate" do
    it "matches an exact 200 body" do
      r = observe_http(resp(status: 200, body: expected))
      expect(r.reason_code).to eq("matched")
      expect(r.match_decision).to eq("matched")
      expect(r.http_status).to eq(200)
      expect(r.received_byte_count).to eq(expected.bytesize)
    end

    it "matches a 200 body with exactly one trailing line feed removed" do
      expect(observe_http(resp(status: 200, body: "#{expected}\n")).reason_code).to eq("matched")
    end

    it "fails a 200 body with two trailing line feeds as content mismatch" do
      expect(observe_http(resp(status: 200, body: "#{expected}\n\n")).reason_code).to eq("http_content_mismatch")
    end

    it "fails a 200 wrong body as http_content_mismatch and hashes the raw body" do
      r = observe_http(resp(status: 200, body: "nope"))
      expect(r.reason_code).to eq("http_content_mismatch")
      expect(r.match_decision).to eq("not_matched")
      expect(r.observed_value_sha256).to eq(Digest::SHA256.digest("nope"))
    end

    it "proves http_body_too_large at the oversize (truncated) boundary" do
      r = observe_http(resp(status: 200, body: "a" * 4097, truncated: true))
      expect(r.reason_code).to eq("http_body_too_large")
      expect(r.match_decision).to eq("not_matched")
      expect(r.received_byte_count).to eq(4097)
      expect(r.observed_value_sha256).to eq(Digest::SHA256.digest("a" * 4097))
    end

    it "reads a full 4096-byte body (not oversize)" do
      body = expected + ("x" * (4096 - expected.bytesize))
      r = observe_http(resp(status: 200, body:, truncated: false))
      expect(r.reason_code).to eq("http_content_mismatch")
      expect(r.received_byte_count).to eq(4096)
    end

    it "maps status codes: 404 mismatch, 408 timeout, 429 rate-limited, 5xx server-error" do
      expect(observe_http(resp(status: 404, body: "")).reason_code).to eq("http_status_mismatch")
      expect(observe_http(resp(status: 404, body: "")).match_decision).to eq("not_matched")
      expect(observe_http(resp(status: 408, body: "")).reason_code).to eq("http_timeout")
      expect(observe_http(resp(status: 429, body: "")).reason_code).to eq("http_rate_limited")
      expect(observe_http(resp(status: 503, body: "")).reason_code).to eq("http_server_error")
      [408, 429, 503].each { |s| expect(observe_http(resp(status: s, body: "")).match_decision).to eq("indeterminate") }
    end

    it "maps transport failures to their reason codes and network outcomes" do
      expect(observe_http(transport(kind: :timeout)).reason_code).to eq("http_timeout")
      expect(observe_http(transport(kind: :timeout)).network_outcome).to eq("timeout")
      expect(observe_http(transport(kind: :tls_failure)).reason_code).to eq("tls_validation_failed")
      expect(observe_http(transport(kind: :tls_failure)).network_outcome).to eq("tls_failure")
      expect(observe_http(transport(kind: :connection_failure)).reason_code).to eq("connection_failure")
      expect(observe_http(transport(kind: :resolver_failure)).network_outcome).to eq("resolver_failure")
      %i[timeout tls_failure connection_failure resolver_failure].each do |k|
        expect(observe_http(transport(kind: k)).match_decision).to eq("indeterminate")
      end
    end

    it "maps a rejected redirect to http_redirect_rejected (not followed)" do
      r = observe_http(transport(kind: :rejected, reason: :redirect_rejected, rejected: true))
      expect(r.reason_code).to eq("http_redirect_rejected")
      expect(r.match_decision).to eq("not_matched")
    end
  end

  describe "restricted-safe output" do
    it "produces only enums/status/count and the digest — never the token or raw content" do
      r = observe_http(resp(status: 200, body: expected))
      expect(r.to_h.values.map(&:to_s).join(" ")).not_to include(token)
      expect(r.to_h.keys).to match_array(%i[method observation_location network_outcome http_status
                                            dns_response_code received_byte_count observed_value_sha256
                                            match_decision reason_code])
      expect(described_class::REASON_CODES).to include(r.reason_code)
    end
  end
end
