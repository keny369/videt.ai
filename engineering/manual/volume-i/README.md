# F1 Engineering Manual

**Volume I — Engineering Principles & Governance**

Version: 0.1 Draft

Status: Engineering Publication

Authority Level: Implementation Governance

---

# Purpose

The Engineering Manual establishes the engineering standards governing the implementation of the F1 platform.

It complements the Product Specification.

The Product Specification defines the required behaviour of the platform.

The Engineering Manual defines the engineering standards used to implement that behaviour.

Together they form the authoritative basis for software development.

---

# Scope

This volume defines:

- engineering governance
- implementation philosophy
- architectural authority
- repository governance
- coding governance
- engineering review standards
- traceability requirements
- AI engineering policy
- documentation standards
- Definition of Done
- change governance
- engineering ethics

This volume intentionally does **not** redefine product behaviour.

---

# Authority Hierarchy

Authority SHALL be resolved by scope before rank, as required by PM-REQ-003 and defined normatively in [CHAPTER-03-Authority-Hierarchy.md](CHAPTER-03-Authority-Hierarchy.md).

On product behaviour, the canonical owner is the Product Specification, and precedence SHALL be:

1. Constitution and governance
2. Foundation layer 000 through 020
3. ADR registry, comprising accepted ADRs and ratified Owner Decisions integrated into their canonical owner
4. Volume specifications
5. Derived implementation artefacts

The Engineering Manual holds no product-behaviour authority at any rank.

On engineering practice, the canonical owner is the Engineering Manual, and precedence SHALL be:

1. Constitution and governance
2. Accepted ADRs
3. Engineering Manual
4. Source code and tests
5. Operational documentation and internal implementation notes

No lower authority may contradict a higher authority within the same scope. An artefact cited outside its own scope is inapplicable rather than outranked.

---

# Audience

This manual applies to:

- Principal Engineers
- Staff Engineers
- Senior Engineers
- Software Engineers
- Engineering Managers
- Technical Leads
- Solution Architects
- DevOps Engineers
- QA Engineers
- AI Coding Agents

---

# Normative Language

The following words have normative meaning.

**MUST**

An absolute requirement.

**SHALL**

Mandatory.

**SHOULD**

Strong recommendation.

**MAY**

Optional.

---

# Relationship to the Product Specification

This manual never replaces the Product Specification.

If a conflict exists:

The Specification prevails.

If implementation exposes an error in the Specification:

1. Stop implementation.
2. Raise an ADR.
3. Correct the Specification.
4. Resume implementation.

Never reverse this order.

---

# Repository Layout

The Engineering Manual SHALL reside under:

engineering/
    manual/
        volume-i/
        volume-ii/
        volume-iii/
        ...

---

# Versioning

Each volume maintains independent versions.

Example

Volume I
v1.0

Volume II
v1.0

Volume III
v0.7

Volumes MAY evolve independently provided cross references remain valid.

---

# Engineering Objective

The objective of engineering is not simply to write software.

The objective is to produce software that:

- satisfies the Specification
- is maintainable
- is testable
- is observable
- is secure
- is deterministic
- is evolvable

Every engineering decision SHALL support these objectives.

---

Copyright © F1 Project

All rights reserved.