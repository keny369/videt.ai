# 003 TERMINOLOGY

## Document Control

- Status: Accepted baseline
- Version: 1.0.0
- Last updated: 2026-07-15
- Owner: Chief Architect
- Classification: Canonical

## Purpose

Define naming, capitalization and vocabulary conventions for all Project F1 documentation.

## Scope

This document standardizes how concepts are named. Concept meaning is defined in [002 GLOSSARY.md](002 GLOSSARY.md).

## Terminology Rules

### Rule 1: Canonical Names

Use canonical names exactly as defined. Do not invent local aliases in individual chapters.

### Rule 2: Stable Product Name

Use Project F1 for the company project context and Discoverability Intelligence Platform for category context.

### Rule 3: Consistent Score Naming

Always use Discoverability Score with capitalized initial letters.

### Rule 4: Pillar Naming

Use the exact seven pillar names:

- Technical Integrity
- Search Presence
- AI Presence
- Authority Signals
- Trust Signals
- Content Quality
- Local Presence

### Rule 5: Role Naming

Use consistent role labels and authorization role identifiers.

Display role labels:

- Executive Buyer
- Marketing Operator
- Technical Implementer
- Security Operator
- Billing Operator
- Organization Administrator

Authorization role identifiers:

- OrganizationAdmin
- MarketingOperator
- TechnicalImplementer
- SecurityOperator
- BillingOperator

### Rule 6: Document Naming

Foundation files are prefixed with three-digit numbers. Volumes use VOLUME_[ROMAN] naming.

### Rule 7: Normative Language

Use MUST for mandatory requirements, SHOULD for strong recommendations, and MAY for optional behavior.

### Rule 8: Time Expressions

Use UTC when specifying operational timestamps or SLA windows.

### Rule 9: Measurement Expressions

Use explicit units and windows, for example ms, seconds, percent over 7 days.

### Rule 10: Avoid Ambiguity

Avoid vague words such as fast, robust, scalable, soon, intuitive, and enterprise-grade unless followed by measurable criteria.

### Rule 11: Event Naming

Canonical domain events in specifications MUST use PascalCase naming, for example EvaluationCompleted and CitationVerified.

## Canonical Terms And Disallowed Variants

| Canonical Term | Avoid | Reason |
| --- | --- | --- |
| Discoverability Intelligence Platform | SEO tool | category clarity |
| Discoverability Score | SEO score, visibility score | preserve model identity |
| Issue | finding, problem item, defect note | sole canonical customer and product deficiency object |
| Recommendation Artifact | output file, generated fix | consistent implementation object |
| Monitoring Run | weekly scan, re-crawl | stable lifecycle term |
| Technical Integrity | technical health score | pillar consistency |
| AI Presence | LLM visibility | pillar consistency |
| Authority Signals | authority score | pillar consistency |

## Abbreviation Policy

- Use abbreviations only after first expanded mention.
- Avoid introducing new abbreviations unless reused at least three times in the same document.
- Do not abbreviate canonical terms in headings.

## Numbering And Identifier Policy

- Foundation documents: 000 to 020.
- ADR entries: ADR-XXX sequential format.
- Versions: semantic style plus architecture phase qualifier where needed.

## API And Data Terminology Rules

- Entities in prose use singular nouns, for example Project, Source, Issue, ScoreSnapshot.
- Table names and endpoints should be pluralized in technical specs unless constrained by framework conventions.
- IDs should be unambiguous about scope, for example account_id, domain_id.

## Tone And Voice Requirements

- write declaratively, not aspirationally
- prioritize precision over rhetoric
- avoid marketing superlatives in technical specifications

## Change Governance

Terminology changes require:

1. glossary update in [002 GLOSSARY.md](002 GLOSSARY.md)
2. terminology update in this document
3. ADR update in [../DECISIONS.md](../DECISIONS.md)
4. refactor of dependent chapters in same change set

## Acceptance Criteria

1. canonical term set and naming rules are explicit
2. disallowed variants are documented for high-risk terms
3. change governance is clear and enforceable

## References

- [002 GLOSSARY.md](002 GLOSSARY.md)
- [010 DOCUMENT_STANDARDS.md](010 DOCUMENT_STANDARDS.md)
- [../DECISIONS.md](../DECISIONS.md)
