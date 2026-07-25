# **Autonomous Build Controller — Design and Implementation Mandate**

You are now authorised to design and implement a repository-native autonomous build controller for this application.

The purpose of the controller is to execute the remaining approved build programme with minimal human intervention while preserving the architectural discipline, evidence, testing standards, delegation boundaries and frozen contracts already established in F-01 through F-04.

This is not permission to create an uncontrolled recursive agent loop.

The controller must be:

- state-driven;
- deterministic where possible;
- bounded;
- auditable;
- resumable;
- branch-isolated;
- test-gated;
- authority-aware;
- failure-safe;
- and designed to stop only when a genuine human decision is required.

The controller must automate the governed software-delivery process, not merely automate the exchange of natural-language prompts.

------

# **1. Initial instruction**

Before modifying the repository:

1. Read the complete repository instructions and specification corpus.
2. Read all frozen foundation contracts and their freeze records.
3. Read the Decision Ledger.
4. Read the Architecture Decision Records.
5. Read the current implementation plan, dependency maps and acceptance criteria.
6. Read the F-04 completion and freeze report.
7. Inspect the current Git history and repository status.
8. Identify the canonical commands for:
   - unit tests;
   - integration tests;
   - acceptance tests;
   - database tests;
   - security scans;
   - dependency audits;
   - architecture checks;
   - formatting and linting;
   - autoloading checks;
   - and any real Redis, Sidekiq or PostgreSQL test harnesses.

Do not assume filenames or commands where the repository already defines them.

Produce a concise repository-grounded implementation plan before writing controller code.

Do not begin autonomous product implementation in this tranche.

This tranche builds and proves the controller only.

------

# **2. Core objective**

Implement a local autonomous delivery controller that can:

1. determine the next authorised build tranche;
2. create an isolated Git branch or worktree;
3. generate a scoped implementation brief from authoritative repository sources;
4. invoke a primary implementation agent;
5. run the required verification suite;
6. invoke an independent review agent;
7. classify the review findings;
8. return validated defects to the implementation agent for correction;
9. repeat within bounded retry limits;
10. commit a verified tranche;
11. update machine-readable build state;
12. update the human-readable Decision Ledger and execution record;
13. pause on defined human-decision conditions;
14. resume safely after human input;
15. never silently cross a frozen contract or authority boundary.

The controller must leave the repository in one of a small number of explicit states:

- `completed`;
- `ready_for_review`;
- `human_decision_required`;
- `blocked_external_dependency`;
- `verification_failed`;
- `retry_limit_reached`;
- `policy_violation`;
- `controller_error`.

There must be no ambiguous “still working” state after the process exits.

------

# **3. Architectural principles**

The controller must follow these principles.

## **3.1 Repository as authority**

The controller must derive work from versioned repository files, not conversational memory.

Chat sessions are not authoritative state.

The authoritative state must live in version-controlled, machine-readable files.

## **3.2 Immutable history**

Completed build attempts, decisions, verification results and escalation records must not be silently overwritten.

New attempts append new records.

Historical decisions remain inspectable.

## **3.3 Explicit authority**

Every decision must be classified as one of:

- autonomous implementation decision;
- autonomous security-preserving decision;
- assumption permitted under delegation;
- owner-ratified decision;
- human decision required;
- prohibited decision.

## **3.4 Isolation**

Each product tranche must be implemented in an isolated Git worktree or equivalent isolated branch workspace.

The controller must not make product changes directly on the protected branch.

## **3.5 No uncontrolled recursion**

Every agent invocation must have:

- a declared role;
- a scoped task;
- allowed tools;
- prohibited actions;
- expected structured output;
- a turn limit;
- a timeout;
- a cost or invocation limit where supported;
- and a defined success or failure result.

## **3.6 Independent review**

The implementation agent must not be the sole authority on whether its own work is complete.

A separate review pass must inspect the complete diff, relevant architecture, tests and acceptance criteria.

