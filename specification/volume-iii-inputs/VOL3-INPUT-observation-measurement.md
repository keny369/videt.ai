# VOL3-INPUT — Module 1: Observation & Measurement Engine

Status: Volume III specification input — future/gated; enters canon only via the vision-set ADR (see `specification/machines/001 VOLUME_III_ARTIFACT_MAP.md`). Nothing in this document is ratified. Volume I/II are frozen and the ratified Product Architecture Manual is the single source of truth (ADR-001/ADR-012). This artifact is future/research-grade and becomes authoritative only when filed through the ADR front door after Day 30 (27 Aug 2026), and only where a controlled Volume I change and an approved OD-010 Measurement Set expressly enable it.

Provenance: codifies `specification/machines/000 MACHINE_BEHAVIOUR_SYNTHESIS.md` §§4–7, `operations/ASSESSMENT_DELIVERY_GUIDE.md` Parts 1/5/6/7/12, `operations/AUTHORITY_ROADMAP.md`, `specification/machines/002 ANSWER_PATH_AND_AUTHORITY_SPEC.md`, and `investor/QUESTION_BANK.md`, expressed as an implementation-grade specification for a future engineering agent. It extends the canonical vocabulary of `specification/011 DOMAIN_MODEL.md`, `specification/002 GLOSSARY.md`, `specification/003 TERMINOLOGY.md`, `specification/volume-i/SCORE_EVIDENCE_MODEL.md`, and the FUTURE-WORKFLOW-001 Observation Contract. It creates **no competing dictionary**: every domain object named here is either an existing canonical object or an explicitly-flagged candidate for the vision-set ADR.

Vocabulary caution recorded, not resolved: this module uses **Finding** in the FUTURE-WORKFLOW-001 research sense (an observed measurement pattern). The frozen `003 TERMINOLOGY.md` names **Issue** as the sole canonical customer/product deficiency object and forbids "finding" as an alias. This document keeps the two strictly separate (a Finding is what the measurement engine emits; an Issue is what the Evaluation Context later creates). The collision itself is left for the vocabulary ADR.

---

## 1. Purpose, scope, and non-goals

### 1.1 Purpose

Define, at implementation grade, how VIDET **observes** AI assistants answering buyer-intent questions about a subject business and **measures** their behaviour into governed, reproducible, honesty-bounded records. The engine is the OBSERVE stage of the OBSERVE → ASSESS → COMPARE → INTERVENE → LEARN customer-value loop (`governance/CUSTOMER_VALUE_CONSTITUTION.md`). Its output is the raw material of the **Perception Graph** — what assistants believe and say — which is later compared against the **Reality Graph** (ground truth) to produce the **Gap** the customer pays to close, informed by the **Intelligence Graph** (per-assistant, per-vertical accreting knowledge).

### 1.2 Scope

This module specifies:

1. The **Observation Contract** — the canonical, typed record of one query→response observation (extends FUTURE-WORKFLOW-001; the manual-era projection is the delivery-guide Part 12 run-log row).
2. **Run orchestration, idempotency, and session isolation.**
3. The **two measurement grades** (Screening and Instrument) as first-class configuration.
4. The **two-arm search-on / search-off** design and its layer-attribution semantics.
5. **Geography / location control**, **model-version capture**, and the **factorial condition matrix**.
6. The **five metrics** with exact formulas, VIDET's declared position weights, and Wilson intervals.
7. The **follow-up chain**, including the mandatory source-elicitation probe.
8. **Run-failure quarantine** (`defective_observation`) criteria.
9. The **complete run-log / Observation data model**, every field typed.
10. **Reproducibility** handling for a stochastic subject.
11. The **OD-010 gate** that stands between this engine and any automated external measurement.
12. **JSON schemas** for the observation record, the measurement run, and the metrics report.
13. **Invariants, state machines, acceptance criteria, and open questions.**

### 1.3 Non-goals

- This module does **not** define scoring weights, Issue creation, RecommendationArtifact rendering, or dashboard widgets — those belong to the Evaluation, Recommendation, and Delivery contexts.
- It does **not** authorize automated collection. Automated activation is gated (see §14). The present, authorized mode is **manual, human-scale observation** per delivery-guide Part 11 guardrail 6.
- It does **not** redefine the ratified `external-observation-v1` payload; it proposes a superset (`ai-answer-observation`) as an ADR candidate.
- It does **not** produce composite scores. Composite "AI ranking scores" are banned (`operations/AUTHORITY_ROADMAP.md` claim discipline; synthesis §4). The engine emits **counts and per-metric rates with intervals**, never a blended index.

---

## 2. Positioning within the three-graph architecture

| Graph | What it holds | This engine's relationship |
|---|---|---|
| **Reality Graph** | Ground truth (the Reality Card): canonical NAP, registrations with numbers, services, locations, practitioners, confusable-entity list | **Input.** Every correctness judgement (facts wrong, entity conflation, boundary breach) is scored against the Reality Graph. The engine never mutates it. |
| **Perception Graph** | What assistants say and believe about the subject | **Primary output.** Each Observation is a timestamped, session-isolated sample of the Perception Graph for one condition cell. |
| **Gap** | The compare-time delta between Reality and Perception | Derived downstream (COMPARE). The engine supplies the measured Perception side and the metrics that quantify the delta. |
| **Intelligence Graph** | Per-assistant, per-vertical empirical behaviour accreting over time | **Secondary output.** Sealed Observations and cross-wave metrics feed the per-assistant behaviour specification (`specification/machines/` empirical files, VOLUME_III_ARTIFACT_MAP layer 6). |

Governing constraint (synthesis §2.1): **there is no ranking engine inside the model.** The engine measures emergent behaviour — token-probability-driven mention and ordering, retrieval footprint, and constraint-fit — never a fictional internal score. All claims about "why" are prohibited absent controls and pre/post evidence.

---

## 3. Canonical objects extended and introduced

### 3.1 Existing canonical objects reused (no redefinition)

- **Evidence** (`evd_id`, logical `evidence_id`) — the immutable governed record. A sealed Observation, once an OD-010 Measurement Set is active, is persisted as **Measurement Evidence** (`evidence_type=external_measurement`) with a payload conforming to the Measurement Set contract. Manual-era Observations are logged in the run-log projection and become Evidence at platform ingestion.
- **Citation** (`cit_id`) — per OD-007, exactly one AIResponse and one Evidence, no direct Evaluation link. Assistant-elicited sources are **not** Citations until verified; they are candidate references flagged `self_reported` (see §11).
- **Source** (`src_id`), **Project** (`prj_id`), **Organization** (`org_id`), **Evaluation** (`eval_id`), **AIResponse** (`air_id`), **Issue** (`iss_id`), **RecommendationArtifact** (`rec_id`), **ScoreSnapshot** — reused verbatim from `011 DOMAIN_MODEL.md`.

### 3.2 Candidate objects introduced by this module (ADR-gated)

All follow ADR-013 Genesis conventions (explicit aggregates, immutable evidence, versioned records) and are **candidates**, valid only after the vision-set ADR:

| Candidate object | Namespace (proposed) | Aggregate root | Responsibility |
|---|---|---|---|
| **Observation** | `obs_id` | Measurement Run | One query→response sample under one condition cell; the Observation Contract record (§5). |
| **Measurement Run** | `mrun_id` | Measurement Run | The orchestration/idempotency boundary for one condition cell × grade × wave (§6–7). |
| **Measurement Wave** | `wave_id` | Measurement Campaign | A temporal batch (baseline / day-7 / day-30 / day-90 / post-version-change) grouping Runs for longitudinal comparison. |
| **Condition Cell** | `cell_id` | Measurement Campaign | A unique tuple of controlled factors (§10). |
| **Metrics Report** | `mrep_id` | Metrics Report | The computed five-metric result for an entity (or the category) over a set of Observations, with grade, N, and intervals (§8, §13). |
| **Follow-up Chain** | `chain_id` | Measurement Run | The ordered probe sequence within one session (§9). |
| **Elicited Source Reference** | `esrc_id` | Observation | An assistant-cited source, `self_reported`, pending verification (§11). |

