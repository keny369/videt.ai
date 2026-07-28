# Videt Website Strategy

Status: Working strategy executing `000 STRATEGY_BRIEF.md`. Marketing document — does not override the Product Architecture Manual. Every product claim herein carries its governing identifier; copy derived from this document inherits those constraints.

## 1. Positioning

**Category:** the Commercial Discoverability Observatory (VISION-001) — the category story the site claims and owns. The ratified spec label remains Discoverability Intelligence Platform (ADR-003, PR-REQ-001) until an ADR changes it; the website uses the Observatory as narrative, once per page, never as the headline — the category is the answer to "so what is it?", delivered after the problem has landed.

**Promise & tagline:** Become the answer. (PR-REQ-003 — spec-canonical, ownable; the brand tagline, the closing line of every page, and a candidate second trade mark. Usage rules: `006 BRAND_PACK.md` §5.)

**Organising frames:** Google indexed the web. AI evaluates it. — and the owner's version: **your business exists twice — as it is, and as the machines believe it is.** The commercial question is no longer "how do I rank?" but "will the machine choose me?" (VISION-001).

**One-sentence definition (the 5-second answer):**

> Videt shows you what the machines believe about your business — and measures it against what's true, with evidence behind every number.

**The strategic resolution of the search/AI tension:** the ratified product measures both search and AI answer surfaces (ADR-003, PR-REQ-002). The website does not present these as two product lines. Search presence is presented as part of the evidence AI weighs — the substrate of evaluation. This keeps the AI-first story honest and makes the search pillars reinforce, rather than dilute, the category narrative:

> AI doesn't invent its answers. It evaluates what it finds — your pages, your structured data, your consistency, your authority. Videt measures what AI has to work with, and what it does with it.

## 2. The Category Narrative

The manifesto thread, woven through every page and published in full as a standalone essay (see IA §6). It is written to the owner — their business, their name, their customers:

1. First they listed you. Then they ranked you. Then they learned about you. Now they answer *for* you. (The four eras — directories, search engines, knowledge graphs, generative intelligence — VISION-001.)
2. Your next customer doesn't scroll a list any more. They ask a machine who to trust, and they get one answer.
3. Which means your business now exists twice: as it really is, and as the machines believe it is. The gap between those two decides whether your name comes up.
4. Five questions decide everything. Does the machine know you exist? Does it understand what you offer? Does it trust what it knows? Does it recommend you? And why?
5. Today you cannot answer a single one of them. Nobody can — the gap is invisible until it is measured.
6. Videt is the observatory for that gap: it watches how the machines see you, measures it against what's true, and shows you — with evidence you can inspect — what to change and whether it worked.
7. Become the answer.

The essay names and claims the category in plain terms — the Commercial Discoverability Observatory — because a category cannot be owned by a company unwilling to say its name in the flagship artifact. Everywhere else the label stays subordinate to the problem (§1).

Tone rule: the narrative is never fear-marketed ("you're invisible and dying"). It is stated as a structural shift, calmly, the way Stripe wrote about internet infrastructure. The reader supplies their own urgency — that is the brief's success metric working as designed.

## 3. Messaging Architecture

The five-question ladder from the brief, mapped to on-page mechanics:

| Time | Visitor question | Answer mechanism |
|---|---|---|
| 5s | What is Videt? | Hero headline carries the 5-second job as the customer's own question; the one-sentence definition lands by ~10 seconds |
| 15s | Why does this matter? | Hero subhead: buying decisions increasingly begin as AI questions |
| 30s | Why now? | "Indexed → evaluated" section immediately below the fold |
| 60s | Why trust Videt? | Evidence principle + non-invasive posture + methodology link |
| Exit | What next? | Early-access CTA (pre-launch) / Get your Discoverability Score (post-launch) |

Five-second comprehension tests (§7) score against this reading of the ladder.

**Message house:**

