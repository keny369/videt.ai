# frozen_string_literal: true

module Platform
  # Evidence Production (F-03, FOUNDATION-003) — FROZEN public contract.
  #
  # The immutable, append-only recording of observed FACTS. This module plus Record and
  # InvalidEvidence is the entire producer/reader surface: a producer (S-05 verification
  # first, later S-07 crawl, S-08 parse) validates a Record and calls `produce`; readers
  # locate Evidence by id or content hash. F-03 records facts and offers NO interpretation
  # — validation heads, adjudication, deduplication and scoring are the evaluation layer
  # (CAP-013/S-09) and deliberately do not exist here.
  #
  # Only this surface may write Evidence: the internal EvidenceStore is the single writer,
  # and spec/architecture/evidence_single_surface_spec.rb fails CI if any code outside the
  # adapter references it. The envelope is immutable at the database — there is no update
  # path here or in SQL. A restricted payload is never inline: the producer stores it behind
  # a reference (F-02 for secrets) and records only the reference + content digest, so the
  # Evidence table holds no plaintext token or raw observation.
  module Evidence
    module_function

    # Append a validated Evidence Record; returns its evidence_id. Idempotent by
    # (organization_id, producer_id, attempt_id) — a retried producer completion writes no
    # second record. Runs in the caller's proved Organization context (RLS-scoped).
    def produce(record, store: nil)
      (store || EvidenceStore.new).append(record)
    end

    def get(evidence_id, store: nil)
      (store || EvidenceStore.new).get(evidence_id)
    end

    def find_by_content_hash(content_sha256, store: nil)
      (store || EvidenceStore.new).find_by_content_hash(content_sha256)
    end
  end
end
