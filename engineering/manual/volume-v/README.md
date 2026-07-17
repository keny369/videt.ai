# Engineering Manual Volume V - Persistence and Data Engineering Standards

    ## Status

    - Status: Normative
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: 2026-07-17

    ## Purpose

    Volume V defines engineering standards for PostgreSQL, schema evolution, data integrity, reconciliation and persistence adapters.

    This volume is subordinate to the Product Specification, ratified Owner Decisions, accepted ADRs and Engineering Manual Volume I. It defines how implementation work SHALL proceed; it does not create product behaviour.

    ## Governing Principles

    - PostgreSQL is persistence infrastructure, not the Domain Model.
- Database constraints SHALL reinforce Domain invariants without becoming their only expression.
- Schema changes SHALL use safe, reversible, expand-and-contract deployment where practical.
- Retention, recovery and archival values SHALL remain deferred to their canonical owner until approved.

    ## Authority Sources

    - schemas/POSTGRESQL_SCHEMA.md
- specification/011 DOMAIN_MODEL.md
- specification/015 DATA_LIFECYCLE.md
- Engineering Manual Volume II persistence architecture

    ## Control Files

    - [INDEX.md](INDEX.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
