# Volume II AI And Evaluation Architecture

## Status And Authority

- Status: Volume II Implementation Architecture Pass 001
- Behavioural baseline: frozen Volume I at `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020). Historical `v1.3-volume-i-corrected` is retained as predecessor history and is not the baseline.
- Engineering-practice baseline: accepted Engineering Manual at `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022), normative for engineering practice only.
- Evidence and Check authority: [Volume I Score and Evidence Model](../volume-i/SCORE_EVIDENCE_MODEL.md)
- Workflow authority: [WF-006 through WF-012](../volume-i/WORKFLOW_SPECIFICATIONS.md)
- Integration boundary: [Integration Contracts](INTEGRATION_CONTRACTS.md)

This document fixes how the Rails application executes deterministic Checks, scoring, recommendations, dormant AI adapters and a future approved Measurement Set. It does not approve an AI provider, external measurement provider, model, prompt, query set or dashboard/history narrative.

## Baseline Activation Matrix

| Facility | Baseline state | Executable behavior |
| --- | --- | --- |
| Seven Check Definitions | active | pure deterministic execution over frozen Evidence |
| External Measurement Set | inactive pending OD-010 | missing applicable Measurement Evidence yields the exact handled results and numeric score remains unavailable |
| Deterministic recommendation templates | active | generate from the frozen catalog without a model call |
| AI-assisted recommendation generation | inactive | fail before reservation/network with `F1-AI-422 / ai_provider_unapproved` |
| OpenAI adapter | dormant | no Integration, Credential, route, job, environment variable or network call |
| Anthropic adapter | dormant | same |
| OpenRouter adapter | dormant | same |
| Google/search measurement adapter | dormant | same until the signed Measurement Set names an eligible adapter |
| Dashboard/history AI narrative | prohibited | no schema field, presenter, placeholder, feature flag, job or provider call |

Dormant means the provider-neutral port, unavailable-adapter implementation and blocked-selection contract fixtures exist, but no concrete OpenAI, Anthropic, OpenRouter, Google or search-provider adapter/package/client code exists. Production and test dependency injection can resolve only the unavailable adapter; no secret can be provisioned and no logical command can reach a provider. Adding concrete vendor adapter code requires a Volume II revision plus the signed-release authority and controlled Volume I change applicable to that behavior.

## Evaluation Execution Topology

The `Evaluation` aggregate owns the applicability, Check Result, Issue, adjudication and scoring publication plan. Work is divided into durable stages:

1. `seal_input_snapshot`
2. `materialize_applicability`
3. `materialize_check_result_keys`
4. `execute_check_result`
5. `seal_issue_set`
6. `resolve_adjudication_gate`
7. `calculate_score`
8. `publish_initial_or_return_reassessment_stage`
9. `refresh_recommendations_and_priority`

Each stage begins only from its PostgreSQL ScheduledAction/Work Dispatch Binding. It loads immutable inputs by identity and digest, writes one checkpoint transaction, and commits the next stage row plus due-now ScheduledAction before the scheduler may dispatch it. Domain-event outbox consumption is reserved to Notification routing. No stage keeps an Active Record transaction open during CPU work or a provider call.

The stage registry in [Background Processing](BACKGROUND_PROCESSING.md) fixes queue, lease, timeout and recovery. A worker redelivery reuses the same stage/check/attempt identity. It never creates another Check Result, Evaluation or usage reservation.

## Check Runtime

Each Check Definition is loaded from an active signed `release_artifacts` row and materialized into an immutable Ruby value. The executor registry maps the seven exact definition/version pairs to seven pure classes below `Evaluation::Domain::Checks`. Dynamic constant names, tenant-authored Ruby, SQL, ERB, JavaScript, model calls and network access are prohibited.

The executor accepts one `CheckInputDTO` containing the complete canonical tuple and returns one `CheckSemanticResultDTO`. Both are exact JSON-Schema-backed values with unknown fields rejected. It receives no current time, random generator, repository, Rails configuration or ambient locale. The surrounding handler supplies the frozen locale/time-zone assumptions and attempt deadline.

