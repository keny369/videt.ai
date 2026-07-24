# Videt Visual Identity

Status: Working identity standard for all Videt marketing and product surfaces. Marketing document — does not override the Product Architecture Manual. Every color token in this document was verified by computation (WCAG contrast; six-check chart-palette validation including color-vision-deficiency simulation); the validation record is in §11.

Selection method: four creative territories were developed independently and scored by a three-lens panel (brand strategy, design craft, pragmatics). The winning direction is recorded here with graft improvements from the runners-up; rejected directions and reasons are recorded in §12.

## 1. Concept — "Meridian — The Observatory"

Evolved 2026-07-23 with the vision overhaul (VISION-001, Commercial Discoverability Observatory). The lineage is continuous and deliberate: first-order surveys were run from meridian observatories — instruments that watched the sky in order to fix, exactly, where things stood on the ground. That is now literally what Videt does: it watches machine perception in order to fix where a business truly stands.

The identity keeps the graphic discipline of the survey — graticule grids, benchmark marks, grid-reference evidence IDs — and gains the observatory's second register: **observation arcs** (the sweep of repeated watching) and the **two-pictures mirror** (Reality beside Perception, the gap annotated). A benchmark remains exactly what Videt sells: a permanent, inspectable mark that says *this value was measured, here, and you can check it* — and the observatory adds the promise that the watching never stops and the learning compounds.

Chalky mineral paper in daylight — this is a daytime observatory; the brand watches machines, not stars, and marketing surfaces stay light-committed (§3). Deep petrol ink, ochre annotation, no gradients.

Calm and exact; authority is implied, never performed. Become the answer, and hold the coordinates to prove it.

Why this direction: the metaphor is the product argument (observe → measure → benchmark → learn), it restates the category story — your business exists twice, and the gap is measurable — without ever illustrating "AI", it is prospective (an observatory watches so you can act), and its signature devices are systemic behaviours a template cannot fake.

## 2. Design Tenets

1. **Evidence is visible.** The product's promise — every score backed by inspectable evidence — is the most-repeated visual unit (§9.4, the evidence cell).
2. **Nothing decorative, everything inspectable.** If an element carries no information, remove it.
3. **Instrument, not theatre.** Restraint in color, motion and elevation. The reader supplies the drama.
4. **Computed, not eyeballed.** Any change to colour tokens re-runs the validation in §11 before merge.
5. **Never the template.** The prohibitions in §10 are binding law, not preference.
6. **Full volume, quiet claims.** Restraint governs claims and clutter, never presence (owner direction, 2026-07-21: sterile marketing pages are rejected). The drama lives in scale contrast in type, the ochre contour layer at strength, instrument motion, and demonstrated product moments — the page must grab an SMB owner's eye while the copy stays evidence-calm.

## 3. Colour — Core Tokens

All ratios are WCAG contrast, independently computed (§11).

### Light mode

| Token | Hex | Ratio on ground / surface | Use |
|---|---|---|---|
| `ground` | `#F2F3EF` | — | Page background. Cool mineral chalk — deliberately not a warm cream. |
| `surface` | `#FAFAF7` | — | Cards, panels, chart surface |
| `ink` | `#1E2B28` | 13.16 / 14.03 | Primary text |
| `ink-secondary` | `#44534E` | 7.27 / 7.74 | Secondary text |
| `ink-muted` | `#5D6B65` | 5.02 / 5.35 | Captions, metadata (AA) |
| `line` | `#D6DAD2` | — | Hairline rules, borders |
| `accent` | `#0E4553` | 9.45 as text; white-on-accent 10.53 | Deep petrol. Interactive chrome only (§5.3) |
| `accent-hover` | `#0A3644` | white-on 12.93 | Hover/active |
| `accent-wash` | `#E3EDEC` | — | Selected states, subtle emphasis backgrounds |
| `horizon` | `#E4EDF1` | ink on it 12.35; petrol on it 8.86 | Observatory-air band wash — cool daylight sections; added 2026-07-23 |
| `ochre` | `#C27E3A` | 2.97 — graphics only | Contours, arcs, annotation strokes. **Never text below 24px** |
| `ochre-deep` | `#875213` | 5.80 / 6.19; on horizon 5.24 | Text-safe Intelligence accent: eyebrows, labels, annotations at text sizes; added 2026-07-23 (fixes the small-ochre-text contrast defect) |

### Mode policy

Marketing surfaces are **light-committed**: the mineral-chalk world is the brand's default face in every viewer theme — the service takes weight off the customer, and the page should feel like it (owner direction, 2026-07-21). The dark palette below remains validated and reserved for product surfaces where viewers choose it (dashboards, code, long working sessions).

