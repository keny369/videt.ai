# Volume I Score And Evidence Model

## Status

- Status: Draft for owner review
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Purpose

Define the canonical, deterministic chain from Evidence through Check Result, Issue, Score Contribution, Recommendation Artifact, Priority Decision, ScoreSnapshot, and reassessment.

This document defines logical product contracts and behavior. It does not define physical schemas, endpoint shapes, serialization formats, or implementation classes.

## Canonical Terminology And Authority

- `Issue` is the only persisted product deficiency object. It is the canonical entity named by [../003 TERMINOLOGY.md](../003%20TERMINOLOGY.md) and [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md). No second persisted deficiency entity or identifier exists.
- Identifiers are opaque, immutable, and globally unique within their namespace. Examples in this document are field names, not compositional identifier formats.
- All timestamps are UTC instants.
- All decimal calculations use base-10 decimal arithmetic. Binary floating-point output MUST NOT determine a persisted score.
- Every version field identifies an immutable policy or definition. Reusing a version identifier for changed content is prohibited.
- OD-001, OD-002, OD-003, and OD-009 remain owner approvals. The interim policies in this document are mandatory until an approved replacement version becomes effective.

## Conceptual Chain

1. Evidence capture and validation.
2. Check execution against a versioned definition and frozen input set.
3. Issue creation or same-run replay resolution.
4. Issue adjudication when review is required or a published Issue is disputed.
5. Score Contribution attribution under a versioned score policy.
6. Immutable ScoreSnapshot creation.
7. Recommendation Artifact generation from score-eligible Issues.
8. Priority Decision generation from published, score-eligible Issues.
9. Reassessment, Issue supersession, and historical comparison.

## Evidence Contract

### Required Attributes

Every Evidence record MUST contain:

- `evidence_id`
- `schema_version`
- `organization_id`
- `project_id`
- `source_id`, nullable only for project-level external measurements
- `evaluation_id`, nullable only for ownership-verification evidence captured before an Evaluation exists
- `evidence_type`: one of `crawl_observation`, `parsed_content`, `external_measurement`, `verification_observation`, or `operator_submission`
- `payload_reference`: an immutable reference to the retained observation or artifact
- `content_sha256`: lowercase 64-character SHA-256 hexadecimal digest of the referenced bytes
- `captured_at_utc`
- `observed_at_utc`
- `source_system`
- `collection_method`
- `collector_version`
- `validation_status`: one of `valid`, `invalid`, or `quarantined`
- `validation_reason_code`, null only when `validation_status=valid`
- `data_classification`: one of `public`, `internal`, `confidential`, or `restricted`
- `retention_class`
- `correlation_id`

### Data Classification Semantics

Classification order is `public < internal < confidential < restricted`:

- `public`: lawfully public source content and observations whose disclosure adds no customer-private or security-sensitive context.
- `internal`: F1-derived operational metadata, scores, and customer results intended for authenticated tenant users but containing no customer-provided nonpublic content.
- `confidential`: customer-provided nonpublic content, detailed Evidence, personal or contact data, and tenant-specific exports that are not security secrets.
- `restricted`: credentials, challenge material, security-incident detail, privileged audit content, or any Evidence explicitly placed behind a security grant.

A derived field inherits the strongest classification of any source value or Evidence used to derive it. An approved declassification is a separate immutable record containing source field or Evidence IDs, original and resulting classification, authorizer, reason, policy version, and effective time; it never mutates the source Evidence. Unknown classification is treated as `restricted`.

### Validation Rules

1. Referenced Organization, Project, Source, and Evaluation records MUST belong to the same Organization.
2. `content_sha256` MUST be recomputed and matched before Evidence becomes `valid`.
3. The retained bytes, content digest, tenant references, provenance fields, and classification are immutable after creation. A corrected observation creates a new Evidence record.
4. Only effectively `valid` Evidence under its latest Validation Decision may support an Issue, included Score Contribution, Recommendation Artifact, or customer-visible citation. The sole exception is a zero-value, excluded `invalid_evidence` diagnostic Contribution in an unavailable calculation; it explains the failure and is never score support or promotion input.
5. Cross-Organization references, missing referenced bytes, digest mismatch, or unknown schema version MUST reject the downstream write with a data-integrity error and an audit event.
6. Every persisted Issue, including a withheld Issue in review, MUST reference at least one effectively valid Evidence record at creation.

`validation_status` is the immutable creation-time decision made by the tenant-scoped integrity-validation service. A later determination appends an immutable Evidence Validation Decision containing decision ID, Evidence ID, prior and resulting effective status, reason code, authority, policy version, `decided_at_utc`, state version, and correlation ID. Valid transitions and authority are exhaustive:

- `valid -> quarantined` for `security_restriction`, `consent_review`, `retention_review`, `digest_recheck_required`, or `schema_recheck_required`. The integrity-validation service may use any listed reason; a SecurityOperator in authorized scope may use only the first three.
- `quarantined -> valid` only by the integrity-validation service after retained bytes, digest, schema, tenant references, consent/retention state, and authority all pass again; reason is `revalidation_passed`.
- `valid -> invalid` or `quarantined -> invalid` only by the integrity-validation service for `immutable_bytes_missing`, `digest_mismatch`, `schema_unsupported`, or `legal_deletion_completed` after the corresponding condition is conclusive.

No same-status Decision is created. `invalid` is terminal; corrected content is new Evidence. Every accepted transition emits `EvidenceValidationChanged` in the same transaction. Check Results and historical snapshots retain the Validation Decision IDs/statuses frozen when they were created and never mutate. A transition away from `valid` atomically performs every applicable current effect before the Decision commits: if the Evidence supports a selected current Issue or any passed/failed Check Result supplying current pillar coverage, mark the Current Score Projection unavailable, add `invalid_evidence` to its de-duplicated fixed-precedence reason set, and suppress every published Recommendation Artifact whose origin Issue is affected; independently, suppress every published Artifact whose rationale or Citation references that Evidence. The event then triggers idempotent score and Recommendation recalculation, which replaces the complete reason set with all and only reasons applicable to the recalculated inputs. A later `quarantined -> valid` triggers recalculation, removes `invalid_evidence` only when no selected score input has invalid Evidence, and may restore a promoted snapshot and eligible Recommendation Artifacts. No automatic republication occurs until every publication predicate passes again.

## Ownership-Verification Evidence Contract

This logical contract operationalizes the OD-001 interim method set without resolving the owner approval.

### Verification Request

Every verification request MUST contain:

- `verification_request_id`
- `schema_version`
- `organization_id`, `project_id`, and `source_id`
- `request_initiator_account_id`
- `method`: `dns_txt` or `http_file`; every other value is rejected as `unsupported_method`
- `canonical_host`
- `challenge_token_sha256`
- restricted `challenge_ciphertext_reference` and `challenge_key_id`, nullable only after terminal cryptographic deletion
- `initial_challenge_delivered_at_utc`
- `issued_at_utc`
- `expires_at_utc`, exactly 24 hours after `issued_at_utc`
- `idempotency_key`
- `request_status`: `pending`, `verified`, `expired`, `canceled`, or `failed`
- `attempt_count`
- `on_demand_observation_count`, initially zero
- `on_demand_in_progress_attempt_id`, nullable
- `last_on_demand_completed_at_utc`, nullable before the first completed on-demand observation
- `last_observed_at_utc`, nullable before the first observation and otherwise equal to the latest completed observation's `completed_at_utc`
- `decision_reason_code`, nullable while pending
- `state_version`

The challenge token MUST contain at least 128 bits of cryptographically random entropy. It is never persisted or logged in plaintext. Request creation envelope-encrypts it under a request-specific key, persists only the restricted ciphertext reference/key identifier and hash, and returns the plaintext through the authorized creation response. Exact creation-command replay by the original actor while the Request remains pending may decrypt and return the same token without changing the Request, expiry, counts, idempotent result, or domain-event set. A separate nonmutating pending-challenge retrieval names the Request ID and requires either the request initiator or an OrganizationAdmin holding `source.verify` in the Request Organization; it returns the same token and no other Request's material. Both paths reauthorize every read and append a restricted security access log without changing domain state. On verified, expired, canceled, or failed transition, the same transaction schedules cryptographic deletion and makes redelivery unavailable immediately; the key and ciphertext are destroyed within 60 seconds, while the digest and access audit remain. A terminal replay or retrieval returns identifiers/status but never challenge material. Decryption failure returns `challenge_redelivery_unavailable`, changes no Request/Source state, and permits authorized cancellation followed by a new Request. Reusing an idempotency key with different canonical request content is rejected as `idempotency_conflict`.

At most one pending Verification Request may exist per Source. A different nonreplay request while one is pending is rejected as `verification_in_progress` before token issuance. A request for a verified, active, disabled, or removed Source is rejected as `source_not_proposed`. The pending-request check, request creation, and Source state-version check are atomic.

### DNS TXT Method

- Observation location: `_f1-verify.<canonical_host>`.
- Required TXT value: the exact ASCII string `f1-verification=<challenge-token>`.
- Multiple TXT records MAY exist; exactly matching any complete TXT value succeeds.
- TXT segment concatenation follows DNS semantics before comparison. Case, whitespace, prefix, or suffix differences fail the observation.
- For `observed_value_sha256`, join character-string segments within each TXT record in resolver-returned order, encode each complete value as UTF-8, concatenate complete records in resolver-returned order separated by one line-feed byte, and hash those bytes before comparison. An absent response has a null hash.
- A DNS lookup has a 10-second timeout. Resolver timeout and temporary resolver failure are retryable; NXDOMAIN and value mismatch remain pending until a later attempt or expiry.

