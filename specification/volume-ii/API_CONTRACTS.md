# Volume II Physical API And Event Contracts

## Status And Authority

- Status: Volume II Implementation Architecture Pass 001
- Behavioural baseline: immutable tag `v1.3-volume-i-corrected`
- Logical authority: [Volume I Workflow Specifications](../volume-i/WORKFLOW_SPECIFICATIONS.md)
- Application command/query authority: [Application Layer](APPLICATION_LAYER.md)
- Integration ingress authority: [Integration Contracts](INTEGRATION_CONTRACTS.md)

This document chooses physical HTTP, JSON, pagination, authentication, authorization and event serialization. It does not create a public developer API, customer API credentials, customer event subscriptions or a webhook capability.

## API Surface And Routing

The Rails router exposes five disjoint surfaces:

| Surface | Prefix | Authentication | Purpose |
| --- | --- | --- | --- |
| Browser HTML/Turbo | `/app`, `/start`, `/invitations` | F1 Session cookie, except receipt-bound entry | Server-rendered product UI |
| Managed-identity return | `/auth` | short-lived provider state followed by one-time Identity Validation Receipt | Begin and consume managed-identity authentication only; never an F1 Session-authorized product surface |
| First-party JSON | `/api/v1` | Same F1 Session cookie plus CSRF; receipt-bound exceptions below | JSON used by approved first-party clients and tests |
| Machine ingress | `/service/v1` | Approved Service JWT Boundary; Session cookies ignored | Narrow service-only commands admitted by Volume I |
| Provider ingress | `/webhooks/<provider>/v1` | Provider-specific signature; Session/JWT ignored | Active provider callbacks only |

Routes not catalogued here return `404` before command construction. CORS is disabled: no cross-origin browser origin receives an allow header. The API has no OAuth scope, personal token, API-key issuance or arbitrary webhook-registration route.

## HTTP And Serialization Baseline

- HTTPS is mandatory. The application rejects a non-forwarded-HTTPS production request with `400`; the edge redirects safe browser `GET`/`HEAD` to HTTPS and never redirects a mutation.
- JSON command/query request and response media type is `application/vnd.f1+json; version=1`. Browser HTML/Turbo and form twins use their exact HTML/form media types below; the managed-identity return alone accepts cross-site form-urlencoded; the Mailgun webhook alone accepts plain `application/json` and returns `text/plain`.
- JSON member names are `snake_case`. Unknown members are rejected unless the selected schema marks them forward-compatible.
- UUID values are lowercase canonical hyphenated strings. Instants are RFC 3339 UTC with exactly six fractional digits and `Z`.
- Counts are JSON integers. Exact decimals, scores, weights and money/cost quantities are base-10 JSON strings; exponent form is prohibited.
- Required nullable members are present with `null`. Optional members are absent, never silently emitted as null.
- Unicode strings must be valid scalar UTF-8 and are normalized to NFC before hashing. The server rejects duplicate JSON object keys, invalid UTF-8, nonfinite numbers and a body over the route limit.
- Default request-body limit is 1 MiB. External Measurement submission is 10 MiB. The Mailgun webhook body limit is 256 KiB. Export retrieval uses the standard command body with an empty `attributes` object.
- Compression is accepted for responses with `Accept-Encoding: br` or `gzip`; request-body compression is rejected.

Every response includes `X-Request-ID` and `X-Correlation-ID`. Every authenticated response includes `Cache-Control: private, no-store`; immutable public compiled assets are the only CDN-cacheable responses.

## Physical Authentication

### Managed identity entry

`GET /auth/start` accepts exactly `purpose`, nullable `organization_id`, nullable `invitation_reference`, and nullable `return_target`. Allowed purposes are `bootstrap_grant_request`, `self_service_bootstrap`, `invitation_response` and `existing_account_sign_in`. `return_target` must be null for the first three purposes and, for `existing_account_sign_in`, is case-sensitive enum `organization_home`, `new_project` or `entitlement_notices`. `organization_home` maps to the shell at `/app`; `new_project` maps only to `/app/projects/new` after current `project.create` authorization; `entitlement_notices` maps only to `/app/entitlement-notices` after current `entitlement.notice.read` authorization. An absent/malformed/unknown target, or a target that fails current authorization, maps to `/app` without failing authentication. The `access_unavailable` outcome wins over every requested target and maps to `/app/access-unavailable`. No baseline target contains a resource ID, raw path, URL, host, query or fragment. `invitation_reference` is nonnull only for `invitation_response` and has the exact opaque-reference contract below; `organization_id` is required for `existing_account_sign_in` and otherwise follows the selected Volume I branch. Every other parameter combination returns the generic invalid-entry page and creates no logical command.

The route starts the managed-identity flow defined in [Integration Contracts](INTEGRATION_CONTRACTS.md). The sole return route is cross-site `POST /auth/callback` with `Content-Type: application/x-www-form-urlencoded` and a 32 KiB body limit. Its decoded body is exactly `state` plus either `receipt` or the closed `error` member; duplicate keys, every other member and every other method or media type are rejected before receipt construction. The callback consumes the one-time identity-service response, creates one restricted server-side Identity Validation Receipt, removes provider parameters from the browser URL, and redirects with `303` to the corresponding receipt-bound form. Identity assertions, authorization codes and receipt plaintext never appear in application URLs after that redirect. Exact state/receipt/error validation, replay behavior and outward failure precedence are delegated without alteration to [Integration Contracts](INTEGRATION_CONTRACTS.md).

`InvitationOpaqueReference` is the one Volume I Invitation identity exposed in a URL or authorized response. Creation draws exactly 32 bytes from the operating-system CSPRNG and encodes them as canonical RFC 4648 base64url without padding: exactly 43 ASCII characters matching `[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]`. The database lookup key and every diagnostic/log value are lowercase SHA-256 over the decoded 32 bytes; the raw reference is stored only in the protected Invitation secret field needed for authorized redelivery and is never an internal public UUID alias. Every tenant-admin `:opaque_reference` and recipient `:opaque_reference` route uses this same constraint. A structurally invalid reference and a valid reference that is unknown, cross-Organization, terminal or identity-mismatched produce the same generic `invitation_not_active` response under the selected receipt/Session disclosure boundary. Rails and edge access logs record only the route template plus digest/redacted `inv_<first-12-digest-hex>`; they never record the raw path segment or the email-link query value. The direct email link uses `/auth/start?purpose=invitation_response&invitation_reference=<InvitationOpaqueReference>`, and every later receipt-bound form action uses that exact reference unchanged.

### F1 Session transport

The exact cookie and CSRF contract is defined in [Security And Performance](SECURITY_PERFORMANCE.md). A valid Session identifies actor and Organization; clients cannot submit `actor_id`, `service_identity_id` or a different Organization. A Session is never accepted on `/service/v1` or `/webhooks`.

### Service identity transport

