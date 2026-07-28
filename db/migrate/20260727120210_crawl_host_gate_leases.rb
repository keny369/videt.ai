# frozen_string_literal: true

# S-07-005 review hardening, round two (ADR-026 CONCURRENCY lens — the fifth lens, which reported
# after the tranche had been recorded as accepted; see ADR-080).
#
# Two confirmed-blocking defects, both in the concurrency slot accounting, and both fixed by making a
# claim an IDENTIFIED, SELF-EXPIRING LEASE rather than an anonymous counter increment.
#
#   1. `release_slot` was unguarded — no claim identity of any kind. One worker calling release twice
#      (a retry, a replayed message, an `ensure` plus an explicit release) decremented a slot it did
#      not hold, and `GREATEST(count - 1, 0)` turned that accounting error into a SILENTLY WIDENED
#      concurrency ceiling: the reviewer drove the count to 0 with two connections still live, and
#      the next claim was granted, so three real connections were accounted as one. :442 calls these
#      ceilings "nonexceedable".
#
#   2. Nothing reconciled the count after PROCESS LOSS. SEARCH_CRAWL_RETRIEVAL :82 is directly on
#      point — "Process loss after claim is repaired by the lease sweeper; the same attempt identity
#      is completed or timed out, never replaced by an unaccounted request." There was no sweeper,
#      and the row can never be deleted, so the count only ever fell via an explicit release. After
#      just two lost workers the host sat at its concurrency target and refused every claim for the
#      rest of the run — which :452 then turns into `content_fetch_failed` and partial coverage for
#      every URL on it.
#
# `active_leases` is the authority: each element is `{"token": uuid, "claimed_at": instant}`.
# Releasing removes a TOKEN, so it is idempotent by construction and can only ever release the claim
# it names. Sweeping removes leases older than the ceiling. `active_connection_count` is kept —
# schema :296 names it — but is now always DERIVED from the lease set in the same statement, so the
# two can never disagree.
class CrawlHostGateLeases < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE crawl_host_gates ADD COLUMN active_leases jsonb NOT NULL DEFAULT '[]';
      -- The named counter and the lease set are one fact, so the database keeps them equal rather
      -- than trusting every writer to.
      ALTER TABLE crawl_host_gates ADD CONSTRAINT crawl_host_gates_lease_count_agrees
        CHECK (active_connection_count = jsonb_array_length(active_leases));
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE crawl_host_gates DROP CONSTRAINT crawl_host_gates_lease_count_agrees;
      ALTER TABLE crawl_host_gates DROP COLUMN active_leases;
    SQL
  end
end