Execution is isolated in a forked worker process with:

- read-only definition and input bytes;
- no database, Redis, S3, DNS or network descriptor;
- five elapsed seconds enforced by the parent;
- 256 MiB address-space ceiling and one CPU core scheduling share; and
- canonical JSON only on stdin/stdout.

The parent calculates the deterministic input hash before execution and output hash after schema validation. It commits only when the retained preimage, hashes and current Evaluation stage agree. A differing output for the same input follows `check_nondeterministic_output`; it is never selected by “last write wins”.

## Result Materialization And Concurrency

Before execution, one transaction inserts or locates every `check_result_keys` row in catalog/subject order. The row retains full preimage, SHA-256 and collision ordinal. Its unique constraint is `(evaluation_id, collision_ordinal, check_result_key_sha256)` plus a serialized preimage-head allocation. Digest equality is followed by byte equality; a collision never merges two subjects.

An execution attempt has immutable identity/input and a mutable write-once terminal checkpoint. The handler claims the key only when no terminal semantic result exists. Timeout/dependency retry uses the same Check Result identity and a new attempt number exactly once at the Volume I delay. Other reasons terminalize immediately. A late child process cannot update after the lease generation or deadline changed.

Check Result publication, Issue derivation and outbox append occur in one transaction. No Issue is created from error, missing Evidence, not-applicable or nonfailure output outside the definition contract.

Check Result key-hash collision retains the accepted nonmerge, restricted-event and Evaluation-failure contract. Issue fingerprint collision is separate: the frozen body says a same-hash/different-preimage tuple may create a second Issue while AC-SM-006 requires a distinct Issue. Under `UPSTREAM-V1-ISSUE-COLLISION-013`, that exact Issue branch cannot persist a second Issue, append `IssueFingerprintCollision`, seal the Issue Set, continue or fail the Evaluation, or publish dependent score, Recommendation or history state until controlled Volume I correction chooses MUST or MUST NOT create and fixes continuation/failure.

## Evaluation Harness

The repository must contain machine-readable fixtures for every active Check Definition:

- schema-valid minimum, maximum and representative inputs;
- every applicability and outcome branch;
- missing, stale, invalid, quarantined and collision inputs;
- exact boundary, ordering, decimal and Unicode cases;
- expected semantic output canonical JSON and SHA-256;
- timeout/dependency first attempt plus retry/exhaustion;
- mutation cases proving one semantic-field change alters the expected hash; and
- randomized property cases that repeat with a committed seed.

The harness executes each fixture 100 times in two clean processes and compares canonical output bytes. CI runs it under the deployment Ruby/Nokogiri/PostgreSQL stack; a runtime or dependency upgrade runs old and new stacks over the full corpus before release. An intentional output change requires new definition and catalog versions, never an in-place golden-file update under the old version.

## Score Calculation

`Evaluation::Domain::ScoreCalculator` uses integers, rationals and PostgreSQL-compatible fixed decimal values only. Binary floating point is prohibited. Ordered contributions are materialized before aggregation. Round-half-up occurs only at the exact Volume I display boundaries; intermediate values retain `numeric(18,10)` precision.

The calculator returns an immutable proposed ScoreSnapshot, Contributions and availability tuple. The publication transaction locks Evaluation, Issue-set serialization head and Project score-projection head, revalidates all Evidence decisions and versions, inserts immutable rows, and advances permitted pointers together. An unavailable result follows the exact initial/reassessment/recalculation branch; no repository method can promote a diagnostic snapshot.

A reconciliation test recalculates every fixture from source rows and proves the stored total, contribution sum, unavailable reasons and current pointers. Database constraints reject NaN, infinity, out-of-range values, incomplete membership and a current pointer to nonpromotable data.

## Deterministic Recommendation Path

