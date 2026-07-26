# S-06-001 Source Scope Predicate (PRULE-021, pure) — Completion Report

Status: **IMPLEMENTED, VERIFIED, INDEPENDENTLY REVIEWED — HELD AT `human_decision_required`.**
Implemented on the isolated branch `tranche/S-06/S-06-001` off base `0f6a625` (the integration tip,
= `origin/implementation/s01-registration-access`). The protected branch (`main`) and the integration
branch are untouched; **nothing is pushed**; no tag moved. The first sub-tranche of the owner-authorised
S-06 block (ADR-049). It is a **pure PORO** and consumes **no** foundation (F-01..F-04) and no S-05 code.

**Why held (not `ready_for_review`):** four of the five independent adversarial lenses returned PASS; the
**security/tenant-isolation lens returned CHANGES_REQUIRED** on one verified, latent scope-boundary
finding (encoded/backslash separator exclusion evasion). The current code is **spec-conformant to
PRULE-021 as literally written**, and the fix requires either deviating from that ratified rule or a
cross-cutting S-07 crawl ruling — a decision the specification does not resolve. Per the owner's
governance ("do not reinterpret repository governance in chat") and AUTONOMOUS_BUILD_CONTROLLER §7
(security + ambiguous product-semantics → human escalation), the controller does **not** silently harden
and stops for an owner ruling. See **Open owner decision** below.

## What was built

The pure Source Scope Predicate of WF-004 (PRULE-021; contracts/S-06.json MTX-072; SECURITY_PERFORMANCE.md
§ PRULE-021), the direct analogue of the S-05-003 pure observation engine.

`Workflows::Wf004::SourceScopePredicate.evaluate(url:, policies:)` takes a candidate canonical URL and the
active Source Scope Policy intersection (an Array of the `Policy` value object) and returns a `Decision`
(`allowed?`, one `reason_code`, and the normalized `canonical_url` on allow). It performs **no**
persistence, **no** outbound call, **no** event and **no** Source/Request transition. It is defined here
and applied later by S-07 against the pinned policy version (MTX-072 rollout); S-07 does not redefine it.

- **Normalization (precedes comparison):** host lowercased per the ratified `ascii-host-v1` contract with
  the trailing dot removed and **no implementation-side IDNA/punycode** (a non-ASCII host is out of
  scope — the reason Volume I fixes so implementations cannot diverge); the default port removed; path
  dot-segments removed (RFC 3986 §5.2.4) and unreserved percent-encoding decoded (so a `%2E`-encoded dot
  is resolved as a dot segment; other escapes keep their byte with the hex uppercased); the fragment
  dropped; userinfo rejected; query pairs decoded, retained per policy and sorted by decoded key then
  value preserving duplicates.
- **Admission:** allowed only when the URL matches **every** active policy intersection (exact host,
  scheme in the allowed set, effective port in the allowed set), **at least one** include prefix and
  **no** exclude prefix (exclusion wins), plus the query rule. A prefix matches the normalized path
  exactly or at a `/` segment boundary (`/shop` matches `/shop/item`, not `/shopping`); root `/` matches
  every absolute path. Query never denies admission — it only shapes the canonical identity.
- **Determinism & safety:** pure (same URL + same policy version ⇒ `==` Decision); an empty policy set
  raises `ArgumentError` rather than silently admitting; a deterministic snake_case denial vocabulary
  (`REASON_CODES`).

## Autonomous interpretation decisions recorded (permitted under delegation)

The contract fixes the rules but not certain surface details; these were resolved deterministically and
consistently with repository convention, and are recorded here for auditor awareness:

- **Denial-reason vocabulary** (`url_malformed`, `url_userinfo_prohibited`, `host_out_of_scope`,
  `scheme_out_of_scope`, `port_out_of_scope`, `path_excluded`, `path_not_included`) and their fixed
  precedence — snake_case, mirroring the S-05-003/registration reason style.
- **Fragment dropped, userinfo rejected** — the normalization prose says both are "prohibited"; a fragment
  is not part of a resource identity so it is dropped, while userinfo in a crawl target is anomalous and
  is rejected.
