# Engineering Manual Volume VIII - Security Engineering Standards

    ## Status

    - Status: Normative
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: 2026-07-17

    ## Purpose

    Volume VIII defines engineering standards for Identity, sessions, authorisation, tenant isolation, secret handling, audit evidence and vulnerability governance.

    This volume is subordinate to the Product Specification, ratified Owner Decisions, accepted ADRs and Engineering Manual Volume I. It defines how implementation work SHALL proceed; it does not create product behaviour.

    ## Governing Principles

    - Security defaults SHALL fail closed.
- Tenant isolation SHALL be preserved across every interface, job, query and administrative path.
- Cryptographic algorithms, rotation periods and legal retention values SHALL not be invented in this manual.
- Defence in depth SHALL be required for identity, authorisation, data protection and audit evidence.

    ## Authority Sources

    - specification/014 SECURITY_MODEL.md
- specification/volume-ii/SECURITY_PERFORMANCE.md
- specification/volume-i/WORKFLOW_SPECIFICATIONS.md
- governance/QUALITY_STANDARD.md

    ## Control Files

    - [INDEX.md](INDEX.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
