# VIDET Brand Pack

Status: Application standard v1, 28 July 2026. `002 VISUAL_IDENTITY.md` governs the identity system; **this pack governs its application** — logo usage, colour-per-background, type, and per-medium specs. Rule zero: **every customer-facing surface conforms to this pack. No exceptions.** New artifacts pass §8 before they ship.

## 1. Logo system

Master vectors in `branding/logo/` (construction spec: `005 LOGO_PROMPTS.md` §2 — 24-unit grid, 3-unit stroke, bar 10:7 over chevron, one-stroke aperture gap, 90° apex):

| File | What | Use |
|---|---|---|
| `videt-mark.svg` | Petrol mark, transparent ground | Default logo everywhere on light grounds |
| `videt-mark-ink.svg` | Ink #1E2B28 mono | B&W documents, fax-grade print, engraving |
| `videt-mark-inverse.svg` | Chalk #F2F3EF | On petrol and dark grounds |
| `videt-seal.svg` | Mark in ruled ring | Favicon, stamps, "verified" states — max once per page |
| `videt-lockup.svg` / `-inverse` | Mark + VIDET wordmark | Headers, signatures, covers. Type is provisional stand-in (Helvetica Neue stack) until Founders Grotesk licence; then reset and outline |
| `videt-avatar.svg` | Chalk mark on petrol square | Social avatars, app icons |

**Rules:** clear space = ½ mark height on all sides, minimum. Minimum sizes: mark 16px / 5mm; seal 24px / 8mm; lockup 90px / 30mm wide. **Never:** stroke-outline versions (the mark is filled shapes only) · recolouring outside §2's matrix · ochre as mark colour · rotation, distortion, shadows, gradients, containers other than the seal ring · any generated raster in production (vectors only) · a chevron wider than the bar (that's a roof, not a benchmark).

## 2. Colour application matrix

Full token system in `002` §3–4. Which logo and text go on which ground:

| Ground | Logo variant | Headings | Body | Notes |
|---|---|---|---|---|
| Chalk `#F2F3EF` (default page) | Petrol mark | Petrol `#0E4553` or ink `#1E2B28` | Ink / ink-2 `#44534E` | The brand's home |
| Surface `#FAFAF7` (cards, PDF panels) | Petrol mark | Petrol / ink | Ink / ink-2 | |
| Wash `#E3EDEC` / Horizon `#E4EDF1` (bands) | Petrol mark | Ink | Ink-2 | |
| Petrol `#0E4553` (closing bands, cohort box, avatar) | **Chalk inverse** | Chalk `#F2F3EF` | Chalk at 85% opacity | Buttons on petrol: chalk ground, petrol text |
| Dark product surfaces `#101A18`/`#172420` | **Chalk inverse** | Dark ink `#E7EBE4` | `#A3B0A8` | Product only — marketing never runs dark (002 §3 mode policy) |
| White paper / mono print | Ink mark (or 100K black) | Ink | Ink | When petrol can't be guaranteed |
| Accent budget | — | — | — | Petrol ≤10% of any surface; ochre `#C27E3A` graphics-only, `#875213` for ochre text; ochre never the mark |

## 3. Typography

| Role | Licensed (pending) | Stand-in — web CSS | Stand-in — PDF/docs |
|---|---|---|---|
| Display & wordmark | Founders Grotesk (Klim), Medium | `"Helvetica Neue", "Archivo", Arial, sans-serif` | Helvetica (core) |
| Text/UI | Untitled Sans (Klim) | same stack | Helvetica |
| Data/mono | Founders Grotesk Mono (Klim) | `"SF Mono", ui-monospace, "Cascadia Mono", Menlo, Consolas, "Liberation Mono", monospace` | Courier (avoid; prefer figures in Helvetica with tabular layout) |

Scale 1.25 on 4px baseline: 13/16/20/25/31/39/49, hero 61/76. Two weights only (Regular, Medium). **Register law:** any numeral that means data is set in the mono with tabular figures — always. Sentence case everywhere including buttons; no exclamation marks; ALL-CAPS only as letterspaced mono labels.

## 4. Per-medium specifications

**4.1 Web (marketing).** Light-committed in every viewer theme. Copy the token block from `003 HOMEPAGE_MOCKUP.html` `:root` verbatim — it is the reference implementation. Nav: mark (22px) + VIDET at 21px/500. Buttons: primary petrol/white, secondary 1px `--ink-3` border, radius 2px, sentence case, action-specific labels. Favicon: `videt-seal.svg` (petrol; 32/16px). OG/social share image: lockup centred on chalk, 1200×630. Motion per 002 §7 (instrument motion; reduced-motion respected).

