# Engineering Manual Volume VII - API and Interface Engineering Standards

    ## Status

    - Status: Normative
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: 2026-07-17

    ## Purpose

    Volume VII defines engineering standards for HTTP contracts, request and response schemas, API safety, OpenAPI description and client guidance.

    This volume is subordinate to the Product Specification, ratified Owner Decisions, accepted ADRs and Engineering Manual Volume I. It defines how implementation work SHALL proceed; it does not create product behaviour.

    ## Governing Principles

    - Existing canonical API contracts are the only authority for routes, methods, fields and errors.
- Transport semantics SHALL be separated from Domain behaviour.
- Controllers SHALL remain thin adapters around Application Services.
- OpenAPI documents describe canonical contracts; they do not create them.

    ## Authority Sources

    - specification/volume-ii/API_CONTRACTS.md
- specification/017 ERROR_MODEL.md
- specification/014 SECURITY_MODEL.md
- Engineering Manual Volume III API implementation standards

    ## Control Files

    - [INDEX.md](INDEX.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
