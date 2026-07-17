---
title: Appendix C — Architectural Decision Record Template
identifier: EM-I-APP-C
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix C — Architectural Decision Record (ADR) Template

## Purpose

This appendix defines the mandatory template for all Architectural Decision Records (ADRs) within the F1 platform.

The template standardises the documentation of significant engineering decisions, ensuring they remain:

- understandable;
- reviewable;
- traceable;
- historically complete;
- maintainable.

Every ADR SHALL use this structure unless superseded by an approved Engineering Manual revision.

---

# ADR Template

```markdown
---
identifier: ADR-###
title:
status:
owner:
date:
reviewers:
supersedes:
superseded_by:
---

# Title

Provide a concise architectural decision title.

---

# Status

One of:

- Proposed
- Under Review
- Accepted
- Superseded
- Withdrawn

---

# Decision Summary

Summarise the decision in one or two paragraphs.

An engineer should understand the decision without reading the remainder of the ADR.

---

# Context

Describe:

- the engineering problem;
- current architecture;
- existing limitations;
- constraints;
- assumptions;
- business context where relevant.

Answer:

Why is this decision necessary?

---

# Decision

Describe the approved architectural decision.

State:

- what will be done;
- what will not be done;
- architectural boundaries;
- implementation expectations.

The decision SHALL be explicit.

---

# Rationale

Explain why this approach was selected.

Discuss:

- engineering reasoning;
- trade-offs;
- maintainability;
- scalability;
- operational implications.

---

# Alternatives Considered

For each alternative include:

## Alternative 1

Description.

Advantages.

Disadvantages.

Reason rejected.

---

## Alternative 2

...

---

# Consequences

Describe expected consequences.

Positive:

- simplicity;
- maintainability;
- consistency;
- performance;
- operational improvements.

Negative:

- migration effort;
- implementation complexity;
- compatibility considerations;
- technical debt.

---

# Risks

Identify:

- engineering risks;
- operational risks;
- security risks;
- migration risks.

Describe mitigation strategies.

---

# Implementation Guidance

Describe implementation expectations.

Include:

- affected layers;
- affected components;
- migration requirements;
- testing expectations;
- documentation updates.

---

# Specification References

Reference governing identifiers.

Examples:

REQ-###

CAP-###

WF-###

API-###

STATE-###

---

# Engineering Manual References

Examples:

EM-I-006

EM-II-004

EM-IV-011

---

# Related ADRs

List related architectural decisions.

---

# Owner Decisions

List applicable Owner Decisions.

---

# Traceability

Implementation SHALL reference this ADR where applicable.

---

# Review Notes

Record significant review comments where beneficial.

---

# Approval

Record:

Decision Owner:

Reviewers:

Approval Date:

Repository Revision:

---

# Change History

| Version | Date | Description |
|----------|------|-------------|
| 1.0 | YYYY-MM-DD | Initial decision |
```

---

# ADR Authoring Guidelines

Every ADR SHALL satisfy the following principles.

## Architectural

The ADR SHALL describe architecture rather than implementation.

Implementation details belong in source code or implementation documentation.

---

## Permanent

An ADR SHALL remain useful years after creation.

Avoid references that depend upon transient implementation details.

---

## Explicit

The decision SHALL be objectively understandable.

Avoid statements such as:

> "This seemed like the best approach."

Instead explain:

- why;
- compared with what;
- under which constraints.

---

## Traceable

Every ADR SHALL reference:

- Product Specification;
- Engineering Manual;
- related ADRs;
- Owner Decisions where applicable.

---

## Reviewable

Another engineer SHALL be capable of independently evaluating whether the decision remains valid.

---

# ADR Review Checklist

Reviewers SHALL confirm:

## Context

- [ ] Problem clearly stated.
- [ ] Constraints identified.
- [ ] Assumptions documented.

---

## Decision

- [ ] Decision unambiguous.
- [ ] Architectural boundaries defined.
- [ ] Scope clear.

---

## Alternatives

- [ ] Real alternatives considered.
- [ ] Trade-offs documented.
- [ ] Selection justified.

---

## Consequences

- [ ] Positive impacts identified.
- [ ] Negative impacts acknowledged.
- [ ] Risks assessed.

---

## Governance

- [ ] Product Specification references included.
- [ ] Engineering Manual references included.
- [ ] Related ADRs identified.
- [ ] Traceability complete.

---

# Anti-Patterns

The following practices are prohibited.

- Recording implementation details instead of architecture.
- Writing ADRs after implementation solely to justify decisions.
- Omitting rejected alternatives.
- Hiding architectural trade-offs.
- Deleting superseded ADRs.
- Treating ADRs as meeting minutes.
- Using ADRs to redefine Product Specification behaviour.

---

# Cross References

- EM-I-012 Architectural Decision Records
- EM-I-003 Authority Hierarchy
- EM-I-015 Requirement Traceability
- Product Specification
