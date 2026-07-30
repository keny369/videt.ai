# Autonomy Policy

## Purpose

This policy defines what the autonomous build controller may decide, what it must escalate, and what it must never do.

The repository, frozen contracts, Decision Ledger, architecture records, and approved build plan are authoritative. Conversational memory is not authoritative state.

## Standing execution authority (DECISIONS ADR-061)

Within an owner-AUTHORISED block, the controller runs each authorised sub-tranche end to end — implement, verify, conduct the ADR-026 five-lens independent review, ACCEPT when every mandatory gate passes with zero confirmed-blocking findings, fast-forward merge into the integration branch, update BUILD_STATE / BUILD_PLAN / ADRs / completion records, and push the integration branch — without stopping for routine acceptance or merge. The objective verification suite plus the independent review ARE the acceptance mechanism. `main` remains untouched; no force-push; no history rewrite; no production path.

`human_gate_before` is set only where a real owner decision is required (a new block, a decomposition, or a genuine contract ambiguity). `human_gate_after` is reserved for a mandatory-gate failure or an acceptance criterion that cannot be objectively satisfied. The controller returns to the owner ONLY for: (1) a genuine repository ambiguity with two materially different valid interpretations affecting behaviour or security; (2) a contract or scope change requiring owner approval; (3) a mandatory verification gate failing or a repository invariant that cannot be satisfied; or when the current authorised block is exhausted and the next requires fresh authorisation.

## Development cadence (DECISIONS ADR-086)

The controller does NOT stop after every implementation unit for strategic confirmation. It continues automatically through the eligible work BUILD_PLAN and BUILD_STATE identify, completes COHERENT BLOCKS of related work, and requests independent adversarial review at meaningful MILESTONES rather than every increment. Repository gates still run continuously after each unit: what changes is the review frequency, never the verification frequency.

It STOPS IMMEDIATELY and requests review on encountering any of these architectural stop conditions:

1. a change to transaction boundaries;
2. a second producer of an immutable entity;
3. changes to authorization or RLS semantics;
4. changes to identity or idempotency ownership;
5. changes to immutable ledger semantics;
6. concurrency primitives or locking strategy;
7. changes that invalidate an accepted proof or accepted contract;
8. repository governance requiring a new ADR or owner decision.

Everything else is normal implementation work. The controller does NOT stop merely because several implementation choices exist, when one is already implied by a repository contract, an accepted ADR or an established architectural principle.

The standard does not move. Professional-grade correctness, scalability, concurrency behaviour, latency and operational robustness take precedence over implementation speed. Each change prefers the smallest repository-consistent form, maintains or improves existing performance characteristics, avoids unnecessary allocations, database round trips and lock duration, and preserves deterministic behaviour under concurrency, recovery semantics and every accepted guarantee. Every completed unit adds or strengthens tests, mutation-tests behavioural invariants where the repository requires it, runs the required gates, and commits with a precise message.

OPTIMISE FOR REDUCING FUTURE COMPLEXITY, NOT TODAY'S LINES OF CODE. Simplicity of ownership boundaries — one producer per entity, one owner per reservation, one authority per identity — predicts behaviour at scale better than local efficiency does.

## Blocking-defect repair authority (DECISIONS ADR-084)

A mandatory gate failure whose ROOT CAUSE HAS BEEN DEMONSTRATED is repaired immediately, whichever tranche owns the defect and whatever tranche is in progress, provided all of: the repair removes the blocker itself rather than merely restoring a passing gate; it is the smallest correction that does so; it does not change product semantics; it does not touch a frozen foundation (F-01 through F-04, which remain an owner decision); it does not require changing repository governance; it is committed separately from the tranche in progress; it is recorded as a follow-up in `BUILD_STATE.open_decisions`; and the full mandatory gate set passes from the resulting state, with repeated whole-suite runs recorded as stability evidence where the failure was nondeterministic.

DEMONSTRATED means reproduced and explained, not inferred: the mechanism is exhibited on demand and the counterfactual shown. Location is not causation — where a symptom appears is not where the defect lives. Ownership is read from BUILD_PLAN; a defect in shared infrastructure owned by no block is repaired under this rule, never assigned to a block inferred from a filename or a commit-message prefix.

Widening a timeout, reordering or seeding tests, excluding a file, quarantining an example, retrying until green, or loosening an assertion are forbidden: each restores the gate and leaves the defect. If any condition fails, stop and escalate. A blocked tranche remains preferable to an unapproved change.

This is not permission to work on another tranche's backlog, nor to repair defects that are not blocking a mandatory gate.

## Decision classes

Every decision made by the controller or an invoked agent must be classified as one of:

