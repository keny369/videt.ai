# Rails Application Architecture

## Status And Scope

- Status: Volume II Implementation Architecture Pass 001 active
- Runtime: Ruby 3.4.10, Rails 8.1.3
- Architecture: modular monolith
- Background runtime: Sidekiq, not Solid Queue
- Source behaviour: immutable corrected Volume I baseline `v1.3-volume-i-corrected` under ADR-017

This document fixes the Rails module, bounded-context, aggregate, dependency, transaction, and concurrency architecture. It does not define new product behaviour.

## Runtime Baseline

The initial implementation locks these versions. Patch upgrades require the ordinary dependency-security change path and must preserve every contract in this Volume II set.

| Component | Baseline |
| --- | --- |
| CRuby | 3.4.10 |
| Rails | 8.1.3 |
| PostgreSQL | 17, Heroku-managed minor patch |
| `pg` | 1.6.3 |
| Puma | 8.0.2 |
| Sidekiq | 8.1.6 |
| `redis-client` | 0.30.0 |
| `connection_pool` | 3.0.2 |
| Queue/cache service target | Heroku Key-Value Store Premium, Valkey major 8 (current platform minor 8.1); Redis protocol compatibility only |
| `turbo-rails` / Turbo | 2.0.23 / 8.0.23 |
| `stimulus-rails` | 1.3.4 |
| RSpec Rails | 8.0.4 |
| Packwerk | 3.3.0 |

The application uses Propshaft and Importmap. It has no production Node.js runtime, JavaScript bundler, GraphQL runtime, Solid Queue database, or second cache/job datastore. Sidekiq owns its queue connection pools and uses the pinned `redis-client`; application code does not substitute `redis`/`hiredis`, create another queue pool, or select a different wire client. The queue and cache clients use only commands accepted by Valkey 8.1 and negotiate the protocol supported by the pinned client/server pair; changing either client version, the Valkey major, or the negotiated protocol is one compatibility-tested runtime-baseline change. `Gemfile.lock` and the import map pin exact transitive artifacts and integrity digests; deployment never resolves an unbounded version.

## Deployment Unit

F1 is one Rails codebase and one deployable release artifact. Web, worker, scheduler, and release processes run the same artifact with different process commands. There is one primary PostgreSQL database. Context boundaries are in-process package boundaries, not network services.

The baseline MUST NOT introduce:

- a microservice or separate context database
- direct HTTP/RPC calls between contexts
- an event broker as a second source of truth
- a second Rails application for administration
- a separate GraphQL API
- engine isolation that creates independent migrations or authentication

## Source Layout And Constant Names

The future application uses these exact roots:

| Path | Purpose |
| --- | --- |
| `app/workflows` | Outer `Workflows` coordinators; the only package permitted to compose public commands/decisions from more than one context |
| `app/contexts/<context>/domain` | Aggregate roots, entities, value objects, invariant policies, domain events |
| `app/contexts/<context>/application/commands` | Immutable command types and one handler per state-changing operation |
| `app/contexts/<context>/application/queries` | Read-only query types and handlers |
| `app/contexts/<context>/application/ports` | Repository and external dependency interfaces owned by the caller |
| `app/contexts/<context>/infrastructure/records` | Package-private Active Record classes |
| `app/contexts/<context>/infrastructure/repositories` | PostgreSQL repository implementations |
| `app/contexts/<context>/infrastructure/adapters` | Provider and cross-context port implementations |
| `app/contexts/<context>/infrastructure/jobs` | Thin Sidekiq transport entry points |
| `app/contexts/<context>/presentation` | Authorized DTO presenters and serializers |
| `app/platform` | IDs, clock, canonical JSON, tenancy, command execution, outbox, audit, telemetry, error primitives |
| `app/controllers/web` | HTML/Turbo controllers |
| `app/controllers/api/v1` | First-party JSON controllers |
| `app/controllers/service/v1` | Signed machine ingress only |
| `app/controllers/webhooks` | Authenticated provider webhook ingress only |
| `app/views` | Server-rendered HTML and Turbo templates |

The ordinary Rails `app` root maps `app/platform` to the `Platform` namespace. Each immediate directory under `app/contexts` is registered as the autoload root for its matching context namespace; `app/platform` itself is not separately pushed as a root. A file below a context MUST define the matching context-qualified constant. Context roots are enforced as packages with Packwerk plus architecture specs. Rails concerns MUST NOT be used to share business behaviour across packages.

