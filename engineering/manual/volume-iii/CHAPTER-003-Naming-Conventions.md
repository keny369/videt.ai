# engineering/manual/volume-iii/CHAPTER-003-Naming-Conventions.md

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

Examples include:

- Organisation
- Project
- Assessment
- Evaluation
- Issue
- Evidence
- Crawl
- Workflow
- Role Assignment
- Emergency Access Grant

Alternative terminology SHALL NOT be introduced without Specification authority.

---

# 6. Class Names

Class names SHALL:

- be singular;
- describe one responsibility;
- use PascalCase.

Examples:

```ruby
Assessment

EvidenceExtractor

NotificationDispatcher

OrganisationRepository

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
AssessmentCreationService

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
AssessmentRepository

ProjectRepository

IssueRepository
```

Infrastructure implementations SHALL describe storage technology only where required.

Example:

```ruby
PostgresAssessmentRepository
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
assessment

evaluation

organisation

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
assessment_repository.rb

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

AssessmentRecalculationJob
```

Jobs SHALL describe business activity.

---

# 15. Events

Domain Events SHALL describe completed business facts.

Examples:

```text
AssessmentCompleted

IssueDetected

OrganisationReactivated

RoleAssignmentExpired
```

Events SHALL:

- use past tense;
- remain immutable;
- describe business outcomes.

---

# 16. Database Objects

Database naming SHALL remain explicit.

Examples:

Tables:

```text
assessments

projects

issues
```

Columns:

```text
created_at

organisation_id

confidence_score
```

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