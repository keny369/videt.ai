# S-05-001 IssueVerificationChallenge — Completion Report

Status: **ready_for_review** — implemented, verified and independently reviewed on branch
`tranche/S-05/S-05-001` (off base `5483e4a`), **not merged**; the protected branch (`main`) is
untouched. This is the first autonomous PRODUCT tranche run through the Autonomous Build Controller's
discipline (CTRL-01 / ADR-026), and the first real consumer of F-02 (Platform::Encryption) and a new
consumer of F-04 (ScheduledActions). It consumes F-01..F-04 only through their frozen façades.

## What was built

The challenge-issuance limb of WF-003 Ownership Verification. An authorized Organization Administrator
or Technical Implementer opens ownership verification for a **proposed** Source:

- One pending `verification_requests` row is created (the aggregate root), with immutable issuance
  provenance, under forced tenant RLS.
- One challenge token (≥128 bits of cryptographically secure entropy) is generated and **protected
  behind F-02** — envelope-encrypted, bound by an AAD to `(org, request, purpose)`. Only the F-02
  ciphertext reference, a protection-profile key reference, and the SHA-256 token digest are stored;
  the plaintext token is returned **only** in the authorized response and appears in no column, log,
  event, or audit.
- The 24-hour expiry is **scheduled through F-04** (`verification_request_expire`, already in the
  ratified catalogue → `ExpireVerificationRequest`) on the same transaction.
- One `SourceVerificationRequested` event, one restricted audit, the command result and the
  idempotency record — all in one atomic commit with the row, the encrypted record, and the schedule.
- Idempotent exact replay by the original actor re-decrypts and returns the same token while pending
  (and appends a restricted security access log); a decryption failure is
  `challenge_redelivery_unavailable` and changes no state.

Explicitly **out of scope** and proven unreachable here: DNS/HTTP observation (Reserve/Complete), the
Source `proposed → verified` transition, expiry/cancel/fail execution, cryptographic deletion, and
scoring/evaluation. The Source stays `proposed`; no `SourceVerified` event is emitted.

## Commit tranche (branch `tranche/S-05/S-05-001`)

| Commit | Purpose |
| --- | --- |
| S-05-001 (1/n) | `verification_requests` migration (RLS, lifecycle guard, method/24h/pending CHECKs, one-pending-per-Source, composite Source FK) + additive runtime grant + F-02 key-ring provisioning substrate + structure.sql |
| S-05-001 (2/n) | `Workflows::Wf003::IssueVerificationChallenge` command/handler/challenge/ledger/store; F-02 encrypt; F-04 schedule; events; `source.verify` baseline row; S-05 error reasons; specs; BUILD_PLAN reconciliation |
| S-05-001 (3/n) | Independent-review repairs: restricted security access log on redelivery; two security-property tests; clarity comments |
| S-05-001 (4/n) | Re-review repair: audit-id traceability fix; access-log content regression test |

## Verification (exact results)

- Whole repository: **1076 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities.
- DB permissions/RLS: `f1:db:verify_runtime` OK as `f1_web` — 15 checks passed (RLS intact).
- `migration_safety_no_drift`: `db:schema:dump` produces no `db/structure.sql` diff post-commit.
- Architecture fitness (`spec/architecture`) green — the F-02 and F-04 single-surface fences pass, so
  the slice consumes both foundations only through their public façades (no internal-class or raw
  OpenSSL reference).

## Independent review (ADR-026)

Two rounds, each by a **separately invoked model with no shared conversational state**, against the
committed diff:

1. Full-tranche review → **pass_with_observations, zero blocking**. Confirmed token-at-rest secrecy,
   tenant/actor isolation, atomic single-transaction commit, least-privilege additive grants, correct
   AAD binding, dev-key-ring gating, and frozen-façade compliance. Recommendations applied: the
   restricted redelivery access log (a real contract requirement), and two security-property tests.
2. Repair-delta review → **pass_with_observations, zero blocking**. Confirmed the access log never
   carries the token, commits atomically under the proved-org context, and writes no extra domain
   state. One traceability fix applied (result now resolves to the access-log audit it wrote), plus an
   audit-content regression test.

## Decision Ledger

| Decision | Authority | Reason |
| --- | --- | --- |
| Add `verification_requests` grant to `lib/f1/runtime_grants.rb` (SELECT/INSERT/UPDATE, no DELETE) | Foundation Consumption Rule (backwards-compatible extension) | The single privilege convergence point must carry every new tenant table; additive, no existing grant changed, FORCE RLS preserved. The file is on the controller's frozen denylist — see the recommendation below. |
| F-02 key-ring provisioning substrate (dev/test default ring + `f1:db:ensure_encryption_key`) | Reproducible-provisioning standard (autonomous) | S-05 is F-02's first consumer; F-02 froze without any key-ring bootstrap. Added outside the frozen surface; production supplies the ring out of band. |
| `challenge_key_id` = protection-profile identifier | Assumption | F-02's façade returns one opaque reference and manages key versions internally; reaching for the internal version would break the Consumption Rule. |
| AAD = (verification, verification_request, request id, challenge_token, org) | Autonomous (security default) | Binds each ciphertext to its Request and tenant; cannot be relocated across Requests or Organizations. |
| `source.verify` baseline row + S-05 error reasons | Autonomous (data addition) | contracts/S-05.json permission_checks / error_contract; no evaluator/engine change. |

Full detail: `DECISIONS.md` ADR-027.

## Non-blocking owner recommendation (controller refinement)

The controller's `FrozenContracts` denylist (v1) escalates on **any** change to
`lib/f1/runtime_grants.rb`, yet every future tenant-table slice (S-06, S-07, …) must add an additive
least-privilege grant there — the file's own charter says "Update this module … when a table …
changes." The v1 controller has no evolution-rule exception, so it would escalate on every new-table
grant, contradicting the ratified Foundation Consumption Rule and the owner's "infrastructure proceeds"
guidance. **Recommendation:** refine `FrozenContracts` to distinguish an additive new-table grant (no
existing grant changed, no privilege widened, FORCE RLS preserved) — which proceeds under the
Consumption Rule — from a privilege-boundary change (a new DELETE, a widened role, a weakened RLS
predicate) — which still escalates. This is a change to a security tripwire and is left for owner
ratification rather than made autonomously.

## What happens next

- **Owner review gate (human_gate_after):** review this branch and, if accepted, merge
  `tranche/S-05/S-05-001` into the integration branch and add `S-05-001` to
  `BUILD_STATE.completed_blocks`.
- **Do NOT begin S-05-002** (the next WF-003 limb) — it is human-gated in `BUILD_PLAN.yml` and its
  scope is defined only from authoritative sources after this review.
- Nothing is pushed; no tag moved; no production path exercised.
