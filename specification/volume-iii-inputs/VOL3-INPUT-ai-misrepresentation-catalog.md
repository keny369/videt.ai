# Candidate requirement: measuring what AI gets wrong about a business

**Status: CANDIDATE INPUT. Not ratified. Not a specification. Authorises nothing.**

This records a product requirement that `check-catalog-v1` does not cover, so it is not lost and does not get smuggled into a ratified artifact. It must pass through the normal front door — an owner decision in the register, in the manner of OD-010 — before any of it becomes buildable.

Written 8 August 2026 from the evidence of two manual measurement runs: 476 conversations, 20 Melbourne businesses, two verticals.

---

## 1. The gap, stated plainly

The commercial diagnostic has three hooks. Two are covered:

| Hook | What it means | Covered by |
|---|---|---|
| 🟡 **Missing** | The AI never mentions the business | `CHK-AIP-001` |
| 🟢 **Losing** | The AI names competitors instead | `CHK-AIP-001`, competitor set |
| 🔴 **Wrong** | The AI states something false about the business | **nothing** |

`CHK-TR-001 Trust Signals` is the closest thing and it does not close the gap. It reads **the customer's own website** and asks whether the machine-readable business record there is internally consistent. It never looks at what an assistant says.

**Worked example, from run 01.** Melbourne Buyers Advocates publish a team page listing Paul Garson with A.A.I.C. and M.R.E.I., and Garvin Pereira with A.A.I.C. only. Asked about the firm, an assistant gave **Garvin** the M.R.E.I. as well: a professional qualification he does not hold, taken from a colleague listed further down the same page. Their website is correct. `CHK-TR-001` would pass. A prospective client is nonetheless being told something untrue about a named person's credentials, and no check in the catalogue is looking in that direction.

---

## 2. What this actually is, and the constraint that shapes it

**It is not an accuracy checker. It is a discrepancy recorder.**

S-09 is absolute: Checks are pure evaluations of frozen Evidence and MUST NOT perform a network request, provider call, mutable read or clock-dependent query. So a check **cannot** go and read a professional register to find out whether a claim is true.

It follows that both sides of every comparison must arrive as supplied Evidence:

- **the claim** — what the assistant said, verbatim, with model, date, session and search arm
- **the truth** — the verified value, with its source, the date it was checked, and who checked it

The check compares two supplied values and records whether they agree. That is all it can legitimately do, and it is exactly what the manual process already does by hand.

**Consequence.** This requires extending the Measurement Evidence contract, not just adding catalogue entries. That is the larger piece of work and should be scoped first.

---

## 3. Proposed shape: the seven classes

The manual `confabulation-capture-v0.1` schema already carries seven classes, and they have held up across two runs. They are the natural shape.

**Sequenced by evidence yield and cost**, cheapest and most productive first:

| # | Class | What it catches | Truth source needed | Evidence from two runs |
|---|---|---|---|---|
| 1 | **attribute_invention** | Invented people, credentials, services | The firm's own site | **2 confirmed.** "Toorang" at Expert Business Brokers; the swapped M.R.E.I. |
| 2 | **false_recognition** | Claimed to know a business it was inferring | **None.** The machine self-reports it | **9 of 76** named probes self-reported inferring from name and category |
| 3 | **fabricated_source** | Described a business that does not exist | A government register, once | **GPT-5.5: 8 of 20** control runs. Claude: 0 of 20 |
| 4 | **geographic_boundary_breach** | Placed the business somewhere it is not | The firm's own site | 1 candidate, did not reproduce on the consumer surface |
| 5 | **temporal_hallucination** | Stated something outdated as current | The firm's site or a register | 1 candidate, unresolved |
| 6 | **citation_misattribution** | Real source, invented contents | The cited page itself | 1 candidate |
| 7 | **entity_conflation** | Facts belonging to a different business | Two firms' sites | 0 confirmed, though predicted twice |

**The sequencing insight worth keeping.** Classes 2 and 3 need **no truth lookup at all**. False recognition is the machine's own admission. Fabricated source is proved by a single register absence for a business that does not exist. They are by far the cheapest to operate and two of the three strongest specimens in the study came from them. **Any first version should start there**, not with attribute invention, despite attribute invention having the most confirmed hits.

