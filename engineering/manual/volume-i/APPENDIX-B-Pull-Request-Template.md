# engineering/manual/volume-i/APPENDIX-B-Pull-Request-Template.md

---
title: Appendix B — Pull Request Template
identifier: EM-I-APP-B
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix B — Pull Request Template

## Purpose

This appendix defines the mandatory Pull Request template for all engineering work within the F1 platform.

Every Pull Request SHALL use this template unless an approved repository governance decision explicitly authorises an alternative.

The purpose of the template is to ensure:

- complete engineering context;
- specification traceability;
- architectural visibility;
- review consistency;
- operational readiness.

---

# Standard Pull Request Template

```markdown
# Summary

Provide a concise description of the engineering objective.

State:

- what changed;
- why the change exists;
- expected engineering outcome.

---

# Engineering Objective

Describe the problem being solved.

Explain:

- business motivation;
- engineering motivation;
- operational motivation.

---

# Specification Traceability

## Product Specification

Reference all applicable identifiers.

Examples:

- REQ-###
- CAP-###
- WF-###
- API-###
- STATE-###
- PR-###
- ERR-###

---

## Engineering Manual

Reference all applicable chapters.

Examples:

- EM-I-006
- EM-II-014
- EM-IV-009

---

## Architectural Decision Records

List applicable ADRs.

Examples:

- ADR-019
- ADR-024

If none:

None.

---

## Owner Decisions

Reference any applicable Owner Decisions.

Examples:

- OD-017
- OD-021

If none:

None.

---

# Architectural Impact

Select one.

- [ ] No architectural change
- [ ] Architectural refinement
- [ ] New architectural decision
- [ ] Existing ADR implemented
- [ ] ADR update required

Explain the architectural consequences.

---

# Components Affected

Identify repository areas.

Examples:

- Domain
- Application
- Infrastructure
- API
- Database
- Frontend
- Background Jobs
- Deployment
- Documentation

---

# Behavioural Impact

Describe:

- externally observable behaviour;
- workflow impact;
- API impact;
- state model impact.

If behaviour is unchanged, explicitly state:

No externally observable behavioural change.

---

# Database Impact

Select all applicable.

- [ ] No schema change
- [ ] New migration
- [ ] Index changes
- [ ] Constraint changes
- [ ] Data migration
- [ ] Rollback required

Provide summary.

---

# Security Review

Describe:

- authentication impact;
- authorisation impact;
- audit impact;
- data protection impact.

If unaffected:

No security behaviour changed.

---

# Performance Review

Describe:

- database implications;
- memory implications;
- CPU implications;
- network implications.

If negligible:

No material performance impact expected.

---

# Observability

Describe additions or changes to:

- structured logging;
- metrics;
- traces;
- dashboards;
- alerts.

If unchanged:

Existing observability remains sufficient.

---

# Testing

List verification performed.

## Unit Tests

...

## Integration Tests

...

## Workflow Tests

...

## Contract Tests

...

## Performance Tests

...

## Manual Verification

...

---

# Operational Impact

Describe:

- deployment requirements;
- feature flags;
- rollout strategy;
- rollback strategy;
- monitoring changes.

---

# Documentation

Confirm documentation updates.

- [ ] Product Specification
- [ ] Engineering Manual
- [ ] ADR
- [ ] API Documentation
- [ ] Runbooks
- [ ] Diagrams
- [ ] None Required

---

# Risks

Describe:

- engineering risks;
- operational risks;
- mitigation.

---

# Technical Debt

Select one.

- [ ] None introduced
- [ ] Debt documented
- [ ] Existing debt reduced

Provide explanation where applicable.

---

# Definition of Done

Confirm.

- [ ] Specification implemented.
- [ ] Engineering Manual complied with.
- [ ] Architecture preserved.
- [ ] Tests passing.
- [ ] Documentation updated.
- [ ] CI successful.
- [ ] Traceability complete.
- [ ] Reviewer guidance included.

---

# Reviewer Guidance

Identify areas requiring particular attention.

Examples:

- concurrency;
- transactions;
- migrations;
- workflow behaviour;
- performance.

---

# Screenshots / Evidence

Attach where appropriate.

Examples:

- UI screenshots;
- benchmark output;
- validator reports;
- architecture diagrams.

---

# Additional Notes

Provide any additional engineering context.
```

---

# Pull Request Review Matrix

Every Pull Request SHALL satisfy the following review matrix.

| Area                          | Required         |
| ----------------------------- | ---------------- |
| Specification Traceability    | Yes              |
| Engineering Manual References | Yes              |
| ADR References                | Where Applicable |
| Testing Evidence              | Yes              |
| Documentation Review          | Yes              |
| Security Review               | Where Applicable |
| Performance Review            | Where Applicable |
| Operational Review            | Yes              |
| CI Success                    | Mandatory        |
| Reviewer Approval             | Mandatory        |

---

# Pull Request Quality Criteria

A Pull Request SHALL be rejected if any of the following are true.

- Missing Specification references.
- Behaviour cannot be traced.
- Architectural impact is unclear.
- Testing evidence absent.
- CI failing.
- Documentation omitted.
- Security considerations ignored.
- Operational consequences undocumented.

---

# AI-Assisted Pull Requests

Where AI materially contributed:

The author SHOULD record:

- AI assistance used;
- human verification completed;
- repository authorities reviewed.

AI authorship SHALL NOT alter review requirements.

---

# Cross References

- EM-I-009 Pull Request Standards
- EM-I-010 Definition of Done
- EM-I-011 Code Review Standard
- EM-I-015 Requirement Traceability
- Product Specification