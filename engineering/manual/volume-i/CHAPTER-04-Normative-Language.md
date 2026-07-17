---
title: Normative Language
identifier: EM-I-004
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 4 — Normative Language

## 1. Purpose

Engineering succeeds only when requirements are interpreted consistently.

This chapter establishes the mandatory language used throughout the Engineering Manual and defines how every statement SHALL be interpreted.

Ambiguous language is prohibited in normative engineering documentation.

Every engineer, reviewer and AI coding agent SHALL interpret the keywords defined in this chapter consistently.

---

# 2. Scope

This chapter applies to:

- the Engineering Manual;
- implementation standards;
- engineering policies;
- review checklists;
- templates;
- coding standards;
- operational procedures;
- future Engineering Manual volumes.

It supplements the terminology used by the Product Specification.

---

# 3. Principles

Engineering documentation SHALL:

- communicate one meaning;
- avoid ambiguity;
- distinguish requirements from guidance;
- separate mandatory rules from recommendations;
- minimise interpretation.

Readers SHALL never need to infer whether a statement is mandatory.

---

# 4. Normative Keywords

The following words have the meanings defined below.

These meanings SHALL be applied regardless of ordinary English usage.

---

## SHALL

Indicates an absolute engineering requirement.

Non-compliance constitutes a governance defect.

Example:

> Controllers SHALL NOT contain business rules.

---

## SHALL NOT

Indicates prohibited behaviour.

No exception exists unless explicitly approved through governance.

Example:

> Business logic SHALL NOT be implemented in database migrations.

---

## MUST

Indicates an unconditional technical requirement.

"MUST" is reserved for requirements whose violation would invalidate implementation correctness, security or repository governance.

Example:

> Every Pull Request MUST pass the complete CI pipeline.

---

## MUST NOT

Indicates behaviour that is never acceptable.

Example:

> Engineers MUST NOT invent product behaviour absent from the Product Specification.

---

## SHOULD

Indicates a strong recommendation.

Departure is permitted only when:

- documented;
- justified;
- reviewed;
- consistent with higher authorities.

Example:

> Services SHOULD remain stateless.

---

## SHOULD NOT

Indicates a practice that is generally discouraged.

Departure requires justification.

---

## MAY

Indicates an optional implementation choice.

Use of MAY SHALL NOT alter externally observable behaviour unless authorised by the Product Specification.

---

## MAY NOT

Indicates the absence of permission.

If uncertainty exists, engineers SHALL assume the behaviour is prohibited until explicitly authorised.

---

# 5. Informative Language

The following words are informative only.

- for example
- note
- illustration
- discussion
- rationale
- background

Informative text SHALL NOT introduce engineering obligations.

---

# 6. Prohibited Language

The following expressions SHALL NOT appear in normative engineering standards because they cannot be objectively verified.

- usually
- often
- generally works
- probably
- normally
- where possible
- if practical
- try to
- best effort
- reasonable
- approximately

Where flexibility is required, it SHALL be expressed explicitly through SHALL, SHOULD or MAY.

---

# 7. Requirement Structure

Normative requirements SHOULD follow this structure:

**Actor**

The responsible party.

**Action**

The required behaviour.

**Constraint**

Conditions under which the behaviour applies.

Example:

> Application Services SHALL execute within a database transaction whenever multiple aggregate updates form one logical unit of work.

---

# 8. Requirement Qualities

Every requirement SHALL be:

- atomic;
- testable;
- unambiguous;
- traceable;
- implementable;
- reviewable.

Requirements failing these characteristics SHALL be revised before publication.

---

# 9. Examples

### Correct

> Domain events SHALL be immutable.

This statement is:

- mandatory;
- measurable;
- reviewable.

---

### Incorrect

> Domain events should generally remain immutable where practical.

This statement is ambiguous because:

- "generally" is undefined;
- "where practical" is subjective;
- reviewers cannot determine compliance.

---

### Correct

> Controllers SHALL translate HTTP requests into application commands and SHALL delegate execution to application services.

---

### Incorrect

> Controllers should remain fairly lightweight.

"Fairly lightweight" has no measurable meaning.

---

# 10. AI Interpretation

AI coding agents SHALL interpret normative language exactly as human reviewers.

An AI agent SHALL NOT weaken:

SHALL

into

SHOULD.

Likewise, informative examples SHALL NOT be treated as mandatory implementation requirements.

---

# 11. Review Checklist

Reviewers SHALL verify:

- every mandatory rule uses normative language;
- recommendations are distinguished from requirements;
- prohibited language is absent;
- requirements are objectively testable;
- examples are clearly informative;
- no ambiguous wording remains.

---

# 12. Compliance

Every future Engineering Manual volume SHALL comply with this chapter.

Normative statements failing these rules SHALL be considered documentation defects.

---

# Cross References

- EM-I-001 Engineering Philosophy
- EM-I-002 Engineering Objectives
- EM-I-003 Authority Hierarchy
- EM-I-015 Documentation Standards
- Product Specification
- RFC 2119 (Normative Keywords)
