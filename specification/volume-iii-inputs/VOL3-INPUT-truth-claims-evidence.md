# Volume III Specification Input — Module 4
# Truth & Claims Specification + Evidence Codification

> **Status:** Volume III specification input — future/gated; enters canon only via the vision-set ADR (see `specification/machines/001 VOLUME_III_ARTIFACT_MAP.md`). **Nothing in this document is ratified.** Volumes I and II are frozen and the ratified Product Architecture Manual is the single source of truth (ADR-001). This artifact is future/research-grade until filed by ADR. It **extends** the canonical vocabulary of `011 DOMAIN_MODEL.md`, `002 GLOSSARY.md`, and `003 TERMINOLOGY.md`; it introduces **no competing dictionary** and creates **no Evidence Type outside the ADR-017 controlled-change process**. Where this document and any ratified document appear to differ, the ratified document governs.

- **Module:** 4 of the Volume III artifact stack — the platform's epistemology (the "accepted new artifact: Truth & Claims Specification", `001 VOLUME_III_ARTIFACT_MAP.md`).
- **Position in filing order:** item 2, immediately after the vision-set ADR and before the Reality-side domain model (layer 1).
- **Audience:** the future implementation agent building the Reality / Perception / Intelligence graphs on top of the frozen Genesis platform.
- **Neutrality:** provider- and framework-neutral. Rails 8 is the delivery target, but no framework lock-in appears in the domain contracts below.
- **Working v0 (already in force, manual era):** the "language law" of `operations/ASSESSMENT_DELIVERY_GUIDE.md` Part 1 and Part 11, and the verified answer-path findings of `operations/AUTHORITY_ROADMAP.md`. This document is the implementation-grade successor to that language law.

---

## 1. Purpose

Define, to implementation precision, **how the platform decides what it is entitled to say, and how strongly.** Every customer-visible statement, every ranking-influencing signal, and every intelligence-layer inference resolves to one or more **Claims**. A Claim is a typed, provenance-bearing, confidence-bearing assertion about a subject, backed by immutable **Evidence**. This module specifies:

1. The **Claim** as a first-class epistemic record, and its precise relationship to the frozen **Evidence** contract, **Citation**, **Issue**, and **AIResponse** entities.
2. The **claim-class taxonomy** (12 classes) with per-class rules: who/what may produce it, evidence required, ranking influence, display permission, confidence model, expiry/revalidation.
3. The **provenance / authority hierarchy** (7 tiers) that gates claim classes and drives reconciliation.
4. The **SOURCE-ELICITATION-AND-VERIFY** rule as a hard invariant — assistant citations are **leads, not findings** — codifying the Clutch confabulation case as the canonical acceptance test.
5. The universal invariants: **every claim carries provenance and confidence**; **missing data is never synthesised** (PRULE-037); **composite scores are banned** (counts + intervals only); **two clocks** (retrieval vs corpus) govern honesty.
6. The **legal guardrails**: no republishing third-party machine statements as fact; regulated-vertical disclaimers; raw outputs private.
7. The binding **data model**: the `claim_record-v1` and `claim_provenance-v1` JSON schemas, with algorithms, a state machine, invariants, acceptance criteria, and open questions.

## 2. Scope and non-goals

**In scope.** The epistemic contract for assertions in all three graphs (Reality, Perception, Intelligence); the classification, provenance, confidence, verification, display, ranking-eligibility, expiry, and legal handling of every such assertion; the schemas and algorithms that enforce it.

**Out of scope (owned elsewhere; referenced, never redefined).**
- The immutable **Evidence** envelope, its closed `evidence_type` taxonomy, `data_classification`, and Validation Decision lifecycle — owned by `011 DOMAIN_MODEL.md` and `volume-i/SCORE_EVIDENCE_MODEL.md`; this module **consumes** it and MUST NOT alter it.
- The **AIResponse / Citation** generation contract `citation-policy-v1` — owned by `SCORE_EVIDENCE_MODEL.md`; this module binds to it for F1's own AI output and MUST NOT weaken it.
- The **confidence policy** numeric model and display bands — owned by OD-003 / `confidence-policy-v1`; this module reuses it verbatim.
- The **Source Registry** (lifecycle, parsers, retirement) — Volume III layer 4; supplies per-source authority and cadence metadata this module references.
- The **AI Measurement Set** — the OD-010 Measurement Set; gates external measurement and therefore Perception-graph Claim production.
- The **subject-side (Reality) domain model** (Business, Practitioner, Licence, Regulator, Industry, Brand) — Volume III layer 1; this module names its subject types abstractly via `subject_ref` and does not fix their internal schemas.

**Explicit non-goals.** No new Evidence Type. No new numeric confidence scale. No composite/blended "AI ranking score". No promise attached to the corpus clock. No resolution of the Finding-vs-Issue vocabulary collision (that is an ADR decision; see §5.9 and Open Questions).

## 3. Vocabulary boundary — how this module extends canon without competing

This module adds exactly **one new first-class concept, the Claim**, plus its provenance record, and **reuses everything else by name**. The following table is the binding cross-walk. A future implementer MUST treat the "Canonical owner" column as authoritative and this module as a consumer.

