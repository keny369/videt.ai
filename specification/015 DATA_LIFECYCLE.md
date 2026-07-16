# 015 DATA_LIFECYCLE

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-16

## Authority

This document defines the canonical lifecycle policy for all major F1 data classes.

All downstream data and storage specifications MUST conform to these lifecycle requirements.

## Purpose

Define creation through destruction behavior for each major data class with ownership, control, and audit expectations.

## Scope

This document covers:

- creation, ingestion, validation, and classification
- storage, transformation, indexing, and retrieval
- export, archival, retention, and deletion
- legal hold and audit behavior
- provenance, lineage, and versioning
- derived, temporary, cached, and AI-generated data
- backup and restore behavior

## Dependencies

- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)

## Definitions

- Logical Deletion: Record is hidden from active use but still recoverable.
- Physical Deletion: Record bytes are removed from primary stores.
- Archival: Data moved to long-term storage class with controlled retrieval.
- Revocation: Access rights are removed while data may still exist.
- Irreversible Destruction: Data is removed and rendered non-recoverable from operational and backup paths after retention obligations end.

## Assumptions

- F1 stores discoverability evidence, evaluations, recommendations, and telemetry.
- Some data classes contain sensitive or regulated information.
- Restore capability is required for critical data classes.

## Constraints

- Data handling MUST follow classification and access policy.
- Retention and deletion rules MUST be auditable.
- Lifecycle controls MUST apply uniformly across primary and derived stores.

## Normative Requirements

### Data Class Ownership

DLC-REQ-001: Every major data class MUST have an owning team and lifecycle owner.

DLC-REQ-002: Data class ownership MUST be documented in canonical specifications.

### Creation, Ingestion, Validation, Classification

DLC-REQ-003: Data creation and ingestion events MUST include provenance metadata.

DLC-REQ-004: Ingested data MUST pass schema and policy validation before use.

DLC-REQ-005: Data classification MUST occur at or before first persistence write.

### Storage, Transformation, Indexing, Retrieval

DLC-REQ-006: Storage location and class MUST align with data classification.

DLC-REQ-007: Transformations MUST preserve lineage links to source records.

DLC-REQ-008: Indexing operations MUST record index version and source snapshot.

DLC-REQ-009: Retrieval operations MUST enforce access policy checks.

### Export, Archival, Retention, Deletion

DLC-REQ-010: Exports MUST include export scope, actor, and timestamp metadata.

DLC-REQ-011: Archival policy MUST define retention window and retrieval controls.

DLC-REQ-012: Retention policy MUST define minimum and maximum retention per class.

DLC-REQ-013: Deletion requests MUST specify logical deletion, physical deletion, archival, revocation, or irreversible destruction mode.

DLC-REQ-014: Irreversible destruction MUST include completion evidence and audit log record.

### Legal Hold

DLC-REQ-015: Legal hold MUST suspend irreversible destruction for affected data.

DLC-REQ-016: Legal hold release MUST be auditable and owner-approved.

### Provenance, Lineage, Versioning

DLC-REQ-017: Provenance metadata MUST include source system, ingest channel, and processing timestamp.

DLC-REQ-018: Lineage metadata MUST link derived outputs to source inputs and transformation steps.

DLC-REQ-019: Data version markers MUST follow [019 VERSIONING.md](019%20VERSIONING.md).

### Access Control And Audit

DLC-REQ-020: Access to Confidential and Restricted data MUST be role-limited and audited.

DLC-REQ-021: Lifecycle events MUST emit audit events with actor, reason, and outcome.

### Derived Data, AI-Generated Data, Temporary Data, Cached Data

DLC-REQ-022: Derived data MUST inherit or strengthen source data classification.

DLC-REQ-023: AI-generated data MUST carry model and prompt version metadata.

DLC-REQ-024: Temporary and cached data MUST define explicit expiration windows.

DLC-REQ-025: Expired temporary or cached data MUST be purged on policy schedule.

### Deleted Data Behavior

DLC-REQ-026: Logical deletion MUST remove records from user-visible workflows.

DLC-REQ-027: Physical deletion MUST remove records from active storage layers.

DLC-REQ-028: Revocation MUST disable access without implying deletion completion.

DLC-REQ-029: Deletion completion status MUST be queryable for audit and support workflows.

