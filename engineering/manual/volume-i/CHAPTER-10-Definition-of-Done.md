---
title: Definition of Done
identifier: EM-I-010
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 10 — Definition of Done

## 1. Purpose

This chapter defines the mandatory completion criteria for all engineering work undertaken within the F1 platform.

No engineering activity is considered complete merely because code has been written or merged.

Work is complete only when it satisfies every applicable engineering, architectural, operational and governance requirement defined by this Engineering Manual.

The Definition of Done establishes the minimum acceptable quality standard for the repository.

---

# 2. Scope

This chapter applies to every engineering deliverable, including:

- Product Specification changes;
- Engineering Manual updates;
- source code;
- database schema;
- infrastructure;
- APIs;
- frontend;
- background processing;
- deployment automation;
- operational tooling.

Every Pull Request SHALL satisfy the applicable Definition of Done before merge.

---

# 3. Principles

Completion is determined by evidence rather than effort.

Engineering SHALL demonstrate that:

- the implementation is correct;
- the implementation is complete;
- the implementation is reviewable;
- the implementation is maintainable;
- the implementation is operationally supportable.

Partial completion SHALL NOT be represented as complete.

---

# 4. Functional Completion

The implementation SHALL:

- satisfy every referenced Product Specification requirement;
- preserve existing externally observable behaviour unless intentionally changed;
- correctly implement all applicable workflows;
- preserve domain invariants;
- satisfy acceptance criteria.

Implementation SHALL NOT introduce undocumented behaviour.

---

# 5. Engineering Completion

The implementation SHALL:

- comply with this Engineering Manual;
- preserve architectural boundaries;
- avoid duplicated business logic;
- avoid unnecessary complexity;
- maintain repository standards;
- remain deterministic.

---

# 6. Traceability

Every implementation SHALL identify its governing authorities.

Where applicable, references SHALL include:

- REQ
- CAP
- WF
- API
- STATE
- ADR
- OD
- EM

Traceability SHALL be sufficiently detailed that an independent reviewer can determine why the implementation exists.

---

# 7. Testing

Applicable automated verification SHALL pass.

Testing SHALL include all relevant categories, including:

- unit tests;
- integration tests;
- workflow tests;
- contract tests;
- regression tests;
- migration verification;
- security testing where applicable;
- performance testing where applicable.

Where automated verification is not practical, manual verification SHALL be documented.

---

# 8. Documentation

Documentation SHALL be updated whenever implementation changes behaviour or engineering practice.

Documentation includes:

- Product Specification;
- Engineering Manual;
- ADRs;
- API documentation;
- operational runbooks;
- deployment procedures;
- diagrams;
- examples.

Documentation SHALL NOT lag implementation.

---

# 9. Code Quality

Implementation SHALL:

- compile successfully;
- pass static analysis;
- satisfy formatting standards;
- contain no debugging artefacts;
- contain no dead code;
- contain no commented-out production logic;
- avoid unnecessary warnings.

---

# 10. Database Changes

Where persistence changes occur:

- migrations SHALL be reviewed;
- rollback strategy SHALL be documented;
- data integrity SHALL be preserved;
- constraints SHALL align with the canonical state model;
- indexes SHALL be reviewed;
- migration risk SHALL be assessed.

---

# 11. Security

Security review SHALL confirm:

- authorisation is correct;
- authentication is unaffected unless intended;
- secrets are protected;
- input validation exists;
- audit requirements remain satisfied;
- no new attack surface has been introduced.

Security SHALL NOT be deferred.

---

# 12. Observability

Every production feature SHALL be observable.

Where appropriate the implementation SHALL provide:

- structured logging;
- metrics;
- tracing;
- audit records;
- operational diagnostics.

Support teams SHALL be capable of diagnosing failures without modifying production code.

---

# 13. Performance

Performance SHALL be considered before completion.

Engineering SHALL confirm that implementation:

- introduces no unnecessary database queries;
- avoids unnecessary network traffic;
- avoids excessive allocations;
- avoids avoidable blocking operations;
- satisfies documented performance expectations.

Performance optimisation SHALL preserve correctness.

---

# 14. Review

Implementation SHALL receive the required engineering review.

Approval SHALL confirm compliance with:

- Product Specification;
- Engineering Manual;
- architectural standards;
- repository governance.

Outstanding blocking review comments SHALL prevent completion.

---

# 15. CI Requirements

The complete Continuous Integration pipeline SHALL succeed.

At minimum:

- build;
- tests;
- validation;
- linting;
- security scanning (where configured);
- documentation generation (where configured).

No implementation SHALL be merged while CI is failing.

---

# 16. Operational Readiness

Where operational impact exists, the implementation SHALL provide:

- deployment instructions;
- rollback procedure;
- monitoring updates;
- alert updates;
- migration plan;
- support documentation.

Operational readiness is part of completion.

---

# 17. AI Engineering

AI-generated work SHALL satisfy exactly the same Definition of Done.

Additional verification SHALL include:

- validation of generated code;
- confirmation of Specification traceability;
- architectural review;
- human approval.

AI-generated work SHALL NOT bypass governance.

---

# 18. Completion Checklist

A deliverable is complete only when all applicable statements below are true.

## Functional

- [ ] Behaviour matches the Product Specification.
- [ ] Acceptance criteria satisfied.
- [ ] Workflows verified.
- [ ] Domain invariants preserved.

## Engineering

- [ ] Engineering Manual complied with.
- [ ] Architecture preserved.
- [ ] Repository standards satisfied.
- [ ] No unnecessary technical debt introduced.

## Verification

- [ ] Automated tests pass.
- [ ] CI succeeds.
- [ ] Static analysis passes.
- [ ] Validation succeeds.

## Documentation

- [ ] Specification updated where required.
- [ ] Engineering Manual updated where required.
- [ ] ADR updated where required.
- [ ] Operational documentation updated.

## Operations

- [ ] Logging reviewed.
- [ ] Metrics reviewed.
- [ ] Tracing reviewed.
- [ ] Deployment reviewed.
- [ ] Rollback documented.

## Governance

- [ ] Pull Request approved.
- [ ] Traceability complete.
- [ ] Required reviewers approved.
- [ ] No blocking findings remain.

Only when every applicable item is complete MAY the implementation be considered Done.

---

# 19. Compliance

Engineering work failing this Definition of Done SHALL NOT be merged into a protected branch.

Exceptions require explicit approval through the project's governance process and SHALL be documented.

---

# Cross References

- EM-I-001 Engineering Philosophy
- EM-I-005 Engineering Principles
- EM-I-007 Repository Governance
- EM-I-009 Pull Request Standards
- EM-I-011 Code Review Standard
- EM-I-016 Traceability
- Product Specification
- Architectural Decision Records