### HTTP File Method

- Observation location: `https://<canonical_host>/.well-known/f1-verification.txt`.
- The request MUST use HTTPS with successful certificate and host validation.
- Redirects are not followed.
- A successful observation requires HTTP `200`, a response body no larger than 4 KiB, and UTF-8 body equal to `f1-verification=<challenge-token>` after removal of at most one trailing line feed. Body reading ignores declared `Content-Length` for the retained observation and stops after end-of-body or exactly 4,097 received entity-body bytes, whichever comes first; 4,097 bytes proves `http_body_too_large` and no later byte is read.
- `observed_value_sha256` is SHA-256 over all raw received entity-body bytes before UTF-8 decoding or trailing-line-feed removal: the complete body when at most 4,096 bytes, or exactly the first 4,097 bytes when oversized. `received_byte_count` follows the same rule.
- Any other status, body, host, scheme, certificate result, or body length fails that observation.
- Connection plus response timeout is 10 seconds. Transport timeout and HTTP `408` map to `http_timeout`; `429` maps to `http_rate_limited`; `5xx` maps to `http_server_error`; every other non-`200` status maps to `http_status_mismatch`. These outcomes remain pending until a later attempt or expiry.

### Attempts, Expiry, And Evidence

- Automated observation slots have due offsets 0, 5, 15, 30, 60, 120, 240, 480, 960, and 1,380 minutes after issuance. Each slot may start only in its half-open window from its due time to the next offset; the final window ends at expiry. If it has not started when the next window begins, it is recorded once as `observation_slot_skipped` and MUST NOT run late. At an exact boundary, the earlier slot is skipped and the later slot is eligible. Terminal request state cancels all remaining slots without skipped events.
- An authorized user MAY request at most 10 on-demand observations in addition to the automated schedule. Acceptance serializes on the Verification Request. It rejects with `on_demand_limit_reached` when `on_demand_observation_count=10`, with `on_demand_observation_in_progress` while `on_demand_in_progress_attempt_id` is nonnull, or with `on_demand_rate_limited` when `last_on_demand_completed_at_utc` is nonnull and `now_utc < last_on_demand_completed_at_utc + 5 minutes`. Equality at the five-minute boundary is allowed. An accepted command atomically assigns the attempt ID, increments both on-demand and total attempt counts, and stores the in-progress marker before the provider call; concurrent commands therefore cannot reserve the same slot. Its completion transaction clears the marker and sets `last_on_demand_completed_at_utc=completed_at_utc`. Provider timeout still completes the observation. If completion persistence fails, the same reserved attempt is retried idempotently and no second count is consumed.
- `attempt_count` increments only when an automated or accepted on-demand provider observation starts. A skipped slot or rejected rate-limited, over-limit, terminal-state, or unauthorized request does not increment it.
- Verification success must be observed and atomically committed before `expires_at_utc`. At exactly `expires_at_utc`, expiry wins; an observation completing at or after that instant cannot verify the request.
- Every started observation ultimately persists exactly one restricted `verification_observation` Evidence, updates Request completion/last-observed fields, and appends exactly one `SourceVerificationObserved` referencing it; transaction failure exposes none of the completion writes and the same reserved slot/attempt identity is retried idempotently. A success includes that work plus Verification Request `verified` with reason `matched`, immediate challenge-redelivery disablement, `SourceVerified`, materialization of `source-scope-interim-v1`, and `Source.Proposed -> Source.Verified` in the same transaction; none may appear without the others.
- Mismatch or dependency failure MUST NOT change the Source lifecycle state. At `expires_at_utc`, a still-pending request becomes `expired` with reason `challenge_expired`, emits `SourceVerificationExpired`, and the Source remains `proposed`.
- The request initiator or an OrganizationAdmin holding `source.verify` may cancel only a pending request using its expected state version. Requester cancellation uses `canceled_by_requester`; an OrganizationAdmin canceling another initiator's request uses `canceled_by_admin`. Cancellation emits `SourceVerificationCanceled` and leaves the Source proposed.
- `failed` may be written only by the integrity-validation service for a nonretryable persisted-request integrity failure discovered after issuance. Missing immutable challenge digest uses `request_digest_unavailable`; unsupported stored schema uses `request_schema_unsupported`. These are the exhaustive failed reasons. Failure stops all observations, emits `SourceVerificationFailed`, and leaves the Source proposed. DNS, HTTP, resolver, certificate, status, content, and timeout outcomes never use `failed`; they remain pending until success, cancellation, or expiry.
- Retry after `expired`, `canceled`, or `failed` creates a new Verification Request and token. It MUST NOT reactivate or mutate the terminal request.
- Every started provider observation creates one restricted `verification_observation` Evidence record, whether matched, not matched, or indeterminate. Its typed payload contains `verification_request_id`, method, canonical observation location, attempt number and origin (`automated` or `on_demand`), nullable automated-slot offset, started/completed times, network outcome (`response`, `timeout`, `resolver_failure`, `connection_failure`, or `tls_failure`), nullable HTTP status or DNS response code, received byte count, nullable `observed_value_sha256` computed by the method rule above, match decision (`matched`, `not_matched`, or `indeterminate`), and exactly one reason code: `matched`, `dns_nxdomain`, `dns_value_mismatch`, `dns_timeout`, `dns_temporary_failure`, `http_status_mismatch`, `http_content_mismatch`, `http_body_too_large`, `http_redirect_rejected`, `http_timeout`, `http_rate_limited`, `http_server_error`, `tls_validation_failed`, or `connection_failure`. Provider text is reduced to the enum/status fields; header values, response body, DNS value, host addresses, and unrestricted error text are discarded. Expiry, cancellation, skipped slots, and request-integrity failure are Request decisions or scheduler records, not fabricated provider-observation Evidence. The payload MUST NOT retain or expose the plaintext challenge token or raw DNS/HTTP content containing it.

## Check Result Contract

### Required Attributes

Every Check Result MUST contain:

- `check_result_id`
- `organization_id`, `project_id`, and `evaluation_id`
- `check_definition_id` and `check_definition_version`
- `pillar_id`
- ordered `evidence_references`
- ordered Evidence Validation Decision ID/status pairs effective as of Check creation
- `evidence_set_hash`
- `execution_status`: `passed`, `failed`, `not_applicable`, or `error`
- `outcome_code`
- `normalized_observation`
- `impact_band`, required for `failed` and null for `passed`, `not_applicable`, or `error`
- `impact_rule_version`
- `confidence_value`, a decimal from `0.0000` through `1.0000`, nullable only when confidence is missing or invalid
- `confidence_status`: `valid`, `missing`, or `invalid`
- `confidence_band`: `low`, `medium`, or `high`
- `confidence_policy_version`
- `rule_or_model_version`
- `deterministic_input_hash`
- `produced_at_utc`

### Deterministic Input And Output

The canonical input tuple is the ordered tuple of Organization, Project, Evaluation input-snapshot identifier, Check Definition identifier and version, pillar identifier, sorted Evidence identifiers and digests, policy versions including impact rule, rule or model version, locale, and time-zone assumption. Locale is `en-AU` and the time-zone assumption is UTC unless the Check Definition explicitly versions another value.

`deterministic_input_hash` is SHA-256 over UTF-8 canonical JSON with keys sorted lexicographically, no insignificant whitespace, decimal values rendered without exponent notation, arrays in declared order, and strings normalized to Unicode NFC. Two executions with the same canonical input tuple MUST produce the same semantic output tuple: execution status, outcome code, normalized observation, impact band, confidence value or status, confidence band, and pillar identifier. Generated identifiers and timestamps are excluded from semantic equality.

Every immutable Check Definition MUST contain an exact impact rule mapping its normalized failed observation to one of `informational`, `low`, `medium`, `high`, or `critical`. The mapping may be constant or threshold-based but MUST include complete boundary fixtures and `impact_rule_version`. Missing or unmapped impact changes the Check Result to `error` and creates no Issue. Manual or AI post-hoc impact changes are prohibited; changed mapping requires a new Check Definition and impact-rule version and a new Evaluation or explicit policy recalculation.

### Interim Confidence Policy `confidence-interim-v1`

- Valid numeric domain: `0.0000` through `1.0000`, rounded half up to four decimal places before band mapping.
- `low`: `0.0000 <= value < 0.6000`.
- `medium`: `0.6000 <= value < 0.8500`.
- `high`: `0.8500 <= value <= 1.0000`.
- A deterministic binary check uses `1.0000` unless its immutable Check Definition declares a different calibrated confidence rule.
- Missing or invalid confidence maps to display band `low`, creates an Issue with adjudication status `review_required`, and records `confidence_status`; the raw invalid value MUST NOT be used downstream.

### Check-To-Issue Rules

- `passed` and `not_applicable` create no Issue.
- `error` creates no Issue and contributes to coverage failure or partial coverage.
- `failed` with valid medium or high confidence creates a published, open Issue.
- `failed` with low, missing, or invalid confidence creates a withheld candidate Issue in `review_required` adjudication status.
- A Check Result MUST map to exactly one pillar. Multi-pillar allocation and duplicate score contribution are prohibited; a related Issue MAY inform multiple Recommendation Artifacts but contributes to one pillar only.

