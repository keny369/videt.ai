# Volume II Implementation Architecture Index

## Status And Authority

- Status: Implementation Architecture Pass 001 complete for all unblocked behavior; baseline freeze blocked by frozen Volume I ambiguities below
- Volume I authority: annotated tag `v1.3-volume-i-corrected` at commit `5d725fa`
- Initial Volume II draft commit: `7213e9a`
- Foundation dependency: 1.0
- Last updated: 2026-07-16
- Owner: Chief Architect

Volume II translates accepted product behavior into one implementation architecture. It cannot create a product actor, action, field, state, transition, failure result, provider behavior or acceptance outcome that is absent from Volume I. When Volume I is ambiguous, the affected route, job or write path remains absent and is listed here.

## Canonical Read Order

1. [Rails Application Architecture](../../architecture/RAILS_APPLICATION_ARCHITECTURE.md)
2. [Application Layer](APPLICATION_LAYER.md)
3. [PostgreSQL Schema](../../schemas/POSTGRESQL_SCHEMA.md)
4. [Background Processing](BACKGROUND_PROCESSING.md)
5. [Search, Crawl And Retrieval](SEARCH_CRAWL_RETRIEVAL.md)
6. [AI And Evaluation](AI_EVALUATION.md)
7. [Integration Contracts](INTEGRATION_CONTRACTS.md)
8. [Physical API And Event Contracts](API_CONTRACTS.md)
9. [Frontend Architecture](FRONTEND_ARCHITECTURE.md)
10. [Security And Performance](SECURITY_PERFORMANCE.md)
11. [Deployment And Observability](DEPLOYMENT_OBSERVABILITY.md)
12. [Testing And Implementation Sequencing](TESTING_ARCHITECTURE.md)

These documents are one architecture. A narrower document owns its named physical detail; the Rails architecture owns package/dependency/transaction rules; the schema owns DDL shape; Volume I always owns observable behavior.

## Fixed Implementation Baseline

| Concern | Selected implementation | Explicitly excluded baseline alternatives |
| --- | --- | --- |
| Application | Rails 8.1.3 modular monolith on Ruby 3.4.10 | microservices, engines as service boundaries, generic service layer |
| Web | Puma 8.0.2, Propshaft, Importmap, Turbo 8/Stimulus | Node production runtime, SPA, GraphQL |
| Persistence | Heroku PostgreSQL 17 with forced RLS and composite tenant keys | SQLite, schema-per-tenant, application-only tenant filtering |
| Jobs/timers | Sidekiq 8.1.6 over two Heroku KVS Premium Valkey 8 services; PostgreSQL ScheduledAction/outbox authority | Solid Queue, Redis/Valkey timer authority, implicit Sidekiq retry |
| Redis | separate Sidekiq and disposable cache instances | shared queues/cache, product state in Redis |
| Objects | private versioned S3 with KMS; CloudFront only for public compiled assets | public/presigned customer objects, CDN Evidence/Export bytes |
| Retrieval | PostgreSQL `tsvector` internal projection | Elasticsearch/OpenSearch, vector database, customer arbitrary search |
| Email | platform-managed Mailgun with uncertainty/reconciliation contract | Postmark, exactly-once provider claim |
| AI/external measurement | dormant adapter ports; deterministic templates and no-set behavior active | provider selection, fallback routing, hidden model/provider call |
| Billing | provider-independent BillingEntity/Plan linkage; dormant Stripe boundary | invoices/payments in core, provider-created bootstrap state |
| Media | Mux unsupported | Integration/Credential/job/route/env support for Mux |
| Deployment | Heroku-26 web/worker/release topology | Kubernetes, serverless functions, in-process scheduler |
| Telemetry | OpenTelemetry to Datadog with canonical audit retained in PostgreSQL | logs as Audit Evidence, unbounded/high-cardinality metric labels |
| Tests | RSpec with real PostgreSQL, controlled adapters and Cuprite system tests | live-provider CI, SQLite, flaky automatic retry |

Changing one of these choices requires an implementation-architecture change and compatibility/migration proof. It does not permit a product-behavior change.

## Architecture Coverage

