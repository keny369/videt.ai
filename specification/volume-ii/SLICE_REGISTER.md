# Volume II Implementation Slice Register

## Status

- Status: Pass A skeleton. Not frozen.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Product-behaviour baseline: `v1.5-volume-i-frozen` (frozen Volume I)
- Engineering-practice baseline: `v1.7-engineering-manual-accepted` (accepted Engineering Manual)

## Authority

This register carries no product authority. Every slice is a grouping of matrix rows, and
every matrix row is derived from an accepted Volume I acceptance criterion. A slice that
cannot name its governing rows is defective. Where this register and Volume I disagree,
Volume I prevails.

## What A Slice Is

A slice is a vertical, independently testable path through the system that produces a user
or system outcome. A slice is never a technical layer: "the persistence layer" and "the API
layer" are not slices, because neither can be verified against an acceptance criterion on
its own.

Each slice is complete when every matrix row assigned to it passes its Volume I acceptance
criteria, and not before.

## Cross-Cutting Rows

Four matrix rows are marked slice `ALL`. These are product rules that span most or all
capabilities, such as tenant isolation and audit obligations. They are not implemented once
in a slice of their own; they are enforced inside every slice and verified in every slice's
test set. A slice is not complete if it satisfies its own rows but breaches a cross-cutting
row.

## Foundation Slice Boundary

S-00 is deliberately bounded. It exists only to make S-01 buildable and MUST NOT become a
platform-build phase. It is complete when S-01 can be implemented and tested, and no later.

S-00 explicitly EXCLUDES: any product route, any product command, any domain aggregate, any
product table beyond what S-01 requires, any background job beyond the adapter S-01 needs,
any AI provider integration, any read model, and any speculative abstraction for later
slices. Anything a later slice needs is built in that slice.

If work in S-00 cannot be justified by "S-01 cannot be implemented or tested without this",
it does not belong in S-00.

## Slice Order

Slices are ordered by dependency. A slice may start when its prerequisites are complete.
S-09 through S-15 form the evaluation pipeline and are strictly ordered, because each
consumes the previous slice's output.

```text
S-00 Foundation
  └─ S-01 Registration and Access
       ├─ S-02 Organization Setup
       │    └─ S-22 Entitlements and Usage
       │    └─ S-23 Account and Organization Lifecycle
       └─ S-03 Project Setup
            └─ S-04 Source Onboarding
                 ├─ S-05 Ownership Verification
                 └─ S-06 Source Discovery and Scope
                      └─ S-07 Crawl Execution and Recovery
                           └─ S-08 Parsing and Validation
                                └─ S-09 Inspection (technical, content, structured)
                                     └─ S-10 AI Discoverability Analysis
                                          └─ S-11 Evidence Capture
                                               └─ S-12 Issues and Adjudication
                                                    └─ S-13 Scoring
                                                         └─ S-14 Recommendations
                                                              └─ S-15 Prioritisation and Action Queue
                                                                   ├─ S-16 Reporting and Dashboard
                                                                   │    └─ S-17 Historical Comparison
                                                                   ├─ S-18 Reassessment
                                                                   └─ S-20 Export and Sharing
S-19 Notifications        (depends on S-01; consumed from S-12 onward)
S-21 Administration and Support Investigation (depends on S-02)
S-24 Incident and Recovery (depends on S-07)
```

## Pass B Status

Pass B is complete: every one of the 97 matrix rows carries a structured contract and 0 rows
remain `Pass B required`. Status below is derived from `IMPLEMENTATION_MATRIX.md` and the
contract sources, which are the canonical owners; where this table and they disagree, they
prevail and this table is defective.

A withheld limb bounds a row rather than blocking it. Every such row's contract is complete and
implementable; one named behaviour is reserved by a pending owner decision and MUST NOT be
effected. See [SPECIFICATION_FREEZE_CANDIDATE.md](SPECIFICATION_FREEZE_CANDIDATE.md) and
[IMPLEMENTATION_BACKLOG.md](IMPLEMENTATION_BACKLOG.md).

