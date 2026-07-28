# VIDET Probe Prompt Kit — v0.1

Status: Operational instrument, 28 July 2026. The paste-ready prompts for manual VIDET tracing across any AI assistant (ChatGPT, Gemini, Grok, Claude, Copilot, Perplexity). Companion to `ASSESSMENT_DELIVERY_GUIDE.md` Parts 5–7 and `investor/QUESTION_BANK.md`. Schema names here (`manual-probe-capture-v0.1`, `confabulation-capture-v0.1`) are candidates that graduate into `specification/volume-iii-inputs/` Module 1 via the normal front door — nothing here is canon. Version this file: any change to a prompt's wording is a new phrasing ID (§1.6); never silently edit a prompt that has produced runs.

---

## 0. The one design rule everything follows

**The measurement is the natural question. The JSON is the transcription.**

If your first message says "return rankings as JSON with citations," you are no longer measuring what a customer sees — you're measuring what the machine does when asked to perform an audit. Assistants answer differently under those conditions (more hedging, more structure, different retrieval behaviour). So every instrument-grade run is staged:

1. **Stage A** — the natural buyer question, verbatim, nothing else. *This is the observation.*
2. **Stage B** — natural follow-ups (anchoring + source elicitation), still in buyer voice.
3. **Stage C** — the JSON transcription prompt, last, same chat. The machine formalises what it already said. It cannot re-answer; the answer is already on the record.
4. **Stage D** — operator verification, outside the chat. You check every claim and citation against reality. *Failures are captured as specimens, not just marked wrong* (§6).

A single-shot combined prompt exists (§7) for demos and quick screens — it is **screening-grade only, never comparable with staged runs**, because the JSON instruction contaminates the answer.

Second rule, from the Clutch case: **everything the machine says about its own sources and reasoning is `self_reported` — a lead, never a finding.** The "logic" it returns in Stage C is a story it composes about itself, not a trace of its mechanism. It's still worth capturing (it tells you what the machine *believes* is persuasive, and it generates verifiable leads), but nothing self-reported enters a client report, score, or plan until Stage D verifies it.

---

## 1. Run conditions (set these BEFORE pasting anything)

Each run = one fresh chat. Record every field in the operator envelope (§5). The machine cannot report most of these — you must.

