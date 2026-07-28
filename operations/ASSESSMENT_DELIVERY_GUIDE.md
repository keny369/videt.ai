# VIDET — Assessment Delivery Guide

Status: Operating guide v1, 27 July 2026. The complete manual method for delivering AI Recommendation Assessments to the first 20 clients — and the codification bridge that turns every manual assessment into future platform data.

Companions: `investor/30_DAY_REVENUE_PLAN.md` (the calendar; its Appendix D is the protocol floor — this guide extends it, overrides nothing), `investor/QUESTION_BANK.md` (question sets), `specification/machines/000 MACHINE_BEHAVIOUR_SYNTHESIS.md` (the evidence base for everything here), `branding/004 FOUNDING_COHORT_OFFER.pdf` (the offer).

> **The method in one sentence:** capture ground truth (Reality Card) → audit the surfaces machines actually read (Readiness Audit) → observe what assistants say (Protocol runs) → compare, count and classify (Findings) → fix what the consensus says matters (Fix Library) → verify, then re-observe (Value Cadence) — logging everything in the schema the platform will later ingest.

---

## Part 1 — The two service grades (and the claim rules that keep you honest)

| Grade | Sampling | What it CAN say | What it MUST NOT say |
|---|---|---|---|
| **Screening** (the A$990/1,490 assessment) | ≥3 fresh-session runs per question per assistant | Counts and observations: "appeared in 2 of 12 runs", "address wrong in 4 runs", "conflated with X twice" — plus variance flags | Percentages presented as stable rates; competitor comparisons; trend claims; any composite score |
| **Instrument** (re-measures, drill-downs, the published study) | 10+ runs per condition (20–30 for client-facing rates), on the client's 5 highest-value questions | Rates **with Wilson intervals and N displayed**; before/after deltas; search-on vs search-off attribution | Causality without controls; permanence; anything about model internals |

The machines' own verdict, adopted as policy: 3 runs is *"a smoke test only"* — powerful for catching gross failures (absence, wrong facts, entity confusion), meaningless for statistics. Sell the screening grade as exactly that: a diagnostic, not a leaderboard. The 90-day re-measure runs the client's 5 money questions at instrument grade (2 assistants × 10 runs = 100 queries ≈ 2.5h) — which is why the A$1,490 bundle is priced above the single assessment.

**Language law (all grades):** counts not scores · every number carries its N · "observed on [date], [assistant]" on every claim · variance reported as a finding, not hidden · abstain where evidence is thin ("we could not distinguish X from Y on this sample") — abstention builds the trust that closes the fix-it engagement.

## Part 2 — The onboarding workflow (per client, with time budget)

| Step | What | Time | Output |
|---|---|---|---|
| 1 | Intake call (or form) — Part 3 fields | 20 min | Completed intake |
| 2 | Build the **Reality Card** | 40 min | Ground truth doc |
| 3 | **Readiness Audit** — Part 4 layers | 60–75 min | Surface-by-surface pass/gap table |
| 4 | Select questions (QUESTION_BANK recipe: ~22 incl. 2 controls) | 15 min | Question sheet |
| 5 | **Observation runs** — Part 5 protocol | 2.5–3.5 h | Run log + screenshot folder |
| 6 | Analyse & classify — Part 6 metrics, Part 7 taxonomy | 45 min | Findings table |
| 7 | Assemble report — Part 9 | 60 min | Client report PDF |
| 8 | Walkthrough call (+ re-measure/referral asks) | 45 min | Testimonial, referrals, fix plan agreed |
| 9 | Log everything in the run schema — Part 12 | 15 min | Future platform data |

Total ≈ 6.5–8 h for the first ones, trending to ≈ 4.5 h by client five as templates harden. Whatever step still eats time at client ten is the September automation shopping list.

## Part 3 — The Reality Card (ground truth before observation — non-negotiable)

You cannot mark a machine's answer wrong without knowing what's true. Capture, verbatim and dated:

1. **Identity:** legal name · trading name(s) · ABN/ACN · entity type · GST status (ABN Lookup screenshot)
2. **Canonical NAP:** the ONE correct name/address/phone/website — as the client asserts it
3. **Registrations & licences:** every register they should appear on, with number and screenshot (see Part 4, Layer 1 per vertical)
4. **Services:** the true service list, each mapped to the page URL that describes it (no page = a gap already)
5. **Locations & service area:** physical sites; suburbs genuinely served; suburbs NOT served (feeds the wrong-area control)
6. **People:** named practitioners + their individual registrations where the vertical has them
7. **Hours**, review-profile locations (the exact GMB/Yelp/etc. listings they own), and social/company pages
8. **Confusable entities:** similarly named businesses, the practitioner-vs-firm split, old trading names — this list is what makes Entity Conflation detectable