The Observation candidate is the platform materialization of the FUTURE-WORKFLOW-001 Observation Contract; the delivery-guide Part 12 run-log is its manual-era projection, field-for-field.

---

## 4. Reproducibility and the stochastic-subject premise

The subject is non-deterministic: recommendation "emerges from autoregressive token probability distributions" (synthesis §2.1), sampling is stochastic, and product-level tool routing and model-version changes are uncontrollable (synthesis §3, Uncontrollable). The engine therefore treats reproducibility as a **measured property, not an assumption**:

- Every Observation records a **`reproducibility_class`**: `stochastic_surface` (default for assistant chat) or `deterministic_surface` (a rare surface that returns identical output for identical input; must be proven, never assumed).
- Reproducibility is achieved by **replication under fresh sessions**, not by seeds. Seed/temperature are declared uncontrollable and are never claimed to be held.
- **Cross-run agreement** is a first-class reported quantity (screening: raw agreement counts; instrument: an agreement statistic — see Open Questions on the exact statistic) so the client sees how stable a behaviour is.
- Cross-wave comparison is valid **only when `assistant_id` and the resolved model version are constant**. A detected version change sets `version_break=true` on the later Wave and **forbids** before/after delta claims across the break; the break is reported as its own event, never silently averaged.
- Determinism guarantees from the platform apply to the **coding and metric computation**, not to the subject: given the same sealed Observation set and the same Metrics Set version, metric outputs MUST be byte-identical (deterministic input hash per `SCORE_EVIDENCE_MODEL.md` canonical-JSON rule).

---

## 5. The Observation Contract

### 5.1 Definition

An **Observation** is the immutable record of exactly one primary question or one follow-up probe issued to one assistant in one isolated session, plus the coded result. It extends the FUTURE-WORKFLOW-001 Observation Contract and is the typed superset of the delivery-guide Part 12 run-log row.

### 5.2 Canonical fields (typed)

Identity & lineage:

| Field | Type | Notes |
|---|---|---|
| `obs_id` | uuid | Opaque, immutable, globally unique (DM-REQ-005). |
| `schema_version` | ascii[1..120] | Observation Contract version, e.g. `observation-contract-v1`. |
| `organization_id` | uuid | Tenant boundary (DM-REQ-006 label). |
| `project_id` | uuid | Every Observation belongs to exactly one Project. |
| `campaign_id` | uuid | Measurement Campaign. |
| `wave_id` | uuid | Temporal batch (baseline/7/30/90/version-change). |
| `mrun_id` | uuid | Owning Measurement Run (condition cell × grade). |
| `cell_id` | uuid | Condition Cell tuple reference (§10). |
| `chain_id` | nullable uuid | Follow-up Chain, when this Observation is a probe. |
| `idempotency_key` | ascii[1..200] | Deterministic dedupe key (§7.2). |
| `correlation_id` | uuid | Cross-context tracing (Logical Event Envelope). |

Subject & question:

| Field | Type | Notes |
|---|---|---|
| `subject_entity_key` | ascii[1..200] | Canonical key of the subject business (the client). |
| `question_id` | ascii[1..120] | Stable ID from the question bank. |
| `question_class` | enum | `A_recommendation`, `B_problem_first`, `C_attribute_niche`, `D_comparison`, `E_validation`, `F_criteria`, `G_price`, `H_urgency`, `I_hire_or_not`, `control_wrong_service`, `control_wrong_area`, `control_fabricated`, `control_closed`, `control_similar_name`, `control_misspelling` (QUESTION_BANK archetypes + controls battery). |
| `question_text_rendered` | text | The exact prompt issued, fill-ins resolved. |
| `wording_variant` | ascii[1..40] | Which phrasing of the question (`w1`..`wk`). |
| `probe_role` | enum | `primary`, `followup_forced_choice`, `followup_contact_details`, `followup_source_elicitation`, `followup_avoid` (see §9). |
| `probe_ordinal` | uint8 | Position in the follow-up chain; `0` for primary. |

Condition (controlled factors — mirror §10):

| Field | Type | Notes |
|---|---|---|
| `assistant_id` | ascii[1..80] | Product identity, e.g. `chatgpt`, `gemini`, `grok`, `claude`. |
| `knowledge_mode` | enum | `search_on`, `search_off`, `unknown` (two-arm; §8). |
| `conversation_mode` | enum | `fresh`, `follow_up`. |
| `location_form` | enum | `suburb`, `city`, `near_me`, `none`. |
| `location_stated_in_prompt` | nullable ascii[1..120] | The place named in-prompt; required non-null when `location_form=near_me`. |
| `grade` | enum | `screening`, `instrument`. |
| `sample_index` | uint16 | 0-based sample number within the cell. |

Capture & provenance:

| Field | Type | Notes |
|---|---|---|
| `product_surface` | enum | `web`, `mobile_app`, `api`, `unknown`. |
| `model_label_shown` | nullable ascii[1..200] | Verbatim UI model string, if displayed. |
| `model_version_resolved` | nullable ascii[1..120] | Best-effort normalized version; null when the provider hides it. |
| `search_toggle_observed` | enum | `on`, `off`, `absent`, `unknown` (what the UI exposed). |
| `session_id` | uuid | Unique per session; enforces isolation (§7.3). |
| `session_fresh` | bool | True = fresh conversation, clean/logged-out where practical. |
| `observer_ip_city` | nullable ascii[1..120] | Observer geography once per session; never a claim of assistant personalization state. |
| `observed_at_utc` | instant | When the response was produced. |
| `captured_at_utc` | instant | When the observer captured it (≥ observed_at_utc). |
| `locale` | const | `en-AU`. |
| `time_zone` | const | `UTC`. |
| `reproducibility_class` | enum | `stochastic_surface`, `deterministic_surface`. |
| `raw_transcript_ref` | ascii[1..200] | Digest-referenced restricted transcript (raw output stays private; §16). |
| `screenshot_ref` | nullable ascii[1..200] | Evidence screenshot handle. |

Coded result:

| Field | Type | Notes |
|---|---|---|
| `subject_mentioned` | bool | Whether the subject was named. |
| `subject_position` | nullable uint16 | 1-based rank if listed; null if unranked-mention or absent. |
| `mention_form` | enum | `ranked_list_item`, `prose_unranked`, `absent`. |
| `subject_cited` | bool | Whether a source was attributed to the subject. |
| `entities_named` | array<NamedEntity> | Every business named, ranked; see §5.3. |
| `facts_asserted` | array<AssertedFact> | Field-level claims about the subject; see §5.3. |
| `caveats_present` | bool | Abstention / hedging / uncertainty language present. |
| `abstained` | bool | The assistant declined to name anyone. |
| `elicited_sources` | array<ElicitedSourceReference> | Source-elicitation output, `self_reported` (§11). |
| `finding_flags` | array<enum> | Zero or more research-sense Findings (§12): `absence`, `entity_conflation`, `temporal_hallucination`, `geographic_boundary_breach`, `authority_spoofing`, `anchoring_fragility`. |
| `defective` | bool | Run-failure quarantine flag (§12.2). |
| `defective_reasons` | array<enum> | Quarantine reason codes (§12.2); non-empty iff `defective=true`. |
| `coder_id` | ascii[1..80] | Human or coding-service identity. |
| `coding_method` | enum | `human`, `assisted`, `automated`. |
| `lifecycle_state` | enum | Observation state machine (§7.4). |
| `sealed_at_utc` | nullable instant | Seal time; set only in `sealed`/`sealed_defective`. |

