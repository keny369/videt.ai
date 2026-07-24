# Project State

> The Snapshot, Baseline Summary, Domain Progress, Active Workstream, Risks and
> Next Checkpoints below are the **specification planning baseline as of
> 2026-07-17** and intentionally lag production implementation. Live engineering
> progress is tracked in [Implementation State](#implementation-state) and on
> `implementation/s01-registration-access`.

## Snapshot

- Date: 2026-07-17
- Status: Volume I is FROZEN at `v1.5-volume-i-frozen` and is the authoritative implementation baseline; the PM-REQ-010 gate for Volume I is satisfied. The RC1 correction programme under ADR-018 is closed and its decisions are integrated under ADR-019 and ADR-020. The Engineering Manual is ACCEPTED at `v1.7-engineering-manual-accepted` as the normative authority for engineering practice only, with no independent product-behaviour authority. Volume II is COMPLETE and IMPLEMENTATION-READY: 97/97 implementation-matrix rows contracted, all 25 contract sources integrated, and the governance repair completed under ADR-023. Seven owner decisions are pending; each withholds one named limb under a deterministic fail-closed interim and none blocks implementation. See [specification/volume-ii/IMPLEMENTATION_READINESS_REPORT.md](specification/volume-ii/IMPLEMENTATION_READINESS_REPORT.md)
- Foundation Baseline: 1.0
- Current Volume I Baseline Tag: `v1.5-volume-i-frozen` (authoritative Volume I implementation baseline, ADR-020); predecessors `v1.4-volume-i-ratified-prelegal` at `b2cb4ca` and `v1.3-volume-i-corrected` at `5d725fa` are retained as history; historical `v1.2-volume-i-frozen` and `v1.1-implementation-ready` are superseded and are not implementation baselines
- Initial Volume II Draft Commit: `7213e9a`
- Current Gate: CLEARED for the Volume II baseline. Under ADR-021 the gate is measured by blocking status rather than by a count. `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023) remain live and pending under their deterministic neutral interims, and each records `Volume II — no`; every other Pass 001 blocker is retired by ratified Owner Decisions integrated under ADR-019 and ADR-020, and ADR-023 re-anchored all 72 sites that still cited one as a live reason. Production implementation may begin at S-01 from [specification/volume-ii/IMPLEMENTATION_BACKLOG.md](specification/volume-ii/IMPLEMENTATION_BACKLOG.md)

## Implementation State

- Date: 2026-07-23
- Branch: `implementation/s01-registration-access` (local only; the origin-trust gate still forbids pushing or moving tags)
- Suite: 678 examples, 0 failures; Zeitwerk and Packwerk clean; Brakeman clean; bundler-audit clean; both databases build from empty with no `db/structure.sql` drift

**The project has crossed from platform construction into workflow implementation.**
The architectural primitives below are complete and are no longer under
construction. New workflows are expected to CONSUME them — validate,
authenticate, authorize, read the target, check the expected version, transition,
emit, record — rather than to extend or redesign them. A review of new work
should ask "does this workflow consume the existing primitives correctly?", not
"should this primitive be reshaped?". Reopening a primitive requires a
demonstrated defect in it, exposed by a real consumer.

### Platform maturity — complete

| Capability | Where it lives |
| --- | --- |
| Identity model and proved tenant context | `f1_enter_context`, `f1_enter_org_context`, `f1_enter_bootstrap_context`; forced RLS on every tenant table |
| Session authorization (org actor) | `IdentityAccess::Authorization::CommandAuthorizer`, `f1_authenticate_session` |
| Permission engine | `Platform::PermissionBaseline` (`permission-baseline-v1`), `authorization_decisions` |
| Service identities | `service_identities`, `Platform::ServiceIdentity`, foreign keys on all six attribution columns, `f1_service_identity_active` |
| Human actor vs service separation | `exactly_one_actor_or_service` plus per-workflow attribution, regression-covered |
| Command ledger | `command_executions`, `command_results`, `Platform::CommandResult`/`Failure`/`ErrorCatalog` |
| Event ledger | `event_registry` with canonical-JSON envelopes and database-recomputed digests |
| Audit | `audit_record_registry` |
| Idempotency and request digests | `idempotency_records`, `Platform::CanonicalJson` |
| Reference registry and non-disclosing resolution | `invitation_reference_registry`, `f1_resolve_invitation_reference` |
| ScheduledAction (durable timers) | `scheduled_actions`, `Platform::ScheduledActions::*`, the 53-literal ratified catalogue |
| Worker/transport authority | restricted transport functions granted to `f1_platform_worker` only; `TransportConnection` off the Active Record pool |
| Time authority | PostgreSQL `transaction_timestamp()` for every deadline; `Platform::Clock` for application-side instants only |
| Concurrency | per-Organization, per-Invitation and per-RoleAssignment advisory locks shared by every transition of that record; `FOR UPDATE SKIP LOCKED` claiming; `RaceHarness` proves both operations in flight before either outcome is released |
| Authority-change serialization | the Organization authorization epoch, advanced in the same transaction as every accepted effective-access mutation; `CommandAuthorizer.authority_current?` is the ratified durable-checkpoint recheck (:333) |
| Last-administrator invariant | `IdentityAccess::Infrastructure::LastAdministratorPredicate` — ONE predicate shared by human revoke and timed expiry (:344 "OD-026 adds no second predicate") |
| Reproducible provisioning | `bin/f1-provision-db`, `F1::RuntimeGrants` as the single grant source, `f1:db:verify_runtime` |

### Application maturity

- **S-02 Organization Setup / tenant genesis complete** (`Workflows::Wf001::BootstrapOrganization`): the self-service commit atomically creates the Organization, Account, baseline BillingEntity, first OrganizationAdmin Assignment, baseline Access and Entitlement policies, BillingEntity-linked Plan Assignment, draft Project and Session, emits exactly the thirteen ordered events, and consumes the Bootstrap Grant — service-attributed, no billing-provider call, one atomic unit proved by rollback injection at every write. `Platform::BaselineContent` is the single canonical source of the three baseline artifacts; the command validates the caller's approved content hashes against it. The genesis is production-reachable: the bootstrapped admin acts through the shared boundary and cannot bypass protected approval.
- Invitation lifecycle complete end to end: create, approve/reject, activate, accept, decline, revoke, expire — one winner under concurrency, exactly one terminal event, no terminal state reopens.
- Organization lifecycle complete: suspend and reactivate under `reactivation-proof-v1`, with suspension's authority invalidation enforced at the shared authorization boundary.
- **Role Assignment and Protected Authority complete**: request, decide (approve/reject), direct activation, revoke, timed expiry, and the OD-026 last-administrator expiry block with its immutable `RoleExpiryBlockDecision`. Protected authority is production-reachable through Request + Decide alone — no fixture writes an allowlist for a principal under test.
- Bootstrap grant issuance and existing-account sign-in complete.
- **S-03 Project Setup — CreateProject limb complete** (`Workflows::Wf002::CreateProject`): an authorized Organization actor (`project.create`, OrganizationAdmin or MarketingOperator) creates one draft Project from a complete `project-profile-v1` body — display name, `en-AU`, `UTC`, `discoverability_assessment`, and either a local-presence reason or an immutable `local-business-profile-v1` whose business name equals the Organization display name and whose canonical content is SHA-256-hashed. Idempotent by key scoped to the Organization; exactly one `ProjectCreated`; production-reachable through the genesis Session; concurrency resolves to one winner + one replay; rollback injection leaves no partial state. The S-02 genesis project creation is unchanged (its reduced first-Project body carries the new profile columns as NULL). Project profile is immutable and the Organization identity and `state` are DB-guarded.
- **S-03 ActivateProject is DEFERRED, not a gap.** WF-002 draft->active is gated on "at least one active same-Project Source" (CAP-003 Product Behavior, WORKFLOW_SPECIFICATIONS.md :659), and an active Source is produced only by CAP-004/CAP-005/CAP-006 — slices S-04 (register), S-05 (verify), S-06 (activate). The projects lifecycle guard refuses every state transition until the activation slice lands and relaxes it for the single draft->active edge under its ratified prerequisites. `project.activate` is intentionally absent from the Permission Baseline until that slice consumes it. The dependency order is CreateProject -> Source register -> verify -> activate -> ActivateProject.
- **S-04 Source Onboarding — RegisterSource limb complete** (`Workflows::Wf004::RegisterSource`): an authorized actor (`source.register` = OrganizationAdmin | MarketingOperator | TechnicalImplementer) registers exactly one **proposed** Source against a draft/active/paused Project from one absolute HTTPS root URI under `source-registration-v1`, with `ascii-host-v1` host normalization, the exact 17-reason first-match order, immutable seven-field provenance (linked to the durable authorization decision), the ratified `(organization_id, project_id, canonical_host)` uniqueness over non-removed Sources, exactly one `SourceRegistered`, and idempotency scoped to the Project (case-only host difference replays; a different host under the same key conflicts). New `sources` table (the first Project-owned table: composite FK `(org,project)->projects(org,id)`, `UNIQUE(org,project,id)`, partial unique host index, forced RLS, `f1_runtime` SELECT/INSERT/UPDATE and never DELETE). The sources lifecycle guard freezes the registration facts and **refuses every state transition** (verify=S-05, activate/disable/remove=S-06). **Source verification and scope are DEFERRED** — no `verification_requests`/`verification_attempts`/`source_set_versions`/`source_scope_change_requests` tables, no `SourceVerified`/`SourceActivated` path, no Project mutation (registration never touches `projects.source_set_version`).
- **FLAGGED Volume I defect (owner-reconciliation, 2026-07-24):** `organization_inactive` is ratified as `F1-AUTH-403` by S-01 sign-in + WF-013 (with passing tests), but S-04.json/WF-004 :406 classify it `F1-DOMAIN-409`. A shared reason_code has one class; per owner decision the existing `F1-AUTH-403` is preserved (no existing slice/test changed) and the conflicting WF-004 mapping is recorded here as a Volume I specification defect. Every other S-04 reason follows S-04.json.
- **S-05 Ownership Verification is HELD pending an owner sequencing decision.** Pre-implementation review found S-05 is not a self-contained slice: it depends on four shared foundations that do not exist and that the spec assigns to other slices (SSRF-safe outbound adapter = S-07 `destination-safety-v1`, which the spec also calls "the only outbound surface"; envelope encryption/key store = foundation + DataLifecycle; Evidence subsystem = CAP-013/S-09; Sidekiq operational wiring), crosses a security-critical outbound-surface ordering defect, and its two governing sources (`contracts/S-05.json` vs `APPLICATION_LAYER` VII:108) name different WF-003 command classes. Full review, the proposed F-01..F-04 foundation tranche, and the required owner decisions are in [S-05_SEQUENCING_REVIEW.md](S-05_SEQUENCING_REVIEW.md). No S-05 code was written; no infrastructure was invented.

### Remaining

Account lifecycle, Support Session, Access Policy activation, Legal Hold and
deletion, then Organization Closure & Identity Retirement (now unblocked on the
BillingEntity side by S-02; still needs the deletion subsystem for its
LifecycleDeletionJob). Ordering stays with
[specification/volume-ii/IMPLEMENTATION_BACKLOG.md](specification/volume-ii/IMPLEMENTATION_BACKLOG.md).

Note on S-02 baseline content: `Platform::BaselineContent` owns the byte
representation of the interim entitlement/plan artifacts (Volume I fixes their
structure but not reproducible bytes — the OD-013 precedent). The metering engine
that INTERPRETS the numeric limits is CAP-024 / S-22 and consumes these bytes
rather than redefining them; do not treat the limits as invented product
behaviour to "correct".

Deliberately deferred, and NOT a gap: the blocked-expiry re-evaluation trigger.
":425 the guard is re-evaluated on each Organization authorization-epoch advance
rather than replayed from a transport queue", and that background exposure
"remains intentionally deferred until the Volume II baseline". The blocked action
completes, its decision persists, and no successor is scheduled. Do not invent a
re-scheduling loop for it.

## Current Objective

Continue [specification/volume-ii/IMPLEMENTATION_BACKLOG.md](specification/volume-ii/IMPLEMENTATION_BACKLOG.md)
in order from the next unbuilt slice. Every workflow now has a complete example
to consume: authenticate through the Session boundary, authorize through the
shared gate, take the record and Organization locks, compare the expected state
version and authorization epoch, transition, advance the epoch in the same
transaction, and write exactly one event, result and audit outcome.

Continue working [specification/volume-ii/IMPLEMENTATION_BACKLOG.md](specification/volume-ii/IMPLEMENTATION_BACKLOG.md) in order. The acceptance criterion is the oracle. Report rather than invent every limb the seven pending decisions reserve, and never resolve one by inference.

## Operating Constraints

- No new governance documents, review packs, matrices, standards, frameworks, indexes, registers, or process documents may be created unless required to remove a demonstrated ambiguity in the product specification itself.
- Treat `v1.5-volume-i-frozen` as the authoritative Volume I implementation baseline; the PM-REQ-010 gate for Volume I is satisfied. Reopening any frozen contract requires a new ADR and, where foundation content is affected, the PM-REQ-009 process. Do not move or replace historical tags.
- Do not edit accepted Volume I behavior for preference, speculative refinement, scope expansion, or governance expansion; only ADR-018 correction-programme changes and controlled defect/owner-decision changes are permitted.
- Permit a Volume I correction after acceptance only for a demonstrated contradiction, non-executable contract, unsafe behavior, invalid acceptance oracle, or an approved owner decision incorporated through controlled change.
- Permit Volume II implementation architecture, but withhold every route, query, control, event shape or job that intersects a recorded upstream blocker.
- Do not infer permission to begin broad implementation from the Volume I freeze or an incomplete Volume II pass.

## Baseline Summary

- Constitution and governance documents are accepted.
- Foundation layer 000 through 020 is authored and integrated.
- Canonical dependency graph is established in manual control documents.
- Canonical diagrams are created and source-controlled.
- TDD, documentation-as-code, and fitness-function policy are established.
- Volume I has been decomposed into a canonical implementation-ready specification set under specification/volume-i.
- Accepted dashboard and history behaviour is deterministic structured data only; AI-generated narrative and its provider calls/placeholders are excluded unless a controlled future Volume I change accepts a separate capability and complete AI contract.
- ADR-017 corrects six demonstrated defects without adding a capability: Mailgun uncertainty, existing-Account sign-in, policy-scheduled reassessment, BillingEntity creation, canonical Evidence vocabulary, and stale CAP-019 wording.

## Domain Progress

- Foundation governance: complete and active
- Volume I Product Foundations: FROZEN at `v1.5-volume-i-frozen`; 27 owner decisions resolved across ADR-019 and ADR-020; the retention/deletion legal package and OD-013 event tenant identity are closed; five non-blocking decisions remain pending (OD-014, OD-023, OD-027, OD-031, OD-032)
- Experience and Interaction: Volume II Pass 001 complete for authorized/unblocked screens; blocked screens are absent
- Domain and State downstream detail: aggregate, workflow, dependency, transaction and lock architecture complete for unblocked behavior
- Data and Persistence downstream detail: PostgreSQL design complete except blocked pretenant/platform/cross-Organization event/audit scope
- Search and Retrieval downstream detail: Pass 001 complete
- AI and Evaluation downstream detail: Pass 001 complete with dormant-provider gates and structured-only dashboard/history behavior
- API and Integration downstream detail: Pass 001 complete for unblocked routes/providers; blocked routes remain absent
- Implementation planning: TDD slices and CI gates specified; broad implementation remains paused

## Active Workstream

1. Preserve every established tag and commit; do not move or delete a baseline.
2. Obtain narrow controlled Volume I corrections for the blockers recorded in the Volume II index that remain live: `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023).
3. Reconcile only the affected Volume II contracts, rerun validation, then freeze the Volume II architecture baseline before broad implementation.
4. Push the two existing commits and corrected tag only after the configured remote is explicitly confirmed as trusted.