### Dark mode (selected, not inverted — product surfaces only)

| Token | Hex | Ratio on ground / surface | Use |
|---|---|---|---|
| `ground` | `#101A18` | — | Green-cast near-black — not slate-900 |
| `surface` | `#172420` | — | Cards, panels, chart surface |
| `ink` | `#E7EBE4` | 14.71 / 13.29 | Primary text |
| `ink-secondary` | `#A3B0A8` | 7.89 / 7.13 | Secondary text |
| `line` | `#2A3733` | — | Hairline rules |
| `accent` | `#79B7BF` | 7.89 / 7.13 as text; dark-ink-on-accent 7.89 | Desaturated mineral petrol |

### Status (reserved — never used as chart series colours)

| State | Light (ratio on `#F2F3EF`) | Dark (ratio on `#172420` / `#101A18`) |
|---|---|---|
| Good | `#2C7A4B` (4.72) | `#3E9B63` (4.64 / 5.13) |
| Warning | `#8A5E06` (5.11) | `#B77E0C` (4.58 / 5.07) |
| Serious | `#A32C22` (6.41) | `#D46B62` (4.64 / 5.14) |
| Info | `#275D8C` (6.22) | `#518EC3` (4.59 / 5.08) |

Rules: status colours ship with icon + label, never colour alone. Warning bronze is dark for an "amber"; small badges pair it with a wash background and icon. The dark variants are first-class tokens shipped in the initial token file — reusing light hexes on dark ground fails contrast and is prohibited.

### Accent derivation note

`#0E4553` sits deliberately greener and darker than any Tailwind step (nearest: cyan-900 `#164E63` at ΔE76 ≈ 6 — clearly distinct, documented here to preempt the comparison). No token in this system matches or near-matches a Tailwind default; every value derives from the survey-instrument references (mineral chalk, petrol ink, ochre contour, madder, olive).

### The three-graph mapping (vision semantics, added 2026-07-23)

The palette carries the vision's architecture (VISION-001, ADR-012). One hue family per graph, everywhere — marketing, product, diagrams:

| Graph | Hue family | Rationale |
|---|---|---|
| **Reality** — what is objectively true | Ink (`#1E2B28`) on chalk | Truth is written in ink; it changes only when the business changes |
| **Perception** — what each machine believes | Petrol family: `#00889E` for "the machine's view", categorical slots for per-provider series | Perception is plural and provider-specific — the categorical set exists for exactly this |
| **Intelligence** — what has been learned | Ochre family (`#C27E3A` strokes, `#875213` text) | The annotation layer: contours, arcs, learned marks drawn over the record — knowledge compounds on top of evidence |

This mapping is binding: never draw Reality in ochre or Intelligence in petrol. The gap between Reality and Perception — the product's subject — is always shown as ochre annotation on the Perception side.

## 4. Colour — Data Visualisation

Validated with the six-check palette validator in both modes (§11).

### Categorical — six hues, FIXED order, never cycled

| Slot | Hex | Assignment convention |
|---|---|---|
| 1 | `#00889E` | The customer ("you") — petrol series hue |
| 2 | `#C27E3A` | Reference/benchmark context — ochre |
| 3 | `#4E6DB5` | Slate blue |
| 4 | `#B5504A` | Madder |
| 5 | `#8E9430` | Olive |
| 6 | `#8064B2` | Muted violet (chart-only; never an identity colour) |

- Worst adjacent CVD separation: ΔE 8.9 (deutan) — above the ≥8 floor. Normal-vision floor 19.4. All slots ≥3:1 on both chart surfaces.
- The order is frozen in design tokens as an ordered array. Chart libraries must not cycle, re-sort or generate colours; a re-ordered palette silently voids the CVD guarantee. The validator is to be committed to this repository and wired into CI so it runs against live token values (§13, item 5).
- A seventh series is never a new hue: fold into "Other", facet, or small multiples.
- Colour follows the entity, never its rank; filters must not repaint surviving series.
- Pure accent `#0E4553` is reserved for interactive chrome; series marks use slot 1 `#00889E` — "clickable" and "series A" must never blur.

### Sequential (magnitude) — single petrol hue, validated ordinal ramps

- Light mode (pale → dark): `#8FB6BA` → `#5F949C` → `#35707D` → `#0E4553`
- Dark mode (dim → bright): `#3A5F66` → `#55858E` → `#79ABB4` → `#A3D2D8`

### Diverging (polarity) — two poles, neutral midpoint

`#A85B2B` (warm) ← `#B4B6B4` (neutral gray) → `#1E6A7A` (cool). Never a hue at the midpoint.

### Chart conduct