### 5.3 Embedded types

`NamedEntity`:

| Field | Type | Notes |
|---|---|---|
| `entity_key` | ascii[1..200] | Canonical key; resolves competitors and the subject. |
| `raw_name` | text | Verbatim name as the assistant wrote it. |
| `position` | nullable uint16 | 1-based rank in the assistant's list; null if prose-unranked. |
| `mention_form` | enum | `ranked_list_item`, `prose_unranked`. |
| `is_subject` | bool | True for the client entity. |

`AssertedFact`:

| Field | Type | Notes |
|---|---|---|
| `field` | enum | `name`, `phone`, `address`, `url`, `services`, `hours`, `registration`, `service_area`. |
| `asserted_value` | text | What the assistant stated. |
| `reality_value` | nullable text | The Reality Card value. |
| `verdict` | enum | `match`, `mismatch`, `unverifiable`, `not_in_reality_card`. |
| `contradicted_reality_field` | nullable ascii[1..120] | Reality Card field this contradicts (Findings linkage). |

`ElicitedSourceReference` (candidate `esrc_id`):

| Field | Type | Notes |
|---|---|---|
| `esrc_id` | uuid | Candidate namespace. |
| `cited_url` | text | The URL the assistant claimed. |
| `attributed_claim` | text | What the assistant said the source supports. |
| `self_reported` | const true | Always flagged; assistant introspection is confabulation-prone. |
| `verification_state` | enum | `unverified`, `url_exists`, `url_absent`, `supports_claim`, `contradicts_claim`, `misattributed`. |
| `verified_by` | nullable ascii[1..80] | Independent verifier; never the eliciting assistant. |

---

## 6. Measurement grades as first-class configuration

The two grades from synthesis §6 and delivery-guide Part 1 are modelled as a **first-class, versioned `MeasurementGrade` config object**, not as prose. A Run references exactly one grade config; the config determines what may be computed and what may be claimed.

### 6.1 `MeasurementGrade` config schema

| Field | Type | `screening` | `instrument` |
|---|---|---|---|
| `grade` | enum | `screening` | `instrument` |
| `min_samples_per_cell` | uint16 | `3` | `10` (directional) / `20`–`30` (client-facing rate) |
| `session_fresh_required` | bool | `true` | `true` |
| `min_days_spread` | uint8 | `2` | `2` |
| `rate_reporting_enabled` | bool | **`false`** (counts only) | `true` |
| `interval_method` | enum | `none` | `wilson_score` (proportions); `bootstrap` (PWS/ERF — see Open Questions) |
| `confidence_level` | decimal | n/a | `0.95` (z = 1.96) |
| `comparison_claims_allowed` | bool | **`false`** | `true` (with N and interval) |
| `trend_claims_allowed` | bool | **`false`** | `true` (only across matched Waves, no version_break) |
| `two_arm_required` | bool | `false` (opportunistic) | `true` where the surface exposes the toggle |
| `controls_required` | array<enum> | `[wrong_service, wrong_area, similar_name]` | `[fabricated, wrong_category, wrong_geography, closed_business, similar_name, misspelling]` |
| `order_permutation_required` | bool | `false` | `true` for anchoring experiments |
| `n_display_required` | const true | `true` | `true` |

### 6.2 Grade claim rules (the language law, machine-enforced)

Adopted verbatim as policy from synthesis §6 and delivery-guide Part 1:

- **Screening = a smoke test only.** It may report **counts of observations** ("appeared in 2 of 12 runs", "address wrong in 4 runs", "conflated with X twice") and variance flags. It **MUST NOT** emit a percentage presented as a stable rate, any competitor comparison, any trend claim, or any composite score. The system MUST reject a screening-grade artifact that contains a rate token.
- **Instrument** may report **rates with a Wilson interval and N always displayed**, before/after deltas (matched Waves only), and search-on vs search-off attribution — but never causality without controls, never permanence, never model internals.
- **All grades:** counts not scores · every number carries its N · "observed on [date], [assistant]" on every claim · variance reported as a Finding, not hidden · abstain where evidence is thin. Composite scores are banned at every grade.

---

## 7. Run orchestration, idempotency, and session isolation

### 7.1 Run structure

A **Measurement Run** (`mrun_id`) executes exactly one **Condition Cell × grade** and produces `min_samples_per_cell` Observations plus any follow-up chains. Runs belong to a Wave; Waves belong to a Campaign. A Campaign targets one Project.

Orchestration pseudocode (provider-neutral; manual or, post-gate, automated):

```
plan_run(cell, grade_config, wave):
  run = MeasurementRun.create(cell, grade_config, wave, state=planned)
  for i in 0 .. grade_config.min_samples_per_cell - 1:
     key = idempotency_key(cell, grade, wave, assistant, sample_index=i)
     if Observation.exists(key): continue          # idempotent no-op
     obs = Observation.reserve(run, sample_index=i, key)   # state=pending
  run.transition(scheduled)
  return run

execute_observation(obs):
  session = open_fresh_session(obs.assistant_id, obs.knowledge_mode)  # §7.3
  response = issue(session, obs.question_text_rendered)               # capture raw
  obs.raw_transcript_ref = store_restricted(response)                 # §16
  obs.observed_at_utc = response.time; obs.captured_at_utc = now()
  obs.transition(elicited)
  if obs.probe_role == 'primary' and chain_enabled(obs):
     run_followup_chain(session, obs)                                 # §9
  close_session(session)                                              # isolation boundary
```

### 7.2 Idempotency

- `idempotency_key = base64( sha256( canonical_json({ measurement_set_id, campaign_id, wave_id, cell_id, assistant_id, grade, sample_index, session_nonce }) ) )` where `session_nonce` is fixed at reservation time.
- **OBS-INV-IDEMP:** dispatching a key that already resolves to an Observation returns the existing `obs_id` and performs no side effect (no duplicate query, no duplicate Evidence). This mirrors the WF-005/WF-006 idempotent-retry discipline (identical reserved slot/attempt identity retried idempotently, `SCORE_EVIDENCE_MODEL.md`).
- A **retry** of a failed execution reuses the same `obs_id` and key; it never mints a second sample. Re-sampling the same cell for more statistical power uses a **new** `sample_index`, hence a new key — an explicit act, never an accident.

### 7.3 Session isolation (non-negotiable)

- Each Observation runs in a **fresh session** (`session_fresh=true`), logged-out or clean-profile where practical (delivery-guide Part 5.1). A `session_id` is unique to one session.
- **One session hosts at most one primary question plus its follow-up chain.** A primary question and its probes share a session (that is the point — anchoring is intra-session); two different primary questions never share a session.
- **The two arms never share a session.** A `search_on` Observation and a `search_off` Observation are always separate sessions (mixing them contaminates parametric-vs-retrieval attribution).
- The observer records only what is observable (surface, model label, toggle state) and **never claims personalization was absent** — only that none was configured (Part 5.1).
- **OBS-INV-ISO:** no two Observations with different `question_id` (primary role) may share a `session_id`; no Observation may share a `session_id` with an Observation of a different `knowledge_mode`.

### 7.4 State machines

**Measurement Run** lifecycle:

```
planned ─▶ scheduled ─▶ executing ─▶ captured ─▶ coded ─▶ sealed
   │           │            │
   └───────────┴────────────┴────────▶ aborted   (recoverable-exhausted / withdrawn)
                             └────────▶ quarantined_partial  (≥1 sealed_defective observation)
```

