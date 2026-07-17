---
title: Branch Strategy
identifier: EM-I-008
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 8 — Branch Strategy

## 1. Purpose

This chapter defines the branching strategy governing all software development within the F1 platform.

The purpose of the branching strategy is to ensure:

- predictable integration;
- reproducible releases;
- controlled architectural evolution;
- complete engineering traceability;
- minimal merge complexity.

The branching model SHALL optimise repository integrity rather than developer convenience.

---

# 2. Scope

This chapter applies to:

- source code;
- documentation;
- Product Specification;
- Engineering Manual;
- infrastructure;
- database migrations;
- automation;
- configuration.

Every repository maintained by the project SHALL adopt these principles unless an approved ADR specifies otherwise.

---

# 3. Branch Philosophy

Branches exist to isolate engineering work.

They SHALL NOT become long-lived independent codebases.

The default branch SHALL remain releasable at all times.

Long-running feature divergence is prohibited unless explicitly approved.

---

# 4. Permanent Branches

The following permanent branches are recognised.

## main

The canonical engineering branch.

Properties:

- protected;
- releasable;
- fully validated;
- tagged at release milestones.

Direct commits to `main` are prohibited except under documented emergency governance.

---

## release/*

Optional release stabilisation branches.

These SHALL exist only when:

- supporting parallel releases;
- managing hotfixes;
- maintaining supported versions.

Release branches SHALL be temporary unless long-term support has been formally adopted.

---

# 5. Working Branches

Working branches SHALL be short-lived.

Approved naming conventions include:

```
feature/<topic>

fix/<topic>

refactor/<topic>

docs/<topic>

test/<topic>

infra/<topic>

spike/<topic>
```

Examples:

```
feature/workflow-engine

fix/read-authorisation

docs/engineering-manual

infra/docker-build
```

---

# 6. Branch Lifetime

Branches SHOULD exist only for the duration required to complete one coherent engineering objective.

Engineering work SHALL be integrated promptly following review.

Branches SHALL NOT accumulate unrelated work.

---

# 7. Scope

Each branch SHALL implement one logical engineering objective.

Examples:

✓ Implement one workflow.

✓ Correct one architectural defect.

✓ Add one Engineering Manual chapter.

Examples that violate governance:

✗ Workflow implementation plus infrastructure upgrade.

✗ Database redesign plus API refactor.

✗ Multiple unrelated bug fixes.

---

# 8. Synchronisation

Working branches SHALL remain synchronised with `main`.

Before opening a Pull Request engineers SHALL:

- rebase or merge current main;
- resolve conflicts;
- execute validation;
- rerun automated tests.

Branches SHALL NOT rely upon obsolete repository state.

---

# 9. Merge Policy

Only reviewed Pull Requests SHALL merge into protected branches.

Every merge SHALL satisfy:

- successful CI;
- successful validation;
- completed review;
- updated documentation;
- traceability.

Fast-forward, squash or merge commits MAY be used according to repository policy.

One strategy SHALL be used consistently.

---

# 10. Experimental Work

Experimental implementation SHALL occur on dedicated branches.

Experimental branches SHALL:

- never be merged accidentally;
- clearly indicate experimental status;
- remain isolated from production work.

If experimentation becomes production architecture it SHALL undergo normal governance before merge.

---

# 11. Hotfixes

Production hotfixes SHALL:

- originate from the latest production tag or approved release branch;
- minimise scope;
- preserve traceability;
- undergo review where operationally possible;
- be merged back into the primary development branch immediately after release.

Hotfixes SHALL NOT become an alternative development workflow.

---

# 12. Protected Branch Rules

Protected branches SHALL enforce:

- mandatory Pull Requests;
- required approvals;
- passing CI checks;
- linear history where configured;
- signed commits if adopted;
- prohibition of force pushes.

Protection settings SHALL be reviewed periodically.

---

# 13. Branch Deletion

Merged working branches SHALL be deleted after successful integration.

Branches SHALL remain only where required for:

- active development;
- supported releases;
- ongoing investigation.

Repository clutter SHALL be minimised.

---

# 14. AI Engineering

AI coding agents SHALL:

- create focused branches;
- implement one engineering objective per branch;
- avoid unrelated modifications;
- maintain repository cleanliness;
- preserve traceability.

AI SHALL NOT create branch structures outside this policy.

---

# 15. Anti-Patterns

The following practices are prohibited:

- long-lived feature branches;
- direct commits to protected branches;
- force pushing shared branches;
- unrelated work in one branch;
- merging failing branches;
- bypassing review;
- leaving stale branches indefinitely.

---

# 16. Review Checklist

Reviewers SHALL verify:

- branch purpose is clear;
- scope is coherent;
- merge target is correct;
- repository is current;
- validation has passed;
- documentation is updated;
- traceability exists;
- no unrelated work is present.

---

# 17. Compliance

Compliance with this chapter is mandatory.

Departures SHALL require documented approval through repository governance.

Repeated violations SHALL trigger an engineering process review.

---

# Cross References

- EM-I-007 Repository Governance
- EM-I-009 Pull Request Standards
- EM-I-010 Definition of Done
- EM-I-011 Code Review Standard
- Product Specification
- Engineering Constitution (when adopted)
