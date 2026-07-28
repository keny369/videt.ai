# Authority Roadmap — Appearing in AI Recommendations (80/20)

Status: Operating reference, 28 July 2026. Two uses: (1) the founder's own plan for Lee Powell / Lumen & Lever; (2) the productised template VIDET applies to customers by tier. Grounded in `specification/machines/000 MACHINE_BEHAVIOUR_SYNTHESIS.md` and extended by the 28 Jul ChatGPT authority-strategy conversation (corpus-layer mechanisms). Sister documents: fix library in `operations/ASSESSMENT_DELIVERY_GUIDE.md` Part 8; question sets in `investor/QUESTION_BANK.md`.

## The governing insight

Assistants answering "who should I use for X in Y?" mostly **search and resolve entities**; parametric fame matters mainly for big brands. Therefore:

| Layer | What it is | Clock | Cost | Who needs it |
|---|---|---|---|---|
| **Retrieval** | What assistants find and resolve when they search: entities, pages in buyer language, the lists/directories already in the answer path, third-party bios | **Weeks** | Days of work | **Every customer** |
| **Corpus** | What future models ingest as authoritative: DOI-indexed papers, JOSS/arXiv, dependency graphs, framework docs, university/course references, coined terminology | Model-training generations (months–years) | Founder-months | Consultants, B2B, founder brands |

The classic mistake (and most "AI visibility" advice): a corpus-layer plan for a retrieval-layer problem. Measure first; fix the fast layer; enter the slow layer cheaply; never promise the slow layer's clock.

## Phase 1 — Retrieval layer (weeks 1–4; ~2 days' effort; ~80% of near-term movement)

