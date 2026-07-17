# engineering/manual/volume-iii/CHAPTER-007-Repository-Standards.md

---
title: Repository Standards
identifier: EM-III-007
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 7 — Repository Standards

## 1. Purpose

This chapter establishes the mandatory standards governing Repository implementations within the F1 platform.

Repositories are the exclusive persistence abstraction between the Application Layer and Infrastructure Layer.

Repositories provide access to persisted business state.

They SHALL NOT become business services, query builders or generic data-access layers.

Every Repository implementation SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- repository interfaces;
- repository implementations;
- persistence abstraction;
- Aggregate loading;
- persistence operations;
- query responsibilities;
- mapping;
- transactions.

Repository architecture is defined in Engineering Manual Volume II. This chapter governs implementation.

---

# 3. Engineering Philosophy

Repositories exist to persist Aggregates.

Repositories do not own business behaviour.

Repositories SHALL abstract persistence technology from business implementation.

Changing persistence technology SHOULD require minimal change outside Infrastructure.

---

# 4. Responsibilities

Repositories SHALL:

- load Aggregates;
- persist Aggregates;
- retrieve Domain objects;
- encapsulate persistence implementation;
- map between persistence models and Domain objects.

Repositories SHALL NOT:

- implement business rules;
- enforce workflow behaviour;
- perform orchestration;
- render API responses;
- execute presentation logic.

---

# 5. Repository Interfaces

Repository interfaces SHALL be owned by the Domain.

Example:

```ruby
module Domain
  class AssessmentRepository
  end
end
```

Interfaces SHALL express business operations rather than SQL operations.

---

# 6. Repository Implementations

Infrastructure SHALL implement repository interfaces.

Example:

```ruby
class PostgresAssessmentRepository
  include AssessmentRepository
end
```

Implementation classes SHALL remain within Infrastructure.

---

# 7. Aggregate Loading

Repositories SHALL return fully valid Domain Aggregates.

Partially initialised Aggregates are prohibited.

Lazy construction of Aggregate invariants is prohibited.

---

# 8. Aggregate Persistence

Repositories SHALL persist complete Aggregate state.

Aggregate consistency SHALL remain atomic.

Partial persistence SHALL occur only where explicitly defined by the Product Specification.

---

# 9. Query Methods

Repository methods SHALL describe business intent.

Preferred:

```ruby
find(id)

load(project_id)

save(assessment)

delete(project)
```

Avoid persistence-oriented interfaces such as:

```ruby
execute_sql

run_query

find_by_sql
```

---

# 10. Persistence Technology

Persistence implementation SHALL remain hidden.

Repository consumers SHALL remain unaware of:

- Active Record;
- SQL;
- PostgreSQL extensions;
- indexes;
- storage optimisation.

Persistence technology SHALL terminate within Infrastructure.

---

# 11. Active Record

Active Record MAY be used internally.

Active Record models SHALL NOT escape repository boundaries.

Business logic SHALL NOT reside within Active Record models.

---

# 12. Transactions

Repositories SHALL NOT own business transactions.

Application Services SHALL own transaction boundaries.

Repositories SHALL participate in transactions initiated elsewhere.

---

# 13. Error Handling

Repositories SHALL distinguish:

- record absence;
- concurrency conflict;
- persistence failure;
- infrastructure failure.

Business interpretation SHALL occur outside the Repository.

---

# 14. Query Optimisation

Repositories MAY optimise persistence.

Examples include:

- eager loading;
- batching;
- indexing;
- prepared statements.

Optimisation SHALL remain invisible to callers.

---

# 15. Mapping

Repositories SHALL map:

```text
Persistence

↓

Domain

↓

Persistence
```

Mapping SHALL remain explicit.

Hidden persistence behaviour is discouraged.

---

# 16. Testing

Repositories SHALL possess:

- unit tests;
- integration tests;
- persistence tests.

Repository behaviour SHALL be independently verifiable.

---

# 17. AI Engineering

AI coding agents SHALL:

- preserve repository boundaries;
- avoid business logic;
- avoid SQL leakage;
- preserve Aggregate integrity;
- keep persistence implementation private.

AI SHALL never bypass repositories to manipulate persistence directly.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Architecture

- [ ] Repository abstraction preserved.
- [ ] Infrastructure isolated.
- [ ] Aggregate consistency maintained.

---

## Implementation

- [ ] Business logic absent.
- [ ] SQL encapsulated.
- [ ] Active Record hidden.

---

## Maintainability

- [ ] Naming appropriate.
- [ ] Mapping explicit.
- [ ] Query optimisation isolated.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Business rules inside repositories.
- Controllers querying Active Record directly.
- Repositories returning persistence models.
- SQL exposed through repository interfaces.
- Repositories owning transactions.
- Repository methods named after SQL operations.
- Hidden persistence callbacks.
- Generic BaseRepository abstractions containing unrelated behaviour.

---

# 20. Compliance

Every Repository SHALL comply with these standards.

Repositories are architectural boundaries protecting the Domain from persistence technology.

Their integrity SHALL be preserved throughout the lifetime of the platform.

---

# Cross References

- EM-II-011 Persistence Architecture
- EM-II-015 Dependency Injection
- EM-III-004 Class Design Standards
- EM-III-006 Service Object Standards
- EM-III-008 Data Transfer Objects
- Product Specification
- Architectural Decision Records