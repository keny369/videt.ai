# frozen_string_literal: true

require "rails_helper"

# The Source Scope Predicate (PRULE-021; contracts/S-06.json MTX-072; SECURITY_
# PERFORMANCE.md § PRULE-021). Pure: given a candidate URL and the active Source Scope
# Policy intersection it returns allowed or a single denial reason, with no persistence,
# no network and no state change. Every normalization rule, the boundary prefix match,
# exclusion-wins, the per-policy intersection, the host/scheme/port scoping and purity
# are proven deterministically here — the S-06-001 tranche is exactly this engine.
RSpec.describe Workflows::Wf004::SourceScopePredicate, type: :model do
  # The S-05-006 `source-scope-interim-v1` shape: HTTPS, default port, the verified
  # canonical host, include "/", no exclude, retain_all.
  def interim(host: "shop.acme.example", **overrides)
    described_class::Policy.new(
      canonical_host: host, allowed_schemes: ["https"], allowed_ports: [443],
      include_prefixes: ["/"], exclude_prefixes: [], query_handling: "retain_all"
    ).with(**overrides)
  end

  def evaluate(url, policies = [interim])
    described_class.evaluate(url:, policies:)
  end

  describe "guard" do
    it "raises when the active policy set is empty (scope was never resolved)" do
      expect { described_class.evaluate(url: "https://shop.acme.example/", policies: []) }
        .to raise_error(ArgumentError)
    end
  end

  describe "admission under the interim policy" do
    it "allows the verified host at root" do
      d = evaluate("https://shop.acme.example/")
      expect(d).to have_attributes(allowed?: true, reason_code: "allowed",
                                   canonical_url: "https://shop.acme.example/")
    end

    it "allows a deep path" do
      expect(evaluate("https://shop.acme.example/a/b/c").allowed?).to be(true)
    end

    it "supplies root when the path is absent" do
      expect(evaluate("https://shop.acme.example").canonical_url).to eq("https://shop.acme.example/")
    end
  end

  describe "TYP-DATA normalization" do
    it "lowercases the host and removes a trailing dot" do
      expect(evaluate("https://SHOP.Acme.Example./x").canonical_url)
        .to eq("https://shop.acme.example/x")
    end

    it "removes the default https port (443)" do
      expect(evaluate("https://shop.acme.example:443/x").canonical_url)
        .to eq("https://shop.acme.example/x")
    end

    it "removes path dot segments" do
      expect(evaluate("https://shop.acme.example/a/./b/../c").canonical_url)
        .to eq("https://shop.acme.example/a/c")
    end

    it "resolves a leading traversal to root without escaping it" do
      expect(evaluate("https://shop.acme.example/../../x").canonical_url)
        .to eq("https://shop.acme.example/x")
    end

    it "decodes unreserved percent-encoding and resolves a %2E dot segment" do
      expect(evaluate("https://shop.acme.example/a/%2E%2E/b").canonical_url)
        .to eq("https://shop.acme.example/b")
      expect(evaluate("https://shop.acme.example/%7Euser").canonical_url)
        .to eq("https://shop.acme.example/~user")
    end

    it "uppercases the hex of a retained (reserved) percent-escape" do
      expect(evaluate("https://shop.acme.example/a%2fb").canonical_url)
        .to eq("https://shop.acme.example/a%2Fb")
    end

    it "drops the fragment" do
      expect(evaluate("https://shop.acme.example/a#section").canonical_url)
        .to eq("https://shop.acme.example/a")
    end

    it "rejects a URL carrying user information" do
      expect(evaluate("https://user:pass@shop.acme.example/").reason_code)
        .to eq("url_userinfo_prohibited")
    end

    it "rejects a malformed candidate (no scheme, empty, control character)" do
      expect(evaluate("shop.acme.example/x").reason_code).to eq("url_malformed")
      expect(evaluate("").reason_code).to eq("url_malformed")
      expect(evaluate("https://shop.acme.example/a b").reason_code).to eq("url_malformed")
    end
  end

  describe "TYP-DATA query handling" do
    it "retain_all keeps every pair, sorted by decoded key then value, preserving duplicates" do
      d = evaluate("https://shop.acme.example/p?b=2&a=1&a=1&a=0")
      expect(d.canonical_url).to eq("https://shop.acme.example/p?a=0&a=1&a=1&b=2")
    end

    it "an explicit allowlist retains only listed keys" do
      policy = interim(query_handling: ["keep"])
      d = evaluate("https://shop.acme.example/p?drop=1&keep=2", [policy])
      expect(d.canonical_url).to eq("https://shop.acme.example/p?keep=2")
    end

    it "retains a pair only when every policy retains its key" do
      a = interim(query_handling: ["x"])
      b = interim(query_handling: ["y"])
      d = evaluate("https://shop.acme.example/p?x=1&y=2&z=3", [a, b])
      expect(d.canonical_url).to eq("https://shop.acme.example/p")
    end

    it "never denies on query alone" do
      expect(evaluate("https://shop.acme.example/p?anything=1").allowed?).to be(true)
    end
  end

  describe "TYP-DATA path prefix boundary" do
    def shop = interim(include_prefixes: ["/shop"])

    it "matches the prefix exactly" do
      expect(evaluate("https://shop.acme.example/shop", [shop]).allowed?).to be(true)
    end

    it "matches at a / segment boundary" do
      expect(evaluate("https://shop.acme.example/shop/item", [shop]).allowed?).to be(true)
    end

    it "does not match a longer non-boundary segment" do
      d = evaluate("https://shop.acme.example/shopping", [shop])
      expect(d).to have_attributes(allowed?: false, reason_code: "path_not_included")
    end

    it "treats the root prefix / as matching every absolute path" do
      expect(evaluate("https://shop.acme.example/anything/at/all").allowed?).to be(true)
    end
  end

  describe "TYP-DATA exclusion wins over inclusion" do
    def with_exclude = interim(include_prefixes: ["/"], exclude_prefixes: ["/private"])

    it "rejects a URL matching both an include and an exclude prefix" do
      d = evaluate("https://shop.acme.example/private/x", [with_exclude])
      expect(d).to have_attributes(allowed?: false, reason_code: "path_excluded")
    end

    it "allows a sibling path that only matches the include" do
      expect(evaluate("https://shop.acme.example/public/x", [with_exclude]).allowed?).to be(true)
    end

    it "applies the exclude boundary rule (/private excludes /private/x, not /privatepool)" do
      expect(evaluate("https://shop.acme.example/privatepool", [with_exclude]).allowed?).to be(true)
    end
  end

  # Owner decision HD-S06-001-SCOPE-SEPARATOR / DECISIONS ADR-051: fail-closed exclusion
  # hardening — %2F, %5C (case-insensitive) and a raw backslash are treated as segment
  # boundaries when testing EXCLUDE prefixes, so an excluded subtree cannot be reached by
  # encoding the separator. Exclusion-only; the canonical URL and include matching are
  # unchanged, and unrelated reserved characters are never decoded.
  describe "ADR-051 fail-closed exclusion separator hardening" do
    def excl(prefix = "/private", **overrides)
      interim(include_prefixes: ["/"], exclude_prefixes: [prefix], **overrides)
    end

    it "denies the exact excluded path and its descendants" do
      %w[/private /private/ /private/secret].each do |path|
        d = evaluate("https://shop.acme.example#{path}", [excl])
        expect(d).to have_attributes(allowed?: false, reason_code: "path_excluded"), path
      end
    end

    it "denies an encoded forward slash in either hex case" do
      %w[/private%2Fsecret /private%2fsecret].each do |path|
        expect(evaluate("https://shop.acme.example#{path}", [excl]).reason_code).to eq("path_excluded"), path
      end
    end

    it "denies an encoded backslash in either hex case" do
      %w[/private%5Csecret /private%5csecret].each do |path|
        expect(evaluate("https://shop.acme.example#{path}", [excl]).reason_code).to eq("path_excluded"), path
      end
    end

    it "denies a raw backslash separator" do
      expect(evaluate('https://shop.acme.example/private\secret', [excl]).reason_code).to eq("path_excluded")
    end

    it "denies mixed and repeated separator representations, including traversal into the excluded subtree" do
      %w[
        /private%2F%5Csecret
        /private%5C%2Fsecret
        /public%2F..%2F..%2Fprivate%2Fsecret
      ].each do |path|
        expect(evaluate("https://shop.acme.example#{path}", [excl]).reason_code).to eq("path_excluded"), path
      end
    end

    it "does NOT deny non-matching lexical prefixes solely because of the exclusion" do
      %w[/privateer /privately /private%20area].each do |path|
        expect(evaluate("https://shop.acme.example#{path}", [excl]).allowed?).to be(true), path
      end
    end

    it "does NOT deny a separator-encoded path that traverses OUT of the excluded subtree" do
      expect(evaluate("https://shop.acme.example/private%2F..%2Fpublic", [excl]).allowed?).to be(true)
    end

    it "does not decode unrelated reserved characters and leaves the canonical URL unchanged" do
      allowed = evaluate("https://shop.acme.example/a%2Fb%3Bc", [interim])
      expect(allowed).to have_attributes(allowed?: true,
                                         canonical_url: "https://shop.acme.example/a%2Fb%3Bc")
    end

    it "applies at a nested exclusion prefix" do
      policy = excl("/a/private")
      expect(evaluate("https://shop.acme.example/a/private%2Fx", [policy]).reason_code).to eq("path_excluded")
      expect(evaluate("https://shop.acme.example/a/public", [policy]).allowed?).to be(true)
    end

    it "excludes even when the include prefix would otherwise admit (exclusion wins across the encoded boundary)" do
      policy = interim(include_prefixes: ["/private"], exclude_prefixes: ["/private/admin"])
      expect(evaluate("https://shop.acme.example/private/reports", [policy]).allowed?).to be(true)
      expect(evaluate("https://shop.acme.example/private/admin%2Fkeys", [policy]).reason_code).to eq("path_excluded")
    end

    it "is deterministic and does not mutate frozen caller input" do
      url = "https://shop.acme.example/private%2Fsecret".freeze
      prefixes = ["/private"].freeze
      policy = interim(include_prefixes: ["/"].freeze, exclude_prefixes: prefixes)
      a = described_class.evaluate(url:, policies: [policy])
      b = described_class.evaluate(url:, policies: [policy])
      expect(a).to eq(b)
      expect(a.reason_code).to eq("path_excluded")
      expect(url).to eq("https://shop.acme.example/private%2Fsecret")
      expect(prefixes).to eq(["/private"])
    end

    it "does not let an encoded separator interfere via query or fragment" do
      # the query/fragment are not the path; an excluded path stays excluded and a query
      # bearing %2F does not create a spurious exclusion on an allowed path
      expect(evaluate("https://shop.acme.example/private?x=a%2Fb", [excl]).reason_code).to eq("path_excluded")
      expect(evaluate("https://shop.acme.example/public?x=a%2Fb#f", [excl]).allowed?).to be(true)
    end

    it "denies an encoded separator sitting exactly at the prefix boundary" do
      %w[/private%2F /private%5C].each do |path|
        expect(evaluate("https://shop.acme.example#{path}", [excl]).reason_code).to eq("path_excluded"), path
      end
      expect(evaluate('https://shop.acme.example/private\\', [excl]).reason_code).to eq("path_excluded")
    end

    it "is thread-safe: concurrent evaluations of the same input agree (mandated)" do
      url = "https://shop.acme.example/private%2Fsecret"
      results = Array.new(50).map { Thread.new { evaluate(url, [excl]).reason_code } }.map(&:value)
      expect(results.uniq).to eq(["path_excluded"])
    end

    it "characterizes the ratified separator set: a DOUBLE-encoded slash is out of ADR-051 scope and not denied" do
      # ADR-051 names exactly %2F, %5C and raw backslash. A double-encoded %252F is NOT a
      # single-pass separator (the %25 stays reserved), so it is allowed and preserved
      # verbatim in the canonical URL. Pinned so this boundary stays intentional; any future
      # extension is a separate owner decision (HD-S06-001 "at minimum" wording).
      d = evaluate("https://shop.acme.example/private%252Fsecret", [excl])
      expect(d).to have_attributes(allowed?: true,
                                   canonical_url: "https://shop.acme.example/private%252Fsecret")
    end
  end

  describe "TYP-SEC host, scheme and port scope" do
    it "a subdomain is out of scope unless separately present" do
      expect(evaluate("https://www.shop.acme.example/").reason_code).to eq("host_out_of_scope")
      expect(evaluate("https://api.shop.acme.example/").reason_code).to eq("host_out_of_scope")
    end

    it "an alternate apex or bare host is out of scope" do
      expect(evaluate("https://acme.example/").reason_code).to eq("host_out_of_scope")
    end

    it "a non-HTTPS scheme is out of scope" do
      expect(evaluate("http://shop.acme.example/").reason_code).to eq("scheme_out_of_scope")
    end

    it "a non-default port is out of scope" do
      expect(evaluate("https://shop.acme.example:8443/").reason_code).to eq("port_out_of_scope")
    end

    it "a non-ASCII host is out of scope (no implementation-side IDNA)" do
      expect(evaluate("https://shöp.acme.example/").reason_code).to eq("host_out_of_scope")
    end

    it "an IPv4 literal that is not the verified host is out of scope" do
      expect(evaluate("https://203.0.113.9/").reason_code).to eq("host_out_of_scope")
    end
  end

  describe "TYP-DATA every active policy intersection must pass" do
    it "rejects when the URL passes one policy and fails another" do
      broad = interim(include_prefixes: ["/"])
      narrow = interim(include_prefixes: ["/shop"])
      d = evaluate("https://shop.acme.example/blog", [broad, narrow])
      expect(d).to have_attributes(allowed?: false, reason_code: "path_not_included")
    end

    it "allows only when the URL passes every policy" do
      broad = interim(include_prefixes: ["/"])
      narrow = interim(include_prefixes: ["/shop"])
      expect(evaluate("https://shop.acme.example/shop/x", [broad, narrow]).allowed?).to be(true)
    end
  end

  describe "TYP-DATA purity" do
    it "returns an equal decision for the same URL under the same policy version" do
      a = evaluate("https://shop.acme.example/x?b=2&a=1")
      b = evaluate("https://shop.acme.example/x?b=2&a=1")
      expect(a).to eq(b)
    end

    it "every out-of-bound URL carries a reason and no canonical_url" do
      %w[
        http://shop.acme.example/ https://shop.acme.example:8443/
        https://www.shop.acme.example/ https://user@shop.acme.example/
      ].each do |url|
        d = evaluate(url)
        expect(d.allowed?).to be(false)
        expect(described_class::REASON_CODES).to include(d.reason_code)
        expect(d.canonical_url).to be_nil
      end
    end
  end
end
