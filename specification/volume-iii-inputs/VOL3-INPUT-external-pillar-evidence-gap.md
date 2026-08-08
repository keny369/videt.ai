# VOL3-INPUT — The External Pillar Evidence Gap: what `CHK-SP-001` and `CHK-AS-001` actually require

Status: **Volume III specification input — scoping, not specification. NOT ratified. NOT canon.**
Prepared 8 August 2026. Volume I/II are frozen and the ratified Product Architecture Manual is the
single source of truth (ADR-001). This document enters canon only through the vision-set ADR front
door, and only where a controlled Volume I change plus an approved OD-010 Measurement Set expressly
enable it.

**This document defines what would have to exist. It invents nothing.** Every field, vocabulary and
bound below is quoted or derived from `specification/volume-i/SCORE_EVIDENCE_MODEL.md`
§ *Provider-Neutral Measurement Evidence Payload `external-observation-v1`*, § *Mandatory Check
Definitions*, § *Score Availability*, and `specification/volume-i/OWNER_DECISION_REGISTER.md` OD-010.
Where a value is not derivable from the repository it is marked **UNDEFINED — owner decision** rather
than supplied.

---

## 0. Why this document exists, and what it answers

A first customer-facing VIDET score is blocked, and it is worth being exact about by what.

`SCORE_EVIDENCE_MODEL.md :589` and `:681`: *"Every applicable pillar MUST have every expected
applicable entry ... represented by exactly one effectively valid score-capable Check Result with
execution status `passed` or `failed`. ... Any error/missing expected entry makes that pillar
`insufficient_data` and the overall score unavailable; no successful sibling Result masks it."*

So the score is available only when **every applicable pillar** reaches a terminal pass or fail. Four
pillars are fed by external measurement. Signing the staged AI Presence set closes exactly one of
them. This document scopes the two that nobody has costed — Search Presence and Authority Signals —
and settles the Local Presence question, so the owner can see whether a real score is a week away or a
quarter away before any further build.

**The short answer, stated up front and then evidenced below:**

| Pillar | Check | What it needs | Buildable today? |
|---|---|---|---|
| Technical Integrity | `CHK-TI-001` | Nothing external | Yes — and see §6, one residual |
| Content Quality | `CHK-CQ-001` | Nothing external | Yes, already decision-grade |
| Trust Signals | `CHK-TR-001` | Nothing external | Yes, already decision-grade |
| AI Presence | `CHK-AIP-001` | Signed Measurement Set + collector | Set staged; **owner signature outstanding** |
| **Search Presence** | **`CHK-SP-001`** | **Frozen query set + a SERP data source** | **No — §2** |
| **Authority Signals** | **`CHK-AS-001`** | **Frozen collection scope + a link/mention index + an attribution rule** | **No — §3** |
| Local Presence | `CHK-LP-001` | Nothing, when validly inapplicable | **Yes — §4, already inapplicable in production** |

---

## 1. The envelope both checks share

Every `external-observation-v1` payload — regardless of kind — contains exactly these, and a
collector that omits one produces `input_evidence_invalid`:

| Field | Shape | Constraint |
|---|---|---|
| `organization_id`, `project_id`, `evaluation_id` | UUID | MUST match the Evidence envelope; a mismatch is a **tenant-integrity failure that fails the whole Evaluation**, not a handled error |
| `measurement_kind` | enum | `search_index_presence` \| `ai_answer_presence` \| `authority_reference_set` \| `local_profile_consistency` |
| `measurement_policy_version` | string | exactly `external-measurement-interim-v1` |
| `collector_adapter_id` | string | nonblank, provider-neutral |
| `collector_adapter_version` | string | immutable |
| `measurement_set_version` | string | the signed set's version |
| `locale` | string | exactly `en-AU` |
| `time_zone` | string | exactly `UTC` |
| `observed_at_utc` | timestamp | MUST equal the Evidence envelope's `observed_at_utc` |
| `fresh_until_utc` | timestamp | **exactly** `observed_at_utc + 24h` |
| `coverage_status` | enum | `complete` \| `partial` \| `indeterminate` |
| *(kind-specific body)* | object | §2, §3 |

### 1.1 The three envelope constraints that decide the operating model

These are not schema trivia. Each one forces a delivery decision.

