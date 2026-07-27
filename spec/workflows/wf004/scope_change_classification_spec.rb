# frozen_string_literal: true

require "rails_helper"

# The Source Scope Change classifier (WF-004 Source Scope Change Contract; owner decision
# HD-S06-002-SCOPE-CLASSIFIER = Option B, DECISIONS ADR-054). Pure: given the current
# active policy, a proposed policy and the verified boundary it returns :contraction,
# :expansion or :boundary_violation, with PRULE-021 (S-06-001) as the admission oracle,
# an explicit query-multiplicity exception, and fail-closed behaviour. These are the
# committed fixtures pinning both dimensions.
RSpec.describe Workflows::Wf004::ScopeChangeClassification, type: :model do
  def pol(inc: ["/"], exc: [], q: "retain_all", host: "shop.acme.example",
          schemes: ["https"], ports: [443])
    Workflows::Wf004::SourceScopePredicate::Policy.new(
      canonical_host: host, allowed_schemes: schemes, allowed_ports: ports,
      include_prefixes: inc, exclude_prefixes: exc, query_handling: q
    )
  end

  let(:boundary) { pol }

  def classify(current, proposed)
    described_class.classify(current:, proposed:, boundary:)
  end

  describe "admitted URL-set dimension" do
    it "a proper subset (narrower includes) is a contraction" do
      expect(classify(pol(inc: ["/"]), pol(inc: ["/shop"]))).to be_contraction
    end

    it "equality is a contraction" do
      expect(classify(pol(inc: ["/shop"]), pol(inc: ["/shop"]))).to be_contraction
    end

    it "a superset (wider includes) is an expansion" do
      r = classify(pol(inc: ["/shop"]), pol(inc: ["/"]))
      expect(r).to have_attributes(classification: :expansion, reason: "broadens_admitted_set")
    end

    it "a mixed change (narrow one prefix, widen another) is an expansion" do
      r = classify(pol(inc: ["/shop"]), pol(inc: ["/blog"]))
      expect(r).to have_attributes(classification: :expansion, reason: "broadens_admitted_set")
    end

    it "adding an exclude prefix (narrower) is a contraction" do
      expect(classify(pol(exc: []), pol(exc: ["/private"]))).to be_contraction
    end

    it "removing an exclude prefix (wider) is an expansion" do
      r = classify(pol(exc: ["/private"]), pol(exc: []))
      expect(r).to have_attributes(classification: :expansion, reason: "broadens_admitted_set")
    end

    it "narrowing a subpath at a boundary (/shop -> /shop/deals) is a contraction" do
      expect(classify(pol(inc: ["/shop"]), pol(inc: ["/shop/deals"]))).to be_contraction
    end

    it "a lexically-longer but non-boundary prefix (/shop -> /shopping) is an expansion" do
      # /shopping is NOT under /shop, so it admits URLs /shop did not
      r = classify(pol(inc: ["/shop"]), pol(inc: ["/shopping"]))
      expect(r).to have_attributes(classification: :expansion, reason: "broadens_admitted_set")
    end
  end

  describe "query-handling multiplicity dimension" do
    it "narrowing retain_all -> allowlist is a contraction" do
      expect(classify(pol(q: "retain_all"), pol(q: ["a"]))).to be_contraction
    end

    it "an equal allowlist is a contraction" do
      expect(classify(pol(q: ["a", "b"]), pol(q: ["a", "b"]))).to be_contraction
    end

    it "a narrower allowlist is a contraction" do
      expect(classify(pol(q: ["a", "b"]), pol(q: ["a"]))).to be_contraction
    end

    it "widening allowlist -> retain_all is an expansion" do
      r = classify(pol(q: ["a"]), pol(q: "retain_all"))
      expect(r).to have_attributes(classification: :expansion, reason: "broadens_query_multiplicity")
    end

    it "widening the retained-key set is an expansion" do
      r = classify(pol(q: ["a"]), pol(q: ["a", "b"]))
      expect(r).to have_attributes(classification: :expansion, reason: "broadens_query_multiplicity")
    end

    it "retain_all -> retain_all is a contraction (no multiplicity change)" do
      expect(classify(pol(q: "retain_all"), pol(q: "retain_all"))).to be_contraction
    end

    it "a path narrowing combined with a query widening is an expansion" do
      r = classify(pol(inc: ["/"], q: ["a"]), pol(inc: ["/shop"], q: "retain_all"))
      expect(r.classification).to eq(:expansion)
    end
  end

  describe "verified-boundary violations are errors, not classifications" do
    it "a different canonical host is a boundary violation" do
      r = classify(pol, pol(host: "www.shop.acme.example"))
      expect(r).to have_attributes(classification: :boundary_violation, reason: "cross_host_expansion")
    end

    it "a non-HTTPS scheme is a boundary violation" do
      r = classify(pol, pol(schemes: ["https", "http"]))
      expect(r).to have_attributes(classification: :boundary_violation, reason: "unsupported_source_scheme")
    end

    it "a non-default port is a boundary violation" do
      r = classify(pol, pol(ports: [443, 8443]))
      expect(r).to have_attributes(classification: :boundary_violation, reason: "port_out_of_boundary")
    end

    it "a boundary violation is decided even when the path would otherwise narrow" do
      r = classify(pol(inc: ["/"]), pol(inc: ["/shop"], host: "other.example"))
      expect(r.classification).to eq(:boundary_violation)
    end
  end

  describe "fail-closed" do
    # A policy-like double that passes the boundary check but raises while its prefixes
    # are read, so classification cannot prove non-broadening.
    def raising_proposed
      Object.new.tap do |o|
        o.define_singleton_method(:canonical_host) { "shop.acme.example" }
        o.define_singleton_method(:allowed_schemes) { ["https"] }
        o.define_singleton_method(:allowed_ports) { [443] }
        o.define_singleton_method(:include_prefixes) { raise "unresolvable prefixes" }
        o.define_singleton_method(:exclude_prefixes) { [] }
        o.define_singleton_method(:query_handling) { "retain_all" }
      end
    end

    it "an unprovable case fails closed to an expansion" do
      r = described_class.classify(current: pol, proposed: raising_proposed, boundary:)
      expect(r).to have_attributes(classification: :expansion, reason: "unprovable_fail_closed")
    end
  end

  describe "purity" do
    it "is deterministic for the same inputs" do
      a = classify(pol(inc: ["/shop"]), pol(inc: ["/"]))
      b = classify(pol(inc: ["/shop"]), pol(inc: ["/"]))
      expect(a).to eq(b)
    end

    it "does not mutate its inputs" do
      current = pol(inc: ["/shop"].freeze, q: ["a"].freeze)
      proposed = pol(inc: ["/shop/deals"].freeze, q: ["a"].freeze)
      described_class.classify(current:, proposed:, boundary:)
      expect(current.include_prefixes).to eq(["/shop"])
      expect(proposed.include_prefixes).to eq(["/shop/deals"])
    end
  end
end
