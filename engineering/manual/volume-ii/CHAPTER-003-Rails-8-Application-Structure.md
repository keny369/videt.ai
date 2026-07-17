---
title: Rails 8 Application Structure
identifier: EM-II-003
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 3 — Rails 8 Application Structure

## 1. Purpose

This chapter defines the canonical Rails 8 application structure for the F1 platform.

Rails provides the runtime framework.

It does **not** define the system architecture.

The purpose of this chapter is to ensure that Rails serves the architecture rather than shaping it.

Every engineer and AI coding agent SHALL organise Rails according to this chapter.

---

# 2. Scope

This chapter governs:

- application layout;
- Rails engines (if adopted);
- directory structure;
- framework responsibilities;
- autoloading;
- naming conventions;
- application boot organisation;
- separation between Rails and the Domain Model.

---

# 3. Design Philosophy

The F1 platform follows the following principles.

### RS-001 — Rails is Infrastructure

Rails provides:

- HTTP
- routing
- dependency wiring
- persistence integration
- configuration
- bootstrapping

Rails SHALL NOT own business behaviour.

---

### RS-002 — Explicit Architecture

The repository SHALL expose engineering intent.

Rails defaults MAY be overridden whenever they reduce architectural clarity.

---

### RS-003 — Framework Independence

The Domain Layer SHALL remain substantially independent of Rails.

Business logic SHALL survive framework replacement with minimal modification.

---

# 4. Canonical Application Layout

```
app/

application/

domain/

infrastructure/

interfaces/

shared/
```

These directories SHALL represent architectural responsibilities rather than Rails conventions.

---

# 5. Application Layer

```
app/application
```

Contains:

- command handlers;
- query handlers;
- orchestration;
- workflow coordination;
- transaction management.

Application Services SHALL:

- coordinate work;
- invoke Domain behaviour;
- invoke repositories;
- publish events.

Application Services SHALL NOT contain business rules.

---

# 6. Domain Layer

```
app/domain
```

Contains:

```
aggregates/

entities/

value_objects/

domain_services/

repositories/

events/

policies/

specifications/
```

Only repository interfaces belong here.

Persistence implementations belong elsewhere.

The Domain SHALL have zero dependency upon Rails.

---

# 7. Infrastructure Layer

```
app/infrastructure
```

Contains:

```
persistence/

redis/

mail/

search/

external/

telemetry/

jobs/

repositories/

storage/
```

Infrastructure SHALL implement interfaces defined by the Domain.

Infrastructure SHALL NOT define business rules.

---

# 8. Interface Layer

```
app/interfaces
```

Contains:

```
http/

controllers/

serializers/

authentication/

presenters/

validators/
```

Responsibilities include:

- request parsing;
- response formatting;
- authentication integration;
- HTTP concerns.

Controllers SHALL remain intentionally small.

---

# 9. Shared Components

```
app/shared
```

Shared components SHALL exist only where:

- no Domain ownership exists;
- duplication would otherwise occur;
- the abstraction is stable.

Large utility directories are prohibited.

---

# 10. Rails Models

Active Record models SHALL be treated primarily as persistence adapters.

They SHALL:

- map database state;
- support persistence;
- support querying.

They SHALL NOT become the primary location for business behaviour.

Business rules belong within the Domain Layer.

---

# 11. Controllers

Controllers SHALL:

- authenticate;
- authorise;
- validate requests;
- invoke Application Services;
- format responses.

Controllers SHALL NOT:

- contain workflows;
- enforce business invariants;
- implement pricing;
- calculate scores;
- manipulate aggregates directly.

Controllers SHOULD normally remain under approximately 100 lines.

---

# 12. Background Jobs

Background jobs SHALL remain lightweight.

A job SHALL:

1. validate input;
2. load dependencies;
3. invoke an Application Service;
4. report completion.

Jobs SHALL NOT contain business workflows.

---

# 13. Initializers

Rails initializers SHALL be limited to:

- framework configuration;
- dependency registration;
- infrastructure setup;
- instrumentation.

Business configuration SHALL NOT reside within initializers.

---

# 14. Configuration

Configuration SHALL remain under:

```
config/
```

Configuration SHALL be:

- declarative;
- environment-aware;
- deterministic;
- version controlled.

Business behaviour SHALL NOT depend upon mutable configuration unless explicitly authorised by the Product Specification.

---

# 15. Autoloading

Zeitwerk SHALL be used.

Directory names SHALL align with namespace structure.

Autoloading SHALL remain deterministic.

Manual require statements SHOULD be exceptional.

---

# 16. Naming

Namespaces SHALL correspond directly to repository structure.

Example:

```
F1::Application::Commands

F1::Domain::Projects

F1::Infrastructure::Persistence

F1::Interfaces::HTTP
```

Namespace ambiguity is prohibited.

---

# 17. Dependency Direction

Dependencies SHALL always flow:

```
Interfaces

↓

Application

↓

Domain

↓

Infrastructure
```

The Domain SHALL never depend upon Rails.

---

# 18. AI Engineering

AI coding agents SHALL:

- preserve directory structure;
- avoid placing business logic inside Rails models;
- avoid introducing "fat controllers";
- avoid framework-driven architecture;
- request clarification where no architectural location exists.

AI SHALL optimise for repository consistency rather than framework convenience.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Structure

- [ ] Correct directory placement.
- [ ] Namespace consistency.
- [ ] Framework isolation maintained.

---

## Responsibilities

- [ ] Controllers remain thin.
- [ ] Application Services coordinate only.
- [ ] Domain owns business rules.
- [ ] Infrastructure owns technology concerns.

---

## Maintainability

- [ ] Architecture understandable.
- [ ] Duplication avoided.
- [ ] Dependencies correct.
- [ ] Rails conventions do not obscure intent.

---

# 20. Anti-Patterns

The following practices are prohibited.

- Fat Active Record models.
- Fat controllers.
- Business rules inside background jobs.
- Business logic inside serializers.
- Service objects performing persistence directly without repository boundaries.
- Cross-layer dependency violations.
- Framework conventions overriding architectural discipline.
- "God" service classes coordinating unrelated domains.

---

# 21. Compliance

Every Rails application component SHALL conform to this structure.

Architectural deviations require an approved ADR before implementation.

Rails is the implementation framework—not the architecture.

---

# Cross References

- EM-II-001 Architecture Philosophy
- EM-II-002 Repository Architecture
- EM-II-004 Layered Architecture
- EM-II-007 Dependency Rules
- EM-II-008 Service Architecture
- EM-II-015 Dependency Injection
- Product Specification
- Architectural Decision Records
