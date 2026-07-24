# Videt — Future Architecture (owner-supplied)

Status: **Future architecture. NOT current Genesis requirements.**

The documents in this folder describe where the **Videt** platform is intended to go. They are conceptual and durable — a direction, not a specification. They carry **no engineering authority**:

- They do **not** override the Product Architecture Manual, Volume I, Volume II, the Engineering Manual, or any ratified Genesis contract.
- They introduce **no** current requirement, table, command, event, or acceptance criterion.
- Nothing here may be implemented as current behaviour, and no future capability may leak into Genesis behaviour.
- Their role is exactly what good architecture documents do: shape platform architecture *without* being implemented. (S-01→S-04 already, without building a single future feature, naturally produced the shapes these documents call for — Source as an aggregate, immutable evidence, provider independence, an outbound abstraction, event lineage, security boundaries.)

Genesis remains the buildable system; `F1` remains the internal engineering codename; Videt is the market brand (see `../BRAND_FOUNDATION.md §11` — the branding/engineering firewall). **Do not inject Genesis table names, slice ids, or `S-0N`/`F-0N` implementation detail into these documents.**

## The document set

| # | Document | Subject | In this folder |
|---|---|---|---|
| 1 | VISION-001 | Commercial Discoverability Observatory (the vision) | owner-supplied |
| 2 | ADR-012 | Future Discoverability Architecture (three-graph model) | owner-supplied |
| 3 | ADR-013 | Genesis Project Conformance (future builds on Genesis) | owner-supplied |
| 4 | FUTURE-DOMAIN-001 | Future domain model | owner-supplied |
| 5 | FUTURE-WORKFLOW-001 | Intervention Learning Lifecycle | owner-supplied |
| 6 | FUTURE-IP-001 | Commercial Discoverability Intelligence (the moat) | owner-supplied |
| 7 | (README) | This file | present |

> **Filing note.** These source documents are owner-supplied strategy artifacts. They should be committed here verbatim from the owner's originals. They were provided to the implementation session as attachments rather than as repository files; to avoid any fidelity drift in canonical strategy text — and because one of the set (FUTURE-DOMAIN-001) was not among the provided attachments — the verbatim documents are filed by the owner (or in a dedicated, checked transcription pass) rather than reproduced here from context. This README establishes their home, their status, the Videt nomenclature, and the foundations amendment below.

## Videt nomenclature (apply lightly to these documents)

Per `../BRAND_FOUNDATION.md §8`. Lead with the Videt mark; keep the descriptive category term in the body.

- "Commercial Discoverability Platform" → **The Videt Platform**
- "Commercial Discoverability Observatory" → **Videt Observatory**
- "Commercial Discoverability Intelligence" → **Videt Intelligence™**
- Company → **Videt**

Do not rename the *concepts* (Reality, Perception, Intelligence, Observatory, Evidence, the gap) — those are the durable vocabulary.

## Architecture amendment — Videt future platform foundations

Genesis has now made explicit (DECISIONS.md ADR-024) the shared platform foundations that were previously implicit. They belong in the future architecture as the layer beneath the conceptual model:

```
Reality  ->  Observation  ->  Perception  ->  Intervention  ->  Intelligence
                                 rests on
    Shared Outbound Transport   (one guarded egress surface)
    Cryptographic Protection    (envelope encryption, vendor-neutral KeyProvider)
    Immutable Evidence Production (append-only, producer/evaluator split)
    Durable Background Execution (idempotent, leased, transaction-safe)
```

These foundations serve Genesis today and Videt tomorrow. They are the concrete substrate on which the Observation → Perception → Intelligence loop of the future architecture will run — built once, correctly, before the features that depend on them.
