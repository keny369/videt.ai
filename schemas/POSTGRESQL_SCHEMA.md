# PostgreSQL Schema

## Status And Database Baseline

- Status: Retained Volume II Pass 001 draft; further expansion paused during the controlled Volume I correction
- Engine: Heroku PostgreSQL 17; Heroku controls the minor patch
- Encoding/collation: UTF-8, database and connection time zone UTC, deterministic `C` collation for canonical keys
- Extensions: `pgcrypto`, `citext` is not used, `pg_trgm`, `btree_gin`
- ORM: Rails Active Record for persistence adapters only

This retained draft fixes its existing table ownership, column, constraint, index, partition, locking, tenancy, retention, and migration choices only to the extent already documented. ADR-017 alignments below inherit corrected Volume I behavior; they do not authorize further Volume II expansion before the corrected baseline is committed and tagged.

## Type And Column Conventions

### Identifiers

- Every stored entity uses one application-generated UUIDv7 `id uuid PRIMARY KEY`. The same UUID is the opaque canonical API/event identifier; there is no second numeric or public ID.
- Foreign keys use `uuid`. Polymorphic audit/event references use `entity_type text` plus `entity_id uuid` and deliberately have no foreign key so retention can remove the target without rewriting evidence.
- UUIDs are never accepted as proof of access and are never sequential integers.

### Time, numbers, hashes, and text

- Instants are `timestamptz(6)` and names end in `_at`; deadlines use `_due_at` or `_expires_at`.
- Durations and counts are integer base units: `integer` where bounded below 2.1 billion, otherwise `bigint`.
- Bytes use `bigint CHECK (value >= 0)`.
- Confidence is `numeric(5,4) CHECK (value BETWEEN 0 AND 1)`.
- Unrounded score arithmetic is `numeric(18,10)`; displayed score is `numeric(4,1) CHECK (value BETWEEN 0 AND 100)`.
- Rational weights use `weight_numerator bigint` and `weight_denominator bigint CHECK (weight_denominator > 0)`.
- SHA-256 values use `bytea CHECK (octet_length(value) = 32)`. HTTP/API adapters encode them as lowercase hexadecimal.
- Canonical normalized email, host, URI, reason code, permission, state, type, and semantic version are `text`. PostgreSQL enum types are prohibited; each finite vocabulary has a `CHECK` constraint so expand/contract migrations remain possible.
- Human free text uses `text` with application Unicode-NFC/scalar validation and a database byte-length ceiling as a defense in depth.
- Nested immutable contract bodies use `jsonb` only where this catalogue says `payload`. Required identity, tenant, relationship, state, version, deadline, ordering, uniqueness, and query fields remain relational.

### Standard column sets

The table catalogue uses these shorthands; they are part of every listed table definition.

| Shorthand | Columns |
| --- | --- |
| `G-IMM` | `id uuid PK`, `schema_version text NOT NULL`, `created_at timestamptz(6) NOT NULL` |
| `G-MUT` | `id uuid PK`, `state_version bigint NOT NULL DEFAULT 0`, `lock_version bigint NOT NULL DEFAULT 0`, `created_at timestamptz(6) NOT NULL`, `updated_at timestamptz(6) NOT NULL` |
| `T-IMM` | `G-IMM` plus `organization_id uuid NOT NULL`, `project_id uuid NULL` |
| `T-MUT` | `G-MUT` plus `organization_id uuid NOT NULL`, `project_id uuid NULL` |
| `LINEAGE` | `correlation_id uuid NOT NULL`, `causation_id uuid NOT NULL`, `command_id uuid NULL`, `idempotency_key_digest bytea NULL`, `content_sha256 bytea NULL` with SHA checks |

`created_at`/`updated_at` are physical persistence times. Product contract times such as `requested_at`, `occurred_at`, `captured_at`, or `completed_at` remain separate columns and are never inferred from Rails timestamps.

## Tenant Isolation And Database Roles

F1 uses one shared schema. Every tenant-owned table has `organization_id NOT NULL`; every Project-owned table also has `project_id NOT NULL`. Parent tables expose `UNIQUE (organization_id, id)`, and children use composite foreign keys containing `organization_id`. Project children additionally use `(organization_id, project_id)`.

Database roles are exact:

| Role | Authority |
| --- | --- |
| `f1_schema_owner` | owns schema/tables; used only by reviewed release migrations |
| `f1_runtime` | web/worker DML through RLS; does not own tables and has no `BYPASSRLS` |
| `f1_readonly_ops` | sanitized operational views only; no raw tenant or secret tables |
| `f1_backup` | Heroku-managed backup role; no application use |

Every tenant table has `ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY`. Its select/insert/update/delete policy requires:

```text
organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
```

Project-scoped operations also require the application-supplied Project to resolve through a composite FK to the same Organization. Missing or malformed transaction context matches no row. Request/job entry points open a transaction and use `SET LOCAL` for `app.organization_id`, `app.actor_id` or `app.service_identity_id`, and `app.correlation_id`. Connection checkout resets every `app.*` setting before reuse.

Pre-Organization bootstrap uses a separate RLS policy on `identity_receipt_nonces` and `bootstrap_grants` comparing `bootstrap_principal_digest` with transaction-local `app.bootstrap_principal_digest`. The bootstrap transaction generates the new Organization UUID first, sets `app.organization_id`, and then inserts all tenant rows. There is no RLS bypass.

Cross-Organization support and investigation process one Organization per transaction with its exact Support Session. Control-plane bridge rows are global restricted metadata; they do not grant a query that sees several Organizations at once.

## Foreign-Key And Deletion Rules

