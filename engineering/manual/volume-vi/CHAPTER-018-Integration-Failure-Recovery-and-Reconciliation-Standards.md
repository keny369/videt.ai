---
title: Integration Failure Recovery and Reconciliation Standards
identifier: EM-VI-018
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 18 - Integration Failure Recovery and Reconciliation Standards

## 1. Purpose

This chapter defines the mandatory engineering standard for integration failure recovery and reconciliation standards in the F1 platform.

The purpose of this standard is to make Integration, Failure, Recovery, Reconciliation implementation predictable, reviewable and subordinate to the Product Specification. It establishes how engineers and AI coding agents SHALL apply the volume concern without inventing product behaviour, routes, states, events, schema objects, operational commitments or commercial values.

## 2. Scope

This chapter governs implementation decisions, design review, verification evidence and repository changes related to integration failure recovery and reconciliation standards.

It applies to application code, tests, documentation, migration work, operational procedures and AI-assisted changes whenever those activities touch this concern. It does not authorise new product capability; missing product-specific values remain deferred to their canonical owner.

## 3. Governing Principles

- Sidekiq is an execution mechanism, not the workflow owner.
- Jobs SHALL remain thin adapters that invoke Application Services.
- All background work SHALL tolerate at-least-once execution and duplicate delivery.
- Reconciliation, replay and administrative recovery SHALL remain audited and authorised.

The concern governed by this chapter SHALL be implemented only after the relevant authority sources have been inspected. A lower-level implementation convenience SHALL NOT override the Product Specification, ratified Owner Decisions, accepted ADRs or existing manual authority.

## 4. Authority Sources

The principal authority sources for this chapter are:

- specification/volume-ii/BACKGROUND_PROCESSING.md
- specification/volume-ii/INTEGRATION_CONTRACTS.md
- specification/018 OBSERVABILITY.md
- Engineering Manual Volume II background processing architecture

If these sources conflict, engineers SHALL stop the affected implementation path and escalate through repository governance. The Engineering Manual may define engineering rules, but it SHALL NOT create product semantics by implication.

## 5. Implementation Requirements

Implementations SHALL satisfy the following requirements.

- The implementation SHALL identify the canonical requirement, workflow, state, schema, security or interface contract before changing behaviour.
- The implementation SHALL keep business rules in the owning Domain or Application abstraction named by higher authority.
- The implementation SHALL expose dependencies explicitly enough for review, testing and failure diagnosis.
- The implementation SHALL avoid hidden global state, reflection-driven behaviour and framework defaults that obscure ownership.
- The implementation SHALL preserve tenant boundaries, authorisation checks, audit obligations and correlation evidence.
- The implementation SHALL use examples only to illustrate an engineering pattern; examples SHALL NOT introduce unapproved routes, tables, events, permissions, states or providers.
- The implementation SHALL record deferred product-specific values as deferred to the canonical owner rather than filling them with arbitrary numbers.

For integration failure recovery and reconciliation standards, reviewers SHALL pay particular attention to Integration, Failure, Recovery, Reconciliation. Any design that makes this concern the owner of business truth SHALL be rejected unless a higher-authority document explicitly grants that ownership.

## 6. Responsibility and Ownership Boundaries

Engineering Governance owns this standard. Product ownership remains with the Product Specification and ratified Owner Decisions. Application owners own use-case orchestration. Domain owners own invariants and business policy. Infrastructure owners implement technical mechanisms without expanding behaviour.

A change under this chapter SHALL name its owning layer and SHALL explain why that layer is the correct boundary. Cross-layer shortcuts are prohibited unless an accepted ADR authorises the exception and the exception is traceable.

## 7. Lifecycle and Execution Rules

Work governed by this chapter SHALL follow this lifecycle:

1. Inspect canonical authority.
2. Identify the owning layer, contract and verification obligation.
3. Make the smallest coherent change that satisfies the requirement.
4. Validate behaviour with targeted tests or documented review evidence.
5. Update traceability and operational notes when the change affects downstream users or maintainers.

