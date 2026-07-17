# Volume II Testing And Implementation Sequencing

## Status And Authority

- Status: Volume II Implementation Architecture Pass 001
- Behavioural baseline: frozen Volume I at `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020). Historical `v1.3-volume-i-corrected` is retained as predecessor history and is not the baseline.
- Engineering-practice baseline: accepted Engineering Manual at `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022), normative for engineering practice only.
- Acceptance authority: [Volume I Acceptance And Test Mapping](../volume-i/ACCEPTANCE_AND_TEST_MAPPING.md)
- Architecture authority: [Rails Application Architecture](../../architecture/RAILS_APPLICATION_ARCHITECTURE.md)
- Deployment gate: [Deployment And Observability](DEPLOYMENT_OBSERVABILITY.md)

This document defines the executable verification architecture and TDD slice order. It does not weaken, reinterpret or add a Volume I acceptance criterion.

## Test Runtime

The test bundle pins RSpec Rails `8.0.4`, Factory Bot Rails `6.5.1`, Capybara `3.40.0`, Cuprite `0.17` and axe-core-capybara `4.12.0`. CI pins the Chromium major and image digest; a browser upgrade runs the complete system/accessibility suite. All dependency versions and checksums live in `Gemfile.lock` and the CI image manifest.

Tests use the production Ruby, Rails and PostgreSQL major versions. SQLite, an in-memory persistence substitute, faker-generated unspecified values, live provider calls and a shared developer database are prohibited. Time-zone is UTC, locale is `en-AU`, process hash seeds are fixed for reproducibility, and tests that need time receive a frozen injected clock.

## Suite Layout

| Directory | Responsibility | Database | Browser/network |
| --- | --- | --- | --- |
| `spec/domain/<context>` | pure values, invariants, policies, aggregate transitions | none | none |
| `spec/application/<context>` | command/query handler behavior through ports | only when repository contract is the subject | fake ports, no socket |
| `spec/persistence` | schema constraints, RLS, repositories, migrations and locking | real PostgreSQL 17 | none |
| `spec/contracts` | JSON Schema, provider adapter, event and generated OpenAPI compatibility | optional fixture DB | loopback stub only |
| `spec/jobs` | ScheduledAction/outbox/job lease/checkpoint behavior | real PostgreSQL/Redis | stub adapters |
| `spec/requests` | HTTP media/auth/CSRF/idempotency/status/redaction contracts | real stack | Rack test |
| `spec/system` | server HTML, Turbo, Stimulus, accessibility and responsive journeys | real stack | pinned headless Chromium |
| `spec/acceptance` | direct Volume I acceptance oracles by ID | real stack as required | controlled adapters/browser |
| `spec/architecture` | package, dependency, registry and prohibited-path assertions | schema/introspection only | none |
| `spec/performance` | query count/plan, allocation, latency and load budgets | production-shaped PostgreSQL | controlled local load |
| `spec/recovery` | crash/checkpoint, restore, Redis/S3/provider outage drills | isolated ephemeral stack | fault proxies/stubs |

An example belongs at the lowest layer that can prove the behavior. Acceptance coverage may compose lower-layer fixtures, but an acceptance ID must also have one directly tagged oracle that states the full observable assertion.

## RSpec Metadata Contract

Every normative example has:

- `acceptance_ids: []` containing canonical AC identifiers when it verifies Volume I;
- `test_types: []` using only `TYP-INT`, `TYP-E2E`, `TYP-SEC`, `TYP-OBS`, `TYP-DATA`, `TYP-AI`;
- `context_owner:` and `workflow_id:` where applicable;
- `risk:` as `critical`, `high`, `medium` or `low`; and
- `parallel_safe:` Boolean with an explicit reason when false.

RSpec configuration rejects an unknown ID/type, an acceptance-tagged pending/skipped example, duplicate global fixture identity, accidental focus and examples whose metadata conflicts with the canonical acceptance row. Test descriptions are not parsed as traceability authority.

After the suite, a formatter emits `tmp/acceptance-results.json` containing acceptance ID, example stable ID, file, seed, status, duration and test types. CI compares it with a generated read-only manifest parsed from Volume I. Every one of the 97 accepted criteria must have at least one passing direct oracle and every planned test type must be represented; extra/unknown IDs fail.

