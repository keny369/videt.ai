# frozen_string_literal: true

require "digest"
require "securerandom"

module Workflows
  module Wf005
    # WHAT A RETIRED FRONTIER ENTRY PRODUCES (S-07-010; WORKFLOW_SPECIFICATIONS.md :452, :462, :464).
    #
    # :452 gives an admitted content URL exactly two covered outcomes, and each has an ARTIFACT that
    # has to exist for the outcome to be true:
    #
    #   * `document_created` — "creates a VALID DOCUMENT". This stages the body, creates the
    #     discovered Document and the queued IngestionJob, and returns the Document's ID so
    #     `crawl_terminal_outcomes.document_id` stops being NULL. S-07-009 recorded that column as
    #     CANDIDATE coverage with its own comment saying so; this is the artifact it was waiting for.
    #   * `content_absent` — "returns terminal 404/410 and creates a valid BODY-FREE
    #     `crawl_observation` with reason `content_absent`". No Document, no IngestionJob, no body.
    #
    # EVERYTHING HERE RUNS ON THE CALLER'S TRANSACTION, which is `CrawlDriver#retire`'s — the one that
    # releases :454's depth seal and writes the terminal outcome, under the per-Crawl frontier
    # advisory lock. That is not a convenience. A Document that committed while the retirement rolled
    # back would be a coverage-bearing artifact for an entry nothing had classified; a retirement that
    # committed while the Document rolled back would be `document_created / covered` naming a Document
    # that does not exist. :452 makes the outcome and the artifact one fact, so they are one commit.
    #
    # AND THE CRAWL IS STILL RUNNING WHEN THEY COMMIT. `documents` and `ingestion_jobs` are both
    # closed on INSERT by `f1_crawl_child_fact_closed`, and `retire` re-reads the Crawl under the same
    # lock before it calls here, so the closure is a backstop behind a decision rather than the only
    # thing standing between a late pass and a run whose coverage was already reported.
    #
    # D3, DECIDED THE WAY ADR-067 RECORDED IT AS AN INTERIM. ADR-067 left open whether the body-free
    # `content_absent` observation is "produced inline at fetch-commit (no IngestionJob, no Document)
    # or via the ingestion pipeline". INLINE, and the reason is that the pipeline alternative cannot
    # be built without inventing product state: an IngestionJob's identity is
    # `(crawl_id, source_id, canonical_url, fetched_body_sha256, ...)` and a 404 has no fetched body
    # to key on, its Document would have no `fetched_object_id`, `byte_size` or `content_sha256`, and
    # :464's success path — which is the only path that produces Evidence — is defined as creating a
    # `source_document` and moving a Document `discovered -> ingested`. Every one of those is a thing
    # :452 says this outcome does NOT have. Inline is the narrow reading; the pipeline reading would
    # require five inventions.
    class IngestionHandoff
      # F-02 AAD binding for the staged response body. `purpose` is the ratified retention class for
      # pre-Evidence bytes — SCORE_EVIDENCE_MODEL.md: "Staging bytes before Evidence creation use
      # `temporary_processing`" — so the binding says what the ciphertext is for, and relocating it to
      # another job, purpose or tenant fails authentication rather than decrypting.
      STAGING_AAD = { application: "wf005", record_type: "ingestion_job", purpose: "temporary_processing" }.freeze

      # F-03 provenance for the body-free observation (:452's `content_absent`).
      OBSERVATION_AAD = { application: "wf005", record_type: "crawl_terminal_outcome",
                          purpose: "product_evidence_payload" }.freeze
      OBSERVATION_PRODUCER = "wf005.crawl_observation"
      OBSERVATION_SCHEMA = "crawl-observation-content-absent-v1"
      EVIDENCE_SOURCE_SYSTEM = "f1.crawler"
      COLLECTION_METHOD = "crawl_content_fetch"
      COLLECTOR_VERSION = CrawlPolicy::SCHEMA_VERSION

      # :462's "response-capture policy version". The bounds that governed what was captured from the
      # response — the per-URL body ceiling, the sentinel rule, the request timeout and the accepted
      # media types — are all `crawl-policy-v1`'s (:425-438, :436, :442).
      CAPTURE_POLICY_VERSION = CrawlPolicy::SCHEMA_VERSION

      # THE CLASSIFICATION OF CRAWLED CONTENT, DERIVED RATHER THAN CHOSEN.
      #
      # SCORE_EVIDENCE_MODEL.md's ladder defines `public` as "LAWFULLY PUBLIC SOURCE CONTENT and
      # observations whose disclosure adds no customer-private or security-sensitive context", and
      # `confidential` as "customer-PROVIDED nonpublic content". A crawl retrieves the first and never
      # the second: F-01 makes every request anonymous and unauthenticated, so anything a Crawl can
      # reach is content the Source serves to any client on the internet.
      #
      # OVER-CLASSIFYING IS NOT THE SAFE DIRECTION HERE, WHICH IS WHY THIS IS DERIVED AND STATED. The
      # same document says "Volume I defines no declassification permission or workflow, so
      # declassification is PROHIBITED": a `restricted` label applied defensively could never be
      # lowered, and `restricted` means "any Evidence explicitly placed behind a security grant" —
      # which would put every crawled page behind a grant that does not exist and block the
      # Check-facing Evidence the whole platform derives from it. The column carries the value per job
      # so a later capture policy can classify differently; this is the rule, not a hardcode.
      CONTENT_CLASSIFICATION = "public"

      def initialize(ids: Platform::Ids.system, correlation_id: nil)
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
      end

      # What one retirement produced. `document_id` is nil for every outcome but `document_created`;
      # `evidence_id` is set only by the `content_absent` limb, whose Evidence is created HERE because
      # it has no job to create it later. `replayed` says the identity already existed, which is the
      # redelivery case :462 requires to return the same job rather than a second one.
      Produced = Data.define(:document_id, :ingestion_job_id, :evidence_id, :replayed) do
        def initialize(document_id: nil, ingestion_job_id: nil, evidence_id: nil, replayed: false) = super
      end

      NOTHING = Produced.new

      # Produce whatever :452's outcome requires. `result` is the `FetchContent::Result`; `nil` for the
      # retirement paths that made no request at all (fail-closed robots), which produce nothing.
      def produce(pg:, organization_id:, crawl:, entry:, result:, now:)
        return NOTHING if result.nil?

        case result.outcome
        when FetchContent::DOCUMENT_CREATED then create_document_and_job(pg, organization_id, crawl, entry, result, now)
        when FetchContent::CONTENT_ABSENT then record_absence(pg, organization_id, crawl, entry, result, now)
        else NOTHING
        end
      end

      private

      # ---- :452's first covered outcome ------------------------------------------

      # THE ORDER IS FORCED BY THE FOREIGN KEYS AND BY THE REPLAY, IN THAT ORDER.
      #
      # A redelivered pass must find its own job and create NOTHING — ":462 — exact fetch replay
      # returns the same job" — so the identity is read FIRST, before any body is staged. Staging
      # before the read would leave an orphan ciphertext per redelivery, each holding a copy of the
      # customer's page bytes that nothing would ever destroy, because the destruction is keyed off
      # the job row that the conflict prevented from being written.
      def create_document_and_job(pg, organization_id, crawl, entry, result, now)
        store = IdentityAccess::Infrastructure::IngestionJobStore.new(pg)
        digest = Digest::SHA256.digest(result.body.to_s)
        existing = store.find_by_identity(organization_id:, crawl_id: crawl["id"], source_id: entry["source_id"],
                                          canonical_url: entry["canonical_url"], fetched_body_sha256: digest)
        if existing
          return Produced.new(document_id: existing["document_id"], ingestion_job_id: existing["id"],
                              replayed: true)
        end

        job_id = @ids.generate
        staged = stage_body(result.body.to_s, job_id, organization_id)
        document = create_document(pg, organization_id, crawl, entry, result, digest, staged, now)
        create_job(store, job_id, organization_id, crawl, entry, result, digest, staged, document, now)

        Produced.new(document_id: document["id"], ingestion_job_id: job_id)
      end

      # ":462 — Staged body bytes are IMMUTABLE AND INACCESSIBLE TO PRODUCT READS."
      #
      # F-02 gives both properties without a second storage subsystem: the bytes are an AES-256-GCM
      # envelope behind a SECURITY DEFINER function, the reference is the only capability that reaches
      # them, no product read path exists, and `Platform::Encryption.erase` is a record-level
      # cryptographic erasure — which is exactly what :464's 60-second deletion and :466's 24-hour
      # destruction each need to be able to do. The canonical `stored_objects` blob store
      # (POSTGRESQL_SCHEMA.md :231, `storage_provider CHECK ('aws_s3')`) is a shared foundation nobody
      # has built and no S-07 tranche owns; see the ADR for why building it here was refused rather
      # than attempted, and FU-65 for the migration.
      #
      # NO STORE ARGUMENT. The F-02 façade's default runs on `ActiveRecord::Base.connection`, which IS
      # the connection this method's caller opened its UnitOfWork on, so the ciphertext commits with
      # the Document and the job or with neither. Naming the internal store here would also break the
      # single-surface fitness spec.
      def stage_body(body, job_id, organization_id)
        aad = Platform::Encryption::Aad.for(**STAGING_AAD, record_id: job_id, tenant: organization_id)
        Platform::Encryption.protect(plaintext: body, aad:)
      end

      def create_document(pg, organization_id, crawl, entry, result, digest, staged, now)
        documents = IdentityAccess::Infrastructure::DocumentStore.new(pg)
        url_digest = Digest::SHA256.digest(entry["canonical_url"].to_s.unicode_normalize(:nfc).b)
        documents.lock_document_line(entry["source_id"], url_digest)
        documents.create(
          id: @ids.generate, now:, correlation_id: @correlation_id, causation_id: crawl["id"],
          command_id: nil, organization_id:, project_id: crawl["project_id"],
          source_id: entry["source_id"], crawl_id: crawl["id"],
          canonical_url: entry["canonical_url"], canonical_url_sha256: url_digest,
          # THE FETCHED OBJECT IS THE STAGED ONE, which is the only object that holds these bytes at
          # the instant the Document is created. It keeps naming that object after :464 destroys it,
          # exactly as a `stored_objects` row survives its own `destroyed` transition: the Document's
          # provenance is a fact about what was fetched, not a promise that the bytes are still there.
          fetched_object_id: staged.reference,
          media_type: result.media_type, byte_size: result.accounted_bytes.to_i, content_sha256: digest
        )
      end

      def create_job(store, job_id, organization_id, crawl, entry, result, digest, staged, document, now)
        created = store.create(
          id: job_id, now:, correlation_id: @correlation_id, causation_id: crawl["id"], command_id: nil,
          organization_id:, project_id: crawl["project_id"], source_id: entry["source_id"],
          crawl_id: crawl["id"], document_id: document["id"], canonical_url: entry["canonical_url"],
          fetched_body_sha256: digest, final_http_status: result.http_status.to_i,
          media_type: result.media_type, staged_body_reference: staged.reference,
          # ":466 — at most 24 hours FROM FETCH COMPLETION", stamped once and frozen by the guard.
          staging_expires_at: IngestionContract.staging_expiry(now),
          # ":462 — received byte count." `FetchContent::Result` carries the ACCOUNTED figure and not
          # the raw one, and on this path they are the same number rather than merely close: F-01
          # never content-decodes, so `Outcome#byte_count` IS `body.bytesize`, and
          # `ByteAccounting.measure` returns `min(received, ceiling)` — where a body that reached the
          # ceiling is `over_limit?`, which `FetchContent#classify` turns into `content_fetch_failed`
          # or `limit_discarded` and never into `document_created`. So the only bodies that reach here
          # were under their ceiling, where accounted == received == the staged bytes' size. The
          # ingester re-derives that equality from the bytes themselves rather than trusting it.
          received_byte_count: result.accounted_bytes.to_i,
          response_capture_policy_version: CAPTURE_POLICY_VERSION,
          data_classification: CONTENT_CLASSIFICATION,
          # :462's job idempotency key IS its identity, which is what makes "exact fetch replay
          # returns the same job" true by construction rather than by a second bookkeeping table.
          idempotency_key: job_identity_key(crawl, entry, digest),
          # ":140 — `ingestion_attempt_due` ... INITIAL or declared 30/120-second retry." The initial
          # attempt is due immediately; the action itself is minted by the handler's terminal
          # transaction (:378), which is the commit this job becomes visible in.
          next_due_at: now
        )
        # A NIL RETURN IS THE CONFLICT, AND IT MUST NOT BE SWALLOWED. `find_by_identity` above already
        # ran on this transaction under the frontier lock, so a conflict here means a writer this
        # design does not have — a second producer of IngestionJobs — and the honest response is to
        # abort the retirement rather than proceed with a Document that has no job.
        return created unless created.nil?

        raise Platform::InvariantViolation, "ingestion job identity conflicted inside its own retirement"
      end

      def job_identity_key(crawl, entry, digest)
        Digest::SHA256.hexdigest(
          [crawl["id"], entry["source_id"], entry["canonical_url"], digest.unpack1("H*"),
           IngestionContract::SCHEMA_VERSION].join(" ")
        )
      end

      # ---- :452's second covered outcome -----------------------------------------

      # ":452 — returns terminal 404/410 and creates a valid BODY-FREE `crawl_observation` with reason
      # `content_absent`." Every word of that sentence is load-bearing here:
      #
      #   * BODY-FREE — the payload carries the observation and no response bytes. `FetchContent`
      #     already returns `body: nil` for this outcome, so there are none to carry.
      #   * VALID — `validation_status: "valid"`, which is F-03's creation-time decision and is what
      #     :452 requires for the outcome to be COVERED. An `invalid` observation would leave the URL
      #     uncovered, and `CoverageClassification` has already classified it covered in this same
      #     transaction; the two must agree or the run's coverage overstates itself.
      #   * `content_absent` AS THE REASON — carried in the payload, because the Evidence envelope's
      #     `validation_reason_code` is null for a valid record by its own CHECK. The reason names why
      #     the content is absent, not why the Evidence is invalid; they are different fields.
      #
      # IDEMPOTENT ON THE FRONTIER ENTRY. F-03 appends on `(organization_id, producer_id, attempt_id)`,
      # and the entry is the one thing that identifies this observation: one admitted URL, one
      # retirement, one observation. A redelivery returns the existing evidence_id and writes nothing.
      def record_absence(pg, organization_id, crawl, entry, result, now)
        payload = Platform::CanonicalJson.encode(absence_payload(crawl, entry, result, now)).b
        aad = Platform::Encryption::Aad.for(**OBSERVATION_AAD, record_id: entry["id"], tenant: organization_id)
        protected_payload = Platform::Encryption.protect(plaintext: payload, aad:)

        record = Platform::Evidence::Record.build(
          schema_version: OBSERVATION_SCHEMA, organization_id:, project_id: crawl["project_id"],
          source_id: entry["source_id"], evaluation_id: evaluation_for(pg, organization_id, crawl),
          evidence_type: "crawl_observation", producer_id: OBSERVATION_PRODUCER, attempt_id: entry["id"],
          payload_reference: protected_payload.reference,
          content_sha256: protected_payload.content_digest.unpack1("H*"),
          captured_at_utc: now, observed_at_utc: now, source_system: EVIDENCE_SOURCE_SYSTEM,
          collection_method: COLLECTION_METHOD, collector_version: COLLECTOR_VERSION,
          validation_status: "valid", validation_reason_code: nil,
          data_classification: CONTENT_CLASSIFICATION,
          payload_retention_class: Platform::Evidence::Record::PRODUCER_RETENTION_CLASS,
          correlation_id: @correlation_id
        )
        Produced.new(evidence_id: Platform::Evidence.produce(record))
      end

      def absence_payload(crawl, entry, result, now)
        {
          "schema_version" => OBSERVATION_SCHEMA,
          "reason" => FetchContent::CONTENT_ABSENT,
          "crawl_id" => crawl["id"],
          "source_id" => entry["source_id"],
          "crawl_frontier_entry_id" => entry["id"],
          "canonical_url" => entry["canonical_url"],
          # The status is part of the observation because :452 admits exactly two, and a reader
          # deriving :478's terminal-outcome map needs to know which was seen.
          "http_status" => result.http_status.to_i,
          "final_url" => result.final_url,
          "redirect_count" => result.redirect_count.to_i,
          "observed_at_utc" => now.getutc.iso8601(6)
        }
      end

      # The Evaluation this Crawl's Evidence belongs to. SCORE_EVIDENCE_MODEL.md makes `evaluation_id`
      # "nullable ONLY for Verification Evidence captured before an Evaluation exists", so a crawl
      # observation carries one: a root Crawl's own pending initial Evaluation (created atomically at
      # the accepted start, OD-018), or the parent Evaluation a reassessment child names.
      def evaluation_for(pg, organization_id, crawl)
        row = pg.exec_params(<<~SQL, [organization_id, crawl["id"]]).to_a.first
          SELECT id FROM evaluations
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND kind = 'initial'
        SQL
        row ? row["id"] : crawl["parent_evaluation_id"]
      end
    end
  end
end
