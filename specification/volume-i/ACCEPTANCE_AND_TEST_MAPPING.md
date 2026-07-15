# Volume I Acceptance And Test Mapping

## Status

- Status: Draft for owner review
- Last Updated: 2026-07-16
- Owner: Chief Rails
- Foundation Version Dependency: 1.0

## Purpose

Define behavioral acceptance criteria for Volume I capabilities and workflows and map each to test intent for later derivation.

This document does not create implementation tests. It defines test-ready criteria and expected verification style.

## Test Type Vocabulary

- TYP-INT: Integration behavior verification
- TYP-E2E: End-to-end workflow verification
- TYP-SEC: Security and authorization verification
- TYP-OBS: Observability and audit evidence verification
- TYP-DATA: Data lifecycle and lineage verification
- TYP-AI: AI policy and output validation verification

## Capability Acceptance Criteria

| Acceptance ID | Capability | Criteria | Planned Test Types |
| --- | --- | --- | --- |
| AC-CAP-001 | CAP-001 | New user registration activates account only after identity validation and emits account lifecycle events. | TYP-INT, TYP-SEC, TYP-OBS |
| AC-CAP-002 | CAP-002 | Organization creation assigns accountable administrator and transitions organization to active state when policy baseline succeeds. | TYP-INT, TYP-SEC |
| AC-CAP-003 | CAP-003 | Project cannot activate until onboarding prerequisites are satisfied and state transition is auditable. | TYP-INT, TYP-OBS |
| AC-CAP-004 | CAP-004 | Property onboarding captures source metadata with tenant-scoped access controls. | TYP-INT, TYP-SEC, TYP-DATA |
| AC-CAP-005 | CAP-005 | Source activation is blocked until approved verification method succeeds. | TYP-E2E, TYP-SEC, TYP-OBS |
| AC-CAP-006 | CAP-006 | Source scope updates enforce boundary constraints and valid source state transitions. | TYP-INT, TYP-SEC |
| AC-CAP-007 | CAP-007 | Authorized crawl trigger creates bounded crawl run with complete status telemetry. | TYP-E2E, TYP-OBS |
| AC-CAP-008 | CAP-008 | Crawl recovery actions are explicit, auditable, and produce terminal state outcomes. | TYP-E2E, TYP-OBS, TYP-SEC |
| AC-CAP-009 | CAP-009 | Technical checks produce deterministic outputs and link to evidence. | TYP-INT, TYP-DATA |
| AC-CAP-010 | CAP-010 | Content checks emit confidence metadata for downstream decisioning. | TYP-INT, TYP-DATA |
| AC-CAP-011 | CAP-011 | Structured-data checks produce explainable validation outcomes with evidence references. | TYP-INT, TYP-DATA |
| AC-CAP-012 | CAP-012 | AI-generated outputs are published only when schema and citation validation pass policy gates. | TYP-AI, TYP-SEC, TYP-OBS |
| AC-CAP-013 | CAP-013 | Evidence records include provenance and retention classification for all published findings. | TYP-DATA, TYP-OBS |
| AC-CAP-014 | CAP-014 | Finding supersession preserves historical lineage across reassessment runs. | TYP-INT, TYP-DATA |
| AC-CAP-015 | CAP-015 | Score snapshots include model version attribution and explainable contribution chain. | TYP-INT, TYP-DATA, TYP-OBS |
| AC-CAP-016 | CAP-016 | Recommendations include rationale, expected impact, and implementation guidance tied to findings. | TYP-INT, TYP-AI |
| AC-CAP-017 | CAP-017 | Prioritization is reproducible for stable inputs and records manual override rationale. | TYP-INT, TYP-OBS |
| AC-CAP-018 | CAP-018 | Reports display score movement and issue status with role-appropriate visibility controls. | TYP-E2E, TYP-SEC |
| AC-CAP-019 | CAP-019 | Historical comparison renders attributable deltas between selected runs. | TYP-INT, TYP-DATA |
| AC-CAP-020 | CAP-020 | Reassessment updates current results while preserving prior run traceability. | TYP-E2E, TYP-DATA |
| AC-CAP-021 | CAP-021 | Notifications route only to authorized recipients and capture delivery outcomes. | TYP-INT, TYP-SEC, TYP-OBS |
| AC-CAP-022 | CAP-022 | Export generation enforces scoped authorization and lifecycle state controls. | TYP-E2E, TYP-SEC, TYP-OBS |
| AC-CAP-023 | CAP-023 | Incident investigation can reconstruct event chain with immutable evidence trail. | TYP-E2E, TYP-OBS, TYP-SEC |
| AC-CAP-024 | CAP-024 | Entitlement enforcement blocks out-of-plan operations with auditable denial reasons. | TYP-INT, TYP-SEC, TYP-OBS |
| AC-CAP-025 | CAP-025 | Suspension revokes access immediately and deletion or archival follows lifecycle policy. | TYP-E2E, TYP-SEC, TYP-DATA |

