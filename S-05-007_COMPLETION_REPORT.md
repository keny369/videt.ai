# S-05-007 automated observation slot schedule — Completion Report

Status: **READY FOR REVIEW** (human_gate_after) — implemented, verified and independently
reviewed on branch `tranche/S-05/S-05-007` off base `af62719` (the owner-authorisation commit
ADR-045). NOT merged; the protected branch (`main`) is untouched and nothing is pushed. The FIFTH
and FINAL sub-tranche of the owner-accepted Observation split (ADR-033); on acceptance it completes
the WF-003 Ownership Verification limb (S-05-001..007). Consumes F-01..F-04 only through their frozen
façades.

## Coherence assessment (owner-directed precondition)

The owner authorised S-05-007 "exactly as defined in BUILD_PLAN" and directed that, before
implementation, the controller assess whether the repository-defined scope remains **one coherent,
reviewable tranche**, decomposing only if it genuinely cannot. **Conclusion: it remains one coherent
tranche; implementation proceeded without decomposition.** Grounds:

- S-05-007 is a single mechanism — "the automated observation slot schedule" — whose three contract
  facets (start-only-in-the-half-open-window; skip-once-and-never-late; terminal-cancellation-without-
  skipped-events) are inseparable views of the same schedule. Split apart they become dead code that
  cannot demonstrate its own acceptance criteria (a schedule with no job; a job with nothing to run; a
  skip with no window; a terminal-cancel with no slots).
- It is the DESIGNATED FINAL unit of an already-smallest-unit split (ADR-032/033 split the Observation
  limb precisely to keep each tranche the smallest self-contained reviewable unit); no further natural
  seam yields independently-verifiable sub-units.
- It REUSES rather than reimplements the built engine: `CompleteVerificationAttempt` (S-05-005/006) and
  `VerificationObservation` (S-05-003) are consumed wholesale; the novel surface is narrow.
- It modifies no frozen foundation (F-04 consumed only through `ScheduledActions::Store#create` and the
  boot `Registry`; terminal cancellation uses the repository's own ratified harmless-terminal-execution
  precedent, not a proactive F-04 cancel).
- It landed at **924 insertions across 13 files** — comparable to the prior sub-tranches and well under
  the configured limits (max 40 changed files; max 3,000 diff lines).

## What was built

The automated observation slot schedule of WF-003 Ownership Verification, in three reviewable commits.

**The schedule (at issuance).** `IssueVerificationChallenge` now schedules, on the same issuing
transaction as the Request and the 24-hour expiry timer, the ten `verification_observation_slot`
ScheduledActions at due offsets **0, 5, 15, 30, 60, 120, 240, 480, 960 and 1,380 minutes** after
issuance (`AutomatedObservationSlotSchedule`, the ratified `VerificationRequestExpirySchedule`
pattern). The ten share a target Request but carry ten distinct action identities because the F-04
identity preimage includes `due_at`; the Request and its whole schedule commit or roll back together.

**The windows (a pure value module).** `AutomatedObservationSlots` maps each offset to its half-open
window `[offset, next_offset)`; the final window ends at expiry (1,440 minutes = the 24-hour lifetime),
so the ten windows tile the whole lifetime with no gap and no overlap.

**The job (`ObserveAutomatedSlot`).** The service-only handler behind a due slot resolves it, under the
per-Request advisory lock, to exactly one outcome:

- **OBSERVE** — in window and pending: reserve ONE automated attempt (origin `automated` with its slot
  offset; `attempt_count + 1` and nothing on-demand) and complete it through the unchanged S-05-005/006
  `CompleteVerificationAttempt` engine (provider call outside the transaction; a match committing
  strictly before `expires_at_utc` fires the atomic success).
- **SKIP** — the half-open window has closed (`now >= issued_at + next_offset`): record
  `observation_slot_skipped` exactly once (a scheduler record — no attempt, no Evidence, no domain
  event) and never run late.
- **VOID** — the Request is already terminal: record NOTHING (no attempt, no observation, no skip). A
  terminal Request thereby "cancels all remaining slots without skipped events" via the ratified
  harmless-terminal-execution pattern (the Invitation/expiry precedent), not a proactive F-04 cancel.
- **RESUME / REBUILD** — idempotent under redelivery: a started slot resumes its reserved attempt
  (never a second one); a skipped slot replays its record.

**The database backstop.** A partial unique index `verification_attempts_one_automated_per_slot` on
`(verification_request_id, automated_slot_offset_minutes) WHERE origin = 'automated'` guarantees at most
one automated attempt per (Request, slot), so a redelivered slot job can never double-count; on-demand
attempts (NULL offset) are excluded and their path is untouched.

## Commit tranche (branch `tranche/S-05/S-05-007`)

