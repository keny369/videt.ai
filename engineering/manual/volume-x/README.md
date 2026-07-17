# Engineering Manual Volume X - Production Engineering Standards

    ## Status

    - Status: Normative
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: 2026-07-17

    ## Purpose

    Volume X defines engineering standards for Deployment, release, runtime operations, incidents, operational access and reliability governance.

    This volume is subordinate to the Product Specification, ratified Owner Decisions, accepted ADRs and Engineering Manual Volume I. It defines how implementation work SHALL proceed; it does not create product behaviour.

    ## Governing Principles

    - Deployment topology, provider choices, service objectives and recovery targets SHALL remain with their canonical owners.
- Process health, application readiness and deployment success SHALL be measured separately.
- Production access SHALL be least-privilege, time-bound where supported, and audited.
- Rollback and roll-forward procedures SHALL preserve data integrity and traceability.

    ## Authority Sources

    - specification/volume-ii/DEPLOYMENT_OBSERVABILITY.md
- specification/018 OBSERVABILITY.md
- governance/WORKFLOW.md
- Engineering Manual Volume I repository governance

    ## Control Files

    - [INDEX.md](INDEX.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