- `sealed` requires every non-defective Observation `sealed` and every defective one `sealed_defective`; the Run's defective observations are reported as their own class, never averaged (§12.2).
- `aborted` if the surface is unavailable or the operator withdraws before useful output; produces no partial rate.

**Observation** lifecycle:

```
pending ─▶ elicited ─▶ transcribed ─▶ coded ─▶ sealed
                                        │
                                        └─▶ sealed_defective   (defective=true)
pending ─▶ void   (never executed; e.g. cell cancelled)
```

- Seal is **append-only and immutable**; a coding correction requires a superseding Observation with lineage to the original, never an in-place edit (Genesis immutability).
- `sealed`/`sealed_defective` are terminal.

---

## 8. The two-arm search-on / search-off design

### 8.1 Rationale

Mention behaviour decomposes into two layers (`002 ANSWER_PATH_AND_AUTHORITY_SPEC.md` §1; AUTHORITY_ROADMAP governing insight):

- **Retrieval authority** — what the assistant finds and resolves when it searches. Clock: **weeks**; re-measurable inside the 90-day window; fixes may be reported as observed deltas.
- **Parametric authority** — what the model already associates from training. Clock: **training generations (months–years)**; unbounded; **never promised, never given a timeline in customer copy.**

### 8.2 Mechanics

- Where the surface exposes a web-search toggle, the engine runs the subject's money questions **both ways** (`search_on`, `search_off`), each arm in its own fresh session, and labels the arm on every Observation (`knowledge_mode`, `search_toggle_observed`).
- Where the surface exposes **no** toggle, `knowledge_mode=unknown` and the arm cannot be attributed; two-arm claims are suppressed for that assistant.
- **Layer attribution** (reported, not asserted as causal):
  - Present with `search_on`, absent with `search_off` → **retrieval-driven presence** (fast layer; fixable in weeks). Recommendation path: retrieval-layer interventions.
  - Present in both arms → **parametric contribution present** (slow layer). Copy MUST NOT promise change here.
  - Absent in both arms → gap spans both layers; retrieval fixes attempted first, corpus layer prescribed only for eligible customer tiers and never with a clock (AUTHORITY_ROADMAP tier mapping).
- **OBS-INV-ARM-CLOCK:** any artifact derived from `search_off` divergence MUST carry the two-clock honesty line and MUST NOT attach a timeline to parametric change.

---

## 9. The follow-up chain and source-elicitation probe

### 9.1 Structure

One follow-up chain per session, anchored to a `primary` Observation whose answer named ≥1 entity. Ordered probes (delivery-guide Part 5.6; QUESTION_BANK follow-ups):

1. `followup_forced_choice` — *"If you could only call one today, which?"* Feeds the **Anchoring** Finding and the **Follow-up Anchoring Index** (§13.5). Mandatory.
2. `followup_contact_details` — *"Give me their contact details."* The **wrong-facts harvest**: every returned field becomes an `AssertedFact` scored against the Reality Card (feeds **Entity Resolution Fidelity**, §13.3). Mandatory when a subject or competitor was named.
3. `followup_source_elicitation` — *"Which pages did you draw those names from?"* Produces `ElicitedSourceReference`s. **These are leads, not findings** (`002 ANSWER_PATH` §1.2; the 28 Jul Clutch confabulation catch: a real URL, wrong contents). Every elicited source is stored `self_reported` and **MUST be independently verified before it may appear in any report, score input, or intervention plan** (§11).
4. `followup_avoid` — *"Any I should avoid?"* Captured with care; reported factually, **never republished as disparagement** (Part 11 guardrail 2).

### 9.2 Chain rules

- Probes inherit the session's `assistant_id`, `knowledge_mode`, and `session_id`; `conversation_mode=follow_up`; `probe_ordinal` increments.
- **Follow-up Observations are anchoring-dependent and are NOT independent samples.** They are excluded from primary-answer Mention-Rate/PWS denominators. Their statistical treatment for the Anchoring Index interval is an Open Question.
- **OBS-INV-SELFREPORT:** an `ElicitedSourceReference` with `verification_state ∈ {unverified, url_exists}` MUST NOT be promoted to a Citation, a score input, or an intervention lead.

---

## 10. Geography / location control and the factorial condition matrix

### 10.1 Location control

- `location_form ∈ {suburb, city, near_me, none}`. A `near_me` variant is issued **only with the location stated in-prompt** (`location_stated_in_prompt` non-null) — the engine never relies on implicit IP geolocation to define the target place (delivery-guide Part 5.2).
- `observer_ip_city` is recorded once per session **for context only**; it is never asserted as the assistant's resolved location.
- Wrong-area control (`control_wrong_area`) probes the subject's exact service in a suburb they do **not** serve, calibrating pattern-matching vs knowing (QUESTION_BANK controls; feeds **Geographic Boundary Breach**).

### 10.2 The factorial condition matrix

A **Condition Cell** (`cell_id`) is a unique tuple of controlled factors. N samples per cell per grade.

| Factor | Domain | Control status |
|---|---|---|
| `knowledge_mode` | `search_on` / `search_off` / `unknown` | Controlled where the surface allows; else observed. |
| `conversation_mode` | `fresh` / `follow_up` | Controlled (fresh baseline is the only clean baseline). |
| `location_form` | `suburb` / `city` / `near_me` / `none` | Controlled (in-prompt). |
| `wording_variant` | `w1..wk` per question | Controlled. |
| `question_class` | A–I + controls | Controlled by design. |
| `assistant_id` | `chatgpt`/`gemini`/`grok`/`claude`/… | Controlled (selection); a factor, not random. |
| `model_version_resolved` | provider-dependent | **Captured, not controllable**; defines Wave comparability (§4). |

Cell budgeting: the delivery-guide recipe selects ~22 questions per assessment (8 A across 3 phrasings × 3 location granularities, 5 B, 3 E incl. one misspelling, 2 C, 2 F/G, 2 controls). Instrument-grade drill-downs run the client's **5 highest-value questions** at N=10–30 per arm.

### 10.3 Controls battery

| Control | Probe | Detects |
|---|---|---|
| `control_wrong_service` | a service the client does not offer | over-eager naming (calibration) |
| `control_wrong_area` | client's service in an unserved suburb | Geographic Boundary Breach / pattern-matching |
| `control_similar_name` | *"Is {confusable} the same as {client}?"* | Entity Conflation (direct test) |
| `control_fabricated` | a non-existent business | fabrication propensity (instrument) |
| `control_closed_business` | a business known closed | Temporal Hallucination (instrument) |
| `control_misspelling` | client name misspelled | resolution robustness (instrument) |

---

## 11. Citation handling and the self-reported gate

- Assistant-elicited sources are **self-reports about sourcing and are partly confabulated** (AUTHORITY_ROADMAP caveat; ANSWER_PATH §1.2). They enter the system as `ElicitedSourceReference` with `self_reported=true`.
- Independent verification is a two-part test: **(a) the URL exists**, and **(b) the page content actually supports the attributed claim.** The canonical failure is real-URL-wrong-contents (Clutch, 28 Jul 2026).
- Only a reference reaching `supports_claim` may become a verified lead feeding a report, an intervention plan, or (via the Evidence/Citation contract, OD-007) a Citation.
- The share of the assistant's citations that pass both parts is the **Citation Accuracy Rate** (§13.4).
- Machine statements about **third parties** are never republished as fact; only the *behaviour* ("named [competitor] in 11 of 12 runs") is reportable (Part 11 guardrails 1–2).

---

## 12. Findings taxonomy and run-failure quarantine

### 12.1 Finding classes (research sense — NOT the canonical Issue)