| Required area | Canonical owner | Coverage status |
| --- | --- | --- |
| Bounded contexts, aggregates, services, dependencies, transactions and locks | Rails Architecture; Application Layer | complete for unblocked operations |
| Tables, columns, keys, constraints, indexes, partitioning, deletion, locking and tenancy | PostgreSQL Schema | complete except final event/audit scope representation |
| Commands, queries, repositories, policies and presenters | Application Layer; API Contracts | command coverage complete; undefined read actions withheld |
| Job catalogue, queues, retry, idempotency, leases, scheduling and dead letters | Background Processing | complete for defined workflows |
| Mailgun, managed identity, DNS/HTTP verification, dormant billing/AI/measurement providers | Integration Contracts | complete |
| Crawl, parse, normalize, index, retrieval, deduplication and rate limits | Search, Crawl And Retrieval | complete |
| Check execution, score, recommendation, prompts, safety, Citation and evaluation harness | AI And Evaluation | complete |
| HTTP/JSON/event, auth, errors, pagination, versioning and Export serialization | API Contracts | complete for defined commands/reads; blocked routes absent |
| Hotwire screens, navigation, forms, async state and accessibility | Frontend Architecture | complete for authorized screens; undefined read screens absent |
| Session, CSRF, authorization, RLS, secrets, audit, caching and query budgets | Security And Performance | complete for defined actions |
| Heroku, Valkey, PostgreSQL, S3/CDN, CI/CD, metrics, logs, health, alerts and recovery | Deployment And Observability | complete |
| RSpec layers, factories, system/contract/acceptance tests and TDD slices | Testing Architecture | complete; blocked acceptance paths identified |

## Frozen Volume I Blockers

### `UPSTREAM-V1-EVENT-SCOPE-001`

The logical event envelope requires `organization_id` as the tenant identity. WF-001 also requires `BootstrapGrantIssued` before any Organization exists, WF-017 permits a platform-wide Incident, and WF-018 permits one Investigation spanning an approved Organization set. Volume I defines neither a permitted substitution nor a representation for those cases. Null, invented platform tenant, one selected tenant, per-Organization duplication and event omission are observably different. Volume II does not select one. Final event/audit DDL and those producers remain blocked; ordinary single-tenant event architecture is complete.

### `UPSTREAM-V1-SESSION-REVOCATION-002`

The Session state model names active-to-revoked through “explicit security revocation” but defines no standalone command, actor, permission, trigger, reason/error precedence, audit outcome or acceptance oracle. Defined Account/Organization lifecycle commands still revoke Sessions atomically. Volume II exposes no current-user sign-out/revocation or independent administrative Session mutation.

### `UPSTREAM-V1-PROJECT-LIFECYCLE-003`

The Project state model names Active-to-Paused, Paused-to-Active and Active/Paused-to-Archived plus three events. WF-002 and the permission baseline define only create and Draft-to-Active. Volume II exposes no pause/resume/archive route, control, job or incident action and does not assign those transitions to `project.activate`.

### `UPSTREAM-V1-READ-AUTHORIZATION-004`

Volume I defines exact read actions for Issue, score summary/detail, history, recommendation, Evidence metadata/payload/restricted, entitlement notices, security notices and one known Export retrieval. It does not define deterministic read authority for Organization home data, Project, Source, Crawl, ordinary Evaluation, Notification inbox, Account/policy administration, Export enumeration/detail, Billing summary, Integration status, Support Session collection, Incident/Investigation/Legal-Hold collection/detail or deletion-job collection. Role labels, mutation permissions, assignment/recipient/requester visibility and phrases such as “own Organization” are not equivalent read contracts. Volume II cannot choose which actors see those objects/fields, so the corresponding routes/screens/query handlers remain absent.

### `UPSTREAM-V1-LOW-COST-METERING-005`

WF-015 requires one Entitlement Decision and one deduplicated LowCostUsageRecord for every authorized `report.view`, `history.view`, `issue.read`, `recommendation.read` and `score.read` response, but does not map composite pages/Frames to one exhaustive operation or define the durable response/replay identity for safe reads and `304`. Different choices change usage and warnings for identical navigation. Every affected GET/Turbo response remains disabled.

### `UPSTREAM-V1-REACTIVATION-PROOF-006`

Account reactivation requires “valid identity” without defining whose identity, proof artifact, freshness, subject binding, disabled-provider behavior or failure precedence. A current administrator Session and a fresh proof bound to the suspended target produce different accepted Accounts. The Account-reactivation command remains unreachable.

### `UPSTREAM-V1-COMPARISON-EVENT-007`

WF-012 names `ComparisonGenerated` for a view-opening read but does not define its outcome set, repeated-view/Frame/prefetch trigger or idempotency identity. One event per HTTP read, one per selected pair and success-only generation are observably different. Historical comparison remains disabled.

### `UPSTREAM-V1-ORGANIZATION-REACTIVATION-PROOF-008`

