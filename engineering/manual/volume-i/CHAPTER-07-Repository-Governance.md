---
title: Repository Governance
identifier: EM-I-007
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 7 — Repository Governance

## 1. Purpose

This chapter defines the governance standards for the F1 source repository.

The repository is the canonical implementation record of the project. Every change SHALL preserve its integrity, traceability and auditability.

The repository SHALL represent the complete engineering history of the platform.

---

# 2. Scope

This chapter governs:

- repository structure;
- commits;
- branches;
- pull requests;
- documentation;
- tags;
- releases;
- version control;
- engineering history.

It applies to every repository contributing to the F1 platform.

---

# 3. Repository Principles

The repository SHALL satisfy the following principles.

## RG-001 — Single Source of Engineering Truth

The repository SHALL contain the authoritative implementation artefacts.

Implementation SHALL NOT depend upon documentation stored elsewhere.

---

## RG-002 — Complete History

Repository history SHALL remain complete.

Every significant engineering decision SHALL be represented by:

- commits;
- ADRs;
- Specification updates;
- Engineering Manual updates.

Engineering decisions SHALL NOT exist only in chat transcripts, emails or verbal discussions.

---

## RG-003 — Traceability

Every commit SHALL be traceable.

Commits SHOULD reference one or more identifiers, including:

- REQ
- CAP
- WF
- API
- STATE
- ADR
- OD
- EM

where applicable.

---

## RG-004 — Atomic Changes

A commit SHALL represent one logical engineering change.

Commits SHALL NOT combine unrelated modifications.

Examples of unrelated work include:

- refactoring;
- feature implementation;
- documentation cleanup;
- dependency upgrades.

These SHALL be committed independently.

---

## RG-005 — Clean Repository

The default branch SHALL remain releasable.

The repository SHALL NOT contain:

- temporary files;
- editor artefacts;
- generated logs;
- experimental implementations;
- abandoned prototypes.

---

# 4. Repository Structure

The top-level repository SHALL remain organised.

Illustrative structure:

```
/
├── specification/
├── engineering/
├── application/
├── infrastructure/
├── scripts/
├── test/
├── docs/
├── docker/
├── config/
└── tools/
```

Each directory SHALL have a clearly defined purpose.

---

# 5. File Ownership

Every significant repository area SHALL have an identified owner.

Ownership defines:

- architectural responsibility;
- review responsibility;
- maintenance responsibility.

Ownership does NOT imply exclusive editing rights.

---

# 6. Commit Standards

Every commit SHALL:

- compile where applicable;
- preserve repository consistency;
- pass required validation;
- represent one coherent change.

Commit messages SHALL follow repository conventions.

Preferred structure:

```
type(scope): concise summary
```

Examples:

```
feat(workflow): implement reassessment guard

fix(schema): align document constraint

docs(engineering): add repository governance
```

---

# 7. Commit Content

A commit SHALL NOT contain:

- unrelated formatting changes;
- speculative implementation;
- dead code;
- commented-out production code;
- unfinished experiments;
- debugging artefacts.

If work is incomplete it SHALL remain on a development branch.

---

# 8. Branch Governance

Protected branches SHALL NOT receive direct commits.

Changes SHALL proceed through the approved review process unless repository governance explicitly authorises an exception.

Long-lived branches SHALL be avoided unless justified by release strategy.

---

# 9. Version Tags

Repository tags SHALL represent meaningful engineering milestones.

Tags SHALL be:

- annotated;
- immutable;
- reproducible.

Moving an existing release tag is prohibited.

If correction is required, create a successor tag.

---

# 10. Generated Artefacts

Generated artefacts SHALL be committed only when required by repository policy.

Automatically generated files SHALL identify:

- generator;
- generation process;
- ownership.

Generated content SHALL NOT become the canonical source.

---

# 11. Repository Hygiene

Repository hygiene SHALL be maintained continuously.

Regular review SHALL identify:

- obsolete files;
- duplicate documents;
- unused scripts;
- stale branches;
- orphaned diagrams;
- outdated references.

Repository cleanup SHALL preserve engineering history.

---

# 12. Documentation Governance

Normative documentation SHALL reside within version control.

Documentation changes affecting engineering behaviour SHALL undergo the same review process as source code.

Documentation SHALL evolve with implementation.

---

# 13. Release Integrity

A release SHALL be reproducible from:

- repository contents;
- tagged revision;
- documented build process.

No release SHALL depend upon unpublished local changes.

---

# 14. AI Contributions

AI-generated contributions SHALL satisfy exactly the same repository standards as human contributions.

AI provenance SHALL NOT reduce review requirements.

Every AI-generated commit SHALL be reviewed before merge.

---

# 15. Review Checklist

Reviewers SHALL confirm:

- repository structure remains consistent;
- commits are atomic;
- history remains meaningful;
- documentation is updated;
- generated artefacts are appropriate;
- no temporary files remain;
- traceability is preserved;
- release integrity is maintained.

---

# 16. Compliance

Violations of repository governance SHALL be corrected before merge.

Repeated violations SHALL trigger an engineering governance review.

Repository quality is a shared engineering responsibility.

---

# Cross References

- EM-I-001 Engineering Philosophy
- EM-I-003 Authority Hierarchy
- EM-I-008 Branch Strategy
- EM-I-009 Pull Request Standards
- EM-I-013 Architectural Decision Records
- Product Specification
