---
title: Redis Architecture
identifier: EM-II-012
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 12 — Redis Architecture

## 1. Purpose

This chapter defines the canonical Redis architecture for the F1 platform.

Redis is an infrastructure component providing high-performance ephemeral data storage.

Redis SHALL be used to improve performance, scalability and operational efficiency.

Redis SHALL NOT become the authoritative source of business truth.

Business state SHALL remain authoritative within PostgreSQL and the Domain Model.

---

# 2. Scope

This chapter governs:

- Redis usage;
- caching;
- distributed locking;
- rate limiting;
- idempotency;
- session support;
- queues;
- ephemeral state;
- invalidation.

Every Redis implementation SHALL comply with this chapter.

---

# 3. Architectural Philosophy

Redis is a performance optimisation.

Redis SHALL never determine business correctness.

Loss of Redis SHALL reduce performance rather than corrupt business behaviour.

The platform SHALL remain functionally correct if Redis is unavailable.

---

# 4. Approved Responsibilities

Redis MAY be used for:

- caching;
- distributed locks;
- idempotency keys;
- rate limiting;
- short-lived coordination;
- temporary workflow state;
- Sidekiq infrastructure;
- request throttling.

Redis SHALL NOT permanently store business entities.

---

# 5. Prohibited Uses

Redis SHALL NOT become:

- the primary database;
- the system of record;
- the authoritative workflow state;
- the only copy of customer data;
- the sole source of audit information.

Persistent business state belongs in PostgreSQL.

---

# 6. Cache Design

Caches SHALL:

- improve performance;
- remain disposable;
- tolerate eviction;
- support explicit invalidation.

Applications SHALL function correctly when cache entries are absent.

Cache misses SHALL NOT constitute business failures.

---

# 7. Cache Keys

Cache keys SHALL:

- remain deterministic;
- include namespace prefixes;
- avoid collisions;
- support invalidation.

Example:

```text
evaluation:12345

project:87

organization:42
```

Opaque key naming is discouraged.

---

# 8. Time-To-Live (TTL)

Every cache entry SHALL possess an explicit expiry unless permanent caching has been architecturally justified.

TTL values SHALL reflect business volatility.

Very long TTLs require engineering justification.

---

# 9. Cache Invalidation

Cache invalidation SHALL be explicit.

Invalidation SHOULD occur after successful transaction commit.

Stale cache entries SHALL never determine business correctness.

---

# 10. Distributed Locking

Redis MAY provide distributed locking where required.

Locks SHALL:

- possess expiry;
- support timeout;
- avoid deadlock;
- remain recoverable.

Locks SHALL protect coordination rather than business invariants.

Business invariants remain the responsibility of the Domain.

---

# 11. Idempotency

Redis MAY store short-lived idempotency records.

Idempotency storage SHALL:

- tolerate expiry;
- support replay detection;
- preserve correctness;
- complement persistent business guarantees.

Redis SHALL NOT become the only persistence mechanism for business idempotency where long-term guarantees are required.

---

# 12. Rate Limiting

Redis MAY implement:

- API throttling;
- login throttling;
- background processing limits;
- customer quotas.

Rate limiting SHALL remain deterministic.

Limits SHALL be configurable.

---

# 13. Session Support

Where Redis is used for session storage:

- sessions SHALL remain recoverable;
- session expiry SHALL be explicit;
- session invalidation SHALL be deterministic.

Session semantics remain governed by the Product Specification.

---

# 14. Background Processing

Redis SHALL support Sidekiq queue infrastructure.

Redis SHALL NOT become the permanent record of job execution.

Business outcomes SHALL be recorded through the Product Specification's workflow and persistence architecture.

---

# 15. High Availability

Redis deployments SHOULD support:

- replication;
- automatic failover;
- monitoring;
- persistence where operationally justified.

Redis availability SHALL improve resilience rather than define correctness.

---

# 16. Security

Redis SHALL:

- require authentication;
- restrict network access;
- encrypt communications where appropriate;
- disable unsafe administrative operations in production.

Redis SHALL never expose sensitive customer information unnecessarily.

---

# 17. Observability

Redis SHALL expose operational telemetry including:

- memory utilisation;
- eviction rate;
- cache hit ratio;
- cache miss ratio;
- connection count;
- latency;
- command throughput.

Operational dashboards SHALL include Redis health.

---

# 18. AI Engineering

AI coding agents SHALL:

- treat Redis as infrastructure;
- avoid storing authoritative business state;
- preserve explicit cache invalidation;
- avoid business rules within cache logic;
- prefer PostgreSQL for durable state.

AI SHALL NOT optimise correctness by depending upon Redis.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Architecture

- [ ] Redis used appropriately.
- [ ] Business state not cached exclusively.
- [ ] Cache disposable.

---

## Correctness

- [ ] Cache invalidation defined.
- [ ] TTL appropriate.
- [ ] Locking justified.

---

## Operations

- [ ] Observability implemented.
- [ ] Security configured.
- [ ] Failure behaviour understood.

---

# 20. Anti-Patterns

The following practices are prohibited.

- Using Redis as the primary database.
- Persisting authoritative business entities solely in Redis.
- Infinite-lived cache entries without justification.
- Hidden cache invalidation.
- Business rules dependent upon cache state.
- Global mutable application state stored in Redis.
- Locking without expiry.
- Assuming Redis availability for business correctness.

---

# 21. Compliance

Every Redis implementation SHALL comply with the architecture defined in this chapter.

Redis exists to improve performance and coordination—not to replace the Domain Model or the primary persistence architecture.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-007 Dependency Rules
- EM-II-011 Persistence Architecture
- EM-II-013 Background Processing
- EM-II-016 Configuration Management
- Engineering Manual Volume V — Infrastructure
- Product Specification
- Architectural Decision Records
