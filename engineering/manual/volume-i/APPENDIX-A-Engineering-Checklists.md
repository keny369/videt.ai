---
title: Appendix A — Engineering Checklists
identifier: EM-I-APP-A
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix A — Engineering Checklists

## Purpose

This appendix consolidates the mandatory engineering checklists referenced throughout the Engineering Manual.

These checklists are normative.

Completion of a checklist SHALL be supported by objective engineering evidence rather than assumption.

---

# A1. Feature Design Checklist

Before implementation begins, confirm:

## Product Authority

- [ ] Governing Product Specification sections identified.
- [ ] Applicable REQ identifiers identified.
- [ ] Applicable CAP identifiers identified.
- [ ] Applicable WF identifiers identified.
- [ ] Applicable API contracts identified.
- [ ] Applicable State Model identified.
- [ ] Applicable Product Rules identified.

---

## Architecture

- [ ] Applicable ADRs reviewed.
- [ ] Applicable Engineering Manual chapters reviewed.
- [ ] Architectural boundaries understood.
- [ ] Aggregate ownership confirmed.
- [ ] Transaction boundaries understood.
- [ ] Security implications reviewed.
- [ ] Operational impact considered.

---

## Delivery

- [ ] Acceptance criteria identified.
- [ ] Test strategy prepared.
- [ ] Traceability established.
- [ ] Risks documented.
- [ ] Technical debt assessment completed.

---

# A2. Implementation Checklist

Before requesting review:

## Correctness

- [ ] Specification implemented faithfully.
- [ ] No undocumented behaviour introduced.
- [ ] Existing behaviour preserved.
- [ ] Domain invariants maintained.

---

## Engineering

- [ ] Architecture preserved.
- [ ] Layer boundaries maintained.
- [ ] Business logic correctly located.
- [ ] Error handling implemented.
- [ ] Logging reviewed.
- [ ] Metrics considered.
- [ ] Tracing considered.

---

## Repository

- [ ] Branch scope remains coherent.
- [ ] Commit history is meaningful.
- [ ] Documentation updated.
- [ ] Generated artefacts reviewed.
- [ ] Temporary code removed.

---

# A3. Pull Request Checklist

Before opening a Pull Request:

- [ ] Summary complete.
- [ ] Specification references included.
- [ ] ADR references included where applicable.
- [ ] Engineering Manual references included.
- [ ] Testing documented.
- [ ] Operational impact documented.
- [ ] Rollback considered.
- [ ] Migration considerations documented.
- [ ] Traceability verified.

---

# A4. Reviewer Checklist

Reviewers SHALL verify:

## Specification

- [ ] Behaviour matches Product Specification.
- [ ] Acceptance criteria satisfied.
- [ ] No invented functionality.

---

## Architecture

- [ ] Architectural integrity preserved.
- [ ] Dependencies appropriate.
- [ ] Business rules remain canonical.
- [ ] No architectural drift.

---

## Engineering

- [ ] Code understandable.
- [ ] Complexity justified.
- [ ] Duplication avoided.
- [ ] Documentation complete.

---

## Quality

- [ ] Tests adequate.
- [ ] CI passes.
- [ ] Security reviewed.
- [ ] Performance considered.
- [ ] Observability adequate.

---

# A5. Database Checklist

For every schema change:

- [ ] Canonical state model preserved.
- [ ] Constraints reviewed.
- [ ] Foreign keys reviewed.
- [ ] Indexes reviewed.
- [ ] Migration reversible where practical.
- [ ] Rollback documented.
- [ ] Data integrity preserved.
- [ ] Production impact assessed.

---

# A6. Security Checklist

Verify:

- [ ] Authentication correct.
- [ ] Authorisation correct.
- [ ] Least privilege maintained.
- [ ] Secrets protected.
- [ ] Input validation complete.
- [ ] Audit requirements satisfied.
- [ ] Security logging reviewed.

---

# A7. Deployment Checklist

Prior to production deployment:

- [ ] Release approved.
- [ ] Version tagged.
- [ ] CI successful.
- [ ] Monitoring updated.
- [ ] Dashboards updated.
- [ ] Alerts configured.
- [ ] Rollback verified.
- [ ] Runbooks current.

---

# A8. Production Readiness Checklist

Confirm:

- [ ] Health checks implemented.
- [ ] Structured logging available.
- [ ] Metrics exported.
- [ ] Traces available.
- [ ] Alerts configured.
- [ ] Incident procedures updated.
- [ ] Support documentation complete.

---

# A9. AI Engineering Checklist

Before accepting AI-generated work:

- [ ] Repository authorities reviewed.
- [ ] No invented behaviour.
- [ ] Product Specification implemented.
- [ ] Engineering Manual followed.
- [ ] ADRs respected.
- [ ] Architecture preserved.
- [ ] Tests reviewed.
- [ ] Documentation updated.
- [ ] Traceability complete.
- [ ] Human approval obtained.

---

# A10. Release Checklist

Prior to release:

- [ ] Definition of Done satisfied.
- [ ] Version identified.
- [ ] Changelog updated.
- [ ] Documentation complete.
- [ ] Validation complete.
- [ ] Outstanding critical defects resolved.
- [ ] Risk assessment reviewed.
- [ ] Production approval recorded.

---

# Checklist Governance

These checklists SHALL evolve with the Engineering Manual.

No checklist item SHALL be removed without evaluating its impact on repository governance.

Where new engineering practices become mandatory, the relevant checklist SHALL be updated concurrently.

---

# Cross References

- EM-I-007 Repository Governance
- EM-I-009 Pull Request Standards
- EM-I-010 Definition of Done
- EM-I-011 Code Review Standard
- EM-I-015 Requirement Traceability
- EM-I-016 AI Engineering Governance
- EM-I-017 Engineering Metrics and Quality Gates
