# frozen_string_literal: true

module Workflows
  module Wf005
    # `ingestion-interim-v1` AS A TRANSCRIPTION (WORKFLOW_SPECIFICATIONS.md :460-466).
    #
    # Everything here is a ratified literal, not a policy this build chose. The three lists are
    # exhaustive and ORDERED, because :464 says "FIRST-MATCH failures" — the order is the contract,
    # so a body that is both the wrong size and the wrong media type is a `received_byte_count_mismatch`
    # and not a `media_type_unsupported`, and a reader can tell which check fired.
    #
    # WHY THE PRE-PERSISTENCE LIST IS SEPARATE FROM THE EXECUTION LIST. :464 splits them: the first
    # eight are checked "BEFORE PERSISTENCE" and describe the INPUT — this job should never have been
    # created, or its input has gone — while the three execution failures describe the ATTEMPT. Only
    # two of the execution three retry, and no pre-persistence failure does, which is why the split is
    # behavioural rather than documentary.
    module IngestionContract
      module_function

      # BOUND, NOT RESTATED. The literal lives at the write site, where the column's CHECK pins it
      # (`IdentityAccess::Infrastructure::IngestionJobStore`), because the persistence package may not
      # depend on this one. One constant, two readers.
      SCHEMA_VERSION = IdentityAccess::Infrastructure::IngestionJobStore::INGESTION_SCHEMA_VERSION

      # :464 — "Before persistence, first-match failures are ...", in the stated order.
      TENANT_MISMATCH = "tenant_mismatch"
      SOURCE_SCOPE_MISMATCH = "source_scope_mismatch"
      STAGED_BODY_MISSING = "staged_body_missing"
      RECEIVED_BYTE_COUNT_MISMATCH = "received_byte_count_mismatch"
      FETCHED_BODY_DIGEST_MISMATCH = "fetched_body_digest_mismatch"
      MEDIA_TYPE_UNSUPPORTED = "media_type_unsupported"
      MALWARE_OR_ACTIVE_CONTENT_DETECTED = "malware_or_active_content_detected"
      INGESTION_POLICY_UNAVAILABLE = "ingestion_policy_unavailable"

      PRE_PERSISTENCE_FAILURES = [
        TENANT_MISMATCH, SOURCE_SCOPE_MISMATCH, STAGED_BODY_MISSING,
        RECEIVED_BYTE_COUNT_MISMATCH, FETCHED_BODY_DIGEST_MISMATCH, MEDIA_TYPE_UNSUPPORTED,
        MALWARE_OR_ACTIVE_CONTENT_DETECTED, INGESTION_POLICY_UNAVAILABLE
      ].freeze

      # :464 — "Execution failures are `ingest_timeout`, `ingest_dependency_unavailable`, or
      # `ingested_evidence_invalid`; unknown diagnostics map to the last reason."
      INGEST_TIMEOUT = "ingest_timeout"
      INGEST_DEPENDENCY_UNAVAILABLE = "ingest_dependency_unavailable"
      INGESTED_EVIDENCE_INVALID = "ingested_evidence_invalid"

      EXECUTION_FAILURES = [INGEST_TIMEOUT, INGEST_DEPENDENCY_UNAVAILABLE, INGESTED_EVIDENCE_INVALID].freeze

      # ":464 — UNKNOWN DIAGNOSTICS MAP TO THE LAST REASON", which is the last of the three named on
      # that line. It is deliberately the NON-RETRYABLE one: an ingestion that failed for a reason
      # nobody enumerated must not be retried on the strength of a guess, and :466 dead-letters it
      # where an operator can see it.
      UNKNOWN_DIAGNOSTIC = INGESTED_EVIDENCE_INVALID

      # :466 — "Each attempt has a 30-SECOND TIMEOUT; equality belongs to timeout and late completion
      # is discarded."
      ATTEMPT_TIMEOUT_S = 30

      # :466 — "ONLY `ingest_timeout` and `ingest_dependency_unavailable` retry, with ONE INITIAL
      # ATTEMPT PLUS TWO RETRIES 30 and 120 seconds after the preceding failed attempt."
      MAX_ATTEMPTS = 3
      DELAYS_S = { 1 => 30, 2 => 120 }.freeze
      RETRYABLE_REASONS = [INGEST_TIMEOUT, INGEST_DEPENDENCY_UNAVAILABLE].freeze

      # :466 — "retains inaccessible staging bytes for AT MOST 24 HOURS FROM FETCH COMPLETION".
      STAGING_RETENTION_S = 24 * 60 * 60

      # :464 — the two events a success emits, and :466's two failure events (API_CONTRACTS.md
      # :811-814). Named here so the handler cannot spell one differently from the registry.
      DOCUMENT_INGESTED = "DocumentIngested"
      INGESTION_SUCCEEDED = "IngestionSucceeded"
      INGESTION_STARTED = "IngestionStarted"
      INGESTION_FAILED = "IngestionFailed"
      INGESTION_DEAD_LETTERED = "IngestionDeadLettered"
      INGESTION_QUEUED = "IngestionQueued"
      DOCUMENT_DISCOVERED = "DocumentDiscovered"

      # :436 — "has a media type before parameters of `text/html` or `application/xhtml+xml`". The
      # SAME list `FetchContent` admits, bound rather than restated: the fetch decides what may be
      # captured and ingestion re-checks the capture, so two literals could disagree about one URL.
      def supported_media_type?(media_type) = FetchContent::DOCUMENT_MEDIA_TYPES.include?(media_type)

      # ":466 — Only `ingest_timeout` and `ingest_dependency_unavailable` retry", and only while
      # attempts remain. Both conjuncts, because ":466 — Other failures AND EXHAUSTED RETRY move
      # `running -> failed -> dead_letter` at one checkpoint."
      def retry_owed?(reason_code, attempt_number)
        RETRYABLE_REASONS.include?(reason_code) && attempt_number.to_i < MAX_ATTEMPTS
      end

      # The delay before the retry that follows the attempt that just failed, in seconds. ":466 — 30
      # and 120 seconds AFTER THE PRECEDING FAILED ATTEMPT", so the caller measures from the
      # committed `completed_at` and not from its own clock.
      def retry_delay_s(attempt_number) = DELAYS_S.fetch(attempt_number.to_i, DELAYS_S.values.last)

      # ":466 — retains inaccessible staging bytes for at most 24 hours FROM FETCH COMPLETION."
      def staging_expiry(fetch_completed_at) = fetch_completed_at + STAGING_RETENTION_S
    end
  end
end