Thin marks; 2px lines; ≥8px markers; 2px surface gaps between fills; legends present for ≥2 series with selective direct labels; grid and axes recessive hairlines; values and labels always in ink tokens, never in series colour; no gradients, no dual axes. Score visualizations must not exaggerate minor changes (004 DESIGN_PRINCIPLES, Principle 7).

## 5. Typography

Single commercial foundry (Klim Type Foundry, Wellington NZ) for one coherent voice across display, text and data; complete open-source fallback stack for zero-cost reproduction. None of the faces below — commercial or fallback — appears on the prohibited list in §10.

| Role | Face | License | Fallback (SIL OFL) | Use |
|---|---|---|---|---|
| Display | **Founders Grotesk** | Klim commercial, desktop + web | Archivo (Omnibus-Type) | Headlines, section titles, hero score numerals, wordmark lockup |
| Text | **Untitled Sans** | Klim commercial | Public Sans (USWDS) | Body, UI labels, long-form; deliberately plain by design |
| Data | **Founders Grotesk Mono** | Klim commercial | IBM Plex Mono (IBM/Bold Monday) | Scores, evidence IDs, timestamps, API output, tables |

**The register law (binding):** a numeral that means data is never set in the text face. Every measured value — scores, deltas, counts, timestamps — is set in the mono with tabular figures. This is a lintable convention (mono class required on all measured values), and it makes "inspectable evidence" a typographic behaviour.

Scale: 1.25 ratio on a 4px baseline — 13 / 16 / 20 / 25 / 31 / 39 / 49px, hero numerals 61/76px. Two weights per family (Regular, Medium); hierarchy comes from size, case and letterspaced mono small-caps labels, never from weight soup. Reading measure caps near 72 characters.

## 6. Shape, Space, Elevation

- Radii: 0px on tables, plots and tags; 2px on inputs and buttons; 4px maximum on cards. Nothing rounder, ever.
- Elevation is tone plus hairline rules, not blur: ground → surface steps bounded by 1px `line` rules; overlays may carry one 0–1px hard-edged shadow. No glassmorphism, no glow.
- Spacing: 4px base grid; generous macro margins around dense, tightly set data blocks — the survey-document pattern of airy sheet, packed measurement block.
- Framing device: fine crop-mark corner ticks (3px strokes) may replace full borders on sections — the plate-margin signature.

## 7. Motion

Instrument motion, not theatre: 120–240ms, ease-out only. No bounce, spring, parallax, pulse or glow. Lines and contours draw in like a plotter pen (stroke-dashoffset, left to right). Score numerals tick to their final value in tabular mono — fast approach, no overshoot, never slot-machine spinning. Hover states swap tone in ≤80ms.

## 8. Voice In Type

The identity carries the brand personality (calm, authoritative, understated — `000 STRATEGY_BRIEF.md`). Sentence case everywhere including headlines and buttons; no exclamation marks; no gradient text; no ALL-CAPS except letterspaced mono small-caps labels.

## 9. Graphic Language

Three cartographic layers plus the canonical component:

1. **Graticule** — a fine 1px coordinate grid with margin ticks, printed at 4–6% ink opacity on large surfaces. The surveyed substrate.
2. **Contour fields** — generated from the customer's actual score topography, drawn as 0.75px ochre `#C27E3A` lines with inline mono labels breaking the line exactly as elevations do on a map. Data as landscape, never decoration; contours appear only where data exists.
3. **Benchmark mark** — Videt's ownable device, an original abstraction of the surveyor's incised benchmark (horizontal datum bar over a chevron): score badge, list bullet, favicon. Set inside a ruled ring it becomes the **verification seal**, used at most once per page for verified states.
4. **The evidence cell** (canonical component) — a score set in the mono face with its evidence identifier and capture timestamp beneath, boxed by hairline rules. This unit appears on marketing pages, dashboards and exports identically; it is the brand's most-repeated element because it is the product's core promise made visible.

5. **Observation arcs** (added 2026-07-23) — concentric ring segments sweeping from a corner or datum point, 0.75px strokes in ochre or petrol at 20–50% opacity, with tiny mono tick labels. The visual register of repeated watching: use behind heroes and observation-related sections; arcs may animate in like a slow sweep (plotter rules apply — no pulsing).
6. **The two-pictures mirror** (added 2026-07-23) — the vision's core concept as a repeatable component: a Reality panel (ink on surface, ruled, factual) beside a Perception panel (same structure, with omissions struck and errors annotated in ochre, neutral provider chips above). The gap is always the ochre layer.