| Slice | Status | Rows | Evidence |
| --- | --- | --- | --- |
| S-00 | Specified; no matrix rows | n/a | This register. S-00 implements no product behaviour, so no acceptance criterion maps to it and it has no contract row. |
| S-01 | **Contracts complete** | MTX-001, MTX-026, MTX-052 | `contracts/S-01.json` |
| S-01,S-19,S-23 | **Contracts complete**; limb withheld under OD-023 | MTX-085 | `contracts/S-19.json` |
| S-01,S-23 | **Contracts complete**; limb withheld under OD-032 | MTX-069 | `contracts/S-23.json` |
| S-02 | **Contracts complete** | MTX-002, MTX-070 | `contracts/S-02.json` |
| S-02,S-22 | **Contracts complete** | MTX-053 | `contracts/S-02.json` |
| S-03 | **Contracts complete**; limb withheld under OD-014 | MTX-003, MTX-027, MTX-054 | `contracts/S-03.json` |
| S-03,S-04 | **Contracts complete**; limb withheld under OD-014 | MTX-055 | `contracts/S-03.json` |
| S-04 | **Contracts complete** | MTX-004 | `contracts/S-04.json` |
| S-05 | **Contracts complete** | MTX-005, MTX-028, MTX-051, MTX-056, MTX-071 | `contracts/S-05.json` |
| S-06 | **Contracts complete** | MTX-006, MTX-029, MTX-057, MTX-072 | `contracts/S-06.json` |
| S-07 | **Contracts complete**; limb withheld under OD-027 | MTX-007, MTX-008, MTX-030, MTX-058, MTX-059, MTX-060 | `contracts/S-07.json` |
| S-07,S-21 | **Contracts complete** | MTX-073 | `contracts/S-07.json` |
| S-08 | **Contracts complete**; limb withheld under OD-027 | MTX-031 | `contracts/S-08.json` |
| S-09 | **Contracts complete** | MTX-009, MTX-010, MTX-011, MTX-061, MTX-064 | `contracts/S-09.json` |
| S-09,S-11,S-12 | **Contracts complete** | MTX-062 | `contracts/S-09.json` |
| S-09,S-12 | **Contracts complete** | MTX-063 | `contracts/S-09.json` |
| S-10 | **Contracts complete** | MTX-012, MTX-065 | `contracts/S-10.json` |
| S-10,S-14 | **Contracts complete** | MTX-066 | `contracts/S-10.json` |
| S-11 | **Contracts complete**; limb withheld under OD-032 | MTX-013 | `contracts/S-11.json` |
| S-11,S-13,S-14 | **Contracts complete** | MTX-067 | `contracts/S-11.json` |
| S-12 | **Contracts complete** | MTX-014, MTX-032, MTX-046, MTX-048, MTX-049, MTX-074 | `contracts/S-12.json` |
| S-12,S-18 | **Contracts complete** | MTX-068, MTX-084 | `contracts/S-12.json` |
| S-13 | **Contracts complete**; limb withheld under OD-032 | MTX-015, MTX-033, MTX-044, MTX-045, MTX-075 | `contracts/S-13.json` |
| S-13,S-17 | **Contracts complete** | MTX-076 | `contracts/S-13.json` |
| S-14 | **Contracts complete** | MTX-016, MTX-034, MTX-077, MTX-078 | `contracts/S-14.json` |
| S-15 | **Contracts complete** | MTX-017, MTX-035, MTX-079, MTX-080 | `contracts/S-15.json` |
| S-16 | **Contracts complete** | MTX-018, MTX-050 | `contracts/S-16.json` |
| S-16,S-17 | **Contracts complete** | MTX-081 | `contracts/S-16.json` |
| S-16,S-20 | **Contracts complete** | MTX-082 | `contracts/S-16.json` |
| S-17 | **Contracts complete** | MTX-019, MTX-037, MTX-083 | `contracts/S-17.json` |
| S-18 | **Contracts complete** | MTX-020, MTX-036, MTX-047 | `contracts/S-18.json` |
| S-19 | **Contracts complete**; limb withheld under OD-023, OD-032 | MTX-021, MTX-039 | `contracts/S-19.json` |
| S-20 | **Contracts complete** | MTX-022, MTX-041, MTX-086, MTX-087 | `contracts/S-20.json` |
| S-21 | **Contracts complete** | MTX-023, MTX-043, MTX-088, MTX-089 | `contracts/S-21.json` |
| S-22 | **Contracts complete**; limb withheld under OD-035 | MTX-024, MTX-040, MTX-090, MTX-091 | `contracts/S-22.json` |
| S-23 | **Contracts complete**; limb withheld under OD-031, OD-032 | MTX-025, MTX-038, MTX-092, MTX-093 | `contracts/S-23.json` |
| S-24 | **Contracts complete** | MTX-042 | `contracts/S-24.json` |
| ALL (cross-cutting) | **Contracts complete**; limb withheld under OD-032, OD-034 | MTX-094, MTX-095, MTX-096, MTX-097 | `contracts/S-XC.json` |
## Register