Adopted from synthesis §5 / delivery-guide Part 7. Each `finding_flag` is detected by the named metric and carries: the verbatim machine text, run reference, date, assistant, and the Reality Card field it contradicts.

| Finding class (`finding_flags`) | Definition | Detected by |
|---|---|---|
| `absence` | Not mentioned for a served intent | Mention Rate vs intent set |
| `entity_conflation` | Facts merged with a confusable; firm/practitioner confusion | Entity Resolution Fidelity vs Reality Card; similar-name control |
| `temporal_hallucination` | Stale facts presented as current | Fact checks vs ground truth; closed-business control |
| `geographic_boundary_breach` | Recommended where not served / absent where served | Wrong-area control |
| `authority_spoofing` | Marketing treated as regulatory/authoritative validation | Citation Accuracy checks |
| `anchoring_fragility` | Present but collapses/inverts under follow-up | Follow-up Anchoring Index |

Vocabulary boundary (unresolved, per governance): these are **Findings**, the measurement engine's output. They are **not** `Issue` objects. Downstream, the Evaluation Context may create an `Issue` from a Finding pattern; that mapping and the naming collision are an ADR decision, recorded here, not resolved.

### 12.2 Run-failure quarantine (`defective_observation`)

A captured Observation is **still evidence** but is quarantined (`defective=true`, `lifecycle_state=sealed_defective`) and reported as its **own class — never silently averaged** — when it contains any of (synthesis §6 run-failure criteria; delivery-guide Part 5.7):

| `defective_reasons` code | Trigger |
|---|---|
| `fabricated_business` | The assistant invented a business. |
| `unresolved_entity_collision` | Unresolvable entity collision on the subject. |
| `unsupported_registration_claim` | A registration/licence claim with no support. |
| `incorrect_contact_detail_as_fact` | A wrong contact detail stated as fact. |
| `citation_does_not_support_claim` | A cited source that does not support its statement. |
| `false_personal_experience_claim` | A false claim of personal experience. |

- **OBS-INV-QUARANTINE:** a `sealed_defective` Observation MUST NOT enter any rate denominator; it is surfaced as a **Defective Observation** finding class with its verbatim text and reason.

---

## 13. The five metrics

For entity *e* over the set of **primary, non-defective** Observations in scope (N of them; follow-up Observations excluded except where a metric is explicitly chain-based). Screening reports **raw counts**; instrument reports **rates with a 95% Wilson interval and N**.

### 13.1 Mention Rate (MR)

- Let `m` = count of in-scope Observations in which *e* is named. `N` = in-scope Observation count.
- **Screening:** report `m of N` (e.g. "2 of 12"). No rate.
- **Instrument:** `MR = m / N`, reported with Wilson 95% CI and N.

### 13.2 Position-Weighted Score (PWS) — a declared reporting convention

- **VIDET reporting weights**, declared in every artifact that shows PWS as *"our reporting convention, explicitly not model internals"*:

  | Placement | Weight |
  |---|---|
  | 1st | 1.00 |
  | 2nd | 0.70 |
  | 3rd | 0.50 |
  | 4th | 0.35 |
  | 5th or later (ranked) | 0.20 |
  | named but unranked (prose) | 0.10 |
  | absent | 0.00 |

- Formula: for each in-scope Observation *i*, `w_i = weight(placement of e in i)`; `PWS(e) = (1 / N) · Σ_i w_i`, range [0, 1].
- PWS is a **per-entity presence-quality index**, not a composite across metrics and not a model-internal score. Combining PWS with MR/ERF/CAR/FAI into a single blended number is the banned composite score and is forbidden.
- **Screening:** report the placement tally (e.g. "1st once, 3rd once, absent 10 times"), not the PWS number as a rate.
- **Instrument:** report PWS with a **bootstrap** interval (PWS is not a Bernoulli proportion; Wilson does not apply — see Open Questions).

### 13.3 Entity Resolution Fidelity (ERF)

- Field set: `{name, phone, address, url, services}` (extendable to `hours`, `registration`, `service_area` where asserted).
- Per Observation asserting ≥1 field: `correct_fields / asserted_fields`, judged against the Reality Card.
- **Aggregation (default, flagged as an Open Question):** pool all asserted field instances across in-scope Observations as one Bernoulli series → `ERF = Σ correct_fields / Σ asserted_fields`. Observations asserting zero fields are excluded from the denominator; report the excluded count.
- **Screening:** raw `correct / asserted` counts.
- **Instrument:** pooled field-level ERF with a Wilson 95% CI on field accuracy and N (of field instances and of Observations).

### 13.4 Citation Accuracy Rate (CAR)

