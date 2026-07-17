# Volume II Frontend Architecture

## Status And Authority

- Status: Volume II Implementation Architecture Pass 001
- Behavioural baseline: immutable tag `v1.3-volume-i-corrected`
- Rendering model: Rails server-rendered HTML with Hotwire
- JavaScript model: Turbo and Stimulus through Importmap; no client application store

This document defines the implementation-facing screen, navigation and browser-state architecture. It inherits the [Volume I capabilities](../volume-i/CAPABILITY_MODEL.md), [Volume I workflows](../volume-i/WORKFLOW_SPECIFICATIONS.md), [APPLICATION_LAYER.md](APPLICATION_LAYER.md), and [SECURITY_PERFORMANCE.md](SECURITY_PERFORMANCE.md). It does not add a capability, actor, field or action.

## Technology Contract

The baseline uses Rails views, ViewComponent-free partial composition, Propshaft, Importmap, `turbo-rails`, and `stimulus-rails` at the exact versions pinned by the Rails architecture. There is no React, Vue, client router, GraphQL client, Node production runtime, JavaScript bundler, browser database or service worker.

Turbo Drive is enabled for every same-origin HTML navigation except:

- identity-provider navigation that deliberately leaves the F1 origin;
- an Export binary response;
- a browser download whose response is not HTML;
- a diagnostic endpoint expressly marked noninteractive.

Turbo Frames partition authorized page reads. Turbo Streams carry committed HTML replacement only in the initiating HTTP response. Stimulus supplies ephemeral interaction behavior only. The accepted baseline has no Action Cable, WebSocket, server-sent-event, background polling or asynchronous push channel.

## Server And Browser State Ownership

| State | Sole owner | Browser representation |
| --- | --- | --- |
| Domain lifecycle, score, Issue, Evidence, recommendation, policy, entitlement, permission and current projection | Server | Authorized rendered DTO only |
| Current Organization | Session-bound Account context | Not selectable across Organizations; Organization ID is not browser authority |
| Current Project | URL | `project_id` path segment validated and authorized on every request |
| Collection filters, stable sort, cursor and page direction | URL query | Canonical query string; shareable only to another independently authorized actor |
| Historical comparison pair and optional rebase target versions | URL/form command | Exact snapshot/version identifiers; server validates compatibility and authority |
| Form command identity | Server-rendered form | Hidden command ID, idempotency key, expected state/epoch and governing versions |
| Disclosure, tab focus, menu open state, copy confirmation | Stimulus | Element-local values; never authority or durable product state |
| Subsequent projection freshness | Server request | Navigation, form response or explicit user refresh fetches the current authorized version; a rendered page is not mutated in the background |

`localStorage`, `sessionStorage`, IndexedDB, cookies other than the platform Session, receipt-entry and CSRF mechanics, and JavaScript globals MUST NOT store domain records, permissions, unredacted DTOs, secrets, identity receipts, Export retrieval authority or pending product decisions.

## Screen And Route Inventory

These are the complete baseline HTML screen families. The route is physical presentation structure, not a new logical API contract.

### Unauthenticated and identity screens

| Screen ID | Route shape | Controller responsibility | Volume I behavior |
| --- | --- | --- | --- |
| `WEB-001` | `/start/sign-in` | initiate managed-identity validation and accept only allowlisted logical return target | CAP-001 existing-account sign-in |
| `WEB-002` | `/start/bootstrap-grant` | request/replay Bootstrap Grant using a fresh purpose-bound receipt | WF-001 grant request |
| `WEB-003` | `/start/bootstrap-organization` | render and submit Organization plus first-Project body | WF-001 self-service branch |
| `WEB-004` | `/invitations/:opaque_reference` | display authorized Invitation response and submit accept/decline | WF-001/WF-013 recipient path |
| `WEB-005` | `/app/access-unavailable` | display deterministic no-effective-access result | WF-001 logical destination |

The optional existing-sign-in return target is the exact case-sensitive enum `organization_home`, `new_project`, or `entitlement_notices`; every other onboarding purpose requires it to be null. `organization_home` maps to the shell at `/app`; `new_project` maps to `/app/projects/new` only after current `project.create`; `entitlement_notices` maps to `/app/entitlement-notices` only after current `entitlement.notice.read`. No baseline return target carries a resource ID. A raw path, URL, host, query string or fragment is never accepted. Unknown, malformed, nonexistent or unauthorized input maps to Organization Home, while an `access_unavailable` sign-in result overrides every requested target.