- **Empty explicit port** (`host:`) and an explicit **default port** (`:443`) both resolve to the scheme
  default (RFC/WHATWG-consistent); a nondefault port is a `port_out_of_scope` **decision**, not malformed.
- **Query handling** is a value-object abstraction (`"retain_all"` or an Array of retained keys); the
  persistence encoding of an allowlist is a later sub-tranche's concern, keeping the predicate decoupled.

## Commit tranche (branch `tranche/S-06/S-06-001`, base `0f6a625`)

| Commit | Purpose |
| --- | --- |
| `339a83a` | S-06 authorisation + decomposition: BUILD_PLAN S-06-001..005, BUILD_STATE, DECISIONS ADR-049 (planning only) |
| `3aaf017` | S-06-001 (1/n): the `SourceScopePredicate` PORO + 34 deterministic examples |

Diff: 5 files, 755 insertions / 21 deletions (product+spec 505 lines across 2 files). **No `db/` change,
no `app/models/` change** — pure predicate, no schema. Well within the reviewability limits (≤40 files,
≤3,000 lines).

## Verification (exact results)

- Whole repository: **1225 examples, 0 failures** (1191 baseline + 34 new). Zeitwerk clean; Packwerk no
  offenses (338 files); Brakeman 0 warnings; bundler-audit no vulnerabilities.
- Architecture fitness (`spec/architecture`) runs green within the full suite.
- `migration_safety_no_drift` / `runtime_role_and_rls`: **not triggered** — no `db/**`, `app/models/**` or
  infrastructure change (the manifest selects them by changed path). No `structure.sql` drift is possible.
- Rubocop: the two new files show only `Layout/SpaceInsideArrayLiteralBrackets` — the identical single cop
  and no-inner-space array idiom as the accepted S-05 baseline code; rubocop is not in the mandatory
  VERIFICATION_MANIFEST set, and the code matches the established codebase style.

## Independent review (ADR-026) — five separately-invoked adversarial lenses

| Lens | Verdict |
| --- | --- |
| Contract correctness | **PASS** — every MTX-072/PRULE-021 clause verified by runnable Ruby, incl. RFC 3986 §5.2.4 and the `%2F` non-decode |
| Determinism / purity (idempotency analogue) | **PASS** — non-mutation, frozen-input safety, total/stable sort, thread-safety all verified |
| Architecture / scope / frozen-contracts | **PASS** — pure PORO, no `db`/`models`/event/job, no foundation consumed, Zeitwerk+Packwerk clean |
| Test quality / coverage (schema-safety N/A) | **PASS** — every normative clause mapped to an assertion; non-tautology proven by mutants |
| Security / tenant-isolation / boundary | **CHANGES_REQUIRED** — one verified latent finding (below); **no host-level false-allow found** |

**No confirmed-blocking finding was repaired.** The single CHANGES_REQUIRED finding is spec-conformant
in isolation and its resolution requires an owner/architecture ruling (see below); the controller does not
silently deviate from the ratified PRULE-021 spec.

## Open owner decision — PRULE-021 exclusion under separator-equivalent characters (HD-S06-001-SCOPE-SEPARATOR)

**Finding (verified).** With a policy that includes `/` and excludes `/private`, these are all **allowed**
by the predicate today:

- `/private%2Fsecret` (encoded slash) → `allowed`
- `/private%5Csecret` (encoded backslash) → `allowed`
- `/private\secret` (raw backslash) → `allowed`

