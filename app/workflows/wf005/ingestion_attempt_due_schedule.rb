# frozen_string_literal: true

module Workflows
  module Wf005
    # The creation point of every `ingestion_attempt_due` action (BACKGROUND_PROCESSING.md :140,
    # :200, :378), which is :378's "exact INGESTION ... action" — the other half of the sentence
    # `CrawlFetchDueSchedule` already implements the frontier half of.
    #
    # ALWAYS ON THE CALLER'S TRANSACTION, for the same reason the frontier link is: ":378 — its
    # terminal transaction creates the exact ingestion or next-frontier action." A fetch pass that
    # committed its Document and IngestionJob without the action would leave a queued job nothing ever
    # ran; a pass that created the action and rolled back the job would dispatch work against a job
    # that does not exist. One commit, both.
    #
    # THE TARGET IS THE INGESTION JOB, NOT THE ATTEMPT, and the reason is stronger here than the
    # analogous ruling for `crawl_fetch_due` (DECISIONS ADR-085, FU-16).
    #
    # :200's dispatch registry records the direct claim owner as "Ingestion Attempt". But an attempt
    # row created at SCHEDULING time would break :466's own bound: ":466 — one initial attempt plus
    # TWO RETRIES", and `attempt_count` is `COUNT(*)` over `ingestion_attempts`, so an action that was
    # created and never delivered would leave a permanently un-started attempt row consuming one of
    # the three. The retry action is minted by the transaction that RECORDS THE FAILURE, so the
    # failing execution would be creating its successor's attempt — which is also a second producer of
    # attempt rows, the exact thing ADR-085 refused.
    #
    # NOTHING IS UNSOUND. The job IS a claim owner: `queued -> running` under a compare-and-set on
    # `state_version` is the claim, and the durable idempotency authority is unchanged — it is the
    # attempt identity `(ingestion_job_id, attempt_number)` under its `ON CONFLICT`, which the
    # executing delivery derives from committed state. And unlike `crawl_frontier_entry`, this
    # `target_type` needs no reconciliation: `ingestion_job` IS a member of the entity-type vocabulary
    # API_CONTRACTS.md declares closed (:812-:815 give it as an event aggregate type), so FU-17's
    # divergence does not extend to this kind.
    #
    # THE REPLAY GENERATION IS THE PRODUCT GENERATION. The ratified identity preimage is
    # `(kind, schema, org, project, target, product_generation, schedule_generation, due_at)`, and
    # :303's authorized replay reuses the SAME job row — so without this a replayed job's first
    # attempt, due at an instant a prior generation's action had also been due at, would REPLAY that
    # spent action instead of creating a new one, and the replay would never run. S-07-011 owns the
    # replay command; this makes its actions distinguishable in advance rather than after the defect.
    module IngestionAttemptDueSchedule
      module_function

      ACTION_KIND = "ingestion_attempt_due"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "ingestion_job"

      # :140 — "initial or declared 30/120-second retry". Both go through here so the identity rule,
      # the lease input and the generation are stated once.
      #
      # `product_attempt_deadline` is :288's LEASE DURATION INPUT, stamped by the producer because
      # only the producer knows it. For ingestion it is the attempt's own bound: :466 gives each
      # attempt a 30-second timeout, so the work this action dispatches may legitimately take that
      # long and no longer. `scheduled_actions` does the arithmetic on a plain instant and never reads
      # `ingestion_jobs` to discover it — the same separation `CrawlFetchDueSchedule` keeps.
      def schedule(pg:, organization_id:, project_id:, job_id:, replay_generation:, due_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil)
        created = Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: job_id,
          product_generation: replay_generation.to_i, schedule_generation: 1,
          due_at:, now:, correlation_id:, causation_id: causation_id || correlation_id, command_id:,
          executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
          product_attempt_deadline: due_at + IngestionContract::ATTEMPT_TIMEOUT_S
        )
        { job_id:, due_at:, action_id: created[:id], replayed: created[:replayed] }
      end

      # ":466 — 30 and 120 seconds AFTER THE PRECEDING FAILED ATTEMPT." The instant is DERIVED from
      # the committed attempt row rather than from this worker's clock, so two deliveries of one
      # action compute the same instant, therefore the same action identity, and the second replays
      # the first's action instead of forking the chain into two retries. That is the same rule
      # ADR-089 established for :444, applied to the schedule :466 states.
      def retry_at(completed_at, attempt_number)
        Platform::PgInstant.utc(completed_at) + IngestionContract.retry_delay_s(attempt_number)
      end
    end
  end
end
