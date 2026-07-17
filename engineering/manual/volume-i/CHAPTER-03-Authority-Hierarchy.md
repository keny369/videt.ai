# engineering/manual/volume-i/CHAPTER-03-Authority-Hierarchy.md

---
title: Authority Hierarchy
identifier: EM-I-003
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 3 — Authority Hierarchy

## 1. Purpose

This chapter establishes the authoritative hierarchy governing all engineering decisions within the F1 platform.

Its purpose is to ensure that every engineer, reviewer and AI coding agent resolves ambiguity consistently and that there is always a single authoritative source for every engineering and product decision.

Authority SHALL always flow downward.

Lower-authority artefacts SHALL NOT contradict higher-authority artefacts.

---

# 2. Scope

This hierarchy governs every engineering activity, including:

- architecture
- implementation
- testing
- deployment
- documentation
- operations
- maintenance
- incident response

It applies equally to:

- engineers
- architects
- reviewers
- AI coding agents
- contractors
- automated tooling

---

# 3. Fundamental Rule

Every engineering decision SHALL be traceable to an authoritative source.

If two sources disagree, the source with the higher authority SHALL prevail.

If no authoritative source exists, implementation SHALL stop until governance resolves the ambiguity.

Engineering SHALL NEVER resolve product ambiguity by assumption.

---

# 4. Authority Levels

## Level 1 — Product Specification

The Product Specification is the highest engineering authority.

It defines:

- product behaviour
- business rules
- state models
- workflows
- API contracts
- security rules
- acceptance criteria
- canonical terminology

The Specification SHALL NOT be contradicted by any lower-level artefact.

---

## Level 2 — Engineering Manual

The Engineering Manual defines implementation standards.

It specifies:

- architectural patterns
- engineering practices
- coding standards
- testing standards
- repository governance
- deployment practices

The Engineering Manual SHALL support the Product Specification.

It SHALL NOT redefine product behaviour.

---

## Level 3 — Architectural Decision Records (ADRs)

ADRs record approved architectural decisions.

Each ADR SHALL:

- identify the decision;
- explain the rationale;
- record alternatives considered;
- document consequences;
- identify approval.

ADRs SHALL NOT contradict the Specification.

Where an ADR changes architecture, the Specification SHALL be updated first or concurrently according to repository governance.

---

## Level 4 — Owner Decisions

Owner Decisions (ODs) record authorised product and governance decisions.

An OD is authoritative only when integrated into its canonical owner.

A standalone register entry SHALL NOT be treated as implemented behaviour.

---

## Level 5 — Source Code

Source code is the implementation of the authorities above.

Source code SHALL:

- implement;
- never reinterpret;
- never extend;
- never weaken

the higher authorities.

If source code conflicts with a higher authority, the source code is defective.

---

## Level 6 — Tests

Automated tests verify implementation.

Tests SHALL verify behaviour.

Tests SHALL NOT define behaviour.

Where a test conflicts with the Specification, the test SHALL be corrected unless the conflict reveals a genuine Specification defect.

---

## Level 7 — Operational Documentation

Operational documentation includes:

- runbooks;
- deployment guides;
- operational procedures;
- support documentation.

These documents SHALL describe implemented behaviour.

They SHALL NOT establish behaviour.

---

## Level 8 — Informative Material

Examples, notes, diagrams, presentations and discussion documents are informative.

Informative material SHALL NOT override normative content.

Where inconsistency exists, informative material SHALL be corrected.

---

# 5. Conflict Resolution

When conflicting information is identified, engineers SHALL:

1. identify the conflicting artefacts;
2. determine the highest authoritative source;
3. implement according to the highest authority;
4. correct the lower-authority artefact through normal governance.

Conflicts SHALL NOT be resolved by choosing the most convenient interpretation.

---

# 6. Missing Authority

If no authoritative decision exists:

Implementation SHALL stop.

The engineer SHALL:

- document the ambiguity;
- identify affected components;
- raise an ADR or Owner Decision where appropriate;
- await resolution.

Implementation by assumption is prohibited.

---

# 7. Traceability

Every implementation SHALL be traceable to one or more canonical identifiers.

Typical references include:

- WF-xxx
- CAP-xxx
- API-xxx
- STATE-xxx
- OD-xxx
- ADR-xxx

Engineering Manual references (EM-I-xxx etc.) govern implementation practice and MAY also be referenced where appropriate.

Traceability SHALL be bi-directional wherever practical.

---

# 8. Examples

### Correct

Specification:

```
WF-018 defines emergency-access behaviour.
```

Engineering Manual:

```
Emergency-access services SHALL implement WF-018 using the workflow patterns defined in Volume III.
```

Source Code:

```
EmergencyAccessService
```

implements WF-018.

---

### Incorrect

Source Code introduces:

```
EmergencyAccessService::temporary_override
```

because it "seems useful."

No Specification authority exists.

This implementation SHALL NOT be merged.

---

# 9. Review Checklist

Every reviewer SHALL confirm:

- The implementation references authoritative requirements.
- No lower-level artefact contradicts a higher-level artefact.
- No undocumented behaviour has been introduced.
- Product behaviour originates from the Specification.
- Engineering practices originate from the Engineering Manual.
- Architectural changes reference approved ADRs.
- Source code contains no normative behaviour absent from the Specification.

---

# 10. Compliance

Compliance with this chapter is mandatory.

Any implementation found to contradict the authority hierarchy SHALL be treated as a repository defect requiring correction before merge.

---

# Cross References

- EM-I-001 Engineering Philosophy
- EM-I-002 Engineering Objectives
- EM-I-007 Repository Governance
- EM-I-012 Architectural Decision Records
- Product Specification
- ADR Register
- Owner Decision Register