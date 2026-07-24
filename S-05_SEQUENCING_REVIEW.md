# S-05 Ownership Verification — Architecture & Sequencing Review

Status: **RATIFIED by owner 2026-07-24.** The F-01…F-04 foundation tranche (§6) is approved; DEF-1 and DEF-2 (§4) are resolved (see §7). Implementation resumes at **F-01**, not S-05. This is a specification/sequencing review, not a spec change; it exists to remove demonstrated ambiguities and an ordering defect surfaced during S-05 pre-implementation review (permitted under PROJECT_STATE Operating Constraints). No Volume I/II contract is altered here.

- Date: 2026-07-24 (reviewed and ratified same day)
- Branch: `implementation/s01-registration-access` (local; nothing pushed, no tags moved)
- Reviewer: implementation agent, at owner instruction ("review S-05/WF-003; stop on any ordering defect, primitive conflict, hidden coupling or contract ambiguity")
- Verdict: **CONFIRMED BLOCKED as a self-contained slice; RESOLVED by the ratified F-01…F-04 tranche below.** S-05 depends on four shared foundations that do not exist and that the specification assigned to *other* slices, it crosses a security-critical outbound-surface ordering defect, and its two governing Volume II sources named different command classes — all now resolved by owner decision (§7).

Built through **S-04** (M1 — Genesis Intake Complete). This review governs whether S-05 may begin.

---

## 1. Why S-05 is different

S-01→S-04 were self-contained: one aggregate, one command family, database-enforced invariants, no outbound I/O, no cryptography beyond hashing, no background execution. Each was production-reachable in a single reviewed slice.

S-05 is the platform's first slice that requires, all at once:
- **Outbound network I/O** — DNS TXT + HTTPS GET to a *customer-controlled* host to observe a challenge (a textbook SSRF surface).
- **Cryptography at rest** — envelope-encrypted challenge tokens with a versioned key and a timed cryptographic deletion.
- **A shared Evidence subsystem** — the first `verification_observation` Evidence producer.
- **Real background execution** — the 0/5/15/30/60/120/240/480/960/1380-minute observation slots, the 24-hour expiry, and the 60-second key destruction.

The product contract itself is *knowable* — the exact predicates (128-bit token, `f1-verification=<token>`, DNS/HTTP byte rules, slot schedule, reason codes) are fully specified in `SCORE_EVIDENCE_MODEL.md`, and OD-001 (the `dns_txt`/`http_file` method set) is ratified. The blockers are the foundations and two inconsistencies below, not the verification logic.

---

## 2. Missing foundations (assumed pre-existing; absent in code)

| # | Foundation S-05 consumes | Spec assigns ownership to | Present in codebase |
|---|---|---|---|
| a | SSRF-safe outbound DNS+HTTP adapter (`destination-safety-v1`) | **S-07** (SECURITY_PERFORMANCE.md L473: *"S-07 owns the only outbound surface in the product"*) | **Absent** — no HTTP/DNS gem; platform is inbound-only |
| b | Envelope encryption + versioned key store + cryptographic deletion | Foundation (014 SEC-REQ-019/020) + DataLifecycle `object_destroy` | **Absent** — only the RLS HMAC proof key (`f1_context_keys`), which is a MAC, not reusable |
| c | Evidence subsystem (`evidence` append-only table + producer contract) | **CAP-013 / S-09+** (Evidence bounded context; "there is no Evidence-creation command") | **Absent** — only reserved permission/action-kind literals |
| d | Background execution (Sidekiq wired to run; ScheduledAction workers executing) | Volume II Background Processing baseline | Gem + adapter present; **no initializer, no `sidekiq.yml`, no redis config, no worker runtime** |

The ScheduledAction catalogue already *reserves* the five S-05 action-kinds (`verification_observation_slot`, `verification_request_expire`, `verification_material_destroy`, plus scope/evidence kinds) and their queue/work-type mappings — so the timer vocabulary is provisioned; only the executors and handlers are missing.

---

## 3. Ordering defect (security-critical)

S-05 must make outbound calls to a host the customer controls. The ratified SSRF egress guard — `destination-safety-v1`, which resolves the host, rejects private/reserved/link-local/`169.254.169.254`/etc. address space, pins the address against DNS-rebinding, verifies the TLS peer, and re-resolves on every redirect — is **defined in and scoped to S-07**, and the same document states **S-07 is the only outbound surface**. `contracts/S-05.json` specifies verification's 10-second timeouts and redirect rejection but **no private-IP/egress/TLS guard**.

Consequence: implementing S-05 before its egress guard would either (a) ship an *unguarded* outbound surface on the platform's most security-sensitive flow, or (b) force this agent to invent an SSRF adapter that the spec says a later slice owns. Both are unacceptable. The egress guard must be a **shared foundation established before S-05**, not an S-07-internal detail.

---

## 4. Contract inconsistencies (owner reconciliation required)

**DEF-1 — Command decomposition disagreement.** The two governing Volume II sources name different command classes for WF-003:
- `contracts/S-05.json` (MTX-028): `CreateVerificationRequest`, `RetrievePendingChallenge`, `RequestOnDemandObservation`, `CancelVerificationRequest`, `RunAutomatedObservationSlot`, `ExpireVerificationRequest`, `FailVerificationRequest`.
- `APPLICATION_LAYER.md` (VII:108 routing registry): `IssueVerificationChallenge`, `ReserveVerificationAttempt`, `CompleteVerificationAttempt`, `CancelVerificationRequest`, `ExpireVerificationRequest`, `FailVerificationRequest`.

These are different names *and* a different decomposition (create+retrieve+on-demand+run-slot vs issue+reserve+complete). "Implement exactly as ratified" is undefined while both are ratified. **Owner must designate the canonical command set** (candidate owner decision).

