# Volume II Implementation Entry Map

## Status

- Status: Implementation handoff. Not product authority. Not frozen.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Product-behaviour baseline: `v1.5-volume-i-frozen` (frozen Volume I)
- Engineering-practice baseline: `v1.7-engineering-manual-accepted` (accepted Engineering Manual)
- Governing change: ADR-023

## Authority

This map carries no product authority and redesigns nothing. It routes implementation work to the
canonical owner that already specifies it. Where this map and a canonical owner disagree, the owner
prevails and this map is defective.

Under PM-REQ-003 authority is resolved by **scope before rank**. Three scopes matter here and they
are not ranked against each other — an artifact outside its own scope is not merely outranked, it is
**inapplicable**:

- **Volume I owns product behaviour.** What the system does. Never inferred from Volume II.
- **Volume II owns the implementation contract.** How this system realises that behaviour.
- **The Engineering Manual owns engineering practice.** How to build anything here. It establishes
  no product behaviour at any rank.

## How To Enter

Do not start from this map. Start from [IMPLEMENTATION_BACKLOG.md](IMPLEMENTATION_BACKLOG.md),
which is generated, ordered by the slice dependency graph, and gives every item its acceptance
criterion, contract, dependencies and verification obligation. This map exists to answer a different
question: *"I am working on authorisation — which document owns it?"*

The **acceptance criterion is the oracle**. An item is done when its criterion passes, and not
before. A contract field is not a suggestion: it names exact ownership and behaviour, and the
Change Boundary in [INDEX.md](INDEX.md) forbids changing a selected database role, table ownership,
lock order, queue identity, provider mapping, API schema, screen or query authorisation, cache key,
retry, timeout, serialisation, deployment resource or test gate as an incidental coding choice.

## Read Before Writing Any Code

Four things about this baseline are counter-intuitive and are settled. Each is ratified behaviour,
not a defect and not a gap. An implementation that "fixes" one of them is non-conformant.

1. **The action queue ships empty, and the numeric score is unavailable** (OD-010). The Check
   catalogue is `check-catalog-v1` exactly; `external-measurement-v1` bundles no query, intent,
   listing, provider or adapter set, so implementations do not invent one. The always-applicable
   external Checks persist handled `input_evidence_missing` errors, and **no Recommendation or
   Priority Decision publishes from an unavailable calculation**. Do not invent a Measurement Set, a
   provider call or a placeholder score to populate the queue.
