---
title: Rails Application Structure
identifier: EM-IV-002
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 2 — Rails Application Structure

## 1. Purpose

This chapter defines the mandatory structural standards governing the Rails 8 application within the F1 platform.

A consistent repository structure enables maintainability, architectural clarity and predictable navigation.

The repository SHALL communicate architecture through its directory structure.

Every Rails application SHALL comply with these standards.

---

# 2. Scope

This chapter governs:

- application layout;
- directory organisation;
- namespaces;
- engines;
- library code;
- configuration;
- ownership boundaries.

These standards apply to the entire Rails repository.

---

# 3. Engineering Philosophy

Repository structure reflects architecture.

Directories SHALL represent architectural responsibilities rather than Rails convenience.

Developers SHOULD locate components through architecture rather than framework familiarity.

---

# 4. Root Structure

The repository SHALL contain clearly defined top-level directories.

Example:

```text
app/
config/
db/
lib/
spec/
script/
bin/
storage/
tmp/
vendor/
engineering/
product/
```

Additional top-level directories require engineering approval.

---

# 5. Application Directory

The `app/` directory SHALL contain executable application code only.

Typical structure:

```text
app/

controllers/

services/

domain/

repositories/

jobs/

mailers/

serializers/

presenters/

views/
```

Directory names SHALL reflect architectural responsibility.

---

# 6. Domain Directory

Business behaviour SHALL reside beneath:

```text
app/domain
```

Typical structure:

```text
domain/

aggregates/

entities/

value_objects/

services/

policies/

events/

repositories/
```

The Domain SHALL remain substantially independent of Rails.

---

# 7. Application Services

Application orchestration SHALL reside beneath:

```text
app/services
```

Application Services SHALL coordinate:

- repositories;
- transactions;
- Domain execution;
- event publication.

They SHALL remain separate from Domain Services.

---

# 8. Controllers

Controllers SHALL reside beneath:

```text
app/controllers
```

Controllers SHALL remain transport adapters.

They SHALL NOT contain business logic.

Controller namespaces SHALL reflect public API structure.

---

# 9. Jobs

Background Jobs SHALL reside beneath:

```text
app/jobs
```

Jobs SHALL:

- schedule work;
- invoke Application Services;
- remain idempotent where required.

Business behaviour SHALL remain elsewhere.

---

# 10. Mailers

Mailers SHALL reside beneath:

```text
app/mailers
```

Mailers SHALL construct outbound communication only.

Business workflow SHALL remain outside mailers.

---

# 11. Serializers

Serializers SHALL reside beneath:

```text
app/serializers
```

Serializers SHALL convert Response DTOs into transport representations.

They SHALL contain no business behaviour.

---

# 12. Libraries

General-purpose implementation SHALL reside beneath:

```text
lib/
```

Only reusable framework-independent support code SHOULD exist within `lib`.

Business behaviour SHALL NOT migrate into library code merely for convenience.

---

# 13. Configuration

Application configuration SHALL reside beneath:

```text
config/
```

Configuration SHALL be:

- deterministic;
- documented;
- version controlled.

Runtime configuration SHALL not depend upon undocumented conventions.

---

# 14. Database

Persistence artefacts SHALL reside beneath:

```text
db/

migrate/

schema/

seeds/
```

Database structure SHALL remain an implementation concern.

Business rules SHALL not exist inside migration scripts.

---

# 15. Specifications

Automated tests SHALL reside beneath:

```text
spec/
```

Structure SHOULD mirror application architecture.

Example:

```text
spec/domain

spec/services

spec/controllers

spec/jobs

spec/repositories
```

Test organisation SHALL reinforce architectural understanding.

---

# 16. Namespaces

Namespaces SHALL correspond directly to repository structure.

Example:

```ruby
Domain::Crawl

Application::CrawlCreationService

Infrastructure::PostgresCrawlRepository
```

Namespace drift is prohibited.

---

# 17. AI Engineering

AI coding agents SHALL:

- preserve directory conventions;
- create files within the correct architectural location;
- maintain namespace consistency;
- avoid introducing convenience directories;
- preserve repository readability.

AI SHALL NOT reorganise the repository without explicit architectural authority.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Structure

- [ ] Files correctly located.
- [ ] Namespaces aligned.
- [ ] Architecture visible.

---

## Maintainability

- [ ] Repository consistent.
- [ ] Directory purpose clear.
- [ ] No misplaced responsibilities.

---

## Governance

- [ ] No unauthorised top-level directories.
- [ ] Domain isolated.
- [ ] Configuration documented.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Business logic in `lib/`.
- Controllers containing orchestration.
- Repository-wide `helpers/` directories containing business logic.
- Generic utility directories.
- Namespace mismatch.
- Architecture hidden beneath framework conventions.
- Convenience folders without architectural ownership.
- Mixing Domain and Infrastructure code.

---

# 20. Compliance

Every Rails repository SHALL comply with these structural standards.

Repository organisation is an architectural asset and SHALL remain stable, discoverable and aligned with the Engineering Manual.

---

# Cross References

- EM-II-002 Repository Architecture
- EM-II-004 Layered Architecture
- EM-II-006 Module Boundaries
- EM-IV-001 Rails 8 Framework Philosophy
- EM-IV-003 Zeitwerk Standards
- Product Specification
- Architectural Decision Records