Execution SHALL be repeatable. Any administrative repair, replay, reconciliation, migration, release or manual action SHALL be auditable and SHALL define its stop condition before it is run.

## 8. Security Considerations

Security controls SHALL fail closed when authority, identity, scope or contract validity cannot be established. This chapter does not weaken tenant isolation, session invalidation, role-expiry behaviour, organization reactivation requirements, emergency-access governance, input validation or audit evidence obligations.

Secret material, credentials, tokens and provider responses SHALL be handled only through approved secret and integration boundaries. Logs, metrics and traces SHALL avoid sensitive payloads while retaining correlation and diagnostic value.

## 9. Reliability and Failure Behaviour

Implementations SHALL define observable failure modes and recovery behaviour. Retries SHALL be safe for duplicate execution where the governing workflow can be retried. Failures SHALL NOT silently advance state, publish events, expose stale authorisation or mask partial completion.

Where product-specific recovery objectives, retention periods, capacity values or service commitments are not ratified, this chapter requires the measurement and governance mechanism only. It SHALL NOT invent the missing value.

## 10. Observability Requirements

Implementations SHALL emit or preserve correlation identifiers, causation where canonically available, actor or service identity, tenant scope, result classification and failure reason without leaking protected payloads.

Observability for integration failure recovery and reconciliation standards SHALL support review of whether the correct owner executed the work, whether authority was checked, whether idempotency or concurrency protections applied, and whether any deferred decision blocked execution.

## 11. Testing and Verification Obligations

Verification SHALL be tied to canonical requirements and acceptance criteria. Tests SHALL include successful paths, relevant negative controls and failure behaviour. Code coverage alone SHALL NOT be accepted as proof of correctness.

Changes under this chapter SHOULD include targeted tests for boundary enforcement, authorisation, idempotency, concurrency, retry behaviour, schema compatibility or contract stability whenever those properties are relevant to the change.

## 12. AI Coding-Agent Requirements

AI coding agents SHALL inspect the authority sources before editing files governed by this chapter. They SHALL keep diffs scoped, avoid fabricated commands or results, record validators actually run and stop when the repository does not resolve a material ambiguity.

AI agents SHALL NOT invent product behaviour, workflows, routes, permissions, schema objects, external-provider guarantees, cryptographic choices, service objectives or operational topology.

## 13. Review Checklist

Reviewers SHALL verify:

- [ ] The change cites the controlling authority.
- [ ] The owning layer is correct and explicit.
- [ ] No product behaviour is invented by this engineering standard or its implementation.
- [ ] Security, reliability and observability obligations are preserved.
- [ ] Tests or documented evidence falsify the material risk in the change.
- [ ] Deferred values are recorded as deferred rather than guessed.
- [ ] AI-generated contributions include truthful validation evidence.

## 14. Prohibited Anti-Patterns

The following anti-patterns are prohibited:

- using framework, database, queue, API or operational mechanics as business owners;
- bypassing Application Services to alter lifecycle state;
- inferring permissions, routes, events, statuses or schema fields from naming conventions;
- relying on unreviewed defaults for security-sensitive or data-sensitive behaviour;
- treating documentation examples as authority;
- claiming validation, test success or command output that was not actually observed;
- widening scope to unrelated repository areas during a narrow change.

## 15. Compliance

Compliance with this chapter is mandatory for all repository changes touching integration failure recovery and reconciliation standards. Non-compliance SHALL be corrected before merge or explicitly waived through the accepted governance process with traceability to the approving authority.

## 16. Cross-References

- Engineering Manual Volume I: authority hierarchy, repository governance and AI governance.
- Engineering Manual Volume II: layered architecture, dependency rules and architecture validation.
- Engineering Manual Volume III: implementation standards, service objects, repositories and testing standards.
- Product Specification: canonical product behaviour, workflow, state, API, security, observability and acceptance authority.
