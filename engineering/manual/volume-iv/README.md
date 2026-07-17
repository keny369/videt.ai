# Engineering Manual Volume IV - Rails Framework Standards

    ## Status

    - Status: Normative
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: 2026-07-17

    ## Purpose

    Volume IV defines engineering standards for Rails 8 framework usage at the interface, application and infrastructure boundaries.

    This volume is subordinate to the Product Specification, ratified Owner Decisions, accepted ADRs and Engineering Manual Volume I. It defines how implementation work SHALL proceed; it does not create product behaviour.

    ## Governing Principles

    - Rails is an implementation framework, not the architecture or the Domain Model.
- Framework mechanics SHALL terminate before entering the Domain Layer.
- Controllers, jobs, mailers and channels SHALL remain adapters around Application Services.
- Framework convenience SHALL NOT redefine product behaviour, workflows, permissions or states.

    ## Authority Sources

    - Product Specification foundations
- Engineering Manual Volume II layered architecture
- Engineering Manual Volume III implementation standards
- architecture/RAILS_APPLICATION_ARCHITECTURE.md

    ## Control Files

    - [INDEX.md](INDEX.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
