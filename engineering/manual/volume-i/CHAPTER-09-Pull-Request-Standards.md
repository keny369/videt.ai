---
title: Pull Request Standards
identifier: EM-I-009
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 9 — Pull Request Standards

## 1. Purpose

This chapter defines the mandatory standards governing Pull Requests (PRs) within the F1 platform.

A Pull Request is the formal engineering review unit through which changes are evaluated, discussed, validated and integrated into the repository.

A Pull Request SHALL demonstrate that an implementation:

- satisfies the Product Specification;
- complies with the Engineering Manual;
- preserves architectural integrity;
- is sufficiently verified;
- is ready for production integration.

A Pull Request SHALL NOT be treated merely as a mechanism for merging code.

---

# 2. Scope

This chapter applies to all Pull Requests affecting:

- source code;
- Product Specification;
- Engineering Manual;
- database schema;
- infrastructure;
- deployment;
- automation;
- configuration;
- documentation with normative effect.

No Pull Request is exempt.

---

# 3. Engineering Philosophy

The objective of a Pull Request is not approval.

The objective is to improve engineering quality.

Every review SHALL assume that defects may exist regardless of the author's seniority, experience or authorship (human or AI).

Review SHALL be collaborative, evidence-based and specification-driven.

---

# 4. Pull Request Requirements

Every Pull Request SHALL:

- address one coherent engineering objective;
- reference the governing Specification identifiers where applicable;
- identify any associated ADRs or Owner Decisions;
- explain the architectural rationale;
- describe implementation impact;
- document any migration or operational considerations;
- identify testing performed.

---

# 5. Mandatory Sections

Every Pull Request description SHALL contain the following sections.

## Summary

A concise explanation of the engineering objective.

---

## Specification References

Canonical identifiers, for example:

- REQ-xxx
- CAP-xxx
- WF-xxx
- API-xxx
- STATE-xxx
- ADR-xxx
- OD-xxx
- EM-I-xxx

Implementation SHALL remain traceable.

---

## Architectural Impact

State whether the change:

- preserves architecture;
- modifies architecture;
- requires an ADR;
- affects layering;
- affects workflow;
- affects persistence;
- affects APIs.

---

## Testing

Identify verification performed, including:

- unit tests;
- integration tests;
- workflow tests;
- contract tests;
- performance tests;
- security tests;
- manual verification where unavoidable.

---

## Operational Impact

Document effects on:

- deployment;
- monitoring;
- logging;
- tracing;
- migrations;
- rollback;
- production support.

---

# 6. Pull Request Size

Pull Requests SHOULD remain focused.

Very large Pull Requests significantly reduce review quality.

Where practical, work SHALL be divided into coherent reviewable units.

Examples:

✓ One workflow implementation.

✓ One database migration.

✓ One specification correction.

✗ Entire subsystem rewrite with unrelated cleanup.

---

# 7. Review Expectations

Reviewers SHALL evaluate:

- correctness;
- architecture;
- maintainability;
- security;
- performance implications;
- observability;
- testability;
- Specification compliance.

Reviewers SHALL NOT approve solely because automated tests pass.

---

# 8. Required Evidence

The author SHALL provide sufficient evidence that the implementation is correct.

Evidence MAY include:

- automated tests;
- validator output;
- architecture diagrams;
- benchmark results;
- screenshots (for UI changes);
- migration plans;
- traceability matrices.

Assertions without evidence SHALL be challenged.

---

# 9. Reviewer Responsibilities

Reviewers SHALL:

- understand the engineering objective;
- review the complete change;
- verify Specification alignment;
- challenge assumptions;
- identify architectural drift;
- confirm adequate testing;
- request clarification where required.

Approval SHALL indicate that the reviewer believes the implementation satisfies repository standards—not merely that the code appears reasonable.

---

# 10. AI-Generated Pull Requests

AI-generated Pull Requests SHALL satisfy exactly the same standards as human-authored Pull Requests.

Additional responsibilities include:

- verification of generated code;
- confirmation of Specification traceability;
- validation of architectural consistency;
- review of generated documentation.

AI provenance SHALL NOT reduce review depth.

---

# 11. Blocking Conditions

A Pull Request SHALL NOT be merged if any of the following apply:

- failing CI;
- unresolved review comments classified as blocking;
- Specification contradiction;
- architectural inconsistency;
- missing traceability;
- undocumented migrations;
- missing tests;
- unresolved security findings;
- unresolved merge conflicts.

---

# 12. Approval Standards

Approval signifies that the reviewer believes:

1. the implementation satisfies the Product Specification;
2. the implementation complies with the Engineering Manual;
3. architectural integrity has been preserved;
4. sufficient verification has occurred;
5. repository quality has not been reduced.

Approval SHALL NOT transfer implementation ownership.

---

# 13. Merge Readiness Checklist

Before merge, the following SHALL be true:

- All blocking comments resolved.
- CI successful.
- Documentation updated.
- Traceability complete.
- Architecture preserved.
- Tests passing.
- Security review completed where applicable.
- Database migrations reviewed.
- Operational impacts documented.
- Reviewer approvals obtained.

---

# 14. Anti-Patterns

The following practices are prohibited:

- "Looks good to me" without review.
- Approval without reading the change.
- Splitting related implementation across undocumented PRs.
- Hidden architectural changes.
- Merging broken builds.
- Ignoring Specification conflicts.
- Accepting AI output without verification.
- Large unrelated formatting-only changes mixed with implementation.

---

# 15. Compliance

Pull Requests that fail to satisfy this chapter SHALL NOT be merged.

Repository governance SHALL favour delayed integration over acceptance of uncertain quality.

---

# Cross References

- EM-I-001 Engineering Philosophy
- EM-I-005 Engineering Principles
- EM-I-007 Repository Governance
- EM-I-008 Branch Strategy
- EM-I-010 Definition of Done
- EM-I-011 Code Review Standard
- Product Specification
- Architectural Decision Records
