---
title: Naming Conventions
identifier: EM-III-003
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 3 — Naming Conventions

## 1. Purpose

This chapter defines the mandatory naming conventions for every implementation artefact within the F1 platform.

Names are part of the architecture.

A correctly named component communicates its responsibility before its implementation is read.

Poor naming increases cognitive load, obscures business intent and accelerates architectural decay.

Every identifier introduced into the repository SHALL comply with this chapter.

---

# 2. Scope

This chapter governs naming for:

- modules;
- classes;
- interfaces;
- services;
- repositories;
- methods;
- variables;
- constants;
- files;
- directories;
- database objects;
- background jobs;
- events.

---

# 3. Naming Philosophy

Names SHALL describe business intent rather than implementation technique.

The Product Specification defines the platform's ubiquitous language.

Implementation SHALL use that language consistently.

A reader unfamiliar with the implementation SHOULD still understand the business meaning of a name.

---

# 4. General Principles

Every name SHALL be:

- descriptive;
- unambiguous;
- pronounceable;
- searchable;
- consistent;
- stable.

Names SHALL optimise readability rather than brevity.

---

# 5. Business Terminology

Business concepts SHALL use the canonical terminology defined in the Product Specification.

The canonical core entities are named by DM-REQ-001 in `specification/011 DOMAIN_MODEL.md`:

- Organization
- Account
- Project
- Source
- Document
- Crawl
- IngestionJob
- ParsingJob
- IndexingJob
- Evaluation
- Issue
- RecommendationArtifact
- AIResponse
- Citation
- Export
- BillingEntity
- Integration
- Credential

Evidence is a lifecycle-bearing auxiliary domain record rather than a DM-REQ-001 core entity, as that requirement expressly records. Role Assignment and Emergency Access Grant are defined by the Volume I identity and access contracts.

DM-REQ-001 is the authority for this list. A name absent from it is not canonical terminology, and this chapter SHALL NOT be read as extending it. Alternative terminology SHALL NOT be introduced without Specification authority, and a term SHALL NOT be presented as canonical merely because it appears in an example.

---

# 6. Class Names

Class names SHALL:

- be singular;
- describe one responsibility;
- use PascalCase.

Examples:

```ruby
Evaluation

EvidenceExtractor

NotificationDispatcher

OrganizationRepository

IssueFingerprintDecision
```

Classes SHALL NOT be named after implementation patterns alone.

Poor examples:

```ruby
Manager

Processor

Utility

Thing

Object
```

---

# 7. Service Names

Services SHALL end with **Service** only where they are genuine Application or Domain Services.

Examples:

```ruby
CrawlCreationService

EvidenceAnalysisService

NotificationDispatchService
```

Services SHALL describe business behaviour rather than technical activity.

---

# 8. Repository Names

Repositories SHALL use the suffix:

```text
Repository
```

Examples:

```ruby
CrawlRepository

ProjectRepository

IssueRepository
```

Infrastructure implementations SHALL describe storage technology only where required.

Example:

```ruby
PostgresCrawlRepository
```

---

# 9. Method Names

Method names SHALL describe behaviour.

Methods returning Boolean values SHALL use predicate naming.

Examples:

```ruby
active?

expired?

authorised?
```

Methods performing actions SHALL use verbs.

Examples:

```ruby
create

publish

archive

dispatch

calculate
```

---

# 10. Variable Names

Variables SHALL:

- describe purpose;
- avoid abbreviations;
- remain sufficiently specific.

Good:

```ruby
crawl

evaluation

organization

confidence_score
```

Poor:

```ruby
obj

tmp

data

value

thing

x
```

Single-letter variables SHALL be limited to conventional iterator usage.

---

# 11. Constants

Constants SHALL:

- use SCREAMING_SNAKE_CASE;
- describe meaning;
- avoid magic values.

Example:

```ruby
MAX_RETRY_ATTEMPTS

DEFAULT_PAGE_SIZE

CACHE_TTL_SECONDS
```

---

# 12. File Names

Ruby files SHALL use:

```text
snake_case.rb
```

Examples:

```text
crawl_repository.rb

issue_detection_service.rb

evaluation.rb
```

File names SHALL match primary class names.

---

# 13. Directory Names

Directories SHALL:

- remain singular where representing a concept;
- remain plural where representing collections by Rails convention only when appropriate;
- reflect architecture rather than implementation convenience.

Directory names SHALL remain stable.

---

# 14. Background Jobs

Background jobs SHALL end with:

```text
Job
```

Examples:

```ruby
EvidenceExtractionJob

NotificationDispatchJob

CrawlExecutionJob
```

Jobs SHALL describe business activity.

---

# 15. Events

Domain Events SHALL describe completed business facts.

Examples:

```text
EvaluationCompleted

IssueCreated

IssueResolved

OrganizationReactivated
```

Events SHALL:

- use past tense;
- remain immutable;
- describe business outcomes.

These are canonical event names taken from `specification/016 STATE_MODEL.md`, which owns the F1 event vocabulary. An event name SHALL NOT be introduced, renamed or inferred by this manual, and a name absent from the state model does not exist.

---

# 16. Database Objects

Database naming SHALL remain explicit.

Examples:

Tables:

```text
evaluations

projects

issues
```

Columns:

```text
created_at

organization_id

confidence_score
```

Table and column names illustrate the naming rule only. The canonical physical schema is owned by `schemas/POSTGRESQL_SCHEMA.md` under the Volume I domain model; no table, column or constraint may be inferred from an example here.

Join tables SHALL remain descriptive.

Abbreviations SHOULD be avoided.

---

# 17. Abbreviations

Abbreviations SHOULD be avoided unless universally understood.

Acceptable examples include:

- API
- HTTP
- URL
- UUID
- JSON

Repository-specific abbreviations are prohibited.

---

# 18. Reserved Words

Ruby reserved words SHALL NOT be reused as identifiers.

Framework-reserved names SHOULD be avoided unless required by Rails conventions.

---

# 19. AI Engineering

AI coding agents SHALL:

- preserve ubiquitous language;
- avoid generic names;
- avoid abbreviations;
- generate descriptive identifiers;
- follow repository naming consistently.

AI SHALL favour clarity over brevity.

---

# 20. Review Checklist

Reviewers SHALL verify:

## Naming

- [ ] Business terminology preserved.
- [ ] Responsibilities obvious.
- [ ] No generic identifiers.

---

## Consistency

- [ ] File names correct.
- [ ] Class names correct.
- [ ] Method names descriptive.

---

## Maintainability

- [ ] Readable.
- [ ] Searchable.
- [ ] Stable.

---

# 21. Anti-Patterns

The following practices are prohibited.

- Manager
- Processor
- Helper
- Utility
- Misc
- Thing
- Data
- Object
- Generic abbreviations
- Single-letter variables outside iterator scope
- Hungarian notation
- Technology-driven names replacing business language

---

# 22. Compliance

Every identifier introduced into the repository SHALL comply with these naming conventions.

Consistent naming is fundamental to architectural readability and long-term maintainability.

---

# Cross References

- EM-III-001 Rails 8 Engineering Philosophy
- EM-III-002 Ruby Coding Standards
- EM-III-004 Class Design Standards
- EM-II-005 Domain-Driven Design
- Product Specification
- Architectural Decision Records
