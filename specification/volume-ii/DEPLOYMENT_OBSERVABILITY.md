# Volume II Deployment, Observability, And Recovery Architecture

## Status And Scope

- Status: Volume II implementation contract
- Behavioural baseline: frozen Volume I at `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020). Historical `v1.3-volume-i-corrected` is retained as predecessor history and is not the baseline.
- Engineering-practice baseline: accepted Engineering Manual at `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022), normative for engineering practice only.
- Platform: Heroku stack `heroku-26`
- Database: PostgreSQL `17`
- Background runtime: Sidekiq `8.1.6`
- Observability: OpenTelemetry exported to Datadog

This document fixes production topology, storage, configuration, deployment, telemetry, alerting, backup, and recovery choices. It creates no product capability or lifecycle transition.

Related contracts:

- [Rails Application Architecture](../../architecture/RAILS_APPLICATION_ARCHITECTURE.md)
- [PostgreSQL Schema](../../schemas/POSTGRESQL_SCHEMA.md)
- [Background Processing](BACKGROUND_PROCESSING.md)
- [Integration Contracts](INTEGRATION_CONTRACTS.md)
- [Quality Attributes](../013%20QUALITY_ATTRIBUTES.md)
- [Security Model](../014%20SECURITY_MODEL.md)
- [Data Lifecycle](../015%20DATA_LIFECYCLE.md)
- [Observability](../018%20OBSERVABILITY.md)

## Inherited Blockers