The reviewer must not edit the implementation branch unless operating in a separately authorised repair role.

## **3.7 Verification over confidence**

Model confidence is not acceptance evidence.

The controller may mark work complete only when objective repository-defined checks pass.

## **3.8 No silent scope expansion**

The controller must not implement a downstream domain merely to make an upstream tranche convenient.

Dependencies must be respected.

## **3.9 Frozen foundations are consumed, not modified**

F-01, F-02, F-03 and F-04 must be consumed only through their frozen public contracts.

Any required modification to a frozen foundation is a mandatory human escalation unless an already-ratified Evolution Rule explicitly permits the change.

------

# **4. Required repository artefacts**

Inspect existing files first and reuse or extend them where appropriate.

Do not create duplicate sources of authority.

At minimum, the controller needs repository-native equivalents of the following.

## **4.1** **`AUTONOMY_POLICY.md`**

Human-readable policy defining:

- what agents may decide;
- what they must escalate;
- prohibited actions;
- frozen-contract rules;
- production access restrictions;
- destructive-operation restrictions;
- credential rules;
- network access rules;
- retry and resource limits;
- branch and merge permissions;
- and human-resumption procedure.

## **4.2** **`BUILD_PLAN.yml`**

Machine-readable dependency graph of remaining work.

Each block should support fields equivalent to:

```yaml
id:
name:
type:
status:
depends_on:
authoritative_sources:
scope:
out_of_scope:
acceptance_criteria:
required_verification:
human_gate_before:
human_gate_after:
risk_level:
allowed_foundation_dependencies:
expected_outputs:
```

Do not populate the complete future plan by guessing.

Derive the initial plan from authoritative specifications and mark uncertain blocks as requiring architecture review.

## **4.3** **`BUILD_STATE.json`**

Machine-readable current state.

It should support fields equivalent to:

```json
{
  "schema_version": 1,
  "controller_version": "",
  "current_block": "",
  "current_tranche": "",
  "status": "",
  "attempt_number": 0,
  "base_commit": "",
  "worktree_path": "",
  "branch_name": "",
  "implementation_commit": null,
  "review_commit": null,
  "last_verified_commit": "",
  "verification_run_id": "",
  "open_decisions": [],
  "completed_blocks": [],
  "failed_attempts": [],
  "updated_at": ""
}
```

All state changes must be validated before writing.

Use atomic file replacement or an equivalent crash-safe mechanism.

## **4.4** **`DECISION_LEDGER.md`**

Preserve the existing ledger if already present.

The controller must append structured records containing:

- decision identifier;
- block and tranche;
- decision;
- authority;
- alternatives considered;
- rationale;
- evidence;
- affected contracts;
- reversibility;
- timestamp;
- commit;
- and whether owner ratification is required.

## **4.5 Machine-readable execution records**

Create an append-only execution-record location, such as:

```text
automation/runs/<run-id>/
```

Each run should retain:

- input task;
- source commit;
- generated implementation brief;
- agent outputs;
- verification commands;
- verification results;
- review findings;
- repair attempts;
- policy decisions;
- final status;
- resource usage if available;
- and resulting commit identifiers.

Do not store secrets, API keys, restricted payloads or full private credentials in these records.

## **4.6 JSON schemas**

Define and validate structured schemas for:

- build state;
- agent implementation result;
- independent review result;
- verification result;
- human escalation;
- repair result;
- and tranche completion report.

Reject malformed agent output rather than attempting to interpret it loosely.

## **4.7 Controller commands**

Provide clear commands equivalent to:

```text
bin/autonomous-build plan
bin/autonomous-build status
bin/autonomous-build run-next
bin/autonomous-build resume
bin/autonomous-build verify
bin/autonomous-build review
bin/autonomous-build abort
```

Use the repository’s established language and tooling conventions.

Do not introduce a new runtime unnecessarily.

------

# **5. Agent roles**

The controller must use fixed roles.

