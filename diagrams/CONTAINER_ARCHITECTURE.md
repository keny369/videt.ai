# Container Architecture Diagram

## Status

- Status: Canonical
- Version: 1.0
- Last Updated: 2026-07-15

## Authority

This is the canonical container architecture diagram for F1 baseline architecture.

## Scope

This diagram shows runtime containers and primary data and integration flows without implementation internals.

## Terminology

Canonical terms are defined in [../specification/003 TERMINOLOGY.md](../specification/003%20TERMINOLOGY.md).

```mermaid
flowchart TB
    USER[Customer Users]

    WEB[F1 Web and API Container]
    WORKER[F1 Job Worker Container]
    DB[F1 Primary Data Store]
    CACHE[F1 Cache and Queue]

    SEARCH[Search Surfaces]
    AI[AI Provider Services]
    BILL[Billing Provider]
    NOTIF[Notification Provider]

    USER --> WEB
    WEB <--> DB
    WEB <--> CACHE
    WEB --> WORKER
    WORKER <--> DB
    WORKER <--> CACHE

    WEB --> SEARCH
    WORKER --> SEARCH
    WORKER --> AI
    WEB --> BILL
    WORKER --> NOTIF
```

## Related Documents

- [../specification/007 ARCHITECTURE_PRINCIPLES.md](../specification/007%20ARCHITECTURE_PRINCIPLES.md)
- [../specification/018 OBSERVABILITY.md](../specification/018%20OBSERVABILITY.md)
