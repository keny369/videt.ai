# frozen_string_literal: true

# S-07-009's ENABLING SCHEMA CHANGE: the terminal checkpoint has no legal move today.
#
# `f1_crawls_guard` admits exactly `queued -> running` and `queued -> failed`, which is what S-07-003
# needed and all it opened — its own migration says so in terms ("running->terminal and cancel are
# relaxed by later tranches"). This is that tranche. WORKFLOW_SPECIFICATIONS.md :736 fixes the whole
# edge set: "Crawl.Queued -> Crawl.Running, Crawl.Failed on the exact pre-execution gate, or
# Crawl.Canceled; Crawl.Running -> Crawl.Completed, Crawl.Failed, or Crawl.Canceled." Nothing wider,
# and in particular nothing OUT of a terminal state.
#
# THREE RULES, AND TWO OF THEM ARE NEW CLOSURES RATHER THAN RELAXATIONS. A migration that only widened
# the edge set would open the terminal transition and leave the record it writes rewritable, which is
# the same class of defect FU-11 was: a column that carries the customer-visible answer and no rule
# saying it may be written once.
#
#   1. THE EDGE SET IS :736's, exactly.
#
#   2. A TERMINAL CRAWL IS FINISHED — no UPDATE of any kind, not merely no state change. :458 says
#      "terminal selection occurs ONCE at a serialized checkpoint", and :735 says a recovery "creates a
#      new linked `Crawl.Queued` attempt RATHER THAN TRANSITIONING THE OLD RECORD"; MTX-030 says "no
#      terminal Crawl is moved back to running". Confining the guard to state changes would have left
#      `coverage_status` and `completion_reason` freely rewritable on a finished run — the checkpoint
#      would be "once" only by convention, and a second opinion about a customer's coverage would be
#      indistinguishable from the first. There is no legitimate writer: `retry_generation`,
#      `recovery_generation` and `recovery_of_id` belong to the NEW attempt a recovery creates, which
#      is exactly what :735 says the old record must not absorb.
#
#   3. THE RUN'S METERING IDENTITY IS FIXED AT THE ACCEPTED START. POSTGRESQL_SCHEMA.md :338 declares
#      `entitlement_decision_id` and `entitlement_reservation_id` "NULL until start", and once the
#      start has stamped them they name the reservation this run is committed or released against at
#      the checkpoint — MTX-030: "commit or release its reservation EXACTLY ONCE". Swapping either is
#      an UPDATE that changes no state, so it would otherwise have passed every check on this table.
#      Scoped on `OLD.started_at IS NOT NULL`, so the accepted start still stamps both in the same
#      statement that leaves `queued`.
#
# WHAT WAS CONSIDERED AND DELIBERATELY NOT TAKEN HERE: freezing `started_at` and `deadline_at` with
# them. The argument is sound — :442 starts the wall clock at the `Queued -> Running` transition and
# `crawl_terminal_deadline` fires at exactly `deadline_at`, so a movable deadline makes the 60-minute
# ceiling renegotiable by an UPDATE — but nothing in production writes either column after the start,
# and the rule costs SIX pre-existing accepted examples across four spec files, whose harnesses
# simulate an expired run by moving the deadline backwards. Rewriting six accepted setups to buy
# defence in depth against a writer that does not exist is not this tranche's trade to make on its own
# authority; it is recorded as FU-30 so it is a deliberate change rather than a side effect of this one.
#
# The frozen request facts are unchanged and are still refused under their own reason code.
class CrawlsTerminalTransitions < ActiveRecord::Migration[8.1]
  # :736's edge set. Terminal states appear only on the right, which is what makes every edge out of
  # `completed`, `failed` and `canceled` unavailable without enumerating them.
  TRANSITIONS = <<~SQL.strip
    (OLD.state = 'queued'  AND NEW.state IN ('running','failed','canceled'))
       OR (OLD.state = 'running' AND NEW.state IN ('completed','failed','canceled'))
  SQL

  # What S-07-003 left, restored verbatim by `down`.
  PRIOR_TRANSITIONS = "OLD.state = 'queued' AND NEW.state IN ('running','failed')"

  def up = write_guard(transitions: TRANSITIONS, terminal_frozen: true, run_identity_frozen: true)

  def down = write_guard(transitions: PRIOR_TRANSITIONS, terminal_frozen: false, run_identity_frozen: false)

  private

  def write_guard(transitions:, terminal_frozen:, run_identity_frozen:)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawls_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        #{terminal_frozen ? terminal_limb : ''}
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
        #{run_identity_frozen ? run_identity_limb : ''}
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          IF NOT (#{transitions}) THEN
            RAISE EXCEPTION 'crawl_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  # Before the frozen-facts limb, deliberately: a terminal row must refuse an UPDATE whatever it
  # touches, and reporting a frozen-fact violation for one would name the wrong rule.
  def terminal_limb = <<~SQL.strip
    IF OLD.state IN ('completed','failed','canceled') THEN
          RAISE EXCEPTION 'crawl_terminal_immutable' USING ERRCODE = 'raise_exception';
        END IF;
  SQL

  def run_identity_limb = <<~SQL.strip
    IF OLD.started_at IS NOT NULL
           AND (NEW.entitlement_decision_id IS DISTINCT FROM OLD.entitlement_decision_id
                OR NEW.entitlement_reservation_id IS DISTINCT FROM OLD.entitlement_reservation_id) THEN
          RAISE EXCEPTION 'crawl_run_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
  SQL
end