Iconography: engraved-line grammar — 1.25px stroke, square terminals, 20px grid, no filled blobs, no emoji, ever. Evidence identifiers are typeset as grid references in the mono (style, not literal geodata). Ochre at text sizes is always `ochre-deep` (§3).

Accent budget: petrol occupies less than 10% of any surface. It is a signal, not a fill.

## 10. Prohibitions (binding)

The owner's standing directive: Videt must never look AI-generated. Prohibited in all Videt design work:

- **Typefaces as identity:** Inter, Space Grotesk, Manrope, Poppins, Plus Jakarta Sans, DM Sans, Lexend, Outfit, Sora, Montserrat, Raleway, Fraunces.
- **Colour:** Tailwind default palette hexes or near-identical shades as brand colours; purple/indigo brand accents; purple-to-blue or teal-to-purple gradients; gradient text; the Anthropic family (warm cream `#F0EEE6`/`#F5F1EA` grounds, terracotta `#D97757`-family accents).
- **Surface effects:** glassmorphism, blur elevation, neon-glow-on-dark, rounded-2xl-everything.
- **Layout tells:** centered hero + three emoji feature cards; emoji as iconography.
- **Motion tells:** springy bounces, floating parallax, pulsing gradients.

## 11. Validation Record

Chart palettes were validated with the six-check palette validator (lightness band, chroma floor, adjacent-pair CVD separation under Machado simulation, normal-vision floor, contrast vs surface), and ordinal ramps with its ordinal mode (monotone lightness, step gaps, pale-end floor, single hue):

- Categorical set vs `#FAFAF7` (light) and `#172420` (dark): **all checks pass** in both modes; worst adjacent pair `#8E9430`↔`#B5504A` at ΔE 8.9 deutan / 19.4 normal; all slots ≥3:1 on both surfaces — with thin headroom (≈3.1:1 floor), so surface-token changes re-trigger validation.
- Sequential ramps (both modes): **all checks pass** (light-end floors 2.10:1 and 2.30:1).
- Text tokens: every text-bearing pairing computed ≥4.5:1 (range 4.58–14.71) including the derived dark status variants.
- 2026-07-23 additions: `ochre-deep #875213` — 5.80 on ground, 6.19 on surface, 5.24 on horizon (AA at all text sizes); `horizon #E4EDF1` — ink 12.35, ink-secondary 6.82, petrol 8.86 on it. Raw `ochre #C27E3A` measures 2.97 on ground and is restricted to graphics and ≥24px display use.
- Independent panel verification reproduced all claimed figures; the two runner-up directions failed here (§12), which is why computation, not taste, is tenet 4.

Any token change re-runs the palette validator (`validate_palette.js "<categorical>" --mode light|dark --surface <chart surface>`) plus the text-contrast script. Neither script is committed to this repository yet — committing both and wiring them into CI is §13 item 5; until then, token changes re-run them manually and update this record.

## 12. Rejected Directions (recorded per repository standards)

| Direction | Territory | Rejection rationale |
|---|---|---|
| The Standing Record | Editorial ledger: ink, ledger stock, oxblood seal | Failed the CVD hard constraint as computed (adjacent chart pairs ΔE 2.4 and 6.3 deutan vs ≥8 floor); light ground measured ΔE76 ≈ 1.9 from the prohibited Anthropic cream — perceptually near-indistinguishable; red-family oxblood accent structurally collides with "serious" status semantics; dark-mode token set incomplete. Its best ideas were grafted: the evidence cell, tick-to-value numeral motion, all-figures-in-mono law. |
| First Light | Deep-field observation: warm near-black, brass signal | Strongest computational rigor of the panel, but brass-on-black drifts fintech-luxury against a brief demanding "instrument, not treasury"; commercial mono license misstated (Berkeley Mono/TX-02 developer tier excludes commercial use); categorical floors passed with zero headroom. Grafted: the register law, accent surface budget, capture timestamps on evidence IDs, day-one dark status tokens. |
| The Instrument | Precision-instrument neutrals + signal hue | Generation failed (agent error); territory unexplored. Its core intent — instrument authority — is substantially covered by the winning survey concept. |

## 13. Open Items

1. Klim licensing purchase (Founders Grotesk, Untitled Sans, Founders Grotesk Mono) — budget early; the OFL fallback stack is shippable but less distinctive.
2. Trademark search on the benchmark mark before registration; the drawn device must be an original abstraction, not a copy of the Ordnance Survey symbol.
3. Wordmark design (Videt lockup in Founders Grotesk) — not yet commissioned.
4. Brand-name ADR dependency — see `000 STRATEGY_BRIEF.md`, Open Naming Items.
5. Commit the palette validator and the text-contrast script into this repository and wire them into CI, so §11's validation is enforced automatically rather than manually.