| Commit | Purpose |
| --- | --- |
| S-05-007 (1/n) `c321f92` | `verification_attempts_one_automated_per_slot` partial unique index + structure.sql + persistence invariants |
| S-05-007 (2/n) `80ddfbc` | `AutomatedObservationSlots` (offsets/windows) + `AutomatedObservationSlotSchedule` + the ten slots scheduled at issuance + PORO/issuance specs |
| S-05-007 (3/n) `66b1df8` | `ObserveAutomatedSlot` command + handler (observe/skip/void/resume/rebuild) + the `VerificationObservationStore` automated-reserve surface + registration + acceptance spec |

## Verification (exact results)

- Whole repository: **1191 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities.
- Background execution (F-04): `f04_background_execution_acceptance_spec` + `scheduled_actions` +
  `claiming_spec` — green (22 examples in the focused run; also within the full suite).
- DB permissions/RLS: `f1:db:verify_runtime` OK as `f1_web` — 15 checks passed (RLS intact).
- `migration_safety_no_drift`: `db:schema:dump` is idempotent; no `db/structure.sql` drift.
- Architecture fitness (`spec/architecture`): **31/0** — foundations consumed only through their
  façades; the F-04 background-execution single-surface and scheduled-action-catalogue fences pass.

## Independent review (ADR-026)

Five adversarial lenses by separately-invoked models with no shared conversational state —
contract-correctness, concurrency/atomicity/idempotency, security/tenant-isolation,
schema/migration-safety, and architecture/scope/frozen-contracts. **Every lens returned PASS with zero
confirmed-blocking findings.** Highlights:

- **Contract:** all ten offsets, the half-open windows (upper bound exclusive; final window ends at
  expiry), skip-once-never-late, terminal-void-without-skip, the `attempt_count`-only reservation, the
  `< expires_at_utc` boundary (preserved by the delegated engine) and the offset recovery/validation are
  all correct; issuance schedules the ten slots in-transaction with distinct identities.
- **Concurrency:** find-before-reserve ordering + the per-Request advisory lock + the single-transaction
  reserve + the byte-identical index predicate close every double-count, duplicate-delivery,
  lost-update and infinite-retry vector; no lock is held across the provider call.
- **Security:** the org context is entered before any org-scoped access (RLS makes a cross-tenant
  request invisible → target mismatch); service-attributed ledger with null actor_id; the slot handler
  never touches the challenge token/ciphertext; the migration grants nothing.
- **Schema:** purely additive migration, no `structure.sql` drift, index correct against both CHECKs,
  the lifecycle guard and the composite FKs.
- **Architecture:** zero `app/platform/` changes; F-04 consumed only via `Store#create` + `Registry`;
  no proactive cancel; no S-06/scoring/on-demand/Cancel/Fail scope creep.

No confirmed-blocking finding was raised, so no repair was required (owner instruction: repair only
confirmed blocking findings).

## Non-blocking findings recorded (not actioned per the "confirmed blocking only" instruction)

- **(low) No lower-bound "not-due" guard** in `ObserveAutomatedSlot` — the handler enforces the upper
  window bound (`window_closed?`) but not `now >= due`. PostgreSQL transaction time is the contract's
  sole due-time authority (F-04 `claim_due` returns only due actions), and the slot's target-integrity
  check is the `slot_offset` validation; an early run under app/DB clock skew is not reachable via the
  normal path and would be benign (a valid observation within the live lifetime, one count). A candidate
  parity follow-up with `ExpireVerificationRequest`'s `scheduled_action_not_due` guard.
- **(observation) The VOID path writes no service-ledger record** (no execution/audit/result), unlike
  the SKIP/DENY paths and the sibling terminal `ExpireVerificationRequest` deny — an audit-trail
  asymmetry, not a correctness defect (the F-04 worker still settles the claim; the Request's own
  terminal transition is the record). A candidate observability follow-up.
- **(observation) A started slot writes no observe-command ledger** — deliberate: resume-by-attempt
  identity is the idempotency mechanism, and the completion engine writes the full observation ledger
  (keyed to the attempt). Noted for auditor awareness.
- **(observation) A slot that reserves in-window and then finds the Request terminalized before
  completion** leaves the attempt `reserved` and returns `verification_request_not_pending` — the
  pre-existing reserve/complete characteristic (on-demand reaches it too), not widened by S-05-007.
- Carried from earlier sub-tranches (recorded in ADR-040/043, not gate failures): the `ServiceLedgerWriters`
  extraction (now a fourth service-store copy with this store's additions), the deny-path idempotency
  alignment, and the SourceVerified event-envelope consistency fields.

## What happens next

- **Owner review gate (human_gate_after):** review `tranche/S-05/S-05-007` and, if accepted, merge it
  into `implementation/s01-registration-access` and add `S-05-007` to `completed_blocks`. Acceptance
  completes the WF-003 Ownership Verification limb (S-05-001..007).
- **No subsequent tranche is begun** (owner instruction). Nothing is pushed; no tag moved; no production
  path exercised.
