# VIDET — Disciplined Entrepreneurship Plan

Step 0 + Bill Aulet's 24 Steps, applied to the Commercial Discoverability Observatory.

Status: Working commercial plan, v2 (rewrite of the 23 July 2026 draft). Not a specification; does not override the Product Architecture Manual. Every market size, price, conversion threshold and unit-economic figure in this document is a **planning hypothesis and test instrument** unless marked as verified. Prepared 24 July 2026.

> **Category thesis.** VIDET makes commercial discoverability observable. It determines whether intelligent systems know, understand, trust and recommend a business — and creates an evidence-backed method for improving those outcomes. Canonical promise: **Become the answer** (PR-REQ-003).

---

## What changed in this rewrite

This plan supersedes the 23 July draft. The draft's discipline is retained — decided-vs-unvalidated separation, decision gates per step, the thin-complete-loop MVBP, the refusal to invent validated-sounding numbers. Six things are corrected:

1. **Brand.** VOI → VIDET everywhere. videt.ai is registered (24 Jul 2026); the trade-mark preparation pack (clearance knock-out, class 42/35/9 specifications, AU/US/UK/EU filing sheets) sits in `branding/trademark/` awaiting counsel. Naming is now an asset, not an open question.
2. **The beachhead/tenancy conflict is named and resolved.** The draft's MVBP — "a paid partner workspace supporting the lifecycle across multiple client businesses" — is not buildable on the frozen Volume I baseline: one Account belongs to exactly one Organization, cross-Organization views and consolidated exports are prohibited, and the consultant is a per-client invited persona (PR-REQ-007, 011 DOMAIN_MODEL). See Steps 2, 12 and 22 for the compliant v1 shape and the gated future decision.
3. **Grounded in what is actually built.** The platform layer is complete and frozen against casual reopening (tenancy with forced RLS, permission engine, command/event/audit ledgers, idempotency, scheduled actions); organisation genesis (S-02), invitation and role lifecycles are done; project creation (S-03 limb) and source registration (S-04 limb) are done; foundations F-01→F-04 are ratified ahead of ownership verification (S-05). 678 examples green. The Observatory extension builds on this — the draft treated the four vision documents as the only substrate.
4. **The OD-010 gate is explicit.** In-product external observation (search and AI surfaces) stays dormant until the owner approves the signed Measurement Set. Every pre-that-date pilot is therefore concierge/manual by necessity, not by preference — which conveniently is also the correct DE Step 21 sequence.
5. **A vocabulary landmine is flagged.** FUTURE-WORKFLOW-001 defines **Finding** as first-class; frozen 003 TERMINOLOGY lists "finding" as a disallowed variant of **Issue**. The vision set also collides with existing ADR-012/013 numbering in DECISIONS.md. Both must be resolved by ADR when the vision documents are filed canonically. Until then this plan uses *Issue* for the ratified deterministic pipeline and *(vision) Finding* only inside intervention-lifecycle language.
6. **The dodged DE mechanics are supplied.** Step 1 gets a real candidate-segment matrix, Step 4 a bottom-up TAM formula with to-be-validated ranges, Steps 15–16 three priceable packages as test instruments.

---

## The Canvas (one page)