### Backup And Restore

DLC-REQ-030: Backup policy MUST cover all critical data classes.

DLC-REQ-031: Restore drills MUST run on a scheduled cadence with documented success criteria.

DLC-REQ-032: Restore operations MUST preserve lineage and audit metadata.

## Volume I Interim Retention And Deletion Contract `retention-interim-v1`

This contract is the deterministic Volume I behavior pending OD-011 approval. It defines logical product outcomes and deadlines, not storage-vendor tiers. Every persisted record and payload has exactly one class below; derived data inherits the class with the longer retention and the stronger security classification. “Age” is elapsed time from the named cursor. Legal hold suspends only irreversible destruction and never restores access or permits a record to be used after its product-validity boundary.

| Retention Class | Included Data | Minimum | Maximum And Cursor | Destruction |
| --- | --- | ---: | --- | --- |
| `ephemeral_secret` | plaintext verification/bootstrap material and decrypted credential material | 0 | 60 seconds after terminal use/revocation/expiry | cryptographic key destruction; never backed up |
| `temporary_processing` | failed/uncommitted fetched bodies, parser/index staging, temporary generation files | 0 | 24 elapsed hours after owning attempt terminalizes | physical delete from primary/cache; never enters analytical backup |
| `delivery_package` | encrypted Export package bytes | 0 | earlier of manifest expiry, revocation, or 24 hours after availability | cryptographic key destruction plus primary/cache deletion; immutable manifest moves to `product_history` |
| `operational_telemetry` | nonsecurity metrics, traces, sanitized provider diagnostics and job performance detail | 30 days | 90 elapsed days after event | physical delete; aggregates containing no tenant/personal identifier may remain |
| `product_evidence_payload` | Source Document, parsed, crawl, external, verification and operator Evidence payload bytes | 30 days | 24 elapsed months after capture | validation changes to invalid with `legal_deletion_completed`; payload/key deleted; lineage metadata/digest moves to `product_history` |
| `product_history` | Evaluation, Check Result, Issue/Case, Contribution, ScoreSnapshot, Recommendation, Priority, policy/version, event, manifest and Evidence-lineage metadata/digests | 7 years | 7 elapsed years after record creation or terminal transition, whichever is later | irreversible destruction after reference-integrity proof |
| `identity_commercial` | Account/Invitation/Session metadata, Organization/Project metadata, Plan/Entitlement/Billing summaries excluding payment-provider detail | active lifetime | 7 elapsed years after Organization closure or Account terminal transition, whichever applies later | irreversible destruction except minimal security/audit evidence |
| `security_audit` | authorization decisions, Support Sessions, approvals, credential/integration metadata, Incident/Investigation, custody/access logs and deletion evidence | 7 years | 7 elapsed years after event/record terminal transition | irreversible destruction only with two-person security approval |

At 30 days before a current `product_evidence_payload` maximum, the lifecycle service emits `EvidenceRetentionExpiring` once and requests reassessment when the Project remains active. Expiry wins at the maximum instant. Destruction appends the Evidence Validation Decision and all score/Recommendation suppression/recalculation effects before bytes become unreachable; no current read may cite expired bytes. A legal hold keeps the bytes but changes effective validation to quarantined with `retention_review` at the normal maximum, so held payload is not decision-grade merely because it remains stored. Release then resumes destruction or revalidation according to the current policy.

### Legal Hold

A Legal Hold contains hold ID/schema version, Organization, exact resource IDs and/or retention classes, inclusive UTC event-time interval, 20-2,000 character legal-purpose reason, requester and distinct approving SecurityOperator Accounts, requested/approved/released times, nullable release reason/approver, status (`pending`, `active`, `rejected`, or `released`), state version, policy version, idempotency key, and correlation ID. Pending to active/rejected and active to released are the only transitions; rejected/released are terminal. Creation and release each require `legal_hold.manage`, expected state version, two different active SecurityOperators, and a Support Session for customer-Organization scope. The release approver must differ from the release requester. Exact replay returns one transition; altered/stale/self-approved/cross-scope requests change nothing. `LegalHoldActivated` and `LegalHoldReleased` identify exact scope and never include held payload.