**DEF-2 — Outbound-surface ownership.** "S-07 owns the only outbound surface" (SECURITY_PERFORMANCE.md L473) contradicts S-05 requiring outbound verification observation. **Owner must decide** whether the SSRF-safe outbound adapter is a shared foundation used by both S-05 (verify) and S-07 (crawl), or whether the slice ordering/ownership text is corrected (candidate owner decision).

Both are stale/ordering defects of the kind already precedented (cf. the `organization_inactive` 403/409 defect flagged in S-04): a later slice must not author or rewrite a shared primitive; the inconsistency is surfaced for reconciliation, not absorbed.

---

## 5. Downstream ownership entanglement

S-05's atomic success commit writes, together: the `verification_observation` Evidence (envelope owned by **CAP-013/S-09**), the `source-scope-interim-v1` policy (kind lifecycle owned by **S-06**), and schedules challenge cryptographic deletion (`object_destroy`, owned by **DataLifecycle**, S-23-area). S-05 is thus entangled with three downstream owners. The proposal below draws the minimum producer-side boundary S-05 needs, leaving each owner's later lifecycle intact.

---

## 6. Proposed foundation tranche (recommended)

A small, explicitly-ratified **Foundation tranche F-01…F-04**, each an independently reviewable, production-reachable step, *then* S-05. This makes the dependency graph explicit without silently spawning unratified product slices.

```
F-01  Outbound Transport (SSRF-safe)   → the shared destination-safety egress guard +
                                          DNS resolver + HTTPS client; the single, guarded
                                          outbound surface. Reused by S-05 (verify) and S-07 (crawl).
F-02  Envelope Encryption + Key Store  → versioned key ring, encrypt/decrypt, timed
                                          cryptographic deletion. Challenge tokens (S-05) are the
                                          first consumer; generalizes the session-token AES-256-GCM shape.
F-03  Evidence Producer Subsystem      → the append-only `evidence` table + producer append path.
                                          S-05 writes verification_observation Evidence; Evidence
                                          VALIDATION (heads/decisions) stays CAP-013/S-09.
F-04  Background Execution Wiring       → Sidekiq initializer + sidekiq.yml + redis/valkey config;
                                          the ScheduledAction worker runtime executing the
                                          verification_observe / expiry / object_destroy work-types.
─────────────────────────────────────────────────────────────────────
S-05  Ownership Verification           → verification tables, commands (per DEF-1 resolution),
                                          challenge issuance, the multi-root success commit,
                                          consuming F-01..F-04.
S-06  Source Discovery & Scope         → the source_scope policy lifecycle.
S-07  Crawl Execution                  → reuses F-01 (no second outbound surface).
```

Scope guards, held to the S-00 discipline ("only what the consuming slice needs"):
- **F-01** builds *only* the egress-guarded DNS/HTTP client S-05 (and S-07) need — not the crawl frontier, robots, or budget machinery (those stay S-07).
- **F-02** builds *only* envelope encryption + key versioning + destruction — not a general KMS.
- **F-03** builds *only* the Evidence envelope + append + the `verification_observation` producer contract — not validation decisions/heads (CAP-013/S-09) and not the scoring pipeline.
- **F-04** wires Sidekiq and the existing ScheduledAction worker to actually run — the timer/catalogue substrate already exists.

Alternative to a foundation tranche: **revise the slice ordering** so S-07's `destination-safety-v1`, the Evidence subsystem, and the encryption primitive are formally pulled ahead of S-05 in `SLICE_REGISTER.md` / `IMPLEMENTATION_BACKLOG.md`, with their ownership reassigned. Same effect; a spec-edit rather than a new tranche. Owner's preference.

---

## 7. Owner decisions — RATIFIED 2026-07-24 (DECISIONS.md ADR-024)

All five are resolved. Recorded in `DECISIONS.md` ADR-024 and the `specification/foundations/` contracts; the specification amendments are applied.

1. **Approach:** ✅ **Ratified the F-01…F-04 foundation tranche.** F-01 → F-02 → F-03 → F-04 → S-05. The next build is F-01, not S-05.
2. **DEF-1:** ✅ **APPLICATION_LAYER owns the canonical WF-003 command vocabulary** (`IssueVerificationChallenge`, `ReserveVerificationAttempt`, `CompleteVerificationAttempt`, `CancelVerificationRequest`, `ExpireVerificationRequest`, `FailVerificationRequest`; retrieval is query `QRY-021`). `contracts/S-05.json` reconciled.
3. **DEF-2:** ✅ **One shared outbound surface (F-01)**; S-05 and S-07 are consumers. "S-07 owns the only outbound surface" corrected in `SECURITY_PERFORMANCE.md` and `S-07.json`.
4. **Encryption key source:** ✅ **Vendor-neutral `KeyProvider`**, initially a platform-managed key ring from deployment secrets (session-key style); no cloud vendor hard-coded.
5. **Evidence boundary:** ✅ **S-05 (via F-03) creates the append-only Evidence store and produces `verification_observation`**; validation heads/decisions/adjudication/lifecycle stay CAP-013/S-09.

S-05 will proceed on ratified ground after F-01…F-04, with no invented infrastructure and no weakened slice.

---

## 8. What is NOT in question
- The verification *product* logic is fully specified (`SCORE_EVIDENCE_MODEL.md`, OD-001 ratified). Once the foundations exist and DEF-1/DEF-2 are settled, S-05 is implementable exactly as ratified.
- S-01→S-04 remain complete and green (678 examples). This review changes nothing already built.
- No mocks, shortcuts, or invented security primitives were introduced. Implementation stopped at the review boundary by design.