## Workflow Acceptance Criteria

| Acceptance ID | Workflow | Criteria | Planned Test Types |
| --- | --- | --- | --- |
| AC-WF-001 | WF-001 | Organization and first project onboarding complete with correct initial states and audit events. | TYP-E2E, TYP-OBS |
| AC-WF-002 | WF-002 | Project activation blocks until prerequisites are complete and emits activation events on success. | TYP-E2E, TYP-INT |
| AC-WF-003 | WF-003 | Verification workflow requires approved method and records evidence for decision outcomes. | TYP-E2E, TYP-SEC, TYP-OBS |
| AC-WF-004 | WF-004 | Source scope changes enforce boundary and authorization constraints across lifecycle transitions. | TYP-E2E, TYP-SEC |
| AC-WF-005 | WF-005 | Crawl and ingestion workflow reaches terminal states with source-level telemetry. | TYP-E2E, TYP-OBS |
| AC-WF-006 | WF-006 | Parsing pipeline transforms ingestion artifacts into evaluation-ready inputs with parse-failure visibility. | TYP-INT, TYP-OBS |
| AC-WF-007 | WF-007 | Evaluation workflow creates evidence-linked findings and deterministic check outputs. | TYP-E2E, TYP-DATA |
| AC-WF-008 | WF-008 | Score generation persists attributable snapshots with model-version lineage. | TYP-INT, TYP-DATA |
| AC-WF-009 | WF-009 | Recommendation generation validates schema, citations, and policy compliance before publication. | TYP-AI, TYP-SEC, TYP-OBS |
| AC-WF-010 | WF-010 | Prioritization and publish flow provides explainable ordering and records manual overrides. | TYP-E2E, TYP-OBS |
| AC-WF-011 | WF-011 | Reassessment workflow links runs and updates current findings without deleting history. | TYP-E2E, TYP-DATA |
| AC-WF-012 | WF-012 | Historical comparison produces attributable deltas for selected valid run sets. | TYP-INT, TYP-DATA |
| AC-WF-013 | WF-013 | Role and policy changes enforce least privilege and capture policy diffs in audit trails. | TYP-E2E, TYP-SEC, TYP-OBS |
| AC-WF-014 | WF-014 | Notification dispatch records delivery state and escalates when channels fail. | TYP-INT, TYP-OBS |
| AC-WF-015 | WF-015 | Entitlement checks execute server-side and return clear denial behavior for blocked actions. | TYP-E2E, TYP-SEC |
| AC-WF-016 | WF-016 | Export workflow enforces authorization scope and export lifecycle state transitions. | TYP-E2E, TYP-SEC, TYP-OBS |
| AC-WF-017 | WF-017 | Incident and recovery workflow classifies severity, executes playbook, and records timeline evidence. | TYP-E2E, TYP-OBS |
| AC-WF-018 | WF-018 | Security investigation workflow preserves chain-of-custody and produces auditable investigation summary. | TYP-E2E, TYP-SEC, TYP-OBS |

## Score Model Acceptance Criteria

| Acceptance ID | Model Area | Criteria | Planned Test Types |
| --- | --- | --- | --- |
| AC-SM-001 | Chain Completeness | Every published recommendation traces to findings and evidence. | TYP-DATA, TYP-OBS |
| AC-SM-002 | Score Attribution | Score snapshots persist model version and contribution records. | TYP-DATA, TYP-INT |
| AC-SM-003 | Finding Evidence | Published findings include at least one auditable evidence reference. | TYP-DATA |
| AC-SM-004 | Reassessment Lineage | Supersession and historical run linkage are queryable and complete. | TYP-DATA, TYP-INT |

## Dependencies

- [INDEX.md](INDEX.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md)
- [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)

## Change Control

Any acceptance mapping change MUST:

1. preserve acceptance identifier stability
2. update all affected CAP, WF, and PRULE cross-references
3. update traceability rows
4. identify owner decision dependencies where unresolved controls affect acceptance outcomes