| # | Box | Working answer |
|---|---|---|
| 1 | Raison d'être | Make commercial discoverability observable and improvable. Category: Commercial Discoverability Observatory. Principles: evidence first, immutable history, explainability, learning from failure. Assets: frozen Volume I/II spec, built Genesis platform, VIDET brand + TM pack, vision architecture, branding/website system. |
| 2 | Initial market | **Hypothesis:** owner-led digital agencies and established consultants with 10–50 retained client domains (AU + UK/US first, per OD-011 markets). Each client = its own Organization; practitioner invited per client. **Challenger to test in parallel:** multi-location service brands buying direct. |
| 3 | Value creation | Recurring observation, evidence-backed intervention plans, client-ready reporting. Value: labour replaced, a resellable new service line, decisions defensible to clients, measured machine-perception movement. |
| 4 | Competitive advantage | Core: longitudinal Commercial Discoverability Intelligence — verified intervention outcomes (including failures), protocol performance, calibrated confidence, on evidence rivals cannot reconstruct. |
| 5 | Customer acquisition | Paid 90-day Partner Pilot (founder-led), one required intervention lifecycle, nested partner + client DMU mapped per deal. |
| 6 | Product unit economics | Platform subscription + per-managed-business capacity; bounded observation allowances; no marketplace commission. All numbers TBV. |
| 7 | Revenue | Short: founder-led paid cohorts. Medium: evidence-led referrals, vertical cases, controlled partner enablement. Long: certified network, benchmarks, intelligence/API. |
| 8 | Overall economics | Margin depends on bounded sampling, declining support, efficient verification. Track partner CoCA, managed-business economics and provider costs separately. |
| 9 | Design & build | MVBP: thinnest complete lifecycle Reality → Observation → Issue/hypothesis → versioned Intervention Plan → verified execution → re-observation → Outcome, per client Organization. Concierge before automation; OD-010 gates in-product observation. |
| 10 | Scaling | Follow-ons: direct brands, franchises, enterprise reputation/governance, data/API. Sequence: evidence design → MVBP → partner scale → intelligence → advanced observatory. |

---

## Step 0 — Raison d'être

**Purpose (Aulet).** Why the venture exists; what must remain true as everything else changes.

**Working answer.** VIDET exists to make commercial discoverability observable, explainable and improvable. It is not an SEO reporting product. It is an observatory that compares business reality with provider-specific machine perception, coordinates measured interventions, and compounds validated learning into commercial intelligence.

**Evidence present.** VISION-001 (five governing questions; Reality/Perception/Intelligence), ADR-012/013 (architecture and Genesis conformance), FUTURE-WORKFLOW-001 (intervention learning lifecycle); frozen Volume I with evidence-first product law (no Issue without evidence, missing data never synthesized); the built platform above; VIDET brand secured with TM pack prepared; category narrative and claim-discipline system in `branding/000–002`.

**Assumptions / unknowns.** The market may need the immediate problem ("does AI recommend me?") before the Observatory category. Buyers must pay for recurring observability, not one novelty scan. Probabilistic association must never be sold as causal certainty.

**Actions.** Adopt the founder charter (evidence, immutability, explainability, provider independence, learning from failure). Two-level message: owner-dream promise outside (Become the answer), Observatory architecture beneath. File the vision set by ADR, resolving the Finding/Issue vocabulary and ADR-numbering collisions.

**Gate.** Proceed when the raison d'être is used to reject one attractive but category-diluting feature in writing.

---

## THEME 1 — WHO IS YOUR CUSTOMER? (Steps 1–5, 9)

### Step 1 — Market segmentation

**Working answer.** Segment by operating workflow and economic behaviour, not size. First-pass matrix (all scores hypotheses to be tested in PMR):

| Candidate segment | Recurring pain | Access | Budget | Portfolio leverage | Implementation authority | Evidence-sharing value |
|---|---|---|---|---|---|---|
| Owner-led digital agencies (10–50 clients) | High | High | Medium | High | High | High |
| Established solo consultants | High | High | Low–Med | Medium | Medium | High |
| Multi-location service brands (direct) | Medium–High | Medium | High | Medium | High | Medium |
| Franchise systems | Medium | Low–Med | High | High | Medium | Medium |
| Professional-services firms (law/accounting/health) | Medium | Medium | High | Low | Low–Med | Low–Med |
| Enterprise brand/reputation teams | Medium | Low | High | Low | Low | Low (procurement-heavy) |
| Platform/API consumers | Low today | Low | Unknown | High | n/a | High later |