The pre-Organization/platform-wide event `organization_id` contradiction described in [Background Processing](BACKGROUND_PROCESSING.md#unresolved-inherited-event-scope-contradiction) remains unresolved. Deployment MUST NOT introduce a sentinel tenant, nullable event convention, or per-Organization copy to bypass it.

Volume I also does not provide complete workflows for Project pause/resume/archive commands or independent Session revocation. Volume II deployment and operations therefore MUST NOT expose an administrative endpoint, console procedure, scheduled job, or incident step that performs those mutations. Defined expiry and Organization/Account lifecycle effects remain available only through their accepted workflows.

## Environment Topology

There are exactly three isolated application environments:

| Environment | Purpose | Customer data | Deployment source |
| --- | --- | --- | --- |
| `development` | local engineering | synthetic only | developer checkout |
| `staging` | production-shaped verification | synthetic or irreversibly anonymized fixture only | immutable candidate slug |
| `production` | customer service | permitted | promotion of the exact staging-verified slug |

Each environment has a distinct Heroku app, PostgreSQL database, queue Redis, cache Redis, S3 buckets/prefixes, KMS keys, Secrets Manager Secret set, Datadog environment, Mailgun domain/credentials and managed-identity audience. No credential, database, Redis service, object key prefix, KMS key, Secret or provider webhook is shared across environments.

Production runs in the Heroku Private Space region whose configuration identifier is `sydney`. All stateful dependencies are placed in or pinned to the same Australian data-residency region where the provider supports it. A cross-region service requires a recorded security/privacy review and must not be enabled merely as failover.

## Release Artifact And Process Formation

One Heroku slug built from one locked Git commit is used by every process. Process commands are fixed by the repository `Procfile`; no Heroku Dashboard command override is permitted.

| Process type | Exact production count | Runtime responsibility | Concurrency |
| --- | ---: | --- | ---: |
| `web` | 2 | Puma Rails HTML/API/webhook service | 2 Puma workers × 5 threads |
| `worker_control` | 2 | Sidekiq `control` and reserved `maintenance` work | 5 threads per process |
| `worker_delivery` | 2 | Sidekiq `delivery` | 10 threads per process |
| `worker_pipeline` | 2 | Sidekiq `pipeline` | 5 threads per process |
| `worker_crawl` | 2 | Sidekiq `crawl` | 10 threads per process |
| `worker_projection` | 1 | Sidekiq `projection` | 5 threads per process |
| `worker_lifecycle` | 1 | Sidekiq `lifecycle` | 2 threads per process |
| `scheduler` | 1 | PostgreSQL due-action/outbox dispatcher | one leader lease |
| `release` | ephemeral | migration preflight and forward migration | one invocation per release |

The selected Heroku dyno class for each process MUST supply at least 1 GiB memory for web/control/delivery/projection/lifecycle and 2 GiB for pipeline/crawl. A SKU name is deployment inventory, not an architecture identity; changing to an equivalent or larger SKU does not change process behavior.

Automatic dyno autoscaling is disabled in the baseline. Production runs exactly the counts and concurrency in this table; neither a dashboard rule nor a queue-latency hook changes them. A count/concurrency change requires a reviewed Volume II revision, connection-budget preflight, load evidence and ordinary release. Scheduler remains one process with one database-elected leader.

## Puma, Rails And Connection Pools

- `RAILS_MAX_THREADS=5` and `WEB_CONCURRENCY=2` are fixed in production.
- Each Puma worker has a PostgreSQL pool of seven and a cache Redis pool of seven.
- Sidekiq PostgreSQL and queue-Redis pools equal process concurrency plus two.
- Scheduler PostgreSQL pool is five; queue-Redis pool is five.
- Release PostgreSQL pool is two.
- The fixed formation consumes at most 122 application/release PostgreSQL connections: web 28, control 14, delivery 24, pipeline 14, crawl 24, projection 7, lifecycle 4, scheduler 5 and release 2. Preflight adds ten reserved operational/provider connections, requires `max_connections >= 189`, and blocks promotion unless the resulting 132 is at or below 70% of the actual plan limit. No hidden review app, console or one-off dyno may consume that reserve in production.
- PostgreSQL `statement_timeout` is 450 ms for ordinary synchronous authorized queries, 750 ms only for the registered internal Retrieval search query, five seconds for command transactions, and the exact smaller workflow deadline where applicable. Migration and lifecycle batch connections use separate role-scoped timeouts.
- PostgreSQL `lock_timeout` is one second for web commands and five seconds for release migrations. An owning workflow's stricter race remains authoritative.
- `idle_in_transaction_session_timeout` is 15 seconds for runtime roles.

No network call, object transfer, PDF/package rendering or provider request is made while a database transaction is open.

## PostgreSQL 17 Service

Production uses one Heroku-managed PostgreSQL 17 primary with high availability, encrypted storage, continuous WAL archiving, point-in-time recovery of no worse than one hour, and daily verified backups. The plan must provide enough connections and I/O for the preflight budgets; a plan change cannot weaken HA, WAL, encryption or retained recovery coverage.

Required database controls are:

- TLS required with certificate verification;
- database and connection time zone UTC;
- schema owned only by `f1_schema_owner`;
- runtime roles have no table ownership or `BYPASSRLS`;
- `FORCE ROW LEVEL SECURITY` and tenant-context integration checks before release;
- SQL-format schema dump;
- `pgcrypto`, `pg_trgm` and `btree_gin` only;
- current and next two monthly event/audit/provider partitions present before readiness passes;
- autovacuum/analyze enabled, with table-specific tuning recorded in deployment inventory;
- slow-query capture at 250 ms with bind values removed; and
- no direct public network access.

The event-scope contradiction prevents production acceptance of the unresolved event forms; it does not authorize loosening RLS or making all event rows nullable.

## Redis Services

Queue and cache use two distinct Heroku Key-Value Store Premium add-ons in the Sydney Private Space. Both run Valkey major 8 (the current Heroku-supported minor is 8.1), require TLS and high availability, and expose separate credentials/URLs. F1 uses only Redis-protocol commands supported by Valkey 8 and the pinned Ruby clients; it does not depend on a Redis-licensed server or third-party marketplace add-on.

Heroku may apply supported Valkey minor updates within major 8 during the declared maintenance window only after staging contract/load/failover tests pass against that minor. A Valkey major change, provider substitution or downgrade requires a Volume II revision and the full queue-loss/cache-fallback/Sidekiq compatibility suite before production. Release preflight rejects a service whose reported major is not 8, HA/TLS is unavailable, or provider is not Heroku Key-Value Store Premium.

### Queue Redis

- Dedicated to Sidekiq.
- TLS required.
- High availability and automatic failover required.
- Eviction policy `noeviction`.
- No Rails cache, rate-limit cache, session data or application value may share it.
- Sidekiq scheduled sets are not timer authority; PostgreSQL reconcilers recover acknowledged-but-lost jobs.
- Memory use alerts at 70%, 80% and 90%; any eviction is critical.

### Cache Redis

- Dedicated to disposable projection/fragment cache and nonauthoritative acceleration. No product entitlement, authorization decision, durable work, Session state or other correctness-bearing limiter is stored here.
- TLS required.
- Eviction policy `allkeys-lfu`.
- Maximum application TTL 15 minutes unless a shorter security convergence rule applies.
- Every cached projection fragment includes Organization authorization epoch, source record versions and policy versions; the authorization decision itself is never cached, and stale/missing projection cache falls back to PostgreSQL.
- Cache unavailability cannot grant access, consume entitlement, create a product result, or lose work.

Sessions are PostgreSQL-backed token digests; neither Redis instance is Session authority.

## Private Object Storage And KMS

AWS S3 stores nonrelational bytes in private buckets with Block Public Access enabled. AWS KMS customer-managed keys provide server-side encryption. Exact environment resources are:

| Bucket role | Permitted objects | Access path | CDN |
| --- | --- | --- | --- |
| `staging` | temporary fetch/parser/index/generation bytes | worker role only | prohibited |
| `evidence` | committed Evidence payloads and immutable generated content | authorized application/worker role | prohibited |
| `exports` | encrypted Export packages | application retrieval after reauthorization | prohibited |
| `assets` | fingerprinted public Rails assets only | public read through CloudFront | permitted |

Object keys are generated by F1 and contain environment, Organization UUID, retention class, owner type, owner UUID, immutable generation/version, and random UUID. They contain no customer name, email, host, URL, provider ID or free text.

Staging, Evidence and Export buckets require TLS, deny public ACL/policy, disable website hosting, deny unencrypted writes, and log control-plane access. Each write supplies expected byte count, SHA-256, media type, retention class, KMS key ARN and encryption-context digest; publication occurs only after a read-back checksum passes. Multipart uploads have persisted upload IDs and are aborted within the owning temporary-processing deadline.

CloudFront serves only the `assets` origin. It has no origin access to staging, Evidence or Export buckets. No signed URL to protected customer bytes is issued in baseline; retrieval streams through an authorized application response and records the exact retrieval outcome.

DataLifecycle is the only authority for protected object/key destruction. S3 lifecycle rules may remove abandoned multipart uploads and already-authorized staging objects, but MUST NOT independently destroy Evidence, product history, Export packages, held data or backup data before the persisted manifest authorizes it.

## Network And Trust Boundaries

- Heroku router to web uses HTTPS only; every application response applies `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`, matching the Security contract.
- Application-to-PostgreSQL, Redis, S3/KMS/Secrets Manager, Datadog, Mailgun, managed identity and DNS resolvers uses TLS where the protocol supports it.
- Outbound provider hosts are allowlisted by exact adapter and environment.
- Crawler and domain-verification connections apply destination safety and cannot use environment HTTP proxy variables.
- Administrative PostgreSQL, Redis and Heroku access requires named SSO/MFA accounts; shared operator accounts are prohibited.
- Production console access is disabled by default. Time-bounded emergency access is audited and cannot invoke undefined Project lifecycle or standalone Session-revocation mutations.

## Environment Variable Contract

Variables not listed here are prohibited in production unless a later Volume II revision admits them. Secret values are marked `secret` and are managed through Heroku's protected configuration with access audit and rotation.

| Variable | Secret | Required process | Contract |
| --- | --- | --- | --- |
| `RAILS_ENV=production` | no | all | exact |
| `RACK_ENV=production` | no | all | exact |
| `RAILS_LOG_TO_STDOUT=true` | no | all | exact |
| `RAILS_SERVE_STATIC_FILES=false` | no | web | assets use CloudFront |
| `RAILS_MAX_THREADS=5` | no | web | exact |
| `WEB_CONCURRENCY=2` | no | web | exact |
| `SECRET_KEY_BASE` | yes | web/worker | platform session/signing bootstrap secret |
| `RAILS_MASTER_KEY` | yes | all | Rails encrypted-config bootstrap only; no tenant provider material |
| `F1_SESSION_REPLAY_KEYS` | yes | web | versioned AES-256-GCM key ring for exact Session-creation response replay; one current key plus only still-needed retired decrypt keys |
| `DATABASE_URL` | yes | all/release | PostgreSQL 17 primary with verified TLS options |
| `SIDEKIQ_REDIS_URL` | yes | worker/scheduler | queue Redis only |
| `CACHE_REDIS_URL` | yes | web/worker | cache Redis only |
| `APP_BASE_URL` | no | web/worker | canonical HTTPS origin |
| `AWS_REGION` | no | worker/web | approved Australian region |
| `AWS_ACCESS_KEY_ID` | yes | web/worker | least-privilege application IAM identity |
| `AWS_SECRET_ACCESS_KEY` | yes | web/worker | rotated application IAM secret |
| `F1_STAGING_BUCKET` | no | workers | private bucket |
| `F1_EVIDENCE_BUCKET` | no | web/workers | private bucket |
| `F1_EXPORT_BUCKET` | no | web/workers | private bucket |
| `F1_ASSET_BUCKET` | no | release | public-assets origin bucket |
| `F1_ASSET_CDN_HOST` | no | web | CloudFront public-assets host |
| `F1_KMS_KEY_ARN` | no | web/workers | environment customer-managed key |
| `MAILGUN_API_BASE` | no | delivery | exact allowed base |
| `MAILGUN_SENDING_DOMAIN` | no | delivery | signed-policy domain |
| `IDENTITY_BOUNDARY_ARTIFACT_SHA256` | no | web/release | 64 lowercase hex digest of the verified active `f1-managed-identity-redirect-v1` release artifact |
| `IDENTITY_RECEIPT_AUTHORIZATION_ENDPOINT` | no | web | exact artifact-mirrored HTTPS authorization endpoint |
| `IDENTITY_RECEIPT_CLIENT_ID` | no | web | exact artifact-mirrored client identity |
| `IDENTITY_RECEIPT_ISSUER` | no | web | exact approved issuer |
| `IDENTITY_RECEIPT_AUDIENCE` | no | web | environment-specific audience |
| `IDENTITY_RECEIPT_JWKS_URL` | no | web | same-origin HTTPS JWKS |
| `F1_DNS_RESOLVER_ADDRESSES` | no | control/crawl | comma-separated approved literal resolver IPs |
| `DD_API_KEY` | yes | all | Datadog ingest key |
| `DD_SITE` | no | all | one approved Datadog site |
| `DD_ENV` | no | all | exact environment name |
| `DD_SERVICE=f1` | no | all | exact service root |
| `DD_VERSION` | no | all | deployed Git SHA |
| `OTEL_SERVICE_NAME=f1` | no | all | exact |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | all | local Datadog agent/buildpack endpoint |

`STRIPE_*`, `OPENAI_*`, `ANTHROPIC_*`, `OPENROUTER_*`, `GOOGLE_*`, `MUX_*`, `POSTMARK_*`, a second database URL, and customer-supplied provider endpoint variables are prohibited. Their presence fails release preflight.

Release preflight signature-verifies the one active managed-identity artifact, compares its SHA-256 and every authorization endpoint/client/issuer/audience/JWKS mirror byte-for-byte, derives the callback from `APP_BASE_URL`, and fails before migration or boot on absence, extra active artifact, signature/key/version error or mismatch. Runtime reads the verified artifact record; environment mirrors never override it.

No Action Cable server, WebSocket route, server-sent-event endpoint, application Pub/Sub namespace or background browser poller is deployed in the baseline. Turbo Streams are rendered only in the initiating HTTP response, and later asynchronous state is observed on a new authorized request.

## Secret Rotation

- Heroku/AWS/Datadog bootstrap secrets rotate at least every 90 days and immediately after suspected disclosure.
- Mailgun and managed identity keys follow their versioned provider/issuer overlap contracts; only active and explicitly overlapping verification versions are accepted.
- Rotation is additive: provision new, verify, activate, observe, revoke old, then destroy old.
- A secret change never occurs by editing a database Credential into a new state outside its command contract.
- CI scans the repository, built slug and generated manifests for secret patterns. Any finding blocks deployment.

## CI/CD And Migration Flow

GitHub Actions is the sole production build initiator. Protected `main` requires review and passing checks. CI performs, in order:

1. dependency lock integrity and reproducible Ruby/JavaScript install;
2. secret, dependency vulnerability and license scans;
3. formatting/lint, architecture-boundary and static-security checks;
4. unit, domain, policy, repository, request, system, contract and acceptance-mapping tests;
5. PostgreSQL schema creation from empty, migration from previous release and production-shaped migration rehearsal;
6. RLS, tenant-isolation, partition, FK/index, immutable-column and query-plan fitness tests;
7. Sidekiq retry-disabled, job-catalogue and process-loss fault tests;
8. adapter contract tests with network denied except explicit simulators;
9. asset build and manifest digest; and
10. build one immutable Heroku slug labeled with Git SHA and dependency lock digests.

The slug deploys to staging. Staging runs smoke, synthetic, migration, queue-loss, provider-simulator and rollback-forward checks. Production promotion uses the exact slug without rebuild and requires recorded approval by one release owner and one different security/operations approver.

The release process obtains a PostgreSQL migration advisory lock, verifies backup/replica/partition/connection headroom, runs expand/backfill/switch-safe migrations, validates RLS, and exits before web formation changes. Failure leaves the previous formation serving and blocks promotion. Contract/destructive migration occurs only in a later release after the documented observation window.

Application rollback promotes the prior slug. Database rollback is never automatic; incompatible data/schema incidents use a reviewed forward fix or PITR recovery. A release cannot change Volume I policy artifacts, provider activation, or product defaults through an environment variable.

## Health And Synthetic Checks

Physical operational endpoints are private from search indexing and return no tenant/provider detail:

| Endpoint | Meaning | Dependencies |
| --- | --- | --- |
| `/health/live` | process event loop responds | none |
| `/health/ready` | process can serve authoritative requests | PostgreSQL query and schema/partition version; process-specific queue Redis only for scheduler/workers |
| `/health/dependencies` | restricted operations detail | PostgreSQL, queue/cache Redis, S3/KMS/Secrets Manager metadata authorization, Datadog exporter and adapter-policy availability; no Secret bytes or provider send |

Cache Redis failure reports degraded but does not fail web readiness. Queue Redis failure also reports degraded without failing web readiness: an accepted command commits its authoritative outbox/ScheduledAction and infrastructure dispatch schedule in PostgreSQL, then returns its normal committed result. Queue Redis failure makes worker and scheduler readiness fail until transport resumes. Provider outages do not fail web liveness; owning workflows fail safely.

Synthetic checks run every five minutes from two external Australian probes and cover public TLS and sign-in entry. Staging additionally runs a synthetic managed-receipt sign-in and an end-to-end deterministic Evaluation. While low-cost/history event blockers remain, staging asserts the affected dashboard/history routes are absent and verifies their projections through internal contract tests; only after controlled correction may synthetics exercise those customer reads. Synthetics never generate Mailgun customer email, AI calls, billing calls, or production mutation.

## Structured Logging

Rails emits one-line JSON to stdout. Heroku log drains send it to Datadog. Every record contains:

- timestamp UTC, severity, environment, service, version, process type and instance;
- event name, workflow ID, correlation and causation IDs;
- Organization and Project IDs where valid and authorized;
- actor or service identity type and opaque ID where permitted;
- command/event/work type and opaque ID;
- attempt/replay/claim generation where applicable;
- normalized outcome, reason code, duration and retry classification; and
- trace and span IDs.

Logs never contain request/response bodies by default. Credentials, cookies, authorization headers, receipt/JWS bytes, idempotency keys, challenge tokens, email addresses, URLs, Evidence/customer text, provider bodies and raw exception parameters are redacted before serialization. Redaction failure drops the unsafe field, emits `telemetry_redaction_failure`, and never blocks the authoritative product transaction.

Operational logs are `operational_telemetry` and retain 30 days searchable, at most 90 days archived. Canonical Audit Evidence remains in PostgreSQL under its own retention and MUST NOT be reconstructed from logs.

## OpenTelemetry And Datadog

Rails, Active Record, Sidekiq, Redis, HTTP, DNS and AWS clients emit OpenTelemetry traces through the Datadog buildpack/agent. W3C `traceparent`/`tracestate` propagates across accepted HTTP boundaries. Sidekiq propagation uses the persisted correlation ID and a transport trace context that is not part of product identity.

Datadog tail sampling retains:

- 100% of error, security, authorization-denial, provider-uncertainty, deletion, recovery and redaction-failure traces;
- 100% of traces slower than the applicable latency budget;
- 10% of other production traces; and
- 100% in staging for acceptance runs.

Trace attributes follow the same redaction and bounded-cardinality rules as logs. Organization, Project, record and provider IDs may be restricted span attributes but never metric tags.

Datadog Error Tracking is the only production exception aggregator. It receives sanitized exception class, normalized message, backtrace, release, process, trace/correlation ID and bounded context. Local variables and request/job payload capture are disabled.

## Metric Catalogue

Metric names are exact and use bounded tags only:

| Metric | Type | Required tags |
| --- | --- | --- |
| `f1.http.requests` | counter | route template, method, status class, outcome |
| `f1.http.duration_ms` | histogram | route template, method, outcome |
| `f1.workflow.completed` | counter | workflow, outcome, reason family |
| `f1.workflow.duration_ms` | histogram | workflow, outcome |
| `f1.sidekiq.queue_depth` | gauge | queue |
| `f1.sidekiq.oldest_age_seconds` | gauge | queue |
| `f1.job.completed` | counter | work type, queue, outcome |
| `f1.job.duration_ms` | histogram | work type, queue, outcome |
| `f1.job.lease_expired` | counter | work type, checkpoint class |
| `f1.outbox.oldest_age_seconds` | gauge | consumer class |
| `f1.scheduler.overdue_seconds` | histogram | action kind |
| `f1.db.pool_utilization` | gauge | process type |
| `f1.db.deadlocks` | counter | transaction class |
| `f1.db.query_duration_ms` | histogram | query name, context |
| `f1.redis.memory_utilization` | gauge | service role |
| `f1.redis.evictions` | counter | service role |
| `f1.integration.calls` | counter | adapter, operation, outcome |
| `f1.integration.duration_ms` | histogram | adapter, operation, outcome |
| `f1.mailgun.uncertain` | gauge | age band |
| `f1.mailgun.reconciliation` | counter | result |
| `f1.evaluation.input_readiness` | counter | readiness, coverage |
| `f1.evidence.validation` | counter | type, status, reason family |
| `f1.score.calculation` | counter | status, completeness |
| `f1.lifecycle.deadline_seconds` | histogram | stage, outcome |
| `f1.security.authorization` | counter | action family, allow/deny, reason family |

Per-Organization cost and usage are stored as authorized durable records and queried into restricted dashboards; Organization UUID is never a Datadog metric tag.

## Dashboards And Alerts

Required dashboards are `Customer Surface Reliability`, `Background And Queue Health`, `Crawl And Evaluation`, `Mailgun Delivery`, `Security And Tenant Isolation`, `Data Lifecycle And Restore`, `PostgreSQL And Redis`, and `Release Health`. Each has an owning role, current release annotation and links to the relevant recovery playbook.

Alerts are exact minimums:

| Severity | Condition | Evaluation | Response target |
| --- | --- | --- | --- |
| critical | suspected cross-Organization access, RLS bypass/context mismatch, secret disclosure, missing required partition causing event rejection, failed tombstone application, or irreversible integrity loss | any occurrence | acknowledge 5 minutes |
| critical | deletion primary/backup deadline missed or restore drill reads tombstoned data | any occurrence | acknowledge 5 minutes |
| high | Mailgun uncertainty/escalation row absent at five minutes | any occurrence | acknowledge 15 minutes |
| high | outbox oldest age over 60 seconds or scheduler heartbeat over 15 seconds | two consecutive samples | acknowledge 15 minutes |
| high | queue Redis eviction or queue memory over 90% | any/5 minutes | acknowledge 15 minutes |
| high | PostgreSQL unavailable, HA failover, connection use over 85%, or deadlock rate over 5/minute | 2 minutes | acknowledge 15 minutes |
| high | customer-facing 5xx over 5% or p95 over 500 ms | 10 minutes | acknowledge 15 minutes |
| medium | standard Evaluation completion p95 over five minutes | 15 minutes | acknowledge 30 minutes |
| medium | any fixed queue exceeds its catalogue latency | 10 minutes | acknowledge 30 minutes |
| medium | cache Redis unavailable or over 80% memory | 10 minutes | acknowledge 30 minutes |
| low | staging synthetic, dependency drift, future-partition lead or backup verification warning | one failed cycle | next business day |

Errors and security events are never sampled out. Provider acceptance uncertainty is neither success nor terminal failure in dashboards or SLO numerators.

## Backup And Restore

Protected data classes receive continuous PostgreSQL WAL protection plus daily encrypted backups. S3 protected objects use encrypted provider durability and inventory/checksum verification; temporary-processing and delivery-package bytes follow their exclusion/lifetime rules. KMS key backup/escrow and destruction controls are recorded separately from object retention.

At least every 90 elapsed days, restore automation creates an isolated environment with no provider-send credentials or public routes, restores PostgreSQL and protected objects to a selected point, applies every backup tombstone before any application read, verifies row/object digests and lineage, records measured RPO/RTO, and destroys the drill copy within 24 hours. Success requires RPO at most one hour and RTO at most four hours under the provisional quality target.

## Recovery Playbooks

Operational playbooks do not grant product mutation authority. They restore infrastructure or invoke an already-authorized application recovery command.

| Playbook | Detection and safe stop | Recovery | Verification and evidence |
| --- | --- | --- | --- |
| PostgreSQL failover | DB health/Heroku event; stop release and new high-cost starts | promote managed HA target; verify roles/RLS/extensions/partitions; resume one process class at a time | checksum, event/outbox continuity, RPO/RTO, synthetic reads and one staging-shaped command |
| PostgreSQL PITR | confirmed corruption/data loss; stop all writers and providers | restore isolated point, apply tombstones, verify, then cut over under incident approval | manifest/root hashes, lost-window report, lineage/audit continuity, RPO/RTO |
| Queue Redis loss | connection/eviction alert; stop scheduler enqueue | provision/recover queue Redis; republish persisted due actions and unconsumed outbox events | no duplicate product attempts, queue age recovery and consumption reconciliation |
| Cache Redis loss | degraded alert; keep correctness reads on PostgreSQL | flush/provision cache; warm only versioned projections | authorization and redaction tests; no product-state delta |
| Worker or scheduler stall | heartbeat/lease alert; stop affected formation | restart formation; PostgreSQL sweeper reclaims expired leases by checkpoint | lease-generation report, deadline/late-result audit, no duplicate side effect |
| Missing partition | release/readiness alert; block event-producing commands rather than lose event | create exact current/future partition under migration role and validate indexes/RLS | registry/partition reconciliation and test event in staging |
| S3/KMS outage | storage errors; stop affected upload/publication, not unrelated reads | restore dependency; resume same staged identity or exact owning retry | byte count/digest/KMS context, orphan multipart and manifest reconciliation |
| Secrets Manager outage | prepared-stage adapter dependency/timeout; no provider checkpoint | restore dependency; allow only the owning Integration-initialization/rotation retry schedule | exact ARN/VersionId digest binding, zero secret leakage and zero Mailgun submission before successful resolution |
| Mailgun acceptance uncertainty | WF-014 signal; automatic resend remains suppressed | read-only reconciliation; only authorized acknowledged replay may send again | exact provider event set, reconciliation result, escalation and replay acknowledgment |
| Credential compromise | security alert; stop new protected checkpoints | revoke/rotate through Credential lifecycle; invalidate bootstrap secret where applicable | version transition, provider test without customer side effect, access/log scan |
| RLS/tenant-isolation incident | any suspected cross-tenant result; stop all web/workers | preserve evidence, revoke affected sessions/credentials only through defined authority, patch and validate isolation before restart | cross-tenant query suite, access timeline, Incident/Investigation Audit Evidence |
| Bad application release | release-health alert; stop promotion | promote prior compatible slug; forward-fix schema if needed | health/synthetic/queue checks and release comparison |
| Deletion/tombstone failure | lifecycle deadline/invariant alert; prevent completion claim | resume exact manifest generation/attempt or authorized replay; never fabricate deletion | per-store outcomes, hold check, Deletion Evidence and backup deadline |

Project pause/resume/archive and standalone Session revocation are not operational recovery tools until Volume I defines their workflows.

## Capacity And Failure Exercises

Before production acceptance and at least quarterly thereafter, staging performs:

- 10× baseline stateless horizontal-scale rehearsal without architecture change;
- database pool saturation and deadlock injection;
- queue Redis loss after acknowledged enqueue;
- cache loss during authorization checks;
- worker death before/after every external checkpoint;
- Mailgun timeout/partial/crash/webhook-order/reconciliation simulation;
- S3/KMS timeout and checksum mismatch;
- Secrets Manager exact-version, timeout, access-denied, missing-version and digest-mismatch simulation;
- missing future partition and migration-lock contention;
- RLS cross-Organization fixture suite;
- PITR plus tombstone-before-read restore drill; and
- rollback from the current slug to the previous compatible release.

Exercise output is immutable restricted operational evidence containing release, configuration digests, start/end time, expected/actual result, RPO/RTO where applicable, gaps, owner and corrective reference. A failed critical exercise blocks production promotion.

## Implementation Readiness Gates

Deployment architecture is ready only when:

1. production topology and connection-pool preflight fit the selected managed plans;
2. queue/cache Redis separation and DB-backed loss recovery pass;
3. RLS, partition and role checks pass from empty and previous schemas;
4. private S3/KMS, exact-resource Secrets Manager and public-assets-only CDN policies pass automated inspection;
5. dormant and unsupported provider variables/packages/routes are absent;
6. Datadog receives redacted logs, metrics, traces, errors and synthetics with release correlation;
7. every critical alert routes to an owner and linked playbook;
8. backup/PITR/restore/tombstone drills meet provisional RPO/RTO;
9. CI promotes the identical staging slug with migration evidence; and
10. inherited Volume I blockers remain explicitly blocked rather than implemented by assumption.