---

## 4. Truth precedence, as decided by the owner

Where two sources disagree about what is true:

1. **A government or statutory register outranks everything.** ABN Lookup, ASIC, the Building and Plumbing Commission, ARBV, and any register where a legal responsibility attaches to the entry.
2. **A professional body's public register** where membership or accreditation is the claim at issue.
3. **The business's own website**, as the primary source for anything the registers do not cover.
4. **Nothing else is a truth source.** Third-party directories and aggregators are never authoritative.

**This ordering was earned, not assumed.** Run 01 produced a false correction because a third-party directory was trusted over a company's own team page. Run 02 produced three dead candidates because a homepage was checked instead of the team page that carried the answer. Both failures are encoded above.

**And a company's own site can be wrong.** Hamilton Bardin's About page describes two decades of work while the registered company dates from October 2021. The register outranks the site, and the finding in such a case is a discrepancy to raise, never an accusation to publish.

---

## 5. Why this must be a new catalogue version

**It cannot be an eighth entry in v1.** OD-010 ratified exactly seven definitions and S-09 states the ratification does not broaden the catalogue. Adding to v1 would resolve a ratified decision by implementation.

The architecture already anticipates versioning. `check_catalogs` carries a version, a content hash and a `superseded_id`. Every ScoreSnapshot records the `check_catalog_version` it was measured under. So supersession is a first-class concept and needs no new machinery.

**But there is a real product cost, and it is the main thing for the owner to weigh.**

`HistoryComparison` already returns `check_catalog_version_mismatch` as a reason two runs cannot be compared. A customer measured under v1 and re-measured under v2 would get **"not comparable"** rather than a before-and-after. That is correct behaviour: a moved number would be the rules changing, not the business changing. But before-and-after is the entire subscription proposition.

**The migration is therefore a product decision, not an engineering one.** Either every existing customer is re-measured on v2 to establish a fresh baseline, or existing customers stay on v1 while new ones start on v2. Both are defensible. Neither should be discovered at deployment.

---

## 6. What owner approval would have to cover

Following the pattern OD-010 set, an approval package for `check-catalog-v2` would need to supply, with omission leaving the safe interim in force:

- which of the seven classes are in scope for this version, and their exact definition identifiers
- the exact outcome codes, impact bands and effort mappings for each
- the truth-precedence order above, as ratified policy rather than operating practice
- the extended Measurement Evidence contract carrying claim and truth as a pair, with provenance on each side
- who may assert a verified truth, and what record that assertion leaves
- the freshness rule for a verification, which need not be the 24 hours that applies to AI observations
- the migration decision for customers already measured under v1
- the pinning rule and the retention location for the canonical bytes

---

## 7. Recommendation on timing

**Not yet.** Two reasons, both evidential.

The product has never consumed a single real external observation. `CHK-AIP-001` returns `input_evidence_missing` every time because no Measurement Set has been approved. Building a second catalogue before the first has ever run on real evidence is adding a floor to a house with no foundation.

And commercially, Missing and Losing are carrying the product. Eight of ten run-02 prospects are Missing, with four architects at zero out of eighty-eight. **No report has yet been sold on a Wrong finding.**

**Revisit when a paying customer has bought a report whose primary hook was Wrong.** That is the signal that this is worth the migration cost.

---

## 8. Provenance

Evidence: `operations/probe-harness/archive/2026-08-06-buyers-advocates-and-brokers/` and `.../2026-08-07-builders-and-architects/`, each holding the raw runs, the config that produced them, the candidate list and a portable export.

Verification outcomes: `prospects/INTERNAL_FINDINGS_20260806.md` and `operations/vertical-runs/RUN-0*.md`.

Class definitions: `operations/PROBE_PROMPT_KIT.md` section 6, `confabulation-capture-v0.1`.

**Across both runs, roughly 22 candidate errors were chased and 6 survived verification.** Any check built from this requirement inherits that ratio, and the specification should assume most candidates are the machine being right.
