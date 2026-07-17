---
title: Repository Architecture
identifier: EM-II-002
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 2 — Repository Architecture

## 1. Purpose

This chapter defines the canonical repository architecture for the F1 platform.

The repository is not merely a storage location for source code.

It is the physical representation of the platform's architecture.

Repository structure SHALL communicate engineering intent, architectural boundaries and ownership without requiring implementation knowledge.

Every file SHALL have an obvious architectural home.

---

# 2. Scope

This chapter governs:

- repository layout;
- directory organisation;
- module ownership;
- application boundaries;
- documentation placement;
- infrastructure organisation;
- testing hierarchy;
- configuration management.

All repository artefacts SHALL comply with this structure.

---

# 3. Repository Philosophy

The repository SHALL satisfy the following objectives.

## RA-001 — Architectural Visibility

Directory structure SHALL reflect architecture rather than framework convention.

An engineer SHALL understand system organisation by examining the repository tree.

---

## RA-002 — Single Responsibility

Each directory SHALL possess one primary architectural purpose.

Mixed responsibilities are prohibited.

---

## RA-003 — Stable Structure

Repository organisation SHALL remain stable.

Structural changes require architectural justification.

---

## RA-004 — Discoverability

Engineers SHALL be capable of locating any implementation artefact predictably.

Repository navigation SHALL not depend upon institutional knowledge.

---

# 4. Canonical Repository Layout

```
f1-platform/

├── app/
├── config/
├── db/
├── docs/
├── infrastructure/
├── lib/
├── scripts/
├── spec/
├── storage/
├── tmp/
├── vendor/
└── README.md
```

Each top-level directory SHALL possess a clearly defined responsibility.

---

# 5. Application Directory

```
app/

├── application/
├── domain/
├── infrastructure/
├── interfaces/
└── shared/
```

Rails default directory organisation SHALL NOT determine business architecture.

The repository SHALL organise implementation according to engineering responsibilities.

---

## application/

Contains:

- command handlers;
- query handlers;
- orchestration;
- application services;
- transaction coordination.

No business rules SHALL originate here.

---

## domain/

Contains:

- aggregates;
- entities;
- value objects;
- domain services;
- specifications;
- policies;
- domain events;
- repositories (interfaces only).

The Domain Layer SHALL remain framework independent.

---

## infrastructure/

Contains:

- Active Record adapters;
- repository implementations;
- Redis;
- PostgreSQL;
- external APIs;
- messaging;
- storage providers;
- email;
- caching;
- observability integrations.

Infrastructure SHALL implement interfaces defined by the Domain.

---

## interfaces/

Contains:

- HTTP controllers;
- GraphQL (if adopted);
- serializers;
- presenters;
- request validation;
- authentication adapters.

Presentation SHALL never contain business rules.

---

## shared/

Contains reusable engineering utilities that do not belong to a single bounded context.

Shared SHALL remain intentionally small.

---

# 6. Documentation

Repository documentation SHALL reside beneath:

```
docs/
```

Recommended structure:

```
docs/

specification/

engineering-manual/

architecture/

adr/

operations/

runbooks/

diagrams/
```

Engineering documentation SHALL NOT be scattered throughout implementation directories.

---

# 7. Database

```
db/

migrate/

schema/

seeds/

fixtures/
```

Database migrations SHALL remain chronologically ordered.

Generated schema SHALL NOT become the authoritative data model.

The Product Specification and Engineering Manual remain authoritative.

---

# 8. Infrastructure

Infrastructure concerns SHALL reside beneath:

```
infrastructure/

docker/

terraform/

kubernetes/

monitoring/

deployment/

ci/
```

Infrastructure SHALL remain isolated from application implementation.

---

# 9. Testing

Testing SHALL remain separated by engineering responsibility.

```
spec/

unit/

integration/

workflow/

contract/

performance/

security/

acceptance/

support/
```

Directory names SHALL communicate verification purpose.

---

# 10. Configuration

Configuration SHALL reside beneath:

```
config/
```

Configuration SHALL remain declarative.

Environment-specific behaviour SHALL be isolated from business behaviour.

---

# 11. Scripts

Engineering utilities SHALL reside beneath:

```
scripts/
```

Examples include:

- validation;
- repository maintenance;
- code generation;
- migrations;
- automation.

Business logic SHALL NOT exist within repository scripts.

---

# 12. Ownership

Every significant repository area SHALL possess an identified architectural owner.

Ownership SHALL include responsibility for:

- quality;
- architectural integrity;
- documentation;
- evolution.

Ownership SHALL survive personnel changes.

---

# 13. Naming

Repository names SHALL be:

- descriptive;
- stable;
- technology neutral where practical;
- singular in purpose.

Abbreviations SHOULD be avoided unless universally understood.

---

# 14. AI Engineering

AI coding agents SHALL:

- preserve repository organisation;
- avoid introducing parallel architectural structures;
- place new implementation within existing architectural boundaries;
- request guidance where no suitable location exists.

AI SHALL NOT invent repository organisation.

---

# 15. Review Checklist

Reviewers SHALL verify:

## Structure

- [ ] Correct directory.
- [ ] Architectural responsibility respected.
- [ ] No mixed concerns.

---

## Dependencies

- [ ] Dependency direction preserved.
- [ ] Framework isolation maintained.
- [ ] Domain independence preserved.

---

## Repository

- [ ] Documentation updated.
- [ ] Naming consistent.
- [ ] Discoverability maintained.

---

# 16. Anti-Patterns

The following practices are prohibited.

- Organising solely according to Rails generators.
- Business logic inside controllers.
- Shared "utils" directories containing unrelated functionality.
- Infrastructure code inside the Domain Layer.
- Duplicate implementations across modules.
- Repository structures requiring tribal knowledge.
- Technology-driven rather than architecture-driven organisation.

---

# 17. Compliance

Every repository change SHALL preserve the architectural structure defined in this chapter.

Repository restructuring requires architectural review and, where significant, an approved ADR.

The repository itself is an architectural artefact and SHALL be maintained accordingly.

---

# Cross References

- EM-II-001 Architecture Philosophy
- EM-II-003 Rails 8 Application Structure
- EM-II-006 Module Boundaries
- EM-II-007 Dependency Rules
- EM-I-007 Repository Governance
- Product Specification
- Architectural Decision Records