**(a) The 24-hour freshness window is a hard operational coupling.** A snapshot may consume the
Evidence only when `observed_at_utc <= snapshot_sealed_at_utc < fresh_until_utc`, and *"equality at
`fresh_until_utc` is stale."* So external collection and Evaluation sealing must happen inside one
24-hour window, every run, for every measurement kind. A nightly batch collector plus a
customer-triggered Evaluation the following afternoon produces `input_evidence_stale` and an
unavailable score. **This is the single most under-appreciated constraint in the contract**: it means
external measurement cannot be a cached asset refreshed weekly; it is a per-evaluation job.

**(b) `complete` and determinate, or nothing.** Both `CHK-SP-001` and `CHK-AS-001` require *"exactly
one fresh, complete, determinate"* Evidence record. *"Partial coverage, any indeterminate item, or a
key-set mismatch produces `input_evidence_indeterminate`"*, which is a handled error, which makes the
pillar insufficient, which makes the overall score unavailable. There is no partial credit. A
collector that resolves 49 of 50 query keys delivers exactly as much score as one that resolved zero.

**(c) Provider text may not be retained.** *"Provider text, prompts, unrestricted responses,
credentials, and opaque error strings are not retained in this payload."* The collector must reduce a
provider response to the typed body **outside** the Evidence record, and the reduction is not
reproducible from the retained bytes. Any dispute about a measurement is therefore adjudicated against
the collector's own restricted logs, not against Evidence — a retention and defensibility question the
Measurement Set's *"retention/access location for the exact approved canonical bytes"* clause (OD-010)
must answer.

---

## 2. `CHK-SP-001` Search Index Presence

### 2.1 Every field, exactly

Body schema `search_index_presence`, quoted from `SCORE_EVIDENCE_MODEL.md :315`:

| Field | Shape | Constraint |
|---|---|---|
| `expected_query_keys` | array of string | **nonempty**; sorted by UTF-8 bytes |
| `items` | array of object | **exactly one item per key, in that order** — a key-set mismatch invalidates |
| `items[].query_key` | string | the key |
| `items[].presence_status` | enum | `present` \| `absent` \| `indeterminate` |
| `items[].matching_urls` | array of string | sorted, unique, **canonical in-scope** URLs |

Two coupled invariants: *"`present` requires at least one URL and `absent` requires none."*

The Check then computes `presence_rate = present_count / expected_count` to four decimals, half up.
`1.0000` is `passed/search_presence_complete`; anything else is `failed/search_presence_gap`.

**Consequence worth stating plainly: a single `indeterminate` item makes the whole payload
indeterminate, so the pillar is insufficient and the score unavailable.** The collector has no way to
say "I could not resolve query 37" and still deliver a score.

### 2.2 What a collector would have to observe

For each query key in the frozen set, at collection time, in the `en-AU` locale: **whether any URL
inside the Project's Source Scope appears in the search index's results for that query's exact text**,
and which URLs those are, canonicalized by the same Source Scope canonicalizer the crawl uses.

Three things that observation is **not**:

- It is not rank or position. The contract asks only present/absent, which is a materially cheaper
  observation than a rank tracker.
- It is not the *site's* performance data. Google Search Console reports queries the site already
  appeared for, is delayed by roughly two days, is sampled, and requires the customer to grant access.
  It cannot answer "is any in-scope URL present for *this* arbitrary query" with a determinate
  present/absent, and its delay conflicts with §1.1(a). **GSC is not a viable adapter for this check**,
  though it is a plausible enrichment elsewhere.
- It is not a crawl. Nothing in the Project's own bytes answers it.

### 2.3 Is it legally and technically obtainable?

**Technically: yes. Legally: only through a licensed route, and that route is the cost.**

| Route | Obtainable | Note |
|---|---|---|
| Scraping Google/Bing SERPs directly | Technically yes | **Prohibited by both providers' terms of service.** Not a route this product may take: PRULE and the Constitution's honesty posture aside, a measurement product whose evidence base is a ToS breach is not sellable to the businesses it reports on, and is not defensible in a dispute. Rejected. |
| Google Programmable Search / Custom Search JSON API | Yes | Officially supported. Returns results from a *programmable* index configured to search the whole web; results are documented as not identical to google.com. Hard daily cap per project historically 10k queries. **Fidelity caveat must be disclosed to the customer.** |
| Bing / other first-party web search APIs | Yes | Officially supported and licensed. Provider availability and terms have moved materially in 2025–2026; **verify current availability before committing an adapter.** |
| Licensed SERP-data vendors (SerpApi, DataForSEO, Oxylabs, Zenserp and similar) | Yes | Sell exactly this observation, per query, with locale targeting. They carry the compliance question commercially. This is the realistic baseline route. |
| Common Crawl / open indexes | Partially | Free, but it is a crawl corpus, not a search index. It cannot answer "does this rank/appear for query Q". Not applicable to `CHK-SP-001`. |

