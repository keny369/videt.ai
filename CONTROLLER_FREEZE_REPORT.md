# Autonomous Build Controller (CTRL-01) — Completion Report

Status: **ready_for_review** (2026-07-25). The controller tranche is implemented, self-proven and
repository-verified; it is **not merged** and **no product tranche (S-05) has been run**. Built to
`specification/automation/AUTONOMOUS_BUILD_CONTROLLER.md` after reconciling that corpus against the
repository (`specification/automation/RECONCILIATION.md`). Consumed F-01..F-04 only through their
frozen contracts.

## Commit tranche

| Commit | Purpose |
| --- | --- |
| CTRL-01 (1/n) | Reconcile automation docs: resolve every `TO_BE_DISCOVERED`, fix `match_paths`, correct `BUILD_STATE`/`BUILD_PLAN` post-F-04 |
| CTRL-01 (2/n) | Foundation: state machine (8 terminal states, closed transitions), atomic `BUILD_STATE`, safe paths |
| CTRL-01 (3/n) | Fail-closed boundaries: schema validation, secret redaction, command policy |
| CTRL-01 (4/n) | Bounded command runner, deterministic verifier, provider-neutral adapters |
| CTRL-01 (5/n) | Git worktree lifecycle, single-run lock, append-only run records |
| CTRL-01 (6/n) | Orchestration core + the synthetic end-to-end proof + 8 safety proofs |
| CTRL-01 (7/n) | CLI `bin/autonomous-build` + next-block planner + live self-proof |
| CTRL-01 (8/n) | Brakeman-clean fix, this report, and the proposed (unexecuted) S-05 pilot |

## Controller architecture (plain language)

- **Work is selected** from versioned files only (`BUILD_PLAN.yml` + `BUILD_STATE.json`), never from a
  chat transcript. `Plan#next_block` returns the first block whose dependencies are all complete/frozen;
  a human-gated block is reported, not run.
- **Agents are invoked** through a provider-neutral adapter interface (planner / implementer / reviewer /
  repair). Every invocation is bounded (turn/invocation budget) and MUST return JSON that passes the
  role's schema — malformed output is rejected, never interpreted.
- **State is persisted** atomically (temp + fsync + rename), validated before every write, with
  `completed_blocks`/`failed_attempts` append-only. The run walks an explicit state machine and always
  exits in exactly one terminal state.
- **Verification** is deterministic tooling over the reconciled manifest: it runs the always-required
  checks plus the sets selected by the changed paths, and a `pass` is invalid if any mandatory check is
  missing. Model confidence is never acceptance evidence.
- **Review** runs against the committed diff via a separate reviewer adapter; the controller confirms
  `reviewed_commit` equals the implementation commit. The default `LocalReviewer` is a deterministic
  stub that explicitly flags it is not a true cross-provider review.
- **Repair loops** are bounded (repair cycles, repeated-identical-failure); a repair re-enters
  verification and produces new commits; exhaustion stops rather than looping.
- **Escalation** is precise and fail-safe: a frozen-contract change, a diff-size breach, an agent
  human-decision status, or an unresolved condition sets `human_decision_required`, writes a decision
  request, preserves the worktree, and stops. Silence is never approval.
- **Resumption**: the lock releases on death; the worktree and `BUILD_STATE` are preserved on any
  non-completed terminal, so a re-run reconciles state and continues.

## Authority model

- **Autonomous**: internal naming, ordinary Rails structure, tests, non-destructive migrations,
  least-privilege permissions/secure defaults, deterministic defect repair, transient-failure retries,
  tranche splitting, documentation, rejecting frozen-contract violations (AUTONOMY_POLICY).
- **Escalation (human_decision_required)**: frozen-contract change, contradictory specs, destructive
  migration, weakened tenancy/security, new paid dependency, ambiguous product semantics, API/DB
  invariant change, reversing a ratified decision, cross-domain reordering, limit breaches, reviewer
  deadlock, unavailable infra, production/data access, prohibited operation, insufficient evidence.
- **Prohibited**: direct product changes on the protected branch, force push / history rewrite,
  automatic merge, production deploy/data/credentials, weakening security/tenant/encryption/audit,
  frozen-foundation edits, test deletion for green, destructive deletion outside the worktree, secret
  inspection, permission-bypass modes, inferring approval from silence.
- **Merge/deploy**: **no automatic merge and no production path in v1** — `merge_authorised` is always false.

## Verification (exact results)

- Controller suite (`spec/automation`): **64 examples, 0 failures** (unit, policy, integration,
  end-to-end). Whole repository: **1037 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses;
  Brakeman 0 warnings; bundler-audit no vulnerabilities.
- Synthetic end-to-end proof passes: worktree → implement → **intentionally fail one check** → repair →
  pass → independent review (one non-blocking observation) → commit → `ready_for_review`, **protected
  branch untouched**. Safety proofs pass: malformed JSON rejected, prohibited command blocked,
  frozen-contract change escalates, duplicate run locked out, retry exhaustion stops with the worktree
  preserved, unavailable reviewer → blocked, secrets redacted. Live: `bin/autonomous-build selftest` →
  `SELFTEST PASS`.

## Schemas and state transitions

- Schemas (versioned, fail-closed): planner, implementer, verifier, reviewer, repair, escalation,
  completion — plus the reviewer finding vocabulary.
