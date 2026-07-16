# Volume II Background Processing Architecture

## Status And Authority

- Status: Volume II implementation contract
- Behavioral baseline: Git tag `v1.3-volume-i-corrected`
- Runtime: Sidekiq `8.1.6`
- Timer, retry, lease, and idempotency authority: PostgreSQL
- Transport: dedicated Redis queue service

This document fixes how accepted Volume I asynchronous behavior is transported, scheduled, retried, recovered, and observed. It MUST NOT add a product attempt, retry, state, reason, notification, or side effect that Volume I does not authorize. Volume I remains authoritative when a workflow supplies a more specific deadline, retry schedule, race rule, or recovery command.

Authoritative behavioral sources are:

- [Volume I Workflow Specifications](../volume-i/WORKFLOW_SPECIFICATIONS.md)
- [Volume I Score And Evidence Model](../volume-i/SCORE_EVIDENCE_MODEL.md)
- [State Model](../016%20STATE_MODEL.md)
- [Error Model](../017%20ERROR_MODEL.md)
- [Data Lifecycle](../015%20DATA_LIFECYCLE.md)
- [Observability](../018%20OBSERVABILITY.md)

## Unresolved Inherited Event-Scope Contradiction

Volume I permits a pre-Organization Bootstrap Grant command and requires `BootstrapGrantIssued`, and it also permits an explicitly platform-wide Incident. Its Logical Event Envelope nevertheless requires an `organization_id` and defines that value as the event tenant. Volume II MUST NOT resolve this by inventing a platform Organization, supplying null, copying one event to multiple Organizations, or omitting the required event.

Until a controlled Volume I correction defines those two scopes:

- production publication of `BootstrapGrantIssued` and platform-wide Incident domain events is blocked;
- their required command and Audit Evidence records remain subject to the same unresolved scope issue;
- tenant-scoped events and Organization-scoped Incidents continue under this architecture; and
- no implementation may infer a wire or persistence representation for the unresolved cases.

This is a reported upstream ambiguity, not a Volume II implementation choice.

Volume I also lacks complete command workflows for Project pause, resume, and archive and for independent Session revocation. This background architecture therefore defines no timer, job, consumer, administrative replay, or incident action for those mutations. Session expiry and Session revocation that is already an atomic effect of an accepted Account or Organization workflow remain governed by those accepted contracts. Project schedule eligibility may observe an already-persisted Project state, but no worker in this catalogue may create an otherwise undefined Project transition.

## Processing Invariants

1. PostgreSQL is the source of truth for whether work exists, is due, is claimed, has started, may retry, is terminal, or is recoverable.
2. Redis and Sidekiq transport identifiers only. Loss, duplication, reordering, or delayed delivery cannot change a product result.
3. Every Sidekiq invocation receives scalar identifiers only. It MUST NOT receive serialized Active Record objects, domain payloads, provider response bodies, secret references, tokens, email addresses, URLs, or customer text.
4. Every handler begins by opening a database transaction, establishing the exact Organization context, and claiming the persisted work generation. A job that cannot claim exits successfully without a product write.
5. Every external call occurs outside a database transaction and only after its workflow-specific durable checkpoint.
6. A Sidekiq invocation is a transport delivery, not a product attempt. Only the owning domain record may allocate or increment a product attempt number.
7. Sidekiq automatic retry and Sidekiq Dead are disabled for all F1 jobs with `retry: false` and `dead: false`. PostgreSQL retry schedules and dead-letter records are exclusive authority.
8. No handler sleeps to wait for a due time or retry. It persists a timer and returns.
9. Sidekiq uniqueness, Redis locks, process mutexes, cache keys, and queue ordering are never correctness controls.
10. Shutdown, process loss, Redis failover, and duplicate enqueue are recovered from persisted leases and idempotency identities.

## Process And Queue Catalogue

The Sidekiq queue names and ownership are exact:

| Queue | Owning process type | Work admitted | Production concurrency per process | Maximum queue latency before alert |
| --- | --- | --- | ---: | ---: |
| `control` | `worker_control` | authorization-epoch effects, expiry commands, schedule decisions, entitlement checkpoints | 5 | 30 seconds |
| `delivery` | `worker_delivery` | in-app delivery, Mailgun attempts, authenticated provider events, reconciliation, notification escalation | 10 | 30 seconds |
| `pipeline` | `worker_pipeline` | ingestion, parsing, Evaluation orchestration, Checks, scoring, recommendations, Export generation | 5 | 60 seconds |
| `crawl` | `worker_crawl` | robots, sitemap and content fetch attempts plus Crawl terminalization | 10 | 60 seconds |
| `projection` | `worker_projection` | indexing, deterministic read projections, projection rebuilds | 5 | 120 seconds |
| `lifecycle` | `worker_lifecycle` | retention, key/object destruction, deletion manifests, backup tombstones, restore-drill records | 2 | 30 seconds for deadline work; 300 seconds otherwise |
| `maintenance` | `worker_control` | invariant sweepers, partition verification and non-product reconciliation | 2 of the `worker_control` concurrency slots | 60 seconds |

One process listens to exactly one queue except `worker_control`, which uses two Sidekiq capsules with fixed concurrency of three for `control` and two for `maintenance`. A process MUST NOT use weighted queue polling. Scaling changes process counts, never queue ownership or per-process concurrency without an architecture change.

`scheduler` is a separate singleton process and is not a Sidekiq worker. It polls PostgreSQL and enqueues due identities. A PostgreSQL singleton lease, not Heroku process count, prevents two active scheduler leaders.

## Sidekiq Argument Envelope

Every job argument is a JSON object with exactly:

| Field | Rule |
| --- | --- |
| `schema_version` | exact string `1.0` |
| `organization_id` | UUID string; null only for an already-authorized platform-control job that does not produce the unresolved event forms above |
| `work_type` | One value from the job catalogue |
| `work_id` | UUID of the restricted Work Dispatch Binding created for this exact enqueue/claim; it is a locator, never the product/attempt/event identity |
| `product_generation` | nonnegative integer persisted by the owning product/checkpoint record; zero only when that work type has no product generation |
| `claim_generation` | positive integer copied from the work row's successful PostgreSQL transport claim; a stale value cannot claim |
| `correlation_id` | UUID copied from the persisted work |
| `causation_id` | UUID copied from the persisted work's Domain Event, ScheduledAction or command cause |

