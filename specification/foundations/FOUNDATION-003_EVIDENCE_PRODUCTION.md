# FOUNDATION-003 — Evidence Producer Foundation

Status: **Ratified contract (ADR-024).** Supporting architecture contract, not a canonical ADR (decision of record: `DECISIONS.md` ADR-024). Implemented by the **F-03** tranche step, after F-02, before S-05.

- Ratified: 2026-07-24 (ADR-024)
- Owner context: the `Evidence` bounded context (Evidence Context, 011 DOMAIN_MODEL.md)
- First producer: **S-05** — the `verification_observation` Evidence record per started observation.
- **Producer/evaluator boundary (ratified):** F-03 establishes the append-only Evidence store and the *producer* path. **CAP-013 / S-09 retains ownership** of evidence *evaluation* — validation decisions, validation heads, adjudication, interpretation and the broader evidence lifecycle. F-03 records facts; it does not decide what they mean.

## Purpose

The immutable, append-only recording of externally observed facts, with full provenance, so that every downstream number can trace to inspectable evidence and no observation is ever mutated or synthesised. This is the platform's "immutable evidence" foundation.

## The EvidenceRecord

Append-only. Written once by a producer; never updated. The canonical envelope (per SCORE_EVIDENCE_MODEL.md) carries at minimum:

- `evidence_id`, `schema_version`
- tenant/subject identity: `organization_id`, `project_id`, nullable `source_id`, nullable `evaluation_id`
- `evidence_type` (the producer's kind; S-05 produces `verification_observation`)
- **producer identity** and `collection_method` / `collector_version` (**methodology version**)
- **captured/observed time** (`captured_at_utc`, `observed_at_utc`)
- **content digest** (`content_sha256`) and `payload_reference` (encrypted or externally referenced payload — never inline plaintext secrets)
- **provenance** (`source_system`, `correlation_id`)
- creation-time `validation_status` + `data_classification` + `payload_retention_class`

## Mandatory properties

1. **Immutability / append-only.** The Evidence repository exposes `append` and identity/content-hash lookup only — no update. A correction is a *new* Evidence record, never an edit.
2. **Producer identity + subject identity** on every record; a record with no producer or no tenant/subject is unrepresentable.
3. **Methodology version** (`collection_method`/`collector_version`) recorded, so the exact rule that produced the observation is auditable and reproducible.
4. **Content digest** over the observed bytes; **payload is encrypted or referenced** (F-02 for secrets), never stored as inline plaintext when restricted.
5. **Classification-aware** — `data_classification` (`public`/`internal`/`confidential`/`restricted`) governs access; `verification_observation` is `restricted`.
6. **Redaction at production** — the producer reduces provider text to enum/status fields; header values, bodies, DNS values, host addresses and error text are discarded, and **no plaintext token or raw observation is retained at rest** (S-05 invariant).
7. **No interpretation.** F-03 does not compute scores, validity beyond the creation-time status, adjudication, or meaning. Those are evaluation capabilities (S-09+).

## Abstraction

```
EvidenceProducer     → append(EvidenceRecord) → evidence_id   (append-only; idempotent by producer/attempt identity)
EvidenceRepository   → get(evidence_id); find_by_content_hash(...)   (read-only)
```

Producers (S-05 verification, later S-07 crawl, S-08 parse) own their `evidence_type` producer contract and consume this append path without redefining the envelope.

## Acceptance criteria (for the F-03 implementation)

- The `evidence` table is append-only: no update path exists; RLS-forced, tenant-scoped; least-privilege runtime grant (SELECT/INSERT, no UPDATE/DELETE).
- A `verification_observation` record persists with full provenance and a content digest; its restricted payload holds no plaintext token or raw observation.
- Appending is idempotent by producer/attempt identity: a retried completion writes no second Evidence record.
- No evaluation, validation-head, adjudication, or scoring table is created (those are CAP-013/S-09).
- The producer/evaluator boundary is asserted: F-03 offers no interpretation surface.

## Non-goals / boundaries

- **Not** evidence validation decisions, validation heads, adjudication, deduplication, supersession, or scoring — all CAP-013 / S-09.
- **Not** the retention/deletion executor (DataLifecycle) — F-03 records the retention class; destruction is elsewhere.
- **Not** a general document/blob store beyond the referenced-payload contract.

## Genesis + Videt

Genesis contracts unchanged. This is the "immutable evidence production" foundation on which the entire Videt intelligence graph rests — every future validated learning traces, ultimately, to an append-only Evidence record produced here. The producer/evaluator split is exactly the layering the future architecture (FUTURE-IP-001) depends on: capture is separate from interpretation.
