# S-06-001 Source Scope Predicate (PRULE-021, pure) — Completion Report

Status: **READY FOR REVIEW.** Implemented, verified, hardened per the owner's Option-A ruling, and
re-reviewed on the isolated branch `tranche/S-06/S-06-001` (base `0f6a625` = the integration tip
`origin/implementation/s01-registration-access`; tip `16f7a89`). The protected branch (`main`) and the
integration branch are untouched; **nothing is pushed**; no tag moved. The first sub-tranche of the
owner-authorised S-06 block (ADR-049). It is a **pure PORO** consuming **no** foundation (F-01..F-04) and
no S-05 code.

The independent security lens's finding **HD-S06-001-SCOPE-SEPARATOR is RESOLVED** (owner Option A,
ADR-051). All five re-run ADR-026 lenses returned **PASS** with **zero confirmed-blocking findings**.

## What was built

The pure Source Scope Predicate of WF-004 (PRULE-021; contracts/S-06.json MTX-072; SECURITY_PERFORMANCE.md
§ PRULE-021), the analogue of the S-05-003 pure observation engine.

`Workflows::Wf004::SourceScopePredicate.evaluate(url:, policies:)` normalizes a candidate canonical URL and
decides admission against the active Source Scope Policy intersection, returning a `Decision` (`allowed?`,
one `reason_code`, normalized `canonical_url` on allow). **No** persistence, outbound call, event, or
Source/Request transition. Defined here; applied later by S-07 against the pinned policy version.

- **Normalization (precedes comparison):** host lowercased per the ratified `ascii-host-v1` contract with
  trailing dot removed and **no implementation-side IDNA/punycode** (a non-ASCII host is out of scope);
  default port removed; path dot-segments removed (RFC 3986 §5.2.4) and unreserved percent-encoding decoded
  (a `%2E` dot resolved as a dot segment; other escapes keep their byte, hex uppercased); fragment dropped;
  userinfo rejected; query pairs decoded, retained per policy, sorted by decoded key then value preserving
  duplicates.
- **Admission:** allowed only when the URL matches **every** active policy intersection (exact host, allowed
  scheme, allowed effective port), **≥1** include prefix and **no** exclude prefix (exclusion wins), plus the
  query rule; a prefix matches the normalized path exactly or at a `/` segment boundary; query never denies.
- **Fail-closed exclusion hardening (owner Option A, ADR-051):** when testing an **exclude** prefix, `%2F`
  and `%5C` (case-insensitive) and a raw `\` are treated as `/`-equivalent boundaries (dot-segments then
  resolved), so an excluded subtree cannot be reached by encoding the separator. Exclusion-only and additive:
  it does **not** decode those characters, alter the canonical URL, or change include matching; the probe only
  ever ADDS denials.
- **Determinism & safety:** pure (same URL + policy version ⇒ `==` Decision); an empty policy set raises;
  deterministic snake_case denial vocabulary.

## Commit tranche (branch `tranche/S-06/S-06-001`, base `0f6a625`)

| Commit | Purpose |
| --- | --- |
| `339a83a` | S-06 authorisation + decomposition: BUILD_PLAN S-06-001..005, BUILD_STATE, DECISIONS ADR-049 (planning) |
| `3aaf017` | S-06-001 (1/n): the `SourceScopePredicate` PORO + 34 examples |
| `8409870` | S-06-001 (2/n): first review outcome + records; escalation ADR-050 (superseded) |
| `7d1e5e8` | S-06-001 (3/n): fail-closed exclusion separator hardening (owner Option A) + DECISIONS ADR-051 |
| `16f7a89` | S-06-001 (4/n): mandated thread-safety + boundary + double-encoding characterization tests |

Diff `0f6a625..16f7a89`: **no `db/` change, no `app/models/` change** — pure predicate, no schema. Within the
reviewability limits (≤40 files, ≤3,000 lines).

## Verification (exact results, at `16f7a89`)

- Whole repository: **1240 examples, 0 failures** (1191 baseline + 49 predicate examples). Zeitwerk clean;
  Packwerk no offenses; Brakeman 0 warnings; bundler-audit no vulnerabilities. Architecture fitness green
  within the full suite.
- `migration_safety_no_drift` / `runtime_role_and_rls`: not triggered — no `db/**`, `app/models/**` or
  infrastructure change (manifest path-selected). No `structure.sql` drift is possible.
- Rubocop: only `Layout/SpaceInsideArrayLiteralBrackets` — the same single cop and no-inner-space array idiom
  as the accepted S-05 baseline; not a mandatory-manifest gate.

## Independent review (ADR-026) — RE-RUN after the Option-A hardening

Five separately-invoked adversarial lenses with no shared state:

| Lens | Verdict |
| --- | --- |
| Security / tenant-isolation / boundary | **PASS** — **HD-S06-001-SCOPE-SEPARATOR RESOLVED**; 60/60 adversarial checks; no new bypass, no over-deny, no regression |
| Contract correctness | **PASS** — faithful, additive, fail-closed; base MTX-072 preserved; RFC §5.2.4 verified |
| Determinism / purity | **PASS** — non-mutation, frozen-input safety, thread-safety (16×500 → 1 result) |
| Architecture / scope / frozen | **PASS** — pure exclusion-only; frozen contract text NOT edited; Zeitwerk+Packwerk clean; minimal |
| Test quality / coverage | **PASS** — every mandated item asserted (thread-safety added); non-tautology proven by mutants |

**Zero confirmed-blocking findings.** The original security finding is explicitly RESOLVED.

## Non-blocking observations recorded (not actioned — "record without expanding scope")

- **(security, follow-up candidate) Broader separator representations.** The owner's ruling named `%2F`, `%5C`
  and raw `\` ("at minimum"). Double-encoded `%252F`, overlong UTF-8 (`%c0%af`) and the Unicode fraction-slash
  `⁄` (U+2044) are **outside the ratified named set** and remain allowed; the predicate never recursively
  decodes and the canonical URL carries them verbatim, so exploitation would require a downstream origin to
  double-decode — a defense-in-depth residual, not a break of the ratified Decision. Pinned by a
  characterization test. Candidate separate owner decision to extend `SEPARATOR_EQUIVALENT` if a future
  consumer's origin double-decodes.
- **(security, low)** A raw C1 control byte in the path is not caught by `CONTROL_OR_SPACE` and the path is not
  `ascii_only?`-checked; same-host, hygiene only (CRLF is already `url_malformed`).
- **(security, low)** Path matching is case-sensitive (`/Private` not excluded by `/private`) — spec-conformant
  (RFC folds only host/scheme).
- **(perf, trivial)** `exclusion_probe` is recomputed per policy, not memoized across the intersection — pure
  and identical each time; micro-perf only.
- **(contract, ambiguity)** MTX-072 says "host lowercase **IDNA** ASCII" while the ratified `ascii-host-v1`
  reading (used here) does no implementation-side punycode; suggest the contract text say "already-ASCII (IDNA
  resolved upstream)".
- **(out-of-scope, by design)** The MTX-072 clause "an out-of-scope redirect is not followed" belongs to S-07;
  its suite must own it.

## What happens next

- **Owner acceptance-and-merge (human_gate_after):** review `tranche/S-06/S-06-001` and, if accepted,
  fast-forward merge it into `implementation/s01-registration-access` and add `S-06-001` to `completed_blocks`.
- **No subsequent tranche is begun** (owner instruction). **No merge, no push, `main` untouched.** S-06-002
  remains `human_gate_before`.