- **Roof (promise):** Become the answer.
- **Pillar 1 — Measurement you can defend.** Deterministic, reproducible assessments; seven scored pillars; every Issue traces to evidence; missing data is never synthesized (PRULE-010, PRULE-011; no-synthesis per WF-012 and PRULE-043 explicit-unavailable semantics).
- **Pillar 2 — Answers, not dashboards.** Decision-ready guidance ranked by impact, confidence and effort; every recommendation is a complete work order with implementation and verification steps (PR-REQ-005, PR-REQ-011, PRULE-026).
- **Pillar 3 — Trust by construction.** Videt never touches your systems; ownership is verified before anything is measured; crawling is polite and bounded; access is deny-by-default (PR-REQ-015, PRULE-020, PRULE-021, PRULE-044).

Every section of every page must ladder to one of these three pillars or be cut.

## 4. Homepage Blueprint

Section order, with draft copy and rationale. Copy is directional; the claim-discipline table in §8 governs final wording. The page is written to the owner: its subject is their business, never the product — features appear only as proof beneath an outcome the reader already wants (§5).

**Phase gating:** the blueprint below is the GA-state homepage. Until OD-010 measurement activates (§12), every section ships in its Phase-1 designed-to variant — measurement copy uses designed-to framing and the trust strip carries architecture facts only, not operational SLAs. Phase-1 variants are noted inline; a copywriter must never lift GA copy into the current site. Vision-layer sections (§4.7) are always labelled as the category's direction, in any phase.

### 4.1 Hero

> **Your next customer just asked an AI who to trust.**
>
> Will it say your name? You built something worth recommending. Videt is being built so the machines can see it — and so you can watch them learn.
>
> The methodology is published. Measurement opens with early access.
>
> [Request early access]   [Read the methodology]

