# Project F1

Project F1 is the canonical Product Architecture Manual for a Discoverability Intelligence Platform.

This repository is documentation-first. Software implementation follows architecture completion.

## Start Here

1. [CLAUDE.md](CLAUDE.md)
2. [governance/PROJECT_CONSTITUTION.md](governance/PROJECT_CONSTITUTION.md)
3. [governance/CUSTOMER_VALUE_CONSTITUTION.md](governance/CUSTOMER_VALUE_CONSTITUTION.md)
4. [governance/QUALITY_STANDARD.md](governance/QUALITY_STANDARD.md)
5. [specification/INDEX.md](specification/INDEX.md)
6. [ROADMAP.md](ROADMAP.md)
7. [PROJECT_STATE.md](PROJECT_STATE.md)

## Canonical Document Flow

1. Constitution and governance define constraints and quality gates.
2. Product Architecture Manual defines business, product, UX, architecture, data, AI, APIs, security, operations, engineering and finance.
3. ADR log captures durable architecture decisions and rationale.
4. Research documents provide evidence and context, but do not override the manual.

## Repository Structure

- `specification/`: Product Architecture Manual volumes and indexes.
- `research/`: supporting market and technical research inputs.
- `governance/`: project constitution, customer value constitution (product-value prioritisation authority), workflow and quality standards.
- `templates/`: reusable templates for ADRs and specifications.
- `roadmap/`: planning artifacts and sequencing details.
- `diagrams/`: architecture and workflow diagrams.
- `wireframes/`: UX flow artifacts.
- `schemas/`: logical and physical data schemas.
- `sql/`: SQL design artifacts and migrations once implementation begins.
- `api/`: API contracts and examples.
- `operations/`: runbooks and operational design.
- `financial-model/`: pricing, unit economics and planning.
- `branding/`, `investor/`, `app-design/`: brand, investor and product presentation assets.

## Rules For Changes

- Update existing documents before adding new files.
- Keep one canonical definition per concept.
- When architecture changes, update affected earlier documents in the same pass.
- Record major decisions in [DECISIONS.md](DECISIONS.md).