## Risks

- Risk: implementation begins from guessed behavior at a frozen-Volume-I gap.
  Mitigation: blocked operations are unreachable and listed centrally in the Volume II index.

- Risk: architecture documents disagree on physical contracts.
  Mitigation: cross-document API/schema/job/security/deployment validation and adversarial role review run before Volume II acceptance.

- Risk: governance artifacts proliferate faster than product specification quality.
  Mitigation: reject new process artifacts unless they remove demonstrated product ambiguity.

- Risk: foundation drift through uncontrolled edits.
  Mitigation: ADR-backed controlled change policy MUST be enforced.

- Risk: quality thresholds remain unresolved at gate deadlines.
  Mitigation: quality attribute owners MUST resolve provisional ranges before gate closure.

## Next Checkpoints

- Resolve only the recorded Volume I blockers that remain live through controlled change — `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023); do not reopen unrelated product behavior or a retired blocker.
- Obtain OD-010 owner approval and exact Measurement Set bytes before complete customer-facing numeric score release.
- OD-011 is closed on 2026-07-17 under ADR-020: `retention-interim-v1` is the approved fixed retention baseline for worldwide availability with principal markets United States, United Kingdom, Australia, New Zealand, Canada and South Africa; qualified external counsel reviewed the position and raised no objection. Its Qualified Legal Approval element was narrowly amended to accept an append-only owner approval record plus a factual counsel-review record, excluding privileged material from this repository by design. See `specification/volume-i/OWNER_DECISION_RECORD_2026-07-17_LEGAL_AND_CLOSURE.md`.
- Revalidate and freeze Volume II only after the blocked contracts are deterministic; accept later Volume I changes only for demonstrated defects or approved owner decisions.