whereas `/private/secret` is correctly `path_excluded`. Because `%2F`/`%5C` are (correctly, per the
ratified normalization) **not** decoded and a raw `\` is passed through, the character after `/private` is
not `/`, so the exclude segment-boundary test misses. Some origins (Apache `AllowEncodedSlashes on`,
several servlet containers/IIS, and WHATWG re-parsers that fold `\`→`/`) resolve these back to
`/private/secret` — the admin-excluded subtree — which S-07 could then turn into Evidence.

**Why it is not silently repaired.** (1) The behaviour is **spec-conformant** to PRULE-021 as written
(boundary = a literal `/` in the normalized path; `%2F` is reserved and preserved). (2) It is **latent**:
the only materialized policy (the S-05-006 interim) ships `exclude_prefixes: []`, the commands that set
non-empty excludes (S-06-002/003) are not built, and the S-07 crawler is not built — no current code path
reaches it. (3) The fix is a genuine product-semantics choice with more than one valid reading (RFC-literal
"different resource, no leak with `AllowEncodedSlashes off`" vs. fail-closed defence-in-depth), spanning the
predicate and S-07 crawl behaviour — an owner/architecture decision under AUTONOMOUS_BUILD_CONTROLLER §7.

**Options (for owner ruling):**

- **Option A (recommended):** Ratify a fail-closed hardening of the predicate — treat `%2F`, `%5C` and a
  raw `\` as segment separators (or quarantine any path bearing a raw `\`/encoded separator with a new
  reason) so exclusion catches them, erring toward exclusion. Small, still-pure addition to S-06-001 with
  covering tests; record the deviation from the literal PRULE-021 boundary rule as an ADR + a PRULE-021
  clarification. Closes the kernel gap before excludes ship (S-06-003) or S-07 crawls.
- **Option B:** Accept S-06-001 as spec-conformant now (latent), and mandate the Option-A hardening as a
  required predecessor to S-06-003 (which enables `exclude_prefixes`) and to S-07 crawl — tracked as an
  owner decision with a covering test.
- **Option C:** Rule that S-07 must crawl canonical URLs **verbatim** with encoded-slash decoding disabled
  (`AllowEncodedSlashes off`) and reject raw backslash, placing the mitigation in S-07; keep S-06-001
  as-is; record the ruling and a covering S-07 test.

**Recommendation:** Option A — the predicate is the enforcement kernel, fail-closed is the correct secure
default, and hardening here means every future consumer (S-06-003 excludes, S-07 crawl) inherits the safe
behaviour. It needs the owner's ratification precisely because it deviates from the literal ratified rule.

## Non-blocking observations recorded (not actioned — "record without expanding scope")

- (security, low) A raw C1 control byte in the path (e.g. ``) is not caught by `CONTROL_OR_SPACE`
  (` - `) and the path is not `ascii_only?`-checked; same-host, so not a scope escape —
  hygiene only. CRLF is already caught (`url_malformed`).
- (security, low) Path matching is case-sensitive (`/Private` not excluded by `/private`) — spec-conformant
  (RFC folds only host/scheme), same risk family as the separator finding; fold/ruling if desired.
- (test, risk→adequate) `spec` L216 asserts `REASON_CODES.include?(reason_code)` (accepts `allowed`); it is
  saved by the co-asserted `allowed?==false`/`canonical_url.nil?` and the specific codes are pinned in the
  dedicated examples. Tighten to denial-codes-only if desired.
- (test, coverage) Uppercase scheme, non-numeric port, IPv6-literal, double-slash paths and empty port are
  implemented but not separately pinned — candidate characterization tests.
- (contract, ambiguity) MTX-072 says "host lowercase **IDNA** ASCII" while the ratified `ascii-host-v1`
  reading (used here) does no implementation-side punycode; suggest the contract text say "already-ASCII
  (IDNA resolved upstream)".
- (out-of-scope, by design) The MTX-072 clause "an out-of-scope redirect is not followed" belongs to S-07
  (the predicate follows nothing); S-07's suite must own it.

## What happens next

- **Owner decision (HD-S06-001-SCOPE-SEPARATOR):** rule Option A / B / C on the exclusion separator finding.
- On an Option-A ruling: apply the small fail-closed hardening + tests to `tranche/S-06/S-06-001`, re-run
  verification and the security lens, then move to `ready_for_review`.
- On an Option-B/C ruling: accept S-06-001 as-is at `human_gate_after`; record the mandated follow-up.
- **No subsequent tranche is begun** (owner instruction). **No merge, no push, `main` untouched.** S-06-002
  remains `human_gate_before`.