**Actions.** Interview four behavioural segments (agencies, solo consultants, multi-location brands, one enterprise team); score on urgency, recurring workflow, willingness to pay, resale margin, evidence rights; exclude career-switching beginners.

**Gate.** No beachhead until one segment scores strongly on pain, access, budget, measurable outcomes and reference value.

### Step 2 — Select the beachhead

**Working answer (hypothesis).** Owner-led agencies and established independent consultants managing ~10–50 retained client domains in high-intent service categories, in Australia first, then UK/US (OD-011's approved English-speaking markets). They are users, implementation coordinators and distributors.

**The constraint the draft missed.** On the frozen baseline a practitioner has no cross-client surface: each client is its own Organization; the practitioner is invited into each with standard roles; no in-product roll-up, consolidated export or portfolio dashboard exists or may be implied (011 DOMAIN_MODEL; CAP-022 non-goal; multi-organization export prohibited). **v1 partner motion:** per-client Organizations + practitioner-assembled portfolio reporting outside the product. **Future decision (owner + ADR + capability contract):** a Partner Portfolio Console. Do not promise it; do not price it; test whether its absence blocks partner adoption — that result is itself a beachhead-validation datum.

**Actions.** Recruit 8–10 paid partner design participants, each contributing 3–5 client businesses (each onboarded as its own Organization); require at least one completed intervention lifecycle per partner; run a five-account direct-brand challenger cohort in parallel.

**Gate.** Confirm agencies as beachhead only if ≥5 sign paid pilots or LOIs with price and start date — and the per-client-Organization workflow survives contact (if partners abandon at multi-login friction, that is a pivot signal toward direct brands, not a reason to breach the tenancy model).

### Step 3 — End-user profile

**Working answer.** Primary user: owner-operator/strategy lead accountable for client retention and commercial outcomes; digitally capable, trusted, coordinates web/content/reputation work; needs a rigorous method to replace improvised prompting and screenshots. Secondary: implementation owners, client approvers.

**Actions.** Observe five live client-reporting sessions and three implementation hand-offs; map real roles onto the ratified role model (OrganizationAdmin, MarketingOperator, TechnicalImplementer — no invented "consultant role", PR-REQ-007); test lifecycle completion without founder assistance.

**Gate.** Lock the profile only when observed workflow, not stated preference, shows a repeatable high-value job.

### Step 4 — Beachhead TAM

**Working answer.** Bottom-up only: `TAM = qualifying partner organisations × (platform ACV + managed-business usage ACV)`. First-pass ranges, explicitly TBV: AU qualifying agencies/consultants fitting the behavioural filter — plausibly 2,000–6,000; UK+US same filter — plausibly 25,000–60,000; hypothesised blended ACV A$6k–15k. That sketches an AU beachhead in the tens of millions and an English-market beachhead in the hundreds of millions annually — **ranges exist to be attacked in PMR, not defended**.

**Actions.** Build a named list of 500 qualifying partners in one or two launch geographies; sample portfolio-size distribution directly; model platform revenue separately from partner-enabled end-client revenue.

**Gate.** Reject any model requiring "every marketing agency" to be a customer.

### Step 5 — Persona

**Working answer (provisional).** Owner-led digital consultant, ~18 retained service-business clients, AU east coast; clients now ask "what does ChatGPT say about us?"; currently answers with ad-hoc prompts and screenshots; needs a credible method, staged intervention plans, proof of implementation, client-ready reporting, and a new recurring revenue line without pretending certainty.

**Gate.** After the first paid pilot, the canonical persona must be a real, named design partner — no synthetic composite survives.

### Step 9 — Next 10 customers

**Working answer.** Ten named paid partners matching the behavioural beachhead, some concentrated in one high-intent vertical for comparability, plus the direct-brand challenger cohort.

**Actions.** Named list with role, portfolio, vertical, trigger and route; paid commitments including evidence-use and anonymised-learning rights; reject pilots that will not implement or re-measure.

**Gate.** ≥7 of 10 independently recognise the same high-priority problem, else revisit Steps 1–5.

---

## THEME 2 — WHAT CAN YOU DO FOR YOUR CUSTOMER? (Steps 6–8)

### Step 6 — Full life-cycle use case

**Working answer.** Partner selects a client business → client Organization exists (or is created) and the practitioner is invited → Reality established (verified Source, ownership proof — the ratified DNS/HTTP-file path) → observation contract defined → repeated observations (concierge until OD-010 Measurement Set activates; in-product after) → Issues and (vision) hypotheses → versioned Intervention Plan → client approval → execution recorded → implementation verified → comparable re-observation → measured Outcome → client report → learning retained.

**Assumptions.** Cognitive load; provider refresh delays lengthen time-to-value; some interventions won't attribute cleanly.

**Actions.** Concierge the full lifecycle before automating any state; design the practitioner view to hide none of the audit trail; measure drop-off per lifecycle state.

**Gate.** The lifecycle must produce value before any complex setup is asked of the user.

### Step 7 — High-level product specification

**Working answer.** An evidence-first Observatory and practitioner operating system: Reality setup; provider-independent observation contracts; immutable observation evidence; provider-specific Perception views; Issues separated from hypotheses; versioned Intervention Plans; approval/execution/verification workflow; comparable re-observation; outcome measurement; client reporting; accumulating Intelligence. Graphs may be represented relationally first — the concept is canonical, the storage engine is not.

**Evidence present.** ADR-012 (three graphs, eight layers); ADR-013 (Genesis conformance); FUTURE-WORKFLOW-001 (canonical aggregate + states); the built platform primitives these will consume.

**Gate.** Build only what the beachhead workflow requires to measure, explain and improve AI recommendation.

### Step 8 — Quantified value proposition

**Working answer.** Four measurable layers: practitioner labour replaced (baseline hours per client per reporting cycle); new recurring service revenue and margin per client; decision quality (prioritised, evidence-backed, client-defensible); measured machine-perception movement (recognition, accuracy, cited presence, recommendation frequency). Client-revenue attribution is a later, cautiously framed outcome — never the launch promise.

**Actions.** Before/after baselines for every pilot (hours, costs, service price, discoverability metrics); partners record actual implementation labour and resale value; report confidence and attribution strength, never theatrical certainty.

**Gate.** No revenue-impact claim until observed; lead with verified time, confidence and service-line value.

---

## THEME 3 — WHY YOU? (Steps 10–11)

### Step 10 — Define your core

**Working answer.** The longitudinal Commercial Discoverability Intelligence system: structured relationships among reality, provider-specific perception, immutable observations, Issues, hypotheses, intervention plans, actual implementations, verification quality, measured outcomes and calibrated confidence. The moat is the accumulated, auditable record of what works, what fails, under which conditions, for which providers — including negative results, which competitors discard.

**Assumptions.** No practical moat until enough comparable lifecycles exist; data rights and anonymisation must be contractual from pilot one; graph vocabulary must not become architecture theatre.

**Actions.** Fix the canonical ontology and minimum structured fields now; secure contractual rights to anonymised aggregated outcomes in every pilot agreement; version protocols, plans, confidence models; retain failed experiments.

**Gate.** Every roadmap item must strengthen measurement trust, the reality/perception record, or the action-to-outcome learning loop.

### Step 11 — Competitive position

**Working answer.** Chart on the customer's two top priorities (hypothesis): **evidential trust** and **implementation usefulness**. AI-visibility monitors sit low-workflow/variable-evidence; SEO suites offer breadth without machine-perception causality; consultants offer interpretation without repeatability. VIDET claims high-traceability + high-workflow-depth with compounding cross-business learning. Honesty rule from the website strategy carries here: several wave tools are measurement-first — differentiate on evidence standards (published methodology, deterministic evaluation, consent-verified measurement, citation-traceable claims), not on a "they're just tactics" straw man.

**Gate.** If prospects don't rank evidence/actionability top-two, redraw the map rather than defending it.

---

## THEME 4 — HOW DOES YOUR CUSTOMER ACQUIRE THE PRODUCT? (Steps 12–13)

### Step 12 — Decision-making unit

**Working answer.** Partner DMU: owner is usually champion + economic buyer; larger agencies add strategy/delivery/finance. Nested client DMU per intervention: business owner/marketing lead approves spend and public-facing changes; implementation owner executes; the ratified role and approval model already expresses this (client-side approvals happen inside the client's Organization, by client-side actors — a governance feature to sell, not a workaround).

**Actions.** Map both DMUs for every pilot; record who approves budget, evidence use, implementation, public changes; keep cohort one owner-accessible, no enterprise procurement.

**Gate.** No opportunity qualified until champion, economic buyer, approval path and likely blocker are explicit.

### Step 13 — Process to acquire a paying customer

**Working answer.** Paid, bounded Partner Pilot: trigger (client AI question or differentiation need) → qualification (portfolio + implementation capacity) → demonstration on one real business → evidence/learning-rights agreement → paid pilot → baseline → client approval → one verified intervention → re-observation → measured review → portfolio expansion.

**Actions.** 90-day paid offer, five managed businesses, one required intervention lifecycle; evidence demonstration and client resale kit; instrument every stage and loss reason.

**Gate.** Shortest process that preserves trust; remove any free step that doesn't raise qualified conversion.

---

## THEME 5 — HOW DO YOU MAKE MONEY? (Steps 15–19, with 14 in Theme 6)

### Step 15 — Business model

**Working answer.** Partner subscription + managed-business capacity + bounded observation allowances; higher tiers add white-label reporting, collaboration seats, later benchmark/intelligence access. Partners charge clients for assessment, observability and implementation; VIDET monetises the system and the intelligence, never a marketplace commission in the MVBP.

**Gate.** No "unlimited" entitlement without measured cost ceilings — this is also ratified entitlement law (hard daily limits exist by policy).

### Step 16 — Pricing framework

**Working answer.** Price against partner economic gain (labour removed, resale enabled, retention supported). Three test packages (hypotheses, AU-market first — instruments, not commitments):

| Package | Test price | Contents |
|---|---|---|
| Partner Pilot (90 days) | A$4,500–7,500 one-off, creditable to annual | 5 managed businesses, 1 full intervention lifecycle, founder-assisted |
| Partner Standard | A$500–900/month + A$60–120 per managed business/month | bounded observation allowance, client reporting |
| Partner Plus | A$1,200–2,000/month | higher volume, white-label, collaboration, priority verification |

**Actions.** Test through real proposals only; capture resale price, delivery labour, support cost per pilot; no low-priced self-serve plan until a genuinely self-serve workflow exists.

**Gate.** Reject any price that cannot fund methodological credibility and education.

### Step 17 — LTV

**Working answer.** Cohort-observed only. Drivers: platform retention, managed-business count, observation volume, benchmark/intelligence attach, partner survival. Prior illustrative figures are planning arithmetic, not evidence.

**Gate.** No uncapped-churn formulas in any investor or operating decision; conservative cohort LTV as soon as data exists.

### Step 18 — Scalable revenue engine

**Working answer.** Short: founder-led named-cohort sales, deeply assisted pilots. Medium: partner referrals, vertical case evidence, practitioner education attached to the product. Long: controlled certified partner network, benchmark-led demand, integrations, data/API. Certification supports distribution; it must not become a course business.

**Gate.** Scale only motions with known conversion, payback and customer quality.

### Step 19 — CoCA

**Working answer.** Fully loaded (founder time, education, demos, enablement, onboarding, methodology support), split by channel (direct partner, partner-referred, direct brand). Today CoCA is unknown; treat every founder hour as cost.

**Gate.** No paid channel scales until cohort LTV/CoCA is credibly above 3 with payback inside available capital.

---

## THEME 6 — HOW DO YOU DESIGN, BUILD AND SCALE? (Steps 14, 20–24)

### Step 14 — Follow-on TAM

**Working answer.** Size independently after beachhead proof: direct multi-location brands, franchise systems, professional-services groups, enterprise brand/reputation and governance, specialist implementation networks, API/data customers. The largest long-term market is probably direct organisational observability and risk governance, not agency tooling.

**Gate.** Enter a follow-on only when beachhead retention is strong and ≥70% of the core transfers unchanged.

### Step 20 — Identify key assumptions

**Working answer (ranked by kill-risk).** 1) Recurring, budgeted pain exists (not curiosity). 2) Repeated observation produces trustworthy, explainable signals (measurement reliability). 3) Practitioners complete lifecycles (implement, verify, re-measure) without founder pushing. 4) Partners resell profitably. 5) Per-client-Organization tenancy is acceptable to partners (the Step 2 constraint). 6) OD-010 Measurement Set approval lands before in-product observation is promised to anyone. 7) Data rights permit aggregated learning. 8) Interventions produce measurable movement inside pilot patience windows.

