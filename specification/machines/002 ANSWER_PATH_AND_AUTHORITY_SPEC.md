# Answer Path & Authority — Future Implementation Specification

Status: Future specification input (Volume III candidate), 28 July 2026. Codifies the verified learnings of the 28 Jul answer-path investigation (Lumen & Lever live case; three-agent verification of assistant-cited sources) into implementation-grade detail for videt.ai. Conformant with ADR-013 (Genesis conventions) and FUTURE-WORKFLOW-001 vocabulary. **Nothing here is ratified**: check identifiers are candidates (the ratified check-catalog-v1 is untouched); "finding" is used in its FUTURE-WORKFLOW-001 sense pending the vocabulary ADR. Graduation path: vision-set ADR filing → Volume III. Operational (manual-era) counterparts: `operations/AUTHORITY_ROADMAP.md`, `operations/ASSESSMENT_DELIVERY_GUIDE.md` Parts 5/8/12.

## 1. The two empirical facts this spec encodes

1. **Mention behaviour decomposes into two layers.** Retrieval authority (what the assistant finds and resolves when it searches — moves in weeks) and parametric authority (what the model already associates — moves in training generations). Confirmed live: ChatGPT articulated the split unprompted; two-arm behaviour observed. Every measurement, recommendation and outcome-attribution in the platform must be layer-aware.
2. **Assistant self-reports about sources are leads, not evidence.** Confirmed live: ChatGPT cited a real Clutch page as supporting entities that do not appear on it (misattribution: real URL, wrong contents). Therefore: elicited citations enter the system flagged `self_reported`, and nothing self-reported may surface in a report, score input or intervention plan until independently verified.

## 2. Candidate domain objects (extends FUTURE-DOMAIN vocabulary)

All objects follow Genesis conventions: explicit aggregates, immutable evidence, versioned records, organ