An active hold is evaluated by exact Organization plus resource/class/time intersection before every irreversible-destruction checkpoint. It changes an eligible job to blocked with reason `deletion_blocked_legal_hold`; it does not prevent Account/Organization access revocation, Organization closure, logical deletion, or package retrieval expiry. At release, the lifecycle service queues each affected blocked job once against current policy; a changed policy may lengthen but never silently shorten an already accrued mandatory minimum.

### Lifecycle Deletion Job

Every accepted delete or closure request creates/replays one LifecycleDeletionJob containing job/schema version; Organization and nullable Account/resource; requested deletion mode (`logical_deletion`, `physical_deletion`, `archival`, `revocation`, or `irreversible_destruction`); requester/approver/service identities; request reason; active retention-policy and hold-snapshot IDs/hashes; exact resource/class manifest; status (`queued`, `running`, `blocked`, `failed`, or `completed`); attempt/replay generation; per-store/index/cache/key/backup outcomes; blocked/failure reason; primary due time; backup purge due time; state version; idempotency key; timestamps; and correlation ID. A missing mode is invalid. Account deletion and Organization closure always include immediate revocation/logical deletion plus eventual irreversible destruction of eligible classes; a hold may block only the latter.

The job starts within 60 seconds of acceptance. Each primary/index/cache/key attempt has a 15-minute timeout and one retry after 5 minutes only for `deletion_dependency_unavailable`; schema, scope, digest, policy and authorization failures are nonretryable. Eligible primary/index/cache/key removal must complete within 30 elapsed days of acceptance. Backup tombstones are written before primary completion and every restore applies them before any product read; affected bytes must age out or be cryptographically erased from backup paths within 35 elapsed days after primary completion. At a due-time equality the deadline/escalation checkpoint wins. Failure or missed deadline emits `LifecycleDeletionFailed` and critical escalation without claiming completion.

Completion requires one immutable Deletion Evidence record listing job/manifest/policy/hold snapshot, every store/index/cache/key/backup outcome and time, pre-destruction digests, tombstone ID, verifier service, completion time, and SHA-256 content digest. It contains no deleted payload. The job becomes completed and emits `AccountDeletionCompleted` or `OrganizationDeletionCompleted` only in the same transaction that persists this evidence. Blocked to queued after hold release and failed to queued by an authorized new replay generation are the only recovery transitions; completed never reopens.

Protected data classes `product_evidence_payload`, `product_history`, `identity_commercial`, and `security_audit` are included in daily encrypted backup coverage. `ephemeral_secret`, `temporary_processing`, and `delivery_package` are excluded. Restore verification runs at least once every 90 elapsed days; success requires restoration into an isolated tenant, digest/lineage verification, tombstone application before read, and destruction of the drill copy within 24 hours. Drill records use `security_audit` retention.

## Decisions

- DEC-015-01: Data lifecycle controls are mandatory release gates, not optional operations guidance.
- DEC-015-02: Deletion modes are explicitly differentiated to prevent policy ambiguity.

## Non-goals

- This document does not define physical database schema.
- This document does not define vendor-specific storage tier settings.

## Risks

- Risk: deletion ambiguity causing compliance exposure.
  Mitigation: explicit deletion-mode controls and audit evidence requirements.
- Risk: lineage gaps reducing trust in recommendations.
  Mitigation: mandatory provenance and lineage metadata.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Ingestion and classification | Data validation tests and policy checks | Chief Rails | CI |
| Retention and deletion controls | Lifecycle integration tests and audit review | Chief Security | CI and release |
| Backup and restore behavior | Restore drills and evidence logs | Chief Rails | Operations gate |

## Volume I Interim Resolutions

- Customer-configurable retention windows are not available in Volume I. `retention-interim-v1` applies until OD-011 approves a replacement; any approved tenant policy may lengthen retention but MUST NOT shorten an accrued minimum or extend product validity.
- Volume I makes no cryptographic-signature claim for Export packages. `export-interim-v1` requires the immutable manifest digests and encrypted package controls defined in the Volume I workflow specification; adding package signing requires a later approved contract version.

## Related Documents

- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)
- [diagrams/DATA_LIFECYCLE.md](../diagrams/DATA_LIFECYCLE.md)

## Change Control

Any change to this document MUST:

1. Include compatibility impact by data class.
2. Include migration and retention impact assessment.
3. Include updated verification evidence requirements.
4. Include ADR references.