| Slice | Title | Outcome | Prerequisites | Dependants | Independent | Withheld |
| --- | --- | --- | --- | --- | --- | --- |
| S-00 | Foundation | A Rails 8 application that can boot, migrate, enqueue, authenticate a request and run its test suite. No product behaviour. | none | S-01 | Yes | n/a |
| S-01 | Registration and Access | A principal can register or accept an invitation and obtain an authorized session. | S-00 | S-02, S-03, S-19 | Yes | none |
| S-02 | Organization Setup | An Organization exists with its baseline access policy and billing entity. | S-01 | S-22, S-23, S-21 | Yes | none |
| S-03 | Project Setup | A Project can be created and activated within an Organization. | S-01 | S-04 | Yes | OD-014 limb |
| S-04 | Source Onboarding | A Source is registered against a Project. | S-03 | S-05, S-06 | Yes | none |
| S-05 | Ownership Verification | Ownership or control of a property is proven. | S-04 | S-06 | Yes | none |
| S-06 | Source Discovery and Scope | Source scope is discovered and controlled. | S-04 | S-07 | Yes | none |
| S-07 | Crawl Execution and Recovery | A Crawl runs, reports progress and recovers. | S-06 | S-08, S-24 | Yes | none |
| S-08 | Parsing and Validation | Crawled Documents are parsed and validated. | S-07 | S-09 | Yes | OD-027 limb |
| S-09 | Inspection | Technical, content and structured-data inspections produce findings. | S-08 | S-10 | Yes | none |
| S-10 | AI Discoverability Analysis | AI analysis produces validated, cited responses. | S-09 | S-11 | Yes | none |
| S-11 | Evidence Capture | Evidence is captured with provenance and lineage. | S-10 | S-12 | Yes | OD-032 limb |
| S-12 | Issues and Adjudication | Issues are created, adjudicated, deduplicated and superseded. | S-11 | S-13 | Yes | none |
| S-13 | Scoring | A score is calculated and attributable to its evidence chain. | S-12 | S-14, S-18 | Yes | OD-032 limb |
| S-14 | Recommendations | Recommendations are generated from Issues. | S-13 | S-15 | Yes | none |
| S-15 | Prioritisation and Action Queue | Recommendations are prioritised and published. | S-14 | S-16 | Yes | none |
| S-16 | Reporting and Dashboard | A customer sees a report with correct visibility and redaction. | S-15 | S-17, S-20 | Yes | none |
| S-17 | Historical Comparison | Two promoted snapshots are compared. | S-16 | none | Yes | none |
| S-18 | Reassessment | A reassessment is scheduled, executed and lineage-tracked. | S-13 | none | Yes | none |
| S-19 | Notifications | A notification is routed and delivered. | S-01 | none | Yes | OD-023 limb |
| S-20 | Export and Sharing | An Export is produced and retrieved. | S-16 | none | Yes | none |
| S-21 | Administration and Support Investigation | Support and investigation operate under audited authority. | S-02 | none | Yes | none |
| S-22 | Entitlements and Usage | Entitlement decisions and usage records are enforced. | S-02 | none | Yes | none |
| S-23 | Account and Organization Lifecycle | Accounts and Organizations move through their lifecycles. | S-02 | none | Yes | OD-031 limb, OD-023 limb |
| S-24 | Incident and Recovery | Incidents are handled and recovery is executed. | S-07 | none | Yes | none |

## Slice Records

Each record below states only what an accepted authority supplies. Interfaces, commands,
persistence, events, jobs and permissions are `Pass B required` unless already fixed by an
accepted authority, because Pass A has no authority to invent them.

### S-00 Foundation

- Outcome: the application boots, migrates, enqueues, authenticates a request, and runs its
  test suite in CI.
- Volume I requirements: none. This slice implements no product behaviour and no acceptance
  criterion maps to it.
- Governing engineering practice: EM-II (architecture), EM-IV (Rails framework standards),
  EM-V (persistence), EM-VI (background processing), EM-X (production), EM-IX (testing).
- Included: application skeleton, layered boundaries, PostgreSQL connection and migration
  harness, Redis and Sidekiq adapter, configuration and secret loading, health endpoint,
  CI pipeline, test harness and factories.
