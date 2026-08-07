# VIDET Prospect Screen: the end-to-end runsheet

Status: operational runsheet v0.3, 6 August 2026. **Not canon.** Config populated and verified against the firms' own sites and ABN Lookup on 6 August 2026. Models under measurement: GPT-5.5 Instant and Claude Sonnet 5. This is the pre-sale screening pass: what you run on a prospect who has not paid, to earn the conversation. The paid flow stays `operations/CLIENT_PLAYBOOK.md` Phases 2 to 12 and nothing here replaces it.

Follow this top to bottom. It contains every prompt, every command, what to do with each output, and the three things you send at the end: a one-page report, an email, and a video.

Sources it obeys: `operations/PROBE_PROMPT_KIT.md` (prompt wording, verbatim), `investor/QUESTION_BANK.md` (archetypes), `investor/30_DAY_REVENUE_PLAN.md` Appendix C rules 2 and 9, Appendix D. Target list: `research/Videt Founding 20 Target List v2.md`.

**The rule that governs everything**, from the target list itself: *no gap gets claimed in outreach until it has been measured.*

---

## 0. The two-surface rule. Read this once, then never forget it.

The harness in this runsheet calls the OpenAI and Anthropic **APIs**. The API is not the consumer product. Different system prompt, different retrieval stack, different personalisation, different model routing. Appendix D section 2 specifies consumer surfaces.

So the work splits in two, and the split is not negotiable:

| | Surface | What it is for | What it may claim |
|---|---|---|---|
| **Screen** (steps 1 to 6) | API, scripted | Cover all ten targets, all questions, both arms, many repeats. Find which story is real. | Internal only. Never quoted to a prospect. |
| **Confirm** (step 7) | ChatGPT and Claude consumer apps, by hand | Re-run only the one or two specimens that reach the page or the camera. | This is what the one-pager cites. |

Every record the harness writes carries `surface: "api"` so this can never quietly get lost. The screen is the microscope. The confirmation is the photograph you publish.

## 0.1 What today produces

Three artifacts per prospect you decide to approach: a one-page report (step 8), an outreach email (step 9), and, for the broker vertical only, one shared video (step 10).

## 0.2 Time budget

| Step | What | Budget |
|---|---|---|
| 1 | One-time setup | 5 min |
| 2 | Four pre-run checks | 10 min |
| 3 | Dry run and model check | 5 min |
| 4 | Run the screen | 25 min wall clock, mostly unattended |
| 5 | Fetch every cited page | 10 min unattended |
| 6 | Read the report, pick the story | 30 min |
| 7 | Manual confirmation on the consumer apps | 30 min |
| 8 | Verify the specimen against the source | 30 min |
| 9 | Write the one-pagers and emails | 60 min |
| 10 | Record the video | 45 min |

About four and a half hours, and it covers all ten targets rather than three.

---

# PART A: THE SCREEN

## Step 1. Setup (5 min, once)

Dependencies are declared inline in the script (PEP 723), so `uv run` resolves them itself. No venv, no install step. Set both keys in your shell profile so they persist:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

```bash
export OPENAI_API_KEY="sk-..."
```

The harness lives in `operations/probe-harness/`:

- `videt_probe.py` is the script. Five subcommands: `plan`, `models`, `run`, `verify`, `report`.
- `probe_config.toml` is the seed file, populated and verified 6 August 2026. Questions, arms, repeats, all ten targets with websites, principals, addresses and the claims a human grades each answer against. To screen a different vertical later, copy this file and change two sections.
- `evidence/` is created on first run and holds everything captured.

## Step 2. The four things to check before you spend money (10 min)

The config is filled in. These four are the ones only you can close.

**1. The OpenAI model id.** `claude-sonnet-5` is exact. "GPT-5.5 Instant" is a ChatGPT product-tier label, not an API id: Instant is the fast non-reasoning tier, which on the API is the chat-tuned model rather than the reasoning one. The config carries a best guess. `models` resolves it against your key in five seconds, which is the only reason this is yours and not mine.

**2. The two fabrication controls, before every run.** Verified on ABN Lookup on 6 August 2026. **The original buyer's-advocate control was retired**: "HARPER AND VALE BUSINESS SOLUTIONS", ABN 22 943 569 955, is a live VIC entity, so the control was pointed at a real business. It is now **Kestrel & Marlowe Buyers Advocates**, confirmed with no combined match. **Ashcroft & Reid Business Brokers** is confirmed clear (114 partial hits on either word, none combining both). Re-check both before any future run: registrations happen, and a control that names a real business is worse than no control.

