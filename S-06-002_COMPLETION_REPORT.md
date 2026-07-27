# S-06-002 Source Scope Change classifier (Option B, pure) — Completion Report

Status: **READY FOR REVIEW.** Implemented and independently reviewed on the isolated branch
`tranche/S-06/S-06-002` (base `6e8413a` = the integration tip after the S-06-001 merge; tip `e8b6d60`).
The protected branch (`main`) and the integration branch are untouched; **nothing is pushed**. The first
sub-tranche of the owner's Option-1 three-way decomposition of S-06-002 (ADR-055/056). It is a **pure PORO**
consuming only S-06-001's merged `SourceScopePredicate` and core Ruby.

All five independent ADR-026 lenses returned **PASS** with **zero confirmed-blocking findings**.

## What was built

The pure Source Scope Change classifier of WF-004 (WORKFLOW_SPECIFICATIONS.md § Source Scope Change
Contract; APPLICATION_LAYER.md § WF-004; owner ruling **Option B**, DECISIONS ADR-054), isolated for
focused adversarial security review per the S-05-003 precedent.

`Workflows::Wf004::ScopeChangeClassification.classify(current:, proposed:, boundary:)` takes three
`SourceScopePredicate::Policy` value objects and returns a `Result` with `classification` ∈
`:contraction | :expansion | :boundary_violation`, so the later Propose/Decide sub-tranches route dual
control (a contraction may later auto-activate without dual control; an expansion needs an OrganizationAdmin).

- **Base classification (ADR-054 §1):** a semantic **subset** test with **PRULE-021 (S-06-001) as the
  admission oracle**. A proposal is a `:contraction` only when its admitted URL set is a subset of the
  current active policy's; any non-strict-subset or **mixed** change is an `:expansion`. Witnesses are
  derived from every include/exclude prefix of both policies (plus a fresh child segment and a no-match
  path) — a finite, **complete** probe set for the `/`-boundary prefix semantics. **Fail-closed**:
  inability to prove non-broadening yields an `:expansion`, never a `:contraction`.
- **Query exception (ADR-054 §2):** any query-handling change that can **increase distinct crawlable
  canonical-URL multiplicity** is an `:expansion`, even though query never affects PRULE-021 admission —
  `retain_all` is the maximal multiplicity, an allowlist is ordered by retained-key-set inclusion, so
  `allowlist -> retain_all` and any widened key-set broaden; narrowing/equality/reorder do not.
- **Boundary (ADR-054 §3):** host/scheme/port beyond the verified boundary is a `:boundary_violation`
  (`cross_host_expansion` / `unsupported_source_scheme` / `port_out_of_boundary`), decided **before** and
  **outside** the fail-closed rescue so a boundary violation can never degrade to an approvable expansion.
- **Pure:** no persistence, outbound call, event, migration, or Source/Request transition; deterministic;
  no input mutation.

## Commit tranche (branch `tranche/S-06/S-06-002`, base `6e8413a`)

| Commit | Purpose |
| --- | --- |
| `7aa7a64` | S-06-002: Option-B classifier ruling (ADR-054); HD-S06-002-SCOPE-CLASSIFIER resolved (planning) |
| `c3aa509` | S-06-002: surface decomposition (ADR-055) — evidence the tranche breaches reviewability (planning) |
| `ff140a6` | S-06-002: Option-1 decomposition ruled (ADR-056); S-06 re-decomposed to six sub-tranches (planning) |
| `ff677f8` | S-06-002 (1/n): the `ScopeChangeClassification` classifier (Option B, pure) + 22 fixtures |
| `e8b6d60` | S-06-002 (2/n): defense-in-depth hardening (boundary outside fail-closed rescue) + test strengthenings |

Diff `6e8413a..e8b6d60`: the classifier (`app/workflows/wf004/scope_change_classification.rb`) + its spec,
plus governance records. **No `db/` change, no `app/models/` change, no command/table/event/store** — pure
classifier per the Option-1 decomposition. Comfortably within reviewability limits.

## Verification (exact results, at `e8b6d60`)

- Whole repository: **1264 examples, 0 failures** (24 classifier examples). Zeitwerk clean; Packwerk no
  offenses; Brakeman 0 warnings; bundler-audit no vulnerabilities. Architecture fitness green in-suite.
- `migration_safety_no_drift` / `runtime_role_and_rls`: not triggered — no `db/**`, `app/models/**` or
  infrastructure change (manifest path-selected). No `structure.sql` drift is possible.
- Rubocop: only `Layout/SpaceInsideArrayLiteralBrackets` — the accepted S-05 baseline idiom; not a
  mandatory-manifest gate.

## Independent review (ADR-026) — five separately-invoked adversarial lenses

| Lens | Verdict |
| --- | --- |
| Security / misclassification bypass | **PASS** — two differential fuzzers, ~22,000 :contraction verdicts, **0 missed broadenings**; witness-set complete |
| Contract correctness | **PASS** — brute-force oracle over **3,969 policy pairs**, 0 dangerous under- or over-classifications; matches ADR-054 exactly |
| Determinism / purity | **PASS** — no mutation (frozen inputs), deterministic (1000×), thread-safe (16×200 → 1), fail-closed only ever yields :expansion |
| Architecture / scope / frozen | **PASS** — pure classifier only; no pull-forward; consumes only S-06-001; Zeitwerk+Packwerk clean |
| Test quality | **PASS** — all mandated fixture categories covered; non-tautology proven by mutants (4/4 + 3/3 killed) |

**Zero confirmed-blocking findings.** One defense-in-depth point (flagged by the purity and contract
lenses) was applied (ADR-057): the boundary check now runs outside the fail-closed rescue, and two spec
assertions were tightened to pin their reason with exclude-narrowing and superset-allowlist fixtures added.

## Non-blocking observations recorded (not actioned — repair-only-confirmed-blocking)

- **(quality nicety)** A host trailing-dot (`host.`) classifies as `:boundary_violation` rather than
  in-boundary (over-strict / fail-safe; the command layer normalizes the host under `ascii-host-v1` before
  it reaches the classifier). Candidate normalization follow-up.
- **(test)** Additional nested include+exclude characterization fixtures could be added; behaviour is
  already correct and fuzzer-covered.
- **(governance)** ADR-054's Scope paragraph was annotated superseded-in-part by ADR-056 (the classifier
  ruling stands; only tranche placement was re-scoped by the Option-1 decomposition).

## What happens next

- **Owner acceptance-and-merge (human_gate_after):** review `tranche/S-06/S-06-002` and, if accepted,
  fast-forward merge it into `implementation/s01-registration-access` and add `S-06-002` to `completed_blocks`.
- **Do not begin S-06-003** (source_scope_change_requests + ProposeSourceScopeChange pending) until S-06-002
  is accepted (owner instruction). **No merge, no push, `main` untouched.** S-06-003..006 remain
  `human_gate_before`. The interim (a contraction remains pending until S-06-004) is fail-closed and is not
  final contract behaviour; no provisional alternative activation path exists.
