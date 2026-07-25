# Agent Output Schemas

## Purpose

All model-facing roles must return structured JSON conforming to versioned schemas.

Machine control must never depend on free-form prose. Human-readable summaries may be generated from validated records.

The controller must reject malformed or schema-incompatible output.

---

## Common rules

Every output object must include:

- `schema_version`
- `role`
- `run_id`
- `block_id`
- `tranche_id`
- `status`
- `generated_at`

Timestamps use ISO 8601 UTC.

Unknown top-level fields should be rejected unless the schema explicitly permits them.

No schema may contain secrets, API keys, production data, or restricted payloads.

---

## Planner result

```json
{
  "schema_version": 1,
  "role": "planner",
  "run_id": "RUN-...",
  "block_id": "S-05",
  "tranche_id": "S-05-001",
  "status": "planned",
  "generated_at": "2026-01-01T00:00:00Z",
  "summary": "",
  "authoritative_sources": [],
  "dependencies": [],
  "scope": [],
  "out_of_scope": [],
  "acceptance_criteria": [],
  "required_verification": [],
  "protected_contracts": [],
  "assumptions": [],
  "possible_escalations": [],
  "recommended_action": "implement"
}
```

Allowed statuses:

- `planned`
- `human_decision_required`
- `blocked_external_dependency`
- `invalid_plan`

---

## Implementation result

```json
{
  "schema_version": 1,
  "role": "implementer",
  "run_id": "RUN-...",
  "block_id": "S-05",
  "tranche_id": "S-05-001",
  "status": "completed",
  "generated_at": "2026-01-01T00:00:00Z",
  "summary": "",
  "files_changed": [],
  "migrations_added": [],
  "tests_added": [],
  "commands_run": [],
  "assumptions": [],
  "decisions": [],
  "possible_escalations": [],
  "known_limitations": [],
  "recommended_next_action": "verify"
}
```

Allowed statuses:

- `completed`
- `partial`
- `human_decision_required`
- `blocked_external_dependency`
- `policy_violation`
- `failed`

The controller must independently verify:

- claimed files against Git;
- claimed commands against captured command records;
- claimed tests against verifier evidence;
- claimed commits against the actual repository state.

---

## Verification result

```json
{
  "schema_version": 1,
  "role": "verifier",
  "run_id": "RUN-...",
  "block_id": "S-05",
  "tranche_id": "S-05-001",
  "status": "pass",
  "generated_at": "2026-01-01T00:00:00Z",
  "verified_commit": "",
  "checks": [
    {
      "id": "test_suite",
      "command": "",
      "exit_status": 0,
      "duration_seconds": 0,
      "output_path": "",
      "warnings": [],
      "failures": []
    }
  ],
  "required_checks": [],
  "missing_checks": [],
  "summary": ""
}
```

Allowed statuses:

- `pass`
- `fail`
- `incomplete`
- `controller_error`

A `pass` is invalid if any required check is missing.

---

## Review result

```json
{
  "schema_version": 1,
  "role": "reviewer",
  "run_id": "RUN-...",
  "block_id": "S-05",
  "tranche_id": "S-05-001",
  "status": "pass",
  "generated_at": "2026-01-01T00:00:00Z",
  "reviewed_commit": "",
  "blocking_findings": [],
  "non_blocking_findings": [],
  "architecture_assessment": "",
  "security_assessment": "",
  "test_assessment": "",
  "recommended_action": "ready_for_review"
}
```

Each finding must conform to:

```json
{
  "finding_id": "FIND-...",
  "severity": "high",
  "classification": "defect",
  "location": "",
  "violated_requirement": "",
  "failure_mode": "",
  "evidence": [],
  "recommended_correction": "",
  "blocks_completion": true
}
```

Severity:

- `critical`
- `high`
- `medium`
- `low`
- `observation`

Classification:

- `defect`
- `risk`
- `observation`
- `false_positive`

Allowed review statuses:

- `pass`
- `pass_with_observations`
- `changes_required`
- `human_decision_required`
- `blocked_external_dependency`
- `review_error`

The controller must verify that `reviewed_commit` equals the actual implementation commit.

---

## Repair result

```json
{
  "schema_version": 1,
  "role": "repair",
  "run_id": "RUN-...",
  "block_id": "S-05",
  "tranche_id": "S-05-001",
  "status": "completed",
  "generated_at": "2026-01-01T00:00:00Z",
  "addressed_findings": [],
  "unresolved_findings": [],
  "files_changed": [],
  "commands_run": [],
  "assumptions": [],
  "recommended_next_action": "verify"
}
```

Allowed statuses:

- `completed`
- `partial`
- `human_decision_required`
- `blocked_external_dependency`
- `failed`

---

## Human escalation

```json
{
  "schema_version": 1,
  "role": "controller",
  "run_id": "RUN-...",
  "block_id": "S-05",
  "tranche_id": "S-05-001",
  "status": "human_decision_required",
  "generated_at": "2026-01-01T00:00:00Z",
  "decision_id": "HD-001",
  "question": "",
  "recommended_option": "A",
  "confidence": 0.85,
  "evidence": [],
  "affected_contracts": [],
  "options": [
    {
      "id": "A",
      "summary": "",
      "benefits": [],
      "risks": []
    }
  ],
  "default_safe_action": "",
  "consequence_of_deferral": ""
}
```

Confidence is a number from 0 to 1.

A human escalation must contain one precise decision question.

---

## Tranche completion report

```json
{
  "schema_version": 1,
  "role": "controller",
  "run_id": "RUN-...",
  "block_id": "S-05",
  "tranche_id": "S-05-001",
  "status": "ready_for_review",
  "generated_at": "2026-01-01T00:00:00Z",
  "base_commit": "",
  "implementation_commit": "",
  "reviewed_commit": "",
  "branch_name": "",
  "worktree_path": "",
  "summary": "",
  "guarantees_established": [],
  "verification_run_id": "",
  "verification_status": "pass",
  "review_status": "pass",
  "decisions_recorded": [],
  "remaining_risks": [],
  "known_limitations": [],
  "merge_authorised": false
}
```

Allowed terminal statuses:

- `ready_for_review`
- `human_decision_required`
- `blocked_external_dependency`
- `verification_failed`
- `retry_limit_reached`
- `policy_violation`
- `controller_error`

---

## Owner decision response

```yaml
schema_version: 1
decision_id: HD-001
selected_option: A
owner_instruction: ""
ratified_at: "2026-01-01T00:00:00Z"
```

The controller must validate the decision identifier and selected option before resuming.

Silence is never approval.
