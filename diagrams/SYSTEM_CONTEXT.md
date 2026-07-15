# System Context Diagram

## Status

- Status: Canonical
- Version: 1.0
- Last Updated: 2026-07-15

## Authority

This is the canonical system context diagram for F1.

## Scope

This diagram defines external actors, external systems, trust boundaries, and responsibility edges for the current baseline scope.

## Terminology

Canonical terms are defined in [../specification/002 GLOSSARY.md](../specification/002%20GLOSSARY.md) and [../specification/003 TERMINOLOGY.md](../specification/003%20TERMINOLOGY.md).

```mermaid
flowchart LR
    subgraph TB1[Customer Trust Boundary]
        OA[Organization Admin]
        MO[Marketing Operator]
        TI[Technical Implementer]
    end

    subgraph TB2[F1 System Boundary]
        F1[F1 Discoverability Intelligence Platform]
    end

    subgraph TB3[Provider Trust Boundary]
        SE[Search Surfaces]
        AI[AI Provider Services]
        BILL[Billing Provider]
        NOTIF[Notification Provider]
        OBS[Monitoring Provider]
    end

    OA -->|Configure and Review| F1
    MO -->|Analyze and Prioritize| F1
    TI -->|Consume Remediation Artifacts| F1

    F1 -->|Query and Observe| SE
    F1 -->|Generate Assisted Artifacts| AI
    F1 -->|Billing Events| BILL
    F1 -->|Delivery Notifications| NOTIF
    F1 -->|Telemetry Export| OBS

    F1 -. MUST NOT Directly Modify .-> PROD[Customer Production Systems]
```

## Related Documents

- [../specification/012 SYSTEM_BOUNDARIES.md](../specification/012%20SYSTEM_BOUNDARIES.md)
- [../specification/014 SECURITY_MODEL.md](../specification/014%20SECURITY_MODEL.md)