## Part 4 — The Readiness Audit (the surfaces machines actually read)

Work the layers in order; mark each item ✔ pass / △ gap / ✘ fail / n/a, with a one-line note and screenshot for anything not-pass. AU surfaces named below; US/UK/CA equivalents are inventoried in `business_recommendation_urls_AU_US_UK_CA.md` (393 surfaces — file it into the repo).

**Layer 1 — Identity & registers (the gate):** ABN Lookup record correct · ASIC company/business-name record · vertical register present-and-accurate: TPB (tax/BAS), ASIC Financial Advisers Register + AFS (advice), AHPRA (health incl. cosmetic/dental/physio/chiro/osteo/psych), state law society / bar (legal), state building authority — VBA/NSW Fair Trading/QBCC/WA BSB/SA/TAS/ACT (builders & trades), state property licence (real estate/buyers agents), ACECQA/Starting Blocks (childcare), NDIS register where relevant, CPA/CAANZ/IPA membership (accounting), MFAA/FBAA (brokers), manufacturer authorised-installer listings (specialist trades — SprungFloors-class businesses live or die here)
**Layer 2 — Maps & local:** Google Maps listing resolves to ONE correct entity (name/address/phone/hours/categories) · Apple Maps · Bing Maps · listing ownership claimed
**Layer 3 — Reviews:** Google review count/recency/response rate · Yelp/Trustpilot where the vertical uses them · reviews landing on the CORRECT listing (branch confusion is an Entity Conflation seed)
**Layer 4 — Website technical:** indexed-page count (`site:` check) · service pages literally titled for buyer language · location/service-area pages · practitioner pages matching register names · schema.org JSON-LD (LocalBusiness + services + sameAs) present and valid · PageSpeed/accessibility sanity · site crawlable (no JS-walled content on key pages) · Wayback history sanity
**Layer 5 — Corroboration:** LinkedIn company + practitioner profiles consistent · industry association memberships listed · any authoritative third-party citations/directories for the vertical · news mentions
**Layer 6 — Red flags (handle per Part 11):** adverse-terms search · AustLII/court/tribunal · ASIC banned & disqualified · AFCA (financial) · ACCC/Product Safety/Ad Standards · AHPRA tribunal decisions (health)

The audit output doubles as the fix plan's skeleton: every △/✘ maps to a Fix Library entry.

## Part 5 — Observation protocol v0.2 (extends 30-day plan Appendix D)

Everything in Appendix D stands (20–25 questions from the bank recipe, ≥3 samples, fresh sessions, ≥2 days, screenshots, counts). **Paste-ready instrument: `operations/PROBE_PROMPT_KIT.md`** — the staged probe prompts (natural question → follow-ups → JSON transcription), operator envelope, verification rows and confabulation-capture schema. Use the kit's prompts verbatim; phrasing changes are new phrasing IDs. Add:

1. **Session hygiene:** fresh conversation per run; logged-out or clean-profile where practical; record what you *can* observe (surface, model label, search on/off if shown) — never claim personalisation was absent, only that none was configured.
2. **Location discipline:** record the location form used in each question (suburb / city / "near me"); run "near me" variants only with the location stated in-prompt; note your own IP city in the run log once per session.
3. **Position capture:** record rank position of every business named, not just the client (feeds Position-Weighted Score and names the true competitors).
4. **Two-arm where the surface allows:** if the assistant exposes a web-search toggle, run the 5 money questions both ways — search-ON divergence from search-OFF tells the client whether their problem is retrieval footprint (fixable in weeks) or model memory (slow, unpromisable). Label arms in the log.
5. **Controls (per Appendix D) plus one:** wrong-service, wrong-area, **and one similar-name probe** ("Is {confusable entity from the Reality Card} the same as {client}?") — direct Entity Conflation test.
6. **Follow-up chain (one per session):** the forced-choice ("if I could only call one today, which?") is mandatory — it feeds the Anchoring finding; then "give me their contact details" — the wrong-facts harvest; then **source elicitation** — "which pages did you draw those names from?" The cited sources become the client's placement-raid leads, but every one is **verified before it appears in a report or fix plan**: assistants cite real pages and misattribute their contents (canonical case, 28 Jul 2026: ChatGPT cited Clutch's Melbourne AI page as supporting firms that do not appear on it — `operations/AUTHORITY_ROADMAP.md`, verified findings). *Note: the phrasings in this item describe the chain's function; the paste-ready instrument text is `PROBE_PROMPT_KIT.md` Stage B (FB1–FB3), used verbatim. The contact-details harvest is an additional follow-up — give it its own phrasing ID.*
7. **Run-failure quarantine:** a run containing a fabricated business, an unresolvable entity collision on the client, or a citation that doesn't support its claim is still evidence — but flag it `defective_observation` and report it as its own finding class, never silently averaged.

