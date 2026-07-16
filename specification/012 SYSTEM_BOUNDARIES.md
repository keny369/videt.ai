# 012 SYSTEM_BOUNDARIES

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-16

## Authority

This document defines the canonical scope boundary for Project F1.

Any scope expansion MUST be explicit, versioned, and approved through ADR governance.

## Purpose

Define what F1 is responsible for, what F1 is not responsible for, and where trust, integration, and ownership boundaries exist.

## Scope

This document defines:

- in-scope capabilities
- out-of-scope capabilities
- external actors and systems
- trust and ownership boundaries
- build versus buy boundaries
- human, automation, and AI responsibilities
- prohibited responsibility leakage
- future options that are not commitments

## Dependencies

- [000 OVERVIEW.md](000%20OVERVIEW.md)
- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [005 PRODUCT_PRINCIPLES.md](005%20PRODUCT_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [008 AI_PRINCIPLES.md](008%20AI_PRINCIPLES.md)
- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)

## Definitions

- System Boundary: The explicit responsibility edge of the F1 platform.
- Trust Boundary: A context where identity assurance, authorization, and data handling controls change.
- Responsibility Leakage: Unplanned transfer of obligations between F1 and external actors.

## Assumptions

- F1 remains recommendation-first in baseline scope.
- Customers own implementation execution on their production systems.
- External providers remain required for billing, notifications, and some AI capabilities.

## Constraints

- Scope decisions MUST align with accepted ADRs.
- Security and privacy controls MUST apply at every trust boundary crossing.
- Out-of-scope responsibilities MUST NOT be implied by UI or documentation language.

## Normative Requirements

### System Purpose

SB-REQ-001: F1 MUST provide discoverability measurement, prioritization, and actionable remediation artifacts.

SB-REQ-002: F1 MUST provide recurring monitoring and trend analysis for subscribed scopes.

### In-Scope Capabilities

SB-REQ-003: In-scope capabilities MUST include:

- domain onboarding and scope configuration
- crawl and ingestion orchestration
- discoverability scoring and issue prioritization
- recommendation artifact generation
- AI-assisted explanation with evidence linkage
- reporting, exports, and monitoring summaries
- integration management for approved external systems

For Volume I, “integration management” means only the platform-managed, policy-approved adapter and Credential lifecycle in `integration-interim-v1`. It does not include a customer connector catalogue, arbitrary endpoint entry, customer-supplied provider credentials, or direct customer mutation of Integration/Credential state.

### Out-Of-Scope Capabilities

SB-REQ-004: Out-of-scope capabilities MUST include:

- direct writes to customer production systems
- autonomous deployment to customer infrastructure
- unmanaged execution of customer code
- legal or tax advisory automation
- generalized business analytics unrelated to discoverability

SB-REQ-005: Product messaging MUST NOT imply out-of-scope responsibilities.

### External Actors

SB-REQ-006: External actor classes MUST include:

- Organization Administrators
- Marketing Operators
- Technical Implementers
- Support and Security Operators
- Billing Contacts

SB-REQ-007: Actor responsibilities MUST be explicitly mapped to authorization roles in [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md).

### External Systems

SB-REQ-008: External system classes MUST include:

- search and AI surfaces
- billing provider
- email and notification provider
- monitoring and error tracking provider
- optional webmaster and performance APIs

SB-REQ-009: Every external system integration MUST have an owner, contract, and failure policy.

### Trust Boundaries

SB-REQ-010: The following trust boundaries MUST be enforced:

- customer user boundary (user to F1)
- tenant boundary (organization to organization)
- provider boundary (F1 to external provider)
- operator boundary (customer roles to internal operator roles)

SB-REQ-011: Boundary crossings MUST emit auditable events.

### Integration Boundaries

SB-REQ-012: Integrations MUST use adapter interfaces defined under [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md).

SB-REQ-013: Integration adapters MUST NOT bypass canonical domain and security checks.

### Ownership Boundaries

SB-REQ-014: Ownership boundaries MUST assign a single accountable owner for each capability class.

SB-REQ-015: Shared ownership MUST be documented as explicit dual-control with decision arbitration.

### Build Versus Buy Boundaries

SB-REQ-016: F1 MUST build domain-specific discoverability logic and recommendation orchestration.

SB-REQ-017: F1 MAY buy commodity capabilities for billing, notifications, and infrastructure observability under documented contracts.

SB-REQ-018: Build-versus-buy decisions MUST include exit strategy and portability review.

### Human Responsibilities

SB-REQ-019: Human operators MUST retain authority for policy overrides, incident response, and security exceptions.

SB-REQ-020: Customer implementers MUST retain authority for production remediation execution.

### Automation Responsibilities

SB-REQ-021: Automation MUST execute deterministic checks, scoring pipelines, state transitions, and reporting workflows.

SB-REQ-022: Automation MUST NOT execute unapproved responsibility transfers across trust boundaries.

### AI Responsibilities

SB-REQ-023: AI workflows MUST generate explanations and artifacts within deterministic guardrails.

SB-REQ-024: AI workflows MUST NOT make irreversible business policy decisions without human authorization.

### Prohibited Responsibility Leakage

SB-REQ-025: F1 MUST NOT assume customer obligations for production change control.

SB-REQ-026: F1 MUST NOT expose provider-specific operational risks as customer-managed tasks without explicit acceptance.

SB-REQ-027: F1 MUST NOT treat undocumented side effects as acceptable behavior.

### Future Possibilities That Are Not Commitments

SB-REQ-028: The following possibilities MAY be explored through ADR governance but are not current commitments:

- controlled remediation execution via customer-approved channels
- additional vertical-specific scoring variants
- expanded integration ecosystem

SB-REQ-029: Future possibilities MUST be labeled as non-commitment in roadmap and product documentation.

## Decisions

- DEC-012-01: Baseline scope remains non-invasive and recommendation-first.
- DEC-012-02: Trust boundaries are explicit constitutional controls.
- DEC-012-03: Scope expansion requires ADR and compatibility assessment.

## Non-goals

- This document does not define detailed feature behavior.
- This document does not define implementation sequencing for each capability.

## Risks

- Risk: Scope creep through undocumented assumptions.
  Mitigation: Scope changes MUST fail review without ADR references.
- Risk: Integration behavior bypassing boundary controls.
  Mitigation: Adapter compliance checks MUST run before release.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| In-scope and out-of-scope controls | Specification review and release checklist | Chief Product | Planning gate |
| Trust and ownership boundaries | Architecture review and security review | Chief Architect and Chief Security | Design gate |
| Responsibility leakage controls | Policy test suite and documentation review | Chief Security | CI and PR review |

## Volume I Interim Resolutions

- Enterprise contracts do not permit delegated remediation execution in Volume I. F1 may produce guidance and approved exports only; any direct or delegated customer-production mutation requires a later explicit capability, authority, rollback, audit, and acceptance contract.
- Volume I recognizes only the four logical integration kinds in `integration-interim-v1`. An additional external-system class is unsupported until a later versioned boundary and adapter contract explicitly adds it.

## Related Documents

- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md)
- [diagrams/SYSTEM_CONTEXT.md](../diagrams/SYSTEM_CONTEXT.md)

## Change Control

Any normative change to this document MUST:

1. Include ADR updates.
2. Identify newly in-scope and out-of-scope impacts.
3. Identify security, privacy, and operational impacts.
4. Update related roadmap and state gates.
