# Volume II External Integration Contracts

## Status And Scope

- Status: Volume II implementation contract
- Behavioral baseline: Git tag `v1.3-volume-i-corrected`
- Active tenant Integration kind: `mailgun_email`
- Active platform boundaries: managed identity receipt validation, approved-service JWT authentication, and domain verification

This document fixes physical adapter, authentication, timeout, retry, rate, failure, secret, and monitoring behavior. It does not activate a dormant provider, add a connector, or change any logical provider outcome defined by Volume I.

Behavioral authority remains:

- [Workflow Specifications](../volume-i/WORKFLOW_SPECIFICATIONS.md)
- [Score And Evidence Model](../volume-i/SCORE_EVIDENCE_MODEL.md)
- [System Boundaries](../012%20SYSTEM_BOUNDARIES.md)
- [Security Model](../014%20SECURITY_MODEL.md)
- [Error Model](../017%20ERROR_MODEL.md)

## Provider Classification

| Provider or boundary | Baseline classification | Physical implementation permitted |
| --- | --- | --- |
| Mailgun | Active `mailgun_email` tenant Integration under `mailgun-email-v1` | Send API, Events API, authenticated webhooks, Credential lifecycle |
| Managed Identity Receipt Service | Active platform identity boundary; never a tenant Integration | signed receipt validation and managed key discovery |
| Approved Service Identity | Active platform authentication boundary; never a tenant Integration | signed short-lived JWT validation for `/service/v1` only |
| DNS/HTTPS domain verification | Active platform network boundary; never a tenant Integration | DNS TXT and exact HTTPS-file observation |
| AWS S3, KMS and Secrets Manager | Active platform infrastructure dependencies | private object storage, encryption and exact-version Credential material resolution only |
| Datadog | Active platform observability dependency | logs, metrics, traces, synthetics and error reporting only |
| Stripe | Dormant `billing_adapter` candidate | policy-unavailable guard only; no SDK, route, webhook, Credential, job, call, or environment variable |
| OpenAI | Dormant `ai_provider_adapter` candidate | policy-unavailable guard only |
| Anthropic | Dormant `ai_provider_adapter` candidate | policy-unavailable guard only |
| OpenRouter | Dormant `ai_provider_adapter` candidate | policy-unavailable guard only |
| Google identity, search, AI, webmaster, performance, or local APIs | Dormant and unselected | no SDK, route, Credential, job, call, or environment variable |
| Search providers generally | Dormant `external_measurement_adapter` candidates pending an approved Measurement Set | no collection or network call |
| Mux | Unsupported; no admitted logical kind or Volume I capability | no package, adapter, table row, route, job, Credential, call, or environment variable |

Dormant does not mean feature-flagged. No feature flag, tenant setting, provider credential, environment variable, code path, or provider availability may activate a dormant provider. Activation requires the exact signed artifacts and controlled behavior required by Volume I.

## Common Adapter Boundary

Every active adapter implements a caller-owned port and returns only F1 normalized value objects. Vendor SDK classes, raw provider errors, response bodies, HTTP clients, and credentials MUST NOT cross the adapter boundary.

Every outbound operation has:

- immutable adapter ID, semantic version, code digest, policy ID/version/digest, and operation name;
- Organization and Project scope where applicable;
- Credential and material version identifiers where applicable;
- absolute monotonic elapsed deadline and separately recorded PostgreSQL deadline;
- request semantic digest, correlation ID, product attempt identity, and external-effect checkpoint;
- normalized outcome, certainty, provider status where allowed, sanitized reason, byte counts, and completion time; and
- an explicit declaration of whether provider submission could have begun.

### HTTP and DNS rules

- TLS certificate and hostname verification are mandatory. TLS verification cannot be disabled by configuration.
- Provider base hosts come only from signed adapter policy or the exact environment allowlist in this document. User-supplied endpoints are prohibited.
- Redirects are rejected unless the active adapter section expressly permits and revalidates them.
- HTTP clients have automatic retry, redirect, cookie persistence and response-body logging disabled.
- A provider call runs outside a database transaction after its durable checkpoint.
- Response reading is bounded by the adapter's exact byte limit. Excess bytes are not retained.
- Provider error text is reduced to a bounded reason code and restricted diagnostic digest. It never enters a result, event, Evidence, Notification, Export, or ordinary log.
- DNS resolution and every connection apply the relevant destination-safety rule. Provider adapters pin an allowed address for one attempt and verify the transport peer.

