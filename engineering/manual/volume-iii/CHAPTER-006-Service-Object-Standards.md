# engineering/manual/volume-iii/CHAPTER-006-Service-Object-Standards.md

---
title: Service Object Standards
identifier: EM-III-006
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 6 — Service Object Standards

## 1. Purpose

This chapter defines the mandatory standards governing Service Objects within the F1 platform.

Service Objects implement application orchestration.

They coordinate business workflows.

They do **not** own business rules.

Business behaviour SHALL remain inside the Domain Model.

Every Service Object SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- Application Services;
- Domain Services;
- orchestration;
- dependency injection;
- transactions;
- service interfaces;
- service composition.

Infrastructure Services are governed separately by Engineering Manual Volume II.

---

# 3. Engineering Philosophy

A Service Object coordinates work.

It does not perform all work.

Its responsibility is to:

- receive requests;
- coordinate collaborators;
- invoke Domain behaviour;
- return results.

A Service Object SHALL remain intentionally thin.

---

# 4. Responsibilities

Application Services SHALL:

- validate request structure;
- load Aggregates;
- coordinate repositories;
- invoke Domain behaviour;
- publish Domain Events;
- manage transactions;
- return business outcomes.

Application Services SHALL NOT:

- implement business invariants;
- perform SQL;
- construct infrastructure;
- render responses;
- contain presentation logic.

---

# 5. Domain Services

Domain Services SHALL exist only where behaviour naturally spans multiple Aggregates.

Examples include:

- policy evaluation;
- cross-Aggregate calculation;
- business algorithms.

Domain Services SHALL remain framework-independent.

---

# 6. Service Structure

Every Service Object SHOULD follow this structure.

```ruby
class AssessmentCreationService
  def initialize(...)
  end

  def call(command)
  end

  private

  ...
end
```

The public interface SHOULD remain minimal.

---

# 7. Public Interface

Service Objects SHOULD expose one primary public method.

Preferred:

```ruby
call(...)
```

Alternative names SHALL describe explicit business behaviour.

Examples:

```ruby
create(...)

publish(...)

archive(...)
```

Multiple unrelated public entry points are discouraged.

---

# 8. Constructor Responsibilities

Constructors SHALL:

- receive dependencies;
- establish valid object state;
- perform no business work.

Dependency creation SHALL occur outside the Service Object.

---

# 9. Transactions

Application Services SHALL own transaction boundaries.

Transactions SHALL begin before Domain execution and commit after successful persistence.

Transaction implementation SHALL remain explicit.

---

# 10. Dependencies

Dependencies SHALL be injected.

Examples include:

- repositories;
- event publishers;
- telemetry abstractions;
- infrastructure gateways.

Hidden dependency resolution is prohibited.

---

# 11. Business Logic

Business rules SHALL remain inside:

- Aggregates;
- Entities;
- Value Objects;
- Domain Services.

Application Services SHALL coordinate rather than decide.

If business policy appears within a Service Object, it SHALL normally be relocated to the Domain.

---

# 12. Persistence

Service Objects SHALL access persistence exclusively through repositories.

Direct SQL is prohibited.

Direct Active Record manipulation SHOULD be avoided outside repository implementations.

---

# 13. Error Handling

Service Objects SHALL distinguish between:

- business failures;
- validation failures;
- infrastructure failures.

Business failures SHOULD return explicit business outcomes.

Infrastructure failures MAY propagate exceptions where appropriate.

---

# 14. Return Values

Service Objects SHALL return predictable results.

Return types SHOULD remain stable.

Preferred approaches include:

- Result Objects;
- Success/Failure objects;
- explicit response DTOs.

Returning arbitrary hashes is discouraged.

---

# 15. Logging

Service Objects SHALL emit only operational logging.

Business audit events SHALL remain governed by the Product Specification.

Logging SHALL support observability without polluting business behaviour.

---

# 16. Collaboration

Service Objects MAY invoke:

- Domain Services;
- repositories;
- infrastructure abstractions.

Service Objects SHALL NOT become orchestrators of numerous unrelated services.

Large orchestration chains indicate excessive responsibility.

---

# 17. Naming

Service Objects SHALL describe business capability.

Examples:

```ruby
AssessmentCreationService

EvaluationCompletionService

IssueDetectionService

EvidenceExtractionService
```

Names ending in:

- Manager
- Processor
- Utility
- Coordinator

SHOULD be avoided.

---

# 18. AI Engineering

AI coding agents SHALL:

- generate thin Service Objects;
- preserve Domain ownership;
- inject dependencies;
- avoid hidden persistence;
- avoid business rules within orchestration.

AI SHALL decompose orchestration rather than enlarge Service Objects indefinitely.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Responsibility

- [ ] Service coordinates.
- [ ] Domain owns business behaviour.
- [ ] One primary responsibility.

---

## Architecture

- [ ] Dependencies injected.
- [ ] Transactions correct.
- [ ] Repository boundaries preserved.

---

## Maintainability

- [ ] Public interface minimal.
- [ ] Naming appropriate.
- [ ] Return type predictable.

---

# 20. Anti-Patterns

The following practices are prohibited.

- God Services.
- Services containing business invariants.
- Direct SQL.
- Active Record persistence logic.
- Hidden dependency creation.
- Multiple unrelated public methods.
- Framework logic inside Domain Services.
- Large orchestration chains.
- Utility Services containing unrelated behaviour.

---

# 21. Compliance

Every Service Object SHALL comply with this chapter.

Service Objects exist to coordinate business execution—not to replace the Domain Model.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-008 Service Architecture
- EM-II-010 Transaction Boundaries
- EM-II-015 Dependency Injection
- EM-III-004 Class Design Standards
- EM-III-005 Method Design Standards
- EM-III-007 Repository Standards
- Product Specification
- Architectural Decision Records