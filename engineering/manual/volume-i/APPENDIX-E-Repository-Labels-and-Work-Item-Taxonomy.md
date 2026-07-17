# engineering/manual/volume-i/APPENDIX-E-Repository-Labels-and-Work-Item-Taxonomy.md

---
title: Appendix E — Repository Labels and Work Item Taxonomy
identifier: EM-I-APP-E
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix E — Repository Labels and Work Item Taxonomy

## Purpose

This appendix defines the canonical taxonomy used to classify engineering work throughout the F1 platform.

A consistent taxonomy enables:

- engineering planning;
- prioritisation;
- reporting;
- automation;
- traceability;
- release management.

Every issue, Pull Request, milestone and engineering task SHALL use this taxonomy.

---

# 1. Engineering Principles

The taxonomy SHALL satisfy the following principles.

- Every work item has one primary type.
- Labels SHALL describe engineering characteristics rather than implementation status.
- Labels SHALL remain stable over time.
- Labels SHALL support automation.
- Labels SHALL NOT duplicate repository hierarchy.

---

# 2. Work Item Types

Every work item SHALL have exactly one Type label.

## type:feature

New functionality implementing the Product Specification.

Examples:

- workflow implementation
- API endpoint
- UI feature

---

## type:defect

Correction of incorrect behaviour.

Examples:

- workflow bug
- security defect
- state transition defect

---

## type:refactor

Behaviour-preserving engineering improvement.

Examples:

- service extraction
- code simplification
- dependency cleanup

---

## type:documentation

Documentation changes only.

Examples:

- Engineering Manual
- Product Specification
- ADR updates

---

## type:security

Security engineering work.

Examples:

- hardening
- authentication
- authorisation
- penetration remediation

---

## type:performance

Performance optimisation.

Examples:

- query optimisation
- caching
- memory reduction

---

## type:operations

Operational engineering.

Examples:

- monitoring
- dashboards
- deployment
- observability

---

## type:test

Testing improvements.

Examples:

- integration tests
- workflow verification
- contract testing

---

## type:maintenance

Routine engineering maintenance.

Examples:

- dependency upgrades
- infrastructure updates
- repository cleanup

---

# 3. Priority Labels

Every work item SHALL possess one priority.

## priority:critical

Immediate engineering action required.

Typically:

- production outage
- security vulnerability
- data corruption

---

## priority:high

High business or engineering impact.

Should normally be completed within the current milestone.

---

## priority:medium

Normal engineering priority.

Default classification.

---

## priority:low

Improvement work.

May be scheduled according to engineering capacity.

---

# 4. Risk Labels

Risk labels identify implementation risk.

- risk:low
- risk:medium
- risk:high
- risk:critical

Risk SHALL be assessed before implementation begins.

---

# 5. Architectural Labels

Applicable architectural areas SHALL be identified.

Examples:

- architecture:domain
- architecture:application
- architecture:workflow
- architecture:api
- architecture:database
- architecture:frontend
- architecture:infrastructure
- architecture:security
- architecture:deployment

Multiple architectural labels MAY be applied.

---

# 6. Component Labels

Components SHOULD identify the implementation area.

Examples:

- component:assessment
- component:crawler
- component:workflow-engine
- component:identity
- component:billing
- component:notifications
- component:search
- component:evidence
- component:organisation
- component:projects

---

# 7. Lifecycle Labels

Exactly one lifecycle label SHOULD exist.

- lifecycle:backlog
- lifecycle:ready
- lifecycle:in-progress
- lifecycle:review
- lifecycle:blocked
- lifecycle:testing
- lifecycle:ready-for-release
- lifecycle:completed

Lifecycle labels SHALL reflect engineering reality.

---

# 8. Governance Labels

Repository governance MAY use:

- governance:adr-required
- governance:spec-update
- governance:engineering-manual
- governance:legal-review
- governance:security-review
- governance:architecture-review

These labels assist engineering governance.

---

# 9. AI Labels

AI-assisted work SHOULD be identified.

Examples:

- ai:assisted
- ai:generated
- ai:review-required

These labels support engineering reporting only.

They SHALL NOT reduce review requirements.

---

# 10. Technical Debt Labels

Technical debt SHALL be explicitly classified.

Examples:

- debt:architecture
- debt:implementation
- debt:documentation
- debt:operations
- debt:testing
- debt:temporary

---

# 11. Release Labels

Release planning MAY use:

- release:v1.0
- release:v1.1
- release:v2.0

Release labels SHALL correspond to planned repository milestones.

---

# 12. Milestone Classification

Engineering milestones SHOULD represent:

- architectural completion;
- specification completion;
- implementation completion;
- operational readiness;
- production release.

Milestones SHALL NOT represent arbitrary calendar dates.

---

# 13. Label Governance

New labels SHALL require engineering governance approval.

Repository administrators SHOULD periodically review labels for:

- duplication;
- ambiguity;
- redundancy;
- obsolete terminology.

Unused labels SHOULD be retired.

---

# 14. Automation

Repository automation MAY use labels to:

- trigger CI workflows;
- request specialist reviewers;
- assign ownership;
- produce release notes;
- generate engineering reports.

Automation SHALL NOT replace engineering judgement.

---

# 15. Review Checklist

Repository administrators SHOULD verify:

- labels remain consistent;
- obsolete labels removed;
- automation remains correct;
- naming conventions preserved;
- engineering taxonomy remains coherent.

---

# 16. Compliance

Every engineering work item SHALL use this taxonomy unless an approved governance decision specifies otherwise.

The taxonomy SHALL evolve deliberately through repository governance.

---

# Cross References

- EM-I-007 Repository Governance
- EM-I-008 Branch Strategy
- EM-I-009 Pull Request Standards
- EM-I-017 Engineering Metrics and Quality Gates
- Product Specification