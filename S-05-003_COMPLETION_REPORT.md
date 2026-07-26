# S-05-003 Observation Engine — Completion Report

Status: **ready_for_review** — implemented, verified and independently reviewed on branch
`tranche/S-05/S-05-003` (off base `05c2011`), **not merged**; the protected branch (`main`) is
untouched and nothing is pushed. First sub-tranche of the owner-accepted Observation split (ADR-033).

## What was built

`Workflows::Wf003::VerificationObservation` — the pure ownership-verification observation engine.
Given `(method, canonical_host, token)` it performs **one guarded outbound observation through the
frozen F-01 façade** (`Platform::Outbound`) and applies the ratified predicate, returning a
restricted-safe `Result`: network outcome, nullable status, received byte count,
`observed_value_sha256` (or nil), match decision, and exactly one of the 14 reason codes.

- **DNS TXT:** `_f1-verify.<host>` via `fetch_dns_txt`; exact ASCII match of a complete TXT value
  against `f1-verification=<token>`; any-matching-record succeeds; per-record segment concatenation;
  case/whitespace/prefix/suffix differences fail; `observed_value_sha256` = SHA-256 of the LF-joined
  complete record values (null on absent); resolver timeout/temporary/host-invalid → indeterminate.
- **HTTP file:** `https://<host>/.well-known/f1-verification.txt` via `fetch` (10s / 4096 / no
  redirects); 200 + ≤4KiB + UTF-8 equality after ≤1 trailing-LF; the **4096/4097 boundary** →
  `http_body_too_large`; `observed_value_sha256` over the raw received bytes (before decode/trim);
  status mapping (408→timeout, 429→rate-limited, 5xx→server-error, other non-200→status-mismatch);
  redirect→`http_redirect_rejected`; tls→`tls_validation_failed`; connection→`connection_failure`.
- **Match decision:** `matched` only on a match; a definite non-match → `not_matched`; a dependency
  failure → `indeterminate` (stays pending until a later attempt or expiry).

**Restricted-safe:** the `Result` carries only the digest and enum/status/count fields — never the
plaintext token or raw DNS/HTTP content. `outbound` is injected so the whole decision is
deterministic in tests with no live network; it consumes **only** the F-01 façade.

Out of scope (later sub-tranches): attempt reservation, Complete + Evidence, the success commit, the
automated slot schedule.

## Commit tranche (branch `tranche/S-05/S-05-003`)

| Commit | Purpose |
| --- | --- |
| S-05-003 (1/n) | The observation engine + spec (every DNS/HTTP predicate, hashing, the 4096/4097 boundary, all 14 reason codes) |
| S-05-003 (2/n) | Independent-review repairs: comment accuracy + three test-coverage additions (no behavior change) |

## Verification (exact results)

- Whole repository: **1123 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit clean.
- Architecture fitness (`spec/architecture`, incl. the outbound single-surface fence): **31/0** — the
  engine consumes only the frozen F-01 façade; no raw socket/DNS/TLS and no internal transport class.
- No `db/structure.sql` change (pure engine; no migration, no grants).

## Independent review (ADR-026)

`pass_with_observations`, **zero blocking findings**; the reviewer byte-level-reproduced the DNS/HTTP
hashing and boundary rules and confirmed the match-decision invariant, restricted-safety and
frozen-façade compliance. Three actionable notes applied (comment + tests, no behavior change).

## What happens next

- **Owner review gate (human_gate_after):** review `tranche/S-05/S-05-003` and, if accepted, merge it
  and add `S-05-003` to `completed_blocks`.
- **S-05-004 was NOT begun** (owner instruction). It is next in the authoritative sequence
  (verification_attempts + ReserveVerificationAttempt) and remains `human_gate_before`.
- Nothing is pushed; no tag moved; no production path exercised.
