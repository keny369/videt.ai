# Foundation Dependency Graph

Status: **Reference map (ADR-024).** One page: what sits on what. Descriptive, not authoritative — the canonical contracts are the slice register, the foundation contracts, and Volume I/II. If this map and a ratified contract disagree, the contract wins and this map is corrected.

Read bottom-up: every layer depends only on the layers beneath it. A layer is built only after its substrate is built.

```
                        ┌─────────────────────────────┐
   FUTURE  (Videt)      │        Videt Platform        │   brand + product surface
   ────────────────     │  Commercial Intelligence     │   compounding, evidence-backed
   conceptual, not      │  Intervention Learning       │   observe → intervene → measure → learn
   Genesis requirements │  Perception (per provider)   │
                        │  Observation Engine          │
                        └──────────────┬──────────────┘
                                       │
   ══════════════════════════ GENESIS ══════════════════════════
                                       │
   PIPELINE (future        Assessment / Scoring (S-13)        each consumes the previous
   slices, ratified        Inspection & AI Analysis (S-09/10)
   but not built)          Parsing (S-08)
                           Crawl Execution (S-07) ───────────┐ consumes F-01
                           Source Discovery & Scope (S-06)   │
                                       │                     │
   VERIFICATION (next      Ownership Verification (S-05) ────┼─ consumes F-01, F-02, F-03, F-04
   product slice)          proposed → verified               │
                                       │                     │
   ───────────────────────────────────┼─────────────────────┘
   PLATFORM FOUNDATIONS    ┌───────────┴───────────────────────────────┐
   (ratified ADR-024;      │  F-04 Background Execution                 │  durable, idempotent, leased
    NOT yet built —        │  F-03 Evidence Production (append-only)    │  producer; eval = S-09/CAP-013
    Phase II, next)        │  F-02 Envelope Encryption (KeyProvider)    │  vendor-neutral, cryptographic erasure
                           │  F-01 Shared Outbound Transport            │  ONE guarded egress; S-05 + S-07 + future
                           └───────────┬───────────────────────────────┘
   ───────────────────────────────────┼───────────────────────────────
   GENESIS DOMAIN          Source (S-04) ✓   Project (S-03 create ✓ / activate ⛔ gated on active Source)
   (built ✓)               Organization + BillingEntity + Policies (S-02) ✓
                           Account · Session · Invitation · Role Assignment (S-01/S-013) ✓
                                       │
   GENESIS KERNEL          Authorization (Permission Baseline) · Command/Result ledger
   (built ✓)               Event registry (canonical envelopes, DB-recomputed digests)
                           Audit registry · Idempotency · ScheduledAction durable timers
                           Service identities · Proved tenant context (forced RLS)
                                       │
   SUBSTRATE (built ✓)     PostgreSQL 17  (RLS, SECURITY DEFINER, pgcrypto, structure.sql)
```

## Legend

- **✓ built** — implemented, tested, green (S-01→S-04; 678 examples).
- **ratified, not built** — contracted and sequenced, no code yet (F-01→F-04, then S-05 onward).
- **⛔ gated** — cannot proceed until its prerequisite exists (Project activation needs an active Source; S-05 needs F-01→F-04).
- **future / conceptual** — Videt platform direction (`branding/future/`); NOT a current Genesis requirement, never implemented as current behaviour.

## The one rule this map encodes

Each foundation is built **once**, correctly, before the capabilities that depend on it — so every later slice gets **simpler**, not more complex. F-01 in particular is the single shared outbound surface for verification, crawl, robots, sitemap, and every future provider/observation/notification consumer: there is never a second egress path.

## Build order (ADR-024)

```
F-01 → F-02 → F-03 → F-04 → S-05 → S-06 → S-03 ActivateProject → S-07 → S-08 → …
```
