# engineering/manual/volume-i/CHAPTER-16-AI-Engineering-Governance.md

---
title: AI Engineering Governance
identifier: EM-I-016
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 16 — AI Engineering Governance

## 1. Purpose

This chapter establishes the mandatory governance framework for the use of Artificial Intelligence in the design, implementation, review, testing and maintenance of the F1 platform.

AI is an engineering accelerator.

It is **not** an engineering authority.

No AI system possesses architectural authority, product authority or governance authority.

Those responsibilities remain with the project's authorised decision makers.

---

# 2. Scope

This chapter applies to every AI system used within the project, including but not limited to:

- coding assistants;
- code generation systems;
- documentation assistants;
- review assistants;
- testing assistants;
- architecture assistants;
- search and reasoning systems;
- autonomous engineering agents.

The standards apply equally regardless of model vendor.

---

# 3. Engineering Philosophy

AI SHALL assist engineering.

AI SHALL NOT direct engineering.

Every engineering decision implemented by AI SHALL be traceable to an authoritative repository artefact.

Confidence, fluency or sophistication of generated output SHALL NOT be treated as evidence of correctness.

---

# 4. Authority

AI SHALL derive engineering behaviour from:

1. Product Specification;
2. Engineering Manual;
3. Accepted ADRs;
4. Approved Owner Decisions;
5. Repository source code.

AI SHALL NOT derive engineering behaviour from:

- internet examples;
- framework defaults;
- blog articles;
- Stack Overflow;
- prior projects;
- assumed conventions.

Repository authority always prevails.

---

# 5. Permitted Activities

AI MAY assist with:

- implementation;
- refactoring;
- documentation;
- testing;
- code review assistance;
- migration generation;
- architectural analysis;
- defect investigation;
- operational analysis;
- repository search.

Provided all work remains subject to engineering governance.

---

# 6. Prohibited Activities

AI SHALL NOT independently:

- invent product behaviour;
- redefine requirements;
- modify workflows;
- alter state models;
- create architectural patterns;
- weaken security controls;
- bypass review;
- approve Pull Requests;
- accept engineering risk;
- change governance artefacts.

These activities require human authority.

---

# 7. Engineering Workflow

Every AI-assisted implementation SHALL follow this sequence.

1. Read governing Specification.
2. Read applicable Engineering Manual chapters.
3. Read applicable ADRs.
4. Analyse existing implementation.
5. Produce implementation.
6. Produce tests.
7. Update documentation.
8. Verify traceability.
9. Submit for review.

AI SHALL NOT skip repository discovery.

---

# 8. Traceability

Every AI-generated implementation SHALL identify its governing authorities.

Examples include:

- REQ identifiers;
- CAP identifiers;
- WF identifiers;
- API identifiers;
- ADR identifiers;
- EM identifiers.

Where no governing authority exists, AI SHALL stop implementation.

---

# 9. Repository Behaviour

AI SHALL preserve repository integrity.

AI SHALL NOT:

- reformat unrelated files;
- rename unrelated identifiers;
- reorder files without purpose;
- modify generated artefacts unnecessarily;
- introduce speculative abstractions;
- perform repository-wide cleanup without explicit instruction.

Repository history SHALL remain meaningful.

---

# 10. Code Generation Standards

Generated code SHALL:

- satisfy the Product Specification;
- comply with the Engineering Manual;
- preserve architectural boundaries;
- remain deterministic;
- include appropriate error handling;
- support observability;
- support automated testing;
- avoid duplicated business logic.

Generated code SHALL be understandable by human engineers.

---

# 11. AI Review Standard

Human review remains mandatory.

Review SHALL verify:

- behavioural correctness;
- Specification compliance;
- architectural integrity;
- security;
- performance;
- maintainability;
- documentation;
- traceability.

AI-generated code SHALL receive the same scrutiny as human-authored code.

---

# 12. Escalation Rules

AI SHALL stop and request human guidance whenever:

- repository authorities conflict;
- Specification ambiguity exists;
- architectural decisions are required;
- governance is unclear;
- security implications are uncertain;
- implementation would require inventing behaviour.

Stopping is preferred to speculation.

---

# 13. Prompt Governance

Prompts used for significant engineering work SHOULD:

- identify governing artefacts;
- define scope;
- prohibit invention;
- require traceability;
- require testing;
- require documentation updates.

Engineering prompts SHALL evolve under version control where reused operationally.

---

# 14. AI Limitations

Engineers SHALL recognise that AI systems:

- may hallucinate;
- may omit constraints;
- may misinterpret context;
- may overstate confidence;
- may generate syntactically correct but semantically incorrect implementations.

Engineering evidence SHALL always take precedence over AI confidence.

---

# 15. Human Responsibilities

Human engineers remain responsible for:

- approving architecture;
- accepting engineering risk;
- approving releases;
- reviewing implementation;
- repository governance;
- production accountability.

Responsibility SHALL NOT be delegated to AI.

---

# 16. Review Checklist

Before accepting AI-generated work reviewers SHALL confirm:

- [ ] Repository authorities consulted.
- [ ] No invented behaviour.
- [ ] Architecture preserved.
- [ ] Traceability complete.
- [ ] Tests adequate.
- [ ] Documentation updated.
- [ ] Security reviewed.
- [ ] Operational considerations documented.
- [ ] Repository standards satisfied.

---

# 17. Anti-Patterns

The following practices are prohibited.

- Accepting AI output without review.
- Treating AI explanations as evidence.
- Allowing AI to redefine architecture.
- Asking AI to "make something up" to complete implementation.
- Using AI-generated code without traceability.
- Ignoring repository authorities because AI produced a convincing alternative.
- Allowing AI to resolve Specification ambiguity independently.

---

# 18. Compliance

All AI-assisted engineering SHALL comply with this chapter.

Violations SHALL be treated as engineering governance defects and corrected before merge.

AI is an implementation tool.

Engineering judgement remains a human responsibility.

---

# Cross References

- EM-I-003 Authority Hierarchy
- EM-I-005 Engineering Principles
- EM-I-007 Repository Governance
- EM-I-009 Pull Request Standards
- EM-I-010 Definition of Done
- EM-I-011 Code Review Standard
- EM-I-015 Requirement Traceability
- Product Specification
- All Engineering Manual Volumes