# engineering/manual/volume-i/APPENDIX-D-Definition-of-Ready.md

---
title: Appendix D — Definition of Ready
identifier: EM-I-APP-D
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix D — Definition of Ready

## Purpose

This appendix defines the mandatory **Definition of Ready (DoR)** for all engineering work undertaken within the F1 platform.

No implementation SHALL begin until the work satisfies the applicable Definition of Ready.

The purpose of the Definition of Ready is to ensure that engineers begin implementation with complete architectural, functional and operational understanding, thereby reducing rework, ambiguity and architectural drift.

The Definition of Ready complements—but does not replace—the Definition of Done.

---

# 1. Scope

The Definition of Ready applies to:

- new features;
- workflow implementations;
- bug fixes with architectural impact;
- database changes;
- infrastructure changes;
- APIs;
- frontend features;
- background processing;
- security enhancements;
- refactoring requiring governance.

Minor documentation corrections MAY be exempt where no engineering behaviour changes.

---

# 2. Engineering Philosophy

Beginning implementation before engineering work is ready creates unnecessary defects.

Engineering SHALL optimise preparation rather than improvisation.

No engineer or AI coding agent SHALL invent missing requirements during implementation.

Missing authority SHALL be resolved before coding begins.

---

# 3. Product Readiness

Implementation SHALL NOT commence until the governing Product Specification is complete.

The following SHALL be identified.

### Product Requirements

- [ ] Applicable REQ identifiers.
- [ ] Applicable CAP identifiers.
- [ ] Applicable WF identifiers.
- [ ] Applicable API contracts.
- [ ] Applicable state model.
- [ ] Applicable acceptance criteria.

---

### Behaviour

- [ ] Expected behaviour understood.
- [ ] Success conditions understood.
- [ ] Failure conditions understood.
- [ ] Error handling defined.
- [ ] Product rules identified.

---

# 4. Engineering Readiness

The implementation SHALL possess sufficient engineering guidance.

Confirm:

- [ ] Applicable Engineering Manual chapters identified.
- [ ] Applicable ADRs reviewed.
- [ ] Repository conventions understood.
- [ ] Existing implementation analysed.
- [ ] Integration points identified.

---

# 5. Architectural Readiness

Engineering SHALL understand:

- [ ] affected aggregates;
- [ ] service boundaries;
- [ ] workflow ownership;
- [ ] transaction boundaries;
- [ ] persistence implications;
- [ ] infrastructure dependencies.

If architecture is unclear, implementation SHALL pause until clarified.

---

# 6. Security Readiness

Confirm:

- [ ] authentication requirements understood;
- [ ] authorisation requirements understood;
- [ ] audit requirements understood;
- [ ] data protection obligations understood;
- [ ] security risks assessed.

---

# 7. Operational Readiness

Confirm:

- [ ] deployment implications understood;
- [ ] rollback strategy considered;
- [ ] monitoring implications understood;
- [ ] logging requirements identified;
- [ ] tracing requirements identified.

---

# 8. Testing Readiness

Implementation SHALL NOT begin without an identified verification strategy.

Confirm:

- [ ] unit testing planned;
- [ ] integration testing planned;
- [ ] workflow verification planned;
- [ ] contract testing planned where applicable;
- [ ] manual verification understood where unavoidable.

---

# 9. Traceability Readiness

Engineering SHALL identify:

- governing Specification identifiers;
- applicable ADRs;
- Engineering Manual chapters;
- affected documentation;
- affected operational procedures.

Traceability SHALL exist before implementation begins.

---

# 10. Repository Readiness

Confirm:

- [ ] appropriate branch created;
- [ ] branch scope defined;
- [ ] repository current;
- [ ] unrelated work absent;
- [ ] engineering objective documented.

---

# 11. AI Engineering Readiness

AI coding agents SHALL additionally confirm:

- [ ] Product Specification loaded.
- [ ] Engineering Manual chapters reviewed.
- [ ] Applicable ADRs reviewed.
- [ ] Repository searched.
- [ ] Existing implementation analysed.
- [ ] No architectural ambiguity exists.

Where ambiguity remains, AI SHALL stop rather than speculate.

---

# 12. Ready Checklist

Implementation MAY begin only when every applicable statement below is true.

## Product

- [ ] Requirements complete.
- [ ] Behaviour understood.
- [ ] Acceptance criteria defined.

## Architecture

- [ ] Architecture understood.
- [ ] Dependencies understood.
- [ ] Boundaries identified.

## Engineering

- [ ] Standards identified.
- [ ] ADRs reviewed.
- [ ] Repository analysed.

## Verification

- [ ] Testing planned.
- [ ] Traceability established.
- [ ] Documentation impact identified.

## Operations

- [ ] Deployment considered.
- [ ] Monitoring considered.
- [ ] Rollback considered.

---

# 13. Work That Is Not Ready

Engineering work SHALL NOT begin if:

- requirements are incomplete;
- architecture is ambiguous;
- Specification conflicts exist;
- ADRs are unresolved;
- testing cannot be defined;
- ownership is unclear;
- traceability cannot be established.

Beginning implementation despite these conditions constitutes an engineering governance defect.

---

# 14. Anti-Patterns

The following practices are prohibited.

- "We'll work it out while coding."
- Inventing missing product behaviour.
- Coding against incomplete workflows.
- Beginning implementation before reading governing artefacts.
- Deferring architectural decisions into source code.
- Assuming framework defaults satisfy product requirements.

---

# 15. Compliance

The Definition of Ready SHALL be satisfied before engineering work begins.

Engineering leadership SHALL prefer delayed implementation over implementation founded upon incomplete or ambiguous authority.

---

# Cross References

- EM-I-003 Authority Hierarchy
- EM-I-007 Repository Governance
- EM-I-010 Definition of Done
- EM-I-015 Requirement Traceability
- EM-I-016 AI Engineering Governance
- Product Specification
- Architectural Decision Records