**Gate.** Test order by existential risk × test cost; measurement reliability, willingness-to-pay, lifecycle completion and partner resale are the first four gates.

### Step 21 — Test key assumptions

**Working answer.** Small controlled experiments: repeated-provider sampling under stable observation contracts (manual, pre-OD-010); blinded analyst agreement on Issues; concierge intervention plans; paid pilots; implementation-evidence audits; staggered re-observation; partner resale tests; confidence calibration against observed outcomes. Preserve contradictory and null results.

**Gate.** Automate a workflow only after its concierge version creates repeated value and measurement passes reliability thresholds.

### Step 22 — Define the MVBP

**Working answer.** The thinnest complete learning loop, per client Organization, consuming the built platform: establish reality (registered + verified Source — S-04/S-05 path); define question and provider scope; repeated immutable observations (concierge collection into the ratified Evidence subsystem until OD-010 activates); evidence-backed Issues and (vision) hypotheses; one versioned Intervention Plan; recorded execution; verified implementation; comparable re-observation; measured Outcome; partner/client report. Cross-business intelligence publication stays manually governed. **Explicitly out:** partner portfolio console (owner decision required), marketplace/payouts, public directory, autonomous agents, broad SEO suite, public benchmarks, certification.

**Sequencing reality.** The build path runs through the ratified foundations first: F-01 outbound transport → F-02 envelope encryption → F-03 evidence producer → F-04 background execution → S-05 verification → S-06 source activation → S-07+ observation/evaluation slices. The intervention-lifecycle extension is a Volume III specification exercise on top — conformant with ADR-013, using the same primitives.