1. Autonomous implementation decision
2. Autonomous security-preserving decision
3. Assumption permitted under delegation
4. Owner-ratified decision
5. Human decision required
6. Prohibited decision

## Autonomous decisions

The controller may proceed without human input for:

- internal naming consistent with repository conventions;
- ordinary Rails structure and conventional refactoring;
- tests required to prove approved behaviour;
- non-destructive migrations;
- indexes and constraints that preserve declared semantics;
- least-privilege permissions;
- secure defaults;
- deterministic defect correction;
- retrying transient verification failures;
- splitting oversized work into smaller reviewable tranches;
- documentation updates required by the authorised tranche;
- ordinary operational configuration already authorised by specification;
- rejecting work that violates frozen contracts;
- use of frozen foundations through their public contracts.

Every material assumption must be recorded in the Decision Ledger.

## Human decision required

The controller must stop when:

1. A frozen contract appears to require modification.
2. Authoritative specifications materially contradict each other.
3. A destructive data migration is required.
4. Tenant isolation would be weakened.
5. Security would be weakened.
6. A new external paid dependency or provider is required.
7. A legal, privacy, retention, or commercial policy must be selected.
8. Product semantics have more than one materially different valid interpretation.
9. A public API meaning would change.
10. A database invariant would change.
11. A prior owner-ratified decision would be reversed.
12. Build-plan ordering would change across domain boundaries.
13. Retry or resource limits are reached.
14. Reviewer and implementer remain in unresolved disagreement.
15. Required credentials, infrastructure, or external services are unavailable.
16. Production deployment or production data access is requested.
17. A configured cost, time, file-count, or diff-size limit is exceeded.
18. An agent attempts a prohibited operation.
19. Acceptance evidence remains insufficient despite passing tests.
20. Confidence is low and the consequences are difficult to reverse.

Human escalation must contain one precise question, a recommended option, confidence, evidence, affected contracts, available options, risks, default safe action, and consequences of deferral.

## Prohibited actions

The controller and its agents must not:

- modify product code directly on the protected branch;
- force push or rewrite Git history;
- automatically merge into the protected branch in controller version 1;
- deploy to production;
- access production credentials or production data;
- weaken authentication, authorisation, tenant isolation, encryption, audit, or retention controls;
- alter frozen foundations without explicit owner approval or a ratified Evolution Rule;
- delete or weaken tests merely to obtain a passing result;
- execute destructive recursive deletion outside the active worktree;
- inspect secret stores or print secret values;
- upload repository content to unapproved external destinations;
- perform destructive database operations outside an explicitly verified test environment;
- use unrestricted permission-bypass modes by default;
- infer owner approval from silence;
- continue after a human gate without a validated owner response;
- rewrite build state to conceal failed attempts;
- allow model prose to substitute for objective verification.

## Git policy

- Product changes occur only in isolated branches or worktrees.
- The protected branch remains untouched by product implementation.
- Force push and history rewriting are prohibited.
- Completed work may be committed automatically inside the isolated worktree.
- Merge requires a separate explicit owner-authorised process.
- Branches containing unmerged work must not be deleted automatically.
- Every commit must identify its build block and tranche.

## Filesystem policy

- Operate only within the repository and configured worktree root.
- Reject unsafe or traversal paths.
- Never delete outside the active worktree.
- Preserve append-only run records.
- Use atomic replacement for mutable state files.

## Command policy

Commands should be allowlisted where practical.

Explicitly block or gate:

- destructive recursive deletion;
- disk formatting;
- broad process termination;
- system configuration changes;
- secret-store inspection;
- arbitrary outbound upload;
- production database access;
- production migration;
- production console access;
- force push;
- protected-branch reset;
- permission-bypass modes.

## Credential and data policy

- Credentials are read only through approved environment mechanisms.
- Secrets must never be written to prompts, logs, state, or run records.
- Secret-like values must be redacted from captured output.
- Production data must never be sent to model providers.
- Development and test environments are the default.
- Unexpected network dependencies require escalation.

## Frozen foundations

F-01, F-02, F-03, and F-04 are consumed only through their frozen public contracts.

Any proposed change to a frozen foundation is a human decision unless an existing ratified Evolution Rule explicitly authorises it.

## Retry limits

Default limits are defined in the controller configuration and must persist across restarts.

A repeated failure with no materially new diagnosis must terminate rather than loop.

## Production restriction

The controller may prepare production-facing code, but it may not:

- deploy;
- run production migrations;
- access live customer data;
- activate live provider credentials;
- or perform irreversible production actions.

Those actions always require explicit human approval outside the autonomous loop.