- Dream-first: the headline puts the reader inside the commercial moment — their customer, mid-question — before any product exists on the page. The product is not named until the reader cares.
- Beside the copy runs the simulated-assistant device (§4.5's centerpiece, hero-sized): the visitor watches the moment happen.
- "Is being built so" is the Phase-1-truthful verb; the methodology line is the present-tense proof point. The GA variant graduates to present tense with measurement activation (§12).
- No provider logos. ChatGPT, Claude and Gemini are named only as surfaces people ask (glossary: AI Assistant Surfaces), never as integrations or partnerships (OD-010: provider-neutral).

### 4.2 The Five Questions

> Five questions now decide how often your name comes up:
>
> 01 — Does the machine know you exist?
> 02 — Does it understand what you offer?
> 03 — Does it trust what it knows?
> 04 — Does it recommend you?
> 05 — Why?
>
> Videt is being built to answer all five — about you, with evidence.

- Lifted directly from VISION-001. The numbering is real sequence, not decoration: each question presupposes the one before it — the ladder of machine confidence. This is the site's most memorable structure and the FAQ's organising spine.

### 4.3 The Eras

> **First they listed you. Then they ranked you. Then they learned about you. Now they answer for you.**
>
> Directories gave way to rankings, rankings to knowledge, knowledge to answers. Your customers ask; the machine replies with one recommendation. Being inside that answer is the new first page.

- The 30-second "why now": VISION-001's four eras compressed into one owner-readable line of history.
- The category line lands here, once per page: "Videt is the Commercial Discoverability Observatory — where you watch the machines learn your business."
- Why-now statistics rule unchanged: cited with named sources or absent; the pre-launch study (§7) is the preferred first source.

### 4.4 Two Pictures Of Your Business

> **There's the business you built. And there's the one the machines describe.**
>
> Side by side: Reality — your services, your places, your proof — and Perception — what an AI system currently believes: the service it missed, the fact that went stale, the competitor it prefers. The gap between the two decides whether your name comes up. It's invisible, until it's measured.

- The vision's core concept (Reality vs Perception — VISION-001, ADR-012) rendered as a mirror any owner reads in five seconds, with illustrative annotations on the Perception side.
- Perception varies by provider; the mirror carries neutral provider chips to plant "each machine sees you differently" without presenting integrations.

### 4.5 Ask Your Assistant

> **Find out now.**
>
> Open ChatGPT, Claude or Gemini and ask it to recommend a business like yours — your service, your city.
>
> If you appeared: for which questions? Was your business cited, or improvised? Will the answer hold next month, on another model, phrased another way?
> If you didn't: that absence is the gap — and it can be measured.
>
> [Request early access — enter your domain]

- The conversion centerpiece (§7) at the urgency peak. Both result paths are scripted in place, so a visitor who *does* appear keeps reading: presence in one answer is an anecdote; the questions underneath it are the instrument's job.
- The domain-field capture sits directly under the device, giving the page a mid-scroll conversion point in addition to the hero and closing CTAs.
- The anecdote-versus-instrument bridge is stated here in one line and expanded in the FAQ (§9.1).

### 4.6 Your Business, Measured

> **One number that means something — because you can open it.**
>
> One Discoverability Score. Seven evidence-backed pillars. Equal weights, published math, no black box.

Seven pillars, presented as one score with seven evidence-backed dimensions (PR-REQ-010 check-catalog-v1): Technical Integrity · Search Presence · AI Presence · Authority Signals · Trust Signals · Content Quality · Local Presence.

The published-math line is real: pillar scoring is 100-point pillars, fixed penalties by impact band, equal weights (SCORE_EVIDENCE_MODEL) — simple enough to print, so print it. Use the canonical pillar names exactly; never "technical health score", "authority score", or "LLM visibility" (003 TERMINOLOGY disallowed variants).

Anchored by a designed sample assessment — the seven-pillar score with an evidence cell (`002 VISUAL_IDENTITY.md` §9.4), labelled illustrative until measurement activates. Cold visitors believe artifacts, not adjectives. The six-step loop (verify · crawl · evaluate · score · act · re-measure) moves to the Product page (§6) — on the homepage it compresses to one caption line under the sample: "Verified ownership in. Evidence-backed score out. Your systems untouched."

### 4.7 From Measured To Learned (vision layer)

> **Fix it once. Know it worked. Keep what you learned.**
>
> Where the Observatory is headed: every change you make is verified, observed again and measured — and the outcome is remembered, so the next recommendation starts smarter than the last. Reports depreciate. Knowledge compounds.

- FUTURE-WORKFLOW-001's intervention learning lifecycle sold as the category's direction, in the owner's terms (certainty, not machinery). Always labelled as vision — "where the Observatory is headed", "is being built to" — never as shipping behaviour (SB-REQ-029 non-commitment labelling; the lifecycle is a future specification).
- This section is the dream's ceiling: the reader should feel that choosing Videt now means their evidence starts compounding first.

### 4.8 The Promise

> **You'll never be shown a number we can't prove.**
>
> No evidence, no Issue. Every Issue traces to evidence you can inspect. Every score movement is attributable. Incomparable history shows no delta. Missing data is never synthesized.

Owner-voiced restatement of the evidence principle; all sentences spec-supported (PRULE-011, PRULE-030, PRULE-032, PRULE-043; WF-012's "does not synthesize values"). This section exists because "trustworthy" is claimed by everyone; Videt can show the machinery.

### 4.9 Three Readers, One Record

Persona strip (PR-REQ-008's buyer/user split):

- **For executives** — trend direction, risk and commercial outcomes, without a single vanity metric.
- **For marketing teams** — which customer questions you're absent from, and what to publish or fix first.
- **For technical implementers** — implementation-ready artifacts with ordered steps and verification, not screenshots of problems.

### 4.10 Trust, By Architecture

Compact, factual, no "enterprise-grade" adjective (003 Rule 10 bans unqualified superlatives — the facts are stronger anyway):

> Deny-by-default access. Hard tenant isolation. Access revocation propagates within 60 seconds. No standing vendor access to customer data — support sessions are time-bound, dual-approved and logged, with customer approval required for cross-tenant access outside audited break-glass emergencies. Any open Issue can be formally disputed, with a 24-hour adjudication SLA. Videt never stores your passwords — identity proof is cryptographically signed and single-use.

(PRULE-041, PRULE-044, CAP-023, CAP-014; credential-free identity per the WF-001 Identity Validation Receipt contract — F1 never receives, stores, or validates raw credentials.)

Phase-1 variant: architecture facts only — deny-by-default, tenant isolation, credential-free identity, never touching customer systems. Operational SLAs (60-second revocation, 24-hour adjudication) appear only once the behaviours they describe are shipped and verified.

### 4.11 Closing

> **Become the answer.**
>
> It's your name they should be saying. Bring your domain — we'll bring the evidence.
>
> [Request early access]

## 5. Voice And Copy Rules

- **It is about them.** Every section is written from the owner's side of the screen and must pass the test: *does this sentence make the reader see their own business?* Sell the dream — being seen, chosen and certain — never the feature. "You" outnumbers "Videt" on every page; a feature may appear only as the proof beneath an outcome the reader already wants.
- Short declaratives. One idea per sentence. No stacked adjectives.
- Plain English over category jargon; the category label appears once per page at most.
- Numbers only when the spec supplies them (60 seconds, 24 hours, seven pillars). Never invent an SLA, benchmark or percentage.
- No fear marketing, no urgency theatrics, no alarmist framing of small changes (004 Principle 7 applies to marketing surfaces too).
- CTAs are action-specific, never bare "Optimize" or "Improve" (004 Principle 10).
- Canonical vocabulary everywhere: Issue (never "finding"), Recommendation Artifact, Discoverability Score, AI Presence, ScoreSnapshot, Monitoring Run (003 TERMINOLOGY).
- If a sentence needs three clauses, it needs to be two sentences.

## 6. Site Information Architecture

**Tier 1 — launch set:**

| Page | Job | Primary pillar |
|---|---|---|
| Home | The full ladder, §4 | All |
| Product ("How it works") | The full measure → recommend → act → re-measure loop (verify · crawl · evaluate · score · act · re-measure, with its spec citations) plus product surfaces per persona | Pillar 2 |
| Methodology | The published scoring math: pillars, weights, penalties, evidence model, determinism — including an explicit treatment of how AI-answer variance is observed, so the reproducibility claim owns its hardest objection. The credibility engine of the whole site. Carries an updates subscription as its capture mechanism. | Pillar 1 |
| FAQ | The §9 objections in buyer-facing form — also the surface AI assistants cite most readily | — |
| Manifesto ("Indexed → Evaluated") | The §2 essay in full; the category-ownership artifact, written to be cited | — |
| Trust & Security | §4.10 expanded: verification, crawling conduct, tenant isolation, support-access governance, dispute process, data classification | Pillar 3 |
| Early access | Single conversion surface | — |

**Tier 2 — post-launch:**

- Audience pages (SMB operators / agencies / in-house growth teams — PR-REQ-006). Agency page must not promise a multi-client portal or consolidated dashboards; per-client organisations are the ratified model (PR-REQ-006; PR-REQ-007's consultant tenancy note; 011 DOMAIN_MODEL Organization-as-tenant-root).
- Research/blog: original measurements of AI discoverability by vertical — the content engine that makes Videt itself the cited answer.
- Pricing: blocked until packaging is ratified (ADR-019). Until then, early access + "talk to us".

**Explicitly not on the site:** integrations marketplace (platform-managed adapters only, PR-REQ-025), competitor benchmarking as a feature (future non-commitment only, SB-REQ-029), public shareable report links (CAP-022 non-goal), auto-fix promises of any kind (PR-REQ-015, SB-REQ-004).

## 7. Conversion Strategy

**Pre-launch (current state — implementation is at S-01; external measurement stays dormant until the OD-010 Measurement Set package is approved and activated):**

- Single conversion goal: early-access list. Form asks for company domain — that one field converts curiosity ("will AI recommend *me*?") into a concrete future first-run and is the seed of onboarding.
- **The self-demonstration device** (homepage §4.5, mirrored in the hero). The site invites the visitor to open their AI assistant and ask it to recommend a business like theirs. The "find out" impulse gets an instant, self-generated payoff — no dormant pipeline required, no fear framing; the reader produces their own evidence. The domain-field capture sits directly beneath it, converting a felt problem, not an abstract one.
- A published sample assessment of Videt's own domain, labelled illustrative, gives that curiosity a concrete artifact to hold.
- **Pre-launch research artifact.** A "State of AI Discoverability" study, produced as a manual marketing study explicitly distinct from the dormant product pipeline. It is the why-now evidence for §4.2, the PR hook, and the first citable asset — pulled forward from the post-launch flywheel because pre-launch is exactly when Videt has no product proof. Release conditions: the study publishes its own protocol (question set, assistants queried, sampling window, citation-counting rules) — a preview of the product's epistemics, not an exception to them — and it carries correlation evidence (how pillar evidence and cited presence co-occur across the sample), not adoption statistics alone. It is the site's only efficacy proof before measurement activates (§9.4).
- Secondary conversion: methodology readership — captured via the methodology page's updates subscription; this audience becomes enterprise pipeline.
- Social-proof substitutes (a pre-launch site has none): the published methodology as proof of competence, a named design-partner program inside the early-access flow, and founder and technical credibility carried on the manifesto.
- No free-scan or instant-score CTA may ship while the measurement pipeline is dormant; a CTA that cannot deliver its promised action is a trust breach the brand cannot afford.

**Post-launch:** primary CTA becomes "Get your Discoverability Score"; first-run experience must deliver the spec's promise of a baseline score and an economically prioritised action list (005 Principles 3–4). The viral loop from research/000 (shareable scores, agency-distributed reports) is roadmap-gated: baseline scope has no public share links, so any share mechanic waits for a ratified capability.

**Measurement:** early-access conversion rate; scroll-depth past The Shift; five-second comprehension tests scored against the §3 ladder; methodology subscriptions. Third-party AI citation of Videt is tracked as a lagging indicator, never a gate.

## 8. Claim Discipline

The load-bearing table. Website copy may make the left claim only in the right-hand form.

| Tempting claim | Truthful form | Authority |
|---|---|---|
| "Continuously monitors your AI visibility" | "Reassess on demand, or on a schedule you set" | PRULE-033, PRULE-045 |
| "Knows what AI thinks about you" | "Measures whether AI-generated answers include and cite your business, for the questions that matter" | CHK-AIP-001 |
| "Tells you why AI doesn't recommend you" | "Shows exactly which customer questions lack cited presence, and what to improve" | OD-010, REC-CHK-AIP-001-v1 |
| "Benchmarks you against competitors" | Own-history trends only; competitor intelligence labelled future/non-commitment if mentioned at all | VOLUME_I_FOUNDATIONS, SB-REQ-029 |
| "Boost your AI rankings" | "Improve the evidence AI evaluates" — never manipulation framing | REC template white-hat clause |
| "AI-powered insights on your dashboard" | Dashboards are deterministic; AI assistance, where enabled, cites evidence for every claim | AI-REQ-023, citation-policy-v1 |
| "We fix your site" / "one-click fix" | "Implementation-ready artifacts; your team stays in control; Videt never touches your systems" | PR-REQ-015, SB-REQ-004 |
| "Real-time" / "always-on" / "unlimited" | Bounded runs, scheduled reassessment, explicit limits — say what the bound is or say nothing | PRULE-008, entitlement policy |
| "Works with ChatGPT, Claude, Gemini…" | Named only as surfaces people ask, never as integrations or partners | OD-010 provider-neutrality |
| Present-tense feature claims pre-GA | Designed-to framing + early access until the OD-010 Measurement Set activates and slices ship | PROJECT_STATE |
| "It learns what works and gets smarter" (interventions, learning loops, benchmarks) | The category's direction, always labelled as vision — "where the Observatory is headed", "is being built to" — never shipping behaviour | VISION-001, FUTURE-WORKFLOW-001, SB-REQ-029 |

House rule: when legal, sales and copy disagree, the specification wins, and the truthful version has so far always been the more distinctive line.

One reading is fixed here so every derivative line inherits it: **"Become the answer" means become the best-evidenced candidate for the answer.** You earn the answer; Videt measures whether you have. The promise is an evidence claim, never an influence claim.

## 9. Objections And The Competitive Frame

Every cold visitor arrives carrying one of these objections. The site answers all four explicitly, shipped as the Tier-1 FAQ page (§6) — the format AI assistants cite most readily:

1. **"Can't I just ask ChatGPT myself?"** You should — that is the demonstration (§4.5). But one prompt is an anecdote: answers shift with phrasing, day and model. Videt is the repeatable version — a defined set of customer questions observed under a documented protocol, with evidence for what appeared, what was cited, and what changed since the last assessment.
2. **"How is this different from the GEO/AEO tools?"** Several of them track AI answers too — the difference is evidence standards. Videt publishes its scoring math, evaluates deterministically and reproducibly, traces every score to inspectable evidence, and measures only on proven ownership. Observation without those standards produces numbers you cannot defend; Videt exists so you can defend every one. And it never attempts to manipulate provider output — the white-hat clause is written into its recommendation templates.
3. **"Why can't I see my competitors' scores?"** A Videt score requires verified, inspectable evidence about a property — the substrate only proven ownership provides (PRULE-005). Whether a competitor's name appears in a public AI answer can be observed without consent, but without that substrate it is an anecdote, not a score, and Videt does not publish numbers it cannot back. Your own history carries the honest trend (CAP-019); competitor intelligence, if it ships, arrives as a ratified capability — a non-commitment until then (SB-REQ-029).
4. **"Can improving my evidence actually change what AI answers?"** Videt makes no influence claim — that is the point of the white-hat posture. The causal chain is stated plainly: AI assistants synthesize answers from the evidence they can find and verify; better evidence raises the odds of cited presence; and the act → re-measure delta is the proof, assessment by assessment, on your own property (CAP-019, CAP-020). The pre-launch study (§7) carries the market-level version: how pillar evidence and cited presence correlate.

The FAQ also states the pricing posture plainly: pre-launch, design-partner terms through early access, pricing published when packaging is ratified (ADR-019). Buyers who need commercial specifics now are routed to the design-partner program (§7).

## 10. Proof Assets To Build

1. **The Methodology page** (§6) — publishes the scoring math and evidence model in full and invites the market to match it.
2. **The Manifesto** — the category essay, written to be quoted, taught and cited (including by AI assistants — see §11).
3. **Trust center** — the §4.10 facts expanded with the named mechanisms (two-person rules, break-glass governance, deletion evidence, four-tier classification).
4. **Crawler conduct page** — the self-identifying bot, robots.txt compliance, rate bounds, scope guarantees (PRULE-021, WF specs). Linked from the user-agent string; site owners who look up the bot find the trust story.
5. **Own research** — original published measurements of AI-answer presence by vertical, the content flywheel that earns citations. The first study ships pre-launch (§7).

## 11. Videt's Own Discoverability

The site must pass its own audit. Structured data (Organization, Product, FAQ), entity-consistent naming, semantic clarity, answerable pages — the manifesto and methodology written so that an AI assistant asked "how do I know if AI recommends my business?" can find and cite Videt. The company's first case study is meant to be itself: **Videt becoming the answer to the question it exists to measure.**

This is a launch-phase project with acceptance criteria scoped to what Videt controls — structured-data validity, entity consistency, answerability audits — while actual third-party AI citation is tracked as a lagging indicator, not a gate (Videt does not control assistant behaviour and must not gate itself on it).

The market's existing vocabulary — GEO, AEO, AI visibility — is captured, not adopted: a vocabulary-bridge asset ("what the market calls GEO, measured properly") maps those queries to Videt's category language, so the site is findable for the searches its market actually makes without surrendering its terminology (the 003 TERMINOLOGY "Canonical Terms And Disallowed Variants" list governs product copy; naming market synonyms in order to map them is positioning, not adoption).

## 12. Launch Phasing

| Phase | Gate | Website posture |
|---|---|---|
| Now | Implementation at S-01; OD-010 Measurement Set unapproved | Manifesto + methodology + FAQ + early access with self-demonstration device and sample assessment; "State of AI Discoverability" study. Designed-to framing throughout. |
| Measurement activation | OD-010 Measurement Set package approved and activated; measurement slices shipped | Present-tense measurement claims unlock; first-run score CTA ships |
| Baseline GA | Volume I capabilities shipped | Full §4 homepage; audience pages; pricing when ratified |
| Growth expansions | Later capability contracts | Competitor intelligence page unlocks only when a ratified capability exists |

## 13. Open Decisions

1. Brand-name ADR (Videt/F1 mapping) — recorded in `000 STRATEGY_BRIEF.md`, Open Naming Items.
2. Pricing and packaging ratification before any pricing page.
3. Visual identity ratification — `002 VISUAL_IDENTITY.md`.
4. Domain and email posture for videt.ai (out of scope for this document).
