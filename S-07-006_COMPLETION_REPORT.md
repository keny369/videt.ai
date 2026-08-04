# S-07-006 — Sitemap Discovery, Deterministic Candidate Ordering, Frontier Admission

Accepted 2026-07-29 under standing delegation ADR-061. Governance record: **ADR-081**.
Review discipline: **ADR-080** — no acceptance until every ADR-026 lens has reported.

## What this tranche owns

Sitemap resolution for one `(crawl, canonical_host)`, end to end:

- **The candidate set (:450).** Robots' `Sitemap:` declarations — stored verbatim and unfiltered by
  S-07-005 — filtered here to same-host, in-scope, canonicalized https URLs, plus
  `https://<canonical_host>/sitemap.xml`. What a site DECLARED and what this platform ADMITTED stay
  two separate, auditable facts.
- **The order (:454).** `SitemapCandidates` — a selection over a SET, not over an arrival sequence,
  so a late-arriving lower-ordered candidate displaces a higher one rather than being dropped for
  arriving late.
- **The traversal.** Breadth-first across sitemap-index edges to the ratified depth, every fetch
  passing the same host gate and the same execution-time `FetchAuthorization` a content fetch does.
- **Frontier admission.** Content URLs at depth 1 (:440), entry tuple `('', 0)` per :454, with the
  discovering sitemap URL carried on the OCCURRENCE where the provenance survives.
- **The outcome (:450).** `succeeded` / `absent` / `unavailable`, write-once, with every skipped or
  failed candidate recorded under its reason and the LIMIT subset separated.

## The security boundary

`SitemapParser` is the platform's boundary against untrusted XML. The review found that its stated
protection did not exist: `Nokogiri::XML::SAX::Document` has no `internal_subset`,
`external_subset` or `start_document_type` callback, so three of its four abort guards were dead
code in every encoding — and the one surviving defence, a raw-byte scan, is defeated by encoding
confusion, because libxml2 auto-detects UTF-16/UTF-32 from the leading bytes with no BOM and
NUL-interleaved ASCII is itself valid UTF-8.

It is now three layered defences:

1. **Encoding gate.** :450 accepts UTF-8 XML only, enforced as a security control: foreign BOM,
   declared non-UTF-8 encoding, invalid UTF-8, or any NUL byte is refused.
2. **Pre-parse byte scan.** Authoritative only because defence 1 guarantees it reads the bytes
   libxml2 will read.
3. **Prolog inspection.** `Nokogiri::XML::Reader` in `NONET` mode, pulled only to the root element,
   reporting a document-type node using libxml2's own lexer — the independent mechanism the dead
   callbacks were supposed to be.

The media-type allowlist fails CLOSED (an absent `Content-Type` is not one of the three ratified
names), and `<loc>` routing tests its immediate parent, so a document cannot choose which of two
code paths its URLs enter.

## Limits, as ratified

- **50 sitemap documents PER RUN** over distinct canonical URLs **attempted** — reserved atomically
  from `crawls.limit_counters` before each attempt. A per-host counter would have let ten hosts
  fetch ten times the maximum; counting successes would have let one index naming dead children
  fetch them all without moving the counter.
- **:454 retention over the whole candidate set**, index children included.
- **Index depth 3**, over-depth children recorded rather than followed.
- **:444 retries** — 30s/120s with `Retry-After`, shared in `Wf005::FetchRetryPolicy`.
- **Per fetch** — hard request timeout, 10 MiB byte cap, hard redirect budget, `F1DiscoverabilityBot`.
  All four are asserted on the REQUEST; the stub used to discard them.

## Concurrency

Discovery for a host is **claimed**: the `pending -> in_progress` transition is version-guarded and
mints a claim token, a losing worker stands down instead of duplicating the traversal, only the
token holder may write the write-once terminal outcome, and a lost attempt may be taken over after
a stale window with the token rotated.

The lease statements were rewritten as correlated sub-selects over the target row's own column. A
`WITH` clause is evaluated once from the statement snapshot and is **not** recomputed by
EvalPlanQual, so `release_slot` was writing a lease array assembled before a concurrent claim —
destroying the lease of a worker that was connecting, and breaching a nonexceedable ceiling. This
was verified independently before and after the change.

## Verification

| Gate | Result |
| --- | --- |
| Complete suite | **1678 examples, 0 failures** |
| Brakeman (`-z`) | clean |
| Packwerk | no offenses, no stale violations |
| Zeitwerk | all is good |
| bundler-audit | no vulnerabilities |
| Architecture fitness | **31 examples, 0 failures** |
| `verify_runtime` | OK as `f1_web`, 15 checks, RLS intact |
| Schema by structure load (ADR-129) | dump **byte-identical** to committed `structure.sql` |
| Migration round-trip | `20260727120220/230/240` down and up, no residue |

Every fix in this tranche was **mutation-checked**: reverted one at a time, with the matching test
required to fail. One test did not discriminate and was rewritten until it asserted the property it
claimed.

## Carried forward

- **FU-8** — the `DiscoverSitemaps`/`Traversal` seam is inverted and `Traversal` has no unit test.
  Accepted backlog; not an S-07-007 dependency.
- **FU-9** — no scheduler re-entry after sustained host-gate contention. Mitigated (the gate now
  reports the real remaining wait), not closed. **S-07-008 must provide the re-entry**; if it does
  not, this reopens S-07-006.
- **Specification reconciliation** — `SEARCH_CRAWL_RETRIEVAL.md` named "Nokogiri SAX in `NONET`
  mode", a configuration the SAX parser context cannot express. The requirement is unchanged and
  more strongly satisfied; the prose now names the mechanism that delivers it. Volume I untouched.