The executable baseline always resolves `generation_mode=deterministic_template`. `Recommendations::Domain::TemplateRenderer` accepts only the named frozen template and explicit typed variables. It is not ERB, Liquid or Markdown execution; it performs a single pass over an allowlisted token map, rejects unknown/missing tokens and HTML-escapes presentation separately.

Template ID/version/hash, input Evidence/Issue versions, rendered structured fields and canonical content digest are stored with the Recommendation Artifact. The same fingerprint returns the same family/version and never renders another artifact. Publication validates schema, origin eligibility, effort, scope and all lineage in the transaction that replaces the current family pointer.

The deterministic fallback is not generated after a failed model call in the same command. In the baseline an AI-assisted request fails before reservation or call; a separately submitted deterministic command may succeed under its own idempotency identity.

## Dormant AI Provider Port

The only application port is:

```text
AiProvider.generate(request:, credential_handle:, deadline:) -> AiProviderResult
```

The request contains adapter policy ID/version/hash, provider/model IDs and immutable versions, prompt-envelope bytes and digest, response JSON Schema ID/hash, correlation token, maximum output bytes/tokens and deadline. It contains no Active Record object, raw secret, callback, tool definition or arbitrary URL. The result is one of `complete`, `definitive_nonacceptance`, `acceptance_unknown`, `authentication_failed`, `rate_limited`, `dependency_failed` or `timed_out`, with only allowlisted metadata.

An approved adapter artifact must fix all of the following before dependency resolution can instantiate an adapter:

- provider and adapter ID/major/code digest;
- exact API origin and path class;
- authentication secret type and rotation behavior;
- model ID/version or immutable provider snapshot identity;
- data-classification allowlist and regional/data-retention approval;
- prompt template and response schema hashes;
- input/output byte and token ceilings;
- connect, first-byte and total timeouts bounded by the 90-second generation deadline;
- provider rate/cost units and entitlement mapping;
- status/error normalization and whether nonacceptance is provable;
- retry policy, which is zero hidden SDK/transport retries for one AIResponse attempt;
- logging/redaction rules; and
- owner, legal/security approval and activation/rollback signatures.

OpenAI, Anthropic and OpenRouter implement this same port only after a matching artifact exists. Provider-specific messages, tool calling, browsing, prompt caching and fallback routing are disabled. OpenRouter cannot silently route among models. Provider failover is a new AIResponse attempt authorized by an active artifact, never an SDK fallback inside one attempt.

## Prompt Contract

When eventually active, `PromptEnvelopeV1` is canonical JSON with exactly:

- system policy identifier/version/hash;
- recommendation template/schema identity;
- untrusted Evidence section containing ordered ID/digest/classification/locator plus escaped text allowed by policy;
- origin Issue and immutable state version;
- locale;
- required output JSON Schema and ordered claim-manifest instructions; and
- correlation token with no tenant name or secret.

Evidence text is length-prefixed JSON data and never interpolated into system/developer instructions. The provider receives no credential, verification token, restricted Evidence, unrestricted URL, hidden prompt, earlier conversation or cross-tenant context. Prompt bytes and response bytes use private encrypted object storage; database rows retain references/digests. Logs retain only sizes, versions and hashes.

The provider must return one JSON object. Markdown fences, prose before/after JSON, duplicate keys, unknown members, invalid UTF-8, nonfinite numbers and over-limit output fail schema validation. No repair prompt or permissive parser runs under the same attempt.

## Safety, Grounding And Citation

The output scanner is deterministic and runs before Citation validation in the Volume I first-match order. Its policies are signed release artifacts with golden positive/negative corpora. A scanner cannot call a model.

Every generated factual claim must appear once in the ordered claim manifest. Citation construction accepts only one AIResponse and one Evidence record; locators are validated against the immutable payload schema and digest. The validation transaction decides every proposed Citation, verifies full claim coverage, rechecks Evidence validation/classification/tenant/origin lineage and then validates or rejects the AIResponse. It cannot partially bind content.