**Verdict: obtainable, via a paid licensed data source, with a disclosed fidelity caveat.** No
free-and-compliant route exists.

### 2.4 What it would cost, per business per run

Cost is a **function of the frozen query-set size**, which is itself an owner decision (OD-010
requires *"the complete ordered search-query keys and exact query text"*). The unit economics:

```
cost_per_business_per_run(SP) = |expected_query_keys| x price_per_SERP_query
```

Indicative unit prices for licensed SERP APIs at small-to-mid volume have sat in the **USD
$0.001–$0.005 per query** band (roughly $1–$5 per 1,000), falling with committed volume.
**These are indicative and MUST be re-quoted at purchase; they are not a repository fact.**

| Frozen query set | Indicative cost per business per run |
|---|---|
| 10 queries | ~USD $0.01–$0.05 |
| 25 queries | ~USD $0.03–$0.13 |
| 50 queries | ~USD $0.05–$0.25 |
| 100 queries | ~USD $0.10–$0.50 |

**The finding: `CHK-SP-001` is cheap.** Even a 100-query set is cents per business per run. Search
Presence is not blocked by money. It is blocked by two things that cost nothing to buy and cannot be
skipped: **a frozen, signed query set**, and **an adapter that returns determinate results for every
key inside the 24-hour window**.

### 2.5 What is UNDEFINED and must come from the owner

1. **The query set itself.** Its size, its exact text, and the rule that generates it per business.
   A per-business set (e.g. "custom home builders Melbourne") is what makes the measurement
   meaningful and what makes the Measurement Set *per-project* rather than global — and the contract
   binds one `measurement_set_version` per Evidence record, so a per-business set implies a
   per-business signed package, with two signatures each. **That is a governance-throughput problem,
   not a technical one, and it is the real scaling question for OD-010.**
2. **What counts as "the index".** Which provider's index is authoritative, and what the customer is
   told when the programmable index and google.com disagree.
3. **The indeterminate policy.** What the collector does when a provider call fails: retry inside the
   window, or fail the run. The contract admits no partial payload.

---

## 3. `CHK-AS-001` Attributable Authority Reference

### 3.1 Every field, exactly

Body schema `authority_reference_set`, quoted from `SCORE_EVIDENCE_MODEL.md :317`:

| Field | Shape | Constraint |
|---|---|---|
| `references` | array of object | sorted by **canonical referrer, then reference type, then canonical target, then immutable observation key** |
| `references[].observation_key` | string | immutable |
| `references[].reference_type` | enum | `backlink` \| `brand_mention` |
| `references[].canonical_referrer` | string | canonical URL of the referring page |
| `references[].canonical_target` | string | canonical **in-scope** target URL |
| `references[].attribution_status` | enum | `attributable` \| `not_attributable` \| `indeterminate` |

*"Exact duplicate tuples are invalid. An empty complete list is a valid zero-signal observation."*

The Check passes when `attributable_count >= 1`, otherwise `failed/authority_reference_absent`.

### 3.2 The structural asymmetry with `CHK-SP-001` — and it matters commercially

**`CHK-AS-001` has no expected-key set.** There is no exhaustiveness obligation to satisfy: the
collector reports the references it observed, and `coverage_status: complete` is the collector's
assertion that it observed the scope it was told to observe. An empty list is explicitly valid and
yields a legitimate `failed/authority_reference_absent` with `medium` impact.

This makes Authority Signals **structurally cheaper to make decision-grade than Search Presence** —
one attributable reference is enough to pass, and zero is a valid, publishable fail.

It also makes it the easiest check in the catalogue to render dishonest. A collector that looks
nowhere, reports an empty list and marks it `complete` produces a schema-valid, decision-grade
`failed` result and a customer-visible Issue that the product cannot substantiate. **The integrity of
`CHK-AS-001` rests entirely on the honesty of one boolean the schema cannot check.** The Measurement
Set's *"authority-reference collection scope/selection rules"* (OD-010) is the only place that
integrity can be established, and it must be written as an auditable scope, not a description.

### 3.3 What a collector would have to observe

For a defined collection scope: pages elsewhere on the web that either link to an in-scope URL
(`backlink`) or mention the business without linking (`brand_mention`), each paired with its
**canonical referrer**, its **canonical in-scope target**, and an **attribution decision**.