### Authenticated Organization and Project screens

| Screen ID | Route shape | Primary query | Required action for navigation visibility |
| --- | --- | --- | --- |
| `WEB-010` | `/app` | `QRY-001 OrganizationHome` | logical destination shell only; no unnamed Organization/Project/notice disclosure |
| `WEB-011` | `/app/projects` | `QRY-002 ProjectCollection` | blocked pending exact Project read authority; create control separately requires `project.create` |
| `WEB-012` | `/app/projects/new` | command form metadata | `project.create` |
| `WEB-013` | `/app/projects/:project_id` | `QRY-003 ProjectOverview` | field actions are defined; response remains blocked pending exact WF-015 low-cost operation/unit mapping |
| `WEB-014` | `/app/projects/:project_id/sources` | `QRY-004 SourceCollection` | blocked pending exact Source read authority |
| `WEB-015` | `/app/projects/:project_id/sources/:id` | `QRY-005 SourceDetail` | blocked pending exact Source read authority |
| `WEB-016` | `/app/projects/:project_id/crawls` | `QRY-022 CrawlCollection` | blocked pending exact Crawl/Project read authority |
| `WEB-017` | `/app/projects/:project_id/crawls/:id` | `QRY-023 CrawlDetail` | blocked pending exact Crawl/Project read authority |
| `WEB-018` | `/app/projects/:project_id/evaluations` | `QRY-006 EvaluationCollection` | read fields and WF-015 operation mapping both remain upstream-blocked |
| `WEB-019` | `/app/projects/:project_id/evaluations/:id` | `QRY-007 EvaluationDetail` | field actions are defined; response remains blocked pending exact WF-015 operation mapping |
| `WEB-020` | `/app/projects/:project_id/history` | `QRY-008 HistoryComparison` and `QRY-025 HistoryCollection` | blocked by low-cost metering; comparison also blocked by event semantics |
| `WEB-021` | `/app/projects/:project_id/issues` | `QRY-009 IssueCollection` | blocked by low-cost metering |
| `WEB-022` | `/app/projects/:project_id/issues/:id` | `QRY-010 IssueDetail` | blocked by low-cost metering; field access remains separate |
| `WEB-023` | `/app/projects/:project_id/recommendations` | `QRY-011 RecommendationCollection` | blocked by low-cost metering |
| `WEB-024` | `/app/projects/:project_id/recommendations/:id` | `QRY-012 RecommendationDetail` | blocked by low-cost metering; field access remains separate |
| `WEB-025` | `/app/projects/:project_id/action-queue` | `QRY-013 ActionQueue` | blocked by low-cost metering |
| `WEB-026` | `/app/notifications` | `QRY-014 NotificationCollection` | blocked pending exact Notification-inbox read authority |
| `WEB-027` | `/app/exports` | `QRY-015 ExportCollection` | blocked pending exact Export-enumeration read authority |
| `WEB-028` | `/app/exports/:id` | `QRY-016 ExportDetail` | blocked pending exact Export-detail read authority; retrieval command result remains available |

`WEB-013` and `WEB-020` contain deterministic structured data only. They MUST NOT contain a heading, blank panel, skeleton, presenter branch, hidden DOM node, data attribute, Stimulus target, provider request or feature flag for dashboard/history AI narrative. Deterministic labels, templates and existing score/Issue/Evidence/recommendation explanations remain unchanged.

### Administration and security screens

