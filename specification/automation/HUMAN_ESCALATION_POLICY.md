# Human Escalation Policy

## Purpose

The autonomous controller should make ordinary implementation decisions and stop only when a genuine owner decision is required.

Escalations must be precise, evidence-based, and easy to answer.

## Mandatory escalation conditions

Escalate when:

- a frozen contract appears to require modification;
- authoritative sources materially contradict each other;
- a destructive migration is required;
- security or tenant isolation would be weakened;
- a new paid external dependency is required;
- legal, privacy, retention, pricing, or commercial policy must be chosen;
- product semantics have multiple materially different valid interpretations;
- a public API or database invariant would change;
- a prior owner-ratified decision would be reversed;
- domain build order would materially change;
- retry, time, cost, file-count, or diff-size limits are reached;
- reviewer and implementer remain in unresolved disagreement;
- credentials, infrastructure, or external services are unavailable;
- production access, deployment, or production data is required;
- an agent attempts a prohibited operation;
- objective acceptance evidence remains insufficient;
- the safe option is unclear and the consequences are difficult to reverse.

## What must not be escalated

Do not ask the owner to decide:

- internal class or method names;
- conventional Rails structure;
- ordinary test organization;
- non-destructive implementation detail;
- standard security-preserving defaults;
- routine defect repair;
- ordinary refactoring within the approved tranche;
- whether to rerun a transiently failed deterministic check;
- how to split an oversized tranche when product semantics are unchanged.

## Escalation format

Each escalation must include:

1. Decision identifier
2. One precise question
3. Recommended option
4. Confidence from 0 to 1
5. Relevant evidence
6. Affected contracts
7. Available options
8. Benefits and risks for each option
9. Default safe action
10. Consequence of deferral
11. Current branch and worktree
12. Resume command

Example:

```json
{
  "schema_version": 1,
  "status": "human_decision_required",
  "decision_id": "HD-017",
  "question": "Should a failed re-observation create a new scheduled action rather than reopen the existing immutable action?",
  "recommended_option": "A",
  "confidence": 0.86,
  "evidence": [
    "F-04 requires immutable execution history",
    "Reopening would alter completed action semantics"
  ],
  "affected_contracts": ["F-04 ScheduledAction"],
  "options": [
    {
      "id": "A",
      "summary": "Create a new scheduled action",
      "benefits": ["Preserves history", "Maintains immutability"],
      "risks": ["Creates an additional record"]
    },
    {
      "id": "B",
      "summary": "Reopen the existing action",
      "benefits": ["Fewer records"],
      "risks": ["Weakens immutable history"]
    }
  ],
  "default_safe_action": "Pause without changing data",
  "consequence_of_deferral": "The tranche remains blocked but no state is lost",
  "resume_command": "bin/autonomous-build resume --decision HD-017"
}
```

## State transition

When escalating:

1. Persist state as `human_decision_required`.
2. Write a decision request to the append-only run record.
3. Preserve the worktree unchanged.
4. Print a concise terminal summary.
5. Exit using the documented decision-required exit code.
6. Do not continue automatically.
7. Do not infer approval from silence.

## Owner response

The owner response must include:

```yaml
schema_version: 1
decision_id: HD-017
selected_option: A
owner_instruction: ""
ratified_at: "2026-01-01T00:00:00Z"
```

The controller must:

- validate the decision identifier;
- validate the selected option;
- append the decision to the Decision Ledger;
- preserve the original request;
- regenerate the implementation brief if the decision changes scope;
- resume only from a valid state.

## External architecture review

The following stages should be presented for independent human or model architecture review:

- F-04 freeze;
- controller design;
- controller completion;
- first S-05 pilot plan;
- first autonomous tranche result;
- permission to expand autonomous scope;
- production-facing or customer-data work.

These gates are separate from ordinary controller escalations.

## Safe default

When uncertain, stop without mutating protected state.

A blocked tranche is preferable to an unapproved architectural or security change.
