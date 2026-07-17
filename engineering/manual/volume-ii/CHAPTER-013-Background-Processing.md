# engineering/manual/volume-ii/CHAPTER-013-Background-Processing.md

---
title: Background Processing
identifier: EM-II-013
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 13 — Background Processing

## 1. Purpose

This chapter defines the canonical background processing architecture for the F1 platform.

Background processing exists to execute work that should not delay synchronous user interactions while preserving business correctness, reliability and observability.

Background execution SHALL improve responsiveness without altering the business semantics defined by the Product Specification.

Background jobs are an implementation mechanism, not a business model.

---

# 2. Scope

This chapter governs:

- Sidekiq architecture;
- asynchronous workflows;
- job execution;
- retries;
- scheduling;
- queue management;
- idempotency;
- failure handling;
- operational monitoring.

Every background job SHALL comply with this chapter.

---

# 3. Architectural Philosophy

Background processing SHALL be:

- deterministic;
- idempotent;
- observable;
- recoverable;
- independently executable.

A background job SHALL execute one clearly defined responsibility.

Business workflows SHALL remain governed by the Domain and Application layers rather than Sidekiq.

---

# 4. Approved Uses

Background processing MAY be used for:

- web crawling;
- AI analysis;
- evidence extraction;
- notifications;
- email delivery;
- scheduled maintenance;
- report generation;
- cache invalidation;
- external API synchronisation;
- search index updates.

---

# 5. Prohibited Uses

Background jobs SHALL NOT:

- replace business workflows;
- own business rules;
- maintain business state;
- bypass transaction boundaries;
- manipulate Aggregates directly without Application Services.

Sidekiq is an execution engine.

It is not the business engine.

---

# 6. Job Structure

Every job SHALL follow this sequence.

```text
Receive Job

↓

Validate Payload

↓

Resolve Dependencies

↓

Invoke Application Service

↓

Record Outcome

↓

Complete
```

Jobs SHALL remain intentionally small.

Business behaviour SHALL reside elsewhere.

---

# 7. Job Payloads

Job payloads SHALL contain only the information required to resume execution.

Payloads SHOULD contain:

- identifiers;
- timestamps;
- version tokens;
- correlation identifiers.

Payloads SHALL NOT contain mutable business objects.

---

# 8. Queue Design

Queues SHALL represent operational priorities rather than business domains.

Recommended queues include:

```text
critical

high

default

low

maintenance
```

Queue proliferation SHOULD be avoided.

---

# 9. Retry Strategy

Retry behaviour SHALL be explicit.

Transient infrastructure failures MAY be retried.

Business validation failures SHALL NOT be retried automatically.

Retries SHALL preserve idempotency.

Infinite retry loops are prohibited.

---

# 10. Idempotency

Every job SHALL be safe to execute more than once unless the Product Specification explicitly defines otherwise.

Repeated execution SHALL NOT create duplicate business effects.

Idempotency SHALL be preserved independently of Sidekiq retry behaviour.

---

# 11. Scheduling

Scheduled jobs SHALL execute according to explicit schedules.

Schedules SHALL remain version controlled.

Business behaviour SHALL NOT depend upon undocumented cron expressions.

---

# 12. Failure Handling

Job failures SHALL be classified.

## Business Failure

Business preconditions not satisfied.

Retry normally inappropriate.

---

## Infrastructure Failure

Temporary technical failure.

Retry MAY be appropriate.

---

## Permanent Failure

Execution impossible without engineering intervention.

Alerting SHALL occur.

---

# 13. Dead Letter Processing

Jobs exceeding retry limits SHOULD be transferred to a dead-letter mechanism.

Dead-letter jobs SHALL remain:

- observable;
- recoverable;
- auditable.

Permanent loss of executable work is prohibited.

---

# 14. Concurrency

Concurrent job execution SHALL preserve business correctness.

Where required:

- distributed locking;
- optimistic concurrency;
- workflow guards;
- idempotency mechanisms

SHALL prevent duplicate business outcomes.

---

# 15. Transactions

Background jobs SHALL NOT own business transactions directly.

Jobs SHALL invoke Application Services, which own transaction boundaries.

Transaction ownership SHALL remain architecturally consistent regardless of execution mechanism.

---

# 16. Observability

Every job SHALL emit:

- structured logs;
- correlation identifiers;
- execution duration;
- retry count;
- completion status;
- failure classification.

Critical jobs SHOULD emit metrics suitable for operational dashboards.

---

# 17. Security

Background jobs SHALL execute using least privilege.

Sensitive information SHALL NOT be stored in job payloads.

Secrets SHALL be resolved at execution time through approved configuration mechanisms.

---

# 18. AI Engineering

AI coding agents SHALL:

- keep jobs lightweight;
- invoke Application Services rather than Domain objects directly;
- preserve idempotency;
- avoid embedding business rules within jobs;
- implement explicit retry strategies.

AI SHALL NOT treat Sidekiq as a workflow engine.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Architecture

- [ ] Job responsibility singular.
- [ ] Application Service invoked.
- [ ] Domain isolated.

---

## Reliability

- [ ] Retry strategy appropriate.
- [ ] Idempotency preserved.
- [ ] Failure classification correct.

---

## Operations

- [ ] Logging implemented.
- [ ] Metrics emitted.
- [ ] Queue selection appropriate.
- [ ] Scheduling documented.

---

# 20. Anti-Patterns

The following practices are prohibited.

- Business rules inside jobs.
- Jobs directly modifying persistence.
- Long-running monolithic jobs.
- Infinite retries.
- Jobs containing mutable Domain objects.
- Queue-per-feature architectures.
- Hidden scheduling.
- Silent job failures.
- Controllers enqueueing work that bypasses Application Services.

---

# 21. Compliance

Every background process SHALL comply with the architecture defined in this chapter.

Background execution is an implementation mechanism for business workflows—not an alternative business architecture.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-008 Service Architecture
- EM-II-009 Command and Query Separation
- EM-II-010 Transaction Boundaries
- EM-II-012 Redis Architecture
- EM-II-014 Event Publication
- Engineering Manual Volume V — Infrastructure
- Product Specification
- Architectural Decision Records