### Retry ownership

Provider SDK and transport retries are always zero. Volume I or [Background Processing](BACKGROUND_PROCESSING.md) owns every allowed retry and due time. A retry allocates or reuses only the product attempt identity permitted by its owning contract.

### Rate behavior

An adapter may enforce a safety concurrency cap but cannot fabricate a customer entitlement or a provider retry. Provider `429` is normalized under the owning contract. A local safety delay persists a scheduled action; it never sleeps in a worker.

### Secret handling

- F1 stores only an AWS Secrets Manager Secret ARN, exact VersionId and material digest in PostgreSQL.
- Secret bytes are fetched only after the protected provider checkpoint authorizes the current Credential version.
- Secret bytes remain in process memory for one call, are never memoized globally, and references are cleared immediately afterward.
- Logs, traces, exception reporting and job arguments contain no secret value, request authorization header, verification token, raw webhook signature or provider body.
- Infrastructure bootstrap credentials are Heroku secrets; tenant provider material is never copied into a Heroku config variable.

#### AWS Secrets Manager resolution

The credential-material reference is exactly `(secret_arn,version_id,secret_sha256)`. `secret_arn` must be an environment-allowlisted Secrets Manager ARN in `AWS_REGION`; `version_id` is 32-64 hexadecimal characters; the request calls `GetSecretValue` with `SecretId=secret_arn` and `VersionId=version_id` and omits `VersionStage`. Endpoint override, cross-region resolution, resource-name lookup, “AWSCURRENT” selection, list/search, batch retrieval and fallback version are prohibited.

The AWS client has SDK retry count zero, a two-second connect ceiling and three-second absolute call deadline inside the Volume I ten-second Integration-initialization deadline. A transient transport timeout or AWS dependency/unavailable result maps to `adapter_initialization_timeout` or `adapter_dependency_unavailable` and receives only Volume I's one retry exactly one second after that initialization attempt terminalizes. Access denial, wrong account/region/ARN or malformed response is `adapter_configuration_invalid`; missing Secret/VersionId, destroyed/disabled version, binary-only value, empty/over-4-KiB value or SHA-256 mismatch is `credential_unavailable`. Those configuration/Credential results are nonretryable for the Delivery attempt and make no Mailgun call.

Only UTF-8 `SecretString` bytes from 1 through 4,096 bytes are admitted. Their SHA-256 must equal the immutable material digest before use. Bytes exist in one adapter-scoped mutable buffer, are never logged/cached/serialized and are overwritten/released after the single operation. AWS credentials authorize only `secretsmanager:GetSecretValue` on the exact environment ARN set plus the exact S3/KMS operations in Deployment; list, create, update and delete are denied to runtime roles.

### Monitoring

Every adapter emits bounded metrics for calls, latency, normalized outcome, timeout, rate-limit, dependency failure, authentication failure, circuit state, response size, and redaction failure. Organization IDs and provider message IDs are trace/log fields, not metric labels.

No circuit breaker may return a success or invent a provider result. An open circuit returns the adapter's existing dependency-unavailable result before a network call and uses only a retry already authorized by the owning workflow.

## Approved Service JWT Boundary

`/service/v1` accepts only `Authorization: Bearer <compact-JWS>`. A browser Session, identity receipt, API key, opaque bearer token, tenant Credential or provider webhook signature is never accepted on this surface.

The compact JWS protected header is exactly `alg=ES256`, `typ=JWT` and nonblank `kid`. `crit`, embedded JWK, X.509 fields, an unprotected header, duplicate JSON member or any other protected header is rejected. The active signed `service-jwt-key-v1` release artifact maps `kid` to one P-256 public JWK, fixed issuer, key version, activation instant and optional retirement instant; runtime cannot fetch a key from a JWT-supplied URL. Private signing material never enters F1.

The claim set is exact:

