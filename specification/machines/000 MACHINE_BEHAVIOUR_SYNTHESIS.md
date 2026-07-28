# Machine Behaviour Synthesis — How AI Assistants Actually Recommend Businesses

Status: Informational research input (same standing as `research/000-initial-concept.md`). Not part of the ratified specification; canonical requirements live in `specification/INDEX.md`. Synthesised 27 July 2026 from four sources in this folder and on the owner's desk: `ChatGPT-5.5 Pseudocode.md`, `Gemini 3.6 Thinking Pseudocode.md`, `Grok Pseudocode.md`, and `business_recommendation_urls_AU_US_UK_CA.md` (393 audit surfaces). Operational application lives in `operations/ASSESSMENT_DELIVERY_GUIDE.md`.

---

## 1. What the three machines were asked, and what they are

Three frontier assistants were asked to describe, as honestly as their self-knowledge allows, how they answer buyer-intent questions about businesses. The three documents are different genres and must be read differently:

- **Grok and Gemini are descriptive** — epistemically careful accounts of what actually happens, with claims labelled by evidence class (directly known / exposed behaviour / inference). These are the reliable sources for *how mention and omission work*.
- **ChatGPT-5.5's is largely normative** — an idealised recommendation architecture (discovery → filter → score → rank → explain, with per-industry weights). It describes how a well-engineered recommender *should* work, not what happens inside a transformer. Its value is different: it enumerates, exhaustively, the **signals a careful evaluator would weigh** — which is exactly the checklist a business must satisfy to be recommendable — and its measurement sections (factorial design, controls, run-failure criteria) are first-rate.

## 2. The consensus — five findings all three agree on

**2.1 There is no ranking engine.** All three state plainly that no explicit business-scoring database exists inside the model. Grok: *"Claims of 'I rank by X score' would be fabrication."* Gemini: ordering is *"an emergent phenomenon resulting from autoregressive token probability distributions."* Recommendation emerges from three inputs: (a) training-data co-occurrence of name + category + location, (b) what retrieval surfaces and in what order, (c) fit to the constraints in the prompt.

**2.2 Entity resolvability is the gate.** Before a business can be recommended it must be *resolvable as one entity*. Inconsistent name/address/phone across surfaces creates competing token associations → lower generation probability, omission, or worse, conflation with a similarly named business. Both descriptive docs name entity confusion (firm vs practitioner; similar names cross-contaminating addresses) as a routine failure mode.

**2.3 Retrieval sees snippets, not sites.** In search-enabled runs the model typically sees 5–20 truncated snippets chosen and ordered by a search engine it does not control. JavaScript-rendered directories, paywalled content, and form-driven registers are effectively invisible. What is written in the first ~200 words of a crawlable, literally-titled page is what exists.

**2.4 Regulated verticals invert the evidence hierarchy.** For accountants, lawyers, health, finance: registers and licence status gate everything, reviews are secondary, abstention and shortlists replace single winners. For agencies/coaches/trades: portfolios, case studies and reviews dominate. Any assessment methodology must be vertical-aware (the two pseudocode docs supply ~40 vertical evidence policies between them; consolidated in the delivery guide).

**2.5 Follow-ups are anchored, not re-evaluated.** In a continuing conversation the candidate pool collapses to names already in context; the first-listed name carries a primacy advantage; the model post-hoc rationalises. A "which one would you pick?" win is substantially a position artifact. Measurement must treat follow-up behaviour as its own metric (Gemini formalises this as the Follow-up Anchoring Index), and fresh sessions as the only clean baseline.

## 3. The Recommendation Signal Stack (consolidated influence model)

Merged from Grok's confidence tiers, Gemini's control tiers, and ChatGPT's signal enumeration. This is the canonical input to VIDET's fix library.

**Tier 1 — High-confidence, directly controllable:**
- Consistent NAP across official site, maps, directories, registers (the entity-resolution gate)
- Presence and accuracy on the relevant professional/statutory registers
- Crawlable official website with precise, literally-titled service + location pages
- Accurate schema.org/JSON-LD structured data
- Named practitioner pages that match register records
- Current contact details and opening hours everywhere

**Tier 2 — Plausible, partially controllable:**
- Recent, voluminous, specific reviews with owner responses, on the correct listing, across multiple platforms
- Independent citations from authoritative local/industry sources; editorial "best of" inclusion
- Problem-first content matching real buyer language; dense niche terminology (strengthens category association)
- Verifiable case studies; published pricing pages

**Tier 3 — Weak or indirect:** awards, generic backlinks, social posting volume, media mentions, Wikipedia/LinkedIn/YouTube presence, sponsorships.

**Explicitly debunked:** *"LLM-optimised keyphrase stuffing"* — Gemini classes AI-targeted prose stuffing below weak, as *unproven speculation* that "does not outperform standard structured clarity." This is load-bearing for VIDET's positioning: the machines themselves refute the snake-oil end of the GEO market.

**Uncontrollable:** training co-occurrence, search-engine ranking algorithms, sampling stochasticity, product-level tool routing, model version changes.

## 4. What VIDET can validly measure — and never claim

**Valid measurements** (all three concur): mention rate, position distribution, shortlist-collapse rate, factual accuracy of stated details against ground truth, sensitivity to wording/location/urgency, anchoring strength, caveat/abstention rates, cross-run agreement, search-on vs knowledge-only divergence, entity-resolution error rates.