**Gate.** MVBP is complete only when a partner pays, receives recurring value, and can explain why they'd be worse off without it.

### Step 23 — Dogs eating the dog food

**Working answer.** Proof = behaviour + economics: partners pay, onboard multiple real client Organizations, obtain client approvals, implement, submit evidence, complete comparable re-observation, review outcomes, request another cycle. A successful first report without implementation or renewal is failure data.

**Actions.** 90-day paid cohort, 5–8 partners, 15–30 businesses; ≥1 complete lifecycle per partner; interview non-converters and churned partners with equal rigour.

**Gate.** No product-market-fit claim from free users, verbal enthusiasm, one-off scans or founder-assisted usage.

### Step 24 — Product plan

**Working answer.**
- **Phase 0 — evidence design:** ontology, observation contracts, data-rights templates, concierge lifecycle; file the vision set by ADR (vocabulary + numbering resolved); obtain OD-010 Measurement Set approval.
- **Phase 1 — MVBP:** per Step 22, on the F-01→F-04 → S-05/S-06 → observation-slice sequence.
- **Phase 2 — workflow and partner scale:** lifecycle automation, collaboration, white-label reporting, protocol library, controlled enablement; the Partner Portfolio Console decision lands here (owner decision + capability contract) informed by pilot friction data.
- **Phase 3 — intelligence:** benchmarks, protocol effectiveness, confidence calibration, recommendation support from validated history.
- **Phase 4 — advanced observatory:** predictive simulation, autonomous intervention agents, data/API products — only with evidence density to deserve them.

