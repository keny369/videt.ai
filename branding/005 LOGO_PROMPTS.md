# VIDET Logo — Image-Model Prompt Pack

Status: Brand asset v1, 28 July 2026. Winning concept "Datum" from a three-concept, judged development round. The mark is the **ratified benchmark device refined** (002 VISUAL_IDENTITY §9.3) — no re-ratification needed. Generation is concept-selection only; the production mark is redrawn as vector per §2. Trademark search before registration is mandatory (002 §13 item 2); the originality deltas vs the Ordnance Survey broad arrow are recorded in §6.

## 1. The concept in one paragraph

A wide horizontal datum bar floating above an upward-pointing chevron, drawn at one uniform bold stroke, square-cut, sharp — the grammar of a first-order survey, which is the product's promise: *this value was measured, here, and you can check it.* The load-bearing element is the negative space: the apex does **not** touch the bar; the one-stroke gap between them is the held sight-line — the mark enacts "it sees" (*videt*) without an eye. The chevron carries a latent inverted V for VIDET without depending on it. Two elements, one weight: the construction class of Chase's octagon and Deutsche Bank's slash — survives a 16px favicon, a blind emboss, and an acquirer's brand audit.

## 2. Construction spec (for the eventual vector redraw)

24×24-unit grid; uniform 3-unit stroke; butt terminals; 0 radius. **Bar:** 20 units wide × 3 deep, rows 5–8, always overshooting the chevron by 3 units each side (datum/horizon, never a roof). **Chevron:** two straight 3-unit strokes at 45°, mitred apex aimed at the bar's midpoint, interior apex angle 90°, overall width 14 units (7:10 to the bar), legs ending in flat horizontal cuts on a shared baseline at row 18. **The aperture:** apex-to-bar clear gap = one stroke (3 units), optically trimmed to ~2.6. **Optical corrections:** 45° legs ~4% thicker than the bar; apex may carry a 0.25-unit flat truncation; mark sits 0.5 unit above geometric centre in a field. **Seal:** the mark inside a single 1-unit ruled ring (⅓ mark stroke), inner Ø ~34 units, ≥4.75 units clearance at the bar corners, nothing else inside.

## 3. The prompts (copy-paste)

### 3.1 Primary — mark only, no text

> Flat vector logo mark, minimal, geometric, Swiss precision. A simple emblem of exactly two elements: one wide horizontal bar floating above one upward-pointing chevron shaped like a wide inverted V, the chevron's sharp apex aimed at the exact centre of the bar without touching it, leaving a clean narrow gap equal to the stroke thickness. Both elements share one identical bold uniform stroke weight with perfectly square-cut flat ends and sharp mitred corners, no rounding anywhere. The horizontal bar is clearly wider than the chevron; the chevron's two straight legs rise at 45 degrees and terminate in flat horizontal cuts on a shared baseline. Only two strokes in the chevron — no third stroke, no vertical stem, not an arrow. Solid deep petrol blue-green, hex #0E4553, on a plain warm off-white chalk background, hex #F2F3EF, flat solid colour only, no gradients, no shadows, crisp 2D vector edges. Emblem centred with very generous empty margin on all sides. Engraved-stamp precision abstracted into a timeless corporate trademark: mid-century Swiss trademark design, drafting-grid geometry, plotter-drawn precision. No text, no letters, no numbers anywhere in the image.

### 3.2 Seal variant — favicon / verification stamp

> Flat vector verification-seal logo, minimal, geometric, Swiss precision. A single unbroken plain circle drawn as one thin hairline ring with no lettering around it, and centred inside it an emblem of exactly two elements: a wide horizontal bar floating above an upward-pointing chevron shaped like a wide inverted V, the chevron's sharp apex aimed at the centre of the bar without touching it, separated by a narrow clean gap. Bar and chevron share one identical bold uniform stroke weight with square-cut flat ends and sharp corners, no rounding; only two strokes in the chevron, no vertical stem, not an arrow. The ring's stroke is much thinner than the emblem's stroke, like a fine ruled line. Generous clear space between the emblem and the inside of the ring; nothing else inside the circle. Solid deep petrol blue-green hex #0E4553 on a warm off-white chalk background hex #F2F3EF, flat solid colour only, no gradients, no shadows, crisp 2D vector edges, centred with generous outer margin. Mid-century Swiss trademark design, drafting precision. No text, no letters, no numbers anywhere in the image.

### 3.3 Alternate — wordmark lockup (proportion study)