`/service/v1` requires `Authorization: Bearer <JWT>` under the exact ES256 claims, key artifact, 120-second lifetime, replay binding and failure contract in [Integration Contracts](INTEGRATION_CONTRACTS.md#approved-service-jwt-boundary). The verified subject resolves one active `service_identities` row and cannot select a broader Organization, Project or permission than its signed scope.

## JSON Command Transport

### Headers

Every `/api/v1` or `/service/v1` state-changing JSON request requires:

| Header | Contract |
| --- | --- |
| `Idempotency-Key` | 16-128 ASCII characters matching `[A-Za-z0-9._~-]+`; stored only as a digest |
| `Content-Type` | `application/vnd.f1+json; version=1` |
| `Accept` | same media type or `*/*`; Export byte retrieval instead requires the stored Export media type or `*/*` |
| `If-Match` | required for an existing mutable target; exactly `"f1-state-<unsigned integer>"` |
| `X-CSRF-Token` | required on every cookie-authenticated unsafe method |
| `X-Correlation-ID` | optional UUID; server generates when absent; invalid values are rejected |

`If-Match` is prohibited for create commands without an existing target. Policy-activation routes are conditional creates: `If-Match` carries the current active Policy Artifact state version, while a permitted first activation requires `If-None-Match: *`; supplying neither or both is invalid. A service request additionally requires `X-F1-Command-ID` as UUIDv7 and `X-F1-Requested-At` as an RFC 3339 instant. The browser controller generates those two logical fields server-side before entering the command bus.

### Body

The physical command body is exactly:

```json
{
  "schema_version": "1.0",
  "attributes": {}
}
```

`attributes` is the route-selected command payload from the Application Layer registry. Organization, Project, target type/ID, action, actor/service, state version, idempotency identity, request time, correlation/causation IDs and governing policy versions are constructed from the authenticated request, route, headers and authoritative policy resolution. A client-supplied duplicate of one of those envelope fields is an unknown member and is rejected. For a human command `causation_id` equals `command_id`; event/timer/service reactions use the causing event or scheduled-action ID.

## Browser Command Twins

Every routable Session-bound human route in the Command Endpoint Catalogue has exactly one HTML form twin obtained by replacing the leading `/api/v1` with `/app` and retaining the remainder byte-for-byte. A mapping marked unavailable has neither JSON route nor browser twin. The four receipt-entry families are explicit: `/api/v1/bootstrap-grants` maps to `/start/bootstrap-grants`, `/api/v1/organizations` to `/start/organizations`, `/api/v1/sessions` to `/start/sessions`, and the two `/api/v1/invitations/by-reference/:opaque_reference/<decision>` routes to `/invitations/:opaque_reference/<decision>`. Service-only and provider routes have no browser twin. No `/commands`, discriminator-selected or other generic mutation endpoint exists.

A browser twin accepts only same-origin `application/x-www-form-urlencoded` and always arrives physically as `POST`. For a JSON `DELETE` route, the form has exactly `_method=delete`; `_method` is absent for a JSON `POST` route and every other value is rejected. Route recognition, `form_binding` verification and CSRF verification use the effective logical method after this exact method override: a `POST` carrying `_method=delete` is bound and checked as `DELETE`, never as `POST`. Multipart forms, JSON at `/app`, Session commands at `/start` or `/invitations`, and receipt credentials in a form body are rejected before command construction.

The decoded form has exactly these transport members:

- `authenticity_token`, verified against the current Session or receipt-entry CSRF binding and the effective logical method after the permitted `_method=delete` override;
- `schema_version=1.0`;
- server-created hidden `command_id` as UUIDv7 and `idempotency_key` satisfying the JSON header grammar;
- server-created hidden `form_binding`, an authenticated, purpose-bound token over command route, effective logical method after the permitted `_method=delete` override, command ID, idempotency key, Session-or-receipt binding digest, Organization/Project/target route values, selected attributes schema, conditional mode, expected state version when present, named success GET route and absolute expiry; expiry is the earliest of 30 minutes, Session expiry and receipt-entry expiry;
- `attributes_present=1`; and
- the selected attributes under bracket paths beginning `attributes[...]`.

An existing mutable target additionally requires hidden `expected_state_version` as an unsigned integer equal to the value in `form_binding`. A policy activation additionally requires `conditional_mode=state_match` with `expected_state_version`, or `conditional_mode=first_activation` with no `expected_state_version`; every other form omits `conditional_mode`. These values adapt to the same `If-Match`/`If-None-Match` command precondition and are never command attributes. Where the selected `ATTR-*` schema contains `expected_authorization_epoch`, that leaf is also server-created hidden input covered by `form_binding`, not an editable control. Missing, altered, expired or cross-route binding, unknown top-level member, duplicate decoded key, or a binding/state mismatch is a `422` form rejection and constructs no command.

The schema adapter is deterministic:

- each exact JSON object member maps to the same bracketed path; nested objects add one bracket segment;
- arrays use contiguous zero-based numeric segments; an exact empty array is represented by the sole child `_empty=true`; unindexed repeated fields, gaps, mixed `_empty` and items, or duplicate indices are invalid;
- an exact empty attributes object is `attributes[_empty]=true`; `_empty` is an adapter sentinel and never enters JSON;
- UUID, instant, hash, enum, ASCII and text scalars use their decoded UTF-8 string; a nullable scalar's empty string maps to JSON null, while empty nonnullable text is validated by its schema;
- `uint` is parsed to a JSON integer, `bool` accepts only `true` or `false`, and exact decimals remain JSON strings; and
- an optional member is absent only when its complete path is absent. Unknown paths are rejected, and the resulting object is validated against the same route-selected `ATTR-*` schema before command construction.

The browser response is selected only by transport, never by command outcome guesswork. For a nonbyte command whose request accepts `text/vnd.turbo-stream.html`, success returns `200 text/vnd.turbo-stream.html` and replaces exactly `command-form-<command_id>` with the committed, currently authorized CommandResult presentation; no callback or precommit stream is allowed. A normal `text/html` success returns `303 See Other` to the named success GET route authenticated inside `form_binding`, after reauthorizing it; if that route is no longer authorized, the location is `/app`. An onboarding result's exact logical destination overrides the form route and is mapped to its named physical GET route. Raw or submitted redirect URLs are never accepted.

Form decode/schema errors before command construction return `422 Unprocessable Content` with the same form identity and deterministic field errors, as HTML or a replacement Turbo Stream according to `Accept`; correction may reuse that identity because no result exists. A committed `F1-USER-400` or `F1-VALIDATION-400` result also renders physically as `422`, but the failed identity remains bound to its retained result and any corrected submission uses a newly issued command ID/idempotency key. Other committed failures retain the fixed `401`, `403`, `409`, `422`, `429`, `503` or `504` status from their logical tuple, render no success fragment and never redirect; any corrected new attempt uses a newly rendered identity. A stale-state `409` presents a reread action, and only that new GET may issue current expected state plus fresh identity. CSRF/authentication/parser failure before safe command construction is a transport error and has no retained command result.

The `BeginExportRetrieval` twin is the sole byte exception: its form is rendered with Turbo disabled, its successful `200` response streams the fixed stored media type with the Export filename and command-result headers below, and the adapter derives that media type rather than trusting browser `Accept`. Any failure emits zero Export bytes and renders the authorized HTML error using the fixed logical status. It never returns a Turbo Stream or `303` after a successful retrieval.

## Terminal Command Results And Responses

Every command returns one committed logical result. `201` means the requested primary effect is a newly committed resource; a separately specified notification, delivery, indexing or projection follow-up does not change it to `202`. `202` is used only where the route catalogue says the requested product effect itself remains pending after the committed command result. Every other success uses `200`. The route catalogue, not controller convention, is the status authority. An allowed exact replay reuses the stored terminal outcome and identifiers but first applies current reauthorization and redaction, may expose a more restrictive payload than the first response, adds `Idempotency-Replayed: true`, and renders `replayed=true`; it never promises a byte-identical original body/status across changed authorization. Current denial returns a newly audited physical view of `F1-AUTH-403` with no stored result payload or target identifiers and does not mutate or replace the stored command result. No `202` represents an unclaimed or incomplete command result.

Success body:

```json
{
  "schema_version": "1.0",
  "data": {
    "type": "command_result",
    "id": "00000000-0000-0000-0000-000000000000",
    "attributes": {
      "outcome": "success",
      "result_schema_version": "1.0",
      "command_type": "...",
      "command_schema_version": "1.0",
      "command_id": "...",
      "idempotency_identity_hash": "...",
      "organization_id": "...",
      "project_id": null,
      "actor_id": "...",
      "service_identity_id": null,
      "correlation_id": "...",
      "causation_id": "...",
      "completed_at_utc": "2026-01-01T00:00:00.000000Z",
      "target_references": [],
      "resulting_state_version": null,
      "governing_policy_versions": [],
      "result_payload": {},
      "audit_outcome_id": "...",
      "replayed": false
    }
  },
  "meta": {"correlation_id": "..."}
}
```

On success, `error_class`, `error_code`, `reason_code`, `severity`, `retryable`, `recovery_action`, and `support_reference` are absent. `target_references` is an array of exact `{ "type": "...", "id": "<uuid>" }` objects sorted by type then ID. `governing_policy_versions` is an array of exact `{ "artifact_type": "...", "artifact_id": "<uuid>", "version": "...", "content_sha256": "..." }` objects sorted by artifact type then ID/version. No member is conditionally repurposed.

Failure uses the same outer form with `data.type=command_result`, no unauthorized target data, and this exact attributes shape:

```json
{
  "outcome": "failure",
  "result_schema_version": "1.0",
  "command_type": "...",
  "command_schema_version": "1.0",
  "command_id": "...",
  "idempotency_identity_hash": "...",
  "organization_id": "...",
  "project_id": null,
  "actor_id": "...",
  "service_identity_id": null,
  "correlation_id": "...",
  "causation_id": "...",
  "completed_at_utc": "2026-01-01T00:00:00.000000Z",
  "governing_policy_versions": [],
  "result_payload": {},
  "error_class": "authorization",
  "error_code": "F1-AUTH-403",
  "reason_code": "...",
  "severity": "warning",
  "retryable": false,
  "recovery_action": "obtain_required_authority_or_use_authorized_actor",
  "support_reference": "...",
  "audit_outcome_id": "...",
  "replayed": false
}
```

Exactly one of `actor_id` and `service_identity_id` is nonnull. `organization_id` is null only for the expressly permitted pre-Organization bootstrap result; `project_id` is nonnull exactly for Project-scoped commands. A failure omits `target_references` and `resulting_state_version`; `result_payload` contains only schema-authorized failure fields and is `{}` when none exist. `support_reference` equals `correlation_id`. A transport/parser rejection that cannot safely construct a logical command uses the same error tuple and correlation metadata but `data.type=transport_error`, has no command/result/idempotency/actor/tenant fields, and cannot be replayed; it is never mislabeled a committed command result.

### Closed result-payload registry

`result_payload` is not an extension bag. The following named objects are recursively closed and are the exhaustive success registry:

| Schema | Exact members |
| --- | --- |
| `RESULT-EMPTY` | Exact `{}`. |
| `RESULT-BOOTSTRAP-GRANT` | Exactly `grant_expires_at_utc: instant`. The Grant ID and state version are the envelope target/resulting version. |
| `RESULT-SELF-SERVICE` | Exactly `resource_state_versions: array<object<ResultResourceState>>[9..9]` containing one each of `organization`, `account`, `billing_entity`, `role_assignment`, `access_policy`, `entitlement_policy`, `plan_assignment`, `project`, and `session`, sorted by type. |
| `RESULT-INVITATION-ACCEPTED` | Exactly `resource_state_versions: array<object<ResultResourceState>>[5..5]` containing one each of `organization`, `account`, `role_assignment`, `invitation`, and `session`, sorted by type. |
| `RESULT-SIGN-IN` | Exactly `resource_state_versions: array<object<ResultResourceState>>[2..2]` containing one `account` and one `session`, sorted by type, plus `logical_destination: object<LogicalDestination>`. |

`ResultResourceState` is discriminated by `type`. For `invitation` it is exactly `type: enum{invitation}`, `id: InvitationOpaqueReference` and `state_version: uint`; every other form is exactly `type: enum{organization,account,billing_entity,role_assignment,access_policy,entitlement_policy,plan_assignment,project,session,bootstrap_grant}`, `id: uuid` and `state_version: uint`. An Invitation reference is returned only to its intended recipient or a currently authorized Invitation administrator. Every entry must equal one same-type/identity envelope `target_references` entry; no extra or missing target is permitted for these schemas. `LogicalDestination` is exactly `kind: enum{organization_home,access_unavailable,authorized_return_target}` and `route_name: nullable enum{organization_home,new_project,entitlement_notices}`. `organization_home` requires the same route name, `access_unavailable` requires null, and `authorized_return_target` requires `new_project` or `entitlement_notices` after the authorization rule above. No resource-bearing destination exists in major 1.

Success selection is exhaustive: `RequestBootstrapGrant` uses `RESULT-BOOTSTRAP-GRANT`; `BootstrapOrganization` uses `RESULT-SELF-SERVICE`; `AcceptInvitation` uses `RESULT-INVITATION-ACCEPTED`; and `SignInExistingAccount` uses `RESULT-SIGN-IN`. Every other command discriminator in the closed Command Endpoint Catalogue, including every route-qualified decision and `BeginExportRetrieval`'s stored logical result, uses `RESULT-EMPTY`. A future command is invalid until this registry explicitly selects its schema.

Failure selection is also exhaustive. `reason_code=stale_state_version` uses exactly `{ "current_state_version": <uint> }` after the actor has been reauthorized for that already-known target. Every other command failure and reason uses exact `{}`. Error tuple, recovery action, policy versions and support reference remain their envelope fields and MUST NOT be duplicated in `result_payload`; partial target, provider response, internal exception and diagnostic fields are forbidden.

HTTP mapping is fixed:

| Logical code | HTTP status |
| --- | ---: |
| `F1-USER-400`, `F1-VALIDATION-400` | 400 |
| `F1-AUTHN-401` | 401 |
| `F1-AUTH-403` | 403 |
| `F1-DOMAIN-409`, `F1-DATA-409` | 409 |
| `F1-AI-422`, `F1-RETRIEVAL-422`, `F1-CITATION-422`, `F1-INGESTION-422`, `F1-PARSING-422`, `F1-INDEXING-422` | 422 |
| `F1-RATELIMIT-429`, `F1-CAPACITY-429` | 429 |
| `F1-DEPENDENCY-503` | 503 |
| `F1-TIMEOUT-504` | 504 |

`401` clears a terminal/invalid Session cookie. `429` includes `Retry-After` only when the logical result names an exact retry instant. `503` and `504` are not automatically retried by browsers, controllers or reverse proxies.

## Command Endpoint Catalogue

The command name is the Application Layer command discriminator. `State` means `If-Match` is required. `Idempotency-Key` is required on every routable command row without exception. Any Result cell marked unavailable is a reserved mapping only: the router exposes no JSON, browser-twin or service route and returns transport `404` until the named controlled Volume I blocker is corrected.

### Identity, tenant and access

| Method and route | Command | Permission/binding | State | Result |
| --- | --- | --- | --- | --- |
| `POST /api/v1/bootstrap-grants` | `RequestBootstrapGrant` | receipt-bound principal | no | 201 |
| `POST /api/v1/organizations` | `BootstrapOrganization` | receipt plus Bootstrap Grant | no | 201 |
| `POST /api/v1/sessions` | `SignInExistingAccount` | existing-sign-in receipt and exact Organization | no | 201 |
| `POST /api/v1/organizations/:organization_id/invitations` | `CreateInvitation` | `invitation.create` | no | 201 |
| `POST /api/v1/organizations/:organization_id/invitations/:opaque_reference/approval` | `DecideInvitation` | `invitation.approve`; decision fixed by route to `approve` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/invitations/:opaque_reference/rejection` | `DecideInvitation` | `invitation.approve`; decision fixed by route to `reject`; required distinct decision actor | yes | 200 |
| `DELETE /api/v1/organizations/:organization_id/invitations/:opaque_reference` | `RevokeInvitation` | `invitation.revoke` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/invitations/:opaque_reference/reissues` | `ReissueInvitation` | `invitation.create` | yes | 201 |
| `POST /api/v1/invitations/by-reference/:opaque_reference/acceptance` | `AcceptInvitation` | invitation-response receipt | yes | 201 |
| `POST /api/v1/invitations/by-reference/:opaque_reference/decline` | `DeclineInvitation` | invitation-response receipt | yes | 200 |
| `POST /api/v1/organizations/:organization_id/role-assignments` | `RequestRoleAssignment` | `role.manage` | no | 201 |
| `POST /api/v1/organizations/:organization_id/role-assignments/:id/approval` | `DecideRoleAssignment` | protected `role.manage`; decision fixed by route to `approve` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/role-assignments/:id/rejection` | `DecideRoleAssignment` | protected `role.manage`; decision fixed by route to `reject` | yes | 200 |
| `DELETE /api/v1/organizations/:organization_id/role-assignments/:id` | `RevokeRoleAssignment` | `role.manage` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/access-policies` | `ActivateAccessPolicy` | `policy.access.manage` | policy conditional | 201 |
| `POST /api/v1/organizations/:organization_id/accounts/:id/suspension` | `SuspendAccount` | `account.suspend` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/accounts/:id/revocation` | `RevokeAccount` | `account.revoke` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/accounts/:id/deletion-jobs` | `DeleteAccount` | `account.delete` | yes | 202 |
| `POST /api/v1/organizations/:organization_id/suspension` | `SuspendOrganization` | `organization.suspend` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/closure-requests` | `RequestOrganizationClosure` | `organization.close` | no | 201 |
| `POST /api/v1/organizations/:organization_id/closure-requests/:id/approval` | `DecideOrganizationClosure` | protected approval; decision fixed by route to `approve` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/closure-requests/:id/rejection` | `DecideOrganizationClosure` | protected approval; decision fixed by route to `reject` | yes | 200 |

### Projects, Sources and intake

| Method and route | Command | Permission/binding | State | Result |
| --- | --- | --- | --- | --- |
| `POST /api/v1/organizations/:organization_id/projects` | `CreateProject` | `project.create` | no | 201 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/activation` | `ActivateProject` | `project.activate` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/sources` | `RegisterSource` | `source.register` | no | 201 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/sources/:id/verification-requests` | `IssueVerificationChallenge` | `source.verify` | yes | 201 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/verification-requests/:id/observations` | `ReserveVerificationAttempt` | `source.verify` | yes | 202 |
| `DELETE /api/v1/organizations/:organization_id/projects/:project_id/verification-requests/:id` | `CancelVerificationRequest` | `source.verify` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/sources/:id/activation` | `ActivateSource` | `source.lifecycle.manage` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/sources/:id/disablement` | `DisableSource` | `source.lifecycle.manage` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/sources/:id/reactivation` | `ReactivateSource` | `source.lifecycle.manage` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/sources/:id/removal` | `RemoveSource` | `source.lifecycle.manage` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/sources/:id/scope-change-requests` | `RequestSourceScopeChange` | `source.scope.propose` | no | 201 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/source-scope-change-requests/:id/approval` | `ApproveSourceScopeChange` | `policy.source_scope.manage` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/source-scope-change-requests/:id/rejection` | `RejectSourceScopeChange` | `policy.source_scope.manage` | yes | 200 |
| `DELETE /api/v1/organizations/:organization_id/projects/:project_id/source-scope-change-requests/:id` | `CancelSourceScopeChange` | requester or OrganizationAdmin | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/crawl-policies` | `ActivateCrawlPolicy` | `policy.crawl.manage` | policy conditional | 201 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/crawls` | `QueueCrawl` | `crawl.trigger` | no | 202 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/crawls/:id/cancellation` | `CancelCrawl` | `crawl.cancel` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/crawls/:id/recovery` | `RecoverCrawl` | `crawl.recover` | yes | 202 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/ingestion-jobs/:id/recovery` | `RequestIngestionReplay` | `ingestion.recover` | yes | 202 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/parsing-jobs/:id/recovery` | `ReplayPipelineStage` | `parsing.recover`; stage fixed by route to `parsing` | yes | 202 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/indexing-jobs/:id/recovery` | `ReplayPipelineStage` | `indexing.recover`; stage fixed by route to `indexing` | yes | 202 |

### Evaluation, score and recommendations

| Method and route | Command | Permission/binding | State | Result |
| --- | --- | --- | --- | --- |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/issues/:id/disputes` | `RequestAdjudication` | `issue.dispute` | yes | 201 |
| `DELETE /api/v1/organizations/:organization_id/projects/:project_id/issues/:id/dispute` | `WithdrawAdjudication` | `issue.dispute` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/issues/:id/adjudication-assignment` | `AssignAdjudication` | `issue.adjudicate`; assigning actor becomes adjudicator | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/issues/:id/adjudication-decision` | `DecideAdjudication` | assigned `issue.adjudicate` actor; explicit upheld/rejected value | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/evidences/:id/validation-decisions` | `ChangeEvidenceValidation` | `evidence.validation.manage` | yes | 201 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/reassessments` | `StartReassessment` | `reassessment.trigger` | no | deferred under `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`; 202 only after correction |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/evaluations/:evaluation_id/reassessment-cancellation` | `CancelReassessment` | `reassessment.cancel`; ID/state version bind the orchestration Evaluation | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/reassessment-schedules` | `ActivateReassessmentSchedule` | `reassessment.trigger` | policy conditional | deferred under `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`; 201 only after correction |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/score-rebases` | `RebaseHistoricalComparison` | `score.rebase` | no | 202 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/recommendations/:id/publication` | `PublishRecommendation` | `recommendation.publish` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/projects/:project_id/priority-overrides` | `OverridePriority` | `priority.override` | no | 201 |

### Delivery, policy, commercial and integrations

| Method and route | Command | Permission/binding | State | Result |
| --- | --- | --- | --- | --- |
| `POST /api/v1/organizations/:organization_id/notification-policies` | `ActivateNotificationPolicy` | `policy.notification.manage` | policy conditional | 201 |
| `POST /api/v1/organizations/:organization_id/notifications/:id/replays` | `ReplayDelivery` | `notification.replay` plus Support Session | yes | 202 |
| `POST /api/v1/organizations/:organization_id/export-policies` | `ActivateExportPolicy` | `policy.export.manage` | policy conditional | 201 |
| `POST /api/v1/organizations/:organization_id/export-approvals` | `RequestExportApproval` | high-risk requester; exact proposed generation selection | no | 201 |
| `POST /api/v1/organizations/:organization_id/export-approvals/:id/approval` | `DecideExportApproval` | distinct `security.investigation.approve`; decision fixed by route to `approve` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/export-approvals/:id/rejection` | `DecideExportApproval` | distinct `security.investigation.approve`; decision fixed by route to `reject` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/exports` | `CreateExport` | `export.create` | no | 202 |
| `POST /api/v1/organizations/:organization_id/exports/:id/retry` | `RetryExport` | `export.retry` | yes | 202 |
| `POST /api/v1/organizations/:organization_id/exports/:id/revocation` | `RevokeExport` | `export.revoke` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/exports/:id/retrievals` | `BeginExportRetrieval` | requester-as-recipient and `export.retrieve` | yes | 200 bytes or JSON error |
| `POST /api/v1/organizations/:organization_id/entitlement-policies` | `ActivateEntitlementPolicy` | `policy.entitlement.manage` | policy conditional | 201 |
| `POST /api/v1/organizations/:organization_id/integrations/:id/disconnection` | `DisconnectIntegration` | `integration.lifecycle.manage` plus Support Session | yes | 200 |
| `POST /api/v1/organizations/:organization_id/integrations/:id/recovery` | `RecoverIntegration` | `integration.lifecycle.manage` plus Support Session | yes | 200 |
| `POST /api/v1/organizations/:organization_id/integrations/:integration_id/credentials/:id/rotations` | `BeginCredentialRotation` | `credential.rotate` plus Support Session | yes | unavailable under `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`; 202 only after correction |
| `POST /api/v1/organizations/:organization_id/integrations/:integration_id/credentials/:id/revocation` | `RevokeCredential` | `credential.revoke` plus Support Session | yes | 200 |

### Security operations and lifecycle

Rows explicitly marked unavailable below are reserved mappings only: the router exposes no physical route and returns transport `404` until the named controlled Volume I blocker is corrected. Their attributes schemas remain retained architecture input and MUST NOT be used through another endpoint.

| Method and route | Command | Permission/binding | State | Result |
| --- | --- | --- | --- | --- |
| `POST /api/v1/organizations/:organization_id/support-sessions` | `RequestSupportSession` | `support.session.request` | no | 201 |
| `POST /api/v1/organizations/:organization_id/support-sessions/:id/approval` | `DecideSupportSession` | `support.session.approve`; decision fixed by route to `security_approve` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/support-sessions/:id/customer-approval` | `DecideSupportSession` | `support.session.customer_approve`; decision fixed by route to `customer_approve` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/support-sessions/:id/rejection` | `DecideSupportSession` | required approver; decision fixed by route to `reject` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/support-sessions/:id/revocation` | `RevokeSupportSession` | `support.session.revoke` | yes | 200 |
| `POST /api/v1/incidents` | `DeclareIncident` | `incident.respond` | no | 201 |
| `POST /api/v1/incidents/:id/step-attempts` | `RunIncidentStep` | `incident.respond`; baseline diagnostic step only | yes | 202 |
| `POST /api/v1/incidents/:id/resolution` | `ResolveIncident` | `incident.respond`; protected approval where required | yes | 200 |
| `POST /api/v1/investigations` | `OpenInvestigation` | `security.investigate` | no | unavailable under `UPSTREAM-V1-EVENT-SCOPE-001`; 202 once corrected |
| `POST /api/v1/investigations/:id/reports` | `PublishInvestigationReport` | `security.investigate` | yes | unavailable under `UPSTREAM-V1-EVENT-SCOPE-001`; 201 once corrected |
| `POST /api/v1/investigations/:id/closure` | `CloseInvestigation` | `security.investigation.approve` | yes | unavailable under `UPSTREAM-V1-EVENT-SCOPE-001`; 200 once corrected |
| `POST /api/v1/legal-holds` | `RequestLegalHold` | `legal_hold.manage` | no | 201 |
| `POST /api/v1/legal-holds/:id/approval` | `DecideLegalHold` | `legal_hold.manage`; distinct approver; decision fixed by route to `approve` | yes | 200 |
| `POST /api/v1/legal-holds/:id/rejection` | `DecideLegalHold` | `legal_hold.manage`; distinct approver; decision fixed by route to `reject` | yes | 200 |
| `POST /api/v1/legal-holds/:id/release-requests` | `RequestLegalHoldRelease` | `legal_hold.manage`; Support Session; exact Hold scope | yes | 201 |
| `POST /api/v1/legal-holds/:id/release-requests/:request_id/approval` | `DecideLegalHoldRelease` | distinct `legal_hold.manage` approver; decision fixed by route to `approve` | yes | 200 |
| `POST /api/v1/legal-holds/:id/release-requests/:request_id/rejection` | `DecideLegalHoldRelease` | distinct `legal_hold.manage` approver; decision fixed by route to `reject` | yes | 200 |
| `POST /api/v1/organizations/:organization_id/deletion-jobs/:id/retry` | `RetryDeletion` | `deletion.retry` | yes | 202 |

### Service-only commands

These rows are routable only through the Approved Service JWT Boundary; cookie Sessions are ignored.

| Method and route | Command | Service permission | Result |
| --- | --- | --- | --- |
| `POST /service/v1/external-measurements` | `SubmitMeasurementEvidence` | `external_measurement.submit` | 201 |
| `POST /service/v1/release-artifacts/:id/activation` | `ActivateReleaseArtifact` | exact artifact-specific release permission | 200 |
| `POST /service/v1/integrations/:id/retirement` | `RetireIntegration` | `integration.policy.activate` | 200 |

Timers and internal event reactions are not HTTP endpoints. They enter the same registered commands from Sidekiq with a verified service identity and a persisted ScheduledAction or Domain Event cause. The reserved `investigation_input_collect` ScheduledAction is consumed only by the `investigation_collect` control-queue job against its frozen per-Organization Support Session and bounded input pages; it has no `/service/v1` or other HTTP route.

## Command Attributes Schema Registry

This registry is closed-world. Each catalogue row selects `ATTR-<Command>` unless a route-qualified schema is listed below. Required members MUST be present and nonnull unless their type explicitly includes `null`; optional members may be absent but, when present, MUST be nonnull unless stated otherwise. Every member not listed for the selected schema is forbidden. A schema is never shared merely because two bodies happen to be empty or similar: every command discriminator and every route-fixed decision has a separately named schema.

The notation is exact: `uuid` is a lowercase canonical UUID; `uint` is a JSON integer from 0 through 9,223,372,036,854,775,807; `uint53` is a JSON integer from 0 through 9,007,199,254,740,991; `decimal` is a nonexponent base-10 JSON string matching `-?(0|[1-9][0-9]*)(\.[0-9]+)?`; `instant` is the UTC format above; `sha256` is 64 lowercase hexadecimal characters; `bool` is a JSON Boolean; `text[a..b]` counts trimmed Unicode scalar values after NFC normalization; `ascii[a..b]` counts ASCII bytes; `enum{...}` permits only the listed strings; `array<T>[a..b]` is a JSON array with the listed cardinality; `nullable T` means the member is required and its JSON value may be null or `T`; `*` means no narrower semantic maximum than the route body limit; `object<X>` is the exact named object below. Arrays marked `sorted-unique` are compared by canonical UTF-8 bytes and reject duplicates or noncanonical order.

The following fields are always derived and therefore forbidden inside `attributes`: Organization/tenant ID except where a route-less security schema expressly declares its scope Organization, Project ID except where `ReassessmentScheduleRules` binds the candidate to its route, route target type or ID, command/action name, actor or service identity, Session or Support Session ID, expected target state version, idempotency key/hash, command/result/correlation/causation IDs, request/authorization time, governing or resolved policy versions except an expressly declared expected parent/candidate reference, authorization epoch except where a command expressly requires an expected epoch, and server-created IDs/timestamps/digests. Identity Validation Receipt and Bootstrap Grant credentials are server-side receipt bindings; their plaintext, nonce, assertion, credential, MFA value, Session token and CSRF token are forbidden.

### Named exact objects

| Object | Exact members and constraints |
| --- | --- |
| `OrganizationProfile` | Exactly `organization_profile_schema_version: enum{organization-profile-v1}`, `display_name: text[1..120]`, `default_locale: enum{en-AU}`, `reporting_time_zone: enum{UTC}`. |
| `ProjectProfile` | Exactly `project_profile_schema_version: enum{project-profile-v1}`, `display_name: text[1..120]`, `default_locale: enum{en-AU}`, `reporting_time_zone: enum{UTC}`, `objective: enum{discoverability_assessment}`, `local_presence_applicable: bool`, `local_presence_reason: nullable text[20..500]`, and `local_business_profile: nullable object<LocalBusinessProfile>` with the WF-002 true/false dependency. |
| `LocalBusinessProfile` | Exactly `schema_version: enum{local-business-profile-v1}`, `business_name: text[1..120]`, `address_text: text[1..500]`, `telephone_e164: ascii[9..16]` matching `+[1-9][0-9]{7,14}`, and `service_areas: array<text[1..120]>[1..50] sorted-unique`. |
| `GrantScope` | Exactly `scope_kind: enum{organization,resources}`, `project_ids: array<uuid>[0..*] sorted-unique`, and `resources: array<object<ResourceRef>>[0..*] sorted-unique`; `organization` requires both arrays empty, while `resources` requires at least one combined member. |
| `ResourceRef` | Exactly `resource_type: ascii[1..120]` using a registered canonical type and `resource_id: uuid`. |
| `PolicyVersionRef` | Exactly `policy_type: enum{global_crawl_safety,organization_crawl}`, `policy_id: uuid`, `version: ascii[1..120]`, and `content_sha256: sha256`. It is an expected parent constraint, not a caller-selected governing result. |
| `AccessRoleTuple` | Exactly `role: enum{OrganizationAdmin,MarketingOperator,TechnicalImplementer,SecurityOperator,BillingOperator}`, `permission_mode: enum{standard,read_only}`, `persona: nullable enum{consultant,executive_buyer}`, and `classification_ceiling: enum{public,internal,confidential,restricted}`. The tuple must occur in the frozen Permission Baseline registry. |
| `AccessDeny` | Exactly `permission: ascii[1..120]` from the closed Permission Baseline action registry, `resource_type: ascii[1..120]` from the domain type registry, and `resource_id: nullable uuid`; null means the complete Organization scope for that permission. |
| `CrawlIntegerLimit` | Exactly `soft: uint` and `hard: uint`, both positive, with `soft <= hard`. |
| `CrawlDecimalLimit` | Exactly `soft: decimal` and `hard: decimal`, both positive nonexponent values with no more than four fractional digits and `soft <= hard`. |
| `NotificationTemplateSegment` | Discriminated union: literal is exactly `kind: enum{literal}`, `text: text[1..2000]`; field is exactly `kind: enum{field}`, `field_path: ascii[1..160]` from the selected `notification_context_v1` variant's field-path registry. No condition, loop, raw HTML or executable template expression exists. |
| `NotificationTemplate` | Exactly `template_key: ascii[1..120]`, `template_version: ascii[1..120]`, `event_type: ascii[1..120]` from the notification-eligible event registry, `channel: enum{in_app,email}`, `subject_segments: array<object<NotificationTemplateSegment>>[0..20]`, `body_segments: array<object<NotificationTemplateSegment>>[1..100]`, and `classification_ceiling: enum{public,internal,confidential,restricted}`. Email requires a nonempty subject; in-app requires an empty subject. |
| `NotificationTemplateRef` | Exactly `channel: enum{in_app,email}`, `template_key: ascii[1..120]`, and `template_version: ascii[1..120]`; it resolves to exactly one candidate template with the same event type/channel. |
| `NotificationRouteRule` | Exactly `route_key: ascii[1..120]`, `event_type: ascii[1..120]` from the notification-eligible event registry, `event_schema_major: enum{1}`, `trigger_predicate: ascii[1..120]` equal to that registry row's closed predicate, `context_variant: enum{invitation,source_verification,crawl,score,adjudication,entitlement,export,security_action,generic_informational}`, `severity: enum{informational,warning,critical}`, `required_permission: ascii[1..120]` from the Permission Baseline registry, `selector_components: array<enum{exact_invitation_recipient,invitation_requester,request_initiator,run_initiator,project_marketing_operators,organization_admins,adjudication_requester,security_support_queue,human_initiator,billing_operators,export_requester,authorized_security_operators,affected_organization_admins}>[1..*] sorted-unique`, `required_channels: array<enum{email,in_app}>[1..2] sorted-unique`, `templates: array<object<NotificationTemplateRef>>[1..2]`, `mandatory: bool`, `informational_email_opt_out_allowed: bool`, and `classification_ceiling: enum{public,internal,confidential,restricted}`. |
| `NotificationPreference` | Exactly `account_id: uuid`, `event_type: ascii[1..120]` from a nonmandatory informational route, and `email_enabled: bool`; in-app, warning, critical, and direct-Invitation email cannot be disabled. |
| `EntitlementOperationRule` | Exactly `operation_class: enum{high_cost,low_cost}`, `usage_unit: enum{crawl_run,reassessment_run,validated_ai_response,export_package,read_request}`, `counter_group_id: enum{crawl.start,reassessment.start,ai.generate,export.generate,baseline_reads}`, `window_kind: enum{utc_calendar_day}`, `requested_units: decimal`, `soft_limit: nullable decimal`, `hard_limit: decimal`, `grace_behavior: enum{block_above_hard_allow_warning_at_soft,allow_over_hard_with_warning}`, `reservation_lifetime_seconds: nullable uint`, `maximum_execution_seconds: nullable uint`, `request_timeout_governed: bool`, and `durable_commit_point: enum{crawl_completed_with_valid_document,reassessment_issue_set_and_score_promoted,validated_ai_response_persisted,export_available,authorized_response_and_usage_record_committed}`. Operation-specific equality constraints below are part of the schema. |
| `AccessPolicyRules` | Exactly `permission_profile_version: enum{permission-baseline-v1}`, `classification_profile_version: enum{score-visibility-v1}`, `protected_permission_profile_version: enum{protected-permissions-v1}`, `allowed_role_tuples: array<object<AccessRoleTuple>>[1..*] sorted-unique`, `scope: enum{organization}`, `denied_permissions: array<ascii[1..120]>[0..*] sorted-unique from the Permission Baseline action registry`, and `denied_resource_scopes: array<object<AccessDeny>>[0..*] sorted-unique`. The tuple array is byte-equivalent to the baseline registry; policy changes can add only denies and cannot express an allow. |
| `CrawlPolicyRules` | Exactly `parent_policy_refs: array<object<PolicyVersionRef>>[1..2] sorted-unique` and `limits`, where `limits` is exactly `accepted_pages_per_run`, `discovered_urls_per_run`, `crawl_depth_edges`, `accounted_response_body_bytes_per_run`, `response_body_bytes_per_url`, `wall_clock_seconds_per_run`, `redirects_per_url`, `concurrent_requests_per_host`, `request_timeout_seconds`, `sitemap_documents_per_run`, and `sitemap_index_depth_edges` as `object<CrawlIntegerLimit>`, plus `request_starts_per_host_per_second: object<CrawlDecimalLimit>`. Every pair is no broader than every named parent/global pair in the same fixed base unit. |
| `ReassessmentScheduleRules` | Exactly `project_id: uuid`, `enabled: bool`, and `cadence_seconds: nullable uint`; enabled requires a positive cadence, disabled requires null, and the first due instant must fit the Volume I upper time bound. |
| `NotificationPolicyRules` | Exactly `channels: array<enum{email,in_app}>[2..2] sorted-unique`, `routes: array<object<NotificationRouteRule>>[1..*] sorted-unique by route_key`, `templates: array<object<NotificationTemplate>>[1..*] sorted-unique by template key/version/channel`, `support_queue_account_ids: array<uuid>[0..*] sorted-unique`, and `preferences: array<object<NotificationPreference>>[0..*] sorted-unique by Account/event`. The frozen warning/critical rows, direct Invitation route, severities, permissions, selectors and both channels must remain byte-equivalent; only the Volume I-authorized informational/security changes validate. |
| `ExportPolicyRules` | Exactly `allowed_formats: array<enum{csv_data,json_data,pdf_report}>[1..3] sorted-unique`, `allowed_object_types: array<enum{evidence_metadata,issue,recommendation_artifact,score_contribution,score_snapshot}>[1..5] sorted-unique`, `allowed_fields: array<ascii[1..120]>[1..*] sorted-unique from the frozen Export field registry`, `max_encrypted_package_bytes: uint`, `max_total_uncompressed_bytes: uint`, and `available_lifetime_seconds: uint`. Values must be subsets or no larger than 104857600 bytes, 262144000 bytes, and 86400 seconds respectively; no public sharing, Evidence payload or multi-Organization switch exists. |
| `EntitlementPolicyRules` | Exactly `plan_version: ascii[1..120]` and `operation_rules`, whose object has exactly the nine keys `crawl.start`, `reassessment.start`, `ai.generate`, `export.generate`, `report.view`, `history.view`, `issue.read`, `recommendation.read`, and `score.read`, each one `object<EntitlementOperationRule>`. High-cost keys require class `high_cost`, their same-named counter group, nonnull reservation/max execution, `request_timeout_governed=false`, blocking grace and their exact durable point. Low-cost keys require class `low_cost`, `baseline_reads`, null reservation/max execution, `request_timeout_governed=true`, warning grace and the response/usage-record durable point. Units, global maxima, 1-15-minute reservation bound, soft-less-than-hard rule and null-soft 80-percent derivation are exactly those in Volume I. |
| `AccessPolicyCandidate` | Exactly `policy_schema_version: enum{access-policy-v1}`, `semantic_version: ascii[1..120]`, `activation_mode: enum{immediate}`, and `rules: object<AccessPolicyRules>`. |
| `CrawlPolicyCandidate` | Exactly `policy_schema_version: enum{crawl-policy-v1}`, `semantic_version: ascii[1..120]`, `activation_mode: enum{immediate}`, and `rules: object<CrawlPolicyRules>`. |
| `ReassessmentSchedulePolicyCandidate` | Exactly `policy_schema_version: enum{reassessment-schedule-v1}`, `semantic_version: ascii[1..120]`, `activation_mode: enum{immediate}`, and `rules: object<ReassessmentScheduleRules>`. |
| `NotificationPolicyCandidate` | Exactly `policy_schema_version: enum{notification-policy-v1}`, `semantic_version: ascii[1..120]`, `activation_mode: enum{immediate}`, and `rules: object<NotificationPolicyRules>`. |
| `ExportPolicyCandidate` | Exactly `policy_schema_version: enum{export-policy-v1}`, `semantic_version: ascii[1..120]`, `activation_mode: enum{immediate}`, and `rules: object<ExportPolicyRules>`. |
| `EntitlementPolicyCandidate` | Exactly `policy_schema_version: enum{entitlement-policy-v1}`, `semantic_version: ascii[1..120]`, `activation_mode: enum{immediate}`, and `rules: object<EntitlementPolicyRules>`. |
| `SourceScopeRules` | Exactly the source-scope contract: `canonical_host: ascii[1..253]`, `allowed_schemes: array<enum{https}>[1..1]`, `allowed_ports: array<uint>[1..*] sorted-unique`, `included_path_prefixes: array<text[1..*]>[1..*] sorted-unique`, `excluded_path_prefixes: array<text[1..*]>[0..*] sorted-unique`, `query_handling: enum{retain_all,retained_key_allowlist}`, and `retained_query_keys: array<text[1..*]>[0..*] sorted-unique`, with the WF-004 query-mode dependency. |
| `ExportSelection` | Exactly `logical_format: enum{pdf_report,csv_data,json_data}`, `objects: array<object<ResourceRef>>[1..*] sorted-unique`, `fields: array<ascii[1..120]>[1..*] sorted-unique`, and `redaction_codes: array<ascii[1..120]>[0..*] sorted-unique`; every value must occur in the active Export Policy allowlist. |
| `InvestigationInputSpec` | Exactly `organization_id: uuid`, `input_type: ascii[1..120]`, `resource_ids: array<uuid>[0..*] sorted-unique`, and `required: bool`. This nested Organization is semantic cross-Organization investigation scope, not the command envelope tenant. |
| `MeasurementPayload` | Exactly the ordered typed payload defined by the referenced active Measurement Set Artifact; no free-form or extra key is accepted. |

### Identity, tenant and access attributes

| Schema | Required attributes | Optional attributes | Route-fixed or conditional contract |
| --- | --- | --- | --- |
| `ATTR-RequestBootstrapGrant` | none | none | Exact empty object. |
| `ATTR-BootstrapOrganization` | `bootstrap_grant_id: uuid`; `bootstrap_grant_state_version: uint`; `organization_profile: object<OrganizationProfile>`; `first_project: object<ProjectProfile>` | none | Grant is a referenced precondition because it is not a route target; receipt principal is transport-bound. |
| `ATTR-SignInExistingAccount` | none | none | Exact Organization comes from the receipt-bound authentication state and route construction. |
| `ATTR-CreateInvitation` | `target_email: ascii[3..254]`; `intended_role: enum{OrganizationAdmin,MarketingOperator,TechnicalImplementer,SecurityOperator,BillingOperator}`; `permission_mode: enum{standard,read_only}`; `persona: nullable enum{consultant,executive_buyer}`; `scope: object<GrantScope>`; `protected_permissions: array<ascii[1..120]>[0..*] sorted-unique`; `intended_assignment_expires_at_utc: nullable instant` | `target_identity: object` | `target_identity`, when present, contains exactly `issuer_key: ascii[1..120]` and `subject: ascii[1..512]`; all tuple rules come from onboarding-interim-v1. |
| `ATTR-DecideInvitation-approval` | none | none | Route fixes `decision=approve`; reason is server-recorded null. |
| `ATTR-DecideInvitation-rejection` | none | `reason: text[1..*]` | Route fixes `decision=reject`; missing reason is stored as null. |
| `ATTR-RevokeInvitation` | `reason: text[20..2000]` | none | — |
| `ATTR-ReissueInvitation` | none | none | Offered tuple is copied from the route predecessor then reauthorized; alteration requires `CreateInvitation`. |
| `ATTR-AcceptInvitation` | none | `account_id: uuid` | Receipt supplies identity; optional Account ID is accepted only for the exact same-Organization matching identity Account. |
| `ATTR-DeclineInvitation` | none | `reason: text[1..2000]` | Missing reason is stored as null. |
| `ATTR-RequestRoleAssignment` | `account_id: uuid`; `role: enum{OrganizationAdmin,MarketingOperator,TechnicalImplementer,SecurityOperator,BillingOperator}`; `permission_mode: enum{standard,read_only}`; `persona: nullable enum{consultant,executive_buyer}`; `scope: object<GrantScope>`; `protected_permissions: array<ascii[1..120]>[0..*] sorted-unique`; `expires_at_utc: nullable instant`; `reason: text[1..*]` | none | — |
| `ATTR-DecideRoleAssignment-approval` | `reason: text[1..*]` | none | Route fixes `decision=approve`. |
| `ATTR-DecideRoleAssignment-rejection` | `reason: text[1..*]` | none | Route fixes `decision=reject`. |
| `ATTR-RevokeRoleAssignment` | `reason: text[1..*]` | none | — |
| `ATTR-ActivateAccessPolicy` | `candidate: object<AccessPolicyCandidate>` | none | Conditional header supplies current/absent state. |
| `ATTR-SuspendAccount` | `reason: text[20..2000]`; `expected_authorization_epoch: uint` | none | — |
| `ATTR-RevokeAccount` | `reason: text[1..*]`; `expected_authorization_epoch: uint` | none | — |
| `ATTR-DeleteAccount` | `reason: text[1..*]`; `expected_authorization_epoch: uint` | none | Deletion manifest and modes are server-derived from the frozen lifecycle contract. |
| `ATTR-SuspendOrganization` | `reason: text[20..2000]`; `expected_authorization_epoch: uint` | none | — |
| `ATTR-RequestOrganizationClosure` | `reason: text[20..2000]`; `expected_authorization_epoch: uint` | none | Retention/hold snapshots are server-derived at acceptance. |
| `ATTR-DecideOrganizationClosure-approval` | none | none | Route fixes `decision=approve`; decision reason is null. |
| `ATTR-DecideOrganizationClosure-rejection` | none | `reason: text[1..*]` | Route fixes `decision=reject`; missing decision reason is stored as null. |

### Project, Source and intake attributes

| Schema | Required attributes | Optional attributes | Route-fixed or conditional contract |
| --- | --- | --- | --- |
| `ATTR-CreateProject` | `profile: object<ProjectProfile>` | none | — |
| `ATTR-ActivateProject` | `source_membership_version: uint` | none | Project version is in `If-Match`. |
| `ATTR-RegisterSource` | `source_request_schema_version: enum{source-registration-v1}`; `submitted_root_uri: ascii[9..*]` | none | URI is constrained by the exact Source-registration grammar, not merely by length. |
| `ATTR-IssueVerificationChallenge` | `method: enum{dns_txt,http_file}` | none | Challenge/token/location/times are server-derived. |
| `ATTR-ReserveVerificationAttempt` | none | none | Route fixes on-demand origin; attempt identity is server-created in the reservation transaction. |
| `ATTR-CancelVerificationRequest` | none | none | Exact reason code is derived from requester-versus-OrganizationAdmin authority. |
| `ATTR-ActivateSource` | none | none | Only `verified -> active`; disabled Sources use `ReactivateSource`. |
| `ATTR-DisableSource` | none | none | — |
| `ATTR-ReactivateSource` | none | none | Only `disabled -> active`. |
| `ATTR-RemoveSource` | none | none | Only the Volume I valid removal transition. |
| `ATTR-RequestSourceScopeChange` | `proposed_rules: object<SourceScopeRules>`; `active_policy_state_version: uint`; `reason: text[20..2000]` | none | — |
| `ATTR-ApproveSourceScopeChange` | `active_policy_state_version: uint` | none | Route fixes approve; decision reason is null. |
| `ATTR-RejectSourceScopeChange` | `active_policy_state_version: uint`; `reason: text[20..2000]` | none | Route fixes reject. |
| `ATTR-CancelSourceScopeChange` | `reason: text[20..2000]` | none | — |
| `ATTR-ActivateCrawlPolicy` | `candidate: object<CrawlPolicyCandidate>` | none | Conditional header supplies current/absent state. |
| `ATTR-QueueCrawl` | none | none | Branch, active Source set and policy snapshots are resolved authoritatively; this route queues only a root initial Crawl. |
| `ATTR-CancelCrawl` | none | none | — |
| `ATTR-RecoverCrawl` | none | none | Creates a linked new Crawl; predecessor is route-bound. |
| `ATTR-RequestIngestionReplay` | `reason: text[20..2000]` | none | Creates one new dead-letter replay generation; target job is route-bound. |
| `ATTR-ReplayPipelineStage-parsing` | `reason: text[20..2000]` | none | Route fixes `stage=parsing`. |
| `ATTR-ReplayPipelineStage-indexing` | `reason: text[20..2000]` | none | Route fixes `stage=indexing`. |

### Evaluation, score and recommendation attributes

| Schema | Required attributes | Optional attributes | Route-fixed or conditional contract |
| --- | --- | --- | --- |
| `ATTR-RequestAdjudication` | `reason: text[20..2000]` | none | Route fixes dispute origin and creates/reuses its Case. |
| `ATTR-WithdrawAdjudication` | `case_id: uuid`; `case_state_version: uint`; `reason: text[20..2000]` | none | Issue version is in `If-Match`. |
| `ATTR-AssignAdjudication` | `case_id: uuid`; `case_state_version: uint` | none | Authenticated assigning actor becomes the adjudicator and must differ from requester. |
| `ATTR-DecideAdjudication` | `case_id: uuid`; `case_state_version: uint`; `decision: enum{uphold,reject}`; `decision_reason: ascii[1..120]`; `rationale: text[20..4000]` | none | Assigned adjudicator is authorization context, not client input. |
| `ATTR-ChangeEvidenceValidation` | `prior_effective_status: enum{valid,quarantined,invalid}`; `resulting_status: enum{valid,quarantined,invalid}`; `reason: enum{security_restriction,consent_review,retention_review,digest_recheck_required,schema_recheck_required,revalidation_passed,immutable_bytes_missing,digest_mismatch,schema_unsupported,legal_deletion_completed}` | none | Exact allowed transition/reason subset is further constrained by actor type in the Evidence contract. |
| `ATTR-StartReassessment` | none | none | Reserved and non-routable under `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`; full-Project semantics otherwise remain architecture input. |
| `ATTR-CancelReassessment` | `reason: text[20..2000]` | none | Evaluation is the route target. |
| `ATTR-ActivateReassessmentSchedule` | `candidate: object<ReassessmentSchedulePolicyCandidate>` | none | Reserved and non-routable under `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`; candidate Project equality otherwise remains architecture input. |
| `ATTR-RebaseHistoricalComparison` | `earlier_evaluation_id: uuid`; `later_evaluation_id: uuid`; `score_policy_version: ascii[1..120]`; `confidence_policy_version: ascii[1..120]`; `eligibility_policy_version: ascii[1..120]`; `fingerprint_version: ascii[1..120]`; `check_catalog_version: ascii[1..120]`; `scope_policy_versions: array<ascii[1..120]>[1..*] sorted-unique`; `pillar_applicability_version: ascii[1..120]` | none | Both retained input sets must contain every exact version; scope-definition hash remains non-overridable. |
| `ATTR-PublishRecommendation` | none | none | Publishes the route Artifact version only. |
| `ATTR-OverridePriority` | `recommendation_artifact_id: uuid`; `prior_order: uint`; `resulting_order: uint`; `reason: text[20..2000]` | none | Both orders are positive; the route has no Artifact ID, so it is semantic input. |

### Delivery, policy, commercial and integration attributes

| Schema | Required attributes | Optional attributes | Route-fixed or conditional contract |
| --- | --- | --- | --- |
| `ATTR-ActivateNotificationPolicy` | `candidate: object<NotificationPolicyCandidate>` | none | Conditional header supplies current/absent state. |
| `ATTR-ReplayDelivery` | `mode: enum{delivery_replay,empty_recipient_replay}`; `reason: text[20..2000]` | `source_delivery_id: uuid`; `duplicate_delivery_risk_acknowledged: bool` | `delivery_replay` requires both optional members; acknowledgment MUST be `true` when source state is `acceptance_unknown` and may be `false` for `terminal_failed`. `empty_recipient_replay` forbids both members and is valid only for `no_authorized_recipient`. |
| `ATTR-ActivateExportPolicy` | `candidate: object<ExportPolicyCandidate>` | none | Conditional header supplies current/absent state. |
| `ATTR-RequestExportApproval` | `selection: object<ExportSelection>` | none | Selection must be high-risk; request hash, one-hour expiry and requester are server-derived. |
| `ATTR-DecideExportApproval-approval` | none | none | Route fixes `decision=approve`; approver separation and one-hour clock are authoritative. |
| `ATTR-DecideExportApproval-rejection` | `reason: text[1..*]` | none | Route fixes `decision=reject`. |
| `ATTR-CreateExport` | `selection: object<ExportSelection>` | `approval_id: uuid` | `approval_id` is required exactly when selection is high-risk and must identify the exact approved selection/request hash. |
| `ATTR-RetryExport` | `selection: object<ExportSelection>`; `reason: text[1..*]` | `approval_id: uuid` | New approval is required exactly when retry selection is high-risk. |
| `ATTR-RevokeExport` | `reason: text[1..*]` | none | — |
| `ATTR-BeginExportRetrieval` | none | none | Exact empty object; Accept header selects no format and must match the stored format. |
| `ATTR-ActivateEntitlementPolicy` | `candidate: object<EntitlementPolicyCandidate>`; `plan_approval_id: uuid` | none | Conditional header supplies current/absent state; plan approval must authorize the candidate's exact canonical bytes. |
| `ATTR-DisconnectIntegration` | `reason: text[20..2000]` | none | — |
| `ATTR-RecoverIntegration` | `reason: text[20..2000]` | none | — |
| `ATTR-BeginCredentialRotation` | none | none | Reserved and non-routable under `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`; Volume II does not invent a token or replacement-material transport. |
| `ATTR-RevokeCredential` | `credential_state_version: uint`; `reason: text[20..2000]` | none | Integration version is carried by `If-Match`. |

### Security, lifecycle and service attributes

| Schema | Required attributes | Optional attributes | Route-fixed or conditional contract |
| --- | --- | --- | --- |
| `ATTR-RequestSupportSession` | `support_case_id: nullable uuid`; `incident_id: nullable uuid`; `resources: array<object<ResourceRef>>[1..*] sorted-unique`; `actions: array<ascii[1..120]>[1..*] sorted-unique`; `reason: text[20..2000]` | none | Exactly one of support-case or Incident ID is nonnull. |
| `ATTR-DecideSupportSession-security-approval` | none | none | Route fixes `decision=security_approve`. |
| `ATTR-DecideSupportSession-customer-approval` | none | none | Route fixes `decision=customer_approve`. |
| `ATTR-DecideSupportSession-rejection` | `reason: text[1..*]` | none | Route fixes `decision=reject`. |
| `ATTR-RevokeSupportSession` | `reason: text[1..*]` | none | — |
| `ATTR-DeclareIncident` | `observed_condition: ascii[1..120]`; `affected_scope: array<object<ResourceRef>>[1..*] sorted-unique`; `affected_workflows: array<ascii[1..120]>[1..*] sorted-unique`; `first_observed_at_utc: instant`; `source_telemetry_reference: ascii[1..512]`; `reason: text[20..2000]` | none | Severity and playbook are server-derived from the frozen trigger and baseline artifact. |
| `ATTR-RunIncidentStep` | `step: enum{capture_diagnostic_snapshot,link_named_remediation,verify_trigger_cleared}` | `remediation_command_result_id: uuid` | Result ID is required only for `link_named_remediation` and forbidden otherwise. Baseline step execution accepts no mutation target/action. |
| `ATTR-ResolveIncident` | none | none | Actor separation for critical/high is checked against the Incident; no client approval object is accepted. |
| `ATTR-OpenInvestigation` | `request_kind: enum{security_anomaly,compliance_inquiry,formal_audit}`; `organization_ids: array<uuid>[1..*] sorted-unique`; `required_inputs: array<object<InvestigationInputSpec>>[1..*]`; `interval_start_utc: instant`; `interval_end_utc: instant`; `legal_purpose: text[20..2000]`; `classification_ceiling: enum{public,internal,confidential,restricted}` | none | Start must be before end; each nested Organization occurs exactly once in the top-level set. |
| `ATTR-PublishInvestigationReport` | `completeness: enum{complete,partial,insufficient}`; `investigation_audit_evidence_item_ids: array<uuid>[0..*]`; `gap_ids: array<uuid>[0..*]`; `conclusions: array<text[1..4000]>[0..*]`; `proposed_actions: array<text[1..2000]>[0..*]` | none | Report digest/version are server-derived from canonical content. |
| `ATTR-CloseInvestigation` | `report_digest: sha256` | none | Closing actor must differ from the opener/report owner under WF-018. |
| `ATTR-RequestLegalHold` | `organization_id: uuid`; `resource_ids: array<uuid>[0..*] sorted-unique`; `retention_classes: array<enum{ephemeral_secret,temporary_processing,delivery_package,operational_telemetry,product_evidence_payload,product_history,identity_commercial,security_audit}>[0..8] sorted-unique`; `event_time_from_utc: instant`; `event_time_to_utc: instant`; `legal_purpose_reason: text[20..2000]` | none | At least one resource or retention class is required; interval is inclusive with from not later than to; scope must intersect active Support Session authority. |
| `ATTR-DecideLegalHold-approval` | none | none | Route fixes `decision=approve`. |
| `ATTR-DecideLegalHold-rejection` | none | none | Route fixes `decision=reject`; the Legal Hold record has no separate rejection-reason field. |
| `ATTR-RequestLegalHoldRelease` | `reason: text[20..2000]` | none | Hold identity/scope/version are route-bound; creates the distinct release request. |
| `ATTR-DecideLegalHoldRelease-approval` | none | none | Route fixes `decision=approve`; approving actor must differ from release requester. |
| `ATTR-DecideLegalHoldRelease-rejection` | `reason: text[1..*]` | none | Route fixes `decision=reject`. |
| `ATTR-RetryDeletion` | `reason: text[1..*]` | none | Creates one new recovery generation for a failed job only. |
| `ATTR-SubmitMeasurementEvidence` | `evaluation_id: uuid`; `measurement_kind: ascii[1..120]`; `measurement_set_id: uuid`; `measurement_set_version: ascii[1..120]`; `measurement_set_sha256: sha256`; `adapter_id: ascii[1..120]`; `adapter_version: ascii[1..120]`; `payload: object<MeasurementPayload>`; `payload_sha256: sha256`; `observed_at_utc: instant`; `data_classification: enum{public,internal,confidential,restricted}`; `payload_retention_class: enum{product_evidence_payload}` | none | Organization/Project are derived from Evaluation and verified service scope; payload key order/coverage follows the active set. |
| `ATTR-ActivateReleaseArtifact` | none | none | Route-bound immutable artifact bytes/signature/owner approval are verified; client cannot replace content or approval metadata. |
| `ATTR-RetireIntegration` | none | none | Reason is route-fixed to `policy_retired`; policy withdrawal/supersession is authoritative service context. |

### Route-qualified schema selection

| Route suffix | Selected schema |
| --- | --- |
| Invitation `/approval`, `/rejection` | `ATTR-DecideInvitation-approval`, `ATTR-DecideInvitation-rejection` respectively |
| Role Assignment `/approval`, `/rejection` | `ATTR-DecideRoleAssignment-approval`, `ATTR-DecideRoleAssignment-rejection` respectively |
| Closure Request `/approval`, `/rejection` | `ATTR-DecideOrganizationClosure-approval`, `ATTR-DecideOrganizationClosure-rejection` respectively |
| Parsing/Indexing `/recovery` | `ATTR-ReplayPipelineStage-parsing`, `ATTR-ReplayPipelineStage-indexing` respectively |
| Support Session `/approval`, `/customer-approval`, `/rejection` | `ATTR-DecideSupportSession-security-approval`, `ATTR-DecideSupportSession-customer-approval`, `ATTR-DecideSupportSession-rejection` respectively |
| Legal Hold `/approval`, `/rejection` | `ATTR-DecideLegalHold-approval`, `ATTR-DecideLegalHold-rejection` respectively |
| Export approval `/approval`, `/rejection` | `ATTR-DecideExportApproval-approval`, `ATTR-DecideExportApproval-rejection` respectively |
| Legal Hold release request `/approval`, `/rejection` | `ATTR-DecideLegalHoldRelease-approval`, `ATTR-DecideLegalHoldRelease-rejection` respectively |

Every other catalogue row selects its exact `ATTR-<Command>` schema. JSON Schema generation MUST prove a one-to-one row-to-schema selection and reject any schema reference not declared above.

### Application registry reconciliation

The Application Layer registry contains exactly `RequestIngestionReplay`, `AssignAdjudication`, `RequestExportApproval`, `DecideExportApproval`, `RequestLegalHoldRelease`, `DecideLegalHoldRelease`, and `ActivateReleaseArtifact` for the corresponding physical routes above. These are names for already-defined Volume I behavior, not new capability, and no API alias may substitute. The three high-risk Incident-step approval routes from the earlier draft remain absent because `incident-diagnostic-interim-v1` has no high-risk mutating step; exposing dormant approval routes would create baseline behavior.

## Query Transport

Queries are `GET` or `HEAD`, create no product transition and accept no `Idempotency-Key`. The outer authenticated-request transaction may update Session activity and write authorization/audit evidence as specified in [Application Layer](APPLICATION_LAYER.md); the Query Handler itself remains read-only.

This transport applies only to nonmetered reads. The five Volume I low-cost operations are deferred under `UPSTREAM-V1-LOW-COST-METERING-005`, which OD-019 resolves by ratifying the metered-read unit; their transport exposure is intentionally deferred to the Volume II baseline. Their proposed physical paths are retained below as blocked mappings, not routable endpoints.

Query success is:

```json
{
  "schema_version": "1.0",
  "data": {},
  "meta": {
    "correlation_id": "...",
    "projection_version": 1,
    "unavailable_reason_codes": []
  }
}
```

Query failure is never serialized as a `command_result` and is exactly:

```json
{
  "schema_version": "1.0",
  "data": null,
  "errors": [{
    "id": "00000000-0000-0000-0000-000000000000",
    "error_class": "authorization",
    "error_code": "F1-AUTH-403",
    "reason_code": "...",
    "severity": "warning",
    "retryable": false,
    "recovery_action": "obtain_required_authority_or_use_authorized_actor",
    "support_reference": "..."
  }],
  "meta": {"correlation_id": "..."}
}
```

The one-element `errors` array uses the same fixed error tuple/HTTP mapping as commands; `id` is the audited query-outcome UUID and `support_reference` equals the correlation ID. Target existence, cross-tenant identifiers, partial DTOs, policy internals and unrestricted diagnostics are forbidden. A blocked route is absent and returns transport `404`, not this query error.

After a route and identifier syntax match, an Organization or product identifier that does not resolve inside the authenticated tenant boundary returns the Volume I `F1-AUTH-403`; the application does not perform a second cross-tenant lookup to distinguish absent from inaccessible. An authenticated but unauthorized known in-tenant action also returns `F1-AUTH-403`. `404` is reserved for uncatalogued routes. A stale/unavailable projection returns `200` with its exact structured status/reasons when Volume I defines that as a product result; infrastructure failure uses the logical error mapping.

### Query catalogue

| Route | Query | Permission | Enablement |
| --- | --- | --- | --- |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/verification-requests/:id/challenge` | `QRY-021 PendingVerificationChallenge` | exact initiator or `source.verify` OrganizationAdmin | enabled |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/issues` | `QRY-009 IssueCollection` | `issue.read` | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/issues/:id` | `QRY-010 IssueDetail` | `issue.read`; Evidence fields independently redacted | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/issues/:id/evidence` | `QRY-036 IssueEvidenceCollection` | `issue.read`; each Evidence item is independently full or reference-only under Evidence field/classification authorization | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/issues/:id/closure-evidence` | `QRY-037 IssueClosureEvidenceCollection` | `issue.read`; each Evidence item is independently full or reference-only under Evidence field/classification authorization | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/issues/:id/adjudication-cases` | `QRY-038 IssueAdjudicationCaseCollection` | `issue.read`; Case fields follow the Issue's current field-authorization result | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/scores/current` | `QRY-024 CurrentScore` | `score.summary.read` or `score.detail.read` by field | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/history` | `QRY-025 HistoryCollection` | `history.read` | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/history/compare` | `QRY-008 HistoryComparison` | `history.read` | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` and `UPSTREAM-V1-COMPARISON-EVENT-007` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/recommendations` | `QRY-011 RecommendationCollection` | `recommendation.read` | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/recommendations/:id` | `QRY-012 RecommendationDetail` | `recommendation.read` | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/recommendations/:id/rationale-evidence` | `QRY-039 RecommendationRationaleEvidenceCollection` | `recommendation.read`; each Evidence item is independently full or reference-only under Evidence field/classification authorization | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/projects/:project_id/action-queue` | `QRY-013 ActionQueue` | `recommendation.read` | deferred under `UPSTREAM-V1-LOW-COST-METERING-005` |
| `GET /api/v1/organizations/:organization_id/entitlement-notices` | `QRY-018 EntitlementNoticeCollection` | `entitlement.notice.read`; notice fields only | enabled |

### Query DTO JSON schema registry

The selected DTO replaces the generic `data` object in the query success envelope. These are closed-world schemas: every listed member is required unless marked optional or redactable, every nullable member is present with null when its stated condition holds, and every unlisted member is forbidden. `decimal` is a nonexponent base-10 JSON string matching `-?(0|[1-9][0-9]*)(\.[0-9]+)?`; all other scalar notation is inherited from the command schema registry. `redactable(T,code)` means the member is present with type `T` when allowed and absent exactly when current field authorization denies it, in which case the nearest `redaction_codes` contains `code`; null is never a redaction placeholder. No unmarked member may be omitted.

Every collection `data` object is exactly `{ "type": <fixed enum>, "items": [...] }`; its `meta` additionally requires `page_size: uint`, `has_more: bool`, and `next_page_after: nullable ascii[1..*]`. A base detail DTO has no pagination members and embeds no child summary rows; a registered child-collection route uses the collection `meta` and returns one bounded child page. `correlation_id: uuid`, `projection_version: uint`, and `unavailable_reason_codes: array<ascii[1..120]>[0..*]` remain required in `meta` for both forms. Item order is the endpoint order defined below, never client-controlled beyond the declared cursor/filter contract. `PillarId` means exactly `enum{technical_integrity,search_presence,ai_presence,authority_signals,trust_signals,content_quality,local_presence}`. `confidence_decimal` means a four-decimal nonexponent string in inclusive range `0.0000..1.0000`; `score_decimal` means a one-decimal nonexponent string in inclusive range `0.0..100.0`.

| Named DTO object | Exact JSON members |
| --- | --- |
| `EvidenceMetadataDTO` | Discriminated by `access_status`. Full form is exactly `evidence_id: uuid`; `access_status: enum{full}`; `schema_version: ascii[1..120]`; `evidence_type: enum{source_document,crawl_observation,parsed_content,external_measurement,verification_observation,operator_attestation}`; `data_classification: enum{public,internal,confidential,restricted}`; `source_system: ascii[1..120]`; `source_id: nullable uuid`; `content_sha256: sha256`; `observed_at_utc: instant`; `validation_status: enum{valid,quarantined,invalid}`; `validation_decision_id: nullable uuid`; `payload_available: bool`; `redaction_codes: array<ascii[1..120]>[0..*]`. `source_id` is null only for project-level `external_measurement` Evidence. Reference-only form is exactly `evidence_id: uuid` and `access_status: enum{restricted}`. Optional `payload` exists only on the full form with `evidence.payload.read`, never for restricted Evidence without `evidence.restricted.read`, and matches the Evidence record's exact registered payload schema. Evidence Source is the conceptual view over these two canonical provenance members and is never emitted as another field. |
| `AdjudicationCaseDTO` | `adjudication_case_id: uuid`; `case_type: enum{system_review,customer_dispute}`; `case_status: enum{requested,assigned,upheld,rejected,withdrawn,obsolete}`; `request_reason: text[1..2000]`; `requested_at_utc: instant`; `assigned_at_utc: nullable instant`; `adjudicator_actor_id: nullable uuid`; `decision_at_utc: nullable instant`; `decision_actor_id: nullable uuid`; `decision_reason_code: nullable ascii[1..120]`; `decision_rationale: nullable text[1..4000]`; `due_at_utc: instant`; `sla_status: enum{within_sla,overdue,critical,closed}`; `preceding_case_id: nullable uuid`; `carried_from_case_id: nullable uuid`; `state_version: uint`. |
| `IssueSummaryDTO` | `issue_id: uuid`; `state_version: uint`; `check_definition_id: ascii[1..120]`; `pillar: PillarId`; `impact_band: enum{informational,low,medium,high,critical}`; `confidence_value: nullable confidence_decimal`; `confidence_status: enum{valid,missing,invalid}`; `confidence_band: enum{low,medium,high}`; `lifecycle_status: enum{candidate,open,resolved,dismissed,superseded}`; `adjudication_status: enum{not_required,review_required,disputed,in_review,upheld,rejected,withdrawn,obsolete}`; `publication_status: enum{withheld,published,suppressed}`; `first_seen_at_utc: instant`; `last_seen_at_utc: instant`; `supersedes_issue_id: nullable uuid`; `closure_reason_code: nullable ascii[1..120]`; `active_adjudication_case_id: nullable uuid`; `latest_adjudication_case_id: nullable uuid`; `redaction_codes: array<ascii[1..120]>[0..*]`. `confidence_value` is null exactly for missing/invalid status. |
| `PillarScoreDTO` | `pillar: PillarId`; `applicable: bool`; `status: enum{not_applicable,scored,insufficient_data,unavailable}`; `score: nullable score_decimal`; `unrounded_value: nullable decimal`; `effective_weight_numerator: decimal`; `effective_weight_denominator: decimal`; `included_contribution_count: uint`; `excluded_issue_count: uint`; `reason_codes: array<ascii[1..120]>[0..*]`. `score` and `unrounded_value` are nonnull exactly for `scored`; applicability/status/weight combinations follow the frozen ScoreSnapshot contract. |
| `ScoreSummaryDTO` | `score_snapshot_id: nullable uuid`; `evaluation_id: nullable uuid`; `issue_set_id: nullable uuid`; `availability_status: enum{available_complete,available_partial,unavailable}`; `overall_score: redactable(nullable score_decimal,score.overall)`; `pillars: redactable(array<object<PillarScoreDTO>>[7..7],score.pillar)` in canonical Pillar order without duplicate `pillar`; `unavailable_reason_codes: array<ascii[1..120]>[0..*]`; `invalidating_evidence_validation_decision_ids: array<uuid>[0..*] sorted-unique`; `recommendation_suppression_required: bool`; `score_policy_version: nullable ascii[1..120]`; `confidence_policy_version: nullable ascii[1..120]`; `eligibility_policy_version: nullable ascii[1..120]`; `projection_state_version: uint`; `updated_at_utc: instant`; `redaction_codes: array<ascii[1..120]>[0..*]`. Null snapshot/evaluation/policy values occur only before a first promotion; when present, `overall_score` is nonnull exactly for an available status. |
| `HistoryItemDTO` | `evaluation_id: uuid`; `score_snapshot_id: uuid`; `issue_set_id: uuid`; `evaluation_completed_at_utc: instant`; `overall_status: enum{complete,partial}`; `overall_score: redactable(score_decimal,score.overall)`; `pillar_scores: redactable(array<object<PillarScoreDTO>>[7..7],score.pillar)` in canonical Pillar order without duplicate `pillar`; `current_at_snapshot_issue_count: redactable(uint,history.issue_detail)`; `score_policy_version: ascii[1..120]`; `confidence_policy_version: ascii[1..120]`; `eligibility_policy_version: ascii[1..120]`; `fingerprint_version: ascii[1..120]`; `check_catalog_version: ascii[1..120]`; `scope_policy_version_set_hash: sha256`; `scope_definition_hash: sha256`; `pillar_applicability_version: ascii[1..120]`; `redaction_codes: array<ascii[1..120]>[0..*]`. Unavailable/nonpromoted snapshots never enter this history collection. |
| `RecommendationSummaryDTO` | `recommendation_id: uuid`; `artifact_family_id: uuid`; `artifact_version: uint`; `origin_issue_id: uuid`; `problem_statement: redactable(text[1..*],issue.summary_text)`; `expected_impact_band: enum{informational,low,medium,high,critical}`; `confidence_value: confidence_decimal`; `confidence_band: enum{low,medium,high}`; `effort_band: enum{low,medium,high,unknown}`; `publication_status: enum{published,suppressed}`; `generation_mode: enum{deterministic_template,ai_assisted}`; `created_at_utc: instant`; `redaction_codes: array<ascii[1..120]>[0..*]`. Draft/retired/noncurrent versions are not collection items. |
| `PriorityItemDTO` | `recommendation: object<RecommendationSummaryDTO>`; `base_order: uint`; `displayed_order: uint`; `impact_rank: enum{critical,high,medium,low,informational}`; `confidence_sort_value: nullable decimal`; `effort_band: enum{low,medium,high,unknown}`; `artifact_created_at_utc: instant`; `priority_policy_version: ascii[1..120]`; `input_sha256: sha256`; `override_actor_id: nullable uuid`; `override_reason: nullable text[20..2000]`; `overridden_at_utc: nullable instant`. The three override fields are all null or all nonnull. |
| `PillarDeltaDTO` | Exactly `pillar: PillarId`, `earlier_score: score_decimal`, `later_score: score_decimal`, and `delta: decimal` in inclusive range `-100.0..100.0`. |
| `EntitlementNoticeDTO` | `decision_id: uuid`; `operation: enum{crawl.start,reassessment.start,ai.generate,export.generate,report.view,history.view,issue.read,recommendation.read,score.read}`; `decision: enum{allow_with_warning,block}`; `reason_code: enum{soft_limit_reached,hard_limit_exceeded,organization_inactive,actor_inactive,service_unauthorized,entitlement_inactive,policy_unavailable,counter_unavailable,cached_policy_snapshot_used,cached_counter_snapshot_used,operation_unknown,reservation_conflict}`; `recovery_action: enum{none,wait_for_window,upgrade_plan,reactivate_organization,reactivate_actor,restore_policy,restore_counter,submit_new_attempt,contact_support}`; `usage_unit: nullable ascii[1..120]`; `window_start_utc: nullable instant`; `window_end_utc: nullable instant`; `soft_limit: nullable decimal`; `hard_limit: nullable decimal`; `requested_units: decimal`; `committed_units_before: nullable decimal`; `committed_units_after: nullable decimal`; `active_reserved_units_before: nullable decimal`; `active_reserved_units_after: nullable decimal`; `occurred_at_utc: instant`. Only warning/violation notice decisions are included; plan/BillingEntity/payment/provider fields are forbidden. |

The exact route-selected top-level DTOs are:

| Query | Exact `data` schema | Pagination and route inputs |
| --- | --- | --- |
| `QRY-021 PendingVerificationChallenge` | `type: enum{pending_verification_challenge}`; `id: uuid`; `attributes` exactly: `verification_request_id: uuid`, `source_id: uuid`, `request_status: enum{pending,verified,expired,canceled,failed}`, `method: enum{dns_txt,http_file}`, `canonical_host: ascii[1..253]`, `challenge_token: nullable ascii[43..43]`, `observation_location: nullable ascii[1..*]`, `required_value: nullable ascii[1..*]`, `issued_at_utc: instant`, `expires_at_utc: instant`, `state_version: uint`, `decision_reason_code: nullable ascii[1..120]`. Pending uses a server-generated 32-byte token encoded as unpadded base64url and has all three challenge fields nonnull; terminal status makes all three null. | No pagination; no query parameters. Decryption failure uses the logical error envelope, not null challenge on a pending request. |
| `QRY-009 IssueCollection` | `type: enum{issues}`; `items: array<object<IssueSummaryDTO>>[0..50]`. | Cursor pagination; optional single-value filters `lifecycle_status: enum{candidate,open,resolved,dismissed,superseded}`, `impact_band: enum{informational,low,medium,high,critical}`, and `pillar: PillarId`; order `created_at_utc DESC, issue_id DESC`. |
| `QRY-010 IssueDetail` base | `type: enum{issue}`; `id: uuid`; `attributes` contains every `IssueSummaryDTO` member plus `lineage_reason: nullable ascii[1..120]`, `closure_evaluation_id: nullable uuid`, `closure_check_result_id: nullable uuid`, `evidence_count: uint`, `closure_evidence_count: uint`, and `adjudication_case_count: uint`. Counts are over the complete immutable reference sets before per-item redaction; child arrays and cursor members are forbidden in this shape. | No pagination; no query parameters. |
| `QRY-036 IssueEvidenceCollection` | `type: enum{issue_evidence}`; `items: array<object<EvidenceMetadataDTO>>[0..50]`. | Route `/issues/:id/evidence`; cursor order is the immutable Issue Evidence `reference_ordinal ASC, evidence_id ASC`; only `page_size` and `page_after`. An Issue must have at least one item across the complete traversal. |
| `QRY-037 IssueClosureEvidenceCollection` | `type: enum{issue_closure_evidence}`; `items: array<object<EvidenceMetadataDTO>>[0..50]`. | Route `/issues/:id/closure-evidence`; cursor order is immutable closure-Evidence `reference_ordinal ASC, evidence_id ASC`; only `page_size` and `page_after`. Nonclosure/adjudication-dismissal states return an empty collection. |
| `QRY-038 IssueAdjudicationCaseCollection` | `type: enum{issue_adjudication_cases}`; `items: array<object<AdjudicationCaseDTO>>[0..50]`. | Route `/issues/:id/adjudication-cases`; cursor order is `requested_at_utc ASC, adjudication_case_id ASC`; only `page_size` and `page_after`. |
| `QRY-024 CurrentScore` | `type: enum{current_score}`; `id` is the route Project UUID; `attributes: object<ScoreSummaryDTO>`. | No pagination; no query parameters. Score-detail-only fields are absent with redaction codes unless `score.detail.read` is allowed. |
| `QRY-025 HistoryCollection` | `type: enum{history}`; `items: array<object<HistoryItemDTO>>[0..50]`. | Cursor pagination; optional `completed_from` and `completed_to` are RFC 3339 UTC instants, both inclusive, and when both exist `completed_from <= completed_to`; order `evaluation_completed_at_utc DESC, evaluation_id DESC`. |
| `QRY-008 HistoryComparison` | `type: enum{history_comparison}`; `id: sha256` of the ordered selected snapshot IDs; `attributes` exactly: `status: enum{comparable,not_comparable,insufficient_history,comparison_unavailable}`, `earlier: nullable object<HistoryItemDTO>`, `later: nullable object<HistoryItemDTO>`, `available_run_count: uint`, `overall_delta: nullable decimal`, `pillar_deltas: array<object<PillarDeltaDTO>>[0..7]` without duplicate `pillar`, `mismatch_codes: array<enum{score_policy_mismatch,confidence_policy_mismatch,eligibility_policy_mismatch,fingerprint_version_mismatch,check_catalog_version_mismatch,scope_policy_version_set_mismatch,scope_definition_mismatch,pillar_applicability_mismatch}>[0..8]`, `next_action_code: nullable enum{complete_initial_evaluation,complete_next_evaluation,select_compatible_pair,request_rebase,retry_projection}`, `redaction_codes: array<ascii[1..120]>[0..*]`. Deltas are nonnull/nonempty only for `comparable`; insufficient history has null selected items as unavailable and exact count 0 or 1. | No pagination; query requires exactly `earlier_score_snapshot_id: uuid` and `later_score_snapshot_id: uuid`, except both are omitted to request the canonical latest compatible pair. One supplied ID, equality, or any other parameter is validation-invalid. |
| `QRY-011 RecommendationCollection` | `type: enum{recommendations}`; `items: array<object<RecommendationSummaryDTO>>[0..50]`. | Cursor pagination; optional `publication_status: enum{published,suppressed}`; order `created_at_utc DESC, recommendation_id DESC`. |
| `QRY-012 RecommendationDetail` base | `type: enum{recommendation}`; `id: uuid`; `attributes` contains every `RecommendationSummaryDTO` member plus `predecessor_recommendation_id: nullable uuid`, `generation_definition_family_id: ascii[1..120]`, `generation_definition_version: ascii[1..120]`, `related_issue_references: array<uuid>[0..*]`, `rationale: redactable(text[1..*],recommendation.rationale)`, `effort_basis: redactable(text[1..*],recommendation.rationale)`, `effort_policy_version: ascii[1..120]`, `implementation_steps: redactable(array<text[1..*]>[1..*],recommendation.steps)`, `verification_steps: redactable(array<text[1..*]>[1..*],recommendation.steps)`, `platform_applicability: redactable(text[1..*],recommendation.rationale)`, `advisory_scope: enum{discoverability_only}`, `ai_response_id: nullable uuid`, and `rationale_evidence_count: uint`. The count is over the complete immutable reference set before per-item redaction; child arrays and cursor members are forbidden in this shape. | No pagination; no query parameters. The baseline may return existing governed `ai_assisted` Recommendation artifacts, but never dashboard/history narrative. |
| `QRY-039 RecommendationRationaleEvidenceCollection` | `type: enum{recommendation_rationale_evidence}`; `items: array<object<EvidenceMetadataDTO>>[0..50]`. | Route `/recommendations/:id/rationale-evidence`; cursor order is immutable rationale-Evidence `reference_ordinal ASC, evidence_id ASC`; only `page_size` and `page_after`. A published Artifact must have at least one item across the complete traversal. |
| `QRY-013 ActionQueue` | `type: enum{action_queue}`; `items: array<object<PriorityItemDTO>>[0..50]`. | Cursor pagination; order `displayed_order ASC, recommendation_id ASC`; no filters. |
| `QRY-018 EntitlementNoticeCollection` | `type: enum{entitlement_notices}`; `items: array<object<EntitlementNoticeDTO>>[0..50]`. | Cursor pagination; order `occurred_at_utc DESC, decision_id DESC`; no filters. `QRY-035 CommercialSummary` is the separately registered blocked BillingEntity/Plan/usage query and has no API route. |

All array item schemas are recursively closed. `QRY-003`/`QRY-008` data contains no narrative, narrative placeholder, presentation-region hint, prompt/model/provider field or provider-call status. The marked blocked DTOs are contract shapes only and cannot be routed until their upstream blockers are resolved.

Volume I does not define read actions or deterministic equivalent predicates for Organization home, Project, Source, Crawl, Evaluation progress/collection, Account administration, general policy administration, Notification inbox, Export list/detail, Integration status, Support Session collection, Billing summary, Incident/Investigation/Legal Hold collection/detail or deletion-job collection. Terms such as “project-visible”, “billing authority” or “lifecycle authority” are not permission contracts. Those routes are intentionally absent until controlled Volume I clarification names the actor/action/resource/field behavior. Exact existing read actions in the table above remain implementable after any named metering blocker is corrected; command-result responses remain available to the actor that submitted the command under the command replay/redaction contract.

No customer-facing arbitrary Document/Evidence full-text search endpoint exists. Internal retrieval is defined in [Search, Crawl And Retrieval](SEARCH_CRAWL_RETRIEVAL.md).

## Pagination, Filtering And Ordering

- Every collection uses cursor pagination. Offset/page-number pagination is prohibited.
- Default page size is 50; `page_size` accepts 1-50. A larger or noninteger value is `F1-VALIDATION-400 / pagination_invalid`.
- `page_after` is an opaque base64url token containing version, endpoint ID, normalized filter hash and the complete persisted sort tuple (including its UUID tie-breaker), authenticated with HMAC-SHA-256. Invalid signature/version/endpoint/filter binding returns `pagination_cursor_invalid`.
- Responses include `meta.page_size`, `meta.has_more` and nullable `meta.next_page_after`; total count is omitted unless the Query contract explicitly supplies a materialized count.
- Every order is total and immutable for one cursor version. Exact orders are Issue collection `created_at_utc DESC, issue_id DESC`; Issue Evidence and closure-Evidence child collections `reference_ordinal ASC, evidence_id ASC`; Issue Case child collection `requested_at_utc ASC, adjudication_case_id ASC`; History collection `evaluation_completed_at_utc DESC, evaluation_id DESC`; Recommendation collection `created_at_utc DESC, recommendation_id DESC`; Recommendation rationale-Evidence child collection `reference_ordinal ASC, evidence_id ASC`; Action Queue `displayed_order ASC, recommendation_id ASC`; and Entitlement Notice collection `occurred_at_utc DESC, decision_id DESC`. No database-default or unstated secondary order is permitted.
- Allowed query members are exact: Issues accept `lifecycle_status`, `impact_band`, and `pillar`; history collection accepts `completed_from` and `completed_to`; Recommendation collection accepts `publication_status`; history comparison accepts the paired snapshot IDs under its DTO contract; child collections accept no filter. Every collection accepts only `page_size` and `page_after` in addition to its listed filters. Unknown parameters are rejected.
- Cursor reads use the projection/data snapshot visible at each request. Inserts before the cursor may appear only on a fresh traversal; no item repeats within one unchanged sort tuple.
- Evidence child collections select and paginate the complete authorized parent reference list before field/classification authorization. Each selected reference retains its ordinal and becomes either the full or exact reference-only `EvidenceMetadataDTO`; no item is dropped, reordered or backfilled because its metadata/payload is restricted.

## Conditional Reads And Concurrency

Detail and projection responses emit `ETag: "f1-<resource-or-projection-version>-<redaction-hash>"`. For an enabled nonmetered read, `If-None-Match` returns `304` only after current authentication, authorization and redaction resolution. Metered reads remain disabled until Volume I defines whether a conditional response is a durable low-cost response and how its Decision/usage identity is deduplicated. ETags are not capability tokens and cannot bypass Session activity or audit requirements.

Commands never infer expected state from a stale query cached by the browser. The form carries the ETag-derived state version and submits it through `If-Match`; a mismatch is the exact stale-state logical result.

## Export Physical Serialization

Export rendering uses the frozen object/field allowlist and redaction decisions in its manifest. No renderer queries live product tables after generation begins. It receives one deeply frozen generation DTO, writes a private staged object, computes member/package SHA-256 while streaming, and publishes only after the stored-object metadata and manifest reconcile. Filenames contain only the Export UUID and fixed ASCII text; customer names never enter a filename.

| Logical format | Media type and filename | Physical contract |
| --- | --- | --- |
| `pdf_report` | `application/pdf`; `f1-report-<export_id>.pdf` | PDF 1.7 generated by Prawn 2.5.0 with the checked-in Noto Sans font files; A4 portrait, 15 mm margins, deterministic section order below |
| `csv_data` | `application/zip`; `f1-data-<export_id>.zip` | ZIP created by rubyzip 3.4.1, no encryption, no ZIP64, deflate level 6, fixed member order below |
| `json_data` | `application/json`; `f1-data-<export_id>.json` | UTF-8 canonical JSON, no BOM or insignificant whitespace, exact decimals as strings and arrays in manifest order |

PDF pages use Noto Sans 10 pt body, 18/14/11 pt level-one/two/three headings, 8 pt table text, 1.35 line height, black text on white and the approved non-color status label. Each page has Export reference, generated-at instant and `Page n of N`; it contains no hidden metadata beyond PDF producer/version, Export ID and generation instant. Reading order is document order. Tables repeat headers and never convey status by color alone.

The PDF section order is title and scope; ScoreSnapshot summary; published Issue summaries; published Recommendation fields; redaction/unavailable codes; generation provenance. Within a section, rows use the exact frozen manifest order. An authorized empty section says `No authorized items`; a wholly unauthorized section is omitted and its redaction code appears in the final code list. Dashboard/history narrative is never generated or reserved.

The CSV archive member order is `manifest.json`, then any nonempty approved members in this fixed sequence: `scores.csv`, `score_contributions.csv`, `issues.csv`, `recommendations.csv`, `evidence_metadata.csv`. `manifest.json` is canonical JSON containing Export/schema IDs, format, generated time, scope hash, ordered member names/digests/sizes, ordered logical fields and redaction codes. CSV uses UTF-8 without BOM, comma delimiter, double-quote escaping by doubled quote, CRLF record endings, one header row in manifest-field order, empty bytes for null, `true`/`false`, RFC 3339 UTC instants with six fractional digits, lowercase UUIDs and exact decimal strings. Records retain manifest object order; formula-capable leading `=`, `+`, `-`, `@`, tab or carriage-return text is prefixed by one apostrophe and the manifest records `spreadsheet_formula_escaped` for that field.

JSON top-level members are exactly `schema_version`, `export_id`, `generated_at_utc`, `scope`, `redaction_codes`, `scores`, `score_contributions`, `issues`, `recommendations`, and `evidence_metadata`. Arrays are always present and may be empty; objects contain only approved fields in lexicographic key order. The physical serializer never substitutes display labels for canonical values.

Content-Disposition is `attachment` with the fixed filename. Responses add `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store`, no `Content-Encoding`, and the stored byte length/digest audit metadata. The renderer is deterministic for identical DTO, dependency/font versions and generation instant, but Volume I does not require two separately generated packages to have identical bytes.

## Export Byte Retrieval

`POST .../exports/:id/retrievals` is the external `BeginExportRetrieval` command and never returns a public/presigned URL. It requires `ATTR-BeginExportRetrieval` (the standard empty-attributes command body), `Idempotency-Key`, current Export `If-Match`, CSRF for a browser Session and an `Accept` value matching the Export's fixed media type or `*/*`. A successful physical response is the bytes rather than the JSON command envelope; `X-F1-Command-Result-ID`, `X-F1-Export-Retrieval-ID`, `X-F1-Content-SHA256` and `Idempotency-Replayed` expose the persisted command/result identity. Any failure returns the standard JSON command result and emits zero bytes. The internal terminal stream record is completed by the registered `CompleteExportRetrieval` operation; it is not a second HTTP command or second product retrieval. The flow uses four physical checkpoints:

1. In a short transaction, claim the exact command/idempotency identity, authenticate, bind tenant, authorize the requester-as-recipient, validate `If-Match`, current Export/manifest/policy and create one `export_retrieval` intent without starting bytes. A concurrent duplicate observes or waits for that same claim and never creates another logical retrieval.
2. Outside a transaction, open the private object and validate storage metadata/digest availability; no client byte is emitted.
3. In a second short transaction, lock the retrieval/Export, reauthenticate and reauthorize current Session, Account, Organization, Export state, effective expiry, manifest, field permission and policy. At expiry equality, expiry wins. Success atomically commits the logical command result, audit, `ExportRetrieved` event/outbox and `stream_started_at`; denial commits the failure result/reason and emits zero bytes.
4. Outside a transaction, stream bounded chunks through Rails, compute byte count/digest, then terminalize the retrieval in a final short transaction. Client disconnect records `client_disconnected`; it never changes Export state.

Revocation or expiry committed before checkpoint 3 yields zero bytes. A change after checkpoint 3 does not recall bytes already emitted, and the audit identifies the exact start authorization decision/time. Client disconnect records an immutable attempt outcome but does not retract the committed logical result or emit another product event. An exact idempotent replay first reapplies current authorization/redaction and, if still allowed, streams the same immutable object under the same logical command/retrieval/result IDs; it records a new byte-stream attempt only. `Range` requests and resumable/public URLs are not supported in the baseline.

## Provider Webhook Ingress

The only active provider route is `POST /webhooks/mailgun/v1/events`. It is the sole exception that accepts `Content-Type: application/json`; every response is `text/plain` with the exact status/body contract in [Integration Contracts](INTEGRATION_CONTRACTS.md). Its signature, timestamp, body, replay and event mapping are delegated there without alteration. Stripe, Mux, OpenAI, Anthropic, Google and OpenRouter routes do not exist in the accepted baseline.

## Physical Domain Event Serialization

### Canonical bytes and envelope

Every Domain Event is one JSON object serialized by RFC 8785 JSON Canonicalization Scheme after every string value has been normalized to Unicode NFC. Input construction rejects duplicate keys, lone surrogates, invalid UTF-8, nonfinite numbers and integers outside `0..9007199254740991`; exact decimals remain strings. The canonical event bytes are UTF-8 with no BOM, trailing newline or transport wrapper. `event_sha256` is lowercase hexadecimal SHA-256 over exactly those bytes. PostgreSQL stores the immutable bytes, byte count and digest; every dispatcher/consumer loads those bytes and verifies both before parsing. It never regenerates delivery bytes from relational columns.

The root object has exactly `event_id: uuid`, `event_type: EventType`, `schema_version: enum{1.0}`, `workflow_id: enum{WF-001,WF-002,WF-003,WF-004,WF-005,WF-006,WF-007,WF-008,WF-009,WF-010,WF-011,WF-012,WF-013,WF-014,WF-015,WF-016,WF-017,WF-018}`, `event_profile: enum{created,state_transition,attempt,decision,policy_activation,projection,failure,recovery}`, `occurred_at_utc: instant`, `organization_id: uuid`, `project_id: nullable uuid`, `affected_entity_type: EventEntityType`, `affected_entity_id: EventEntityIdentity`, `aggregate_version: uint53`, `actor_id: nullable uuid`, `service_identity_id: nullable uuid`, `correlation_id: uuid`, `causation_id: uuid`, `command_id: nullable uuid`, `idempotency_identity_hash: nullable sha256`, `outcome: enum{success,failure}`, `reason_code: nullable EventReasonCode`, `audit_record_id: uuid`, `related_entities: array<object<EventEntityRef>>[0..*] sorted-unique`, `governing_versions: array<object<EventGoverningVersion>>[0..*] sorted-unique`, `event_payload: object<EventProfilePayload>`, `input_hash: nullable sha256`, and `output_hash: nullable sha256`. Optional `notification_context_v1` is the only additional root member and is present exactly when an outbox route is created. Exactly one actor/service field is nonnull. The inline event catalogue below fixes the workflow, affected type, allowed profile variants, reason source and extra schema. The Volume I profile first-match rule selects one allowed variant for each occurrence; a producer cannot select another allowed variant when an earlier predicate applies. Unknown members, event types, type/profile pairs and extra-schema combinations are prohibited.

Physical event named types are closed:

| Type | Exact physical schema |
| --- | --- |
| `EventEntityType` | Enum `account`, `service_identity`, `organization`, `organization_closure_request`, `billing_entity`, `role_assignment`, `access_policy`, `entitlement_policy`, `plan_assignment`, `project`, `session`, `bootstrap_grant`, `invitation`, `source`, `verification_request`, `source_scope_change_request`, `crawl`, `crawl_limit_decision`, `fetch_attempt`, `ingestion_job`, `document`, `parsing_job`, `parsed_artifact`, `indexing_job`, `index_receipt`, `evaluation`, `evaluation_input_snapshot`, `check_applicability_snapshot`, `check_result`, `check_attempt`, `issue_set`, `issue`, `adjudication_case`, `adjudication_sla_decision`, `evidence`, `evidence_validation_decision`, `score_snapshot`, `score_contribution`, `current_score_projection`, `recommendation_artifact`, `ai_response`, `citation`, `fingerprint_collision_decision`, `priority_decision`, `action_queue_projection_version`, `reassessment_result`, `notification`, `delivery`, `delivery_attempt`, `delivery_reconciliation`, `notification_escalation`, `notification_replay_acknowledgement`, `entitlement_decision`, `entitlement_reservation`, `entitlement_lease_heartbeat`, `low_cost_usage_record`, `export_approval`, `export`, `export_retrieval`, `integration`, `credential`, `support_session`, `incident`, `incident_decision`, `incident_step_attempt`, `incident_restoration_check`, `investigation`, `investigation_input`, `investigation_report`, `legal_hold`, `legal_hold_release_request`, `lifecycle_deletion_job`, `deletion_manifest`, `policy_artifact`, `release_artifact`, `scheduled_action`, `provider_message`, `provider_event`, and `audit_record`; no other value is accepted in major 1. Measurement Evidence uses `evidence` with `evidence_type=external_measurement` and is never another entity type. |
| `EventEntityIdentity` | Canonical lowercase UUID for every entity type except `invitation`, `provider_message` and `provider_event`, which require lowercase SHA-256 over the decoded Invitation reference bytes or provider identifier respectively. |
| `EventEntityRef` | Exactly `entity_type: EventEntityType`, `identity_kind: enum{uuid,sha256}`, and `entity_id: EventEntityIdentity`. `identity_kind=sha256` is required exactly for `invitation`, `provider_message` and `provider_event`; every other type requires `uuid`. Entries are sorted by entity type UTF-8 bytes then normalized ID, contain no duplicate pair and never contain a raw Invitation or provider identifier. |
| `EventArtifactType` | Enum `access_policy`, `classification_profile`, `protected_permission_profile`, `source_scope_policy`, `global_crawl_safety`, `crawl_policy`, `parser_definition`, `normalization_schema`, `index_definition`, `check_catalog`, `check_definition`, `score_policy`, `confidence_policy`, `eligibility_policy`, `fingerprint_policy`, `pillar_applicability`, `recommendation_template`, `effort_policy`, `priority_policy`, `reassessment_schedule_policy`, `notification_policy`, `notification_template`, `entitlement_policy`, `plan_approval`, `export_policy`, `retention_policy`, `incident_playbook`, `support_access_policy`, `integration_adapter_policy`, `measurement_set`, `citation_policy`, `ai_policy`, or `release_artifact`. |
| `EventGoverningVersion` | Exactly `artifact_type: EventArtifactType`, `artifact_id: uuid`, `version: ascii[1..120]`, and `content_sha256: sha256`; sorted by artifact type, ID, version, then digest and duplicate-free. Every governing artifact named by the workflow is present and no inferred/current-at-consumption version is added. |
| `EventPointer` | Exactly `pointer_name: enum{current_evaluation,current_evaluation_input_snapshot,current_issue_set,current_score_snapshot,current_score_projection,current_recommendation_artifact,current_action_queue}` and `entity: nullable object<EventEntityRef>`. A pointer name not meaningful to the selected projection event is prohibited. |
| `EventImmutableRecord` | Exactly `entity: object<EventEntityRef>` and `content_sha256: sha256`. |
| `InputReadinessFailedEntry` | Exactly `entity: object<EventEntityRef>` and `reason_code: EventReasonCode`. `entity.entity_type=document`. Entries preserve the sealed Volume I evaluation-input manifest's failed-subset order exactly; publishers do not sort, deduplicate, regroup or translate them. |
| `EventReasonCode` | Lowercase machine token matching `[a-z][a-z0-9_]{0,119}`. It is not free text or open vocabulary: the catalogue's reason-source column requires an exact byte-for-byte copy from the expressly named machine-code field or literal. Human-submitted `reason`, rationale, explanation, note and diagnostic text remain only in their restricted retained/audit records and never populate root `reason_code`, `transition_reason_code`, `sanitized_reason_code` or `decision_reason_code`. When Volume I supplies no exact machine code, the catalogue source is `none` and root `reason_code` is null; no publisher may derive, slug, translate or default a code from prose. |
| `EventStateCode` | Lowercase ASCII token matching `[a-z][a-z0-9_]{0,119}` and constrained to the affected record's state domain below. |
| `EventStageCode` | Enum `source_verification_observation`, `check_execution`, or `notification_delivery`; the selected attempt extra schema narrows it to one literal. No other major-1 event admits the attempt profile. |

The state domains used by lifecycle profiles are exact:

| Affected entity | Permitted state codes |
| --- | --- |
| `account` | `pending`, `active`, `suspended`, `revoked` |
| `session` | `active`, `revoked`, `expired` |
| `organization` | `pending`, `active`, `suspended`, `closed` |
| `organization_closure_request` | `pending`, `approved`, `rejected`, `expired`, `executed` |
| `billing_entity` | `pending`, `active`, `past_due`, `suspended`, `closed`; the reserved states remain unreachable |
| `bootstrap_grant` | `issued`, `consumed`, `revoked`, `expired` |
| `invitation` | `pending_approval`, `active`, `accepted`, `declined`, `rejected`, `revoked`, `expired` |
| `role_assignment` | `pending`, `active`, `rejected`, `revoked`, `expired` |
| `access_policy` | `draft`, `active`, `superseded`, `retired` |
| `plan_assignment` | `active`, `superseded`, `revoked` |
| `support_session` | `pending`, `active`, `rejected`, `expired`, `revoked` |
| `legal_hold` | `pending`, `active`, `rejected`, `released` |
| `lifecycle_deletion_job` | `queued`, `running`, `blocked`, `failed`, `completed` |
| `project` | `draft`, `active`, `paused`, `archived` |
| `source` | `proposed`, `verified`, `active`, `disabled`, `removed` |
| `verification_request` | `pending`, `verified`, `expired`, `canceled`, `failed` |
| `source_scope_change_request` | `pending`, `approved`, `rejected`, `expired`, `canceled` |
| `document` | `discovered`, `ingested`, `parsed`, `indexed`, `quarantined`, `retired` |
| `crawl` | `queued`, `running`, `completed`, `failed`, `canceled` |
| `ingestion_job`, `parsing_job`, `indexing_job` | `queued`, `running`, `succeeded`, `failed`, `dead_letter` |
| `evaluation` | `pending`, `running`, `completed`, `failed`, `superseded` |
| `evidence` | effective validation `valid`, `quarantined`, or `invalid` |
| `check_result` | `passed`, `failed`, `inconclusive`, `not_applicable`, `error` |
| `issue` | lifecycle `candidate`, `open`, `resolved`, `dismissed`, or `superseded` |
| `adjudication_case` | `requested`, `assigned`, `upheld`, `rejected`, `withdrawn`, `obsolete` |
| `recommendation_artifact` | `draft`, `published`, `suppressed`, `retired` |
| `ai_response` | `requested`, `generated`, `validated`, `rejected`, `expired` |
| `citation` | `proposed`, `verified`, `invalid`, `superseded` |
| `current_score_projection` | `available_complete`, `available_partial`, `unavailable` |
| `action_queue_projection_version` | `published` |
| `reassessment_result` | `completed`, `failed`, `canceled` |
| `notification` | `pending`, `uncertain`, `sent`, `partial`, `failed`, `suppressed` |
| `delivery` | `pending`, `attempting`, `accepted`, `delivered`, `retry_scheduled`, `acceptance_unknown`, `terminal_failed`, `suppressed` |
| `entitlement_reservation` | `reserved`, `executing`, `committed`, `released`, `expired` |
| `entitlement_lease_heartbeat` | `renewed` |
| `export` | `pending`, `generating`, `available`, `failed`, `expired`, `revoked` |
| `export_retrieval` | `intent`, `stream_started`, `denied` |
| `integration` | `proposed`, `connected`, `degraded`, `disconnected`, `retired` |
| `credential` | `pending`, `active`, `rotating`, `revoked`, `expired` |
| `incident` | `open`, `mitigated`, `resolved` |
| `incident_step_attempt` | `running`, `succeeded`, `failed` |
| `incident_restoration_check` | `passed` |
| `investigation` | `open`, `reported`, `closed` |

For a created record whose immutable status is not a mutable lifecycle above—Evidence, ScoreSnapshot, priority/entitlement decisions, snapshots, retrievals and audit records—`to_state` is the exact retained status/value named by its selected extra schema; a publisher cannot invent another state token.

### Inline event type catalogue

The table is the complete physical `EventType` enum. A comma-separated cell admits each exact case-sensitive name and no pattern expansion. `ST` means `state_transition`; `R` means `recovery` only when all Volume I recovery fields are present; `C`, `A`, `D`, `P`, `PJ` and `F` mean `created`, `attempt`, `decision`, `policy_activation`, `projection` and `failure`. Every `R` admitted below has `base_profile=state_transition`; no major-1 event admits attempt-based recovery. Where a cell contains multiple profiles, the Volume I first-match predicates choose one: `R` on nonnull recovery lineage, otherwise `C` only with absent prior aggregate, otherwise `ST` for a lifecycle change. Every other combination is invalid. In the reason column, `transition` means the exact retained `transition_reason_code`; `attempt` means exact `sanitized_reason_code`; `decision` means exact `decision_reason_code`; `projection` means the first retained unavailable-reason code; `result` means exact retained terminal result reason; and a named literal schema means the exact mapping declared by that extra schema. For a successful `R`, root reason is the current transition's normally-null `transition_reason_code`, never `earlier_terminal_reason_code`. `none` requires null. All sources are machine codes under `EventReasonCode`; prose is never a source.

| Event types | Workflow | Affected entity | Allowed profile(s) | Extra schema | Reason source |
| --- | --- | --- | --- | --- | --- |
| `BootstrapGrantIssued` | WF-001 | `bootstrap_grant` | C | `none` | none; emission unavailable under `UPSTREAM-V1-EVENT-SCOPE-001` |
| `BootstrapGrantConsumed` | WF-001 | `bootstrap_grant` | ST | `none` | none |
| `BootstrapGrantExpired` | WF-001 | `bootstrap_grant` | ST | `none` | transition |
| `AccountProvisionRequested` | WF-001 | `account` | C | `none` | none |
| `AccountActivated` | WF-001 | `account` | ST | `none` | none |
| `OrganizationCreated` | WF-001 | `organization` | C | `none` | none |
| `OrganizationActivated` | WF-001 | `organization` | ST | `none` | none |
| `BillingStateChanged` | WF-001 or WF-013 | `billing_entity` | C or ST | `billing_transition` | none |
| `RoleGranted` | WF-001 or WF-013 | `role_assignment` | C or ST | `none` | none |
| `PlanAssigned` | WF-001 | `plan_assignment` | C | `none` | none |
| `AccessPolicyActivated` | WF-001 or WF-013 | `access_policy` | P | `none` | none |
| `EntitlementPolicyActivated` | WF-001 or WF-015 | `entitlement_policy` | P | `none` | none |
| `ProjectCreated` | WF-001 or WF-002 | `project` | C | `none` | none |
| `SessionCreated` | WF-001 | `session` | C | `session_creation` | none |
| `ProjectActivated` | WF-002 | `project` | ST | `none` | none |
| `ProjectPaused`, `ProjectReactivated`, `ProjectArchived` | WF-002 | `project` | ST | `none` | unavailable under `UPSTREAM-V1-PROJECT-LIFECYCLE-003` |
| `SourceVerificationRequested` | WF-003 | `verification_request` | C | `none` | none |
| `SourceVerificationObserved` | WF-003 | `verification_request` | A | `source_verification_attempt` | attempt |
| `SourceVerified` | WF-003 | `source` | ST | `none` | none |
| `SourceVerificationExpired`, `SourceVerificationCanceled`, `SourceVerificationFailed` | WF-003 | `verification_request` | ST | `none` | transition |
| `SourceRegistered` | WF-004 | `source` | C | `none` | none |
| `SourceScopeChangeRequested` | WF-004 | `source_scope_change_request` | C | `none` | none |
| `SourceScopeChangeApproved` | WF-004 | `source_scope_change_request` | ST | `none` | none |
| `SourceScopeChangeRejected`, `SourceScopeChangeCanceled` | WF-004 | `source_scope_change_request` | ST | `none` | none |
| `SourceScopeChangeExpired` | WF-004 | `source_scope_change_request` | ST | `none` | transition |
| `SourceActivated` | WF-004 | `source` | ST | `none` | none |
| `SourceDisabled`, `SourceRemoved` | WF-004 | `source` | ST | `none` | transition |
| `CrawlPolicyActivated` | WF-005 | `policy_artifact` | P | `none` | none |
| `CrawlQueued` | WF-005 | `crawl` | C | `crawl_terminal` | none |
| `CrawlStarted` | WF-005 | `crawl` | ST | `crawl_terminal` | none |
| `CrawlCompleted` | WF-005 | `crawl` | ST or R | `crawl_terminal` | none |
| `CrawlFailed`, `CrawlCanceled` | WF-005 | `crawl` | ST | `crawl_terminal` | transition |
| `CrawlSoftLimitApproaching`, `CrawlLimitReached` | WF-005 | `crawl` | D | `crawl_limit_decision` | decision |
| `DocumentDiscovered` | WF-005 | `document` | C | `none` | none |
| `DocumentIngested`, `DocumentParsed`, `DocumentIndexed` | WF-005/WF-006 | `document` | ST or R | `none` | none |
| `IngestionQueued` | WF-005 | `ingestion_job` | C | `pipeline_job` | none |
| `IngestionStarted`, `IngestionSucceeded` | WF-005/WF-006 | `ingestion_job` | ST or R | `pipeline_job` | none |
| `IngestionFailed`, `IngestionDeadLettered` | WF-005/WF-006 | `ingestion_job` | ST | `pipeline_job` | transition |
| `IngestionReplayRequested` | WF-005 | `ingestion_job` | ST | `replay_request` | none |
| `ParsingQueued` | WF-006 | `parsing_job` | C | `pipeline_job` | none |
| `ParsingStarted`, `ParsingSucceeded` | WF-006 | `parsing_job` | ST or R | `pipeline_job` | none |
| `ParsingFailed`, `ParsingDeadLettered` | WF-006 | `parsing_job` | ST | `pipeline_job` | transition |
| `ParsingReplayRequested` | WF-006 | `parsing_job` | ST | `replay_request` | none |
| `IndexingQueued` | WF-006 | `indexing_job` | C | `pipeline_job` | none |
| `IndexingStarted`, `IndexingSucceeded` | WF-006 | `indexing_job` | ST or R | `pipeline_job` | none |
| `IndexingFailed`, `IndexingDeadLettered` | WF-006 | `indexing_job` | ST | `pipeline_job` | transition |
| `IndexingReplayRequested` | WF-006 | `indexing_job` | ST | `replay_request` | none |
| `ExternalMeasurementAccepted` | WF-006 | `evidence` | C | `external_measurement` | none |
| `EvaluationInputsReady` | WF-006 | `evaluation_input_snapshot` | C | `input_readiness` | none |
| `EvaluationInputsBlocked` | WF-006 | `evaluation_input_snapshot` | C | `input_readiness` | literal `evaluation_inputs_unavailable` |
| `EvaluationPending` | WF-005 | `evaluation` | C | `evaluation_counts` | none |
| `EvaluationStarted` | WF-006/WF-007/WF-011 | `evaluation` | C or ST | `evaluation_counts` | none |
| `EvaluationCompleted`, `EvaluationSuperseded` | WF-007/WF-011 | `evaluation` | ST or R | `evaluation_counts` | none |
| `EvaluationFailed` | WF-007/WF-011 | `evaluation` | ST | `evaluation_counts` | transition |
| `CheckExecutionRetried` | WF-007 | `check_attempt` | A | `check_execution` | attempt |
| `CheckResultCreated` | WF-007 | `check_result` | C | `check_result` | `check_result` |
| `CheckResultFingerprintCollision` | WF-007 | `check_result` | D | `fingerprint_collision` | none |
| `IssueCreated` | WF-007 | `issue` | C | `none` | none |
| `IssueDisputed` | WF-007 | `adjudication_case` | C | `adjudication` | none |
| `IssueAdjudicationAssigned` | WF-007 | `adjudication_case` | ST | `adjudication` | none |
| `IssueAdjudicated` | WF-007 | `adjudication_case` | ST | `adjudication` | transition |
| `IssueDisputeWithdrawn` | WF-007 | `adjudication_case` | ST | `adjudication` | none |
| `IssueAdjudicationOverdue`, `IssueAdjudicationReminder`, `IssueAdjudicationCritical` | WF-007 | `adjudication_case` | D | `adjudication_sla` | decision |
| `IssueFingerprintCollision` | unavailable | unavailable | unavailable | deferred under `UPSTREAM-V1-ISSUE-COLLISION-013` | unavailable |
| `EvidenceValidationChanged` | WF-007/WF-008 | `evidence` | D | `evidence_validation` | decision |
| `ScoreSnapshotCreated` | WF-008 | `score_snapshot` | C | `score_snapshot` | none |
| `ScoreSnapshotPromoted`, `ScoreCalculationUnavailable`, `ScoreRecalculated` | WF-008/WF-011 | `current_score_projection` | PJ | `score_projection` | projection |
| `RecommendationArtifactGenerated` | WF-009 | `recommendation_artifact` | C | `none` | none |
| `RecommendationPublished` | WF-009 | `recommendation_artifact` | ST | `none` | none |
| `RecommendationSuppressed`, `RecommendationRetired` | WF-009 | `recommendation_artifact` | ST | `none` | transition |
| `AIResponseRequested` | WF-009 | `ai_response` | C | `ai_response` | none |
| `AIResponseGenerated`, `AIResponseValidated` | WF-009 | `ai_response` | ST or R | `ai_response` | none |
| `AIResponseRejected`, `AIResponseExpired` | WF-009 | `ai_response` | ST | `ai_response` | transition |
| `CitationProposed` | WF-009 | `citation` | C | `citation` | none |
| `CitationVerified` | WF-009 | `citation` | ST or R | `citation` | none |
| `CitationInvalidated`, `CitationSuperseded` | WF-009 | `citation` | ST | `citation` | transition |
| `AIResponseFingerprintCollision` | WF-009 | `ai_response` | D | `fingerprint_collision` | none |
| `CitationFingerprintCollision` | WF-009 | `citation` | D | `fingerprint_collision` | none |
| `RecommendationPrioritized` | WF-010 | `recommendation_artifact` | D | `priority_decision` | none |
| `ActionQueuePublished` | WF-010 | `action_queue_projection_version` | PJ | `action_queue` | projection |
| `ReassessmentSchedulePolicyActivated` | WF-011 | `policy_artifact` | P | `none` | none |
| `ReassessmentScheduleEvaluated` | WF-011 | `scheduled_action` | D | `schedule_decision` | decision |
| `ReassessmentCompleted` | WF-011 | `reassessment_result` | C | `reassessment` | none |
| `ReassessmentFailed`, `ReassessmentCanceled` | WF-011 | `reassessment_result` | C | `reassessment` | result |
| `IssueSuperseded`, `IssueResolved` | WF-011 | `issue` | ST | `none` | transition |
| `InvitationApprovalRequested` | WF-013 | `invitation` | C | `none` | none |
| `InvitationActivated` | WF-013 | `invitation` | C or ST | `none` | none |
| `InvitationAccepted` | WF-001/WF-013 | `invitation` | ST | `none` | none |
| `InvitationDeclined`, `InvitationRejected`, `InvitationRevoked` | WF-001/WF-013 | `invitation` | ST | `none` | none |
| `InvitationExpired` | WF-001/WF-013 | `invitation` | ST | `none` | transition |
| `RoleAssignmentRequested` | WF-013 | `role_assignment` | C | `none` | none |
| `RoleRejected`, `RoleRevoked` | WF-013 | `role_assignment` | ST | `none` | none |
| `RoleExpired` | WF-013 | `role_assignment` | ST | `none` | transition |
| `RoleExpiryBlocked` | WF-013 | unavailable | unavailable | deferred under `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` | unavailable |
| `AccessPolicySuperseded`, `AccessPolicyRetired` | WF-013 | `access_policy` | ST | `none` | transition |
| `SupportSessionRequested` | WF-013 | `support_session` | C | `none` | none |
| `SupportSessionActivated` | WF-013 | `support_session` | ST | `none` | none |
| `SupportSessionRejected`, `SupportSessionRevoked` | WF-013 | `support_session` | ST | `none` | none |
| `SupportSessionExpired` | WF-013 | `support_session` | ST | `none` | transition |
| `AccountSuspended`, `AccountReactivated`, `AccountRevoked` | WF-013 | `account` | ST | `none` | none |
| `SessionRevoked`, `SessionExpired` | WF-001/WF-013 | `session` | ST | `none` | transition; standalone explicit revocation deferred under `UPSTREAM-V1-SESSION-REVOCATION-002` |
| `OrganizationSuspended`, `OrganizationReactivated`, `OrganizationClosed` | WF-013 | `organization` | ST | `none` | none |
| `OrganizationClosureRequested` | WF-013 | `organization_closure_request` | C | `none` | none |
| `OrganizationClosureApproved` | WF-013 | `organization_closure_request` | ST | `none` | none |
| `OrganizationClosureRejected` | WF-013 | `organization_closure_request` | ST | `none` | none |
| `OrganizationClosureExpired` | WF-013 | `organization_closure_request` | ST | `none` | transition |
| `LegalHoldRequested` | WF-013 | `legal_hold` | C | `none` | none |
| `LegalHoldActivated` | WF-013 | `legal_hold` | ST | `none` | none |
| `LegalHoldRejected` | WF-013 | `legal_hold` | ST | `none` | transition |
| `LegalHoldReleased` | WF-013 | `legal_hold` | ST | `none` | none |
| `AccountDeletionRequested`, `OrganizationDeletionRequested` | WF-013 | `lifecycle_deletion_job` | C | `deletion_job` | none |
| `AccountDeletionBlocked`, `OrganizationDeletionBlocked`, `LifecycleDeletionFailed` | WF-013 | `lifecycle_deletion_job` | ST | `deletion_job` | transition |
| `AccountDeletionCompleted`, `OrganizationDeletionCompleted` | WF-013 | `lifecycle_deletion_job` | ST or R | `deletion_job` | none |
| `IntegrationProposed` | WF-014 | `integration` | C | `integration_attempt` | none |
| `IntegrationConnected` | WF-014 | `integration` | ST or R | `integration_attempt` | none |
| `IntegrationDegraded`, `IntegrationDisconnected`, `IntegrationRetired` | WF-014 | `integration` | ST | `integration_attempt` | transition |
| `CredentialProvisioned` | WF-014 | `credential` | C | `integration_attempt` | none |
| `CredentialActivated` | WF-014 | `credential` | ST or R | `integration_attempt` | none |
| `CredentialRevoked`, `CredentialExpired` | WF-014 | `credential` | ST | `integration_attempt` | transition |
| `CredentialRotationStarted`, `CredentialRotated` | WF-014 | `credential` | unavailable | unavailable under `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` | unavailable |
| `NotificationPolicyActivated` | WF-014 | `policy_artifact` | P | `none` | none |
| `NotificationCreated` | WF-014 | `notification` | C | `notification_aggregate` | none |
| `NotificationDeliveryAttempted` | WF-014 | `delivery` | A | `notification_delivery_attempt` | attempt |
| `NotificationDeliveryAccepted`, `NotificationDelivered`, `NotificationDeliveryReconciled` | WF-014 | `delivery` | ST or R | `notification_delivery` | none |
| `NotificationRetryScheduled`, `NotificationDeliveryAcceptanceUnknown`, `NotificationDeliverySuppressed`, `NotificationDeliveryFailed` | WF-014 | `delivery` | ST | `notification_delivery` | transition |
| `NotificationSent` | WF-014 | `notification` | ST | `notification_aggregate` | none |
| `NotificationUncertain`, `NotificationPartial`, `NotificationFailed`, `NotificationSuppressed` | WF-014 | `notification` | ST | `notification_aggregate` | transition |
| `NotificationEscalated` | WF-014 | `notification` | D | `notification_escalation_decision` | decision |
| `NotificationReplayRequested` | WF-014 | `notification` | D | `notification_replay_decision` | none |
| `EntitlementChecked`, `EntitlementWarningIssued`, `EntitlementViolationDetected` | WF-015 | `organization` | D | `entitlement_decision` | decision |
| `EntitlementReserved` | WF-015 | `entitlement_reservation` | C | `entitlement_reservation` | none |
| `EntitlementExecutionStarted`, `EntitlementCommitted`, `EntitlementReleased` | WF-015 | `entitlement_reservation` | ST | `entitlement_reservation` | none |
| `EntitlementReservationExpired` | WF-015 | `entitlement_reservation` | ST | `entitlement_reservation` | transition |
| `EntitlementLeaseRenewed` | WF-015 | `entitlement_lease_heartbeat` | C | `entitlement_lease_heartbeat` | none |
| `ExportPolicyActivated` | WF-016 | `policy_artifact` | P | `none` | none |
| `ExportRequested` | WF-016 | `export` | C | `export` | none |
| `ExportGenerating`, `ExportAvailable` | WF-016 | `export` | ST or R | `export` | none |
| `ExportFailed`, `ExportExpired` | WF-016 | `export` | ST | `export` | transition |
| `ExportRevoked` | WF-016 | `export` | ST | `export` | none |
| `ExportRetrieved` | WF-016 | `export_retrieval` | ST | `export_retrieval` | none |
| `IncidentRaised` | WF-017 | `incident` | C | `incident` | none; platform-wide emission unavailable under `UPSTREAM-V1-EVENT-SCOPE-001` |
| `IncidentSeverityAssigned` | WF-017 | `incident` | D | `incident_severity_decision` | decision |
| `SecurityIncidentCustomerActionRequired` | WF-017 | `incident` | D | `incident_customer_action` | decision |
| `IncidentRecoveryStepStarted` | WF-017 | `incident_step_attempt` | C | `incident_step` | none |
| `IncidentRecoveryStepCompleted` | WF-017 | `incident_step_attempt` | ST or R | `incident_step` | none |
| `IncidentRecoveryFailed` | WF-017 | `incident_step_attempt` | ST | `incident_step` | transition |
| `IncidentMitigated`, `IncidentResolved` | WF-017 | `incident` | ST | `incident` | none |
| `IncidentRestorationVerified` | WF-017 | `incident_restoration_check` | C | `incident_restoration_check` | none |
| `SecurityInvestigationOpened` | WF-018 | `investigation` | C | `investigation` | none; unavailable under `UPSTREAM-V1-EVENT-SCOPE-001` |
| `InvestigationAuditEvidenceCollected`, `InvestigationGapRecorded` | WF-018 | `investigation_input` | C | `investigation_input` | unavailable under `UPSTREAM-V1-EVENT-SCOPE-001` |
| `SecurityInvestigationReported`, `SecurityInvestigationClosed` | WF-018 | `investigation` | ST | `investigation` | unavailable under `UPSTREAM-V1-EVENT-SCOPE-001` |

Every WF-017 row above is available only for a single-Organization Incident. The same event type for a platform-wide Incident is unavailable under `UPSTREAM-V1-EVENT-SCOPE-001`; a publisher cannot choose one Organization, duplicate the event per tenant or omit the tenant field.

### Closed profile payloads

Each selected profile has the exact base members below, followed by exactly the members in its catalogue-selected extra schema. An extra schema may narrow a base member to an event-specific literal/enum or require equality with another retained field, but it never appends or redeclares a base member. `none` adds no members. There is no free-form `details`, `metadata`, `attributes` or extension object.

| Profile | Exact `event_payload` members and dependencies |
| --- | --- |
| `created` | Base members are `from_state: null`, `to_state: EventStateCode`, `prior_aggregate_version: null`, and `committed_aggregate_version: uint53`. Committed version equals root `aggregate_version`; root `input_hash` is nonnull. |
| `state_transition` | Base members are `from_state: EventStateCode`, `to_state: EventStateCode`, `prior_aggregate_version: uint53`, `committed_aggregate_version: uint53`, and `transition_reason_code: nullable EventReasonCode`; committed version equals root aggregate version and prior is lower. This field copies only an exact machine `transition_reason_code` retained separately from human reason/rationale; it is null where the catalogue source is `none`. Root `reason_code` equals it exactly when the catalogue source is `transition`. |
| `attempt` | Base members are `stage_or_operation: EventStageCode`, `attempt_number: uint53`, `replay_generation: uint53`, `started_at_utc: instant`, `completed_at_utc: instant`, `deadline_at_utc: instant`, `terminal_outcome: enum{succeeded,failed,acceptance_unknown,suppressed}`, `sanitized_reason_code: nullable EventReasonCode`, `provider_call_occurred: bool`, and `provider_call_id_sha256: nullable sha256`; attempt number is positive, times are ordered, and provider digest is nonnull exactly when a call occurred. The sanitized reason is an exact retained machine code, never sanitized prose; root reason equals it for catalogue source `attempt`. |
| `decision` | Base members are `decision_type: ascii[1..120]`, `decision_id: uuid`, `subject: object<EventEntityRef>`, `decision_value: ascii[1..120]`, `decision_status: ascii[1..120]`, `decision_reason_code: nullable EventReasonCode`, `authority_actor_id: nullable uuid`, `authority_service_identity_id: nullable uuid`, and `definition_versions: array<object<EventGoverningVersion>>[1..*] sorted-unique`. The three decision tokens exactly copy the selected immutable decision record named by the extra schema; exactly one authority is nonnull and both root hashes are nonnull. `decision_reason_code` is only an exact retained machine code and root reason equals it for catalogue source `decision`; submitted/manual rationale never enters either field. |
| `policy_activation` | Exactly `policy_type: EventArtifactType`, `policy_id: uuid`, `new_version: ascii[1..120]`, `new_content_sha256: sha256`, `prior_policy_id: nullable uuid`, `prior_version: nullable ascii[1..120]`, `activated_at_utc: instant`, `activation_mode: enum{immediate}`, `approver_actor_id: nullable uuid`, `approver_service_identity_id: nullable uuid`, and `approval_artifact_id: nullable uuid`. Prior ID/version are both null only on first activation; exactly one approver/approval-artifact form is nonnull. |
| `projection` | Base members are `source_records: array<object<EventImmutableRecord>>[1..*] sorted-unique`, `prior_projection_version: nullable uint53`, `prior_pointers: array<object<EventPointer>>[0..*] sorted-unique`, `resulting_projection_version: uint53`, `resulting_pointers: array<object<EventPointer>>[0..*] sorted-unique`, `resulting_status: EventStateCode`, `unavailable_reason_codes: array<EventReasonCode>[0..*]` in the source contract's fixed order, and `redaction_codes: array<ascii[1..120]>[0..*] sorted-unique`. Root `reason_code` equals the first unavailable reason, or null when the array is empty. |
| `failure` | Base members are `command_or_stage_id: uuid`, `failure_result: object<FailureEventResult>`, `affected_existing_target: nullable object<EventEntityRef>`, `side_effect_count: uint53`, `preserved_partial_subset: array<object<EventEntityRef>>[0..*] sorted-unique`, `coverage_status: nullable EventStateCode`, and `coverage_reason_codes: array<EventReasonCode>[0..*]` in contract order. A failed create has null target. Side-effect count is zero with empty subset/null coverage unless the selected extra schema expressly permits a preserved subset, in which case count equals its cardinality. |
| `recovery` | Discriminated by `base_profile: enum{state_transition,attempt}` and contains exactly that base profile's complete members and selected extra schema plus `recovery_of_id: uuid`, positive `recovery_generation: uint53`, `recovery_command_id: uuid`, and `earlier_terminal_reason_code: EventReasonCode`. Root command ID equals the recovery command; first-attempt events cannot use this profile. `earlier_terminal_reason_code` preserves the earlier machine failure code for lineage but never becomes the successful recovery event's root reason. |

`FailureEventResult` contains exactly `result_id: uuid` and every member of the physical failure attributes object in Terminal Command Results And Responses, using the command's selected closed failure `result_payload`; it contains no HTTP status/header, transport error, target reference or internal diagnostic.

The extra schemas are closed and append these exact members:

| Schema | Exact additional `event_payload` members |
| --- | --- |
| `none` | none |
| `billing_transition` | `lifecycle_reason: enum{bootstrap_materialization,bootstrap_activation,organization_closure}` |
| `session_creation` | `creation_reason: enum{self_service_bootstrap,invitation_acceptance,existing_account_sign_in}` and `destination: object<LogicalDestination>` |
| `source_verification_attempt` | Constrains base `stage_or_operation=source_verification_observation`; appends `verification_request_id: uuid`, `source_id: uuid`, `method: enum{dns_txt,http_file}`, `observation_number: uint53`, and `observation_outcome: enum{matched,mismatched,dependency_unavailable,timeout}`. |
| `crawl_terminal` | `coverage_status: nullable enum{full,partial}`, `completion_reason: nullable enum{completed,limit_reached,partial_source_failure,canceled,failed}`, and `accepted_document_count: uint53`; values are null/zero before terminal derivation |
| `crawl_limit_decision` | Base `decision_id` is the immutable `crawl_limit_decisions.id`, `decision_type=crawl_limit_observation`, `subject` is the affected Crawl, `decision_value=soft_reached` for `CrawlSoftLimitApproaching` or `hard_reached` for `CrawlLimitReached`, `decision_status=final`, and `decision_reason_code` is null for soft or `limit_reached` for hard. Authority is the crawler service identity; `definition_versions` is exactly the pinned global/Organization/Project Crawl Policy set and root input/output hashes equal the decision row. Appends `limit_dimension: enum{accepted_pages_per_run,discovered_url_queue,crawl_depth_from_source_root,accounted_response_body_bytes_per_run,response_body_per_url,wall_clock_run_duration,redirects_per_url,request_rate_per_canonical_host,concurrent_requests_per_canonical_host,connection_plus_response_time_per_request,sitemap_documents_per_run,sitemap_index_nesting_depth}`, `threshold_kind: enum{soft,hard}`, `configured_value: uint53`, `observed_value: uint53`, `affected_source_count: uint53`, and `affected_url_count: uint53`. |
| `pipeline_job` | `document_id: uuid`, `input_content_sha256: sha256`, `output_entity: nullable object<EventEntityRef>`, and `output_content_sha256: nullable sha256`; output fields are both nonnull only on success |
| `replay_request` | Appends `source_generation: uint53` and `requested_generation: uint53` to the `dead_letter -> queued` state transition. `requested_generation=source_generation+1` and `transition_reason_code=null`; a submitted replay reason remains in the restricted command/audit record and is not a machine code. The request event is not `recovery` and has no recovery members; only the eventual successful completion may select `recovery` and own recovery lineage. |
| `external_measurement` | `evidence_type: enum{external_measurement}`, `validation_status: enum{valid}`, `source_id: nullable uuid`, `measurement_set_id: uuid`, `measurement_set_version: ascii[1..120]`, and `content_sha256: sha256`; created `to_state=valid` |
| `input_readiness` | `readiness_status: enum{ready_full,ready_partial,blocked}`, `coverage_status: enum{full,partial}`, `successful_count: uint53`, `failed_count: uint53`, and `failed_entries: array<object<InputReadinessFailedEntry>>[0..*]` in the sealed Volume I evaluation-input manifest's failed-subset order. `successful_count + failed_count` equals the sealed manifest entry count, `failed_count` equals `failed_entries` cardinality, and every entry's exact retained failure reason is present. `EvaluationInputsReady` requires `readiness_status` in `ready_full,ready_partial`, created `to_state` equal to that status and root `reason_code=null`; `ready_full` additionally requires `coverage_status=full` and zero failed entries, while `ready_partial` requires `coverage_status=partial` and at least one successful entry. `EvaluationInputsBlocked` requires `readiness_status=blocked`, created `to_state=blocked` and root `reason_code=evaluation_inputs_unavailable`. |
| `evaluation_counts` | `expected_result_count: nullable uint53`, `actual_result_count: nullable uint53`, and `error_result_keys: array<sha256>[0..*] sorted-unique`; all are null/empty before terminal evaluation, and terminal completion/failure requires both counts |
| `check_execution` | Constrains base `stage_or_operation=check_execution` and root affected identity to the emitted `check_attempts.id`; appends `check_result_id: uuid`, `check_catalog_version: ascii[1..120]`, `check_definition_id: ascii[1..120]`, `check_definition_version: ascii[1..120]`, `applicability_key_sha256: sha256`, `check_result_key_sha256: sha256`, `deterministic_input_sha256: sha256`, `execution_status: enum{passed,failed,inconclusive,not_applicable,error}`, `elapsed_milliseconds: uint53`, and `retry_of_attempt_number: uint53`. |
| `check_result` | `check_catalog_version: ascii[1..120]`, `check_definition_id: ascii[1..120]`, `check_definition_version: ascii[1..120]`, `applicability_key_sha256: sha256`, `check_result_key_sha256: sha256`, `deterministic_input_sha256: sha256`, `execution_status: enum{passed,failed,inconclusive,not_applicable,error}`, `error_reason_code: nullable EventReasonCode`, `elapsed_milliseconds: uint53`, `output_sha256: sha256`, `execution_attempt_count: uint53`, and `evidence_references: array<object<EventEntityRef>>[0..*] sorted-unique`; created `to_state` equals `execution_status`. `error_reason_code` is nonnull exactly for `execution_status=error` and copies the Check Result machine code; root `reason_code` equals it. |
| `adjudication` | `issue_id: uuid`, `adjudication_case_id: uuid`, `case_type: enum{system_review,customer_dispute}`, `case_status: enum{requested,assigned,upheld,rejected,withdrawn,obsolete}`, `sla_status: enum{within_sla,overdue,critical,closed}`, and `due_at_utc: instant` |
| `adjudication_sla` | Base `decision_id` is `adjudication_sla_decisions.id`, `decision_type=adjudication_sla`, `subject` is the affected Case, `decision_value` is `overdue`, `reminder` or `critical` fixed by event type, `decision_status=final`, and `decision_reason_code` equals the retained SLA row. Authority is the adjudication lifecycle service; definition versions and input/output hashes exactly equal that row. Appends `issue_id: uuid`, `due_at_utc: instant`, `original_requested_at_utc: instant`, `sla_status: enum{overdue,critical}`, and `reminder_sequence: uint53`; critical uses the replaced reminder sequence. |
| `fingerprint_collision` | Base `decision_id` is `fingerprint_collision_decisions.id`, `decision_type=fingerprint_collision`, `decision_value=collision_detected`, `decision_status=final` and `decision_reason_code=null`. Authority is the detecting service identity; definition versions and root input/output hashes exactly equal the immutable Decision row. Appends `fingerprint_kind: enum{check_result,ai_response,citation}`, `fingerprint_sha256: sha256`, `conflicting_record: object<EventEntityRef>`, and `existing_record: object<EventEntityRef>`; both references have the selected fingerprint type and different IDs, while retained preimages remain restricted and absent. For `CheckResultFingerprintCollision`, the Check Result slot preallocates `conflicting_record.entity_id` for the affected Evaluation before execution; root affected identity and Decision `subject` equal that same conflicting identity, and `existing_record` is the prior hash-bucket Check Result. The collision fails that candidate's Evaluation before Check execution and requires no terminal Check Result. `IssueFingerprintCollision` is not admitted by this schema under `UPSTREAM-V1-ISSUE-COLLISION-013`. |
| `evidence_validation` | Constrains base `decision_type=evidence_validation`, base `decision_id` to the retained Validation Decision, `decision_value: enum{valid,quarantined,invalid}`, `decision_status=final` and `decision_reason_code` to its validation reason; appends only `prior_status: enum{valid,quarantined}`. |
| `score_snapshot` | `calculation_status: enum{complete,partial,unavailable}`, `issue_set_id: uuid`, `unavailability_reason_codes: array<EventReasonCode>[0..*]` in Score-policy precedence, and `content_sha256: sha256`; created `to_state` equals `calculation_status`. |
| `score_projection` | Constrains base `resulting_status` to `available_complete`, `available_partial` or `unavailable` and base `unavailable_reason_codes` to Score-policy precedence; appends `score_snapshot_id: nullable uuid`, `calculation_status: enum{complete,partial,unavailable}`, and `current_issue_set_id: nullable uuid`. |
| `ai_response` | `recommendation_artifact_id: uuid`, `origin_issue_id: uuid`, `request_fingerprint_sha256: sha256`, `model_version: ascii[1..120]`, `prompt_template_version: ascii[1..120]`, and `generated_content_sha256: nullable sha256` |
| `citation` | `ai_response_id: uuid`, `evidence_id: uuid`, `claim_sha256: sha256`, `fingerprint_sha256: sha256`, and `evidence_content_sha256: sha256` |
| `priority_decision` | Base `decision_id` is the per-Artifact `priority_decisions.id`, `decision_type=recommendation_priority`, `subject` is the affected Recommendation Artifact, `decision_value` is `computed_order` encoded as canonical unsigned decimal ASCII matching `0\|[1-9][0-9]*`, `decision_status=final` and `decision_reason_code=null`. Any submitted/manual explanation remains restricted retained rationale and is not serialized as a machine reason. Authority, definition versions and input/output hashes exactly equal the immutable Priority Decision. Appends `priority_policy_version: ascii[1..120]` and `decision_input_sha256: sha256`; no priority-band member exists. |
| `action_queue` | Constrains root affected entity to the immutable `action_queue_projection_version`, base `resulting_status=published`, base `resulting_projection_version` to that row's positive version, and the sole resulting `current_action_queue` pointer to that version; prior pointer/version and source records exactly match its frozen predecessor/source set. Appends `ordered_recommendation_ids: array<uuid>[0..*]` and `priority_policy_version: ascii[1..120]`. Order is the published queue order and duplicates are prohibited. |
| `schedule_decision` | Constrains base `decision_id` to the terminalized `scheduled_actions.id`, `decision_type=reassessment_schedule_slot`, `subject` to that Scheduled Action, `decision_value: enum{admitted,superseded_policy,inactive_scope,active_evaluation_conflict,ineligible}`, `decision_status=final` and `decision_reason_code` to its exact machine schedule reason. Authority is the schedule-evaluation service identity; `definition_versions` is exactly the immutable Schedule Policy and eligibility-policy version set frozen on Scheduled Action terminalization, while root input/output hashes are the canonical hashes persisted by that same terminalization. Appends `schedule_policy_id: uuid`, `schedule_policy_version: ascii[1..120]`, `slot_number: uint53`, `due_at_utc: instant`, `coalesced_first_slot_number: nullable uint53`, `coalesced_last_slot_number: nullable uint53`, and `coalesced_missed_count: uint53`. |
| `reassessment` | `trigger_kind: enum{manual,scheduled}`, `prior_evaluation_id: uuid`, `current_evaluation_id: nullable uuid`, `schedule_policy_id: nullable uuid`, `schedule_policy_version: nullable ascii[1..120]`, `schedule_slot_number: nullable uint53`, `schedule_due_at_utc: nullable instant`, `failure_stage: nullable ascii[1..120]`, and `terminal_reason_code: nullable EventReasonCode`; the four schedule members are all nonnull exactly when scheduled |
| `deletion_job` | `subject_type: enum{account,organization}`, `subject_id: uuid`, `deletion_manifest_id: nullable uuid`, `legal_hold_ids: array<uuid>[0..*] sorted-unique`, and `deletion_reason_code: nullable EventReasonCode` |
| `integration_attempt` | `adapter_id: ascii[1..120]`, `adapter_version: ascii[1..120]`, `attempt_generation: uint53`, and `credential_id: nullable uuid` |
| `notification_aggregate` | `generation: uint53`, `required_delivery_count: uint53`, `known_success_count: uint53`, `terminal_failure_count: uint53`, `suppressed_count: uint53`, and `acceptance_unknown_count: uint53` |
| `notification_delivery_attempt` | Constrains base `stage_or_operation=notification_delivery` and root affected identity to the Delivery; appends `notification_id: uuid`, `delivery_attempt_id: uuid`, `channel: enum{in_app,email}`, and `dispatch_checkpoint: enum{recorded}`. Provider-call occurrence/identifier and terminal result come only from the attempt base fields; the terminal Delivery Attempt appears in root `related_entities`. |
| `notification_delivery` | `notification_id: uuid`, `delivery_id: uuid`, `channel: enum{in_app,email}`, `attempt_id: nullable uuid`, `provider_event_id_sha256: nullable sha256`, and `acceptance_evidence_kind: enum{none,synchronous_2xx,authenticated_provider_event}` |
| `notification_escalation_decision` | Base `decision_id` is `notification_escalations.id`, `decision_type=notification_escalation`, `subject` is the affected Notification, `decision_value=escalation_required`, `decision_status=final` and reason is the retained escalation reason. Authority is the delivery service; definition versions and input/output hashes exactly equal the escalation row. Appends `generation: uint53` and `escalation_scope: enum{delivery,notification,no_authorized_recipient}`. |
| `notification_replay_decision` | Base `decision_id` is `notification_replay_acknowledgements.id`, `decision_type=notification_replay`, `subject` is the source Notification, `decision_value: enum{delivery_replay,empty_recipient_replay}`, `decision_status=acknowledged` and `decision_reason_code=null`. The submitted replay reason remains restricted retained rationale and audit evidence; it is never converted to a machine code or copied into the event. Authority is the human actor under the Support Session; definition versions and input/output hashes exactly equal the acknowledgement row. Appends `source_generation: uint53`, `requested_generation: uint53`, `source_delivery_id: nullable uuid`, and `duplicate_delivery_risk_acknowledged: bool`; `requested_generation=source_generation+1`, source Delivery is nonnull exactly for delivery replay and acknowledgment is true exactly when its state was `acceptance_unknown`. |
| `entitlement_decision` | Base `decision_id` is `entitlement_decisions.id`, `decision_type=entitlement`, `subject` is `account` for a human or `service_identity` for a machine and never Organization, `decision_value: enum{allow,allow_with_warning,block}`, `decision_status=final` and reason is the retained Entitlement Decision reason. Root affected entity is the existing Organization. Authority is the entitlement service; definition versions are exactly the pinned Plan/Entitlement Policy/approval/counter set and input/output hashes equal the decision row. Appends `operation: enum{crawl.start,reassessment.start,ai.generate,export.generate,report.view,history.view,issue.read,recommendation.read,score.read}`, `window_start_utc: instant`, `window_end_utc: instant`, `counter_before: decimal`, `counter_after: decimal`, `soft_limit: decimal`, and `hard_limit: decimal`. |
| `entitlement_reservation` | `entitlement_decision_id: uuid`, `operation: enum{crawl.start,reassessment.start,ai.generate,export.generate}`, `reserved_units: decimal`, `lease_expires_at_utc: instant`, and `retry_of_decision_id: nullable uuid` |
| `entitlement_lease_heartbeat` | Created `to_state=renewed`; appends `entitlement_reservation_id: uuid`, `heartbeat_generation: uint53`, `prior_lease_expires_at_utc: instant`, `renewed_lease_expires_at_utc: instant`, `renewed_at_utc: instant`, and `worker_service_identity_id: uuid`. Every value is copied exactly from the immutable Entitlement Lease Heartbeat row. Generation is positive, `renewed_lease_expires_at_utc` is strictly later than `prior_lease_expires_at_utc`, and `renewed_at_utc` is strictly earlier than `renewed_lease_expires_at_utc`. |
| `export` | `format: enum{pdf_report,csv_data,json_data}`, `manifest_sha256: nullable sha256`, `package_sha256: nullable sha256`, `compressed_bytes: nullable uint53`, `uncompressed_bytes: nullable uint53`, and `retrieval_expires_at_utc: nullable instant` |
| `export_retrieval` | `export_id: uuid`, `recipient_account_id: uuid`, `authorized_at_utc: instant`, and `content_sha256: sha256` |
| `incident` | `severity: enum{low,medium,high,critical}`, `playbook_version: ascii[1..120]`, and `required_customer_action: nullable ascii[1..120]` constrained to that pinned playbook |
| `incident_severity_decision` | Base `decision_id` is `incident_decisions.id`, `decision_type=incident_severity`, `subject` is the affected Incident, `decision_value: enum{low,medium,high,critical}`, `decision_status=final` and reason is the retained severity reason. Authority, Incident Playbook definitions and input/output hashes exactly equal the immutable row. Appends `playbook_version: ascii[1..120]` and `severity_predicate_sha256: sha256`. |
| `incident_customer_action` | Base `decision_id` is `incident_decisions.id`, `decision_type=incident_customer_action`, `subject` is the affected Incident, `decision_value` is an exact required-action code in the pinned Incident Playbook, `decision_status=required` and reason is the retained row reason. Authority, definitions and input/output hashes exactly equal that row. Appends `severity: enum{low,medium,high,critical}`, `playbook_version: ascii[1..120]`, and `disclosure_scope_version: ascii[1..120]`. |
| `incident_restoration_check` | Created `to_state=passed`; appends `incident_id: uuid`, `observation_number: enum{2}`, `observation_outcome: enum{passed}`, `observed_at_utc: instant`, `trigger_predicate_sha256: sha256`, `immediate_observation_sha256: sha256`, and `five_minute_observation_sha256: sha256`. |
| `incident_step` | `incident_id: uuid`, `playbook_step_id: ascii[1..120]`, `rollback_outcome: nullable enum{not_required,succeeded,failed}`, and `restoration_assertion_sha256: nullable sha256`. `IncidentRecoveryStepStarted` creates `running` and requires both nullable outcome fields null; `IncidentRecoveryStepCompleted` transitions `running -> succeeded` and requires both fields nonnull; `IncidentRecoveryFailed` transitions `running -> failed`, requires `rollback_outcome=failed` and permits the restoration assertion only when one was actually executed and retained. |
| `investigation` | `approved_organization_ids: array<uuid>[1..*] sorted-unique`, `support_session_ids: array<uuid>[1..*] sorted-unique`, and `report_id: nullable uuid` |
| `investigation_input` | `investigation_id: uuid`, `input_type: ascii[1..120]`, `coverage_status: enum{collected,gap}`, `content_sha256: nullable sha256`, and `gap_reason_code: nullable EventReasonCode`; exactly one of content digest or gap reason is nonnull |

### Notification context union and trigger table

When present, `notification_context_v1` is exactly the common object plus one variant selected by `context_variant`. Common members are `schema_version: enum{notification-context-v1}`, `context_variant: enum{invitation,source_verification,crawl,score,adjudication,entitlement,export,security_action,generic_informational}`, `organization_id: uuid`, `project_id: nullable uuid`, `affected_resource: object<EventEntityRef>`, `initiating_account_id: nullable uuid`, `initiating_service_identity_id: nullable uuid`, `current_status: EventStateCode`, `reason_code: nullable EventReasonCode`, `action_reference: object<EventEntityRef>`, `data_classification: enum{public,internal,confidential,restricted}`, and `visibility_versions: array<object<EventGoverningVersion>>[1..*] sorted-unique`. Organization/Project/resource values equal the root event; exactly one initiator is nonnull; `reason_code` equals the root reason, and the variant below fixes the status domain and action-reference type. The action reference is a type/ID pair from the producing workflow, never a free-text action label.

Variant members are exhaustive:

- `invitation` requires `current_status` in `active,accepted,declined,rejected,revoked,expired`; `action_reference.entity_type=invitation` and the affected Invitation identity; plus `invitation_id_sha256: sha256`, `invitation_reference_redacted: ascii[15..15]` equal to `inv_` plus the first 12 digest hex characters, `requester_account_id: uuid`, `target_email_sha256: sha256`, `target_account_id: nullable uuid`, `intended_role: enum{OrganizationAdmin,MarketingOperator,TechnicalImplementer,SecurityOperator,BillingOperator}`, `permission_mode: enum{standard,read_only}`, `persona: nullable enum{consultant,executive_buyer}`, `scope: object<GrantScope>`, `invitation_state` equal to `current_status`, `expires_at_utc: instant`, and `active_delivery_occurred: bool`.
- `source_verification` requires `current_status: enum{verified,expired}`; `action_reference.entity_type` in `source,verification_request` as fixed by the event type; plus `verification_request_id: uuid`, `source_id: uuid`, and `request_initiator_account_id: uuid`.
- `crawl` requires `current_status: enum{running,completed,failed}` and `action_reference.entity_type=crawl`; plus `crawl_id: uuid`, `coverage_status: enum{full,partial}`, and `completion_reason: enum{completed,limit_reached,partial_source_failure,canceled,failed}`.
- `score` requires `current_status: enum{available_partial,unavailable}` and `action_reference.entity_type=current_score_projection`; plus `score_snapshot_id: nullable uuid`, `calculation_status: enum{partial,unavailable}`, and `unavailability_reason_codes: array<EventReasonCode>[0..*]` in Score policy precedence. Snapshot is null exactly when unavailable.
- `adjudication` requires `current_status: enum{upheld,rejected,withdrawn,overdue,critical}` and `action_reference.entity_type=adjudication_case`; plus `issue_id: uuid`, `adjudication_case_id: uuid`, `requester_account_id: uuid`, `decision: enum{upheld,rejected,withdrawn,overdue,reminder,critical}`, and `due_at_utc: instant`. A reminder uses current status `overdue`.
- `entitlement` requires `current_status: enum{allow_with_warning,block}` and `action_reference.entity_type=entitlement_decision`; plus `decision_id: uuid`, `operation: enum{crawl.start,reassessment.start,ai.generate,export.generate,report.view,history.view,issue.read,recommendation.read,score.read}`, `subject_account_id: nullable uuid`, `subject_service_identity_id: nullable uuid`, `window_start_utc: instant`, `window_end_utc: instant`, `soft_limit: decimal`, `hard_limit: decimal`, and `decision_reason: EventReasonCode`. Exactly one subject is nonnull.
- `export` requires `current_status: enum{available,failed}` and `action_reference.entity_type=export`; plus `export_id: uuid`, `requester_account_id: uuid`, `export_status` equal to `current_status`, and `retrieval_expires_at_utc: nullable instant`. Expiry is nonnull exactly for available.
- `security_action` requires `current_status: enum{open,mitigated,resolved}` and `action_reference.entity_type=incident`; plus `incident_id: uuid`, `disclosure_scope_version: ascii[1..120]`, `affected_resources: array<object<EventEntityRef>>[1..*] sorted-unique`, and `required_customer_action: ascii[1..120]` exactly equal to a code in the pinned Incident Playbook.
- `generic_informational` adds no members. It is permitted only for an optional informational route explicitly present in the effective Notification Policy for an event type in the inline catalogue; `current_status` must be in that event's affected-entity state domain, and its template may reference common fields only.

The accepted notification-eligible event types and predicates are:

| Event types | Variant | Route predicate |
| --- | --- | --- |
| `InvitationActivated`, `InvitationAccepted`, `InvitationDeclined`, `InvitationRejected`, `InvitationExpired` | `invitation` | unconditional when the exact type/major is present in the effective route table |
| `InvitationRevoked` | `invitation` | `active_delivery_occurred=true` |
| `SourceVerified`, `SourceVerificationExpired` | `source_verification` | unconditional |
| `CrawlCompleted` | `crawl` | `coverage_status=partial` |
| `CrawlFailed`, `CrawlLimitReached` | `crawl` | unconditional |
| `ScoreSnapshotPromoted` | `score` | `calculation_status=partial` |
| `ScoreCalculationUnavailable` | `score` | `calculation_status=unavailable` |
| `IssueAdjudicated`, `IssueDisputeWithdrawn`, `IssueAdjudicationOverdue`, `IssueAdjudicationReminder`, `IssueAdjudicationCritical` | `adjudication` | unconditional |
| `EntitlementWarningIssued`, `EntitlementViolationDetected` | `entitlement` | unconditional |
| `ExportAvailable`, `ExportFailed` | `export` | unconditional |
| `SecurityIncidentCustomerActionRequired` | `security_action` | unconditional |

An effective policy may add/remove only Volume I-permitted informational rows. Such a row must reference an exact inline-catalogue event type at major 1 and either its fixed baseline variant/predicate above or `generic_informational`; an active policy cannot create another event/context mapping or relax a predicate. If an event matches an effective route but lacks a complete schema-valid context, event production fails before the owning commit as `F1-DATA-409 / notification_event_invalid`; it does not silently commit an unroutable mandatory/selected notification. The consumer revalidates the exact stored bytes/context so post-write corruption or unsupported major still dead-letters without a Notification write.

In the same transaction as each admitted event, the producer creates zero or one outbox route for each required consumer; every route is unique on `(event_id,consumer_name)`. There is no Kafka, external event broker, customer event stream or public event-history endpoint.

The accepted baseline has exactly one Domain Event consumer: `notification_route_v1` on the `delivery` queue. Its route exists only when the committing event type and major version occur in the effective Notification Policy route table and the event carries the complete required `notification_context_v1`. The route captures that policy/table identity with the event. If either predicate is false, the event has zero consumer rows. No naming convention, current-policy lookup, role inference or generic consumer registration may create a route after commit.

The `event_consume` Sidekiq envelope carries `work_id` equal to a restricted `work_dispatch_bindings.id` bound to exactly one outbox-route row plus the route's claim generation; it does not carry a caller-selected route or consumer. The job reloads the binding, its sole route, `consumer_name`, event bytes and digest, accepts only the supported event major/required shape, then atomically commits the idempotent notification-routing result, unique `(consumer_name,event_id)` consumption and route completion. Unknown major, digest/shape failure or missing required notification context enters `event_dead_letters` and performs no Notification product write.

All event types not matching the effective Notification Policy predicate have zero consumer rows. Pipeline/search/index/projection continuations, timers and other internal work use an explicit persisted ScheduledAction or owning work row; an implementation MUST NOT infer them as event consumers. A missing consumer route cannot be repaired by inventing one from event type after commit; correction follows the owning replay/recovery contract.

### Upstream behavioural blockers

`UPSTREAM-V1-EVENT-SCOPE-001`: Volume I makes `organization_id` mandatory in every logical event envelope. WF-001 requires `BootstrapGrantIssued` before an Organization exists, WF-017 permits a platform-wide Incident, and WF-018 permits one Investigation to span an approved Organization set. No permitted substitution or representation covers those producers. Null, an invented platform Organization, one selected Organization, duplicated per-Organization events and omission are observably different. Volume II does not select one silently. Physical emission and final DDL for those scope classes remain blocked pending controlled Volume I clarification; ordinary single-tenant events remain fully specified.

`UPSTREAM-V1-PROJECT-LIFECYCLE-003`: Volume I's state model permits `Project.Active -> Paused`, `Project.Paused -> Active`, and Active/Paused to Archived, and names `ProjectPaused`, `ProjectReactivated`, and `ProjectArchived`, but WF-002 defines only Draft to Active and the permission matrix names only `project.create` and `project.activate`. Volume II therefore exposes no pause, resume, or archive endpoint and does not assign those operations to `project.activate`. Their actor, trigger, permission, preconditions, failure result, idempotency and acceptance behavior require controlled Volume I clarification.

`UPSTREAM-V1-SESSION-REVOCATION-002` — Status: Resolved by ADR-019. OD-016 defines current-Session sign-out through `session.terminate` and single-Session security revocation through `session.revoke`, adding revoke reasons `self_sign_out` and `security_revocation`; the Session row's transition authority is named by a PM-REQ-009 controlled foundation change. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-READ-AUTHORIZATION-004` — Status: Resolved by ADR-019. OD-020 adds explicit customer-facing read rows to `permission-baseline-v1` for Organization home data, Project, Source, Crawl, Evaluation, Notification inbox and Export enumeration, each tenant-scoped and least-privilege. Read authority over security, administrative and internal operational objects — Support Session, Incident, Investigation, Legal Hold, Emergency Access Grant, deletion jobs and privileged Billing surfaces — remains deny-by-default pending a separate owner decision, so any collection exposing those objects lies outside the resolved set and stays genuinely undecided. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-LOW-COST-METERING-005` — Status: Resolved by ADR-019. OD-019 ratifies the metered-read unit, and the commercial clarification makes read limits and similar numerals versioned policy configuration bound to an approved policy version rather than Volume I constants. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-REACTIVATION-PROOF-006` — Status: Resolved by ADR-019. OD-021 ratifies Account reactivation Option 1: it proves only the acting administrator's current MFA-satisfied Session, restores state, creates no Session and consults no target identity. This is distinct from OD-022 and decides nothing about `organization.reactivate`. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-COMPARISON-EVENT-007` — Status: Resolved by ADR-019. OD-024 removes `ComparisonGenerated` as a Volume I domain event. The comparison read emits no domain event and is side-effect-free; its `compatible`, `insufficient_history`, `not_comparable` and `comparison_unavailable` outcomes remain deterministic and its audit obligations are discharged entirely by Audit Evidence with correlation ID. No route, projection or serializer may emit, suppress, deduplicate or meter the removed name. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-ORGANIZATION-REACTIVATION-PROOF-008` — Status: Resolved by ADR-019. OD-022 defines the `organization_reactivation` Identity Validation Receipt purpose: MFA-attested with the assurance version, bound to Organization ID, issuer and subject, 10-minute expiry, nonce-consumed only by the reactivation command, creating no Session. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`: Volume I requires a fresh rotation token but defines no issuing authority or operation, entropy/wire format, TTL/equality boundary, one-use consumption point, Credential/Integration/actor binding, retry/replay behavior, or exact transport for the new secret-store material reference. These choices change observable acceptance and recovery behavior. Volume II therefore exposes no `BeginCredentialRotation` route, attributes payload, scheduled substitute, `CredentialRotationStarted`, or `CredentialRotated` emission and does not invent a token. Credential revocation/expiry and Integration isolation remain available under their separate contracts.

`UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` — Status: Resolved by ADR-019. OD-025 removes `ReassessmentTriggered` as a canonical domain event through a PM-REQ-009 controlled foundation change to the WF-011 coverage row in `018 OBSERVABILITY.md`. The previously unresolvable question of whether an Entitlement-blocked branch emits a trigger event does not arise, because no trigger event exists. Provenance is retained on the Reassessment Result record and its Audit Evidence; execution stays observable through `ReassessmentScheduleEvaluated`, `EvaluationStarted`, `ReassessmentCompleted`, `ReassessmentFailed` and `ReassessmentCanceled`. No route or serializer may emit the removed name. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` — Status: Resolved by ADR-019. OD-026 defines `RoleExpiryBlockDecision` as an immutable `decision` record and binds `RoleExpiryBlocked` to exactly one producer, the role-expiry lifecycle service, with a mandatory security notification route. The Assignment remains `active` and effective past `expires_at_utc` until the guard clears; no Assignment lifecycle status is added. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-DOCUMENT-LIFECYCLE-012` — Status: Resolved by ADR-019. OD-015 removes the `quarantined` and `retired` Document states and the `DocumentQuarantined` and `DocumentRetired` events through a PM-REQ-009 controlled foundation change to `016 STATE_MODEL.md`. The Document lifecycle is `discovered -> ingested -> parsed -> indexed` and `indexed` is terminal. The states are removed rather than reserved, so no migration shape, route, job or event may admit either. Evidence quarantine is a separate, unaffected state machine. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

`UPSTREAM-V1-ISSUE-COLLISION-013` — Status: Resolved by ADR-019. OD-017 fixes the collision outcome: on an Issue fingerprint collision the second Issue MUST NOT be created and the affected Evaluation fails closed using the existing canonical collision outcome and telemetry. No alternative duplicate Issue may be silently persisted. The semantic contract is now canonical in Volume I. Any corresponding API surface, transport contract, routing, serialization or application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

## Versioning And Compatibility

- `/api/v1` and media `version=1` are one physical major. A breaking required-field/type/meaning change creates `/api/v2`; it never changes v1 in place.
- Same-major additions are optional, explicitly documented and absent by default until consumers prove tolerance. Renaming, repurposing or changing nullability is breaking.
- Command, result and event logical schema versions remain separately visible inside the physical major.
- A deprecated endpoint returns `Deprecation: true`, `Sunset`, and a successor `Link` for at least one accepted client release window. It remains behaviorally compatible until removal in the next physical major.
- Generated OpenAPI 3.1 and JSON Schema artifacts are derived from these route/command registries during implementation. Generated artifacts are verification output, not a competing authority.

## Prohibited Alternatives

- No GraphQL, generic CRUD controller, `resources` route inferred beyond this catalogue, offset pagination or public API token.
- No controller writes Active Record directly or calls another HTTP endpoint in the same application.
- No HTTP proxy, SDK or browser automatically retries a mutation.
- No provider callback trusts a body before signature and replay validation.
- No unredacted DTO, raw Evidence payload, credential, identity receipt, Session token or internal exception appears in an API response.
- No AI narrative field or placeholder appears in dashboard or history JSON.
