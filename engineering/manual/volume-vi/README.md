# Engineering Manual Volume VI - Background Processing and Integration Standards

    ## Status

    - Status: Normative
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: 2026-07-17

    ## Purpose

    Volume VI defines engineering standards for Sidekiq execution, job contracts, retries, reliable publication and external integration boundaries.

    This volume is subordinate to the Product Specification, ratified Owner Decisions, accepted ADRs and Engineering Manual Volume I. It defines how implementation work SHALL proceed; it does not create product behaviour.

    ## Governing Principles

    - Sidekiq is an execution mechanism, not the workflow owner.
- Jobs SHALL remain thin adapters that invoke Application Services.
- All background work SHALL tolerate at-least-once execution and duplicate delivery.
- Reconciliation, replay and administrative recovery SHALL remain audited and authorised.

    ## Authority Sources

    - specification/volume-ii/BACKGROUND_PROCESSING.md
- specification/volume-ii/INTEGRATION_CONTRACTS.md
- specification/018 OBSERVABILITY.md
- Engineering Manual Volume II background processing architecture

    ## Control Files

    - [INDEX.md](INDEX.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
