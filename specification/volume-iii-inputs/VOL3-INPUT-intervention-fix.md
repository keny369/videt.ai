# Volume III Input — Intervention & Fix Library (Module 3)

**Status:** Volume III specification input — future/gated; enters canon only via the vision-set ADR (see `specification/machines/001 VOLUME_III_ARTIFACT_MAP.md`). Volume I/II are frozen and the ratified Product Architecture Manual is the single source of truth (ADR-001). Nothing in this document is ratified. Candidate identifiers, aggregate names, states, and enums are proposals conformant with ADR-013 (Genesis conventions) and FUTURE-WORKFLOW-001 vocabulary; they acquire authority only through the ADR front door. This document EXTENDS the existing vocabulary and never establishes a competing dictionary.

**Module scope:** Codify the fix system as executable specification: the two-layer clock taxonomy, the intervention-type catalogue mapped 1:1 to FUTURE-WORKFLOW-001 canonical intervention types, the concrete patterns verified in the answer-path teardown, the Intervention Plan aggregate that links findings → fixes → verification → re-observation → outcome, the refuse-to-sell list, binding claim discipline, and the two schemas (Intervention Plan + Fix Catalogue).

**Author's note on FUTURE-WORKFLOW-001:** the verbatim FUTURE-WORKFLOW-001 "Intervention Learning Lifecycle" is an owner-supplied strategy artifact filed outside this repository (`branding/future/README.md`). This module reconstructs its intervention vocabulary from the four places it is already distilled — `MACHINE_BEHAVIOUR_SYNTHESIS.md §7`, `ASSESSMENT_DELIVERY_GUIDE.md Part 8/10/12`, `AUTHORITY_ROADMAP.md`, and `002 ANSWER_PATH_AND_AUTHORITY_SPEC.md` — and flags every place where a name or field must be confirmed against the owner's original on filing.

---

## 0. Reader orientation

### 0.1 Where this sits in the lifecycle

The Videt future architecture runs one loop (ADR-012; `VIDET_DISCIPLINED_ENTREPRENEURSHIP_PLAN.md`):

```
Reality  ->  Observation  ->  Perception  ->  Intervention  ->  Intelligence
```

Module 3 owns the **Intervention** station and its two neighbours' contracts:

