# S-XC Cross-Cutting Obligations — Volume II fragment

Structured contract: `specification/volume-ii/contracts/S-XC.json`.
Merge targets are routed explicitly by the marker headings below: the first three sections append to
`specification/volume-ii/APPLICATION_LAYER.md`; the last section appends to
`specification/volume-ii/SECURITY_PERFORMANCE.md`.
Matrix rows owned by this contract: MTX-094 (AC-PRULE-043), MTX-095 (AC-PRULE-044),
MTX-096 (AC-PRULE-045), MTX-097 (AC-PRULE-046). These are the four rows the matrix marks slice `ALL`.

S-XC is **not a slice**. It owns no route, command, table, event, permission, job or aggregate, and it
redefines nothing another contract owns. It exists because the Slice Register says these rows cannot be
closed any other way: *"A cross-cutting obligation is enforced in every slice, so it cannot be discharged
by one slice's contract; each remains `Pass B required` until every slice records its application."*

That evidence now exists. All 93 rows across `contracts/S-01.json` through `contracts/S-24.json` record
`tenant_boundary`, `audit_record`, `observability` and `test_contracts`; every one of the 24 slices
records its exact permission cells, its authorization entry point, its idempotency identity and its audit
set. These four rows are closed **against that accumulated evidence**. Every claim below names the slice
and row it is drawn from, so a reader can check it rather than trust it. Nothing here re-derives a slice,
and nothing here restates a PRULE as though restatement were a contract.

---

## APPLICATION_LAYER.md

## PRULE-043 Zero Contribution And Deterministic Downstream Refresh

Matrix row: MTX-094 (AC-PRULE-043). Slice: `ALL`.
Structured contract: `specification/volume-ii/contracts/S-XC.json`.
Governing authority: PRULE-043; SCORE_EVIDENCE_MODEL.md Evidence Validation Rules, Score Contribution
Contract, Completeness Status, Recommendation Artifact and `priority-interim-v1`; CAP-013, CAP-014,
CAP-015, CAP-016, CAP-017, CAP-019; WF-007, WF-008, WF-009, WF-010, WF-012, WF-013; OD-009
(**ratified**) and OD-011 (**resolved**).

### What this row is, and what it is not

