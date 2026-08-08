# frozen_string_literal: true

require "rails_helper"

# `parsed-observation-v1` (WORKFLOW_SPECIFICATIONS.md :476). Pure, so every field rule and
# every invalid condition is pinned against real bytes rather than against a fixture of the
# output.
RSpec.describe Workflows::Wf006::ParsedObservation, type: :model do
  def policy
    Workflows::Wf004::SourceScopePredicate::Policy.new(
      canonical_host: "example.com", allowed_schemes: ["https"], allowed_ports: [443],
      include_prefixes: ["/"], exclude_prefixes: [], query_handling: "retain_all"
    )
  end

  def build(html, source_root: false, media_type: "text/html", outcomes: nil)
    described_class.build(bytes: html, canonical_document_url: "https://example.com/",
                          media_type:, source_root:, scope_policies: [policy],
                          terminal_outcomes: outcomes)
  end

  def schema = Workflows::Wf006::ParsedObservationSchema

  describe "the top-level shape" do
    it "contains exactly the seven declared fields for a non-root document" do
      payload = build("<html><head><title>Hi</title></head><body></body></html>")

      expect(payload.keys).to contain_exactly(*Workflows::Wf006::ParsedObservationSchema::TOP_LEVEL)
      expect(payload["schema_version"]).to eq("parsed-observation-v1")
      expect(payload["document_kind"]).to eq("html")
    end

    it "adds the terminal-outcome map only for a Source root" do
      root = build("<html></html>", source_root: true, outcomes: { "https://example.com/" => "document_valid" })
      leaf = build("<html></html>")

      expect(root).to have_key("crawl_terminal_outcomes")
      expect(leaf).not_to have_key("crawl_terminal_outcomes")
    end

    it "reports xhtml for the other supported media type" do
      payload = build("<html xmlns='http://www.w3.org/1999/xhtml'></html>", media_type: "application/xhtml+xml")

      expect(payload["document_kind"]).to eq("xhtml")
    end

    it "strips media-type parameters before deciding support" do
      expect(described_class).to be_supported_media_type("text/html; charset=utf-8")
      expect(described_class).not_to be_supported_media_type("application/pdf")
    end

    it "lower-cases a BCP-47 language and rejects a non-tag" do
      expect(build("<html lang='EN-AU'></html>")["document_language"]).to eq("en-au")
      expect(build("<html lang='not a tag'></html>")["document_language"]).to be_nil
      expect(build("<html></html>")["document_language"]).to be_nil
    end
  end

  describe "title_nodes" do
    it "orders by document position with a stable locator" do
      payload = build("<html><head><title>One</title></head><body><title>Two</title></body></html>")

      expect(payload["title_nodes"]).to eq([
        { "position" => 0, "text" => "One", "locator" => "head/title[0]" },
        { "position" => 1, "text" => "Two", "locator" => "head/title[1]" }
      ])
    end

    it "RETAINS blank text rather than dropping the node" do
      payload = build("<html><head><title></title></head></html>")

      expect(payload["title_nodes"].length).to eq(1)
      expect(payload["title_nodes"].first["text"]).to eq("")
    end

    it "decodes HTML character references" do
      expect(build("<html><head><title>A &amp; B</title></head></html>")["title_nodes"].first["text"])
        .to eq("A & B")
    end

    it "retains internal whitespace" do
      expect(build("<html><head><title>A   B</title></head></html>")["title_nodes"].first["text"])
        .to eq("A   B")
    end
  end

  describe "link_edges" do
    it "canonicalizes an in-scope target through the frozen Crawl scope predicate" do
      payload = build('<html><body><a href="/about">x</a></body></html>')
      edge = payload["link_edges"].first

      expect(edge["target_canonical_url"]).to eq("https://example.com/about")
      expect(edge["target_rejection_reason"]).to be_nil
    end

    it "rejects an out-of-scope host with the one admitted reason" do
      payload = build('<html><body><a href="https://elsewhere.test/x">x</a></body></html>')

      expect(payload["link_edges"].first["target_canonical_url"]).to be_nil
      expect(payload["link_edges"].first["target_rejection_reason"]).to eq("outside_source_scope")
    end

    it "names the exhaustive rejection reasons for empty and non-HTTP targets" do
      payload = build('<html><body><a href="">a</a><a href="mailto:x@example.com">b</a></body></html>')

      expect(payload["link_edges"].map { |e| e["target_rejection_reason"] })
        .to eq(%w[empty unsupported_scheme])
    end

    it "gives every edge exactly one of URL or reason — never both, never neither" do
      payload = build('<html><body><a href="/a">a</a><a href="">b</a><a href="https://x.test/">c</a></body></html>')

      payload["link_edges"].each do |edge|
        expect([edge["target_canonical_url"], edge["target_rejection_reason"]].compact.length).to eq(1)
      end
    end

    it "sorts relation tokens distinct and lower-case" do
      payload = build('<html><body><a href="/a" rel="NOFOLLOW noopener nofollow">a</a></body></html>')

      expect(payload["link_edges"].first["relation_tokens"]).to eq(%w[noopener nofollow].sort)
    end

    # S-07-007's IN-CRAWL DISCOVERY READS THIS EXTRACTION, NOT ITS OWN. `Wf005::LinkDiscovery`
    # calls `link_targets` so that the set the crawl follows and the set `CHK-TI-001` asks about
    # are the SAME set by construction: :478 derives the Check's targets from `link_edges`, so a
    # URL one admits and the other misses is a permanently `unobserved` target and an
    # indeterminate Check. This pins the equality directly — every admitted edge, no more and no
    # fewer, with its own zero-based position — because that is the property, not "it returns
    # some links".
    it "exposes exactly `link_edges`' admitted targets to in-crawl discovery, with positions" do
      html = '<html><head><link rel="stylesheet" href="/s.css"></head>' \
             '<body><a href="/about">x</a><a href="https://elsewhere.test/x">y</a>' \
             '<a href="">z</a><a href="mailto:a@b.c">m</a></body></html>'
      payload = build(html)
      targets = described_class.link_targets(bytes: html, canonical_document_url: "https://example.com/",
                                             media_type: "text/html", scope_policies: [policy])

      admitted = payload["link_edges"].reject { |e| e["target_canonical_url"].nil? }
      expect(targets.map { |t| t["canonical_url"] }).to eq(admitted.map { |e| e["target_canonical_url"] })
      expect(targets.map { |t| t["link_position"] }).to eq(admitted.map { |e| e["position"] })
      # And concretely: the stylesheet IS a target (which is why CHK-TI-001 stays indeterminate on
      # a real CMS page), while the off-host, empty and non-HTTP hrefs are not.
      expect(targets.map { |t| t["canonical_url"] })
        .to eq(["https://example.com/s.css", "https://example.com/about"])
    end

    it "yields no discovery targets for a media type the crawl never accepts" do
      expect(described_class.link_targets(bytes: '<a href="/a">x</a>', canonical_document_url: "https://example.com/",
                                          media_type: "text/css", scope_policies: [policy])).to eq([])
    end

    it "includes <link> elements alongside anchors, in document order" do
      payload = build('<html><head><link href="/feed" rel="alternate"></head><body><a href="/a">a</a></body></html>')

      expect(payload["link_edges"].map { |e| e["position"] }).to eq([0, 1])
      expect(payload["link_edges"].map { |e| e["href"] }).to contain_exactly("/feed", "/a")
    end
  end

  describe "organization_nodes" do
    def ld(json) = build(%(<html><head><script type="application/ld+json">#{json}</script></head></html>))

    it "admits a JSON-LD Organization and records its name and url" do
      payload = ld('{"@context":"https://schema.org","@type":"Organization","name":"Acme","url":"https://example.com"}')

      expect(payload["organization_nodes"].length).to eq(1)
      node = payload["organization_nodes"].first
      expect(node["name"]).to eq("Acme")
      expect(node["url"]).to eq("https://example.com")
      expect(node["parse_status"]).to eq("valid")
    end

    it "ignores a node whose @type is not Organization" do
      expect(ld('{"@type":"WebPage","name":"x"}')["organization_nodes"]).to be_empty
    end

    it "keeps duplicate nodes DISTINCT" do
      payload = ld('[{"@type":"Organization","name":"Acme"},{"@type":"Organization","name":"Acme"}]')

      expect(payload["organization_nodes"].length).to eq(2)
      expect(payload["organization_nodes"].map { |n| n["locator"] }.uniq.length).to eq(2)
    end

    it "produces ONE malformed item with null name and url rather than disappearing" do
      payload = ld("{not json at all")

      expect(payload["organization_nodes"].length).to eq(1)
      node = payload["organization_nodes"].first
      expect(node["parse_status"]).to eq("malformed")
      expect(node["name"]).to be_nil
      expect(node["url"]).to be_nil
    end

    it "finds a nested Organization and orders by traversal path" do
      payload = ld('{"@type":"WebPage","publisher":{"@type":"Organization","name":"Nested"}}')

      expect(payload["organization_nodes"].map { |n| n["name"] }).to eq(["Nested"])
    end
  end

  describe "untrusted content" do
    it "never fetches a remote JSON-LD context — @context is read as data" do
      # If a remote context were dereferenced this would be an unguarded egress path from
      # inside the parser. The guarded outbound surface is the only egress F1 has, and the
      # parser does not consume it, so a context URL can only ever be a string.
      expect(Platform::Outbound).not_to receive(:fetch)

      payload = build(%(<html><head><script type="application/ld+json">) +
                      %({"@context":"https://malicious.test/ctx.jsonld","@type":"Organization","name":"x"}) +
                      %(</script></head></html>))

      expect(payload["organization_nodes"].first["name"]).to eq("x")
    end

    it "does not expand an external entity" do
      xml = %(<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]>) +
            %(<html xmlns="http://www.w3.org/1999/xhtml"><head><title>&x;</title></head></html>)
      payload = build(xml, media_type: "application/xhtml+xml")

      expect(payload["title_nodes"].first["text"]).not_to include("root:")
    end

    it "returns a payload for bytes it cannot parse at all, rather than losing the Document" do
      payload = build("\xff\xfe not really html")

      expect(payload["schema_version"]).to eq("parsed-observation-v1")
      expect(schema.valid(payload, source_root: false)).to be_valid
    end
  end

  describe "the schema gate" do
    it "accepts a well-formed payload" do
      expect(schema.valid(build('<html><head><title>T</title></head><body><a href="/a">a</a></body></html>'),
                          source_root: false)).to be_valid
    end

    it "rejects an unknown top-level field" do
      payload = build("<html></html>").merge("extra" => 1)

      expect(schema.valid(payload, source_root: false).reason).to match(/unknown_top_level_field/)
    end

    it "rejects a repeated position" do
      payload = build('<html><body><a href="/a">a</a><a href="/b">b</a></body></html>')
      payload["link_edges"][1]["position"] = 0

      expect(schema.valid(payload, source_root: false).reason).to match(/position_repeats/)
    end

    it "rejects wrong ordering" do
      payload = build('<html><body><a href="/a">a</a><a href="/b">b</a></body></html>')
      payload["link_edges"].reverse!

      expect(schema.valid(payload, source_root: false).reason).to match(/ordering_wrong/)
    end

    it "rejects a blank locator" do
      payload = build("<html><head><title>T</title></head></html>")
      payload["title_nodes"][0]["locator"] = "  "

      expect(schema.valid(payload, source_root: false).reason).to match(/locator_blank/)
    end

    it "rejects a target carrying both a URL and a rejection reason" do
      payload = build('<html><body><a href="/a">a</a></body></html>')
      payload["link_edges"][0]["target_rejection_reason"] = "empty"

      expect(schema.valid(payload, source_root: false).reason).to match(/link_target_both/)
    end

    it "rejects a target carrying neither" do
      payload = build('<html><body><a href="/a">a</a></body></html>')
      payload["link_edges"][0]["target_canonical_url"] = nil

      expect(schema.valid(payload, source_root: false).reason).to match(/link_target_neither/)
    end

    it "rejects a Source-root payload with no terminal-outcome map" do
      payload = build("<html></html>")

      expect(schema.valid(payload, source_root: true).reason).to match(/root_terminal_outcomes_absent/)
    end

    it "rejects an outcome that contradicts the sealed Crawl snapshot" do
      payload = build("<html></html>", source_root: true,
                                       outcomes: { "https://example.com/" => "document_valid" })

      result = schema.valid(payload, source_root: true,
                                     sealed_outcomes: { "https://example.com/" => "content_fetch_failed" })

      expect(result.reason).to match(/terminal_outcome_contradicts_crawl/)
    end

    it "accepts an outcome map that agrees with the sealed snapshot" do
      payload = build("<html></html>", source_root: true,
                                       outcomes: { "https://example.com/" => "document_valid" })

      expect(schema.valid(payload, source_root: true,
                                   sealed_outcomes: { "https://example.com/" => "document_valid" })).to be_valid
    end
  end
end