- Of the sources the assistant cites about the subject, the share that **exist AND support the attributed claim** (both parts of §11's test), pooled across in-scope Observations.
- Every source is `self_reported` until independently verified; unverified sources are `indeterminate`, not counted as accurate.
- **Screening:** raw `supporting / total_cited` counts.
- **Instrument:** CAR with a Wilson 95% CI and N.

### 13.5 Follow-up Anchoring Index (FAI)

- Computed for the **category** (all entities), not per entity, to contextualise any "the AI picked us/them!" excitement.
- Over the `followup_forced_choice` Observations: `FAI = wins_by_first_listed / forced_choice_followups`, where a "win" = the forced-choice selection equals the entity first-listed in the immediately preceding primary answer of the same session.
- **Screening:** raw `wins / chains` counts.
- **Instrument:** FAI with a 95% interval, plus (instrument only) an **order-permutation experiment** that permutes the presented order to separate primacy from merit.

### 13.6 Wilson score interval (the canonical interval for proportions)

For a proportion `p̂ = x / n` at confidence level with `z` (z = 1.96 for 95%):

```
denom  = 1 + z^2 / n
centre = (p̂ + z^2 / (2n)) / denom
half   = ( z * sqrt( p̂*(1 - p̂)/n + z^2/(4 n^2) ) ) / denom
CI     = [ centre - half , centre + half ]   clamped to [0, 1]
```

- Applies to MR, ERF (field-level), CAR, FAI. **Not** to PWS (use bootstrap).
- N is always displayed alongside the interval. Confidence bands, where shown, follow OD-003 (`low` `0.0000–0.6000`, `medium`, `high`), never a fabricated composite.

---

## 14. The OD-010 gate

- **OD-010 is the Measurement Set** — signed, immutable, owner-approved (VOLUME_III_ARTIFACT_MAP layer 3). It is ratified as **OD-010 Option 1** (the seven-check baseline catalogue, thresholds, impact mappings, and measurement contracts).
- **No automated external measurement may run without an approved, active Measurement Set.** Per `INTEGRATION_CONTRACTS.md`, search providers are **dormant `external_measurement_adapter` candidates pending an approved Measurement Set** — *no collection, no network call*. This engine's automated mode inherits that gate.
- Every automated Observation that becomes **Measurement Evidence** MUST carry `measurement_set_id`, `measurement_set_version`, `measurement_policy_version` (existing constant `external-measurement-interim-v1`), `collector_adapter_id`, and `collector_adapter_version`, and MUST respect the 24-hour `fresh_until_utc = observed_at_utc + 24h` freshness rule (`SCORE_EVIDENCE_MODEL.md`).
- The engine's richer AI-answer observation is proposed as a payload **superset** of the ratified `external-observation-v1` `ai_answer_presence` body (`presence_status`, `citation_status`, entity keys). Graduating that superset requires a **controlled Volume I change and an OD-010 Measurement Set revision** — it MUST NOT silently redefine the frozen v1 contract.
- **Present authorized mode:** manual, human-scale observation only (Part 11 guardrail 6). Automated activation is additionally gated on the **ToS / durability ruling in counsel's brief** (Open Question). The manual run-log is the lawful path today and is the exact projection the platform later ingests.
- **OBS-INV-OD010:** an automated Observation without a reference to an active OD-010 Measurement Set MUST NOT be created and MUST NOT produce Measurement Evidence.

---

## 15. JSON schemas

### 15.1 Observation record (`observation-contract-v1`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://videt.ai/schemas/observation-contract-v1.json",
  "title": "Observation",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "obs_id", "schema_version", "organization_id", "project_id",
    "campaign_id", "wave_id", "mrun_id", "cell_id", "idempotency_key",
    "correlation_id", "subject_entity_key", "question_id", "question_class",
    "question_text_rendered", "wording_variant", "probe_role", "probe_ordinal",
    "assistant_id", "knowledge_mode", "conversation_mode", "location_form",
    "grade", "sample_index", "product_surface", "search_toggle_observed",
    "session_id", "session_fresh", "observed_at_utc", "captured_at_utc",
    "locale", "time_zone", "reproducibility_class", "raw_transcript_ref",
    "subject_mentioned", "mention_form", "subject_cited", "entities_named",
    "facts_asserted", "caveats_present", "abstained", "elicited_sources",
    "finding_flags", "defective", "defective_reasons", "coder_id",
    "coding_method", "lifecycle_state"
  ],
  "properties": {
    "obs_id": { "type": "string", "format": "uuid" },
    "schema_version": { "const": "observation-contract-v1" },
    "organization_id": { "type": "string", "format": "uuid" },
    "project_id": { "type": "string", "format": "uuid" },
    "campaign_id": { "type": "string", "format": "uuid" },
    "wave_id": { "type": "string", "format": "uuid" },
    "mrun_id": { "type": "string", "format": "uuid" },
    "cell_id": { "type": "string", "format": "uuid" },
    "chain_id": { "type": ["string", "null"], "format": "uuid" },
    "idempotency_key": { "type": "string", "minLength": 1, "maxLength": 200 },
    "correlation_id": { "type": "string", "format": "uuid" },
    "subject_entity_key": { "type": "string", "minLength": 1, "maxLength": 200 },
    "question_id": { "type": "string", "minLength": 1, "maxLength": 120 },
    "question_class": { "enum": [
      "A_recommendation","B_problem_first","C_attribute_niche","D_comparison",
      "E_validation","F_criteria","G_price","H_urgency","I_hire_or_not",
      "control_wrong_service","control_wrong_area","control_fabricated",
      "control_closed","control_similar_name","control_misspelling" ] },
    "question_text_rendered": { "type": "string" },
    "wording_variant": { "type": "string", "maxLength": 40 },
    "probe_role": { "enum": [
      "primary","followup_forced_choice","followup_contact_details",
      "followup_source_elicitation","followup_avoid" ] },
    "probe_ordinal": { "type": "integer", "minimum": 0, "maximum": 255 },
    "assistant_id": { "type": "string", "minLength": 1, "maxLength": 80 },
    "knowledge_mode": { "enum": ["search_on","search_off","unknown"] },
    "conversation_mode": { "enum": ["fresh","follow_up"] },
    "location_form": { "enum": ["suburb","city","near_me","none"] },
    "location_stated_in_prompt": { "type": ["string","null"], "maxLength": 120 },
    "grade": { "enum": ["screening","instrument"] },
    "sample_index": { "type": "integer", "minimum": 0 },
    "product_surface": { "enum": ["web","mobile_app","api","unknown"] },
    "model_label_shown": { "type": ["string","null"], "maxLength": 200 },
    "model_version_resolved": { "type": ["string","null"], "maxLength": 120 },
    "search_toggle_observed": { "enum": ["on","off","absent","unknown"] },
    "session_id": { "type": "string", "format": "uuid" },
    "session_fresh": { "type": "boolean" },
    "observer_ip_city": { "type": ["string","null"], "maxLength": 120 },
    "observed_at_utc": { "type": "string", "format": "date-time" },
    "captured_at_utc": { "type": "string", "format": "date-time" },
    "locale": { "const": "en-AU" },
    "time_zone": { "const": "UTC" },
    "reproducibility_class": { "enum": ["stochastic_surface","deterministic_surface"] },
    "raw_transcript_ref": { "type": "string", "minLength": 1, "maxLength": 200 },
    "screenshot_ref": { "type": ["string","null"], "maxLength": 200 },
    "subject_mentioned": { "type": "boolean" },
    "subject_position": { "type": ["integer","null"], "minimum": 1 },
    "mention_form": { "enum": ["ranked_list_item","prose_unranked","absent"] },
    "subject_cited": { "type": "boolean" },
    "entities_named": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["entity_key","raw_name","mention_form","is_subject"],
        "properties": {
          "entity_key": { "type": "string", "maxLength": 200 },
          "raw_name": { "type": "string" },
          "position": { "type": ["integer","null"], "minimum": 1 },
          "mention_form": { "enum": ["ranked_list_item","prose_unranked"] },
          "is_subject": { "type": "boolean" }
        }
      }
    },
    "facts_asserted": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["field","asserted_value","verdict"],
        "properties": {
          "field": { "enum": ["name","phone","address","url","services","hours","registration","service_area"] },
          "asserted_value": { "type": "string" },
          "reality_value": { "type": ["string","null"] },
          "verdict": { "enum": ["match","mismatch","unverifiable","not_in_reality_card"] },
          "contradicted_reality_field": { "type": ["string","null"], "maxLength": 120 }
        }
      }
    },
    "caveats_present": { "type": "boolean" },
    "abstained": { "type": "boolean" },
    "elicited_sources": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["esrc_id","cited_url","attributed_claim","self_reported","verification_state"],
        "properties": {
          "esrc_id": { "type": "string", "format": "uuid" },
          "cited_url": { "type": "string" },
          "attributed_claim": { "type": "string" },
          "self_reported": { "const": true },
          "verification_state": { "enum": [
            "unverified","url_exists","url_absent",
            "supports_claim","contradicts_claim","misattributed" ] },
          "verified_by": { "type": ["string","null"], "maxLength": 80 }
        }
      }
    },
    "finding_flags": {
      "type": "array",
      "items": { "enum": [
        "absence","entity_conflation","temporal_hallucination",
        "geographic_boundary_breach","authority_spoofing","anchoring_fragility" ] },
      "uniqueItems": true
    },
    "defective": { "type": "boolean" },
    "defective_reasons": {
      "type": "array",
      "items": { "enum": [
        "fabricated_business","unresolved_entity_collision",
        "unsupported_registration_claim","incorrect_contact_detail_as_fact",
        "citation_does_not_support_claim","false_personal_experience_claim" ] },
      "uniqueItems": true
    },
    "coder_id": { "type": "string", "maxLength": 80 },
    "coding_method": { "enum": ["human","assisted","automated"] },
    "lifecycle_state": { "enum": [
      "pending","elicited","transcribed","coded","sealed","sealed_defective","void" ] },
    "sealed_at_utc": { "type": ["string","null"], "format": "date-time" }
  },
  "allOf": [
    { "if": { "properties": { "location_form": { "const": "near_me" } } },
      "then": { "properties": { "location_stated_in_prompt": { "type": "string" } },
                "required": ["location_stated_in_prompt"] } },
    { "if": { "properties": { "defective": { "const": true } } },
      "then": { "properties": { "defective_reasons": { "minItems": 1 } } } },
    { "if": { "properties": { "defective": { "const": false } } },
      "then": { "properties": { "defective_reasons": { "maxItems": 0 } } } },
    { "if": { "properties": { "mention_form": { "const": "ranked_list_item" } } },
      "then": { "properties": { "subject_position": { "type": "integer" } },
                "required": ["subject_position"] } }
  ]
}
```

### 15.2 Measurement Run (`measurement-run-v1`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://videt.ai/schemas/measurement-run-v1.json",
  "title": "MeasurementRun",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "mrun_id","schema_version","organization_id","project_id","campaign_id",
    "wave_id","cell_id","grade_config","assistant_id","planned_sample_count",
    "lifecycle_state","two_arm","measurement_set_ref","created_at_utc"
  ],
  "properties": {
    "mrun_id": { "type": "string", "format": "uuid" },
    "schema_version": { "const": "measurement-run-v1" },
    "organization_id": { "type": "string", "format": "uuid" },
    "project_id": { "type": "string", "format": "uuid" },
    "campaign_id": { "type": "string", "format": "uuid" },
    "wave_id": { "type": "string", "format": "uuid" },
    "cell_id": { "type": "string", "format": "uuid" },
    "grade_config": {
      "type": "object",
      "additionalProperties": false,
      "required": ["grade","min_samples_per_cell","rate_reporting_enabled",
        "interval_method","comparison_claims_allowed","trend_claims_allowed",
        "two_arm_required","controls_required","n_display_required"],
      "properties": {
        "grade": { "enum": ["screening","instrument"] },
        "min_samples_per_cell": { "type": "integer", "minimum": 3 },
        "session_fresh_required": { "const": true },
        "min_days_spread": { "type": "integer", "minimum": 0 },
        "rate_reporting_enabled": { "type": "boolean" },
        "interval_method": { "enum": ["none","wilson_score","bootstrap"] },
        "confidence_level": { "type": ["number","null"], "minimum": 0.5, "maximum": 0.999 },
        "comparison_claims_allowed": { "type": "boolean" },
        "trend_claims_allowed": { "type": "boolean" },
        "two_arm_required": { "type": "boolean" },
        "order_permutation_required": { "type": "boolean" },
        "controls_required": { "type": "array", "items": { "type": "string" } },
        "n_display_required": { "const": true }
      },
      "allOf": [
        { "if": { "properties": { "grade": { "const": "screening" } } },
          "then": { "properties": {
            "rate_reporting_enabled": { "const": false },
            "comparison_claims_allowed": { "const": false },
            "trend_claims_allowed": { "const": false },
            "interval_method": { "const": "none" } } } }
      ]
    },
    "assistant_id": { "type": "string", "maxLength": 80 },
    "knowledge_mode": { "enum": ["search_on","search_off","unknown"] },
    "planned_sample_count": { "type": "integer", "minimum": 3 },
    "two_arm": { "type": "boolean" },
    "measurement_set_ref": {
      "type": ["object","null"],
      "additionalProperties": false,
      "properties": {
        "measurement_set_id": { "type": "string", "format": "uuid" },
        "measurement_set_version": { "type": "string", "maxLength": 120 },
        "measurement_policy_version": { "const": "external-measurement-interim-v1" }
      },
      "description": "Null only for manual-era runs; MUST be non-null for any automated run (OBS-INV-OD010)."
    },
    "lifecycle_state": { "enum": [
      "planned","scheduled","executing","captured","coded","sealed",
      "aborted","quarantined_partial" ] },
    "created_at_utc": { "type": "string", "format": "date-time" },
    "sealed_at_utc": { "type": ["string","null"], "format": "date-time" },
    "observation_ids": { "type": "array", "items": { "type": "string", "format": "uuid" } }
  }
}
```