| Concept used here | Canonical owner | This module's relationship |
|---|---|---|
| Evidence, Evidence Payload, Evidence Provenance, Evidence Classification | `011 DOMAIN_MODEL.md`, `SCORE_EVIDENCE_MODEL.md`, `002 GLOSSARY.md` | A Claim **references** ≥0 Evidence records; a value-asserting Claim references ≥1 effectively-valid Evidence. Never mutates Evidence. |
| `evidence_type` closed taxonomy (`source_document`, `crawl_observation`, `parsed_content`, `external_measurement`, `verification_observation`, reserved `operator_attestation`) | ADR-017 controlled taxonomy | Claim class is **orthogonal** to Evidence Type (see §3.1). No new type is introduced. |
| `data_classification` (`public < internal < confidential < restricted`) | `SCORE_EVIDENCE_MODEL.md` | A Claim **inherits** the strongest classification of its backing Evidence. No declassification. |
| Confidence value + bands | OD-003, `confidence-policy-v1`, ADR-019 | Claim confidence uses this exact model (§8). |
| Citation, AIResponse, `citation-policy-v1` | `SCORE_EVIDENCE_MODEL.md`, PRULE-014 | An `AIGeneratedSummary` Claim from F1's own output is produced only through `citation-policy-v1`; a Citation ultimately grounds a customer-visible Claim (§10.4). |
| Issue | `011 DOMAIN_MODEL.md` | A Claim is **not** an Issue. An Issue is a prioritised discoverability deficiency; a Claim is an epistemic assertion. A Reality↔Perception Claim mismatch is one input a future evaluator may raise as an Issue. |
| Finding (research/FUTURE-WORKFLOW-001 sense) | `000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §5, FUTURE-WORKFLOW-001 | Used only in the audit-taxonomy sense (§11). The legal claim class in §5.9 is named `Finding-of-court-or-regulator` precisely to keep the three senses distinct. Collision unresolved by mandate. |
| Reality / Perception / Intelligence graphs; Observation; Intervention | ADR-012, VISION-001 | Claims are the nodes/edges these graphs are made of. The loop `Reality → Observation → Perception → Intervention → Intelligence` is the lifecycle context. |
| Intervention types (EntityIdentityConsolidation, StructuredDataCorrection, …) | FUTURE-WORKFLOW-001, `ASSESSMENT_DELIVERY_GUIDE.md` Part 8 | Referenced where a Claim state triggers a fix; not redefined. |

### 3.1 The load-bearing distinction: Claim Class is not Evidence Type

`evidence_type` describes **how an observation was captured** (a crawl, a parse, an external measurement, an ownership-verification probe). It is a **closed** taxonomy under ADR-017 and MUST NOT be extended by this module.

`claim_class` describes **the epistemic status of an assertion** derived from one or more Evidence records (is it verified, merely claimed, an opinion, an unadjudicated allegation, an AI confabulation?). It is a **new, orthogonal dimension** that lives on Claim nodes, not on Evidence.

Example: a single `crawl_observation` Evidence record of a business's own homepage can ground a `Claimed` NAP Claim, a `MarketingClaim` ("best in Melbourne") Claim, and an `Opinion` Claim (a testimonial quote), all at once. Same Evidence Type; three claim classes. This separation is what lets the platform be honest without inventing a competing dictionary.

## 4. The epistemic core

### 4.1 Where Claims live

Claims populate the three graphs (ADR-012):

- **Reality graph** — what is true about the subject, captured as ground truth. Seeded manually by the **Reality Card** (`ASSESSMENT_DELIVERY_GUIDE.md` Part 3): canonical NAP, registrations with numbers, services, locations, practitioners, confusable-entity list. Reality Claims are the yardstick against which Perception is judged.
- **Perception graph** — what a specific AI assistant, on a specific date, in a specific run, asserted about the subject. Perception Claims are almost always low-authority (Tier 7) and enter **unverified** by construction. **OD-010 gates their production**: no external measurement Claim exists until the Measurement Set is approved.
- **Intelligence graph** — what the platform has *learned* by comparing Reality and Perception across time and interventions: calibrated confidence, intervention outcomes (including failures), provider characteristics. Intelligence Claims are almost always `Inferred` or `Estimated` and are deterministically derived, never synthesised.

### 4.2 The Claim record (informal shape; formal schema in §12)

A Claim binds a **subject**, a **predicate** (a canonical attribute key), an **object value**, a **claim class**, **provenance** (≥0 provenance entries, each pointing at one Evidence record and one Source), a **confidence** (value + band), a **verification state**, and the derived **ranking-influence** and **display-permission** flags.

```
Claim := ⟨ subject_ref, predicate, object_value ⟩
         classified as   claim_class
         grounded by      provenance[]  → evidence_id[] (011 Evidence)
         graded by        confidence_value ∈ [0.0000,1.0000], confidence_band ∈ {low,medium,high}
         staged by        verification_state
         gated by         ranking_influence_allowed, display_permission
         bounded by        observed_at_utc, expires_at_utc
```

### 4.3 The four honesty axioms (binding on every Claim)

1. **Provenance-completeness.** Every Claim that asserts an object value MUST reference at least one effectively-valid Evidence record and record its authority tier. A value-asserting Claim with zero valid Evidence is rejected at creation (mirrors the frozen invariant "every persisted Issue MUST reference at least one effectively valid Evidence record", `SCORE_EVIDENCE_MODEL.md` Validation Rule 6). **No claim without evidence.**
2. **No synthesis.** Missing data MUST NEVER be fabricated, interpolated, or "reasonably assumed" to fill a gap. This is PRULE-037's "missing data MUST never be synthesized" applied to the epistemic layer. An absent value is `absent`, never a guessed value. An `Inferred` Claim may combine *present* Claims by deterministic rule; it may not invent inputs.
3. **Counts, not composites.** Quantitative outputs are **counts and confidence intervals with N displayed**, never blended scores. "Appeared in 2 of 12 runs" is lawful; "AI visibility score 6.4/10" is banned (`000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §4; `AUTHORITY_ROADMAP.md` claim discipline). `Estimated` Claims carry an explicit interval and method.
4. **Two clocks.** Every Perception Claim and every intervention-outcome Intelligence Claim is tagged with the clock it lives on: **retrieval** (site/registers/maps/reviews; propagates in days-to-weeks; re-measurable within the 90-day window) or **corpus** (parametric memory; model-training generations; unbounded). The corpus clock is **never promised** and never given a customer-facing timeline.

## 5. The claim-class taxonomy

Twelve classes. The set below **extends** the illustrative list in `001 VOLUME_III_ARTIFACT_MAP.md` (which named ten) by splitting `Review` out of `Opinion` and `RegulatoryAction` out of `Finding-of-court-or-regulator`, because their production rules and legal handling differ materially. The enum is **closed under controlled change**: adding a class is an ADR event.

`claim_class ∈ { Verified, Corroborated, Claimed, Inferred, Estimated, Opinion, Review, Allegation, FindingOfCourtOrRegulator, RegulatoryAction, MarketingClaim, AIGeneratedSummary }`

### 5.0 Per-class rules matrix (normative summary)

Legend — **Rank?** = may this class, on its own, influence a ranking-influencing signal or Contribution. **Show?** = default display permission (see §7 for the enum). **Conf. model** = how confidence is assigned (§8).

