# engineering/manual/volume-ii/CHAPTER-008-Service-Architecture.md

---
title: Service Architecture
identifier: EM-II-008
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 8 — Service Architecture

## 1. Purpose

This chapter defines the canonical service architecture for the F1 platform.

Services coordinate behaviour.

They do not own business behaviour.

Business behaviour belongs to the Domain Model.

Service architecture exists to ensure that orchestration, infrastructure integration and application coordination remain separated from business rules.

Every service SHALL possess one clearly defined responsibility.

---

# 2. Scope

This chapter governs:

- Application Services;
- Domain Services;
- Infrastructure Services;
- Integration Services;
- service responsibilities;
- service composition;
- service lifecycles;
- service dependencies.

Every implementation service SHALL conform to this chapter.

---

# 3. Service Philosophy

A service performs work.

A service is **not** a container for miscellaneous business logic.

Whenever behaviour naturally belongs to an Aggregate, Entity or Value Object, it SHALL remain there.

Services SHALL exist only where they provide genuine architectural value.

---

# 4. Service Classification

The platform recognises four service categories.

| Service Type           | Responsibility                       |
| ---------------------- | ------------------------------------ |
| Application Service    | Workflow orchestration               |
| Domain Service         | Domain behaviour spanning Aggregates |
| Infrastructure Service | Technical implementation             |
| Integration Service    | External system communication        |

No additional service categories SHALL be introduced without an approved ADR.

---

# 5. Application Services

## Purpose

Application Services coordinate use cases.

They orchestrate business workflows.

They do **not** own business policy.

---

### Responsibilities

Application Services SHALL:

- receive validated requests;
- load Aggregates;
- coordinate repositories;
- manage transactions;
- invoke Domain behaviour;
- publish Domain Events;
- return application results.

---

### Application Services SHALL NOT:

- enforce business invariants;
- execute SQL;
- call external APIs directly;
- contain presentation logic;
- implement persistence.

---

### Typical Flow

```text
Request

↓

Application Service

↓

Aggregate

↓

Repository

↓

Domain Event

↓

Response
```

---

# 6. Domain Services

## Purpose

Domain Services contain business behaviour that cannot naturally belong to one Aggregate.

Examples include:

- cross-Aggregate calculations;
- policy evaluation;
- complex business decision algorithms.

---

### Domain Services SHALL:

- remain technology independent;
- depend only upon the Domain;
- remain deterministic;
- expose business language.

---

### Domain Services SHALL NOT:

- access infrastructure;
- perform persistence;
- send email;
- publish telemetry;
- invoke HTTP.

---

# 7. Infrastructure Services

Infrastructure Services implement technical capabilities.

Examples include:

- email delivery;
- Redis caching;
- PostgreSQL persistence;
- OpenTelemetry;
- object storage;
- queue publishing.

Infrastructure Services SHALL implement interfaces owned elsewhere.

---

# 8. Integration Services

Integration Services encapsulate communication with external systems.

Examples include:

- Stripe;
- Mailgun;
- OpenAI;
- Google APIs;
- AWS services.

Integration Services SHALL isolate external dependencies from the Domain.

External SDKs SHALL terminate here.

---

# 9. Service Composition

Services MAY collaborate.

However:

- orchestration SHALL remain explicit;
- ownership SHALL remain clear;
- dependency direction SHALL remain correct.

Deep service call chains SHOULD be avoided.

---

# 10. Service Lifetime

Services SHOULD be stateless.

Mutable shared service state is prohibited unless explicitly required by infrastructure.

State belongs to:

- Aggregates;
- repositories;
- persistence.

Not services.

---

# 11. Transactions

Application Services normally own transaction boundaries.

Domain Services SHALL remain unaware of transaction mechanics.

Infrastructure SHALL execute transaction implementation.

---

# 12. Service Interfaces

Every public service SHALL expose a stable interface.

Interfaces SHOULD describe business intent.

Examples:

```text
AssessmentService.start()

EvaluationService.complete()

ProjectService.archive()
```

Avoid implementation-oriented names.

Examples of prohibited names include:

```text
AssessmentProcessorV2

GenericWorkflowManager

UtilityCoordinator
```

---

# 13. Naming

Service names SHALL describe responsibilities.

Examples:

AssessmentCreationService

EvidenceExtractionService

IssueResolutionService

NotificationDispatchService

Names ending in:

Manager

Processor

Handler

Utility

Coordinator

SHOULD be avoided unless they genuinely describe architectural responsibility.

---

# 14. Dependency Rules

Application Services MAY depend upon:

- Domain;
- repository interfaces;
- Domain Services;
- injected infrastructure abstractions.

Infrastructure Services SHALL NOT depend upon Application Services.

Domain Services SHALL NOT depend upon Infrastructure Services.

---

# 15. Error Handling

Services SHALL propagate errors appropriate to their architectural responsibility.

Examples:

- Domain → Domain Exception.
- Application → Workflow Failure.
- Infrastructure → Infrastructure Exception.
- Interface → HTTP Response.

Each layer SHALL translate rather than reinterpret errors.

---

# 16. Observability

Every service SHALL support:

- structured logging;
- tracing;
- metrics where appropriate.

Observability SHALL remain orthogonal to business behaviour.

Instrumentation SHALL NOT pollute Domain logic.

---

# 17. AI Engineering

AI coding agents SHALL:

- preserve service responsibilities;
- avoid creating "God Services";
- avoid placing business logic inside Infrastructure Services;
- avoid using services as generic utility containers;
- prefer Domain behaviour over service abstraction where appropriate.

AI SHALL request clarification where service ownership is ambiguous.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Responsibility

- [ ] Service has one responsibility.
- [ ] Business behaviour correctly located.
- [ ] Service category appropriate.

---

## Architecture

- [ ] Dependency direction preserved.
- [ ] Transactions correctly owned.
- [ ] Infrastructure isolated.

---

## Maintainability

- [ ] Naming appropriate.
- [ ] Stateless where practical.
- [ ] Public interface minimal.
- [ ] Collaboration understandable.

---

# 19. Anti-Patterns

The following practices are prohibited.

- God Services.
- Generic Utility Services containing unrelated behaviour.
- Services owning business invariants.
- Infrastructure Services invoking Aggregates directly.
- Application Services containing SQL.
- Services maintaining mutable global state.
- Deep service dependency chains.
- Service Locator as a service dependency mechanism.
- Framework-specific behaviour inside Domain Services.

---

# 20. Compliance

Every service implementation SHALL conform to the architectural responsibilities defined in this chapter.

Service boundaries are fundamental to the maintainability of the platform.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-004 Layered Architecture
- EM-II-005 Domain-Driven Design
- EM-II-006 Module Boundaries
- EM-II-007 Dependency Rules
- EM-II-009 Command and Query Separation
- EM-II-010 Transaction Boundaries
- EM-II-015 Dependency Injection
- Product Specification
- Architectural Decision Records