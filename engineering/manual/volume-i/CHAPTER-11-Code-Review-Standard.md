# engineering/manual/volume-i/CHAPTER-11-Code-Review-Standard.md

---
title: Code Review Standard
identifier: EM-I-011
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 11 — Code Review Standard

## 1. Purpose

This chapter establishes the engineering standard governing code review within the F1 platform.

Code review is the primary mechanism by which engineering quality is preserved before changes become part of the canonical implementation.

The objective of code review is not fault finding.

The objective is to improve correctness, maintainability, architectural integrity and collective ownership of the platform.

Every production change SHALL undergo review unless an emergency governance process explicitly authorises an exception.

---

# 2. Scope

This standard applies to all reviewable engineering artefacts, including:

- application source code;
- infrastructure as code;
- database migrations;
- Product Specification;
- Engineering Manual;
- CI/CD configuration;
- deployment automation;
- operational tooling;
- security policies;
- test suites.

All contributors—including AI coding agents—are subject to this standard.

---

# 3. Review Philosophy

Every review SHALL be guided by the following principles:

- assume good intent;
- review the implementation, not the individual;
- challenge assumptions with evidence;
- preserve architectural integrity;
- improve the implementation before approval;
- leave the repository in a better state than before.

A review is an engineering activity, not an administrative approval.

---

# 4. Reviewer Responsibilities

A reviewer SHALL:

- understand the purpose of the change;
- read the complete change set;
- verify Specification compliance;
- verify Engineering Manual compliance;
- assess architectural impact;
- assess operational impact;
- identify defects;
- identify unnecessary complexity;
- verify traceability;
- ensure sufficient testing has occurred.

Approval indicates professional confidence that the change satisfies repository standards.

---

# 5. Author Responsibilities

The author SHALL provide sufficient information to support effective review.

Every Pull Request SHALL include:

- engineering objective;
- Specification references;
- Engineering Manual references where applicable;
- ADR references where applicable;
- architectural rationale;
- testing evidence;
- deployment considerations;
- rollback considerations where appropriate.

The author SHALL respond constructively to review feedback.

---

# 6. Review Criteria

Every review SHALL consider the following dimensions.

## Functional Correctness

Does the implementation satisfy the Product Specification?

---

## Architectural Integrity

Does the implementation preserve the approved architecture?

---

## Maintainability

Can another engineer understand and maintain the implementation?

---

## Readability

Does the code clearly communicate intent?

---

## Simplicity

Is the implementation simpler than reasonable alternatives?

---

## Security

Have security implications been considered?

---

## Performance

Are obvious performance regressions avoided?

---

## Observability

Can the implementation be diagnosed in production?

---

## Testability

Can the behaviour be verified automatically?

---

## Operational Readiness

Can the implementation be deployed, monitored and supported safely?

---

# 7. Review Depth

Review depth SHALL be proportional to engineering risk.

Examples:

### Low Risk

- documentation corrections;
- comments;
- formatting;
- minor refactoring.

### Medium Risk

- application services;
- queries;
- reporting;
- infrastructure configuration.

### High Risk

- authentication;
- authorisation;
- workflow engine;
- persistence;
- state transitions;
- billing;
- security;
- concurrency;
- distributed systems.

Higher-risk changes SHALL receive correspondingly deeper review.

---

# 8. Blocking Findings

The following findings SHALL block approval until resolved.

- Specification contradiction.
- Architectural violation.
- Security vulnerability.
- Missing authorisation.
- Missing tests.
- Broken CI.
- Incorrect workflow behaviour.
- Data integrity risk.
- Hidden side effects.
- Undocumented migration risk.
- Repository governance violation.

---

# 9. Non-Blocking Findings

Examples include:

- naming improvements;
- documentation enhancements;
- simplification opportunities;
- style suggestions;
- future refactoring ideas.

Non-blocking findings SHOULD still be discussed.

---

# 10. AI Review Requirements

AI-generated code SHALL receive the same review as human-authored code.

Reviewers SHALL NOT assume correctness because:

- the implementation compiles;
- automated tests pass;
- the AI explains its reasoning confidently.

AI-generated implementations SHALL be evaluated solely on engineering evidence.

---

# 11. Reviewer Conduct

Reviewers SHALL:

- be respectful;
- be objective;
- explain reasoning;
- cite Specification or Engineering Manual authority where practical;
- distinguish mandatory changes from recommendations.

Review comments SHOULD educate as well as correct.

---

# 12. Author Conduct

Authors SHALL:

- respond professionally;
- provide clarification when requested;
- avoid defensive argument;
- update documentation where required;
- rerun validation after changes.

Engineering discussion SHALL remain evidence-based.

---

# 13. Approval

A reviewer SHALL approve only when satisfied that:

- the Product Specification is implemented correctly;
- the Engineering Manual has been followed;
- architecture is preserved;
- repository quality has not been reduced;
- sufficient verification has occurred.

Approval SHALL NOT be based on schedule pressure.

---

# 14. Review Checklist

Before approving, reviewers SHALL confirm:

## Specification

- [ ] Behaviour matches Specification.
- [ ] No undocumented functionality introduced.
- [ ] Acceptance criteria remain satisfied.

## Architecture

- [ ] Layer boundaries preserved.
- [ ] Business logic correctly located.
- [ ] Dependencies remain appropriate.

## Engineering

- [ ] Code is understandable.
- [ ] Complexity justified.
- [ ] Duplication avoided.
- [ ] Error handling appropriate.

## Operations

- [ ] Logging sufficient.
- [ ] Metrics appropriate.
- [ ] Tracing considered.
- [ ] Deployment impact understood.

## Verification

- [ ] Tests adequate.
- [ ] CI passes.
- [ ] Documentation updated.
- [ ] Traceability complete.

---

# 15. Anti-Patterns

The following review practices are prohibited:

- approving without reading;
- reviewing only changed lines without surrounding context;
- accepting "it probably works";
- approving because of delivery pressure;
- bypassing required reviewers;
- reviewing personality instead of implementation;
- accepting undocumented architectural changes;
- assuming AI-generated code is self-validating.

---

# 16. Compliance

No production change SHALL be merged without satisfying this review standard.

Repeated failures to comply SHALL be addressed through engineering governance and process improvement.

---

# Cross References

- EM-I-007 Repository Governance
- EM-I-008 Branch Strategy
- EM-I-009 Pull Request Standards
- EM-I-010 Definition of Done
- EM-I-012 Architectural Decision Records
- EM-IX Quality Engineering & Testing
- Product Specification

```