| # | Class | Who/what may produce | Evidence required | Min authority tier | Rank? | Show? | Conf. model | Expiry / revalidation |
|---|---|---|---|---|---|---|---|---|
| 1 | **Verified** | Platform verification pipeline only | ≥1 valid Evidence from Tier 1–2, **or** F1 `verification_observation`, **or** ≥2 independent Tier ≤3 reconciled to one value | 1–2 (or F1-verified) | Yes | show_as_fact (+source) | High (≥0.85) unless policy caps | Source-cadence; on expiry → downgrade to Corroborated/Claimed |
| 2 | **Corroborated** | Reconciliation engine | ≥2 independent Evidence, none contradicting | 3–4 | Yes (lower weight) | show_as_fact (+sources) | Medium–High | Source-cadence; re-reconcile |
| 3 | **Claimed** | First-party extraction | 1 first-party Evidence | 4 | No (needs corroboration to rank) | show_attributed ("as stated by the business") | Low–Medium | On re-crawl of the first-party Source |
| 4 | **Inferred** | Deterministic inference rules only (no LLM synthesis) | Lineage to ≥1 present Claim/Evidence | Inherited (capped) | Internal only by default | internal | Computed, capped below inputs | Recompute when any input changes |
| 5 | **Estimated** | Estimation policy (versioned) | Method + interval + N | Inherited | No (display-only unless OD-010 says otherwise) | show_attributed (interval + N) | Interval-based; point-as-fact forbidden | Recompute on new observations |
| 6 | **Opinion** | Extraction, always attributed | 1 Evidence carrying the statement | Any | No | show_attributed (never as platform fact) | Assertion-confidence only | On source change |
| 7 | **Review** | Review-platform Source extraction | 1 review Evidence | 6 | Aggregate only (count/recency), never individual content | show_attributed (aggregate) | Assertion-confidence; aggregate counts | Rolling; recount |
| 8 | **Allegation** | Extraction, flagged | 1 Evidence of the allegation | Any | Never positively | human-first; report only as verified public record | Existence-confidence, not truth-confidence | Re-check for adjudication/withdrawal |
| 9 | **FindingOfCourtOrRegulator** | Official-adjudication Source extraction | 1 official-record Evidence | 1–2 | Factual public record — constrained (legal gate) | human-first; show_as_fact only after legal gate | High (adjudicated) | Re-check for appeal/overturn |
| 10 | **RegulatoryAction** | Regulator Source extraction | 1 regulator-record Evidence | 1–2 | Factual public record — constrained (legal gate) | human-first; show_as_fact only after legal gate | High | Revalidate status (may be lifted) |
| 11 | **MarketingClaim** | First-party/marketing extraction | 1 Evidence carrying the claim | 4 | Never | show_attributed (labelled marketing) | n/a for truth | On re-crawl |
| 12 | **AIGeneratedSummary** | Any AI/LLM (measured assistants; F1's own AIResponse) | The captured AI output as Evidence | 7 | **Never** (until re-derived & re-classified) | hidden/internal until verified; then reclassified | Lead-only; no truth-confidence | Immediate on capture; superseded by verified re-derivation |

The subsections below give the binding detail per class.

### 5.1 Verified
- **Definition.** An assertion the platform is entitled to state as fact because it is grounded in top-tier authority or independent reconciliation.
- **Producer.** The platform verification pipeline **only**. No extraction path may write `Verified` directly; extraction produces `Claimed`/`Corroborated` candidates that the pipeline promotes.
- **Promotion predicate.** `Verified` requires **one** of: (a) ≥1 effectively-valid Evidence from a Tier 1 (government registry) or Tier 2 (professional regulator) Source whose payload asserts the object value at a resolvable `assertion_locator`; (b) an F1 `verification_observation` Evidence proving ownership/control (the frozen ownership-verification contract); (c) ≥2 **independent** (distinct `source_system`) Evidence records of Tier ≤3 reconciled to exactly one normalised value with zero contradicting Evidence.
- **Ranking.** May influence ranking-relevant signals and Contributions.
- **Display.** `show_as_fact`, source always attributed.
- **Confidence.** Numeric via `confidence-policy-v1`; a promotion policy MAY floor it in the High band but MUST NOT assert `1.0000` for anything that can go stale.
- **Expiry.** Bound to the source class cadence (§9). On expiry, the pipeline **downgrades** (never deletes) to `Corroborated` or `Claimed` and recomputes any dependent signal.

### 5.2 Corroborated
- **Definition.** Consistent across independent mid-tier sources, but neither top-tier-authoritative nor F1-verified.
- **Producer.** Reconciliation engine.
- **Predicate.** ≥2 independent Evidence records of Tier 3–4, agreeing after normalisation, none contradicting.
- **Ranking.** Yes, at lower weight than `Verified`.
- **Display.** `show_as_fact` with all corroborating sources listed.
- **Note.** A single contradicting Evidence of equal-or-higher tier moves the Claim to `verification_state = contradicted` and blocks ranking until reconciled.

### 5.3 Claimed
- **Definition.** A first-party assertion (the business's own site/profile) not yet independently corroborated. This is the honest default for most freshly-extracted business facts.
- **Producer.** First-party extraction from a Source the subject controls.
- **Ranking.** **No** by itself. A `Claimed` fact may be *shown* ("as stated by the business") but MUST be corroborated before it influences a ranking signal — this is the entity-resolution discipline of the machine consensus applied epistemically.
- **Display.** `show_attributed`, phrased as first-party assertion.

### 5.4 Inferred
- **Definition.** Derived by the platform from other **present** Claims/Evidence via a deterministic, versioned rule (e.g., service area inferred from the set of literally-titled suburb pages; entity-resolution status inferred from NAP consistency).
- **Producer.** Deterministic inference rules **only**. **No LLM synthesis** — an inference is a pure function of its declared inputs (PRULE-037; and `citation-policy-v1`'s no-free-text discipline). If a rule would need an absent input, the output is `absent`, not inferred.
- **Lineage.** MUST record `derived_from_claim_ids` and the `inference_rule_version`. Confidence is capped at or below the minimum confidence of its inputs.
- **Display.** `internal` by default; a specific rule may be promoted to customer-visible only with an explicit display policy.

### 5.5 Estimated
- **Definition.** A quantitative approximation with an explicit method and an explicit interval (e.g., "review count in the 40–60 range on the correct listing"; "typical fee band").
- **Rule.** MUST carry `estimation_method_version`, an interval (`lower`, `upper`), and N. A point value presented as fact is **forbidden** (composite-score ban corollary). Wilson intervals are the reference method for proportions (`ASSESSMENT_DELIVERY_GUIDE.md` Part 6).
- **Ranking.** Display-only unless an approved OD-010 measurement policy explicitly authorises an interval-aware signal at Instrument grade (Open Question).

### 5.6 Opinion
- **Definition.** A subjective evaluative statement attributed to a named or aggregate source ("clients describe them as approachable").
- **Rule.** **Always attributed; never asserted as the platform's own fact.** A third party's opinion about a third party is never republished as fact (`ASSESSMENT_DELIVERY_GUIDE.md` Part 11.2).
- **Confidence.** Only **assertion-confidence** (how sure we are the source made the statement), never **truth-confidence**.

### 5.7 Review
- **Definition.** A first-person customer review on a review platform — a specialised, high-volume `Opinion` with distinct handling.
- **Rule.** Individual review *content* is never republished as fact and never republished as disparagement. Only **aggregate** signals (count, recency, response rate on the **correct** listing) may inform a signal, and only as counts. Reviews landing on the wrong listing are an Entity Conflation seed, not a fact about the subject.

### 5.8 Allegation
- **Definition.** An unproven accusation (a complaint, an adverse claim not adjudicated).
- **Rule.** May **never** positively influence ranking. Handled human-first (`ASSESSMENT_DELIVERY_GUIDE.md` Part 11.3): surfaced verbally to the client first, and appearing in a customer-visible artifact only as **verified public record with source and date**. Confidence is **existence-confidence** (the allegation exists), never truth-confidence (the allegation is true).

### 5.9 FindingOfCourtOrRegulator
- **Definition.** An adjudicated determination by a court or regulator (AustLII / tribunal decision; AHPRA tribunal outcome; ASIC banned-and-disqualified record).
- **Vocabulary hazard (recorded, not resolved).** This class uses the word **Finding** in its **legal** sense. That word already carries two other senses in the repository: (a) `003 TERMINOLOGY` forbids "finding" as a variant of **Issue**; (b) FUTURE-WORKFLOW-001 defines **Finding** as a first-class intervention-lifecycle object. **Three senses, one word.** Per mandate this collision is **not resolved here** — it is an ADR decision (vision-set filing, `001 VOLUME_III_ARTIFACT_MAP.md` filing order item 1). Candidate disambiguation for the ADR: keep `Issue` for the deficiency object, keep `Finding` for the FUTURE-WORKFLOW-001 object, and name this legal class `AdjudicatedDetermination` (recorded as a rename candidate; **not adopted** here — the class ships as `FindingOfCourtOrRegulator` until the ADR rules).
- **Producer.** Extraction from an official adjudication Source (Tier 1–2).
- **Ranking / Display.** Factual public record, but subject to the **legal gate** (§11.6): `display_permission` may not be set to `show_as_fact` for this class without the counsel sign-off recorded in Open Questions. Handled human-first.
- **Expiry.** Re-checked for appeal/overturn; an overturned determination transitions to `contradicted`/`withdrawn`.

### 5.10 RegulatoryAction
- **Definition.** A regulator-issued action or sanction distinct from a court finding: licence suspension, ban, enforceable undertaking, condition on registration.
- **Rule.** As §5.9 for legal gating and human-first handling, plus **status revalidation** — regulatory actions can be lifted; a stale "suspended" Claim is a Temporal Hallucination waiting to happen and MUST be revalidated on cadence.

### 5.11 MarketingClaim
- **Definition.** A promotional self-assertion ("award-winning", "Melbourne's #1", "trusted by thousands").
- **Rule — the Authority Spoofing guard.** A `MarketingClaim` MUST NEVER be treated as regulatory, authoritative, or independent validation. This is the direct codification of the **Authority Spoofing** finding class (`000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §5): marketing/promotional content treated as authority is a defect, not a signal. Never influences ranking; displayed only as labelled marketing.

### 5.12 AIGeneratedSummary
- **Definition.** Any statement produced by an AI assistant or LLM. This includes (a) the third-party assistants VIDET measures, and (b) F1's own governed `AIResponse`.
- **The confabulation rule (hard invariant — see §6).** An `AIGeneratedSummary` is a **LEAD, never a finding.** It enters the system flagged `self_reported`/`unverified`, at authority Tier 7. It **may never influence ranking** and **may never be shown to the user as fact** in this class. To become usable, its constituent factual assertions MUST be **independently re-derived** from non-AI Evidence and **re-classified** as the appropriate class (`Verified`/`Corroborated`/`Claimed`/…). Only the re-derived Claim — never the `AIGeneratedSummary` itself — may reach `show_as_fact`.
- **F1's own AI output.** When (b) applies, the `AIGeneratedSummary` is produced **only** through `citation-policy-v1` (PRULE-014): every customer-visible generated value is in the claim manifest, and every claim carries a verified Citation to valid Evidence before publication. F1's AI never emits an unverified customer-visible fact; the class exists so that even F1's own generated prose is epistemically labelled and traceable.
- **Handling divergence (Open Question).** Class (a) and class (b) share `claim_class = AIGeneratedSummary` but differ sharply downstream; a handling flag or sub-class ruling is flagged for ADR.

## 6. The SOURCE-ELICITATION-AND-VERIFY invariant (hard)

> **INVARIANT SEV-1.** Any assertion whose provenance is an AI assistant's self-report about its own sources or about a third party enters the system as a **LEAD**, at authority Tier 7, with `verification_state = self_reported` and `claim_class = AIGeneratedSummary`. It MUST NOT surface in a report, a score input, a ranking signal, or an intervention plan until each factual sub-assertion is **independently verified** against non-AI Evidence and re-expressed as a new, separately-classified Claim. Nothing `self_reported` is ever averaged, ranked, or displayed as fact.

This is the epistemic spine of the platform and the difference between VIDET and the "AI visibility" snake-oil market. It operationalises two empirical facts (`002 ANSWER_PATH_AND_AUTHORITY_SPEC.md` §1; `AUTHORITY_ROADMAP.md`): assistant introspection about sourcing is partly confabulated, and observation outranks interrogation.

### 6.1 The canonical acceptance test — the Clutch confabulation case (28 Jul 2026)

The verification pipeline MUST pass this test, drawn verbatim from the verified answer-path investigation (`AUTHORITY_ROADMAP.md`, "Refuted — the confabulation catch"; `ASSESSMENT_DELIVERY_GUIDE.md` Part 5 step 6):

- **Setup.** An assistant (ChatGPT) cited a **real** URL (a Clutch "Melbourne AI" page — the URL resolves, HTTP 200, nothing hallucinated at URL level) as **supporting** the claim that certain firms (Synap, Integral Mind, Lumen & Lever) are top providers.
- **Truth.** That page contains **none** of those firms; its listed firms are unrelated dev shops (Dotsquares, DianApps, xfive).
- **Required system behaviour.** The pipeline MUST classify the elicited citation as `AIGeneratedSummary` / `self_reported`; MUST attempt independent verification by fetching the cited page and checking whether the page's content actually asserts the attributed value at a resolvable `assertion_locator`; MUST detect the mismatch (**real URL, wrong contents**); MUST set `verification_state = contradicted` for the attributed claim and record a **Citation-Accuracy failure**; and MUST **prevent** the assertion from becoming a customer-visible finding or a ranking input.
- **Test oracle.** *A cited source that exists but does not support its attributed statement MUST NOT yield a `Verified` or `Corroborated` Claim, MUST yield a Citation-Accuracy defect, and MUST be reported (if at all) only as "assistant X cited page Y, which does not contain Z" — never as "Z is true."*

This case is the single most important fixture in the module's test suite. Any implementation that would let a real-URL/wrong-contents citation promote to a shown-as-fact Claim is **non-conformant**.

### 6.2 Citation-Accuracy as a first-class metric

Reusing the manual-era definition (`ASSESSMENT_DELIVERY_GUIDE.md` Part 6): **Citation Accuracy Rate** = of the URLs/sources an assistant cites about the subject, the share that **exist AND support the attributed claim**. The verify gate computes, per elicited citation, a boolean `cited_url_resolves` and a boolean `content_supports_claim`; the pair `(true, false)` is the confabulation signature and is quarantined as a `defective_observation` (Part 5 step 7) — reported, never averaged.

## 7. Display permission and ranking influence (derived, never hand-set)

Both flags are **computed** from `(claim_class, verification_state, authority_tier, legal_flags)` by versioned policy; an implementer MUST NOT set them ad hoc.

**`display_permission ∈ { hidden, internal, show_attributed, show_as_fact }`**
- `hidden` — not shown anywhere (e.g., any `self_reported` `AIGeneratedSummary`; quarantined Evidence).
- `internal` — visible to platform operators only (most `Inferred` Claims; raw Perception observations before aggregation).
- `show_attributed` — customer-visible **with explicit attribution** and, where applicable, an interval + N ("as stated by the business", "1 review platform, 47 reviews", "ChatGPT, observed 2026-07-27").
- `show_as_fact` — customer-visible as the platform's own asserted fact. Reachable **only** by `Verified`/`Corroborated`, and by `FindingOfCourtOrRegulator`/`RegulatoryAction` **after** the §11.6 legal gate.

**`ranking_influence_allowed ∈ { true, false }`** — true only for `Verified` and `Corroborated` (and the constrained legal classes after gating), false for everything else. `AIGeneratedSummary` and `MarketingClaim` are hard `false` in all states.

**Raw-outputs-private rule.** Raw machine outputs stay private (`ASSESSMENT_DELIVERY_GUIDE.md` Part 11.1). A stored `AIGeneratedSummary` Evidence payload is at least `confidential`; the Claim over it is `hidden` until re-derivation.

## 8. Confidence model (binds to OD-003 / `confidence-policy-v1`)

Claim confidence uses the **ratified** model verbatim; this module adds no new scale.

- **Storage.** `confidence_value` on `0.0000..1.0000`, round-half-up to four decimals, under policy `confidence-policy-v1`.
- **Display bands (OD-003, ADR-019).** Low `[0.0000, 0.6000)`, Medium `[0.6000, 0.8500)`, High `[0.8500, 1.0000]`.
- **Missing/invalid.** Recorded explicitly, **displays Low**, and — where the Claim feeds an evaluator — routes the derived Issue to `review_required` (OD-003 ratified behaviour). A Claim MUST NOT silently omit confidence.
- **Two confidence quantities (§Open Question).** For `Opinion`/`Review`/`Allegation`, the meaningful quantity is **assertion-confidence** (that the statement was made), not **truth-confidence**. This module stores `confidence_basis ∈ { authority, corroboration, inference, estimation_interval, assertion_only, existence_only }` alongside the value so the number is never read as a truth probability it isn't. The single-field mapping to OD-003 for these classes is flagged for owner ruling.
- **No composite.** Confidence is a per-Claim property; it is **never** blended across Claims into an aggregate "score". Aggregate outputs are counts + intervals (§4.3 axiom 3).
- **AI-derived confidence.** MUST NOT bypass deterministic policy mapping (OD-003 AI Implications). An assistant's stated self-confidence is itself an `AIGeneratedSummary` and is a lead, not a confidence value.

## 9. Provenance and the authority hierarchy

### 9.1 The seven-tier authority hierarchy

Every provenance entry records an `authority_tier` (1 = strongest). Tiers gate the maximum claim class an entry can support and drive reconciliation weighting. This encodes the ChatGPT truth hierarchy (`001 VOLUME_III_ARTIFACT_MAP.md` layer 2) and the regulated-vertical evidence inversion (`000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §2.4).

| Tier | Authority class | Examples | Max class it can ground (alone) |
|---|---|---|---|
| 1 | **Government registry** | ABN Lookup, ASIC, Companies House, state building authorities (VBA/QBCC), ACECQA | Verified |
| 2 | **Professional regulator** | AHPRA, TPB, ASIC Financial Advisers Register + AFS, state law society/bar, MFAA/FBAA | Verified |
| 3 | **Official directory** | aidirectory.industry.gov.au, Starting Blocks, manufacturer authorised-installer listings | Corroborated (Verified only via reconciliation) |
| 4 | **First-party** | the subject's own verified website/profile, schema.org/JSON-LD they control | Claimed |
| 5 | **Independent source** | reputable editorial, news, industry-association pages, "best-of" roundups | Corroborated (with a second independent source) |
| 6 | **Review platform** | Google, Yelp, Trustpilot | Review / Opinion (aggregate only) |
| 7 | **AI extraction** | assistant self-reports, LLM summaries | AIGeneratedSummary (lead only) |

**Vertical inversion (binding).** In regulated verticals (accounting, legal, health, finance) Tier 1–2 register status **gates everything** and Tier 6 reviews are secondary; abstention/shortlists replace single winners. In unregulated services (agencies, coaches, trades) Tier 4–6 (portfolio, case studies, reviews) carry more weight. The authority-policy MUST be **vertical-aware**; the per-vertical policies (Volume III layer 5) supply the weights. No universal weighting is asserted here.

### 9.2 Reconciliation rule (deterministic)

When multiple provenance entries assert values for one `(subject_ref, predicate)`:
1. Normalise each value (NAP normalisation, casing, whitespace, phone/URL canonicalisation).
2. Group by normalised value.
3. **Agreement:** if the highest-authority group has no equal-or-higher-tier contradicting group, and it satisfies the promotion predicate (§5.1/§5.2), promote to `Verified`/`Corroborated`.
4. **Contradiction:** if two groups of equal-or-higher tier disagree, set `verification_state = contradicted`, block ranking, and (in the assessment context) raise this as an **Entity Conflation** or **Temporal Hallucination** candidate for an evaluator — never auto-pick a winner.
5. **No synthesis:** the reconciled value is always one of the observed normalised values; the engine never manufactures a "blended" value.

## 10. Binding to the frozen platform

### 10.1 To the Evidence model (`011 DOMAIN_MODEL.md`, `SCORE_EVIDENCE_MODEL.md`)
- A Claim references Evidence by `evidence_id`; a value-asserting Claim requires ≥1 **effectively-valid** Evidence (latest Validation Decision = `valid`).
- A Claim **inherits** the strongest `data_classification` among its backing Evidence; **no declassification** (unknown → `restricted`).
- When backing Evidence transitions away from `valid` (quarantined/invalid), every dependent Claim MUST recompute: value-asserting Claims lose that provenance entry, may drop class, and — if they fed a signal — trigger the same suppression/recalculation cascade the frozen model already defines for Contributions and Recommendation Artifacts.
- Claims introduce **no new Evidence Type** and write nothing into the Evidence envelope.

### 10.2 To OD-003 confidence
- Verbatim reuse (§8). ADR-019 is the integration point.

### 10.3 To PRULE-037 (no synthesis)
- Axiom 2 (§4.3) is PRULE-037 lifted to the claim layer: absent → `absent`, never fabricated. Inference is pure over present inputs.

### 10.4 To `citation-policy-v1` (PRULE-014)
- F1's own customer-visible AI output is an `AIGeneratedSummary` produced only through `citation-policy-v1`: claim manifest complete, every claim covered by a **verified** Citation to valid Evidence, `prohibited_advisory_domain` and provider-gate enforced. The Citation is the machine-checkable link from a shown Claim to its Evidence. A Claim that would be shown as fact but lacks a verified Citation (for AI-generated content) is non-publishable, exactly as the frozen contract requires.
- The `citation-policy-v1` output scanner order (`prompt_instruction_leakage`, `secret_or_personal_data`, `prohibited_advisory_domain`, `unsafe_external_action`, `output_schema_invalid`) is inherited unchanged; a Claim never weakens it.

### 10.5 To OD-010 (measurement gating)
- Perception-graph Claims are external-measurement outputs and are **gated by the OD-010 Measurement Set**. Until OD-010 is approved, Perception Claims are produced only in the manual assessment context and never as automated `external_measurement` Evidence. The corpus clock is never promised.

### 10.6 To the audit / findings taxonomy
- The six machine-consensus finding classes (Absence, Entity Conflation, Temporal Hallucination, Geographic Boundary Breach, Authority Spoofing, Anchoring Fragility) plus Defective Observation are the *consumers* of Claims: each is a comparison between Reality Claims and Perception Claims (§11 below). This module supplies the Claims; the assessment/evaluation layer raises the findings.

## 11. Legal and ethics guardrails (non-negotiable; codifies `ASSESSMENT_DELIVERY_GUIDE.md` Part 11)

1. **Raw outputs private.** Raw machine outputs stay private; only verified, attributed Claims reach a report. Backing `AIGeneratedSummary` Evidence is ≥ `confidential`.
2. **No republishing third-party machine statements as fact.** "Assistant X named [competitor] in 11 of 12 runs" is a reportable **count**; the assistant's *opinions* about that competitor are `Opinion`/`AIGeneratedSummary` and are **never** republished as fact. This is the hardest line in the module.
3. **Adverse records human-first.** `Allegation`, `FindingOfCourtOrRegulator`, `RegulatoryAction` about the client are surfaced verbally first and appear in an artifact only as verified public record with source and date.
4. **Regulated-vertical disclaimer.** Every artifact touching a regulated vertical carries: *"This is a measurement of AI assistant behaviour, not professional, financial, legal or medical advice."* Personalised legal/tax/compliance conclusions are prohibited (inherited from the frozen Recommendation contract's `prohibited_advisory_domain`).
5. **No guarantees.** No guarantee of mention, position, or timing — ever, anywhere, including sales copy. The corpus clock is never promised.
6. **Legal-class display gate.** `FindingOfCourtOrRegulator` and `RegulatoryAction` may not reach `display_permission = show_as_fact` without the counsel sign-off recorded in Open Questions, evaluated against the OD-011 markets and the counsel brief.
7. **Tenant isolation.** Claims are Organization- and Project-scoped; evidence folders are never commingled (OD-011 governs production customer-data use).

## 12. Data model — schemas

All identifiers are opaque, immutable, globally unique within namespace (DM-REQ-005). Timestamps are `*_at_utc`. Digests are lowercase 64-char SHA-256. All snake_case. **Proposed namespaces (ADR to confirm):** Claim `clm_`, Claim Provenance `clp_`. Claim is modelled as an **auxiliary lifecycle-bearing record** in the style of Evidence (`evd_id`), not asserted as a new DM-REQ-001 core entity — that classification is an Open Question for the vision-set ADR.

### 12.1 `claim_record-v1`

```json
{
  "$schema": "https://videt/spec/vol3/claim_record-v1.json",
  "type": "object",
  "required": [
    "claim_id", "schema_version", "organization_id", "project_id",
    "graph", "subject_ref", "predicate", "object_value", "object_value_sha256",
    "claim_class", "provenance", "evidence_refs", "authority_tier",
    "confidence_value", "confidence_band", "confidence_basis",
    "verification_state", "ranking_influence_allowed", "display_permission",
    "data_classification", "observed_at_utc", "captured_at_utc",
    "first_seen_at_utc", "last_confirmed_at_utc",
    "policy_versions", "state_version", "correlation_id"
  ],
  "properties": {
    "claim_id":        { "type": "string", "description": "opaque immutable id, namespace clm_" },
    "schema_version":  { "type": "string", "const": "claim_record-v1" },
    "organization_id": { "type": "string" },
    "project_id":      { "type": "string" },
    "graph":           { "enum": ["reality", "perception", "intelligence"] },

    "subject_ref": {
      "type": "object",
      "required": ["subject_type", "subject_id", "subject_label"],
      "properties": {
        "subject_type": { "enum": ["organization","practitioner","source","service","location","brand","competitor_entity"] },
        "subject_id":   { "type": "string" },
        "subject_label":{ "type": "string" },
        "confusable_of":{ "type": ["string","null"], "description": "clm_/subject_id this may be conflated with (Reality Card confusable list)" }
      }
    },

    "predicate":         { "type": "string", "description": "canonical attribute key, e.g. nap.phone, registration.ahpra, service.offered, service_area.suburb, mention.assistant, position.rank, review.count" },
    "object_value":      { "description": "normalized typed value; JSON null only when verification_state=absent" },
    "object_value_sha256": { "type": "string" },
    "value_normalization_version": { "type": "string" },

    "claim_class": {
      "enum": ["Verified","Corroborated","Claimed","Inferred","Estimated","Opinion",
               "Review","Allegation","FindingOfCourtOrRegulator","RegulatoryAction",
               "MarketingClaim","AIGeneratedSummary"]
    },

    "evidence_refs": {
      "type": "array",
      "items": { "type": "string", "description": "evidence_id (011 Evidence); MUST be effectively valid for a value-asserting Claim" },
      "minItems": 0
    },
    "provenance": {
      "type": "array",
      "items": { "$ref": "claim_provenance-v1" },
      "minItems": 0
    },
    "authority_tier": { "type": "integer", "minimum": 1, "maximum": 7, "description": "strongest (lowest) tier among provenance" },

    "confidence_value": { "type": "number", "minimum": 0.0, "maximum": 1.0, "description": "0.0000..1.0000, round-half-up 4dp, confidence-policy-v1" },
    "confidence_band":  { "enum": ["low","medium","high"] },
    "confidence_basis": { "enum": ["authority","corroboration","inference","estimation_interval","assertion_only","existence_only","missing"] },
    "estimation": {
      "type": ["object","null"],
      "properties": {
        "lower": { "type": "number" }, "upper": { "type": "number" },
        "n": { "type": "integer" }, "method_version": { "type": "string" }
      }
    },

    "verification_state": {
      "enum": ["candidate","self_reported","corroborating","verified","contradicted","absent","expired","withdrawn"]
    },
    "ranking_influence_allowed": { "type": "boolean" },
    "display_permission": { "enum": ["hidden","internal","show_attributed","show_as_fact"] },

    "two_clock_layer": { "enum": ["retrieval","corpus","not_applicable"] },
    "legal_flags": {
      "type": "array",
      "items": { "enum": ["regulated_vertical","adverse_record","third_party_statement","marketing","defamation_risk","human_first_required"] }
    },
    "data_classification": { "enum": ["public","internal","confidential","restricted"], "description": "inherited strongest; no declassification; unknown => restricted" },

    "lineage": {
      "type": ["object","null"],
      "properties": {
        "derived_from_claim_ids": { "type": "array", "items": { "type": "string" } },
        "inference_rule_version": { "type": "string" },
        "supersedes_claim_id":    { "type": ["string","null"] }
      }
    },

    "observed_at_utc":      { "type": "string", "format": "date-time" },
    "captured_at_utc":      { "type": "string", "format": "date-time" },
    "first_seen_at_utc":    { "type": "string", "format": "date-time" },
    "last_confirmed_at_utc":{ "type": "string", "format": "date-time" },
    "expires_at_utc":       { "type": ["string","null"], "format": "date-time" },
    "revalidation_policy_version": { "type": ["string","null"] },

    "policy_versions": {
      "type": "object",
      "required": ["classification_policy","authority_policy","confidence_policy","verify_policy"],
      "properties": {
        "classification_policy": { "type": "string" },
        "authority_policy":      { "type": "string" },
        "confidence_policy":     { "type": "string", "const": "confidence-policy-v1" },
        "verify_policy":         { "type": "string" }
      }
    },
    "state_version":  { "type": "integer" },
    "correlation_id": { "type": "string" }
  }
}
```

### 12.2 `claim_provenance-v1`

```json
{
  "$schema": "https://videt/spec/vol3/claim_provenance-v1.json",
  "type": "object",
  "required": [
    "provenance_id", "schema_version", "claim_id", "evidence_id",
    "source_ref", "authority_tier", "collection_method", "collector_version",
    "observed_at_utc", "captured_at_utc", "assertion_locator",
    "self_reported", "verified", "reconciliation_decision"
  ],
  "properties": {
    "provenance_id":  { "type": "string", "description": "opaque immutable id, namespace clp_" },
    "schema_version": { "type": "string", "const": "claim_provenance-v1" },
    "claim_id":       { "type": "string" },
    "evidence_id":    { "type": "string", "description": "exactly one 011 Evidence record backing this entry" },

    "source_ref": {
      "type": "object",
      "required": ["source_system","source_kind"],
      "properties": {
        "source_system":   { "type": "string", "description": "provenance source_system, verbatim from Evidence Provenance" },
        "source_id":       { "type": ["string","null"] },
        "source_url_sha256": { "type": ["string","null"], "description": "digest of the canonical cited URL; never store PII in the URL" },
        "source_kind":     { "enum": ["government_registry","professional_regulator","official_directory","first_party","independent_source","review_platform","ai_extraction"] }
      }
    },
    "authority_tier": { "type": "integer", "minimum": 1, "maximum": 7 },

    "collection_method": { "type": "string" },
    "collector_version": { "type": "string" },
    "observed_at_utc":   { "type": "string", "format": "date-time" },
    "captured_at_utc":   { "type": "string", "format": "date-time" },

    "assertion_locator": { "type": "string", "description": "where in the immutable Evidence payload the value is asserted (selector/offset/anchor); MUST resolve inside the payload" },

    "self_reported": { "type": "boolean", "description": "true for AI-elicited citations; forces claim_class=AIGeneratedSummary and verification_state=self_reported until verified" },
    "cited_url_resolves":     { "type": ["boolean","null"], "description": "verify-gate: did the cited URL resolve" },
    "content_supports_claim": { "type": ["boolean","null"], "description": "verify-gate: does the resolved content assert the attributed value at assertion_locator" },

    "verified":         { "type": "boolean" },
    "verified_at_utc":  { "type": ["string","null"], "format": "date-time" },
    "verifier_identity":{ "type": ["string","null"] },

    "corroborates": { "type": "array", "items": { "type": "string" }, "description": "provenance_ids agreeing after normalization" },
    "contradicts":  { "type": "array", "items": { "type": "string" }, "description": "provenance_ids disagreeing" },
    "reconciliation_decision": { "enum": ["matched","conflict","superseded","pending"] }
  }
}
```

## 13. Algorithms (pseudocode; deterministic, provider-neutral)

### 13.1 The verify gate (SOURCE-ELICITATION-AND-VERIFY)

```
function verify_provenance(p: Provenance) -> Provenance:
    if p.source_ref.source_kind == "ai_extraction" or p.self_reported:
        # AI-elicited: a LEAD, never a finding
        p.self_reported = true
        p.cited_url_resolves     = fetch_resolves(p.source_ref.source_url_sha256)   # dereference the ACTUAL cited URL
        if not p.cited_url_resolves:
            p.verified = false; p.reconciliation_decision = "conflict"
            emit CitationAccuracyDefect(reason="url_unresolved"); return p
        content = fetch_payload(p.evidence_id)                                       # the captured page as Evidence
        p.content_supports_claim = payload_asserts_value(content, p.assertion_locator, claim.object_value)
        if not p.content_supports_claim:
            # THE CLUTCH SIGNATURE: real URL, wrong contents
            p.verified = false; p.reconciliation_decision = "conflict"
            emit CitationAccuracyDefect(reason="content_mismatch"); return p
        # even when it does support, an AI lead is only ever a corroboration INPUT,
        # never self-promoting: it must be re-derived from a non-AI source
        p.verified = true; p.reconciliation_decision = "matched"; return p
    else:
        p.verified = payload_asserts_value(fetch_payload(p.evidence_id),
                                           p.assertion_locator, claim.object_value)
        p.reconciliation_decision = p.verified ? "matched" : "conflict"; return p
```

### 13.2 Classify + gate (produces a Claim)

```
function classify(subject, predicate, value, provenance_set) -> Claim:
    for p in provenance_set: verify_provenance(p)
    best_tier = min(p.authority_tier for p in provenance_set)         # 1 strongest

    # NO SYNTHESIS: never fabricate a value
    if value is ABSENT: return Claim(class=none, verification_state="absent", value=null)

    non_ai = [p for p in provenance_set if p.source_ref.source_kind != "ai_extraction"]
    verified_non_ai = [p for p in non_ai if p.verified]

    if any(p from ai_extraction and unverified): 
        base_class = "AIGeneratedSummary"; state = "self_reported"

    class = choose_class(best_tier, verified_non_ai, predicate, vertical_policy)
    # choose_class encodes §5/§9: Tier1-2 -> Verified; >=2 independent verified -> Verified/Corroborated;
    # single first-party -> Claimed; review platform -> Review/Opinion; marketing text -> MarketingClaim;
    # court/regulator source -> FindingOfCourtOrRegulator/RegulatoryAction; ai only -> AIGeneratedSummary

    conf = confidence_policy_v1(class, verified_non_ai, corroboration_count)          # OD-003 model
    band = band_of(conf)                                                             # Low/Med/High per OD-003
    if conf is MISSING: conf=explicit_missing; band="low"; route_issue="review_required"

    rank = class in {"Verified","Corroborated"}                                      # legal classes gated separately
    display = display_policy(class, state, best_tier, legal_flags)                   # §7
    classification = strongest_classification(evidence_of(provenance_set))           # no declassification
    return Claim(subject, predicate, value, class, provenance_set, best_tier,
                 conf, band, state, rank, display, classification, ...)
```

### 13.3 Expiry / revalidation

```
on schedule(revalidation_policy):
    for claim where now_utc >= claim.expires_at_utc:
        re_observe(claim)                       # re-crawl / re-query the same source class
        if re_confirmed:  claim.last_confirmed_at_utc = now; claim.expires_at_utc = now + cadence(claim)
        elif contradicted: claim.verification_state = "contradicted"; recompute_dependents(claim)
        elif gone:        claim.verification_state = "expired";  downgrade(claim)   # Verified -> Corroborated/Claimed
        # NEVER extend expiry by assumption; a stale value is expired, not re-asserted
```

## 14. Claim verification state machine

```
        ┌─────────────┐  first evidence           ┌──────────────┐
        │  (create)   │ ────────────────────────▶ │  candidate   │
        └─────────────┘                            └──────┬───────┘
                                                          │
        ai-elicited / self_reported ──────────────▶ ┌─────▼────────┐
                                                     │ self_reported│──verify fail (Clutch)──▶ contradicted
                                                     └─────┬────────┘
                                                verify ok  │ (still a lead; must re-derive)
                                                           ▼
        second independent evidence ─────────────▶ ┌──────────────┐
                                                     │ corroborating│
                                                     └─────┬────────┘
                                promotion predicate met    │        equal-tier conflict
                                                           ▼               │
                                                     ┌──────────┐          ▼
                                                     │ verified │     ┌───────────────┐
                                                     └────┬─────┘     │  contradicted │
                            expiry / source gone         │           └───────────────┘
                                                         ▼
                                                   ┌──────────┐   subject withdraws / legal
                                                   │ expired  │        │
                                                   └──────────┘        ▼
                                                              ┌──────────────┐
        no value observed ───────────────────────────────────│  withdrawn   │  (terminal)
                                                   absent      └──────────────┘
```

- `absent` is not an error and never a fabricated value.
- `verified`/`corroborating` can fall back to `contradicted` on new conflicting evidence.
- `withdrawn` and terminal legal outcomes are terminal; a corrected observation is a **new** Claim (immutability, mirroring Evidence).

## 15. Invariants (test-validated; each maps to an acceptance criterion)

- **INV-1 (no claim without evidence).** A value-asserting Claim has ≥1 effectively-valid Evidence; creation otherwise rejects.
- **INV-2 (SEV-1 / verify gate).** No `self_reported` provenance yields `ranking_influence_allowed=true` or `display_permission=show_as_fact`; the Clutch fixture (real URL, wrong contents) yields a Citation-Accuracy defect and `contradicted`.
- **INV-3 (no synthesis).** No Claim's `object_value` is any value absent from its provenance; absent inputs yield `absent`, never a guess.
- **INV-4 (no composite).** No customer-visible numeric aggregates a blended score across Claims; quantitative outputs carry N and, for `Estimated`, an interval.
- **INV-5 (classification inheritance).** A Claim's `data_classification` equals the strongest of its Evidence; no path lowers it; unknown → `restricted`.
- **INV-6 (confidence law).** `confidence_value` conforms to `confidence-policy-v1`; band boundaries equal OD-003; missing confidence displays Low and routes any derived Issue to `review_required`.
- **INV-7 (authority gate).** No provenance entry grounds a class above its tier ceiling (§9.1); `MarketingClaim` and `AIGeneratedSummary` never set `ranking_influence_allowed=true`.
- **INV-8 (two clocks).** Every Perception and intervention-outcome Claim carries `two_clock_layer`; nothing customer-facing attaches a timeline to `corpus`.
- **INV-9 (legal handling).** `Allegation`/`FindingOfCourtOrRegulator`/`RegulatoryAction` Claims carry `human_first_required`; none reaches `show_as_fact` without the legal gate; no third-party `Opinion`/`AIGeneratedSummary` is republished as fact.
- **INV-10 (Evidence cascade).** Backing-Evidence transition away from `valid` recomputes dependent Claims and cascades suppression/recalculation exactly as the frozen Contribution/Recommendation model requires.
- **INV-11 (immutability).** A Claim's identity, subject, predicate, and the digests of its backing Evidence are immutable; a correction is a new Claim linked by `supersedes_claim_id`.
- **INV-12 (citation binding).** An F1-AI-generated `show_as_fact` Claim has a `citation-policy-v1`-verified Citation to valid Evidence for every manifest value.

## 16. Acceptance criteria

- **AC-TC-01.** Given Evidence from ABN Lookup (Tier 1) asserting a phone number at a resolvable locator, the pipeline produces a `Verified` NAP Claim with `ranking_influence_allowed=true`, `display_permission=show_as_fact`, confidence in the High band, and a source-cadence `expires_at_utc`.
- **AC-TC-02 (Clutch — the canonical test).** Given an AI-elicited citation whose URL resolves but whose content does not contain the attributed firms, the pipeline (a) classifies it `AIGeneratedSummary`/`self_reported`, (b) sets `cited_url_resolves=true`, `content_supports_claim=false`, (c) emits a Citation-Accuracy defect, (d) sets the attributed Claim `contradicted`, (e) never sets `show_as_fact` or `ranking_influence_allowed=true`. Report text renders as "assistant cited page Y, which does not contain Z" — never "Z is true."
- **AC-TC-03.** A single first-party website assertion yields `Claimed` (not `Corroborated`/`Verified`), `show_attributed`, `ranking_influence_allowed=false`; adding a second independent Tier-3+ agreeing Evidence promotes it to `Corroborated` and flips ranking eligibility on.
- **AC-TC-04.** A promotional "best in Melbourne" string yields `MarketingClaim`, never influences ranking, and is displayed only as labelled marketing (Authority Spoofing guard).
- **AC-TC-05.** A missing/invalid confidence input produces an explicit missing confidence that displays Low and routes the derived Issue to `review_required` (OD-003).
- **AC-TC-06.** An `Estimated` review-count Claim carries an interval and N; no point value is shown as fact; no composite score is produced.
- **AC-TC-07.** Backing Evidence transitioning `valid → quarantined` recomputes the dependent Claim, drops it below `Verified` if it was the sole support, and cascades suppression to any dependent published Recommendation Artifact.
- **AC-TC-08.** A court/regulator record yields `FindingOfCourtOrRegulator`/`RegulatoryAction` with `human_first_required`; absent the counsel-gate flag, `display_permission` is capped below `show_as_fact`.
- **AC-TC-09.** Every produced Claim carries `two_clock_layer`; a Perception Claim on the corpus layer never emits a customer-facing timeline.
- **AC-TC-10.** No Claim exists whose `object_value` is absent from all its provenance entries (no-synthesis fuzz test).
- **AC-TC-11.** A Claim's `data_classification` equals the strongest backing-Evidence classification across a battery of mixed-classification inputs; no path declassifies; unknown maps to `restricted`.
- **AC-TC-12.** An F1-AI `show_as_fact` Claim without a `citation-policy-v1`-verified Citation for a manifest value is non-publishable.

## 17. Traceability (this input → existing canon)

| This module | Extends / depends on |
|---|---|
| Claim references Evidence; no new Evidence Type | `011 DOMAIN_MODEL.md`; ADR-017 closed `evidence_type` taxonomy; `SCORE_EVIDENCE_MODEL.md` Evidence contract |
| Confidence model (§8) | OD-003; `confidence-policy-v1`; ADR-019 |
| No-synthesis (INV-3) | PRULE-037 |
| AI-output binding (§10.4, INV-12) | `citation-policy-v1`; PRULE-014 |
| Verify gate + Clutch test (§6, AC-TC-02) | `AUTHORITY_ROADMAP.md` verified findings; `ASSESSMENT_DELIVERY_GUIDE.md` Part 5; `002 ANSWER_PATH_AND_AUTHORITY_SPEC.md` §1 |
| Finding taxonomy consumers (§10.6) | `000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §5; `ASSESSMENT_DELIVERY_GUIDE.md` Part 7 |
| Two clocks; composite-score ban; corpus never promised | `000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §4, §7; `AUTHORITY_ROADMAP.md` claim discipline |
| Measurement gating | OD-010 Measurement Set |
| Legal guardrails (§11) | `ASSESSMENT_DELIVERY_GUIDE.md` Part 11; OD-011; counsel brief |
| Reality/Perception/Intelligence placement | ADR-012; VISION-001; FUTURE-WORKFLOW-001 |
| Finding-word triple collision (§5.9) | `003 TERMINOLOGY.md`; FUTURE-WORKFLOW-001; deferred to vocabulary ADR |

## 18. Open questions (decisions requiring an ADR / owner ruling before build)

1. **Domain-model status of Claim.** New DM-REQ-001 core entity vs. auxiliary lifecycle record (the Evidence `evd_id` pattern). This module assumes auxiliary; the ruling belongs to the vision-set ADR that files the layer-1 Reality-side domain model.
2. **The Finding triple-collision.** Three senses of "Finding" (Issue-variant forbidden by `003 TERMINOLOGY`; FUTURE-WORKFLOW-001 first-class object; the legal class here). Rename candidate `AdjudicatedDetermination` recorded but not adopted. ADR must decide.
3. **Authority weights.** Per-vertical numeric authority-tier weights and the reconciliation tie-break (`authority-policy-v1`) need OD-003-style owner calibration with drift monitoring; none is asserted here.
4. **Expiry cadences.** Per-source revalidation cadences depend on the Source Registry Specification (layer 4) and OD-010; placeholders in §9/§13.3 are non-binding.
5. **Two confidences.** Canonical single-field mapping of assertion-confidence vs. truth-confidence (Opinion/Review/Allegation) to OD-003 needs an owner ruling; `confidence_basis` is the interim carrier.
6. **Legal republication thresholds.** What may appear in a customer-visible artifact for `FindingOfCourtOrRegulator`/`RegulatoryAction`/`Allegation`, and the human-first gate, require counsel sign-off against OD-011 and the counsel brief before `show_as_fact` is permitted for these classes.
7. **Estimated and ranking.** Whether interval-bearing `Estimated` Claims may ever influence a ranking signal at Instrument grade, pending OD-010.
8. **F1-AI vs measured-AI `AIGeneratedSummary`.** Same class, materially different handling; a handling flag or sub-class ruling is required.
9. **Verify-observation Evidence type.** Whether SEV-1's verification step needs a dedicated Evidence Type or can reuse the closed taxonomy's `external_measurement`/`verification_observation`; ADR-017 controlled-change implications must be assessed before build.

---

*End of Volume III specification input — Module 4. Future/gated. Enters canon only via the vision-set ADR.*
