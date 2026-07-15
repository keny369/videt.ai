# Volume I Product Rules

## Status

- Status: Draft for owner review
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Rule Model

Each rule records:

- stable identifier
- statement
- source requirement references
- owner
- verification method
- related capabilities
- related workflows
- unresolved decision dependency, when applicable

## Rules

| ID | Rule Statement | Source References | Owner | Verification Method | Related Capabilities | Related Workflows | Decision Dependency |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PRULE-001 | Registration MUST require identity validation before active access is granted. | SEC-REQ-001, PM-REQ-003 | Chief Security | Security integration tests and audit log review | CAP-001 | WF-001 | None |
| PRULE-002 | Organization creation MUST assign an accountable administrator. | DOM-REQ-001 | Chief Product | Workflow acceptance tests | CAP-002 | WF-001 | None |
| PRULE-003 | Project activation MUST be blocked until onboarding prerequisites are satisfied. | DOM-REQ-007, BND-REQ-004 | Chief Architect | State transition tests | CAP-003 | WF-002 | None |
| PRULE-004 | Project scope MUST remain within verified source boundaries. | BND-REQ-001, BND-REQ-003 | Chief Architect | Boundary conformance checks | CAP-003, CAP-004 | WF-002, WF-004 | None |
| PRULE-005 | Source verification MUST complete before source activation. | DOM-REQ-009, SEC-REQ-010 | Chief Security | Verification workflow tests | CAP-005 | WF-003 | OD-001 |
| PRULE-006 | Source lifecycle transitions MUST follow defined valid state paths only. | ST-REQ-001 | Chief Architect | State machine conformance tests | CAP-006 | WF-004 | None |
| PRULE-007 | Crawl triggers MUST be authorized and policy-bounded. | SEC-REQ-006, BND-REQ-005 | Chief Security | Authorization and policy tests | CAP-007 | WF-005 | None |
| PRULE-008 | Crawl runs MUST enforce configured depth and resource boundaries. | QA-REQ-007 | Chief Rails | Load and boundary tests | CAP-007 | WF-005 | OD-005 |
| PRULE-009 | Partial crawl failures MUST be visible and attributable at source scope. | OBS-REQ-004, ERR-REQ-003 | Chief Rails | Observability acceptance tests | CAP-008 | WF-005, WF-017 | None |
| PRULE-010 | Evaluation checks MUST produce deterministic outputs for deterministic inputs. | ENG-REQ-005, QA-REQ-002 | Chief Architect | Repeatability tests | CAP-009, CAP-010, CAP-011 | WF-007 | None |
| PRULE-011 | Every published finding MUST reference at least one auditable evidence item. | DOC-REQ-002, DOM-REQ-012 | Chief Architect | Traceability matrix and sample audits | CAP-009, CAP-013 | WF-007 | None |
| PRULE-012 | Content checks MUST emit confidence metadata when used for ranking or recommendations. | QA-REQ-002 | Chief Product | Evaluation output validation | CAP-010 | WF-007 | None |
| PRULE-013 | Structured-data checks MUST preserve validation context for explainability. | QA-REQ-002, DOC-REQ-035 | Chief Architect | Evidence lineage tests | CAP-011 | WF-007 | None |
| PRULE-014 | AI outputs MUST pass schema and citation validation before publication. | AI-REQ-006, AI-REQ-008 | Chief Architect | AI output validation tests | CAP-012 | WF-009 | None |
| PRULE-015 | AI responses MUST be rejected when policy or safety constraints are violated. | AI-REQ-010, SEC-REQ-018 | Chief Security | Safety policy tests | CAP-012 | WF-009 | None |
| PRULE-016 | Evidence records MUST include provenance and retention classification metadata. | DATA-REQ-003, DATA-REQ-006 | Chief Architect | Data model and retention tests | CAP-013 | WF-006, WF-007 | None |
| PRULE-017 | Finding supersession MUST preserve historical lineage and closure rationale. | ST-REQ-006, DOM-REQ-013 | Chief Architect | Historical comparison tests | CAP-014 | WF-007, WF-012 | None |
| PRULE-018 | Account state transitions MUST emit auditable lifecycle events. | DOM-REQ-005, OBS-REQ-002 | Chief Security | Event contract and audit tests | CAP-001 | WF-001 | None |
| PRULE-019 | Organization state transitions MUST enforce active or suspended policy gates. | ST-REQ-002 | Chief Architect | State transition tests | CAP-002 | WF-001 | None |
| PRULE-020 | Verification evidence channel selection MUST be from approved methods only. | SEC-REQ-011 | Chief Security | Verification channel policy tests | CAP-005 | WF-003 | OD-001 |
| PRULE-021 | Source discovery MUST reject non-compliant scope expansions. | BND-REQ-002, BND-REQ-006 | Chief Architect | Boundary enforcement tests | CAP-006 | WF-004 | None |
| PRULE-022 | Recovery actions MUST be explicit, authorized, and audited. | ERR-REQ-004, SEC-REQ-016 | Chief Security | Incident recovery tests | CAP-008 | WF-017 | None |
| PRULE-023 | Duplicate finding creation MUST be prevented by deterministic deduplication logic. | DOM-REQ-014, ENG-REQ-006 | Chief Rails | Deduplication regression tests | CAP-014 | WF-007 | None |
| PRULE-024 | Score calculation MUST include model version attribution. | VER-REQ-004, DOC-REQ-002 | Chief Architect | Score snapshot contract tests | CAP-015 | WF-008 | None |
| PRULE-025 | Score recalculation MUST be explainable via evidence and finding deltas. | QA-REQ-001, DOM-REQ-015 | Chief Product | Historical delta review tests | CAP-015 | WF-008, WF-012 | OD-002, OD-003 |
| PRULE-026 | Recommendation artifacts MUST include rationale, expected impact, and implementation guidance. | PROD-REQ-011 | Chief Product | Artifact quality review rubric | CAP-016 | WF-009 | None |
| PRULE-027 | Recommendations MUST map to one or more findings and evidence references. | DOC-REQ-002, DOM-REQ-012 | Chief Architect | Traceability audits | CAP-016 | WF-009 | None |
| PRULE-028 | Prioritization MUST consider impact, confidence, and effort dimensions. | PROD-REQ-012 | Chief Product | Prioritization logic tests | CAP-017 | WF-010 | None |
| PRULE-029 | Priority order MUST be reproducible for stable inputs and policy versions. | ENG-REQ-005, VER-REQ-004 | Chief Architect | Determinism and regression tests | CAP-017 | WF-010 | None |
| PRULE-030 | Reports MUST expose score movement and issue status with source attribution. | PROD-REQ-014, DOC-REQ-002 | Chief Product | Report acceptance tests | CAP-018 | WF-010 | None |
| PRULE-031 | Dashboard visibility MUST respect role-based data access controls. | SEC-REQ-004 | Chief Security | Authorization UI and API tests | CAP-018 | WF-010 | None |
| PRULE-032 | Historical comparison MUST use stable baseline definitions and run lineage. | VER-REQ-002, DOM-REQ-013 | Chief Architect | Baseline consistency tests | CAP-019 | WF-012 | None |
| PRULE-033 | Reassessment MUST supersede prior findings without deleting historical records. | ST-REQ-006, DATA-REQ-007 | Chief Architect | Reassessment lifecycle tests | CAP-020 | WF-011 | None |
| PRULE-034 | Notifications MUST be policy-routed and recipient-authorized. | SEC-REQ-013, OBS-REQ-005 | Chief Security | Notification policy tests | CAP-021 | WF-014 | OD-004 |
| PRULE-035 | Export requests MUST be scoped, authorized, and time-bounded. | SEC-REQ-014, DATA-REQ-008 | Chief Security | Export policy tests | CAP-022 | WF-016 | None |
| PRULE-036 | Export lifecycle MUST support revoke and expire states with audit records. | ST-REQ-007, OBS-REQ-006 | Chief Architect | Export lifecycle tests | CAP-022 | WF-016 | None |
| PRULE-037 | Incident investigations MUST preserve immutable evidence trail. | SEC-REQ-020, OBS-REQ-007 | Chief Security | Incident audit tests | CAP-023 | WF-017, WF-018 | None |
| PRULE-038 | Administrative remediation actions MUST require privileged authorization and reason capture. | SEC-REQ-021 | Chief Security | Admin action policy tests | CAP-023 | WF-017, WF-018 | None |
| PRULE-039 | Entitlement checks MUST execute server-side before gated actions. | BND-REQ-007, SEC-REQ-022 | Chief Rails | Server-side enforcement tests | CAP-024 | WF-015 | OD-006 |
| PRULE-040 | Entitlement violations MUST return clear, auditable denial reasons. | PROD-REQ-015, OBS-REQ-008 | Chief Product | User-facing denial and telemetry tests | CAP-024 | WF-015 | OD-006 |
| PRULE-041 | Suspension MUST revoke active access immediately. | SEC-REQ-023, ST-REQ-008 | Chief Security | Access revocation tests | CAP-025 | WF-015 | None |
| PRULE-042 | Deletion and archival MUST follow lifecycle retention controls. | DATA-REQ-010, DATA-REQ-011 | Chief Architect | Retention and deletion audits | CAP-025 | WF-016 | None |

## Dependencies

- [INDEX.md](INDEX.md)
- [PRODUCT_DEFINITION.md](PRODUCT_DEFINITION.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
- [../001 PRODUCT_ARCHITECTURE_MANUAL.md](../001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- [../014 SECURITY_MODEL.md](../014%20SECURITY_MODEL.md)
- [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md)
- [../016 STATE_MODEL.md](../016%20STATE_MODEL.md)
- [../017 ERROR_MODEL.md](../017%20ERROR_MODEL.md)
- [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md)

## Change Control

Any rule change MUST:

1. preserve identifier stability
2. update traceability references
3. update affected CAP and WF references
4. update decision dependencies if owner-level choices are impacted