## Pillar Contract

| Pillar ID | Canonical Name | Included Signal Boundary | Explicit Exclusions |
| --- | --- | --- | --- |
| `technical_integrity` | Technical Integrity | crawlability, transport, rendering, performance, canonicalization, redirects, sitemaps, robots directives, link integrity, and machine-readable technical health | content meaning, authority, and external search presence |
| `search_presence` | Search Presence | observed indexing, result-surface presence, query coverage, search snippets, and search-engine accessibility outcomes | on-site technical implementation and AI answer presence |
| `ai_presence` | AI Presence | observed or measured representation, citation, retrieval readiness, and answer-surface presence in approved AI channels | general search ranking and unvalidated model opinion |
| `authority_signals` | Authority Signals | attributable external links, mentions, citations, entity authority, and source reputation signals | first-party content quality and local listing completeness |
| `trust_signals` | Trust Signals | identity consistency, security/trust disclosures, authorship, policy transparency, review/reputation evidence, and verifiable credibility signals | raw authority volume and technical transport checks already allocated elsewhere |
| `content_quality` | Content Quality | relevance, completeness, originality, semantic clarity, structure, freshness, and answer usefulness of first-party content | transport, indexing presence, and external authority |
| `local_presence` | Local Presence | location/service-area identity, local listing consistency, local citations, and local-intent presence | non-local search and general organization authority |

Every score-capable Check Definition MUST name exactly one Pillar ID. Changing a Check Definition's Pillar ID is a breaking score-model change and requires a new Check Definition version and score-policy version.

## Issue Contract

### Required Attributes

Every Issue MUST contain:

- `issue_id`
- `organization_id`, `project_id`, `source_id`, and `evaluation_id`; `source_id` is nullable only when the immutable Check Definition declares `subject_scope=project`
- `check_result_id`, `check_definition_id`, and `check_definition_version`
- `issue_type`
- `pillar_id`
- `canonical_subject_type` and `canonical_subject_key`
- `fingerprint_version`, `fingerprint_sha256`, and retained `fingerprint_preimage`
- `impact_band`: `informational`, `low`, `medium`, `high`, or `critical`
- `confidence_value`, nullable only under the confidence fallback rule
- `confidence_status` and `confidence_band`
- `lifecycle_status`: `candidate`, `open`, `resolved`, `dismissed`, or `superseded`
- `adjudication_status`: `not_required`, `review_required`, `disputed`, `in_review`, `upheld`, `rejected`, `withdrawn`, or `obsolete`
- `publication_status`: `withheld`, `published`, or `suppressed`
- one or more `evidence_references`
- `first_seen_at_utc` and `last_seen_at_utc`
- `supersedes_issue_id`, nullable for the first Issue in a lineage
- `lineage_reason`, nullable only when `supersedes_issue_id` is null
- `closure_reason_code`, nullable until resolved, dismissed, or superseded
- `closure_evaluation_id`, `closure_check_result_id`, and `closure_evidence_references`, required for resolved or superseded status and otherwise null
- `active_adjudication_case_id`, nonnull only while the current case is open
- `latest_adjudication_case_id`, nullable only when no adjudication case has ever existed
- `state_version`
- `created_at_utc` and `updated_at_utc`

### Adjudication Case Contract

An Adjudication Case is the immutable-history logical record for one review or dispute; it is not a second deficiency entity. Every case contains `adjudication_case_id`, `organization_id`, `project_id`, `issue_id`, `case_type` (`system_review` or `customer_dispute`), `case_status` (`requested`, `assigned`, `upheld`, `rejected`, `withdrawn`, or `obsolete`), `requested_by_actor_id` or service identity, `requested_at_utc`, nonblank `request_reason`, `assigned_at_utc`, `adjudicator_actor_id`, `decision_at_utc`, `decision_actor_id`, `decision_reason_code`, `decision_rationale`, `due_at_utc`, `sla_status` (`within_sla`, `overdue`, `critical`, or `closed`), nullable `preceding_case_id`, nullable `carried_from_case_id`, nullable `overdue_event_emitted_at_utc`, nullable `critical_event_emitted_at_utc`, `last_reminder_sequence` initially zero, `state_version`, and creation/update timestamps. Fields not yet applicable are null. `preceding_case_id` links an earlier Case for the lineage without inheriting its SLA; `carried_from_case_id` is nonnull only when reassessment carries the same open Case obligation and its SLA cursor.

`requested -> assigned`; `assigned -> upheld or rejected`; `requested or assigned customer_dispute -> withdrawn`; and `requested or assigned -> obsolete` on reassessment are the only case transitions. Closed case content is immutable. The Issue's `adjudication_status` is the current projection of its active or latest case: requested system review maps to `review_required`, requested customer dispute to `disputed`, assigned to `in_review`, and the four closed outcomes to the same-named Issue status. A closed case clears `active_adjudication_case_id` and remains referenced by `latest_adjudication_case_id`. A later valid dispute creates a new Case with `preceding_case_id` equal to the prior latest Case and a new 24-hour SLA; it never overwrites or inherits an earlier case's SLA and decision history.

Case reason and terminal fields are exact:

- A system-review request uses `request_reason` equal to `low_confidence`, `missing_confidence`, or `invalid_confidence` from the Check Result, except that a recurrence after a dismissed predecessor uses `recurrence_after_dismissal`. A customer dispute stores the submitter's 20-2,000 character text. While requested or assigned, all decision fields are null.
- Uphold sets `decision_reason_code=issue_valid`, the assigned adjudicator as decision actor, decision commit time, and the required 20-4,000 character rationale.
- Reject sets one of `false_positive`, `not_applicable`, `insufficient_evidence`, or `out_of_scope`, the assigned adjudicator/time, and the required 20-4,000 character rationale.
- Withdrawal requires a 20-2,000 character command reason, sets decision actor/time to the requester or acting OrganizationAdmin, uses `withdrawn_by_requester` or `withdrawn_by_admin`, and copies that reason to `decision_rationale`.
- Obsoletion sets the reassessment service as decision actor, publication-transaction time, reason `case_carried_to_successor` when a successor Case carries it or `condition_absent` when no condition remains, and null decision rationale. Every closed Case sets `sla_status=closed`; its due time and emitted-event cursor remain immutable.

For a rejected Case, the Issue's required `closure_reason_code` is exactly the Case `decision_reason_code`; its closure Evaluation, Check Result, and Evidence fields remain null because adjudication dismissal is not an observed-absence closure. For a resolved or superseded Issue, `closure_check_result_id` is the exact proving or successor Check Result named by the reconciliation rule, and `closure_evidence_references` is exactly that Check Result's frozen Evidence list.

### Lifecycle And Adjudication State Machine

| Trigger | Required From State | Result | Authority | Deterministic Conditions |
| --- | --- | --- | --- | --- |
| medium/high-confidence failed check | no same-run Issue | `open / not_required / published` | tenant-scoped evaluation service identity | valid Evidence and Check Result; atomic deduplication succeeds |
| low/missing/invalid-confidence failed check | no same-run Issue | `candidate / review_required / withheld` | tenant-scoped evaluation service identity | adjudication case created with due time 48 hours after creation |
| submit dispute | `open / not_required`, `open / upheld`, or `open / withdrawn` | `open / disputed / suppressed` | OrganizationAdmin, MarketingOperator, or TechnicalImplementer holding `issue.dispute` | create a new customer-dispute Case due 24 hours after submission; nonblank 20-2,000 character reason; expected `state_version`; requester can read the Issue |
| assign adjudicator | `review_required` or `disputed` | same lifecycle / `in_review` / unchanged publication | SecurityOperator or time-bounded support session holding `issue.adjudicate` | adjudicator differs from requester; expected Issue and Case state versions |
| uphold | `in_review` | `open / upheld / published` | assigned actor holding `issue.adjudicate` | reason `issue_valid`; 20-4,000 character rationale; expected Issue and Case state versions; same current Issue lineage leaf |
| reject as invalid or not applicable | `in_review` | `dismissed / rejected / suppressed` | assigned actor holding `issue.adjudicate` | enumerated reject reason and 20-4,000 character rationale; expected Issue and Case state versions |
| withdraw dispute | `disputed` or `in_review` originating from a dispute | `open / withdrawn / published` | original requester or OrganizationAdmin holding `issue.dispute` | allowed before decision; expected Issue and Case versions; 20-2,000 character reason |
| completed reassessment no longer observes condition without pending adjudication | current `open` leaf with `not_required`, `upheld`, or `withdrawn` | `resolved / preserve prior adjudication status / suppressed` | reassessment service identity | completed replacement Evaluation; closure Evidence and reason `condition_absent` |
| completed reassessment no longer observes condition with pending adjudication | current `candidate` or `open` leaf with `review_required`, `disputed`, or `in_review` | `resolved / obsolete / suppressed` | reassessment service identity | completed replacement Evaluation; closure Evidence and reason `condition_absent`; pending case closes obsolete |
| completed reassessment observes same fingerprint | current `candidate` or `open` leaf | predecessor becomes `superseded / preserve adjudication unless an active case becomes obsolete / suppressed`; immutable successor becomes current | reassessment service identity | atomic supersession rules below |