| Claim | Contract |
| --- | --- |
| `iss` | byte-equal to the key artifact's fixed issuer |
| `aud` | one string equal to canonical `APP_BASE_URL` plus `/service/v1` |
| `sub` | byte-equal to one active `service_identities.subject` bound to the header key |
| `jti` | canonical UUIDv7, nonblank and unique except exact request replay |
| `iat` | integer NumericDate no more than 30 seconds in the future |
| `exp` | integer NumericDate exactly 120 seconds after `iat`; at equality expiry wins |
| `organization_id` | canonical UUID or JSON null, exactly matching the service identity's fixed Organization scope |
| `project_id` | canonical UUID or JSON null; nonnull only with a matching nonnull Organization and fixed Project scope |
| `permission_scope_sha256` | 64 lowercase hexadecimal characters matching the canonical active service scope digest |
| `key_version` | byte-equal to the active/overlap release-artifact version |

Unknown or missing claims, an array audience, noninteger NumericDate, lifetime other than 120 seconds, unsupported/retired key, invalid signature, inactive service identity, scope mismatch or server time at/after `exp` returns generic `F1-AUTHN-401 / authentication_failed` before command construction. Restricted audit records the exact reason without token bytes or claims containing tenant data.

The first valid use atomically inserts one immutable `service_jwt_bindings` row keyed by `(issuer,jti)` with the service identity, key version, JWT digest, `X-F1-Command-ID`, canonical request digest and expiry. Reuse is admitted only when all those values are byte-identical and follows normal command idempotency/current authorization; any other reuse is `authentication_failed` and creates no command. The binding is retained through JWT expiry plus the command-idempotency evidence lifetime. Thus response-loss replay remains possible without making one JWT a general multi-command bearer.

Every accepted request still resolves the current service identity state, Organization/Project scope, permission, policy and command binding after signature validation. Key overlap admits old and new verification keys only during the signed overlap interval; a new request must use the version named in its token, and retirement immediately rejects that key for new authentication. Metrics cover bounded validation outcome, key version, expiry/replay class and latency; JWT, `jti`, subject, Organization and Project are never metric labels or ordinary log values.

## Mailgun Adapter `mailgun-email-v1`

### Physical identity and endpoints

- Adapter ID: `mailgun-email`
- Adapter major version: `1`
- Send endpoint: `POST {MAILGUN_API_BASE}/v3/{MAILGUN_SENDING_DOMAIN}/messages`
- Events endpoint: `GET {MAILGUN_API_BASE}/v3/{MAILGUN_SENDING_DOMAIN}/events`
- `MAILGUN_API_BASE` is exactly `https://api.mailgun.net` or `https://api.eu.mailgun.net` and must match the signed policy.
- No other scheme, host, port, path prefix, tenant override, or redirect is permitted.

### Authentication and secret material

Send and event-history requests use HTTPS Basic authentication with username `api` and the active secret material referenced by the Organization Credential. The API key is loaded from AWS Secrets Manager by its exact Secret ARN and VersionId. Webhook authentication uses the separately versioned Mailgun webhook signing key through the same resolver contract.

Credential initialization, rotation, expiry, revocation, disconnect, recovery and retirement are exactly those in `integration-interim-v1`. A disconnected/retired Integration or unavailable/invalid/revoked/expired Credential causes no Mailgun call.

The signed restricted `mailgun-email-v1` release artifact is the only initial material-reference authority. It contains the allowed sending domain plus the initial API-key and webhook-key `(secret_arn,version_id,secret_sha256,secret_type)` references, never secret bytes. Lazy Organization Integration initialization copies the exact platform-managed API-key reference into its immutable per-Organization Credential material-version row after artifact signature/hash and Secret value validation. Multiple initial Credential rows intentionally may name that same immutable reference; Organization isolation is enforced by the Credential/attempt rows and the reference is never customer-visible. Webhook authentication resolves the artifact's exact webhook-key reference before untrusted request content is used to locate an Organization.