A validated response remains unpublished until the Recommendation Artifact publication transaction rechecks origin and expiry. At expiry equality, expiry wins. Rejected/expired attempts remain immutable and cannot be reopened.

## AI Cost And Latency Enforcement

No provider call starts before the `ai.generate` Entitlement Decision/reservation, AIResponse requested row, exact prompt object and external-effect `prepared` checkpoint commit. Immediately before writing to the network the attempt commits `submission_started`. The adapter disables automatic retries.

- generation deadline: exactly 90 elapsed seconds from AIResponse request;
- validation/durable-commit deadline: strictly before two elapsed minutes from request;
- publication expiry: exactly 24 hours after validation when not already bound;
- response byte/token and monetary ceilings: exact active adapter artifact values; absence rejects before call;
- cost record: provider/model, input/output units, normalized currency minor units, artifact price version and provider request ID when known;
- uncertainty: process/connection loss after submission starts cannot be treated as nonacceptance and cannot silently resubmit the attempt.

The entitlement usage commits only with the validated AIResponse durable point. Every terminal nonvalidated outcome releases once. Provider invoice data is operational reconciliation, not a BillingEntity/Invoice product entity.

## Measurement Set Execution

Before OD-010 approval, no measurement scheduler, query row, adapter Integration, Credential, provider environment variable or provider job exists. The Evaluation Input Snapshot records the absent set and exact missing kinds; the Check runtime executes the prescribed handled outcomes.

After a complete signed package is activated, `release_artifacts` stores the exact canonical bytes and signatures. A release transaction verifies digest, both required approvals, effective time and predecessor/rollback rules, then advances the active Measurement Set head. Evaluations pin the active set only when their input window opens; later activation or rollback cannot alter a sealed Evaluation.

External measurement runs outside the Rails Check executor. An eligible tenant-scoped adapter executes exact provider/query definitions, creates a canonical `external-observation-v1` payload, and submits it to the service endpoint before the fixed intake deadline. Rails verifies service JWT, set/adapter versions, full key/order/coverage, schema/digest/freshness and tuple uniqueness before appending Measurement Evidence. A provider call never occurs during Check execution.

## AI Narrative Prohibition

`ProjectOverviewDTO`, `HistoryComparisonDTO`, database projections, JSON schemas, HTML presenters, exports and notification templates have no dashboard/history narrative member. No call site may invoke `AiProvider` from CAP-018 or WF-012. Narrative absence does not enter loading, partial, degraded, unavailable or error state. Deterministic labels, frozen templates and the already-defined score/Issue/Evidence/Recommendation explanations remain permitted.

## Observability

Metrics use bounded labels for stage, definition, result, reason family, adapter/provider/model version and environment. Tenant, prompt, Evidence, URL, provider request IDs and content never become labels. Restricted logs/traces carry correlation and lineage IDs, versions/digests, attempt checkpoint, deadline, sizes/units, scanner result, Citation coverage and terminal reason.

Alerts cover Check nondeterminism, result-key collision, missing catalog, Evaluation stage deadline, score reconciliation mismatch, pointer invariant failure, AI call while provider unapproved, uncommitted/released entitlement drift, AI acceptance uncertainty and Citation coverage regression.

## Verification Gates

Implementation must prove:

1. all seven Check executors are pure, networkless and byte-deterministic;
2. exact timeout/retry/equality cases commit one semantic result;
3. every complete/partial/unavailable score fixture reconciles exactly;
4. deterministic templates work with no AI Integration or Credential;
5. an AI-assisted request under the baseline makes zero reservation/provider call and returns `ai_provider_unapproved`;
6. dormant provider adapters cannot be resolved from production configuration;
7. prompt injection, schema, safety and Citation corpora fail closed;
8. Measurement Set absence makes the exact external Results and numeric score unavailable;
9. a future submitted measurement cannot mutate a sealed Evaluation; and
10. dashboard/history paths contain no AI field, placeholder, feature flag, job or provider invocation.
