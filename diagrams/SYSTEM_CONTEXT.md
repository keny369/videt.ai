# System Context Diagram

## Status

- Status: Canonical
- Version: 1.1
- Last Updated: 2026-07-16

## Authority

This is the canonical system context diagram for F1.

## Scope

This diagram defines external actors, external systems, trust boundaries, and responsibility edges for the current baseline scope.

## Edge Notation

A solid edge is an active baseline responsibility. A dotted edge is a gated or dormant boundary that the accepted baseline does not exercise. Volume I owns the governing behaviour; where this diagram and a Volume I contract disagree, Volume I governs.

The Search Surfaces, AI Provider, and Billing Provider edges are dotted because the accepted baseline makes no call to any of them: `external-measurement-v1` bundles no active Measurement Set pending OD-010 and Checks make no network call, `ai-response-interim-v1` names no approved provider so AI-assisted generation fails closed pending OD-007 and OD-010, and WF-001 creates and activates the baseline BillingEntity with no provider call under the OD-008 interim. The Search Surfaces edge is inbound because external measurement is an ingestion boundary: an eligible adapter submits frozen `external-observation-v1` Measurement Evidence to F1, and F1 issues no outbound query.

## Terminology

Canonical terms are defined in [../specification/002 GLOSSARY.md](../specification/002%20GLOSSARY.md) and [../specification/003 TERMINOLOGY.md](../specification/003%20TERMINOLOGY.md).

```mermaid
flowchart LR
    subgraph TB1[Customer Trust Boundary]
        OA[Organization Administrator]
        MO[Marketing Operator]
        TI[Technical Implementer]
        SO[Security / Support Operator]
        BO[Billing Operator / Billing Contact]
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
        WMP[Optional Webmaster and Performance APIs]
    end

    OA -->|Configure and Govern| F1
    MO -->|Analyze and Prioritize| F1
    TI -->|Consume Remediation Artifacts| F1
    SO -->|Security Governance and Time-bounded Support| F1
    BO -->|Approved Billing and Entitlement Operations| F1

    SE -.->|Measurement Evidence, inbound, only when an approved Measurement Set is active| F1
    F1 -.->|Use only when approved| AI
    F1 -.->|Billing Events, dormant boundary, no baseline call| BILL
    F1 -->|Delivery Notifications| NOTIF
    F1 -->|Telemetry Export| OBS
    F1 -.->|Collect only when approved| WMP

    F1 -. MUST NOT Directly Modify .-> PROD[Customer Production Systems]
```

Support work is performed through the governed, time-bounded SecurityOperator support session; `SupportOperator` is not a standing authorization role. Billing Contact is the external actor class represented by the canonical Billing Operator role for authorized product actions.

## Related Documents

- [../specification/012 SYSTEM_BOUNDARIES.md](../specification/012%20SYSTEM_BOUNDARIES.md)
- [../specification/014 SECURITY_MODEL.md](../specification/014%20SECURITY_MODEL.md)