**3. Two corrections to the target list, which change how you pitch.** Both are recorded in the config's `notes`:

- **Vision Brokers and Advisors is head-officed in North Sydney**, with Melbourne as one of four offices. It is not a Melbourne firm. That sharpens rather than weakens the hook: the geography question is directly commercial for them, and the entity probe now asks whether the machine places them in Melbourne, Sydney, or somewhere else.
- **Expert Business Brokers are not "both MDs".** Sam Vasli holds the Principal and Managing Director title; Daniel Callegari is a Business Analyst and Licensed Business Broker. Do not repeat the both-MDs framing in outreach.

**4. Two blanks that are findings, not gaps.** `principal` is empty for Concierge Buyers Advocates and Melbourne Buyers Advocates because **neither names a principal on its own site.** Concierge publishes no address either, having gone fully mobile in 2020. That is the strongest structural hook in the advocate vertical: a business with no named human and no address on its own site cannot be resolved as an entity, so any principal or address a machine states for them is invention by definition, checkable in one click against their own About page. Leave both blank.

Your options if you want to change scope: `repeats_vertical = 3` and `repeats_entity = 2` are the screening floor, raise either if a finding looks marginal; drop `arms` to `["search"]` to halve the cost and lose the retrieval-versus-memory split; set `enabled = false` on a provider to run one model only.

## Step 3. Dry run and model check (5 min)

```bash
uv run operations/probe-harness/videt_probe.py plan
```

This makes no calls. It prints the job matrix, the call count and a cost estimate with its assumptions stated. Expect 212 jobs, 356 provider calls, and roughly $40 across both providers. If that surprises you, lower `repeats_vertical` before you spend anything.

```bash
uv run operations/probe-harness/videt_probe.py models
```

**What this is doing, plainly.** It asks each provider one question: "what models will you let this key use?" It sends no prompts, measures nothing, costs nothing. It is the equivalent of checking a phone number is connected before you dial it.

**What comes back.** Two blocks of lines, one per model, prefixed by provider:

```
anthropic  claude-sonnet-5
anthropic  claude-opus-5
...
openai     gpt-5.5
openai     gpt-5.5-chat-latest
...
```

If a key is wrong or unset you get `anthropic ERROR: ...` or `openai ERROR: ...` on one line instead of a list. That tells you which of the two keys to fix.

**What you are looking for.** Exactly two strings.

1. **`claude-sonnet-5`** in the anthropic block. Confirmed present 6 August 2026. If it ever is not, your key has not been granted it and that must be fixed before running, because it is half the study.
2. **The OpenAI id for the Instant tier.** "GPT-5.5 Instant" is what the ChatGPT app shows you; it is not an API name.

**Resolved 6 August 2026, and worth recording because it was not what I expected.** There is **no `gpt-5.5-chat-latest`.** The `-chat-latest` variants stop at 5.3. The 5.5 family on the key is `gpt-5.5`, `gpt-5.5-2026-04-23`, `gpt-5.5-pro` and its dated pin. So Instant is not a separate model id at all: it is the base 5.5 model held at its lowest reasoning effort, which is exactly what the ChatGPT Instant tier is. The config now carries:

```toml
[providers.openai]
model            = "gpt-5.5-2026-04-23"
reasoning_effort = "minimal"
```

Dated pin rather than the bare `gpt-5.5` alias, so the model cannot be repointed underneath a study in progress and quietly break comparability between your early and late runs.

**This is the check earning its place.** Had it been skipped, all 178 OpenAI jobs would have failed identically on a model id that does not exist.

**One thing to check after the run:** if `reasoning_effort` is rejected by the endpoint, the harness retries without it and writes `reasoning.effort=minimal rejected` into that run's `deviations`. Grep for that before describing anything as Instant tier, because without it you measured the default effort instead:

```bash
grep -c "reasoning.effort" operations/probe-harness/evidence/runs.jsonl
```

**What to report.** Nothing goes to a prospect from this step. It is a preflight check. But write the two exact ids you settled on into your day's notes, because `model_requested` and `model_reported` are stamped on every run record and a prospect can legitimately ask which model was asked. If the two ever disagree in `runs.jsonl`, the provider silently routed you elsewhere, and that is a deviation worth knowing about.