All unspecified transitions are invalid, rejected with a domain conflict, and audited. `resolved`, `dismissed`, and `superseded` are terminal for that Issue record. Reappearance creates a new Issue; it never reopens or mutates a terminal record.

### Adjudication SLA, Timeout, And Races

- A system-created `review_required` case is due 48 elapsed hours after Issue creation. A user dispute is due 24 elapsed hours after dispute submission.
- At the due time, an unresolved case remains score- and priority-ineligible, `sla_status` becomes `overdue`, and exactly one `IssueAdjudicationOverdue` event is emitted to the SecurityOperator support queue. No automatic uphold or dismissal is permitted.
- While the case remains open, one `IssueAdjudicationReminder` is emitted at `due_at_utc + 24 hours * n` for every integer `n >= 1`. It contains Case/Issue IDs, due time, `reminder_sequence=n`, current SLA status, and original request time and routes through the mandatory support-queue route. At exactly 168 elapsed hours after the original request, `sla_status` becomes `critical` and exactly one `IssueAdjudicationCritical` event replaces any reminder due at that same instant; `last_reminder_sequence` still advances past the replaced sequence so it is never emitted later. Later daily reminders continue. Closing the case cancels future scheduled SLA events.
- Submit-dispute commands carry expected Issue state version. Assignment, decision, and withdrawal commands carry both expected Issue and expected Adjudication Case state versions. A command is idempotent by `adjudication_case_id`, action, and command idempotency key. Exact replay returns the stored outcome without another event or recalculation.
- A command carrying either stale required version, targeting a terminal Issue, or targeting a non-current lineage leaf is rejected as `stale_issue_version`; a current Issue with a stale Case version uses `stale_case_version`. If reassessment supersedes a case, the old case becomes `obsolete` and cannot decide the successor.
- At exactly any due, reminder, or critical scheduler instant, the SLA scheduler transition/cursor and event commit before assignment, decision, withdrawal, or reassessment obsoletion/carry at the same timestamp. A later command may close or carry the Case; the emitted event remains historical and is not retracted or re-emitted.
- When a reassessment observes the same fingerprint while a predecessor Case is open, that Case becomes `obsolete` and a successor Case is created with both `preceding_case_id` and `carried_from_case_id` equal to the predecessor Case, the same case type, original requester, request reason, `requested_at_utc`, `due_at_utc`, SLA status, `overdue_event_emitted_at_utc`, `critical_event_emitted_at_utc`, and `last_reminder_sequence`. System review maps the successor to `candidate / review_required / withheld`; customer dispute maps it to `open / disputed / suppressed`. If the predecessor was assigned and its adjudicator remains authorized at the reassessment checkpoint, the assignment and `in_review` projection carry; otherwise the successor is unassigned and uses its case-type projection. Already-emitted overdue, critical, and reminder events are never re-emitted for the successor; future reminders continue at the next sequence from the original request time. No new SLA clock starts.
- Before an accepted dispute, uphold, reject, or withdrawal commits, the same transaction marks the Current Score Projection `unavailable`, retains its current/last-promoted pointers for history only, unions `issue_set_incomplete` into the fixed-precedence unavailable-reason set, sets `recommendation_suppression_required=true`, and suppresses every published Recommendation Artifact whose `origin_issue_id` is the affected Issue. The corresponding `IssueAdjudicated`, `IssueDisputed`, or `IssueDisputeWithdrawn` event triggers idempotent score recalculation. Recalculation creates or reuses an immutable ScoreSnapshot, replaces the unavailable-reason set with all and only then-applicable reasons, and refreshes downstream current projections; it never mutates an earlier snapshot. No current read may return the stale pre-transition numeric score between the Issue transition and recalculation.
- A Recommendation Artifact may be drafted for a withheld origin Issue but MUST NOT be published or prioritized. Every published Artifact with that origin becomes suppressed when the origin becomes ineligible and may be republished only after that origin and all Artifact validation predicates pass again; optional related Issues never govern this transition.

## Deduplication Fingerprint And Idempotency

### Canonical Hash Contract

Unless a narrower contract says otherwise, every model hash uses the canonical JSON, Unicode, decimal, and SHA-256 rules defined for `deterministic_input_hash`.

- A Check Result's `evidence_set_hash` contains Evidence IDs, content digests, schema versions, and the effective Validation Decision ID/status as of Check creation, sorted by Evidence ID. A later Decision never changes that Check Result or hash.
- `contribution_input_hash` contains Issue ID and state version, Check Result ID, sorted Evidence IDs/digests and latest effective Validation Decision IDs/statuses as of calculation, pillar, impact, penalty, inclusion decision and reason, scope-definition hash, and all score/confidence/eligibility policy versions.
- `input_set_hash` contains Evaluation ID, Issue-set ID, scope-definition hash, check-catalog and applicability versions, every governing policy version, the exact coverage inputs below including current Evidence Validation Decisions for every score-capable Check Result, and all Score Contribution semantic tuples sorted by Issue ID. A Contribution semantic tuple contains exactly Issue ID/state version, lifecycle/adjudication/publication states, current-leaf boolean, nullable active/latest Case IDs, ordered Evidence ID/digest/Validation-Decision tuples, pillar, impact, penalty, signed value, included boolean, exclusion reason, ordered rationale Evidence IDs, policy versions, and `contribution_input_hash`; it excludes `score_contribution_id` and the circular `score_snapshot_id` back-reference.

`scope_definition_hash` is SHA-256 over canonical JSON containing Organization ID, Project ID, and the complete active Source set sorted by Source ID. Each Source tuple contains Source ID, canonical host, lifecycle status `active`, and its active Source Scope Policy ID, version, content hash, normalized allowed schemes, allowed ports, include prefixes, exclude prefixes, and query-handling rule. The preimage also contains active Organization- and Project-scope Source Scope Policy IDs, versions, content hashes, and normalized rules, sorted by scope then policy ID. It contains no capture timestamp or generated snapshot ID. The baseline preimage always covers every active Project Source; omission of one makes the hash invalid.

Coverage inputs in `input_set_hash` are Crawl ID, `coverage_status`, `completion_reason`, each Source/root terminal status and reason sorted by Source ID then canonical root URL, accepted Document IDs sorted by ID, failed or omitted canonical candidate URLs with reason sorted by URL, and each applicable pillar's score-capable Check Result ID, execution status, and sorted Evidence ID/current effective Validation Decision ID/status tuples, sorted by pillar then Check Result ID. A count without the listed identities is insufficient.

Generated IDs for the record being hashed, creation timestamps, correlation IDs, and presentation-only fields are excluded. Any semantic input change MUST change the corresponding hash; ordering or serialization variation alone MUST NOT.

### Fingerprint `issue-fingerprint-v1`

The fingerprint preimage is canonical JSON containing exactly:

1. `organization_id`
2. `project_id`
3. `source_id`
4. `check_definition_id`
5. `issue_type`
6. `canonical_subject_type`
7. `canonical_subject_key`

Keys are sorted lexicographically, strings are Unicode NFC and trimmed, and no insignificant whitespace is emitted. Identifiers and case-sensitive subject values otherwise retain case.

For a URL subject key, canonicalization MUST lowercase scheme and IDNA ASCII host, remove the default port, remove the fragment, resolve dot segments, use `/` for an empty path, normalize percent-encoded unreserved characters, and sort query pairs by decoded key then decoded value while preserving duplicates. User information is prohibited. For non-URL subjects, the immutable Check Definition MUST declare its canonicalization algorithm and test fixtures.

`fingerprint_sha256` is SHA-256 over the UTF-8 preimage. A semantic change to the tuple or canonicalization requires a new fingerprint version.

### Replay And Collision Behavior

- Within one Evaluation, uniqueness authority is the full tuple `(evaluation_id, fingerprint_version, fingerprint_preimage)`, not the hash alone.
- An atomic create with an exact existing tuple returns the existing Issue and stored command result. It MUST NOT create another Issue or emit another `IssueCreated` event.
- Concurrent exact creates have the same result as sequential replay.
- If the hash matches but the retained preimage differs, the records MUST NOT merge. The second full tuple may create its own Issue in the hash bucket, and the system emits `IssueFingerprintCollision` with restricted data-integrity telemetry. The full preimage remains authoritative.
- Cross-Evaluation equality is a reassessment match, not same-run deduplication, and follows supersession rules.

## Supersession And Reassessment Semantics

Issues are immutable observation versions except for controlled lifecycle, adjudication, and audit metadata transitions. A completed reassessment publishes a replacement Issue set atomically. Baseline reassessment covers every active Source in the Project; scope-limited requests are rejected before execution. Equality of prior and current `scope_snapshot_id` is not required when the normalized full-Project scope-definition hash is unchanged.

An immutable Issue Set contains `issue_set_id`, Organization, Project, originating Evaluation, ordered Issue IDs, ordered current-leaf Issue IDs, a content hash, and `sealed_at_utc`. Its membership is exactly every Issue in the Project lineage graph that existed at the seal checkpoint and is either a current leaf or an ancestor of a current leaf; later-created Issues never enter an earlier set. It therefore includes terminal current leaves and non-current ancestors. It contains exactly one current leaf for every full fingerprint identity represented in the Project at that checkpoint. Both lists are ordered by fingerprint preimage, then Issue originating-Evaluation creation time, then Issue ID. Reassessment membership is the prior current set union every successor and new Issue created by the two passes below. Adjudication, Evidence, and policy recalculation reuse the current set membership while freezing each member's then-current state version in Contributions.

