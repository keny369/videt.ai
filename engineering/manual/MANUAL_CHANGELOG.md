# Manual Changelog

## Purpose

This changelog records repository changes to the Engineering Manual. It is separate from product release notes and does not describe application implementation.

## 1.2 - 2026-07-17 - Remediation and Acceptance (ADR-022)

- ACCEPTED. The Engineering Manual is the normative authority for engineering practice at 12 volumes and 240 chapters, with no independent product-behaviour authority.
- Removed five OD-014 pre-emptions across EM-III-010, EM-III-005, EM-II-008 and EM-II-009; corrected to the canonical `project.activate` with the deferral cited.
- Purged an invented core entity that DM-REQ-001 does not define: 65 references across 21 chapters, plus its derived route, table, job, events, DTOs, factory, repositories and services. It is named in ADR-022; this control document does not restate it, because the manual now forbids the name.
- Corrected 204 product-domain spellings of the Organization entity to the canonical form across 190 files and renamed EM-VIII-007 to match. Ordinary English of the same word was deliberately left alone.
- Fixed the generator defect that produced the front matter debt, retired all 237 remaining defective files, and deleted `scripts/front_matter_baseline.txt`. Zero registered debt.
- Repaired Volume I chapter corruption: EM-I-001 was wrapped in a stray code fence with paste junk in its final cross-reference; seven further chapters carried stray trailing fences.
- Added six product-authority checks, eight negative controls and `scripts/test_generate_engineering_manual.py`.

## 1.1 - 2026-07-17 - Governance Pass 001

- Reconciled three conflicting authority hierarchies onto one canonical scoped model under ADR-021. MANUAL_AUTHORITY.md, IMPLEMENTATION_AGENT_ENTRYPOINT.md, EM-I-003, EM-I-016, the Volume I README and EM-XII-002 now restate the same model.
- Corrected the two structural defect classes preventing authority metadata from being parsed, in EM-I-003 and EM-XII-002. The remaining 247 affected files are recorded in `scripts/front_matter_baseline.txt` as registered debt.
- Added front matter structure checks and three negative controls to scripts/validate_engineering_manual.py.
- Recorded product-behaviour ownership conflicts in Volume III. Remediation requires its own controlled change and did not occur in this pass.

## 1.0 - 2026-07-17

- Completed Engineering Manual Volumes IV through XII.
- Added volume support files for repository integration.
- Added master controls, authority model, traceability and validation report.
- Added scripts/validate_engineering_manual.py with isolated negative controls.

## Governance

Manual changes SHALL remain traceable to authority sources and validation evidence. Changelog entries SHALL distinguish documentation baselines from implementation, release and final frozen baselines.
