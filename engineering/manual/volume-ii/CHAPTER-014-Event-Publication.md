# engineering/manual/volume-ii/CHAPTER-014-Event-Publication.md

---
title: Event Publication
identifier: EM-II-014
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 14 — Event Publication

## 1. Purpose

This chapter defines the canonical event publication architecture for the F1 platform.

Domain Events communicate that a significant business occurrence has successfully completed.

Events SHALL preserve business meaning without exposing implementation details.

This chapter governs **how** Domain Events are published after they have been created by the Domain Model. It does **not** define which events exist—that authority belongs exclusively to the Product Specification.

---

# 2. Scope

This chapter governs:

- Domain Event publication;
- publication sequencing;
- Outbox implementation;
- event delivery;
- event persistence;
- event ordering;
- retry behaviour;
- publication observability.

This chapter does **not** define:

- event schemas;
- event ownership;
- workflow semantics.

Those remain governed by the Product Specification.

---

# 3. Architectural Philosophy

Domain Events are business facts.

Event publication is an infrastructure concern.

The Domain decides **that** an event occurred.

Infrastructure decides **how** it is delivered.

These responsibilities SHALL remain separate.

---

# 4. Domain Event Lifecycle

The canonical lifecycle SHALL be:

```text
Business Operation

↓

Aggregate

↓

Domain Event Created

↓

Transaction Commit

↓

Outbox Persisted

↓

Publisher Dispatches Event

↓

Consumers Process Event
```

Every published event SHALL represent committed business state.

---

# 5. Event Ownership

| Concern                  | Owner                 |
| ------------------------ | --------------------- |
| Business Meaning         | Product Specification |
| Event Creation           | Domain                |
| Transaction Coordination | Application           |
| Persistence              | Infrastructure        |
| Publication              | Infrastructure        |
| Delivery                 | Infrastructure        |

Ownership SHALL remain exclusive.

---

# 6. Publication Timing

Domain Events SHALL NOT be published before successful transaction commit.

Publication SHALL occur only after:

- business invariants succeed;
- persistence succeeds;
- transaction commits.

Rolled-back transactions SHALL NOT produce published events.

---

# 7. Outbox Pattern

The platform SHALL employ the Outbox Pattern for reliable publication.

Business state and Outbox records SHALL be committed atomically.

Event dispatch MAY occur asynchronously.

This guarantees that committed business events cannot be lost due to transient infrastructure failures.

---

# 8. Delivery Semantics

Event publication SHALL support **at-least-once delivery**.

Consumers SHALL therefore be idempotent.

The platform SHALL never depend upon exactly-once delivery guarantees provided by infrastructure.

Business correctness SHALL be preserved through idempotent processing.

---

# 9. Ordering

Ordering SHALL be guaranteed only where required by the Product Specification.

Global ordering is not required.

Where ordering matters, ordering SHALL normally be preserved within:

- Aggregate;
- workflow instance;
- business stream.

Ordering assumptions SHALL remain explicit.

---

# 10. Event Payloads

Event payloads SHALL:

- remain immutable;
- describe completed business facts;
- avoid implementation detail;
- avoid transport-specific metadata.

Payloads SHOULD include:

- identifier;
- occurrence timestamp;
- correlation identifier;
- causation identifier;
- business identifiers.

Payloads SHALL NOT expose persistence internals.

---

# 11. Publication Failures

Publication failures SHALL be classified.

## Temporary Failure

Examples:

- network interruption;
- broker unavailable.

Retry MAY occur.

---

## Permanent Failure

Examples:

- invalid configuration;
- unsupported destination.

Operational intervention SHALL occur.

---

## Business Failure

Business failures SHALL occur before event publication.

Business failures SHALL NOT create publishable Domain Events.

---

# 12. Retries

Publication retries SHALL:

- preserve ordering where required;
- preserve idempotency;
- avoid duplicate business effects.

Retry behaviour SHALL be observable.

Infinite retry loops are prohibited.

---

# 13. Consumers

Consumers SHALL:

- treat events as immutable;
- remain idempotent;
- tolerate duplicate delivery;
- reject malformed payloads.

Consumers SHALL NOT assume exclusive delivery.

---

# 14. Event Versioning

Where event evolution becomes necessary:

- backward compatibility SHOULD be preserved;
- versioning SHALL be explicit;
- event meaning SHALL remain stable.

Breaking event changes require architectural review.

---

# 15. Observability

Every publication SHALL support:

- structured logging;
- correlation identifiers;
- publication latency;
- retry count;
- publication outcome;
- failure classification.

Operational dashboards SHOULD expose publication health.

---

# 16. Security

Published events SHALL expose only information required by consumers.

Sensitive information SHALL remain protected.

Event publication SHALL comply with applicable data classification and privacy requirements.

---

# 17. AI Engineering

AI coding agents SHALL:

- publish events only after successful transaction completion;
- preserve Outbox semantics;
- avoid publishing directly from Domain objects;
- preserve event immutability;
- implement idempotent consumers.

AI SHALL NOT invent new Domain Events.

Only events defined by the Product Specification may be implemented.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Publication

- [ ] Events published after commit.
- [ ] Outbox used correctly.
- [ ] Delivery semantics preserved.

---

## Architecture

- [ ] Domain creates events.
- [ ] Infrastructure publishes events.
- [ ] Ownership preserved.

---

## Reliability

- [ ] Retry behaviour appropriate.
- [ ] Consumers idempotent.
- [ ] Observability complete.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Publishing events before transaction commit.
- Infrastructure inventing Domain Events.
- Controllers publishing Domain Events.
- Domain publishing directly to message brokers.
- Mutable event payloads.
- Business logic inside event publishers.
- Consumers depending upon exactly-once delivery.
- Silent publication failures.

---

# 20. Compliance

Every Domain Event publication SHALL comply with this chapter.

Business events are part of the platform's observable behaviour and SHALL be published consistently, reliably and deterministically.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-005 Domain-Driven Design
- EM-II-008 Service Architecture
- EM-II-010 Transaction Boundaries
- EM-II-013 Background Processing
- Engineering Manual Volume V — Infrastructure
- Product Specification (Canonical Domain Events)
- Architectural Decision Records