> Flat vector logo lockup on a wide horizontal canvas, minimal, geometric, Swiss precision. On the left, a small emblem of exactly two elements: one wide horizontal bar floating above one upward-pointing chevron shaped like a wide inverted V, its sharp apex aimed at the bar's centre without touching it, both drawn at one identical bold uniform stroke weight with square-cut flat ends, no rounding, no third stroke, no vertical stem. To the right of the emblem, vertically centred, the single word "VIDET" in clean geometric sans-serif capital letters, plain unmodified letterforms, even generous letterspacing, medium weight, no stylisation or substitution of any letter. Everything in solid deep petrol blue-green hex #0E4553 on a warm off-white chalk background hex #F2F3EF, flat colour only, no gradients, no shadows, crisp 2D vector edges, generous margin all round. Mid-century Swiss trademark design, drafting precision, timeless corporate identity. The only text in the image is the five capital letters spelling exactly VIDET.

### 3.4 Negative prompt (full list — Flux/SD negative field; for the lockup, drop the first four terms)

> text, letters, words, typography, numbers, watermark, signature, gradient, glow, neon, chrome, metallic, 3D, bevel, emboss, extrusion, drop shadow, glassmorphism, transparency, purple, indigo, violet, circuit board, neural network, brain, sparkles, stars, swoosh, orbit, connected dots, eyeball, iris, pupil, realistic eye, shield, crest, checkmark, badge ribbon, rounded corners, blob, mascot, hand-drawn, sketch, brush stroke, texture, grain, noise, photorealistic, reflection, frame, border decoration, multiple logos, collage, mockup, arrow, arrowhead, broad arrow, vertical stem, three-pronged mark, military rank insignia, sergeant stripes, double chevron

**Midjourney note:** `--no` degrades on multi-word phrases — compress to single tokens: `--no gradient, 3D, shadow, glow, text, letters, purple, eye, shield, checkmark, arrow, stem, mascot, texture, mockup` and append `--ar 1:1 --style raw`. DALL·E/Ideogram: append negatives as a sentence starting "Avoid:".

## 4. Workflow

- **Aspect:** 1:1 for mark and seal; 3:1 (or 16:9) for the lockup.
- **Volume:** 30–50 generations of the primary (vary seed only, never the prompt mid-run), ~20 each of seal and lockup. A 1-in-10 keeper rate is normal for pure geometry — don't lower the bar to raise yield.
- **Keep only if ALL hold:** identical stroke weights bar/chevron · every terminal square-cut · apex clearly NOT touching the bar, gap ≈ one stroke · bar wider than chevron · perfect bilateral symmetry · one flat #0E4553 on clean #F2F3EF.
- **Reject on sight:** any third element (dot, tick, second bar) · third stroke / vertical stem / arrowhead (the Ordnance Survey drift) · tapered strokes · military-rank double chevron · any tilt.
- **Colour variants to produce after selection:** petrol on chalk (primary) · chalk on petrol (inverse) · ink #1E2B28 mono (documents) · never ochre as the mark colour (ochre is the annotation layer, 002 §3 mapping).
- **Type honesty:** every lockup generation is a proportion study — models mangle even five capitals. The production wordmark is set manually in Founders Grotesk (fallback Archivo), Medium, letterspaced; "videt.ai" is always set manually, never generated.
- **Production path:** pick the best generation → redraw as SVG on the §2 grid → that vector is the logo; the generation never ships.

## 4a. Production vectors (built 28 Jul 2026)

Spec-exact master SVGs live in `branding/logo/`: `videt-mark.svg` (petrol, transparent ground), `videt-mark-ink.svg` (#1E2B28 mono for documents), `videt-mark-inverse.svg` (chalk, for petrol/dark grounds), `videt-seal.svg` (ruled-ring verification seal). Geometry per §2: bar 20×3 at rows 5–8; chevron outer span 14 with 90° apex at (12, 11); one-stroke aperture gap (production keeps the exact 3.0-unit gap — the §2 "~2.6 optical trim" is deliberately not implemented, as a sub-unit apex nudge complicates the grid for negligible gain at logo sizes); legs carry the ~4% optical thickening. Generated images (incl. GPT's 28 Jul candidate — right concept, inverted bar/chevron proportion) are concept references only; these vectors are the logo.

## 5. Rejected concepts (recorded)

**Aperture** (bar interrupted by a slit + observed point): amends the ratified continuous datum bar — a sliced datum reads as a broken benchmark — and its distinguishing micro-geometry dies at 16px. **V-monogram** (downward V under the bar): inverts the canonical device, aims the gesture away from the datum, carries a latent "value declined" reading — the worst note for a measurement brand — and lands in the crowded Vue/Vercel V-mark neighbourhood.

## 6. Trademark note

Bar-over-upward-chevron shares structural schema with the Ordnance Survey cut mark (a UK Crown broad-arrow mark). Recorded originality deltas: two-stroke chevron with **no vertical stem and no third stroke**; **detached** apex with a one-stroke aperture gap; 90° apex; bar overshooting the chevron. These deltas are the originality argument; the professional trademark search (already in the identity's open items and counsel's brief) runs before registration, and the reject-on-sight rules in §4 keep generated candidates on the defensible side of the line.
