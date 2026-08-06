# frozen_string_literal: true

require "base64"
require "digest"
require "securerandom"

module Workflows
  module Wf005
    # ONE INGESTION ATTEMPT (S-07-010; WORKFLOW_SPECIFICATIONS.md :462, :464, :466).
    #
    # THREE PHASES, and the split is forced by what each one may hold.
    #
    #   1. CLAIM, in its own transaction. `queued -> running` under a compare-and-set on
    #      `state_version`, plus one `ingestion_attempts` row under `UNIQUE (job, attempt_number)`.
    #      Committing the claim FIRST is what makes a lost worker visible: the attempt row and its
    #      lease exist, so the next delivery can tell "someone is working on this" from "someone
    #      died", which a claim made inside the settle could not.
    #   2. THE WORK, holding NO LOCK. :464's eight first-match pre-persistence checks, over bytes this
    #      phase decrypts. It opens a transaction — every table it reads is RLS-forced and the proved
    #      Organization context lives on the connection — but it takes no row lock and no advisory
    #      lock, which is the half that matters: a 10 MiB AES-GCM decrypt is short and not free, and
    #      it has no business happening while `FOR UPDATE` is held on the job.
    #   3. THE SETTLE, on the CALLER'S transaction — the handler's terminal one. There is no external
    #      call anywhere in this workflow, so the Evidence, the Document advance, the job transition,
    #      the attempt terminalization, the staging destruction, the events and the ledger are ONE
    #      commit. That is stronger than the fetch path can be, and it is stronger deliberately:
    #      MTX-008 says "the durable handoff COMMITS WITH THE INGESTION JOB SUCCESS, so a parsing
    #      consumer can never observe a succeeded job without its Evidence."
    #
    # A LATE COMPLETION IS DISCARDED, WHICH IS A RULE AND NOT AN ACCIDENT. ":466 — Each attempt has a
    # 30-second timeout; EQUALITY BELONGS TO TIMEOUT AND LATE COMPLETION IS DISCARDED." So the settle
    # re-locks the job and re-reads the attempt before it writes anything, and a delivery whose
    # attempt was reclaimed while it worked writes NOTHING — no Evidence, no Document advance, no
    # state change. Checking afterwards would have meant producing the Evidence first and rolling it
    # back, which works only for as long as nothing else in the transaction has already been observed.
    class IngestionExecution
      # F-03 provenance for the `source_document` Evidence :464 requires.
      EVIDENCE_AAD = { application: "wf005", record_type: "ingestion_job",
                       purpose: "product_evidence_payload" }.freeze
      EVIDENCE_PRODUCER = "wf005.ingestion"
      EVIDENCE_SCHEMA = "source-document-v1"
      EVIDENCE_SOURCE_SYSTEM = IngestionHandoff::EVIDENCE_SOURCE_SYSTEM
      COLLECTION_METHOD = "crawl_content_ingestion"
      COLLECTOR_VERSION = IngestionContract::SCHEMA_VERSION

      # The claim's verdict. `kind` is what this delivery may do next, and nothing else in this class
      # decides it: `:claimed` performs an attempt, `:reclaimed` settles a dead one, and the other
      # three write nothing at all.
      #
      # `reenter_at` IS ONLY EVER SET ON `:contended`, AND IT IS NOT COSMETIC. A contended delivery
      # settles its own action, so without a successor the job would be stranded the moment the
      # incumbent died: `running`, holding a lease that will expire, with no pending action left to
      # notice. See `contended_at` for why the instant is read from the incumbent's own row.
      Claim = Data.define(:kind, :job, :attempt, :attempt_number, :reason_code, :reenter_at) do
        def initialize(job: nil, attempt: nil, attempt_number: nil, reason_code: nil,
                       reenter_at: nil, **) = super
        def performable? = kind == :claimed
        def settleable? = %i[claimed reclaimed].include?(kind)
        def reenters? = kind == :contended
      end

      # What the work phase decided. `reason_code` nil means every :464 check passed and `body` holds
      # the exact staged bytes.
      Work = Data.define(:reason_code, :body, :document, :evaluation_id) do
        def initialize(reason_code: nil, body: nil, document: nil, evaluation_id: nil) = super
        def ok? = reason_code.nil?
      end

      # What the settle committed. `state` is the job's resulting state, or `:discarded` for a late
      # completion that wrote nothing.
      # `entry_version` is the job's `state_version` AT THE MOMENT THE SETTLE TOOK ITS LOCK — the
      # version the `queued -> running` claim committed. Every event this settle causes derives its
      # aggregate version by counting FORWARD from it, so no reader has to reverse-engineer which of
      # two or three edges a version belongs to.
      Settlement = Data.define(:state, :reason_code, :evidence_id, :evidence_content_sha256,
                               :document_id, :attempt_number, :completed_at, :retry_at, :entry_version,
                               :job) do
        def initialize(reason_code: nil, evidence_id: nil, evidence_content_sha256: nil,
                       document_id: nil, retry_at: nil, entry_version: 0, **) = super
        def succeeded? = state == IdentityAccess::Infrastructure::IngestionJobStore::SUCCEEDED
        def dead_lettered? = state == IdentityAccess::Infrastructure::IngestionJobStore::DEAD_LETTER
        def retried? = !retry_at.nil?
        def discarded? = state == :discarded
      end

      CONTENDED = "ingestion_attempt_contended"
      NOT_RUNNABLE = "ingestion_job_not_runnable"
      MISSING = "scheduled_action_target_mismatch"
      DISCARDED = "ingestion_late_completion_discarded"

      def initialize(ids: Platform::Ids.system, correlation_id: nil, command_id: nil)
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @command_id = command_id
      end

      # ---- phase 1: the claim ----------------------------------------------------

      def claim(organization_id:, job_id:, now:)
        Platform::UnitOfWork.run do |conn|
          store = job_store(conn.raw_connection, organization_id)
          job = store.lock_job(organization_id, job_id)
          next Claim.new(kind: :missing, reason_code: MISSING) if job.nil?

          case job["state"]
          when IdentityAccess::Infrastructure::IngestionJobStore::QUEUED
            start_attempt(store, organization_id, job, now)
          when IdentityAccess::Infrastructure::IngestionJobStore::RUNNING
            reclaim_or_defer(store, organization_id, job, now)
          else
            # `succeeded`, `failed` and `dead_letter` are settled states. A `failed` job is between
            # its own two edges only inside one transaction (:466 — "at ONE checkpoint"), so a
            # delivery that finds one has arrived at a job nothing is going to run.
            Claim.new(kind: :not_runnable, job:, reason_code: NOT_RUNNABLE)
          end
        end
      end

      # ":466 — one initial attempt plus two retries." The number comes from COMMITTED state, so
      # neither a process loss nor a redelivery can reset it, and the exhausted case is a settled
      # `dead_letter` rather than a fourth attempt.
      def start_attempt(store, organization_id, job, now)
        number = store.attempt_count(organization_id, job["id"]) + 1
        return Claim.new(kind: :not_runnable, job:, reason_code: NOT_RUNNABLE) if number > IngestionContract::MAX_ATTEMPTS

        moved = store.start(organization_id, job["id"], job["state_version"].to_i, number, now)
        if moved.to_i.zero?
          return contended(store, organization_id, job, now)
        end

        attempt = store.claim_attempt(
          id: @ids.generate, now:, correlation_id: @correlation_id, causation_id: job["crawl_id"],
          command_id: @command_id, organization_id:, project_id: job["project_id"],
          ingestion_job_id: job["id"], attempt_number: number,
          replay_generation: job["replay_generation"].to_i,
          # :304's "immutable ... input identity": the digest of the exact bytes this attempt is
          # ingesting, which is what makes an attempt record verifiable against its own input.
          input_sha256: unhex(job["fetched_body_sha256"]), claim_owner: @ids.generate,
          # ":466 — Each attempt has a 30-second timeout."
          deadline_at: now + IngestionContract::ATTEMPT_TIMEOUT_S
        )
        # Two deliveries that computed the same number: `ON CONFLICT` gives exactly one an attempt.
        # The loser has already lost the `start` compare-and-set above in every reachable ordering,
        # so this is the backstop rather than the mechanism — and it fails closed either way.
        return contended(store, organization_id, job, now) if attempt.nil?

        Claim.new(kind: :claimed, job: store.get(organization_id, job["id"]), attempt:,
                  attempt_number: number)
      end

      # A `running` job belongs either to a LIVE worker or to a DEAD one, and the lease is what tells
      # them apart. This is the same construction `FetchContent#reclaim_expired` uses and it is chosen
      # for the same reason: reclamation that happens on the next claim cannot itself be lost, and
      # needs no scheduled sweep to exist first.
      #
      # THE STALE ATTEMPT IS TERMINALIZED HERE, IN THE CLAIM'S OWN TRANSACTION, and the job is left
      # `running` for the settle to fail. ":466 — equality belongs to timeout": a lease that expired
      # is an attempt that ran past its bound, which is `ingest_timeout` exactly.
      def reclaim_or_defer(store, organization_id, job, now)
        attempt = store.latest_attempt(organization_id, job["id"])
        # A `running` job with no attempt row at all cannot happen — `start_attempt` writes both in
        # one transaction — so it is corruption rather than a race, and guessing at it would run an
        # ingestion nobody claimed.
        raise Platform::InvariantViolation, "running ingestion job has no attempt" if attempt.nil?
        if attempt["outcome"].nil? && lease_live?(attempt, now)
          return contended(store, organization_id, job, now, attempt:)
        end

        if attempt["outcome"].nil?
          store.terminalize_attempt(attempt["id"], attempt["checkpoint_version"].to_i, now,
                                    outcome: "failed", reason_code: IngestionContract::INGEST_TIMEOUT)
        end
        Claim.new(kind: :reclaimed, job:, attempt: store.latest_attempt(organization_id, job["id"]),
                  attempt_number: attempt["attempt_number"].to_i,
                  reason_code: attempt["reason_code"] || IngestionContract::INGEST_TIMEOUT)
      end

      # A CONTENDED DELIVERY MINTS ITS OWN SUCCESSOR, AND THAT IS THE WHOLE OF IT.
      #
      # `Worker#run_handler` SETTLES any result that is not a confirmed lease loss, so a contended
      # delivery ends its action. If the incumbent then dies, the job is left `running` behind an
      # attempt lease that will lapse with NOTHING pending to notice — permanently, because
      # `running_work_sweep_due` has no registered handler and :466's retry is only ever minted by a
      # settle that never happens. Found by this tranche's own review rather than in production.
      #
      # THE INSTANT IS THE INCUMBENT'S OWN LEASE BOUNDARY, read from the committed attempt row, so two
      # contended deliveries compute the SAME `due_at` and therefore the same action identity — the
      # second replays the first's successor instead of forking a second chain. When there is no
      # attempt to read (the loser of a `queued -> running` compare-and-set arrives before the winner's
      # attempt row is visible) the lease length is the honest bound: it is the longest the winner can
      # legitimately hold the claim.
      #
      # IT CANNOT SPIN. Each successor is at or after the incumbent's lease boundary, and by then the
      # job is either settled — `ingestion_job_not_runnable`, which mints nothing — or reclaimable.
      def contended(store, organization_id, job, now, attempt: nil)
        attempt ||= store.latest_attempt(organization_id, job["id"])
        expires = attempt && attempt["outcome"].nil? && attempt["lease_expires_at"]
        at = expires ? Platform::PgInstant.utc(expires) : now.utc + IdentityAccess::Infrastructure::IngestionJobStore::ATTEMPT_LEASE_SECONDS
        Claim.new(kind: :contended, job:, attempt:, reason_code: CONTENDED, reenter_at: at)
      end

      def lease_live?(attempt, now)
        expires = attempt["lease_expires_at"]
        !expires.nil? && Platform::PgInstant.utc(expires) > now.utc
      end

      # ---- phase 2: the work -----------------------------------------------------

      # :464'S EIGHT FIRST-MATCH PRE-PERSISTENCE CHECKS, IN THE ORDER :464 STATES THEM. The order is
      # the contract, not a preference: a capture that is both the wrong size and the wrong media type
      # is a `received_byte_count_mismatch`, and a reader can tell from the reason which check fired.
      def perform(claim:, now:)
        job = claim.job
        Platform::UnitOfWork.run do |conn|
          pg = conn.raw_connection
          job_store(pg, job["organization_id"])
          checks(pg, job, now)
        end
      rescue Platform::Encryption::Error
        # A crypto failure reaching the staged bytes is a DEPENDENCY failure, not a missing body: the
        # ciphertext is there and cannot be opened. :466 makes this one of the two retryable reasons,
        # which is right — a retired wrapping key or an unavailable provider can be restored.
        Work.new(reason_code: IngestionContract::INGEST_DEPENDENCY_UNAVAILABLE)
      end

      def checks(pg, job, now)
        document = IdentityAccess::Infrastructure::DocumentStore.new(pg)
                                                                .get(job["organization_id"], job["document_id"])
        return Work.new(reason_code: IngestionContract::TENANT_MISMATCH) unless same_tenant?(job, document)
        return Work.new(reason_code: IngestionContract::SOURCE_SCOPE_MISMATCH) unless in_scope?(pg, job)

        body = staged_body(job, now)
        return Work.new(reason_code: IngestionContract::STAGED_BODY_MISSING) if body.nil?
        return Work.new(reason_code: IngestionContract::RECEIVED_BYTE_COUNT_MISMATCH) unless
          body.bytesize == job["received_byte_count"].to_i
        return Work.new(reason_code: IngestionContract::FETCHED_BODY_DIGEST_MISMATCH) unless
          Digest::SHA256.digest(body) == unhex(job["fetched_body_sha256"])
        return Work.new(reason_code: IngestionContract::MEDIA_TYPE_UNSUPPORTED) unless
          IngestionContract.supported_media_type?(job["media_type"])

        # :464's SEVENTH CHECK, `malware_or_active_content_detected`, IS NOT PERFORMED, and saying so
        # here is the honest form of that. It requires a scanning provider: this build has none, no
        # ratified detection contract exists, and adding an external provider is an owner decision
        # under the autonomy policy rather than an implementer's. Recorded as FU-66 with the exact
        # obligation, so the gap is visible in the follow-up ledger rather than only in this comment.
        # Nothing is silently passed — the check does not run, and the record says it does not.

        return Work.new(reason_code: IngestionContract::INGESTION_POLICY_UNAVAILABLE) unless
          IngestionHandoff::CAPTURE_POLICY_VERSION == job["response_capture_policy_version"]

        Work.new(body:, document:, evaluation_id: evaluation_for(pg, job))
      end

      # ":464 — `tenant_mismatch`." RLS and the composite foreign keys already make a cross-Organization
      # or cross-Project pairing unwritable, so this can only fire on corruption — which is exactly
      # when a check that reads the two rows and compares them is worth having, because the FK proves
      # the link existed at INSERT and this proves it still holds at the moment Evidence is produced.
      def same_tenant?(job, document)
        return false if document.nil?

        %w[organization_id project_id source_id crawl_id].all? { |c| document[c] == job[c] } &&
          document["canonical_url"] == job["canonical_url"]
      end

      def in_scope?(pg, job)
        store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
        FetchAuthorization.new(store).in_current_scope?(
          organization_id: job["organization_id"], project_id: job["project_id"],
          source_id: job["source_id"], canonical_url: job["canonical_url"]
        )
      end

      # ":462 — Staged body bytes are immutable and inaccessible to product reads"; ":466 — a replay
      # after destruction is `staged_body_missing`". THREE WAYS THE BYTES ARE GONE, and all three are
      # the same answer: the reference was destroyed, the 24-hour bound has passed, or the record no
      # longer resolves. The expiry is checked BEFORE the read, so a job whose window closed cannot be
      # ingested by a worker that happens to arrive before the destruction executor does.
      def staged_body(job, now)
        return nil if job["staged_body_reference"].nil?
        return nil if Platform::PgInstant.utc(job["staging_expires_at"]) <= now.utc

        aad = Platform::Encryption::Aad.for(**IngestionHandoff::STAGING_AAD, record_id: job["id"],
                                            tenant: job["organization_id"])
        Platform::Encryption.reveal(job["staged_body_reference"], aad:)
      end

      # ---- phase 3: the settle ---------------------------------------------------

      # Runs on the CALLER'S transaction. Returns the Settlement the handler records; it writes no
      # ledger row itself, exactly as `CrawlDriver` writes none.
      def settle(pg:, claim:, work:, now:)
        store = job_store(pg, claim.job["organization_id"])
        job = store.lock_job(claim.job["organization_id"], claim.job["id"])
        return discarded(claim) unless owns?(job, claim)

        reason = terminal_reason(claim, work, now)
        return succeed(pg, store, job, claim, work, now) if reason.nil?

        fail_attempt(store, job, claim, reason, now)
      rescue Platform::Evidence::InvalidEvidence
        # ":464 — Execution failures are ... `ingested_evidence_invalid`." An envelope F-03 REFUSES is
        # exactly that, and it is deliberately NOT one of :466's two retryable reasons: the same bytes
        # would build the same invalid envelope, so a retry could only fail identically. Letting it
        # escape instead would have the worker classify a governed domain outcome as a defect.
        #
        # NOTHING PARTIAL SURVIVES THE RAISE. `Record.build` validates before anything is appended, so
        # the refusal happens before the Evidence row, before the job transition and before the
        # Document advance; the settle then takes the failure path on the same transaction.
        fail_attempt(store, store.lock_job(claim.job["organization_id"], claim.job["id"]), claim,
                     IngestionContract::INGESTED_EVIDENCE_INVALID, now)
      end

      # ":466 — LATE COMPLETION IS DISCARDED." This delivery no longer owns the attempt it started:
      # another delivery reclaimed the expired lease and settled it. Nothing is written — not the
      # Evidence, not the Document advance, not a second opinion about the outcome.
      def discarded(claim)
        Settlement.new(state: :discarded, reason_code: DISCARDED, document_id: claim.job["document_id"],
                       attempt_number: claim.attempt_number, completed_at: nil,
                       entry_version: claim.job["state_version"].to_i, job: claim.job)
      end

      def owns?(job, claim)
        return false if job.nil? || job["state"] != IdentityAccess::Infrastructure::IngestionJobStore::RUNNING
        return false unless job["state_version"].to_i == claim.job["state_version"].to_i

        claim.attempt && job["attempt_count"].to_i == claim.attempt_number.to_i
      end

      # The reason this attempt failed, or nil when it succeeded. A reclaimed attempt carries its own;
      # a performed one carries the work's, and then :466's timeout is applied last because an attempt
      # that produced a valid result AFTER its deadline is still late.
      def terminal_reason(claim, work, now)
        return claim.reason_code if claim.kind == :reclaimed
        return work.reason_code unless work.ok?
        return IngestionContract::INGEST_TIMEOUT if expired?(claim.attempt, now)

        nil
      end

      # ":466 — equality belongs to timeout."
      def expired?(attempt, now)
        deadline = attempt && attempt["deadline_at"]
        !deadline.nil? && now.utc >= Platform::PgInstant.utc(deadline)
      end

      # ":464 — Success ATOMICALLY creates one immutable `source_document` Evidence ..., changes
      # Document discovered to ingested, changes the job to succeeded, deletes the separate staging
      # reference within 60 seconds."
      #
      # THE ORDER IS THE SAFETY. The job's compare-and-set decides the winner, so it comes before the
      # Document advance — advancing first and then losing the transition would leave a Document
      # `ingested` with no succeeded job to justify it. The Evidence is produced before both because
      # `ingestion_jobs_succeeded_carries_evidence` refuses the row without it; a lost race after that
      # rolls the whole transaction back, so no orphan Evidence survives.
      def succeed(pg, store, job, claim, work, now)
        evidence = produce_evidence(job, claim, work, now)
        org = job["organization_id"]
        if store.succeed(org, job["id"], job["state_version"].to_i, evidence.id, now).to_i.zero?
          return discarded(claim)
        end

        advance_document(pg, org, work.document, job, now)
        store.terminalize_attempt(claim.attempt["id"], claim.attempt["checkpoint_version"].to_i, now,
                                  outcome: "succeeded", output_object_id: evidence.id,
                                  output_sha256: evidence.content_sha256)
        destroy_staging(store, org, job, now)

        Settlement.new(state: IdentityAccess::Infrastructure::IngestionJobStore::SUCCEEDED,
                       evidence_id: evidence.id,
                       evidence_content_sha256: evidence.content_sha256.unpack1("H*"),
                       document_id: job["document_id"], attempt_number: claim.attempt_number,
                       completed_at: now, entry_version: job["state_version"].to_i,
                       job: store.get(org, job["id"]))
      end

      # PRULE-009 / MTX-008 — "each successful SAME-VERSION job advances the Document EXACTLY ONCE,
      # guarded on the Document by its version rather than by delivery deduplication". The guard is
      # the compare-and-set; a Document that did not move is corruption, because exactly one job ever
      # references a given Document and only one delivery can have reached here.
      def advance_document(pg, organization_id, document, job, now)
        documents = IdentityAccess::Infrastructure::DocumentStore.new(pg)
        current = documents.get(organization_id, job["document_id"])
        moved = documents.mark_ingested(organization_id, job["document_id"],
                                        current["state_version"].to_i, now)
        return if moved.to_i.positive?

        raise Platform::InvariantViolation,
              "succeeded ingestion job did not advance its Document (#{document && document['id']})"
      end

      # ":464 — deletes the SEPARATE staging reference within 60 seconds." In the same commit, which
      # is the strongest reading of "within": the bytes are cryptographically erased and the row
      # records that they were, and the Evidence payload — a different protected record — is what
      # survives. `erase` is idempotent, so a redelivery that somehow reached here destroys nothing
      # twice.
      def destroy_staging(store, organization_id, job, now)
        reference = job["staged_body_reference"]
        return if reference.nil?

        store.destroy_staging(organization_id, job["id"], now)
        Platform::Encryption.erase(reference)
      end

      # ":466 — Other failures and exhausted retry move `running -> failed -> dead_letter` AT ONE
      # CHECKPOINT." Both edges in one transaction, which is what "one checkpoint" means: a job cannot
      # be observed `failed` and un-dead-lettered when no retry is owed.
      def fail_attempt(store, job, claim, reason, now)
        org = job["organization_id"]
        if claim.kind == :claimed
          store.terminalize_attempt(claim.attempt["id"], claim.attempt["checkpoint_version"].to_i, now,
                                    outcome: "failed", reason_code: reason)
        end
        return discarded(claim) if store.fail(org, job["id"], job["state_version"].to_i, reason, now).to_i.zero?

        failed = store.get(org, job["id"])
        if IngestionContract.retry_owed?(reason, claim.attempt_number)
          # The instant is derived from the COMMITTED completion, never from this worker's clock, so
          # two deliveries compute the same `due_at` and therefore the same action identity.
          retry_at = IngestionAttemptDueSchedule.retry_at(failed["completed_at"], claim.attempt_number)
          store.requeue(org, job["id"], failed["state_version"].to_i, retry_at, now)
          return Settlement.new(state: IdentityAccess::Infrastructure::IngestionJobStore::QUEUED,
                                reason_code: reason, document_id: job["document_id"],
                                attempt_number: claim.attempt_number, completed_at: failed["completed_at"],
                                retry_at:, entry_version: job["state_version"].to_i,
                                job: store.get(org, job["id"]))
        end

        store.dead_letter(org, job["id"], failed["state_version"].to_i, now)
        Settlement.new(state: IdentityAccess::Infrastructure::IngestionJobStore::DEAD_LETTER,
                       reason_code: reason, document_id: job["document_id"],
                       attempt_number: claim.attempt_number, completed_at: failed["completed_at"],
                       entry_version: job["state_version"].to_i, job: store.get(org, job["id"]))
      end

      # ---- the Evidence ----------------------------------------------------------

      Produced = Data.define(:id, :content_sha256)

      # ":464 — one immutable `source_document` Evidence containing THE EXACT STAGED BYTES/REFERENCE
      # AND CRAWL/FETCH PROVENANCE."
      #
      # THE PAYLOAD CARRIES THE BYTES, and it has to. The Evidence's own reference cannot point at the
      # STAGING record, because the same sentence destroys that record moments later and
      # SCORE_EVIDENCE_MODEL.md makes "missing referenced bytes" a data-integrity error for every
      # downstream write. So this protects a second, retained record — canonical JSON carrying the
      # provenance plus the body — and the staging record is what gets erased. That is precisely why
      # :464 calls the destroyed one "the SEPARATE staging reference".
      #
      # IDEMPOTENT ON `(organization_id, producer_id, attempt_id)`, with the JOB as the attempt
      # identity: :462 keys the job on the fetched body, so one job is one body is one Evidence, and a
      # redelivery returns the existing evidence_id rather than appending a second record for the
      # same bytes.
      def produce_evidence(job, claim, work, now)
        payload = Platform::CanonicalJson.encode(evidence_payload(job, claim, work, now)).b
        aad = Platform::Encryption::Aad.for(**EVIDENCE_AAD, record_id: job["id"],
                                            tenant: job["organization_id"])
        protected_payload = Platform::Encryption.protect(plaintext: payload, aad:)

        record = Platform::Evidence::Record.build(
          schema_version: EVIDENCE_SCHEMA, organization_id: job["organization_id"],
          project_id: job["project_id"], source_id: job["source_id"],
          evaluation_id: work.evaluation_id, evidence_type: "source_document",
          producer_id: EVIDENCE_PRODUCER, attempt_id: job["id"],
          payload_reference: protected_payload.reference,
          content_sha256: protected_payload.content_digest.unpack1("H*"),
          captured_at_utc: Platform::PgInstant.utc(job["queued_at"]), observed_at_utc: now,
          source_system: EVIDENCE_SOURCE_SYSTEM, collection_method: COLLECTION_METHOD,
          collector_version: COLLECTOR_VERSION, validation_status: "valid", validation_reason_code: nil,
          data_classification: job["data_classification"],
          payload_retention_class: Platform::Evidence::Record::PRODUCER_RETENTION_CLASS,
          correlation_id: @correlation_id
        )
        Produced.new(id: Platform::Evidence.produce(record), content_sha256: protected_payload.content_digest)
      end

      def evidence_payload(job, claim, work, now)
        {
          "schema_version" => EVIDENCE_SCHEMA,
          "ingestion_job_id" => job["id"], "document_id" => job["document_id"],
          "crawl_id" => job["crawl_id"], "source_id" => job["source_id"],
          "canonical_url" => job["canonical_url"],
          "final_http_status" => job["final_http_status"].to_i,
          "media_type" => job["media_type"],
          "received_byte_count" => job["received_byte_count"].to_i,
          "fetched_body_sha256" => hex(job["fetched_body_sha256"]),
          "response_capture_policy_version" => job["response_capture_policy_version"],
          "ingestion_schema_version" => job["ingestion_schema_version"],
          "attempt_number" => claim.attempt_number.to_i,
          "replay_generation" => job["replay_generation"].to_i,
          "observed_at_utc" => now.getutc.iso8601(6),
          # Base64 because canonical JSON carries text and a response body is bytes. The digest above
          # is over THIS payload; the body's own digest is the field two lines up, so a reader can
          # verify the decoded bytes against the fetch without trusting either alone.
          "body_base64" => Base64.strict_encode64(work.body.to_s)
        }
      end

      # SCORE_EVIDENCE_MODEL.md makes `evaluation_id` "nullable ONLY for Verification Evidence
      # captured before an Evaluation exists", so crawl-produced Evidence carries the Evaluation its
      # Crawl belongs to: a root Crawl's own pending initial Evaluation (created atomically at the
      # accepted start, OD-018) or the parent Evaluation a reassessment child names. Resolved in the
      # WORK phase and carried, so the settle opens no extra read inside its own transaction.
      def evaluation_for(pg, job)
        row = pg.exec_params(<<~SQL, [job["organization_id"], job["crawl_id"]]).to_a.first
          SELECT e.id FROM evaluations e
          WHERE e.organization_id = $1::uuid AND e.crawl_id = $2::uuid AND e.kind = 'initial'
        SQL
        return row["id"] if row

        crawl = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
                                                                  .crawl(job["organization_id"], job["crawl_id"])
        crawl && crawl["parent_evaluation_id"]
      end

      def job_store(pg, organization_id)
        store = IdentityAccess::Infrastructure::IngestionJobStore.new(pg)
        store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
        store
      end

      def hex(value) = value.to_s.sub(/\A\\x/, "")
      def unhex(value) = [hex(value)].pack("H*")
    end
  end
end