Note what the schema forces that a raw backlink export does not give you:

- **Referrer/target pairing per reference.** Row-level, not aggregate. Domain-level "referring
  domains: 43" is not convertible into this body.
- **A canonical in-scope target.** The target must survive the Project's own Source Scope predicate.
- **A `brand_mention` with a canonical target.** A mention that does not link still needs a canonical
  in-scope target field. **UNDEFINED — owner decision:** which target a non-linking mention is
  attributed to (presumably the Source root, but the contract does not say, and inventing it here
  would be exactly the error this document exists to avoid).
- **`attribution_status`.** See §3.5.

### 3.4 Is it legally and technically obtainable?

**Backlinks: yes, commercially. Brand mentions: yes, less precisely. Attribution: not until it is
defined.**

| Route | Obtainable | Note |
|---|---|---|
| Commercial link indexes (Ahrefs, Majestic, Moz, Semrush) via API | Yes | Row-level referrer→target data with anchor context. Licensed, ToS-clean. The realistic route. |
| Common Crawl | Partially | Free and legally clean, but a periodic corpus: coverage is incomplete and staleness is measured in weeks. It cannot honestly support `coverage_status: complete`, and it conflicts with §1.1(a). |
| Google Search Console link report | Partially | Owner-consented, first-party, free — but sampled, aggregated, delayed, and it reports only what Google chose to show. Not row-level-complete. |
| News/mention APIs and social listening for `brand_mention` | Yes | Licensed. Coverage is inherently a subset of the web, which is a real limit on any `complete` claim. |
| Scraping third-party SEO dashboards | — | Prohibited. Rejected on the same grounds as §2.3. |

**Verdict: `backlink` references are obtainable today through a licensed API. `brand_mention` is
obtainable but its coverage claim is weaker. Neither can be delivered until `attributable` has a
definition.**

### 3.5 The blocking undefined: `attributable`

The Check is named *Attributable Authority Reference*. `attribution_status` is the field that decides
pass or fail. **The repository nowhere defines what makes a reference `attributable`.**

This is not an oversight to be patched here. OD-010's approval package explicitly reserves it:
*"authority-reference collection **scope/selection rules**"* is owner-supplied content. Candidate
readings — each defensible, each producing a different customer-visible result for the same web:

- the reference is **verifiably present** on a live page the collector fetched itself (attribution =
  observation quality);
- the referrer is **independent** of the subject (not owned, not paid, not a directory the business
  submitted itself) (attribution = editorial independence);
- the reference **names the business as an entity**, not merely a string match (attribution = entity
  resolution).

The third reading is the one that connects to the `VOL3-INPUT-reality-entity` entity ontology and to
the `self_reported → verified` gate in `VOL3-INPUT-truth-claims-evidence`. **Recommend the owner
decide `attributable` jointly with those two modules rather than inside a collector.**

### 3.6 What it would cost, per business per run

```
cost_per_business_per_run(AS) = per_domain_backlink_query + per_business_mention_query
```

Commercial link-index APIs price by subscription plus row/credit consumption rather than per query.
Indicative posture at small volume: **entry API access in the USD $100–$500 per month band**, with
row/credit allowances that comfortably cover **hundreds to low thousands of business-runs per month**.
**Indicative and MUST be re-quoted; not a repository fact.**

Amortised: **roughly USD $0.10–$1.00 per business per run at low volume, falling sharply with
volume** — dominated by the subscription floor, not by marginal use. Mention coverage, if bought
separately, adds a second subscription of similar order.

**The finding: `CHK-AS-001` costs more than `CHK-SP-001` and is still not expensive.** Its blocker is
the undefined `attributable` rule and the row-level pairing requirement, not price.

---

## 4. `CHK-LP-001` — can it be legitimately not-applicable, and what does that do?

**Yes, on both counts, and the second answer is the one that matters.**

### 4.1 It can be not-applicable, under exact conditions

`SCORE_EVIDENCE_MODEL.md :587`: *"`local_presence` may be `not_applicable` only when the Project
profile explicitly records `local_presence_applicable=false`, an OrganizationAdmin or MarketingOperator
records a nonblank reason, and the score-policy snapshot captures that decision version."*

`:273`: *"`CHK-LP-001`: exactly one Project entry; it is inapplicable only when the frozen Project
profile validly records `local_presence_applicable=false` and its nonblank reason."*

`:207`: `not_applicable` *"is valid only for `CHK-LP-001`"* — every other check treats an attempted
not-applicable as `check_catalog_integrity_failure`.

