# Quality Standard

## Purpose

Define canonical quality requirements for document classes in this repository.

## Document Classes

### Constitutional And Foundation Documents

Documents in the immutable foundation layer `specification/000` through `specification/020` MUST comply with structural and governance controls defined in [../specification/010 DOCUMENT_STANDARDS.md](../specification/010%20DOCUMENT_STANDARDS.md).

### Volume And Strategy Documents

Volume-level and strategy documents SHOULD include:

- Purpose
- Scope
- Business rationale
- Functional specification
- Technical specification
- Acceptance criteria
- Risks
- Future evolution
- References

If a section is intentionally not applicable, rationale MUST be stated.

## Change Governance

- Every architecture-impacting change MUST have ADR traceability in [../DECISIONS.md](../DECISIONS.md).
- Changes that affect sequencing MUST update [../ROADMAP.md](../ROADMAP.md) and [../PROJECT_STATE.md](../PROJECT_STATE.md).
- Changes to canonical terminology MUST update [../specification/002 GLOSSARY.md](../specification/002%20GLOSSARY.md) and [../specification/003 TERMINOLOGY.md](../specification/003%20TERMINOLOGY.md).