## Bounded Contexts And Ownership

| Context constant | Owns write authority for | May publish |
| --- | --- | --- |
| `IdentityAccess` | Account, Identity Validation Receipt metadata, Bootstrap Grant, Session, Invitation, Role Assignment, Access Policy; Credential security-policy validation for the Integration aggregate | identity, session, grant, invitation, role and policy events |
| `TenantGovernance` | Organization lifecycle, authorization epoch, closure request, Organization-wide policy pointers | Organization and closure lifecycle events |
| `Projects` | Project lifecycle, source-set version, current projection pointers | Project and projection events |
| `Intake` | Source and Project-membership transitions; Crawl aggregate write coordination including IngestionJob, ParsingJob and IndexingJob lineage; verification request/attempt, scope request, Document, Parsed Artifact and Evaluation Input Snapshot | source, verification, crawl, ingestion, parsing, indexing-job and snapshot events |
| `Retrieval` | Indexing transition validation inside the Crawl unit of work, Index Receipt and searchable Document projection | index-receipt and retrieval-projection events |
| `Evidence` | Evidence record metadata/Payload binding, Provenance, lineage, Validation Decision, Citation lifecycle | Evidence and Citation events |
| `Evaluation` | Evaluation aggregate write coordination including Check applicability, Check Result, Issue and Adjudication Case lineage; Issue Set, ScoreSnapshot and Reassessment Result | evaluation, Check, Issue, Case, score and reassessment events |
| `Recommendations` | RecommendationArtifact aggregate write coordination including AIResponse and Citation lineage; family/version, priority decision/override and action-queue projection | recommendation, AIResponse, Citation and action-queue events |
| `AiOrchestration` | AIResponse generation/safety validation inside the RecommendationArtifact unit of work, only when an approved provider policy exists | no independently committed lifecycle event |
| `Delivery` | Notification, recipient, Delivery/attempt, Export/manifest/retrieval | notification and Export events |
| `Commercial` | BillingEntity, plan assignment, Entitlement Decision, reservation, counter, usage record | billing, plan, entitlement, usage events |
| `Integrations` | Integration aggregate write coordination including Credential lifecycle; adapter registration and provider checkpoint/attempt/event | Integration, Credential and provider checkpoint events |
| `SecurityOperations` | Support Session, Incident, Investigation, high-risk approval, custody and report | support, incident, investigation, approval events |
| `DataLifecycle` | LegalHold, LifecycleDeletionJob, deletion manifest/outcome/evidence, backup tombstone | hold, deletion, tombstone and restore events |
| `Platform` | command/result/idempotency, authorization decision record, audit, event registry/outbox/inbox, scheduled action, stored-object metadata | infrastructure telemetry only; no product lifecycle event invented here |

`OrganizationMembership` and `EffectivePermission` are computed views. They have no command handler, mutable record, repository `save`, or domain-event stream.

## Canonical Aggregate Boundaries

The Aggregate Boundaries section and DM-REQ-008 in `specification/011 DOMAIN_MODEL.md` control write entry. Entity context, lifecycle-policy owner and physical lock row are separate concepts; none creates another aggregate root. A command targeting a child enters the listed root coordinator, which calls the lifecycle owner inside the same database unit of work. A child repository cannot expose `save` to a controller, job, adapter, or another aggregate.

| Target entity or state | Canonical aggregate root and command entry | Lifecycle-policy owner invoked by root | Repository/serialization guard |
| --- | --- | --- | --- |
| Organization, Account membership policy | Organization | TenantGovernance plus IdentityAccess policy | Organization row and authorization epoch |
| Project, Source membership | Project | Projects plus Intake Source policy | Project row and source-set sequence |
| Crawl, IngestionJob, ParsingJob, IndexingJob | Crawl | Intake; Retrieval validates indexing transition | Crawl row plus child attempt/checkpoint row |
| Evaluation, Check Result, Issue, Adjudication Case | Evaluation | Evaluation | Evaluation row, Issue lineage head and calculation sequence |
| RecommendationArtifact, AIResponse, Citation | RecommendationArtifact | Recommendations; AiOrchestration and Evidence validate response/Citation | Recommendation family row and child fingerprint guard |
| BillingEntity and contract/billing state | BillingEntity | Commercial | BillingEntity row |
| Integration and Credential lifecycle | Integration | Integrations; IdentityAccess validates secret-access policy | Integration row and Credential/material-version rows |