Every immutable Check Definition declares one `absence_proof_mode` and an `absence_coverage_selector` containing its governed Source IDs and canonical subject namespace or path predicate. “Full relevant coverage” means the replacement Crawl/Check coverage inputs contain a terminal covered outcome for every admitted candidate matching that exact selector and contain no matching failed, omitted, or limit-discarded candidate.

- `check_pass_resolves_all`: a `passed` replacement Check Result for the same definition and exact `absence_coverage_selector`, with valid Evidence and full relevant coverage, proves absence for every predecessor governed by that selector.
- `observed_subject_set`: a terminal `passed` or `failed` replacement Check Result may prove absence only when it contains an immutable exhaustive canonical subject set, `subject_set_complete=true`, valid Evidence, and full relevant coverage, and the predecessor's canonical subject is absent from that set.
- `never_automatic`: absence never resolves an Issue automatically; it remains `resolution_unverified` until an explicit future governed rule applies.

`not_applicable`, `error`, a missing Check Result for the predecessor's Check Definition/selector, incomplete relevant coverage, invalid Evidence, or a Check Definition without a recognized mode never proves absence. Closure Evidence is exactly the proving Check Result and all of its frozen Evidence references.

Reconciliation uses two ordered passes. First, process each current predecessor Issue exactly once in fingerprint-preimage then Issue-ID order:

1. If its fingerprint is observed and the predecessor is `candidate` or `open`, create one successor with a new Issue ID, `supersedes_issue_id` pointing to the predecessor, and `lineage_reason=condition_persisted`; carry `first_seen_at_utc`; set successor `last_seen_at_utc` to the new observation time. The predecessor becomes superseded/suppressed with closure reason `condition_persists_in_successor`, closure Evaluation, and the successor Check Result/Evidence as closure Evidence. An open Case follows the obsolete-and-carry rule. With no open Case, derive the successor state afresh from current confidence, including a new system-review Case for low, missing, or invalid confidence; prior `upheld` or `withdrawn` remains historical.
2. If its fingerprint is observed and the predecessor is terminal `dismissed`, create a new `candidate / review_required / withheld` successor with `supersedes_issue_id` pointing to the predecessor and `lineage_reason=condition_recurred_after_dismissal`; do not mutate the predecessor. In the same transaction create a new system-review Case with reason `recurrence_after_dismissal`, `preceding_case_id` equal to the predecessor's latest Case when present, request time equal to successor creation, and due time 48 hours later; do not carry its prior SLA. If the terminal predecessor is `resolved`, create a successor with `supersedes_issue_id` pointing to the predecessor and `lineage_reason=condition_recurred_after_resolution`, leave the predecessor unchanged, and derive state from current confidence.
3. If its fingerprint is not observed, the predecessor is `candidate` or `open`, and the replacement Check Result for its Check Definition/selector satisfies the declared absence-proof mode, set the predecessor to `resolved` with closure reason `condition_absent` and link the exact closure Check Result, its Evidence, and Evaluation.
4. If its fingerprint is not observed, the predecessor is `candidate` or `open`, and absence is not proved for any reason, leave it current and unchanged and add one `resolution_unverified` entry to the Reassessment Result with Issue ID and exactly one reason selected in this precedence: `absence_mode_never_automatic`, `check_not_applicable`, `check_error`, `check_missing`, `coverage_incomplete`, `evidence_invalid`, or `absence_mode_unknown`. Absence under an unrecognized mode, invalid Evidence, or incomplete coverage MUST NOT resolve an Issue. A non-observed terminal `resolved` or `dismissed` current leaf remains unchanged and creates no `resolution_unverified` entry.

Second, process the replacement Evaluation's observed fingerprints in canonical fingerprint-preimage order. For each fingerprint not matched to any predecessor in the first pass, create exactly one new current Issue with no supersedes link and initial state derived from current confidence. This new-fingerprint pass is not repeated per predecessor.

Every supersession link MUST remain in the same Organization and Project, point to an earlier Evaluation, be acyclic, and have at most one direct successor. There MUST be exactly one current leaf per full fingerprint identity; that leaf may be terminal when the condition is resolved or dismissed. A scope change does not fork lineage for an Issue that remains inside the evaluated intersection. Check-definition changes that alter identity create a new fingerprint; automatic split or merge lineage is prohibited. Optional related-Issue references may describe a split or merge but do not affect supersession or score.

Reassessment execution freezes active Source-set version and normalized full-scope definition hash. The publication transaction re-resolves both under lock; any Source activation/disable/removal or normalized scope-policy change produces `source_scope_changed_during_reassessment`, publishes none of the staged result, and requires a new full-scope attempt. Reassessment publication is one atomic domain commit containing: every predecessor lifecycle/Case transition; every successor and new Issue; the sealed replacement `issue_set_id`; all staged Score Contributions and the complete/partial ScoreSnapshot; current Issue-set, ScoreSnapshot, and Current Score Projection pointers; Recommendation suppression/publication deltas; the terminal completed Reassessment Result referencing those exact records; and one entitlement-commit intent in the transactional outbox. WF-008 in reassessment staging mode MUST NOT advance a pointer before this commit. On any validation or persistence failure, none of those writes or the commit intent becomes visible, the last completed Issue set and ScoreSnapshot remain current, and the reservation is released through the failure path. The entitlement service consumes the committed intent exactly once; redelivery cannot double-count. Retrying a failed reassessment uses a new Evaluation attempt linked to the failed one; completed stages may be reused only by immutable input hash.

## Interim Discoverability Score Policy

### Policy Identity And Applicability

The mandatory interim policy is `score-interim-v1`. It remains effective until an approved OD-002 replacement becomes active.

All seven pillars are applicable by default. `local_presence` may be `not_applicable` only when the Project profile explicitly records `local_presence_applicable=false`, an OrganizationAdmin or MarketingOperator records a nonblank reason, and the score-policy snapshot captures that decision version. Every other pillar remains applicable in baseline scope.

Every applicable pillar MUST have at least one valid score-capable Check Result with execution status `passed` or `failed` in the Evaluation. `not_applicable` and `error` do not satisfy coverage. Otherwise that pillar is `insufficient_data` and the overall score is unavailable.

### Impact Penalty Table

| Impact Band | Penalty Points |
| --- | ---: |
| `critical` | 40.0 |
| `high` | 20.0 |
| `medium` | 10.0 |
| `low` | 5.0 |
| `informational` | 0.0 |

An eligible current Issue creates exactly one included Score Contribution for its pillar. Penalties are not multiplied by confidence, occurrence count, source count, or Recommendation count under the interim policy.

### Score Contribution Contract

Scoring selects exactly one immutable `issue_set_id`: either a sealed staged prospective set for an Evaluation completion/reassessment or the already-current set for adjudication/evidence/policy recalculation. “Current” in this section means the prospective current lineage leaf inside that selected set; an initial Evaluation is valid even though no Project current pointer exists yet. Every Issue in the selected set creates one Score Contribution record containing:

- `score_contribution_id`
- `score_snapshot_id`, `issue_set_id`, `issue_id`, and `check_result_id`
- `issue_state_version`
- `lifecycle_status_at_snapshot`, `adjudication_status_at_snapshot`, and `publication_status_at_snapshot`
- `is_current_lineage_leaf_at_snapshot`
- nullable `active_adjudication_case_id_at_snapshot` and `latest_adjudication_case_id_at_snapshot`
- Evidence IDs sorted ascending, with each content digest and effective Validation Decision ID/status as of calculation
- `pillar_id`
- `impact_band`
- `penalty_points`
- `signed_contribution_value`, equal to `-penalty_points` when included and `0.0` when excluded
- `included`
- `exclusion_reason_code`, null only when included
- ordered `rationale_evidence_references`, exactly the Issue's Evidence IDs sorted ascending
- `score_policy_version`, `confidence_policy_version`, and `eligibility_policy_version`
- `contribution_input_hash`

An Issue is included only when all are true in the selected Issue set:

1. `lifecycle_status=open`.
2. `adjudication_status` is `not_required`, `upheld`, or `withdrawn`.
3. `publication_status=published`.
4. It is the prospective current lineage leaf.
5. Every referenced Evidence record is valid and same-Organization.

`penalty_points` always equals the impact-table value even when excluded; only `signed_contribution_value` becomes `0.0`. An excluded Issue receives exactly one reason under this first-match precedence: `superseded` when lifecycle is superseded; `not_current` when it is not the selected current leaf; `invalid_evidence` when any referenced Evidence is not effectively valid; `dismissed`; `resolved`; `in_review`; `disputed`; then `review_required`. A state failing inclusion but matching none of these is `contribution_mismatch` and makes the calculation unavailable rather than inventing a reason. Under the OD-009 interim policy, excluded Issues contribute zero to both score and priority. An `invalid_evidence` contribution is a zero-value diagnostic retained only in an unavailable calculation; any prospective current Issue whose Evidence is not effectively valid makes the overall calculation `unavailable` and prevents snapshot promotion.

### Pillar And Overall Formula

For each applicable pillar:

`raw_pillar_score = 100.0 - sum(included penalty_points for that pillar)`