2. **Security and administrative objects are unreadable** (OD-020's carve-out, pending OD-034).
   Support Session, Incident, Investigation, Legal Hold, Emergency Access Grant, deletion jobs and
   privileged Billing have no read row and stay deny-by-default. Every command, approval,
   command-result and audit path is fully available.
3. **Every metered read route Blocks** (OD-019's fail-closed leg, pending OD-035). No route declares
   one of the five low-cost operations, so each resolves `operation_unknown` and returns Block with
   `contact_support`. Non-metered reads are unaffected.
4. **A withheld limb is never resolved by inference.** Build the surrounding behaviour; never effect
   the limb. Resolving one by analogy or convenience resolves a pending owner decision by
   implementation, which is the exact failure the register exists to prevent.

## Entry Map

Order is the dependency order of the slice graph. "Start at" names the first backlog rows.

### 1. Identity and authentication

- Slice: **S-01 Registration and Access** — the first slice with product behaviour. Start here.
- Start at: MTX-001 (AC-CAP-001), MTX-026 (AC-WF-001), MTX-052 (AC-PRULE-001)
- Product behaviour: `../volume-i/CAPABILITY_MODEL.md` CAP-001; `../volume-i/WORKFLOW_SPECIFICATIONS.md` WF-001
- Implementation contract: `contracts/S-01.json`; [APPLICATION_LAYER.md](APPLICATION_LAYER.md), [SECURITY_PERFORMANCE.md](SECURITY_PERFORMANCE.md)
- Note: WF-001 atomically creates the first OrganizationAdmin Assignment and activates
  `access-policy-v1` under a valid unconsumed Bootstrap Grant. This is one of exactly **two**
  bootstrap exceptions to the protected-grant rule; no other existing-Organization grant may use it.
  `BootstrapGrantIssued` and `BootstrapGrantExpired` are the only events permitted to substitute the
  bootstrap principal for `organization_id`, under the DM-REQ-013 gate (OD-013 Option 1).

### 2. Organization and tenancy

- Slice: **S-02 Organization Setup**
- Start at: MTX-002 (AC-CAP-002), MTX-053, MTX-070
- Product behaviour: CAP-002; WF-001; WF-013 tenant lifecycle
- Implementation contract: `contracts/S-02.json`; [APPLICATION_LAYER.md](APPLICATION_LAYER.md)
- Note: tenancy is not optional and not application-only. Forced RLS with composite tenant keys is
  the fixed baseline ([INDEX.md](INDEX.md)); MTX-095 requires proving RLS holds **independently of
  the application check**, with the application check stubbed to allow. WF-001 creates and activates
  the baseline BillingEntity and links its Plan Assignment with no external provider call.

### 3. Authorisation and permission matrix

- Cross-cutting: **MTX-095 (AC-PRULE-044)** — enforced in every slice, never built once.
- Product behaviour: `../volume-i/WORKFLOW_SPECIFICATIONS.md#permission-baseline` — the closed
  `permission-baseline-v1` enumeration and the six-step effective-authorization algorithm; PRULE-044
- Implementation contract: `contracts/S-XC.json`; [SECURITY_PERFORMANCE.md](SECURITY_PERFORMANCE.md)
- **Withheld limb (OD-034):** complete allow/deny fixtures for security, administrative and internal
  operational object **read** cells. Those classes have no row and stay deny-by-default.
- Note: one authorization facade, invoked inside the unit of work, never at a transport edge alone.
  Deny-by-default is the rule, not the fallback: undefined role, permission, resource scope or tenant
  context is denied. An `Actor` line grants no authority. A Support Session **scopes an
  already-permitted action** and is never itself a read grant. Policy deny beats every Role allow.

### 4. Persistence and data lifecycle

- Slices: **S-23 Tenant Lifecycle** and the schema itself
- Start at: MTX-025 (AC-CAP-025), MTX-038 (AC-WF-013), MTX-092, MTX-093
- Product behaviour: `../015 DATA_LIFECYCLE.md`; `../016 STATE_MODEL.md`; WF-013; PRULE-042
- Implementation contract: `contracts/S-23.json`; [../../schemas/POSTGRESQL_SCHEMA.md](../../schemas/POSTGRESQL_SCHEMA.md)
- **Withheld limbs:** OD-031 (routine retention-expiry destruction, under
  `retention-destruction-trigger-interim-v1`); OD-032 (canonical namespace for an unassigned record).
- Note: `retention-interim-v1` is a **fixed approved baseline**, not an interim, and
  customer-configurable retention is not approved. No LifecycleDeletionJob may complete without
  entering `running` (OD-033). Document `quarantined`/`retired` are **removed**, not reserved
  (OD-015) — no column, CHECK or migration may admit either.

### 5. Events, idempotency and audit

- Cross-cutting: **MTX-097 (AC-PRULE-046)** — the envelope rule, enforced everywhere.
- Product behaviour: `../018 OBSERVABILITY.md`; WF envelope contracts; PRULE-046
- Implementation contract: `contracts/S-XC.json`; [API_CONTRACTS.md](API_CONTRACTS.md) event tables
- **Withheld limb (OD-032):** canonical namespace for an unassigned record.
- Note: every event and audit record carries a **nonnull `organization_id`** (OD-013 Option 1). A
  platform-wide Incident or cross-Organization Investigation is N Organization-owned records sharing
  one `correlation_id`; `correlation_id` expresses coordination and confers no ownership and no
  access. `ReassessmentTriggered`, `DocumentQuarantined`, `DocumentRetired` and `ComparisonGenerated`
  are **permanently excluded** from the event registry. Client-supplied idempotency keys are
  prohibited on GET.

### 6. Collection, parsing and indexing

- Slices: **S-04 Source Onboarding → S-05 Ownership Verification → S-06 Scope → S-07 Crawl → S-08 Parsing**
- Start at: MTX-004, then MTX-005/028/051/056/071, MTX-006, MTX-007, MTX-031
- Product behaviour: CAP-005 through CAP-008; WF-003 through WF-006
- Implementation contract: `contracts/S-04.json` … `contracts/S-08.json`
- **Withheld limb (OD-027):** a `has_one` narrowing, a `unique (parsing_job_id)` constraint, and any
  second IndexingJob per ParsingJob. `indexing-interim-v1` pins both keys. These three artifacts may
  be **named as withheld** and never contracted as settled — the validator enforces it.
- Note: ownership verification is **DNS TXT and HTTPS file only** (OD-001, ratified). Other methods
  are **out of baseline scope**, not blocked pending approval; naming one as a rejection fixture is
  required, asserting one as usable is a validator failure.

### 7. Scoring and calculation availability

- Slices: **S-09 Inspection → S-10 AI Analysis → S-11 Evidence → S-12 Issues → S-13 Scoring**
- Start at: MTX-009 (AC-CAP-009), through MTX-015 (AC-CAP-015)
- Product behaviour: CAP-009 through CAP-015; WF-007, WF-008; `../volume-i/SCORE_EVIDENCE_MODEL.md`
- Implementation contract: `contracts/S-09.json` … `contracts/S-13.json`
- **Withheld limb (OD-032):** namespace for ScoreSnapshot, Check Result, Issue Set and peers.
- Note: **the numeric score is unavailable at baseline** (OD-010) — see Read Before Writing Any Code.
  On an Issue fingerprint collision the second Issue **MUST NOT** be created and the Evaluation fails
  closed as `F1-DATA-409 / issue_fingerprint_key_collision`, `retryable=false` (OD-017). Frozen prose
  in `SCORE_EVIDENCE_MODEL.md` still says the second tuple "may create" its own Issue; that is stale
  and **permits behaviour the owner forbade** — WF-007 and OD-017 prevail.

### 8. Recommendations and priority decisions

- Slices: **S-14 Recommendations → S-15 Prioritisation and Action Queue**
- Start at: MTX-016 (AC-CAP-016), MTX-017 (AC-CAP-017)
- Product behaviour: CAP-016, CAP-017; WF-009, WF-010; OD-003, OD-009
- Implementation contract: `contracts/S-14.json`, `contracts/S-15.json`
- Note: **the queue ships empty** and that is correct (OD-010). Disputed and review-required Issues
  are excluded from published scoring and prioritisation until eligible (OD-009). Confidence is
  numeric `0.0000`–`1.0000` with displayed Low/Medium/High bands (OD-003). No narrative field, no
  reserved narrative slot, no provider call.

### 9. Metering and billing

- Slice: **S-22 Entitlement and Metering**
- Start at: MTX-024 (AC-CAP-024), MTX-040 (AC-WF-015), MTX-090, MTX-091
- Product behaviour: CAP-024; WF-015; PRULE-039, PRULE-040; OD-006, OD-008, OD-019
- Implementation contract: `contracts/S-22.json`
- **Withheld limb (OD-035):** the route-to-operation declaration and `report.view`'s read surface.
- Note: build the whole path — the checkpoint, the immutable Decision, the counters, the reservation,
  the replay identity and the Block leg. The **high-cost** path (`crawl.start`,
  `reassessment.start`, `ai.generate`, `export.generate`) is fully reachable. Only the **low-cost**
  read responses Block, on `operation_unknown`. The five low-cost operation strings are **not
  permissions**; that `issue.read` and `recommendation.read` appear in both vocabularies is a
  coincidence, and inferring one from the other grants authority Volume I never wrote.

### 10. Notifications and delivery

- Slice: **S-19 Notifications and Delivery**
- Start at: MTX-021 (AC-CAP-021), MTX-039, MTX-085 (AC-PRULE-034)
- Product behaviour: CAP-021; WF-014; PRULE-034; OD-004 (in-app plus email; Mailgun, not Postmark)
- Implementation contract: `contracts/S-19.json`
- **Withheld limb (OD-023):** credential rotation begin and complete. No
  `credential.rotation_token.issue` permission exists; `credential.rotate` is canonical but
  unreachable. Delivery against an already-active Credential is settled.
- Note: Mailgun provides **at-least-once application attempt processing with explicit
  provider-acceptance uncertainty** and no exactly-once claim. No automatic resend while uncertain;
  administrative replay requires explicit duplicate-risk acknowledgment. Reauthorize and redact
  **every attempt**, not just the first.

### 11. User interface and administration

- Slices: **S-16 Reporting → S-17 Historical Comparison → S-20 Export → S-21 Administration and Support Investigation**
- Start at: MTX-018 (AC-CAP-018), MTX-019 (AC-CAP-019), MTX-022 (AC-CAP-022), MTX-023 (AC-CAP-023)
- Product behaviour: CAP-018, CAP-019, CAP-022, CAP-023; WF-012, WF-016, WF-018
- Implementation contract: `contracts/S-16.json`, `S-17.json`, `S-20.json`, `S-21.json`;
  [FRONTEND_ARCHITECTURE.md](FRONTEND_ARCHITECTURE.md)
- **Withheld limb (OD-012):** customer notification on emergency access, pending qualified legal
  review. The emergency-access **architecture** is ratified and settled; `emergency_customer_access`
  does not exist and the fail-closed outcome is **permanent baseline**.
- Note: object-level authorization strictly **before** field-level redaction, with a whole-object
  denial for an actor who cannot access the object at all. The comparison read is side-effect-free
  and emits **no** domain event (OD-024). Customer-facing reads render only on their explicit OD-020
  row; administrative collections do not render at all.
- **Known completeness gap, recorded not invented:** the Emergency Access Grant has no
  `emergency_access_grants` table, no `emergency_access_grant` `EventEntityType` member and no
  `EmergencyAccess*` `EventType` rows, and Volume I's Versioned Policy Resolution enumeration names
  no artifact type to back `emergency-access-v1`. This is a Volume II completeness gap, **not** a
  withheld limb and not an authority gap — nothing about it awaits an owner. It bounds the Grant
  only and is deep inside S-21; it blocks no earlier slice. See
  [IMPLEMENTATION_READINESS_REPORT.md](IMPLEMENTATION_READINESS_REPORT.md).

### 12. Observability, security and operations

- Slice: **S-24 Incident and Recovery**, plus cross-cutting MTX-094 and MTX-096
- Start at: MTX-042 (AC-WF-017)
- Product behaviour: `../018 OBSERVABILITY.md`; `../014 SECURITY_MODEL.md`; WF-017; PRULE-037, PRULE-038
- Implementation contract: `contracts/S-24.json`; [DEPLOYMENT_OBSERVABILITY.md](DEPLOYMENT_OBSERVABILITY.md), [TESTING_ARCHITECTURE.md](TESTING_ARCHITECTURE.md)
- Note: `incident-diagnostic-interim-v1` is the **only** active playbook and declares no mutation, so
  it consumes no High-Risk Remediation Approval. `incident.respond` and a High-Risk Approval **never**
  substitute for an underlying target-workflow permission. Denials are events, not gaps: every denial
  emits exactly one authorization audit event and performs no state change or provider call.
  Telemetry MUST NOT carry a raw identity assertion, email, token, credential or authentication
  factor.

## Related Documents

- [IMPLEMENTATION_BACKLOG.md](IMPLEMENTATION_BACKLOG.md) — generated; start here
- [IMPLEMENTATION_READINESS_REPORT.md](IMPLEMENTATION_READINESS_REPORT.md) — what is proven and what is not
- [IMPLEMENTATION_MATRIX.md](IMPLEMENTATION_MATRIX.md) — generated; the controlling row set
- [SLICE_REGISTER.md](SLICE_REGISTER.md) — slice dependency graph
- [INDEX.md](INDEX.md) — fixed implementation baseline and Change Boundary
- [RATIFICATION_STATUS_OVERLAY.md](RATIFICATION_STATUS_OVERLAY.md) — where frozen prose is stale, and in which direction

## Change Control

This map is superseded by the canonical owners it routes to. Correct it when a slice's owner changes;
never use it to record a product decision.
