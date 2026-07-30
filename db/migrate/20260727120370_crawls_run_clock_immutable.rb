# frozen_string_literal: true

# FU-30: `crawls.started_at` and `crawls.deadline_at` were writable after the accepted start, so the
# 60-minute run ceiling was renegotiable by an UPDATE that changes no state.
#
# WHY THIS IS NOT MERELY UNTIDY. WORKFLOW_SPECIFICATIONS.md :442 starts wall-clock duration "at the
# atomic `Crawl.Queued -> Crawl.Running` transition", and BACKGROUND_PROCESSING.md :139 fires
# `crawl_terminal_deadline` at exactly `deadline_at`. Both of those are statements about a FIXED
# instant. A movable column makes the ceiling advisory: the run's own bound, the instant its terminal
# checkpoint was scheduled for, and the elapsed figure every `wall_clock_run_duration` limit decision
# records would all be derived from a value that anything holding UPDATE could move afterwards —
# without changing `state`, and therefore without meeting any other check on this table.
#
# `20260727120360` froze the METERING identity for the same reason and deliberately left these two,
# because the rule cost six pre-existing accepted examples whose harnesses simulate an expired run by
# writing `deadline_at` backwards. Rewriting six accepted setups was recorded as FU-30 rather than taken
# as a side effect of the tranche that noticed it. This is that repair, taken on its own authority, and
# the harnesses now express an old run the way production does: by advancing the clock, and by renewing
# :551's entitlement lease through the same `Platform::Entitlement::Service#heartbeat` every pass uses.
#
# SCOPED ON `OLD.started_at IS NOT NULL`, so the accepted start still stamps both columns in the same
# statement that leaves `queued` — `IdentityAccess::Infrastructure::CrawlStartStore#start` is the only
# writer of either, and it is unaffected. After it, neither column may move again by any route.
class CrawlsRunClockImmutable < ActiveRecord::Migration[8.1]
  # The metering identity `20260727120360` froze, with the run's clock added.
  FROZEN_AFTER_START = <<~SQL.strip
    NEW.started_at IS DISTINCT FROM OLD.started_at
                OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
                OR NEW.entitlement_decision_id IS DISTINCT FROM OLD.entitlement_decision_id
                OR NEW.entitlement_reservation_id IS DISTINCT FROM OLD.entitlement_reservation_id
  SQL

  # What `20260727120360` left: the metering identity alone.
  PRIOR = <<~SQL.strip
    NEW.entitlement_decision_id IS DISTINCT FROM OLD.entitlement_decision_id
                OR NEW.entitlement_reservation_id IS DISTINCT FROM OLD.entitlement_reservation_id
  SQL

  def up = write_guard(FROZEN_AFTER_START)

  def down = write_guard(PRIOR)

  private

  def write_guard(frozen)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawls_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.state IN ('completed','failed','canceled') THEN
          RAISE EXCEPTION 'crawl_terminal_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.kind IS DISTINCT FROM OLD.kind
           OR NEW.parent_evaluation_id IS DISTINCT FROM OLD.parent_evaluation_id
           OR NEW.parent_crawl_id IS DISTINCT FROM OLD.parent_crawl_id
           OR NEW.requested_crawl_policy_id IS DISTINCT FROM OLD.requested_crawl_policy_id
           OR NEW.requested_crawl_policy_version IS DISTINCT FROM OLD.requested_crawl_policy_version
           OR NEW.requested_entitlement_policy_id IS DISTINCT FROM OLD.requested_entitlement_policy_id
           OR NEW.requested_entitlement_policy_version IS DISTINCT FROM OLD.requested_entitlement_policy_version
           OR NEW.trigger_kind IS DISTINCT FROM OLD.trigger_kind
           OR NEW.triggered_by_account_id IS DISTINCT FROM OLD.triggered_by_account_id
           OR NEW.queued_at IS DISTINCT FROM OLD.queued_at
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'crawl_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.started_at IS NOT NULL
           AND (#{frozen}) THEN
          RAISE EXCEPTION 'crawl_run_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          IF NOT ((OLD.state = 'queued'  AND NEW.state IN ('running','failed','canceled'))
                  OR (OLD.state = 'running' AND NEW.state IN ('completed','failed','canceled'))) THEN
            RAISE EXCEPTION 'crawl_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end
end