`pillar_score = min(100.0, max(0.0, raw_pillar_score))`

Pillar scores are persisted to one decimal place using round-half-up. Intermediate sums are not rounded.

Each applicable pillar has equal exact rational weight with `effective_weight_numerator=1` and `effective_weight_denominator=applicable_pillar_count`. Inapplicable pillars have null score, numerator `0`, and denominator `1`. A rounded display weight is nonauthoritative; finite decimal weights are never summed as score inputs.

`overall_score = sum(unrounded applicable pillar_score) / applicable_pillar_count`

The overall score is clamped to `0.0..100.0` and persisted to one decimal place using round-half-up.

### Completeness Status

- `complete`: every applicable pillar has valid terminal coverage; crawl coverage is full; no current Issue is excluded for review, dispute, in-review status, or invalid Evidence.
- `partial`: every applicable pillar can be scored, but crawl coverage is partial or at least one current Issue is excluded for review, dispute, or in-review status. The numeric score MUST be accompanied by excluded-Issue count and coverage reasons.
- `unavailable`: any applicable pillar has zero valid terminal score-capable Check Results, any current Issue references Evidence not effectively valid, the score policy is missing or invalid, or the Issue-set publication is incomplete. Overall score is null and no current ScoreSnapshot is promoted.

## ScoreSnapshot Contract

Every persisted ScoreSnapshot MUST contain:

- `score_snapshot_id`
- `organization_id`, `project_id`, `evaluation_id`, and `issue_set_id`
- `scope_snapshot_id`
- `scope_definition_hash`
- `score_policy_version`, `confidence_policy_version`, `eligibility_policy_version`, and `fingerprint_version`
- `check_catalog_version`, `pillar_applicability_version`, and `scope_policy_version_set_hash`
- per-pillar applicability, status, unrounded calculation value, persisted value, effective-weight numerator and denominator, optional nonauthoritative display weight, included contribution count, excluded Issue count, and ordered coverage reason codes
- `overall_status`: `complete`, `partial`, or `unavailable`
- `overall_score`, null only when unavailable
- `input_set_hash`
- `evidence_validation_decision_set_hash`, over the sorted Evidence ID and effective Validation Decision ID/status tuples used by all Contributions and every score-capable Check Result supplying applicable-pillar coverage
- `prior_score_snapshot_id`, nullable for the first snapshot
- `created_at_utc`
- `creation_reason`: `evaluation_completed`, `issue_adjudicated`, `issue_disputed`, `dispute_withdrawn`, `evidence_validation_changed`, `policy_recalculation`, or `historical_rebase`

Per-pillar status is exactly `not_applicable`, `scored`, `insufficient_data`, or `unavailable`, selected by this first-match order:

1. An inapplicable pillar is `not_applicable`, has null score, weight `0/1`, and sole reason `pillar_not_applicable`.
2. If any of `issue_set_incomplete`, `score_policy_unavailable`, `confidence_policy_unavailable`, `eligibility_policy_unavailable`, `scope_definition_invalid`, `check_catalog_unavailable`, `contribution_mismatch`, or `score_invariant_failure` applies, every applicable pillar is `unavailable` with null score and all applicable codes from that set in overall precedence order; an affected pillar additionally includes `invalid_evidence` in its overall-precedence position, while an unaffected pillar does not.
3. A pillar affected by invalid Evidence in one of its prospective-current Issues or passed/failed coverage Checks is `unavailable` with null score and reason `invalid_evidence`; an unaffected pillar does not inherit another pillar's invalid-Evidence reason.
4. An applicable pillar with zero effectively valid passed/failed score-capable Check Results is `insufficient_data`, has null score, and has sole reason `no_valid_terminal_check`; this derives overall reason `applicable_pillar_insufficient_data`.
5. Every remaining applicable pillar is `scored` with calculated values and the applicable de-duplicated reasons in this order: `crawl_partial`, `review_required_excluded`, `disputed_excluded`, `in_review_excluded`. A fully covered scored pillar has an empty reason list. One unavailable or insufficient pillar makes the overall score unavailable but does not erase reproducible per-pillar values for other pillars in that immutable diagnostic snapshot.

ScoreSnapshots and Score Contributions are immutable. The idempotency tuple is `(evaluation_id, score_policy_version, confidence_policy_version, eligibility_policy_version, scope_snapshot_id, input_set_hash, creation_reason)`. Exact replay returns the existing snapshot. A changed input or policy creates a new snapshot. Snapshot creation serializes per Project. `prior_score_snapshot_id` is the immediately preceding newly created ScoreSnapshot for that Project in this serialized calculation order, whether promoted or unavailable, and is null only when none exists; exact replay retains the original link. When one historical-rebase command creates two snapshots, the earlier Evaluation by `created_at_utc`, then Evaluation ID, is created first, and neither rebase snapshot changes a Current Score Projection pointer. Only complete or partial snapshots other than `historical_rebase` may advance a current pointer; a rebase snapshot is permanently noncurrent.

### Current Score Projection

Each Project has one mutable Current Score Projection containing Project ID, nullable `current_issue_set_id` before first promotion, nullable `latest_calculation_issue_set_id` before first calculation, `last_promoted_score_snapshot_id` nullable before first promotion, `latest_calculation_score_snapshot_id` nullable before first calculation, `availability_status` (`available_complete`, `available_partial`, or `unavailable`), ordered `unavailable_reason_codes`, invalidating Evidence Validation Decision IDs, boolean `recommendation_suppression_required`, state version, and `updated_at_utc`. Successful promotion atomically points both Issue-set fields and both snapshot fields to the promoted pair, clears unavailable reasons/invalidating Decisions, and sets the boolean false. Outside reassessment staging, an unavailable calculation advances only the two latest-calculation fields; it never changes the nullable current/last-promoted pair. An unavailable reassessment-staging calculation may retain immutable diagnostic Snapshot/Contribution records in staging storage but changes no Current Score Projection field or pointer; the failed Reassessment Result identifies `scoring / score_unavailable`, and staged diagnostics are correlated by Evaluation/correlation ID rather than exposed as current. A Validation Decision that changes current score-supporting Evidence away from `valid` atomically changes availability to `unavailable`, retains the current/last-promoted pair for history only, records the invalidating Decision, unions `invalid_evidence` into the de-duplicated fixed-precedence reason set, sets the boolean true, suppresses every published Recommendation Artifact whose origin Issue uses that Evidence, and independently suppresses every published Artifact whose rationale or Citation references it before the Decision commits. Current UI, logical API, notification, and export reads use this projection: when unavailable they return no current numeric score and the exact reason codes. Revalidation recalculates against the selected current set and replaces the reason set with all and only currently applicable codes; only a complete/partial promoted snapshot restores availability, and Recommendation Artifacts republish only after their full eligibility rules pass.

`unavailable_reason_codes` is de-duplicated and ordered by this fixed precedence: `issue_set_incomplete`, `score_policy_unavailable`, `confidence_policy_unavailable`, `eligibility_policy_unavailable`, `scope_definition_invalid`, `check_catalog_unavailable`, `applicable_pillar_insufficient_data`, `invalid_evidence`, `contribution_mismatch`, `score_invariant_failure`. `issue_set_incomplete` includes either incomplete sealed membership or a current Issue state version newer than the last promoted snapshot while deterministic recalculation is pending. Every unavailable calculation contains every applicable code in that order. Unknown conditions map to `score_invariant_failure` and retain restricted diagnostic detail; no other customer-visible code is allowed.

### Normative Score Fixtures

1. Seven applicable pillars, at least one valid passed Check Result in each pillar, and no eligible Issues: every pillar and overall score are `100.0`.
2. Valid coverage in every pillar, one `high` Technical Integrity Issue, and no other Issues: Technical Integrity is `80.0`; the other six pillars are `100.0`; overall is `97.1` because `(80 + 600) / 7 = 97.142857...` and round-half-up produces `97.1`.
3. Two `critical` and two `high` Issues in one pillar: raw pillar score is `-20.0`, persisted pillar score is `0.0`.
4. The Issue in fixture 2 becomes disputed: its contribution becomes excluded in a new immutable snapshot; Technical Integrity and overall become `100.0`; status is `partial`; the prior `97.1` snapshot remains unchanged.
5. Local Presence is validly not applicable, every applicable pillar has valid coverage, and one `medium` Content Quality Issue exists: Content Quality is `90.0`; six applicable pillars have equal weight; overall is `98.3`.

## Recommendation Artifact And Priority Decision

### Recommendation Artifact

Required attributes are `recommendation_id`, exactly one `origin_issue_id`, ordered optional `related_issue_references`, nonblank `problem_statement`, nonblank `rationale`, `expected_impact_band`, `confidence_value`, `confidence_band`, `effort_band` (`low`, `medium`, `high`, or `unknown`), nonblank `effort_basis`, `effort_policy_version`, one or more ordered `implementation_steps`, one or more ordered `verification_steps`, `platform_applicability`, `advisory_scope` fixed to `discoverability_only`, ordered `rationale_evidence_references`, `generation_mode` (`deterministic_template` or `ai_assisted`), nullable `ai_response_id`, `artifact_version`, and `publication_status` (`draft`, `published`, `suppressed`, or `retired`). `expected_impact_band`, `confidence_value`, and `confidence_band` equal the origin Issue values; they are not independently inferred. The origin Issue alone governs eligibility, suppression, priority, and lifecycle. Related Issue references are informational, same-Organization references only; they cannot supply required Evidence, alter score/priority/publication eligibility, or become additional origins.

