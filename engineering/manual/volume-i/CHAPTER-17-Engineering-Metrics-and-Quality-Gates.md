---
title: Engineering Metrics and Quality Gates
identifier: EM-I-017
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 17 — Engineering Metrics and Quality Gates

## 1. Purpose

This chapter establishes the engineering metrics and quality gates that govern software delivery within the F1 platform.

Engineering quality SHALL be measured using objective evidence rather than subjective opinion.

Metrics exist to inform engineering judgement.

They SHALL NOT replace engineering judgement.

Quality gates define the minimum conditions under which engineering work may progress from one lifecycle stage to the next.

---

# 2. Scope

This chapter applies to:

- implementation;
- Product Specification changes;
- Engineering Manual updates;
- infrastructure;
- database changes;
- deployment;
- releases;
- operational improvements.

Every engineering artefact SHALL pass the applicable quality gates before progressing.

---

# 3. Engineering Philosophy

Quality is created continuously.

It SHALL NOT be inspected into the software at the end of development.

Every engineering activity SHALL contribute positively to the overall quality of the platform.

---

# 4. Engineering Metrics

Metrics SHALL be objective, reproducible and actionable.

They SHALL support engineering decisions rather than management reporting alone.

Metrics SHALL identify trends rather than assign blame.

---

## EM-001 Build Health

The engineering organisation SHALL continuously monitor:

- successful build percentage;
- failed builds;
- build duration;
- build stability.

Persistently unstable builds SHALL be treated as engineering defects.

---

## EM-002 Test Health

Engineering SHALL monitor:

- unit test success;
- integration test success;
- workflow verification success;
- contract verification success;
- regression stability.

Declining test reliability SHALL trigger investigation.

---

## EM-003 Repository Health

Repository quality SHOULD include monitoring of:

- merge frequency;
- branch lifetime;
- review turnaround;
- documentation completeness;
- stale branches;
- stale Pull Requests.

Repository health directly influences engineering velocity.

---

## EM-004 Defect Quality

Engineering SHOULD monitor:

- escaped defects;
- regression defects;
- severity distribution;
- defect recurrence;
- mean time to correction.

Repeated defects indicate systemic engineering issues.

---

## EM-005 Operational Quality

Production engineering SHOULD observe:

- service availability;
- incident frequency;
- mean time to detect;
- mean time to recover;
- deployment success rate.

Operational quality SHALL influence engineering priorities.

---

## EM-006 Technical Debt

Engineering SHALL maintain visibility of:

- architectural debt;
- implementation debt;
- documentation debt;
- infrastructure debt;
- operational debt.

Technical debt SHALL be visible to engineering leadership.

---

# 5. Quality Gates

Engineering SHALL satisfy the following gates.

---

## Gate 1 — Specification Ready

Before implementation begins:

- Specification approved.
- Requirements complete.
- Acceptance criteria defined.
- Architectural authority identified.

Implementation SHALL NOT begin against incomplete requirements.

---

## Gate 2 — Implementation Ready

Before review:

- Implementation complete.
- Documentation updated.
- Tests written.
- Traceability established.
- Local validation successful.

---

## Gate 3 — Review Ready

Before approval:

- Pull Request complete.
- Architectural review complete.
- Security review completed where required.
- Repository standards satisfied.

---

## Gate 4 — Integration Ready

Before merge:

- CI successful.
- Review approvals complete.
- Documentation merged.
- Migration reviewed.
- Deployment considerations documented.

---

## Gate 5 — Release Ready

Before release:

- Version identified.
- Release notes prepared.
- Rollback validated.
- Monitoring configured.
- Operational documentation updated.

---

## Gate 6 — Production Ready

Before production deployment:

- Deployment approved.
- Alerts configured.
- Dashboards updated.
- Incident procedures available.
- Support teams informed where required.

---

# 6. Metric Interpretation

Metrics SHALL identify engineering improvement opportunities.

Metrics SHALL NOT be used:

- as performance quotas;
- to discourage reporting;
- to incentivise superficial optimisation.

Engineering behaviour SHALL optimise platform quality rather than metric appearance.

---

# 7. Thresholds

Engineering leadership MAY establish operational thresholds.

Examples include:

- minimum CI success rate;
- maximum build duration;
- maximum open critical defects;
- minimum automated test coverage;
- maximum stale Pull Request age.

Thresholds SHALL remain documented and periodically reviewed.

---

# 8. AI Engineering

AI-generated work SHALL satisfy every applicable quality gate.

AI SHALL NOT bypass:

- testing;
- review;
- validation;
- documentation;
- traceability.

Automation SHALL strengthen governance rather than weaken it.

---

# 9. Review Checklist

Reviewers SHALL verify:

- appropriate quality gates satisfied;
- engineering evidence available;
- metrics unaffected or improved;
- operational readiness confirmed;
- documentation complete;
- traceability preserved.

---

# 10. Anti-Patterns

The following practices are prohibited.

- Measuring activity instead of outcomes.
- Ignoring declining engineering quality.
- Treating passing CI as sufficient evidence.
- Gaming engineering metrics.
- Waiving quality gates without governance.
- Prioritising velocity over correctness.
- Ignoring technical debt accumulation.

---

# 11. Compliance

Engineering work SHALL NOT advance beyond an applicable lifecycle stage unless the required quality gates have been satisfied.

Exceptions SHALL:

- identify the affected gate;
- document the reason;
- identify residual risk;
- receive formal approval;
- define remediation.

---

# Cross References

- EM-I-002 Engineering Objectives
- EM-I-007 Repository Governance
- EM-I-009 Pull Request Standards
- EM-I-010 Definition of Done
- EM-I-011 Code Review Standard
- EM-I-015 Requirement Traceability
- EM-IX Quality Engineering & Testing
- EM-X Release Engineering & Production Operations
- Product Specification
