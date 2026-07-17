# Manual Authority

## Authority Model

Authority is resolved by scope before rank, as required by PM-REQ-003 in the foundation document `specification/001 PRODUCT_ARCHITECTURE_MANUAL.md`. The canonical statement of the model is PM-REQ-003 and its subrequirements; this document restates it for the Engineering Manual and SHALL NOT diverge from it.

Every decision SHALL first be classified into exactly one authority scope. Only that scope's precedence ladder SHALL then be applied. An artefact holds no authority outside its own scope. Outside its scope an artefact is inapplicable rather than outranked, and SHALL NOT be cited to settle a decision belonging to another scope.

## Scope A — Product Behaviour

Canonical owner: the Product Specification and ratified decisions.

Precedence:

1. Constitution and governance.
2. Foundation layer 000 through 020.
3. ADR registry: accepted ADRs and ratified Owner Decisions integrated into their canonical owners.
4. Volume specifications.
5. Derived implementation artefacts.

The Engineering Manual holds no authority in this scope at any rank. It is a derived implementation artefact with respect to product behaviour and SHALL reference the canonical owner rather than restate, resolve or imply product behaviour.

## Scope B — Engineering Practice

Canonical owner: the Engineering Manual, under Engineering Governance.

Precedence:

1. Constitution and governance.
2. Accepted ADRs.
3. Existing Engineering Manual content.
4. New Engineering Manual content.
5. Source code and tests.
6. Indexes, summaries, generated control documents and informative material.

The Product Specification does not define engineering practice. In this scope it is inapplicable rather than superior.

## Conflict Resolution

Lower-authority artefacts SHALL NOT contradict higher-authority artefacts within the same scope. Cross-scope conflicts SHALL be resolved by scope ownership rather than by rank.

If a conflict cannot be resolved by this model, or the scope of the decision is itself disputed, affected implementation SHALL stop until the canonical owner resolves the issue.

## Canonical Ownership

Product behaviour, state, workflows, permissions, routes, schemas, commercial values, legal obligations and operational commitments are owned by the Product Specification and ratified decisions. Engineering Governance owns implementation standards and repository stewardship.

A pending Owner Decision SHALL retain its deterministic interim behaviour. No manual content, example or index SHALL resolve a pending Owner Decision by implication.

## Amendment Governance

Amendments SHALL identify the affected authority, update traceability, preserve historical records and pass the manual validator. Examples remain non-authoritative and SHALL be corrected if they appear to create behaviour.