No enabled baseline path replaces or destroys that shared initial secret-store version. `BeginCredentialRotation` and its material intake remain unreachable under [`UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`](APPLICATION_LAYER.md#upstream-v1-credential-rotation-token-009); a controlled correction and matching Volume II revision must define per-Credential versus coordinated shared-material replacement, safe old-version destruction and migration before rotation can be enabled. No fallback environment secret reference and no `MAILGUN_*_SECRET_ARN` or VersionId environment variable exists.

### Send request

The rendered, authorized Delivery supplies exactly one recipient, one approved sender, subject, text body, optional HTML body only when the approved template defines it, and these Mailgun user variables:

- `f1_delivery_token`: the opaque correlation token;
- `f1_delivery_id`: the Delivery UUID;
- `f1_replay_generation`: unsigned decimal generation; and
- `f1_schema_version`: `mailgun-delivery-v1`.

The user-variable values are evidence locators, not provider idempotency keys. The application stores only their digests where Volume I prohibits plaintext retention. The adapter MUST NOT set a provider option that changes Mailgun recipient expansion, tracking, retry or unsubscribe semantics outside the approved template/policy.

### Checkpoint and timeout

The caller durably commits `prepared`, validates the exact Integration/Credential/material, and commits `submission_started` before opening the request body. The transport performs one network submission operation.

The absolute elapsed deadline is ten seconds from the start of DNS resolution. Component ceilings are two seconds for DNS/TCP/TLS connection, three seconds for request write, and the remaining absolute budget for response headers/body. A component timeout cannot extend the absolute deadline. At or after the deadline, timeout wins.

A process loss or any incomplete result after `submission_started` maps to `acceptance_unknown`; the adapter never repeats the request. Only a result that proves no network submission began may enter the definitive-nonacceptance retry path.

### Response and retry mapping

Response mapping is exactly WF-014:

- complete `2xx`: `accepted`;
- complete `429`: definitive nonacceptance and the declared Delivery retry;
- complete non-`408`, non-`429` `4xx`: terminal failure;
- `408`, `5xx`, malformed or partial response, connection loss, process loss, or indeterminate write: `acceptance_unknown`;
- provider/client automatic retry: prohibited.

`Retry-After` is accepted only as the Volume I unsigned delta-seconds value from 60 through 1,800. HTTP date and every other form are ignored.

The sending-domain safety cap is four concurrently open Mailgun network calls per application environment. The dispatcher delays excess eligible work through PostgreSQL in FIFO order `(due_at,delivery_id,attempt_number)` without changing its product due time. The provider `429` contract remains authoritative.

### Webhook ingress

The webhook endpoint accepts HTTPS `POST` with `Content-Type: application/json` only and has a 256 KiB uncompressed-body ceiling. Transfer or content encoding, duplicate JSON members, invalid UTF-8, a non-object root, and trailing non-whitespace bytes are invalid. The accepted root has exactly two required object members, `signature` and `event-data`; additional root members are invalid. Before using event data it validates:

1. `signature` contains exactly string `timestamp`, `token`, and `signature` members; timestamp is unsigned decimal epoch seconds, token is 50 lowercase hexadecimal characters, and signature is 64 lowercase hexadecimal characters;
2. the signature timestamp is within the closed interval from five minutes before through five minutes after PostgreSQL receive time;
3. the supplied signature equals, in constant time, lowercase hexadecimal HMAC-SHA256 over the exact ASCII bytes `timestamp || token` using an active or rotation-overlap webhook key;
4. the token SHA-256 has not authenticated different content inside the five-minute window; and
5. `event-data` contains string `id` of 1-255 UTF-8 bytes, string `event` of 1-64 ASCII characters, finite numeric epoch-seconds `timestamp`, string `recipient`, object `message` with object `headers` containing string `message-id`, and object `user-variables`. The required user variables are the four exact strings sent by this adapter. `f1_delivery_id` is a canonical UUID, `f1_replay_generation` is unsigned decimal, and `f1_schema_version` is `mailgun-delivery-v1`. `severity` is an optional string used only for a `failed` event. Unknown `event-data`, `message`, `headers`, and `user-variables` members are ignored for state but are covered by the authenticated normalized-content digest.

The normalized content is canonical JSON containing only provider event ID/type/time, message ID, normalized recipient, the four required F1 variables, and nullable severity. The recipient is normalized by `onboarding-interim-v1` and must match the Delivery recipient digest; event time is stored as a microsecond UTC instant by decimal conversion without binary floating-point. The first successful transaction atomically inserts the webhook-token binding, provider-event registry/event row and due-now `provider_event_consume` Scheduled Action. Exact authenticated replay of the same token/content or exact duplicate event ID/content is acknowledged without another action. Reuse of a token or event ID with different normalized content persists the applicable conflict when authentication and tenant binding are provable, produces the WF-014 ambiguous condition, and never replaces the first event.

The response contract deliberately uses Mailgun's provider acknowledgment meanings: only `200` acknowledges success, `406` rejects without retry, and `503` asks for provider retry where that Mailgun event class supports it. Every response is `text/plain; charset=utf-8`, has `Cache-Control: no-store`, and contains exactly the stated ASCII body.

| Ingress outcome | Status | Body | Durable effect and retry meaning |
| --- | --- | --- | --- |
| new authenticated event or authenticated same-ID/different-content conflict durably committed | `200 OK` | `ok\n` | committed once; no provider retry required |
| exact authenticated token/content replay or event-ID/content duplicate after the original commit | `200 OK` | `ok\n` | no new state/action; stops provider retry after response loss |
| bad/stale signature, unknown key, malformed/oversize/encoded body, wrong media type or method, missing/invalid required field, unresolvable tenant binding, or authenticated token reused with different content before a safe conflict binding can be proved | `406 Not Acceptable` | `reject\n` | restricted telemetry only; Mailgun must not retry |
| PostgreSQL, secret-resolution, or internal dependency failure before the complete token/event/action transaction commits | `503 Service Unavailable` | `retry\n` | no partial token/event/action commit; Mailgun may retry; read-only reconciliation remains recovery authority when Mailgun does not retry that event class |

No redirect, HTML, JSON error, tenant/provider identifier, exception text, `Retry-After`, or alternative status is returned. Process loss after commit and before response is recovered by the exact replay row. Process loss before commit leaves no token binding and permits a later authenticated retry.

Webhook ingress resolves the Organization through the registered Integration/domain mapping before opening the tenant transaction. It cannot accept an Organization or Delivery binding from an unverified request field.

### Read-only reconciliation

Reconciliation performs an Events API query using the exact correlation token, recipient digest binding and replay generation. It follows Mailgun pagination links only when their host, scheme and path remain inside the configured Events endpoint. It reads at most 100 events or 20 pages and obeys the same ten-second absolute deadline. Hitting either bound without proving the complete exact result is `dependency_error`, not `none`.

The adapter sends no message during reconciliation. `matched`, `none`, `ambiguous`, `dependency_error`, and `authentication_failed` map only as WF-014 defines. A missing event never proves nonacceptance.

### Mailgun monitoring

Required signals include submissions by normalized result, local deduplication hits, calls after each checkpoint, definitive retries, `acceptance_unknown` count/age, reconciliation result/latency, webhook authentication failures, duplicate/ambiguous provider event IDs, permanent failures, acknowledged replays, API rate limits, active Credential version and adapter initialization outcomes. An uncertain Delivery must have its escalation row within five minutes.

## Domain Verification Boundary

Domain verification is a platform service, not an Organization Integration and not a search-provider adapter.

### DNS TXT observation

- Query name is the exact Volume I `_f1-verify.<canonical_host>` value.
- The resolver is the environment's approved recursive resolver configured through `F1_DNS_RESOLVER_ADDRESSES`; entries are literal public resolver IP addresses owned by the infrastructure configuration, never tenant input.
- UDP is attempted first and TCP is used only when the authenticated DNS response is truncated.
- No DNS library retry is enabled.
- The absolute lookup deadline is ten seconds.
- Resolver timeout and temporary failure are normalized to the existing DNS reasons; NXDOMAIN and mismatch are completed observations, not transport retries.
- Raw returned values and IP addresses are never logged or retained outside the bounded Evidence digest contract.

### HTTPS-file observation

- The URL is exactly `https://<canonical_host>/.well-known/f1-verification.txt` on port 443.
- Redirect count is zero.
- Immediately before connection, the adapter applies `destination-safety-v1`, rejects mixed public/prohibited answers, pins the first sorted public global-unicast address, sends the canonical host in Host/SNI, and verifies the peer address.
- TLS certificate and hostname validation are mandatory.
- DNS, connection, TLS, request and response share the ten-second absolute deadline.
- Response reading stops at EOF or 4,097 bytes exactly as Volume I specifies.
- The client has no retry, cookie, proxy-from-user-input, decompression, redirect or body logging behavior.

Destination-safety rejection is retained as restricted diagnostic detail and maps outward to the existing `connection_failure` observation reason; it does not add a product reason.

### Scheduling, rate and monitoring

PostgreSQL schedules the exact automated slots. At most one observation is active per Verification Request, and at most two verification connections are active per canonical host across an environment. Excess concurrency delays within the slot window; it never starts after the window.

Required monitoring includes due/start/complete/skip lateness, DNS/HTTP normalized reasons, TLS failures, prohibited-address rejections, body-limit results, on-demand concurrency/rate/count denials, expiry races, Evidence persistence recovery and challenge-key destruction within 60 seconds.

## Managed Identity Receipt Boundary

The approved managed identity service is a platform identity boundary and never creates an Organization Integration or Credential. It validates user credentials and factors; F1 receives only the signed Identity Validation Receipt.

### Browser redirect protocol

The only browser handshake is `f1-managed-identity-redirect-v1`; OIDC authorization-code, implicit/hybrid, SAML, provider cookie introspection, direct credential POST, access/refresh token and unsigned assertion flows are absent. A signed release artifact fixes one HTTPS `authorization_endpoint`, `client_id`, receipt issuer, receipt audience, callback URI equal to canonical `APP_BASE_URL` plus `/auth/callback`, and JWKS URL. The release environment carries byte-identical mirrors plus the artifact digest solely as boot assertions; the verified active artifact is runtime authority and any mismatch fails release/boot. The authorization endpoint and JWKS URL have the same exact origin as the issuer, contain no user information or fragment, and cannot be changed by request, tenant, return target or environment outside the signed artifact.

`GET /auth/start` first validates its local purpose/bindings, then creates one server-side flow lasting five elapsed minutes. It generates independent 32-byte operating-system-CSPRNG `state` and receipt `nonce` values, exposes each as 43-character unpadded base64url, and stores only SHA-256 digests with the exact purpose, nullable Organization/Invitation and logical-return binding. It returns `303 See Other` to the fixed authorization endpoint with one RFC 3986 query whose members are sorted by UTF-8 name and percent-encoded with uppercase hexadecimal:

| Parameter | Exact value |
| --- | --- |
| `client_id` | signed artifact client ID |
| `redirect_uri` | exact registered callback URI |
| `response_type` | `f1_identity_receipt` |
| `response_mode` | `form_post` |
| `schema_version` | `onboarding-interim-v1` |
| `purpose` | the selected one of the four frozen receipt purposes |
| `state` | raw flow state |
| `nonce` | raw receipt nonce |
| `fresh_authentication` | `required` |
| `mfa` | `required` for `existing_account_sign_in`; `not_requested` for the other three purposes |

No Organization ID, Invitation reference, email, subject, return target, credential, factor or tenant name leaves F1 in that request. The managed service authenticates the principal and returns only an HTTPS cross-site `POST` to the registered callback. A success body is exactly `application/x-www-form-urlencoded` with unique fields `state=<flow-state>&receipt=<compact-JWS>`; a provider-declined body instead has unique fields `state=<flow-state>&error=<access_denied|authentication_failed|identity_unavailable>`. The body ceiling is 32 KiB, request compression/multipart/JSON/GET callbacks and unknown or duplicate fields are rejected, and the callback never accepts a receipt or error in its URL. Callback handling has a five-second elapsed deadline and no provider network call.

F1 hashes and consumes `state`, loads the exact unexpired flow, and for success validates that the receipt nonce/purpose/audience match it before atomically binding the flow, restricted Receipt and receipt-entry handle. State is one-use: an exact callback replay after the binding exists returns `303` to the same receipt-bound local form without recreating a Receipt/handle; altered, expired or terminal flow input returns the generic invalid-entry page. A declared provider error terminalizes the flow and returns the same generic authentication-failed entry page with restricted reason only. A database failure before commit returns `503` and leaves the flow unused; a loss after commit is exact-replay safe. The callback ignores any F1 Session cookie, is exempt only from Session CSRF, and relies on exact state/nonce/signature validation; the resulting local form uses the separate receipt-entry CSRF contract.

### Receipt format and validation

The physical receipt is a three-segment compact JWS whose segments are unpadded base64url and whose signature is `ES256` with the JOSE fixed-width 64-byte `R || S` representation. The protected header contains exactly `alg="ES256"`, `typ="JWT"`, and `kid`; `kid` is 1-64 ASCII characters matching `[A-Za-z0-9._-]+` and is the logical issuer key/version. An unprotected header, `crit`, embedded JWK, X.509 field, duplicate JSON member or any unknown header is rejected.

The payload contains exactly this closed claim set; duplicate or unknown claims are rejected:

| Claim | JSON type and exact contract |
| --- | --- |
| `iss` | string byte-equal to `IDENTITY_RECEIPT_ISSUER` |
| `aud` | one string byte-equal to `IDENTITY_RECEIPT_AUDIENCE`; arrays are invalid |
| `jti` | lowercase canonical UUIDv7; the logical Receipt ID |
| `schema_version` | string exactly `onboarding-interim-v1` |
| `sub` | nonempty opaque issuer-scoped string of at most 255 Unicode scalar values; compared byte-for-byte and never Unicode-normalized |
| `email` | string already byte-equal to the verified normalized ASCII email produced by the exact `onboarding-interim-v1` algorithm |
| `name` | trimmed Unicode-NFC string of 1-120 Unicode scalar values; the logical display name |
| `email_verified` | Boolean literal `true` |
| `purpose` | string in `bootstrap_grant_request`, `self_service_bootstrap`, `invitation_response`, `existing_account_sign_in` |
| `iat` | integer NumericDate; the logical `validated_at_utc` |
| `exp` | integer NumericDate exactly `iat + 600`; the logical `expires_at_utc` |
| `nonce` | exactly 43 unpadded base64url characters decoding to the 32-byte nonce requested by the bound flow |
| `authentication_assurance_version` | required 1-64 ASCII `[A-Za-z0-9._-]+` string only for `existing_account_sign_in`; absent otherwise |
| `mfa_satisfied` | required Boolean only for `existing_account_sign_in`; absent otherwise |

The logical receipt digest is SHA-256 over the exact compact-JWS ASCII bytes and is not a self-referential claim. Validation rejects a receipt when PostgreSQL receive time is at/after `exp` or `iat` is more than 30 seconds after receive time; command acceptance independently must commit strictly before `exp`. JSON numbers other than integer `iat`/`exp`, invalid UTF-8, non-NFC `name`, a non-normalized email, or any mismatch between `kid` and the selected key artifact is invalid.

F1 accepts only:

- issuer `IDENTITY_RECEIPT_ISSUER`;
- audience `IDENTITY_RECEIPT_AUDIENCE`;
- a key from `IDENTITY_RECEIPT_JWKS_URL` whose HTTPS origin exactly matches `IDENTITY_RECEIPT_ISSUER`; and
- the Volume I receipt lifetime and purpose constraints.

JWKS retrieval has a two-second absolute timeout, zero client retry, a 256 KiB body limit, no cross-origin redirect, and TLS verification. Successfully validated keys are cached for five minutes but never beyond a key's declared validity. An unknown `kid` permits one forced refresh within the same two-second budget. Cache or JWKS failure fails closed as the existing outward `authentication_failed` result for sign-in, or the applicable existing receipt-invalid result for another branch, while retaining a restricted dependency reason; it creates no Session or Account.

Receipt digest and nonce consumption are PostgreSQL authority. Signature validation alone never proves unused status. Raw credentials, factor values, identity-provider session cookies and access/refresh tokens never enter F1.

### Rate and monitoring

Receipt cryptographic validation has a safety cap of 20 concurrent validations per web process. Excess work waits in request order only while the receipt and request deadline remain valid; it does not create a new rate-limit result. Heroku edge denial-of-service controls may reject abusive transport before a logical command is accepted, but F1 defines no additional product rate-limit state for managed identity. The database nonce and command idempotency controls remain correctness authority.

Monitor validation result, issuer/schema/purpose mismatch, key refresh, unknown key, signature failure, nonce replay, assurance failure, rate denial and latency. Subject, email, nonce and receipt bytes are prohibited metric labels and ordinary logs.

## Dormant Provider Contracts

The following matrix is exhaustive. “None” is a required absence, not an implementation choice:

| Provider boundary | Authentication | Retry | Failure behavior | Rate limit | Timeout | Idempotency | Monitoring |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Stripe | no key lookup/header and no OAuth | none | `integration_policy_unavailable` before adapter/secret/network work | no limiter or provider interpretation | no provider deadline because no call exists | no provider/customer key; ordinary rejected command identity only | count blocked adapter-selection attempts by bounded provider kind/reason |
| OpenAI | no API key, project or organization header | none | frozen `ai_provider_unapproved` before prompt construction | no token/request limiter | no provider deadline | no provider request/fingerprint submission | blocked-selection count; zero outbound-call invariant |
| Anthropic | no API key or version header | none | frozen `ai_provider_unapproved` before prompt construction | no token/request limiter | no provider deadline | no provider request/fingerprint submission | blocked-selection count; zero outbound-call invariant |
| OpenRouter | no API key, referral or title header | none | frozen `ai_provider_unapproved` before prompt construction | no token/request limiter | no provider deadline | no provider request/fingerprint submission | blocked-selection count; zero outbound-call invariant |
| Google identity/search/AI/webmaster/performance/local APIs | no OAuth, API key, service account or application-default credentials | none | relevant policy-unavailable/missing-Evidence path before endpoint selection | no limiter | no provider deadline | no provider request identity | blocked-selection count by bounded logical provider class; zero outbound-call invariant |
| Other search/measurement provider | no credential or endpoint selection | none | missing Evidence under the no-Measurement-Set contract | no limiter | no provider deadline | no provider request identity | Measurement-Set gate outcome and zero outbound-call invariant |
| Mux | no token ID/secret or signed playback key | none | unsupported kind rejected before Integration creation | no limiter | no provider deadline | no upload/asset/playback identity | unsupported-kind rejection count and dependency/env/route absence checks |

No row may be changed from “none” by environment configuration, credential presence, provider SDK behavior or feature flag. Activation requires the controlled artifact/product boundary already stated for that row and a corresponding Volume II revision.

### Stripe

No baseline command contacts Stripe. Bootstrap and BillingEntity activation are provider-independent. `billing_adapter` returns `F1-DOMAIN-409 / integration_policy_unavailable` before secret retrieval, entitlement commitment, callback processing or network access. No `/stripe` webhook route, SDK, secret, scheduled synchronization or provider table row may exist in an enabled runtime.

### OpenAI, Anthropic and OpenRouter

No baseline request contacts these providers. Deterministic Recommendation generation remains available; an AI-assisted request follows the frozen `ai_provider_unapproved` result. No SDK initialization, model discovery, fallback chain, hidden environment toggle, prompt transmission, Credential row or outbound DNS connection is allowed.

### Google and search providers

No Google identity, search, AI, webmaster, performance or local API is selected. External search/AI/local/authority observations remain missing Evidence until OD-010's complete signed Measurement Set binds exact providers and adapters. Internal PostgreSQL Retrieval indexing is not a Google/search-provider integration.

### Mux

Mux is outside the admitted integration kinds and Volume I capabilities. It is not dormant: it is unsupported. A Mux dependency requires a controlled product-boundary change before Volume II may define an adapter.

## Platform Infrastructure Providers

AWS S3/KMS/Secrets Manager and Datadog are infrastructure dependencies under [System Boundaries](../012%20SYSTEM_BOUNDARIES.md), not tenant Integrations. Their contracts are defined in [Deployment And Observability](DEPLOYMENT_OBSERVABILITY.md). They MUST NOT create Organization Integration records or appear in customer integration state; Secrets Manager references are metadata of the already-defined Credential material version only.

## Contract Verification

CI and staging contract tests MUST prove:

1. only explicitly active application-integration boundaries can initiate product-provider network traffic; the separate S3/KMS/Secrets Manager, Datadog, Heroku/PostgreSQL/Redis, and CloudFront infrastructure paths are limited to the contracts in Deployment And Observability;
2. dormant/unsupported provider packages, routes, credentials, variables and DNS attempts are absent;
3. every HTTP/DNS client has implicit retry disabled and exact deadline/size/redirect behavior;
4. provider secrets and bodies cannot enter logs, traces, events, job arguments or error responses;
5. Mailgun process loss at every checkpoint produces the exact uncertainty or no-submission result;
6. webhook duplicate, replay, timestamp, signature, cross-tenant and ambiguous-content fixtures are deterministic;
7. reconciliation never sends and cannot infer failure from absence;
8. verification destination-safety, byte-boundary and slot-window fixtures reproduce Volume I;
9. managed identity signature, key rotation, nonce replay, purpose, assurance and outage fixtures create no raw credential state; and
10. adapter substitution cannot change a logical result without a separately accepted contract version.