**Gate.** No phase begins until the previous passes its customer-value, reliability and unit-economic gates. Roadmap follows evidence density, not architectural elegance.

---

## Primary Market Research plan (six weeks)

| Week | Focus | Output |
|---|---|---|
| 1 | Prepare | Interview guide, segment matrix, 500-name list seed, assumption register with thresholds |
| 2 | Problem evidence | 10 agency/consultant interviews + observation of 2 live reporting workflows; no pitching |
| 3 | Segment comparison | 10 more partner interviews + 10 multi-location-brand interviews |
| 4 | Concierge test | 3–5 manual audits with repeated sampling, evidence and action plans (also seeds the "State of AI Discoverability" study — see `branding/001` §7) |
| 5 | Commercial test | Paid pilot proposals at the Step 16 package variants; DMU mapped per deal |
| 6 | Decision | Select/reject beachhead; freeze MVBP boundary; approve measurement methodology experiment; update this plan |

Interview discipline (kept verbatim in spirit from the draft): collect the most recent real occasion, actual behaviour, budget source and consequence of inaction; never ask "would you use this?", never teach the problem before measuring it.

## 90-day decision plan

- **Days 1–30 — prove the problem:** PMR complete; real persona selected; measurement repeatability study running (manual); five paid-pilot candidates.
- **Days 31–60 — prove the value:** concierge audits delivered; paid proposals issued; MVBP frozen around observed behaviour; variable-cost model drafted.
- **Days 61–90 — prove the loop:** first paid cohort; two reporting cycles where possible; adoption, reuse, resale, cost and conversion measured; continue/pivot/stop decision.