1. **Baseline assessment before anything** (protocol per delivery guide). For Lee: Lumen & Lever = practice run 0f — the founder's own before/after story.
2. **Entity consolidation** (fix #1, EntityIdentityConsolidation): one machine-readable graph. Schema.org `Person` + `Organization` with `sameAs` to LinkedIn, GitHub, all properties; plain indexable sentences stating relationships ("Lee Powell founded Lumen & Lever"; "rtfstruct powers Sourcetrace") on every relevant page; kill name variants.
3. **Buyer-language pages** (fixes #4/#6): literally-titled service + location pages matching the questions people actually ask. No page containing the phrase = nothing for retrieval to hand the model.
4. **Citation-gap raid** (fix #8, targeted): identify the exact lists, directories, roundups and profiles the *currently-recommended competitors* appear in (search the buyer questions; audit what surfaces and what the assistants cite), then obtain every legitimately available placement. These pages are proven to be in the answer path — the highest-leverage citations that exist.
5. **Third-party bio seeding** (fix #8/#5): book 1 meetup talk + 2 podcast guest slots now — the value is the indexed bio pages, transcripts, and backlinks within weeks, not the audience.
6. **Re-measure at 30 days** (light pulse) and 90 days (full) — deltas are the proof and the case study.

## Phase 2 — Cheap corpus entries (months 2–3; low effort; run while Phase 1 propagates)

- **Zenodo DOI on every open-source release** (~1 hour, free; GitHub→Zenodo integration). The DOI is plumbing — its value is the Crossref/Scholar/OpenAlex indexing chain behind it.
- **One JOSS paper** (Journal of Open Source Software) for the flagship tool (rtfstruct) — the most achievable genuinely citable artifact for a practitioner: software + short peer-reviewed paper.
- **One local talk per month** (PyCon-AU-tier meetups, not international keynotes) — each produces a speaker page, slides, video, transcript.
- **2–3 industry-publication pieces** (InfoQ / The New Stack tier) framed as engineering findings, not marketing.

## Phase 3 — Compounding authority (months 4–12+; only after the 90-day re-measure validates Phase 1)

arXiv preprints (endorsement needed) · conference circuit proper · **original terminology** in versioned papers (phrases get repeated; repetition gets cited) · the one-famous-OSS-project flywheel (adoption/dependents are the KPI, never stars) · standards-body contributions. **Recursive authority** is the selection principle throughout: seek citations from sources that are themselves cited and demonstrably ingested (framework docs, university pages, Stack Overflow, major-vendor cookbooks).

## Customer tier mapping (the productised cut-through)

| Customer type | Prescribe |
|---|---|
| Local trades, clinics, restaurants-tier | **Phase 1 only.** Corpus layer is irrelevant noise for them — saying so builds trust |
| Agencies, consultants, B2B services, professional firms | Phase 1 + Phase 2 (the practitioner-as-entity variant: the person is the hub) |
| Founder brands, tool builders, research-adjacent firms | Phases 1–3, with the honest clock on 3 |

## Claim discipline (binding)

Phase 1 outcomes are re-measurable within the 90-day window and may be reported as observed deltas. Phase 2–3 are **never promised** and never given a timeline in customer copy — the honest line stands: *retrieval-layer fixes propagate in days to weeks and we re-measure them; what the models remember from training changes slowly and no one can schedule it.* Composite scores (e.g. "entity recognition 4/10") remain banned; findings are expressed as counted observations.

## Verified answer-path findings — Melbourne AI advisory (28 Jul 2026)

ChatGPT's self-reported sources were independently verified (3-agent sweep: Clutch, Synap lattice, live query sweep). Results:

**Confirmed:** every URL ChatGPT cited exists (nothing hallucinated at URL level). Synap's buyer-phrase lattice is real and fully mapped: title/H1-level phrases on dedicated pages, per-city variants, a 16-node JSON-LD @graph (Organization, Person, ProfessionalService, Products, FAQPage, BreadcrumbList), FAQ questions phrased exactly as buyer queries (LLM-quotable Q&A), transparent on-page pricing (concrete numbers for models to cite), ABN + CBD address in footer, active sitemap, guide-style blog.

**Refuted — the confabulation catch:** the Clutch Melbourne AI page ChatGPT cited contains *none* of Synap, Integral Mind or Lumen & Lever (its top firms are dev shops: Dotsquares, DianApps, xfive…). "Synap dominates" overstated a 2-of-4-query showing. The model cited a real page and misattributed its contents — canonical example of why assistant-cited sources are leads, never findings. **Flip side: the Clutch AI-consultants Melbourne category is winnable — no boutique advisory is on it.**

**Baseline truth:** Lumen & Lever surfaced for *zero* of the four buyer queries. And a technical defect: lumenlever.com serves the full site HTTP 200 (no 301 to lumenandlever.com) — two indexable duplicates splitting link equity.

**The cheapest query in the market:** "fractional AI advisor Melbourne" — almost no directories rank; individual practitioners' single pages do (Synap's *Sydney* page ranks #1 for the Melbourne query). Winnable with one dedicated page.

### Lumen & Lever — week one, in order

0. **Canonical-domain fix first** (one line): 301 lumenlever.com → lumenandlever.com so every new citation accrues to one domain.
1. **Baseline assessment** (practice run 0f) — the before picture; today's verified truth is 0-of-4.
2. **Entity graph**: JSON-LD @graph mirroring the proven pattern — Organization + Person (Lee Powell) + ProfessionalService + FAQPage + BreadcrumbList, `sameAs` across LinkedIn/GitHub/properties; plain-sentence relationship statements on every page.
3. **The phrase lattice** (mirror targets, verified in the index): a dedicated **"Fractional AI Advisor Melbourne"** page first (cheapest confirmed win), then "AI Consulting Melbourne", "AI Readiness Assessment", each with FAQ blocks phrased as buyer questions. Consider on-page pricing — it demonstrably gives models concrete numbers to cite (business decision, not required).
4. **Placement raid** (all verified live in the answer path): Clutch free profile via clutch.co/get-listed + 2–3 verified client reviews (organic rank is review-driven; sponsorship exists but is not required — note the page's "we may earn a fee" disclosure) · GoodFirms · **aidirectory.industry.gov.au** (Australian Government AI directory — highest-authority free citation available) · iaaic.org · Built In Melbourne · DesignRush / TechBehemoths (medium) · Sortlist (low). Expertise.com deprioritised (no Melbourne AI category).
5. **The roundup play**: three of the ranking pages for these queries are competitor-authored "top AI companies Melbourne" blog posts (Enterprise Monkey, Team400, Flowtivity). Publish Lumen & Lever's own honest "Melbourne AI advisory landscape" roundup targeting the same phrases — replicating the exact mechanism that put them on page one. Honesty rule: genuinely useful, competitors included, no self-crowning.
6. **Bios**: one meetup talk + two podcast slots booked.
7. **30-day pulse** on the four buyer queries; 90-day full re-measure.

## Questions worth putting to an assistant (hypothesis generators, not evidence)

1. "Search again and list the exact pages you would draw from to answer '{buyer question}' — URL by URL."
2. "Which directories, lists or publications do {named competitors} appear in that {client} doesn't?"
3. "What does the web currently say about {client}? What entity confusion or gaps do you see?"
4. The same buyer question with browsing off, then on — parametric vs retrieval, live (two-arm protocol, informally).

Caveat recorded from the machine docs: assistant introspection about its own sourcing is partly confabulated — treat answers as leads to verify, never as findings. Observation (fresh sessions, counted, screenshotted) outranks interrogation.