1. **Fresh chat, memory off.** ChatGPT: Settings → Personalization → Memory off, and custom instructions off (or a temporary chat). Gemini: no relevant prior activity, Gems off. Grok: fresh chat, personalization off if offered. If you can't disable memory, record `memory_state: "uncontrolled"` — the run is screening-grade at best.
2. **Account state.** Logged in/out, free/paid tier, which model selected in the picker (record the label *you* selected AND what the product displayed — they differ).
3. **Geography.** Your physical location, VPN on/off + exit country, browser locale. Assistants localise; a Melbourne question asked from a US IP is a different experiment.
4. **Search arm.** Three states:
   - `on` — product's browsing left enabled/default.
   - `forced_off_by_prompt` — prefix Stage A with exactly: *"Please answer from your own knowledge only — do not search the web for this."* (This is the only permitted contamination, and it's declared.)
   - `unknown` — product gives no control and no indication.
   Run both arms as separate chats. The delta between arms is the retrieval-vs-parametric split — one of the most valuable numbers in the whole assessment.
5. **Unprimed means unprimed.** In a recommendation probe (§2), never mention the subject business, in this chat or recent history. The primed entity-resolution probe (§3) is a separate fresh chat, always run after the unprimed ones that day, never before.
6. **Phrasing ID.** Use the exact phrasing from your declared set (below) and record which. Phrasing is a condition variable; "best" vs "recommend" vs "who should I use" are different experiments.
7. **Capture.** Screenshot the full answer (visible citations included) and save the chat share-link if the product offers one. The share-link is your evidence artifact.
8. **If the assistant asks a clarifying question**, reply exactly: *"Just your best recommendations."* Record that this happened (`clarifier_asked: true`).

---

## 2. PROBE R — Recommendation probe (unprimed)

### Stage A — the natural question (paste ONLY this)

Pick one phrasing, fill the slots, paste nothing else:

- **R1:** `Who are the best {{CATEGORY}} in {{LOCATION}}?`
- **R2:** `Can you recommend a {{CATEGORY_SINGULAR}} in {{LOCATION}}? {{NEED_SENTENCE}}`
- **R3:** `I'm looking for a {{CATEGORY_SINGULAR}} in {{LOCATION}} for {{USE_CASE}}. Who should I consider and why?`

Slots: `{{CATEGORY}}` e.g. "AI consultants" · `{{LOCATION}}` e.g. "Melbourne" · `{{NEED_SENTENCE}}` an optional one-line buyer need, e.g. "I run a 40-person accounting firm and want help adopting AI." · `{{USE_CASE}}` e.g. "a fractional AI advisor engagement". Map each run to its QUESTION_BANK archetype (A–I) in the envelope.

Let it finish completely. Screenshot.

### Stage B — natural follow-ups (in order, buyer voice)

- **FB1 (depth):** `Are there any others worth considering?`
- **FB2 (anchoring):** `Of all of those, which single one would you pick for {{USE_CASE}}, and why?`
- **FB3 (source elicitation):** `How do you know about these companies — where does this information come from? Please list the specific pages or sources for each one.`

FB2 feeds the Follow-up Anchoring Index (does the machine stay committed or reshuffle?). FB3 is the confabulation trap — its output is 100% `self_reported` and every URL it names goes to Stage D.

### Stage C — the transcription prompt (paste verbatim, last)

```
Thank you. Now, as a final step, transcribe THIS conversation into a single JSON object.

Rules:
- Transcribe only what you already said above. Do not add new recommendations, revise rankings, or search again.
- If you did not state something above, use null. Never guess. Never invent a URL — if you are not certain a URL is real and exactly correct, put it in "url_uncertain" instead of "url".
- Return ONLY the JSON object, no commentary.

{
  "schema": "videt.manual-probe-capture-v0.1",
  "probe": "recommendation",
  "assistant_self_id": {
    "product": "<what product are you>",
    "model_version_displayed": "<the model version you believe you are, or null>",
    "search_used_this_chat": true | false | "unknown"
  },
  "question_answered": "<the user's first question, verbatim>",
  "clarifier_asked": true | false,
  "recommendations": [
    {
      "position": 1,
      "name_as_written": "<entity name exactly as you wrote it>",
      "url": "<official website ONLY if you are certain>",
      "url_uncertain": "<best guess if not certain, else null>",
      "location_attributed": "<the location you attributed to it>",
      "descriptors": ["<the qualities/services you attributed to it>"],
      "first_mentioned_in": "initial_answer" | "followup_1" | "followup_2",
      "why_recommended_self_report": "<the reasoning you gave — your own account>",
      "sources_self_report": [
        {
          "source_name_or_url": "<as you stated in this chat>",
          "claimed_support": "<what you claimed this source shows about this entity>",
          "certainty": "certain" | "likely" | "reconstructed_guess"
        }
      ]
    }
  ],
  "entities_mentioned_but_not_recommended": ["<names>"],
  "final_single_pick": { "name": "<from the 'which one' follow-up>", "reason_self_report": "<...>" },
  "caveats_you_stated": ["<hedges/disclaimers you gave>"],
  "self_report_disclaimer": "I acknowledge that my account of my own sources and reasoning may not reflect my actual mechanisms and must be independently verified."
}
```

The `certainty` enum matters: machines will often confess `reconstructed_guess` when given the option — that's a confabulation self-flagging for free. The fixed `self_report_disclaimer` string doubles as a schema-compliance check.

---

## 3. PROBE E — Entity-resolution probe (primed, separate fresh chat)

Measures whether the machine can resolve and correctly describe THE SUBJECT. Run against the client's Reality Card. New chat, same run conditions.

### Stage A

`What can you tell me about {{BUSINESS_NAME}}, the {{CATEGORY_SINGULAR}} in {{LOCATION}}? What do they do, who runs them, and would you recommend them?`

### Stage B

- **FE1 (disambiguation):** `Are there any other businesses with the same or a similar name you might be mixing them up with?`
- **FE2 (source elicitation):** `Where does your information about them come from? List specific pages or sources.`

### Stage C — transcription (same rules preamble as §2, then:)

```
{
  "schema": "videt.manual-probe-capture-v0.1",
  "probe": "entity_resolution",
  "assistant_self_id": { ...as in the recommendation probe... },
  "subject_as_understood": {
    "name_as_written": "", "url": null, "url_uncertain": null,
    "location_attributed": "", "services_attributed": [], "people_attributed": [],
    "founded_or_age_attributed": null, "credentials_attributed": [],
    "recommendation_stance": "recommended" | "neutral" | "cautioned" | "declined_to_say",
    "stance_reason_self_report": ""
  },
  "recognition_level_self_report": "know_this_specific_business" | "recognise_name_only" | "inferring_from_name_and_category" | "do_not_know",
  "possible_confusions_self_report": ["<other entities you might be conflating>"],
  "sources_self_report": [ { "source_name_or_url": "", "claimed_support": "", "certainty": "certain" | "likely" | "reconstructed_guess" } ],
  "self_report_disclaimer": "<same fixed string>"
}
```

`recognition_level_self_report` is the key field: `inferring_from_name_and_category` is the machine admitting it's generating plausible filler — which, said confidently in prose, is exactly the confabulation your client would never detect. Every field here gets checked against the Reality Card in Stage D; every wrong field is a specimen.

---

## 4. Sampling discipline

- One run = one fresh chat = one row. Never continue an old chat for a new run.
- **Screening grade:** ≥3 runs per (assistant × question × arm). Counts only ("mentioned in 0 of 3").
- **Instrument grade:** N=10–30 per condition cell; rates with Wilson intervals; only then are rates client-facing.
- Spread runs across ≥2 days and times of day; assistants are stochastic and product-side changes happen without notice.
- A malformed run (refusal, truncation, product error, wrong arm by accident) is quarantined as `defective_observation` — logged, never averaged into denominators.

---

## 5. Operator envelope (you fill this — the machine can't)

One per run, alongside the machine's JSON:

```
{
  "schema": "videt.operator-envelope-v0.1",
  "run_id": "R-{{YYYYMMDD}}-{{ASSISTANT}}-{{NNN}}",
  "operator": "", "datetime_local": "", "timezone": "",
  "assistant_product": "", "model_selector_chosen": "", "interface": "web" | "app",
  "account_state": "logged_out" | "free" | "paid",
  "geography": { "physical": "", "vpn_exit": null, "browser_locale": "" },
  "memory_state": "fresh_memory_off" | "uncontrolled",
  "search_arm": "on" | "forced_off_by_prompt" | "unknown",
  "probe": "recommendation" | "entity_resolution",
  "phrasing_id": "R1" | "R2" | "R3" | "E1",
  "intent_archetype": "A".."I",
  "category": "", "location": "", "use_case": "",
  "subject_business": "", "subject_named_in_probe": false,
  "subject_mentioned_by_machine": true | false,
  "subject_position": null,
  "capture": { "share_link": null, "screenshots": [], "raw_json_saved_as": "" },
  "deviations": "",
  "grade": "screening" | "instrument" | "demo_contaminated"
}
```

`subject_mentioned_by_machine` + `subject_position` are yours to judge from the transcript (the unprimed machine doesn't know there IS a subject). These two fields alone drive Mention Rate and Position-Weighted Score.

---

## 6. Stage D — Verification and CONFABULATION CAPTURE

Every self-reported source and every factual claim about the subject gets checked by a human against the live source. **The point is not a pass/fail mark — it's that every failure is a specimen.** Confabulations are VIDET's core evidence asset: they prove the problem exists, they seed the Truth & Claims test corpus, and they are the single most persuasive artifact in a sales conversation ("here is the machine, in writing, citing a page that doesn't say that").

For each claim/citation, record a verification row; when the outcome is anything other than `supports`, promote it to a full confabulation capture:

```
{
  "schema": "videt.confabulation-capture-v0.1",
  "capture_id": "CONF-{{YYYYMMDD}}-{{NNN}}",
  "run_id": "<the run that produced it>",
  "claim_verbatim": "<exactly what the machine said, quoted from transcript>",
  "claim_stage": "initial_answer" | "followup" | "source_elicitation" | "json_transcription",
  "cited_source": "<URL or source name, if any>",
  "verification": {
    "checked_at": "", "method": "manual_visit" | "archive" | "registry_lookup",
    "outcome": "supports"
             | "source_exists_but_does_not_support"   // the Clutch class: real page, invented contents
             | "source_does_not_exist"                 // fabricated URL/source
             | "source_unreachable"                    // record and retry once, next day
             | "partially_supports",                   // some of the claim, not the load-bearing part
    "what_the_source_actually_shows": "<one paragraph, factual>",
    "evidence": { "screenshot_of_claim": "", "screenshot_of_source": "", "source_archive_link": null }
  },
  "confabulation_class": "citation_misattribution"     // real source, wrong contents (Clutch)
                       | "fabricated_source"           // source doesn't exist
                       | "entity_conflation"           // facts from a different business
                       | "temporal_hallucination"      // outdated stated as current
                       | "attribute_invention"         // services/people/credentials invented
                       | "geographic_boundary_breach"  // wrong-location entity presented as local
                       | "false_recognition",          // claimed to 'know' a business it was inferring
  "machine_certainty_at_time": "certain" | "likely" | "reconstructed_guess" | "not_elicited",
  "materiality": "high" | "medium" | "low",
  "usable_as_sales_specimen": true | false,
  "notes": ""
}
```

Rules:
- **Screenshot both sides, same day.** The claim AND the source page. Pages change; a specimen without a dated capture of the source is unusable. Archive the source page (e.g. web.archive.org) when possible.
- `machine_certainty_at_time` is the interesting cross-tabulation: a `certain` × `source_exists_but_does_not_support` capture is the perfect specimen — maximum machine confidence, verifiably false.
- Materiality: `high` = would change a buyer's decision or defame/misdescribe the subject; that's what goes in reports and sales decks.
- Client reports name the confabulation *class and evidence*, never speculation about why the machine did it. We show what it said and what is true; we don't pretend to explain its internals.
- The verification rows (including clean `supports` outcomes) feed the Citation Accuracy Rate. The captures feed the findings taxonomy and, later, Module 4's test corpus.

---

## 7. Single-shot screening variant (demos only)

For a live demo or a fast screen where staging is impractical — **grade: `demo_contaminated`, never comparable with staged runs**:

```
{{NATURAL QUESTION exactly as in §2 Stage A}}

After you have fully answered the question above in your normal way, then — as a separate second section — provide the same answer transcribed as JSON using this schema: {{paste §2 Stage C schema}}. The JSON must transcribe your answer above, not replace it.
```

This is excellent theatre for the walkthrough close (the prospect watches the machine rank their competitors in real time). It is not measurement.

---

## 8. What to expect per model (record deviations, don't fight them)

- **ChatGPT:** best JSON compliance; will sometimes re-search at Stage C — the instruction forbids it, but if the UI shows searching, record it in `deviations`. Temporary Chat is the clean condition.
- **Gemini:** may wrap JSON in prose or markdown fences (fine — strip them); more likely to refuse the "recommend one" follow-up; search arm is hard to force off — expect `unknown` arms.
- **Grok:** most likely to editorialise inside JSON fields and to be overconfident in `certainty` — its `certain` misattributions are often the best specimens.
- **Claude:** most likely to volunteer `reconstructed_guess` honestly; may decline confident rankings — a declined ranking is itself a data point (`recommendation_stance` capture).
- **Perplexity/Copilot:** citation-forward products; visible link citations are *retrieval* citations (record them in the envelope from your screenshot — they're real observed behaviour, distinct from FB3's self-reports; verify them too).
- Any model may ignore the schema. Do not re-prompt more than once (`Please output only the JSON object.`). If it still fails, transcribe by hand from your screenshot — the observation is not wasted; only the transcription convenience is.

## 9. Volume III bridge

Each staged run yields four artifacts: the machine JSON (§2/§3), the operator envelope (§5), verification rows + confabulation captures (§6), and the screenshots/share-link. These map onto Module 1's observation schema (run + condition cell + capture), Module 4's `self_reported → verified` state machine and claim classes, and the findings taxonomy — so nothing collected manually is thrown away when the platform builds. When these schemas graduate, they do so through the vision-set ADR; bump the version string here first and note the change.