## Factory And Fixture Strategy

Factory Bot builds persistence records only. Domain objects use explicit builders in their context. Rules are:

- each factory creates the smallest schema-valid row in one declared lifecycle state;
- associations are explicit; creating one row never creates a hidden Organization/project graph;
- traits represent named contract states, not arbitrary field combinations;
- immutable/versioned records are never updated to create another state; builders create successor rows;
- sequences are deterministic per process and UUIDv7/time come from injected test generators;
- no callback sends a job, provider request, event or outbox entry;
- `build_stubbed` is prohibited for domain/repository assertions because it masks database behavior; and
- lint creates every factory under RLS and verifies teardown.

Large stable policy, Check, parser, prompt and provider artifacts are byte fixtures under `spec/fixtures/contracts/<artifact>/<version>/`. Each has canonical bytes, expected SHA-256, schema, signature fixture and provenance README. A fixture change under an existing immutable version fails checksum validation.

Golden behavioral corpora are separate from row factories. They include URL/crawl, robots/sitemap, parser, Check, score, recommendation, safety/Citation, Mailgun mapping and event-envelope cases. Each case has a stable case ID and expected canonical result bytes.

## Database Isolation

Ordinary unit/request examples run in a database transaction with `SET LOCAL` RLS context and roll back. Examples covering multiple connections, locks, jobs, isolation, LISTEN/wake behavior, partitioning, concurrent indexes or browser servers opt out and truncate only the test schema tables in reverse dependency order between examples. Sequence reset is irrelevant because IDs are UUIDv7.

Each parallel CI worker receives a separate PostgreSQL database, Redis namespace, S3 emulator bucket and encryption key. Tests never share Organization IDs across workers. Connection checkout assertions prove all `app.*` settings are empty before use.

Schema tests inspect `pg_catalog`, not only Rails metadata. They prove every declared FK, `NOT NULL`, check, unique/partial index, partition, privilege, RLS policy, FORCE RLS flag, composite tenant key and immutable-table grant. The runtime test role never owns a table or has `BYPASSRLS`.

## Contract Tests

### Commands, queries and events

Canonical JSON Schema files are generated from the application registries and then tested against hand-authored golden examples. Generation is one-way; changing generated output requires changing this architecture registry, not accepting drift.

Contract tests prove:

- exact required/nullable/optional fields and unknown-member behavior;
- canonical JSON, Unicode, decimal, timestamp and UUID encoding;
- command request hashing and altered-payload conflicts;
- all logical error-to-HTTP mappings;
- event major/minor compatibility and dead-letter behavior;
- pagination cursor signature/filter/order binding;
- current reauthorization/redaction on replay/ETag; and
- absence of dashboard/history narrative members.

The pre-Organization/platform-wide event contract is expected to remain an explicit failing/blocked architecture fixture, not a guessed schema, until Volume I resolves `organization_id`.

The Issue-fingerprint same-hash/different-preimage fixture remains an explicit blocked architecture fixture under `UPSTREAM-V1-ISSUE-COLLISION-013`: it proves no second Issue, `IssueFingerprintCollision`, Issue Set or dependent score/recommendation/history publication can be selected by implementation choice. The distinct Check Result key-collision fixture continues to prove its accepted nonmerge, event and Evaluation-failure behavior and is not gated.

### External providers

Provider specs use WebMock with all external network disabled. Adapters receive golden request/response byte fixtures captured from provider documentation or a dedicated noncustomer sandbox and manually stripped of secrets/customer data. VCR cassettes and production response recordings are prohibited.

Every active adapter contract covers authentication construction, timeout phase, status/body mapping, rate-limit parsing, transport retry disabled, idempotency/correlation fields, malformed/partial response, redaction and monitoring. A sandbox smoke test may run manually before release but is never the deterministic CI oracle.

Mailgun additionally uses a local fault server capable of accepting bytes and dropping the response, delayed/reordered/duplicate signed webhooks, same-event-ID conflicting bodies and reconciliation query outcomes. Tests count actual TCP submissions for an attempt so a post-`submission_started` redelivery cannot pass by merely deduplicating the product result.

