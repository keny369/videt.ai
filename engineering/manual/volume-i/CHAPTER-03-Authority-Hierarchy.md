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

# 4. Authority Scopes

Authority SHALL be resolved by scope before rank, as required by PM-REQ-003.

Every decision SHALL first be classified into exactly one authority scope. Only that scope's precedence ladder SHALL then be applied.

An artefact holds no authority outside its own scope. Outside its scope an artefact is not merely outranked, it is inapplicable, and it SHALL NOT be cited to settle a decision belonging to another scope.

A single global ladder is prohibited. Ranking the Engineering Manual against the Product Specification implies that manual content carries product authority at some rank, which is false in every case.

---

## 4.1 Scope A — Product Behaviour

The canonical owner is the Product Specification, comprising the foundation layer and the volume specifications, as amended only by ratified Owner Decisions and accepted ADRs integrated into their canonical owner.

This scope covers:

- product behaviour
- business rules
- state models
- workflows
- permissions and routes
- API contracts
- schemas
- security rules
- commercial values, legal obligations and operational commitments
- acceptance criteria
- canonical terminology

Precedence within this scope SHALL be:

1. Constitution and governance
2. Foundation layer 000 through 020
3. ADR registry, comprising accepted ADRs and ratified Owner Decisions integrated into their canonical owner
4. Volume specifications
5. Derived implementation artefacts

The Engineering Manual holds no authority in this scope at any rank. This chapter SHALL NOT be read as granting the Engineering Manual a product-behaviour rank above, below or alongside any artefact in this scope. The Engineering Manual SHALL reference the canonical owner instead of restating, resolving or implying product behaviour.

---

## 4.2 Scope B — Engineering Practice

The canonical owner is the Engineering Manual.

This scope covers:

- architectural patterns
- engineering practices
- coding standards
- testing standards
- repository governance
- deployment practices

Precedence within this scope SHALL be:

1. Constitution and governance
2. Accepted ADRs
3. Engineering Manual
4. Source code and tests
5. Operational documentation and informative material

The Product Specification does not define engineering practice. In this scope it is inapplicable rather than superior.

---

## 4.3 Artefact Rules

### Owner Decisions

Owner Decisions (ODs) record authorised product and governance decisions.

An OD is authoritative only when integrated into its canonical owner.

A standalone register entry SHALL NOT be treated as implemented behaviour.

A pending OD SHALL retain its deterministic interim behaviour. No artefact in any scope SHALL resolve a pending OD by implication, example or convenience.

### Architectural Decision Records

ADRs record approved architectural decisions.

Each ADR SHALL:

- identify the decision;
- explain the rationale;
- record alternatives considered;
- document consequences;
- identify approval.

ADRs SHALL NOT contradict the Product Specification.

An accepted ADR authorises the PM-REQ-009 controlled-change process. It SHALL NOT by itself change foundation content. Where a change alters foundation content, the change SHALL be made in the foundation document itself with its impact mapping in the same change set.

### Source Code

Source code is the implementation of the authority governing it.

Source code SHALL:

- implement;
- never reinterpret;
- never extend;
- never weaken

that authority.

If source code conflicts with its governing authority, the source code is defective.

### Tests

Automated tests verify implementation.

Tests SHALL verify behaviour.

Tests SHALL NOT define behaviour.

Where a test conflicts with the Product Specification, the test SHALL be corrected unless the conflict reveals a genuine Specification defect.

### Operational Documentation

Operational documentation includes:

- runbooks;
- deployment guides;
- operational procedures;
- support documentation.

These documents SHALL describe implemented behaviour.

They SHALL NOT establish behaviour.

### Informative Material

Examples, notes, diagrams, presentations and discussion documents are informative.

Informative material SHALL NOT override normative content in any scope.

Where inconsistency exists, informative material SHALL be corrected.

---

# 5. Conflict Resolution

When conflicting information is identified, engineers SHALL:

1. identify the conflicting artefacts;
2. classify the decision into exactly one authority scope;
3. discard artefacts that are inapplicable to that scope;
4. determine the highest authoritative source within that scope;
5. implement according to that source;
6. correct the lower-authority artefact through normal governance.

Conflicts SHALL NOT be resolved by choosing the most convenient interpretation, nor by selecting the scope that produces the preferred outcome.

Where the scope of the decision is itself disputed, affected implementation SHALL stop until the canonical owner resolves the scope.

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