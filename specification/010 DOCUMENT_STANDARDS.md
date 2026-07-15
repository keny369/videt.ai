# 010 DOCUMENT_STANDARDS

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines constitutional documentation standards for all canonical artifacts.

All specification documents MUST comply with these standards.

## Purpose

Define writing, structure, traceability, documentation-as-code rules, and governance requirements.

## Scope

This document applies to:

- foundation documents
- volume specifications
- ADR entries
- canonical diagrams
- generated and source documentation artifacts

## Dependencies

- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [002 GLOSSARY.md](002%20GLOSSARY.md)
- [003 TERMINOLOGY.md](003%20TERMINOLOGY.md)
- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [009 DECISION_FRAMEWORK.md](009%20DECISION_FRAMEWORK.md)

## Definitions

- Canonical Document: Authoritative artifact controlling a concept.
- Generated Documentation: Documentation output produced from source definitions.
- Documentation Drift: Mismatch between requirements, code, tests, and documentation.

## Assumptions

- Canonical requirements remain in version control.
- Documentation and architecture reviews are enforced through merge gates.
- Generated documentation reproducibility is required.

## Constraints

- Canonical terms MUST follow glossary and terminology controls.
- Normative requirements MUST be testable, reviewable, or measurable.
- Contradictions MUST be resolved at canonical source.

## Normative Requirements

### Canonical Structure And Required Sections

DOC-REQ-001: Every foundation document MUST include Title, Status, Authority, Purpose, Scope, Dependencies, Definitions, Assumptions, Constraints, Normative Requirements, Decisions, Non-goals, Risks, Verification, Open Questions, Related Documents, and Change Control. A document MAY satisfy this through stricter equivalent sections with an explicit section mapping.

DOC-REQ-002: Section mappings for stricter canonical structures MUST be explicit and MUST be declared inline or in [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md).

DOC-REQ-003: Empty ceremonial sections MUST NOT be included. Non-applicable sections MUST state rationale.

### Canonical Reference And Terminology Rules

DOC-REQ-004: Documents MUST reference canonical definitions rather than redefining them.

DOC-REQ-005: Terms defined in [002 GLOSSARY.md](002%20GLOSSARY.md) MUST preserve canonical meaning.

DOC-REQ-006: Language conventions from [003 TERMINOLOGY.md](003%20TERMINOLOGY.md) MUST be enforced.

### Writing And Normative Language Rules

DOC-REQ-007: Normative language MUST use RFC-style keywords MUST, MUST NOT, SHOULD, SHOULD NOT, MAY.

DOC-REQ-008: Ambiguous normative wording MUST NOT be used.

DOC-REQ-009: Requirements MUST be testable, reviewable, or measurable.

### Documentation-As-Code Policy

DOC-REQ-010: Documentation MUST live beside the versioned system artifacts it describes for each domain boundary.

DOC-REQ-011: Public interfaces MUST have structured documentation.

DOC-REQ-012: Domain behavior MUST be documented through canonical specifications, executable tests, meaningful type or interface definitions, and concise code-level documentation.

DOC-REQ-013: Code comments MUST explain rationale, constraints, invariants, non-obvious tradeoffs, and failure behavior.

DOC-REQ-014: Code comments MUST NOT restate obvious code semantics.

DOC-REQ-015: Public modules, classes, functions, APIs, events, schemas, configuration, and extension points MUST be documented.

DOC-REQ-016: Documentation generation MUST be deterministic and reproducible.

DOC-REQ-017: Generated documentation MUST NOT be edited manually.

DOC-REQ-018: Source documentation MUST identify canonical ownership.

DOC-REQ-019: Examples SHOULD be executable or test-backed.

DOC-REQ-020: API documentation MUST be generated from canonical interface definitions for each API surface.

DOC-REQ-021: Schema documentation MUST be generated from canonical schema definitions for each schema surface.

DOC-REQ-022: State diagrams SHOULD be generated from canonical state definitions.

DOC-REQ-023: Test names and structure MUST communicate behavioral intent.

DOC-REQ-024: Architectural decisions MUST reference affected code, tests, diagrams, and specifications.

DOC-REQ-025: Documentation drift MUST be treated as build or review failure.

DOC-REQ-026: A change is incomplete when code, tests, and documentation disagree.

### Traceability Chain

DOC-REQ-027: The following traceability chain MUST be maintained and auditable:

```text
Requirement
    -> Decision
    -> Design
    -> Code
    -> Test
    -> Generated Documentation
    -> Operational Evidence
```

DOC-REQ-028: Traceability gaps MUST fail review gate unless approved exception is present.

### Diagram Standards

DOC-REQ-029: Each canonical architecture view MUST have one source-controlled diagram file.

DOC-REQ-030: Diagram labels MUST follow canonical terminology.

DOC-REQ-031: Diagram changes MUST update related specification references in the same change set.

### Review And Change Set Standards

DOC-REQ-032: Every architecture change set MUST include dependency impact and contradiction checks.

DOC-REQ-033: Foundation changes MUST include ADR references and compatibility analysis.

DOC-REQ-034: Roadmap and project state updates MUST accompany sequencing changes.

DOC-REQ-035: Any foundation document change that relies on centralized section mapping MUST update [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md) in the same change set.

## Decisions

- DEC-010-01: Documentation-as-code is constitutional policy.
- DEC-010-02: Traceability chain is mandatory governance control.
- DEC-010-03: Documentation drift is a release-blocking quality issue.

## Non-goals

- This document does not prescribe one documentation generation tool.
- This document does not replace detailed code style guides.

## Risks

- Risk: duplicate narrative sources create contradictions.
  Mitigation: canonical reference requirements and review gates.
- Risk: generated and source docs diverge.
  Mitigation: deterministic generation and drift-failure policy.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Structure and terminology compliance | Documentation lint and review checklist | Chief Architect | PR review |
| Traceability chain coverage | Traceability matrix and link checks | Chief Architect | Review gate |
| Documentation-as-code controls | Build checks for generated artifacts and source ownership | Chief Rails | CI |

## Open Questions

- Which documentation classes require immediate generation automation in the next cycle?
- Which legacy docs need section-mapping upgrades first for full policy alignment?

## Related Documents

- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md)
- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)
- [../diagrams/INDEX.md](../diagrams/INDEX.md)

## Change Control

Any normative change MUST:

1. Include ADR reference.
2. Include impact analysis for traceability and generated documentation.
3. Include affected document and automation updates.
4. Update related verification gates.