Dormant Stripe, OpenAI, Anthropic, Google, OpenRouter and search adapter tests prove dependency resolution and every route/job/env path remain absent. Mux is unsupported and has no adapter contract.

## Security Test Matrix

`spec/security/permission_matrix_spec.rb` is generated as cases, not implementation, from all 71 actions and 53 permission rows in Volume I. For every actor/action it covers allow, deny and each conditional predicate. Separate pairwise and adversarial cases cover:

- Organization/Project/resource scope and cross-tenant opaque-ID substitution;
- explicit deny, default deny, policy/version conflict and last-admin races;
- suspended/revoked Account, Organization and Session boundaries;
- stale authorization epoch and 60-second cache convergence with authoritative recheck;
- Support Session resource/action/customer/emergency scope;
- Evidence Classification allow/omit/restricted-reference/whole-object denial;
- RLS under web, worker, readonly and attempted owner-role paths;
- CSRF, session fixation/rotation, open redirect, cookie and security headers;
- SSRF, DNS rebinding, XML entity and prompt-injection corpora;
- secret/log/metric/error/HTML/JSON leakage; and
- export reauthorization before the first byte.

Undefined read actions discovered in Volume I are not filled with a generated allow case. Their screen/route specs remain blocked and prove the route is absent until the product contract names the permission.

## Concurrency And Idempotency

Concurrency specs use independent database connections synchronized by barriers, not sleeps. Each registered serialization rule has two- and eight-worker permutations with reversed commit order. Required cases include bootstrap, invitation, Project/Source uniqueness, verification slots, policy activation, Crawl budgets/frontier, result fingerprints, Issue successors, score promotion, reassessment, entitlement, Delivery attempts, Export retrieval/revocation, outbox consumption and lifecycle deletion.

Each state-changing endpoint runs this common table:

1. initial request;
2. exact sequential replay;
3. concurrent exact replay;
4. same key/different canonical body;
5. same digest/different retained preimage test double;
6. stale state version;
7. crash immediately before commit;
8. crash immediately after commit/before response; and
9. current reauthorization/redaction loss before replay.

The oracle counts domain rows, transitions, events, usage, jobs and provider submissions, not just HTTP responses.

## Time And Scheduled Work

Product decisions use a fake injected clock whose value is also installed as the PostgreSQL transaction reference. Tests execute before, exactly at and after every deadline. Job arrival may be arbitrarily late; the handler compares database time and persisted due/deadline rather than assuming punctual delivery.

Scheduler tests advance by explicit instants, run the dispatcher and drain only named actions. They cover leadership loss, duplicate wakeups, Redis loss, outage coalescing, lease expiry, worker death and recovery. No assertion uses real sleeping except a separately quarantined infrastructure timing probe.

## System And Accessibility Tests

Capybara/Cuprite drives real Rails and Sidekiq test processes. Identity callbacks and providers are controlled local adapters. System tests cover only user-visible integration that request/domain tests cannot prove:

- managed-identity return and bootstrap/invitation/sign-in journeys;
- Turbo form success, validation, stale version, denial and Session expiry;
- asynchronous completion remaining unchanged until navigation or explicit refresh, plus absence of Action Cable/WebSocket/SSE/background polling;
- dashboard/history structured-only output;
- issue/adjudication, recommendation, notification and Export journeys where their read permission is defined;
- keyboard/focus/error-summary/live-region behavior;
- axe WCAG 2.2 AA scans on every screen state; and
- 320 CSS-pixel, 200% zoom, reduced-motion and data-table alternatives.

Screenshot comparison is diagnostic only, never the sole behavioral oracle. Unresolved Project/Source/Crawl/general-admin read screens are not given an inferred actor and cannot be marked complete.

## Performance Verification

Performance tests use deterministic production-shaped datasets at small, target and 2x target cardinalities. They enforce budgets from `SECURITY_PERFORMANCE.md` for SQL count, statement time, response time, memory and payload. `pg_stat_statements` and `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` artifacts are retained in CI for registered hot queries.