## **5.1 Planner**

The planner:

- reads the current build block;
- reads authoritative sources;
- identifies dependencies;
- produces the smallest reviewable tranche;
- specifies in-scope and out-of-scope work;
- lists acceptance criteria;
- lists required tests;
- identifies protected contracts;
- and identifies possible escalation conditions.

The planner does not modify product code.

## **5.2 Implementer**

The implementer:

- works only within the current isolated worktree;
- implements only the authorised tranche;
- runs targeted tests while developing;
- records assumptions;
- does not weaken tests;
- does not modify frozen contracts;
- and returns structured completion output.

## **5.3 Verifier**

The verifier is primarily deterministic tooling, not model opinion.

It runs the required commands and returns:

- command;
- exit status;
- duration;
- relevant output location;
- failures;
- warnings;
- and whether the complete required verification set passed.

## **5.4 Independent reviewer**

The reviewer:

- reads the implementation brief;
- reads the complete diff;
- inspects affected surrounding code;
- checks architectural boundaries;
- checks frozen-contract consumption;
- checks tenancy and authorisation;
- checks data integrity;
- checks concurrency and idempotency where relevant;
- checks tests for false assurance;
- runs additional targeted tests where permitted;
- and returns structured findings.

The reviewer must classify every finding as:

- `critical`;
- `high`;
- `medium`;
- `low`;
- `observation`;
- or `false_positive`.

Every defect finding must include:

- exact location;
- violated requirement;
- concrete failure mode;
- supporting evidence;
- recommended correction;
- and whether it blocks completion.

## **5.5 Repair agent**

The repair agent receives only:

- the approved implementation brief;
- verified blocking review findings;
- relevant failed verification output;
- and current diff context.

It must not reinterpret the entire product scope unless a finding demonstrates that the original plan was invalid.

------

# **6. Model arrangement**

Use Claude Code as the initial primary implementer unless the local environment or owner configuration states otherwise.

Support an independent reviewer through one of:

1. OpenAI Codex CLI or API;
2. a second independently invoked Claude session with a reviewer-only prompt and no shared conversational state;
3. another configured reviewer adapter.

The controller architecture must not be hard-coded to a single provider.

Define an adapter interface for:

- planner;
- implementer;
- reviewer;
- and repair agent.

Provider-specific command construction must remain behind those adapters.

No provider may receive unrestricted credentials by default.

No provider may be allowed to deploy to production.

Do not require the OpenAI reviewer to be active in the first controller test if credentials are unavailable.

Provide a deterministic local reviewer stub or same-provider independent-review mode for proving orchestration.

Clearly distinguish:

- controller readiness;
- same-provider review;
- and true cross-provider review.

------

# **7. Autonomous authority rules**

The controller may proceed without human input for:

- internal naming consistent with repository conventions;
- ordinary Rails structure;
- test additions;
- non-destructive migrations;
- indexes and constraints that preserve declared semantics;
- least-privilege permissions;
- secure defaults;
- refactoring required solely to complete the authorised tranche;
- deterministic defect correction;
- retrying transient verification failures;
- splitting oversized work into smaller tranches;
- rejecting work that violates frozen contracts;
- documentation updates required by the completed tranche;
- and conventional operational configuration already authorised by the specification.

The controller must stop for human input when any of the following occurs:

1. A frozen contract appears to require modification.
2. Two authoritative specifications materially contradict each other.
3. A destructive data migration is required.
4. Tenant isolation would be weakened.
5. Security would be weakened.
6. A new external paid dependency or provider is required.
7. A legal, privacy, retention or commercial policy must be chosen.
8. Product semantics have more than one materially different valid interpretation.
9. A public API meaning would change.
10. A database invariant would change.
11. A previously owner-ratified decision would be reversed.
12. The build plan would need material reordering across domain boundaries.
13. The controller reaches its retry limit.
14. Independent reviewer and implementer remain in unresolved disagreement.
15. Required credentials, external services or infrastructure are unavailable.
16. Production deployment is requested.
17. The work exceeds configured cost, time, file-count or diff-size limits.
18. The agent attempts a prohibited operation.
19. Acceptance evidence is insufficient despite apparently passing tests.
20. Confidence is low and the consequences are difficult to reverse.