Publication requires the origin Issue to be the current score-eligible leaf and every rationale Evidence reference to be effectively valid, same-Organization Evidence directly referenced by that Issue or its Check Result. `deterministic_template` requires null `ai_response_id`; `ai_assisted` requires one validated, unexpired AIResponse for this exact Recommendation version. Empty steps, blank text, unknown impact/confidence value, absent effort basis/policy, absent platform applicability, an invalid origin/Evidence/AIResponse, or any other advisory scope blocks publication. AI-proposed effort MUST pass the versioned effort-policy validator. An authorized correction creates a new Artifact version and never mutates a published version.

Personalized legal or tax conclusions, compliance determinations, filing positions, or instructions to take a legal/tax action are prohibited in generated and deterministic output and fail nonretryably with `prohibited_advisory_domain`. A Recommendation may state an observed discoverability fact and may direct the customer to consult a qualified professional; it may not supply the professional conclusion.

A Recommendation Artifact MUST NOT be published if its origin Issue is score-ineligible. A later dispute or dismissal of that Issue suppresses the Artifact without deleting it. A related Issue state change has no effect. Suppression and republication emit audited state events.

### AIResponse And Citation Contract `citation-interim-v1`

The OD-007 interim model is one-directional: a Citation belongs to exactly one AIResponse and points to exactly one Evidence record. Neither AIResponse nor Citation stores a direct Evaluation link; evaluation traversal is `AIResponse -> Recommendation Artifact -> origin Issue -> Check Result/Evidence`. A read-model projection MAY denormalize that traversal but MUST NOT become write authority.

Every AIResponse contains `ai_response_id`, schema version, Organization and Project IDs, target `recommendation_id` and `artifact_version`, `origin_issue_id` and its state version, ordered input Evidence ID/content-digest/Validation-Decision tuples, prompt template ID/version, model ID/version, response-policy and citation-policy versions, locale, `request_fingerprint_sha256` and retained preimage, idempotency key, immutable generated-payload reference and content digest nullable until generated, ordered claim manifest nullable until generated, status (`requested`, `generated`, `validated`, `rejected`, or `expired`), nullable rejection reason, `requested_at_utc`, nullable generated/validated/rejected/expired times, `generation_due_at_utc` exactly 90 seconds after request, `validation_due_at_utc` exactly two minutes after request, nullable `publication_expires_at_utc` exactly 24 hours after validation, state version, and correlation ID.

The AIResponse request-fingerprint preimage is canonical JSON containing exactly Organization, Project, target Recommendation/version, origin Issue/state version, ordered Evidence tuples, prompt template/version, model/version, response-policy/citation-policy versions, and locale. Exact preimage replay returns the original attempt and never calls the provider or validates twice. Reuse of its idempotency key with a different preimage is `idempotency_conflict`. A same hash with a different retained preimage never merges and emits restricted `AIResponseFingerprintCollision` telemetry.

AIResponse transitions are exhaustive: `requested -> generated`; `requested -> rejected` for `generation_timeout`, `provider_failure`, or `policy_denied`; `generated -> validated`; `generated -> rejected` for `schema_invalid`, `citation_missing`, `citation_invalid`, `stale_input`, `prohibited_advisory_domain`, `policy_denied`, or `validation_timeout`; and unpublished `validated -> expired`. At exactly `generation_due_at_utc` timeout wins over provider completion. Validation and the `ai.generate` durable entitlement commit must commit strictly before `validation_due_at_utc`; at that exact two-minute maximum-execution instant, lease expiry and `validation_timeout` win over validation. At exactly `publication_expires_at_utc`, expiry wins over publication. Publication atomically binds the validated AIResponse to the target Artifact version and cancels expiry; a bound response remains validated as immutable lineage. Rejected and expired are terminal. Provider or validation retry creates a new AIResponse attempt linked by causation ID; it never reopens a terminal response.

The generated payload has an ordered claim manifest with exactly one entry for each customer-visible `problem_statement`, `rationale`, `expected_impact_band`, `confidence_value`, `confidence_band`, `effort_basis`, `platform_applicability`, `implementation_steps[i]`, and `verification_steps[i]` value. Each entry contains a unique `claim_key` equal to that logical path and `claim_sha256` over its canonical UTF-8 value. No customer-visible generated value may exist outside this manifest. Citation coverage passes only when every claim has at least one verified Citation, every Citation targets a manifest claim, and no Citation for the response remains proposed or invalid.

Every Citation contains `citation_id`, schema version, Organization and Project IDs, exactly one `ai_response_id`, exactly one `evidence_id`, `claim_key`, `claim_sha256`, Evidence content digest and effective Validation Decision ID/status, a nonblank immutable `evidence_locator`, `citation_policy_version`, `fingerprint_sha256` and retained preimage, status (`proposed`, `verified`, `invalid`, or `superseded`), nullable reason code, proposed/decided timestamps, deciding citation-validation service identity, state version, and correlation ID. It intentionally contains no `evaluation_id`.

The Citation fingerprint preimage is canonical JSON containing exactly Organization, Project, AIResponse ID, Evidence ID/content digest/Validation Decision ID/status, claim key/digest, normalized evidence locator, and citation-policy version. Within one AIResponse, the full retained preimage is uniqueness authority. Exact replay returns one Citation and event outcome; same-hash/different-preimage records never merge and emit restricted `CitationFingerprintCollision` telemetry.

The tenant-scoped citation-validation service changes `proposed -> verified` only when Organization/Project match, the AIResponse claim exists with the same digest, the Evidence is effectively valid with the frozen digest/Decision, the locator resolves inside the immutable Evidence payload, and the Evidence is directly in the origin Issue or its Check Result lineage. Failure changes `proposed -> invalid` with exactly one first-match reason in this order: `tenant_mismatch`, `claim_missing`, `claim_digest_mismatch`, `evidence_not_valid`, `evidence_digest_mismatch`, `locator_unresolved`, or `evidence_not_in_origin_lineage`. AIResponse rejection or validation timeout changes any remaining proposed Citation to invalid with `response_rejected` or `validation_timeout` in the same transaction. `verified -> superseded` occurs only when a later published Artifact version replaces the target version and uses reason `artifact_version_superseded`. Invalid and superseded are terminal; corrected linkage is a new Citation. One validation transaction always persists a terminal decision for every proposed Citation and changes the AIResponse to `validated` when full coverage passes or `rejected` when it fails. The transaction binds validated draft content to the target Artifact version only on full pass; on failure it retains the rejected response and Citation decisions for audit and publishes no AI-assisted Artifact.

### Interim Priority Policy `priority-interim-v1`

Only published Recommendation Artifacts whose origin Issue is score-eligible receive a Priority Decision. Deterministic base order is:

1. origin Issue impact rank first: critical, high, medium, low, informational;
2. origin Issue confidence value descending; missing confidence sorts last;
3. effort band first in the order low, medium, high, unknown;
4. earliest Recommendation Artifact creation time;
5. opaque Recommendation identifier ascending as the final tie-breaker.

Every Priority Decision stores all sort inputs, policy version, computed order, and input hash. A manual override requires `priority.override`, actor identity, nonblank 20-2,000 character reason, prior order, resulting order, and timestamp. It changes the displayed order only; it never changes score, impact, confidence, or the deterministic base order.

## Score Visibility And Redaction

Executive Buyer is a product persona, not a distinct foundation authorization role. In baseline behavior it uses a read-only MarketingOperator assignment. A support operator uses a time-bounded SecurityOperator support session; `SupportOperator` is not a standing role.

| Actor Or Role | Overall And Pillar Scores | Published Issue Summary | Contribution Detail | Evidence Metadata | Evidence Payload | History | Export |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OrganizationAdmin | allow, with classified fields omitted above ceiling | allow, with classified fields omitted above ceiling | allow, with classified fields omitted above ceiling | allow through `confidential`; higher classification is reference-only | allow through `confidential`; `restricted` requires `evidence.restricted.read` | allow, with classified fields omitted above ceiling | allow with identical field rules |
| MarketingOperator | allow, with classified fields omitted above `internal` | allow, with classified fields omitted above `internal` | allow through `internal` | allow through `internal`; higher classification is reference-only | allow through `internal` | allow, with classified fields omitted above `internal` | allow with identical field rules |
| Executive Buyer persona | allow through `internal`; higher-classified fields omitted | allow through `internal`; higher-classified fields omitted | deny | deny | deny | allow through `internal`; higher-classified fields omitted | summary-only through `internal` |
| TechnicalImplementer | allow, with classified fields omitted above ceiling | allow, with classified fields omitted above ceiling | allow, with classified fields omitted above ceiling | allow through `confidential`; higher classification is reference-only | allow through `confidential` | allow, with classified fields omitted above ceiling | allow with identical field rules |
| SecurityOperator | allow when incident, adjudication, or support scope is active | allow in authorized scope | allow in authorized scope | allow in authorized scope | allow including restricted only in authorized scope | allow in authorized scope | security-authorized only |
| BillingOperator | deny | deny | deny | deny | deny | deny | deny |
| Tenant-scoped service identity | minimum fields required for assigned workflow | minimum required | minimum required | minimum required | minimum required | no interactive access | deny |