DM-REQ-001 entities not named as independent canonical roots above remain children even when stored in separate tables or assigned a specialist context. Notification, Export, Incident, Investigation, LegalHold and LifecycleDeletionJob are additional lifecycle roots defined by accepted Volume I contracts; they do not alter the seven foundation aggregate boundaries.

The following are serialization guards, not aggregate roots, and prevent unrelated hot-row contention:

- `recommendation_families` allocates Artifact versions and current pointers.
- `issue_lineage_heads` allocates a single current leaf per full fingerprint preimage.
- `project_calculation_sequences` serializes score publication and prior-snapshot linkage.
- `entitlement_counter_windows` serializes reservations and committed usage per counter window.
- `scheduled_actions` serializes one timer identity and its dispatch/cancellation state.

## Dependency Rules

### Layer direction

Dependencies MUST point inward:

```text
controller / job / provider webhook
              |
              v
application command or query
              |
              v
domain aggregate / value object / policy

infrastructure repository or adapter --> application port
presentation serializer -------------> authorized query DTO
```

Domain code depends only on Ruby standard-library abstractions and `Platform` value primitives. It MUST NOT depend on Rails, Active Record, Sidekiq, Redis, HTTP clients, vendor SDKs, controllers, presenters, or another context's record class.

### Cross-context direction

The allowed compile-time dependency graph is:

```text
Platform
  ^
  +-- IdentityAccess       TenantGovernance       Projects
  +-- Intake              Retrieval              Evidence
  +-- Evaluation          Recommendations         AiOrchestration
  +-- Delivery            Commercial             Integrations
  +-- SecurityOperations  DataLifecycle

Application orchestrators depend on public application ports from the
contexts they coordinate; contexts do not depend on orchestrators.
```

No context may directly reference another context's Active Record class, table-backed association, repository implementation, Sidekiq job, controller, or presenter. Cross-context reads use a named public query returning a frozen DTO. Cross-context writes use a named command or a versioned event. Cycles are forbidden.

### Provider direction

The calling context owns the port. `Integrations` resolves an approved adapter and supplies a port implementation; the vendor adapter depends on the port contract. Vendor SDK types MUST NOT cross the adapter boundary or enter a domain/event payload.

## Command And Transaction Model

Every state-changing operation enters through one command handler. The handler runs these stages in order:

1. validate physical schema and canonicalize the logical command
2. establish transaction-local tenant and request context
3. authenticate the principal or service identity
4. claim the idempotency identity and compare the complete request hash
5. resolve authoritative permission, policies, entitlement and expected versions
6. load and lock only the required aggregate roots
7. invoke aggregate transitions and validate invariants
8. persist domain state, logical result, authorization decision, audit record, domain events, any required Notification-consumer outbox route, and any next ScheduledAction atomically
9. commit
10. enqueue or render only from the committed result

Validation, authentication, or authorization rejection still persists the required restricted command/audit outcome in its own transaction. Exact replay reads the retained result, reauthorizes disclosure, applies current redaction, and performs no stage from step 6 onward.

The application MUST NOT use Active Record callbacks for workflow orchestration, provider dispatch, event publication, current-pointer changes, usage commitment, or audit creation. Database triggers are limited to mechanical `updated_at`, partition routing supplied by PostgreSQL, and immutable-row protection explicitly named by the schema; no trigger may invent domain behaviour.

## Named Multi-Root Transactions

Multi-root writes are allowed only for these frozen workflows and use the listed boundary:

