# Product Architecture Manual Index

## Purpose

Define canonical navigation, authority ordering, and dependency sequencing for the Product Architecture Manual.

## Canonical Read Order

1. Constitution and governance
2. Immutable foundation layer 000 through 020
3. Volume I Product Specification Set
4. Downstream domain specifications
5. Derived implementation and operations artifacts

## Dependency Model

```text
000-020 Immutable Foundation
            |
            v
Volume I Product Specification Set
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

Rules:

- Downstream specifications MAY depend on upstream specifications.
- Upstream constitutional documents MUST NOT silently depend on downstream implementation choices.

## Foundation Layer (Immutable)

Foundation Version: 1.0

- [000 OVERVIEW.md](000%20OVERVIEW.md)
- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [002 GLOSSARY.md](002%20GLOSSARY.md)
- [003 TERMINOLOGY.md](003%20TERMINOLOGY.md)
- [004 DESIGN_PRINCIPLES.md](004%20DESIGN_PRINCIPLES.md)
- [005 PRODUCT_PRINCIPLES.md](005%20PRODUCT_PRINCIPLES.md)
- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [008 AI_PRINCIPLES.md](008%20AI_PRINCIPLES.md)
- [009 DECISION_FRAMEWORK.md](009%20DECISION_FRAMEWORK.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)
- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [012 SYSTEM_BOUNDARIES.md](012%20SYSTEM_BOUNDARIES.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)
- [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md)

## Foundation Governance

- Foundation documents are immutable except through controlled change.
- Any normative foundation change MUST include ADR reference and impact mapping.
- All downstream specs MUST declare the referenced foundation version.
- Foundation documents that use stricter equivalent section structures MUST maintain mappings in [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md).

## Volume Layer

### Volume I Product Foundations

- [volume-i/INDEX.md](volume-i/INDEX.md)
- [VOLUME_I_FOUNDATIONS.md](VOLUME_I_FOUNDATIONS.md)
- Status: Accepted; acceptance change set pending commit and tag
- Gate: Accepted baseline MUST be committed and tagged before Volume II starts
- Canonical Rule: The decomposed Volume I set under [volume-i/INDEX.md](volume-i/INDEX.md) is canonical for implementation-ready product specification details. [VOLUME_I_FOUNDATIONS.md](VOLUME_I_FOUNDATIONS.md) remains the strategic umbrella and entry point.

### Volume II And Beyond

- Status: Paused
- Start Condition: Volume I accepted baseline committed and tagged under foundation 1.0 controls
- Scope: implementation-facing experience and interaction design; detailed domain design; PostgreSQL and persistence design; search, crawl, and retrieval design; AI pipeline and evaluation design; physical API and event schemas; Rails application architecture; background processing; integration adapters; deployment and operational design; and TDD implementation sequencing.
- Inheritance Rule: Volume II MUST inherit accepted Volume I behaviour and MUST NOT redefine product meaning without a controlled Volume I change.

## Canonical Diagrams

- [../diagrams/INDEX.md](../diagrams/INDEX.md)

## Foundation Traceability

- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)

## Foundation Section Mapping Registry

- [FOUNDATION_SECTION_MAPPINGS.md](FOUNDATION_SECTION_MAPPINGS.md)

## Dependencies

- [../CLAUDE.md](../CLAUDE.md)
- [../governance/PROJECT_CONSTITUTION.md](../governance/PROJECT_CONSTITUTION.md)
- [../governance/QUALITY_STANDARD.md](../governance/QUALITY_STANDARD.md)
- [../governance/WORKFLOW.md](../governance/WORKFLOW.md)
- [../DECISIONS.md](../DECISIONS.md)
- [../ROADMAP.md](../ROADMAP.md)
- [../PROJECT_STATE.md](../PROJECT_STATE.md)
