# engineering/manual/volume-iii/CHAPTER-017-Logging-and-Observability-Standards.md

---
title: Logging and Observability Standards
identifier: EM-III-017
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 17 — Logging and Observability Standards

## 1. Purpose

This chapter defines the mandatory engineering standards governing logging and observability throughout the F1 platform.

Observability exists to make production behaviour understandable without modifying running software.

Logs, metrics and traces SHALL collectively describe the operational state of the platform.

Every production component SHALL comply with these standards.

---

# 2. Scope

This chapter governs:

- application logging;
- structured logs;
- metrics;
- distributed tracing;
- correlation identifiers;
- observability instrumentation;
- operational diagnostics;
- production telemetry.

These standards apply to every deployable service.

---

# 3. Engineering Philosophy

Software that cannot be observed cannot be operated reliably.

Observability SHALL be designed into the implementation.

It SHALL NOT be retrofitted after deployment.

Instrumentation SHALL support diagnosis without altering business behaviour.

---

# 4. Observability Components

Every production service SHALL implement:

- structured logging;
- application metrics;
- distributed tracing;
- health reporting;
- correlation identifiers.

Together these provide operational visibility.

---

# 5. Structured Logging

Logs SHALL be machine-readable.

Preferred formats include:

- JSON;
- OpenTelemetry-compatible structures.

Every log entry SHALL include:

- timestamp;
- severity;
- service;
- environment;
- operation;
- correlation identifier.

Free-form logging SHOULD be avoided.

---

# 6. Log Levels

The platform SHALL use the following levels consistently.

| Level | Purpose                                      |
| ----- | -------------------------------------------- |
| DEBUG | Development diagnostics                      |
| INFO  | Normal operational events                    |
| WARN  | Recoverable abnormal conditions              |
| ERROR | Failed operations                            |
| FATAL | Service termination or unrecoverable failure |

Severity SHALL reflect operational impact.

---

# 7. Correlation Identifiers

Every externally initiated request SHALL receive a correlation identifier.

The identifier SHALL propagate across:

- HTTP requests;
- background jobs;
- message publication;
- external integrations.

Correlation SHALL support end-to-end tracing.

---

# 8. Metrics

The platform SHALL expose operational metrics including:

- request count;
- request latency;
- error rate;
- queue depth;
- queue latency;
- retry count;
- database latency;
- cache performance.

Metrics SHALL remain low-cardinality where practical.

---

# 9. Distributed Tracing

Distributed tracing SHALL capture:

- request lifecycle;
- service boundaries;
- external integrations;
- background execution;
- database operations.

Tracing SHALL preserve causal relationships between operations.

---

# 10. Business Events

Business events SHALL remain distinct from operational telemetry.

Examples:

Business:

- AssessmentCompleted
- IssueDetected

Operational:

- request completed
- queue retry
- database timeout

Business semantics SHALL not be inferred from infrastructure logs.

---

# 11. Sensitive Information

Logs SHALL NEVER contain:

- passwords;
- API keys;
- access tokens;
- session secrets;
- encryption keys;
- personal data beyond approved operational requirements.

Sensitive information SHALL be redacted before logging.

---

# 12. Performance

Instrumentation SHALL minimise production overhead.

Observability SHALL not materially degrade application performance.

Sampling MAY be employed where appropriate.

Critical failures SHALL always be recorded.

---

# 13. Error Logging

Errors SHALL include:

- error identifier;
- classification;
- affected operation;
- correlation identifier;
- retry status where applicable.

Stack traces SHALL be available internally but SHALL NOT be exposed to clients.

---

# 14. Operational Dashboards

Production dashboards SHOULD expose:

- application availability;
- latency;
- throughput;
- queue health;
- infrastructure health;
- deployment version;
- error trends.

Dashboards SHALL support operational decision-making.

---

# 15. Retention

Log retention SHALL comply with:

- legal obligations;
- security requirements;
- operational needs;
- privacy policies.

Retention periods SHALL be centrally governed.

---

# 16. AI Engineering

AI coding agents SHALL:

- generate structured logging;
- preserve correlation identifiers;
- avoid logging sensitive data;
- instrument significant operations;
- distinguish business events from operational telemetry.

AI SHALL NOT introduce console debugging into production code.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Logging

- [ ] Structured format.
- [ ] Appropriate severity.
- [ ] Sensitive data protected.

---

## Observability

- [ ] Metrics present.
- [ ] Tracing implemented.
- [ ] Correlation propagated.

---

## Operations

- [ ] Dashboards supported.
- [ ] Error logging complete.
- [ ] Performance acceptable.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Plain-text console logging.
- Logging secrets.
- Missing correlation identifiers.
- Logging entire request payloads unnecessarily.
- Business logic embedded within telemetry.
- Excessive DEBUG logging in production.
- Silent failures.
- Unstructured log messages.
- Metrics with unbounded cardinality.

---

# 19. Compliance

Every deployable service SHALL comply with these standards.

Observability is a production capability, not a debugging convenience.

Reliable operation depends upon complete, structured and secure telemetry.

---

# Cross References

- EM-II-013 Background Processing
- EM-II-014 Event Publication
- EM-III-016 Error Handling Standards
- Engineering Manual Volume VIII — Security Engineering
- Engineering Manual Volume X — Production Operations
- Product Specification
- Architectural Decision Records