PRULE-043 names six capabilities and six workflows. It therefore binds exactly eight slices — S-09, S-11,
S-12, S-13, S-14, S-15, S-17 and S-23 — and no others. This section is the canonical owner of the
cross-capability zero-contribution rule; it is what
[MTX-015's rollout](#cap-015-scoring-and-recalculation) means when it records that *"PRULE-043's
cross-capability zero-contribution rule is MTX-094's and is consumed here, not restated"*.

This row does not re-derive those slices. It closes the rule by naming, per slice, the mechanism that
already discharges it, and by asserting the clauses that fall **between** slices — which is where a
cross-cutting rule actually fails.

### Zero to score and zero to priority are two different mechanisms

The rule says ineligible Issues *"MUST contribute zero to score and priority"*. Those are not one clause
implemented twice.

- **On score**, a zero contribution is *recorded*. `penalty_points` always equals the impact-table value
  even when excluded; only `signed_contribution_value` becomes `0.0`, and exactly one first-match
  `exclusion_reason_code` is stored. A zero contribution is therefore attributable, not absent
  ([MTX-045](#score-attribution-and-contribution-reconciliation)).
- **On priority**, a zero contribution is an *absence*. S-13's zero has no priority analogue: an
  ineligible origin Issue receives **no Priority Decision at all** — not ranked last, not ranked with a
  zero weight, not included with a suppression marker
  ([MTX-035](#wf-010-prioritize-and-publish-action-queue)).

Conflating the two produces a ranked ineligible Artifact, which is the exact outcome OD-009 Option 2 was
ratified to prevent. The fixture set asserts both forms separately.

### The wide commit, and the history that sits outside it

The rule's second clause — *"non-valid Evidence MUST make current score unavailable"* — is a
**wide commit**, for the same reason promotion is one. A transition away from `valid` performs every
applicable current effect atomically **before the Validation Decision commits**: the Current Score
Projection goes unavailable, `invalid_evidence` joins its de-duplicated fixed-precedence reason set,
every published Artifact whose origin Issue is affected is suppressed, and — *independently* — every
published Artifact whose rationale or Citation references that Evidence is suppressed
([MTX-013](#cap-013-evidence-capture-and-provenance)). A narrow commit leaves a stale numeric score
readable between the Decision and the propagation.

The two suppression paths are separate clauses and collapsing them into one is the natural implementation
error: an Artifact can cite Evidence in its rationale without that Evidence supporting its origin Issue.

The mirror boundary is equally load-bearing, and S-11's
[MTX-067](SECURITY_PERFORMANCE.md#prule-016-evidence-contract-retention-split-and-propagation) states the reconciliation exactly:
*"the same Evidence transition makes the current view unavailable and leaves the historical view intact"*.
ScoreSnapshots and Score Contributions are immutable; a later Issue or Evidence decision never rewrites
them. The retained last-promoted snapshot stays readable **as history** throughout the unavailable window,
and [MTX-044](SECURITY_PERFORMANCE.md#chain-completeness-and-suppression-before-a-current-read) asserts that retention expressly —
because deleting it would satisfy *"no current numeric score"* for entirely the wrong reason.
[MTX-037](#wf-012-compare-historical-results) is the S-17 half of the same boundary: the comparison writes
nothing, so its application of PRULE-043 is a prohibition rather than an action.

### Create or reuse is the existing tuple, not a new mechanism

*"Eligibility/retention change MUST create/reuse an immutable snapshot"* is discharged by the seven-element
ScoreSnapshot idempotency tuple already contracted at
[MTX-033](#wf-008-calculate-score-from-issues). Nothing new is introduced. Exact replay of the Decision
command returns the stored Decision **without** repeating suppression, the event or the recalculation
([MTX-013](#cap-013-evidence-capture-and-provenance)), and recalculation replaces the *complete* reason
set rather than applying a delta — so a redelivery converges on one reason set instead of accumulating
codes.

Republication is deliberately asymmetric with suppression: it requires the **full** publication predicate
set to pass again, not merely the condition that caused suppression to clear
([MTX-078](SECURITY_PERFORMANCE.md#prule-027-sole-origin-and-origin-governed-eligibility)).

### The retention limb

`DLC-REQ-012` reaches this rule through Evidence, not through a separate mechanism. Retention-expiry
quarantine and hold quarantine drive the **identical** propagation as a security quarantine, because all
three are transitions away from `valid`. Under ratified OD-011 a legal hold suspends **irreversible
destruction only** — never access revocation and never product-validity expiry — so a held Evidence
Payload still makes the current score unavailable at its expiry cursor while its bytes survive
([MTX-093](SECURITY_PERFORMANCE.md#prule-042-retention-and-deletion)).

### Two precisions recorded, neither resolved

- AC-PRULE-043 names *Citation Evidence* invalidation. The Citation record is CAP-012's in S-10, which
  PRULE-043's Related Capabilities column does not list. The reach is nonetheless consistent: the
  **suppression obligation** the criterion creates lands on CAP-016 in S-14, which the column does list.
  S-10 supplies the record identity; S-14 discharges the obligation. Nothing is missing.
- PRULE-043 does **not** name CAP-018. The *"before a current read"* clause belongs to AC-SM-001 and is
  [MTX-044](SECURITY_PERFORMANCE.md#chain-completeness-and-suppression-before-a-current-read)'s. S-16 consumes the projection
  state; it does not implement PRULE-043.

**No slice bound by PRULE-043 fails to apply it.** OD-009 and OD-011 are settled authority and nothing is
withheld on this row.

## PRULE-045 Policy Capture Activation And Re-Resolution

Matrix row: MTX-096 (AC-PRULE-045). Slice: `ALL`.
Structured contract: `specification/volume-ii/contracts/S-XC.json`.
Governing authority: PRULE-045; WORKFLOW_SPECIFICATIONS.md Versioned Policy Resolution and Role
Assignment And Policy Artifact; CAP-002, CAP-006, CAP-007, CAP-015, CAP-020, CAP-021, CAP-022, CAP-024;
WF-004, WF-005, WF-008, WF-011, WF-013, WF-014, WF-015, WF-016; OD-002, OD-003, OD-005, OD-006, OD-026
(all **settled**).

### The eighteen types, and who may touch them

Volume I closes the list: `access`, `source_scope`, `crawl`, `reassessment_schedule`, `entitlement`,
`notification`, `export`, `score`, `confidence`, `score_eligibility`, `priority`, `check_catalog`,
`external_measurement`, `effort`, `recommendation_template`, `ai_response`, `ai_safety`, `citation`.
It splits them cleanly: tenant-scoped mutable policy under the Policy Artifact lifecycle, or a global
immutable release artifact activatable **only** by its named owner-approval release service.

Every bound slice's activation was reconciled against that split rather than against intuition. S-02 and
S-23 own `access`; S-06 owns `source_scope`; S-07 owns `crawl` narrowing; S-18 owns
`reassessment_schedule`; S-19 owns `notification`; S-20 owns `export` narrowing; S-22 owns `entitlement`.
S-09, S-13, S-14 and S-15 **consume** the system-governed versions and activate none —
[MTX-036](#wf-011-trigger-reassessment) records the sharp edge of this: `reassessment.trigger` grants
nothing over `score`, `confidence`, `score_eligibility`, `check_catalog`, `external_measurement`,
`effort`, `priority` or global Crawl safety versions.

### Immediate means immediate, and the client clock never decides

Every activation command requests `activation_mode=immediate` and **MUST omit** client-supplied effective
and expiry times. The activation transaction assigns `effective_at_utc` to **its own commit time** and
sets `expires_at_utc=null`. Any other mode, or any supplied time, is schema-invalid and changes nothing.

Volume I schedules no future activation and no automatic policy expiry. That is not an omission to be
helpfully filled: *"A future scheduling or expiring-policy capability requires an explicit later contract
rather than overloading these states."* No `draft` version becomes active by the passage of time, and no
`active` version becomes `superseded` without an activation commit.

### The two instants, and why they must differ

This is the clause that makes PRULE-045 a real rule rather than a lookup.

- An **immediately executed** command resolves versions active at the server `authorization_check_at_utc`.
- A **queued** command keeps that initial snapshot **for audit** but, immediately before execution,
  resolves a *new* execution snapshot at `policy_resolution_at_utc=execution_check_at_utc` — and **that
  later snapshot governs** allow, deny and execution.

[MTX-030](#wf-005-execute-crawl-and-ingestion) records it in the sharpest available form: an authorization
or scope result established at queue time is **never** trusted at execution time, and every URL is
validated against the pinned **and** current restrictive scope. [MTX-036](#wf-011-trigger-reassessment)
records the audit consequence: the schedule decision persists the due-time **and** the evaluation-time
state versions — two instants, because the entire point of re-resolution is that they can differ.

After a durable reservation or run starts, resolution stays **pinned** to the execution snapshot, with
exactly one exception: a new security or source-scope restriction takes effect at the next checkpoint.
That exception is narrow and directional — it can only ever tighten.

### Blocking, and the two things that look like blocks and are not

*"Missing, stale, conflicting, incomplete, future-effective, expiring, or unknown policy blocks
state-changing behaviour"* with `policy_unavailable`, and **no implicit default is invented** except where
Volume I declares an interim policy. Seven clauses, seven fixtures — a clause list satisfied by only its
first member is untested.

Two adjacent cases are deliberately **not** blocks, and conflating them with absence is the natural
implementation error:

1. Absence of an **optional** higher-scope Source Scope restriction is the neutral **full set** inside the
   verified Source boundary. A missing or ambiguous **mandatory** Source-level policy denies **all** URLs.
   Same word, opposite outcomes ([MTX-072](SECURITY_PERFORMANCE.md#prule-021-source-scope-predicate)).
2. Absence or disablement of the optional `reassessment_schedule` policy **creates no scheduled request and
   does not block manual reassessment**. PRULE-045 says so in its own final sentence. S-18 contracts
   manual-only operation as a correct, complete, successful outcome — never as degraded, blocked or an
   error ([MTX-036](#wf-011-trigger-reassessment)).

### Narrowing is one-directional, and rollback is not a bypass

Global safety bounds cannot be weakened; effective crawl and capacity limits are the **most restrictive**
of global safety, approved entitlement, Organization and Project limits. A rollback creates a **new
candidate version** carrying the prior normalized rules and passes the **same** authority and
non-broadening validation as any other activation. A rollback that would broaden Source Scope, Crawl,
Export or Access is rejected: historical content is never a bypass.

### One precision recorded, not resolved

PRULE-045's Related Workflows column does not name WF-001, yet AC-PRULE-045's first clause is about the
byte-exact **bootstrap** Access and Entitlement policies and the BillingEntity-linked Plan Assignment,
which execute inside the WF-001 transaction. The reach is nonetheless consistent, because the Related
Capabilities column **does** name CAP-002: S-02's contract owns the bootstrap policy-activation
obligations and S-01 owns the transaction they execute in — exactly the ownership split the Slice Register
already records for CAP-002 ([MTX-002](#cap-002-organization-setup)). Nothing is missing and nothing is
invented.

**No slice bound by PRULE-045 fails to apply it.** All five decisions are settled. OD-005's ratification
confirms this row's shape rather than complicating it: threshold numerals are versioned policy
configuration bound to an approved policy version rather than immutable Volume I constants, so a numeric
change is a policy-version change and not a Volume I revision.

## PRULE-046 Command Result Event And Execution Envelopes

Matrix row: MTX-097 (AC-PRULE-046). Slice: `ALL`. **Limb withheld under OD-032.**
Structured contract: `specification/volume-ii/contracts/S-XC.json`.
Governing authority: PRULE-046; WORKFLOW_SPECIFICATIONS.md Logical Command Envelope And Replay, Logical
Result And Error Contract and Logical Event Envelope; CAP-001 through CAP-025; WF-001 through WF-018;
DM-REQ-002, DM-REQ-006, DM-REQ-013, SM-REQ-004, SM-REQ-005, ERR-REQ-004, OBS-REQ-015; OD-013, OD-019,
OD-024 (**settled**) and **OD-032 (pending)**.

### OD-032 — the withheld limb, stated exactly

OD-032 is **pending** (`Current Status: Pending owner approval`) and is the only pending decision reaching
any of these four rows. It reaches MTX-097 alone.

Its exact question is which lifecycle owner and canonical identifier namespace `011 DOMAIN_MODEL.md`
assigns to the lifecycle-bearing records DM-REQ-001's core-entity catalogue does not name: **ScoreSnapshot,
Check Result, Session, LegalHold, LifecycleDeletionJob, Notification, Delivery, Parsed Artifact, Index
Receipt and Issue Set**. Its Affected Product Rules name PRULE-046 and its Affected Acceptance Criteria
name AC-PRULE-046, and the link is exactly the **identity** envelope:

- DM-REQ-006 requires identifier namespaces to appear in logs, audit events and telemetry labels;
- DM-REQ-013 and the Logical Event Envelope require `affected_entity_type` and `affected_entity_id`;
- SM-REQ-004 requires every transition attempt's audit event to carry `entity_id`.

None of those can be satisfied *with a namespace* for a record that has none.

**The withheld limb on MTX-097 is exactly this and nothing else:** the DM-REQ-006 canonical identifier
namespace for those ten records; the DM-REQ-002 lifecycle owner for the five that `016 STATE_MODEL.md`
names no owner for (ScoreSnapshot, Check Result, Parsed Artifact, Index Receipt, Issue Set); and the
bounded-context definition for LegalHold, whose `016` owner names a `Security Context` that `011` does not
define among its bounded contexts.

**Behaviour is permitted under the interim, and is contracted here in full.** Safe Interim Behavior is
explicit: Volume I's existing logical field names and behavioural contracts for these records are
*unchanged and remain authoritative for behaviour*, while *any Volume II or persistence artifact that
requires a canonical namespace for an unassigned record remains blocked rather than choosing one*.
Blocking Impact records `Volume II — no for behaviour, yes for any artifact requiring a canonical
namespace`. So every envelope field is present and populated, every event emits, and exact replay and
concurrency repeat no product side effect. The ten records travel in envelopes by their Volume I logical
field names. **The limb withholds a label and blocks no behaviour:** an unnamespaced ScoreSnapshot still
emits its transition audit event with a populated `entity_id`.

Two prohibitions follow and both are absolute. No `evd_id`-style prefix is chosen for any of the ten —
including **by analogy** to Evidence's accepted `evd_id` exposed through the logical field `evidence_id`,
which OD-032's own Recommended Option cites as the precedent the decision would follow; inferring one from
it would resolve a pending decision by implementation. And where `016` **already** names a lifecycle owner
— Session's Identity and Access Context, LifecycleDeletionJob's Data Lifecycle Context, Notification's and
Delivery's Delivery Context, LegalHold's Security Context — that assignment **stands and is not
reopened**. What remains withheld is the DM-REQ-001 namespace, not those existing assignments.

This is the envelope-layer statement of the identical limb already withheld at
[MTX-013](#cap-013-evidence-capture-and-provenance) (LegalHold, Check Result),
[MTX-015](#cap-015-scoring-and-recalculation) (ScoreSnapshot, Issue Set),
[MTX-021](#wf-014-deliver-notifications) (Notification, Delivery) and
[MTX-025](#wf-013-manage-tenant-lifecycle) (Session, LegalHold, LifecycleDeletionJob). It resolves nothing
they left open.

### The preimage is the authority; the hash is an index

The envelope's canonical request hash is SHA-256 over UTF-8 canonical JSON containing command type, schema
version, actor or service identity, Organization or bootstrap principal, nullable Project, target type and
nullable ID, action, expected version, `command_payload` and sorted policy versions. `command_id`, the
idempotency key, the requested time, the correlation and causation IDs and transport metadata are
**excluded** — which is precisely what makes a replay carrying a new `command_id` still a replay, and an
altered payload under the same key a conflict.

The same discipline runs through every slice that hashes anything: S-09's retained result-key preimage,
S-10's AIResponse request-fingerprint preimage, S-12's full `(evaluation_id, fingerprint_version,
fingerprint_preimage)` tuple. A unique index on a bare hash is **forbidden**, because a same-hash
different-preimage record must be detectable rather than merged.

### Twenty-four idempotency identities, none of them a restatement

`Exact replay/concurrency repeat no product side effect` is one sentence in Volume I and twenty-four
distinct mechanisms in Volume II. Each slice records its own and none is generic:

| Slice | Identity it records |
| --- | --- |
| S-01 | per branch; receipt nonce single-use inside the atomic commit ([MTX-026](#wf-001-onboard-organization-or-invited-account)) |
| S-02 | inherits the WF-001 self-service envelope ([MTX-002](#cap-002-organization-setup)) |
| S-03 | creation by key; activation by state guard ([MTX-027](#wf-002-create-and-activate-project-scope)) |
| S-04 | key recorded **inside** the immutable registration provenance, so replay identity is auditable from the Source itself ([MTX-004](#cap-004-website-or-property-onboarding)) |
| S-05 | creation by key; reserved attempt identity; no second count on completion retry ([MTX-028](#wf-003-verify-property-ownership-or-control)) |
| S-06 | request by key; decisions guarded by request status ([MTX-029](#wf-004-manage-source-scope)) |
| S-07 | `(crawl_id, evaluation_kind=initial_assessment)`; a replayed root command returns its stored result rather than a rejection, which OD-018 states expressly ([MTX-030](#wf-005-execute-crawl-and-ingestion)) |
| S-08 | key plus replay generation per job ([MTX-031](#wf-006-process-parsing-and-validation-pipeline)) |
| S-09 | the retained canonical uniqueness **preimage**; `check_result_key_sha256` is its index ([MTX-061](#prule-010-check-materialization-canonical-order-and-determinism)) |
| S-10 | the AIResponse request-fingerprint preimage ([MTX-012](#cap-012-ai-discoverability-analysis)) |
| S-11 | Decision key; exact replay returns the Decision **without** repeating suppression, the event or recalculation ([MTX-013](#cap-013-evidence-capture-and-provenance)) |
| S-12 | `(evaluation_id, fingerprint_version, fingerprint_preimage)` ([MTX-032](#wf-007-generate-issues-from-checks-and-adjudicate)) |
| S-13 | the seven-element ScoreSnapshot tuple ([MTX-033](#wf-008-calculate-score-from-issues)) |
| S-14 | generation key over frozen input; publication by Artifact ID plus expected family version ([MTX-034](#wf-009-generate-recommendations)) |
| S-15 | `(recommendation_artifact_id, priority_policy_artifact_id, priority_policy_version, eligible_set_sha256)` ([MTX-035](#wf-010-prioritize-and-publish-action-queue)) |
| S-16 | the OD-019 **server-minted** Read Decision ID; client-supplied idempotency keys are prohibited on GET ([MTX-018](#cap-018-reporting-and-dashboarding)) |
| S-17 | none — the comparison writes nothing; its response identity is the `sha256` over the ordered snapshot IDs ([MTX-037](#wf-012-compare-historical-results)) |
| S-18 | **four** distinct identities, none interchangeable ([MTX-036](#wf-011-trigger-reassessment)) |
| S-19 | `(event_id, policy_version, template_version, generation)` and `(notification_id, recipient_id, channel, replay_generation)` ([MTX-039](#wf-014-deliver-notifications)) |
| S-20 | **four** distinct identities that are never interchanged ([MTX-041](#wf-016-export-reports-and-data)) |
| S-21 | create scope by Organization, command type and key; collection by checkpoint identity ([MTX-043](#wf-018-investigate-and-audit-security-or-compliance-events)) |
| S-22 | **three** distinct identities, none interchangeable ([MTX-040](#wf-015-enforce-entitlements)) |
| S-23 | key plus expected record state version ([MTX-038](#wf-013-manage-tenant-lifecycle)) |
| S-24 | create scope by Organization, command type and key ([MTX-042](#wf-017-handle-incident-and-recovery)) |

Idempotency **scope** differs by kind and the difference is load-bearing: for an existing target it is
Organization, command type, target resource type and ID, and key; for a create it is Organization, command
type, and key; pre-Organization bootstrap substitutes the immutable bootstrap-principal ID for
Organization.

### Profile selection is not a choice

The eight event profiles are selected by a deterministic first-match order and *"a producer cannot choose
a weaker profile for convenience"*. The adversarial cases are the ones worth asserting: a recovery that
also transitions state selects `recovery`; a policy activation that also creates its first version selects
`policy_activation`, not `created`; a suppression selects `state_transition`, not `failure`; and a
state-transition event reporting a failure outcome in its payload **remains** `state_transition`. That
last one is why S-13's unavailable calculation is a first-class retained result rather than a `failure`
event.

Semantics matching none or more than one row fail **before publication** as
`F1-DATA-409 / event_profile_unmapped`, emitting no malformed substitute.

### The two removed events, and the one permitted substitution

`ComparisonGenerated` and `ReassessmentTriggered` are **removed** as Volume I domain events under ratified
OD-024 and OD-025. They are asserted absent, never emitted and never metered. Under OD-024 the WF-012
comparison read is audit-only and side-effect-free, and
[MTX-037](#wf-012-compare-historical-results) records that its audit trail is not merely supporting
evidence but *the entire discharge* of the workflow's audit obligation — which is why the removed event
costs the workflow nothing.

Under ratified OD-013 Option 1 canonical ownership of every event, Incident and Investigation is
**singular and always an Organization**. Coordination across Organizations is a relationship between
Organization-owned records and never an owner: a platform-wide Incident is N Organization-scoped Incident
records and a cross-Organization Investigation is N Organization-scoped Investigation records, each
emitting one Organization-scoped event and linked by a shared `correlation_id` that grants no access
([MTX-042](#wf-017-handle-incident-and-recovery),
[MTX-043](#wf-018-investigate-and-audit-security-or-compliance-events)). No producer emits with null, a
sentinel, an invented platform tenant, an arbitrarily selected Organization or an omitted tenant field,
and **no `event_scope` field exists on any event**.

The sole exception is S-01's DM-REQ-013 pre-Organization bootstrap substitution, which WF-001 expressly
names: `BootstrapGrantIssued` and `BootstrapGrantExpired` carry the immutable `bootstrap_principal_id`
**in `organization_id` itself** rather than in any separate field. It is asserted absent from every other
event type and from every event after an Organization exists.

### Where the envelope meets authorization

One clause, and it is easy to miss. Before returning retained identifiers or result data, an **exact
replay reauthorizes** the current actor against the target and applies **current** field redaction;
denial returns `F1-AUTH-403` with no retained payload while the stored outcome remains unchanged. Treating
a stored result as pre-authorized is the failure that clause exists to prevent. The general authorization
model is [MTX-095](SECURITY_PERFORMANCE.md#prule-044-effective-authorization-on-every-protected-read-and-command)'s and is
consumed here, not restated.

### One adjacent distinction, recorded so it is not mistaken for a permission

Under ratified OD-019 the five low-cost operation strings a metered read declares are **metering classes,
not authorization tokens**. `report.view`, `history.view` and `score.read` do not exist in the Permission
Baseline at all. A read is authorized by its own named permission and metered by its declared operation;
neither substitutes for the other ([MTX-091](SECURITY_PERFORMANCE.md#prule-040-usage-accounting)).

**No slice fails to apply PRULE-046.** All 24 record an exact idempotency identity, an audit set under one
correlation ID and an observability contract against the three envelopes. Only the OD-032 namespace limb is
withheld.

---

## SECURITY_PERFORMANCE.md

## PRULE-044 Effective Authorization On Every Protected Read And Command

Matrix row: MTX-095 (AC-PRULE-044). Slice: `ALL`.
Structured contract: `specification/volume-ii/contracts/S-XC.json`.
Governing authority: PRULE-044; WORKFLOW_SPECIFICATIONS.md Actor Resolution, Permission Baseline and Role
Assignment And Policy Artifact (the six-step effective-authorization algorithm); SEC-REQ-004 through
SEC-REQ-009 and SEC-REQ-013; CAP-001 through CAP-025; WF-001 through WF-018; OD-012, OD-013, OD-020,
OD-026 (all **settled**).

### One facade, because a controller is not a boundary

PRULE-044 binds every capability and every workflow — all 24 slices, without exception. The reason it
cannot live in a controller is structural rather than stylistic: the same protected behaviour is reachable
from routed requests, service identities, background jobs, event consumers and lifecycle sweeps. A check
placed at the transport edge is bypassed by four of those five.

Volume II already resolves this at one place. `Platform::AuthenticatedRequest` step 5 resolves the
authorization epoch, Assignments, policies, support scope and classification through
`IdentityAccess::Public::Authorize`, and every command handler and query handler performs its named object
and field authorization through **that same sole facade**. Authorization resolves *inside* the unit of
work — after the Organization row is acquired at tier one and the Account and Session rows at tier two,
and before the handler executes — and the authorization and audit records persist at tier fourteen in the
same transaction. A denial and its audit event therefore commit together or not at all.

Every one of the 24 slices records an entry point, and the recorded pattern is consistent:

- **S-01, S-02** — the identity and bootstrap service, before any record is created. There is no route and
  therefore *no controller-only check to bypass*
  ([MTX-026](APPLICATION_LAYER.md#wf-001-onboard-organization-or-invited-account),
  [MTX-002](APPLICATION_LAYER.md#cap-002-organization-setup)).
- **S-03 – S-08** — each application command before validation of the body and before any insert; and
  again at the `Queued -> Running` commit, where policy, entitlement and the OD-018 guard are re-resolved
  ([MTX-030](APPLICATION_LAYER.md#wf-005-execute-crawl-and-ingestion)).
- **S-09 – S-15** — each service command before mutation, with promotion, publication and override
  re-resolving **inside their own committing transaction**, so an authorization result is never carried
  across a state-version boundary ([MTX-033](APPLICATION_LAYER.md#wf-008-calculate-score-from-issues),
  [MTX-034](APPLICATION_LAYER.md#wf-009-generate-recommendations), [MTX-035](APPLICATION_LAYER.md#wf-010-prioritize-and-publish-action-queue)).
- **S-16, S-17** — every read before any field is serialized, object decision strictly before field
  decision ([MTX-018](APPLICATION_LAYER.md#cap-018-reporting-and-dashboarding),
  [MTX-037](APPLICATION_LAYER.md#wf-012-compare-historical-results)).
- **S-19** — the handler, and **again before every single attempt**; the rule's own words are
  *"reauthorize/redact every attempt"* ([MTX-039](APPLICATION_LAYER.md#wf-014-deliver-notifications)).
- **S-20** — three non-interchangeable entry points, and the second is the point of the workflow: the
  command handler; **the retrieval recheck** at checkpoints 1 and 3; and the lifecycle-service expiry
  checkpoint ([MTX-041](APPLICATION_LAYER.md#wf-016-export-reports-and-data)).
- **S-21** — each command, and again on **every collection page**
  ([MTX-043](APPLICATION_LAYER.md#wf-018-investigate-and-audit-security-or-compliance-events)).
- **S-22** — the server-side entitlement checkpoint; *no client-side trust for entitlement decisions*
  ([MTX-040](APPLICATION_LAYER.md#wf-015-enforce-entitlements)).
- **S-23, S-24** — each command, and again at every durable checkpoint of a running privileged operation,
  which stops before the next protected side effect after revocation
  ([MTX-038](APPLICATION_LAYER.md#wf-013-manage-tenant-lifecycle), [MTX-042](APPLICATION_LAYER.md#wf-017-handle-incident-and-recovery)).

### The six steps, in order, and the traps in each

The algorithm is a pure deterministic function — Volume I states that repeating evaluation with the same
frozen inputs yields the same decision — and it is not a set of checks that may be reordered.

1. Authenticate an active nonexpired Session or the expressly named tenant-scoped service identity. **An
   inactive Account or Organization denies before Assignment evaluation** — the ordering is the contract,
   not an optimisation.
2. Resolve exactly one active Organization Access Policy plus every active narrower policy whose scope
   contains the target. Applicable policies combine by **intersection**, so the union of all matching
   denies wins. Missing or conflicting policy is `policy_unavailable` — a *policy* failure, not an
   authority failure, and never `F1-AUTH-403`.
3. Select active Role Assignments whose normalized scope contains the target. Resource containment
   requires exact type and ID membership; Project scope contains that Project and its child resources
   only; an empty non-Organization scope grants **nothing**.
4. Read the role/action cell from `permission-baseline-v1` and apply `permission_mode`, persona,
   support-session and action-specific conditions. **A `deny` cell never becomes allowed by another
   policy**; a conditional cell is allowed only when its stated condition is true.
5. Union the permissions allowed by at least one Assignment, then **subtract** every applicable policy
   deny. Policy deny has precedence over every Role allow. Multiple Assignments never raise classification
   above the strongest ceiling of an Assignment that independently allows the field.
6. Allow only when action, Organization, resource, support-session and classification all pass. Otherwise
   `F1-AUTH-403` with no product side effect.

### Two enforcements of one rule, and neither is redundant

In the **application**, `access-policy-v1` is the mandatory baseline. A later Organization policy may add
denies or narrower scopes but can never turn a baseline deny or conditional cell into an unconditional
allow, raise a classification ceiling, change protected status, introduce a role or persona, broaden
outside the Organization, or leave zero active OrganizationAdmin Accounts able to perform `role.manage`,
`project.create`, `policy.access.manage` and `account.reactivate`. Any of those is `access_policy_invalid`
and changes nothing.

In **PostgreSQL**, every tenant row carries `ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY`
resolving `organization_id = f1_current_organization_id()`, and application code **cannot** make tenant
context authoritative by executing `SET`, `SET LOCAL`, `set_config` or a raw SQL wrapper. A human read
enters through `f1_enter_human_context`; a SecurityOperator read in authorized scope enters through
`f1_enter_scoped_security_context`, which validates the exact active Support Session and Organization
scope. Neither accepts a caller-supplied actor, Service Identity ID or scope
([MTX-037](APPLICATION_LAYER.md#wf-012-compare-historical-results),
[MTX-043](APPLICATION_LAYER.md#wf-018-investigate-and-audit-security-or-compliance-events),
[MTX-038](APPLICATION_LAYER.md#wf-013-manage-tenant-lifecycle)).

The fixtures assert them **independently**: a cross-Organization read is attempted with the application
check stubbed to allow, and RLS must still refuse it.

### An `Actor` line grants no authority, and neither does an operation name

Three recorded findings from the slices, each of which would be an invented permission if trusted the
other way:

- **CAP-016 names TechnicalImplementer as an actor. WF-009 denies it `recommendation.publish`.** The actor
  list is a consumer role, not a publication grant
  ([MTX-034](APPLICATION_LAYER.md#wf-009-generate-recommendations)).
- **The five low-cost operation strings are metering classes.** `report.view`, `history.view` and
  `score.read` do not exist in the Permission Baseline at all, and the coincidence of `issue.read` and
  `recommendation.read` with real tokens grants nothing
  ([MTX-091](#prule-040-usage-accounting)).
- **No principal permission exists** for Check execution, applicability sealing, Citation validation,
  score calculation or promotion, Artifact generation, base-order computation or queue publication — and
  none may be invented. S-09, S-10, S-11, S-13, S-14, S-15 and S-16 each record this against their own
  capability.

Two permissions are denied to **every** role including the one that would seem to own them:
`export.expire` (lifecycle service only, [MTX-087](APPLICATION_LAYER.md#prule-036-export-lifecycle-transitions)) and
`emergency_access.expire` (emergency-access lifecycle service only — a human cannot expire or extend a
Grant, [MTX-023](APPLICATION_LAYER.md#wf-018-investigate-and-audit-security-or-compliance-events)). The one transition no human
can request is the one that most needs to be automatic and exactly-once.

### A Support Session scopes; it does not grant

This phrasing recurs across S-11, S-12, S-16, S-17 and S-21 because it is the trap: a Support Session
scopes an **already-permitted** action to an Organization, resource and action allowlist. It is **not
itself a read grant** and it **never widens** a Permission Baseline cell. A session-scoped SecurityOperator
still cannot reach a permission its baseline cell denies.

Similarly, an explicit `evidence.restricted.read` protected grant raises **only** the granted
OrganizationAdmin's Evidence payload access to `restricted`. It broadens no resource scope and no other
field permission ([MTX-050](#score-visibility-and-redaction-enforcement)).

### Denial is an event, not a gap

An authorization denial returns `F1-AUTH-403`, emits **exactly one** authorization audit event, and
performs no state change and no provider call. The decision record carries the base cell, **every
conditional result**, the applicable denies and the classification ceiling — the conditional results are
what make a conditional cell's *evaluation* reconstructible rather than just its verdict.

S-23's [MTX-069](#prule-018-account-lifecycle-authority) states the relationship precisely: PRULE-018
obliges every **denied** attempt at these entry points to emit its auditable outcome, so an authorization
denial is never silent.

Two error properties are asserted rather than assumed:

- **Indistinguishability where Volume I requires it.** Under ratified OD-016 an unauthorized
  `session.revoke`, a Session outside the actor's authorized scope, and a nonexistent Session identifier
  all return an *indistinguishable* `F1-AUTH-403`, so Session existence is not disclosed
  ([MTX-025](APPLICATION_LAYER.md#wf-013-manage-tenant-lifecycle)).
- **Non-substitution.** A cross-tenant reference in a comparison is `F1-AUTH-403 / tenant_mismatch` and
  **never** a mismatch code — a mismatch code would leak the existence of another Organization's snapshot
  ([MTX-083](#prule-032-comparison-compatibility-and-rebase)).

### The 60-second bound is measured, not assumed

Revocation takes effect on the next protected request, and authorization caches and active sessions MUST
reflect it within 60 seconds. Cache convergence time is recorded per suspension as a **measured** value,
with the `control` queue's 30-second latency alert as the leading indicator for a breach
([MTX-092](#prule-041-suspension-propagation-and-convergence)). The Organization authorization epoch is
the serialization point: policy and Assignment mutation atomically advances it with the last-admin
predicate, so two concurrent removals cannot both pass.

### An authority gap, reported and not invented

This one matters and it is **not** a labelling error.

OD-020's Ratified Behavior grants explicit read rows for the seven customer-facing object classes and then
states that read authority for **security, administrative and internal operational objects** — Support
Session, Incident, Investigation, Legal Hold, Emergency Access Grant, LifecycleDeletionJob and other
deletion jobs, and privileged Billing surfaces — *"remains deny-by-default pending a separate decision"*,
with its Blocking Impact recording that limb as *out of scope for this decision rather than resolved by
it*. The Permission Baseline's own OD-020 binding paragraph repeats it verbatim.

**That separate decision has no OD number and is absent from the register's pending set.** It is therefore
neither a pending Owner Decision this row may withhold against, nor a settled one this row may implement.

The consequence is precise, and it is a Volume I coverage boundary rather than a defect in any slice:
AC-PRULE-044's *"complete permission-matrix allow/deny fixtures"* clause is satisfiable for every
enumerated cell, and is **not** satisfiable for an object class that has no row at all. The position every
affected slice already takes — and the one this row records — is that those reads stay denied on the
authority of the **unregistered pending decision the Permission Baseline names in its own text**, not on
the authority of any blocker tag. Deferring a customer-facing read under a retired tag would be a defect;
deferring a security or administrative read is substantively correct but must be attributed to the right
authority.

This row resolves nothing here and reports it for the owner.

**No slice fails to apply PRULE-044.** All 24 record `tenant_boundary`, `permission_checks` and
`authorization_entry_point` against `permission-baseline-v1` and the Volume I effective-authorization
algorithm. All four of this row's decisions are settled and nothing is withheld.
