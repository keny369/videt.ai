# frozen_string_literal: true

module Workflows
  module Wf005
    # The deterministic crawl frontier order (WORKFLOW_SPECIFICATIONS.md :454; contracts/S-07.json
    # MTX-030 `domain_service` — "the dequeue order ... [is a] pure function applied by the worker").
    #
    # Volume I fixes the order as the tuple
    #
    #     (depth, origin_rank, canonical_url, discovering_document_url, link_position)
    #
    # where `root < sitemap < link`, strings compare by UTF-8 bytes, and a root or sitemap candidate
    # uses an empty discovering-document URL and link position zero. Breadth-first falls out of the
    # tuple: `depth` leads, so every depth-`d` discovery is sealed before any depth-`d+1` candidate.
    #
    # SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic Selection requires that order to be
    # MATERIALIZED into `crawl_frontier_entries.dequeue_key bytea` so PostgreSQL can order and
    # uniquely index it, and requires that materialization to be "tested against a reference tuple
    # comparator". `bytea` compares bytewise, so the encoding must be ORDER-PRESERVING: for any two
    # candidates, `encode(a) <=> encode(b)` must equal `tuple(a) <=> tuple(b)`. Everything below
    # exists to make that true.
    #
    # Why the string fields are terminated rather than length-prefixed. A length prefix does not
    # preserve lexicographic order — `"b"` (length 1) would sort before `"ab"` (length 2) because
    # the prefix is compared first, while the tuple requires `"ab" < "b"`. The order-preserving
    # encoding for a variable-length field inside a composite key is instead to escape the
    # terminator: `0x00 -> 0x00 0xFF`, then close the field with `0x00 0x00`. A real `0x00` byte
    # therefore always compares below the terminator, and no field's bytes can be confused with the
    # boundary. The fixed-width numeric fields need no such treatment: unsigned big-endian of a
    # constant width already compares bytewise in numeric order.
    #
    # The trailing entry UUID makes the key TOTAL, which is what lets `crawl_frontier_entries` carry
    # a unique index on `(crawl_id, dequeue_key)` without two genuinely distinct candidates ever
    # colliding: the Volume I tuple alone is not unique (deduplication is what removes equal tuples,
    # and it keeps the first in this order), so the UUID is a tiebreak that can never reorder two
    # candidates that differ in any tuple field.
    module FrontierOrder
      module_function

      # `root < sitemap < link` (:454). The rank is what the key encodes; the name is what the row
      # stores, so the two can never drift.
      ORIGINS = { "root" => 0, "sitemap" => 1, "link" => 2 }.freeze
      ORIGIN_NAMES = ORIGINS.keys.freeze

      # Field framing for the variable-length UTF-8 fields.
      ESCAPE = "\x00\xFF".b
      TERMINATOR = "\x00\x00".b
      NUL = "\x00".b

      def origin_rank(origin)
        ORIGINS.fetch(origin) { raise ArgumentError, "unknown frontier origin #{origin.inspect}" }
      end

      # The materialized dequeue key. `depth` and `link_position` are non-negative integers;
      # `canonical_url` and `discovering_document_url` are Strings (the latter empty for a root or
      # sitemap candidate); `entry_id` is a UUID string, appended raw so the key is total.
      #
      # Widths are generous on purpose — depth is bounded at 10 and link position by the page's link
      # count under `crawl-policy-v1`, but a fixed 4-byte field costs nothing and removes any
      # possibility of an overflow silently reordering the frontier.
      def dequeue_key(depth:, origin:, canonical_url:, discovering_document_url:, link_position:, entry_id:)
        [
          uint32(depth),
          uint8(origin_rank(origin)),
          field(canonical_url),
          field(discovering_document_url),
          uint32(link_position),
          uuid_bytes(entry_id)
        ].join.b
      end

      # The reference comparator the encoding is tested against — Volume I's tuple, expressed
      # directly. `dequeue_key` must agree with this for every pair of candidates.
      def compare(a, b)
        tuple(a) <=> tuple(b)
      end

      def tuple(candidate)
        [
          candidate[:depth].to_i,
          origin_rank(candidate[:origin]),
          candidate[:canonical_url].to_s.unicode_normalize(:nfc).b,
          candidate[:discovering_document_url].to_s.unicode_normalize(:nfc).b,
          candidate[:link_position].to_i,
          uuid_bytes(candidate[:entry_id])
        ]
      end

      # ---- encodings ----------------------------------------------------------

      # NFC UTF-8 bytes with the terminator escaped, then closed. NFC is applied here (and in the
      # comparator) so two byte-different spellings of the same Unicode string cannot occupy two
      # frontier positions — SEARCH_CRAWL_RETRIEVAL.md fixes the fields as "NFC UTF-8".
      def field(value)
        value.to_s.unicode_normalize(:nfc).b.gsub(NUL, ESCAPE) + TERMINATOR
      end

      def uint32(value)
        raise ArgumentError, "negative value #{value}" if value.to_i.negative?

        [value.to_i].pack("N")
      end

      def uint8(value) = [value.to_i].pack("C")

      # The 16 raw bytes of a canonical UUID string.
      def uuid_bytes(uuid)
        [uuid.to_s.delete("-")].pack("H*")
      end
    end
  end
end
