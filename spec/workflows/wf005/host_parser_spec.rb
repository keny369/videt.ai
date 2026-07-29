# frozen_string_literal: true

require "rails_helper"

# WF-005 has ONE host parser (S-07-007 review, ADR-026 architecture lens).
#
# `FetchContent` briefly carried a second, naive `URI.parse(...).host` that rescued to `""`, and the
# value it produced was written into the IMMUTABLE `fetch_attempts.canonical_host`. On a well-formed
# canonical URL the two agree, so nothing observable diverged — which is exactly why this is worth
# pinning rather than contriving an end-to-end case for: the hazard is that they disagree on inputs a
# remote `Location` header can choose, and an empty host in an immutable audit row is not recoverable.
RSpec.describe "WF-005 canonical host parsing", type: :model do
  subject(:parser) { Workflows::Wf005::FetchAuthorization }

  def fetch_content_host_of(url)
    Workflows::Wf005::FetchContent.new.send(:host_of, url)
  end

  describe "the canonical parser" do
    it "drops userinfo, so an attacker cannot spell a foreign host into the authority" do
      expect(parser.host_of("https://evil.example@shop.acme.example/p")).to eq("shop.acme.example")
    end

    it "keeps an IPv6 literal whole" do
      expect(parser.host_of("https://[2001:db8::1]:443/p")).to eq("[2001:db8::1]")
    end

    it "strips the port and lowercases" do
      expect(parser.host_of("https://SHOP.Acme.Example:443/p")).to eq("shop.acme.example")
    end

    it "NEVER RAISES on input URI.parse rejects, and still reads the host" do
      hostile = ["https://shop.acme.example/a path", "https://shop.acme.example/a|b",
                 "https://shop.acme.example/<>"]
      hostile.each do |url|
        expect { URI.parse(url) }.to raise_error(URI::InvalidURIError), url
        expect(parser.host_of(url)).to eq("shop.acme.example"), url
      end
    end
  end

  describe "FetchContent uses it" do
    it "delegates rather than parsing hosts a second way" do
      # The naive version returned "" for the malformed inputs, and "" is what would have been
      # written into the immutable record.
      ["https://shop.acme.example/a path", "https://evil.example@shop.acme.example/p",
       "https://[2001:db8::1]:443/p"].each do |url|
        expect(fetch_content_host_of(url)).to eq(parser.host_of(url)), url
        expect(fetch_content_host_of(url)).not_to be_empty, url
      end
    end
  end
end