**Why this one is yours and not mine:** the list depends on your account's entitlements, which I cannot see without your key.

## Step 4. Run the screen (25 min, mostly unattended)

```bash
uv run operations/probe-harness/videt_probe.py run
```

What it does per job: asks the question cold, runs the two follow-ups on the first repeat, then makes a **separate** call on a fresh context to transcribe the answer into structured data. That separation matters. The kit's Stage C has the machine transcribe itself, which is fine when a human is driving a browser, but a second independent call removes the self-report contamination entirely. Every record notes `transcription_method: separate_call_fresh_context` so the deviation is on the record, not hidden.

It is **resumable**. If it dies, or you interrupt it, run the same command again and it skips everything already completed. To re-run one thing:

```bash
uv run operations/probe-harness/videt_probe.py run --only BB-1a
```

**Two things it does deliberately that look like bugs:**

- **A refusal is recorded, not retried.** If a model declines, that is an observation with its own finding class (`defective_observation`), not a failure. There is no automatic fallback to another model, because a fallback would silently swap the model being measured and corrupt the count.
- **It stores the entire raw response**, not just the text. If the structured extraction gets a field wrong, the evidence is still there to re-read. Extraction is a view over the evidence, never the evidence itself.

Output: `operations/probe-harness/evidence/runs.jsonl`, one JSON object per run, carrying the operator envelope fields the kit requires (timestamp, model requested, model reported, arm, repeat, location note, deviations) plus the raw response, the transcript and every URL seen.

## Step 5. Fetch every cited page (10 min, unattended)

```bash
uv run operations/probe-harness/videt_probe.py verify
```

This is the screenshot replacement, and it is better evidence than a screenshot. It collects every URL any answer cited or mentioned, fetches it, and saves the page text to `evidence/sources/` with a header carrying the URL, the fetch timestamp, the HTTP status and a SHA-256 of the body.

That gives you the dated capture of **the source side** of every claim. The claim side is already in `runs.jsonl`. Read them beside each other and you have done Stage D verification without opening a browser.

Limits, stated honestly: it strips HTML crudely, so a heavily scripted page may come back thin, and it does not execute JavaScript. When a page comes back empty and the claim matters, open it by hand.

## Step 6. Read the report and pick the story (30 min)

```bash
uv run operations/probe-harness/videt_probe.py report
```

Four blocks come out. Here is what each is for.

**1. Country attributed, per question.** This is the broker geography experiment. Compare `BB-1a` (no country word) against `BB-1b` (with "Australia"). The number you want is one sentence of this shape:

> Across N sampled answers to the unqualified question, X of Y named firms were attributed to the United States. Adding one word changed that to A of B.

That is a count, not a score, so it sits inside Appendix C rule 2. **It may not reproduce.** Your Florida finding came from a web search, not an assistant. If both arms come back clean and Australian, that is the finding, the broker hook becomes whatever else the report turns up, and there is no video today. Do not re-run until you get the answer you wanted. That single temptation is the only thing that would make the whole instrument worthless.

**2. Unprimed mentions per target.** Straight counts: "named in 2 of 18 sampled answers, first-listed in 1, (+3 only after prompting)".

The split matters and it is the one number people misread. The headline count is **cold mentions**: named in the answer to the buyer's question, unprompted. The bracketed figure is businesses that appeared only after a follow-up nudged for more. A firm that never comes up cold but surfaces under "are there any others worth considering?" is not being recommended, it is being retrieved on request. Report the cold number. Mention the prompted one only as context, never as the count. Three targets will come back as `GENERIC NAME, match by hand`: Buyers Advocate, Melbourne Buyers Advocates, Expert Business Brokers. The script refuses to guess whether "buyers advocate" in an answer means the business or the job title. **That refusal is itself the finding**, and it is a good one: a business whose name is indistinguishable from its category cannot be retrieved as an entity. Say exactly that on their page.

**3. Primed entity probes.** Per target: what the machine claimed about recognition, which people it attributed, which credentials it attributed, and the list of claims a human must now check. Watch `recognition`. A run that self-reports `inferring_from_name_and_category` while writing confident prose is the machine admitting it is generating plausible filler, and that is the highest-value specimen in the whole screen.

**4. Fabrication controls.** Either it abstained, which proves it *can* say "I don't know" and forecloses the "everyone knows AI makes things up" dismissal, or it described a business that does not exist, which is the CONF-20260729-001 specimen all over again. Both outcomes are useful. Keep whichever you get.

