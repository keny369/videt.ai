# Volume III Artifact Map — Where the Proposed Platform Documents Fit

Status: Informational planning input, 28 July 2026. Not canonical; records the owner-reviewed disposition of the proposed six-layer artifact stack against the existing Product Architecture Manual, so nothing is built twice and nothing canonical is bypassed. Filing occurs after the 30-day revenue plan concludes (Day 30 = 27 Aug 2026).

## Disposition of the six layers

| Proposed artifact | Disposition | Canonical home | When |
|---|---|---|---|
| 1. Canonical domain model (subject-side: Business, Practitioner, Licence, Regulator, Industry, Brand…) | Platform-side entities already frozen in `011 DOMAIN_MODEL.md`; subject-side = the Reality Graph, sketched in ADR-012 (Future) | Volume III, via the vision-set ADR filing | Post Day 30 |
| 2. Evidence ontology | Evidence Type is a CLOSED taxonomy (ADR-017); extension = controlled Volume I change. Per-source authority/decay/legal-risk is a *source* property | Merged into layer 4 (source registry); seeds: ChatGPT truth hierarchy + 393-surface inventory | With layer 4 |
| 3. AI measurement specification | Already named by governance: the **OD-010 Measurement Set** (signed, immutable, owner-approved). Scientific content consolidated in `000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §6 + `operations/ASSESSMENT_DELIVERY_GUIDE.md` Parts 5–6; canonical fields in FUTURE-WORKFLOW-001 Observation Contract | OD-010 approval package | Before measurement activation |
| 4. Source registry specification (lifecycle, parsers, retirement) | Genuinely new; matches ADR-012 provider-adapter pattern. Robots/captcha/paid-source questions belong to the ToS analysis in counsel's brief | Volume III | Phase 2 platform work |
| 5. Recommendation policy library (per industry, versioned) | Seeded: ~40 per-industry policies in `specification/machines/`; repo already has the versioned-policy idiom (check-catalog-v1 etc.) | Versioned policies, pilot verticals first, written from pilot data | Post Day 30, per vertical |
| 6. AI behaviour specification (per assistant, empirical) | v0 exists: this folder (self-reports, treated as hypotheses). Empirical version accretes from delivery-guide Part 12 run logs; equals "provider characteristics" in ADR-012's Intelligence Graph | One file per assistant in `specification/machines/`, data-grown | Continuous from client one |

## Additional artifacts — dispositions

Glossary → extend `002/003` by ADR, never duplicate · Scoring catalog → exists for ratified scope (SCORE_EVIDENCE_MODEL) · Prompt catalog → mandated by AI-REQ-004 when AI features build · Experiment log → is FUTURE-WORKFLOW-001 · Failure catalog → seeded (synthesis §5 taxonomy) · Evaluation dataset → being built now (Reality Cards + controls + run logs) · Legal & compliance matrix → grows from OD-011 markets + counsel brief · ADRs → exist (`DECISIONS.md`, controlled process).

## The accepted new artifact: Truth & Claims Specification

The platform's epistemology — claim classes (Verified / Corroborated / Claimed / Inferred / Estimated / Opinion / Allegation / Finding of a court or regulator / Marketing Claim / AI-generated Summary) with per-class rules: producer, required evidence, ranking influence, display permission, confidence model, expiry/revalidation. Fragments already ratified: citation-policy-v1, OD-003 confidence bands, PRULE-037, classification levels, guide Part 11. Working v0 = the delivery guide's language law. Full specification drafted at vision-set filing as a foundation-level document (ADR-governed), because it constrains all of Volume III.

## Drafted inputs (28 Jul 2026)

Four highly-detailed specification-input modules now exist in `specification/volume-iii-inputs/` (Module 1 Observation & Measurement; Module 2 Reality Graph/Entity/Source Registry; Module 3 Intervention & Fix Library; Module 4 Truth & Claims). They are future/gated drafts with a binding reconciliation backlog in that folder's `00-README.md` — thirteen items to resolve before ADR filing, including the four-graph (`governance/CUSTOMER_VALUE_CONSTITUTION.md`, ADR-048 Accepted) vs three-graph alignment, the Source-vs-Registry-Surface split, and the claim-class count. These do not change canon.

## Filing order (Day 30+)

1. Vision set filed by ADR — resolving the ADR-012/013 numbering collision and the Finding-vs-Issue vocabulary collision.
2. Truth & Claims Specification.
3. Reality-side domain model (layer 1).
4. Pilot-vertical recommendation policies (layer 5) from pilot data.
5. Layers 3/4/6 as the platform build reaches them.

## Standing governance rules

No dictionary beside 002/003 · no Evidence Type outside the controlled-change process · nothing in `machines/` or `operations/` outranks the ratified manual · research graduates to canon only through the ADR front door.
