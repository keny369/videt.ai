# Autonomy Policy

## Purpose

This policy defines what the autonomous build controller may decide, what it must escalate, and what it must never do.

The repository, frozen contracts, Decision Ledger, architecture records, and approved build plan are authoritative. Conversational memory is not authoritative state.

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