Undefined permission or scope is deny-by-default. Organization scope is mandatory for every allow.

Classification ceilings are `confidential` for OrganizationAdmin and TechnicalImplementer, `internal` for MarketingOperator and the Executive Buyer persona, and `restricted` for a SecurityOperator only inside active incident/adjudication/support scope. An explicit `evidence.restricted.read` grant raises only the granted OrganizationAdmin Evidence payload access to `restricted`; it does not broaden resource scope or other field permissions.

`redacted_field_codes` uses these stable logical groups: `score.overall`, `score.pillar`, `issue.summary_text`, `issue.subject`, `score.contribution_detail`, `evidence.metadata`, `evidence.payload`, `recommendation.rationale`, `recommendation.steps`, `history.issue_detail`, and `export.detail_fields`. When only some fields in a group are omitted, append the exact snake-case logical field name, for example `evidence.metadata.content_sha256`. Codes describe omitted fields only and never reveal their values.

- If the actor cannot access the requested score object, the whole request is denied with an auditable authorization error.
- If the actor can access the score object but not a field, the field is omitted and its stable field code appears in `redacted_field_codes`; no value-derived placeholder is returned.
- When an actor can read the origin Issue but an Evidence record exceeds that actor's classification ceiling, return only `evidence_id` and `access_status=restricted`; omit payload reference, content digest, provenance detail, and observation content. This reference-only result applies to `confidential` as well as `restricted` Evidence when the actor's ceiling is lower.
- The strongest classification among a field's source Evidence governs that derived field unless an explicit approved declassification record exists.
- The same allow, omit, and deny semantics apply to UI read models, logical API responses, exports, notifications, and support views.

## Reassessment Result And Historical Comparison

Every terminal Reassessment Result contains `reassessment_result_id`, nonnull `prior_evaluation_id`, nullable `current_evaluation_id` only for a precreation Entitlement Block, `prior_scope_snapshot_id`, nullable `current_scope_snapshot_id` only for that same precreation Block, `entitlement_decision_id`, `status` (`completed`, `failed`, or `canceled`), `issue_set_id` and `score_snapshot_id` required when completed and null otherwise, `issue_supersession_summary` and `recommendation_status_delta` required when completed and null otherwise, ordered `resolution_unverified_entries` containing Issue ID and exact reason code, nullable `failure_stage`, `terminal_reason_code` null only when completed, `started_at_utc`, `completed_at_utc`, and `correlation_id`. Resolution-unverified entries use the predecessor processing order above. Every other failed/canceled Result references its Evaluation. A pending attempt uses the canonical Evaluation plus immutable orchestration context; it is not represented as a terminal Reassessment Result.

For completed status, `failure_stage` and terminal reason are null. Nonsuccess mapping is exhaustive: Entitlement Block -> `entitlement / entitlement_blocked`; Crawl failure -> `crawl / crawl_failed`; parsing or check pipeline failure -> `evaluation / evaluation_pipeline_failed`; stage timeout -> the active stage plus `stage_timeout`; unavailable score -> `scoring / score_unavailable`; active Source/scope mismatch -> `publication / source_scope_changed_during_reassessment`; atomic validation/conflict/write failure -> `publication / publication_failed`; accepted cancellation -> `cancellation / canceled_by_actor`. No other customer-visible pair is allowed; restricted diagnostics retain the internal cause.

A reassessment is permitted only after one current Issue Set and promoted ScoreSnapshot exist for a prior completed Evaluation. Otherwise `initial_evaluation_required` rejects the command before entitlement, Evaluation, or Reassessment Result creation. Reassessment is orchestration over a new canonical Evaluation, not a separate mutable state machine. Pipeline timeout/failure or accepted cancellation while Evaluation is running transitions it to failed. Unavailable scoring, Source/scope race, publication failure, or accepted post-completion cancellation leaves Evaluation completed and records only the failed/canceled Reassessment Result. A precreation Entitlement Block creates no Evaluation. Every nonsuccess emits the matching `ReassessmentFailed` or `ReassessmentCanceled`, leaves the last promoted Issue set/ScoreSnapshot projection unchanged, and releases any reservation exactly once. Retry creates a new Evaluation attempt linked by causation ID.

Direct numeric score comparison is permitted only when both snapshots have identical score, confidence, eligibility, fingerprint, check-catalog, scope-policy, normalized `scope_definition_hash`, and pillar-applicability versions. Otherwise the comparison result is `not_comparable`, contains every applicable reason in this fixed order, and contains no numeric delta: `score_policy_mismatch`, `confidence_policy_mismatch`, `eligibility_policy_mismatch`, `fingerprint_version_mismatch`, `check_catalog_version_mismatch`, `scope_policy_version_set_mismatch`, `scope_definition_mismatch`, and `pillar_applicability_mismatch`. An explicitly requested rebase requires OrganizationAdmin `score.rebase` and an exact target version for every versioned dimension, all available to both retained input sets; omission, ambiguity, or unavailable input rejects the request. Rebase cannot make different normalized scope-definition hashes comparable. It creates new immutable noncurrent snapshots for both evaluations and never mutates originals or advances a current pointer.

Historical views reconstruct Issue and adjudication state only from each ScoreSnapshot's immutable Contributions, including captured Issue state version, lifecycle/publication/adjudication values, Case references, Evidence IDs, and Validation Decision IDs/statuses. Later Issue or Evidence decisions do not rewrite historical state. Current views use the Current Score Projection and return no numeric score while it is unavailable, even though its retained last snapshot remains accessible as history.

When fewer than two completed Evaluations with promoted ScoreSnapshots are available, historical comparison returns `insufficient_history`, `available_run_count` equal to 0 or 1, and `next_action_code=complete_initial_evaluation` for zero or `complete_next_evaluation` for one; it does not return an empty or synthetic delta.

## Allowed Transformations

- Valid Evidence -> Check Result when all input and policy versions are frozen.
- Failed Check Result -> Issue under the confidence and deduplication rules.
- Current Issue -> Score Contribution under the eligibility policy.
- Complete contribution set -> immutable ScoreSnapshot under the score policy.
- Eligible origin Issue -> published Recommendation Artifact.
- Eligible published Recommendation Artifact -> Priority Decision from its origin Issue.
- Completed replacement Evaluation -> atomic Issue supersession and Reassessment Result.

## Prohibited Transformations

- Evidence bypassing Check Result and Issue directly into score.
- Any persisted Issue without valid same-Organization Evidence.
- Score or priority contribution from a review-required, disputed, in-review, dismissed, resolved, superseded, or non-current Issue.
- Publication or prioritization of a Recommendation Artifact whose origin Issue is ineligible.
- A Citation with zero or multiple AIResponse/Evidence parents, or a Citation/AIResponse direct Evaluation write link under `citation-interim-v1`.
- ScoreSnapshot, Score Contribution, or historical Issue-state mutation.
- Supersession across Organizations or Projects, lineage cycles, or more than one direct successor.
- Hash-only Issue merging without retained-preimage equality.
- Redaction rules that differ by UI, logical API response, export, notification, or support view.

## Acceptance Criteria

- AC-SM-001: Every published Recommendation Artifact has exactly one eligible origin Issue and at least one valid same-Organization Evidence path; every AI-assisted version has one validated unexpired AIResponse and complete verified one-AIResponse/one-Evidence Citations with no direct Evaluation write link.
- AC-SM-002: The normative score fixtures reproduce the exact pillar, overall, status, version, contribution, exclusion, and idempotency results defined in this document.
- AC-SM-003: Creating any Issue fails when Evidence is absent, invalid, quarantined, missing required fields, or cross-Organization.
- AC-SM-004: Reassessment produces an acyclic single-successor lineage with exactly one current leaf per fingerprint, and incomplete coverage never falsely resolves an Issue.
- AC-SM-005: Review-required, disputed, and in-review Issues have zero score and priority contribution; adjudication creates or reuses a new immutable current ScoreSnapshot without changing history.
- AC-SM-006: Same-run exact Issue replay and concurrency return one Issue, while a same-hash/different-preimage collision never merges records and emits one collision event per attempted conflicting create.
- AC-SM-007: Role and classification fixtures produce the exact allow, omitted-field, restricted-reference, and denied-object outcomes across every delivery surface.
- AC-SM-008: Verification fixtures for success, mismatch, dependency timeout, expiry, duplicate submission, unsupported method, cross-Organization reference, and stale state version produce the exact request status, Source state, Evidence, reason code, and event outcome.

## Dependencies

- [INDEX.md](INDEX.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
- [../003 TERMINOLOGY.md](../003%20TERMINOLOGY.md)
- [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md)
- [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- [../014 SECURITY_MODEL.md](../014%20SECURITY_MODEL.md)
- [../016 STATE_MODEL.md](../016%20STATE_MODEL.md)
- [../017 ERROR_MODEL.md](../017%20ERROR_MODEL.md)
- [../019 VERSIONING.md](../019%20VERSIONING.md)

## Change Control

Any normative update MUST:

1. preserve the canonical Issue entity and conceptual chain
2. update rule references and acceptance mappings
3. preserve immutable historical snapshots and Issue lineage
4. update owner-decision interim behavior when an approved replacement becomes effective
5. update capability, workflow, traceability, and visibility contracts in the same change set
