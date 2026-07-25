# Automation Documents — Repository Reconciliation

Reconciled 2026-07-25, before writing controller code (AUTONOMOUS_BUILD_CONTROLLER.md §1). The
supplied automation documents were treated as **inputs, not authority**: each was checked against
the actual repository and corrected. No contradiction was found that blocks building the controller;
any discovered later is a mandatory escalation, not a silent decision.

## Authoritative state vs. conversational memory

Authoritative state lives in version-controlled files: `specification/automation/BUILD_STATE.json`,
`BUILD_PLAN.yml`, `DECISIONS.md`, the F-0N freeze reports, and the repository itself. Chat history is
**not** authoritative. The controller derives all work from these files, never from a transcript.

## Corrections applied

| Item | Was | Now |
| --- | --- | --- |
| `BUILD_STATE.json` | `controller_version: unimplemented`, `status: planned`, `completed_blocks: []` — implied F-04 unbuilt | F-01..F-04 in `completed_blocks` (frozen), `current_block: CTRL-01`, `status: in_progress`, `base_commit` = HEAD; conversational-memory-not-authoritative note added |
| `BUILD_PLAN.yml` | F-04 `pending_freeze_confirmation`; CTRL-01 `planned` | F-04 `frozen` (ADR-025 / freeze report); CTRL-01 `in_progress` |
| Directory | `specification/automatation/` (misspelled) | `specification/automation/` (matches every internal reference) |

## `TO_BE_DISCOVERED` → canonical commands (VERIFICATION_MANIFEST.yml)

Every placeholder was resolved to a real, repository-root-runnable command, or explicitly marked
`covered_by` where the repository has no dedicated tool (recorded, not silently dropped):

| Check | Canonical command | Note |
| --- | --- | --- |
| repository_cleanliness | `git status --porcelain` (expect empty) | |
| complete_test_suite | `bundle exec rspec` | |
| brakeman | `bundle exec brakeman -q --no-pager -z` | `-z` = nonzero exit on any warning |
| packwerk | `bin/packwerk check` | |
| bundler_audit | `bundle exec bundle-audit check --update` | |
| zeitwerk | `bin/rails zeitwerk:check` | |
| migration_safety_no_drift | `bin/f1db db:schema:dump && git diff --exit-code db/structure.sql` | **no `strong_migrations` gem exists**; safety here = schema builds from migrations with no `structure.sql` drift |
| runtime_role_and_rls | `bin/f1db f1:db:verify_runtime` | one canonical task covers database_permissions + row_level_security + tenant isolation at the DB boundary |
| database_constraints | `covered_by: complete_test_suite` | the store/guard specs assert every CHECK + trigger; no dedicated tool |
| architecture_fitness | `bundle exec rspec spec/architecture` | the single-surface fitness specs |
| authorization_and_tenant_isolation | `covered_by: complete_test_suite` | CommandAuthorizer + RLS specs; no dedicated "fitness" command |
| redis_sidekiq_acceptance | `bundle exec rspec spec/acceptance/f04_background_execution_acceptance_spec.rb` | |
| concurrency_and_idempotency | `bundle exec rspec spec/platform/scheduled_actions` | |
| stale_lease_recovery | `bundle exec rspec spec/platform/scheduled_actions/claiming_spec.rb` | |
| controller_unit/integration/policy/crash_recovery/locking/end_to_end | `bundle exec rspec spec/automation/<area>` | the controller's own specs, built in this tranche |

## `match_paths` corrections

The manifest shipped with a generic `packages/**` layout that does not exist here. Corrected to the
actual Packwerk roots and paths: `app/platform/**`, `app/contexts/**`, `app/workflows/**`, `db/**`,
`lib/f1/runtime_grants.rb`, `config/sidekiq.yml`, `config/sidekiq_lifecycle.yml`,
`config/initializers/sidekiq.rb`, `app/platform/scheduled_actions/**`.

## Placeholders / decisions recorded (not silently resolved)

- **`max_model_spend_usd_per_tranche: null`** — provider spend is not machine-measurable in the local
  Claude Code environment; the limit stays null and cost is bounded instead by the invocation/turn/time
  limits (max_agent_invocations_per_tranche, max_wall_clock_seconds_per_run). Recorded as an assumption.
- **Cross-provider reviewer (mandate §6: "OpenAI Codex CLI")** — no OpenAI credentials are assumed. The
  controller defines a provider-neutral reviewer adapter; the synthetic proof uses a deterministic
  same-process independent-review stub, which §6 explicitly permits ("Provide a deterministic local
  reviewer stub … for proving orchestration"). Controller readiness, same-provider review and true
  cross-provider review are kept distinct.
- **Controller location** — `automation/` (top-level, outside the Rails `app/`, so it is not part of the
  product Packwerk graph or Zeitwerk autoload); CLI `bin/autonomous-build`; specs `spec/automation/`;
  append-only run records `automation/runs/<run-id>/`. Ruby + RSpec, per repository convention; no new runtime.

## Contradictions found

None that block the build. If the controller later finds two authoritative sources materially
contradicting, or a required frozen-foundation change, it escalates (`human_decision_required`) rather
than deciding.
