# frozen_string_literal: true

# S-07-006 review hardening (ADR-026 schema and concurrency lenses).
#
# THREE CONFIRMED-BLOCKING DEFECTS.
#
# 1. THE TERMINAL DECISION WAS NOT WRITE-ONCE. `20260727120220`'s own rationale says the sitemap
#    decision is frozen "for the same reason the robots one is", but its frozen set named only four
#    of the seven columns the terminal statement writes. `sitemap_documents_fetched` and
#    `sitemap_max_index_depth` are written ONLY by `terminalize_sitemaps`, in the same statement that
#    sets the terminal state — they are terminal-decision fields by construction, and they are the
#    OBSERVED VALUES :442 requires a limit decision to record. `sitemap_discarded` is written by
#    `begin_sitemaps` in the same statement as `sitemap_candidates`; freezing one and not the other
#    is arbitrary. Reviewed as the runtime role, all three were rewritable after terminalisation.
#
#    This is the third appearance of the same defect class: S-07-005 was blocked for omitting
#    `robots_rules_schema` from the robots frozen set, and `20260727120200` exists only to repair it.
#    So the guard is rebuilt to derive its frozen set from a NAMED LIST that the migration and the
#    review can both read, rather than from a hand-copied condition.
#
# 2. UNBOUNDED AUDIT PAYLOADS SAT ON THE HOT LOCKED ROW. `sitemap_discarded` receives the OVERFLOW of
#    the declared candidate set — `retain` keeps 50 and discards EVERYTHING ELSE — and the declared
#    set comes from robots.txt, where :448 bounds the body at 1 MiB but nothing bounds the number of
#    `Sitemap:` lines. That is ~39,000 candidates, ~2.8 MB detoasted, on the row `lock_gate` reads
#    with `SELECT g.* ... FOR UPDATE` before EVERY fetch. Measured at ~15 ms per gate read held under
#    an exclusive row lock that every worker on that host serialises behind.
#
#    Both halves are fixed: the lists are bounded here so the row cannot grow without limit, and the
#    hot read is projected (in the store) so the bulk never travels on the locked path at all.
#
# 3. THE TERMINAL WRITE WAS NOT BOUND TO THE WORKER HOLDING THE CLAIM (ADR-026 concurrency lens).
#    `terminalize_sitemaps` matched on `sitemap_state = 'in_progress'` alone, so a worker that LOST
#    the `pending -> in_progress` race could still write the write-once outcome for a run another
#    worker was executing. Reviewed live: the loser wrote `unavailable` / `documents_fetched = 0`
#    while the winner's sitemap-origin frontier entries existed in the same Crawl, and the winner's
#    own terminalize then matched zero rows SILENTLY. `sitemap_claim_token` makes the terminal write
#    answer to the claim, so only the executing worker can close its own attempt.
#
#    Honouring the claim needs a way back from a LOST worker, or a crashed traversal would wedge the
#    host as `in_progress` for the rest of the run — the robots limb already has exactly this in
#    `robots_attempt_started_at`. `sitemap_attempt_started_at` is its counterpart: a claim older than
#    the stale bound may be taken over, and the takeover rotates the token so the lost worker cannot
#    later terminalize on top of its successor.
class HardenCrawlHostGateSitemaps < ActiveRecord::Migration[8.1]
  TERMINAL = %w[succeeded absent unavailable].freeze

  # Every column the sitemap decision writes. Frozen once the decision is terminal — the whole set,
  # not a subset, because "which of these is really part of the decision" is exactly the judgement
  # that produced the defect twice before.
  FROZEN = %w[
    sitemap_state sitemap_outcome_reason sitemap_terminal_at sitemap_candidates
    sitemap_discarded sitemap_documents_fetched sitemap_max_index_depth
    sitemap_skipped sitemap_limit_reasons sitemap_claim_token
  ].freeze

  # The retained set is :454's 50. The audit lists are bounded generously above any legitimate value
  # — a real host declares a handful of sitemaps — so the bound is a safety ceiling on a remote
  # input, not a scheduling target. The workflow truncates to these values and records that it did,
  # so a bound is never reached silently.
  CANDIDATE_BOUND = 50
  AUDIT_BOUND = 200

  def up
    execute <<~SQL
      ALTER TABLE crawl_host_gates
        ADD COLUMN sitemap_claim_token uuid,
        ADD COLUMN sitemap_attempt_started_at timestamptz(6);

      -- An in-progress attempt always names its claim and when it started; a pending one names
      -- neither. Without this the reclamation window has nothing to measure and the token is
      -- optional exactly when it is load-bearing.
      ALTER TABLE crawl_host_gates ADD CONSTRAINT crawl_host_gates_sitemap_claim_shape
        CHECK ((sitemap_state = 'pending')
               = (sitemap_claim_token IS NULL AND sitemap_attempt_started_at IS NULL));

      ALTER TABLE crawl_host_gates
        ADD CONSTRAINT crawl_host_gates_sitemap_candidates_bounded
          CHECK (jsonb_array_length(sitemap_candidates) <= #{CANDIDATE_BOUND}),
        ADD CONSTRAINT crawl_host_gates_sitemap_discarded_bounded
          CHECK (jsonb_array_length(sitemap_discarded) <= #{AUDIT_BOUND}),
        ADD CONSTRAINT crawl_host_gates_sitemap_skipped_bounded
          CHECK (jsonb_array_length(sitemap_skipped) <= #{AUDIT_BOUND}),
        ADD CONSTRAINT crawl_host_gates_sitemap_limit_reasons_bounded
          CHECK (jsonb_array_length(sitemap_limit_reasons) <= #{AUDIT_BOUND});
    SQL
    rebuild_guard
  end

  def down
    execute <<~SQL
      ALTER TABLE crawl_host_gates
        DROP CONSTRAINT crawl_host_gates_sitemap_claim_shape,
        DROP COLUMN sitemap_attempt_started_at,
        DROP COLUMN sitemap_claim_token,
        DROP CONSTRAINT crawl_host_gates_sitemap_limit_reasons_bounded,
        DROP CONSTRAINT crawl_host_gates_sitemap_skipped_bounded,
        DROP CONSTRAINT crawl_host_gates_sitemap_discarded_bounded,
        DROP CONSTRAINT crawl_host_gates_sitemap_candidates_bounded;
    SQL
    restore_previous_guard
  end

  private

  def list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"

  def frozen_condition
    FROZEN.map { |c| "NEW.#{c} IS DISTINCT FROM OLD.#{c}" }.join("\n             OR ")
  end

  def rebuild_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_host_gates_sitemap_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF OLD.sitemap_state IN #{list(TERMINAL)} THEN
          IF #{frozen_condition} THEN
            RAISE EXCEPTION 'crawl_host_gate_sitemap_decision_frozen' USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        IF NEW.sitemap_state IS DISTINCT FROM OLD.sitemap_state THEN
          IF NOT ((OLD.sitemap_state = 'pending' AND NEW.sitemap_state = 'in_progress')
                  OR (OLD.sitemap_state = 'in_progress' AND NEW.sitemap_state IN #{list(TERMINAL)})
                  OR (OLD.sitemap_state = 'in_progress' AND NEW.sitemap_state = 'pending')) THEN
            RAISE EXCEPTION 'crawl_host_gate_sitemap_transition_unavailable % -> %',
              OLD.sitemap_state, NEW.sitemap_state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  def restore_previous_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_host_gates_sitemap_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF OLD.sitemap_state IN #{list(TERMINAL)} THEN
          IF NEW.sitemap_state IS DISTINCT FROM OLD.sitemap_state
             OR NEW.sitemap_outcome_reason IS DISTINCT FROM OLD.sitemap_outcome_reason
             OR NEW.sitemap_terminal_at IS DISTINCT FROM OLD.sitemap_terminal_at
             OR NEW.sitemap_candidates IS DISTINCT FROM OLD.sitemap_candidates THEN
            RAISE EXCEPTION 'crawl_host_gate_sitemap_decision_frozen' USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        IF NEW.sitemap_state IS DISTINCT FROM OLD.sitemap_state THEN
          IF NOT ((OLD.sitemap_state = 'pending' AND NEW.sitemap_state = 'in_progress')
                  OR (OLD.sitemap_state = 'in_progress' AND NEW.sitemap_state IN #{list(TERMINAL)})
                  OR (OLD.sitemap_state = 'in_progress' AND NEW.sitemap_state = 'pending')) THEN
            RAISE EXCEPTION 'crawl_host_gate_sitemap_transition_unavailable % -> %',
              OLD.sitemap_state, NEW.sitemap_state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end
end
