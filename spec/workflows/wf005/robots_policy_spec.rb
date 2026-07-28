# frozen_string_literal: true

require "rails_helper"

# S-07-005 robots policy — the GOLDEN CORPUS SEARCH_CRAWL_RETRIEVAL.md § Robots And Sitemap
# Processing requires ("The parser implements the exact `F1DiscoverabilityBot` longest-rule algorithm
# from Volume I and is covered by a golden corpus").
#
# Every case below is traceable to a clause of WORKFLOW_SPECIFICATIONS.md :448. The parser is pure,
# so these are also the determinism guarantee: the same bytes decide the same way on every retry and
# every replay.
RSpec.describe Workflows::Wf005::RobotsPolicy, type: :model do
  subject(:policy) { described_class }

  def parse(body) = policy.parse(body)
  def allows?(body, path) = policy.allowed?(parse(body).rules, path)

  describe "agent-group selection (exact token, ASCII-case-insensitive, `*` only as fallback)" do
    it "selects the exact F1DiscoverabilityBot group over a wildcard group" do
      body = <<~ROBOTS
        User-agent: *
        Disallow: /

        User-agent: F1DiscoverabilityBot
        Disallow: /private
      ROBOTS
      expect(parse(body).agent_group).to eq("f1discoverabilitybot")
      expect(allows?(body, "/shop")).to be(true)      # the wildcard's blanket deny does NOT apply
      expect(allows?(body, "/private/x")).to be(false)
    end

    it "matches the exact token ASCII-case-insensitively" do
      %w[f1discoverabilitybot F1DISCOVERABILITYBOT F1discoverabilityBOT].each do |token|
        body = "User-agent: #{token}\nDisallow: /x\n"
        expect(parse(body).agent_group).to eq("f1discoverabilitybot"), "#{token} did not match"
        expect(allows?(body, "/x")).to be(false)
      end
    end

    it "falls back to `*` only when the exact token names no group" do
      body = "User-agent: *\nDisallow: /private\n"
      expect(parse(body).agent_group).to eq("*")
      expect(allows?(body, "/private")).to be(false)
      expect(allows?(body, "/public")).to be(true)
    end

    it "ignores a group addressed to some other crawler entirely" do
      body = "User-agent: OtherBot\nDisallow: /\n"
      expect(parse(body).agent_group).to be_nil
      expect(allows?(body, "/anything")).to be(true)
    end

    it "applies one rule block to every agent in a consecutive user-agent run" do
      body = "User-agent: OtherBot\nUser-agent: F1DiscoverabilityBot\nDisallow: /shared\n"
      expect(parse(body).agent_group).to eq("f1discoverabilitybot")
      expect(allows?(body, "/shared")).to be(false)
    end

    it "starts a NEW group when a user-agent line follows a rule line" do
      body = "User-agent: OtherBot\nDisallow: /\nUser-agent: F1DiscoverabilityBot\nDisallow: /mine\n"
      expect(allows?(body, "/anything")).to be(true)   # OtherBot's blanket deny is not ours
      expect(allows?(body, "/mine")).to be(false)
    end
  end

  describe "the longest-rule algorithm, allow winning equal-length ties" do
    it "lets the LONGEST matching rule win regardless of file order" do
      body = "User-agent: *\nDisallow: /a\nAllow: /a/b\nDisallow: /a/b/c\n"
      expect(allows?(body, "/a")).to be(false)
      expect(allows?(body, "/a/b")).to be(true)        # longer allow beats the shorter disallow
      expect(allows?(body, "/a/b/c")).to be(false)     # longer disallow beats the allow
      expect(allows?(body, "/a/b/z")).to be(true)
    end

    it "lets ALLOW win an equal-length tie" do
      %w[allow_first disallow_first].each do |order|
        body = order == "allow_first" ? "User-agent: *\nAllow: /x\nDisallow: /x\n"
                                      : "User-agent: *\nDisallow: /x\nAllow: /x\n"
        expect(allows?(body, "/x")).to be(true), "#{order} did not let allow win the tie"
      end
    end

    it "allows a path no rule matches" do
      expect(allows?("User-agent: *\nDisallow: /private\n", "/public")).to be(true)
    end

    it "treats an empty Disallow as allow-everything rather than a deny-all rule" do
      body = "User-agent: *\nDisallow:\n"
      expect(parse(body).rules).to be_empty
      expect(allows?(body, "/anything")).to be(true)
    end

    it "treats `Disallow: /` as a whole-host deny" do
      expect(allows?("User-agent: *\nDisallow: /\n", "/")).to be(false)
      expect(allows?("User-agent: *\nDisallow: /\n", "/deep/path")).to be(false)
    end

    it "matches by prefix, so /shop does not deny /shopping only by accident of naming" do
      # robots prefix semantics DO deny /shopping under `Disallow: /shop` — unlike the S-06 scope
      # predicate, which is segment-boundary matched. The two rules are different and both are right.
      body = "User-agent: *\nDisallow: /shop\n"
      expect(allows?(body, "/shopping")).to be(false)
      expect(allows?(body, "/sho")).to be(true)
    end
  end

  describe "crawl delay (more restrictive only, never less)" do
    it "reads a positive integer or decimal delay in milliseconds" do
      expect(parse("User-agent: *\nCrawl-delay: 2\n").crawl_delay_ms).to eq(2000)
      expect(parse("User-agent: *\nCrawl-delay: 0.5\n").crawl_delay_ms).to eq(500)
    end

    it "never lets a delay INCREASE the rate" do
      # :448 — a positive crawl-delay makes the rate more restrictive than policy; it never
      # increases it. A delay shorter than the policy interval is therefore inert.
      expect(policy.effective_interval_ms(1000, 2000)).to eq(2000)   # slower wins
      expect(policy.effective_interval_ms(1000, 100)).to eq(1000)    # faster is ignored
      expect(policy.effective_interval_ms(1000, 0)).to eq(1000)
    end

    it "ignores a malformed or negative delay rather than guessing" do
      expect(parse("User-agent: *\nCrawl-delay: soon\n").crawl_delay_ms).to be_nil
      expect(parse("User-agent: *\nCrawl-delay: -5\n").crawl_delay_ms).to be_nil
    end
  end

  describe "sitemap collection (file-level, ordered, for S-07-006)" do
    it "collects Sitemap locations in file order regardless of agent group" do
      body = <<~ROBOTS
        Sitemap: https://h.example/sitemap-1.xml
        User-agent: *
        Disallow: /x
        Sitemap: https://h.example/sitemap-2.xml
      ROBOTS
      expect(parse(body).sitemaps)
        .to eq(["https://h.example/sitemap-1.xml", "https://h.example/sitemap-2.xml"])
    end

    it "collects none when the file declares none" do
      expect(parse("User-agent: *\nDisallow: /x\n").sitemaps).to be_empty
    end
  end

  describe "malformed input is ignored, never fatal (:448)" do
    it "ignores unrecognized fields, comment-only lines and lines with no colon" do
      body = <<~ROBOTS
        # a comment
        Nonsense
        Unknown-Field: value
        User-agent: *
        Disallow: /x   # trailing comment
      ROBOTS
      expect(allows?(body, "/x")).to be(false)
      expect(allows?(body, "/y")).to be(true)
    end

    it "replaces invalid byte sequences rather than raising" do
      body = "User-agent: *\nDisallow: /caf\xFF\nDisallow: /x\n".b
      expect { parse(body) }.not_to raise_error
      expect(allows?(body, "/x")).to be(false)
    end

    it "returns an empty rule set for an empty body" do
      expect(parse("").rules).to be_empty
      expect(parse("").agent_group).to be_nil
    end

    it "ignores a rule line that appears before any user-agent line" do
      expect(allows?("Disallow: /x\nUser-agent: *\nDisallow: /y\n", "/x")).to be(true)
      expect(allows?("Disallow: /x\nUser-agent: *\nDisallow: /y\n", "/y")).to be(false)
    end
  end

  describe "determinism" do
    it "decides identically across repeated parses of the same bytes" do
      body = "User-agent: *\nDisallow: /a\nAllow: /a/b\nCrawl-delay: 1\n"
      10.times do
        expect(parse(body).to_json_h).to eq(parse(body).to_json_h)
        expect(allows?(body, "/a/b")).to be(true)
      end
    end

    it "publishes a versioned rules schema so a stored decision is interpretable later" do
      expect(parse("User-agent: *\nDisallow: /x\n").to_json_h["schema"]).to eq("robots-rules-v1")
    end
  end
end