- Default foreign-key action is `ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `ON DELETE CASCADE` is permitted only for the explicitly owned join/detail tables named in this document and only when parent and child share one retention class.
- A nullable lifecycle link uses `ON DELETE SET NULL` only where Volume I permits the reference to disappear; baseline schema uses retained opaque references instead, so no core relation uses implicit `SET NULL`.
- Domain history, Evidence, Issue/score lineage, event, audit, approvals, manifests, and custody references never cascade.
- There is no generic `deleted_at`, Paranoia/discard gem, default scope, or hidden tombstone state. Logical removal uses the exact Volume I state. Physical destruction is performed only by `DataLifecycle` against a frozen manifest.
- Object bytes live in private storage. Database rows store an immutable key/reference, digest, encryption-key reference, classification, retention class, size, media type, and lifecycle status.

## Table Catalogue

An `_id` named below has a composite tenant FK to the same-Organization parent unless the row is explicitly global or the reference is an intentionally retained opaque audit reference. `payload jsonb` means exactly the versioned nested fields in the named Volume I contract; arbitrary extra keys are rejected before insert.

### Platform and immutable release data

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `service_identities` | `G-MUT` | `organization_id uuid NULL`, `project_id uuid NULL`, `subject text NOT NULL UNIQUE`, `display_name text NOT NULL`, `status text CHECK (status IN ('active','suspended','revoked'))`, `key_id text NOT NULL`, `permission_scope jsonb NOT NULL`, `activated_at`, `revoked_at` |
| `identity_receipt_nonces` | `G-IMM` | `receipt_id uuid UNIQUE`, `issuer_key text`, `issuer_subject text`, purpose CHECK bootstrap_grant_request/self_service_bootstrap/invitation_response/existing_account_sign_in, assurance version/MFA Boolean NULL unless sign-in, `bootstrap_principal_digest bytea`, `normalized_email_digest bytea`, `receipt_digest bytea UNIQUE`, `validated_at`, `expires_at`, `consumed_at`, `consumed_command_id uuid`, `status text CHECK (status IN ('available','consumed','expired','rejected'))`; secret assertion/factor bytes are absent |
| `command_executions` | `G-IMM`, `LINEAGE` | `command_type`, `command_schema_version`, exactly one of `actor_id`/`service_identity_id`, `organization_id NULL`, `bootstrap_principal_digest NULL`, `project_id NULL`, `target_type`, `target_id NULL`, `action`, `expected_state_version NULL`, `requested_at`, `client_requested_at NULL`, `authorization_check_at`, `policy_versions jsonb`, `canonical_payload jsonb`, `request_sha256`, `status CHECK ('received','completed')`; XOR and tenant/bootstrap checks |
| `idempotency_records` | `G-MUT` | `scope_kind`, `organization_id NULL`, `bootstrap_principal_digest NULL`, `command_type`, `target_type`, `target_id NULL`, `key_digest`, `request_sha256`, `command_execution_id`, `command_result_id NULL`, `retain_until`; unique exact scope tuple plus key digest |
| `command_results` | `G-IMM`, `LINEAGE` | `command_execution_id UNIQUE`, `result_schema_version`, `outcome CHECK ('success','failure')`, `organization_id NULL`, `project_id NULL`, exactly one actor/service, `completed_at`, `target_refs jsonb`, `resulting_state_version NULL`, `error_class/code/reason/severity/retryable/recovery_action/support_reference` nullable as one failure tuple, `authorized_payload jsonb`, `audit_record_id`; success/failure nullability checks |
| `authorization_decisions` | `T-IMM`, `LINEAGE` | `subject_type`, `subject_id`, `action`, `resource_type`, `resource_id NULL`, `decision CHECK ('allow','deny')`, `reason_code`, `organization_epoch`, `membership_snapshot jsonb`, `role_assignment_versions jsonb`, `policy_snapshot_id`, `support_session_id NULL`, `classification_ceiling`, `decided_at` |
| `audit_record_registry` | `G-IMM` | `audit_record_id uuid UNIQUE`, `occurred_at`, `retention_class CHECK ('security_audit')`, `partition_month date` |
| `audit_records` | `T-IMM`, `LINEAGE` | `audit_record_id uuid`, `occurred_at`, actor/service XOR, `workflow_id`, `entity_type`, `entity_id NULL`, `from_state NULL`, `to_state NULL`, `outcome`, `reason_code NULL`, `authorization_decision_id NULL`, `support_session_id NULL`, `classification`, `payload jsonb`, `payload_sha256`; monthly partitioned on `occurred_at`; FK to registry |
| `event_registry` | `G-IMM` | `event_id uuid UNIQUE`, `event_type`, `schema_version`, `occurred_at`, `organization_id`, `aggregate_type`, `aggregate_id`, `aggregate_version`, `partition_month date` |
| `domain_events` | `T-IMM`, `LINEAGE` | `event_id uuid`, `event_type`, `workflow_id`, `event_profile`, `occurred_at`, `affected_entity_type/id`, `aggregate_version`, actor/service XOR, `outcome`, `reason_code NULL`, `audit_record_id`, `related_entities jsonb`, `governing_versions jsonb`, `payload jsonb`, `input_sha256 NULL`, `output_sha256 NULL`; monthly partitioned on `occurred_at`; FK to registry |
| `outbox_messages` | `G-MUT` | `event_id uuid UNIQUE`, `topic text`, `available_at`, `claimed_at NULL`, `claimed_by NULL`, `published_at NULL`, `attempt_count integer`, `last_error_code NULL`, `status CHECK ('pending','claimed','published','quarantined')`; payload is read from `domain_events` |
| `event_consumptions` | `G-IMM` | `consumer_name`, `event_id`, `event_schema_version`, `consumed_at`, `result_sha256`; unique `(consumer_name,event_id)` |
| `event_dead_letters` | `G-MUT` | `consumer_name`, `event_id`, `reason_code`, `payload_reference`, `first_seen_at`, `last_seen_at`, `replay_generation`, `status CHECK ('quarantined','replayed','retired')`; unique `(consumer_name,event_id,replay_generation)` |
| `scheduled_actions` | `G-MUT`, `LINEAGE` | `organization_id NULL`, `project_id NULL`, `action_kind`, `target_type/id`, `generation integer`, policy ID/version/content hash NULL, slot number NULL, `due_at`, coalesced first slot/due NULL and `coalesced_missed_count` default 0, due-time and evaluation-time Organization/Project state-version references NULL, `not_before_at`, `claimed_at NULL`, `dispatched_at NULL`, `canceled_at NULL`, `completed_at NULL`, `decision_result CHECK ('admitted','superseded_policy','inactive_scope','active_evaluation_conflict','ineligible') NULL`, exact decision reason NULL, `status CHECK ('pending','claimed','dispatched','canceled','completed','quarantined')`, `payload_refs jsonb`; generic unique `(action_kind,target_type,target_id,generation,due_at)` and reassessment-slot unique `(project_id,policy_id,policy_version,slot_number,due_at)` |
| `stored_objects` | `T-MUT`, `LINEAGE` | `owner_type/id`, `object_key UNIQUE`, `storage_provider CHECK ('aws_s3')`, `bucket_role`, `media_type`, `byte_size`, `content_sha256`, `classification`, `retention_class`, `kms_key_ref`, `encryption_context_sha256`, `status CHECK ('staged','published','destroy_pending','destroyed','quarantined')`, `published_at/destroyed_at NULL`, `valid_until NULL` |
| `release_artifacts` | `G-MUT` | `artifact_type`, `artifact_id text`, `semantic_version`, `owner`, `released_at`, `status CHECK ('draft','active','superseded','retired')`, `schema_version`, `normalized_payload jsonb`, `content_sha256`, `supersedes_id NULL`, `activated_at NULL`; unique `(artifact_type,artifact_id,semantic_version)` and `(content_sha256,artifact_type)` |
| `release_artifact_signatures` | `G-IMM` | `release_artifact_id`, `signer_identity`, `signature_algorithm`, `key_id`, `signature bytea`, `signed_at`; unique `(release_artifact_id,signer_identity)` |

`release_artifacts` stores immutable Check Catalog, Check Definition content mirrors, policies owned globally, templates, playbooks, and a future owner-approved Measurement Set. Volume II does not create Measurement Set bytes.

### Identity, access, and tenant governance

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `organizations` | `T-MUT` | self-FK `organization_id=id`, `display_name`, `default_locale`, `reporting_time_zone`, `profile_schema_version`, `state CHECK ('pending','active','suspended','closed')`, `authorization_epoch bigint`, current `access_policy_id`, `entitlement_policy_id`, `plan_assignment_id`, `billing_entity_id`, `creator_account_id NULL` until bootstrap commit, lifecycle timestamps/reason |
| `accounts` | `T-MUT` | `identity_issuer_key`, `identity_subject`, `normalized_email`, `display_name`, `state CHECK ('pending','active','suspended','revoked')`, `identity_receipt_digest`, lifecycle timestamps/reason; unique `(organization_id,identity_issuer_key,identity_subject)` |
| `sessions` | `T-MUT` | `account_id`, `token_sha256 UNIQUE`, `identity_receipt_digest`, creation reason CHECK bootstrap/invitation_acceptance/existing_account_sign_in, `authorization_context_version`, `issued_at`, `last_activity_at`, `idle_expires_at`, `absolute_expires_at`, `state CHECK ('active','revoked','expired')`, `revoked_at/expired_at/reason NULL`, `correlation_id`; checks `idle_expires_at<=absolute_expires_at`; no Account-level active-Session uniqueness |
| `bootstrap_grants` | `G-MUT`, `LINEAGE` | `bootstrap_principal_digest`, `allowed_action CHECK ('organization.bootstrap')`, `issuer_service_identity_id`, `policy_version`, `issued_at`, `expires_at`, `state CHECK ('issued','consumed','revoked','expired')`, `consuming_command_id NULL`, `organization_id NULL`, `reason_code NULL`; one partial unique issued grant per principal; one consumed self-service grant per principal |
| `invitations` | `T-MUT`, `LINEAGE` | `opaque_reference_sha256 UNIQUE`, encrypted `opaque_reference_object_id`, `target_email`, `target_email_sha256`, `target_identity_issuer/subject NULL`, `canonical_role`, `permission_mode`, `persona NULL`, `scope_sha256`, `protected_permission_preview jsonb`, requester/approver IDs, policy versions, request/approval/activation/expiry/terminal timestamps, `reissue_of_id NULL`, `fulfilled_by_role_assignment_id NULL`, `state CHECK ('pending_approval','active','accepted','declined','rejected','revoked','expired')`, `reason NULL`; open-preimage partial unique index |
| `role_assignments` | `T-MUT`, `LINEAGE` | `account_id`, `canonical_role`, `permission_mode`, `persona NULL`, `scope_sha256`, `state CHECK ('pending','active','rejected','revoked','expired')`, `requester_id`, request/effective/approval-due/expiry/terminal times, `reason NULL`, `organization_epoch_at_decision`; active tuple partial unique |
| `role_assignment_scope_projects` | `T-IMM` | `role_assignment_id`, `scoped_project_id`; unique pair; cascade only from Role Assignment during eligible physical destruction |
| `role_assignment_scope_resources` | `T-IMM` | `role_assignment_id`, `resource_type`, `resource_id`; unique tuple; same-retention cascade only |
| `role_assignment_permissions` | `T-IMM` | `role_assignment_id`, `permission`; unique pair |
| `role_assignment_approvals` | `T-IMM`, `LINEAGE` | `role_assignment_id`, `approver_account_id NULL`, `platform_identity_id NULL`, `authority`, `decision`, `reason`, `decided_at`, `policy_version`, `separation_result`; approver XOR, unique approver per assignment |
| `policy_artifacts` | `T-MUT`, `LINEAGE` | `policy_type`, `scope_kind`, `scope_sha256`, `semantic_version`, `state CHECK ('draft','active','superseded','retired')`, `normalized_rules jsonb`, `effective_at`, `expires_at NULL`, `supersedes_id NULL`, `content_sha256`, creator/approver IDs; unique version and partial unique active `(organization_id,policy_type,scope_sha256)` |
| `policy_scope_projects` | `T-IMM` | `policy_artifact_id`, `scoped_project_id`; unique pair |
| `policy_scope_resources` | `T-IMM` | `policy_artifact_id`, `resource_type/id`; unique tuple |
| `policy_snapshots` | `T-IMM`, `LINEAGE` | `workflow_id`, `resolved_at`, `versions jsonb`, `normalized_values jsonb`, `content_sha256`; unique content within Organization/project |
| `closure_requests` | `T-MUT`, `LINEAGE` | requester/approver IDs, `organization_state_version`, `authorization_epoch`, retention/legal-hold snapshot IDs, `requested_at`, `approval_due_at`, decision/executed times, `state CHECK ('pending','approved','rejected','expired','executed')`, `reason`; one pending/approved request per Organization |

`organization_memberships` is a read-only SQL view deriving Account state, Organization epoch, ordered effective Role Assignment IDs/versions, and derived Membership status. The runtime role has no insert/update/delete privilege on the view or its source through that name.

### Projects, Source, crawl, and intake

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `projects` | `T-MUT` | `project_id` is null in common set, `display_name`, `locale`, `time_zone`, local-applicability/profile fields, objective, `state CHECK ('draft','active','paused','archived')`, `source_set_version bigint`, current Evaluation/Issue Set/Score pointers, lifecycle timestamps/reason; unique `(organization_id,id)` |
| `sources` | `T-MUT`, `LINEAGE` | `project_id NOT NULL`, submitted/canonical root URI, `canonical_host`, registration/normalization versions, registering Account/decision IDs, `state CHECK ('proposed','verified','active','disabled','removed')`, current scope-policy ID, lifecycle times/reason; partial unique `(organization_id,project_id,canonical_host)` where state != removed |
| `source_set_versions` | `T-IMM` | `project_id`, `version bigint`, ordered `source_ids jsonb`, `scope_versions jsonb`, `content_sha256`, `sealed_at`; unique `(project_id,version)` |
| `verification_requests` | `T-MUT`, `LINEAGE` | `project_id`, `source_id`, method CHECK dns/http, challenge ciphertext object/key refs, challenge digest, request initiator, `requested_at`, `expires_at`, automated/on-demand counters/cursors, in-progress attempt ID NULL, `state CHECK ('pending','verified','expired','canceled','failed')`, reason; partial unique pending per Source |
| `verification_attempts` | `T-MUT`, `LINEAGE` | `project_id`, request/source IDs, attempt number, origin CHECK automated/on_demand, automated slot offset NULL, reserved/started/completed/deadline times, network outcome/status/code/byte count/digest/match/reason, `state CHECK ('reserved','running','completed','quarantined')`; unique `(verification_request_id,attempt_number)` |
| `source_scope_change_requests` | `T-MUT`, `LINEAGE` | `project_id`, `source_id`, proposed policy payload/hash, requester/approver IDs, `requested_at`, `approval_due_at`, terminal time, `state CHECK ('pending','approved','rejected','canceled','expired')`, reason |
| `crawls` | `T-MUT`, `LINEAGE` | `project_id`, parent Evaluation/Crawl NULL, kind CHECK root/reassessment_child, request source-set/policy snapshot IDs, entitlement Decision/reservation NULL until start, queued/started/terminal/deadline times, `state CHECK ('queued','running','completed','failed','canceled')`, coverage CHECK full/partial NULL, completion reason NULL, all limit counters bigint/jsonb, retry/recovery generation |
| `crawl_sources` | `T-IMM` | `project_id`, `crawl_id`, `source_id`, `source_state_version`, `scope_policy_id/version`, canonical root, order integer; unique `(crawl_id,source_id)` and `(crawl_id,order)` |
| `crawl_candidates` | `T-MUT` | `project_id`, `crawl_id`, `source_id`, canonical URL/hash, discovery kind, depth, parent candidate NULL, enqueue/commit order, `state CHECK ('discovered','queued','in_progress','terminal','discarded')`, reason; unique `(crawl_id,canonical_url_sha256)` |
| `crawl_fetch_attempts` | `T-MUT`, `LINEAGE` | candidate/source IDs, attempt number, scheduled/started/completed/deadline times, reserved/accounted/expanded/limit-probe bytes, HTTP status/media type NULL, redirect target NULL, object ID NULL, outcome/reason, `state CHECK ('scheduled','running','succeeded','failed','canceled','discarded')`; unique `(crawl_candidate_id,attempt_number)` |
| `crawl_url_outcomes` | `T-IMM`, `LINEAGE` | candidate/source IDs, terminal commit order, outcome/reason, Document ID NULL, accounted byte totals, coverage effect; unique `crawl_candidate_id` |
| `crawl_limit_outcomes` | `T-IMM`, `LINEAGE` | `crawl_id`, dimension, configured/observed values, source/URL counts, occurred_at; unique `(crawl_id,dimension)` |
| `documents` | `T-MUT`, `LINEAGE` | `project_id`, `source_id`, `crawl_id`, canonical URL/hash, positive version, predecessor ID NULL, fetched object ID, media type, byte size/digest, `state CHECK ('discovered','ingested','parsed','indexed','quarantined','retired')`, lifecycle times/reason; unique `(source_id,canonical_url_sha256,version)` |
| `ingestion_jobs` | `T-MUT`, `LINEAGE` | `project_id`, `crawl_id`, `document_id`, generation, attempt count, next due/deadline NULL, `state CHECK ('queued','running','succeeded','failed','dead_letter')`, reason; unique semantic generation tuple |
| `ingestion_attempts` | `T-IMM`, `LINEAGE` | job ID, attempt number, scheduled/actual start/completed/deadline times, input/output object/digests NULL, outcome/reason; unique `(ingestion_job_id,attempt_number)` |
| `parsing_jobs` | `T-MUT`, `LINEAGE` | `project_id`, ingestion/document IDs, content digest, parser ID/version, generation/attempt count/due/deadline, `state CHECK ('queued','running','succeeded','failed','dead_letter')`, reason; unique `(document_id,content_sha256,parser_version,generation)` |
| `parsing_attempts` | `T-IMM`, `LINEAGE` | job ID, attempt number, scheduled/actual/deadline, input/output digests/object ID NULL, outcome/reason; unique `(parsing_job_id,attempt_number)` |
| `parsed_artifacts` | `T-IMM`, `LINEAGE` | `project_id`, document/parsing job IDs, parser/schema versions, normalized payload object ID, payload digest, title/link/organization manifest hashes, classification; unique `(document_id,parser_version,payload_sha256)` |
| `evaluation_input_snapshots` | `T-IMM`, `LINEAGE` | `project_id`, `evaluation_id`, `crawl_id`, source-set/policy/parse-manifest versions, status CHECK ready_full/ready_partial/blocked, ordered reasons jsonb, manifest/content hash, `sealed_at`; unique `evaluation_id` and manifest hash tuple |
| `evaluation_input_manifest_entries` | `T-IMM` | `project_id`, snapshot ID, entry type, source/document/job/artifact IDs nullable by type, terminal status/reason, ordering integer, entry digest; unique `(snapshot_id,ordering)` |
| `evaluation_input_evidence_entries` | `T-IMM` | `project_id`, snapshot ID, Evidence ID, Evidence digest, Validation Decision ID/status, ordering integer; unique `(snapshot_id,evidence_id)` and `(snapshot_id,ordering)` |
| `external_measurement_submissions` | `T-IMM`, `LINEAGE` | `project_id`, evaluation ID, measurement kind/set version/hash, adapter ID/version, payload/object/digest, observed/captured/fresh times, Evidence ID, outcome; unique `(evaluation_id,measurement_kind,measurement_set_version)` |

Scheduled reassessment uses one Project-scoped `policy_artifacts` row with `policy_type=reassessment_schedule` and schema-validated enabled/cadence payload. `scheduled_actions` stores exact policy ID/version, slot number/due time, coalesced range/count, due-time and evaluation-time scope-state references, and terminal decision identity in the named columns above; `payload_refs` carries only immutable references required by the admitted action. No separate mutable schedule-preference table is permitted.

### Retrieval

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `indexing_jobs` | `T-MUT`, `LINEAGE` | `project_id`, parsing job/artifact/document IDs, target ID/version, generation/attempt count/due/deadline, `state CHECK ('queued','running','succeeded','failed','dead_letter')`, reason; unique `(parsed_artifact_id,content_sha256,target_id,schema_version,generation)` |
| `indexing_attempts` | `T-IMM`, `LINEAGE` | job ID, attempt number, scheduled/actual/deadline, input/output digest, outcome/reason; unique `(indexing_job_id,attempt_number)` |
| `index_receipts` | `T-IMM`, `LINEAGE` | `project_id`, indexing job/document/artifact IDs, target/version, indexed payload digest, indexed_at; unique `indexing_job_id` |
| `search_documents` | `T-MUT` | `project_id`, source/document/artifact IDs, canonical URL, title, normalized body, `search_vector tsvector`, `content_sha256`, classification, projection version, indexed_at, retired_at NULL; unique `(document_id,projection_version)` |

### Evidence, Checks, Issues, and scores

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `evidences` | `T-IMM`, `LINEAGE` | `project_id`, `source_id` and `evaluation_id` nullable only as Volume I permits; `evidence_type CHECK` with exact six recognized values `source_document`, `crawl_observation`, `parsed_content`, `external_measurement`, `verification_observation`, `operator_attestation`; object ID; captured/observed times; `source_system`, collection method, collector version and governing schema/policy version references as the one Evidence Provenance representation; initial validation status/reason; Evidence Classification; `payload_retention_class CHECK ('product_evidence_payload')`; validity times. Evidence Source is derived from `source_system` plus nullable `source_id` and has no column. The Evidence row is `product_history`; no baseline command may insert reserved `operator_attestation`; `operator_submission` fails before persistence. |
| `evidence_lineages` | `T-IMM` | `project_id`, child Evidence ID, parent Evidence/artifact/document/check ID and type, ordering, relationship; unique lineage tuple |
| `evidence_validation_decisions` | `T-IMM`, `LINEAGE` | `project_id`, Evidence ID, prior/result status, reason, policy version, deciding actor/service XOR, Evidence state version, decided_at; unique `(evidence_id,state_version)` |
| `check_definitions` | `G-IMM` | stable definition ID, semantic version, pillar, owner/release, normalized contract payload, content hash, impact/effort/rule versions, active Catalog refs; unique `(definition_id,semantic_version)` |
| `check_catalogs` | `G-MUT` | Catalog version, owner/release, state, executor/external/effort policy versions, content hash, superseded ID NULL, activated_at; unique version/hash |
| `check_catalog_entries` | `G-IMM` | Catalog ID, Definition ID/version/digest, ordering; unique `(catalog_id,ordering)` and `(catalog_id,definition_id,definition_version)` |
| `check_applicability_snapshots` | `T-IMM`, `LINEAGE` | `project_id`, Evaluation ID, Catalog ID/version/hash, source-set/scope/policy versions, content hash, sealed_at; unique Evaluation |
| `check_applicability_entries` | `T-IMM` | `project_id`, snapshot ID, Definition ID/version, subject type/key/preimage/hash, applicability, reason, expected Result key/preimage/hash, ordering; unique key preimage identity and ordering |
| `evaluations` | `T-MUT`, `LINEAGE` | `project_id`, kind CHECK initial/reassessment/retry, Crawl ID NULL, prior/retry-of Evaluation IDs NULL, input/applicability snapshot IDs, policy snapshot ID, `state CHECK ('pending','running','completed','failed','superseded')`, started/completed/failed/superseded/deadline times, reason, current publication marker |
| `evaluation_orchestration_contexts` | `T-IMM` | `project_id`, Evaluation ID UNIQUE, prior current pointers, source-set/scope/policy hashes, root Entitlement Decision/reservation, stage input hashes, publication preconditions jsonb |
| `deduplication_keys` | `T-IMM` | `project_id`, namespace, digest, full preimage jsonb, collision ordinal integer, allocated_at; unique `(organization_id,namespace,digest,collision_ordinal)` and `(organization_id,namespace,digest,full_preimage)` |
| `check_result_slots` | `T-MUT` | `project_id`, Evaluation/applicability entry IDs, expected key digest/preimage ID, ordering, `state CHECK ('pending','running','terminal')`, attempt count, terminal Result ID NULL; unique applicability entry |
| `check_attempts` | `T-IMM`, `LINEAGE` | `project_id`, slot ID, attempt number, scheduled/started/completed/deadline, deterministic input hash, output hash NULL, outcome/reason; unique `(slot_id,attempt_number)` |
| `check_results` | `T-IMM`, `LINEAGE` | `project_id`, Evaluation/slot/Definition IDs/version, pillar/subject identity, deterministic input/output hashes, outcome/status/reason, normalized observation jsonb, confidence/band/status, impact/effort fields, score/recommendation eligibility, completed_at; unique slot and semantic result key |
| `check_result_evidences` | `T-IMM` | `project_id`, Check Result ID, Evidence ID/digest, Validation Decision ID/status, ordering; unique pair/order |
| `issues` | `T-MUT`, `LINEAGE` | `project_id`, Evaluation/Check Result IDs, fingerprint dedup key ID, impact/confidence/effort, lifecycle/adjudication status fields, `state CHECK ('candidate','open','resolved','dismissed','superseded')`, predecessor/successor IDs NULL, publication/suppression/terminal times/reasons; direct-successor uniqueness |
| `issue_evidences` | `T-IMM` | `project_id`, Issue ID, Evidence ID/digest, role, ordering; unique pair/ordering |
| `issue_lineage_heads` | `T-MUT` | `project_id`, fingerprint dedup key ID, current Issue ID, current state version; unique fingerprint key |
| `adjudication_cases` | `T-MUT`, `LINEAGE` | `project_id`, Issue ID, requester/assignee/decider IDs nullable, case kind/status/SLA status, request/due/decision/withdrawal/obsoleted times, reminder cursor, reason/decision; one open Case per Issue/type |
| `issue_sets` | `T-IMM`, `LINEAGE` | `project_id`, Evaluation ID, ordered Issue/current-leaf IDs jsonb, content hash, sealed_at; unique Evaluation/hash |
| `issue_set_memberships` | `T-IMM` | `project_id`, Issue Set ID, Issue ID, current-leaf boolean, frozen state/version, ordering; unique pair/order |
| `project_calculation_sequences` | `T-MUT` | `project_id`, next sequence bigint, current ScoreSnapshot ID NULL; unique project |
| `score_snapshots` | `T-IMM`, `LINEAGE` | `project_id`, sequence, Evaluation/Issue Set/Catalog/applicability/policy IDs+hashes, prior Snapshot ID NULL, calculation status/completeness, overall value NULL, unrounded value NULL, ordered unavailable reasons, input/output semantic hashes, current/promotable flags, created trigger/time; unique `(project_id,sequence)` and complete idempotency hash tuple |
| `score_snapshot_pillars` | `T-IMM` | `project_id`, Snapshot ID, pillar, applicability/status, weight numerator/denominator, penalty/unrounded/rounded values NULL, reasons jsonb, ordering; unique pillar/order |
| `score_contributions` | `T-IMM`, `LINEAGE` | `project_id`, Snapshot/Issue/Check Result IDs, frozen Issue state/version, eligibility/exclusion reason, impact/confidence/penalty, weighted rational/decimal values, semantic hashes; unique `(score_snapshot_id,issue_id)` |
| `score_contribution_evidences` | `T-IMM` | `project_id`, Contribution ID, Evidence/Decision IDs and digests/statuses, ordering; unique pair/order |
| `current_score_projections` | `T-MUT` | `project_id UNIQUE`, current Snapshot ID NULL, last promoted Snapshot ID NULL, latest calculation Snapshot ID NULL, status, ordered unavailable reasons, source versions, projection version, calculated_at |
| `reassessment_results` | `T-IMM`, `LINEAGE` | `project_id`, prior/current Evaluation IDs, prior/current scope Snapshot IDs, Entitlement Decision ID, `trigger_kind CHECK ('manual','scheduled')`; schedule policy ID/version/content hash, slot number and due-at all NULL exactly for manual and all NOT NULL exactly for scheduled; status CHECK completed/failed/canceled, Issue Set/Score IDs NULL as contract permits, supersession/recommendation deltas jsonb, failure stage/reason NULL, started/completed times |
| `reassessment_resolution_entries` | `T-IMM` | `project_id`, Reassessment Result ID, Issue ID, reason, ordering; unique pair/order |

### Recommendations and AI lineage

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `recommendation_families` | `T-MUT` | `project_id`, origin Issue ID, recommendation kind, next version integer, latest Artifact ID NULL, current published Artifact ID NULL; unique `(origin_issue_id,recommendation_kind)` |
| `recommendation_artifacts` | `T-MUT`, `LINEAGE` | `project_id`, family/origin Issue IDs and frozen version, positive artifact version, predecessor ID NULL, generation mode CHECK deterministic_template/ai_assisted, template/effort/schema/policy versions, immutable content object/digest, `state CHECK ('draft','published','suppressed','retired')`, publication/suppression/retirement times/reasons; unique `(family_id,artifact_version)` and direct predecessor successor |
| `recommendation_related_issues` | `T-IMM` | `project_id`, Artifact ID, related Issue ID, ordering; unique pair/order; informational flag fixed true |
| `recommendation_evidences` | `T-IMM` | `project_id`, Artifact ID, Evidence/Decision IDs/digests/statuses, role, ordering; unique pair/order |
| `ai_responses` | `T-MUT`, `LINEAGE` | `project_id`, Artifact/Recommendation version, origin Issue/version, prompt/model/response/citation policy versions, locale, request fingerprint/preimage, generated object/digest NULL, claim-manifest hash NULL, `state CHECK ('requested','generated','validated','rejected','expired')`, reason/times/deadlines/expiry; unique request fingerprint+preimage allocation |
| `ai_response_input_evidences` | `T-IMM` | `project_id`, AIResponse ID, Evidence/Decision IDs/digests/statuses, ordering; unique pair/order |
| `ai_claims` | `T-IMM` | `project_id`, AIResponse ID, claim key, claim digest, locator, classification, ordering; unique key/order |
| `citations` | `T-MUT`, `LINEAGE` | `project_id`, AIResponse/Evidence IDs, claim key/digest, Evidence digest/Decision/status, locator, policy/fingerprint/preimage, `state CHECK ('proposed','verified','invalid','superseded')`, reason/times, deciding service ID; no Evaluation ID column; unique fingerprint/preimage allocation |
| `priority_decisions` | `T-IMM`, `LINEAGE` | `project_id`, policy/version, Issue Set/Score IDs, ordered input/output hashes, decided_at |
| `priority_decision_items` | `T-IMM` | `project_id`, Decision/Artifact/origin Issue IDs, base rank, impact/confidence/effort inputs, exclusion/suppression reason NULL, ordering; unique Artifact/order |
| `priority_overrides` | `T-IMM`, `LINEAGE` | `project_id`, Priority Decision/Artifact IDs, actor ID, display rank, reason, expected versions, decided_at; unique `(priority_decision_id,artifact_id)` |
| `action_queue_projections` | `T-MUT` | `project_id UNIQUE`, Priority Decision ID, ordered Artifact IDs/json, projection version/status/reasons, built_at |

AI tables exist to preserve the accepted dormant contract and future migration shape, but no baseline write path reaches them without approved signed artifacts. CAP-019 has no dashboard/history narrative table, column, placeholder, or provider path; this six-defect alignment does not decide any unrelated AI explanation contract.

### Notifications and Exports

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `notifications` | `T-MUT`, `LINEAGE` | `project_id NULL`, triggering event ID, policy/template versions, context payload/hash, replay-of ID NULL, generation, `state CHECK ('pending','uncertain','sent','partial','failed','suppressed')`, terminal time/reason; unique `(event_id,policy_version,template_version,generation)` |
| `notification_recipients` | `T-IMM` | Notification ID, recipient kind/account ID NULL/email digest NULL, selector/authorization decision IDs, classification ceiling, ordering; exactly one recipient form; unique identity/order |
| `deliveries` | `T-MUT`, `LINEAGE` | Notification/recipient IDs, channel CHECK in_app/email, replay generation, Integration/Credential versions always NULL for in-app and nullable for email until individually resolved by an attempt, provider-correlation-token digest NULL before the first email-attempt claim, `state CHECK ('pending','attempting','accepted','delivered','retry_scheduled','acceptance_unknown','terminal_failed','suppressed')`, attempt count, provider message ID NULL, scheduled retry/uncertainty/terminal times/reason; unique `(notification_id,recipient_id,channel,replay_generation)` |
| `delivery_attempts` | `T-MUT`, `LINEAGE`; identity and prepared inputs immutable after insert | Delivery ID, attempt number/generation, required logical adapter-policy identity and executing adapter code version nonnull at claim; resolved adapter-policy artifact ID/version/content hash and Integration/Credential/material versions NULL until individually resolved and all required values nonnull before `submission_started`; prepared/scheduled/submission-started/completed/deadline times; request and application-deduplication-key digests; provider-correlation-token digest; `dispatch_checkpoint CHECK ('prepared','submission_started','recorded')`; certainty; provider status/message ID NULL; provider event ID NULL; outcome/reason; retry due NULL; unique `(delivery_id,generation,attempt_number)` and unique claimed `(delivery_id,generation,attempt_number,request_digest)`; checkpoint order permits `prepared -> recorded` only for a proven no-submission outcome and otherwise only `prepared -> submission_started -> recorded`, and terminal outcome/completed time become immutable together |
| `delivery_reconciliations` | `T-IMM`, `LINEAGE` | Delivery/attempt/generation IDs, sequence CHECK 0/1/2/3, scheduled/started/completed times, exact-token/recipient/generation query digest, outcome CHECK matched/none/ambiguous/dependency_error/authentication_failed, matched provider event ID NULL, resulting state NULL, reason; unique `(delivery_id,generation,sequence)` |
| `provider_event_registry` | `G-IMM` | Integration ID, provider kind, provider event ID, received_at, partition month; unique `(integration_id,provider_event_id)` |
| `provider_events` | `T-IMM`, `LINEAGE` | Integration ID, provider kind/event ID/message ID, provider-correlation-token digest, recipient digest, replay generation, authenticated-at/received-at/provider-at, event type/outcome/reason, normalized payload jsonb/digest; monthly partitioned on received_at; FK registry |
| `notification_escalations` | `T-IMM`, `LINEAGE` | Notification/Delivery ID NULL, generation, kind CHECK terminal_failure/acceptance_unknown/empty_selector, reason, due/created/resolved times, support reference; unique `(delivery_id,generation,kind)` with the separate empty-selector uniqueness predicate |
| `notification_replay_acknowledgements` | `T-IMM`, `LINEAGE` | replay mode CHECK delivery_replay/empty_recipient_replay; old/new Notification IDs; old/new Delivery IDs required only for delivery_replay; same logical recipient/channel digest required for delivery_replay; support Session/actor IDs, reason, `duplicate_delivery_risk_acknowledged`, acknowledged/requested times, request digest; Boolean must be true when source Delivery state is acceptance_unknown; unique new generation |
| `export_approvals` | `T-MUT`, `LINEAGE` | Export request hash/scope, requester/approver IDs, expected versions, approved/expires/used times, state CHECK pending/approved/rejected/expired/used; single-use unique used attempt |
| `exports` | `T-MUT`, `LINEAGE` | `project_id NULL`, requester/recipient Account IDs equal, format, policy/approval/Entitlement IDs, frozen scope/hash/redaction codes, manifest hash/object ID NULL, size totals, `state CHECK ('pending','generating','available','failed','expired','revoked')`, requested/generating/available/expiry/revoked/failed times, reason, retry-of ID NULL |
| `export_manifest_objects` | `T-IMM` | Export ID, object type/id/version/hash, ordering; unique object/order |
| `export_manifest_fields` | `T-IMM` | Export ID, manifest object ID, logical field, classification, redaction outcome, ordering; unique field/order |
| `export_manifest_members` | `T-IMM` | Export ID, member name/type, compressed/uncompressed sizes, content digest, ordering; unique name/order |
| `export_retrievals` | `T-IMM`, `LINEAGE` | Export/requester IDs, authorization/policy decision IDs, attempted/started/completed times, bytes streamed, outcome/reason; no reusable URL stored |

### Commercial and entitlement

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `billing_entities` | `T-MUT`, `LINEAGE` | internal contract reference, active Plan Assignment ID NULL only while pending, `state CHECK ('pending','active','past_due','suspended','closed')`, lifecycle times/reason, last billing event ID NULL; partial unique nonclosed per Organization; insert authority exists only inside the WF-001 bootstrap transaction and performs no provider call |
| `plan_approvals` | `G-IMM` | plan ID/version, normalized payload/hash, approver/signature refs, approved/effective times |
| `plan_assignments` | `T-MUT`, `LINEAGE` | BillingEntity ID NOT NULL with composite same-Organization FK, plan approval/version/hash, assigned by, effective/ended times, `state CHECK ('active','superseded','revoked')`; partial unique active per Organization |
| `entitlement_counter_windows` | `T-MUT` | counter group, window start/end, soft/hard limits, reserved/committed/low-cost units, policy/version, `reconciliation_state`, unique `(organization_id,counter_group,window_start,window_end)` |
| `entitlement_decisions` | `T-IMM`, `LINEAGE` | actor/service XOR, operation, requested units, window, policy/plan versions, counter before/after values, cached snapshot ID/age NULL, decision CHECK allow/allow_with_warning/block, reason/recovery, retry-of ID NULL, decided_at |
| `entitlement_reservations` | `T-MUT`, `LINEAGE` | Decision/counter-window IDs, units, lease generation, lease due, last heartbeat, `state CHECK ('reserved','executing','committed','released','expired')`, terminal time/reason; one reservation per Decision |
| `entitlement_lease_heartbeats` | `T-IMM` | reservation ID, generation, heartbeat/due times, worker identity; unique `(reservation_id,generation,heartbeat_at)` |
| `low_cost_fallback_snapshots` | `T-IMM` | whole counter tuple payload/hash, captured/expires times, policy/version; unique tuple hash |
| `low_cost_usage_records` | `T-IMM`, `LINEAGE` | Decision ID, counter window, units, durable response hash, reconciliation state/time; unique Decision |
| `entitlement_commit_intents` | `T-MUT`, `LINEAGE` | reservation ID, durable output type/id/hash, `state CHECK ('pending','committed','released')`, terminal time/reason; unique reservation/output |

### Integrations and Credential metadata

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `integrations` | `T-MUT`, `LINEAGE` | kind, adapter ID/version, policy ID/version/hash/major, `state CHECK ('proposed','connected','degraded','disconnected','retired')`, active Credential ID NULL, last success/attempt times, reason, attempt generation; partial unique nonretired `(organization_id,kind,policy_major)` |
| `credentials` | `T-MUT`, `LINEAGE` | Integration ID, purpose, secret type, active/pending material version IDs NULL, `state CHECK ('pending','active','rotating','revoked','expired')`, lifecycle/validation times, reason, rotation token digest; no secret plaintext |
| `credential_material_versions` | `T-IMM` | Credential ID, material version, secret-store reference, reference digest, secret type, created/activated/expires/destroyed times, status CHECK pending/active/retired/destroyed; unique `(credential_id,material_version)` |
| `integration_attempts` | `T-IMM`, `LINEAGE` | Integration ID, Credential/material versions, operation, generation/attempt number, scheduled/started/completed/deadline times, provider call ID NULL, outcome/reason; unique semantic attempt |

Only `mailgun_email` can materialize under the frozen active policy. Dormant/unsupported providers have no Integration or Credential row.

### Security operations

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `support_sessions` | `T-MUT`, `LINEAGE` | requester/approver SecurityOperator IDs, support case/Incident ID, customer approval ref NULL, reason, request/approval/start/expiry/reject/revoke times, `state CHECK ('pending','active','rejected','expired','revoked')`, decision reason |
| `support_session_scopes` | `T-IMM` | Support Session ID, resource type/id, action; unique tuple |
| `support_session_approvals` | `T-IMM`, `LINEAGE` | Session ID, approval kind, approver Account/platform identity, decision/reason/time/policy/separation; unique kind/approver |
| `incidents` | `G-MUT`, `LINEAGE` | platform-wide boolean, primary Organization ID NULL, severity/reason, detected/declared times, declarer/commander IDs, playbook artifact/version/hash, `state CHECK ('open','mitigated','resolved')`, mitigation/restoration/closure fields |
| `incident_organizations` | `G-IMM` | Incident ID, Organization ID, affected resources/workflows jsonb; unique pair |
| `incident_step_attempts` | `G-MUT`, `LINEAGE` | Incident ID, Organization ID NULL, playbook/step versions, sequence/generation, target/action/expected version, input/output hashes, scheduled/started/completed/deadline times, linked remediation result NULL, `state CHECK ('pending','running','succeeded','failed')`, reason |
| `high_risk_approvals` | `G-MUT`, `LINEAGE` | Incident/Organization IDs, playbook/step/target/action, expected version, request hash, requester/approver IDs, approved/expires times, used step attempt ID NULL, `state CHECK ('approved','used','expired','revoked')`; one-use constraint |
| `incident_restoration_checks` | `G-IMM`, `LINEAGE` | Incident ID, predicate/version, observation sequence CHECK 1/2, due/observed times, input/output hashes, result/reason; unique incident/predicate/sequence |
| `investigations` | `G-MUT`, `LINEAGE` | primary Organization ID NULL, cross-org boolean, requester/legal purpose, interval start/end, investigation-input-plan hash, `state CHECK ('open','reported','closed')`, completeness NULL, current report ID NULL, closure approver/time |
| `investigation_organizations` | `G-IMM` | Investigation/Organization/Support Session IDs, frozen input/resource scope hash; unique pair |
| `investigation_required_inputs` | `G-IMM` | Investigation/Organization IDs, input kind/ref, query hash, classification ceiling, ordering; unique input/order |
| `investigation_audit_evidence_items` | `G-IMM`, `LINEAGE` | Investigation/Organization/required-input IDs, input reference, query hash, collector/time, stored object/digest/classification, custody hash, ordering; retained as `security_audit`, not an Evidence record |
| `custody_transfers` | `G-IMM`, `LINEAGE` | Investigation Audit Evidence Item ID, from/to identities, purpose, transferred_at, item digest, acknowledgement digest, sequence; unique item/sequence |
| `investigation_access_logs` | `G-IMM`, `LINEAGE` | Investigation Audit Evidence Item/Organization IDs, actor/service, Support Session ID, action, accessed_at, outcome/reason |
| `investigation_gaps` | `G-IMM`, `LINEAGE` | Investigation/Organization/required-input IDs, reason, occurred_at, ordering; unique required input/report version |
| `investigation_reports` | `G-IMM`, `LINEAGE` | Investigation ID, positive version, scope/completeness, timeline/object/gap/proposed-action payload, content digest, published/closure verification times; unique version/digest |
| `investigation_report_items` | `G-IMM` | Report ID, item kind/ref/digest, ordering; unique order |

### Data lifecycle

| Table | Standard | Additional columns and constraints |
| --- | --- | --- |
| `legal_holds` | `G-MUT`, `LINEAGE` | primary Organization ID, requester/approver IDs, reason, policy/scope hash, request/decision/release times, `state CHECK ('pending','active','rejected','released')`, decision reason |
| `legal_hold_scopes` | `G-IMM` | Legal Hold ID, Organization ID, resource type/id, retention classes jsonb; unique tuple |
| `legal_hold_approvals` | `G-IMM`, `LINEAGE` | Hold ID, approver ID, decision/reason/time/policy/separation; unique approver |
| `lifecycle_deletion_jobs` | `G-MUT`, `LINEAGE` | Organization ID, target type/id, request type, policy/snapshot/manifest hashes, queued/started/deadline/terminal times, attempt/recovery generation, `state CHECK ('queued','running','blocked','failed','completed')`, reason, Deletion Evidence ID NULL; unique target/idempotency generation |
| `lifecycle_deletion_manifest_entries` | `G-IMM` | Job ID, Organization ID, resource type/id or object key, retention class, eligible/due times, hold intersection hash, required action, ordering, entry digest; unique order/resource |
| `lifecycle_deletion_outcomes` | `G-IMM`, `LINEAGE` | Job/manifest entry IDs, attempt generation, outcome CHECK deleted/retained/blocked/failed/not_found, reason, object digest/tombstone ID NULL, completed_at; unique entry/generation |
| `deletion_evidences` | `G-IMM`, `LINEAGE` | Job/Organization/target IDs, manifest/outcome root hashes, deleted/retained/blocked counts, primary completion/backup due times, approver/service identities, completed_at, content digest |
| `backup_tombstones` | `G-MUT`, `LINEAGE` | Job/Organization/target IDs, target digest, primary deleted at, backup deadline, last verified at, restore detected at NULL, redelete completed at NULL, `state CHECK ('pending_expiry','verified_absent','restore_detected','redeleted','failed')`, reason |
| `restore_drills` | `G-MUT` | environment, backup identifier digest, scope, started/completed times, RPO/RTO measurements, tombstone-check result, `state CHECK ('scheduled','running','passed','failed')`, Audit Evidence reference/digest, reason |

## State And Immutability Enforcement

- Mutable lifecycle tables have a vocabulary `CHECK`, `state_version`, and `lock_version`. Application transition services enforce the allowed edge; integration specs exercise every invalid edge.
- Immutable tables grant the runtime role `INSERT, SELECT` but not `UPDATE`; physical deletion remains through the DataLifecycle database function/role invoked by an authorized manifest worker.
- Versioned immutable payloads never update. A correction creates a successor row and updates only its serialization/current projection in the same transaction.
- Database check constraints enforce actor/service XOR, required/null field combinations, nonnegative versions/counts, positive artifact versions, digest lengths, and deadline ordering.
- Current pointers use composite same-Organization foreign keys and cannot point to diagnostic/nonpromotable rows.

## Required Uniqueness

In addition to table-specific constraints above, the schema MUST provide these conflict or identity guarantees:

- one active Account identity per `(organization_id, identity_issuer_key, identity_subject)`
- one issued unexpired Bootstrap Grant and one consumed self-service grant per principal
- one open Invitation per complete normalized open-preimage hash, with the full preimage retained and compared
- one active Role Assignment per Account/role/mode/persona/full canonical scope tuple
- one active Policy Artifact per Organization/type/full canonical scope
- one reassessment schedule-slot decision per `(project_id,policy_id,policy_version,slot_number,due_at)` with any coalesced range retained in that decision
- one nonremoved Source per `(organization_id, project_id, canonical_host)`
- one pending Verification Request per Source
- one root initial Evaluation per Crawl and one promoted current Evaluation pair per Project
- one external observation per `(evaluation_id, measurement_kind, measurement_set_version)`
- one Check Result per expected applicability slot
- one current Issue leaf per full fingerprint preimage
- one Artifact family per `(origin_issue_id, recommendation_kind)` and one Artifact per positive family version
- one direct successor per Issue and Artifact predecessor
- one Provider Event per `(integration_id, provider_event_id)`
- one Delivery per Notification/recipient/channel/replay generation
- one claimed Delivery attempt per Delivery/generation/attempt/request digest and one reconciliation record per uncertainty sequence
- one nonclosed BillingEntity per Organization and one same-Organization BillingEntity per Plan Assignment
- one active Plan Assignment per Organization
- one Entitlement Reservation and one usage record per Decision
- one nonretired Integration per Organization/kind/adapter-policy major
- one scheduled-action identity per action/target/generation/due instant
- one outbox message per event and one consumption per event/consumer

Digest uniqueness never substitutes for complete preimage equality. `deduplication_keys` allocates a collision ordinal under a transaction lock and stores the complete canonical preimage. Same digest/different preimage remains distinct and emits restricted collision telemetry.

## Index Catalogue

Every FK has a reverse B-tree index. Every tenant query index starts with `organization_id`; Project query indexes then include `project_id`. Required indexes are:

- lifecycle collections: `(organization_id, project_id, state, created_at DESC, id DESC)` where Project applies
- default global collections: `(state, created_at DESC, id DESC)` on restricted control tables
- due work partial: `(due_at, id)` where state is a stable active value such as `pending`, `queued`, `running`, `retry_scheduled`, or `available`
- command replay: full idempotency scope tuple plus `key_digest`
- event ordering: `(organization_id, affected_entity_type, affected_entity_id, aggregate_version)`
- correlation timeline: `(organization_id, correlation_id, occurred_at, id)`
- lineage: every predecessor, successor, retry-of, causation, Evidence parent and current-pointer column
- current score: unique `(organization_id, project_id)` including current/last/latest pointers and status
- Issue lists: `(organization_id, project_id, state, impact, created_at DESC, id DESC)`
- action queue: `(organization_id, project_id, projection_version)` with items ordered by persisted rank
- Notification lists: `(organization_id, occurred_at DESC, id DESC)` through Notification creation time
- history: `(organization_id, project_id, completed_at DESC, id DESC)` on completed Evaluations/Snapshots
- support due work: approval/expiry indexes on Invitation, Role Assignment, Support Session, Closure Request and Hold
- retention: `(retention_class, valid_until, id)` on stored objects and `(state, deadline_at, id)` on deletion/tombstone jobs
- search: GIN `search_vector`, GIN trigram on normalized title/canonical URL, and B-tree `(organization_id,project_id,classification,retired_at)`

No partial-index predicate uses `now()`. Expiry is materialized through an explicit state transition.

## Partitioning

Mutable domain, current projection, Evidence, Issue, score, recommendation, entitlement, and lifecycle tables are not partitioned initially.

The following append-only tables use monthly range partitions on their named timestamp:

- `domain_events.occurred_at`
- `audit_records.occurred_at`
- `provider_events.received_at`
- future high-volume transport attempt telemetry, if separated from canonical attempt rows

Global ID registries remain unpartitioned so uniqueness spans all months. Two future monthly partitions MUST exist before the current month ends. There is no default partition; a missing partition fails loudly and alerts before event acceptance.

A partition may be dropped only after the retention cursor is eligible, every LegalHold/resource intersection is evaluated, required immutable product history and Audit Evidence has been migrated or preserved, and a Deletion Evidence record is committed. If held and unheld rows share a partition, eligible unheld rows are deleted in bounded batches; the partition is not dropped.

## Optimistic And Pessimistic Locking

- `state_version` is the product-visible expected version and increments on every accepted lifecycle or authorization-relevant mutation.
- `lock_version` is Active Record's internal optimistic-lock column and increments on any mutable-row update, including projection rebuild metadata.
- A command compares the requested `expected_state_version`, then persists with `lock_version`; either mismatch returns the frozen stale-state result and never silently retries as a new command.
- Serialization rows and equality races use row locks in the total order defined by the Rails architecture.
- `FOR UPDATE SKIP LOCKED` is limited to due dispatch, outbox batches, and checkpointed deletion manifests. It is not used to choose a business winner whose order is product-visible unless Volume I supplies the ordering.

## Migration Sequence And Safety

Migrations use expand/backfill/switch/contract:

1. preflight extension/version/lock-size and replica/backup health
2. add nullable column/table/index/constraint as nonvalid where supported
3. deploy code capable of dual-read or dual-write only when the design requires it
4. backfill in bounded idempotent batches with progress evidence
5. validate constraints and RLS policies
6. switch reads/current pointers
7. observe one release window
8. remove old path in a later release

Rules:

- Large indexes use concurrent creation outside a transaction and a named retry-safe migration.
- New required columns are not added with a volatile table-rewrite default. Backfill, validate, then set `NOT NULL`.
- Table/column rename uses compatibility views or dual fields across releases; never one-step rename for a live interface.
- Destructive migration has a recorded irreversible classification, backup/restore proof, retention/LegalHold assessment, and rollback-forward plan.
- RLS is enabled and forced before any tenant table becomes reachable by runtime code.
- A migration may not disable RLS for application traffic.
- Schema dump is SQL format so extensions, checks, RLS, partitions, generated search columns, and views remain canonical.
- CI migrates from an empty database, the previous release schema, and a production-shaped fixture; it runs rollback only for migrations classified reversible.

## Corrected Volume I Constraints Inherited By This Draft

- Evidence Type recognizes the exact six literals, rejects `operator_submission`, and has no baseline write path for reserved `operator_attestation`.
- WF-001 is the sole baseline BillingEntity insert/activation path; its Plan Assignment linkage is required and provider-independent. The schema recognizes reserved `past_due`/`suspended` literals, but no baseline command, callback, job, or closure path may enter or exit them; baseline closure requires active-to-closed.
- Scheduled reassessment uses Project-scoped `reassessment_schedule` Policy Artifacts and exact scheduled-action slot identities; due-time and evaluation-time scope states both govern eligibility, and no commercial cadence default is stored.
- Dashboard/history projection remains deterministic structured data only and has no AI narrative/summary column, placeholder, or provider path.
- Mailgun uses unique local attempt claims, `acceptance_unknown`, immutable reconciliation, and acknowledged replay; no table or constraint claims provider-side exactly-once delivery.

Further schema expansion remains paused until the corrected Volume I baseline is committed and tagged.
