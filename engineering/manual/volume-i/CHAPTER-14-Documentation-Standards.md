# engineering/manual/volume-i/CHAPTER-14-Documentation-Standards.md

---
title: Documentation Standards
identifier: EM-I-014
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 14 — Documentation Standards

## 1. Purpose

This chapter establishes the documentation standards governing every repository artefact within the F1 platform.

Documentation is a first-class engineering deliverable.

It SHALL be maintained with the same discipline, review standards and version control as source code.

Documentation exists to communicate engineering intent, preserve architectural knowledge and provide an authoritative basis for implementation, maintenance and operational support.

Poor documentation is an engineering defect.

---

# 2. Scope

These standards apply to:

- Product Specification
- Engineering Manual
- Architectural Decision Records
- API documentation
- database documentation
- deployment documentation
- operational runbooks
- engineering guides
- diagrams
- repository README files
- onboarding material

This chapter applies to every Markdown document committed to the repository.

---

# 3. Documentation Principles

Documentation SHALL satisfy the following principles.

## DS-001 — Canonical

Every normative statement SHALL have one authoritative owner.

Documentation SHALL NOT duplicate authoritative content.

Instead, it SHALL reference the canonical source.

---

## DS-002 — Accurate

Documentation SHALL describe the current implementation or approved architecture.

Historical behaviour SHALL be identified explicitly.

Documentation SHALL NOT describe behaviour that no longer exists.

---

## DS-003 — Complete

Documentation SHALL provide sufficient information for an engineer unfamiliar with the implementation to understand:

- purpose;
- scope;
- rationale;
- constraints;
- interactions;
- responsibilities.

---

## DS-004 — Reviewable

Every normative document SHALL be capable of engineering review.

Requirements SHALL be objective.

Ambiguous wording is prohibited.

---

## DS-005 — Traceable

Normative documentation SHALL reference:

- Specification identifiers;
- ADRs;
- Engineering Manual chapters;
- related workflows;
- related APIs;
- related state models.

---

# 4. Documentation Hierarchy

Engineering documentation SHALL follow the authority hierarchy established in EM-I-003.

No document SHALL contradict a higher-authority artefact.

Documentation SHALL identify whether it is:

- Normative
- Informative
- Historical
- Deprecated
- Superseded

---

# 5. Document Metadata

Every normative document SHALL begin with metadata including:

```yaml
title:
identifier:
version:
status:
owner:
last_reviewed:
authority:
```

Additional metadata MAY be included where appropriate.

---

# 6. Required Structure

Normative engineering documents SHOULD contain:

1. Purpose
2. Scope
3. Definitions
4. Principles
5. Mandatory Standards
6. Examples
7. Anti-Patterns
8. Review Checklist
9. Compliance
10. Cross References

Volumes MAY introduce additional sections where justified.

---

# 7. Writing Standards

Documentation SHALL be:

- precise;
- concise;
- technically accurate;
- grammatically correct;
- consistently formatted;
- professionally written.

Engineers SHALL avoid:

- conversational language;
- speculative statements;
- subjective terminology;
- unexplained abbreviations;
- implementation folklore.

---

# 8. Normative Language

Normative documents SHALL use the terminology defined in EM-I-004.

Mandatory requirements SHALL use:

- SHALL
- MUST

Recommendations SHALL use:

- SHOULD

Optional behaviour SHALL use:

- MAY

Informative discussion SHALL clearly distinguish itself from normative requirements.

---

# 9. Diagrams

Architectural diagrams SHALL:

- identify scope;
- identify ownership;
- identify primary interactions;
- remain synchronised with implementation;
- use consistent notation.

Diagrams SHALL supplement documentation.

They SHALL NOT replace normative requirements.

---

# 10. Examples

Examples SHALL:

- demonstrate correct implementation;
- remain clearly marked as informative;
- avoid introducing undocumented behaviour.

Examples SHALL never become the sole definition of engineering behaviour.

---

# 11. Version Control

Documentation SHALL evolve with implementation.

Every behavioural change SHALL evaluate whether documentation requires modification.

Repository history SHALL preserve previous versions through Git rather than duplicated document copies.

---

# 12. Review

Documentation reviews SHALL evaluate:

- correctness;
- completeness;
- consistency;
- traceability;
- clarity;
- authority alignment.

Documentation review SHALL occur alongside implementation review where both change together.

---

# 13. AI Documentation

AI-generated documentation SHALL satisfy the same standards as human-authored documentation.

Human reviewers SHALL verify:

- factual correctness;
- Specification alignment;
- Engineering Manual compliance;
- cross references;
- consistency with existing repository terminology.

AI-generated text SHALL NOT be accepted solely because it is well written.

---

# 14. Anti-Patterns

The following practices are prohibited.

- Duplicating authoritative requirements.
- Describing obsolete behaviour as current.
- Undocumented terminology.
- Missing ownership.
- Broken cross references.
- Out-of-date diagrams.
- Specification drift.
- Placeholder text committed to the repository.
- TODO sections without ownership.

---

# 15. Documentation Quality Checklist

Every normative document SHALL satisfy the following.

## Structure

- [ ] Purpose defined.
- [ ] Scope defined.
- [ ] Metadata complete.
- [ ] Compliance section included.

## Content

- [ ] Accurate.
- [ ] Complete.
- [ ] Current.
- [ ] Normative language correct.

## Governance

- [ ] Cross references verified.
- [ ] Authority hierarchy respected.
- [ ] Review completed.
- [ ] Version updated.

---

# 16. Compliance

Documentation quality is an engineering responsibility.

Documentation that fails to satisfy this chapter SHALL be corrected before associated implementation is considered complete.

Documentation defects SHALL be tracked and prioritised in the same manner as implementation defects.

---

# Cross References

- EM-I-003 Authority Hierarchy
- EM-I-004 Normative Language
- EM-I-007 Repository Governance
- EM-I-010 Definition of Done
- EM-I-012 Architectural Decision Records
- EM-I-016 Traceability
- Product Specification
- Engineering Manual (All Volumes)