**4.2 Customer-facing PDF/print.** A4, 16mm margins, chalk ground. Header: filled mark (≈5.5mm tall) + VIDET wordmark, `videt.ai` right-aligned in ink-3; hairline `#D6DAD2` rule beneath. Petrol section headings; ochre-deep `#875213` for small accent labels; petrol solid boxes carry chalk text. Footer: trust line + disclaimers per claim discipline. Reference implementation: `004 FOUNDING_COHORT_OFFER.pdf` (generator script archived in session scratchpad; regenerate via fpdf2 with filled-shape mark, never line-drawn).

**4.3 Assessment reports.** Follow `operations/ASSESSMENT_DELIVERY_GUIDE.md` Part 9 sections, in this pack's colours/type: header per 4.2, all counts/dates/IDs in mono, evidence-cell styling per 002 §9.4, seal used once — beside the "screenshot-backed and dated" declaration. Every report footer: "This is a measurement of AI assistant behaviour, not professional advice." + evidence line.

**4.4 Email.** Signature: lockup (PNG @2x from `videt-lockup.svg`, ~180px wide) or text-only fallback "Lee Powell · VIDET · videt.ai" in default type. No banners, no quotes, no colours beyond the lockup.

**4.5 Social.** Avatar: `videt-avatar.svg`. Banners: lockup on chalk, generous clear space. Post graphics inherit §2 matrix; counts-not-scores applies to any number shown.

**4.6 Slides (when needed).** Chalk ground, ink text, petrol headings, mark top-left at minimum size, one idea per slide, numerals in mono.

## 5. Voice quick-card (binding; full rules `001` §5 and §8)

**Tagline: "Become the answer."** — always with the full stop, always sentence case, never reworded, never translated into an influence claim (fixed reading, 001 §8: *become the best-evidenced candidate for the answer — you earn the answer; VIDET measures whether you have*). It closes pages and decks; in lockups it may sit beneath the wordmark in ink-2 at ~40% of cap height. Support lines ("Know whether AI sees your business", "See what AI sees" — the latter reserved until measurement is live) are descriptors, not the tagline.


It's about them — "you" outnumbers VIDET · counts, never scores; every number carries its N and date · no guarantees of mention, position or timing · never SEO/GEO/"AI visibility platform" · providers named only as surfaces people ask · calm, not fear — the demonstration does the persuading · "around 22" in writing, bare "22" spoken · "this August", never "this month" · delivery clock in writing always "of payment" · Australian English · "findings" is the concierge-report term; the capitalised "Issue" appears only inside the branded promise line ("No evidence, no Issue.") and platform-era copy · machine statements are never republished as standalone claims — white-hat framing uses the sanctioned form "better evidence for the machines to check".

## 6. Asset inventory (customer-facing)

`branding/logo/*` (7 vectors) · `003 HOMEPAGE_MOCKUP.html` + published artifact (reference web implementation) · `004 FOUNDING_COHORT_OFFER.pdf` (reference document implementation) · assessment report template (per guide Part 9 + §4.3) · outreach/demo scripts (`investor/30_DAY_REVENUE_PLAN.md` Appendices F–G).

## 7. Governance

Identity changes go through `002` (and ADR where it touches ratified matter) — this pack then updates in lockstep. Generated imagery is concept-exploration only; production is vectors from `branding/logo/`. The Founders Grotesk licence purchase converts every provisional-type surface in one pass (lockup reset + outline; web stack front-loaded with the licensed face).

## 8. Conformance checklist (run before anything customer-facing ships)

1. Logo: correct variant for the ground (§2), filled master geometry, clear space and minimum size respected, no stroke versions
2. Colours: only system hexes; petrol ≤10%; ochre rules respected; light-committed on marketing surfaces
3. Type: stand-in stacks exactly as §3; numerals-in-mono; sentence case; two weights
4. Copy: §5 quick-card passes line-by-line; claim-discipline table (`001` §8) consulted for any new claim
5. Legal: disclaimers present (reports/regulated verticals); no third-party machine statements republished
6. File hygiene: vectors from `branding/logo/`, no ad-hoc redraws; new assets added to §6