Human escalations must contain:

- one precise question;
- the recommended decision;
- confidence level;
- relevant evidence;
- affected contracts;
- available options;
- advantages and risks of each;
- default safe action;
- and consequences of deferring the decision.

Do not ask the owner to decide ordinary implementation details.

------

# **8. Safety and operational boundaries**

The first version of the controller must obey all of the following.

## **8.1 Git**

- No direct product-code changes on the protected branch.
- No force push.
- No history rewriting.
- No automatic deletion of branches containing unmerged work.
- No automatic merge to the protected branch in version one.
- Automatic commits within the isolated worktree are permitted.
- Every commit must identify the build block and tranche.
- The controller must confirm a clean base state before starting.

## **8.2 Filesystem**

- Operate only within the repository and designated worktree root.
- Refuse unsafe paths.
- Prevent path traversal.
- Do not delete files outside the active worktree.
- Preserve run records.

## **8.3 Commands**

Use an allowlist where practical.

At minimum, prohibit or explicitly gate:

- destructive recursive deletion;
- disk formatting;
- broad process termination;
- system configuration changes;
- secret-store inspection;
- arbitrary outbound uploads;
- database destruction;
- production migration;
- production console access;
- force push;
- protected-branch resets;
- and permission-bypass modes.

Do not use unrestricted permission-bypass flags as the default operating mode.

## **8.4 Credentials**

- Read credentials only through existing approved environment mechanisms.
- Never write credentials to prompts, logs or execution records.
- Redact secrets from captured command output.
- Do not send production data to external model providers.
- Use development and test environments only.

## **8.5 Database**

- No production connection.
- No destructive database operation without an explicit test-environment check.
- Migrations must be inspected and tested.
- Tenant row-level-security checks remain mandatory where relevant.
- Database grants and triggers must be included in verification when changed.

## **8.6 Network**

- Default to no network access except approved model APIs, dependency registries and explicitly authorised development services.
- Record which external endpoints are required.
- Stop on an unexpected network dependency.

------

# **9. Worktree lifecycle**

For each tranche:

1. Confirm protected branch and base commit.
2. Confirm clean working state.
3. Create a unique branch.
4. Create a unique isolated worktree.
5. Write run metadata.
6. Generate the implementation brief.
7. Invoke the implementer.
8. Run targeted verification.
9. Run full required verification.
10. Commit only when implementation verification passes.
11. Invoke independent review against the committed diff.
12. Classify findings.
13. Repair verified blocking defects.
14. Rerun all affected verification.
15. Repeat review if the diff materially changes.
16. Produce final tranche report.
17. Mark `ready_for_review`.
18. Stop before merge.

The first controller version must not automatically merge.

------

# **10. Verification policy**

The controller must discover repository-defined verification requirements and encode them centrally.

The verification manifest must support:

- always-required checks;
- checks selected by changed path;
- checks selected by architectural area;
- checks selected by database changes;
- checks selected by security-sensitive changes;
- checks selected by background-job changes;
- and complete release-gate checks.

A successful targeted suite is not sufficient if the tranche requires full verification.

At minimum, preserve the current standard represented by the completed foundations, including the repository equivalents of:

- complete automated test suite;
- Brakeman;
- Packwerk;
- bundler-audit;
- Zeitwerk;
- database permission checks;
- row-level-security checks;
- and any foundation-specific fitness suites.

The controller must not:

- remove a failing test to obtain green status;
- reduce test coverage without recorded justification;
- convert a meaningful assertion into a weak existence check;
- mark a flaky failure as transient without evidence;
- or accept skipped security checks silently.

