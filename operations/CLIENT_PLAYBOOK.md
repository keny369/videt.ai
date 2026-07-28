# VIDET Client Playbook — one client, start to finish

Status: Operational runbook v1.0, 28 July 2026. This is your single working document: follow it top to bottom for every client and it tells you what to do, which document to open (exact path), what you produce, and roughly how long each step takes. It **cites** the source documents rather than restating them — when the playbook and a source disagree, the source wins; fix the playbook. Plain language throughout. Nothing here is customer-facing.

> The method in one sentence (from the delivery guide's opening): capture ground truth (Reality Card) → audit the surfaces machines actually read (Readiness Audit) → observe what assistants say (Protocol runs) → compare, count and classify (Findings) → fix what the consensus says matters (Fix Library) → verify, then re-observe (Value Cadence).

---

## The document map (bookmark this table)

| When | Open | Why |
|---|---|---|
| Pitching & selling | `investor/30_DAY_REVENUE_PLAN.md` | Scripts, pricing, rules. Appendix map: targets A · offer B · standing rules C · protocol D · tracker E · demo script F · outreach templates G · objection log H · checkpoints/pivot I · case-study kit J · DE conformance K · forbidden list L |
| The thing you send prospects | `branding/004 FOUNDING_COHORT_OFFER.pdf` | The one-page offer. Know its promises — they bind you (see Phase 1) |
| Everything after payment | `operations/ASSESSMENT_DELIVERY_GUIDE.md` | The 12-part delivery manual. Parts map: grades 1 · onboarding 2 · Reality Card 3 · Readiness Audit 4 · observation 5 · metrics 6 · findings 7 · fixes 8 · report 9 · value cadence 10 · legal 11 · codification 12 |
| Building the question set | `investor/QUESTION_BANK.md` | Nine archetypes A–I, per-vertical example sets, the two controls, follow-up chains |
| Running observations | `operations/PROBE_PROMPT_KIT.md` | The paste-ready prompts (Stages A–D), run conditions, confabulation capture |
| Writing the fix plan | `operations/AUTHORITY_ROADMAP.md` + delivery guide Part 8 | The two-clock model, the 80/20 fix sequence, verified directory URLs |
| Explaining machine behaviour | `specification/machines/000 MACHINE_BEHAVIOUR_SYNTHESIS.md` | What the machines themselves say about how they recommend — your "why" answers |
| Any customer-facing artifact | `branding/006 BRAND_PACK.md` | Colours, type, logo files (`branding/logo/`), voice quick-card, conformance checklist §8 |

---

## Phase 0 — Prospect and pitch

1. **Pick the prospect and the message.** Open `investor/30_DAY_REVENUE_PLAN.md` Appendix G and copy the template that fits: **G.1** trades/building (leads with your flooring **client** work — SprungFloors/JA Floors are clients, always worded as such), **G.2** professional services (opens "Hi [name] — a question you probably can't answer today…"), **G.3** Scaling members (opens with the invisible-funnel angle — "…just a customer you never met"). Personalise the brackets; send. Log the pitch same day in Appendix E's tracker (standing rule, Appendix C rule 8).
2. **Attach or follow with the offer.** Send `branding/004 FOUNDING_COHORT_OFFER.pdf`. Nothing else — no methodology, no spec, no architecture, ever (Appendix C rule 6, "sizzle, not machinery").
3. **The demo IS the pitch.** When you get a conversation, run Appendix F's 90-second demo: ask for permission ("Can I show you something about your business? Ninety seconds."), open ChatGPT or Gemini live, type "Who's the best [their service] in [their suburb/city]?" and let them read the answer as a customer would. If they appear *well*, use the contingency line: "That's one answer, today, phrased one way. The assessment asks 22 real buyer questions across four assistants, repeatedly. Want to know if it holds?"
4. **Language laws while selling:** never say SEO, GEO or "AI visibility platform" (Appendix C rule 4). In writing it's "around 22" questions; spoken it's bare "22" (Brand Pack §5 voice quick-card). Category education is one line maximum: "This is where customers increasingly start." (Appendix F step 5).
5. **Objections and no-sales get logged** same day in Appendix H. Free-pilot requests are refused — "'we'd love to try it free' is a no with flattery" (Appendix L, the forbidden list — reread it whenever tempted).

**Example** — a G.2-style opener you can adapt for an accountant: *"Hi Maria — a question you probably can't answer today: when someone asks ChatGPT who the best small-business accountant in Carlton is, does your name come up — and are the details right when it does? I check exactly that. Takes me a week, costs less than one lost client."*

## Phase 1 — Close, payment, and the clock

1. **Price from Appendix B** (`investor/30_DAY_REVENUE_PLAN.md`): Assessment **A$990** (anchor A$1,490; "founding cohort of 20" price) · Assessment + 90-day re-measure **A$1,490** — *push everyone to the bundle; it manufactures the before/after case study* · Fix-it engagement A$2,500–5,000 **only when they ask**, max 2 this month.
2. **The close** is Appendix F step 6 — one answer, one day, one phrasing versus "22 real buyer questions" (spoken: bare 22), four assistants, counts, screenshots, ten fixes.
3. **Payment: 100% up front, invoice on the spot** (Appendix B). No payment = no start: "a yes without payment is a no with manners" (Day 20 rule). The delivery clock starts at payment — the offer PDF's footer promises, verbatim, "delivered personally by the founder within five business days of payment", so both the clock AND the personal delivery bind you.
4. **Know what the PDF promised** (it binds your delivery): around 22 questions across ChatGPT, Gemini, Claude and Perplexity, every answer counted; wrong details logged verbatim with screenshots; competitors named factually; ten prioritised plain-English fixes; a 45-minute founder walkthrough; "We ran it on our own business first — then on client businesses. Ask to see those reports." — keep the Lumen & Lever report and permission-cleared client reports ready to show.
5. **Capacity guard:** if paid-but-undelivered backlog exceeds 8, raise prices for new sales to A$1,290/1,790 or open a stated waitlist — never let delivery slip past 5 business days (Day 17 rule).
6. Record the sale in Appendix E's tracker with the delivery-due date (paid + 5 business days).

## Phase 2 — Onboard: intake and the Reality Card (~1 hour)

Open `operations/ASSESSMENT_DELIVERY_GUIDE.md` and stay in it through Phase 8.

1. **Intake (20 min, Part 2):** run the intake call (or form) collecting the Part 3 fields: services and highest-value service lines, suburbs served and NOT served, and any similarly-named businesses. Also gather competitors and buyer personas — these are NOT Part 3 fields but playbook additions you need for the 3–5 business-specific questions (Appendix D §1). (Playbook default, since the offer promises "nothing needed from your side": desk-research everything first, then one short confirmation call for anything only the client can assert.)
2. **Build the Reality Card (40 min, Part 3) — non-negotiable ground truth, dated, with screenshots:** legal + trading names, ABN/ACN (ABN Lookup screenshot), the ONE canonical NAP (name/address/phone), every licence and registration with number, true service list mapped to page URLs (a service with no page is already a gap), locations + suburbs served/not served (this feeds the wrong-area control), named practitioners with their individual registrations, hours, review-profile locations, and the **confusable-entities list** — similarly named businesses, the practitioner-vs-firm split, old trading names. Without the confusables you cannot detect Entity Conflation later.

**Example Reality Card confusable entry:** *"'Carlton Accounting Group' (different firm, Sydney) — confusable with client 'Carlton Accounting & Advisory' (Melbourne). Watch for machines blending the two."*

## Phase 3 — Readiness Audit (60–75 min)

Part 4 of the delivery guide: work the **six layers in order**, marking every item ✔ pass / △ gap / ✘ fail / n-a, one-line note, screenshot for anything not-pass:

1. Identity & registers (ABN Lookup, ASIC, the vertical's register — AHPRA, TPB, law society, state building authority, etc.)
2. Maps (Google/Apple/Bing resolve to ONE correct entity, ownership claimed)
3. Reviews (count, recency, response rate, on the CORRECT listing)
4. Website technical (literally-titled service pages, valid schema.org JSON-LD, crawlability, PageSpeed)
5. Corroboration (LinkedIn, associations, directories, news)
6. Red flags (adverse terms, AustLII, ASIC banned register, AFCA — handled per Part 11's legal rules, never editorialised)

Every △/✘ maps to a Fix Library entry (Part 8) — **the audit output is the fix plan's skeleton**, so be precise here and Phase 8 writes itself.

## Phase 4 — Build the question set (15 min)

Open `investor/QUESTION_BANK.md`. Recipe (per Appendix D §1 of the revenue plan): **20–25 questions = the vertical's set from the bank + 3–5 business-specific + 2 controls.** The bank's default mix allocates: **A Recommendation ×8 · B Problem-first ×5 · E Validation ×3 · C Attribute/niche ×2 · F/G Criteria-or-Price ×2 · + 2 controls** — substitute D Comparison, H Urgency or I Hire-or-not where the vertical warrants (e.g. I for coaches, H for emergency trades), don't force all nine.

**Examples (from the bank):**
- A: "Who's the best small-business accountant in {suburb}?"
- B: "My BAS is three months overdue and I'm worried about ATO penalties — who should I talk to?"
- C: "Xero-certified accountant near {suburb} with fixed monthly fees?"
- E: "Is {business} any good? Are they registered tax agents?"
- I (the category gatekeeper): "Are business coaches worth it or a waste of money?"

**The two controls are non-negotiable:** wrong-service ("Who's the best {unrelated service} in {their suburb}?" — calibrates how freely the assistant names businesses it shouldn't) and wrong-area (their exact service in a suburb they don't serve — if they appear there too, the machine is pattern-matching, not knowing).

## Phase 5 — Observation runs (2.5–3.5 h, spread over ≥2 days)

Open `operations/PROBE_PROMPT_KIT.md` and use its prompts **verbatim** (changed wording = a new phrasing ID). The protocol is delivery guide Part 5 layered on revenue-plan Appendix D:

1. **Assistants:** ChatGPT, Gemini, Claude, Perplexity (Appendix D §2) — consumer surfaces, queried manually, fresh conversations.
2. **Run conditions first** (kit §1): fresh chat, memory off, note account tier and your IP city, pick the search arm. Each run = one fresh chat = one row.
3. **Sampling floor:** every question ≥3 times per assistant, spread across ≥2 days. Screenshot every response — "Nothing is reported that isn't captured" (Appendix D §4).
4. **Stage the probes** (kit §2–3): natural question first (e.g. R1: "Who are the best {{CATEGORY}} in {{LOCATION}}?"), THEN follow-ups, THEN the JSON transcription — never JSON first. **Unprimed means unprimed** (kit §1.5): never mention the client in a recommendation probe; the primed Probe E (entity resolution — "What can you tell me about {{BUSINESS_NAME}}…", kit §3) runs in its own fresh chat, always AFTER the day's unprimed runs. Probe E is what feeds Entity Resolution Fidelity — don't skip it.
5. **The follow-up chain, once per session.** The paste-ready text is the kit's Stage B, verbatim: FB1 "Are there any others worth considering?" → FB2 "Of all of those, which single one would you pick for {{USE_CASE}}, and why?" → FB3 "How do you know about these companies — where does this information come from? Please list the specific pages or sources for each one." The delivery guide's Part 5 item 6 phrases ("if I could only call one today, which?", "give me their contact details", "which pages did you draw those names from?") describe the chain's *function* — they are shorthand, not paste text. The contact-details facts harvest is an additional follow-up from the guide/bank: if you run it, give it its own phrasing ID. (Source divergence flagged: guide Part 5 item 6 wording vs kit FB1–FB3 should be reconciled; until then the kit's text is the instrument.)
6. **Two-arm** search-ON vs search-OFF on the client's 5 money questions where the surface allows (Part 5 item 4). The forced-off prefix line is in kit §1: "Please answer from your own knowledge only — do not search the web for this."
7. **Position capture:** record the rank of every business named, not just the client (Part 5 item 3).
8. **Controls** (Part 5 item 5): the two from Phase 4 plus one similar-name probe from the Reality Card: "Is {confusable entity} the same as {client}?"
9. **Quarantine:** any run with a fabricated business, an entity collision on the client, or an unsupportable citation is flagged `defective_observation` — reported as its own finding class, never averaged in (Part 5 item 7).

## Phase 6 — Verify everything; capture confabulations

Kit §6 (Stage D). Every source the machine cited and every fact it stated about the client gets human-verified against the live page or the Reality Card **before it can appear anywhere**. Assistant-cited sources are leads, never findings (the standing rule from the Clutch case — the machine cited a real page and misattributed its contents).

Every failed verification becomes a **confabulation capture** (kit §6 schema): the verbatim claim, the cited source, what the page actually shows, **screenshots of both sides taken the same day**, and one of the seven classes (citation misattribution, fabricated source, entity conflation, temporal hallucination, attribute invention, geographic boundary breach, false recognition). These are your best report exhibits and future sales specimens.

**Example capture, in one sentence:** *"ChatGPT (26 Jul, search-on) said 'their office is on Collins Street' citing the client's own site; the site — screenshotted same day — shows the office moved to Richmond in 2024. Class: temporal hallucination. Reality Card field contradicted: address."*

## Phase 7 — Analyse and classify (45 min)

Delivery guide Parts 6–7.

1. **Metrics (Part 6):** at screening grade you report **counts and raw observations only** — Mention Rate as a count ("appeared in 2 of 12 runs"), positions as raw facts ("first-listed in 3 of 12 runs", "ranked 2nd on 26 Jul, ChatGPT"), Entity Resolution Fidelity as per-field right/wrong counts against the Reality Card, Citation Accuracy from Phase 6's verification rows as counts. The **Position-Weighted Score** (weights 1st = 1.00, 2nd = 0.70, 3rd = 0.50, 4th = 0.35, 5th+ = 0.20, unranked mention = 0.10 — always framed as "our convention, not model internals") is a derived score: reserve it for **instrument grade**, where rates with Wilson intervals and N are also permitted (10+ runs per condition). At screening grade a weighted score would breach the counts-not-scores law — report the positions, not the blend.
2. **Findings (Part 7):** classify every non-pass observation as exactly one of seven classes — Absence, Entity Conflation, Temporal Hallucination, Geographic Boundary Breach, Authority Spoofing, Anchoring Fragility, Defective Observation — each carrying the verbatim machine text, run reference, date, assistant, and the Reality Card field it contradicts.

**The allowed claim shapes** (Part 1): "appeared in 2 of 12 runs", "address wrong in 4 runs", "conflated with X twice". Every number carries its N and "observed on [date], [assistant]". Where evidence is thin, abstain in writing: "we could not distinguish X from Y on this sample."

## Phase 8 — Assemble the report (60 min)

Delivery guide Part 9 fixes the section order — do not improvise it:

1. The questions your customers ask
2. What the machines said (counts, excerpts, screenshots)
3. Two pictures — Reality Card vs what assistants believe, gaps highlighted
4. What they got wrong (facts table with run references)
5. Who they named instead (factual, attributed: "Assistant X, sampled N times on date Y, named …" — no commentary on competitors' businesses, Appendix C rule 9)
6. Readiness scorecard (the Phase 3 layers as ✔/△/✘)
7. The ten fixes, prioritised (Phase 9's content)
8. What happens next — the 90-day re-measure

**Visual conformance:** `branding/006 BRAND_PACK.md` §4.2–4.3 (filled master mark in the header from `branding/logo/`, counts/dates/IDs set in the mono stack) and run the §8 conformance checklist before it ships. **Mandatory report furniture — every report, every vertical:** the measurement-disclaimer footer (brand pack §4.3: "This is a measurement of AI assistant behaviour, not professional advice.") and the closing line "Every observation in this report is screenshot-backed and dated. Ask us for any of them." (Appendix D §6). Regulated verticals (health, finance, legal) upgrade to the extended Part 11 wording: "…not professional, financial, legal or medical advice."

## Phase 9 — The fix plan (inside the report)

Sources: delivery guide Part 8 + `operations/AUTHORITY_ROADMAP.md`.

1. **Map each finding to one of the ten canonical interventions** (Part 8): EntityIdentityConsolidation, ThirdPartyProfileCorrection, StructuredDataCorrection, ContentClarification, KnowledgeSourceAlignment, LocationCorrection, ReviewSignalImprovement, CitationAcquisition, AuthorityContentPublication, TechnicalAccessibilityCorrection — each with its verification step and expected clock.
2. **Sequence by the roadmap's 80/20** (Phase 1 = retrieval layer, weeks): entity/domain consolidation first, then buyer-language pages, then the **placement raid — targets come from the client's own answer path**, not a fixed list: audit which surfaces the currently-recommended competitors are cited from (roadmap Phase 1 item 4), then get the client onto those. The Lumen & Lever week-one section is the worked example of a verified raid list *for one vertical* (Melbourne AI advisory: clutch.co/get-listed + 2–3 reviews, GoodFirms, aidirectory.industry.gov.au, iaaic.org, Built In Melbourne) — regenerate the equivalent list per client from their answer path. The vertical's registers come from the Phase 3 audit (Layer 1), not the raid. Then third-party bios and the roundup play.
3. **The two clocks, stated honestly** (roadmap claim discipline — the only permitted framing): "retrieval-layer fixes propagate in days to weeks and we re-measure them; what the models remember from training changes slowly and no one can schedule it." Tier 3 corpus fixes are strategy for consultants/B2B/founder brands only, never timelined; for local-services clients, omit the tier and say so.
4. **What VIDET refuses to sell — say it in the report** (Part 8): AI-keyphrase stuffing (the machines themselves call it ineffective — "does not outperform standard structured clarity"), review manipulation, guaranteed mentions, promises about model memory. Fixes are framed as "better evidence for the machines to check" (brand voice quick-card).

## Phase 10 — Deliver: the 45-minute walkthrough

1. Send the report PDF within the 5-business-day clock; hold the walkthrough as close behind it as the client allows.
2. **Agenda = walk the report's eight sections in order** (they're sequenced to land: questions → what machines said → the two pictures → wrong facts → competitors → scorecard → fixes → next). Spend the most time on sections 3, 4 and 7.
3. **Agree the fix plan before the call ends** (Part 10 week-0 obligation): every fix gets an owner assigned — client, their web person, or a VIDET fix-it engagement — or it won't happen and the re-measure will show nothing.
4. **End with the two asks, scripted** (Appendix F step 7): the 90-day re-measure ("in 90 days I can re-run every question and put your before-and-after on paper") and referrals ("two businesses like yours who should see this" — the Day 27 phrasing).
5. If they say something quotable, ask on the spot: "can I quote that?" (Appendix J). Your own business (Lumen & Lever) is disclosed as own; client practice-run businesses (SprungFloors, JA Floors, Whollistica) appear only with written permission and always worded as client work — never as "our own companies", never as customers.
6. Log the call, any objections (Appendix H) and the asks' outcomes in Appendix E, same day.

## Phase 11 — Value cadence, re-measure, case study

1. **The pulses are scheduled work, not vibes** (delivery guide Part 10): **Week 4** — light pulse: the 5 money questions, 1 assistant, 3 runs (~30 min), email the client the delta counts. **Week 8** — second pulse, same sizing. Between pulses, confirm implemented fixes live ("implemented and confirmed live" notes to the client). The pulses keep the re-measure meaningful and the client warm for it.
2. **The 90-day re-measure** (Part 1 sizing): the client's 5 money questions at instrument grade — 2 assistants × 10 runs ≈ 100 queries ≈ 2.5 h — which is exactly why the A$1,490 bundle costs more. Hold the original question wording constant. Deliver the before/after side by side. (If the client implemented no fixes, the re-measure still runs — an unchanged picture is itself the finding, reported honestly.)
3. **Case study** (Appendix J): build it from the delta; get written consent for anything public; own-business case studies always carry the disclosure.

## Phase 12 — Log and codify (15 min — do not skip)

Delivery guide Part 12: fill the three log sheets so the future platform inherits every client —
- **Run log** (one row per run): run_id · client · date_time · assistant · model_label_shown · search_arm · session_fresh · question_id · question_class(A–I/control) · location_form · client_mentioned · position · …
- **Audit log** (one row per surface): client · layer · surface · country · status(✔/△/✘/na) · note · screenshot_ref · fix_id
- **Fix log** (one row per fix): fix_id · client · intervention_type · trigger_finding_ids · owner · agreed_date · implemented_date · verified_date · verification_evidence_ref

Keep one evidence folder per client, never commingled. This 15 minutes is the codification bridge — it is what makes client one's data usable by videt.ai later.

---

## The laws that apply everywhere (memorise these five)

1. **Counts, not scores.** The exemplar sentence: "You appeared in 2 of 20 sampled answers; cited once; address wrong in 4; [competitor] named 11 times." No composite scores, ever (Appendix C rule 2; Part 1).
2. **Nothing is reported that isn't captured.** Screenshot-backed, dated, N attached, "observed on [date], [assistant]" — and variance is reported as a finding, never smoothed over.
3. **Assistant-cited sources are leads, never findings.** Verify before it touches a report or fix plan (kit §6; Part 5 item 6).
4. **"Around 22" in writing; 20–25 is the internal spec; delivery is "within 5 business days of payment."** The offer PDF's exact promises are the contract until a real one exists.
5. **Sizzle, not machinery.** No methodology, spec or architecture leaves the building — not to clients, not to partners (Appendix C rule 6; Appendix L).

## Time budget (Part 2's table — your dashboard)

Intake 20 min → Reality Card 40 min → Readiness Audit 60–75 min → questions 15 min → observation 2.5–3.5 h → analyse 45 min → report 60 min → walkthrough 45 min → logging 15 min. **Total ≈ 6.5–8 h for the first ones, trending to ≈ 4.5 h by client five.** Whatever still eats time at client ten is the September automation shopping list.

## Not written anywhere yet — decide before client one

Honest gaps across all source documents (so you stop wondering where these live — they don't, yet):

1. **Engagement terms / contract** — nothing exists beyond "invoice on the spot"; the offer PDF is an offer, not a contract. One item for Luisa alongside the trademarks. Until then, the PDF's promises + the report disclaimer are your written terms.
2. **Invoicing mechanics** — Day 1 of the revenue plan already prescribes the setup tasks (invoice template, SKUs in your invoicing tool, payment details, booking link); what's undecided is the tool choice and GST treatment. The entity question stays with Luisa and must not block invoicing (Day 1 rule).
3. **The intake form and report template** — the delivery guide's Missing-inputs checklist (end of document, after Part 12) says: intake form built from Part 3; report template shell exists per Appendix D §6 but needs Part 9 sections 3 (Two pictures) and 6 (Readiness scorecard) added.
4. **The three log spreadsheets** (Phase 12) — schemas exist in Part 12; the actual sheets don't.
5. **Booking/scheduling tool** for the walkthrough (Day 1 names a "booking link" but no tool); no-show handling.
6. **Follow-up templates** — Appendix G is single-touch; no second-touch or post-demo follow-up message exists.
7. **The proof reports** — the PDF says "Ask to see those reports"; have the Lumen & Lever run plus assessments 0a/0b (SprungFloors/JA Floors — client businesses, written permission required before showing) presentable before the first prospect asks.
8. **Refund/dispute policy and client-data retention** — undefined; park with Luisa.
9. **Case-study consent wording** — Appendix J names the ask; no written consent line exists.

**Playbook defaults until decided** (mine, not canon — override freely): "delivered" = report PDF sent; evidence folders named `clients/{client-slug}/{YYYY-MM-DD}-assessment/` with `runs/`, `audit/`, `captures/` inside; walkthrough booked at the moment of invoice for day 4 or 5 of the clock.
