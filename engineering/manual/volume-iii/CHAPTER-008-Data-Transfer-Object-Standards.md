# engineering/manual/volume-iii/CHAPTER-008-Data-Transfer-Object-Standards.md

---
title: Data Transfer Object (DTO) Standards
identifier: EM-III-008
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 8 — Data Transfer Object (DTO) Standards

## 1. Purpose

This chapter defines the mandatory standards governing Data Transfer Objects (DTOs) within the F1 platform.

DTOs exist to transport data between architectural layers without exposing Domain objects or Infrastructure implementation.

DTOs SHALL carry data.

They SHALL NOT contain business behaviour.

Every DTO introduced into the repository SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- Command DTOs;
- Query DTOs;
- Response DTOs;
- Event DTOs;
- Integration DTOs;
- serialization boundaries;
- validation responsibilities;
- immutability.

These standards apply to every architectural boundary.

---

# 3. Engineering Philosophy

DTOs exist to isolate layers.

The Domain Model SHALL NOT be exposed across application boundaries.

DTOs SHALL communicate information while preserving architectural independence.

DTOs are not business objects.

DTOs are not persistence models.

DTOs are not API resources.

---

# 4. Responsibilities

DTOs SHALL:

- transport data;
- remain immutable;
- possess explicit structure;
- validate structural integrity where appropriate;
- remain framework-independent.

DTOs SHALL NOT:

- implement business rules;
- own persistence;
- coordinate workflows;
- invoke services;
- contain business calculations.

---

# 5. Categories

The platform recognises the following DTO categories.

## Command DTO

Represents a request to perform business work.

Example:

```ruby
CreateAssessmentCommand
```

---

## Query DTO

Represents a request for information.

Example:

```ruby
FindAssessmentQuery
```

---

## Response DTO

Represents information returned by the Application Layer.

Example:

```ruby
AssessmentResponse
```

---

## Integration DTO

Represents data exchanged with external systems.

Example:

```ruby
MailgunWebhookPayload
```

---

## Event DTO

Represents transport-specific event serialization.

Event DTOs SHALL remain separate from Domain Events.

---

# 6. Immutability

All DTOs SHALL be immutable.

After construction:

- fields SHALL NOT change;
- state SHALL remain fixed;
- behaviour SHALL remain deterministic.

Immutable DTOs reduce accidental coupling and simplify reasoning.

---

# 7. Validation

DTO validation SHALL verify:

- required fields;
- type correctness;
- structural integrity;
- format constraints.

Business validation SHALL occur within the Domain.

Example:

Valid:

- UUID format;
- timestamp format;
- email format.

Invalid:

- organisation lifecycle;
- workflow rules;
- permissions;
- pricing logic.

---

# 8. Construction

DTO construction SHALL be explicit.

Example:

```ruby
CreateAssessmentCommand.new(
  organisation_id:,
  project_id:,
  initiated_by:
)
```

Implicit dynamic construction SHOULD be avoided.

---

# 9. Naming

DTO names SHALL describe their purpose.

Examples:

```ruby
CreateAssessmentCommand

AssessmentSummaryResponse

IssueSearchQuery

NotificationRequest
```

Generic names are prohibited.

Examples:

```ruby
Request

Payload

Data

Message
```

---

# 10. Serialization

DTOs MAY support serialization.

Serialization SHALL remain deterministic.

Supported formats MAY include:

- JSON;
- MessagePack;
- protocol-specific payloads.

Serialization SHALL NOT introduce business behaviour.

---

# 11. Mapping

Mapping SHALL occur explicitly.

```text
Request

↓

Command DTO

↓

Application Service

↓

Domain

↓

Response DTO

↓

Serializer
```

Implicit automatic mapping SHOULD be avoided where it obscures engineering intent.

---

# 12. API Boundaries

Controllers SHALL exchange DTOs rather than Domain objects.

The Domain SHALL remain unaware of HTTP.

DTOs preserve architectural separation.

---

# 13. Integration Boundaries

External APIs SHALL exchange Integration DTOs.

External payloads SHALL NOT directly populate Domain objects.

Transformation SHALL occur explicitly.

---

# 14. Versioning

Where DTO evolution becomes necessary:

- compatibility SHALL be preserved where practical;
- versioning SHALL remain explicit;
- deprecated fields SHALL be documented.

Breaking DTO changes require architectural review.

---

# 15. Testing

DTOs SHALL possess:

- construction tests;
- serialization tests;
- validation tests;
- mapping tests where appropriate.

DTOs SHALL remain deterministic.

---

# 16. AI Engineering

AI coding agents SHALL:

- generate immutable DTOs;
- avoid business behaviour;
- preserve explicit mapping;
- maintain framework independence;
- use descriptive names.

AI SHALL NOT expose Domain objects across architectural boundaries.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Structure

- [ ] Immutable.
- [ ] Explicit fields.
- [ ] Appropriate validation.

---

## Architecture

- [ ] No business logic.
- [ ] No persistence.
- [ ] Layer isolation preserved.

---

## Maintainability

- [ ] Clear naming.
- [ ] Explicit mapping.
- [ ] Stable serialization.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Mutable DTOs.
- Business logic inside DTOs.
- Active Record models used as DTOs.
- Domain objects exposed to controllers.
- Generic payload objects.
- Hidden serialization behaviour.
- Automatic reflection-based mapping.
- Infrastructure dependencies inside DTOs.

---

# 19. Compliance

Every Data Transfer Object SHALL comply with these standards.

DTOs exist to preserve architectural boundaries and maintain implementation independence across the platform.

---

# Cross References

- EM-II-004 Layered Architecture
- EM-II-008 Service Architecture
- EM-II-009 Command and Query Separation
- EM-III-006 Service Object Standards
- EM-III-007 Repository Standards
- EM-III-009 Value Object Standards
- Product Specification
- Architectural Decision Records