**Invalid claims:** internal ranking weights (none exist); causal proof that one optimisation caused one change (without controls and pre/post evidence); a universal "AI ranking score"; permanence ("recommended today ≠ recommended tomorrow"); anything about hidden chain-of-thought. Grok's closing verdict names the trap directly: the highest-value use of measurement is *"to surface systematic failure modes … rather than to produce a spurious 'AI ranking' leaderboard."*

## 5. The findings taxonomy (adopted)

Gemini's four named failure modes become VIDET's audit finding categories, extended by the presence dimension:

| Finding class | Definition | Detected by |
|---|---|---|
| **Absence** | Not mentioned for a buyer intent the business genuinely serves | Mention rate vs intent set |
| **Entity Conflation** | Metadata merged with a similarly named entity; firm/practitioner confusion | Entity Resolution Fidelity vs Reality Card |
| **Temporal Hallucination** | Outdated facts presented as current (old address, closed status, stale registration) | Fact checks vs ground truth |
| **Geographic Boundary Breach** | Recommended outside true service area, or absent inside it | Wrong-area controls |
| **Authority Spoofing** | Marketing/promotional content treated as regulatory or authoritative validation | Citation Accuracy checks |
| **Anchoring Fragility** | Presence exists but collapses (or inverts) under follow-up pressure | Follow-up Anchoring Index |

## 6. Measurement standards (adopted, tiered)

The sources converge on statistics that manual delivery cannot fully afford, so VIDET adopts them in two declared grades:

- **Screening grade (concierge assessments):** ≥3 fresh-session samples per question per assistant. Valid for: detecting gross failure modes (absence, wrong facts, conflation), reporting **counts of observations**. Invalid for: percentage claims, competitor comparisons, trend claims. ChatGPT's verdict is adopted verbatim as policy: three runs is *"a smoke test only … never make comparative claims from it."*
- **Instrument grade (drill-downs, re-measures, published studies):** 10 runs per condition for directional work; 20–30+ for client-facing rate estimates; uncertainty intervals (Wilson) always displayed with N; question families not treated as independent observations; two-arm search-on/search-off where the surface permits; controls battery (fabricated business, wrong-category, wrong-geography, closed business, similar-name, misspelling); anchoring order-permutation experiments; longitudinal waves at baseline/7/30/90 days and after model-version changes.

**Adopted metrics** (formulas in the delivery guide): Mention Rate; Position-Weighted Score with VIDET's declared reporting weights (1st = 1.00, 2nd = 0.70, 3rd = 0.50, 4th = 0.35, 5th+ = 0.20, unranked mention = 0.10) — *a VIDET reporting convention, explicitly not model internals*; Entity Resolution Fidelity; Citation Accuracy Rate; Follow-up Anchoring Index.

**Run-failure criteria** (a captured run is quarantined as a defective observation if it contains): fabricated business, unresolved entity collision, unsupported registration claim, incorrect contact detail presented as fact, citation that does not support its statement, or false claim of personal experience.

## 7. Implications for VIDET

1. **The fix library writes itself, and it matches the vision.** Tier 1/2 of the signal stack maps almost one-to-one onto FUTURE-WORKFLOW-001's canonical intervention types (EntityIdentityConsolidation, StructuredDataCorrection, ThirdPartyProfileCorrection, CitationAcquisition, ReviewSignalImprovement, ContentClarification, LocationCorrection, MetadataCorrection, TechnicalAccessibilityCorrection, KnowledgeSourceAlignment). The machines independently confirmed the intervention menu the vision documents specified.
2. **The Reality Card is mandatory.** Fact-checking machine answers requires ground truth captured first — canonical NAP, registrations with numbers, services, locations, practitioners, confusable-entity list. This is the manual seed of the Reality Graph.
3. **The Reality-side audit is enumerable.** The 393-surface URL inventory (AU/US/UK/CA registries, maps, review platforms, technical checks, adverse-record searches) turns "improve your presence" into a deterministic checklist with a defined pass/gap state per surface.
4. **Honesty is the differentiator the machines endorse.** No fake composite scores, declared conventions, uncertainty with every rate, abstention when evidence is weak — the measurement itself must behave the way the product principles demand of dashboards.
5. **Two clocks govern fixes:** retrieval-layer changes (site, registers, maps, reviews) propagate in days-to-weeks and are re-measurable within a 90-day window; parametric-memory changes are slow, unbounded, and must never be promised.

## 8. Governance and risk notes

- These documents are **self-reports by the systems being measured** — treat as strong hypotheses, not ground truth; the assessment protocol tests them continuously (that is the product).
- Legal (all three flag it): raw model outputs stored privately; only verified, aggregated patterns reported; machine statements about third-party businesses never republished as fact; regulated-vertical reports carry "measurement of assistant behaviour, not professional advice" disclaimers.
- Provider ToS/durability remains an open strategic item (already in counsel's brief): manual, human-scale querying now; any automation waits on the OD-010 measurement-set decision and the ToS analysis.
- Vocabulary: this document uses "finding" in its research sense; the ratified pipeline's customer-facing deficiency object remains **Issue** (003 TERMINOLOGY) — the collision is recorded for resolution when the vision set is filed by ADR.
