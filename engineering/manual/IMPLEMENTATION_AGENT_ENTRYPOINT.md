# Implementation Agent Entrypoint

## Read First

1. Product Specification index and foundation documents.
2. Owner Decision register and ratified Owner Decision records.
3. Workflow, state, API, schema, security, observability and acceptance contracts.
4. Engineering Manual Volume I authority and governance chapters.
5. The volume governing the affected implementation concern.
6. Existing source, tests and validators near the intended change.

## Authority Precedence

Product Specification and integrated decisions outrank the Engineering Manual. Existing manual content outranks generated summaries and indexes. Examples are non-authoritative.

## Traceability Requirements

Every material implementation change SHALL identify the requirement, authority source, verification evidence and affected ownership boundary. Tests SHALL prove the requirement rather than merely execute code.

## Repository Inspection Requirements

Agents SHALL inspect existing code, tests, validators and documentation before modification. They SHALL avoid broad rewrites when a narrow change satisfies the authority.

## Stop Conditions

Stop when product behaviour is missing, authority materially conflicts, a required owner decision is unresolved, validation cannot be made meaningful, or unrelated repository changes cannot be isolated.

## Validation Requirements

Run the narrowest relevant executable validation after the first substantive edit. For manual changes, run scripts/validate_engineering_manual.py and the negative controls when changing validator logic.

## Commit and Evidence Requirements

Commits SHALL be scoped, reviewable and traceable. Do not push, rewrite history or move existing tags without explicit approval. Completion claims SHALL name commands actually run.

## Prohibition Against Invented Behaviour

Agents SHALL NOT invent workflows, routes, commands, states, events, permissions, schema objects, provider guarantees, cryptographic choices, commercial values, legal obligations, service objectives, recovery objectives or deployment topology.

## Current Gate

Application implementation remains gated by the requirement to inspect the specific implementation slice and verify that the Product Specification resolves the behaviour being implemented. The manual baseline alone does not authorise application code changes.