| Workflow | One atomic commit contains |
| --- | --- |
| Self-service bootstrap | receipt nonce and grant claim; Organization; Account; baseline BillingEntity; initial Role Assignment; baseline Access/Entitlement/Plan records with same-Organization BillingEntity linkage; draft Project; Session; ordered result/audit/events |
| Existing-account sign-in | receipt nonce; exact Account/Organization/assurance check; current authorization-context snapshot; one Session; logical destination result/audit/`SessionCreated` |
| Invitation acceptance | receipt nonce; Invitation; Account create/reuse; exact Role Assignment create/reuse; Session; result/audit/events |
| Access mutation | Organization authorization epoch plus target Assignment/Policy/Account/Session effects and event |
| Project activation | Project state and verified-active Source-membership version check |
| Verification success | Verification Request/attempt, Source transition, Verification Evidence, first Source Scope Policy and events |
| Crawl start | Entitlement reservation, Crawl transition and initial Evaluation creation when the root branch applies |
| Ingestion success | IngestionJob, Document transition, source-document Evidence and events |
| Parsing success | ParsingJob, Parsed Artifact, Document transition, platform-derived Evidence, IndexingJob and events |
| Evaluation seal | Evaluation state, complete Result set, Issue plan, Issue Set and events |
| Score publication | calculation sequence, ScoreSnapshot/pillars/Contributions, current projection and events |
| Adjudication or Evidence validation | Case/Issue or Validation Decision, score-unavailable projection, affected Recommendation suppression and events |
| Recommendation publication | family sequence, immutable Artifact/version bindings, prior retirement/current pointer and events |
| AI validation | AIResponse terminal state, every Citation decision and Artifact binding; no network call |
| Reassessment publication | Source-set recheck, prior/current Evaluation pointers, Issue/Case lineage, score, recommendation deltas, terminal result, entitlement intent and events |
| Entitlement reservation | counter window, Decision, reservation and counter values |
| Export availability | verified manifest, final object pointer, usage commit intent and available transition |
| Organization closure | closure execution, BillingEntity and Organization close, Session revocation, queued-work cancellation markers, deletion job and events |
| Deletion completion | final manifest outcomes, immutable Deletion Evidence and terminal job state |

The Evaluation-seal boundary is executable for ordinary Issue derivation and for the separately specified Check Result key-collision failure path. It is not executable for an Issue-fingerprint same-hash/different-preimage branch under `UPSTREAM-V1-ISSUE-COLLISION-013`: the transaction must not choose second-Issue persistence, publish `IssueFingerprintCollision`, seal an Issue Set or advance score/recommendation/history until controlled Volume I correction defines the product outcome and Evaluation continuation/failure.

All other cross-context reactions occur after commit through the exact ScheduledAction/Work Dispatch Binding registry. Domain-event outbox consumption is closed to `notification_route_v1`; it is not a generic workflow bus. A derived-read delay MUST NOT weaken a command invariant.

## Locking And Concurrency

### Lock order

Every required advisory and row lock is determined before the first row lock. Locks are acquired by the total tuple `(tier, table_name_utf8_bytes, organization_id_uuid_bytes_or_zero, project_id_uuid_bytes_or_zero, row_id_uuid_bytes_or_zero)`. Rows of the same table therefore lock by ascending UUID bytes; alternatives in one tier never depend on call order. A transaction that discovers a lower tuple after acquiring a higher tuple rolls back and retries from a fresh read; it never acquires out of order.

The tiers are:

1. Organization, bootstrap-principal serialization row, or BillingEntity when the same Organization transaction requires it
2. Account / Role Assignment / Session
3. Project / source-set sequence
4. Source / Verification Request / Crawl
5. Document / ingestion / parsing / indexing job
6. Evaluation / Issue lineage head / Adjudication Case
7. project calculation sequence / ScoreSnapshot projection
8. Recommendation family / AIResponse
9. Entitlement counter window / reservation
10. Notification / Delivery / Export
11. Integration / Credential
12. Incident / Investigation / Support Session
13. LegalHold / LifecycleDeletionJob
14. command result / audit / domain event / Notification outbox route / next ScheduledAction rows

An advisory lock for a not-yet-existing identity occupies tier zero and uses `(namespace_utf8_bytes, complete_preimage_sha256, collision_ordinal)` ordering. It is released only after the permanent serialization row exists. Code that cannot acquire the full sorted set must split the work at a committed event boundary. PostgreSQL deadlock or serialization failure retries the same physical transaction at most twice with delays of 10 and 50 milliseconds, reusing the command/idempotency claim and incrementing no product attempt; exhaustion maps to the Volume I concurrency result rather than creating a third product execution.

### Concurrency primitives

