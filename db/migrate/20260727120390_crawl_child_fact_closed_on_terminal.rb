# frozen_string_literal: true

# R6-2 AND R6-3: A TERMINAL CRAWL HAS A CLOSED FACT SET, AND THE DATABASE IS WHAT CLOSES IT.
#
# Owner ruling 2 of the round-6 programme: "Once a Crawl becomes terminal, no new child fact may be
# inserted for that Crawl. Treat a post-terminal child fact as a data-integrity violation, not as an
# accepted timing window. Own this rule at the database boundary so every producer is covered."
#
# WHAT THE GUARDS ALREADY DID AND WHY IT WAS NOT THIS. `crawl_limit_decisions_guard` and
# `crawl_terminal_outcomes_guard` are `BEFORE DELETE OR UPDATE` and raise unconditionally: T-IMM, no
# row ever changes. That makes each row immutable ONCE WRITTEN and says nothing about whether it may
# be written. Round 6 read the catalogue and stated the gap exactly: `f1_runtime` retains INSERT on
# both tables, the guards cover UPDATE/DELETE only, and the composite foreign keys and RLS policies
# validate identity and tenant rather than PARENT STATE. A valid child fact could therefore be
# inserted after any terminal state and permanently disagree with the frozen Crawl outcome, which
# `f1_crawls_guard` then makes uncorrectable because it admits no edge out of a terminal row.
#
# WHY ONE FUNCTION AND NOT A REPAIRED CALL SITE. This defect class has now been repaired three times
# at one producer each: B7/R2-B1 fenced `CrawlDriver#retire` with the frontier lock and a state
# re-read, R5-3 fenced Admission's fall-through, and both left the OTHER producers alone. Round 6
# found the two that were left — hard-expired Admission (R6-2) and in-progress sitemap discovery
# (R6-3) — and the honest reading is that a rule enforced once per producer will keep being one
# producer behind. The parent's state is a property of the parent, so it is checked where the parent
# lives.
#
# THE LOCK GRAPH IS UNCHANGED, WHICH IS THE PART THAT NEEDED CHECKING. Every one of these tables
# already carries a composite foreign key to `crawls (organization_id, project_id, id)`, so every
# INSERT ALREADY acquires `FOR KEY SHARE` on that Crawl row. This function takes the same lock on the
# same row a few microseconds earlier. It introduces no edge that the referential integrity check did
# not already introduce, so the subsystem's one order — `crawl-frontier:<crawl>` advisory, THEN
# `crawls` — is exactly as it was, and no new cycle is reachable.
#
# AND `FOR KEY SHARE` IS WHY IT IS DETERMINISTIC RATHER THAN ADVISORY. A plain `SELECT state` would
# read the committed preimage under READ COMMITTED and pass while a terminal transition sat
# uncommitted one lock away — which is PRECISELY the interleaving round 6 reproduced: Admission read
# `running`, blocked on the foreign key's own tuple lock, and committed its decisions after
# CancelCrawl's `canceled` landed. `FOR KEY SHARE` conflicts with the `FOR UPDATE` both terminal
# handlers take, so this transaction blocks until the terminal decision is committed or rolled back
# and then reads the answer rather than a memory of it.
#
# WHAT IS GOVERNED AND WHAT IS DELIBERATELY NOT. The governed set is the rows the terminal selection
# and the coverage record READ, because those are the ones that can permanently disagree with a
# frozen outcome:
#
#   * `crawl_limit_decisions`      — :442's immutable observations, and the once-per-run event with them
#   * `crawl_terminal_outcomes`    — :452's coverage classification per retired entry
#   * `crawl_frontier_entries`     — the candidate population :458 counts; R6-3's late `/late` offer
#   * `crawl_frontier_occurrences` — the same population's dedup record
#   * `crawl_host_gates`           — :450/:452's sitemap and robots outcomes, which feed `unresolved`
#
# NOT GOVERNED, each for a stated reason rather than by omission:
#
#   * `fetch_attempts` — FU-32 is the OPEN OWNER DECISION that a cancellation is pass-boundary
#     effective, and `Handlers::CancelCrawl` discloses in terms that an already-authorized pass may
#     still write attempt rows. Those rows are inert: no terminal query reads them. Closing them here
#     would silently decide FU-32, which this tranche is not authorized to do.
#   * `crawl_budget_counters` and `crawl_sitemap_document_charges` — reservation bookkeeping, not
#     facts about the run's coverage. A late RELEASE of reserved bytes is correct and necessary
#     cleanup, and refusing it would strand budget rather than protect a record.
#   * `crawl_sources`, `evaluations`, `evaluation_orchestration_contexts` — written at queue time or
#     owned by another workflow's lifecycle, neither of which is a post-terminal production path.
#
# THE UPDATE LIMB EXISTS FOR EXACTLY ONE TABLE. `crawl_host_gates` records its :450 outcome by
# UPDATING a claimed row, so R6-3's second variant — `sitemap_unavailable` committed after the
# checkpoint had already counted `unresolved_discovery = 0` — is an UPDATE and no INSERT rule can
# reach it. The limb is narrowed to the columns that ARE the outcome, so a gate's pacing and
# bookkeeping columns stay writable and the rate window is not broken by a terminal run.
#
# A REFUSED LATE CLAIM LEAVES A CLAIMED GATE, AND THAT IS THE RIGHT RESIDUE. A worker whose sitemap
# terminalization is refused leaves its gate `in_progress` on a Crawl that is over. Nothing reads it
# again, the coverage record is already frozen, and inventing a sweep here would be an ad hoc
# substitute for S-07-011's stranded-claim recovery. It is recorded there rather than improvised here.
class CrawlChildFactClosedOnTerminal < ActiveRecord::Migration[8.1]
  GOVERNED_INSERT = %w[
    crawl_limit_decisions
    crawl_terminal_outcomes
    crawl_frontier_entries
    crawl_frontier_occurrences
    crawl_host_gates
  ].freeze

  # The columns that ARE :450/:452's sitemap and robots outcome. Everything else on the gate — the
  # rate window, the pacing floor, the deferral counters — stays writable on a terminal run.
  SITEMAP_OUTCOME_COLUMNS = %w[
    sitemap_state sitemap_outcome_reason sitemap_terminal_at sitemap_limit_reasons
    robots_state robots_terminal_reason robots_terminal_at
  ].freeze

  def up
    execute <<~SQL
      CREATE FUNCTION f1_crawl_child_fact_closed() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE
        parent_state text;
      BEGIN
        -- FOR KEY SHARE, not a plain read: this must BLOCK on an uncommitted terminal transition
        -- rather than pass on its preimage. It is the same lock this row's foreign key takes on the
        -- same row in the same statement, so it adds no edge to the subsystem's lock order.
        SELECT c.state INTO parent_state
        FROM crawls c WHERE c.id = NEW.crawl_id FOR KEY SHARE;

        -- FAIL CLOSED. The foreign key guarantees the parent exists, so an invisible row means this
        -- statement is running outside a proved Organization context, and a child fact written from
        -- outside one may not be admitted on the strength of a check that could not run.
        IF parent_state IS NULL THEN
          RAISE EXCEPTION 'crawl_child_fact_parent_unreadable' USING ERRCODE = 'raise_exception';
        END IF;

        IF parent_state IN ('completed', 'failed', 'canceled') THEN
          RAISE EXCEPTION 'crawl_child_fact_after_terminal' USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NULL;
      END;
      $$;
    SQL

    # AFTER, NOT BEFORE, AND THE REASON IS TENANT ISOLATION RATHER THAN TASTE. PostgreSQL evaluates a
    # policy's WITH CHECK limb on the row a BEFORE trigger leaves behind, so a BEFORE trigger runs
    # AHEAD of RLS. This function reads `crawls` under the caller's own context, so on a cross-tenant
    # insert it would find the parent invisible and refuse with `crawl_child_fact_parent_unreadable` —
    # pre-empting the RLS refusal and answering a tenant violation with a state message. PROOF 40b
    # exists to prove that limb refuses as RLS, and it is right to.
    #
    # AFTER-ROW COSTS NOTHING HERE. The statement still aborts, the advisory `FOR KEY SHARE` is still
    # taken inside the same statement and before commit, and it now sits alongside the composite
    # foreign key's own constraint trigger, which is the same lock on the same row.
    GOVERNED_INSERT.each do |table|
      execute <<~SQL
        CREATE TRIGGER #{table}_terminal_closure AFTER INSERT ON #{table}
          FOR EACH ROW EXECUTE FUNCTION f1_crawl_child_fact_closed();
      SQL
    end

    execute <<~SQL
      CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON crawl_host_gates
        FOR EACH ROW
        WHEN (#{SITEMAP_OUTCOME_COLUMNS.map { |c| "NEW.#{c} IS DISTINCT FROM OLD.#{c}" }.join(' OR ')})
        EXECUTE FUNCTION f1_crawl_child_fact_closed();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS crawl_host_gates_terminal_outcome_closure ON crawl_host_gates;"
    GOVERNED_INSERT.each do |table|
      execute "DROP TRIGGER IF EXISTS #{table}_terminal_closure ON #{table};"
    end
    execute "DROP FUNCTION IF EXISTS f1_crawl_child_fact_closed();"
  end
end