------

# **11. Retry and loop limits**

Set explicit configurable defaults.

Suggested initial limits:

- planner attempts per tranche: 2;
- implementation attempts per tranche: 3;
- repair cycles per tranche: 3;
- independent review cycles: 2;
- repeated identical verification failure: 2;
- maximum agent invocations per tranche: 10;
- maximum changed files before escalation: 40;
- maximum diff size before forced tranche split: choose a repository-appropriate value;
- maximum wall-clock execution per controller run: configurable;
- maximum model spend per tranche: configurable when provider usage is measurable.

A repeated failure with no materially new diagnosis must stop rather than loop.

Persist attempt counts across process restarts.

------

# **12. Crash safety and resumption**

The controller must be safely resumable after:

- process termination;
- machine restart;
- model timeout;
- test timeout;
- malformed model output;
- partial state-file write;
- Git command failure;
- and reviewer failure.

On startup, reconcile:

- machine-readable state;
- worktree existence;
- branch existence;
- Git commits;
- run records;
- and active process locks.

Use a controller lock so two autonomous runs cannot operate on the same build state simultaneously.

Do not assume that a model invocation failed merely because its response was not captured.

Where completion is ambiguous, inspect the worktree and Git state before retrying.

------

# **13. Structured agent outputs**

All model-facing prompts must require structured JSON conforming to versioned schemas.

Human-readable reports may be generated from those records, but machine control must not depend on free-form prose.

The implementation result should include fields equivalent to:

```json
{
  "status": "completed",
  "summary": "",
  "files_changed": [],
  "migrations_added": [],
  "tests_added": [],
  "commands_run": [],
  "assumptions": [],
  "decisions": [],
  "possible_escalations": [],
  "known_limitations": [],
  "recommended_next_action": ""
}
```

The review result should include fields equivalent to:

```json
{
  "status": "pass",
  "reviewed_commit": "",
  "blocking_findings": [],
  "non_blocking_findings": [],
  "architecture_assessment": "",
  "security_assessment": "",
  "test_assessment": "",
  "recommended_action": ""
}
```

The controller must verify that:

- the reviewed commit matches the actual implementation commit;
- files claimed as changed match Git;
- tests claimed as run are supported by captured execution evidence;
- and no agent can mark its own unverified statements as objective verification.

------

# **14. Human decision workflow**

When a human decision is required:

1. Set state to `human_decision_required`.
2. Write a decision request file.
3. Print a concise terminal summary.
4. Exit with a distinct non-zero or documented decision-required exit code.
5. Do not continue automatically.
6. Preserve the worktree exactly.
7. Provide a resume command.
8. Validate the owner’s response before resuming.
9. Append the ratified decision to the Decision Ledger.
10. Regenerate the affected implementation brief if necessary.

Support a response format equivalent to:

```yaml
decision_id: HD-001
selected_option: A
owner_instruction: ""
ratified_at: ""
```

Do not infer owner approval from silence.

------

# **15. Controller implementation quality**

Treat the controller as production-quality internal engineering infrastructure.

It must have:

- unit tests;
- integration tests;
- schema-validation tests;
- state-transition tests;
- policy tests;
- command-construction tests;
- malformed-agent-output tests;
- retry-limit tests;
- crash-recovery tests;
- concurrent-controller lock tests;
- Git worktree lifecycle tests;
- secret-redaction tests;
- escalation tests;
- and end-to-end dry-run coverage.

Use dependency injection or equivalent seams so model providers, Git, process execution and clocks can be tested without real external calls.

Do not make tests depend on paid model invocations.

Provide fake provider adapters for deterministic controller testing.

------

# **16. Required end-to-end proof**

Before declaring the controller complete, prove the following with a synthetic, non-product tranche.

The synthetic tranche should:

