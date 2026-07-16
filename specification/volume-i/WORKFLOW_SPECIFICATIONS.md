# Volume I Workflow Specifications

## Status

- Status: Draft for owner review
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Workflow Coverage

This document defines 18 canonical workflows using stable identifiers WF-001 through WF-018.

PRULE-044, PRULE-045, and PRULE-046 and the Normative Execution Contracts below apply to every workflow. A workflow-specific clause may narrow authority or behavior but cannot weaken those cross-cutting rules.

Every workflow includes:

- purpose and actors
- preconditions and triggers
- primary path
- alternate path
- failure path
- recovery path
- state transitions
- domain events
- authorization and security notes
- audit and observability notes
- acceptance criteria reference

## Normative Execution Contracts

### Actor Resolution

- Organization Administrator, Marketing Operator, Technical Implementer, Security Operator, and Billing Operator map to the canonical authorization identifiers OrganizationAdmin, MarketingOperator, TechnicalImplementer, SecurityOperator, and BillingOperator.
- Executive Buyer is a product persona using a MarketingOperator Role Assignment with `permission_mode=read_only` and `persona=executive_buyer`. That assignment receives only the Read-Only Executive Buyer column below, not standard MarketingOperator permissions. It is not a separate authorization role.
- Consultant is a product persona using only explicit invited OrganizationAdmin, MarketingOperator, or TechnicalImplementer Role Assignments in each customer Organization. It has no standing role, cross-Organization session, or implicit permission.
- Support Operator is work performed through the governed SecurityOperator support session defined below. Every read and action records the support-session ID. It is not a standing authorization role.
- Automation scheduler, system automation, and internal service role mean tenant-scoped machine identities granted only the named workflow permissions.
- Chief Security actions in WF-018 mean a SecurityOperator holding the separately approved `security.investigation.approve` permission.
- A list of actors separated by “or” or commas means any one authorized actor. Dual control applies only where this document explicitly requires a different requester and approver.
- Every permission is constrained to the actor's Organization and granted Project or resource scope. Undefined role, permission, resource scope, or tenant context is denied by default.

### Logical Command Envelope And Replay

Every state-changing workflow command MUST carry:

- `command_id` and `idempotency_key`
- `command_type` and `schema_version`
- `actor_id` or `service_identity_id`
- `organization_id`, nullable only for a pre-Organization bootstrap command that carries `bootstrap_principal_id`
- target resource type and identifier; the identifier is nullable only for a create command whose target does not yet exist
- requested action
- `expected_state_version`, when the target already exists
- every policy version used to authorize or constrain the command
- `requested_at_utc`
- `correlation_id` and `causation_id`

For an existing target, idempotency scope is Organization, command type, target resource type and ID, and idempotency key. For a create command, it is Organization, command type, and idempotency key; pre-Organization bootstrap substitutes the immutable bootstrap-principal ID for Organization. A client-generated target ID is optional and, when supplied, is part of the canonical body rather than required for replay protection.

The canonical request hash is SHA-256 over UTF-8 canonical JSON containing command type, actor or service identity, Organization or bootstrap principal, target type and nullable ID, action, expected version, normalized semantic command body, and sorted policy versions. Keys are lexicographically sorted, strings use Unicode NFC, decimals use nonexponent base-10 form, arrays retain declared semantic order, and no insignificant whitespace is present. `command_id`, idempotency key, requested time, correlation/causation IDs, and transport metadata are excluded. The platform MUST retain this hash and the terminal result for the resulting resource's retained lifetime plus 30 days, or 30 days for a rejected/no-resource command, subject to longer legal retention. Exact replay never repeats state transition, usage consumption, provider dispatch, or domain event. Before returning retained identifiers or result data, it reauthorizes the current actor against the target and applies current field redaction; denial returns `F1-AUTH-403` with no retained payload while the stored outcome remains unchanged. Reuse with a different canonical request hash is rejected as `idempotency_conflict`. Concurrent exact commands have the same product result as sequential replay.

### Logical Event Envelope

Every workflow event MUST contain `event_id`, `event_type`, `schema_version`, `occurred_at_utc`, `organization_id`, `affected_entity_id`, `aggregate_version`, `actor_id` or `service_identity_id`, `correlation_id`, `causation_id`, `outcome`, and nullable `reason_code`. Event consumers deduplicate by `event_id`; redelivery MUST NOT repeat a product side effect. Producer and consumer deduplication records are retained for the event's governed retention lifetime plus 30 days, subject to longer legal retention.

### Permission Baseline

| Permission | OrganizationAdmin | MarketingOperator | TechnicalImplementer | SecurityOperator | BillingOperator | Read-Only Executive Buyer | Service Identity |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `organization.bootstrap` | eligible registrant bootstrap only | deny | deny | deny | deny | deny | approved identity service only |
| `project.create`, `project.activate` | allow | allow | deny | deny | deny | deny | deny |
| `source.register`, `source.scope.propose` | allow | allow | allow | deny | deny | deny | workflow-specific only |
| `source.lifecycle.manage` | allow | allow | deny | deny | deny | deny | workflow-specific only |
| `source.verify` | allow | deny | allow | deny | deny | deny | verification service only |
| `crawl.trigger`, `crawl.cancel` | allow | allow | deny | deny | deny | deny | scheduler only |
| `crawl.recover` | allow | allow | deny | support-session only | deny | deny | recovery service only |
| `parsing.recover` | allow | allow | deny | support-session only | deny | deny | parsing-recovery service executes approved replay only |
| `reassessment.trigger` | allow | allow | deny | deny | deny | deny | Project scheduler only |
| `reassessment.cancel` | allow | allow | deny | deny | deny | deny | reassessment service executes accepted cancellation only |
| `issue.read`, `score.summary.read`, `history.read`, `recommendation.read` | allow | allow | allow | authorized incident/adjudication scope only | deny | allow | workflow-specific only |
| `score.detail.read`, `evidence.metadata.read` | allow | allow | allow | authorized incident/adjudication scope only | deny | deny | workflow-specific only |
| `evidence.payload.read` | classification-limited | classification-limited | classification-limited | authorized incident/adjudication scope only | deny | deny | workflow-specific only |
| `evidence.restricted.read` | protected explicit grant only | deny | deny | authorized incident/adjudication scope only | deny | deny | workflow-specific only |
| `evidence.validation.manage` | deny | deny | deny | quarantine-only in authorized security/legal scope | deny | deny | integrity-validation service only for all allowed transitions |
| `issue.dispute` | allow | allow | allow | deny | deny | deny | deny |
| `issue.adjudicate` | deny | deny | deny | allow, including approved support session | deny | deny | deny |
| `recommendation.publish`, `priority.override` | allow | allow | deny | deny | deny | deny | deterministic publication service only when policy permits |
| `role.manage` | allow for non-protected tenant grants | deny | deny | allow | deny | deny | security-bootstrap service for first SecurityOperator only |
| `policy.access.manage` | allow for non-protected tenant policy | deny | deny | allow | deny | deny | deny |
| `policy.source_scope.manage` | allow | allow for Project scope | deny | deny | deny | deny | deny |
| `policy.crawl.manage` | allow to narrow Organization bounds | allow to narrow Project bounds | deny | deny | deny | deny | release service activates global safety bounds only |
| `policy.notification.manage` | allow for optional informational routes/templates/preferences only | deny | deny | security templates, support-queue roster, and critical selectors only | deny | deny | deny |
| `policy.entitlement.manage` | deny | deny | deny | deny | allow | deny | billing adapter may synchronize approved plan only |
| `entitlement.notice.read` | allow | allow | allow | deny | allow | deny | deny |
| `security.notice.read` | allow for own Organization disclosure scope | deny | deny | allow in incident scope | deny | deny | deny |
| `policy.export.manage` | allow to narrow baseline | deny | deny | allow for restricted/security scope | deny | deny | release service activates baseline only |
| `score.rebase` | allow | deny | deny | deny | deny | deny | scoring service executes authorized request only |
| `notification.replay` | deny | deny | deny | support-session only | deny | deny | deny |
| `export.create`, `export.retrieve` | allow | allow | allow | authorized investigation scope only | deny | summary-only | export service executes approved request |
| `export.retry`, `export.revoke` | allow | allow for own requested Export | allow for own requested Export | authorized investigation scope only | deny | deny | export service executes approved request |
| `export.expire` | deny | deny | deny | deny | deny | deny | export lifecycle service only |
| `incident.respond`, `security.investigate` | deny | deny | deny | allow | deny | deny | incident service only |
| `security.investigation.approve` | deny | deny | deny | protected explicit grant | deny | deny | deny |
| `support.session.request`, `support.session.revoke` | deny | deny | deny | allow | deny | deny | deny |
| `support.session.approve` | deny | deny | deny | protected allow; approver differs from requester | deny | deny | deny |
| `support.session.customer_approve` | allow for own Organization | deny | deny | deny | deny | deny | deny |
| `support.session.expire` | deny | deny | deny | deny | deny | deny | support-session lifecycle service only |
| `account.suspend`, `account.reactivate`, `account.revoke`, `account.delete` | allow for tenant-managed accounts subject to last-admin rule | deny | deny | allow for security action | deny | deny | lifecycle service executes approved request only |

