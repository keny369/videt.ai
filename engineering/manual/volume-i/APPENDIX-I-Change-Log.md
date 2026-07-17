# engineering/manual/volume-i/APPENDIX-I-Change-Log.md

---
title: Appendix I — Change Log
identifier: EM-I-APP-I
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix I — Change Log

## Purpose

This appendix records the chronological history of modifications to **Engineering Manual – Volume I** after its initial publication.

Unlike the Version History, which records formal releases, the Change Log records the engineering changes introduced within each published version.

The Change Log forms part of the permanent engineering record and SHALL remain complete, accurate and auditable.

---

# 1. Change Log Principles

The Change Log SHALL:

- record engineering changes chronologically;
- distinguish editorial from normative changes;
- identify governing authority;
- preserve historical accuracy;
- support repository traceability.

Changes SHALL NEVER be removed from the log.

Corrections SHALL be recorded as subsequent entries.

---

# 2. Change Classification

Every change SHALL be assigned one of the following classifications.

## Editorial

Examples:

- spelling corrections;
- grammar improvements;
- formatting;
- reference corrections;
- diagram layout improvements.

Editorial changes SHALL NOT modify engineering obligations.

---

## Clarification

Clarifies existing engineering intent without changing normative behaviour.

Examples:

- improved wording;
- additional examples;
- expanded explanatory notes.

---

## Normative

Introduces or modifies engineering obligations.

Examples:

- new mandatory standards;
- altered review requirements;
- updated governance rules;
- revised compliance obligations.

Normative changes SHALL identify approval authority.

---

## Structural

Changes affecting document organisation.

Examples:

- chapter restructuring;
- appendix reorganisation;
- navigation improvements;
- identifier consolidation.

---

# 3. Change Log Format

Every entry SHALL contain:

| Field               | Description                                        |
| ------------------- | -------------------------------------------------- |
| Identifier          | Unique change identifier                           |
| Date                | YYYY-MM-DD                                         |
| Version             | Manual version                                     |
| Type                | Editorial / Clarification / Normative / Structural |
| Description         | Summary of change                                  |
| Authority           | Governing approval                                 |
| Repository Revision | Git revision                                       |
| Author              | Responsible engineering owner                      |

---

# 4. Current Release

## Version 1.0.0

### Initial Publication

| Field               | Value                                                        |
| ------------------- | ------------------------------------------------------------ |
| Change ID           | CL-2026-001                                                  |
| Date                | YYYY-MM-DD                                                   |
| Version             | 1.0.0                                                        |
| Type                | Initial Release                                              |
| Authority           | Engineering Governance                                       |
| Repository Revision | Initial publication revision                                 |
| Description         | First publication of Engineering Manual Volume I. Establishes the normative governance framework for implementation, repository management, engineering standards, architectural governance, AI engineering governance, quality gates, traceability, documentation standards and engineering appendices. |

---

# 5. Future Entries

Subsequent revisions SHALL append new entries.

Example:

| Change ID   | Version | Type      | Description                                    |
| ----------- | ------- | --------- | ---------------------------------------------- |
| CL-2026-002 | 1.0.1   | Editorial | Corrected cross-reference identifiers.         |
| CL-2026-003 | 1.1.0   | Normative | Added Engineering Manual Volume XI references. |
| CL-2026-004 | 2.0.0   | Breaking  | Revised engineering governance model.          |

Entries SHALL remain in chronological order.

---

# 6. Repository Traceability

Every Change Log entry SHOULD reference:

- Git commit;
- annotated release tag;
- Pull Request;
- ADR where applicable;
- Product Specification revision where applicable.

Example:

```
Repository Revision:
b2cb4ca

Release Tag:
engineering-manual-v1.0.0

Pull Request:
PR-214

ADR:
ADR-041
```

---

# 7. Relationship to Version History

The Version History records published releases.

The Change Log records engineering changes within those releases.

Both SHALL remain synchronised.

---

# 8. Engineering Governance

Normative changes SHALL:

1. identify affected chapters;
2. identify engineering rationale;
3. identify approval authority;
4. update the Version History;
5. update repository release notes where applicable.

Editorial corrections SHALL remain visible even when no version increment is required.

---

# 9. AI-Assisted Changes

Where AI materially assisted a documentation revision:

- human review SHALL remain mandatory;
- engineering ownership SHALL remain human;
- repository approval SHALL remain unchanged.

AI participation SHALL NOT alter Change Log requirements.

---

# 10. Repository Automation

Repository tooling MAY automatically generate draft Change Log entries.

Automatically generated entries SHALL be reviewed before publication.

Automation SHALL NOT become the authoritative record without engineering approval.

---

# 11. Archival Policy

The Change Log SHALL remain permanently available.

Historical entries SHALL NOT be:

- deleted;
- rewritten;
- reordered;
- merged.

Subsequent corrections SHALL be appended as new entries.

---

# 12. Review Checklist

Before publication reviewers SHALL confirm:

- [ ] Every normative change recorded.
- [ ] Version History updated.
- [ ] Repository revision recorded.
- [ ] Release tag recorded.
- [ ] Approval authority recorded.
- [ ] Cross references remain valid.
- [ ] Chronological order preserved.

---

# 13. Compliance

Maintaining the Change Log is mandatory.

Every published Engineering Manual revision SHALL include corresponding Change Log entries.

Failure to maintain an accurate Change Log SHALL constitute a repository governance defect.

---

# Cross References

- EM-I-007 Repository Governance
- EM-I-012 Architectural Decision Records
- EM-I-014 Documentation Standards
- APPENDIX-H Version History
- Product Specification