- Mutable roots and mutable projections use optimistic `lock_version` plus the Volume I `state_version` exposed to callers.
- Race-critical transitions use `SELECT ... FOR UPDATE` on the serialization/root row.
- Due-work dispatch uses `FOR UPDATE SKIP LOCKED` over `scheduled_actions`.
- Transaction-scoped PostgreSQL advisory locks are allowed only for a stable hash namespace where no row can exist yet, such as first allocation of a fingerprint digest or bootstrap principal. A row is created before the lock is released.
- Redis locks, Sidekiq uniqueness, process mutexes, and cache `add` are never correctness controls.
- Network calls, object-store uploads, PDF rendering, DNS/HTTP observations, crawl fetches, and AI/provider calls never run while a database transaction is open.

PostgreSQL transaction time owns all persisted equality races. Network elapsed deadlines use a monotonic process clock, then recheck database time before the terminal commit. Late results are discarded when a persisted deadline has won.

## External-Side-Effect Checkpoints

Every external effect uses four durable stages; Mailgun uses the stricter WF-014 uncertainty rule:

1. `prepared`: the unique attempt identity, immutable request payload hash, deadline, required logical `mailgun-email-v1` identity and executing adapter code version are claimed before Integration/Credential validation; resolved policy-artifact/Integration/Credential/material versions start null and are filled only as prepared-stage validation resolves them
2. `submission_started`: the serialized prepared-stage executor rechecks authority/deadline and commits the checkpoint before any network write
3. provider call outside the transaction
4. `recorded`: response/event mapping is committed idempotently, or the attempt terminalizes by its exact timeout rule

A claimed Mailgun attempt still at stage 1 may be resumed by one serialized executor because no provider submission has begun. Exhausted retryable Integration initialization or a transport outcome proving no network submission completes that prepared attempt as definitively nonaccepted and follows the fixed Delivery retry schedule; invalid/missing policy/configuration, disconnected/retired Integration, or unavailable/invalid/revoked/expired Credential terminal-fails that attempt with its exact reason. No other prepared-stage failure retries. Exactly one executor may advance the attempt to stage 2; the adapter and client disable implicit transport retry and perform one network submission operation. A crash, timeout, `408`, `5xx`, partial response, or other incomplete result after stage 2 transitions the Delivery to `acceptance_unknown`; no worker may re-enter that attempt's provider call. Read-only reconciliation and an explicitly acknowledged `delivery_replay` targeting only the source Delivery's same logical email recipient are the only uncertainty recovery paths; only `empty_recipient_replay` may resolve a whole current selector union. The application deduplication/correlation key prevents duplicate local submission of one claimed attempt but never claims provider exactly-once delivery.

## Read Models

Read projections are rebuildable and never write authority. Each projection stores:

- Organization and Project scope
- source aggregate IDs and exact versions/hashes
- projection schema version
- redaction-independent structured values
- `projection_version`, `built_at_utc`, status and ordered unavailable reasons

Authorization and field redaction are applied after loading the projection. A projection MUST NOT precompute a role-wide allow that can outlive the Organization authorization epoch. Dashboard and history projections contain deterministic structured data only and have no narrative column, presenter slot, job, or provider path.

## Architecture Fitness Checks

Future CI MUST fail when any of these conditions occurs:

- a context references another context's record, repository implementation, job, controller, or presenter
- a domain class references Rails, Active Record, Sidekiq, Redis, HTTP, a provider SDK, wall-clock time, or nondeterministic randomness directly
- a controller mutates an Active Record model without a command handler
- a query handler writes, enqueues, consumes entitlement, or calls a provider
- a presenter queries, writes, authorizes, or calls a provider
- an Active Record callback publishes an event or coordinates a workflow
- a provider adapter returns vendor SDK types across its port
- a job receives an Active Record serialization, secret, token, or payload bytes
- a cross-context dependency cycle exists
- a provider call occurs inside an open database transaction
- a dashboard/history component references `AiOrchestration`
- Solid Queue is configured as the Active Job backend

## Corrected Volume I Constraints Inherited By This Architecture

ADR-017 closes the six defects. This architecture therefore inherits: purpose-bound existing-account Session creation; `reassessment_schedule` Policy Artifacts, exact due-slot identities, and due-time plus current scope-state eligibility; WF-001-only BillingEntity creation with only active-to-closed baseline closure; the canonical Evidence vocabulary with reserved/unavailable `operator_attestation`; deterministic structured-only CAP-019 output with no AI narrative path; and Mailgun pre-validation attempt claims, exhaustive prepared-stage outcomes, `acceptance_unknown`/read-only reconciliation, and no provider exactly-once claim.
