# Manual Validation Report

## Status Vocabulary

- VERIFIED: Check passed with direct command evidence.
- VERIFIED_WITH_FINDINGS: Check passed or was completed with recorded non-blocking findings.
- INCOMPLETE: Required work remains unfinished.
- CONFLICT: Authoritative sources materially contradict one another.
- DEFERRED: Product-specific value or exposure remains with a canonical owner.
- UNAVAILABLE: Evidence source could not be inspected in this repository.

## Current Status

CONFLICT

The authority-hierarchy contradictions recorded by Governance Pass 001 are resolved under ADR-021, and both validator suites pass. The status is CONFLICT because Governance Pass 001 surfaced an unresolved material contradiction: Engineering Manual Volume III establishes product behaviour owned by the Product Specification, including examples that pre-empt pending OD-014. It is recorded under Findings and MUST be corrected by controlled change before Volume II begins. The status returns to VERIFIED_WITH_FINDINGS when that correction lands.

## Evidence Recorded

- Repository authority sources inspected under specification, governance, architecture, schemas and engineering/manual.
- Manual structure generated directly in the repository without ZIP handling.
- scripts/validate_engineering_manual.py checks expected volumes, chapter counts, identifiers, links, master index entries, removed event names, prohibited state references, placeholders, fences, duplicate-like content and front matter structure.
- Isolated negative controls are defined for duplicate identifier, missing chapter, title mismatch, broken link, unbalanced fence, unresolved placeholder, missing master index entry, removed event reference, prohibited state reference, front matter not at start, indented front matter and stale front matter baseline.

## Governance Pass 001 Evidence

Commands run on 2026-07-17, output observed rather than assumed:

- `python3 scripts/validate_engineering_manual.py` - passed, exit 0.
- `python3 scripts/validate_engineering_manual.py --negative-controls` - passed, exit 0, twelve controls.
- Mutation testing of the three new controls. Neutering `front_matter_defect` failed the `front matter not at start` and `indented front matter` controls; suppressing stale-baseline reporting failed the `stale front matter baseline` control; exempting every path via the baseline failed both defect controls. Each mutation was reverted and both suites re-run to exit 0. The new controls are load-bearing rather than vacuous.

## Findings

- Every one of the 249 chapters and appendices carried one of two structural defects preventing authority metadata from being parsed by a conforming reader: 70 files with a path heading before the front matter, 177 files with indented front matter, and the two authority chapters corrected by Governance Pass 001. The validator previously passed only because it was written around both defects. The outstanding 247 files are recorded in `scripts/front_matter_baseline.txt` and are registered debt, not conformance.
- CONFLICT: Engineering Manual Volume III establishes product behaviour it does not own. `Project#archive!` and `project.archive!` in EM-III-010 pre-empt pending OD-014 and its live blocker `UPSTREAM-V1-PROJECT-LIFECYCLE-003`. EM-III-003 presents an invented `Assessment` entity as canonical terminology, which DM-REQ-001 does not define; it propagates to invented events, a `POST /assessments` route and an `assessments` table. Volume III also uses the non-canonical spelling `Organisation`. Remediation requires its own controlled change under ADR-021's review checkpoint.
- Existing Volume I contains template examples with publication placeholder tokens. These are preserved legacy template artefacts and are not used by new authored volumes.
- Product-specific operational values such as service objectives, recovery targets, retention periods, deployment topology and cryptographic choices remain deferred to canonical owners where not ratified. The credential-rotation limb of OD-023 is clean; no manual chapter supplies rotation begin or completion behaviour.
- This baseline is a documentation baseline and does not begin application implementation.