Unknown or extra fields cause the invocation to record restricted transport-contract telemetry and exit without claiming work. The handler reloads all policy, permission, tenant, Project, deadline, attempt, and payload data from PostgreSQL. Sidekiq JIDs are diagnostic only and never enter a domain identity, result, event, or idempotency preimage.

## Durable Scheduling

### Timer authority

`scheduled_actions` is the sole physical timer authority. A domain table may expose `next_due_at` for an authorized query, but that field MUST reference or be transactionally derived from one scheduled action and MUST NOT be independently polled.

Each scheduled action stores:

- action ID and schema version;
- Organization and nullable Project;
- exact `action_kind`, target type and target ID;
- product generation and schedule generation;
- policy ID, version, and content digest where applicable;
- due instant and optional not-before instant;
- immutable identity preimage and SHA-256;
- status `pending`, `claimed`, `dispatched`, `canceled`, `completed`, or `quarantined`;
- claim owner, claim generation, claimed time, lease expiry, dispatch time, completion time, and reason;
- correlation and causation IDs; and
- the immutable references needed by the owning Volume I contract, never secret or payload bytes.

One unique row exists for the complete action identity. Exact creation replay returns it. A same digest with a different retained preimage does not merge.

### Due-time claim

The scheduler performs this algorithm using PostgreSQL time:

1. Acquire or renew the singleton scheduler lease for 15 seconds.
2. Start a transaction at `READ COMMITTED`.
3. Read at most 100 eligible rows using `ORDER BY due_at, id FOR UPDATE SKIP LOCKED` where status is `pending`, `due_at <= transaction_timestamp()`, and `not_before_at` is null or not later than that same timestamp.
4. Set each row to `claimed`, increment `claim_generation`, set a 30-second claim lease, create/exact-replay the restricted Work Dispatch Binding for the registry-selected target, and commit.
5. Enqueue the scalar Sidekiq argument envelope with `work_id` equal to that binding ID and `claim_generation` equal to the claimed action's generation to the action's fixed queue.
6. After Redis acknowledges enqueue, start a new transaction and set `status=dispatched` and `dispatched_at` only if the same scheduler owner and claim generation still own the row. If the receiving job has already transferred the claim, this acknowledgement is an idempotent no-op. An enqueue failure may return the row to `pending` only while that same scheduler owner and generation still hold it and `dispatched_at` is null; the action identity is unchanged and the infrastructure dispatch schedule below applies.

On receipt, the job locks the ScheduledAction and accepts only `claimed` or `dispatched` state with the argument's exact claim generation. In one transaction it compares and swaps the claim owner from the named scheduler process to its own worker process, sets `status=dispatched` and `dispatched_at` if not already set, and renews the 30-second lease before touching product work. A duplicate invocation that finds the same worker ownership resumes the same claim; any other owner, generation, pending state, terminal state, or expired-and-reclaimed generation exits without product work. This transfer is valid both before and after the scheduler's acknowledgement transaction, eliminating the enqueue/mark race. The scheduler acknowledgement cannot overwrite worker ownership, and a response-lost enqueue cannot be reverted after worker transfer.

The receiving job then rechecks the product deadline and race at transaction time. Queue arrival time never decides a Volume I equality race.

### Action-kind catalogue

The following `action_kind` values are exhaustive for the accepted baseline:

| Action kind | Queue | Owning Volume I behavior |
| --- | --- | --- |
| `bootstrap_grant_expire` | `control` | Grant expiry; event publication remains subject to the event-scope ambiguity |
| `session_expire` | `control` | idle or absolute Session expiry |
| `invitation_expire` | `control` | pending-approval or active Invitation expiry |
| `role_assignment_expire` | `control` | approval or active Assignment expiry |
| `source_scope_request_expire` | `control` | pending scope-request expiry |
| `verification_observation_slot` | `control` | exact automated Verification Request slot |
| `verification_request_expire` | `control` | 24-hour challenge expiry |
| `verification_material_destroy` | `lifecycle` | key/ciphertext destruction within 60 seconds |
| `crawl_dispatch` | `crawl` | admitted queued Crawl start |
| `crawl_fetch_due` | `crawl` | one selected persisted fetch attempt, including an immediate first attempt |
| `crawl_terminal_deadline` | `crawl` | exact 60-minute terminal checkpoint |
| `ingestion_attempt_due` | `pipeline` | initial or declared 30/120-second retry |
| `parsing_attempt_due` | `pipeline` | initial or declared 30/120-second retry |
| `indexing_attempt_due` | `projection` | initial or declared 30/120-second retry |
| `check_attempt_due` | `pipeline` | initial or one-second declared retry |
| `evaluation_stage_advance` | `pipeline` | immediate next sealed Evaluation stage checkpoint |
| `evaluation_deadline` | `pipeline` | persisted Evaluation stage deadline |
| `score_recalculation_due` | `pipeline` | immediate idempotent recalculation after accepted adjudication/Evidence-validation invalidation |
| `adjudication_due` | `control` | case due decision/reminder checkpoint |
| `ai_generation_deadline` | `pipeline` | dormant AIResponse deadline; no row is created without approved artifacts |
| `ai_validation_deadline` | `pipeline` | dormant Citation/validation deadline |
| `ai_publication_expire` | `control` | dormant validated-response expiry |
| `reassessment_slot` | `control` | exact anchored Project schedule slot |
| `notification_delivery_attempt_due` | `delivery` | initial or definitive-nonacceptance Delivery attempt |
| `notification_reconciliation_due` | `delivery` | immediate, 1-, 5-, or 30-minute read-only reconciliation |
| `notification_escalation_due` | `delivery` | five-minute escalation deadline |
| `credential_initialization_retry` | `delivery` | one-second Mailgun initialization retry within the same attempt |
| `credential_expire` | `control` | Credential expiry checkpoint |
| `entitlement_lease_expire` | `control` | reservation expiry/release decision |
| `export_generate` | `pipeline` | authorized asynchronous generation |
| `export_expire` | `control` | frozen/current-policy retrieval expiry |
| `export_policy_reevaluate` | `control` | idempotent reevaluation after policy contraction |
| `closure_request_expire` | `control` | 24-hour Closure Request expiry |
| `organization_closure_execute` | `lifecycle` | due-now tenant lifecycle execution after committed distinct approval |
| `support_session_expire` | `control` | pending or four-hour active expiry |
| `incident_restoration_observe` | `control` | exact second five-minute observation |
| `investigation_input_collect` | `control` | immediate next bounded page for one frozen WF-018 required input; creation/execution remains blocked by event-scope ambiguity |
| `provider_event_consume` | `delivery` | immediate processing of one authenticated persisted Mailgun provider event |
| `projection_repair_due` | `projection` | one invariant-sweep-authorized current-score/action-queue pointer repair |
| `transport_lease_sweep_due` | `maintenance` | periodic expired-claim and Redis-quarantine recovery sweep |
| `running_work_sweep_due` | `maintenance` | periodic work/state/deadline/Organization/policy invariant sweep |
| `entitlement_invariant_sweep_due` | `maintenance` | periodic Reservation action/terminal-state invariant sweep |
| `staged_object_invariant_sweep_due` | `maintenance` | periodic expired/missing temporary-object authority sweep |
| `export_invariant_sweep_due` | `maintenance` | periodic generation-lease and effective-expiry invariant sweep |
| `mailgun_uncertainty_sweep_due` | `maintenance` | periodic reconciliation/escalation-presence sweep with no send authority |
| `deletion_tombstone_invariant_sweep_due` | `maintenance` | periodic deletion/hold/deadline/tombstone invariant sweep |
| `evidence_retention_warning` | `lifecycle` | one warning 30 days before payload maximum |
| `lifecycle_deletion_start` | `lifecycle` | start within 60 seconds of acceptance |
| `lifecycle_deletion_attempt_due` | `lifecycle` | initial or one five-minute dependency retry |
| `lifecycle_deletion_deadline` | `lifecycle` | primary or backup deadline escalation |
| `backup_tombstone_verify` | `lifecycle` | restore/tombstone verification |
| `restore_drill_due` | `lifecycle` | at-least-90-day restore drill |
| `partition_maintenance_due` | `maintenance` | create/verify required future partitions |

