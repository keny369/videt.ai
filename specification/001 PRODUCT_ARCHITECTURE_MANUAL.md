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

PM-REQ-003: Manual authority MUST be resolved by scope before rank. Every decision MUST first be classified into exactly one authority scope; only that scope's precedence ladder MUST then be applied. An artifact holds no authority outside its own scope. Outside its scope an artifact is not merely outranked, it is inapplicable, and it MUST NOT be cited to settle a decision belonging to another scope.

PM-REQ-003.1: The authority scopes and their canonical owners MUST be:

1. Repository governance, owned by the constitution and governance documents. This scope is superior to every other scope.
2. Product behavior, owned by the foundation layer 000 through 020 and the volume specifications, as amended only by ratified Owner Decisions and accepted ADRs integrated into their canonical owner. Product behavior comprises behavior, business rules, state models, workflows, permissions, routes, API contracts, schemas, security rules, commercial values, legal obligations, operational commitments, acceptance criteria, and canonical terminology.
3. Architectural decision, owned by the ADR registry and bounded by product behavior.
4. Engineering practice, owned by the Engineering Manual. Engineering practice comprises architectural patterns, coding, testing, repository, review, and deployment standards.

PM-REQ-003.2: Within the product-behavior scope, precedence MUST be:

1. Constitution and governance
2. Foundation layer 000 through 020
3. ADR registry, comprising accepted ADRs and ratified Owner Decisions integrated into their canonical owner
4. Volume specifications
5. Derived implementation artifacts

PM-REQ-003.3: Within the engineering-practice scope, precedence MUST be:

1. Constitution and governance
2. Accepted ADRs
3. Engineering Manual
4. Source code and tests
5. Operational documentation and informative material

PM-REQ-003.4: The Engineering Manual MUST NOT establish product behavior. It holds no product-behavior authority at any rank and MUST reference the canonical owner instead of restating, resolving, or implying product behavior. Source code, tests, operational documentation, indexes, generated summaries, and examples MUST NOT establish behavior in any scope.

PM-REQ-003.5: An accepted ADR authorizes the PM-REQ-009 controlled-change process; it MUST NOT by itself change foundation content. Where a change alters foundation content, the change MUST be made in the foundation document itself with its impact mapping in the same change set.

PM-REQ-003.6: Where a conflict cannot be resolved because the scope of the decision is itself disputed, affected implementation MUST stop until the canonical owner resolves the scope. Scope ambiguity MUST NOT be resolved by assumption or by selecting the more convenient ladder.

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

PM-REQ-014: Intra-foundation cross-references MAY be bidirectional for consistency, but they MUST NOT alter the authority scope or precedence defined by PM-REQ-003. Contradictions MUST be resolved through ADR-governed updates.

## Decisions

- DEC-001-01: Foundation layer scope is extended to 000 through 020 and declared baseline 1.0.
- DEC-001-02: Dependency sequencing is constitutional and enforced through roadmap and review gates.
- DEC-001-03: Controlled change is mandatory for all normative foundation updates.
- DEC-001-04: Authority is scoped rather than linear. A single global ladder was proved unsound because it forced the Engineering Manual to be ranked against the Product Specification, which invited manual content to be read as product authority at some rank. Scope classification precedes rank, and the Engineering Manual holds no product-behavior authority at any rank.

## Non-goals

- This document does not define detailed product behavior.
- This document does not define implementation tasks.

## Risks

- Risk: downstream chapters diverge from foundation requirements.
  Mitigation: review gates MUST enforce reference and traceability checks.
- Risk: uncontrolled foundation edits.
  Mitigation: ADR and impact mapping requirements MUST block ungoverned changes.
- Risk: scoped authority is misread as granting the Engineering Manual product authority within its own scope.
  Mitigation: PM-REQ-003.4 MUST be enforced as an absolute exclusion rather than a ranking, and review MUST reject manual text that establishes product behavior.
- Risk: a decision is classified into the wrong scope to reach a preferred outcome.
  Mitigation: PM-REQ-003.6 MUST stop implementation on disputed scope, and scope classification MUST be stated in the change set.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Foundation completeness 000 to 020 | Index and file inventory review | Chief Architect | Architecture review |
| Dependency and sequencing compliance | Roadmap and state gate review | Chief Architect | Planning gate |
| Controlled change governance | ADR and traceability matrix checks | Chief Architect | PR review |
| Foundation section conformance mappings | Mapping registry and structure review | Chief Architect | PR review |
| Intra-foundation dependency precedence | Cross-reference and contradiction review | Chief Architect | PR review |
| Authority scope classification and ladder application | Scope statement and precedence review against PM-REQ-003 | Chief Architect | PR review |
| Engineering Manual product-behavior exclusion | Manual ownership audit against PM-REQ-003.4 | Chief Architect | PR review |

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
