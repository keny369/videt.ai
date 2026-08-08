# Volume III Specification Inputs — Index & Reconciliation Backlog

Status: **Future / gated specification inputs. NOT ratified. NOT canon.** Prepared 28 July 2026 by multi-agent authoring + reconciliation. The ratified Product Architecture Manual (Foundation 000–020, Volume I/II frozen) is the single source of truth (ADR-001). These four documents codify the machine-behaviour, measurement, intervention and truth-model insights as **implementation-ready inputs for a future Volume III**, so a future engineering agent can build from them — but they enter canon **only through the vision-set ADR**, after Day 30 (27 Aug 2026), and only where a controlled Volume I change plus an approved OD-010 Measurement Set expressly enable it.

Nothing here overrides the frozen manual, the Accepted `governance/CUSTOMER_VALUE_CONSTITUTION.md` (ADR-048), or any owner decision. Where these drafts and an accepted authority disagree, the accepted authority wins and the draft is wrong until reconciled.

## The four modules

| File | Codifies | Extends |
|---|---|---|
| `VOL3-INPUT-observation-measurement.md` | How VIDET observes assistants and measures behaviour: Observation Contract, screening vs instrument grades, two-arm search on/off, the five metrics with formulas, run-failure quarantine, the typed run-log schema | FUTURE-WORKFLOW-001 Observation Contract; SCORE_EVIDENCE_MODEL external-observation; OD-010 gate |
| `VOL3-INPUT-reality-entity.md` | The subject-side world: entity ontology, the Reality Card as entity-resolution gate, the 393-surface Source Registry as a typed subsystem, per-vertical evidence policies | 011 DOMAIN_MODEL; ADR-012 provider-adapter pattern |
| `VOL3-INPUT-intervention-fix.md` | The fix system as executable spec: two-layer clock taxonomy, fix catalogue mapped 1:1 to canonical intervention types, verified competitor patterns, the Intervention Plan aggregate, the refuse-to-sell guardrails (INV-IP-2) | FUTURE-WORKFLOW-001 intervention types; Intervention Plan aggregate |
| `VOL3-INPUT-truth-claims-evidence.md` | The platform's epistemology: the claim-class taxonomy, provenance/authority hierarchy, the source-elicitation-and-verify invariant (the Clutch confabulation case), evidence codification | The accepted "Truth & Claims Specification" (artifact map); Evidence model; citation-policy-v1; OD-003 |

## Later candidate inputs (added after the 28 July authoring pass)

These are **not** part of the four-module set above and are **not** covered by its reconciliation backlog. Each was written from a specific, dated piece of evidence and records a gap so it is not lost and does not get smuggled into a ratified artifact. Same front door: an owner decision in the register, in the manner of OD-010.

| File | Records | Written from |
|---|---|---|
| `VOL3-INPUT-ai-misrepresentation-catalog.md` | A product requirement `check-catalog-v1` does not cover: measuring what AI gets wrong about a business | Two manual measurement runs — 476 conversations, 20 Melbourne businesses, two verticals (8 Aug 2026) |
| `VOL3-INPUT-external-pillar-evidence-gap.md` | What `CHK-SP-001` and `CHK-AS-001` would each require field by field, whether it is obtainable, what it costs per business per run, and the `CHK-LP-001` applicability question — plus the `CHK-TI-001` `policy_excluded` residual | The frozen `external-observation-v1` contract, OD-010's approval package, and measurement against the live `xirconhomes.com.au` crawl (8 Aug 2026) |

## Reconciliation backlog — RESOLVE BEFORE ADR FILING (binding)

The reconciler found the following. These are **known defects in these drafts**, recorded so no one mistakes them for reconciled canon. Each is an owner/ADR decision, not a silent edit.

### Canon-alignment defects (must fix before filing)