| Screen ID | Route shape | Primary query | Scope |
| --- | --- | --- | --- |
| `WEB-030` | `/app/administration/access` | `QRY-017 AccessAdministration` | broad collection blocked pending read authority; exact command-result scope only |
| `WEB-031` | `/app/administration/notifications` | notification-policy subset of `QRY-017`/`QRY-014` | blocked for policy/inbox reads; `policy.notification.manage` authorizes mutation only |
| `WEB-032` | `/app/entitlement-notices` | `QRY-018 EntitlementNoticeCollection` | `entitlement.notice.read` fields only; no BillingEntity, Plan or payment/provider fields |
| `WEB-034` | `/app/administration/commercial` | `QRY-035 CommercialSummary` | blocked pending exact commercial-summary read authority |
| `WEB-033` | `/app/administration/lifecycle` | `QRY-019 LifecycleAdministration` | broad collection blocked; exact command/audit result scope only |
| `WEB-040` | `/app/security/support-sessions` | `QRY-029 SupportSessionCollection` | blocked pending exact Support-Session collection read authority |
| `WEB-041` | `/app/security/incidents` and `/app/security/incidents/:id` | `QRY-030 IncidentCollection` / `QRY-031 IncidentDetail` | blocked pending exact Incident read authority |
| `WEB-042` | `/app/security/investigations/:id` | `QRY-032 InvestigationDetail` | blocked pending exact detail-response authority; named workflow input collection remains separately scoped |
| `WEB-043` | `/app/security/legal-holds` | `QRY-033 LegalHoldCollection` | blocked pending exact Legal-Hold collection read authority |
| `WEB-044` | `/app/security/deletion-jobs` | `QRY-034 DeletionJobCollection` | blocked pending exact deletion-job collection read authority |

Security screens never create a bypass. Hidden navigation and disabled controls are usability only; every direct request reauthenticates and reauthorizes.

## Navigation Architecture

Every authenticated page uses one server-rendered shell:

1. skip link;
2. Organization identity and read-only Account/Session status; no standalone sign-out/revoke control exists pending upstream clarification;
3. Project selector populated only from authorized `QRY-002` results;
4. primary Project navigation;
5. conditional Administration/Security navigation;
6. page breadcrumb and heading;
7. flash/status live region;
8. main workspace.

The Project navigation order is Overview, Sources, Crawls, Evaluations, History, Issues, Recommendations, Action Queue and Exports. Blocked collection destinations are omitted until their upstream read authority is resolved. Read-only Account/Session status is Organization-level; the Notification-inbox destination is omitted while its read contract is blocked. Administration and Security groups appear only when their landing query is authorized.

