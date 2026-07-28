# frozen_string_literal: true

require "rails_helper"

# S-07-004 deterministic frontier order (WORKFLOW_SPECIFICATIONS.md :454; SEARCH_CRAWL_RETRIEVAL.md
# § Frontier And Deterministic Selection, which requires the materialized `dequeue_key` to be
# "tested against a reference tuple comparator").
#
# The binding property is that the BYTEWISE order of `dequeue_key` equals the order of Volume I's
# tuple `(depth, origin_rank, canonical_url, discovering_document_url, link_position)`. PostgreSQL
# orders and uniquely indexes `bytea` bytewise, so if that equivalence fails anywhere the database's
# idea of "next candidate" silently diverges from the contract's.
#
# This is proved exhaustively over the space where an encoding realistically breaks — variable-length
# string fields whose prefixes collide, the NUL byte the framing has to escape, and the CROSS-PRODUCT
# of the two string fields (the only way a field-boundary defect shows) — rather than by sampling.
RSpec.describe Workflows::Wf005::FrontierOrder, type: :model do
  subject(:order) { described_class }

  # A fixed UUID so the total-order tiebreak never masks a real field difference.
  def candidate(depth: 0, origin: "root", url: "https://a.example/", discovering: "", position: 0,
                id: "00000000-0000-4000-8000-000000000001")
    { depth:, origin:, canonical_url: url, discovering_document_url: discovering,
      link_position: position, entry_id: id }
  end

  def key(c) = order.dequeue_key(**c.slice(:depth, :origin, :canonical_url, :link_position, :entry_id)
                                     .merge(discovering_document_url: c[:discovering_document_url]))

  # -1/0/1 normalization, so a comparator returning any negative/positive integer still matches.
  def sign(n) = n.negative? ? -1 : (n.positive? ? 1 : 0)

  describe "the encoding agrees with the reference tuple comparator" do
    # An alphabet chosen for the ways a composite key breaks: the NUL byte the framing escapes, an
    # ASCII boundary pair that exposes a length-prefix inversion, a path separator, and a multi-byte
    # character whose bytes are all high.
    #
    # A raw 0xFF byte is deliberately ABSENT and cannot be tested: `field` and `tuple` both call
    # `unicode_normalize(:nfc)`, which raises on invalid UTF-8, so such input can never reach the
    # encoder. The escape byte's role is exercised instead by the multi-byte character, whose
    # continuation bytes are >= 0x80 and sort above the terminator.
    ALPHABET = ["\x00", "a", "b", "/", "é"].freeze

    def strings_up_to(length)
      out = [""]
      current = [""]
      length.times do
        current = current.flat_map { |s| ALPHABET.map { |c| s + c.dup.force_encoding("UTF-8") } }
        out.concat(current)
      end
      out.select { |s| s.dup.force_encoding("UTF-8").valid_encoding? }
    end

    it "orders every pair of canonical URLs exactly as the tuple does (exhaustive to length 2)" do
      corpus = strings_up_to(2)
      pairs = 0
      corpus.combination(2) do |a, b|
        ca = candidate(url: a)
        cb = candidate(url: b)
        expect(sign(key(ca) <=> key(cb))).to eq(sign(order.compare(ca, cb))),
                                            -> { "URL pair #{a.inspect} vs #{b.inspect} disagrees" }
        pairs += 1
      end
      # The prefix-collision case a length prefix would get wrong ("b" vs "ab") is inside this space.
      expect(pairs).to be > 400
    end

    it "orders every pair of discovering-document URLs exactly as the tuple does" do
      corpus = strings_up_to(2)
      corpus.combination(2) do |a, b|
        ca = candidate(origin: "link", discovering: a)
        cb = candidate(origin: "link", discovering: b)
        expect(sign(key(ca) <=> key(cb))).to eq(sign(order.compare(ca, cb))),
                                            -> { "discovering pair #{a.inspect} vs #{b.inspect} disagrees" }
      end
    end

    # Varying ONE field at a time cannot see a field-boundary defect: the bug shape is a URL whose
    # bytes bleed into the next field, which only shows when both vary together. This is the
    # cross-product, so the boundary between the two variable-length fields is genuinely covered
    # rather than sampled by one hand-picked example.
    it "orders every pair over the CROSS-PRODUCT of both variable-length fields" do
      corpus = strings_up_to(1)
      candidates = corpus.product(corpus).map { |u, d| candidate(origin: "link", url: u, discovering: d) }
      mismatches = 0
      candidates.combination(2) do |a, b|
        mismatches += 1 unless sign(key(a) <=> key(b)) == sign(order.compare(a, b))
      end
      expect(mismatches).to eq(0)
      expect(candidates.size).to be >= 36
    end

    it "keeps the shorter string first when it is a prefix of the longer one" do
      short = candidate(url: "https://a.example/shop")
      long  = candidate(url: "https://a.example/shopping")
      expect(key(short) <=> key(long)).to eq(-1)
      expect(sign(order.compare(short, long))).to eq(-1)
    end

    it "does not let a length prefix invert lexicographic order (the encoding's whole point)" do
      # "b" is one byte, "ab" is two; a naive length-prefixed key would order "b" first.
      b  = candidate(url: "b")
      ab = candidate(url: "ab")
      expect(key(ab) <=> key(b)).to eq(-1)
      expect(sign(order.compare(ab, b))).to eq(-1)
    end

    it "refuses input the encoder cannot normalize, rather than encoding it inconsistently" do
      invalid = candidate(url: "a\xffb".b)
      expect { key(invalid) }.to raise_error(StandardError)
    end

    it "cannot confuse an embedded NUL with the field boundary" do
      # Without escaping, "a\x00b" would terminate the URL field early and leak into the next one.
      embedded = candidate(url: "a\x00b")
      plain    = candidate(url: "a", discovering: "b")
      expect(key(embedded)).not_to eq(key(plain))
      expect(sign(key(embedded) <=> key(plain))).to eq(sign(order.compare(embedded, plain)))
    end
  end

  describe "field precedence" do
    # Ordering by depth is necessary for breadth-first but NOT sufficient: the SEAL is enforced at
    # selection by CrawlFrontierStore#claim_next, exercised in spec/acceptance/wf005_crawl_frontier_spec.rb.
    it "orders by depth first" do
      shallow = candidate(depth: 1, url: "https://z.example/zzz")
      deep    = candidate(depth: 2, url: "https://a.example/aaa")
      expect(key(shallow) <=> key(deep)).to eq(-1)
    end

    it "orders root < sitemap < link within a depth" do
      keys = %w[root sitemap link].map { |o| key(candidate(depth: 1, origin: o)) }
      expect(keys).to eq(keys.sort)
      expect(described_class::ORIGINS.values_at("root", "sitemap", "link")).to eq([0, 1, 2])
    end

    it "orders by canonical URL before discovering document URL" do
      a = candidate(origin: "link", url: "https://a.example/1", discovering: "https://z.example/")
      b = candidate(origin: "link", url: "https://a.example/2", discovering: "https://a.example/")
      expect(key(a) <=> key(b)).to eq(-1)
    end

    it "orders by link position last, numerically rather than lexically" do
      second = candidate(origin: "link", position: 2)
      tenth  = candidate(origin: "link", position: 10)
      expect(key(second) <=> key(tenth)).to eq(-1)   # "10" would sort before "2" as a string
    end

    it "breaks a fully-equal tuple by entry id, so the key is total" do
      a = candidate(id: "00000000-0000-4000-8000-00000000000a")
      b = candidate(id: "00000000-0000-4000-8000-00000000000b")
      expect(key(a) <=> key(b)).to eq(-1)
      expect(key(a)).not_to eq(key(b))
    end

    it "sorts a mixed frontier exactly as the reference comparator does" do
      candidates = [
        candidate(depth: 1, origin: "link", url: "https://a.example/b", discovering: "https://a.example/", position: 3),
        candidate(depth: 0, origin: "root", url: "https://b.example/"),
        candidate(depth: 1, origin: "sitemap", url: "https://a.example/b"),
        candidate(depth: 0, origin: "root", url: "https://a.example/"),
        candidate(depth: 1, origin: "link", url: "https://a.example/a", discovering: "https://a.example/", position: 1)
      ]
      by_key = candidates.sort_by { |c| key(c) }
      by_tuple = candidates.sort { |x, y| order.compare(x, y) }
      expect(by_key).to eq(by_tuple)
      expect(by_key.map { |c| c[:canonical_url] })
        .to eq(["https://a.example/", "https://b.example/", "https://a.example/b",
                "https://a.example/a", "https://a.example/b"])
    end
  end

  describe "normalization and guards" do
    it "treats NFC-equivalent spellings as the same key" do
      composed   = candidate(url: "https://a.example/café")   # é
      decomposed = candidate(url: "https://a.example/café")  # e + combining acute
      expect(key(composed)).to eq(key(decomposed))
    end

    it "refuses an unknown origin rather than ranking it arbitrarily" do
      expect { order.origin_rank("guessed") }.to raise_error(ArgumentError, /unknown frontier origin/)
    end

    it "refuses a negative depth or link position" do
      expect { order.uint32(-1) }.to raise_error(ArgumentError, /negative/)
    end
  end
end
