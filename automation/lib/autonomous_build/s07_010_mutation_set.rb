# frozen_string_literal: true

module AutonomousBuild
  # THE S-07-010 MUTATION SET, IN THE REPOSITORY.
  #
  # The ledger is REGENERATED from this file by `f1:mutations:regenerate SET=s07_010`, never edited by
  # hand. Each entry names an exact substitution and the proof that must reject it, so the repository
  # can replay the whole set and recompute every verdict from first principles.
  #
  # WHAT A ROW IS FOR. Not "the suite is green" — a passing suite says only that nothing it happens to
  # check is broken. A row says: REMOVE THIS EXACT CONTROL AND THIS EXACT PROOF FAILS. The controls
  # chosen here are the ones whose absence would be silent and expensive: a covered outcome with no
  # artifact behind it, a retention bound nobody enforces, staged customer bytes nobody destroys, a
  # retry schedule that runs forever, and a late worker overwriting a settled job.
  module S07010MutationSet
    HANDOFF = "app/workflows/wf005/ingestion_handoff.rb"
    EXECUTION = "app/workflows/wf005/ingestion_execution.rb"
    CONTRACT = "app/workflows/wf005/ingestion_contract.rb"
    SCHEDULE = "app/workflows/wf005/ingestion_attempt_due_schedule.rb"
    DOCUMENT_STORE = "app/contexts/identity_access/infrastructure/document_store.rb"
    JOB_STORE = "app/contexts/identity_access/infrastructure/ingestion_job_store.rb"
    OUTCOME_STORE = "app/contexts/identity_access/infrastructure/crawl_terminal_outcome_store.rb"
    FETCH_HANDLER = "app/workflows/wf005/handlers/record_fetch_attempt.rb"
    FETCH_HANDLER_INGEST = "app/workflows/wf005/handlers/run_ingestion_job.rb"

    INGESTION_PROOF = "spec/acceptance/wf005_document_ingestion_spec.rb"
    SCHEMA_PROOF = "spec/persistence/documents_and_ingestion_schema_spec.rb"
    # NOT `crawl_terminal_fact_closure_spec`. Its PROOF 156 derives every Crawl child table and
    # requires the closure TRIGGER to exist on each — which answers "was this table classified" and
    # says nothing about whether the trigger still refuses anything. A mutant that leaves the trigger
    # in place with a WHEN clause that never holds passes it untouched, and did: the row below
    # survived until `documents_and_ingestion_schema_spec` measured the REFUSAL rather than the row.

    ENTRIES = [
      # ---- :452's artifacts. A covered outcome with nothing behind it is the defect the whole
      # tranche exists to make impossible, and it is invisible from the coverage number alone. -----
      { id: "s10-document-not-created", blocker: "S-07-010/:452", file: HANDOFF, proof: INGESTION_PROOF,
        description: "`document_created` produces no Document, so :452's covered outcome asserts an " \
                     "artifact that does not exist and `crawl_terminal_outcomes.document_id` is NULL again",
        from: "        when FetchContent::DOCUMENT_CREATED then create_document_and_job(pg, organization_id, crawl, entry, result, now)",
        to: "        when FetchContent::DOCUMENT_CREATED then NOTHING",
        expectation: "kill" },
      { id: "s10-absence-not-recorded", blocker: "S-07-010/:452", file: HANDOFF, proof: INGESTION_PROOF,
        description: "a terminal 404/410 records no body-free `crawl_observation`, so the URL is " \
                     "counted covered on the strength of Evidence nobody created",
        from: "        when FetchContent::CONTENT_ABSENT then record_absence(pg, organization_id, crawl, entry, result, now)",
        to: "        when FetchContent::CONTENT_ABSENT then NOTHING",
        expectation: "kill" },
      { id: "s10-observation-invalid", blocker: "S-07-010/:452", file: HANDOFF, proof: INGESTION_PROOF,
        description: ":452 requires a VALID observation for the outcome to be covered; an `invalid` " \
                     "one leaves the URL uncovered while the classification already said covered",
        from: "          validation_status: \"valid\", validation_reason_code: nil,\n          data_classification: CONTENT_CLASSIFICATION,",
        to: "          validation_status: \"quarantined\", validation_reason_code: \"unreviewed\",\n          data_classification: CONTENT_CLASSIFICATION,",
        expectation: "kill" },
      { id: "s10-outcome-document-unlinked", blocker: "S-07-010/:301", file: OUTCOME_STORE,
        proof: INGESTION_PROOF,
        description: "the terminal outcome stops naming the Document it was produced with, restoring " \
                     "the NULL S-07-009 could not fill",
        from: "                 $14::uuid,", to: "                 NULL::uuid,",
        expectation: "kill" },

      # ---- :462's identity, which is what makes an exact fetch replay return the same job --------
      { id: "s10-replay-forks-the-job", blocker: "S-07-010/:462", file: HANDOFF, proof: INGESTION_PROOF,
        description: "the fetch replay check is removed, so a redelivered pass stages the customer's " \
                     "page a second time and creates a second Document for one retained fetch",
        from: "        if existing\n          return Produced.new(document_id: existing[\"document_id\"], ingestion_job_id: existing[\"id\"],\n                              replayed: true)\n        end\n",
        to: "",
        expectation: "kill" },
      { id: "s10-version-not-allocated", blocker: "S-07-010/:302", file: DOCUMENT_STORE,
        proof: SCHEMA_PROOF,
        description: "every Document is version 1 with no predecessor, so a re-crawl collides on " \
                     "`(source_id, canonical_url_sha256, version)` instead of superseding",
        from: "                 COALESCE((SELECT p.version FROM prior p), 0) + 1,\n                 (SELECT p.id FROM prior p),",
        to: "                 1,\n                 NULL::uuid,",
        expectation: "kill" },

      # ---- :464's success, which is atomic or it is nothing --------------------------------------
      { id: "s10-staging-not-destroyed", blocker: "S-07-010/:464", file: EXECUTION, proof: INGESTION_PROOF,
        description: "':464 deletes the separate staging reference' is skipped, so the customer's " \
                     "page bytes stay recoverable for ever behind a live capability",
        from: "        destroy_staging(store, org, job, now)\n", to: "",
        expectation: "kill" },
      { id: "s10-document-not-advanced", blocker: "S-07-010/:464", file: EXECUTION, proof: INGESTION_PROOF,
        description: "a succeeded job leaves its Document `discovered`, so :472's parse manifest " \
                     "selects a Document that never became ingested",
        from: "        advance_document(pg, org, work.document, job, now)\n", to: "",
        expectation: "kill" },
      { id: "s10-document-advance-unguarded", blocker: "S-07-010/PRULE-009", file: DOCUMENT_STORE,
        proof: SCHEMA_PROOF,
        description: "PRULE-009's same-version guard removed from the Document advance, so the " \
                     "exactly-once rule rests on delivery deduplication rather than on the row",
        from: "             AND state_version = $3::bigint AND state = ",
        to: "             AND state = ",
        expectation: "kill" },

      # ---- :466's bounds. Each of these fails OPEN, which is why each has a row -------------------
      { id: "s10-staging-bound-unenforced", blocker: "S-07-010/:466", file: EXECUTION,
        proof: INGESTION_PROOF,
        description: "the 24-hour staging bound is not consulted, so a worker arriving after the " \
                     "window ingests bytes the contract says are gone",
        from: "        return nil if Platform::PgInstant.utc(job[\"staging_expires_at\"]) <= now.utc\n",
        to: "",
        expectation: "kill" },
      { id: "s10-digest-unverified", blocker: "S-07-010/:464", file: EXECUTION, proof: INGESTION_PROOF,
        description: "the staged bytes are not re-verified against the digest the fetch recorded, so " \
                     "Evidence can be produced from content the Crawl never retrieved",
        from: "        return Work.new(reason_code: IngestionContract::FETCHED_BODY_DIGEST_MISMATCH) unless\n          Digest::SHA256.digest(body) == unhex(job[\"fetched_body_sha256\"])\n",
        to: "",
        expectation: "kill" },
      { id: "s10-retry-unbounded", blocker: "S-07-010/:466", file: CONTRACT, proof: INGESTION_PROOF,
        description: "':466 one initial attempt plus TWO retries' loses its bound, so a dependency " \
                     "outage retries for ever instead of dead-lettering where an operator sees it",
        from: "        RETRYABLE_REASONS.include?(reason_code) && attempt_number.to_i < MAX_ATTEMPTS",
        to: "        RETRYABLE_REASONS.include?(reason_code)",
        expectation: "kill" },
      { id: "s10-nonretryable-retried", blocker: "S-07-010/:466", file: CONTRACT, proof: INGESTION_PROOF,
        description: "':466 ONLY ingest_timeout and ingest_dependency_unavailable retry' is widened, " \
                     "so a `staged_body_missing` job is retried against bytes that are gone",
        from: "      RETRYABLE_REASONS = [INGEST_TIMEOUT, INGEST_DEPENDENCY_UNAVAILABLE].freeze",
        to: "      RETRYABLE_REASONS = [INGEST_TIMEOUT, INGEST_DEPENDENCY_UNAVAILABLE, STAGED_BODY_MISSING].freeze",
        expectation: "kill" },
      { id: "s10-retry-instant-from-worker-clock", blocker: "S-07-010/:466", file: SCHEDULE,
        proof: INGESTION_PROOF,
        description: "the retry instant is taken from the worker's clock rather than the committed " \
                     "completion, so two deliveries compute two identities and the chain forks",
        from: "        Platform::PgInstant.utc(completed_at) + IngestionContract.retry_delay_s(attempt_number)",
        to: "        Time.now.utc + IngestionContract.retry_delay_s(attempt_number)",
        expectation: "kill" },
      { id: "s10-timeout-equality-lost", blocker: "S-07-010/:466", file: EXECUTION, proof: INGESTION_PROOF,
        description: "':466 equality belongs to timeout' weakened to a strict inequality, so a result " \
                     "produced exactly at the bound is accepted",
        from: "        !deadline.nil? && now.utc >= Platform::PgInstant.utc(deadline)",
        to: "        !deadline.nil? && now.utc > Platform::PgInstant.utc(deadline)",
        expectation: "kill" },
      { id: "s10-late-completion-accepted", blocker: "S-07-010/:466", file: EXECUTION,
        proof: INGESTION_PROOF,
        description: "':466 late completion is DISCARDED' removed, so a delivery whose attempt was " \
                     "reclaimed still writes Evidence and advances the Document",
        from: "        return discarded(claim) unless owns?(job, claim)\n", to: "",
        expectation: "kill" },
      { id: "s10-contended-claim-taken", blocker: "S-07-010/:466", file: EXECUTION, proof: INGESTION_PROOF,
        description: "a LIVE lease is treated as reclaimable, so two workers ingest one body " \
                     "concurrently and the second settles over the first",
        from: "        if attempt[\"outcome\"].nil? && lease_live?(attempt, now)",
        to: "        if false",
        expectation: "kill" },
      { id: "s10-contended-strands-the-job", blocker: "S-07-010/:466", file: FETCH_HANDLER_INGEST,
        proof: INGESTION_PROOF,
        description: "a contended delivery mints no successor, so a job whose incumbent then dies is " \
                     "left `running` behind a lapsing lease with nothing pending to notice — for ever, " \
                     "because :466's retry is only ever minted by a settle that never happens",
        from: "            link = reenter(raw, command, ctx, prepared, claim)\n", to: "            link = {}\n",
        expectation: "kill" },

      # ---- :378's ingestion link, which is the only thing that runs any of it --------------------
      { id: "s10-ingestion-action-not-created", blocker: "S-07-010/:378", file: FETCH_HANDLER,
        proof: INGESTION_PROOF,
        description: "':378 its terminal transaction creates the exact INGESTION action' is dropped, " \
                     "so every queued job waits for a dispatch that is never minted",
        from: "          link.merge(terminal_checkpoint(common, link)).merge(ingestion_link(common, pass))",
        to: "          link.merge(terminal_checkpoint(common, link))",
        expectation: "kill" },

      # ---- REVIEW ROUND 1. Every row below covers a control that existed with NO proof at all, or
      # that did not exist until the review found its absence. -------------------------------------
      { id: "s10-byte-count-unchecked", blocker: "S-07-010/R1-2/:464", file: EXECUTION,
        proof: INGESTION_PROOF,
        description: ":464's `received_byte_count_mismatch` is not checked, so Evidence can be made " \
                     "from staged bytes that are not the size the fetch recorded",
        from: "        return Work.new(reason_code: IngestionContract::RECEIVED_BYTE_COUNT_MISMATCH) unless\n          body.bytesize == job[\"received_byte_count\"].to_i\n",
        to: "", expectation: "kill" },
      { id: "s10-media-type-unchecked", blocker: "S-07-010/R1-2/:464", file: EXECUTION,
        proof: INGESTION_PROOF,
        description: ":464's `media_type_unsupported` is not checked, so a capture outside :436's two " \
                     "media types becomes a `source_document` and enters :472's parse manifest",
        from: "        return Work.new(reason_code: IngestionContract::MEDIA_TYPE_UNSUPPORTED) unless\n          IngestionContract.supported_media_type?(job[\"media_type\"])\n",
        to: "", expectation: "kill" },
      { id: "s10-scope-recheck-dropped", blocker: "S-07-010/R1-2/:464", file: EXECUTION,
        proof: INGESTION_PROOF,
        description: ":464's `source_scope_mismatch` is not checked, so a URL the Source's CURRENT " \
                     "scope no longer admits is still turned into Evidence after the run",
        from: "        return Work.new(reason_code: IngestionContract::SOURCE_SCOPE_MISMATCH) unless in_scope?(pg, job)\n",
        to: "", expectation: "kill" },
      { id: "s10-capture-policy-unchecked", blocker: "S-07-010/R1-2/:464", file: EXECUTION,
        proof: INGESTION_PROOF,
        description: ":464's `ingestion_policy_unavailable` is not checked, so a body captured under a " \
                     "policy this ingester does not implement is ingested as though it had been",
        from: "        return Work.new(reason_code: IngestionContract::INGESTION_POLICY_UNAVAILABLE) unless\n          IngestionHandoff::CAPTURE_POLICY_VERSION == job[\"response_capture_policy_version\"]\n",
        to: "", expectation: "kill" },
      { id: "s10-refusal-order-inverted", blocker: "S-07-010/R1-2/:464", file: EXECUTION,
        proof: INGESTION_PROOF,
        description: ":464's FIRST-MATCH order inverted, so a job failing several checks reports a " \
                     "later reason than the contract fixes — the exact defect class ADR-072 recorded " \
                     "as confirmed-blocking at S-03 for MTX-027",
        from: "        return Work.new(reason_code: IngestionContract::RECEIVED_BYTE_COUNT_MISMATCH) unless\n          body.bytesize == job[\"received_byte_count\"].to_i\n        return Work.new(reason_code: IngestionContract::FETCHED_BODY_DIGEST_MISMATCH) unless\n          Digest::SHA256.digest(body) == unhex(job[\"fetched_body_sha256\"])\n        return Work.new(reason_code: IngestionContract::MEDIA_TYPE_UNSUPPORTED) unless\n          IngestionContract.supported_media_type?(job[\"media_type\"])\n",
        to: "        return Work.new(reason_code: IngestionContract::MEDIA_TYPE_UNSUPPORTED) unless\n          IngestionContract.supported_media_type?(job[\"media_type\"])\n        return Work.new(reason_code: IngestionContract::RECEIVED_BYTE_COUNT_MISMATCH) unless\n          body.bytesize == job[\"received_byte_count\"].to_i\n        return Work.new(reason_code: IngestionContract::FETCHED_BODY_DIGEST_MISMATCH) unless\n          Digest::SHA256.digest(body) == unhex(job[\"fetched_body_sha256\"])\n",
        expectation: "kill" }
    ].map { |e| e.transform_keys(&:to_s) }.freeze

    # TRIGGER MUTATIONS. These act on a PostgreSQL trigger definition rather than on a file, and the
    # harness replays them with the same sealing and verification.
    #
    # EACH MUTANT IS A `CREATE TRIGGER`, NEVER A `CREATE OR REPLACE FUNCTION`. `replay_trigger`
    # restores by re-creating the TRIGGER from what the catalogue reported before the change, so a
    # mutant that altered the FUNCTION instead would survive the restoration and leave the database
    # permanently weakened while the row recorded `"restored": true`. The mutants below disarm the
    # guard by giving it a WHEN clause that can never hold — `id` is the primary key and is NOT NULL —
    # which is exactly as disabling as replacing the body and is fully undone by the restore.
    TRIGGER_MUTATIONS = [
      {
        id: "s10-job-guard-disarmed", blocker: "S-07-010/:303", mechanism: "trigger",
        table: "ingestion_jobs", trigger: "ingestion_jobs_lifecycle_guard", proof: SCHEMA_PROOF,
        description: "the Ingestion Job lifecycle guard never fires, so every illegal edge, a moved " \
                     "replay generation, a re-pointed Evidence link and a mutated capture are all admitted",
        mutant_ddl: "CREATE TRIGGER ingestion_jobs_lifecycle_guard BEFORE UPDATE ON public.ingestion_jobs " \
                    "FOR EACH ROW WHEN (new.id IS NULL) EXECUTE FUNCTION f1_ingestion_jobs_lifecycle_guard()",
        expectation: "kill"
      },
      {
        id: "s10-document-guard-disarmed", blocker: "S-07-010/:302", mechanism: "trigger",
        table: "documents", trigger: "documents_lifecycle_guard", proof: SCHEMA_PROOF,
        description: "the Document lifecycle guard never fires, so `discovered -> indexed` and the " \
                     "self-edge are admitted and OD-015's closed edge set becomes a convention",
        mutant_ddl: "CREATE TRIGGER documents_lifecycle_guard BEFORE UPDATE ON public.documents " \
                    "FOR EACH ROW WHEN (new.id IS NULL) EXECUTE FUNCTION f1_documents_lifecycle_guard()",
        expectation: "kill"
      },
      {
        id: "s10-evidence-containment-disarmed", blocker: "S-07-010/R1-1/:128", mechanism: "trigger",
        table: "ingestion_jobs", trigger: "ingestion_jobs_evidence_containment", proof: SCHEMA_PROOF,
        description: "the durable handoff may name Evidence from ANOTHER Project of the same " \
                     "Organization — FU-7's defect class, fourth occurrence, measured live before it " \
                     "was repaired",
        mutant_ddl: "CREATE TRIGGER ingestion_jobs_evidence_containment BEFORE INSERT OR UPDATE OF " \
                    "evidence_id ON public.ingestion_jobs FOR EACH ROW WHEN (new.id IS NULL) " \
                    "EXECUTE FUNCTION f1_ingestion_job_evidence_contained()",
        expectation: "kill"
      },
      {
        id: "s10-document-closure-removed", blocker: "S-07-010/owner-ruling-2", mechanism: "trigger",
        table: "documents", trigger: "documents_terminal_closure", proof: SCHEMA_PROOF,
        description: "a Document may be created against an ALREADY-TERMINAL Crawl, which changes that " \
                     "run's coverage after the run was decided and cannot be corrected",
        mutant_ddl: "CREATE TRIGGER documents_terminal_closure AFTER INSERT ON public.documents " \
                    "FOR EACH ROW WHEN (new.id IS NULL) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        expectation: "kill"
      }
    ].map { |e| e.transform_keys(&:to_s) }.freeze
  end
end