## Part 6 — Metrics (definitions you report against)

For entity *e* over *N* fresh runs of a question set:
- **Mention Rate** `MR = runs mentioning e ÷ N` (instrument grade only as a rate; screening grade reports the raw count)
- **Position-Weighted Score** — VIDET reporting weights, declared in every report as *our convention, not model internals*: 1st = 1.00 · 2nd = 0.70 · 3rd = 0.50 · 4th = 0.35 · 5th+ = 0.20 · unranked mention = 0.10 · absent = 0
- **Entity Resolution Fidelity** `ERF = correct fields (name/phone/address/URL/services) ÷ fields asserted by the assistant`, judged against the Reality Card
- **Citation Accuracy Rate** = of URLs/sources the assistant cites about the client, the share that exist AND support the attributed claim
- **Follow-up Anchoring Index** = share of forced-choice follow-ups won by the first-listed candidate (reported for the *category*, it contextualises any "the AI picked us/them!" excitement)

## Part 7 — Findings taxonomy (what every observation becomes)

Classify every non-pass observation as exactly one of: **Absence** (not mentioned for a served intent) · **Entity Conflation** (facts merged with a confusable) · **Temporal Hallucination** (stale facts as current) · **Geographic Boundary Breach** (recommended where they don't serve / absent where they do) · **Authority Spoofing** (marketing treated as authority) · **Anchoring Fragility** (present but collapses under follow-up) · **Defective Observation** (run-failure class — reported, not averaged). Each finding carries: the verbatim machine text, run reference, date, assistant, and the Reality Card field it contradicts.

## Part 8 — The Fix Library (findings → interventions, with verification and clocks)

Every fix maps to a canonical intervention type from FUTURE-WORKFLOW-001 — so today's manual advice is tomorrow's platform vocabulary. Confidence tiers from the machine consensus.

| # | Fix (intervention type) | Typical trigger findings | Tier | Verification step | Expected clock |
|---|---|---|---|---|---|
| 1 | **EntityIdentityConsolidation** — one canonical NAP everywhere; kill duplicates/old listings; disambiguate from confusables | Entity Conflation, Absence | High | Re-crawl each surface; duplicate listings gone | 1–4 weeks |
| 2 | **ThirdPartyProfileCorrection** — fix maps/directories/register listings (address, categories, hours) | Temporal Hallucination, Boundary Breach | High | Screenshot corrected listing live | Days–3 weeks |
| 3 | **StructuredDataCorrection** — valid JSON-LD (LocalBusiness, services, sameAs to registers/socials) | Absence, Conflation | High | Schema validator pass; re-crawl | 1–6 weeks (index) |
| 4 | **ContentClarification** — literally-titled service + location pages in buyer language; answer the problem-first questions on-page | Absence (esp. problem-first) | High | Pages live, indexed (`site:` check) | 2–8 weeks |
| 5 | **KnowledgeSourceAlignment** — practitioner pages matching register records; register entries current | Authority gaps, Conflation | High | Register + site show identical names/credentials | Days–4 weeks |
| 6 | **LocationCorrection** — explicit service-area statements; correct geo signals | Geographic Boundary Breach | High | Corrected surfaces live | 1–4 weeks |
| 7 | **ReviewSignalImprovement** — recent, specific reviews on the correct listing; owner responses | Weak presence, Absence | Plausible | Review count/recency delta on correct listing | Rolling, 4–12 weeks |
| 8 | **CitationAcquisition** — authoritative directory/association/editorial citations for the vertical | Absence, weak corroboration | Plausible | Citations live and indexed | 4–12 weeks |
| 9 | **AuthorityContentPublication** — case studies, credential-backed niche content | Absence in specialist intents | Plausible | Published + indexed | 6–12 weeks |
| 10 | **TechnicalAccessibilityCorrection** — crawlability, JS-walled content exposed, key facts in first 200 words | Absence despite good content | High | Rendered-text check; index count | 1–6 weeks |

**Tier 3 — corpus-layer fixes (consultants/B2B/founder brands only; see `operations/AUTHORITY_ROADMAP.md`):** DOI-indexed publications (Zenodo/JOSS), talk and podcast bio seeding, original terminology in versioned papers, open-source adoption signals. Clock: months-to-years, governed by model training cycles — prescribed as strategy, **never promised, never given a timeline in customer copy**. For local-services customers this tier is explicitly omitted, and saying so is a trust move.

**What VIDET refuses to sell** (say it in the report — it builds trust and matches the machine consensus): AI-keyphrase stuffing ("LLM-optimised copy") — classed *unproven speculation* by the machines themselves; review manipulation; anything promising a guaranteed mention. **Never promise** changes to model parametric memory — the honest line: *"retrieval-layer fixes propagate in days to weeks and we re-measure them; what the model remembers from training changes slowly and no one can schedule it."*

## Part 9 — Report assembly (extends Appendix D §6 skeleton)

Section order: (1) The questions your customers ask · (2) What the machines said — counts, excerpts, screenshots · (3) **Two pictures** — Reality Card vs what assistants believe, gaps highlighted · (4) What they got wrong — facts table (each with run reference) · (5) Who they named instead — factual, attributed · (6) **Readiness scorecard** — Part 4 layers as ✔/△/✘ per surface · (7) The ten fixes — from Part 8, prioritised by tier × trigger severity, each with its verification step and clock · (8) What happens next — the 90-day re-measure. Footer on every report: evidence-backed line + the Part 11 disclaimers. Visual execution follows `branding/006 BRAND_PACK.md` §4.2–4.3: filled master mark in the header, counts/dates/IDs in the mono, the verification seal at most once per report.

## Part 10 — The value cadence (measurable value before the platform exists)

- **Week 0:** assessment delivered; fix plan agreed; owner assigned per fix (client / their web person / you)
- **Weeks 1–3:** client executes Tier-1 fixes (most are listings, registers, schema, pages); you verify each fix (Part 8 column 5) — *verification is a deliverable*: send the "implemented and confirmed live" note
- **Week 4:** light pulse — the 5 money questions, 1 assistant, 3 runs (~30 min); email the delta counts. This monthly pulse is 30 minutes of work that renews the relationship
- **Week 8:** second pulse + nudge outstanding fixes
- **Week 90-day:** instrument-grade re-measure (the bundle deliverable): before/after on the 5 money questions with real Ns; the delta narrative is the case study — and the client's reason to continue
- Every artefact (fix confirmations, pulse emails, delta reports) goes in the client evidence folder — the folder IS the future case study and the platform's seed data

## Part 11 — Legal & ethics guardrails (non-negotiable)

1. Raw machine outputs stay private; reports contain verified, attributed observations only
2. Machine statements about **third parties** are never republished as fact — "Assistant X named [competitor] in 11 of 12 runs" is reportable; the assistant's *opinions* about the competitor are not
3. Adverse-record findings (Layer 6) about your own client are handled verbally first, in the report only as verified public record with source
4. Regulated verticals: every report carries *"This is a measurement of AI assistant behaviour, not professional, financial, legal or medical advice."*
5. No guarantees of mention, position or timing — ever, anywhere, including sales conversations
6. Manual, human-scale querying only in this phase; no scraping or automation ahead of the ToS analysis in counsel's brief and the OD-010 decision
7. All client data handled under the engagement terms; evidence folders per client, not commingled

## Part 12 — The codification bridge (do this and the platform inherits everything)

Log every run, every audit item, every fix in these shapes from client one:

**Run log (one row per run)** — `run_id · client · date_time · assistant · model_label_shown · search_arm(on/off/unknown) · session_fresh(y/n) · question_id · question_class(A–I/control) · location_form · client_mentioned(y/n) · position · cited(y/n) · other_businesses_named[ranked] · facts_asserted_about_client · facts_wrong[field:said→true] · caveats_present(y/n) · follow_up_type · follow_up_winner · defective(y/n+reason) · screenshot_ref`

**Audit log (one row per surface)** — `client · layer · surface · country · status(✔/△/✘/na) · note · screenshot_ref · fix_id(if gap)`

**Fix log (one row per fix)** — `fix_id · client · intervention_type(Part 8) · trigger_finding_ids · owner · agreed_date · implemented_date · verified_date · verification_evidence_ref`

These map 1:1 onto the future platform's Observation, Evidence and Intervention Plan records (FUTURE-WORKFLOW-001). Twenty clients logged this way = the platform's first dataset, the calibration baseline for confidence models, and the raw material of the "State of AI Discoverability" study — three assets for the price of doing the work properly once.

---

**Missing-inputs checklist (fill before client one):** intake form built from Part 3 · report template shell (exists per Appendix D — add Part 9 sections 3 and 6) · the three log sheets as spreadsheet tabs · the URL inventory file moved from Desktop into the repo · client engagement terms reviewed against Part 11 (one item for Luisa alongside the trademarks).
