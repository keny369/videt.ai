# Manual Authority

## Authority Hierarchy

1. Product Specification and foundation documents.
2. Ratified ADRs and Owner Decisions integrated into canonical owners.
3. Canonical workflow, state, API, schema, security and acceptance contracts.
4. Existing Engineering Manual content.
5. New Engineering Manual content.
6. Indexes, summaries and generated control documents.

Lower-authority artefacts SHALL NOT contradict higher-authority artefacts. If conflict cannot be resolved by this hierarchy, affected implementation SHALL stop until the canonical owner resolves the issue.

## Canonical Ownership

Product behaviour, state, workflows, permissions, routes, schemas, commercial values, legal obligations and operational commitments are owned by the Product Specification and ratified decisions. Engineering Governance owns implementation standards and repository stewardship.

## Amendment Governance

Amendments SHALL identify the affected authority, update traceability, preserve historical records and pass the manual validator. Examples remain non-authoritative and SHALL be corrected if they appear to create behaviour.