**Day-90 gates:** one narrow segment shows recurring high-priority pain; ≥5 partners pay or sign time-bound commitments at sustainable prices; customers trust and reuse the evidence; repeated sampling yields explainable confidence; credible path to LTV/CoCA > 3; captured data strengthens the core rather than a generic services business. **Stop/pivot triggers:** one-off curiosity, disguised consulting, outcomes indistinguishable from provider noise, or partner abandonment at per-client tenancy (→ test direct-brand pivot before any tenancy-model change).

## Final assessment (this rewrite's view)

The Observatory direction materially improves the venture: from commoditisable monitoring toward a defensible learning system with a practitioner delivery layer. The architecture is unusually strong for this stage — and that is exactly the risk. The scarce resources are paid proof and measurement credibility, not design. Scores in the draft (opportunity 8.5, coherence 9, defensibility 9, commercial proof 4, methodological proof 3.5) are directionally fair; treat them as rhetoric, not measurement. The single most important sentence in the draft survives unchanged: **build the thinnest complete learning loop, sell it immediately, and let measured customer behaviour — not the elegance of the future architecture — determine what becomes real next.** Two additions this rewrite insists on: the tenancy-compliant partner motion is a testable hypothesis with a defined pivot, and no external observation is promised to any customer before the OD-010 Measurement Set is approved.

## Source basis

VISION-001; ADR-012; ADR-013; FUTURE-WORKFLOW-001; frozen Volume I (`v1.5-volume-i-frozen`) and Volume II implementation contracts; PROJECT_STATE.md implementation state (2026-07-23/24) including the F-01→F-04 foundations ratification (DECISIONS.md ADR-024); branding/000–002 and branding/trademark/; the 23 July 2026 draft plan (superseded by this document).
