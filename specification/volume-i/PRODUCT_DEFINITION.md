# Volume I Product Definition

## Status

- Status: Accepted
- Last Updated: 2026-07-16
- Owner: Chief Product
- Foundation Version Dependency: 1.0

## Authority

This document is the canonical product-definition baseline for Volume I and is subordinate to foundation 000 through 020.

## Purpose

Define product purpose, users, outcomes, value boundaries, constraints, and exclusions without requiring downstream invention.

## Scope

This document defines product-level requirements PR-REQ-001 through PR-REQ-030.

## Product Purpose And Category

PR-REQ-001: F1 MUST operate as a Discoverability Intelligence Platform rather than a generic SEO audit utility.

PR-REQ-002: The product MUST continuously measure, explain, prioritize, and support remediation of discoverability outcomes across search and AI answer surfaces.

PR-REQ-003: The primary customer promise MUST remain Become the answer.

## Core Customer Problem

PR-REQ-004: The product MUST answer three canonical customer questions with evidence:

1. Why discoverability is underperforming.
2. What should be fixed first.
3. How to execute fixes with minimal ambiguity.

PR-REQ-005: The product MUST prioritize decision-ready guidance over diagnostic data volume.

## Target Users And Actors

PR-REQ-006: Primary user segments MUST include SMB operators, agencies, and in-house mid-market or enterprise growth teams.

PR-REQ-007: Secondary actor segment MAY include consultants delivering discoverability programs.

Consultant is a commercial persona, not a runtime role. A consultant participates only as an invited Account in the customer's Organization with one or more existing OrganizationAdmin, MarketingOperator, or TechnicalImplementer Role Assignments; it receives no implicit cross-Organization scope or additional permission. A consultant serving multiple customers uses separate tenant-scoped assignments and authorization contexts for each Organization.

PR-REQ-008: The platform MUST distinguish buyer and user concerns:

- Executive Buyer: commercial outcomes, risk, trend direction.
- Marketing Operator: issue priority and content or channel actions.
- Technical Implementer: implementation guidance and verification.

PR-REQ-009: Organization Administrator and Security or Billing operators MUST be supported as governance actors according to foundation security and boundary requirements.

An Account belongs to exactly one Organization. `OrganizationMembership` is the derived `(organization_id, account_id)` authorization view over current Account state, Organization authorization epoch, and Role Assignments; it is not a separate mutable entity, permission source, or expiry clock. Bootstrap creates the first active view atomically. An Invitation identifies one intended recipient and offered grant, has exact pending/active/terminal behavior, reaches the recipient through the mandatory direct Mailgun route, and supports accept, decline, revoke, expiry, duplicate suppression, existing-member handling, wrong-identity denial, and terminal reissue exactly as `onboarding-interim-v1` defines. No Account or membership grant exists merely because an Invitation was sent.

## Jobs To Be Done And Desired Outcomes

PR-REQ-010: The product MUST support diagnosis of discoverability gaps with evidence and confidence signals.

PR-REQ-011: The product MUST support priority sequencing by impact, confidence, and effort.

PR-REQ-012: The product MUST support production of implementation-ready remediation artifacts without direct production mutation.

PR-REQ-013: The product MUST support reassessment and trend comparison over time.

PR-REQ-014: Desired customer outcomes MUST include measurable score movement, issue closure progression, and improved discoverability presence.

Until OD-010 is approved, PR-REQ-010, PR-REQ-011, and PR-REQ-014 use the deterministic `check-catalog-v1` measurement boundary: `CHK-TI-001` Technical Integrity, `CHK-SP-001` Search Presence, `CHK-AIP-001` AI Presence, `CHK-AS-001` Authority Signals, `CHK-TR-001` Trust Signals, `CHK-CQ-001` Content Quality, and `CHK-LP-001` Local Presence when applicable. Pure Check execution makes no external call. Because query, intent, listing, provider, and adapter selection are product strategy, `external-measurement-v1` bundles no active external Measurement Set before OD-010 approval; the three always-applicable external Results (`CHK-SP-001`, `CHK-AIP-001`, and `CHK-AS-001`) therefore use handled `input_evidence_missing`, while `CHK-LP-001` does the same only when the frozen Project profile makes local presence applicable and otherwise returns `not_applicable/local_presence_not_applicable` without Measurement Evidence. No path creates an Issue, and missing applicable Evidence makes the numeric score unavailable. Once exact owner-approved Measurement Set bytes activate, an eligible adapter may create only schema-valid immutable `external-observation-v1` Measurement Evidence before Evaluation sealing. Stale, indeterminate, invalid, or cross-Organization required Evidence remains non-decision-grade. The interim catalog defines executable behavior and historical lineage without silently approving final commercial measurement breadth, provider choice, or thresholds.

## Product Value Boundaries

PR-REQ-015: In baseline scope, F1 MUST provide recommendation artifacts and MUST NOT directly modify customer production systems.

PR-REQ-016: The product MUST preserve explainability for score movement and recommendation rationale.

PR-REQ-017: Product behavior MUST remain subordinate to system boundaries in [../012 SYSTEM_BOUNDARIES.md](../012%20SYSTEM_BOUNDARIES.md).

## Product Maturity Stages

PR-REQ-018: Product maturity stages for Volume I planning MUST be:

- Stage 1: Baseline onboarding and initial assessment.
- Stage 2: Continuous monitoring and reassessment.
- Stage 3: Comparative and operational governance features within established boundaries.

PR-REQ-019: Any stage advancement that changes system boundaries, security assumptions, or AI behavior MUST require ADR-governed approval.

## Product Non-Goals And Explicit Exclusions

PR-REQ-020: The platform MUST NOT be treated as a generic web analytics replacement.

PR-REQ-021: The platform MUST NOT perform autonomous deployment or direct customer system mutation in baseline scope.

PR-REQ-022: The platform MUST NOT provide legal or tax advisory automation.

PR-REQ-023: The platform MUST NOT imply capabilities that are explicitly out of scope in [../012 SYSTEM_BOUNDARIES.md](../012%20SYSTEM_BOUNDARIES.md).

## Assumptions

PR-REQ-024: Baseline workflows assume customer-owned remediation execution.

PR-REQ-025: Baseline workflows assume external providers for selected services such as billing, notification, monitoring, and some AI capabilities. Mailgun is the selected baseline email delivery provider through a versioned adapter; Postmark is not in baseline scope. Volume I provider connections are platform-managed under `integration-interim-v1`; customers cannot create arbitrary connectors, enter provider credentials, or mutate Integration/Credential lifecycle state.

PR-REQ-026: Baseline quality thresholds remain provisional where unresolved in [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md).

## Constraints

PR-REQ-027: Volume I MUST NOT redefine domain ownership, security architecture, tenancy strategy, or AI behavior established by foundation documents.

PR-REQ-028: Product requirements MUST remain traceable to research, foundation requirements, and ADRs.

PR-REQ-029: Product requirements that depend on unresolved owner decisions MUST reference [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) and define safe provisional behavior.

PR-REQ-030: Volume I content MUST remain implementation-ready but MUST NOT include implementation code or framework-scaffolding decisions beyond accepted baseline architecture.

## Dependencies

- [INDEX.md](INDEX.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md)
- [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
- [../005 PRODUCT_PRINCIPLES.md](../005%20PRODUCT_PRINCIPLES.md)
- [../../research/000-initial-concept.md](../../research/000-initial-concept.md)

## Change Control

Any normative change to this document MUST:

1. update dependent CAP, WF, and PRULE references
2. update [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
3. add or update owner decisions where unresolved decisions are introduced