`WORKFLOW_SPECIFICATIONS.md :657` fixes the shape: when false, `local_presence_reason` is **20–500
trimmed Unicode scalar values** and `local_business_profile` is **null**.

So a business with no physical premises — an online-only trader, a fully remote service business — is
exactly the case the contract admits, provided an authorized human records a real reason. It is a
**declared, attributed, versioned decision**, not an inference. Nothing may derive it from the absence
of an address.

### 4.2 The path exists and works — but the Projects that were actually evaluated do not use it

`app/controllers/app/projects_controller.rb:132` creates a Project with
`"local_presence_applicable" => false` and a recorded reason, because *"the branch that asserts one
requires a complete local-business-profile body, which has no form yet."* Declaring false is
implemented, and the `projects_local_profile_shape` CHECK enforces its exact shape.

**Measured in the development database on 2026-08-08, it is not the path the real evaluations took:**

| Projects | Count |
|---|---|
| Total | 18 |
| Carrying any profile (`project_profile_schema_version` non-null) | **2** |
| Of those, declaring `local_presence_applicable = false` with a reason | 2 |
| Carrying **no** profile at all — every profile column NULL | **16** |

The all-NULL shape is legal (`projects_local_profile_shape` admits it as its first branch), and it is
**not** a valid false: `:273` requires the profile to *"validly record `local_presence_applicable=false`
and its nonblank reason."* So those Projects keep Local Presence **applicable**, with no Measurement
Evidence, which is exactly the result observed on the `xirconhomes.com.au` evaluation:
`CHK-LP-001 -> error / local_profiles_absent / input_evidence_missing`.

**The actionable finding: the pillar the product could legitimately switch off for free is switched
on by omission.** Recording the declared-false profile on the Project-creation path the real
evaluations use is small, contained work with no external dependency, and it removes one of the four
blocking pillars outright.

### 4.3 What it does to score availability

`:678`: *"An inapplicable pillar is `not_applicable`, has null score, weight `0/1`, and sole reason
`pillar_not_applicable`."* `:644`: *"Each applicable pillar has equal exact rational weight ...
`effective_weight_denominator = applicable_pillar_count`."* And `:589`'s coverage obligation binds
**applicable** pillars only.

Two precise consequences:

1. **It removes a blocker.** Local Presence stops being able to make the score unavailable. The
   contract's own worked example confirms it (`:698`): *"Local Presence is validly not applicable,
   every applicable pillar has valid coverage ... six applicable pillars have equal weight; overall is
   `98.3`."*
2. **It re-weights the score.** Six applicable pillars at `1/6` each instead of seven at `1/7`. Every
   remaining pillar becomes worth more.

**But it does not make the score available.** The applicable set still contains Search Presence, AI
Presence and Authority Signals, and each is `insufficient_data` until it has Evidence.

### 4.4 The honest count of what stands between here and a first score

With Local Presence validly inapplicable, and `CHK-TI-001` reaching a decision (§6):

| Applicable pillar | Status today | What closes it |
|---|---|---|
| Technical Integrity | reaches a decision after in-crawl link discovery, subject to §6 | §6's owner decision |
| Content Quality | **scored** | — |
| Trust Signals | **scored** | — |
| AI Presence | `insufficient_data` | **owner signature on the staged package**, then collect + submit |
| Search Presence | `insufficient_data` | frozen query set (§2.5) + licensed SERP adapter |
| Authority Signals | `insufficient_data` | `attributable` definition (§3.5) + link-index adapter |

**Three pillars, three blockers, and none of them is money.**

---

## 5. The conclusion the owner asked for: a week, or a quarter?

**Neither, and the reason is not what it looks like.**

The engineering is small. Two collector adapters against licensed APIs, both reducing a provider
response to a typed body, both submitted through the `external-observation-v1` intake that is already
built, validated and proved. Total marginal running cost is **cents to a dollar per business per
run**. If the query set, the intent set and the `attributable` rule were handed over signed tomorrow,
the adapters are days of work, not months.

**The critical path is governance throughput, not engineering, and it has a scaling problem nobody
has costed.**

OD-010 requires **two signatures, from Chief Product and Chief Architect, over the same package
SHA-256**, and the package must contain *"the complete ordered search-query keys and exact query
text"*. A search-query set that is meaningful is per-business ("custom home builders Melbourne" is not
a useful query for a business broker). Every Evidence record binds exactly one
`measurement_set_version`.