1. create an isolated worktree;
2. receive a small harmless task;
3. invoke the fake or test implementer;
4. intentionally fail one verification check;
5. trigger a bounded repair cycle;
6. pass verification;
7. invoke the independent-review adapter;
8. produce one non-blocking observation;
9. commit the work;
10. update build state;
11. produce a completion report;
12. stop at `ready_for_review`;
13. leave the protected branch untouched.

Also prove:

- malformed model JSON is rejected;
- a prohibited command is blocked;
- a frozen-contract modification triggers escalation;
- duplicate controller execution is locked out;
- an interrupted run resumes safely;
- retry exhaustion stops;
- an unavailable reviewer produces a controlled blocked state;
- and secrets are redacted from logs.

Do not use S-05 as the controller’s first implementation test.

Use a harmless controller fixture or synthetic repository task.

------

# **17. First real pilot after controller completion**

After the controller itself is complete and verified:

1. Stop.
2. Present the controller tranche report.
3. Present the proposed initial machine-readable build graph.
4. Identify uncertain or human-gated blocks.
5. Recommend one narrowly scoped S-05 pilot tranche.
6. Explain exactly what the controller would do.
7. Explain exactly what it would not do.
8. Wait for owner approval before running the first real autonomous product tranche.

The first real pilot should:

- be small;
- avoid frozen-foundation changes;
- avoid destructive migrations;
- have clear acceptance criteria;
- exercise normal domain implementation;
- and stop before merge.

------

# **18. Deliverables**

Complete this controller tranche in reviewable commits.

The final report must include:

## **Commit tranche**

For each commit:

- commit identifier;
- purpose;
- guarantees introduced;
- files added or changed.

## **Controller architecture**

Explain in plain language:

- how work is selected;
- how agents are invoked;
- how state is persisted;
- how verification works;
- how review works;
- how repair loops work;
- how escalation works;
- and how resumption works.

## **Authority model**

List:

- autonomous decisions;
- escalation decisions;
- prohibited actions;
- and merge/deployment restrictions.

## **Verification**

Provide exact results for:

- controller unit tests;
- integration tests;
- end-to-end synthetic test;
- security checks;
- repository-wide checks;
- malformed-output tests;
- policy tests;
- crash-recovery tests;
- and concurrency-lock tests.

## **Schemas and state transitions**

List all machine-readable schemas and valid state transitions.

## **Provider support**

State:

- which implementer adapter is active;
- which reviewer adapter is active;
- which adapters are stubs;
- required environment variables;
- and what happens when a provider is unavailable.

Do not expose secret values.

## **Decision Ledger**

Record every autonomous assumption and any repository-level decision introduced by the controller.

## **Remaining risks**

Be explicit about:

- false confidence;
- agent collusion or correlated failure;
- review limitations;
- model-provider outages;
- runaway cost;
- large-diff risk;
- local-machine risk;
- and areas still requiring human judgement.

## **Operating instructions**

Provide the exact commands to:

- inspect status;
- plan the next tranche;
- run a synthetic test;
- run the next real tranche;
- stop safely;
- resume;
- inspect run records;
- answer a human decision;
- and clean up completed worktrees safely.

## **Proposed next step**

Provide the exact proposed S-05 pilot tranche, but do not execute it.

------

# **19. Completion standard**

The autonomous controller is not complete merely because it can call Claude Code in a loop.

It is complete only when:

- work is derived from authoritative repository state;
- every invocation is bounded;
- every state transition is explicit;
- every completion claim is independently verified;
- every tranche is isolated;
- every decision is attributable;
- every failure is recoverable or terminal;
- frozen contracts are protected;
- human escalation is precise;
- the protected branch remains untouched;
- and the synthetic end-to-end proof passes.

Proceed autonomously through design, implementation, testing, review, correction and controller freeze.

Make highest-probability, best-practice implementation decisions under the existing delegation.

Stop only for a genuine Level-3 condition, an unresolved contradiction in authoritative sources, a required destructive operation, a security compromise, or an unavailable external dependency that prevents the controller itself from being proven locally.