Organization reactivation requires fresh managed identity plus MFA after every Session is revoked. None of the four accepted Identity Validation Receipt purposes admits reactivation, and existing-account sign-in rejects the inactive Organization. A new purpose, reused sign-in receipt, raw provider proof and revoked-Session command would be different product contracts. The Organization-reactivation command remains unreachable.

### `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`

Credential rotation requires a fresh rotation token and new material validation but defines neither the token issuer/lifetime/one-use binding nor the exact new-material reference carried or selected by it. Self-contained, opaque database and direct-reference designs authorize different material and retry behavior. Rotation begin/completion remains unreachable until Volume I fixes the token, material and replay contract.

### `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`

WF-011 does not define whether `ReassessmentTriggered` occurs for an admitted trigger that Entitlement then blocks. That branch creates a failed Reassessment Result with no Evaluation, while an executable run creates and starts an Evaluation. Emission for every admitted trigger, only after Evaluation creation, and different affected entity/profile choices produce different event histories. Schedule activation, due-slot execution and manual reassessment start remain unreachable until Volume I fixes the event occurrence, affected record, profile and replay identity.

### `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011`

WF-013 names `RoleExpiryBlocked` when expiry would remove the last effective Organization Administrator, but supplies no immutable decision, attempt or failure record for the mandatory event-profile fields and no retry/terminal schedule behavior. The Role contract also requires a mandatory security/OrganizationAdmin notification, while the accepted WF-014 trigger table defines no route predicate, selectors, permission, severity or context for this event. The last-admin block branch remains unreachable; ordinary nonblocking Role Assignment expiry remains defined.

### `UPSTREAM-V1-DOCUMENT-LIFECYCLE-012`

The foundation state model permits a Document in discovered, ingested, parsed or indexed state to become quarantined, and an indexed or quarantined Document to become retired, and names `DocumentQuarantined` and `DocumentRetired`. WF-005/WF-006 define only discovered-to-ingested-to-parsed-to-indexed execution and supply no quarantine/retirement trigger, actor or service authority, permission, command, reason precedence, idempotency, recovery or acceptance behavior. Automatic Evidence-driven quarantine, retention-driven retirement, an administrator command and no executable path are observably different. Volume II recognizes the reserved states in migration shape but exposes no operation, job, event or DML grant for either transition.

### `UPSTREAM-V1-ISSUE-COLLISION-013`

The canonical Issue fingerprint contract says a same-hash/different-preimage second tuple “may create” its own Issue, while AC-SM-006 requires an altered tuple to create a distinct Issue. Persisting the second Issue versus retaining only restricted collision telemetry changes Issue-set membership, Evaluation continuation, scoring, recommendations and history. Volume II does not choose between those outcomes. The second-Issue write, `IssueFingerprintCollision` publication, Issue-set sealing and every dependent score/recommendation/history publication for that affected Evaluation remain blocked until controlled Volume I correction says MUST or MUST NOT create the second Issue and defines whether the Evaluation continues or fails. The separate Check Result key-collision nonmerge/fail-closed path remains executable and unchanged.

These are deterministic product-behavior ambiguities: competent implementations could expose different data, transitions, usage or events while plausibly complying. They require a narrow controlled Volume I correction; Volume II must not resolve them.

## Implementation Gate

Implementation may begin only for slices whose command/read/event dependencies do not intersect a blocker. Slice 1 platform primitives may implement a nullable-neutral event registry shape but cannot finalize or emit the blocked scope classes. Write slices for accepted commands, crawler/parser/Check/score/recommendation/Delivery/Export machinery may proceed behind tests. No customer UI slice is complete until its exact read permission exists.

The Volume II architecture baseline may be frozen only when:

1. all thirteen upstream Volume I blockers have accepted deterministic corrections;
2. affected API/application/frontend/schema/job text is aligned without changing other behavior;
3. cross-document, identifier, link, table and terminology validation passes;
4. every physical operation maps to one Volume I behavior and every required behavior maps to one physical owner or explicit dormant gate;
5. critical and high implementation-disagreement risks are zero; and
6. the full diff contains no software implementation.

## Change Boundary

After acceptance, an implementation team may choose local variable names, private method extraction and equivalent query syntax only when tests prove the same contract. It may not change a selected database role, table ownership, lock order, queue/action identity, provider mapping, API schema, screen/query authorization, cache key, retry, timeout, serialization, deployment resource or test gate as an incidental coding choice.

Any future product-meaning change first changes Volume I through controlled change. Volume II then records only the implementation consequence.