### Action-to-work dispatch registry

Every asynchronous job other than `event_consume` is reachable through exactly one ScheduledAction, including work due immediately. The action's `target_id` is the direct claim-owner row ID for a specialized job. The registry is closed:

| Action kind | Enqueued `work_type` | Direct claim owner |
| --- | --- | --- |
| `bootstrap_grant_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `session_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `invitation_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `role_assignment_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `source_scope_request_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `verification_observation_slot` | `verification_observe` | Verification Attempt |
| `verification_request_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `verification_material_destroy` | `object_destroy` | `work_executions` object-destruction identity |
| `crawl_dispatch` | `crawl_orchestrate` | `work_executions` Crawl/generation identity |
| `crawl_fetch_due` | `crawl_fetch` | Fetch Attempt |
| `crawl_terminal_deadline` | `crawl_orchestrate` | `work_executions` Crawl/deadline identity |
| `ingestion_attempt_due` | `ingest` | Ingestion Attempt |
| `parsing_attempt_due` | `parse` | Parsing Attempt |
| `indexing_attempt_due` | `index` | Indexing Attempt |
| `check_attempt_due` | `check_execute` | Check Attempt |
| `evaluation_stage_advance` | stage registry's exact work type | Evaluation Stage Checkpoint or its declared Check Attempt child |
| `evaluation_deadline` | `evaluation_advance` | Evaluation Stage Checkpoint |
| `score_recalculation_due` | `score_publish` | `work_executions` Project/current-projection/source-input identity |
| `adjudication_due` | `scheduled_action_dispatch` | ScheduledAction |
| `ai_generation_deadline` | `recommendation_generate` | `work_executions` AI generation identity; dormant |
| `ai_validation_deadline` | `recommendation_generate` | `work_executions` AI validation identity; dormant |
| `ai_publication_expire` | `scheduled_action_dispatch` | ScheduledAction; dormant |
| `reassessment_slot` | `scheduled_action_dispatch` | ScheduledAction with persisted decision/start checkpoint |
| `notification_delivery_attempt_due` | `delivery_execute` | Delivery Attempt |
| `notification_reconciliation_due` | `delivery_reconcile` | Delivery Reconciliation |
| `notification_escalation_due` | `scheduled_action_dispatch` | ScheduledAction |
| `credential_initialization_retry` | `delivery_execute` | same Delivery Attempt still at `prepared` |
| `credential_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `entitlement_lease_expire` | `entitlement_reconcile` | `work_executions` Reservation/generation identity |
| `export_generate` | `export_generate` | `work_executions` Export/generation/manifest identity |
| `export_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `export_policy_reevaluate` | `scheduled_action_dispatch` | ScheduledAction |
| `closure_request_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `organization_closure_execute` | `scheduled_action_dispatch` | ScheduledAction |
| `support_session_expire` | `scheduled_action_dispatch` | ScheduledAction |
| `incident_restoration_observe` | `incident_observe` | `work_executions` Incident/step/generation identity |
| `investigation_input_collect` | `investigation_collect` | Investigation Collection Checkpoint |
| `provider_event_consume` | `provider_event_consume` | `work_executions` provider-event identity |
| `projection_repair_due` | `projection_build` | `work_executions` projection/source-version identity |
| `transport_lease_sweep_due` | `invariant_sweep` | `work_executions` sweep-type/anchored-slot identity |
| `running_work_sweep_due` | `invariant_sweep` | `work_executions` sweep-type/anchored-slot identity |
| `entitlement_invariant_sweep_due` | `invariant_sweep` | `work_executions` sweep-type/anchored-slot identity |
| `staged_object_invariant_sweep_due` | `invariant_sweep` | `work_executions` sweep-type/anchored-slot identity |
| `export_invariant_sweep_due` | `invariant_sweep` | `work_executions` sweep-type/anchored-slot identity |
| `mailgun_uncertainty_sweep_due` | `invariant_sweep` | `work_executions` sweep-type/anchored-slot identity |
| `deletion_tombstone_invariant_sweep_due` | `invariant_sweep` | `work_executions` sweep-type/anchored-slot identity |
| `evidence_retention_warning` | `scheduled_action_dispatch` | ScheduledAction |
| `lifecycle_deletion_start` | `lifecycle_delete` | `work_executions` deletion/entry/generation identity |
| `lifecycle_deletion_attempt_due` | `lifecycle_delete` | same deletion work identity |
| `lifecycle_deletion_deadline` | `lifecycle_delete` | `work_executions` deadline identity |
| `backup_tombstone_verify` | `lifecycle_delete` | `work_executions` tombstone identity |
| `restore_drill_due` | `invariant_sweep` | `work_executions` restore-drill identity |
| `partition_maintenance_due` | `partition_maintain` | `work_executions` table/month identity |

The scheduler locks the ScheduledAction, validates this mapping and the exact ready target row, increments the action and target claim generations independently, and creates the Work Dispatch Binding in one transaction. Envelope `work_id` is always that binding's UUID. The binding retains the source ScheduledAction ID/generation and, for a specialized type, the direct target table/row/generation; a generic `scheduled_action_dispatch` binds the action as both source and target. The receiver's restricted claim function resolves the binding and atomically transfers the action and direct owner to the worker, or transfers neither; completion terminalizes both. Enqueue failure releases only the still-scheduler-owned action/target generations. No worker scans a domain/attempt table, and no producer directly pushes an immediate job to Redis.

`evaluation_stage_advance` selects its work type only from the exact stage registry below; an inconsistent stage/action tuple quarantines as `scheduled_work_mapping_mismatch`. Every other action has one literal work type. A specialized target missing, already terminal, wrong-Organization, wrong generation or not byte-equal to the action identity quarantines before enqueue and performs no product work.

Absence of an action kind is not permission to schedule work directly in Redis. Adding a kind is an implementation-architecture change and, if customer-visible timing or behavior changes, first requires controlled Volume I change.

## Outbox And Event Consumption

Every admitted domain event commits with the authoritative state change. An outbox row is a required-consumer route, not a second event copy: its identity is unique `(event_id,consumer_name)`, and an event with no registered consumer has no outbox row. Application code MUST NOT call Sidekiq from a command transaction or an Active Record callback.

### Closed consumer registry

The accepted baseline has exactly one domain-event consumer:

| Consumer | Queue | Route creation predicate | Product effect |
| --- | --- | --- | --- |
| `notification_route_v1` | `delivery` | At event commit, the exact event type and major version is a route in the effective Notification Policy and the event contains its complete `notification_context_v1`. This includes every mandatory baseline route in Volume I and only then-active optional informational routes. | Apply WF-014 once using the event, captured policy/template versions and route context; either create/replay its Notification/Deliveries or record the exact invalid-event failure/escalation. |

The producer evaluates that predicate in its command transaction and inserts the route row with the event and captured Notification Policy identity. The consumer never discovers a route from naming convention, free text, recipient guess, current policy, or role label. All other admitted event types have zero consumer routes. Pipeline advancement, search/index work, deterministic projection rebuild and timers use an explicitly persisted ScheduledAction or `work_executions` identity created by their owning operation; they are not inferred from a domain event. The baseline frontend has no asynchronous UI-invalidation transport. The unresolved pretenant/platform/cross-Organization scope classes emit no physical event or route until `UPSTREAM-V1-EVENT-SCOPE-001` is corrected.

Adding another consumer, queue, or route predicate requires a Volume II architecture revision; it first requires controlled Volume I change when it alters customer-visible behavior. There is no wildcard, default, runtime-discovered, environment-enabled or “owning queue” consumer.

### Route dispatch and consumption

The scheduler scans route rows ordered by `available_at,id`. For each row it:

1. locks an eligible `pending` row, or a `published` row lacking its consumption for at least 60 seconds, using `FOR UPDATE SKIP LOCKED` and PostgreSQL time;
2. sets `claimed`, increments `claim_generation`, records its scheduler owner and a 30-second lease, and commits;
3. creates/exact-replays a Work Dispatch Binding to that outbox route and enqueues one `event_consume` envelope to the fixed `delivery` queue with `work_id` equal to the binding ID and the route's exact claim generation; and
4. after Redis acknowledgement, marks `published` only if that scheduler owner/generation still holds the route. Enqueue failure returns it to `pending` only under the same owner/generation and only before a receiver transfer.

The receiving job resolves the binding, then reloads its fixed route, event and consumer name from PostgreSQL. It uses the same scheduler-to-worker compare-and-swap handoff as ScheduledAction dispatch, so arrival before acknowledgement is valid and acknowledgement cannot overwrite worker ownership. A different/terminal binding or route generation exits. In one transaction `notification_route_v1` performs its idempotent product writes, inserts unique `(consumer_name,event_id)` consumption, and sets the route `consumed`; a uniqueness loss reloads that stored result. Unknown major or invalid required shape enters `event_dead_letters`, sets the route `quarantined`, and performs no Notification product write.

This is deliberate at-least-once transport. A `published` route without its exact consumption is eligible for the same-row republish after 60 seconds. Aggregate event order is reconstructed from aggregate version; if this consumer observes version `n+1` before a routed predecessor `n`, it records `predecessor_event_unavailable`, applies the infrastructure dispatch retry and performs no product write. An unrouted predecessor is not awaited.

## Work Claims And Leases

Every asynchronous mutable work row has:

- `claim_owner` as a random process-instance UUID;
- positive `claim_generation`;
- `claimed_at` and `lease_expires_at` from PostgreSQL;
- nullable `last_heartbeat_at`; and
- an exact state and product attempt generation.

Lease duration is `max(30 seconds, product_attempt_deadline - claim_time + 30 seconds)` capped at 15 minutes. A handler whose work can legitimately exceed 15 minutes divides it into checkpointed members; no individual claim exceeds the cap. Heartbeat interval is one third of the lease duration, rounded down to whole seconds and bounded from 5 through 30 seconds.

A heartbeat transaction verifies owner, claim generation, nonterminal state, current authorization/policy checkpoint, and unexpired lease before extending from database time. It never increments a product state version, emits a domain event, or changes a product deadline.

At lease expiry, a sweeper locks the row and applies one of these exhaustive results:

- work not yet past an external-submission checkpoint: release the transport claim and enqueue the same product attempt identity;
- Mailgun at or after `submission_started`: apply WF-014 `acceptance_unknown` and never resubmit;
- another provider effect at or after its durable checkpoint: use that adapter contract's explicit uncertainty or reconciliation result;
- a pure deterministic computation with no committed terminal result: release the transport claim and recompute the same product attempt identity;
- a Volume I attempt deadline already won: persist that workflow's exact timeout outcome; or
- an unclassifiable checkpoint: quarantine with `work_checkpoint_unmapped`, perform no side effect, and raise a critical integrity alert.

Reclaim increments only `claim_generation`. It does not increment product attempt, retry, replay, reservation, Delivery, or recovery generation.

## Retry Ownership

### Product retries

Product retry schedules are exactly those in Volume I. A handler persists the failed attempt, creates the unique next `scheduled_action`, and returns. Provider SDK, HTTP client, Active Job, Sidekiq, Redis, and database adapters MUST NOT add a retry.

A PostgreSQL deadlock or serialization failure before commit follows the Rails architecture's one initial execution plus at most two same-command transaction re-executions after 10 and 50 milliseconds, only while the original workflow deadline remains strictly unexpired. Each re-execution reuses the same command/idempotency/advisory identity, reloads every value, and creates no product attempt, job retry, event or external effect. Exhaustion or deadline equality maps once to the owning Volume I dependency/concurrency result; no new top-level command is fabricated.

### Infrastructure dispatch retries

Failure to enqueue an already-persisted identity uses attempts at 1, 5, 30, 120, and 600 elapsed seconds after the preceding failure. Attempt six quarantines the transport record with `redis_dispatch_exhausted` and raises a high alert. There is no human, console, Rake, Sidekiq-Web or product replay command for transport quarantine.

The scheduler persists a queue-transport health sample every five seconds using one TLS-authenticated Redis `PING`; the client has a one-second deadline and zero retry. Queue transport becomes `healthy` only after three consecutive persisted successes from the elected scheduler, each at least five seconds apart, with no intervening failure. On the next `invariant_sweep`, at most 100 ScheduledActions quarantined solely for `redis_dispatch_exhausted` are returned to `pending` in `(due_at,id)` order and at most 100 matching outbox routes are returned in `(available_at,id)` order; their dispatch-attempt counter resets and `transport_recovery_generation` increments. Their action/event, product generation, due/available time, policy, idempotency preimage and product attempt remain unchanged. A later Redis failure persists a failed sample and restarts the three-success gate. Other quarantine reasons never enter this path.

Event-consumer dependency failure uses the same infrastructure schedule. Unknown schema, invalid event contract, tenant mismatch, and deterministic consumer integrity failure do not retry and enter `event_dead_letters` immediately.

## Domain Dead Letters And Replay

The authoritative dead-letter location is exact:

| Work | Dead-letter authority | Recovery |
| --- | --- | --- |
| Ingestion | `ingestion_jobs.state=dead_letter` | authorized `ingestion.recover` creates a new replay generation |
| Parsing | `parsing_jobs.state=dead_letter` | authorized `parsing.recover` creates a new replay generation |
| Indexing | `indexing_jobs.state=dead_letter` | authorized `indexing.recover` creates a new replay generation |
| Event consumption | `event_dead_letters` | terminal baseline quarantine; alert and preserve exact event/consumer/reason for a reviewed future architecture correction, with no replay path |
| Scheduled/outbox transport | route/action `status=quarantined` with `redis_dispatch_exhausted` | automatic same-identity recovery only after the three-sample queue-health gate; every other reason remains terminal quarantine |
| Notification | Delivery terminal or uncertain state | only WF-014 reconciliation or authorized replay |
| Export | `exports.state=failed` | authorized `export.retry` with the required new approval/reservation |
| Lifecycle deletion | `lifecycle_deletion_jobs.state=failed` | authorized deletion retry generation |
| Incident step | failed step attempt | new idempotent diagnostic attempt or separately authorized remediation |

No database administrator, Sidekiq Web action, Redis operation, Rake task or console retry may bypass these recoveries. Sidekiq Web is read-only in production. Event dead-letter replay and nontransport ScheduledAction replay are absent from the baseline; defining either requires an explicit Volume II revision and controlled Volume I change when delayed execution is customer-visible.

## Job Catalogue

| `work_type` | Queue | Handler responsibility | Durable idempotency authority |
| --- | --- | --- | --- |
| `event_consume` | `delivery` | run the route row's fixed `notification_route_v1` consumer | outbox route unique `(event_id,consumer_name)` plus consumption row |
| `scheduled_action_dispatch` | action queue | execute one claimed due action | scheduled-action full identity |
| `verification_observe` | `control` | perform one reserved DNS/HTTP observation | request/slot or on-demand attempt identity |
| `crawl_orchestrate` | `crawl` | advance canonical dequeue/checkpoint order | Crawl/generation and candidate order |
| `crawl_fetch` | `crawl` | perform one candidate attempt | candidate/attempt identity |
| `ingest` | `pipeline` | validate staged body and create Evidence | IngestionJob/generation/attempt |
| `parse` | `pipeline` | create one immutable Parsed Artifact | ParsingJob/generation/attempt |
| `index` | `projection` | update one retrieval projection and receipt | IndexingJob/generation/attempt |
| `evaluation_advance` | `pipeline` | advance one sealed Evaluation stage | Evaluation/stage/input hash |
| `check_execute` | `pipeline` | compute one expected Result slot | applicability slot/attempt |
| `score_publish` | `pipeline` | serialize one Snapshot calculation/publication | Project calculation sequence/input hash |
| `recommendation_generate` | `pipeline` | create deterministic Artifact or governed dormant AI attempt | family/version/input hash |
| `projection_build` | `projection` | compare-and-swap repair only `current_score_v1` or `action_queue_v1` after an invariant-sweep mismatch | projection name/resource, expected pointer version and source digest |
| `delivery_execute` | `delivery` | execute one in-app or Mailgun attempt | Delivery/generation/attempt/request digest |
| `delivery_reconcile` | `delivery` | perform read-only provider evidence query | Delivery/generation/sequence |
| `provider_event_consume` | `delivery` | authenticate/deduplicate/reduce provider event | Integration/provider event ID |
| `entitlement_reconcile` | `control` | expire/release/commit persisted reservation | reservation/generation |
| `export_generate` | `pipeline` | render, validate and publish one package | Export/generation/manifest hash |
| `incident_observe` | `control` | execute named diagnostic observation | Incident/playbook/step/generation |
| `investigation_collect` | `control` | collect one bounded page for one frozen required input under its exact Organization Support Session | Investigation/required-input/query-hash/page-cursor generation |
| `lifecycle_delete` | `lifecycle` | execute one manifest checkpoint | deletion job/entry/attempt generation |
| `object_destroy` | `lifecycle` | destroy one authorized object/key | manifest entry/generation |
| `partition_maintain` | `maintenance` | create/verify future append-only partitions | month/table identity |
| `invariant_sweep` | `maintenance` | recover expired transport leases and detect stuck state | sweeper/type/cursor identity |

Handlers are context-qualified under the source layout in [Rails Application Architecture](../../architecture/RAILS_APPLICATION_ARCHITECTURE.md). The table fixes responsibilities and identities; it does not require one class to combine unrelated context logic.

### Job-to-application operation registry

Each job invokes only these registered operations. Multiple names in one row are a persisted checkpoint sequence: after every committed operation the job reloads the checkpoint, so process loss resumes at the first uncommitted step and never repeats a provider effect.

| Work type | Permitted Application operations or technical terminal action |
| --- | --- |
| `event_consume` | `CreateNotification` exactly once for `notification_route_v1`; invalid contract instead records the required escalation/dead letter |
| `scheduled_action_dispatch` | the exact action-kind table below; no arbitrary command discriminator |
| `verification_observe` | `CompleteVerificationAttempt` or `FailVerificationRequest` for the already-reserved attempt; it cannot create a new Verification Request |
| `crawl_orchestrate` | `StartCrawl`, `CompleteCrawl`, `FailCrawl`, or `CancelCrawl`, selected solely from persisted Crawl/deadline state |
| `crawl_fetch` | `RecordFetchAttempt`; its terminal transaction creates the exact ingestion or next-frontier action |
| `ingest` | `CompleteIngestion` or `FailIngestion` |
| `parse` | `CompleteParsing` or `FailParsing` |
| `index` | `CompleteIndexing` or `FailIndexing` |
| `evaluation_advance` | the operation fixed by the Evaluation stage registry below; terminal initial-Evaluation fatal/deadline outcome uses `FailEvaluation`, while a reassessment terminal uses `FailReassessment` as the one multi-root terminal operation |
| `check_execute` | `ExecuteChecks` for the one declared result-key attempt only |
| `score_publish` | Evaluation stage: `CalculateScore`, then `PublishScore` or the reassessment publication branch. `score_recalculation_due`: `RecalculateScore` only, which owns its exact unavailable/new-snapshot publication transaction. |
| `recommendation_generate` | deterministic `GenerateRecommendation`, then `PublishRecommendation` or `SuppressRecommendation`; dormant governed AI alone may use `RecordAiResponse` and `ValidateAiResponse` at its named checkpoints |
| `projection_build` | no product operation; byte-equal compare-and-swap repair of the two registered pointers only |
| `delivery_execute` | `DispatchDeliveryAttempt`; prepared-stage initialization retry resumes that same operation/attempt |
| `delivery_reconcile` | `ReconcileDelivery` only; it cannot send |
| `provider_event_consume` | `RecordProviderEvent` only |
| `entitlement_reconcile` | exactly one of `HeartbeatEntitlement`, `CommitEntitlement`, `ReleaseEntitlement` from persisted Reservation state/deadline |
| `export_generate` | `StartExportGeneration`, then `CompleteExportGeneration` or `FailExportGeneration` |
| `incident_observe` | `ObserveRestoration` for the persisted playbook/observation identity |
| `investigation_collect` | `CollectInvestigationInput` for one registered page checkpoint |
| `lifecycle_delete` | `StartLifecycleDeletion`, `ExecuteLifecycleDeletionCheckpoint`, `FailLifecycleDeletion`, or `VerifyBackupTombstone` as fixed by action kind/checkpoint |
| `object_destroy` | DataLifecycle's exact manifest-authorized object/key destruction checkpoint; no aggregate transition outside its owning deletion/material contract |
| `partition_maintain` | technical create/verify for the action's allowlisted table/month only; no product row mutation |
| `invariant_sweep` | the named mechanical invariant checks/recoveries in this document only; it may create `projection_repair_due` but cannot invoke a customer command |

The generic `scheduled_action_dispatch` mapping is exhaustive:

| Action kind | Operation |
| --- | --- |
| `bootstrap_grant_expire` | `ExpireBootstrapGrant` |
| `session_expire` | `ExpireSession` |
| `invitation_expire` | `ExpireInvitation` |
| `role_assignment_expire` | `ExpireRoleAssignment`; ordinary nonblocking expiry only, while the last-OrganizationAdmin block branch is unavailable under `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` |
| `source_scope_request_expire` | `ExpireSourceScopeChange` |
| `verification_request_expire` | `ExpireVerificationRequest` |
| `adjudication_due` | `MarkAdjudicationOverdue`; the checkpoint's persisted sequence also determines the already-defined reminder/critical emission, never an adjudication decision |
| `ai_publication_expire` | `ExpireAiResponse`; dormant |
| `reassessment_slot` | reserved mapping only; insertion and dispatch are unavailable under `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`; after correction it invokes `EvaluateReassessmentSlot`, then `StartReassessment` only when that committed decision is `admitted` |
| `notification_escalation_due` | `EscalateNotification` |
| `credential_expire` | `ExpireCredential` |
| `export_expire` | `ExpireExport` |
| `export_policy_reevaluate` | `ReevaluateExportPolicy` |
| `closure_request_expire` | `ExpireOrganizationClosure` |
| `organization_closure_execute` | `ExecuteOrganizationClosure`; `DecideOrganizationClosure(approve)` creates this due-now action atomically, and the human decision never executes closure inline |
| `support_session_expire` | `ExpireSupportSession` |
| `evidence_retention_warning` | `RecordEvidenceRetentionWarning` |

An action mapped to a specialized work type cannot enter this generic table. A generic action not present here is `scheduled_work_mapping_mismatch` and quarantines; it is never dispatched by method-name reflection.

`credential_rotation_retry` is deliberately absent. No rotation ScheduledAction or Integration Attempt may be created while `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` leaves the initiating token/material binding undefined; the frozen retry times do not make an unreachable rotation physically executable.

No `reassessment_slot` row may be inserted or dispatched while `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` leaves the required trigger event's occurrence and affected record undefined. A `role_assignment_expire` action may terminalize an ordinary accepted expiry, but when the last-OrganizationAdmin invariant blocks expiry it MUST remain uncompleted and enter technical quarantine without product mutation, Domain Event or guessed Notification while `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` is unresolved; replay from quarantine is unavailable. This fail-closed transport state is not a product retry decision.

No Document-quarantine or Document-retirement action kind, work type, lifecycle branch or inferred parser consequence exists while `UPSTREAM-V1-DOCUMENT-LIFECYCLE-012` is unresolved. Parsing/indexing failure leaves the Document at its last accepted state exactly as Volume I specifies.

`UPSTREAM-V1-ISSUE-COLLISION-013` applies only to the Issue-fingerprint same-hash/different-preimage branch. Check Result key collision keeps its accepted fail-closed execution and telemetry. On the blocked Issue branch, `execute_check_result` may not commit the disputed second-Issue outcome or `IssueFingerprintCollision`; `seal_issue_set` and all later Evaluation stages for that Evaluation remain undispatched, and the owning checkpoint is technically quarantined without a product Issue, Issue Set, score, Recommendation, history publication or guessed Evaluation terminal event. Quarantine is only a fail-closed transport gate and cannot be replayed until controlled Volume I correction defines second-Issue persistence and Evaluation continuation/failure.

### Evaluation stage registry

The nine AI/Evaluation topology stages are persisted in `evaluation_stage_checkpoints` and transported through only the catalogue work types below. A stage claim is infrastructure ownership, not another Evaluation or product attempt.

| Stage kind | Work type / queue | Maximum one-claim execution | Completion/recovery boundary |
| --- | --- | ---: | --- |
| `seal_input_snapshot` | `evaluation_advance` / `pipeline` | 30 seconds | immutable snapshot/blocked result transaction; process loss recomputes same input identity |
| `materialize_applicability` | `evaluation_advance` / `pipeline` | 30 seconds | complete ordered applicability membership and digest |
| `materialize_check_result_keys` | `evaluation_advance` / `pipeline` | 30 seconds | complete ordered slot-key membership and digest |
| `execute_check_result` | `check_execute` / `pipeline` | five seconds per child process plus five seconds parent/checkpoint budget | child `check_attempts` own the exact Volume I retry; stage completes only when every expected key is terminal |
| `seal_issue_set` | `evaluation_advance` / `pipeline` | 30 seconds | immutable Issue Set and derivation transaction |
| `resolve_adjudication_gate` | `evaluation_advance` / `pipeline` | 30 seconds | either records gate-ready or returns without blocking until the accepted adjudication event/deadline wakes the same stage identity |
| `calculate_score` | `score_publish` / `pipeline` | 30 seconds | immutable proposed ScoreSnapshot/input digest; no pointer changes yet |
| `publish_initial_or_return_reassessment_stage` | `score_publish` / `pipeline` | 30 seconds | exact atomic publication or reassessment-stage result transaction |
| `refresh_recommendations_and_priority` | `recommendation_generate` / `pipeline` | 60 seconds | deterministic Artifact/priority membership and current-pointer transaction; dormant AI path cannot be reached without approved artifacts |

The stage-to-operation mapping is exact: `seal_input_snapshot` invokes `SealEvaluationInputs`; `materialize_applicability` invokes `MaterializeCheckApplicability`; `materialize_check_result_keys` invokes `MaterializeCheckResultKeys`; each `execute_check_result` child invokes `ExecuteChecks` for only its declared key; `seal_issue_set` invokes `SealIssueSet`; `resolve_adjudication_gate` invokes `ResolveAdjudicationGate`; `calculate_score` invokes `CalculateScore`; `publish_initial_or_return_reassessment_stage` invokes `PublishScore` for an initial Evaluation or `PublishReassessment` for reassessment; and `refresh_recommendations_and_priority` invokes deterministic `GenerateRecommendation` followed by `PublishActionQueue`. No stage selects an operation from mutable configuration or method-name reflection.

The claim ceiling cannot extend a Volume I stage/workflow deadline. At equality the product deadline wins. Pure work lost before its completion transaction releases/reclaims the same checkpoint and input digest under the lease rules; committed completion is a duplicate no-op. An input digest or stage generation mismatch quarantines as `evaluation_stage_input_mismatch` and cannot be repaired by accepting a late result. The next stage row and its due-now ScheduledAction are created only in the preceding completion transaction.

### Investigation collection registry

When `UPSTREAM-V1-EVENT-SCOPE-001` is corrected, `OpenInvestigation` atomically freezes the ordered required-input plan and creates one `investigation_collection_checkpoints` row plus one due-now `investigation_input_collect` action for every required input. Until then, Open/collection/report/closure execution remains unavailable because Volume II cannot persist the required cross-Organization events differently.

Each checkpoint identity is `(investigation_id,organization_id,required_input_id,query_sha256,page_sequence)`. Page 1 has no cursor. A nonterminal page returns at most 1,000 records and at most 8 MiB of canonical bytes, ordered by `(occurred_at,event_id)`; it persists the last tuple as the exclusive next-page cursor and creates exactly one due-now action for the next sequence. The bounds segment one logical required input and never turn omitted records into a complete result. Every page separately validates the frozen Support Session, `security.investigate`, Organization/resource set, interval, classification ceiling, query hash and current expiry/revocation at the read transaction's PostgreSQL timestamp.

The restricted work-dispatch binding establishes only the one Organization context for that page. In the authorized read transaction, the collector materializes a deeply immutable page DTO and its query/result digests, records the access decision and closes the transaction. It then writes the encrypted staging object outside a transaction and validates size/digest/KMS metadata. A final restricted transaction appends the immutable Investigation Audit Evidence Item/custody record or the exact gap, terminalizes the page and either creates the next action or marks that required input complete. Object failure, denied/expired Support Session, missing input or integrity failure creates the Volume I gap; it does not read another Organization or silently skip a page. Process loss before terminalization reuses the same page/object identity; a committed item/gap is a duplicate no-op.

When every required input is terminal, completeness is derived exactly as WF-018 defines and the Investigation remains Open until the separately authorized report command. Collection has no public/service HTTP route, no implicit retry with a new query identity and no direct Sidekiq enqueue. Report publication can reference only committed item/gap IDs from the frozen plan.

## Sweepers And Reconciliation

| Mechanism | Trigger | Exact responsibility |
| --- | --- | --- |
| scheduler lease | elected scheduler inline every 5 seconds | renew 15-second singleton lease or stop all polling/seeding |
| queue transport health | elected scheduler inline every 5 seconds | persist the exact Redis health sample; never recover work inline |
| timer registry reconciliation | elected scheduler inline every 5 seconds | ensure at most 20 missing invariant/partition/restore actions per pass under the cadence rule below; never execute them |
| due-action poll | elected scheduler inline every 1 second | claim at most 100 due actions |
| outbox poll and missing consumption | elected scheduler inline every 1 second | claim at most 100 pending routes or published routes missing their consumption for at least 60 seconds |
| expired transport leases | `transport_lease_sweep_due`, every 15 seconds | release/reclassify expired claims by checkpoint and apply the three-sample Redis recovery gate |
| running work invariant | `running_work_sweep_due`, every 60 seconds | compare state, lease, attempt deadline, Organization and policy checkpoint |
| entitlement lease invariant | `entitlement_invariant_sweep_due`, every 15 seconds | ensure/invoke the exact reservation expiry/commit/release action identity |
| staged-object invariant | `staged_object_invariant_sweep_due`, every 5 minutes | create exact destruction actions for expired temporary objects or alert on missing manifest authority |
| Export invariant | `export_invariant_sweep_due`, every 60 seconds | detect generating work without live lease and ensure exact effective-expiry action |
| Mailgun uncertainty invariant | `mailgun_uncertainty_sweep_due`, every 60 seconds | ensure reconciliation/escalation actions exist without acquiring a provider gate or sending |
| partition invariant | `partition_maintenance_due`, hourly and at release | require current plus two future monthly partitions |
| deletion/tombstone invariant | `deletion_tombstone_invariant_sweep_due`, every 5 minutes | detect missing start/primary/backup/hold/tombstone actions and deadlines |
| restore drill execution | `restore_drill_due`, at `last_verified_drill_at + 90 days` or release time plus 90 days when none exists | execute the separately defined restore exercise; completion records verification and schedules the next due instant |

Technical periodic cadence is UTC-epoch anchored. For cadence `C` seconds, slot `n` is the half-open interval `[n*C,(n+1)*C)` and its action identity includes mechanism plus `n`; due time is the slot start. Release seeds the latest elapsed slot for each invariant mechanism and the current partition action in its migration transaction, plus the one restore-drill action. Successful sweep completion computes the first slot whose start is strictly after current PostgreSQL time and creates exactly that one next action; it records the count/range of elapsed skipped slots as diagnostic coalescing metadata and never creates catch-up actions. Thus one outage produces at most one overdue execution per mechanism.

While leader, timer registry reconciliation applies the same rule when no nonterminal action exists: it inserts only the latest elapsed cadence slot (or the exact partition/restore due identity), never every missed slot. It uses the ScheduledAction uniqueness preimage, so a race with completion/release is exact replay. It does not change an existing due time, cancel a product timer, or execute work. Partition actions use UTC calendar month identity rather than epoch seconds; restore-drill actions use the last verified drill identity rather than a cadence slot.

A sweeper is an invariant repair mechanism, not an alternate workflow. It invokes the same application handler and uses the same persisted identity as ordinary delivery.

## Shutdown And Deploy Behavior

On `SIGTERM`, a worker immediately stops fetching new Sidekiq jobs, continues heartbeats for owned work, and has 25 seconds to finish or persist a safe checkpoint. It MUST NOT start an external call when fewer than five seconds remain before forced termination. Forced termination leaves the lease to expire; recovery follows the checkpoint table above.

The scheduler relinquishes its lease and stops claiming before shutdown. A release never drains PostgreSQL timers or mutates their due times. Queue pause is permitted only by stopping the owning process; persisted due work accumulates and is recovered in due order.

## Observability Contract

Every job log and trace contains work type/ID, Organization where valid, Project where applicable, product and claim generations, queue, queued/due/claimed/started/completed times, lease owner/generation, product attempt, correlation/causation IDs, terminal outcome, sanitized reason, and whether execution was original delivery, duplicate no-op, lease recovery, or authorized replay.

Required metrics are:

- queue depth and oldest age by fixed queue;
- due-action and outbox oldest age;
- job execution latency and queue latency by work type/outcome;
- claim conflicts, duplicate no-ops, expired leases, and reclaims;
- domain retry, transport retry, quarantine, dead-letter and authorized replay counts;
- scheduler leadership and heartbeat age;
- missed product deadlines and late-result discard counts; and
- sweeper detection and successful repair counts.

Metric labels MUST use bounded work type, queue, result, reason family, and environment values. UUIDs, URLs, provider IDs, email addresses and customer text belong only in restricted structured logs/traces, never metric labels.

## Verification Gates

Implementation acceptance requires automated proof that:

1. Redis loss after enqueue is repaired from PostgreSQL without a duplicate product side effect.
2. Duplicate, reordered and concurrent Sidekiq delivery returns one product result.
3. Process death before and after every external checkpoint yields the exact declared recovery result.
4. No Sidekiq retry creates a product attempt and every F1 job has automatic retry/dead disabled.
5. Every action kind maps to one queue, handler, identity and Volume I contract.
6. Every lease expiry path is exhaustive; an unmapped checkpoint quarantines and alerts.
7. Due-time equality is decided using PostgreSQL time after job arrival.
8. Dead-letter replay cannot occur through Sidekiq Web or a console shortcut.
9. RLS context is established before the first tenant-row query and cleared on connection reuse.
10. The unresolved pre-Organization/platform-wide event scope remains blocked rather than silently represented.
