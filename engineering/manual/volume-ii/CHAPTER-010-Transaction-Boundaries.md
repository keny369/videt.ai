---
title: Transaction Boundaries
identifier: EM-II-010
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 10 — Transaction Boundaries

## 1. Purpose

This chapter establishes the canonical transaction model for the F1 platform.

Transactions preserve business consistency.

They ensure that changes to business state either complete successfully as one coherent operation or have no observable effect.

Transactions are an implementation concern owned by the Application Layer.

Business rules determine **what** must be consistent.

Transactions determine **how** consistency is preserved.

---

# 2. Scope

This chapter governs:

- transaction ownership;
- Aggregate consistency;
- transaction lifetimes;
- commit behaviour;
- rollback behaviour;
- concurrency control;
- idempotency interactions;
- event publication sequencing.

Every operation that modifies business state SHALL comply with this chapter.

---

# 3. Architectural Philosophy

Transactions exist to preserve business invariants.

Transactions SHALL remain:

- explicit;
- predictable;
- minimal in scope;
- deterministic.

Long-running transactions are prohibited.

Business workflows MAY span multiple transactions.

Individual transactions SHALL remain short-lived.

---

# 4. Transaction Ownership

The Application Layer SHALL own transaction boundaries.

Application Services SHALL:

- begin transactions;
- coordinate Aggregate operations;
- invoke repository persistence;
- commit successful changes;
- roll back failed changes.

The Domain Layer SHALL remain unaware of transaction implementation.

---

# 5. Aggregate Consistency

An Aggregate defines the primary consistency boundary.

A single transaction SHOULD normally modify one Aggregate.

Multiple Aggregate transactions require explicit architectural justification.

Where multiple Aggregates participate in one business workflow, eventual consistency SHOULD be preferred unless strong consistency is required by the Product Specification.

---

# 6. Transaction Lifecycle

Every transaction SHALL follow this sequence.

```text
Begin

↓

Load Aggregate(s)

↓

Execute Domain Behaviour

↓

Validate Invariants

↓

Persist Changes

↓

Publish Domain Events

↓

Commit

↓

Return Result
```

If any mandatory step fails before commit, the transaction SHALL be rolled back.

---

# 7. Rollback

Rollback SHALL occur whenever:

- business invariants fail;
- validation fails;
- persistence fails;
- optimistic concurrency fails;
- infrastructure prevents successful completion.

Rollback SHALL restore the persisted business state to that which existed before the transaction began.

Partial persistence is prohibited.

---

# 8. Commit Behaviour

A transaction SHALL be committed only after:

- Aggregate invariants succeed;
- persistence succeeds;
- repository operations complete successfully.

Domain Events SHALL represent committed business facts.

Events SHALL NOT describe rolled-back work.

---

# 9. Domain Events

Domain Events SHALL be published only after successful transaction completion.

A rolled-back transaction SHALL NOT emit Domain Events.

Where an Outbox Pattern is employed, event persistence SHALL occur atomically with business persistence.

Publication MAY occur asynchronously after commit.

---

# 10. Optimistic Concurrency

The platform SHALL prefer optimistic concurrency control.

Concurrency conflicts SHALL be detected before commit.

Conflict detection SHOULD use:

- version numbers;
- concurrency tokens;
- authorization epochs;
- business version identifiers.

Conflict resolution SHALL preserve business correctness.

---

# 11. Idempotency

Commands SHALL support idempotency where required by the Product Specification.

Repeated execution of an already successful command SHALL NOT create duplicate business effects.

Idempotency SHALL be implemented independently of transaction mechanics.

---

# 12. Long-Running Workflows

Business workflows MAY span multiple transactions.

Examples include:

- evaluations;
- external crawls;
- evidence collection;
- notifications;
- billing.

Long-running workflows SHALL coordinate state through workflow orchestration rather than long-lived database transactions.

---

# 13. External Systems

Transactions SHALL NOT remain open while waiting for:

- HTTP requests;
- external APIs;
- email delivery;
- message brokers;
- human interaction.

External communication SHALL occur before transaction commencement or after successful commit, depending upon the required business semantics.

---

# 14. Nested Transactions

Nested transactions SHOULD be avoided.

Where framework support exists, nested transaction semantics SHALL be explicitly understood before adoption.

Nested transactions SHALL NOT obscure business consistency.

---

# 15. Isolation

Isolation levels SHALL preserve business correctness.

Isolation SHALL be selected according to business requirements rather than framework defaults.

Higher isolation SHALL be justified by business need.

---

# 16. Failure Recovery

Where transaction failure occurs:

- business state SHALL remain consistent;
- retries SHALL preserve idempotency;
- partial work SHALL remain recoverable where applicable.

Recovery behaviour SHALL remain deterministic.

---

# 17. AI Engineering

AI coding agents SHALL:

- preserve transaction ownership within Application Services;
- avoid opening transactions within controllers;
- avoid persistence inside Domain objects;
- avoid long-running transactions;
- preserve idempotency guarantees.

AI SHALL NOT introduce transaction boundaries without understanding Aggregate consistency requirements.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Transaction Ownership

- [ ] Application Service owns transaction.
- [ ] Domain unaware of transactions.
- [ ] Infrastructure executes persistence only.

---

## Consistency

- [ ] Aggregate invariants preserved.
- [ ] Rollback behaviour correct.
- [ ] Commit sequencing correct.

---

## Reliability

- [ ] Idempotency preserved.
- [ ] Domain Events published after commit.
- [ ] External calls outside active transactions.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Controllers owning transactions.
- Domain objects opening transactions.
- Long-running database transactions.
- Publishing Domain Events before commit.
- External HTTP calls inside open transactions.
- Multiple Aggregate mutation without architectural justification.
- Silent retry loops that violate business semantics.
- Partial persistence during transaction failure.

---

# 20. Compliance

Every transaction SHALL comply with the architectural rules defined in this chapter.

Transaction correctness is fundamental to business correctness.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-004 Layered Architecture
- EM-II-005 Domain-Driven Design
- EM-II-008 Service Architecture
- EM-II-009 Command and Query Separation
- EM-II-011 Persistence Architecture
- EM-II-014 Event Publication
- Product Specification
- Architectural Decision Records