Each authorized collection test proves total ordering, cursor stability, index use, bounded rows/bytes and constant query count as associations grow. Strict loading raises on an undeclared association. Query budget regressions fail CI; a waiver requires an explicit architecture change, expiry and owner.

## Migration And Release Tests

CI runs three PostgreSQL paths:

1. build current schema from empty;
2. migrate a fixture at the prior production schema to current; and
3. restore a sanitized production-shaped logical fixture, migrate and validate.

It then runs constraint/RLS introspection, background compatibility and old-code/new-schema plus new-code/old-expanded-schema smoke tests for rolling releases. Concurrent indexes use their retry-safe release task in an ephemeral database. Destructive migrations require restore proof and legal-hold/retention fixtures.

## Architecture Tests

Packwerk and custom introspection fail when:

- a context imports another context's private constant;
- a controller/job touches Active Record or a provider directly;
- a context opens a transaction, enqueues, or calls another context;
- an aggregate child is saved outside its canonical root repository;
- an unregistered command/query/job/event/adapter/table appears;
- a mutable table lacks one owner/root/lock rank or RLS class;
- a provider SDK has automatic retry enabled;
- a dashboard/history code path references an AI adapter;
- a dormant/unsupported provider has a route, credential or environment key; or
- production code performs network access from a Check/parser process.

## CI Quality Gates

Pull requests run, in order:

1. dependency lock/checksum and secret scan;
2. Markdown/schema/OpenAPI/event registry validation;
3. RuboCop, ERB/JS lint and Zeitwerk eager load;
4. Packwerk and architecture specs;
5. domain/application/persistence/contract/request/job suites;
6. security/RLS/concurrency suites;
7. system/accessibility suite;
8. acceptance-manifest reconciliation;
9. migration compatibility; and
10. targeted performance budgets.

Main-branch release candidates additionally run full property/golden corpora, recovery/fault suite, production-shaped plans, dependency vulnerability scan, container/buildpack provenance verification and staging smoke. No flaky retry plugin is allowed. A failed example must fail the build; quarantining requires a named defect, owner and expiry and cannot cover critical/high or acceptance tests.

Coverage uses branch coverage as a diagnostic with minimum 95% for domain/application packages and 90% overall, but line coverage never substitutes for acceptance mapping, mutation tests or invariant cases. Mutation testing is mandatory for pure authorization, canonicalization, score, priority, scheduling and Check policies; the changed package must kill all non-equivalent mutations.

## TDD Implementation Sequence

Implementation proceeds in vertical slices, and a later slice does not begin until the preceding slice's gates pass:

1. platform primitives: canonical JSON, IDs/time, result/error, unit of work, RLS context, audit/outbox and idempotency;
2. managed identity, bootstrap, Session and access policy;
3. Project creation/activation and Source registration/verification/scope;
4. Crawl frontier, destination safety, ingestion and object lifecycle;
5. parsing, Evaluation input and retrieval index;
6. Check catalog/execution, Evidence, Issue and adjudication;
7. score, history structured data and reassessment;
8. deterministic recommendations and priority;
9. Notification/Mailgun and entitlement;
10. Export, security operations and data lifecycle; and
11. provider-neutral unavailable-adapter and policy-guard fixtures proving every dormant vendor package, client, route, Credential, job and outbound call is absent; no concrete dormant-provider implementation.

Every slice intersecting a blocker in the [Volume II Index](INDEX.md)—including undefined read permissions, Project pause/archive, standalone Session revocation, pretenant/platform event scope, reactivation proof, metered reads, comparison events, Credential-rotation token/material binding, reassessment-trigger event semantics, the Role-expiry-blocked event/notification record, Document quarantine/retirement or the Issue-fingerprint collision branch—remains gated. This is an upstream Volume I block, not permission to improvise.

## Release Exit Criteria

A slice is releasable only when every mapped acceptance oracle passes; no critical/high security or architecture defect remains; schema/rollback-forward and observability exist; fault recovery passes; performance budgets pass; and its runbook is exercised. Whole-product implementation readiness additionally requires controlled Volume I resolution of every blocker recorded in [Volume II Index](INDEX.md).
