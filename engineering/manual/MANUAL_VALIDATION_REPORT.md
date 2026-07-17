# Manual Validation Report

## Status Vocabulary

- VERIFIED: Check passed with direct command evidence.
- VERIFIED_WITH_FINDINGS: Check passed or was completed with recorded non-blocking findings.
- INCOMPLETE: Required work remains unfinished.
- CONFLICT: Authoritative sources materially contradict one another.
- DEFERRED: Product-specific value or exposure remains with a canonical owner.
- UNAVAILABLE: Evidence source could not be inspected in this repository.

## Current Status

VERIFIED

The Engineering Manual is accepted as the normative authority for engineering practice. It holds no independent product-behaviour authority at any rank, as required by PM-REQ-003.4. The CONFLICT recorded by Governance Pass 001 is closed: the product-behaviour ownership breaches it found are corrected and are now enforced by executable checks rather than by review attention.

Accepted at 12 volumes and 240 chapters, checked against the frozen Volume I baseline. OD-014 and OD-023 remain pending under their deterministic neutral interims and are expressly not resolved by this acceptance.

## Evidence Recorded

- Repository authority sources inspected under specification, governance, architecture, schemas and engineering/manual.
- scripts/validate_engineering_manual.py checks expected volumes, chapter counts, identifiers, links, master index entries, removed event names, prohibited state references, placeholders, fences, duplicate-like content, front matter structure and product-authority ownership.
- scripts/test_generate_engineering_manual.py checks that the generator emits conforming authority metadata for every declared chapter.
- Negative controls are defined for every failure mode relied upon for acceptance and are proved load-bearing by mutation testing rather than assumed.

## Governance Pass 002 Evidence

Commands run on 2026-07-17, output observed rather than assumed:

- `python3 scripts/validate_engineering_manual.py` - passed, exit 0.
- `python3 scripts/validate_engineering_manual.py --negative-controls` - passed, exit 0.
- `python3 scripts/test_generate_engineering_manual.py` - passed, exit 0.
- Mutation testing of the generator fix: reverting `dedent_block` to `textwrap.dedent` made all 180 declared chapters unparseable and failed 8 checks. Reverted; suite returns to exit 0.
- Independent parse proof: a conforming front-matter reader written without project code parses the authority metadata of every chapter and appendix.

## Findings

- Zero registered front-matter debt. Every chapter and appendix carries authority metadata that a conforming reader parses. `scripts/front_matter_baseline.txt` is retired and the structural check now has no exemptions.
- The generator defect that produced the debt is fixed at source. `textwrap.dedent` computed a longest-common indent that any column-zero interpolation collapsed to nothing, silently leaving front matter indented; `dedent_block` strips a fixed indent and cannot be defeated by interpolated content. Regression tests cover it.
- Volume I chapter corruption corrected. EM-I-001 was wrapped in a stray code fence so its entire body rendered as a code block, and its final cross-reference carried paste junk including a non-breaking space. Seven further Volume I chapters carried a stray trailing fence. None was detectable while the fence check exempted Volume I.
- Product-specific operational values such as service objectives, recovery targets, retention periods, deployment topology and cryptographic choices remain deferred to canonical owners where not ratified. The OD-023 credential-rotation limb is clean; no chapter supplies rotation begin or completion behaviour.
- Volume I retains legitimate template tokens: ISO date-format examples in the ADR, change-log and version-history templates, and one anti-pattern entry prohibiting unowned placeholder sections. These are template content rather than unresolved placeholders, and the publication-placeholder exemption remains scoped to Volume I for that reason.
- This is a documentation baseline. It does not begin application implementation and does not begin Specification Volume II.