**Now pick.** You are looking for one specimen per prospect you intend to approach. A usable specimen is: specific (a name, a number, an address, a credential), checkable in one click, and stated without hedging. "May offer" is not a finding. Rank by materiality: would this change a buyer's decision, or misdescribe the business?

What to hunt per target, from the verified config. Each target's `claims_to_check` and `notes` carry the detail; this is the shape.

| Target | Hunt | Why it is checkable in one click |
|---|---|---|
| **Concierge Buyers Advocates** | Any principal name or street address | Their own About page names no human and publishes no address. Anything the machine states is invention by definition. **Strongest structural hook on the list.** |
| **Lloyds Business Brokers** | Entity conflation | Shares a name with Lloyds Bank and Lloyd's of London, and runs two live domains. Highest conflation risk here by a distance. |
| **Melbourne Buyers Advocates** | Conflation with Concierge | A competitor's homepage title is literally "Melbourne Buyers Advocates". Facts crossing between the two are textbook conflation, and both firms are on your list. |
| **Trident Business Sales** | An invented AIBB membership | They publish REIV credentials, not AIBB. An awarded AIBB membership is a fabricated credential. |
| **Mercury** | Invented or inflated credentials | Sells on AIBB, CPBB and registered-valuer status. Credentials are the highest-materiality class in a credential-led category. |
| **Vision Brokers** | Where it places them | Sydney head office, Melbourne is one of four. Does the machine put them in Melbourne, Sydney, or nowhere? |
| **Buyers Advocate** | Cited-but-not-retrieved | They publish the "Top 10 Best Buyers Agents in Melbourne" page that ranks the category. If the machines cite that page while failing to retrieve its author as an entity, that is the sharpest finding in this vertical. |
| **Cate Bakos, Metropole** | Stale or wrong, not absent | Most-cited in the category, so absence is not the story. The pitch to a category's authority is not "you're invisible", it is "you are the source, and it is quoting you wrong". For Metropole specifically: group-wide facts restated as Melbourne facts. |
| **Expert Business Brokers** | Absence, as the control | Thin marketing, generic name. The control on whether measured absence alone converts. Rank last. |

---

# PART B: CONFIRM, THEN PUBLISH

## Step 7. Manual confirmation on the consumer product (30 min)

**This is the step that makes anything publishable.** For each specimen you selected, re-run it by hand on the consumer app and screenshot that.

Conditions first, per kit section 1: ChatGPT with Temporary Chat on, memory off, custom instructions off. Claude in a fresh chat. No VPN, Melbourne, Australian IP. One fresh chat per run. If it asks a clarifying question, reply exactly `Just your best recommendations.`

**Pick the matching tier in each app**, so the confirmation lines up with what the screen measured: **GPT-5.5 Instant** in ChatGPT's model picker (not Thinking), and **Claude Sonnet 5** in Claude's picker. Note the label the picker shows and the label the product displays in the answer; they differ, and both go in your notes. The surfaces still are not identical, which is exactly why this step exists, but matching the tier removes the one difference you can control.

Prompts are verbatim from `PROBE_PROMPT_KIT.md`. Do not tidy the punctuation; changed wording is a new phrasing ID.

**For a vertical specimen (contamination, absence, who-got-named):**

```
Who are the best business brokers in Melbourne?
```

then, same chat:

```
Are there any others worth considering?
```

```
Of all of those, which single one would you pick for selling a $3 million Australian business, and why?
```

```
How do you know about these companies — where does this information come from? Please list the specific pages or sources for each one.
```

Swap the first line for `Who are the best buyers advocates in Melbourne?` and the anchoring follow-up for `...for buying a first investment property in Melbourne, and why?` on the advocate side.

**For an entity specimen (misdescription, invented credentials):**

```
What can you tell me about {BUSINESS NAME}, the {buyers advocate|business broker} in Melbourne? What do they do, who runs them, and would you recommend them?
```

then:

```
Are there any other businesses with the same or a similar name you might be mixing them up with?
```

```
Where does your information about them come from? List specific pages or sources.
```

**For the geography experiment on camera**, run both arms in separate fresh chats, one word apart:

```
Who are the best business brokers in Melbourne?
```

```
Who are the best business brokers in Melbourne, Australia?
```

Screenshot every answer in full, citations included. Save the share link if the product offers one. Three runs minimum of anything that becomes a count on the page.

