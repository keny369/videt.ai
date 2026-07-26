# S-05-005 CompleteVerificationAttempt (observation recording) — Completion Report

Status: **ACCEPTED AND MERGED** (owner approval, 2026-07-26) — fast-forward merged from
`tranche/S-05/S-05-005` into the integration branch `implementation/s01-registration-access` at
`feec2fd`; added to `BUILD_STATE.completed_blocks` (BUILD_PLAN S-05-005 → completed, DECISIONS
ADR-041). The protected branch (`main`) is untouched and nothing is pushed. It was implemented,
verified and independently reviewed on that branch off base `e96cb3d` (the owner-authorisation commit
ADR-039). Third sub-tranche of the owner-accepted Observation split (ADR-033). The first real F-03
Evidence producer. Consumes F-01..F-04 only through their frozen façades.

## What was built

`Workflows::Wf003::CompleteVerificationAttempt` — the service-executed observation-recording limb of
WF-003. Given a reserved attempt it runs the observation and records the outcome:

- **Provider call outside every transaction** (contracts/S-05.json transaction_boundary): a read-and-
  reveal transaction resolves the inputs and decrypts the challenge token behind F-02; the S-05-003
  engine (`VerificationObservation`) then runs with no transaction held; a completion transaction
  commits only the recorded outcome.
- **Exactly one restricted `verification_observation` Evidence** (F-03), whether matched, not matched
  or indeterminate. Its redacted payload (enums, counts and the `observed_value_sha256` hash — never
  the plaintext token or raw DNS/HTTP content) is protected behind an F-02 reference; the Evidence
  envelope records only the reference + content digest. Produced through the frozen
  `Platform::Evidence.produce` surface, idempotent on `(organization_id, producer_id, attempt_id)`.
- **Exactly one `SourceVerificationObserved`** referencing that Evidence; the attempt `reserved ->
  completed` with the outcome columns; the Request `last_observed_at_utc`, on-demand marker cleared and
  `last_on_demand_completed_at_utc` set — all atomic, the Request `request_status` held `pending`.
- **A matched observation is RECORDED only:** the Source is left `proposed` and the Request `pending`
  (the matched success commit — Request `verified` + `SourceVerified` + `Source.Proposed -> Verified` +
  scope materialization — is S-05-006, proved unreachable here).
- **Idempotent by the reserved attempt identity:** a persisted completion replays without re-observing;
  a completion-persistence failure leaves the attempt `reserved` and a retry re-runs under the SAME
  attempt, consuming no second count (`attempt_count` was incremented at reservation, never here). The
  completion transaction locks the Request, re-reads and re-checks idempotency, and guards both UPDATEs
  on the expected state versions (a lost race raises and rolls back the whole record — Evidence, F-02
  ciphertext and ledger together).
- **Service-attributed** (`service_identity_id` set, null human actor); no permission check — authority
  was established at Request creation and on-demand acceptance (MTX-051). Completion and expiry
  serialize on the same `verification-request:<id>` advisory lock, so expiry-versus-completion races
  are ordered.

The migration relaxes exactly the `reserved -> completed` guard edge (mirroring S-05-002's
`pending -> expired`); no new table, column, index or grant (the attempt outcome columns and the
`evidence` grant already exist). Two new F1-DOMAIN-409 reasons: `verification_attempt_target_mismatch`,
`verification_attempt_not_reserved`.

## Commit tranche (branch `tranche/S-05/S-05-005`)

| Commit | Purpose |
| --- | --- |
| S-05-005 (1/n) | Relax the verification_attempts guard for exactly `reserved -> completed` + structure.sql + on-demand/completion error reasons + the invariants guard-test update |
| S-05-005 (2/n) | `CompleteVerificationAttempt` command + handler (two-phase; F-03 Evidence; SourceVerificationObserved) + `VerificationObservationStore` (service-attributed) + acceptance spec |
| S-05-005 (3/n) | Independent-review repair (comment accuracy: the service-store duplication is the third structural copy — a ServiceLedgerWriters extraction is a deferred follow-up) |

## Verification (exact results)

- Whole repository: **1158 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities.
- DB permissions/RLS: `f1:db:verify_runtime` OK as `f1_web` — 15 checks passed (RLS intact).
- `migration_safety_no_drift`: `db:schema:dump` is idempotent; no `db/structure.sql` drift.
- Architecture fitness (`spec/architecture`, incl. the F-03 evidence single-surface fence): green — the
  slice consumes F-01..F-04 only through their public façades and writes Evidence only through
  `Platform::Evidence.produce`.

## Independent review (ADR-026)

Five adversarial lenses by separately-invoked models with no shared conversational state
(contract-correctness, security/no-secret-at-rest, F-03/F-02 integration, concurrency/idempotency,
architecture/frozen-contract): **PASS_NO_BLOCKING — zero blocking findings, zero confirmed-blocking
after the verify pass.** The reviewers confirmed the provider-call-outside-every-transaction structure,
the single restricted Evidence + single observed event, the atomic version-guarded record with LostRace
rollback, the token confined to the reveal/provider phases and absent from every persisted column, the
Evidence Record shape against the canonical F-03 acceptance test, the single-surface producer usage and
transaction-sharing atomicity, the transaction-local context across the two transactions, and
frozen-façade compliance. One review-driven repair applied (comment accuracy only).

## Non-blocking findings recorded (not actioned per the "confirmed blocking only" instruction)

- **(low) started/completed instants:** the Evidence and attempt record `started_at ≈ completed_at` at
  the completion instant, because a command's `RequestContext` carries a single clock `now`; capturing
  the true pre-provider-call start would need a different clock model. No observable effect.
- **(observation) deny-path idempotency:** the completion's precondition denials write no idempotency
  record, so a retried denied completion re-emits ledger rows, diverging from ExpireVerificationRequest
  which makes such denials replayable — a candidate consistency alignment.
- **(observation) terminal race between phases:** a Request that goes terminal (expiry/cancel) between
  the provider call and the commit records no Evidence (the completion returns `not_pending`) and leaves
  the attempt `reserved`; a later cleanup limb is out of scope here.
- **(observation) test coverage:** the at-rest token-absence assertion could also pin
  `command_results.authorized_payload`; a true concurrent two-racer completion test could join the
  sequential idempotency coverage (the same non-blocking note carried from S-05-004).
- **(follow-up) ServiceLedgerWriters extraction:** now warranted at the third service-store copy;
  deferred as it would edit the merged expiry stores.

## What happens next

- **Owner review gate (human_gate_after):** review `tranche/S-05/S-05-005` and, if accepted, merge it
  into `implementation/s01-registration-access` and add `S-05-005` to `completed_blocks`.
- **S-05-006 is NOT begun** (owner instruction). It is next in the authoritative sequence (the matched
  success commit + source-scope-interim-v1) and remains `human_gate_before`; it carries the flagged
  Source Scope / S-06 architectural dependency to decide before it runs.
- Nothing is pushed; no tag moved; no production path exercised.
