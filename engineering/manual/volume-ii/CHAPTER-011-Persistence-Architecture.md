---
title: Persistence Architecture
identifier: EM-II-011
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 11 — Persistence Architecture

## 1. Purpose

This chapter defines the canonical persistence architecture for the F1 platform.

Persistence exists to durably store business state.

Persistence is **not** the business model.

Business behaviour SHALL originate from the Domain Layer.

Persistence SHALL faithfully represent Domain state without becoming the source of business truth.

---

# 2. Scope

This chapter governs:

- persistence responsibilities;
- repository implementations;
- Active Record usage;
- database interaction;
- schema ownership;
- object-relational mapping;
- persistence consistency;
- database abstraction.

Every persistent business object SHALL comply with this chapter.

---

# 3. Architectural Philosophy

Persistence is an Infrastructure concern.

The database stores business state.

The Domain owns business meaning.

The database SHALL NOT determine:

- business rules;
- workflow behaviour;
- Aggregate boundaries;
- lifecycle transitions.

---

# 4. Architectural Ownership

| Concern            | Owner                      |
| ------------------ | -------------------------- |
| Business Behaviour | Domain                     |
| Transactions       | Application                |
| Persistence        | Infrastructure             |
| Storage            | PostgreSQL                 |
| Mapping            | Repository Implementations |

Ownership SHALL remain exclusive.

---

# 5. Repository Pattern

All persistence SHALL occur through repositories.

The Domain SHALL define repository interfaces.

Infrastructure SHALL provide repository implementations.

Example:

```text
CrawlRepository

↓

PostgresCrawlRepository
```

Application Services SHALL depend upon repository interfaces rather than concrete implementations.

---

# 6. Active Record

Active Record SHALL be treated as a persistence mechanism.

Active Record models SHALL:

- map persisted state;
- support persistence;
- support querying;
- support optimistic locking where required.

Active Record models SHALL NOT become business-domain objects.

Business invariants SHALL remain in Aggregates.

---

# 7. Object Mapping

Persistence models SHALL accurately represent Domain state.

Mapping SHALL remain explicit.

Implicit persistence behaviour SHOULD be avoided where it obscures engineering intent.

Complex mapping logic SHOULD reside within repository implementations rather than Active Record callbacks.

---

# 8. Persistence Operations

Repository implementations SHALL provide business-oriented operations.

Examples:

```text
save(crawl)

find(project_id)

load(evaluation_id)
```

Repositories SHALL NOT expose SQL-oriented interfaces.

Examples such as:

```text
execute_sql()

run_query()

select_all()
```

are prohibited as public repository interfaces.

---

# 9. Aggregate Persistence

Aggregates SHALL normally be persisted atomically.

Repository implementations SHALL preserve Aggregate consistency.

Persistence SHALL NOT expose partially modified Aggregates.

---

# 10. Identity

Entity identity SHALL remain independent of persistence implementation.

Identifiers SHALL:

- remain immutable;
- possess no business meaning;
- survive persistence implementation changes.

Primary keys SHALL support identity rather than define it.

---

# 11. Database Constraints

Database constraints SHALL reinforce business correctness.

Examples include:

- foreign keys;
- uniqueness constraints;
- check constraints;
- not-null constraints.

Database constraints SHALL complement—but SHALL NOT replace—Domain invariant enforcement.

---

# 12. Optimistic Locking

Optimistic locking SHALL be preferred.

Version columns or equivalent mechanisms SHOULD detect concurrent modification.

Concurrency failures SHALL be surfaced as business-aware failures by the Application Layer.

---

# 13. Lazy Loading

Implicit lazy loading SHOULD be avoided where it obscures performance characteristics.

Repository implementations SHOULD explicitly load required data.

Hidden database activity SHALL be minimised.

---

# 14. N+1 Queries

Repository implementations SHALL avoid N+1 query patterns.

Performance optimisation SHALL remain explicit.

Query optimisation SHALL NOT compromise architectural boundaries.

---

# 15. Persistence Events

Persistence SHALL NOT define Domain Events.

Domain Events originate from successful business operations.

Persistence MAY support Outbox storage where required by the event publication architecture.

---

# 16. Schema Evolution

Schema evolution SHALL occur through controlled migrations.

Schema changes SHALL:

- preserve data integrity;
- remain reversible where practical;
- maintain compatibility with deployment strategy;
- align with the Product Specification.

Schema changes SHALL undergo architectural review.

---

# 17. Soft Deletion

Soft deletion SHALL be employed only where required by the Product Specification.

Deletion strategy SHALL reflect business semantics rather than framework convenience.

Hidden default scopes that obscure deleted records SHOULD be avoided.

---

# 18. AI Engineering

AI coding agents SHALL:

- preserve repository boundaries;
- avoid placing business logic inside Active Record models;
- avoid direct SQL within Application Services;
- preserve Aggregate consistency;
- prefer repository interfaces over persistence implementation.

AI SHALL NOT allow persistence concerns to leak into the Domain.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Architecture

- [ ] Repository interfaces correctly owned.
- [ ] Infrastructure implementations isolated.
- [ ] Active Record used only for persistence.

---

## Consistency

- [ ] Aggregate persistence correct.
- [ ] Transactions preserved.
- [ ] Concurrency handled.

---

## Performance

- [ ] N+1 queries avoided.
- [ ] Lazy loading understood.
- [ ] Database constraints appropriate.

---

# 20. Anti-Patterns

The following practices are prohibited.

- Business rules inside Active Record callbacks.
- Controllers executing SQL.
- Repository interfaces exposing SQL concepts.
- Domain objects depending upon persistence.
- Hidden persistence side effects.
- Mutable persistence state bypassing Aggregates.
- Database triggers implementing business rules.
- Active Record models functioning as Aggregate Roots.

---

# 21. Compliance

Every persistence implementation SHALL comply with the architecture defined in this chapter.

Persistence exists to support the Domain—not replace it.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-005 Domain-Driven Design
- EM-II-007 Dependency Rules
- EM-II-008 Service Architecture
- EM-II-010 Transaction Boundaries
- EM-II-012 Redis Architecture
- Product Specification
- Architectural Decision Records