Volume I defines no standalone current-user sign-out/Session-revocation command and no Project pause, resume or archive command contract. The frontend MUST NOT render those controls, infer permissions for them, or submit such operations. They remain `UPSTREAM-V1-SESSION-REVOCATION-002` and `UPSTREAM-V1-PROJECT-LIFECYCLE-003` in [APPLICATION_LAYER.md](APPLICATION_LAYER.md#upstream-blockers-and-ambiguities).

Manual reassessment and reassessment-schedule controls MUST NOT render while `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` leaves the mandatory trigger-event occurrence and affected record undefined. A hidden form, direct Turbo submission or background-created schedule MUST NOT bypass that gate.

No Document quarantine or retirement control, status-changing link or inferred retention action renders because OD-015 removes the `quarantined` and `retired` Document states and their events; no such control exists to render. Reserved state labels may appear only in retained historical data after a future controlled correction, never as an enabled baseline action.

No presenter may fabricate a second Issue, collision status, partial Issue Set, score, Recommendation or history result for an Evaluation gated by `UPSTREAM-V1-ISSUE-COLLISION-013`. Existing accepted history remains renderable under its independent read gates, but the blocked collision branch produces no customer-visible placeholder, inferred failure, stale-current promotion or fallback result.

Organization-home data, Project/Source/Crawl/Evaluation collections, Notification inbox, Export collection/detail, Integration status, Support-Session collection, Incident/Investigation/Legal-Hold views and broad administration collections whose read authority is absent from Volume I MUST NOT render using a mutation permission, recipient binding, requester status, ownership or Role-name inference. They remain deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; the home logical destination may render only its shell. Exact Evidence, entitlement-notice, command-result and Export-retrieval scopes remain available; the otherwise named score, Issue, history and Recommendation reads are separately disabled until the low-cost response contract is corrected.

Every screen or Frame mapped or potentially mapped to `report.view`, `history.view`, `issue.read`, `recommendation.read` or `score.read` MUST NOT be made reachable by selecting a convenient operation or by counting a full page and its Frames ad hoc. They remain deferred under `UPSTREAM-V1-LOW-COST-METERING-005`, including apparently single-purpose History, Issue, Recommendation and Current Score responses. Historical comparison is additionally deferred under `UPSTREAM-V1-COMPARISON-EVENT-007`.

Navigation visibility MUST be computed from the same current authorization facade used by the target request, but it never substitutes for target authorization. A stale visible link may produce an authorized denial; a hidden link does not prove denial. No navigation payload contains a cross-Organization ID.

## Page And Frame Structure

A full page renders the shell and exactly one primary `main` element. Frames use stable IDs derived from public screen region names, never raw user content:

| Frame ID | Purpose | Refresh source |
| --- | --- | --- |
| `project_summary` | current score/status/coverage structured summary | `QRY-003` |
| `project_issue_summary` | current Issue counts and authorized links | `QRY-003` |
| `project_action_summary` | current action-queue subset | `QRY-003` |
| `source_collection` | paginated Sources | `QRY-004` |
| `crawl_collection` | paginated Crawl summaries | `QRY-022` |
| `evaluation_collection` | paginated run history | `QRY-006` |
| `history_comparison` | selected structured comparison | `QRY-008` |
| `issue_collection` | filtered/paginated Issues | `QRY-009` |
| `recommendation_collection` | filtered/paginated Artifacts | `QRY-011` |
| `action_queue` | ordered current queue | `QRY-013` |
| `notification_collection` | blocked Notification-inbox collection | `QRY-014` |
| `export_collection` | current actor-visible Exports | `QRY-015` |

A Frame endpoint materializes one registered AuthorizedDTO. It MUST NOT compose a second frame by making an internal HTTP request. A Frame response cannot broaden the full-page DTO and has the same authorization/redaction rules as direct navigation.

For a WF-015 low-cost query, no HTML or Turbo response is renderable until `Workflows::Wf015::LowCostRead` has committed the Decision and, when allowed, the unique usage record. Browser retry, Frame lazy loading and full-page composition MUST NOT create an unstated charging boundary. The physical replay identity and composite `report.view` unit remain blocked as stated above.

No frame is lazy-loaded merely to conceal a slow unbounded query. Lazy loading is allowed for a below-the-fold registered query only when its loading state and terminal unavailable/error state are defined and accessible.

## Turbo Mutation Contract

All mutations submit ordinary same-origin Rails forms to command controllers. Controllers construct one registered command and invoke its workflow handler.

- Transport, never a controller's judgment about the command, selects success rendering. Every receipt-entry form under `/start` or `/invitations` sets `data-turbo="false"`, submits with `Accept: text/html`, and on success receives `303 See Other` to the exact authorized logical destination. Every Session-bound `/app` form is Turbo-enabled: when Turbo is present it submits with `Accept: text/vnd.turbo-stream.html` and every nonbyte success returns `200` with the committed CommandResult form replacement; it never redirects. The no-JavaScript fallback for that same form submits `Accept: text/html` and receives `303` to its authenticated named success GET route. No form/controller may choose a different mode per outcome.
- Schema/field validation returns `422 Unprocessable Content` and the same form with deterministic field errors.
- Authentication failure returns `401`; the full-page handler offers managed reauthentication and does not echo protected form values.
- Authorization denial returns `403` with the stable support reference and no protected partial.
- Stale state/idempotency conflict returns `409` with current safe state metadata and a fresh-form action.
- Rate/capacity/dependency results retain their registered physical mapping and `Retry-After` only when Volume I supplies an exact retry instant.

A Turbo Stream response MUST be created from the committed CommandResult. It cannot be emitted from an Active Record callback or before commit. Failure renders no optimistic success fragment.

## Form Architecture

Each mutation screen uses one form object matching one physical command schema. The form renders:

- a server-created `command_id` and idempotency key;
- target type/ID and Project context as noneditable displayed context where applicable; route segments and the authenticated `form_binding`, not submitted hidden target/Project fields, are authority;
- expected state version and Organization authorization epoch where required;
- only an expected parent/version/candidate reference expressly admitted by the selected `ATTR-*` schema; resolved current governing policy versions remain server-derived and are never submitted;
- one CSRF token;
- only fields admitted by the command schema.

On a pre-command form decode/schema `422`, the same command/idempotency identity remains because no semantic command was accepted. A committed `F1-USER-400` or `F1-VALIDATION-400` result is also rendered physically as `422`, but that identity is terminal and the corrected form receives a new command ID/idempotency key. Every other committed result and a deliberate start-over likewise uses a new identity. A double-submit Stimulus controller may disable the button and show progress, but server idempotency remains the only correctness control.

Every invalid form renders an error-summary heading, links to each invalid control, `aria-invalid=true`, and an associated error description. Focus moves to the summary after a Turbo replacement. A stale `409` never silently overwrites current values; it presents a reread-and-resubmit action with a new idempotency key.

Destructive or high-risk actions use a dedicated confirmation form showing the exact target, scope and required reason/acknowledgment. A browser confirmation dialog alone is insufficient.

## Asynchronous Completion And Page Freshness

An asynchronous workflow renders its committed pending/current state in the initiating response. Later worker completion does not push, broadcast, poll or mutate that page. The next authorized navigation, explicit user refresh or separately initiated form/query request loads the current state and projection version from the server. No baseline route creates an Action Cable subscription, WebSocket, server-sent-event stream, refresh timer, background fetch loop or domain-event-driven UI invalidation.

This is a fixed implementation choice, not a degraded mode: queue/cache/provider availability cannot turn push on, and the absence of an asynchronous message is not an error or incomplete response. Synchronous command responses may still use Turbo Streams generated from their committed CommandResult. Adding asynchronous UI invalidation requires an explicit Volume II revision and controlled Volume I change if it alters promised user-visible timing or behavior.

## Stimulus Contract

Allowed Stimulus responsibilities are menu/disclosure behavior, focus management, form double-submit presentation, clipboard copy of already authorized rendered text, progressive filter submission, and upload progress where an approved flow exists.

Stimulus MUST NOT:

- calculate a score, comparison, priority, eligibility or state transition;
- decide a permission, classification or redaction;
- construct a provider prompt or call a provider;
- alter command identity/governing versions after render;
- retain a domain object after navigation;
- infer success before a committed server result;
- create dashboard/history narrative or placeholder content.

## Loading, Empty, Partial And Error States

Every registered frame has exactly five presentation states derived from its DTO:

- **loading**: transient request indicator with the existing accessible region label;
- **content**: query succeeded and returned its complete authorized nonempty structured DTO;
- **empty**: query succeeded and returned an authorized zero-item collection;
- **partial**: Volume I explicitly permits a partial structured result and supplies complete reason codes;
- **unavailable/error**: query failed or projection is unavailable with the registered outward reason and support reference.

An authorization denial is not an empty collection. A redacted field is omitted or represented by the canonical redaction code, never substituted with fabricated content. Missing AI narrative is ordinary successful baseline output and enters none of these exceptional states.

## Accessibility And Responsive Rules

All screens MUST satisfy WCAG 2.2 AA verification under the existing quality gate. Baseline implementation requirements are:

- semantic landmarks and heading order;
- complete keyboard operation and visible focus;
- server-rendered labels/instructions for every control;
- accessible names for icon-only controls;
- status changes announced through one `aria-live=polite` region, with urgent security/session loss using `assertive` only where required;
- focus restoration after Frame/Stream replacement;
- data visualizations paired with the same authorized structured table and text values;
- no color-only status or trend distinction;
- reduced-motion preference disables nonessential transition animation;
- 200% zoom and 320 CSS-pixel viewport without loss of action or horizontal page scrolling, except an individually scrollable labelled data table.

At narrow widths the primary navigation becomes an accessible disclosure and tables use labelled horizontal containers or definition-list presentation. Responsive transformation MUST NOT omit fields or actions that are otherwise authorized.

## Browser Caching And Sensitive Presentation

Protected HTML, Turbo and JSON responses use `Cache-Control: private, no-store`; browser history may retain the rendered page only as the user agent's transient UI and MUST revalidate on restoration. Static fingerprinted assets use public immutable caching. Export bytes use the headers in [SECURITY_PERFORMANCE.md](SECURITY_PERFORMANCE.md) and are never placed in the Turbo cache.

The Turbo cache is cleared when a response observes Session expiry/revocation or Account/Organization suspension/closure. No standalone sign-out behavior is inferred. Forms containing identity, security, Evidence or Export scope fields opt out of Turbo preview.

## Frontend Verification

System and component tests MUST cover:

- every screen's query/permission mapping and direct-route denial;
- navigation as convenience rather than authority;
- Turbo success, validation, stale-state, authentication and authorization responses;
- form idempotency across double submit and `422` rerender;
- absence of Action Cable/WebSocket/SSE/background-polling routes and current-state retrieval on navigation or explicit refresh;
- zero SQL in presenters and no lazy DTO field access;
- keyboard, focus, error summary, live-region and automated accessibility checks;
- responsive behavior at the required viewport/zoom;
- absence of CAP-018/WF-012 narrative DOM, Stimulus targets, provider calls and feature paths.