**If the consumer product does not reproduce what the API screen found, the finding does not go on the page.** It stays as internal method material. That happens, and it is the system working.

## Step 8. Verify the specimen (30 min)

Before anything is a finding, in this order:

1. **Every named entity against ABN Lookup** (abr.business.gov.au). Existence, entity name, trading name, state. One screenshot each. This is where fabricated entities fall out.
2. **Every URL the answer cited.** Most are already fetched in `evidence/sources/` from step 5. Open the saved text beside the claim. The failure you are hunting is a **real page that does not support the claim**. That is the Clutch class, the most common failure and the most damning on camera, precisely because the link works, which is why nobody checks.
3. **Geography, for every broker firm named.** Registered address and stated location. A firm in Melbourne, Florida presented in answer to a question a Melbourne buyer asked is `geographic_boundary_breach`. State the fact. Never characterise the firm.
4. **Credentials claimed.** AIBB membership against the AIBB member directory. Registered valuer status against the relevant register. For buyer's advocates, the estate agent licence against the Victorian public register held by Consumer Affairs Victoria. **Confirm the exact register name and URL before you cite it**, because citing a register wrongly in a report about citation errors is not survivable.
5. **Each primed answer field against your config's `principal` and `claims_to_check`.** You have no Reality Card for a prospect, so the standard is: publicly verifiable and dated. Anything you cannot verify from a public source is an unknown, and unknowns do not go on the page.

Then classify. Exactly one class per observation, no blending:

Absence · Entity Conflation · Temporal Hallucination · Geographic Boundary Breach · Authority Spoofing · Anchoring Fragility · Defective Observation

Write a capture file for every failure into `operations/captures/CONF-20260806-NNN.md`, using the schema in kit section 6 and modelled on `operations/captures/CONF-20260729-001.md`. Copy that file's habit of writing down explicitly what the finding does **not** say. That accuracy guard is what makes a specimen safe to use.

## Step 9. The one-page report and the email (60 min)

**The one-pager does not exist in canon.** The eight-section report in the playbook is the paid A$990 deliverable and must not be given away. This is the pre-sale page: enough measured truth to be undeniable, not enough to be the product. Playbook default, mine not canon, override freely.

### The template

> **[Business name] — what AI assistants said, [date]**
>
> *A screening pass, not an assessment. [N] sampled answers across ChatGPT and Claude on [dates], asked from Melbourne in fresh sessions with memory off. Every observation below is screenshot-backed.*
>
> **1. The question your buyers asked**
> Verbatim, one or two. *"Who are the best business brokers in Melbourne?"*
>
> **2. What came back**
> Three or four counts. Nothing else. Shapes: named in 2 of 12 sampled answers · first-listed in 1 · not named at all on Claude · 4 of 11 firms named were United States firms.
>
> **3. One thing it said, and what is actually true**
> The verbatim machine quote in its own block. Then the verified fact beside it. Then the date of both captures. **One** specimen, not three. One with proof beats three with assertion.
>
> **4. Who it named instead**
> "ChatGPT, sampled 5 times on 6 August, named: [list]." Nothing further. No adjectives about anyone's business.
>
> **5. What this does not tell you**
> "This is [N] answers to [X] questions, on one day, on two assistants. It cannot tell you whether that holds, and one answer is not a verdict either way. The assessment asks around 22 real buyer questions across four assistants, repeatedly over days, and hands you the counts, the screenshots and ten prioritised fixes."
>
> **6. If you want yours measured properly**
> Founding cohort, A$990, or A$1,490 with the 90-day re-measure. Delivered personally within five business days of payment.
>
> ---
> *This is a measurement of AI assistant behaviour, not professional advice.*
> *Every observation in this report is screenshot-backed and dated. Ask us for any of them.*

Both footer lines are mandatory report furniture, per brand pack section 4.3 and Appendix D section 6. Visual conformance: filled master mark in the header from `branding/logo/`, counts and dates in the mono stack, and run the brand pack section 8 checklist before it ships.

**Section 5 is the one you will want to cut. Do not.** It is what makes sections 2 and 3 believable, and it doubles as the sales argument: the limits of the free page are the specification of the paid one.

**Section 4 is the legal one.** You are sending a document naming a prospect's competitors to that prospect. Appendix C rule 9 is not decorative: every competitor line is "Assistant X, sampled N times on [date], named Y" and nothing else.

### The email

