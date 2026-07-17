# engineering/manual/volume-ii/CHAPTER-009-Command-and-Query-Separation.md

---
title: Command and Query Separation (CQS)
identifier: EM-II-009
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 9 — Command and Query Separation (CQS)

## 1. Purpose

This chapter establishes the canonical Command and Query Separation (CQS) architecture for the F1 platform.

The platform SHALL distinguish between operations that change business state and operations that retrieve information.

Commands modify the business.

Queries observe the business.

No operation SHALL perform both responsibilities simultaneously.

This separation improves correctness, determinism, scalability, testability and architectural clarity.

---

# 2. Scope

This chapter governs:

- commands;
- command handlers;
- queries;
- query handlers;
- read models;
- write models;
- request processing;
- business workflows.

Every externally observable business operation SHALL conform to this chapter.

---

# 3. Architectural Philosophy

Business behaviour exists in two fundamentally different forms.

### Commands

Commands request that the system attempt to change business state.

Commands express intent.

Success is not guaranteed.

---

### Queries

Queries request information.

Queries SHALL NOT modify business state.

Queries SHALL be observational.

---

# 4. Fundamental Rule

A software operation SHALL be either:

- a Command;

or

- a Query.

It SHALL NOT be both.

---

# 5. Commands

## Definition

A Command represents a request to perform a business action.

Examples include:

- CreateAssessment
- StartEvaluation
- ArchiveProject
- ReactivateOrganisation
- ResolveIssue
- AssignRole

Commands describe business intent.

---

## Command Characteristics

Every Command SHALL:

- express one business intention;
- be immutable after creation;
- validate structure before execution;
- invoke an Application Service;
- execute within a defined transaction;
- produce deterministic behaviour.

---

## Commands SHALL NOT:

- return mutable business state;
- perform reporting;
- expose persistence;
- contain presentation logic.

---

# 6. Command Handlers

Command Handlers coordinate command execution.

Responsibilities include:

- validation;
- Aggregate loading;
- transaction coordination;
- Domain invocation;
- persistence;
- event publication.

Command Handlers SHALL remain thin.

Business rules belong in the Domain.

---

# 7. Command Results

Commands SHALL return one of:

- success;
- business rejection;
- validation failure;
- infrastructure failure.

Command results SHALL clearly distinguish business failures from technical failures.

---

# 8. Queries

## Definition

Queries retrieve information without modifying business state.

Examples include:

- GetAssessment
- ListProjects
- FindIssues
- ReadEvidence
- SearchOrganisations

---

## Query Characteristics

Queries SHALL:

- remain side-effect free;
- execute deterministically;
- avoid business mutation;
- avoid transaction ownership unless required for consistency;
- remain idempotent.

---

# 9. Query Handlers

Query Handlers SHALL:

- execute read operations;
- compose read models;
- optimise retrieval;
- remain independent of business mutation.

Query Handlers SHALL NOT invoke business workflows.

---

# 10. Read Models

Read Models MAY differ from write models.

Read Models SHOULD optimise:

- reporting;
- searching;
- presentation;
- filtering;
- aggregation.

Read Models SHALL NOT become the canonical business model.

The Domain remains authoritative.

---

# 11. Write Models

Write Models SHALL preserve:

- invariants;
- consistency;
- lifecycle;
- Aggregate ownership.

Commands SHALL modify only write models.

---

# 12. Transactions

Commands normally execute within transactions.

Queries SHOULD avoid unnecessary transactions.

Transaction ownership SHALL remain within the Application Layer.

---

# 13. Domain Interaction

Command Handlers SHALL invoke:

- Aggregates;
- Domain Services;
- repository interfaces.

Queries SHOULD avoid invoking business behaviour except where required to preserve business meaning.

---

# 14. Events

Successful Commands MAY produce Domain Events.

Queries SHALL NEVER produce Domain Events.

Completed business occurrences—not data retrieval—generate events.

---

# 15. Performance

Commands optimise correctness.

Queries optimise retrieval.

Different optimisation strategies MAY therefore exist.

Architectural separation SHALL remain intact.

---

# 16. Naming

Commands SHOULD use imperative names.

Examples:

```
CreateAssessment

ArchiveProject

AssignRole
```

Queries SHOULD use interrogative or retrieval-oriented names.

Examples:

```
GetAssessment

FindProjects

ListIssues

SearchEvidence
```

---

# 17. AI Engineering

AI coding agents SHALL:

- distinguish commands from queries;
- avoid state mutation during queries;
- avoid reporting inside commands;
- preserve deterministic behaviour;
- preserve architectural separation.

Where uncertainty exists, AI SHALL request clarification rather than combine responsibilities.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Commands

- [ ] Single business intention.
- [ ] Business mutation only.
- [ ] Domain invoked.
- [ ] Events correctly produced.

---

## Queries

- [ ] Side-effect free.
- [ ] No state mutation.
- [ ] Read model appropriate.

---

## Architecture

- [ ] CQS preserved.
- [ ] Transactions correctly owned.
- [ ] Domain integrity maintained.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Commands returning mutable Domain objects.
- Queries modifying business state.
- Query Handlers publishing Domain Events.
- Reporting embedded within Command Handlers.
- Controllers directly executing business mutation.
- Combined "UpdateAndReturn" operations.
- Read models becoming business models.
- Business rules implemented within Query Handlers.

---

# 20. Compliance

Every business operation SHALL comply with the Command and Query Separation model defined in this chapter.

Architectural exceptions require an approved ADR before implementation.

Separation between observation and mutation is fundamental to the maintainability and correctness of the F1 platform.

---

# Cross References

- EM-II-004 Layered Architecture
- EM-II-005 Domain-Driven Design
- EM-II-008 Service Architecture
- EM-II-010 Transaction Boundaries
- EM-II-014 Event Publication
- Product Specification
- Architectural Decision Records