1. **Four-graph vs three-graph.** `governance/CUSTOMER_VALUE_CONSTITUTION.md` (Accepted, ADR-048) is authoritative and defines **Reality / Perception / Gap / Intelligence** with the OBSERVE → ASSESS → COMPARE → INTERVENE → LEARN loop. Modules 1 & 2 correctly build on it; **Modules 3 & 4 use an unratified three-graph branding model and drop the Gap graph** — they must be realigned to the four-graph Constitution (or explicitly record Gap collapsed into COMPARE, pending ADR). The branding `002 VISUAL_IDENTITY.md §3` colour mapping also names three graphs — a marketing device, but flag it for alignment.
2. **Gap / COMPARE ownership hole.** Across the four modules nobody owns the Gap Graph / COMPARE stage — the divergence layer the customer actually pays to close. The Constitution makes it first-class; a module must own it.
3. **ADR-012 / ADR-013 identifier collision.** Frozen ADR-012 = "Foundation Baseline 1.0 & Controlled Change"; ADR-013 = "Canonical Diagram Authority". The Desktop vision docs reuse those numbers for different content. No module may cite ADR-012/013 as if the future meaning were ratified. Resolution is reserved for the vision-set ADR (`001 VOLUME_III_ARTIFACT_MAP.md`).
4. **OD-013 miscitation (Module 3).** OD-013 is "Event Tenant Identity", not Source ownership. The organization-owned-Source rule lives in the S-05/S-06 source-scope work and OD-001 ownership verification. Re-anchor.
5. **OD-010 must not read as approved (Module 1).** The external Measurement Set is **unapproved**; the label must show future/unapproved state, not ratified.
6. **Claim-class count: 12 vs 10.** The accepted artifact-map sketch names 10 claim classes; Module 4 asserts 12. Module 4 owns the enum, must reconcile to 10 + flag the two additions for the ADR, and Module 2 must **reference** it, not define its own Claimed/Verified vocabulary.
7. **"Finding" three ways.** FUTURE-WORKFLOW-001 "Finding" (measurement pattern), Module 4 "Finding of a court or regulator" (claim class), and the frozen-forbidden Issue-synonym "finding" (003 TERMINOLOGY) must each be flagged so none reads as the prohibited object. No module presents any "Finding" as a ratified first-class object.

### Cross-module seams (must assign a single owner)

8. **Source entity vs Registry Surface overload.** The frozen tenant-owned `Source` (DM-REQ-001, ownership-verified) must not be overloaded by the platform-curated 393-surface registry. Registry surfaces need a distinct term (e.g. **Registry Surface** / Corroboration Surface).
9. **Observed assistant answer vs frozen AIResponse/Citation.** The frozen `AIResponse` and OD-007 `Citation` are F1's *own* guidance payloads. Observed third-party assistant answers and their self-reported citations must be **new candidate objects**, distinct from the frozen entities. Modules 1 & 4 settle jointly.
10. **`self_reported → verified` gate — single owner.** The Clutch-confabulation rule (assistant citations are leads, not evidence) is encoded in four places. Module 4 (epistemics) owns the `self_reported` field and its state machine; Modules 1 & 3 reference it.
11. **Confidence serialization — one shared contract.** OD-003 mandates numeric 0.0000–1.0000 + derived Low/Medium/High band. All four schemas must serialize confidence identically; never a free-form band string, never a composite/efficacy score.
12. **Finding taxonomy owner.** The findings taxonomy (Absence, Entity Conflation, Temporal Hallucination, Geographic Boundary Breach, Authority Spoofing, Anchoring Fragility) currently lives only in the non-canonical `machines/000`. A module must own it as the producer boundary between measurement (Module 1) and detection.
13. **Provenance/authority tiers — one vocabulary.** Module 4's 7-tier claim-provenance hierarchy and Module 2's Source-priority scheme must become one shared source-authority tier vocabulary.

## Filing order (post Day 30, per `001 VOLUME_III_ARTIFACT_MAP.md`)

1. Vision set filed by ADR — resolves the ADR-012/013 numbering and the Finding/Issue collision, and ratifies the graph model (three vs four).
2. Truth & Claims Specification (from Module 4, reconciled to 10+2 claim classes).
3. Reality-side domain model + Source/Registry-Surface split (Module 2).
4. Observation & Measurement Engine (Module 1) — gated on OD-010 Measurement Set approval and the ToS/automation ruling in counsel's brief.
5. Intervention & Fix Library (Module 3).

Until then: **manual, human-scale observation only** (the concierge assessment). These inputs describe the platform to be built after selling proof and the ADR filings — not before.