An authorization denial returns `F1-AUTH-403`, emits one authorization audit event, and performs no state change or provider call. Score and Evidence field-level behavior additionally follows [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#score-visibility-and-redaction).

### Role Assignment And Policy Artifact

Role Assignment is a logical authorization record with `role_assignment_id`, Organization and Account, role identifier, `permission_mode` (`standard` or `read_only`), optional persona, permission scope, status, requester, approver, requested/effective/expiry timestamps, reason, and state version. Statuses are `pending`, `active`, `rejected`, `revoked`, and `expired`. Valid transitions are pending to active, rejected, or expired; active to revoked or expired. Revoked, rejected, and expired are terminal. Exact replay is idempotent; every other invalid or stale transition is rejected and audited.

Policy Artifact is an immutable versioned logical contract, not an additional core domain aggregate. It contains `policy_id`, `policy_type`, Organization and optional Project/resource scope, semantic version, status, normalized rule values, `effective_at_utc`, nullable `expires_at_utc`, superseded version, content SHA-256, creator, approver, `created_at_utc`, and state version. `access` is the Access Policy type. Statuses are `draft`, `active`, `superseded`, and `retired`. Exactly one version per policy type and identical scope may be active at an instant. Volume I does not schedule future policy activation or automatic policy expiry: every activation command requests `activation_mode=immediate` and MUST omit client-supplied effective and expiry times; any other mode or supplied time is schema-invalid and changes nothing. The activation transaction assigns `effective_at_utc` to its own commit time and `expires_at_utc=null`. Activation requires the expected current state version, schema-valid normalized rules, and authorized approver, and atomically activates the new version, supersedes the prior version, and emits its workflow-specific activation event at that commit time. Activated content never mutates; rollback activates a new version containing the prior normalized rules. A future scheduling or expiring-policy capability requires an explicit later contract rather than overloading these states.

Grants containing `issue.adjudicate`, `evidence.restricted.read`, `evidence.validation.manage`, `security.investigate`, `security.investigation.approve`, `support.session.approve`, `role.manage`, `account.suspend`, `account.revoke`, `account.delete`, or cross-Organization support access are protected. They require approval within 24 hours by a SecurityOperator other than the requester. Unapproved requests expire; rejection or expiry grants nothing. The one first OrganizationAdmin assignment created atomically by WF-001 under a valid unconsumed bootstrap grant is the sole tenant-bootstrap exception: the approved identity/bootstrap service creates it with the new tenant, and transaction rollback removes both if either cannot activate. The first SecurityOperator assignment in an Organization is requested by its OrganizationAdmin and requires two distinct pre-provisioned platform security identities through the security-bootstrap service; neither may be the requester or target. After one active tenant SecurityOperator exists, the normal distinct SecurityOperator rule applies. No other existing Organization grant can use either exception. Revocation takes effect on the next protected request, and authorization caches and active sessions MUST reflect it within 60 seconds. A running privileged operation rechecks at each durable checkpoint and stops before the next protected side effect after revocation.

### Support Session Lifecycle

A Support Session contains session ID, requesting and approving SecurityOperator Accounts, support-case or Incident ID, affected Organization, resource and action allowlists, nonblank 20-2,000 character reason, customer-approval reference when required, `requested_at_utc`, `approval_due_at_utc`, `started_at_utc`, `expires_at_utc`, `rejected_at_utc`, `revoked_at_utc`, decision reason, status, and state version. Statuses are `pending`, `active`, `rejected`, `expired`, and `revoked`. Valid transitions are pending to active, rejected, or expired; active to expired or revoked. Rejected, expired, and revoked are terminal. `approval_due_at_utc` is exactly 24 hours after request. A pending session with every required approval becomes active immediately when the final approval commits; `started_at_utc` is that commit time and `expires_at_utc` is exactly 4 hours later. Approval cannot schedule a future start. A pending session not fully approved before its due time expires; at exactly the due time expiry wins over an approval. An active session expires at exactly `expires_at_utc`; extension is a new session.

Creation requires `support.session.request`; activation requires a different SecurityOperator with `support.session.approve`. Cross-Organization customer access additionally requires an OrganizationAdmin in the affected tenant holding `support.session.customer_approve`. The customer approval may be bypassed only when an open severity-critical Incident explicitly names that Organization, the requested resource/action scope, and `emergency_customer_access=true`; distinct SecurityOperator approval remains mandatory. Rejection requires either required approver, expected state version, and a nonblank reason; it prevents later activation. The requester, approving SecurityOperator, or the affected Incident's named commander may revoke an active session using `support.session.revoke`, expected state version, and a nonblank reason. Timed pending or active expiry is performed only by the support-session lifecycle service holding `support.session.expire`. Every request rechecks active status, expiry, exact allowlists, Organization, and underlying permissions. Revocation or expiry denies the next request and all caches converge within 60 seconds. Creation, activation, rejection, timed expiry, and revocation emit `SupportSessionRequested`, `SupportSessionActivated`, `SupportSessionRejected`, `SupportSessionExpired`, and `SupportSessionRevoked` respectively, each exactly once under replay.

### Versioned Policy Resolution

The policy artifact types used in Volume I are `access`, `source_scope`, `crawl`, `entitlement`, `notification`, `export`, `score`, `confidence`, `score_eligibility`, and `priority`. Every gated command captures an immutable Policy Snapshot containing the resolved policy versions and normalized effective values.

- An immediately executed command resolves versions active at `requested_at_utc`. A queued command keeps that initial snapshot for audit but, immediately before execution, resolves a new execution snapshot using `policy_resolution_at_utc=execution_check_at_utc`; that later snapshot governs allow/deny and execution. `requested_at_utc` never changes.
- Global safety bounds cannot be weakened. Effective crawl and capacity limits are the most restrictive of global safety, approved entitlement, Organization, and Project limits.
- Source scope is the intersection of verified Source boundary, active Organization policy, and active Project policy. Absence or ambiguity is deny-by-default.
- A missing, expired, unknown, or internally inconsistent policy blocks a new state-changing action with `policy_unavailable`; no implicit default is invented except where this document declares an interim policy.
- A queued state-changing action re-resolves policy as above immediately before execution. After a durable reservation or run starts, it remains pinned to the execution snapshot except that a new security or source-scope restriction takes effect at the next checkpoint.
- A source-scope restriction stops scheduling newly disallowed URLs. In-flight disallowed content is discarded as evaluation input, recorded as quarantined telemetry, and cannot become valid Evidence.

Tenant policy administration is exact: Access Policy follows WF-013; Source Scope follows the contract below; OrganizationAdmin and MarketingOperator may only make Crawl Policy values more restrictive within their allowed scope; BillingOperator may activate an approved Entitlement Policy or plan synchronization; Notification Policy changes follow the mandatory-route rules below; and Export Policy may only narrow the baseline formats, fields, size, or lifetime. `score`, `confidence`, `score_eligibility`, `priority`, and global Crawl safety versions are system-governed and may be activated only by the release service from an owner-approved artifact. Pending owner decisions use the named interim versions in these documents; no tenant actor can alter them.

### Source Scope Change Contract

A Source Scope Policy contains one exact `canonical_host`, allowed schemes, allowed port set, one or more included path prefixes, zero or more excluded path prefixes, query handling (`retain_all` or an explicit retained-key allowlist), policy version, and scope. On first successful verification, the platform atomically materializes mandatory version `source-scope-interim-v1` for that Source: HTTPS, its default port, the verified canonical host only, included prefix `/`, no excluded prefix, and `retain_all`. Host is lowercase IDNA ASCII without trailing dot; default port is removed; path dot segments and unreserved percent encoding are normalized; fragment and user information are prohibited; query pairs are retained and sorted by decoded key then value while preserving duplicates. A path prefix matches the normalized path exactly or at a `/` segment boundary, so `/shop` matches `/shop/item` but not `/shopping`. Subdomains, alternate apex/`www` hosts, ports, and schemes are outside scope unless separately present in the verified policy. A URL is allowed only when it matches every active policy intersection, at least one include prefix, no exclude prefix, and the query rule. Exclusion wins over inclusion, and an out-of-scope redirect is not followed.

A source-scope change request contains request ID, Organization, Project and Source IDs, current and proposed normalized host/path/query rules and their content hashes, expected active policy version, requester, nonblank 20-2,000 character request reason, `requested_at_utc`, `due_at_utc=requested_at_utc+24 hours`, status, nullable decision actor/time/reason, idempotency key, state version, correlation ID, and nullable activated policy version. Statuses are `pending`, `approved`, `rejected`, `expired`, or `canceled`. The only transitions are `pending -> approved`, `rejected`, `expired`, or `canceled`; every terminal request is immutable. Exact replay returns the stored request/decision, while changed content under the same key is `idempotency_conflict`.

- Contraction within an already verified Source boundary submitted by OrganizationAdmin or MarketingOperator may be approved and activate atomically in its creation transaction without dual control. A TechnicalImplementer may propose it but cannot approve or activate it.
- Expansion within the same canonical verified host submitted by a non-admin remains pending for an OrganizationAdmin approval. An OrganizationAdmin requester may approve it atomically; when the requester is not an OrganizationAdmin, the approving OrganizationAdmin MUST be a different Account.
- A new host is a new Source and MUST pass WF-003; it cannot be approved as a policy expansion. Baseline Source registration and crawling support HTTPS only. HTTP or any other scheme is rejected as `unsupported_source_scheme`; it does not create a second same-host Source.
- At exactly `due_at_utc`, the source-scope lifecycle service's expiry transition wins over approval, rejection, or cancellation; it emits `SourceScopeChangeExpired` once and changes no policy or Source state.
- Approval activates one new immutable `source_scope` policy version. Rejection, expiry, cancellation, stale expected version, or unauthorized approval changes nothing.
- Approval/rejection requires expected request state and active-policy versions. Approval sets decision actor/time, null decision reason, activated policy version, and emits `SourceScopeChangeApproved` in the activation transaction. Rejection requires a 20-2,000 character reason and emits `SourceScopeChangeRejected`. The requester or OrganizationAdmin may cancel a pending request using expected state version and a 20-2,000 character reason; cancellation emits `SourceScopeChangeCanceled`. Only an OrganizationAdmin may approve or reject an expansion; the approver must differ from a non-admin requester.

### Interim Crawl Policy `crawl-interim-v1`

| Resource Dimension | Soft Limit | Hard Limit | Unit |
| --- | ---: | ---: | --- |
| accepted pages per run | 8,000 | 10,000 | pages |
| discovered URL queue | 16,000 | 20,000 | distinct canonical URLs |
| crawl depth from Source root | 8 | 10 | link edges |
| accounted response-body bytes per run | 1,000 | 1,250 | MiB |
| response body per URL | 8 | 10 | MiB |
| wall-clock run duration | 45 | 60 | minutes |
| redirects per URL | 5 | 10 | redirects |
| request rate per canonical host | 1 | 2 | requests per second |
| concurrent requests per canonical host | 2 | 4 | requests |
| connection plus response time per request | 10 | 15 | seconds |
| sitemap documents per run | 40 | 50 | distinct canonical sitemap URLs |
| sitemap-index nesting depth | 2 | 3 | sitemap-index edges |

`KiB` and `MiB` mean 1,024 and 1,048,576 bytes. An accepted page is one distinct canonical in-scope URL whose terminal response is successful `2xx`, no larger than the response maximum, has a media type before parameters of `text/html` or `application/xhtml+xml`, and creates a valid Document. Redirect responses, robots/sitemap discovery fetches, unsupported content types, failed responses, and duplicate canonical URLs do not count as accepted pages. The Source root is depth 0, a sitemap-discovered content URL starts at depth 1, and each followed content link adds one edge; redirects do not add crawl depth. The discovered queue counts distinct content-candidate URLs after Source Scope canonicalization, including an in-scope URL even when it is later rejected for depth; robots and sitemap-document URLs use their separate bounds and do not consume this queue. Response-size and run-byte accounting apply to every content, robots, and sitemap attempt, including retries and bodies later rejected. For attempt `i`, `accounted_response_bytes_i = max(received_entity_body_bytes_i_after_transfer_coding, expanded_body_bytes_i_after_content_decoding)`; run-wide accounted response-body bytes are exactly `sum(accounted_response_bytes_i)` in canonical dequeue/attempt order. Before body reading, the scheduler reserves up to the per-URL maximum from the remaining run-wide budget in that order; concurrent reservations MUST NOT sum above the run-wide maximum, unused bytes are released in the same order, and an attempt cannot add accounted bytes beyond its reservation. To distinguish an exact-maximum body from an over-limit body, the reader may inspect at most one nonretained sentinel byte on each accounting path after the maximum; sentinel bytes are recorded separately as `limit_probe_bytes`, are never parsed or retained, and do not enter either accounted counter. EOF at the maximum is allowed; observing a sentinel byte fails that URL as over-limit.

Limits are inclusive maxima over accepted or accounted values; `limit_probe_bytes` are detection telemetry, not accepted/accounted capacity. Wall-clock duration starts at the atomic `Crawl.Queued -> Crawl.Running` transition. A soft event fires when the observed or reserved value first equals the soft limit. A capacity hard-limit event fires before an action would exceed the maximum; the exceeding page, URL, or accounted bytes are not accepted. A URL deeper than 10, response with a sentinel beyond 10 MiB on either byte path, request exceeding 15 seconds, fourth-level sitemap index, fifty-first sitemap, or eleventh redirect fails that URL without retaining its body as valid Evidence. At 60 elapsed minutes, no new request starts and incomplete requests are canceled. Soft-limit crossing emits `CrawlSoftLimitApproaching` once per dimension and run. For each canonical host, request-rate observation is the count of request starts in the rolling half-open interval `(start_time - 1 second, start_time]`; a start that would make the count exceed 2 is delayed. The baseline scheduler targets at most 1 start in that interval and at most 2 concurrent requests; 2 starts per rolling second and 4 concurrent requests are nonexceedable safety ceilings, not normal scheduling targets. At any other hard limit, stop scheduling affected work, preserve successful artifacts, record dimension, configured value, observed value, affected Source and URL counts, set `coverage_status=partial` and `completion_reason=limit_reached`, and emit `CrawlLimitReached` exactly once per dimension and run.

A fetch receives one initial attempt plus at most two retries for timeout, `408`, `429`, or `5xx`. Retry delays are exactly 30 seconds after completion of the first failed attempt and 120 seconds after completion of the second failed attempt. A valid integer `Retry-After` from 1 through 120 seconds replaces that retry's delay; every other value is ignored. Other `4xx`, policy denial, invalid URL, and content validation errors are non-retryable. A Crawl retry after terminal failure is a new attempt linked to the prior run and uses a new Crawl ID; command replay with the original idempotency key returns the original run.

The baseline crawler user-agent token is `F1DiscoverabilityBot`. Before any content URL on a host, fetch `https://<canonical_host>/robots.txt` under the same request timeout/retry bounds with a 1 MiB response maximum. A valid `2xx` body is decoded as UTF-8 with invalid byte sequences replaced, unrecognized or malformed lines ignored, and parsed using ASCII-case-insensitive user-agent token comparison for the exact token, falling back to `*`; the longest matching allow/disallow normalized path rule wins and allow wins equal-length ties. `404` or `410` means no robots restrictions. `401` or `403`, content over 1 MiB, or exhausted timeout/`5xx` retries denies all content fetching for that host for the run and records `robots_unavailable_fail_closed`. A positive robots crawl-delay makes the request rate more restrictive than policy; it never increases rate. Robots-disallowed URLs are recorded as skipped, are excluded from coverage denominator and Evidence, and are not treated as fetch failures. Redirects are rechecked against robots and Source Scope Policy before following.

Sitemap discovery uses all in-scope `Sitemap:` locations in the parsed robots file plus `https://<canonical_host>/sitemap.xml`; canonical duplicates are fetched once. A sitemap or sitemap index must remain on the verified canonical host and pass Source Scope, robots, redirect, request, retry, and 10 MiB received/expanded body limits. Baseline accepts media type before parameters `application/xml`, `text/xml`, or `application/sitemap+xml` and UTF-8 XML only; malformed XML, unsupported format, cross-host location, over-depth index, and over-count sitemap are recorded and skipped. A sitemap index may nest through three edges from an initial sitemap. Content URLs still pass normal scope, robots, queue, depth, and deduplication rules. When robots declares no sitemap and the default sitemap returns `404` or `410`, record `sitemap_absent`; this is covered and does not reduce coverage. If at least one sitemap candidate succeeds, other non-limit sitemap-candidate failures remain telemetry and do not reduce coverage; any sitemap depth/count/body/time limit still produces `limit_reached`. If a declared sitemap exists, or the default returns a non-`404`/`410` response, and no sitemap candidate succeeds after retries/validation, record `sitemap_unavailable`; link discovery may continue but coverage is partial.

Coverage classification is exhaustive. The content coverage set is every distinct canonical in-scope candidate retained by deduplication, plus every in-scope candidate discarded by a Crawl limit; robots-disallowed URLs, duplicate occurrences, unsupported media types, and redirect targets rejected by current scope are recorded as `policy_excluded` and are outside the denominator. An admitted content URL has a covered outcome only when it creates a valid Document, or returns terminal `404`/`410` and creates a valid body-free `crawl_observation` with reason `content_absent`. Exhausted timeout/`408`/`429`/`5xx`, DNS/TLS/connection failure, other `4xx`, redirect-limit exhaustion, malformed accepted media, Document validation failure, or per-URL body/request limit is `content_fetch_failed`, remains in the denominator, and makes coverage partial. `robots_unavailable_fail_closed` makes that Source root failed and coverage partial. A Source root succeeds only when its depth-zero URL ultimately creates a valid Document after in-scope redirects; every other root outcome is a Source-root failure even if another URL for that Source succeeds. For a completed run with no limit hit, any Source-root failure, `content_fetch_failed`, or `sitemap_unavailable` yields `completion_reason=partial_source_failure`; otherwise it is `completed`. A limit hit takes the higher `limit_reached` precedence already defined.

Selection under every finite bound is deterministic. Source roots are ordered by canonical root URL UTF-8 bytes and then Source ID. Sitemap candidates are ordered by sitemap-index depth, canonical URL UTF-8 bytes, and discovering sitemap URL; only the first 50 distinct candidates in that order are retained. Content traversal is breadth-first: all depth `d` discoveries are sealed before any depth `d+1` candidate is selected. Within one depth, dequeue order is `(depth, origin_rank, canonical_url, discovering_document_url, link_position)`, where `root < sitemap < link`, strings compare by UTF-8 bytes, and root or sitemap candidates use empty discovering-document URL and link position zero. Concurrent fetch completion does not change discovery order: completed responses are buffered and their outgoing links are canonicalized, sorted, and committed in dequeue sequence. All run-wide byte, page, and queue admission accounting is also applied in dequeue sequence. Deduplication retains the first candidate in this order. If more than 20,000 distinct candidates are discovered, retain the lowest 20,000 by this order and record all later candidates as `queue_limit_discarded`. The accepted-page limit retains the first 10,000 successful Documents in dequeue order; a later success is discarded as `page_limit_discarded` and cannot become Evidence.

`coverage_status` is `full` or `partial`. `completion_reason` is `completed`, `limit_reached`, `partial_source_failure`, `canceled`, or `failed`. The canonical Crawl state remains `completed`, `failed`, or `canceled`. A run is failed when it yields zero valid Documents or every active Source root fails. Otherwise terminal subset failures or limit hits produce completed with partial coverage. Evaluation may proceed from completed partial coverage; score status follows the completeness rules in the score model.

Terminal selection occurs once at a serialized checkpoint. A cancellation committed strictly before that checkpoint yields `Crawl.Canceled`; a cancellation at or after the checkpoint is rejected as `crawl_already_terminal`. At exactly the 60-minute boundary the wall-clock terminal handler wins over a simultaneous cancellation. Otherwise zero valid Documents or failure of every active Source root yields `Crawl.Failed`; otherwise the Crawl completes. The single completion reason follows precedence `canceled`, `failed`, `limit_reached`, `partial_source_failure`, then `completed`. Any in-scope candidate not evaluated because of depth, sitemap, queue, page, byte, response, request, or wall-clock bound makes coverage partial and records its exact limit reason. A completed Crawl is `full` only when every in-scope candidate admitted by the frozen discovery rules reached a terminal covered outcome and no Source or discovery path has an unresolved failure.

### Interim Parsing And Evaluation-Input Contract `parsing-interim-v1`

The parse manifest is the complete set of distinct Documents whose IngestionJobs reached `succeeded` for the selected Crawl, ordered by Source ID, canonical Document URL UTF-8 bytes, then Document ID. Each manifest tuple contains Organization, Project, Source, Crawl, IngestionJob, Document and input-Evidence IDs, whether the Document is the Source-root Document, media type, content digest, classification, and latest effective Evidence Validation Decision. A missing tuple, duplicate Document, cross-Organization reference, manifest/content-digest mismatch, or manifest that omits a succeeded IngestionJob is `input_manifest_invalid` and blocks Evaluation input readiness; an implementation cannot silently drop it.

Exactly one ParsingJob exists per `(document_id, content_digest, parser_definition_version)` tuple. It contains ParsingJob ID, all manifest references, parser definition and normalization-schema versions, current status, attempt number, last reason code, nullable Parsed Artifact ID/digest, state version, idempotency key, replay generation, queued/started/completed timestamps, and correlation/causation IDs. An exact duplicate ingestion signal returns the existing job. A changed digest or parser version creates a distinct job and cannot overwrite an earlier result.

Every successful job creates one immutable Parsed Artifact containing Artifact ID, all tenant/Project/Source/Document/ParsingJob references, canonical URL, Source-root boolean, input media type/digest, parser definition and normalization-schema versions, normalized-payload reference and SHA-256 digest, classification, created time, and correlation ID. The normalized payload MUST validate against its named immutable schema; Check Definition semantics and the mandatory baseline catalog remain separate inputs to WF-007. Parsed Artifact content never mutates.

The ParsingJob reason set and precedence are exhaustive. Before parser execution, first match wins in this order: `tenant_mismatch`, `input_quarantined`, `input_bytes_missing`, `input_digest_mismatch`, `unsupported_media_type`, `parser_policy_unavailable`. During execution, the only reasons are `parser_timeout`, `parser_dependency_unavailable`, or `normalized_output_invalid`. `text/html` and `application/xhtml+xml`, before media-type parameters, are the only baseline supported inputs. Unknown reasons map to `normalized_output_invalid` with restricted diagnostics and never become a successful artifact.

- Each attempt has a 30-second elapsed timeout; at exactly 30 seconds the timeout transition wins over parser completion.
- Only `parser_timeout` and `parser_dependency_unavailable` are internally retryable. They receive one initial attempt plus two retries exactly 30 and 120 seconds after the preceding failed attempt. A failure emits `ParsingFailed`; before an allowed retry the same job transitions `failed -> queued`, increments attempt number, and emits no second failure for the prior attempt.
- Every other reason is nonretryable. It transitions `running -> failed -> dead_letter` at the same serialized terminal checkpoint, emitting one `ParsingFailed` and one `ParsingDeadLettered`. Exhausting the third retry does the same. A late completion after timeout or dead letter is discarded and cannot create an Artifact.
- Authorized replay of `dead_letter` requires `parsing.recover`, expected job state version, a nonblank 20-2,000 character reason, and a new idempotency key. It increments replay generation and transitions that job to queued with attempt number one. Exact replay returns the same generation. A successful replay never changes an already sealed Evaluation Input Snapshot; a new Evaluation is required to consume it.

After every parse-manifest job is `succeeded` or `dead_letter`, the evaluation-input service creates one immutable Evaluation Input Snapshot containing snapshot, Organization, Project, Evaluation and Crawl IDs; Crawl coverage/status/reason; parser policy, definition and normalization-schema versions; every ordered manifest tuple with ParsingJob terminal state/reason and nullable Parsed Artifact ID/digest; successful and dead-letter counts; successful and total Source-root counts; failed-subset Document IDs/reasons; `readiness_status`; `coverage_status`; canonical content hash; created time; and correlation ID.

Readiness derivation is exact:

1. `blocked` when the manifest is invalid, parser policy is unavailable, zero Parsed Artifacts succeeded, or zero Source-root Parsed Artifacts succeeded. Coverage is `partial`; no checks execute.
2. `ready_full` when the Crawl coverage is full and every manifest job succeeded. Coverage is `full`.
3. `ready_partial` in every remaining case with at least one successful Parsed Artifact and at least one successful Source-root Parsed Artifact. Coverage is `partial`, and every failed Document/reason remains in the snapshot.

For an initial Evaluation, `ready_full` or `ready_partial` leaves it pending for WF-007's single start transition. `blocked` atomically transitions `Evaluation.Pending -> Evaluation.Running -> Evaluation.Failed` solely to record the terminal input-gate failure, emits one `EvaluationStarted`, one `EvaluationInputsBlocked`, and one `EvaluationFailed` with `evaluation_inputs_unavailable`, and performs no Check/provider side effect. For a reassessment Evaluation already running under WF-011, ready status attaches the snapshot without another start event; blocked transitions it once to failed with the same reason and triggers the reassessment failure/release path. `EvaluationInputsReady` is emitted exactly once only for `ready_full` or `ready_partial`.

### Interim Entitlement Contract

The mandatory provisional policy is `entitlement-interim-v1` until an approved OD-006 replacement activates. An Entitlement Policy contains policy and plan versions, Organization, effective time, and a required `operation_rules` map keyed by operation class. Each rule contains usage unit, UTC window start and end, soft limit, hard limit, grace behavior, reservation lifetime, maximum execution duration, and durable commit point. One active policy therefore governs all listed operation classes; a missing or duplicate class makes the policy invalid. If soft limit is omitted, the interim value is 80 percent of the hard limit, rounded down to the usage unit. Soft limit MUST be lower than hard limit.

High-cost operations are `crawl.start`, `reassessment.start`, `ai.generate`, and `export.generate`. Low-cost operations are `report.view`, `history.view`, `issue.read`, `recommendation.read`, and `score.read`. Under the OD-006 interim policy, a high-cost operation is allowed only when `committed_units + active_reserved_units + requested_units <= hard_limit`; a result greater than the hard limit is blocked, while equality is allowed. A resulting value greater than or equal to the soft limit returns allow-with-warning. A low-cost read at or above its hard limit remains allowed with an over-limit warning while the Organization remains active and either the human Account is active or the tenant-scoped service identity remains authorized. This interim classification does not approve the final grace policy.

Exactly one root high-cost operation governs a baseline execution. A direct/manual or scheduled initial Crawl uses `crawl.start`. `reassessment.start` subsumes its internally invoked WF-005 through WF-008 deterministic core and those stages MUST NOT also reserve or commit `crawl.start`; optional AI generation still uses a separate `ai.generate` request, and an Export uses `export.generate`. Every stage records the root Decision/reservation ID so nesting cannot double meter.

| Operation | Interim Usage Unit | Units Requested | Prestart Reservation Lifetime | Maximum Execution | Durable Commit Point |
| --- | --- | ---: | ---: | ---: | --- |
| `crawl.start` | `crawl_run` | 1 | 15 minutes | 65 minutes | Crawl reaches `completed` with at least one valid Document |
| `reassessment.start` | `reassessment_run` | 1 | 15 minutes | 120 minutes | replacement full-Project Issue set and ScoreSnapshot are promoted |
| `ai.generate` | `validated_ai_response` | 1 | 15 minutes | 2 minutes | validated AIResponse is persisted for downstream use |
| `export.generate` | `export_package` | 1 | 15 minutes | 15 minutes | Export becomes available |
| each low-cost read | `read_request` | 1 | 0; no reservation | request timeout of governing workflow | authorized response and its exactly-once LowCostUsageRecord reach the durable response checkpoint |

An approved Entitlement Policy may define an additional metered resource, but it MUST name its unit, reservation amount derivation, window, and commit/release point; absence of any field makes that policy invalid and blocks the high-cost action.

Every Entitlement Decision stores decision ID, Organization, human Account ID or service-identity ID, operation, usage unit, policy and plan versions, counter-window start and end, soft and hard limits, committed units before and after decision, active reserved units before and after decision, requested units, reservation ID nullable unless a high-cost action is allowed, nullable `cached_snapshot_id` and `cached_snapshot_age`, idempotency key, nullable `retry_of_decision_id`, decision (`allow`, `allow_with_warning`, or `block`), reason code, recovery action, and timestamps. Reason code is exactly one of `within_limit`, `soft_limit_reached`, `hard_limit_exceeded`, `organization_inactive`, `actor_inactive`, `service_unauthorized`, `entitlement_inactive`, `policy_unavailable`, `counter_unavailable`, `cached_policy_snapshot_used`, `cached_counter_snapshot_used`, `operation_unknown`, or `reservation_conflict`; recovery action is one of `none`, `wait_for_window`, `upgrade_plan`, `reactivate_organization`, `reactivate_actor`, `restore_policy`, `restore_counter`, `submit_new_attempt`, or `contact_support`.

Evaluation short-circuits in this precedence: `organization_inactive`, human `actor_inactive` or machine `service_unauthorized`, `entitlement_inactive`, `operation_unknown`, `policy_unavailable`, `counter_unavailable`, `reservation_conflict`, `hard_limit_exceeded`, `soft_limit_reached`, then `within_limit`. High-cost hard or any earlier failure returns Block; high-cost soft returns AllowWithWarning; high-cost within returns Allow. For a low-cost read only, policy or counter unavailability with an eligible atomic LowCostFallbackSnapshot instead returns AllowWithWarning using `cached_policy_snapshot_used` or `cached_counter_snapshot_used`; policy wins when both are unavailable. The Decision uses the complete cached policy-and-counter tuple rather than mixing a current component with a cached component. Recovery mapping is fixed: within/soft -> `none`; hard -> `wait_for_window`; Organization -> `reactivate_organization`; actor -> `reactivate_actor`; service or unknown operation -> `contact_support`; inactive entitlement -> `upgrade_plan`; policy/cached-policy -> `restore_policy`; counter/cached-counter -> `restore_counter`; reservation conflict -> `submit_new_attempt`.

Nullability follows the short-circuit and is not implementation choice. Organization/actor identity, operation, requested units, idempotency/retry lineage, decision, reason, recovery, and timestamps are always nonnull. For Organization/actor/service failure, all plan/policy/rule/counter/reservation/cache fields are null. For inactive entitlement, retain its assigned plan version when present and set policy/rule/counter/reservation/cache fields null. For unknown operation, retain plan version and set usage unit, policy/rule/counter/reservation/cache fields null. For unavailable policy, retain plan version and set policy version, rule/counter/reservation/cache fields null unless the bounded cached fallback is used, in which case store the complete cached versions/values, snapshot ID, and age. For unavailable counter, store plan/policy/rule fields but set all four before/after counter fields and reservation/cache fields null unless the same complete cached fallback is used. Every other Block has nonnull before counters with after counters equal to before and null reservation/cache fields. A high-cost Allow/AllowWithWarning has after active-reserved units equal to before plus requested units and a reservation; committed units do not change. A low-cost Decision has no reservation and its immutable decision-time before/after counters are equal; the separate LowCostUsageRecord below performs usage accounting at the durable response checkpoint.

A LowCostFallbackSnapshot is captured only when the active policy and authoritative counter are simultaneously valid. It contains snapshot ID, Organization, plan/policy/rule versions and normalized values, usage unit, counter window and values, and `snapshot_captured_at`. If either dependency is unavailable, fallback uses this whole tuple; it never combines values captured at different instants. `cached_snapshot_age = decision_time - snapshot_captured_at`, and fallback is allowed when that age is at most 24 hours. The cached counter view additionally includes every unreconciled LowCostUsageRecord for the same Organization/window committed strictly after snapshot capture, once by record ID. When both dependencies are unavailable, the Decision reason is `cached_policy_snapshot_used`; the one snapshot ID and age govern every cached field.

Every allowed low-cost read appends exactly one immutable LowCostUsageRecord at the same durable checkpoint that makes the authorized response returnable. The record contains Decision ID, Organization, operation, usage unit, counter window, requested units, idempotency key, and commit time; Decision ID is its uniqueness key. Counter resolution includes each record exactly once, including while authoritative reconciliation is delayed, and emits `EntitlementCommitted` with a null reservation ID. Exact command replay returns the stored response and record without another increment or event. A denied read or a request that never reaches the durable authorized-response checkpoint creates no record.

- High-cost allowance is an atomic reserve operation. Concurrent decisions MUST serialize against the same counter window.
- Queueing a high-cost action reserves nothing and creates no authoritative Entitlement Decision. Low-cost reads are checked immediately before their durable response; immediate high-cost work and queued high-cost work are checked only at the protected execution checkpoint immediately before their first provider or workflow side effect, where the Allow/AllowWithWarning Decision and reservation are created atomically.
- A high-cost reservation expires after its resolved prestart lifetime if execution has not started. Under `entitlement-interim-v1` that lifetime is exactly 15 minutes for every high-cost operation; an Organization policy may shorten it to a whole number of minutes from 1 through 15 but cannot lengthen it, and any missing, zero, fractional, or greater value makes the policy invalid. Once execution starts, it holds a renewable lease with a heartbeat at least every 5 minutes. At exactly the prestart expiry, execution-start loses to expiry. At exactly 15 minutes since the last accepted heartbeat or the maximum execution instant, the lease-expiry handler wins over a new heartbeat or protected side effect. It commits exactly once only if the durable commit point committed strictly before that instant; otherwise it releases exactly once. Cancellation or any terminal failure before the listed commit point releases even when intermediate Documents or other partial artifacts exist; those artifacts remain governed by their workflow but are not a usage commitment.
- Exact replay with the same idempotency key returns the immutable original Decision and current linked Reservation state and cannot double-count. After a blocked Decision or a Reservation reaches `released` or `expired`, a new execution attempt MUST use a new idempotency key and set `retry_of_decision_id` to the preceding Decision; reuse of the terminal key never creates or reopens a reservation.
- Attempting execution with an expired linked Reservation returns the immutable original Allow Decision plus current Reservation state and domain conflict `reservation_expired`; it creates no new Decision and performs no side effect. Only the new-key retry creates a fresh Decision.
- Missing, stale, or invalid counters or policy fail closed for high-cost operations. Low-cost reads may use the complete LowCostFallbackSnapshot for at most 24 hours under the exact cached reason above; after that they return a Block Decision with `policy_unavailable` or `counter_unavailable` plus outward reason `entitlement_unavailable`.

### Interim Notification Contract `notification-interim-v1`

The baseline channels are in-app and email. Mailgun is the selected baseline email delivery provider through adapter policy `mailgun-email-v1`; Postmark is not a baseline provider. Provider substitution requires a new adapter-policy version and must preserve every logical Delivery, idempotency, timeout, status-mapping, retry, bounce, and audit invariant in this contract. A logical Notification contains notification ID, triggering event ID and type, Organization and resource scope, template and policy versions, severity, action reference, occurred time, correlation ID, and aggregate status. Raw Evidence payloads, secrets, verification tokens, provider credentials, and unrestricted internal errors are prohibited from the payload. Baseline warning/critical routes, their severities, and both channels cannot be disabled. OrganizationAdmin may add or remove informational routes, choose an approved informational template, and manage opt-outs; SecurityOperator may version security templates, the support-queue roster, and critical-route selectors. Neither may add a new channel or broaden data visibility.

Baseline routes are:

| Trigger | Recipients | Required Permission | Severity |
| --- | --- | --- | --- |
| `SourceVerified` | request initiator and OrganizationAdmin accounts | `source.scope.propose` | informational |
| `SourceVerificationExpired` | request initiator and OrganizationAdmin accounts | `source.verify` | warning |
| `CrawlCompleted` with partial coverage, `CrawlFailed`, or `CrawlLimitReached` | run initiator; Project MarketingOperator accounts; OrganizationAdmin accounts | `history.read` | warning |
| `ScoreSnapshotPromoted` with partial status or `ScoreCalculationUnavailable` | Project MarketingOperator accounts; OrganizationAdmin accounts | `score.summary.read` | warning |
| `IssueAdjudicated`, `IssueDisputeWithdrawn` | adjudication requester and OrganizationAdmin accounts | `issue.read` | informational |
| `IssueAdjudicationOverdue` | SecurityOperator support queue | `issue.adjudicate` | warning |
| `IssueAdjudicationReminder` | SecurityOperator support queue | `issue.adjudicate` | warning |
| `IssueAdjudicationCritical` | SecurityOperator support queue | `issue.adjudicate` | critical |
| `EntitlementWarningIssued` or `EntitlementViolationDetected` | human initiating Account when present; otherwise Project MarketingOperator accounts; OrganizationAdmin and BillingOperator accounts | `entitlement.notice.read` | warning |
| `ExportAvailable` | Export requester | `export.retrieve` | informational |
| every transition to `ExportFailed` | Export requester | `export.retrieve` | warning |
| `SecurityIncidentCustomerActionRequired` | authorized SecurityOperator accounts and OrganizationAdmin accounts within the event's disclosure scope | `security.notice.read` | critical |

Each semicolon-separated selector component resolves active Accounts in the event Organization/resource scope that hold the route's Required Permission at event consumption. Components are unioned and deduplicated by Account ID into one stored recipient snapshot; a zero-result component records selector telemetry but is not independently a failure when another component supplies an authorized recipient. A SecurityOperator support-queue component additionally requires an active roster entry in the Notification Policy. Later roster changes affect only reauthorization, not addition of recipients. Each recipient receives one Delivery per required channel. If the final authorized union for a mandatory route is empty, the Notification becomes `failed` with reason `no_authorized_recipient`, creates no Delivery, and creates exactly one operational escalation record within 5 minutes; the escalation record exists even if no human is then assigned. Before each attempt the platform re-evaluates the route permission, Organization/resource scope, Account status, and current verified delivery address; later loss of authorization becomes `suppressed`, not sent. Informational email may be opted out and then becomes `suppressed` with `informational_email_opt_out`; in-app and all warning or critical deliveries are mandatory while the recipient remains authorized. After authorization and opt-out checks, an email Delivery with no current verified delivery address transitions directly to `terminal_failed` with `recipient_address_unavailable`, makes no Mailgun call, and follows the required-delivery escalation rule.

Delivery states are `pending`, `attempting`, `accepted`, `delivered`, `retry_scheduled`, `terminal_failed`, or `suppressed`. In-app becomes delivered when the authorized recipient record is durably created. Email becomes accepted when Mailgun accepts the idempotent request. `accepted` and `delivered` are success-stable states: no callback deadline or F1 resend applies, and accepted may remain accepted indefinitely, but either may become `terminal_failed` on a later authenticated permanent-failure event. `terminal_failed` and `suppressed` are absorbing. Mailgun provider event IDs are deduplicated. An authenticated event for any prior provider attempt is still authoritative while the Delivery is `retry_scheduled`: acceptance or delivery cancels the scheduled retry and moves to `accepted` or `delivered`; permanent failure cancels it and moves to `terminal_failed`. Duplicate or out-of-order acceptance/delivery events cannot regress a state; a permanent failure has precedence and can change retry-scheduled, accepted, or delivered to terminal-failed exactly once.

Each provider attempt has a 10-second timeout. A synchronous Mailgun `2xx` result maps to `accepted`; timeout, `408`, `429`, or `5xx` maps to `retry_scheduled`; and `400`, `401`, `403`, `404`, or any other non-`429` `4xx` maps to `terminal_failed`. Retryable results receive the initial attempt plus three retries at exactly 1, 5, and 30 minutes after completion of the preceding failed attempt. `Retry-After` replaces that retry's delay only when its raw value is an unsigned base-10 HTTP delta-seconds integer from `60` through `1800` inclusive; the delay is exactly that many elapsed seconds. HTTP-date, signed, fractional, whitespace-containing, malformed, or out-of-range values are ignored. There is no additional “transient” category.

Authenticated Mailgun events map as follows: `accepted` or `stored` maps to `accepted`; `delivered` maps to `delivered`; `failed` with permanent severity, `rejected`, `bounced`, `complained`, or `unsubscribed` maps to `terminal_failed`; and a temporary delivery failure maps to `accepted` because Mailgun owns that message's provider-side retry and F1 MUST NOT resend it. Unknown authenticated event types are retained as `provider_event_ignored` and do not change Delivery state. Failed signature/timestamp authentication is retained as restricted security telemetry and does not change state. For a single provider event ID, only the first authenticated mapping applies. Permanent-failure precedence applies across all attempt message IDs in the Delivery generation.

Provider requests use an idempotency token derived from Notification, recipient, channel, and replay generation. The Mailgun result contract stores adapter version, provider message and event IDs, authenticated-event result, normalized provider state, provider timestamp, received time, retry classification, and sanitized reason code; provider bodies and credentials are never retained in Notification payloads. In-app `delivered` and Mailgun email `accepted` or `delivered` count as success. The logical Notification is `sent` when every required nonsuppressed Delivery succeeds, `partial` when at least one succeeds and one terminally fails, `failed` when at least one required nonsuppressed Delivery exists and every such Delivery terminally fails, and `suppressed` when one or more Deliveries existed and every Delivery is suppressed before dispatch. Suppressed deliveries do not count as success or failure. A later permanent Mailgun failure recomputes the aggregate status and escalation exactly once.

Any terminally failed required Delivery creates exactly one escalation within 5 minutes in the SecurityOperator support queue with the Notification, recipient, channel, reason, attempts, and correlation ID. Privileged replay requires `notification.replay`, a 20-2,000 character reason, and creates a linked new replay generation; it never mutates prior attempts.

### Interim Export Contract `export-interim-v1`

Baseline formats are the logical output selections `pdf_report`, `csv_data`, and `json_data`; Volume I does not prescribe physical PDF layout, character encoding, delimiter, archive container, member naming, or byte-for-byte serialization. A `pdf_report` logical result contains the authorized ScoreSnapshot summary fields, published Issue summary fields, and published Recommendation fields defined by the score model. `csv_data` and `json_data` may additionally contain requester-selected Score Contribution and Evidence-metadata logical fields from that model. The frozen allowlist names every included object ID and logical field; no unlisted object or field may appear. Evidence payload bytes and restricted fields are never included unless the requester independently holds their read permission and the active Export Policy allows them. Baseline creates one Organization-scoped Export per request, sets recipient equal to the requesting Account, and creates no public or anonymous share. Multi-Organization export is prohibited; WF-018 must submit a separate approved Export per Organization.

The baseline maximum is 100 MiB encrypted package size and 250 MiB total uncompressed member size. The package is encrypted at rest and in transit, has no baseline digital-signature claim, and its frozen manifest expiry is exactly 24 hours after availability unless the creation-time policy is already shorter. An Organization Export Policy may remove formats, lower either size, shorten lifetime, or remove fields; it cannot broaden this baseline. Every retrieval resolves the then-active Export Policy. Its effective retrieval expiry is `min(frozen_manifest_expires_at, available_at_utc + current_policy_lifetime)`; current format, field, compressed-size, and uncompressed-size bounds also apply to the frozen manifest. At `now_utc >= effective_retrieval_expires_at`, the expiry checkpoint wins over retrieval, returns `export_expired`, emits no bytes, and the export lifecycle service materializes `Export.Expired` exactly once without changing the immutable manifest. A current-policy scope or size contraction that makes the package ineligible returns `export_scope_no_longer_authorized` and no bytes; the package is never partially stripped. Missing or invalid current Export Policy returns `policy_unavailable` and no bytes.

Every package has an immutable manifest containing Export, Organization, requester and recipient IDs; logical format; frozen object and field allowlists; `redacted_field_codes`; selected ScoreSnapshot, Evaluation, Issue-set, Recommendation, Evidence-metadata, scope, and policy versions; implementation-defined member filename and media type; member byte size and SHA-256 digest; total compressed and uncompressed sizes; package SHA-256; created, available, expires, and revoked times; and generation correlation ID. A manifest mismatch, omitted selected object, extra object/field, digest mismatch, size excess, or unsupported logical format fails generation and publishes no retrieval option. Acceptance validates decoded logical objects and fields plus the declared manifest/digests; it does not require two conforming serializers to emit byte-identical packages.

An Export is high-risk when it includes any restricted Evidence field or is requested by a SecurityOperator for an investigation. Each create or linked-retry generation attempt then requires its own single-use approval containing `approval_id`, Organization, requester, approver, logical format, exact object/field allowlists, request hash, `approved_at_utc`, `expires_at_utc` exactly 1 hour later, nullable `used_by_export_id`, and state version. The approver is a different active SecurityOperator holding `security.investigation.approve`. Creation and the immediate `Pending -> Generating` checkpoint must both commit before approval expiry; at the exact expiry instant expiry wins. Starting generation atomically sets `used_by_export_id`; reuse, altered content, self-approval, or a retry without a new approval is rejected before reservation or generation. Approval expiry after generation starts does not cancel that pinned attempt, but current permission revocation still stops it at the next protected checkpoint. Retrieval and revocation do not consume or require a new generation approval; they reauthorize their named permission, current investigation scope, and current policy independently.

## WF-001 Onboard Organization And Initial Project

- Identifier: WF-001
- Purpose: Establish an organization and first project with valid governance context.
- Actors: Eligible self-service registrant or invited Account; Organization Administrator after bootstrap
- Related Capabilities: CAP-001, CAP-002, CAP-003
- Trigger: User completes registration and starts onboarding.
- Preconditions: Identity validation succeeded and the Account is pending activation. A self-service registrant has an unconsumed, time-bounded bootstrap grant, or an invited user has an active invitation for an existing Organization.
- Primary Path:
  1. For self-service bootstrap, atomically create the Organization in pending state and assign the registering Account its first OrganizationAdmin Role Assignment.
  2. Activate the Account and Organization after the baseline access policy validates.
  3. Create the first Project in draft state using the exact WF-002 Project field contract.
  4. Consume the bootstrap grant and return the Organization, Account, Role Assignment, and Project identifiers.
- Alternate Path: Organization exists and user is invited as admin; workflow skips organization creation and proceeds to project creation if authorized.
- Failure Path: Invalid or conflicting identity, invitation, policy, or idempotency data rejects the atomic transaction and leaves no partially active Organization.
- Recovery Path: User corrects the identified input or obtains a new invitation or bootstrap grant, then retries with a new command; exact command replay returns the prior result.
- State Transitions: Account.Pending -> Account.Active; Organization.Pending -> Organization.Active; Project.Draft.
- Domain Events: AccountActivated, OrganizationCreated, OrganizationActivated, ProjectCreated.
- Authorization: Self-service creation requires the unconsumed `organization.bootstrap` grant; invited flow requires the invitation's Organization scope. No pre-existing OrganizationAdmin privilege is required before self-service tenant creation.
- Security Notes: Enforce tenant boundary establishment before project creation.
- Audit and Observability: Emit correlation_id across account, organization, and project events.
- Acceptance Criteria: AC-WF-001

## WF-002 Create And Activate Project Scope

- Identifier: WF-002
- Purpose: Create any tenant Project in draft and transition it to active when onboarding prerequisites are met.
- Actors: Organization Administrator, Marketing Operator
- Related Capabilities: CAP-003, CAP-004
- Trigger: User requests Project creation or activation.
- Preconditions: Organization is active. Creation requires `project.create`; activation requires an existing draft Project and `project.activate` in the Organization.
- Primary Path:
  1. For creation, normalize the display name to Unicode NFC, trim leading/trailing Unicode whitespace, and require 1-120 Unicode scalar values. `default_locale` MUST equal `en-AU`, `reporting_time_zone` MUST equal `UTC`, `local_presence_applicable` MUST be Boolean, its reason MUST be null when true and 20-500 trimmed scalar values when false, and objective MUST equal `discoverability_assessment`; every other value is rejected.
  2. Idempotently create exactly one draft Project in the actor's Organization and emit `ProjectCreated`.
  3. For activation, validate those required fields and at least one active Source belonging to the Project, then transition draft to active exactly once.
- Alternate Path: Creation may complete without activation. Activation leaves Project draft with reason `active_source_required` when no Source has completed verification and activation.
- Failure Path: Activation attempt blocked due to unmet policy checks.
- Recovery Path: Resolve missing requirements and re-attempt activation.
- State Transitions: Project.Draft -> Project.Active.
- Domain Events: ProjectCreated, ProjectActivated.
- Authorization: OrganizationAdmin or MarketingOperator holding `project.create` for creation and `project.activate` for activation.
- Security Notes: Activation rights must be explicitly granted.
- Audit and Observability: Creation input hash, creator, state version, activation check outcomes, replay result, and denial reasons are logged.
- Acceptance Criteria: AC-WF-002

## WF-003 Verify Property Ownership Or Control

- Identifier: WF-003
- Purpose: Confirm tenant authority over a source before activation.
- Actors: Organization Administrator, Technical Implementer
- Related Capabilities: CAP-004, CAP-005, CAP-006
- Trigger: Authorized user creates a verification request or requests an allowed on-demand observation.
- Preconditions: Source is `proposed`; its Project may be draft or active; actor holds `source.verify`; the canonical host is within the registered Source boundary; no other pending Verification Request exists for the Source.
- Primary Path:
  1. Validate the logical Verification Request, tenant references, idempotency key, and OD-001 interim method; generate, envelope-encrypt, persist, and securely deliver the recoverable pending challenge under the exact redelivery/deletion contract.
  2. Execute or skip automated slots and serialize authorized on-demand observations under the exact completion-cursor, in-progress reservation, count, window, method, hashing, reason, and timeout contract in the score and evidence model.
  3. For every started observation, persist restricted Verification Evidence and `SourceVerificationObserved`; on an exact match before expiry, include Request verification, `SourceVerified`, `source-scope-interim-v1`, and Source proposed-to-verified in the same transaction.
- Alternate Path: Mismatch or retryable dependency failure leaves the Verification Request pending and Source proposed until a scheduled or authorized on-demand observation succeeds.
- Failure Path: Unsupported method, invalid request, cross-Organization reference, stale state version, second nonreplay request while one is pending, idempotency conflict, or an exact on-demand concurrency/rate/count denial creates no observation. A pending request that reaches its 24-hour expiry becomes expired with `challenge_expired`; an authorized cancel uses its exact requester/admin reason; only the integrity-validation service may fail it with one of the two exhaustive integrity reasons. Source remains proposed in every terminal nonsuccess case.
- Recovery Path: Exact pending creation replay may redeliver the same challenge to an authorized actor. If decryption is unavailable, cancel then create a new Request; otherwise correct an immediately rejected request or create a new challenge after expired, canceled, or failed status. Terminal challenge material cannot be redelivered or reused.
- State Transitions: Source.Proposed -> Source.Verified on success only. Verification Request.Pending -> Verified, Expired, Canceled, or Failed.
- Domain Events: SourceVerificationRequested, SourceVerificationObserved, SourceVerified, SourceVerificationExpired, SourceVerificationCanceled, SourceVerificationFailed.
- Authorization: OrganizationAdmin or TechnicalImplementer holding `source.verify`; the request initiator or OrganizationAdmin may cancel a pending request; the verification service identity may observe only its assigned request.
- Security Notes: Prevent unauthorized property binding.
- Audit and Observability: Persist every challenge-delivery access without plaintext, cryptographic-deletion outcome, automated-slot due/window/started/skipped result, on-demand count/in-progress/completion cursor and denial, sanitized Verification Evidence and method-defined digest, attempt count, exact reason, policy, actor/service identity, latency, event IDs, correlation ID, and decision trail.
- Acceptance Criteria: AC-WF-003

## WF-004 Manage Source Scope

- Identifier: WF-004
- Purpose: Maintain active source scope for crawling and evaluation.
- Actors: Organization Administrator, Marketing Operator, Technical Implementer
- Related Capabilities: CAP-006, CAP-007
- Trigger: Source register, scope-change, activate, disable, reactivate, or remove request.
- Preconditions: The Project belongs to the actor's Organization. Registration requires `source.register`; scope proposal requires `source.scope.propose`; policy activation requires `policy.source_scope.manage`; Source lifecycle mutation requires `source.lifecycle.manage`. Existing-Source actions require the Source to belong to that Project.
- Primary Path:
  1. For registration, normalize the exact host, reject a duplicate same-Project host for any Source not `removed`, and create one proposed Source with immutable registration-scope version 1 and provenance. Re-registration after removal creates a new Source and never reopens the removed record.
  2. For an existing Source scope change, resolve the current Source Scope Policy, validate expected version, and apply an authorized contraction or create the required pending expansion request.
  3. Activate, disable, reactivate, or remove the Source only through a foundation-valid transition and persist the pinned policy version.
- Alternate Path: Same-host expansion requested by a non-admin remains pending for a different OrganizationAdmin decision for at most 24 hours.
- Failure Path: Cross-host expansion, unverified Source activation, stale policy version, boundary violation, unauthorized decision, or expired request changes no scope or Source state.
- Recovery Path: Narrow the request, verify a new Source, obtain the required approval, or resubmit against the current policy version.
- State Transitions: SourceScopeChangeRequest.Pending -> Approved, Rejected, Expired, or Canceled under the exact race rules. Source.Verified -> Source.Active; Source.Active -> Source.Disabled; Source.Disabled -> Source.Active or Source.Removed. Direct Source.Active -> Source.Removed and Source.Active -> Source.Verified are invalid.
- Domain Events: SourceRegistered, SourceScopeChangeRequested, SourceScopeChangeApproved, SourceScopeChangeRejected, SourceScopeChangeExpired, SourceScopeChangeCanceled, SourceActivated, SourceDisabled, SourceRemoved.
- Authorization: OrganizationAdmin, MarketingOperator, or TechnicalImplementer may register or propose scope with the named permission. Only OrganizationAdmin or MarketingOperator holding `source.lifecycle.manage` may activate/disable/reactivate/remove. Policy mutation requires `policy.source_scope.manage`; TechnicalImplementer cannot approve or activate one.
- Security Notes: Source scope must not cross tenant boundaries.
- Audit and Observability: Record normalized prior and proposed rules, request and approver identities, expected and activated versions, decision reason, effective time, affected running Crawls, and full Source lifecycle events.
- Acceptance Criteria: AC-WF-004

## WF-005 Execute Crawl And Ingestion

- Identifier: WF-005
- Purpose: Crawl active sources and ingest evidence artifacts.
- Actors: Organization Administrator, Marketing Operator, scheduler service identity; approved time-bounded SecurityOperator support session for terminal recovery only
- Related Capabilities: CAP-007, CAP-008
- Trigger: A manual/scheduled Crawl request or a Crawl Policy narrowing command.
- Preconditions: A Crawl request requires an active Project, at least one active Source, `crawl.trigger` or the Project scheduler authority, resolvable request-time Source Scope/Crawl Policy Snapshots, and Entitlement policy/counter context for the execution check. A policy command independently requires an active Organization, `policy.crawl.manage` at Organization or Project scope, expected current policy version, complete proposed limits, and its parent/global safety versions; it does not require an active Project/Source, `crawl.trigger`, Crawl entitlement/counter availability, or a Source snapshot.
- Primary Path (Crawl Execution):
  1. Create a queued Crawl pinned to the request-time scope, crawl, entitlement, and policy versions; queueing reserves no usage.
  2. Immediately before `Queued -> Running`, re-resolve policy and either atomically obtain `crawl.start` Decision/reservation for a root Crawl or validate the existing parent `reassessment.start` reservation for a reassessment stage; pin the execution snapshot, then start fetches under `crawl-interim-v1`, apply the canonical root/sitemap/breadth-first dequeue and concurrent-result commit order, validate every URL against the pinned and current restrictive scope, and collect only the retained accepted artifacts.
  3. Create IngestionJobs and transition each through canonical queued, running, and terminal states.
  4. At the serialized terminal checkpoint, derive Crawl state, coverage status, and the single completion reason using the exact boundary and precedence rules.
  5. For a root `crawl.start`, commit or release its reservation exactly once at the listed Crawl durable point. For a reassessment child stage, publish terminal telemetry but leave the parent `reassessment.start` reservation executing for WF-011's publication commit/release.
- Policy Management Subflow: OrganizationAdmin holding `policy.crawl.manage` may activate a more restrictive immutable Organization version; MarketingOperator with that permission may do so only for a Project. Every numeric value must be at or below the resolved parent/global hard and soft bounds and soft must not exceed hard. A stale, broader, incomplete, or unauthorized version changes nothing. A new restriction affects queued work immediately and running work at the next checkpoint under the global policy rule.
- Alternate Path: Some Source roots or Documents fail, or a hard limit is reached; successful subsets remain available and the Crawl completes with partial coverage when at least one valid Document exists and not every Source root failed.
- Failure Path: A current-policy or Entitlement Block before start transitions the queued Crawl to failed with its exact reason and no fetch/provider side effect or reservation. Zero valid Documents, failure of every active Source root, nonrecoverable policy or integrity error before useful output, or exhausted run-level recovery causes Crawl failed.
- Recovery Path: Per-fetch retry follows the fixed two-retry schedule. Authorized `crawl.recover` creates a linked new Crawl attempt after terminal failure; it does not move a completed or failed Crawl back to running.
- State Transitions: Crawl.Queued -> Crawl.Running, Crawl.Failed on the exact pre-execution gate, or Crawl.Canceled; Crawl.Running -> Crawl.Completed, Crawl.Failed, or Crawl.Canceled. A failed Crawl recovery creates a new linked Crawl.Queued attempt rather than transitioning the old record. IngestionJob.Queued -> IngestionJob.Running -> IngestionJob.Succeeded or IngestionJob.Failed; failed retry may return to queued and exhausted jobs enter dead_letter under the foundation model.
- Domain Events: CrawlPolicyActivated, CrawlQueued, CrawlStarted, CrawlSoftLimitApproaching, CrawlLimitReached, CrawlCompleted, CrawlFailed, CrawlCanceled, IngestionStarted, IngestionSucceeded, IngestionFailed, IngestionDeadLettered.
- Authorization: OrganizationAdmin or MarketingOperator holding `crawl.trigger`; scheduler service identity for configured Project schedules; cancellation requires `crawl.cancel`; terminal recovery requires `crawl.recover`, including a SecurityOperator only through an active Support Session that names the Crawl and recovery action. Policy narrowing separately requires OrganizationAdmin at Organization scope or MarketingOperator at Project scope holding `policy.crawl.manage`; no crawl-execution permission is implied.
- Security Notes: Crawler enforces the exact verified Source, Source Scope Policy, robots, redirect, and current restrictive-policy boundaries defined above; it invents no broader “legal” exception or bypass.
- Audit and Observability: Capture Crawl and attempt IDs, command and correlation IDs, all policy versions and effective limits, per-Source root status, retries, accepted pages and bytes, coverage status, completion reason, every limit value and observation, entitlement reservation outcome, and terminal state.
- Acceptance Criteria: AC-WF-005

## WF-006 Process Parsing And Validation Pipeline

- Identifier: WF-006
- Purpose: Transform raw crawl artifacts into validated evaluation inputs.
- Actors: System automation; Organization Administrator, Marketing Operator, or approved time-bounded SecurityOperator support session for dead-letter replay
- Related Capabilities: CAP-008, CAP-009, CAP-010, CAP-011
- Trigger: Ingestion completion signal, a retry timer, all parse-manifest jobs becoming terminal, or an authorized dead-letter replay command.
- Preconditions: Automated execution uses the complete selected-Crawl parse manifest and tenant-scoped parsing service. Human replay requires the target dead-letter ParsingJob, `parsing.recover`, expected state version, reason, and new idempotency key under `parsing-interim-v1`.
- Primary Path:
  1. Seal the complete ordered parse manifest and create/reuse one ParsingJob for every tuple.
  2. Execute each job under the exact timeout, reason-precedence, and retry rules; validate the immutable Parsed Artifact before success.
  3. When every job is terminal, create exactly one immutable Evaluation Input Snapshot and derive blocked, ready-full, or ready-partial without dropping a failed member.
  4. Continue the initial or reassessment Evaluation only through the lifecycle behavior in the parsing contract.
- Alternate Path: `ready_partial` continues with exact failed-subset identities/reasons and partial coverage; concurrent completion order never changes the ordered snapshot or hash.
- Failure Path: Any exact blocked predicate produces `evaluation_inputs_unavailable`, no Check/provider side effect, and the specified initial or reassessment Evaluation failure transaction.
- Recovery Path: Internal retry follows the fixed 30/120-second schedule. Authorized dead-letter replay follows the new-generation contract; later success is visible only to a new Evaluation Input Snapshot and Evaluation.
- State Transitions: IngestionJob.Succeeded -> ParsingJob.Queued -> ParsingJob.Running -> ParsingJob.Succeeded or ParsingJob.Failed; retryable ParsingJob.Failed -> ParsingJob.Queued; exhausted/nonretryable ParsingJob.Failed -> ParsingJob.DeadLetter; authorized DeadLetter -> Queued. Initial Evaluation remains Pending on ready or atomically Pending -> Running -> Failed on blocked; reassessment remains Running on ready or moves Running -> Failed on blocked.
- Domain Events: IngestionSucceeded, ParsingStarted, ParsingSucceeded, ParsingFailed, ParsingDeadLettered, ParsingReplayRequested, EvaluationInputsReady, EvaluationInputsBlocked, EvaluationStarted, EvaluationFailed.
- Authorization: Tenant-scoped parsing/evaluation service identities execute and retry; OrganizationAdmin or MarketingOperator holding `parsing.recover`, or a SecurityOperator through an active Support Session naming the job/action, may request dead-letter replay; only the parsing-recovery service performs it.
- Security Notes: Every input and output reference is same-Organization; quarantined/invalid Evidence cannot produce a Parsed Artifact; input sanitation and untrusted-content isolation are mandatory.
- Audit and Observability: Persist every contract field, manifest and snapshot hash, attempt/replay generation, scheduled/actual times, reason, failed subset, readiness derivation, Evaluation transition, authorization, event ID, and correlation ID.
- Acceptance Criteria: AC-WF-006

## WF-007 Generate Issues From Checks And Adjudicate

- Identifier: WF-007
- Purpose: Convert technical, content, and structured-data checks into canonical Issues and complete required adjudication without blocking eligible subsets.
- Actors: System automation; Organization Administrator, Marketing Operator, or Technical Implementer for disputes; Security Operator or approved support session for adjudication
- Related Capabilities: CAP-009, CAP-010, CAP-011, CAP-013, CAP-014
- Trigger: Immutable Evaluation input snapshot is ready, an authorized dispute/adjudication command is submitted, or an Evidence Validation Decision command/automated determination occurs.
- Preconditions: Evaluation generation requires Check definitions, pillar mappings, model/rule versions, confidence policy, Issue fingerprint version, valid Evidence, and tenant-scoped service identity. Adjudication follows its Case preconditions. Evidence validation follows the action-specific subflow below rather than requiring the Evidence to remain valid.
- Primary Path:
  1. For an initial pending Evaluation, transition it to running after input readiness; for a reassessment Evaluation already running under WF-011, validate its matching immutable orchestration/readiness snapshots and continue without another transition or EvaluationStarted event. Execute the frozen Check Definition set against the frozen input tuple.
  2. Persist deterministic Check Results and bind each failed result to valid same-Organization Evidence.
  3. Atomically create or replay exactly one same-run Issue per full fingerprint preimage, with state derived from confidence.
  4. After every required Check Result is terminal and the Issue set is internally consistent, seal the immutable Evaluation Issue set and transition Evaluation to completed. It remains staged and does not advance a current Issue-set pointer until WF-008 can atomically promote it with a scorable ScoreSnapshot.
- Alternate Path: A failed check with low, missing, or invalid confidence creates `candidate / review_required / withheld`, starts the 48-hour adjudication SLA, and does not block completion, scoring of the eligible subset, or other recommendation generation.
- Failure Path: Missing policy or definition version, invalid or cross-Organization Evidence, unhandled check error, inconsistent replay, or atomic publish failure transitions Evaluation running to failed and publishes no partial Issue set as current.
- Recovery Path: Retryable service failure uses the same command and input hashes. A failed Evaluation is retained; rerun creates a new pending Evaluation linked to it. Hash collision follows the non-merge collision path in the score and evidence model.
- Adjudication Subflow:
  1. An authorized dispute supplies expected Issue state version, 20-2,000 character reason, and idempotency key; the Issue becomes disputed and suppressed.
  2. A SecurityOperator or approved support session different from the requester assigns the case and decides uphold or reject with expected Issue and Case state versions, exact decision reason, and a 20-4,000 character rationale, or the requester/OrganizationAdmin withdraws a dispute before decision with both versions and a 20-2,000 character reason.
  3. Upheld or withdrawn Issues become published and eligible; rejected Issues become dismissed with Issue closure reason equal to the Case reject reason. Before dispute, uphold, rejection, or withdrawal commits, atomically make the Current Score Projection unavailable with `issue_set_incomplete` and suppress every published Recommendation Artifact whose origin is the affected Issue; every outcome then triggers idempotent score and downstream projection refresh under the score model.
  4. At 24 hours for disputes or 48 hours for system review, unresolved cases become overdue without automatic decision and follow the exact escalation schedule in the score and evidence model.
- Evidence Validation Subflow:
  1. A command names Evidence, prior effective status, expected validation-state version, resulting status, enumerated reason, policy version, authority, idempotency key, and correlation ID. A stale version, same-status request, or unlisted transition/reason is rejected without a Decision.
  2. A SecurityOperator holding `evidence.validation.manage` in active incident/adjudication/support scope may submit only `valid -> quarantined` for `security_restriction`, `consent_review`, or `retention_review`. The integrity-validation service may execute every transition/reason expressly allowed by the Evidence contract. Neither may mutate Evidence bytes or an earlier Decision.
  3. Atomically append the Decision and `EvidenceValidationChanged`, update every affected current score/Recommendation projection before commit, and enqueue idempotent recalculation. Exact replay returns the Decision without repeating suppression, event, or recalculation.
  4. Revalidation or corrected authority submits a new Decision against the latest version. Invalid is terminal; corrected content is new Evidence.
- State Transitions: Initial Evaluation.Pending -> Evaluation.Running -> Evaluation.Completed or Evaluation.Failed. Reassessment enters Running in WF-011 and WF-007 changes that Running Evaluation only to Completed or Failed. Issue transitions are exactly those in the Issue lifecycle and adjudication state machine.
- Domain Events: EvaluationStarted, CheckResultCreated, IssueCreated, IssueDisputed, IssueAdjudicationAssigned, IssueAdjudicated, IssueDisputeWithdrawn, IssueAdjudicationOverdue, IssueAdjudicationReminder, IssueAdjudicationCritical, EvaluationCompleted, EvaluationFailed, IssueFingerprintCollision, EvidenceValidationChanged.
- Authorization: Evaluation service identity for checks and creation; `issue.dispute` for dispute or withdrawal as defined; `issue.adjudicate` for assignment and decision; `evidence.validation.manage` under the exact operator/service limits for Evidence transitions. No other actor may change Issue or Evidence validation state.
- Security Notes: Ensure check outputs cannot access data outside tenant scope.
- Audit and Observability: Track frozen input and output hashes, definitions and policies, Evidence references, fingerprint preimage and hash, replay/collision outcome, Issue state versions, case requester and adjudicator, decisions, SLA due and overdue timestamps, downstream recalculation ID, and exact failure reason.
- Acceptance Criteria: AC-WF-007

## WF-008 Calculate Score From Issues

- Identifier: WF-008
- Purpose: Produce immutable, exactly reproducible Discoverability Score snapshots from governed Issues and Evidence.
- Actors: System automation
- Related Capabilities: CAP-012, CAP-015, CAP-018
- Trigger: Evaluation completed, Issue adjudicated, Issue disputed, dispute withdrawn, Evidence validation changed, or approved policy recalculation requested.
- Preconditions: Exactly one sealed staged prospective Issue set for Evaluation completion/reassessment, or the atomic current Issue set for recalculation; all required policy and catalog versions; scope snapshot; valid contribution input hashes; score eligibility determinable for every Issue in the selected set.
- Primary Path:
  1. Validate the selected Issue Set's exact membership/current-leaf lists and freeze/hash its state-at-snapshot fields, current effective Evidence Validation Decisions, Check Results, exact scope/coverage, applicability, catalog, and policy inputs.
  2. Create one included or excluded Score Contribution for every Issue in the selected set using the fixed exclusion precedence, Evidence list, and impact-table penalty; compute all pillar values, weights, status, ordered coverage reasons, and overall value under `score-interim-v1` or its approved replacement.
  3. Validate the normative invariants and fixtures, then create or reuse the immutable idempotent ScoreSnapshot.
  4. For an initial Evaluation completion, atomically promote its staged Issue set, complete/partial ScoreSnapshot, and Current Score Projection. In reassessment staging mode, return complete/partial validated staged records to WF-011 without advancing any pointer; an unavailable staged result changes no Current Score Projection field or pointer and returns `score_unavailable` to WF-011, with any retained diagnostics correlated only to that Evaluation. For adjudication, Evidence revalidation, or policy recalculation, atomically promote the new complete/partial ScoreSnapshot against the already-current Issue set and update the projection. Every other unavailable calculation creates/reuses an immutable unavailable ScoreSnapshot and diagnostic Contributions, advances only `latest_calculation_issue_set_id` and `latest_calculation_score_snapshot_id`, leaves nullable `current_issue_set_id` and last-promoted snapshot unchanged, and sets availability/recommendation suppression with the complete ordered reason-code set.
- Alternate Path: Review-required, disputed, and in-review Issues receive zero-value excluded contributions under the OD-009 interim policy; scoring continues with `partial` status when every applicable pillar still has valid terminal coverage.
- Failure Path: Apply the score model's exhaustive mapping: incomplete membership or state-version mismatch -> `issue_set_incomplete`; missing/invalid score, confidence, or eligibility policy -> its named policy-unavailable code; bad scope -> `scope_definition_invalid`; missing catalog -> `check_catalog_unavailable`; uncovered pillar -> `applicable_pillar_insufficient_data`; any non-valid current score input Evidence -> `invalid_evidence`; reconciliation mismatch -> `contribution_mismatch`; every otherwise unclassified invariant -> `score_invariant_failure`. Persist all applicable codes in fixed precedence, advance no promoted pointer, and suppress origin-Issue Recommendations. Reassessment staging additionally preserves every pre-attempt projection field.
- Recovery Path: Correct the missing or inconsistent input and submit an idempotent recalculation. Identical inputs return the stored result; changed inputs create a new snapshot without mutating history.
- State Transitions: No Evaluation transition. Score calculation result becomes Complete, Partial, or Unavailable; only Complete or Partial advances the current ScoreSnapshot pointer.
- Domain Events: ScoreSnapshotCreated, ScoreSnapshotPromoted, ScoreCalculationUnavailable, ScoreRecalculated, EvidenceValidationChanged.
- Authorization: Tenant-scoped scoring service identity only; policy recalculation additionally requires an approved active policy version.
- Security Notes: Score visibility follows the exact role, classification, and delivery-surface matrix in the score and evidence model.
- Audit and Observability: Persist every policy and catalog version, input-set hash, contribution inclusion or exclusion, unrounded and rounded values, effective weights, coverage and completeness reasons, prior snapshot, creation trigger, idempotency outcome, and movement attribution.
- Acceptance Criteria: AC-WF-008

## WF-009 Generate Recommendations

- Identifier: WF-009
- Purpose: Generate actionable Recommendation Artifacts from Issues and score context.
- Actors: System automation
- Related Capabilities: CAP-012, CAP-016, CAP-017
- Trigger: A complete or partial ScoreSnapshot is promoted, or Issue eligibility changes.
- Preconditions: The atomic Issue set is stable, meaning its current pointer and every referenced Issue `state_version` match the frozen generation input; each candidate has exactly one current origin Issue and valid citation-ready Evidence in that Issue/Check lineage.
- Primary Path:
- Primary Path:
  1. Select each current score-eligible Issue requiring action as the sole origin of a separate Recommendation Artifact; optional related Issue references remain informational.
  2. For `ai_assisted`, create/replay the fingerprinted AIResponse request, atomically persist its generated payload and proposed one-AIResponse/one-Evidence Citations, then run `citation-interim-v1` validation. The validation transaction persists every Citation decision, changes the response to validated or rejected, and binds draft content only on complete coverage. For `deterministic_template`, generate directly from the versioned template with null AIResponse ID and origin-lineage Evidence.
  3. Validate Artifact schema, exact origin impact/confidence, `advisory_scope=discoverability_only`, AIResponse/Citation coverage when applicable, origin eligibility/Evidence, and policy constraints; reject every personalized legal/tax conclusion, determination, filing position, or action instruction as `prohibited_advisory_domain`.
- Alternate Path: AI-assisted generation is rejected, expires, or is unavailable; a new deterministic-template Artifact version may be generated. A withheld Issue may have a draft but cannot publish.
- Failure Path: AIResponse/Citation or Artifact validation fails, enters a prohibited advisory domain, lacks valid origin-lineage Evidence, references a stale/ineligible origin, or changes during generation; persist the exact rejected response/Citation outcomes where created and publish no Artifact. `prohibited_advisory_domain` is nonretryable for the same content; recovery requires a discoverability-only new AIResponse attempt or template version.
- Recovery Path: Regenerate from the same frozen eligible origin using a new linked AIResponse attempt or the versioned deterministic template with `advisory_scope=discoverability_only`; if that output fails schema, Citation, Evidence, eligibility, or advisory-domain validation, retain draft/failure metadata and publish nothing.
- State Transitions: Recommendation.Draft -> Recommendation.Published or Recommendation.Suppressed; Published -> Suppressed when its origin Issue becomes ineligible; Suppressed -> Published only after that origin is eligible and validation reruns. AIResponse and Citation transitions are exactly those in `citation-interim-v1`.
- Domain Events: RecommendationArtifactGenerated, RecommendationPublished, RecommendationSuppressed, AIResponseRequested, AIResponseGenerated, AIResponseValidated, AIResponseRejected, AIResponseExpired, CitationProposed, CitationVerified, CitationInvalidated, CitationSuperseded, AIResponseFingerprintCollision, CitationFingerprintCollision.
- Authorization: Generation service identity; deterministic auto-publication service or OrganizationAdmin/MarketingOperator holding `recommendation.publish`. TechnicalImplementer is a consumer and cannot publish.
- Security Notes: Enforce AI safety and prompt integrity constraints.
- Audit and Observability: Log origin/related Issue distinction, generation mode, response/Citation fingerprints and replay outcomes, prompt/model/policy versions, every claim/Citation decision, expiry/binding, Artifact version, and validation outcome.
- Acceptance Criteria: AC-WF-009

## WF-010 Prioritize And Publish Action Queue

- Identifier: WF-010
- Purpose: Produce prioritized execution queue for recommendations and report outcomes.
- Actors: Organization Administrator, Marketing Operator; read-only Executive Buyer as consumer
- Related Capabilities: CAP-016, CAP-017, CAP-018, CAP-022
- Trigger: Recommendation publication completed.
- Preconditions: Frozen set of published Recommendation Artifacts whose sole origin Issues are score-eligible; priority policy version available.
- Primary Path:
  1. Read each origin Issue's persisted impact/confidence plus Artifact effort, creation time, and identifier factors.
  2. Compute the exact lexicographic base ordering under `priority-interim-v1` and persist every sort input and input hash.
  3. Publish the action queue. An optional report export is a separate authorized `ExportRequested` command into WF-016 and cannot emit `ExportAvailable` directly.
- Alternate Path: OrganizationAdmin or MarketingOperator applies a display-order override with prior and resulting order, actor, timestamp, and a 20-2,000 character reason; base order remains unchanged and queryable.
- Failure Path: Prioritization fails due to incomplete factor set.
- Recovery Path: Backfill missing factors and recalculate priority.
- State Transitions: Recommendation publication status does not change; creation of an immutable Priority Decision records prioritization.
- Domain Events: RecommendationPrioritized, ActionQueuePublished; optional export continues with ExportRequested in WF-016.
- Authorization: Priority service identity computes base order; manual override requires `priority.override`; export requires `export.create`. Executive Buyer can read but cannot reorder or create a full-detail export.
- Security Notes: Manual overrides require actor attribution.
- Audit and Observability: Track ranking inputs and manual override events.
- Acceptance Criteria: AC-WF-010

## WF-011 Trigger Reassessment

- Identifier: WF-011
- Purpose: Re-run discovery and Evaluation to atomically publish a superseding Issue set and ScoreSnapshot while preserving the last successful current result until replacement succeeds.
- Actors: Organization Administrator, Marketing Operator, scheduler service identity
- Related Capabilities: CAP-007, CAP-015, CAP-019, CAP-020
- Trigger: Scheduled/manual reassessment request or an authorized cancellation command targeting its Evaluation.
- Preconditions: Start requires `reassessment.trigger`, an active Project with at least one active Source, the complete active Source set, one prior completed Evaluation with current promoted Issue Set and ScoreSnapshot, and current Entitlement, Source Scope, Crawl, score, confidence, eligibility, and fingerprint policy context. Cancellation requires `reassessment.cancel`, the target Evaluation and orchestration context, expected Evaluation state version, nonblank 20-2,000 character reason, and the same Organization/Project scope.
- Primary Path:
  1. Immediately before execution, re-resolve policy, obtain the high-cost `reassessment.start` Decision/reservation, freeze active Source-set version and normalized full-scope hash, then atomically create the new Evaluation and move it `Pending -> Running` with its immutable orchestration context linked to the prior completed Evaluation.
  2. Execute WF-005 through WF-007 using immutable stage input hashes and pinned policy snapshots; derive and seal the exact planned predecessor/Case transitions and prospective successor Issue set without changing current pointers; then invoke WF-008 in reassessment staging mode against that prospective final set so it creates/reuses Contributions and a scorable ScoreSnapshot without promotion.
  3. Immediately before publication, re-resolve the active Source-set version and normalized full-scope hash. If either differs from the frozen values, fail with `source_scope_changed_during_reassessment`; otherwise, in one atomic commit apply exact same/new/absence-proof/incomplete-coverage supersession and Case-carry rules and persist the final successor Issue set, staged Contributions and ScoreSnapshot, Recommendation deltas, completed Reassessment Result, all current pointers/projection, and entitlement-commit outbox intent.
  4. After commit, publish the attributable Issue, score, Recommendation, scope, and coverage events and consume the entitlement intent exactly once.
- Alternate Path: With no prior promoted Evaluation pair, reject `initial_evaluation_required` before Entitlement, Evaluation, or Reassessment Result creation. A scope-limited request likewise produces only command rejection `scope_limited_reassessment_unsupported` and no reservation, Evaluation, or Reassessment Result. An Entitlement Block after those checks returns a failed Reassessment Result with null current Evaluation, `terminal_reason_code=entitlement_blocked`, and the linked Entitlement Decision carrying its exact reason; it creates no reservation or stage output.
- Cancellation Path: A targetable Evaluation is never durably visible in `pending`, because creation and start are atomic. Cancellation committed while it is running transitions it to failed with `canceled_by_actor`, records a canceled Reassessment Result, and releases. Cancellation committed after Evaluation completion but before publication leaves the Evaluation completed, records the canceled Result, discards staged publication, and releases. At the exact Evaluation-completion checkpoint completion wins and the cancellation is then evaluated in the post-completion window; at the exact publication commit publication wins and cancellation is rejected as `reassessment_already_terminal`. Cancellation before an Evaluation identifier exists or after a terminal Result is rejected with no state change.
- Failure Path: Pipeline failure or timeout before Evaluation completion transitions running to failed. Unavailable score, Source/scope race, or atomic publication failure after Evaluation completion leaves the Evaluation completed. Each records a failed terminal Reassessment Result outside the failed publication transaction, emits no entitlement commit intent, releases the reservation, and leaves every prior current pointer and every Current Score Projection field unchanged; an unavailable staged ScoreSnapshot is diagnostic only and never becomes latest/current.
- Recovery Path: Retry creates a new Evaluation attempt linked by causation ID. A completed immutable stage may be reused only when its full input hash matches; replay cannot duplicate Issues, usage, snapshots, or events.
- State Transitions: Evaluation.Pending -> Evaluation.Running occurs in the creation transaction; Running -> Completed or Failed. Running cancellation uses Failed plus `canceled_by_actor`; post-completion cancellation never changes Evaluation.Completed. Reassessment Result is an immutable completed, failed, or canceled terminal outcome, not a separate mutable domain state machine.
- Domain Events: ReassessmentTriggered, EvaluationStarted, ReassessmentCompleted, ReassessmentFailed, ReassessmentCanceled, IssueSuperseded, IssueResolved, ScoreSnapshotPromoted.
- Authorization: OrganizationAdmin or MarketingOperator holding `reassessment.trigger`, or Project scheduler service identity, may start. OrganizationAdmin or MarketingOperator holding `reassessment.cancel` may cancel under the exact timing rules. The reassessment service performs only pinned start/cancel/publication actions.
- Security Notes: Preserve tenant boundaries across historical run linking.
- Audit and Observability: Link all Evaluation attempts, stage hashes, scope and policy snapshots, entitlement reservation, prior and current pointers, each supersession or unresolved-resolution reason, atomic publish outcome, retry causation, and failure code.
- Acceptance Criteria: AC-WF-011

## WF-012 Compare Historical Results

- Identifier: WF-012
- Purpose: Present prior-versus-current discoverability outcomes with attributable deltas.
- Actors: Organization Administrator, Marketing Operator, Technical Implementer, read-only Executive Buyer, authorized SecurityOperator scope
- Related Capabilities: CAP-014, CAP-015, CAP-019, CAP-020
- Trigger: User opens historical comparison view.
- Preconditions: Actor holds `history.read`. Numeric comparison additionally requires two completed promoted ScoreSnapshots satisfying the exact compatibility predicate in the score and evidence model.
- Primary Path:
  1. Retrieve the selected snapshots and their state-at-snapshot Issue, Recommendation, scope, coverage, and policy versions.
  2. Validate compatibility and compute exact score, Issue, and Recommendation deltas only when compatible.
  3. Return attributable delta records and comparison status; generated narrative cannot alter or replace numeric facts.
- Alternate Path: Non-consecutive compatible runs may be selected. An explicit rebase requires OrganizationAdmin `score.rebase` and exact requested score, confidence, eligibility, fingerprint, catalog, scope-policy, and applicability versions available to both retained input sets. It creates separate immutable noncurrent snapshots under those versions before comparison; omission or ambiguity of any target version rejects the rebase, and different normalized scope-definition hashes remain noncomparable.
- Failure Path: With fewer than two completed Evaluations, return `insufficient_history` and available count. With mismatched required dimensions, return `not_comparable`, all applicable fixed-order codes from the score model, and no numeric score delta. Missing projection data returns `comparison_unavailable` with correlation ID and does not synthesize values.
- Recovery Path: Select a compatible pair, request an authorized rebase, or retry projection generation. Projection rebuild is bounded to one initial attempt plus two retries at 1 and 5 minutes, then returns terminal `comparison_unavailable` and escalates to support.
- State Transitions: No domain entity transition required; read-model generation lifecycle.
- Domain Events: ComparisonGenerated.
- Authorization: OrganizationAdmin, MarketingOperator, TechnicalImplementer, read-only Executive Buyer, or authorized SecurityOperator scope holding `history.read`; field-level redaction follows the score model. Rebase additionally requires OrganizationAdmin `score.rebase`.
- Security Notes: Historical access restricted by tenant scope.
- Audit and Observability: Log actor and scope, selected snapshot IDs, compatibility inputs and result, mismatch codes, rebase snapshot IDs, retry count, redaction result, latency, and correlation ID.
- Acceptance Criteria: AC-WF-012

## WF-013 Manage Roles, Access Policies, And Account Lifecycle

- Identifier: WF-013
- Purpose: Administer role assignment, access policy, and tenant Account lifecycle updates.
- Actors: Organization Administrator, Security Operator
- Related Capabilities: CAP-001, CAP-002, CAP-024, CAP-025
- Trigger: Authorized actor submits a Role Assignment, Access Policy, Support Session, Account suspension/reactivation/revocation, or Account deletion command, or the lifecycle service reaches a Support Session due/expiry time.
- Preconditions: Organization is active. A Role Assignment or Account action requires its target Account to belong to the Organization; Access Policy and Support Session actions use their own Organization/resource scope. A human actor holds the exact action permission, and every command on an existing record includes its expected state or policy version. Timed Support Session expiry is executed only by the lifecycle service from the persisted due or expiry time.
- Primary Path:
  1. Validate tenant scope, permission subset, requester authority, expected version, separation rules, and expiry.
  2. For a non-protected grant, activate the Role Assignment or new immutable Access Policy version; for a protected grant, create pending approval due in 24 hours.
  3. On valid distinct SecurityOperator approval, atomically activate and supersede affected policy; on revocation, immediately mark the assignment revoked.
  4. Invalidate or refresh authorization context so the next protected request uses the new decision and all session caches converge within 60 seconds.
- Alternate Path: Protected grant remains pending without conferring access until a different SecurityOperator approves it.
- Failure Path: Unauthorized, self-approved protected, privilege-escalating, cross-Organization, stale-version, conflicting-active-policy, expired, or idempotency-conflicting command changes nothing and emits an auditable denial.
- Recovery Path: Correct scope or permissions, obtain the different approver before expiry, or submit a new version against the current active version. Expired or rejected assignments cannot be activated.
- Account Lifecycle Subflow:
  1. Suspension requires `account.suspend`, expected Account state version, and nonblank 20-2,000 character reason; it atomically transitions active to suspended and revokes sessions before success returns.
  2. Reactivation requires `account.reactivate`, valid identity and retained unexpired assignments, and transitions suspended to active; expired or revoked grants are not restored.
  3. Permanent access removal requires `account.revoke` and transitions active or suspended to revoked. The last active OrganizationAdmin Account cannot be suspended or revoked unless another active Account receives an active OrganizationAdmin assignment in the same transaction.
  4. Deletion requires `account.delete`, first reaches revoked if necessary, and creates one idempotent LifecycleDeletionJob under the active retention/legal-hold policy. Legal hold yields `deletion_blocked_legal_hold` while access remains revoked; eligible data reaches deletion-complete with retained deletion evidence. No command silently hard-deletes audit evidence.
  5. A SecurityOperator Account action additionally requires one active Support Session naming the Account and exact action; that session's distinct approval supplies the required dual control. An Incident without such a session is insufficient. OrganizationAdmin tenant action does not require a Support Session but remains subject to the last-admin and protected-permission rules.
- Support Session Subflow:
  1. A SecurityOperator holding `support.session.request` creates `pending` with exact Organization/resource/action allowlists and `approval_due_at_utc=requested_at_utc+24 hours`.
  2. Cross-Organization access collects the affected OrganizationAdmin approval unless the exact critical-emergency predicate in the Support Session contract is already true. A different SecurityOperator holding `support.session.approve` supplies the final security approval.
  3. The final required approval atomically activates the session immediately for four hours. A required approver may instead reject before activation. At exactly the pending due time the support-session lifecycle service holding `support.session.expire` expires an incompletely approved request.
  4. The requester, approver, or affected Incident commander holding `support.session.revoke` may revoke an active session; at exactly its active expiry the lifecycle service holding `support.session.expire` expires it. Reject, expiry, revoke, stale version, or replay can never extend or reactivate it.
- State Transitions: RoleAssignment.Pending -> Active, Rejected, or Expired; Active -> Revoked or Expired. AccessPolicy.Draft -> Active or Retired; Active -> Superseded or Retired. SupportSession.Pending -> Active, Rejected, or Expired; Active -> Expired or Revoked. Account.Active -> Account.Suspended or Account.Revoked; Account.Suspended -> Account.Active or Account.Revoked. LifecycleDeletionJob.Queued -> Running, Blocked, or Failed; Running -> Completed, Blocked, or Failed; Blocked -> Queued only after hold release; Failed -> Queued through authorized idempotent retry. Completed is terminal. All other transitions are invalid.
- Domain Events: RoleAssignmentRequested, RoleGranted, RoleRejected, RoleRevoked, RoleExpired, AccessPolicyActivated, AccessPolicySuperseded, AccessPolicyRetired, SupportSessionRequested, SupportSessionActivated, SupportSessionRejected, SupportSessionExpired, SupportSessionRevoked, AccountSuspended, AccountReactivated, AccountRevoked, AccountDeletionRequested, AccountDeletionBlocked, AccountDeletionCompleted.
- Authorization: OrganizationAdmin may manage non-protected tenant grants and tenant-managed Accounts; SecurityOperator may manage and distinctly approve protected grants or take scoped security lifecycle action. No actor may approve its own protected request. The lifecycle service executes deletion work only from an approved command.
- Security Notes: Enforce least privilege and immutable audit logs.
- Audit and Observability: Record canonical prior and proposed content hashes, versions, request and approver, separation result, scope, reason, due/effective/expiry times, every Support Session approval reference and allowlist, event IDs, Account from/to state, last-admin check, deletion/legal-hold outcome, affected sessions, cache convergence time, and every denied or stale attempt.
- Acceptance Criteria: AC-WF-013

## WF-014 Deliver Notifications

- Identifier: WF-014
- Purpose: Dispatch notifications based on defined lifecycle and failure events.
- Actors: Notification service identity; Organization Administrator or Security Operator for allowed policy changes; approved time-bounded SecurityOperator support session for replay and terminal recovery
- Related Capabilities: CAP-021
- Trigger: An event listed in the active Notification Policy route table is consumed, or an authorized Notification Policy activation command is submitted.
- Preconditions: Delivery requires a valid not-previously-consumed event envelope, active `notification-interim-v1` or approved replacement, and schema-valid evaluable selectors; a zero-account mandatory union follows the defined failure path. A policy command instead requires expected current policy version and the exact policy-management authority below.
- Primary Path:
  1. Idempotently create one logical Notification from triggering event, policy version, template version, and resource context.
  2. Resolve the exact recipient set and create one in-app and one email Delivery per recipient unless informational email was opted out.
  3. Before every attempt, re-evaluate authorization, apply field redaction, and suppress a no-longer-authorized Delivery.
  4. Dispatch with provider idempotency token, persist per-attempt result and provider message ID, apply the exact synchronous-result and authenticated-event mapping, cancel a scheduled retry when a prior-attempt event becomes authoritative, apply the exact 1-, 5-, and 30-minute delays after preceding failures, and derive aggregate status.
- Policy Management Subflow: OrganizationAdmin holding `policy.notification.manage` may submit an immutable version that changes optional informational routes/templates/preferences only; SecurityOperator holding that permission may change security templates, support-queue roster, and critical selectors. The command includes expected active version, complete normalized route/template/selector content, `activation_mode=immediate`, and no client-supplied effective or expiry time. Validate that both baseline channels and every warning/critical trigger, severity, Required Permission, and non-broadened field visibility remain present. A valid command atomically assigns commit-time effectiveness, activates, and supersedes under the Policy Artifact contract and emits `NotificationPolicyActivated`; stale, incomplete, future-effective, expiring, route-removing, channel-removing, visibility-broadening, or unauthorized content changes nothing and emits one denial audit event.
- Alternate Path: One channel succeeds while another retries or terminally fails; the logical Notification becomes partial only after a required Delivery reaches terminal failure. No unapproved third or “delayed” channel is used.
- Failure Path: Policy or authorization loss suppresses before dispatch. Missing current verified address follows `recipient_address_unavailable` without a provider call. The exact non-`429` `4xx` synchronous mapping or authenticated permanent provider event terminates that Delivery immediately; retryable exhaustion after four total attempts terminates it. Every terminally failed required Delivery and every mandatory empty-selector union creates exactly one support escalation within 5 minutes.
- Recovery Path: SecurityOperator support session holding `notification.replay` may submit a reasoned replay, which creates a linked new generation. The new generation resolves the route against the then-active policy and current authorized selector union; it does not reuse the old recipient snapshot. Thus repaired roster/authorization may recover an empty-union failure, while removed recipients receive nothing. Prior recipients, attempts, and aggregate history remain immutable.
- State Transitions: Delivery.Pending -> Attempting, TerminalFailed with `recipient_address_unavailable`, or Suppressed; Attempting -> Accepted, Delivered, RetryScheduled, TerminalFailed, or Suppressed; RetryScheduled -> Attempting, Accepted, Delivered, TerminalFailed, or Suppressed; Accepted -> Delivered or TerminalFailed; Delivered -> TerminalFailed only on an authenticated permanent Mailgun failure. A RetryScheduled transition caused by a prior-attempt event atomically cancels its timer. TerminalFailed and Suppressed are absorbing. Notification.Pending -> Sent, Partial, Failed, or Suppressed; Pending -> Failed with `no_authorized_recipient` is valid for a mandatory empty selector union; a later permanent Mailgun result recomputes the exact aggregate and may move Sent -> Partial or Failed or Partial -> Failed, but no other aggregate regression is valid.
- Domain Events: NotificationPolicyActivated, NotificationCreated, NotificationDeliveryAttempted, NotificationDeliveryAccepted, NotificationDelivered, NotificationRetryScheduled, NotificationDeliverySuppressed, NotificationDeliveryFailed, NotificationSent, NotificationPartial, NotificationFailed, NotificationSuppressed, NotificationEscalated, NotificationReplayRequested.
- Authorization: Notification service identity dispatches; OrganizationAdmin holding `policy.notification.manage` changes only optional informational routing/templates/preferences; SecurityOperator with the same scoped permission controls security templates, support-queue roster, and critical selectors without removing mandatory routes; replay requires approved support session and `notification.replay`.
- Security Notes: Sensitive payload redaction and recipient verification mandatory.
- Audit and Observability: Track triggering event, recipient-resolution and authorization decisions, redacted field codes, channel, attempt generation and number, exact scheduled and actual times, timeout, provider and adapter versions, provider message ID, provider-status mapping, reason code, aggregate outcome, escalation ID, and end-to-end latency.
- Acceptance Criteria: AC-WF-014

## WF-015 Enforce Entitlements

- Identifier: WF-015
- Purpose: Gate operations based on plan limits and entitlements.
- Actors: Tenant-scoped entitlement service identity; Billing Operator for approved policy activation
- Related Capabilities: CAP-024, CAP-025
- Trigger: A low-cost read is about to reach its durable response checkpoint, an immediate or queued high-cost operation is about to execute its first protected side effect, or a BillingOperator/billing-adapter submits an Entitlement Policy activation or approved plan-synchronization command. Queue creation alone does not trigger a Decision or reservation.
- Preconditions: For an enforcement request, the command envelope identifies Organization, exactly one human Account or tenant-scoped service identity, operation string, requested units, and idempotency key; inactive Organization/actor, unauthorized service, unknown operation, inactive entitlement, missing policy, and unavailable counter are evaluated into the exact immutable Block Decision rather than rejected as unmet workflow preconditions. Invalid tenant references, both/neither actor forms, malformed units, or malformed command envelope are request-schema rejections and create no Decision. A policy command instead requires expected current policy version and the exact policy-management authority below.
- Primary Path:
  1. Resolve and snapshot plan, entitlement, operation class, counter window, soft and hard limits, requested units, and actor scope.
  2. At that execution/response checkpoint, serialize against the counter window and atomically return the immutable Block, AllowWithWarning, or Allow Decision; a high-cost Allow/AllowWithWarning creates its reservation using the resolved prestart lifetime, while a low-cost Decision never reserves. A queued high-cost action has no earlier authoritative Decision to reuse.
  3. After high-cost execution, commit or release the reservation exactly once according to durable-output rules. At the low-cost durable response checkpoint, append or replay the exact LowCostUsageRecord before transport return.
- Policy Management Subflow: A BillingOperator holding `policy.entitlement.manage`, or the authorized billing adapter acting for an already approved plan, submits a complete immutable policy with expected current version, `activation_mode=immediate`, and no client-supplied effective or expiry time. Validate the exact baseline operation map, units, windows, soft/hard ordering, grace behavior, prestart lifetime, maximum execution, durable commit point, plan approval reference, and activation mode. A valid command atomically assigns commit-time effectiveness, activates the new version, supersedes the prior version, and emits `EntitlementPolicyActivated` at commit; a stale, future-effective, expiring, incomplete, commercially unapproved, broadened-beyond-global-safety, or unauthorized command changes nothing and emits one denial audit event. A tenant actor cannot invent a plan or alter system-governed operation classes.
- Alternate Path: Soft threshold allows with warning. Low-cost reads at hard threshold remain warning-only under the OD-006 interim policy and still create one usage record. The complete LowCostFallbackSnapshot is usable when `decision_time - snapshot_captured_at <= 24 hours`; equality is allowed and any greater age is expired. Policy reason wins when both dependencies are unavailable, and current/cached components are never mixed.
- Failure Path: High-cost hard threshold, inactive entitlement, missing or invalid policy/counter, stale reservation, unknown operation, or counter conflict blocks before side effect with exact reason. Cached low-cost fallback expiry returns `entitlement_unavailable`.
- Recovery Path: Upgrade or correct the plan, wait for a new usage window, release an executing reservation when the operation terminates, or restore the authoritative counter. Exact replay uses the same idempotency key and returns the original Decision/current Reservation state without a new attempt. A retry after Block, Released, or Expired uses a new key and `retry_of_decision_id`; replay or retry cannot consume usage twice.
- State Transitions: EntitlementDecision is immutable Allow, AllowWithWarning, or Block. Reservation.Reserved -> Executing, Released, or Expired; Executing -> Committed or Released. Committed, Released, and Expired are terminal. EntitlementPolicy follows the Policy Artifact draft/active/superseded/retired transitions.
- Domain Events: EntitlementPolicyActivated, EntitlementChecked, EntitlementWarningIssued, EntitlementViolationDetected, EntitlementReserved, EntitlementExecutionStarted, EntitlementLeaseRenewed, EntitlementCommitted, EntitlementReleased, EntitlementReservationExpired.
- Authorization: Server-side entitlement service identity only makes decisions. BillingOperator holding `policy.entitlement.manage` activates approved commercial policy; billing adapter may synchronize only the approved plan version. OrganizationAdmin has no entitlement-policy mutation permission and may only read allowed entitlement notices through `entitlement.notice.read`.
- Security Notes: No client-side trust for entitlement decisions.
- Audit and Observability: Persist every Entitlement Decision field, counter before/after values, recovery action, cached-snapshot ID/age, each LowCostUsageRecord and reconciliation state, idempotency and retry lineage, every reservation heartbeat/state, commit or release event, actor, and correlation ID.
- Acceptance Criteria: AC-WF-015

## WF-016 Export Reports And Data

- Identifier: WF-016
- Purpose: Generate and deliver authorized export packages.
- Actors: Organization Administrator, Marketing Operator, Technical Implementer, read-only Executive Buyer, authorized SecurityOperator investigation scope; Organization Administrator or Security Operator for narrower Export Policy activation
- Related Capabilities: CAP-022
- Trigger: Authorized create, retrieve, retry, or revoke command for an Export; the export lifecycle service reaches an available Export's persisted expiry; or an authorized Export Policy narrowing command.
- Preconditions: Creation requires exportable immutable artifacts from exactly one Organization, `export.create`, recipient equal to the active requesting Account, exact field/redaction scope, an allowed reserved high-cost Entitlement Decision, and active `export-interim-v1` or narrower Export Policy. A high-risk Export additionally requires the exact distinct approval defined by that contract. Other human actions require the existing Export, expected state version, and their exact permission. Timed expiry requires `export.expire` service authority and the persisted expiry instant, not a human command.
- Primary Path:
  1. Freeze the authorized logical format, exact one-Organization object/field scope, redaction result, artifact versions, requester-as-recipient, policy, approval when required, and request hash in a pending Export.
  2. Transition to generating, create the encrypted package asynchronously, decode and validate every selected logical object/field plus each `export-interim-v1` manifest, digest, and size invariant, and commit or release entitlement once.
  3. On success, transition to available and issue an authorized retrieval option expiring at the active policy lifetime, exactly 24 hours after availability in baseline.
  4. Retrieval reauthorizes `export.retrieve`, the requester-as-recipient, Account/Organization, Export state, manifest scope, current field permissions, and the then-active Export Policy before returning bytes. Current permission or policy narrower than the frozen manifest denies the whole package with `export_scope_no_longer_authorized`; missing/invalid policy denies with `policy_unavailable`. At or after the effective retrieval expiry, the lifecycle-service expiry checkpoint wins, returns `export_expired`, and emits no bytes. Revoke invalidates retrieval immediately.
- Policy Management Subflow: OrganizationAdmin holding `policy.export.manage` may activate an immutable Organization policy that only removes formats/fields, lowers sizes, or shortens lifetime. SecurityOperator with that permission may additionally narrow restricted/security export scope. Expected current version, `activation_mode=immediate`, and omission of client-supplied effective/expiry times are mandatory; the transaction assigns commit-time effectiveness and null expiry. A broader, stale, future-effective, expiring, incomplete, or unauthorized policy changes nothing. Activation enqueues idempotent expiry reevaluation for every available Export in scope, while retrieval independently applies the new policy immediately so queue delay cannot expose bytes.
- Alternate Path: Read-only Executive Buyer receives summary-only scope; restricted or disallowed fields are omitted according to the score visibility contract and listed in the manifest. WF-018 creates separate approved Export requests and packages for each Organization; it never combines them.
- Failure Path: Authorization, approval, policy, entitlement, cross-Organization, or recipient mismatch denial creates no Export. Unsupported logical format, generation, decoded-object, extra-field, size, digest, scope, or manifest failure transitions generating to failed, publishes no retrieval option, releases usage, and retains exact reason/correlation metadata.
- Recovery Path: An actor holding `export.retry` corrects scope or policy, obtains a new entitlement reservation and, for high-risk content, a new single-use approval, then submits a linked retry command moving failed to pending. Exact replay returns the original generation result and never creates another package or consumption.
- State Transitions: Export.Pending -> Export.Generating -> Export.Available or Export.Failed; Export.Available -> Export.Expired or Export.Revoked; Export.Failed -> Export.Pending only through an authorized linked retry.
- Domain Events: ExportPolicyActivated, ExportRequested, ExportGenerating, ExportAvailable, ExportFailed, ExportExpired, ExportRevoked, ExportRetrieved.
- Authorization: Creation requires `export.create`; retrieval requires `export.retrieve` by the requester-as-recipient; retry requires `export.retry`; revoke requires `export.revoke`; timed or policy-shortened expiry requires the export lifecycle service's `export.expire`. MarketingOperator and TechnicalImplementer may retry or revoke only an Export they requested; read-only Executive Buyer may create/retrieve summary-only output and cannot retry/revoke. A SecurityOperator requester remains confined to current investigation scope; each create or retry generation attempt requires a new approval from a different qualified SecurityOperator, while retrieve and revoke require no generation approval and independently reauthorize. The export service executes only the frozen authorized scope.
- Security Notes: Retrieval reauthorizes Organization, recipient, Export state, current Account, current field scope, and current Export Policy; package content never exceeds the frozen manifest; access is denied at the earlier of frozen expiry or the then-active shorter policy lifetime, with equality owned by expiry.
- Audit and Observability: Track requester/recipient, format, frozen scope and redacted-field codes, policy/artifact versions, entitlement reservation, every manifest field/digest/size, generation/retry state, retrieval authorization and time, expiration/revocation, and correlation ID.
- Acceptance Criteria: AC-WF-016

## WF-017 Handle Incident And Recovery

- Identifier: WF-017
- Purpose: Detect and respond to operational incidents affecting workflows.
- Actors: Security Operator; approved time-bounded SecurityOperator support session
- Related Capabilities: CAP-008, CAP-013, CAP-021, CAP-023
- Trigger: A versioned alert emits an incident candidate, or a SecurityOperator holding `incident.respond` declares one with a 20-2,000 character reason.
- Preconditions: Trigger contains correlation ID, observed condition, affected workflow/resource scope, first-observed time, and source telemetry reference.
- Incident Contract: Incident contains ID, Organization scope or explicit platform-wide scope, affected resources/workflows, severity (`critical`, `high`, `medium`, or `low`), severity reason code, detected/declared times, declaring identity, commander, active playbook ID/version, status, state version, mitigation and restoration-check records, closure actor/approver, and correlation ID. Critical means confirmed/suspected cross-Organization disclosure, credential compromise, irreversible integrity loss, or complete platform-wide protected-workflow outage; high means one or more Organizations cannot complete a protected workflow or integrity is at risk without confirmed loss; medium means partial/degraded protected workflow with a safe workaround; low means no current protected-workflow or customer-data impact. When multiple predicates match, strongest severity wins.
- High-Risk Remediation Approval Contract: Each high-risk playbook step attempt requires a distinct immutable approval containing `approval_id`, Incident and Organization, playbook and step versions, target type and ID, requested action, expected target state version, canonical command request hash, requester and approver Accounts, `approved_at_utc`, `expires_at_utc=approved_at_utc+1 hour`, nullable `used_by_step_attempt_id`, and approval state version. The approver MUST be a different active SecurityOperator holding protected `security.investigation.approve`. The complete step command and atomic step-start/approval-consumption transaction must commit strictly before expiry; at exact expiry the approval-expiry check wins. Step start atomically sets `used_by_step_attempt_id`; changed hash/version/scope, self-approval, reuse, or expired approval performs no side effect. Each retry or different high-risk action requires a new approval. Exact replay returns the original step attempt and cannot consume the approval or execute the step twice. This approval does not replace any required Support Session, affected-Organization customer approval, or emergency predicate.
- Primary Path:
  1. Idempotently create or correlate one Incident, freeze the triggering Evidence set, compute severity, and assign an authorized commander.
  2. Resolve an active immutable playbook whose declared applicability includes the severity and affected workflow. Each step names exact permission, precondition, expected state/version, reversible action or explicit irreversibility, checkpoint, rollback, and restoration assertion.
  3. Execute only authorized named steps, recording input/output hashes and rechecking session/permission at each checkpoint. A temporary mitigation moves Open to Mitigated only when its declared assertion passes.
  4. Verify every playbook restoration assertion immediately and again 5 elapsed minutes later. Only two passes permit Mitigated to Resolved; critical/high resolution additionally requires a different SecurityOperator holding `security.investigation.approve`.
- Alternate Path: Diagnostic collection may continue when no playbook applies, but privileged mutation is blocked with `recovery_playbook_unavailable`. A fallback is allowed only when it is a named branch in the active playbook.
- Failure Path: A denied, stale, failed, or unverifiable recovery step leaves Incident Open or Mitigated, records the exact failed step/reason/rollback result, and emits `IncidentRecoveryFailed`; it never marks restoration complete.
- Recovery Path: Correct authorization or inputs, activate an approved applicable playbook version, execute its declared rollback/fallback, or submit a new idempotent step attempt. Critical/high failure creates exactly one operational escalation record for the current failed-step generation.
- State Transitions: Incident.Open -> Incident.Mitigated -> Incident.Resolved.
- Domain Events: IncidentRaised, IncidentSeverityAssigned, IncidentRecoveryStepStarted, IncidentRecoveryStepCompleted, IncidentRecoveryFailed, IncidentMitigated, IncidentRestorationVerified, IncidentResolved.
- Authorization: SecurityOperator holding `incident.respond`; a Support Session is permitted only within approved incident scope. Workflow services execute only named playbook steps. Cross-Organization read, restricted-Evidence export, credential revoke/rotation, Account security lifecycle action, destructive data action, or security-policy change is high-risk and requires the exact single-use High-Risk Remediation Approval before each step attempt.
- Security Notes: No implicit break-glass path exists; emergency access still follows the Support Session emergency predicate and dual control.
- Audit and Observability: Record every contract field, trigger/telemetry hash, severity predicate, playbook/step/version, authorization and approval, expected/actual state, rollback, both restoration observations, timeline, event, and denied attempt.
- Acceptance Criteria: AC-WF-017

## WF-018 Investigate And Audit Security Or Compliance Events

- Identifier: WF-018
- Purpose: Support forensic investigation and compliance evidence production.
- Actors: Security Operator; approved per-Organization Support Sessions for cross-Organization collection; different SecurityOperator approval holder for closure or high-risk export
- Related Capabilities: CAP-023
- Trigger: Authorized SecurityOperator submits a security anomaly, compliance inquiry, or formal audit request with Organization/resource scope and 20-2,000 character reason.
- Preconditions: Actor holds `security.investigate`; request names the required telemetry/Evidence source set, time interval, legal purpose, classification ceiling, and expected Investigation state version when existing. A one-Organization request is confined to that permission scope. A request spanning Organizations additionally supplies one active Support Session per affected Organization; each session names the requester, `security.investigate`, every required source/resource, and the affected Organization, and has the exact customer approval or critical-emergency bypass plus distinct SecurityOperator approval required by the Support Session contract. Missing, expired, or mismatched session makes the cross-Organization request invalid.
- Investigation Contract: Investigation contains ID, one Organization or an approved cross-Organization Organization set, frozen Support Session IDs when cross-Organization, request/actor/legal purpose, frozen time interval and required source set per Organization, status/state version, collected Evidence Item IDs, gap records, completeness (`complete`, `partial`, or `insufficient`), report version/digest, proposed actions, closure approver, and correlation ID. Each Evidence Item stores immutable source reference, collection query hash, collected-by/time, content digest, classification, custody transfers, and access log. `complete` means every required source yielded validated records; `partial` means at least one but not all did; `insufficient` means none did.
- Primary Path:
  1. Freeze the authorized query plan and collect each required source with digest and chain-of-custody metadata; every query rechecks Organization, interval, classification, incident scope, and the affected Organization's frozen Support Session when cross-Organization. Session expiry or revocation before a query denies that query and creates its explicit gap; it never permits another Organization's session to substitute.
  2. Order records by occurred time then event ID, link correlation/causation, and create a gap for each missing, expired, denied, or integrity-invalid source without synthesizing an event.
  3. Produce an immutable versioned report containing scope, completeness, ordered timeline, Evidence Item list/digests, explicit gaps, conclusions separated from facts, and proposed actions.
  4. Transition Reported to Closed only after a different SecurityOperator holding `security.investigation.approve` verifies report digest, gaps, proposed actions, and access trail.
- Alternate Path: Partial or insufficient Evidence still produces a Reported outcome with the exact completeness value and gap reasons; it cannot claim a complete reconstruction.
- Failure Path: Invalid scope, missing/mismatched cross-Organization Support Session, unauthorized query, digest/custody failure, stale state, or missing required report field changes no Investigation state and records a denial/integrity outcome. A session that expires after Investigation creation denies subsequent affected-Organization queries and produces explicit gaps, so a report may become partial or insufficient but no out-of-session read occurs.
- Recovery Path: Correct the request, restore an authorized source, or append newly collected Evidence in a new report version. Prior report versions and gaps never mutate. Remediation executes through WF-017 or another named workflow, not directly from the report.
- State Transitions: Investigation.Open -> Investigation.Reported -> Investigation.Closed.
- Domain Events: SecurityInvestigationOpened, InvestigationEvidenceCollected, InvestigationGapRecorded, SecurityInvestigationReported, SecurityInvestigationClosed.
- Authorization: SecurityOperator holding Organization-scoped `security.investigate`; cross-Organization collection additionally requires the complete per-Organization Support Session set above, and no standing role or one session grants access to another Organization. Final closure always requires a different holder of `security.investigation.approve`. Every SecurityOperator investigation Export is high-risk and follows the distinct single-use approval plus WF-016 permissions, manifest, redaction, and lifecycle. An approved cross-Organization Investigation creates one separately approved Organization-scoped Export per Organization; a combined multi-Organization package is always rejected.
- Security Notes: Preserve chain-of-custody and evidentiary integrity.
- Audit and Observability: Persist the request/query hashes, source-by-source outcomes, every Evidence Item/custody/access record, ordering inputs, gap, completeness derivation, report versions/digests, distinct approval, linked remediation, and Export IDs.
- Acceptance Criteria: AC-WF-018

## Dependencies

- [INDEX.md](INDEX.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [ACCEPTANCE_AND_TEST_MAPPING.md](ACCEPTANCE_AND_TEST_MAPPING.md)
- [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md)
- [../016 STATE_MODEL.md](../016%20STATE_MODEL.md)
- [../017 ERROR_MODEL.md](../017%20ERROR_MODEL.md)
- [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md)

## Change Control

Any normative workflow change MUST:

1. preserve identifier stability
2. update related capabilities and product rules
3. update acceptance criteria mappings
4. update traceability rows and owner decision references where applicable