Adapt Appendix G.2. The claim in the email is the count from section 2, quoted exactly, nothing extrapolated. Draft:

> Hi [name],
>
> A question you probably can't answer today: when someone asks ChatGPT who the best [business broker / buyers advocate] in Melbourne is, does your name come up, and are the details right when it does?
>
> I checked. On [date] I asked that question and [N-1] others across ChatGPT and Claude, in fresh sessions, from Melbourne. [One measured count, verbatim from section 2.] I've put the counts and what I found on one page, attached. Every line on it is screenshot-backed and dated.
>
> It's one day and two assistants, so it can't tell you whether that holds. That's what the full assessment is for: around 22 real buyer questions across four assistants, repeated over days, with the counts, the screenshots and ten plain-English fixes. Founding cohort of 20 this August.
>
> Worth 90 seconds on a call?
>
> Lee

Log every send in the Appendix E tracker the same day. Log any reply or objection in Appendix H the same day.

## Step 10. The video (45 min)

**One video, not ten.** The broker geography finding is vertical-level, needs no claim about any prospect, and serves five targets. Record it **only if step 7 reproduced the contamination on the consumer product.** If it did not, there is no video today, and that is the correct outcome.

Production rules from `branding/007 SCALING_LISTING.md`: real screens only, never re-shoot for a better answer, never stage one, QuickTime and a phone mic is enough, no music, one take is fine.

| Time | Screen | Say |
|---|---|---|
| 0:00-0:05 | Blank ChatGPT tab | "This is the question an owner asks when they're thinking about selling. Watch what comes back." Type it live, slowly. |
| 0:05-0:25 | The answer rendering | Nothing. Silence while a machine ranks your market. Scroll gently. Do not narrate. |
| 0:25-0:45 | Same answer, cursor on the location lines | "It's ranked them. It's told me who it would sell its own business through. So let's do the thing nobody does. Let's check where they are." |
| 0:45-1:15 | New tab, the register or the firm's own contact page | The factual line only. The postcode and the state on screen, long enough to read. |
| 1:15-1:35 | Second arm typed live | "Now watch what one word does." Type the version with Australia in it. Let it answer. |
| 1:35-1:50 | The two answers side by side | "Same question. One word. Different market." |
| 1:50-2:10 | Card 3 from `branding/listing-assets/` | The scoreboard beat, verbatim from the Scaling script: keep your provider, I'm the diagnostic and the scoreboard. Twenty founding places, delivered personally. |

**The legal decision, and it is yours not mine.** The Scaling video script carries a binding rule: *name no real company on camera.* The geography finding cannot be shown without a real firm's location on screen. Those two are in direct tension.

The safe cut, and my recommendation: show the postcode and the state as a neutral, verifiable, public fact. Say nothing whatsoever about the firm, its quality, its conduct or its intentions. Never suggest anyone was trying to mislead anyone. The claim on camera is about the machine's answer pool, not about any broker. Blur or scroll past every name you are not required to show. Say invented, misplaced or wrong-hemisphere. Never say lying.

If it still reads too close to the line when you watch it back, the fallback is the fabrication control from step 6 block 4: a business that does not exist, described confidently, with the register showing nothing. That was the CONF-20260729-001 play, and it harms nobody, which is exactly why it was chosen last time.

---

## What this is not

- **Not an assessment.** Ten screening passes do not become case studies and must never be described as such.
- **Not a free pilot.** The page is a measured hook with a price on it, not a sample of the deliverable. "We'd love to try it free" is still a no with flattery.
- **Not methodology out the door.** Sizzle, not machinery. Nothing from this runsheet, the harness, the kit, the delivery guide or the spec goes to a prospect, ever.
- **Not a claim about anyone's business.** Every competitor line stays factual and attributed. Every finding is about what a machine said, verified against a public record, on a stated date.
- **Not the platform.** `operations/probe-harness/` is throwaway operations tooling. It is not app code, not spec, not a Volume III prototype. When the platform does this properly, delete it.

## Before you close the laptop (15 min, do not skip)

`runs.jsonl` and `evidence/sources/` committed or backed up. Capture files written for every failure. Consumer-product screenshots filed per prospect under `prospects/{slug}/2026-08-06-screen/`. Sends logged in the Appendix E tracker with the date. Replies and objections logged in Appendix H.

This is the codification bridge. It is what makes today's data usable by the platform later, and it is the first thing anyone skips.