- Excluded: every product route, command, aggregate, event, job and table not required by
  S-01. No speculative abstraction for a later slice.
- Completion criteria: S-01 can be implemented and tested. Nothing further.
- Independent: yes.
- Pending-OD constraints: none.

### S-03 Project Setup

- Outcome: a Project can be created and activated within an Organization.
- Matrix rows: MTX-003 (AC-CAP-003), MTX-027 (AC-WF-002), MTX-054 (AC-PRULE-003),
  MTX-055 (AC-PRULE-004).
- Permitted: `project.create` and `project.activate`, the only Project commands the Volume I
  permission contract defines.
- Withheld under OD-014 / `UPSTREAM-V1-PROJECT-LIFECYCLE-003`: Project pause, resume and
  archive. `016 STATE_MODEL.md` names the four transitions and their events, but Volume I
  defines no command, actor or permission for them, and OD-014 reserves that choice.
  The slice MUST NOT expose a route, control, command, service, job or entity method for
  them, and MUST NOT assign them to `project.activate`.
- Representation permitted, effect withheld: the Project state model includes `paused` and
  `archived`, and AC-CAP-020 and AC-PRULE-045 contain guards that read those states. The
  implementation MAY represent and read them; it MUST NOT provide any path that enters them.
- Completion criteria: MTX-003, MTX-027, MTX-054 and MTX-055 pass for the create and
  activate paths, with the pause/resume/archive paths asserted absent.
- Independent: yes, for the permitted limb.

### S-19 Notifications

- Outcome: a notification is routed, delivered and observable.
- Matrix rows: MTX-021 (AC-CAP-021), MTX-039 (AC-WF-014), MTX-085 (AC-PRULE-034).
- Withheld under OD-023 / `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`: credential rotation
  begin and complete. `integration-interim-v1` requires a "fresh rotation token" to begin
  rotation but defines no issuer, format, lifetime, consumption point, binding or transport.
  This slice owns the capability whose Integration holds the Mailgun Credential, which is
  why the register maps OD-023 to CAP-021 and WF-014 rather than to a credential capability.
- Permitted: delivery, routing, retry and observability against an already-active Credential.
- Completion criteria: MTX-021, MTX-039 and MTX-085 pass for delivery, with rotation begin
  and complete asserted unreachable.
- Independent: yes, for the permitted limb.

### S-23 Account and Organization Lifecycle

- Outcome: Accounts and Organizations move through their accepted lifecycles.
- Matrix rows: MTX-025 (AC-CAP-025), MTX-038 (AC-WF-013), MTX-093 (AC-PRULE-042).
- Withheld under OD-031: routine retention-expiry destruction, under
  `retention-destruction-trigger-interim-v1`.
- Withheld under OD-023: any credential-rotation limb reached from this slice.
- Permitted: the accepted suspend, reactivate, revoke, delete, closure and support paths.
- Independent: yes, for the permitted limbs.

## Pending-Decision Position

Five owner decisions remain pending. The Owner Decision Register records each as
`Volume II — no` for blocking impact under its interim, so none blocks this pass and none
blocks the Volume II baseline. Each withholds a limb:

| OD | Affected rows | Withheld limb | Slice |
| --- | --- | --- | --- |
| OD-014 | MTX-003, MTX-027, MTX-054, MTX-055 | Project pause/resume/archive transition | S-03 |
| OD-023 | MTX-021, MTX-039, MTX-085 | Credential rotation begin/complete | S-19, S-23 |
| OD-027 | MTX-008, MTX-031, MTX-060 | Second IndexingJob per ParsingJob; index-key narrowing | S-07, S-08 |
| OD-031 | MTX-025, MTX-038, MTX-093 | Routine retention-expiry destruction | S-23 |
| OD-032 | MTX-013, MTX-015, MTX-021, MTX-025, MTX-045, MTX-069, MTX-097 | Canonical namespace for an unassigned record | S-11, S-13, S-19, S-23 |

No slice may implement a withheld limb. No slice is blocked in full by a withheld limb.
This register resolves no owner decision.

## Change Control

Any change to this register MUST:

1. name the matrix rows each slice covers;
2. preserve slice identifiers;
3. keep the dependency order acyclic;
4. keep every withheld limb withheld until its owner decision is ratified and integrated;
5. pass `scripts/validate_volume_ii.py` and its negative controls.
