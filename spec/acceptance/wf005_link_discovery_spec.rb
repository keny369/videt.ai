# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf006_parse_chain"

# S-07-007 IN-CRAWL LINK DISCOVERY — the frontier is fed by what the pages actually say.
#
# Governing text: WORKFLOW_SPECIFICATIONS.md :440 ("each followed content link adds one edge";
# "the discovered queue counts distinct content-candidate URLs after Source Scope
# canonicalization"), :450 ("content URLs still pass normal scope, destination safety, robots,
# queue, depth, and deduplication rules"), :452, :454 (the dequeue tuple, breadth-first sealing,
# and "completed responses are buffered and their outgoing links are canonicalized, sorted, and
# committed in dequeue sequence"), :478 (the `CHK-TI-001` target set);
# SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic Selection.
#
# EVERY EXAMPLE DRIVES THE PRODUCTION CHAIN through the real `RecordFetchAttempt` behind real
# ScheduledActions. Only the frozen F-01 outbound facade is stubbed.
RSpec.describe "WF-005 in-crawl link discovery", type: :acceptance,
               acceptance_ids: %w[AC-WF-005 AC-CAP-009],
               test_types: %w[TYP-E2E TYP-DATA TYP-SEC] do
  include Wf006ParseChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # A METHOD, NOT A CONSTANT (a constant assigned inside a `RSpec.describe` block lands on
  # `Object` and is visible to every other spec in the suite — the trap `wf007_evaluation_spec`
  # records having been caught by). And `site_host` rather than `host`, because `host` is a
  # helper `Wf005CrawlChain#verify` already resolves against the example group: defining one
  # here overrode it and broke bootstrap for every example in this file.
  def site_host = "shop.acme.example"

  def linking_page(*hrefs, title: "t")
    anchors = hrefs.map { |h| %(<a href="#{h}">x</a>) }.join
    "<html><head><title>#{title}</title></head><body>#{anchors}</body></html>"
  end

  def frontier_entries(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT canonical_url, origin, depth, state, reason, discovering_document_url, link_position,
             parent_entry_id
      FROM crawl_frontier_entries WHERE crawl_id = $1::uuid ORDER BY dequeue_key
    SQL
  end

  def occurrences(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT occurrence_url, discovering_document_url, link_position, duplicate_reason
      FROM crawl_frontier_occurrences WHERE crawl_id = $1::uuid ORDER BY occurrence_order
    SQL
  end

  def links_in(cid) = frontier_entries(cid).select { |e| e["origin"] == "link" }

  # NO KEYWORD PARAMETER, deliberately. Every call site passes a brace-less hash literal
  # (`crawled("/" => ..., "/a" => ...)`), and Ruby routes a trailing hash to KEYWORDS whenever
  # the method declares any — so a `limit:` here made every call pass zero positional arguments
  # and fail with "given 0, expected 1" before reaching a single assertion.
  #
  # The bound is 24 passes rather than the harness default of 12 because these runs traverse
  # several depths, and a run truncated mid-traversal would make a discovery defect look like a
  # passing example.
  def crawled(pages)
    ctx = crawlable
    drain_fetches(ctx, outbound_pages(pages), limit: 24)
    ctx
  end

  # =====================================================================================
  describe ":440 — each followed content link adds one edge" do
    # THE DEFECT THIS TRANCHE REPAIRS, stated as the thing that is now true. Before it, a run
    # was seeded only from the Source root and the sitemap, so `/about` was named by the root
    # page and never fetched. The frontier is the authority for what the run reached.
    it "fetches a page that is linked but absent from the sitemap" do
      ctx = crawled("/" => { body: linking_page("/about") }, "/about" => { body: linking_page })

      linked = links_in(ctx[:crawl_id]).sole
      expect(linked["canonical_url"]).to eq("https://#{site_host}/about")
      expect(linked["state"]).to eq("terminal")
      expect(terminal_outcomes(ctx[:crawl_id]).map { |o| o["outcome"] })
        .to eq(%w[document_created document_created])
    end

    # :440 — "the Source root is depth 0 ... and each followed content link adds ONE edge."
    # The chain root(0) -> a(1) -> b(2) is asserted at every hop, because an off-by-one here
    # is invisible until the depth bound truncates a site one level too early or too late.
    it "adds exactly one edge per hop, and records the discovering document and position" do
      ctx = crawled("/" => { body: linking_page("/a") },
                    "/a" => { body: linking_page("/b") },
                    "/b" => { body: linking_page })

      by_url = links_in(ctx[:crawl_id]).to_h { |e| [e["canonical_url"], e] }
      expect(by_url["https://#{site_host}/a"]["depth"].to_i).to eq(1)
      expect(by_url["https://#{site_host}/b"]["depth"].to_i).to eq(2)
      # :454's tuple carries the whole provenance for a link candidate, unlike a sitemap one.
      expect(by_url["https://#{site_host}/b"]["discovering_document_url"]).to eq("https://#{site_host}/a")
      expect(by_url["https://#{site_host}/b"]["link_position"].to_i).to eq(0)
      expect(by_url["https://#{site_host}/b"]["parent_entry_id"]).not_to be_nil
    end

    # :454 — "within one depth, dequeue order is (depth, origin_rank, canonical_url, ...)",
    # and content traversal is breadth-first. Both depth-1 pages are sealed before the
    # depth-2 page they lead to is selected.
    it "traverses breadth-first: every depth-1 discovery is sealed before depth 2 is selected" do
      ctx = crawled("/" => { body: linking_page("/b", "/a") },
                    "/a" => { body: linking_page },
                    "/b" => { body: linking_page("/c") },
                    "/c" => { body: linking_page })

      # THE ORDER THE RUN ACTUALLY RETIRED THEM IN. `commit_order` is assigned by the database
      # as each entry terminalizes, so this is the run's real traversal rather than a re-read
      # of the ordering it was supposed to follow.
      order = DbInspector.all(<<~SQL, [ctx[:crawl_id]]).map { |r| r["canonical_url"] }
        SELECT e.canonical_url FROM crawl_terminal_outcomes o
        JOIN crawl_frontier_entries e ON e.id = o.crawl_frontier_entry_id
        WHERE o.crawl_id = $1::uuid ORDER BY o.commit_order
      SQL

      expect(order.first).to eq("https://#{site_host}/")
      # `/a` sorts below `/b` by canonical URL bytes, so depth 1 is (a, b) regardless of the
      # order the page named them, and `/c` — discovered from `/b` — comes strictly after both.
      expect(order[1, 2]).to eq(["https://#{site_host}/a", "https://#{site_host}/b"])
      expect(order.last).to eq("https://#{site_host}/c")
    end
  end

  # =====================================================================================
  describe ":450 — a discovered candidate passes the same rules every other candidate does" do
    # THE SCOPE PREDICATE DOES NOT FORK. An off-host link is refused by
    # `Wf004::SourceScopePredicate` — the same module the frontier, `FetchAuthorization` and
    # the parser's `link_edges` all resolve through — so it never becomes a candidate and no
    # request is ever made for it. The stub raises on an unexpected fetch, which is the
    # assertion: an off-host request would fail this example rather than pass it silently.
    it "never admits an out-of-scope link, and never requests one" do
      ctx = crawled("/" => { body: linking_page("https://evil.example/x", "/about") },
                    "/about" => { body: linking_page })

      expect(links_in(ctx[:crawl_id]).map { |e| e["canonical_url"] })
        .to eq(["https://#{site_host}/about"])
    end

    # :454 — "deduplication retains the first candidate in this order", and the duplicate is
    # recorded as an occurrence "without becoming another candidate". Two pages naming the
    # same target is the ordinary shape of a site nav, so this is the common case, not an edge.
    it "records a second discovery of the same URL as an occurrence, not a second candidate" do
      ctx = crawled("/" => { body: linking_page("/a", "/shared") },
                    "/a" => { body: linking_page("/shared") },
                    "/shared" => { body: linking_page })

      expect(links_in(ctx[:crawl_id]).count { |e| e["canonical_url"] == "https://#{site_host}/shared" })
        .to eq(1)
      dup = occurrences(ctx[:crawl_id]).select { |o| o["occurrence_url"] == "https://#{site_host}/shared" }
      expect(dup.length).to eq(1)
      expect(dup.sole["duplicate_reason"]).to eq("duplicate_discovery")
    end

    # THE SAME PAGE NAMING THE SAME TARGET TWICE is two distinct referrers at two positions
    # (:294 keys a referrer on `(document_id, referring URL, link position)`), and exactly one
    # candidate. A nav-plus-footer link is this case on every real site.
    it "treats two positions on one page as one candidate and one extra occurrence" do
      ctx = crawled("/" => { body: linking_page("/a", "/a") }, "/a" => { body: linking_page })

      expect(links_in(ctx[:crawl_id]).length).to eq(1)
      expect(occurrences(ctx[:crawl_id]).map { |o| o["link_position"].to_i }).to eq([1])
    end

    # A LINK BACK TO THE SOURCE ROOT is the most common link on the web and must not create a
    # second entry for a URL the run already holds at depth 0.
    it "does not re-admit the Source root when a page links to it" do
      ctx = crawled("/" => { body: linking_page("/a") }, "/a" => { body: linking_page("/") })

      roots = frontier_entries(ctx[:crawl_id]).select { |e| e["canonical_url"] == "https://#{site_host}/" }
      expect(roots.length).to eq(1)
      expect(roots.sole["origin"]).to eq("root")
      expect(roots.sole["depth"].to_i).to eq(0)
    end
  end

  # =====================================================================================
  describe "only a page has outgoing links" do
    # :452 gives an admitted content URL exactly one covered form that produces a body — "it
    # creates a valid Document". A 404 is covered and body-free, and an unsupported media type
    # is `policy_excluded`; neither can be traversed, and neither may abort the run.
    it "discovers nothing from a 404, and still retires it as content_absent" do
      ctx = crawled("/" => { body: linking_page("/gone") }, "/gone" => { status: 404, body: "" })

      expect(links_in(ctx[:crawl_id]).map { |e| e["canonical_url"] }).to eq(["https://#{site_host}/gone"])
      expect(terminal_outcomes(ctx[:crawl_id]).map { |o| o["outcome"] })
        .to contain_exactly("document_created", "content_absent")
    end

    it "discovers nothing from an unsupported media type, and retires it as policy_excluded" do
      ctx = crawled("/" => { body: linking_page("/style.css") },
                    "/style.css" => { body: "a{}", type: "text/css" })

      css = terminal_outcomes(ctx[:crawl_id]).find { |o| o["outcome"] == "policy_excluded" }
      expect(css).not_to be_nil
      expect(css["reason"]).to eq("unsupported_media_type")
      # It joined the frontier and was retired; it produced no further candidates.
      expect(links_in(ctx[:crawl_id]).length).to eq(1)
    end
  end

  # =====================================================================================
  describe "the residual that link discovery alone cannot close" do
    # THIS IS THE CONTRACT'S OWN CONSEQUENCE, PINNED SO IT CANNOT BE MISREAD AS A BUG HERE.
    #
    # :478 derives `CHK-TI-001`'s targets from EVERY in-scope `link_edges` target, and
    # `link_edges` includes `<link href>` as well as `<a href>`. :452 records an unsupported
    # media type as `policy_excluded`, and the payload's reason vocabulary (:294) has no token
    # for it, so it can only be `unobserved` — which the Check evaluates BEFORE pass or fail.
    #
    # So a page that links to a same-host stylesheet, font, image or JSON endpoint — which is
    # every page built by every mainstream CMS — leaves `CHK-TI-001` indeterminate no matter
    # how completely the crawl fetched it. Discovery closes the HTML half of the gap and
    # cannot close this half: the remedy is a Volume I decision about whether a
    # `policy_excluded` target belongs in the target set at all, exactly as it is already
    # excluded from :452's coverage denominator. Recorded, not repaired here.
    it "leaves an in-scope non-HTML target unobserved even when the run fetched it" do
      ctx = crawlable
      run_to_parsed(ctx, outbound_pages(
                           "/" => { body: '<html><head><title>t</title><link rel="stylesheet" href="/s.css">' \
                                          '</head><body><a href="/a">x</a></body></html>' },
                           "/a" => { body: linking_page },
                           "/s.css" => { body: "a{}", type: "text/css" }
                         ))

      outcomes = terminal_outcomes(ctx[:crawl_id]).to_h { |o| [o["crawl_frontier_entry_id"], o["outcome"]] }
      urls = frontier_entries(ctx[:crawl_id])
      css = urls.find { |e| e["canonical_url"].end_with?("/s.css") }
      expect(css).not_to be_nil, "the stylesheet must be DISCOVERED — it is an in-scope link edge"

      css_id = DbInspector.one(<<~SQL, [ctx[:crawl_id]])["id"]
        SELECT id FROM crawl_frontier_entries
        WHERE crawl_id = $1::uuid AND canonical_url LIKE '%/s.css' LIMIT 1
      SQL
      expect(outcomes[css_id]).to eq("policy_excluded")

      # And `policy_excluded` is precisely the outcome the TI derivation maps to `unobserved`.
      expect(Workflows::Wf006::EvidenceDerivation::TARGET_OUTCOME.fetch("policy_excluded").first)
        .to eq(Workflows::Wf006::EvidenceDerivation::UNOBSERVED)
    end
  end
end
