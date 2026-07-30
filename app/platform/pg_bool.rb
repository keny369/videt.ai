# frozen_string_literal: true

module Platform
  # Read a PostgreSQL boolean whose Ruby encoding depends on the CONNECTION, not on the value.
  #
  # This exists because it FAILS SILENTLY AND FAILS FALSE. An ActiveRecord-owned connection carries type
  # mapping and yields `true`; a raw `PG.connect` (the shape several test harnesses and the transport
  # connection use) yields the string `"t"`. A predicate written against one of those is not merely
  # imprecise on the other — it is a constant. The S-07-012 review round found exactly that: a freshly
  # written `... == "t"` was always false on the connection it actually ran on, so a PINNED crawl frontier
  # went on reporting itself DRAINED, which is the very statement the check had just been added to stop.
  #
  # A wrong boolean read has no failure mode that looks like a failure, so the sites that MUST cross the
  # two encodings go through one implementation. It is not yet the repository's only such reader: a dozen
  # pre-existing `truthy`/`== "t"` helpers remain on connections whose encoding never varies, and folding
  # them in is a separate sweep, not a claim this file gets to make.
  module PgBool
    module_function

    TRUE_VALUES = [true, "t", "true", "1"].freeze

    def true?(value) = TRUE_VALUES.include?(value)
  end
end