### 15.3 Metrics report (`metrics-report-v1`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://videt.ai/schemas/metrics-report-v1.json",
  "title": "MetricsReport",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "mrep_id","schema_version","organization_id","project_id","campaign_id",
    "wave_id","scope","grade","assistant_id","knowledge_mode","N",
    "defective_excluded_count","metrics","position_weight_table","computed_at_utc",
    "deterministic_input_hash"
  ],
  "properties": {
    "mrep_id": { "type": "string", "format": "uuid" },
    "schema_version": { "const": "metrics-report-v1" },
    "organization_id": { "type": "string", "format": "uuid" },
    "project_id": { "type": "string", "format": "uuid" },
    "campaign_id": { "type": "string", "format": "uuid" },
    "wave_id": { "type": "string", "format": "uuid" },
    "scope": {
      "type": "object",
      "additionalProperties": false,
      "required": ["kind","entity_key"],
      "properties": {
        "kind": { "enum": ["entity","category"] },
        "entity_key": { "type": ["string","null"], "maxLength": 200 }
      }
    },
    "grade": { "enum": ["screening","instrument"] },
    "assistant_id": { "type": "string", "maxLength": 80 },
    "knowledge_mode": { "enum": ["search_on","search_off","unknown","combined"] },
    "N": { "type": "integer", "minimum": 0, "description": "In-scope primary, non-defective Observations." },
    "defective_excluded_count": { "type": "integer", "minimum": 0 },
    "version_break": { "type": "boolean", "default": false },
    "metrics": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "mention_rate": { "$ref": "#/$defs/proportionMetric" },
        "position_weighted_score": {
          "type": "object",
          "additionalProperties": false,
          "required": ["placement_tally"],
          "properties": {
            "placement_tally": {
              "type": "object",
              "additionalProperties": false,
              "properties": {
                "rank_1": { "type": "integer", "minimum": 0 },
                "rank_2": { "type": "integer", "minimum": 0 },
                "rank_3": { "type": "integer", "minimum": 0 },
                "rank_4": { "type": "integer", "minimum": 0 },
                "rank_5_plus": { "type": "integer", "minimum": 0 },
                "prose_unranked": { "type": "integer", "minimum": 0 },
                "absent": { "type": "integer", "minimum": 0 }
              }
            },
            "pws_value": { "type": ["number","null"], "minimum": 0, "maximum": 1 },
            "interval_method": { "enum": ["none","bootstrap"] },
            "ci_low": { "type": ["number","null"], "minimum": 0, "maximum": 1 },
            "ci_high": { "type": ["number","null"], "minimum": 0, "maximum": 1 }
          },
          "description": "pws_value/ci_* null at screening grade (placement_tally only)."
        },
        "entity_resolution_fidelity": {
          "allOf": [ { "$ref": "#/$defs/proportionMetric" } ],
          "description": "numerator=correct fields, denominator=asserted fields; observations_asserting_zero excluded."
        },
        "citation_accuracy_rate": { "$ref": "#/$defs/proportionMetric" },
        "follow_up_anchoring_index": {
          "allOf": [ { "$ref": "#/$defs/proportionMetric" } ],
          "description": "category scope only; numerator=first-listed wins, denominator=forced-choice chains."
        }
      }
    },
    "position_weight_table": {
      "type": "object",
      "additionalProperties": false,
      "required": ["rank_1","rank_2","rank_3","rank_4","rank_5_plus","prose_unranked","absent","disclaimer"],
      "properties": {
        "rank_1": { "const": 1.0 },
        "rank_2": { "const": 0.7 },
        "rank_3": { "const": 0.5 },
        "rank_4": { "const": 0.35 },
        "rank_5_plus": { "const": 0.2 },
        "prose_unranked": { "const": 0.1 },
        "absent": { "const": 0.0 },
        "disclaimer": { "const": "VIDET reporting convention, not model internals." }
      }
    },
    "claim_guard": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "rates_permitted": { "type": "boolean" },
        "comparisons_permitted": { "type": "boolean" },
        "trends_permitted": { "type": "boolean" },
        "two_clock_line_required": { "const": true }
      }
    },
    "computed_at_utc": { "type": "string", "format": "date-time" },
    "deterministic_input_hash": { "type": "string", "pattern": "^[a-f0-9]{64}$" }
  },
  "$defs": {
    "proportionMetric": {
      "type": "object",
      "additionalProperties": false,
      "required": ["numerator","denominator"],
      "properties": {
        "numerator": { "type": "integer", "minimum": 0 },
        "denominator": { "type": "integer", "minimum": 0 },
        "rate": { "type": ["number","null"], "minimum": 0, "maximum": 1 },
        "interval_method": { "enum": ["none","wilson_score"] },
        "confidence_level": { "type": ["number","null"] },
        "ci_low": { "type": ["number","null"], "minimum": 0, "maximum": 1 },
        "ci_high": { "type": ["number","null"], "minimum": 0, "maximum": 1 }
      },
      "allOf": [
        { "description": "Screening grade: rate and ci_* MUST be null; numerator/denominator carry the count." }
      ]
    }
  }
}
```

---

## 16. Raw output handling, legal, and privacy

- **Raw captured transcripts stay private.** They are digest-referenced (`raw_transcript_ref`) exactly as the `verification_observation` payload holds no plaintext (`SCORE_EVIDENCE_MODEL.md`); reports contain only verified, attributed observations (Part 11 guardrail 1). Proposed classification: `restricted`; retention aligned to `015 DATA_LIFECYCLE.md` at filing (Open Question).
- **Third-party statements** are never republished as fact; only measured behaviour and the subject's own verified public record appear (guardrails 2–3).
- **Regulated verticals:** every derived artifact carries *"This is a measurement of AI assistant behaviour, not professional, financial, legal or medical advice."*
- **No guarantees** of mention, position, or timing — ever (guardrail 5).
- **Manual, human-scale only** until the ToS analysis and the OD-010 decision clear automation (guardrail 6; §14).

---

## 17. Invariants (test-validated, DM-REQ-004/012 discipline)

- **OBS-INV-IDEMP** — a repeated `idempotency_key` yields the existing Observation and no side effect.
- **OBS-INV-ISO** — session isolation: no cross-question primary sharing a session; no cross-arm sharing a session.
- **OBS-INV-FRESH** — every primary baseline Observation has `session_fresh=true`; a follow-up shares its primary's session and only its primary's.
- **OBS-INV-QUARANTINE** — a `sealed_defective` Observation never enters any rate denominator and is reported as the Defective Observation class.
- **OBS-INV-SELFREPORT** — an unverified `ElicitedSourceReference` never becomes a Citation, score input, or intervention lead.
- **OBS-INV-SCREEN-NO-RATE** — a screening-grade Metrics Report has null `rate`/`ci_*` on every metric and no comparison/trend claim; a rate token in a screening artifact is a validation failure.
- **OBS-INV-N-DISPLAY** — every reported number carries its N.
- **OBS-INV-NO-COMPOSITE** — no artifact blends the five metrics into a single score; PWS is per-entity presence quality, explicitly labelled a reporting convention.
- **OBS-INV-ARM-CLOCK** — any `search_off`-derived claim carries the two-clock line and attaches no timeline to parametric change.
- **OBS-INV-VERSION-BREAK** — a Wave with `version_break=true` cannot be the "after" side of a before/after delta.
- **OBS-INV-OD010** — no automated Observation or Measurement Evidence exists without an active OD-010 Measurement Set reference.
- **OBS-INV-SEAL-IMMUT** — a sealed Observation is immutable; corrections supersede with lineage.
- **OBS-INV-DETERMINISM** — identical sealed input + identical Metrics Set version ⇒ byte-identical metric output (canonical-JSON deterministic hash).

---

## 18. Acceptance criteria

- **AC-OBS-01** — Given a planned cell for a screening Run (`min_samples_per_cell=3`), when it executes, then exactly 3 primary Observations exist, each with `session_fresh=true`, unique `session_id`, and `grade=screening`; a fourth dispatch on the same keys creates nothing (OBS-INV-IDEMP).
- **AC-OBS-02** — Given a `near_me` Observation, when `location_stated_in_prompt` is null, then creation is rejected by schema.
- **AC-OBS-03** — Given a screening Metrics Report, when it is assembled, then Mention Rate appears as "m of N", no metric has a non-null `rate`, and any embedded rate token fails validation (OBS-INV-SCREEN-NO-RATE).
- **AC-OBS-04** — Given an instrument Metrics Report for MR with x=7, n=20, then `rate=0.3500`, and `ci_low`/`ci_high` equal the Wilson 95% bounds with N=20 displayed.
- **AC-OBS-05** — Given an Observation naming the subject 1st once, 3rd once, and absent in 10 of 12 in-scope Observations, then the PWS placement tally is `{rank_1:1, rank_3:1, absent:10}` and (instrument only) `pws_value = (1.00 + 0.50)/12 = 0.1250`, always shown with the weight-table disclaimer.
- **AC-OBS-06** — Given a follow-up chain, when the forced-choice selection equals the primary's first-listed entity, then that chain counts as a first-listed win in the category FAI; the follow-up Observations do not enter the primary MR/PWS denominators.
- **AC-OBS-07** — Given an elicited source with `verification_state=url_exists` (URL resolves but content unchecked), then it MUST NOT appear in any report, score input, or intervention plan (OBS-INV-SELFREPORT).
- **AC-OBS-08** — Given an Observation containing a fabricated business, then `defective=true`, `defective_reasons=[fabricated_business]`, `lifecycle_state=sealed_defective`, and it is excluded from every rate denominator and surfaced as a Defective Observation (OBS-INV-QUARANTINE).
- **AC-OBS-09** — Given two Waves with different `model_version_resolved`, then the later Wave has `version_break=true` and no before/after delta may be computed across the break (OBS-INV-VERSION-BREAK).
- **AC-OBS-10** — Given a `search_off` divergence artifact, then the two-clock honesty line is present and no timeline is attached to parametric change (OBS-INV-ARM-CLOCK).
- **AC-OBS-11** — Given no active OD-010 Measurement Set, when an automated Run is requested, then no Observation and no Measurement Evidence is created (OBS-INV-OD010); a manual Run may proceed with `measurement_set_ref=null`.
- **AC-OBS-12** — Given the same sealed Observation set and Metrics Set version processed twice, then the two Metrics Reports have identical `deterministic_input_hash` and identical metric outputs (OBS-INV-DETERMINISM).
- **AC-OBS-13** — Given any Metrics Report, then no field blends the five metrics into a single composite score (OBS-INV-NO-COMPOSITE), and every reported number displays its N (OBS-INV-N-DISPLAY).
- **AC-OBS-14** — Given a `search_on` Observation and a `search_off` Observation of the same question, then they never share a `session_id` (OBS-INV-ISO).
- **AC-OBS-15** — Given a similar-name control, when the assistant conflates the subject with the confusable, then `finding_flags` includes `entity_conflation` and the contradicted Reality Card field is recorded.

---

## 19. Open questions (require ADR / owner ruling before build)

See the structured `open_questions` list accompanying this artifact. In summary: (1) the Finding-vs-Issue vocabulary collision; (2) the canonical ERF aggregation method and its interval; (3) the PWS interval method and whether the weight table is fixed or Measurement-Set-versioned; (4) whether the AI-answer observation payload graduates as an `external-observation-v1` superset via controlled Volume I change; (5) the cross-run agreement statistic and its reporting threshold; (6) model-version normalization and tool-routing observability limits; (7) the statistical treatment of chain-dependent follow-up data; (8) sample-size floor sign-off governance; (9) the ToS / durability / geography-control ruling gating automated activation; (10) whether a defective observation may ever contribute to any denominator (default: never); (11) retention/classification of raw measurement transcripts against `015 DATA_LIFECYCLE.md`.

---

*End of VOL3-INPUT — Module 1: Observation & Measurement Engine. Future/gated specification input; not ratified; enters canon only via the vision-set ADR.*
