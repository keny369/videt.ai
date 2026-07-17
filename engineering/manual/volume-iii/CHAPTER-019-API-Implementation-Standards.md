---
title: API Implementation Standards
identifier: EM-III-019
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 19 — API Implementation Standards

## 1. Purpose

This chapter defines the mandatory engineering standards governing HTTP API implementation throughout the F1 platform.

The API layer exists to expose Product Specification behaviour over HTTP.

It is an Interface Layer.

It SHALL NOT contain business logic.

Every API implementation SHALL comply with these standards.

---

# 2. Scope

This chapter governs:

- Rails controllers;
- HTTP endpoints;
- request processing;
- response generation;
- serialization;
- authentication integration;
- authorization integration;
- API versioning.

These standards apply to every externally accessible HTTP endpoint.

---

# 3. Engineering Philosophy

Controllers translate HTTP into application requests.

Controllers SHALL remain intentionally thin.

Business behaviour SHALL remain inside the Application and Domain Layers.

The API exists to expose behaviour—not implement it.

---

# 4. Controller Responsibilities

Controllers SHALL:

- receive HTTP requests;
- authenticate requests;
- authorize access;
- validate request structure;
- construct Command or Query DTOs;
- invoke Application Services;
- return HTTP responses.

Controllers SHALL NOT:

- implement business rules;
- manipulate persistence;
- construct SQL;
- perform workflow orchestration.

---

# 5. Request Lifecycle

Every request SHALL follow the following lifecycle.

```text
HTTP Request

↓

Authentication

↓

Authorization

↓

Request Validation

↓

DTO Construction

↓

Application Service

↓

Response DTO

↓

Serialization

↓

HTTP Response
```

Business logic SHALL begin only after successful request validation.

---

# 6. Routing

Routes SHALL represent business capabilities.

Examples:

```text
POST /widgets

GET /widgets/{id}

POST /widgets/{id}/inspections
```

Routes SHALL avoid implementation terminology.

These are fictional routes from an unrelated domain, shown to illustrate the naming rule only. F1 routes are owned by the Volume I capability, workflow and permission contracts and their accepted API exposure. This manual SHALL NOT define, name or imply an F1 route, and no route may be inferred from an example here. A route whose read or command authority Volume I does not define SHALL NOT be implemented.

---

# 7. Controllers

Controllers SHOULD remain small.

Typical controller actions SHOULD contain only:

- request extraction;
- validation;
- service invocation;
- response rendering.

Large controllers indicate misplaced responsibilities.

---

# 8. Request Validation

Controllers SHALL validate:

- payload structure;
- media type;
- parameter presence;
- identifier format.

Business validation SHALL occur elsewhere.

---

# 9. DTO Usage

Controllers SHALL exchange DTOs with the Application Layer.

Controllers SHALL NOT expose:

- Domain Entities;
- Value Objects;
- Active Record models.

Architectural boundaries SHALL remain explicit.

---

# 10. Responses

Responses SHALL:

- remain deterministic;
- use stable schemas;
- include correlation identifiers where appropriate;
- preserve documented API contracts.

HTTP responses SHALL reflect Product Specification behaviour.

---

# 11. HTTP Status Codes

Status codes SHALL represent transport outcomes.

Examples:

| Status | Meaning                              |
| ------ | ------------------------------------ |
| 200    | Successful retrieval                 |
| 201    | Resource created                     |
| 202    | Accepted for asynchronous processing |
| 204    | Successful with no response body     |
| 400    | Invalid request                      |
| 401    | Authentication required              |
| 403    | Authorization denied                 |
| 404    | Resource not found                   |
| 409    | Business conflict                    |
| 422    | Validation failure                   |
| 500    | Internal failure                     |

Status codes SHALL remain consistent across the platform.

---

# 12. Error Responses

API errors SHALL include:

- stable error identifier;
- human-readable message;
- correlation identifier;
- optional field reference;
- retry guidance where appropriate.

Implementation details SHALL remain hidden.

---

# 13. Serialization

Serialization SHALL occur outside the Domain.

Serializers SHALL transform Response DTOs into transport formats.

Serialization SHALL remain deterministic.

---

# 14. Versioning

Public APIs SHALL be explicitly versioned where compatibility requires it.

Versioning strategy SHALL remain documented.

Breaking API changes SHALL require architectural review.

---

# 15. Security

Controllers SHALL enforce:

- authentication;
- authorization;
- rate limiting where required;
- request validation;
- secure headers.

Controllers SHALL never trust external input.

---

# 16. Observability

Every request SHALL emit:

- correlation identifier;
- request duration;
- status code;
- endpoint;
- error identifier where applicable.

Operational telemetry SHALL remain automatic.

---

# 17. AI Engineering

AI coding agents SHALL:

- generate thin controllers;
- preserve DTO boundaries;
- avoid business logic;
- use Application Services exclusively;
- preserve consistent response structures.

AI SHALL NOT access persistence directly from controllers.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Architecture

- [ ] Thin controllers.
- [ ] DTO boundaries preserved.
- [ ] Application Services used.

---

## HTTP

- [ ] Status codes correct.
- [ ] Responses deterministic.
- [ ] Errors consistent.

---

## Security

- [ ] Authentication enforced.
- [ ] Authorization enforced.
- [ ] Validation complete.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Fat controllers.
- Active Record queries inside controllers.
- Business rules inside controllers.
- Returning Domain Entities directly.
- Manual JSON construction throughout controllers.
- Authentication bypass.
- Inconsistent HTTP status codes.
- Transport-specific business logic.
- Controller-managed transactions.

---

# 20. Compliance

Every API implementation SHALL comply with these standards.

Controllers exist solely to translate HTTP into Application Layer requests while preserving architectural integrity.

---

# Cross References

- EM-II-004 Layered Architecture
- EM-II-008 Service Architecture
- EM-III-006 Service Object Standards
- EM-III-008 Data Transfer Object Standards
- EM-III-015 Validation Standards
- EM-III-016 Error Handling Standards
- Engineering Manual Volume VII — API Standards
- Product Specification
- Architectural Decision Records
