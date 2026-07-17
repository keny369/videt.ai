---
title: Requirement Traceability
identifier: EM-I-015
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 15 — Requirement Traceability

## 1. Purpose

Requirement traceability is the mechanism by which every engineering artefact can be traced from business intent through implementation and into operational verification.

The purpose of traceability is to demonstrate, with objective evidence, that:

- every implemented behaviour originates from an approved requirement;
- every requirement has been implemented;
- every implementation has been verified;
- every production behaviour can be explained.

Traceability SHALL exist throughout the complete engineering lifecycle.

---

# 2. Scope

This chapter applies to:

- Product Specification;
- Engineering Manual;
- Architectural Decision Records;
- source code;
- database schema;
- APIs;
- workflows;
- infrastructure;
- automated tests;
- deployment artefacts;
- operational monitoring.

Traceability SHALL not terminate at source code.

---

# 3. Traceability Philosophy

The repository SHALL answer four fundamental questions for every significant engineering artefact.

## Why does it exist?

Reference:

- REQ
- CAP
- WF
- API
- STATE
- ADR
- OD

---

## How is it implemented?

Reference:

- source code;
- migrations;
- infrastructure;
- configuration;
- deployment.

---

## How is it verified?

Reference:

- unit tests;
- integration tests;
- acceptance tests;
- workflow verification;
- security testing;
- performance testing.

---

## How is it operated?

Reference:

- monitoring;
- logging;
- tracing;
- dashboards;
- operational procedures.

---

# 4. Canonical Traceability Chain

The preferred traceability chain is:

```
Business Requirement

↓

Capability

↓

Workflow

↓

API / State Model

↓

Engineering Manual

↓

ADR

↓

Implementation

↓

Automated Tests

↓

Deployment

↓

Production Monitoring

↓

Operational Evidence
```

Every engineering artefact SHOULD participate in this chain where applicable.

---

# 5. Mandatory References

Every implementation SHALL reference its governing authorities.

Typical references include:

```
REQ-012

CAP-018

WF-007

STATE-004

API-013

ADR-019

OD-017

EM-I-006
```

Identifiers SHALL remain stable.

---

# 6. Bidirectional Traceability

Traceability SHALL operate in both directions.

It SHALL be possible to determine:

Requirement → Implementation

and

Implementation → Requirement

Neither direction alone is sufficient.

---

# 7. Implementation Requirements

Every significant implementation SHALL identify:

- governing requirements;
- governing workflows;
- governing ADRs;
- engineering standards applied.

Comments MAY be used where appropriate.

Repository structure MAY provide implicit traceability where consistently enforced.

---

# 8. Testing Traceability

Every acceptance criterion SHALL possess one or more verification methods.

Verification SHALL identify:

- test identifier;
- test type;
- execution environment;
- expected outcome.

Untested requirements SHALL be treated as incomplete.

---

# 9. Operational Traceability

Production behaviour SHALL remain observable.

Operational evidence SHOULD include:

- logs;
- metrics;
- traces;
- audit records;
- dashboards;
- alerts.

Operational evidence SHALL support post-incident investigation.

---

# 10. Change Traceability

Every engineering change SHALL identify:

- why the change occurred;
- affected requirements;
- affected workflows;
- affected tests;
- affected documentation;
- affected operations.

Engineering history SHALL remain reconstructable.

---

# 11. AI Engineering

AI coding agents SHALL preserve traceability.

AI SHALL NOT:

- invent identifiers;
- remove traceability;
- weaken requirement links;
- implement behaviour without governing references.

Missing traceability SHALL be treated as a blocking defect.

---

# 12. Traceability Matrix

Major engineering initiatives SHOULD maintain a traceability matrix.

Example:

| Requirement | Workflow | ADR     | Implementation    | Test   |
| ----------- | -------- | ------- | ----------------- | ------ |
| REQ-021     | WF-005   | ADR-019 | EvaluationService | IT-052 |

Matrices SHALL remain synchronised with implementation.

---

# 13. Review Checklist

Reviewers SHALL confirm:

- governing requirements identified;
- Specification references valid;
- Engineering Manual references valid;
- ADR references correct;
- tests mapped;
- documentation updated;
- operational evidence identified.

---

# 14. Anti-Patterns

The following practices are prohibited.

- Orphan implementation.
- Requirements without implementation.
- Implementation without requirements.
- Tests without governing behaviour.
- Undocumented production behaviour.
- Broken traceability links.
- Invented identifiers.
- Duplicate canonical owners.

---

# 15. Compliance

Engineering work lacking complete traceability SHALL NOT satisfy the Definition of Done.

Traceability SHALL be maintained continuously throughout the lifetime of the platform.

---

# Cross References

- EM-I-003 Authority Hierarchy
- EM-I-007 Repository Governance
- EM-I-009 Pull Request Standards
- EM-I-010 Definition of Done
- EM-I-012 Architectural Decision Records
- Product Specification