- **Inbound:** it consumes *findings* (detection outputs from the Perception layer — the finding-class taxonomy of `MACHINE_BEHAVIOUR_SYNTHESIS §5`) and ratified **Issues** (the deterministic pipeline's deficiency object, `011 DOMAIN_MODEL.md`). Findings and Issues are kept strictly separate here (see §2.3 — the vocabulary collision).
- **Core:** it produces a versioned **Intervention Plan** aggregate that binds each finding/Issue to one or more typed **Interventions** drawn from a versioned **Fix Catalogue**.
- **Outbound:** each Intervention carries a **verification** contract (the fix is live and correct on the surface) and feeds a **re-observation** contract (did assistant behaviour move), whose comparable before/after deltas become the measured **Outcome** and, in aggregate, **Intelligence**.

### 0.2 The load-bearing honesty commitments (restated, binding)

Everything in this module is subordinate to these. They are not style; they are invariants (see §8):

1. **Two clocks, and we never promise the slow one.** Retrieval-layer fixes propagate in days-to-weeks and are re-measurable inside a 90-day window; corpus-layer changes are unbounded and unschedulable. The customer-facing line is fixed: *"retrieval-layer fixes propagate in days to weeks and we re-measure them; what the models remember from training changes slowly and no one can schedule it."*
2. **Counts, not composite scores.** Composite/synthetic scores are banned (`AUTHORITY_ROADMAP.md`, `branding/000–002`). Outcomes are counted observations with N, and at instrument grade, Wilson intervals. OD-003's numeric-confidence-with-Low/Medium/High-band model governs any confidence display; it is never a merged efficacy score.
3. **Leads, not evidence.** Assistant self-reports about their own sources are confabulated (verified live: real Clutch URL, wrong contents). Anything `self_reported` is a lead that MUST be independently verified before it enters a report, a score input, or an Intervention Plan.
4. **OD-010 gates external measurement.** Re-observation is external measurement. Until the OD-010 Measurement Set is approved, re-observation is concierge-collected Evidence only; nothing here implies an active in-product Measurement Set.
5. **We refuse to sell what the machines debunked.** The refuse-to-sell list (§8.4) is a product boundary, not a preference.

---

## 1. The two-layer model as a first-class taxonomy

The single most important structural fact the three machines and the live teardown confirmed: **mention behaviour decomposes into two layers with different clocks** (`002 ANSWER_PATH_AND_AUTHORITY_SPEC §1`; `AUTHORITY_ROADMAP` governing insight). Layer is therefore a first-class attribute of every intervention type, every Intervention line item, and every Outcome attribution — not a footnote.

### 1.1 `Layer` enumeration (closed)

| Value | Name | What moves | Clock | Re-measurable in 90-day window | Who needs it |
|---|---|---|---|---|---|
| `retrieval` | Retrieval layer | What an assistant *finds and resolves* when it searches: resolvable entities, buyer-language pages, the lists/directories/roundups already in the answer path, indexed third-party bios | Days–weeks | Yes | Every customer |
| `corpus` | Corpus (parametric) layer | What *future models ingest* as authoritative during training: DOI-indexed papers, JOSS/arXiv, dependency graphs, framework/university references, coined terminology, deeply-propagated bios | Model-training generations (months–years); unbounded | No | Consultants, B2B, founder brands only |

`Layer` is closed. A third value is not added without an ADR; if a future mechanism does not clearly move one of these two, that is a signal the mechanism is not yet understood well enough to sell.

### 1.2 The `PropagationClock` value object

Every Fix Catalogue entry and every Intervention carries a `PropagationClock`:

```
PropagationClock {
  layer:            Layer            // retrieval | corpus
  typical_min:      Duration         // e.g. P3D
  typical_max:      Duration         // e.g. P8W  (null for corpus — unbounded)
  remeasure_window: Duration | null  // retrieval: P90D; corpus: null
  promisable:       boolean          // retrieval MAY be true; corpus MUST be false
  customer_timeline_permitted: boolean  // retrieval MAY be true; corpus MUST be false
}
```

### 1.3 The honest-clock rule (binding invariant, encoded)

> **INV-CLOCK-1.** For any Fix Catalogue entry or Intervention with `layer = corpus`: `promisable = false`, `customer_timeline_permitted = false`, `typical_max = null`, `remeasure_window = null`, `due_at = null`. No `Export`, report section, or sales artefact may render a date, deadline, or "by when" for a corpus-layer intervention.

> **INV-CLOCK-2.** For `layer = retrieval`: an Outcome may be reported only against the intervention's declared `remeasure_window` (default `P90D`), with counts and N; a rate is permitted only at instrument grade with a Wilson interval.

> **INV-CLOCK-3.** For a **local-services** customer (§9), no corpus-layer intervention may appear in an approved Intervention Plan at all. The report states this omission explicitly — *"the corpus layer is irrelevant to your business and we are not selling it to you"* — because saying so is a trust move (`AUTHORITY_ROADMAP` tier mapping; `ASSESSMENT_DELIVERY_GUIDE` Part 8 Tier 3).

### 1.4 Dual-layer interventions

Some interventions act on both layers with different immediacy. **AuthorityBioSeeding** (a booked talk / podcast slot) yields *indexed bio pages, transcripts, backlinks within weeks* (retrieval effect) AND, over training generations, *parametric bio association* (corpus effect). Such an intervention is modelled with `primary_layer = retrieval` and a declared `secondary_layer = corpus`. The retrieval effect is promisable and re-measurable; the corpus effect inherits every INV-CLOCK-1 prohibition. The report attributes only the retrieval delta and states the corpus effect as unschedulable strategy.

---

## 2. Finding → Issue → Intervention: the input contract

### 2.1 Finding classes consumed (detection inputs)

Interventions are triggered by finding classes from the adopted taxonomy (`MACHINE_BEHAVIOUR_SYNTHESIS §5`; `ASSESSMENT_DELIVERY_GUIDE Part 7`). This module treats these as an **input enumeration** (`FindingClass`), not as a persisted deficiency object:

| `FindingClass` | Definition | Detected by |
|---|---|---|
| `absence` | Not mentioned for a buyer intent the business genuinely serves | Mention rate vs intent set |
| `entity_conflation` | Facts merged with a similarly-named entity; firm/practitioner confusion | Entity Resolution Fidelity vs Reality Card |
| `temporal_hallucination` | Stale facts presented as current (old address, closed status, lapsed registration) | Fact checks vs ground truth |
| `geographic_boundary_breach` | Recommended outside true service area, or absent inside it | Wrong-area controls |
| `authority_spoofing` | Marketing/promotional content treated as regulatory/authoritative validation | Citation Accuracy checks |
| `anchoring_fragility` | Present, but collapses or inverts under follow-up pressure | Follow-up Anchoring Index |
| `defective_observation` | Run-failure class (fabricated business, unresolved collision, unsupported citation) | Run-failure quarantine — reported, never averaged |

`defective_observation` is a quarantine class: it triggers no intervention on the client and is reported as its own finding, never silently averaged into rates.

### 2.2 Each finding carries (input record shape)

```
Finding {
  finding_id:        candidate-namespace (fnd_id)   // CANDIDATE — see open questions
  finding_class:     FindingClass
  reality_card_field: string        // the ground-truth field it contradicts
  verbatim_machine_text: string     // the exact assistant text
  observation_refs:  Observation[]  // runs that evidence it (date, assistant, arm)
  layer_hint:        Layer | unknown // two-arm search-on/off divergence, if available
  severity_signal:   { count: int, n: int }  // counts + N, never a score
}
```

`layer_hint` is derived from two-arm behaviour: an absence that appears search-OFF but resolves search-ON indicates a retrieval-footprint problem (fast layer); an absence in both arms indicates a parametric-memory problem (slow layer). This hint routes an intervention to the correct layer and, downstream, constrains what may be promised.

### 2.3 The Finding vs Issue collision (recorded, NOT resolved)

FUTURE-WORKFLOW-001 makes **Finding** a first-class object. Frozen `003 TERMINOLOGY` lists "finding" as a **disallowed variant of Issue** — "Issue" is the sole canonical customer and product deficiency object. This is a known, binding collision (`VIDET_DISCIPLINED_ENTREPRENEURSHIP_PLAN §5`; `MACHINE_BEHAVIOUR_SYNTHESIS §8`).

This module does **not** resolve it. Its interim discipline:

- The **finding-class taxonomy** above is used strictly as a *detection input vocabulary* internal to the Intervention station.
- The ratified deterministic pipeline's **Issue** (`iss_id`, Evaluation-owned) remains the canonical deficiency object; a `Finding` may map to an `Issue` but is not renamed to it and does not supersede it.
- An Intervention MUST be able to reference **either** a `Finding` (vision vocabulary) **or** an `Issue` (ratified) as its trigger, via `trigger_refs[]` that carries a discriminated type. This keeps both worlds addressable until the vocabulary ADR chooses.
- Per OD-009, any Issue in `disputed` or `review_required` state is excluded from published scoring and prioritisation and MUST NOT drive an approved Intervention until eligible.

Resolution is an ADR decision at vision-set filing. Downstream implementers MUST NOT collapse the two on their own authority.

---

## 3. The Intervention Type Catalogue (canonical types)

Each type below is mapped 1:1 to a FUTURE-WORKFLOW-001 canonical intervention type and specified with the full attribute set the prompt requires: **trigger findings · layer · confidence tier · prescribed action pattern · verification method · expected propagation clock · customer-tier applicability**. Confidence tiers derive from the Recommendation Signal Stack (`MACHINE_BEHAVIOUR_SYNTHESIS §3`): Tier 1 → `high`, Tier 2 → `plausible`, Tier 3 / debunked → `weak` / `debunked`.

`ConfidenceTier` enum (closed): `high` | `plausible` | `weak` | `debunked`. `debunked` types are refuse-to-sell (§8.4) and MUST NOT appear in an approved plan.

`CustomerTier` enum (closed): `local_services` | `professional_firm` | `founder_brand` (§9).

### 3.1 Retrieval-layer types (every customer)

These ten are the ratified-adjacent core; they map to the Delivery Guide Part 8 numbered fixes and to `MACHINE_BEHAVIOUR_SYNTHESIS §7`.

---

**IT-01 · EntityIdentityConsolidation**
- **Signal-stack tier / confidence:** Tier 1 → `high`.
- **Layer / clock:** `retrieval`; typical 1–4 weeks; remeasure P90D; promisable.
- **Trigger findings:** `entity_conflation`, `absence` (where the cause is unresolvable identity).
- **Prescribed action pattern:** establish ONE canonical NAP (name/address/phone/website) across official site, maps, directories, and registers; kill duplicate and stale listings; publish plain, indexable relationship sentences ("X founded Y"; "Z operates from {address}"); disambiguate explicitly from the Reality Card's confusable-entity list; where applicable, apply the **canonical-domain 301 pattern** (§4.6) so all equity accrues to one domain. Instantiates the **JSON-LD entity-graph pattern** (§4.2) for `sameAs` wiring.
- **Verification method:** re-crawl each surface; confirm duplicate/old listings removed or merged; confirm one resolvable entity per surface. Evidence: dated screenshots + rendered-text capture per surface.
- **Customer-tier applicability:** all tiers (the entity-resolution gate is universal).

---

**IT-02 · StructuredDataCorrection**
- **Tier / confidence:** Tier 1 → `high`.
- **Layer / clock:** `retrieval`; typical 1–6 weeks (index-bound); remeasure P90D; promisable.
- **Trigger findings:** `absence`, `entity_conflation`.
- **Prescribed action pattern:** author valid schema.org/JSON-LD — `LocalBusiness`/`ProfessionalService`, `service` entries, `sameAs` to registers and socials, `Person` for named practitioners. Instantiates the **JSON-LD entity-graph pattern** (§4.2).
- **Verification method:** schema validator pass (structured-data test) + re-crawl showing the graph in rendered HTML. Evidence: validator report + crawl capture.
- **Customer-tier applicability:** all tiers.
- **Note:** absorbs part of the scope the synthesis names **MetadataCorrection** (see §3.3).

---

**IT-03 · ThirdPartyProfileCorrection**
- **Tier / confidence:** Tier 1 → `high`.
- **Layer / clock:** `retrieval`; typical days–3 weeks; remeasure P90D; promisable.
- **Trigger findings:** `temporal_hallucination`, `geographic_boundary_breach`, `entity_conflation`.
- **Prescribed action pattern:** correct maps/directories/register listings — address, categories, hours, service area — so third-party surfaces agree with the Reality Card canonical NAP; claim listing ownership where unclaimed.
- **Verification method:** screenshot the corrected listing live on each surface; confirm the corrected field renders. Evidence: dated live-listing capture.
- **Customer-tier applicability:** all tiers.

---

**IT-04 · ContentClarification**
- **Tier / confidence:** Tier 1 → `high`.
- **Layer / clock:** `retrieval`; typical 2–8 weeks; remeasure P90D; promisable.
- **Trigger findings:** `absence` (especially problem-first intents where no page carries the buyer's language).
- **Prescribed action pattern:** publish literally-titled service + location pages in buyer language; answer the problem-first questions (Question Bank classes A/B/H) on-page, with the key facts in the first ~200 words of crawlable text. Instantiates the **phrase-lattice pattern** (§4.1) and the **FAQ-as-buyer-query pattern** (§4.3).
- **Verification method:** pages live and indexed (`site:` check returns them); rendered-text check confirms buyer phrase present at title/H1 and in first 200 words. Evidence: `site:` result + rendered capture.
- **Customer-tier applicability:** all tiers.

---

**IT-05 · KnowledgeSourceAlignment**
- **Tier / confidence:** Tier 1 → `high`.
- **Layer / clock:** `retrieval`; typical days–4 weeks; remeasure P90D; promisable.
- **Trigger findings:** `authority_spoofing` (authority gaps), `entity_conflation`.
- **Prescribed action pattern:** make named practitioner pages match register records exactly (names, credentials, registration numbers); ensure register entries themselves are current (TPB, ASIC/AFS, AHPRA, law society/bar, state building authority, etc. — Delivery Guide Part 4 Layer 1). The register and the site must state identical names/credentials.
- **Verification method:** side-by-side confirmation that register + site show identical names/credentials. Evidence: dated capture of both.
- **Customer-tier applicability:** all tiers where the vertical has statutory registers; the practitioner-as-entity variant is emphasised for `professional_firm` and `founder_brand`.

---

**IT-06 · LocationCorrection**
- **Tier / confidence:** Tier 1 → `high`.
- **Layer / clock:** `retrieval`; typical 1–4 weeks; remeasure P90D; promisable.
- **Trigger findings:** `geographic_boundary_breach`.
- **Prescribed action pattern:** publish explicit service-area statements; correct geo signals (map service areas, location pages, structured `areaServed`); ensure suburbs NOT served are not implied.
- **Verification method:** corrected surfaces live; service-area statement renders and is indexable. Evidence: live capture per surface.
- **Customer-tier applicability:** all tiers with a geographic service model (highest value for `local_services`).

---

**IT-07 · ReviewSignalImprovement**
- **Tier / confidence:** Tier 2 → `plausible`.
- **Layer / clock:** `retrieval`; rolling 4–12 weeks; remeasure P90D; promisable as *activity*, never as *outcome*.
- **Trigger findings:** weak presence, `absence`.
- **Prescribed action pattern:** cultivate recent, specific, voluminous reviews on the CORRECT listing, across the platforms the vertical uses, with owner responses. **Boundary:** review *manipulation* is refuse-to-sell (§8.4) — this type covers legitimate solicitation and correct-listing hygiene only.
- **Verification method:** review count/recency/response-rate delta on the correct listing (not a competitor's or a duplicate). Evidence: dated listing capture with counts.
- **Customer-tier applicability:** all tiers; dominant weight for `local_services`.

---

**IT-08 · CitationAcquisition**
- **Tier / confidence:** Tier 2 → `plausible`.
- **Layer / clock:** `retrieval`; typical 4–12 weeks; remeasure P90D; promisable as *activity*.
- **Trigger findings:** `absence`, weak corroboration.
- **Prescribed action pattern:** run the **citation-gap raid** — identify the exact lists, directories, roundups, and profiles the *currently-recommended competitors* appear in (these are proven to be in the answer path), then obtain every legitimately available placement. Instantiates the **directory/placement registry pattern** (§4.4). Also the entry point for retrieval-layer **bio seeding** (indexed bio pages/transcripts/backlinks within weeks). **Self-reported constraint:** any assistant-elicited citation lead enters flagged `self_reported` and MUST be independently verified before it becomes an acquisition target in an approved plan (the Clutch misattribution case).
- **Verification method:** citation live and indexed; the placement page actually contains the client entity (guarding against the misattribution failure). Evidence: live page capture + rendered-text confirmation of the entity.
- **Customer-tier applicability:** all tiers.

---

**IT-09 · AuthorityContentPublication**
- **Tier / confidence:** Tier 2 → `plausible`.
- **Layer / clock:** `retrieval`; typical 6–12 weeks; remeasure P90D; promisable as *activity*.
- **Trigger findings:** `absence` in specialist/niche intents.
- **Prescribed action pattern:** publish credential-backed niche content — verifiable case studies, problem-first guides, and the **roundup play** (§4.5): an honest "landscape" roundup targeting the same buyer phrases the competitor-authored roundups rank for (competitors genuinely included, no self-crowning).
- **Verification method:** published + indexed (`site:`), buyer phrase present. Evidence: `site:` + rendered capture.
- **Customer-tier applicability:** all tiers; strongest for `professional_firm` and `founder_brand`.

---

**IT-10 · TechnicalAccessibilityCorrection**
- **Tier / confidence:** Tier 1 → `high`.
- **Layer / clock:** `retrieval`; typical 1–6 weeks; remeasure P90D; promisable.
- **Trigger findings:** `absence` *despite* good content (i.e. the content exists but is invisible to retrieval).
- **Prescribed action pattern:** make key pages crawlable (no JS-walled key content); expose facts in rendered HTML; put the buyer-relevant facts in the first ~200 words; fix indexation defects. Retrieval sees snippets, not sites — what is not in the first ~200 words of a crawlable, literally-titled page effectively does not exist.
- **Verification method:** rendered-text check (content present without JS execution) + index-count (`site:`) delta. Evidence: rendered capture + index count.
- **Customer-tier applicability:** all tiers.

### 3.2 Corpus-layer types (professional firms and founder brands only)

**CANDIDATE type names** — proposed here for the Delivery Guide Tier-3 descriptors; FUTURE-WORKFLOW-001's verbatim names prevail on filing (open question). All four inherit every INV-CLOCK-1 prohibition: unbounded clock, not promisable, no customer timeline, prescribed as strategy only.

---

**IT-C1 · ScholarlyPublicationSeeding** *(candidate)*
- **Confidence:** `plausible` as strategy; efficacy is a training-cycle bet, never a promise.
- **Layer / clock:** `corpus`; months–years; not promisable; no timeline.
- **Trigger findings:** persistent `absence` in both search arms for specialist/expert intents (parametric-memory gap), for `founder_brand`/`professional_firm` only.
- **Prescribed action pattern:** Zenodo DOI on every open-source release (the value is the Crossref/Scholar/OpenAlex indexing chain, not the DOI itself); one JOSS paper for a flagship tool; selective arXiv preprints (endorsement-gated). Recursive-authority selection principle: seek artefacts in sources that are themselves cited and demonstrably ingested.
- **Verification method (activity, not outcome):** DOI issued and resolvable; paper accepted/indexed. Evidence: DOI record + index listing. **No behavioural promise attaches.**
- **Customer-tier applicability:** `founder_brand` (full), `professional_firm` (practitioner-as-entity variant); **excluded for `local_services`**.

---

**IT-C2 · TerminologyEstablishment** *(candidate)*
- **Confidence:** `plausible` as strategy.
- **Layer / clock:** `corpus`; months–years; not promisable.
- **Trigger findings:** category-association weakness at the parametric layer for expert/niche intents.
- **Prescribed action pattern:** coin and repeat original terminology in versioned papers, talks, and docs — "phrases get repeated; repetition gets cited." Standards-body and framework-doc contributions where genuinely earned.
- **Verification method (activity):** term appears in ≥N independent third-party sources over time (a lead-count, not an efficacy claim). Evidence: citation instances.
- **Customer-tier applicability:** `founder_brand` primarily.

---

**IT-C3 · OpenSourceAdoptionCultivation** *(candidate)*
- **Confidence:** `plausible` as strategy.
- **Layer / clock:** `corpus`; months–years; not promisable.
- **Trigger findings:** absent tool/framework association at the parametric layer.
- **Prescribed action pattern:** the one-famous-OSS-project flywheel — the KPI is adoption/dependents (dependency-graph presence), never stars; framework-docs and major-vendor-cookbook citations are the recursive-authority targets.
- **Verification method (activity):** dependents/adoption count over time (descriptive, not causal). Evidence: dependency-graph snapshot.
- **Customer-tier applicability:** `founder_brand` / tool builders only.

---

**IT-C4 · AuthorityBioSeeding** *(candidate; DUAL-LAYER)*
- **Confidence:** `plausible`.
- **Layer / clock:** `primary_layer = retrieval` (indexed bio pages/transcripts/backlinks in weeks — promisable, remeasure P90D) with `secondary_layer = corpus` (parametric bio association over training generations — NOT promisable, no timeline).
- **Trigger findings:** `absence`; weak corroboration; thin practitioner-entity footprint.
- **Prescribed action pattern:** book local talks (meetup/PyCon-AU tier, not international keynotes) and podcast guest slots; each produces a speaker page, slides, video, and transcript. The retrieval value is the indexed pages; the corpus value is unschedulable.
- **Verification method:** speaker/transcript pages live and indexed (retrieval, verifiable). Evidence: live capture. The corpus effect is never verified as an outcome.
- **Customer-tier applicability:** `professional_firm`, `founder_brand`. The retrieval portion may be offered to any tier as CitationAcquisition-adjacent activity; the corpus framing is withheld from `local_services`.

### 3.3 The MetadataCorrection reconciliation (open)

`MACHINE_BEHAVIOUR_SYNTHESIS §7` names **MetadataCorrection** as an eleventh canonical retrieval-layer type. Delivery Guide Part 8 has no distinct row for it — its scope (title/meta/structured-attribute correctness) is folded into **IT-02 StructuredDataCorrection** and **IT-03 ThirdPartyProfileCorrection**. This module keeps MetadataCorrection recorded as a **catalogue alias** pending reconciliation against FUTURE-WORKFLOW-001 (open question), rather than either dropping the canonical name or minting an overlapping active type. Implementers MUST NOT create a competing eleventh type on their own authority.

---

## 4. The concrete pattern library (codified from the verified teardown)

Patterns are reusable, evidence-backed *action templates* that intervention types instantiate. They are codified from the 28 Jul 2026 answer-path investigation (Lumen & Lever live case; three-agent verification of assistant-cited sources; the Synap phrase-lattice mapping) in `AUTHORITY_ROADMAP.md` and `002 ANSWER_PATH_AND_AUTHORITY_SPEC.md`. Each pattern has: a *detector* (how a finding surfaces the need), an *action template*, a *verification*, and a *layer*.

`PatternId` enum (closed for this module; extensible only by ADR): `phrase_lattice` · `jsonld_entity_graph` · `faq_as_buyer_query` · `directory_placement_registry` · `roundup_play` · `canonical_domain_301`.

### 4.1 `phrase_lattice` — buyer-phrase lattice
- **Empirical basis:** Synap's buyer-phrase lattice is real and mapped — title/H1-level phrases on dedicated pages, per-city variants. A Synap *Sydney* page ranked #1 for the *Melbourne* query. "No page containing the phrase = nothing for retrieval to hand the model."
- **Detector:** `absence` for a buyer intent whose exact phrase has no dedicated, literally-titled page.
- **Action template:** build one dedicated page per (buyer-phrase × location) node; put the phrase at title and H1; start from the cheapest confirmed win (the query with almost no directory competition — e.g. "fractional AI advisor Melbourne").
- **Verification:** page indexed (`site:`), phrase at title/H1, present in first 200 words rendered.
- **Layer:** `retrieval`. **Instantiated by:** IT-04, IT-06.

### 4.2 `jsonld_entity_graph` — entity `@graph`
- **Empirical basis:** a verified 16-node JSON-LD `@graph` — `Organization`, `Person`, `ProfessionalService`, `Products`, `FAQPage`, `BreadcrumbList` — with `sameAs` across LinkedIn/GitHub/properties, ABN + address in footer, active sitemap.
- **Detector:** `entity_conflation` or `absence` traceable to unresolved entity identity / missing structured relationships.
- **Action template:** publish a coherent `@graph` binding Organization + Person + ProfessionalService + FAQPage + BreadcrumbList; wire `sameAs` to every owned property and register; add plain-sentence relationship statements on every relevant page.
- **Verification:** structured-data validator pass; graph present in rendered HTML; `sameAs` targets resolve.
- **Layer:** `retrieval`. **Instantiated by:** IT-01, IT-02.

### 4.3 `faq_as_buyer_query` — FAQ phrased as the buyer's question
- **Empirical basis:** FAQ questions phrased *exactly as buyer queries* produce LLM-quotable Q&A; transparent on-page pricing gives models concrete numbers to cite (a business decision, not required).
- **Detector:** `absence` for problem-first (Question Bank class B) or price (class G) intents.
- **Action template:** add FAQ blocks whose questions are verbatim buyer queries, with concise, quotable answers; optionally include concrete pricing.
- **Verification:** FAQ present in rendered HTML and `FAQPage` schema; question strings match the buyer-intent set.
- **Layer:** `retrieval`. **Instantiated by:** IT-04, IT-09.

### 4.4 `directory_placement_registry` — the citation-gap raid
- **Empirical basis:** the specific directories in the answer path are enumerable and mostly free/legitimate — e.g. Clutch (`clutch.co/get-listed`, review-driven organic rank; sponsorship exists but is not required — note the "we may earn a fee" disclosure), GoodFirms, `aidirectory.industry.gov.au` (highest-authority free citation), iaaic.org, Built In, DesignRush/TechBehemoths (medium), Sortlist (low). A winnable category can exist with *no* incumbent boutique on it.
- **Detector:** `absence`/weak corroboration where competitors appear on placements the client does not.
- **Action template:** maintain a per-vertical **placement registry** — the ranked list of answer-path directories with acquisition method (free/review-gated/paid), authority weight, and disclosure notes; obtain every legitimately available free placement first. Every registry entry is `self_reported`-cleared: the placement page must actually contain the client entity before it counts.
- **Verification:** placement live, indexed, and *containing the client entity* (misattribution guard).
- **Layer:** `retrieval`. **Instantiated by:** IT-08.

### 4.5 `roundup_play` — publish your own honest landscape roundup
- **Empirical basis:** several ranking pages for these buyer queries are competitor-authored "top {category} {city}" roundups. Publishing an honest landscape roundup targeting the same phrases replicates the exact mechanism that put those pages on page one.
- **Detector:** `absence` where competitor-authored roundups occupy the answer path.
- **Action template:** publish a genuinely useful "{city} {category} landscape" roundup targeting the same phrases; competitors genuinely included; **no self-crowning** (binding honesty rule).
- **Verification:** page indexed and phrase-targeted; honesty review passed (competitors present, no self-ranking claim).
- **Layer:** `retrieval`. **Instantiated by:** IT-09.

### 4.6 `canonical_domain_301` — collapse duplicate domains
- **Empirical basis:** a live technical defect — `lumenlever.com` served the full site HTTP 200 with no 301 to `lumenandlever.com`, producing two indexable duplicates splitting link equity.
- **Detector:** `entity_conflation`/`absence` where multiple indexable domains or duplicate URLs split equity.
- **Action template:** 301-redirect the non-canonical domain(s)/URLs to the single canonical domain *before* acquiring new citations, so all equity accrues to one entity.
- **Verification:** non-canonical domain returns 301 to canonical; single indexable entity confirmed.
- **Layer:** `retrieval`. **Instantiated by:** IT-01.

---

## 5. The Intervention Plan aggregate (extends FUTURE-WORKFLOW-001)

### 5.1 Concept and boundary

The **Intervention Plan** is the aggregate root that binds findings/Issues → typed interventions → verification → re-observation → measured Outcome, per client `Organization`. It is the platform record of the FUTURE-WORKFLOW-001 loop's Intervention station and the direct descendant of the Delivery Guide's manual **Fix log** (Part 12). It is **versioned and immutable-by-version**: an approved plan is never edited; a new version supersedes it.

**Aggregate boundary (candidate, ADR-013 conventions):** the Intervention Plan root owns its `Intervention` line items, its approval record, and its Outcome record. Writes enter through the root (mirrors DM-REQ-008). It references — never owns — `Finding`/`Issue`, `Observation`/Evidence, `Source`, and the Reality Card.

**Relationship to the ratified RecommendationArtifact (open question):** the ratified `RecommendationArtifact` references *exactly one* origin Issue (DM-REQ-011) and has states `draft`/`published`/`suppressed`/`retired`. The Intervention Plan references *many* findings/Issues and carries a richer lifecycle. Whether Intervention Plan is a new aggregate (`ivp_id`) or a versioned super-structure over RecommendationArtifact is an ADR ruling — flagged, not decided here.

### 5.2 Intervention Plan schema

```
InterventionPlan {
  intervention_plan_id: ivp_id            // CANDIDATE namespace
  organization_id:      org_id            // tenant boundary (011 DOMAIN_MODEL)
  project_id:           prj_id            // the discoverability program
  business_ref:         string            // subject business (Reality Graph entity)
  version:              int               // monotonic; 1..n
  status:               PlanStatus         // see §5.4
  customer_tier:        CustomerTier       // local_services | professional_firm | founder_brand

  reality_card_ref:     evidence_ref       // ground truth snapshot (immutable)
  observation_baseline_ref: observation_set_ref  // the "before" measurement set
  trigger_refs:         TriggerRef[]       // discriminated: {kind: finding|issue, id}

  interventions:        Intervention[]     // line items (§5.3); >= 1

  approval: {
    approver_id:        actor_id | null
    approved_at_utc:    timestamp | null
    approval_evidence_ref: evidence_ref | null   // client sign-off record
  }

  outcome: {
    reobservation_refs: observation_set_ref[]     // the "after" measurement sets
    layer_attribution:  LayerAttribution | null   // retrieval vs corpus (§7.4)
    remeasure_grade:    "screening" | "instrument"
    recorded_at_utc:    timestamp | null
  } | null

  created_at_utc:       timestamp
  superseded_by:        ivp_id | null
  superseded_at_utc:    timestamp | null
  catalogue_version:    string             // pins the Fix Catalogue version used (e.g. fix-catalog-v1)
}
```

### 5.3 Intervention (line item) schema

```
Intervention {
  intervention_id:      ivn_id             // CANDIDATE namespace
  intervention_type:    InterventionTypeId // IT-01..IT-10, IT-C1..IT-C4
  catalogue_entry_ref:  fxc_id             // versioned Fix Catalogue entry (§6)
  primary_layer:        Layer              // retrieval | corpus
  secondary_layer:      Layer | null       // set only for dual-layer (IT-C4)
  confidence_tier:      ConfidenceTier     // high | plausible | weak | (debunked forbidden in approved plan)

  trigger_refs:         TriggerRef[]       // >= 1 (finding or issue)
  target_surfaces:      Surface[]          // maps/register/site-page/directory/etc.
  applied_patterns:     PatternId[]        // from §4

  prescribed_action:    string             // instantiated from the catalogue action pattern
  owner:                OwnerRole          // client | client_web_person | operator
  status:               InterventionStatus // see §5.4

  promised:             boolean            // MUST be false if primary_layer=corpus
  due_at_utc:           timestamp | null   // MUST be null if primary_layer=corpus

  verification: {
    method:             VerificationMethod // catalogue-defined
    status:             "pending" | "passed" | "failed"
    evidence_ref:       evidence_ref | null
    verified_at_utc:    timestamp | null
  }

  reobservation: {
    measurement_ref:    observation_set_ref | null
    arm:                "search_on" | "search_off" | "unknown"
    before:             { count: int, n: int }
    after:              { count: int, n: int }
    wilson_interval:    Interval | null    // instrument grade only
  } | null

  outcome_classification: OutcomeClass | null  // effective | no_change | regressed | inconclusive
  self_reported_inputs_cleared: boolean         // true iff any self_reported lead was verified first
}
```

### 5.4 State machines

**PlanStatus** (aggregate root):

```
draft
  -> proposed        (all line items typed, triggers attached, refuse-to-sell excluded)
proposed
  -> approved        (client approval evidence recorded)
  -> withdrawn       (never approved)
approved
  -> in_execution    (>=1 intervention moves to in_progress)
in_execution
  -> verified        (all non-deferred interventions verification.passed)
verified
  -> re_observing    (comparable re-observation started; OD-010-gated)
re_observing
  -> outcome_recorded (Outcome deltas recorded with N)
outcome_recorded
  -> closed
any(approved..outcome_recorded)
  -> superseded      (a new version replaces this plan; superseded_by set)
```

**InterventionStatus** (line item):

```
proposed -> approved -> in_progress -> implemented
implemented -> verification_pending -> verified
verified -> re_observed
re_observed -> {effective | no_change | regressed | inconclusive}   // sets outcome_classification
// side transitions:
proposed|approved -> rejected     (client declines, or refuse-to-sell caught in review)
approved|in_progress -> blocked   (dependency/ToS/consent block)
approved -> deferred              (out of scope this version; carried to next)
```

`OutcomeClass` enum (closed): `effective` | `no_change` | `regressed` | `inconclusive`. `inconclusive` is mandatory (not a failure state) when N is below the grade threshold or controls are absent — it protects the no-false-causality invariant.

### 5.5 Invariants (test-validated before build; mirrors DM-REQ-004/011)

- **INV-IP-1.** An Intervention references ≥1 `trigger_ref`; a plan references ≥1 Intervention.
- **INV-IP-2.** No Intervention with `confidence_tier = debunked` (refuse-to-sell) may exist in a plan whose status is ≥ `proposed`.
- **INV-IP-3.** For any Intervention with `primary_layer = corpus`: `promised = false` and `due_at_utc = null` (INV-CLOCK-1). For a `customer_tier = local_services` plan, no corpus-layer Intervention may exist at all (INV-CLOCK-3).
- **INV-IP-4.** An Intervention MUST NOT enter `re_observed` before `verification.status = passed` (verification precedes outcome — the fix must be provably live before behaviour change is measured).
- **INV-IP-5.** A CitationAcquisition (IT-08) or any Intervention whose `applied_patterns` includes `directory_placement_registry` MUST have `self_reported_inputs_cleared = true` before the plan reaches `approved` — no unverified self-reported lead may be acted on.
- **INV-IP-6.** `outcome.layer_attribution` may assert a layer only when supported by a documented estimator (two-arm divergence, §7.4); otherwise it is null and the Outcome is reported as an observed delta without layer causation.
- **INV-IP-7.** No composite/synthetic score appears anywhere in the aggregate. Confidence, where displayed, uses the OD-003 numeric-with-band model and is never a merged efficacy figure.
- **INV-IP-8.** An approved plan is immutable; changes are made by minting `version = n+1` and setting `superseded_by`/`superseded_at_utc` on version n.
- **INV-IP-9.** An Outcome recorded before OD-010 activation is sourced only from concierge-collected Evidence and is labelled as such; it MUST NOT imply an active in-product Measurement Set.
- **INV-IP-10.** Any Issue in OD-009 `disputed`/`review_required` state MUST NOT be a `trigger_ref` on an Intervention in an approved plan.

### 5.6 Candidate domain events (extends the DM-REQ-013 envelope)

PascalCase per Rule 11 of `003 TERMINOLOGY`. Each carries the full Logical Event Envelope (event_id, schema_version, workflow_id, occurred_at_utc, organization_id, affected_entity_type/id, correlation_id, causation_id, actor/service identity):

- `InterventionPlanDrafted`
- `InterventionPlanProposed`
- `InterventionPlanApproved`
- `InterventionExecuted`
- `InterventionVerified`
- `ReObservationCompleted`
- `OutcomeRecorded`
- `InterventionPlanSuperseded`
- `InterventionRejected` (carries reason; refuse-to-sell rejections are auditable)

---

## 6. The Fix Catalogue schema (versioned intervention-type definitions)

The Fix Catalogue is the versioned registry of intervention-type definitions — the platform equivalent of the ratified `check-catalog-v1` idiom (a named, versioned, immutable policy set). An Intervention Plan pins the `catalogue_version` it was built against, so historical plans remain interpretable after the catalogue evolves.

### 6.1 FixCatalogueEntry schema

```
FixCatalogueEntry {
  fxc_id:                 fxc_id             // CANDIDATE namespace
  intervention_type_id:   InterventionTypeId // IT-01..IT-10, IT-C1..IT-C4
  future_workflow_name:   string             // the FUTURE-WORKFLOW-001 canonical name (verbatim)
  catalogue_version:      string             // e.g. fix-catalog-v1
  status:                 "active" | "alias" | "refuse_to_sell" | "deprecated"

  layer:                  Layer
  secondary_layer:        Layer | null
  confidence_tier:        ConfidenceTier
  signal_stack_tier:      1 | 2 | 3          // MACHINE_BEHAVIOUR_SYNTHESIS §3

  trigger_finding_classes: FindingClass[]
  applicable_patterns:    PatternId[]

  prescribed_action_pattern: {
    preconditions:        string[]
    steps:                string[]
    artifacts_produced:   string[]
  }

  verification_method: {
    check_type:           string             // re-crawl | validator | site:-index | live-screenshot | rendered-text
    evidence_required:    string[]
    pass_criteria:        string
  }

  propagation_clock:      PropagationClock    // §1.2
  customer_tier_applicability: CustomerTier[]

  claim_permissions: {
    may_report:           string[]           // e.g. "activity completed", "surface corrected & live"
    must_not_claim:       string[]           // e.g. "guaranteed mention", "timeline for corpus effect"
    outcome_reportable:   boolean            // false for corpus-only strategy items
  }

  refuse_to_sell:         boolean
  refuse_rationale:       string | null      // machine-debunked basis, if applicable
}
```

### 6.2 Refuse-to-sell entries carried in the catalogue (as guardrails, not products)

Refuse-to-sell items are recorded in the catalogue with `status = refuse_to_sell` and `refuse_to_sell = true` so the platform can *detect and block* them, and so the report can name them (naming them builds trust and matches the machine consensus). They can never be added to a plan (INV-IP-2). See §8.4 for the list.

---

## 7. Verification and re-observation (two distinct checks)

The Delivery Guide separates two things the platform must not conflate:

### 7.1 Verification — "the fix is live and correct on the surface"
- A per-intervention deliverable (Part 10: *verification is a deliverable*). It confirms the surface changed (listing corrected, schema valid, page indexed, 301 in place, placement live-and-containing-the-entity).
- It is a **retrieval-layer fact about the world**, not a claim about assistant behaviour. It gates re-observation (INV-IP-4).
- Evidence is immutable and dated (append-only, producer/evaluator split — the shared Immutable Evidence Production foundation).

### 7.2 Re-observation — "did assistant behaviour move"
- Comparable before/after measurement of the client's money questions, per the observation protocol (fresh sessions, ≥N samples, two-arm where the surface allows). This is **external measurement** and is **OD-010-gated**.
- Grades follow the two service grades: **screening** (≥3 fresh-session runs; counts only) and **instrument** (10+ runs; rates with Wilson intervals and N). A rate is never emitted at screening grade.

### 7.3 The value cadence encoded
- Weeks 1–3: client executes Tier-1 (retrieval) fixes; operator verifies each → `InterventionVerified`.
- Week 4 / Week 8: light pulses (screening grade) — delta counts, renew the relationship.
- 90-day: instrument-grade re-observation of the 5 money questions → `ReObservationCompleted` → `OutcomeRecorded`. The delta narrative is the case study.

### 7.4 Layer attribution of Outcome (estimator, provisional)
- The proposed estimator uses **two-arm divergence**: if a mention/position delta appears in the search-ON arm but not search-OFF, attribute to the retrieval layer; a delta present in both arms (rare, slow) is a candidate corpus signal but is reported cautiously and never causally without controls.
- Absent a documented estimator run, `outcome.layer_attribution = null` and the delta is reported as observed-not-attributed (INV-IP-6). The estimator's formal definition is an open question tied to the OD-010 Measurement Set.

### 7.5 Causality discipline
- No Outcome is labelled causal without the controls battery (fabricated-business, wrong-category, wrong-geography, closed-business, similar-name, misspelling). Without controls, the strongest permitted label is `observed_delta_not_causal`; the strongest `OutcomeClass` reachable is `effective`/`no_change`/`regressed` *as description*, never *as proof of cause*.

---

## 8. Binding claim discipline and the refuse-to-sell boundary

### 8.1 Language law (all grades, all artefacts)
- Counts, not composite scores. Every number carries its N. Every claim is stamped "observed on {date}, {assistant}". Variance is reported as a finding, not hidden. Abstain where evidence is thin.
- Confidence display, where present, is OD-003 numeric (0.0000–1.0000) with Low/Medium/High bands — never a merged efficacy score.

### 8.2 What may be promised
- **Retrieval-layer activity** ("we will correct the listing / publish the page / obtain the placement") and **re-measurement** ("we will re-observe your money questions at 90 days") are promisable.
- **Outcomes are never guaranteed** — no promise of mention, position, or timing, ever, anywhere, including sales conversations.

### 8.3 What may never be promised
- Any change to model **parametric memory** (the corpus layer) or its timing. The fixed honest line stands verbatim (§0.2.1).
- Permanence — "recommended today ≠ recommended tomorrow."

### 8.4 The refuse-to-sell list (machine-debunked; recorded as guardrails)
Carried in the Fix Catalogue as `refuse_to_sell = true`, blocked from every plan (INV-IP-2), and named in the report:

| Refused practice | Basis (machine-debunked / ethical) |
|---|---|
| AI-keyphrase / "LLM-optimised copy" stuffing | Classed *unproven speculation, below weak* by the machines themselves; "does not outperform standard structured clarity." |
| Review manipulation (fake/incentivised reviews, review gating) | Ethical + platform-policy violation; corrupts the very signal IT-07 legitimately improves. |
| Any guaranteed-mention / guaranteed-position / guaranteed-timing offer | Contradicts the no-guarantees guardrail and the two-clock reality. |
| Promising corpus/parametric-memory change or its schedule | Unschedulable; INV-CLOCK-1. |
| Scraping/automation of measurement ahead of the ToS analysis and OD-010 | Manual, human-scale querying only in this phase (Delivery Guide Part 11.6). |

### 8.5 Third-party and legal discipline (carried from Part 11)
- Raw machine outputs stay private; plans and reports carry verified, attributed observations only.
- Machine *opinions* about third parties are never republished as fact; "Assistant X named {competitor} in 11 of 12 runs" is reportable, the assistant's judgement of them is not.
- Adverse-record findings about the client (Delivery Guide Layer 6) are handled verbally first and appear only as verified public record with source.
- Regulated-vertical plans/reports carry: *"This is a measurement of AI assistant behaviour, not professional, financial, legal or medical advice."*

---

## 9. Customer-tier applicability matrix

`CustomerTier` governs which layers and which intervention types are eligible, and is a required field on every Intervention Plan.

| `CustomerTier` | Examples | Eligible layers | Eligible intervention types | Corpus framing |
|---|---|---|---|---|
| `local_services` | Local trades, clinics, restaurants, high-end trades (flooring/pools/solar) | `retrieval` only | IT-01 … IT-10 | **Excluded and explicitly stated as excluded** — "the corpus layer is irrelevant to your business; we are not selling it to you" (trust move). No IT-Cx in any plan. |
| `professional_firm` | Agencies, consultants, B2B services, professional firms (accountants, lawyers, brokers, advisers) | `retrieval` + `corpus` | IT-01 … IT-10 + IT-C1/IT-C2/IT-C4 (practitioner-as-entity variant; the person is the hub) | Prescribed as strategy, never promised, no timeline. |
| `founder_brand` | Founder brands, tool builders, research-adjacent firms | `retrieval` + `corpus` | IT-01 … IT-10 + IT-C1 … IT-C4 | Full corpus programme, with the honest clock on every corpus item. |

The matrix is enforced: a corpus-layer Intervention in a `local_services` plan fails INV-IP-3 and cannot reach `proposed`.

---

## 10. Worked trace (illustrative, non-normative)

A `founder_brand` client (à la Lumen & Lever) surfaces `absence` for all four buyer queries; `layer_hint = retrieval` (absent in both arms for one query → dual). A single Intervention Plan v1 is drafted:

1. **IT-01 EntityIdentityConsolidation** applying `canonical_domain_301` (301 the duplicate domain) + `jsonld_entity_graph`. Verify: non-canonical returns 301; graph validates.
2. **IT-04 ContentClarification** applying `phrase_lattice` (dedicated "Fractional AI Advisor {City}" page — the cheapest confirmed win) + `faq_as_buyer_query`. Verify: page indexed, phrase at H1.
3. **IT-08 CitationAcquisition** applying `directory_placement_registry` (government AI directory, Clutch free profile, GoodFirms, iaaic) — every lead `self_reported`-cleared before acquisition. Verify: placements live and containing the entity.
4. **IT-09 AuthorityContentPublication** applying `roundup_play` (honest landscape roundup; competitors included; no self-crowning). Verify: indexed, honesty review passed.
5. **IT-C4 AuthorityBioSeeding** (dual-layer): one meetup talk + two podcast slots. Verify retrieval portion (indexed bio pages); corpus portion carries no promise, no date.

Baseline = 0/4 (screening). At 90 days, instrument-grade re-observation of the 5 money questions → `OutcomeRecorded` with counts, N, and Wilson intervals; `layer_attribution` set only if the two-arm estimator supports it. Corpus items are re-visited as strategy, never re-measured as promised outcomes.

---

## 11. Acceptance criteria

A conforming Volume III implementation of this module satisfies all of the following (each is intended to be test-validated, mirroring DM-REQ-004/012):

1. **AC-1 — Layer is first-class.** `Layer` is a closed `retrieval|corpus` enum present on every Fix Catalogue entry, Intervention, and Outcome attribution; a value outside the enum is rejected.
2. **AC-2 — Honest clock enforced.** Any corpus-layer Intervention with `promised = true`, a non-null `due_at_utc`, a `customer_timeline_permitted = true`, or a rendered date in any Export fails validation (INV-CLOCK-1).
3. **AC-3 — Local-services corpus exclusion.** A `local_services` plan containing any IT-Cx / corpus-layer Intervention fails INV-IP-3; the report renders the explicit exclusion statement.
4. **AC-4 — 1:1 type mapping.** Every Fix Catalogue entry maps to exactly one FUTURE-WORKFLOW-001 canonical intervention type (or is marked `alias`/`refuse_to_sell`), and every Delivery-Guide Part 8 fix has a corresponding active entry.
5. **AC-5 — Trigger linkage.** Every Intervention references ≥1 finding/Issue trigger; every plan references ≥1 Intervention (INV-IP-1).
6. **AC-6 — Verification precedes outcome.** No Intervention reaches `re_observed`/`OutcomeRecorded` while `verification.status ≠ passed` (INV-IP-4).
7. **AC-7 — Self-reported gate.** No `self_reported` citation/placement lead is acted on in an approved plan without `self_reported_inputs_cleared = true` (INV-IP-5); the misattribution guard (placement must contain the entity) is enforced at verification.
8. **AC-8 — No composite scores.** No aggregate field, event payload, or Export emits a composite/synthetic score; confidence uses OD-003 numeric-with-band only (INV-IP-7).
9. **AC-9 — Grade-correct claims.** Screening-grade re-observation emits counts only; a rate (with Wilson interval and N) is emitted only at instrument grade.
10. **AC-10 — Refuse-to-sell blocked.** No `debunked`/`refuse_to_sell` type can be added to a plan at status ≥ `proposed` (INV-IP-2); refused practices are still nameable in the report.
11. **AC-11 — OD-010 respected.** Pre-OD-010, recorded Outcomes are sourced from concierge Evidence and labelled as such; nothing implies an active in-product Measurement Set (INV-IP-9).
12. **AC-12 — Layer attribution guarded.** `outcome.layer_attribution` is non-null only when a documented two-arm estimator supports it; otherwise the delta is reported without layer causation (INV-IP-6).
13. **AC-13 — Versioned & immutable.** Approved plans are immutable; changes mint a new version and set `superseded_by`; the plan pins the `catalogue_version` it was built against.
14. **AC-14 — Pattern instantiation.** Each of the six patterns (`phrase_lattice`, `jsonld_entity_graph`, `faq_as_buyer_query`, `directory_placement_registry`, `roundup_play`, `canonical_domain_301`) is instantiable by at least its declared intervention types, with a detector, action template, and verification.
15. **AC-15 — Finding/Issue separation.** The finding-class taxonomy is used only as detection input; the canonical `Issue` is never renamed to "finding"; both are addressable as triggers pending the vocabulary ADR.
16. **AC-16 — Codification-bridge fidelity.** The Intervention Plan / Intervention schemas superset the Delivery-Guide Part 12 Fix log fields (`fix_id · intervention_type · trigger_finding_ids · owner · agreed_date · implemented_date · verified_date · verification_evidence_ref`), so manual logs ingest without loss.

---

## 12. Open questions (require ADR / owner ruling before build)

These are carried into the machine-readable `open_questions` list; summarised here for the reader:

1. **Finding vs Issue** — binding vocabulary collision; ADR at vision-set filing decides. Do not pre-empt.
2. **Corpus-layer type names** — IT-C1…IT-C4 names are candidates pending the verbatim FUTURE-WORKFLOW-001.
3. **MetadataCorrection** — distinct type or alias of IT-02/IT-03? Reconcile with FUTURE-WORKFLOW-001.
4. **Aggregate identity** — new Intervention Plan aggregate vs versioned RecommendationArtifact extension (cardinality differs from DM-REQ-011).
5. **Candidate id namespaces** — `ivp_id`, `ivn_id`, `fxc_id`, and observation/finding namespaces need Chief Architect assignment.
6. **OD-010 interaction** — precise pre-activation recording of Outcome deltas without implying an active Measurement Set.
7. **Layer-attribution estimator** — formal, testable definition of the two-arm estimator before any layer-attributed claim ships.
8. **Verification automation vs ToS** — automated re-crawl verification depends on the counsel ToS/durability analysis; manual until resolved.
9. **Causal-attribution controls** — exact controls battery required before an Outcome may be labelled causal; pin to the OD-010 Measurement Set.
10. **Truth & Claims Specification dependency** — claim classes governing supporting Evidence are drafted at filing and constrain this module's provisional claim-permission fields.

---

*End of Volume III Input — Intervention & Fix Library (Module 3). Future/gated. Enters canon only via the vision-set ADR.*
