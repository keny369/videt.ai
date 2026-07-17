# engineering/manual/volume-ii/CHAPTER-015-Dependency-Injection.md

---
title: Dependency Injection
identifier: EM-II-015
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 15 — Dependency Injection

## 1. Purpose

This chapter defines the canonical dependency injection (DI) architecture for the F1 platform.

Dependency Injection exists to separate object construction from object behaviour.

The objective is to reduce coupling, improve testability, preserve architectural boundaries and enable infrastructure implementations to evolve independently of business logic.

Every dependency introduced into the platform SHALL conform to this chapter.

---

# 2. Scope

This chapter governs:

- dependency injection;
- object construction;
- dependency ownership;
- service composition;
- infrastructure wiring;
- interface implementation;
- application bootstrapping.

It does **not** govern application configuration, which is defined in **EM-II-016 Configuration Management**.

---

# 3. Architectural Philosophy

Software components SHOULD depend upon abstractions rather than implementations.

Object creation is an infrastructure concern.

Business behaviour SHALL remain independent of construction mechanics.

The Domain SHALL never construct infrastructure dependencies.

---

# 4. Dependency Ownership

Dependencies SHALL be owned according to the following responsibilities.

| Concern               | Owner                    |
| --------------------- | ------------------------ |
| Business Behaviour    | Domain                   |
| Workflow Composition  | Application              |
| Object Construction   | Infrastructure           |
| Framework Wiring      | Rails                    |
| Runtime Configuration | Configuration Management |

Construction and behaviour SHALL remain separate.

---

# 5. Constructor Injection

Constructor injection SHALL be the default dependency injection mechanism.

Example:

```ruby
class AssessmentService
  def initialize(repository:, publisher:)
    @repository = repository
    @publisher = publisher
  end
end
```

Dependencies SHALL be explicit.

Hidden dependencies are prohibited.

---

# 6. Interface-Based Design

Application Services SHOULD depend upon interfaces.

Example:

```text
AssessmentRepository

↓

PostgresAssessmentRepository
```

Business logic SHALL remain unaware of implementation classes.

---

# 7. Infrastructure Wiring

Infrastructure SHALL assemble object graphs during application startup.

Examples include:

- repository implementations;
- event publishers;
- mail adapters;
- Redis clients;
- telemetry exporters.

Business components SHALL receive fully constructed dependencies.

---

# 8. Domain Layer

The Domain SHALL NOT:

- instantiate repositories;
- instantiate HTTP clients;
- instantiate Redis clients;
- instantiate database connections;
- instantiate framework services.

The Domain SHALL receive abstractions only.

---

# 9. Application Layer

Application Services MAY receive:

- repository interfaces;
- Domain Services;
- event publishers;
- infrastructure abstractions.

Application Services SHALL NOT construct these dependencies internally.

---

# 10. Infrastructure Layer

Infrastructure SHALL construct concrete implementations.

Examples include:

```text
PostgresAssessmentRepository

MailgunNotificationGateway

RedisIdempotencyStore

OpenTelemetryPublisher
```

Infrastructure SHALL satisfy interfaces defined elsewhere.

---

# 11. Service Lifetimes

Services SHOULD normally be stateless.

Singleton lifetime MAY be appropriate for:

- configuration;
- telemetry;
- infrastructure clients.

Request-scoped lifetimes MAY be used where required.

Service lifetime SHALL be chosen deliberately.

---

# 12. Service Locator

The Service Locator pattern SHALL NOT be used as the primary dependency mechanism.

Hidden runtime dependency resolution increases coupling and reduces testability.

Framework internals MAY use service location where unavoidable, but business implementation SHALL remain explicitly injected.

---

# 13. Factories

Factories MAY construct complex objects.

Factories SHALL:

- encapsulate construction;
- avoid business behaviour;
- remain deterministic;
- avoid persistence.

Factories SHALL complement rather than replace dependency injection.

---

# 14. Testing

Dependency Injection SHALL support isolated testing.

Test doubles MAY replace:

- repositories;
- infrastructure services;
- event publishers;
- external integrations.

Testing SHALL NOT require modification of business code.

---

# 15. Framework Integration

Rails SHALL be used to bootstrap dependencies.

Rails SHALL NOT determine business dependency direction.

Framework convenience SHALL NOT override architectural clarity.

---

# 16. Runtime Resolution

Runtime dependency graphs SHOULD remain predictable.

Dependency cycles SHALL be prevented.

Object construction SHALL fail fast where required dependencies cannot be resolved.

---

# 17. AI Engineering

AI coding agents SHALL:

- prefer constructor injection;
- depend upon interfaces;
- avoid Service Locator;
- avoid hidden singleton dependencies;
- preserve explicit construction.

AI SHALL NOT instantiate infrastructure directly from Domain objects.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Injection

- [ ] Dependencies explicit.
- [ ] Constructor injection used.
- [ ] Interfaces preferred.

---

## Architecture

- [ ] Domain independent.
- [ ] Infrastructure constructs implementations.
- [ ] Dependency direction preserved.

---

## Maintainability

- [ ] Testability improved.
- [ ] Hidden dependencies absent.
- [ ] Object construction understandable.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Service Locator as the default dependency mechanism.
- Global mutable singleton state.
- Domain objects constructing infrastructure services.
- Hidden runtime dependency resolution.
- Application Services instantiating repositories.
- Controllers constructing business dependencies.
- Framework-specific dependency annotations throughout the Domain.

---

# 20. Compliance

Every dependency introduced into the platform SHALL comply with this chapter.

Dependency Injection exists to preserve architectural independence, explicitness and long-term maintainability.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-007 Dependency Rules
- EM-II-008 Service Architecture
- EM-II-010 Transaction Boundaries
- EM-II-016 Configuration Management
- Engineering Manual Volume III — Rails 8 Standards
- Product Specification
- Architectural Decision Records