- States: working `idle, planning, implementing, verifying, committing, reviewing, repairing, reporting`;
  terminal `completed, ready_for_review, human_decision_required, blocked_external_dependency,
  verification_failed, retry_limit_reached, policy_violation, controller_error`. Transitions are the
  closed table in `state_machine.rb` (commit before review; failed verify → repair; terminal states
  never transition).

## Provider support

- **Implementer**: `Adapters::ClaudeCodeImplementer` (real; headless `claude -p … --output-format json`,
  no permission-bypass flag). Env: `F1_CONTROLLER_IMPLEMENTER_MODEL` (optional). Unavailable when the
  `claude` CLI is not on `PATH` → `available?` false → the controller reports a blocked state rather than proceeding.
- **Reviewer**: `Adapters::LocalReviewer` (deterministic same-process stub; §6). A true cross-provider
  reviewer (e.g. an OpenAI/Codex adapter) is a configurable adapter and is **not active by default**; no
  OpenAI credentials are assumed. The stub always records that it is not cross-provider review.
- **Testing**: `Adapters::Fake` deterministic adapters; no test depends on a paid model invocation.

## Decision Ledger (controller-introduced autonomous decisions)

- Controller lives in `automation/` (outside the Rails app, so it is not in the product Packwerk graph
  or Zeitwerk autoload) with CLI `bin/autonomous-build` and specs `spec/automation`. Ruby + RSpec, per
  repository convention; no new runtime. **Authority: autonomous (structure).**
- `max_model_spend_usd_per_tranche` left null (spend not machine-measurable locally); cost is bounded by
  invocation/turn/time limits instead. **Authority: assumption.**
- Verification manifest placeholders resolved / consolidated onto real commands, recorded in
  `RECONCILIATION.md` (no `strong_migrations`; DB permissions/RLS/tenant = `f1:db:verify_runtime`).
  **Authority: autonomous (defect/reconciliation).**

## Remaining risks

- **Same-provider review is not independent enough**: the default reviewer is a deterministic stub; true
  correlated-failure protection needs a cross-provider adapter before trusting autonomous product work.
- **Local-machine + provider outage**: the controller runs locally; a `claude` outage blocks
  implementation (surfaced as a blocked state, not a silent stall).
- **Large-diff / false confidence**: bounded by the diff-size/file-count escalation and by the verifier
  being authoritative, but a subtle logic defect can still pass automated checks — human review before
  merge remains mandatory.
- **No cost metering**: guarded by invocation/time limits, not dollars.

## Operating instructions

```
bin/autonomous-build status     # build state + next authorised block
bin/autonomous-build plan       # inspect the next block (and any human gate)
bin/autonomous-build selftest   # run the synthetic proof (no product change)
bin/autonomous-build verify     # run the always-required checks on the current repo
bin/autonomous-build run-next   # refuses a human-gated tranche; no autonomous product run in v1
bin/autonomous-build resume --decision HD-xxx --option A
bin/autonomous-build abort      # release a stale lock (worktrees preserved)
```
Run records: `automation/runs/<run-id>/` (append-only, redacted). Worktrees are preserved on any
non-completed terminal; remove them explicitly after review.

## Completion standard (§19) — met

Work derives from authoritative repository state; every invocation is bounded; every state transition is
explicit; every completion claim is independently verified; every tranche is isolated; every decision is
attributable; every failure is recoverable or terminal; frozen contracts are protected; human escalation
is precise; the protected branch remains untouched; the synthetic end-to-end proof passes.

## Proposed next step — first S-05 pilot tranche (NOT AUTHORISED, NOT EXECUTED)

Presented for owner approval only; the controller has not run it.

- **Block**: S-05 Ownership Verification (WF-003), first limb.
- **Proposed pilot tranche `S-05-001` — `IssueVerificationChallenge`**: create a `VerificationRequest`
  aggregate and issue one challenge, storing the challenge material behind **F-02** (`Platform::Encryption`)
  and scheduling the 24-hour `verification_request_expire` via **F-04** (`Platform::BackgroundExecution`
  / the ScheduledAction catalogue). No outbound observation (that is the later `verification_observe`
  limb via **F-01**), no scoring/evaluation (CAP-013/S-09), no frozen-foundation change, no destructive migration.
- **Acceptance**: an authorized actor issues a challenge for a verified-eligible Source; the request +
  encrypted challenge + scheduled expiry persist; the WF-003 command vocabulary
  (`IssueVerificationChallenge`, per APPLICATION_LAYER / ADR-024 DEF-1) is honored; full suite + DB/RLS +
  architecture fitness green.
- **What the controller would do**: isolate a worktree, generate the brief from `contracts/S-05.json` +
  `APPLICATION_LAYER` + `SCORE_EVIDENCE_MODEL.md`, implement only this limb, verify (full suite + DB
  permissions/RLS + background-execution checks), independently review the committed diff, and stop at
  `ready_for_review`. **What it would not do**: touch F-01..F-04, run an outbound observation, evaluate
  evidence, migrate destructively, merge, or deploy.

**This is a proposal. Approve it (and, per the escalation policy, the controller-completion and
first-pilot architecture-review gates) before any autonomous product tranche runs.**
