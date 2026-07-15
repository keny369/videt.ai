# 001 PRODUCT_ARCHITECTURE_MANUAL

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines the constitutional operating model for the Product Architecture Manual.

All specification work MUST follow this model.

## Purpose

Define manual structure, authority precedence, dependency model, sequencing rules, and controlled change governance.

## Scope

This document governs:

- architecture manual structure and ownership
- immutable foundation layer policy
- dependency and sequencing model
- acceptance and review gates
- implementation gate policy
- foundation change governance

## Dependencies

- [000 OVERVIEW.md](000%20OVERVIEW.md)
- [002 GLOSSARY.md](002%20GLOSSARY.md)
- [003 TERMINOLOGY.md](003%20TERMINOLOGY.md)
- [009 DECISION_FRAMEWORK.md](009%20DECISION_FRAMEWORK.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)
- [../DECISIONS.md](../DECISIONS.md)

## Definitions

- Foundation Layer: Constitutional documents 000 through 020.
- Downstream Specification: Volume and implementation-facing specification that depends on the foundation layer.
- Controlled Change: Normative change with ADR, impact mapping, and compatibility assessment.

## Assumptions

- Documentation-first delivery remains mandatory.
- Repository artifacts remain canonical source of truth.
- Volume II and later work remains paused until required upstream gates pass.

## Constraints

- Upstream constitutional documents MUST NOT depend on downstream implementation choices.
- Downstream specifications MAY depend on upstream specifications.
- Normative foundation changes MUST use controlled change governance.

## Normative Requirements

PM-REQ-001: The immutable foundation layer MUST include [000 OVERVIEW.md](000%20OVERVIEW.md) through [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md).

PM-REQ-002: All downstream specifications MUST reference foundation definitions, principles, and policies instead of redefining them.

PM-REQ-003: Manual authority precedence MUST be:

1. Constitution and governance
2. Foundation layer 000 through 020
3. ADR registry
4. Volume specifications
5. Derived implementation artifacts

PM-REQ-004: Domain coverage MUST include business, market, product, UX, architecture, database, AI, APIs, engineering, operations, finance, security, infrastructure, and implementation.

PM-REQ-005: No new downstream domain chapter MAY start until required upstream dependency gates are met.

PM-REQ-006: Every architecture-impacting change MUST include ADR traceability.

PM-REQ-007: Every foundation document MUST include these sections or an explicitly stricter canonical equivalent with a section mapping declared inline or in [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md):

1. Title
2. Status
3. Authority
4. Purpose
5. Scope
6. Dependencies
7. Definitions
8. Assumptions
9. Constraints
10. Normative Requirements
11. Decisions
12. Non-goals
13. Risks
14. Verification
15. Open Questions
16. Related Documents
17. Change Control

PM-REQ-008: Foundation baseline version MUST be declared as 1.0 and treated as immutable except by controlled change.

PM-REQ-009: Controlled change for foundation documents MUST include:

- ADR reference
- affected downstream document list
- affected tests, diagrams, schemas, and contracts
- compatibility assessment
- migration assessment when applicable

PM-REQ-010: Implementation work MUST NOT begin until foundation and required volume gates are accepted.

### Canonical Dependency Graph

```text
000-020 Immutable Foundation
            |
            v
Volume I Product Foundations
            |
            v
Experience and Interaction
            |
            v
Domain and State
            |
            v
Data and Persistence
            |
            v
Search and Retrieval
            |
            v
AI and Evaluation
            |
            v
API and Integration
            |
            v
Implementation
```

PM-REQ-011: The dependency graph MUST be represented in [INDEX.md](INDEX.md) and MUST govern roadmap sequencing.

PM-REQ-012: Upstream constitutional documents MUST NOT silently depend on downstream implementation choices.

PM-REQ-013: Any foundation document that relies on centralized section mapping MUST include non-applicable section rationale in [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md).

PM-REQ-014: Intra-foundation cross-references MAY be bidirectional for consistency, but they MUST NOT alter authority precedence defined by PM-REQ-003. Contradictions MUST be resolved through ADR-governed updates.

## Decisions

- DEC-001-01: Foundation layer scope is extended to 000 through 020 and declared baseline 1.0.
- DEC-001-02: Dependency sequencing is constitutional and enforced through roadmap and review gates.
- DEC-001-03: Controlled change is mandatory for all normative foundation updates.

## Non-goals

- This document does not define detailed product behavior.
- This document does not define implementation tasks.

## Risks

- Risk: downstream chapters diverge from foundation requirements.
  Mitigation: review gates MUST enforce reference and traceability checks.
- Risk: uncontrolled foundation edits.
  Mitigation: ADR and impact mapping requirements MUST block ungoverned changes.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Foundation completeness 000 to 020 | Index and file inventory review | Chief Architect | Architecture review |
| Dependency and sequencing compliance | Roadmap and state gate review | Chief Architect | Planning gate |
| Controlled change governance | ADR and traceability matrix checks | Chief Architect | PR review |
| Foundation section conformance mappings | Mapping registry and structure review | Chief Architect | PR review |
| Intra-foundation dependency precedence | Cross-reference and contradiction review | Chief Architect | PR review |

## Open Questions

- Which future domains require additional constitutional foundations after 020?
- Which governance checks require automation priority in the next planning cycle?

## Related Documents

- [INDEX.md](INDEX.md)
- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)
- [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md)
- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)

## Change Control

Any normative change to this document MUST:

1. Include ADR reference.
2. Include dependency model impact analysis.
3. Include roadmap and project state impact updates.
4. Update related governance and traceability documents.