Read together, that says: **one signed, dual-signature Measurement Set per business** — which is
sustainable for the Founding 20 and is not sustainable at 200.

That is the actual finding, and it is worth more than the collector estimate:

> **The blocker to a first score is one signature. The blocker to the hundredth score is that the
> contract, read literally, requires a hand-signed measurement package per customer.**

### 5.1 The isolated owner decision this raises

**Can a Measurement Set carry a per-business *query-generation rule* rather than literal per-business
query text, so one signed package serves many businesses?**

- If **yes**: one signed package per vertical (home builders, business brokers, buyers' advocates),
  the query set is derived deterministically per Project from the signed rule plus the Project
  profile, and the signed bytes still fully determine the measurement. Scales. Requires a Volume I
  change, because `:315` freezes `expected_query_keys` as content and OD-010 requires *"exact query
  text"*.
- If **no**: per-business signed packages, and delivery capacity is bounded by the signing rate of two
  named humans. Then the honest sales position is a bounded cohort, not a self-serve product.

**This is the decision that sets pricing, delivery promise and what may be said on a sales call.** It
is isolable, it needs no further engineering to answer, and it should be answered before either
collector is built.

### 5.2 Recommended order

1. **Sign the staged AI Presence package.** One pillar, zero new engineering, and it exercises the
   whole signature → activation → submission → check path once, for real, at small blast radius.
2. **Answer §5.1.** Rule-derived or literal query sets.
3. **Define `attributable`** (§3.5), with the entity and truth-claims modules, not inside a collector.
4. **Then** build the two adapters. They are the cheap part and they are last for a reason: each one
   is a few days once its inputs are frozen, and worthless before.

---

## 6. Recorded, not repaired: the `CHK-TI-001` residual

In-crawl link discovery (S-07-007) is built, so the crawl now follows the links its pages name and
every in-scope **HTML** target reaches a terminal outcome. That converts most of the Technical
Integrity target set from `unobserved` to `reachable`/`absent`.

It does not finish the job, and the reason is a contract consequence rather than a defect in the
implementation:

- `:478` derives `CHK-TI-001`'s targets from **every** in-scope `link_edges` target, and `link_edges`
  covers `<link href>` as well as `<a href>`.
- `:452` records an **unsupported media type** as `policy_excluded` and places it *"outside the
  denominator"* of crawl coverage.
- `:294`'s target reason vocabulary is exactly `document_valid`, `content_absent`, `fetch_failed`,
  `limit_discarded`, `parse_omitted` — **there is no token for `policy_excluded`** — so such a target
  can only be `unobserved`, and `unobserved` is evaluated **before** pass or fail.

Measured on the real subject site: the `xirconhomes.com.au` home page alone names **79 distinct
in-scope targets, of which 37 are stylesheets, fonts, images or JSON endpoints**. Every one is fetched,
correctly classified `policy_excluded`, and correctly recorded `unobserved` — leaving
`relevant_coverage: partial` and `CHK-TI-001` at `error/internal_link_coverage_incomplete` no matter
how completely the crawl ran. This is the shape of every mainstream-CMS page, not an edge case.

**The isolated owner decision:** should a `policy_excluded` target be in `CHK-TI-001`'s target set at
all, given that `:452` already excludes it from the coverage denominator it is the analogue of? A
Volume I amendment either (a) excludes `policy_excluded` targets from the derived target set, or
(b) admits a sixth reason token for them that does not force `unobserved`. Both are one-paragraph
changes; neither may be made by an implementer, because both change what the product tells a customer.

Until it is decided, Technical Integrity remains `insufficient_data` and the table in §4.4 has **four**
open pillars, not three.

---

## 7. What this document deliberately does not do

- It does not choose a provider, a vendor, a query, an intent, a threshold or an adapter. OD-010
  reserves every one of those, and `PRODUCT_DEFINITION.md :70` states plainly that *"no implementation
  invents a query, prompt, provider, listing directory, threshold or adapter."*
- It does not map the existing `videt.api-probe-v0.1` transcripts onto `search_index_presence` or
  `authority_reference_set`. Those records carry `turns`, `urls_seen`, `arm`, `provider` and
  `model_reported`; they contain **no per-query search-index presence** and **no reference type,
  canonical referrer or attribution status**. A prior session refused that mapping and the refusal was
  correct: the fields are absent, not merely unformatted, and manufacturing them would put fabricated
  Evidence behind a customer-visible score.
- It does not amend Volume I. §2.5, §3.5, §5.1 and §6 are stated as owner decisions and left open.
