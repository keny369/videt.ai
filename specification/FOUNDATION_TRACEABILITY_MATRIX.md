# Foundation Traceability Matrix

## Purpose

Provide governance-level traceability from constitutional requirements to decisions, verification, and downstream impact.

## Foundation Baseline

- Baseline Version: 1.0
- Scope: Foundation documents 000 through 020

## Matrix

| Requirement Area | Canonical Document | Requirement Identifier | Governing Principle | Related ADR | Verification Method | Planned Automated Test Or Fitness Function | Downstream Specifications Affected | Current Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Foundation completeness | [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md) | PM-REQ-001 | Constitutional source of truth | ADR-006, ADR-012 | Index and file inventory review | Documentation coverage check FF-011 | All volumes and downstream specs | Active |
| Dependency sequencing | [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md) | PM-REQ-011, PM-REQ-012 | Upstream before downstream | ADR-008 | Roadmap and state gate review | Layering check FF-003 | All downstream layers | Active |
| Canonical terms | [003 TERMINOLOGY.md](003%20TERMINOLOGY.md) | Rule 1, Rule 7 | Terminology consistency | ADR-006 | Terminology review checklist | Documentation lint and keyword scan | All volumes and APIs | Active |
| Foundation structure policy | [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md) | DOC-REQ-001 | Structured constitutional docs | ADR-012 | Document structure review | Documentation lint rule set | Foundation docs and volume docs | Active |
| Documentation-as-code | [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md) | DOC-REQ-010 through DOC-REQ-026 | Single source for docs and behavior | ADR-010 | PR review and generated artifact checks | Documentation drift check FF-011 | Engineering and API specs | Active |
| Traceability chain | [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md) | DOC-REQ-027, DOC-REQ-028 | Requirement to operational evidence continuity | ADR-010 | Traceability matrix review | Traceability completeness check planned | All downstream specs | Active |
| TDD discipline | [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md) | ENG-REQ-006 through ENG-REQ-022 | Red, Green, Refactor default | ADR-009 | CI evidence and PR policy checks | Test posture check FF-005 | Implementation layer | Active |
| TDD exception governance | [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md) | ENG-REQ-023 through ENG-REQ-025 | Controlled exceptions only | ADR-009 | Exception registry audit | Exception compliance check planned | Implementation layer | Active |
| Architecture fitness framework | [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md) | ARC-REQ-008 through ARC-REQ-010 | Measurable architecture policy | ADR-011 | Fitness catalog audit | FF-001 through FF-026 | Architecture and implementation layers | Active |
| Dependency cycles | [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md) | FF-001 | Boundary integrity | ADR-011 | CI dependency analysis | FF-001 | Domain and implementation specs | Planned automation |
| Module boundaries | [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md) | FF-002 | Explicit ownership boundaries | ADR-011 | Architecture test review | FF-002 | Domain and implementation specs | Planned automation |
| API compatibility | [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md) | FF-012 | Consumer stability | ADR-011 | Contract compatibility review | FF-012 | API and integration specs | Planned automation |
| AI evaluation regression | [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md) | FF-022 | AI quality protection | ADR-011 | AI benchmark review | FF-022 | AI and evaluation specs | Planned automation |
| Domain entity governance | [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md) | DM-REQ-001 through DM-REQ-019 | Domain-centered architecture | ADR-008 | Domain model review and invariant checks | Architecture tests FF-002, FF-003 | Domain, state, data, API specs | Active |
| Scope boundary control | [012 SYSTEM_BOUNDARIES.md](012%20SYSTEM_BOUNDARIES.md) | SB-REQ-001 through SB-REQ-029 | Scope containment | ADR-008 | Scope review gate | Responsibility leakage check planned | Product, UX, API specs | Active |
| Quality attribute gating | [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md) | QA-REQ-001 through QA-REQ-025 | Measurable non-functional controls | ADR-011 | SLO and quality evidence review | FF-015, FF-017, FF-025 | Architecture, operations, AI specs | Active |
| Security architecture | [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md) | SEC-REQ-001 through SEC-REQ-040 | Security by default | ADR-012 | Security test and review evidence | FF-019, FF-020, FF-021 | All downstream specs | Active |
| Data lifecycle controls | [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md) | DLC-REQ-001 through DLC-REQ-032 | Data governance and auditability | ADR-012 | Lifecycle and retention review | Schema compatibility FF-013 | Data, API, operations specs | Active |
| Canonical state transitions | [016 STATE_MODEL.md](016%20STATE_MODEL.md) | SM-REQ-001 through SM-REQ-010 | Deterministic lifecycle control | ADR-008 | State transition test suite | Architecture test FF-002 | Domain, data, implementation specs | Active |
| Canonical error taxonomy | [017 ERROR_MODEL.md](017%20ERROR_MODEL.md) | ERR-REQ-001 through ERR-REQ-020 | Consistent failure handling | ADR-011 | Error handling and exposure review | Error-rate regression FF-017 | API, UX, operations specs | Active |
| Observability coverage | [018 OBSERVABILITY.md](018%20OBSERVABILITY.md) | OBS-REQ-001 through OBS-REQ-024 | Operability and diagnosability | ADR-011 | Telemetry coverage review | Observability coverage FF-018 | All downstream specs | Active |
| Versioning and compatibility | [019 VERSIONING.md](019%20VERSIONING.md) | VER-REQ-001 through VER-REQ-017 | Controlled evolution | ADR-012 | Compatibility and migration review | API compatibility FF-012, schema compatibility FF-013 | API, data, integration specs | Active |
| Controlled extensibility | [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md) | EXT-REQ-001 through EXT-REQ-026 | Bounded extension model | ADR-013 | Extension policy review | Interface compliance checks planned | Integration and implementation specs | Active |

## Governance Notes

- Matrix rows represent major constitutional controls, not exhaustive requirement enumeration.
- Matrix updates MUST accompany normative foundation changes.
- Missing matrix coverage for new constitutional controls MUST fail review gate.
