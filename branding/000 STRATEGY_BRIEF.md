# Videt — Product & Website Strategy Brief

Status: Owner-supplied brief, adjusted for conformance with the ratified Volume I specification. Marketing document — does not override the Product Architecture Manual. Adjustments are recorded at the end of this document with their governing identifiers.

Brand name: Videt (videt.ai). The name Videt appears nowhere in the ratified specification; the product's internal codename is F1. See Open Naming Items below.

## Vision (Overhauled 2026-07-23)

The owner overhauled the long-term vision with a future-vision document set: VISION-001 "Commercial Discoverability Observatory", ADR-012 "Future Discoverability Architecture", ADR-013 "Genesis Project Conformance" and FUTURE-WORKFLOW-001 "Intervention Learning Lifecycle" (currently outside the repository; see Open Naming Items). All branding and website work aligns to it.

The vision in brief:

- A business exists twice: **Reality** — what is objectively true about it — and **Perception** — what each AI provider believes about it. The gap between the two decides whether the machine recommends you.
- Videt is the **Observatory** for that gap: it observes machine perception, explains the differences, guides verified interventions, re-observes, and converts measured outcomes into compounding **Intelligence**. Reports depreciate; knowledge compounds.
- The commercial question has changed from "How do I rank first?" to **"Will the machine choose me?"**
- The Observatory answers five questions for every organisation: Does the machine know you exist? Does it understand your business? Does it trust what it knows? Does it recommend you? **Why?**
- Discovery's four eras frame the category narrative: directories listed you, search engines ranked you, knowledge graphs learned about you — now generative systems answer *for* you.

Marketing sells this vision as the category story, from the owner's perspective — the dream of being seen, chosen and certain — never as a feature list. Vision-layer capabilities (interventions, learning loops, benchmarking) are the direction of the category and carry non-commitment labelling (SB-REQ-029); shipping-behaviour claims remain gated by the claim discipline in `001 WEBSITE_STRATEGY.md`.

## Your Role

You are the Head of Product Marketing, Creative Director, UX Strategist, Information Architect and Chief Revenue Officer for Videt.

Your responsibility is to create a website that establishes Videt as the leader of the Discoverability Intelligence category — AI-led, with search as the substrate (ADR-003).

Approach every recommendation as if you were preparing the company for rapid commercial growth, enterprise sales and potential acquisition.

Your work should combine:

- Product marketing
- Category design
- SaaS positioning
- Conversion optimisation
- Sales psychology
- Information architecture
- UX
- UI
- Brand strategy
- B2B enterprise marketing
- Startup growth

Your recommendations should always balance commercial performance with technical accuracy.

## About Videt

Videt (videt.ai) exists because customer discovery has changed.

For two decades businesses competed to appear in search engine results.

Today millions of people ask AI assistants directly.

Instead of searching "Best accountant in Melbourne", they ask ChatGPT.

Instead of searching "Which CRM should I buy?", they ask Claude.

Instead of comparing dozens of websites, they increasingly trust a single AI-generated recommendation.

Businesses are no longer competing only for search rankings. They are competing to be included inside AI-generated answers.

Most organisations have no reliable way to see whether AI systems know enough about them to recommend them.

Videt exists to solve that problem.

## The Fundamental Question

Everything Videt does revolves around answering one question:

> When someone asks AI for a business like mine… will it recommend me?

Everything else is supporting evidence.

Never lose sight of this.

## The Problem

Traditional SEO measures visibility inside search engines.

AI assistants don't return search results. They generate answers.

Businesses absent from those answers are absent from the decision.

Today most organisations cannot reliably answer:

- whether AI-generated answers include and cite your business
- which customer questions you appear for, and which you are absent from
- how discoverability changes over time
- what should be improved, in what order, and why

Videt is built specifically to answer those questions.

## What Videt Does

Videt measures an organisation's discoverability — across AI answer surfaces and the search surfaces AI evaluates — on demand and on a schedule the customer controls.

It measures whether AI-generated answers include your business, with attributable citations, for the customer questions that matter.

It scores discoverability across seven evidence-backed pillars: Technical Integrity, Search Presence, AI Presence, Authority Signals, Trust Signals, Content Quality and Local Presence.

It pinpoints which customer intents lack cited presence in AI answers.

It produces prioritised, implementation-ready Recommendation Artifacts — complete work orders with rationale, impact, confidence, effort, ordered implementation steps and ordered verification steps.

It tracks discoverability across assessments: every completed evaluation produces an immutable ScoreSnapshot, and any two comparable assessments produce exact, attributable deltas.

It makes opaque AI behaviour measurable — and every number traces to inspectable evidence.

Rather than asking "How many keywords do I rank for?", Videt asks:

> Is this business present, and cited, in the answers AI generates?

## What Videt Is NOT

Do not position Videt as:

- another SEO audit tool
- another analytics dashboard
- another marketing platform
- another rank tracker
- another keyword optimiser

Those belong to a previous generation.

Videt belongs to the emerging AI discovery ecosystem.

Important nuance (ADR-003): Videt is not AI-only. The ratified product unifies traditional search discoverability and AI answer discoverability in one operating model, because search presence is part of the evidence AI evaluates. Lead with AI; carry search as the substrate. Never describe the product as "an SEO tool", and never describe it as ignoring search.

## Market Opportunity

AI assistants are becoming a primary discovery channel.

Every improvement in AI reasoning increases the importance of being understood by AI.

That creates a new optimisation category. Videt is built to measure it.

## Core Positioning

Videt is the Commercial Discoverability Observatory: it shows organisations how intelligent machines perceive them, measures the gap against reality, and — as the vision matures — proves which changes close it.

The product is diagnostic before it is prescriptive.

Evidence before recommendations.

Measurement before optimisation.

Confidence before action.

Canonical promise (PR-REQ-003): **Become the answer.**

## Core Brand Personality

Videt should feel:

- intelligent
- calm
- authoritative
- analytical
- trustworthy
- premium
- understated
- evidence-driven

Avoid:

- hype
- sensationalism
- fear marketing
- AI buzzwords
- exaggerated claims

The tone should resemble Stripe, Linear, Notion or Vercel more than a typical marketing platform. The visual identity must not clone them, and must not resemble the recognisable AI-generated-site aesthetic (see `002 VISUAL_IDENTITY.md`).

This posture is codified: Trust Over Hype is product law (005 Product Principles, Principle 8). The website's restraint is a product feature.

## Guiding Strategic Frame

One idea is woven through the entire website:

> **Google indexed the web. AI evaluates it.**

Indexing asked: does this page exist, and does it match the query?
Evaluation asks: is this business worth recommending — and can that be evidenced?

This transition explains why discoverability has changed without pages of technical explanation. Videt frames the market around this shift and owns the category narrative rather than participating in it.

## Repository

The project repository is the single source of truth (ADR-001). It contains business strategy, product specification, engineering specification, workflows, architecture, research and terminology.

Use those documents to verify details. Do not invent product capabilities. Treat repository documentation as authoritative.

Focus primarily on:

- `specification/volume-i/PRODUCT_DEFINITION.md`
- `specification/volume-i/CAPABILITY_MODEL.md`
- `specification/volume-i/SCORE_EVIDENCE_MODEL.md`
- `specification/003 TERMINOLOGY.md` and `specification/002 GLOSSARY.md`
- `specification/005 PRODUCT_PRINCIPLES.md` and `specification/004 DESIGN_PRINCIPLES.md`
- `research/000-initial-concept.md`
- `branding/001 WEBSITE_STRATEGY.md` (the working strategy that executes this brief)

Engineering documents exist primarily to validate technical claims rather than drive messaging.

## Website Objective

The website should accomplish five things.

- Within five seconds visitors should understand: **What is Videt?**
- Within fifteen seconds: **Why does this matter?**
- Within thirty seconds: **Why is this becoming important now?**
- Within one minute: **Why should I trust Videt?**
- Before leaving: **What should I do next?**

## Success Metric

Someone who has never heard of Videt should leave believing:

> "I hadn't considered whether AI recommends my business before today."

followed immediately by:

> "I need to find out."

## Guiding Principles

Every recommendation should be:

- commercially grounded
- technically accurate
- evidence-based
- customer-centric
- differentiated
- simple to understand

Whenever there is a conflict between sounding impressive and being clear, choose clarity.

Never use jargon where plain English communicates the idea more effectively.

## Adjustments From The Ratified Specification

This brief was verified claim-by-claim against the ratified Volume I baseline. The following statements from the original draft were adjusted because the specification contradicts or qualifies them. Website copy must respect these.

| Original claim | Adjustment | Authority |
|---|---|---|
| "Videt continuously measures AI discoverability" | The spec states continuity at purpose level (PR-REQ-002: the product MUST continuously measure), but baseline execution mechanics are manual trigger plus customer-scheduled reassessment, and "Continuous monitoring and reassessment" is the Stage 2 maturity label. Copy describing behaviour says on-demand and scheduled; never "always-on" or "real-time". | PR-REQ-002, PR-REQ-018, PRULE-033, PRULE-045, CAP-020 |
| "It determines how AI systems understand a business" | Videt measures observed, cited presence in AI-generated answers for an approved intent set (CHK-AIP-001). It does not model AI "understanding": the `ai_presence` pillar's signal boundary excludes unvalidated model opinion, and raw provider responses are never retained. | CHK-AIP-001, SCORE_EVIDENCE_MODEL pillar registry (`ai_presence`), external-observation-v1 |
| "It identifies the signals influencing AI recommendation" | Videt identifies which customer intents lack cited presence and issues evidence-backed Recommendation Artifacts. It does not claim to reverse-engineer provider ranking signals, and its templates explicitly forbid manipulation framing. | OD-010, REC-CHK-AIP-001-v1 |
| "It benchmarks competitors" | Not in the ratified baseline. Own-history comparison ships (CAP-019, Release Classification: Baseline Core, via WF-012); competitor benchmarking is a later Growth-tier expansion and must be labelled a non-commitment wherever mentioned. | VOLUME_I_FOUNDATIONS.md, SB-REQ-029, CAP-019 |
| "Not an SEO tool / scope is AI discoverability" | Correct that Videt is not a generic SEO audit utility (PR-REQ-001). Incorrect as a scope claim: the product measures both search and AI answer surfaces, equal-weighted across applicable pillars under the interim score policy. | ADR-003, PR-REQ-002, CHK-SP-001, SCORE_EVIDENCE_MODEL "Pillar And Overall Formula" |
| Present-tense shipping claims | Implementation is at S-01; external measurement (Search Presence, AI Presence, Authority Signals) is dormant until the OD-010 Measurement Set activates. Pre-launch copy uses designed-to framing and an early-access conversion path. See claim discipline in `001 WEBSITE_STRATEGY.md`. | OD-010, PROJECT_STATE.md |

## Open Naming Items

1. **Brand-name ratification.** Videt/videt.ai appears in no ratified document. Adopting it for engineering-visible surfaces (crawler user agent `F1DiscoverabilityBot`, error namespaces such as `F1-AI-422`, repository name) is a controlled change requiring an ADR. Marketing may proceed with Videt as the public brand while F1 remains the internal codename; the ADR should record that mapping.
2. **Pricing and packaging.** No prices or tiers are ratified (ADR-019 separates commercial numerals from Volume I). The website must not invent them.
3. **Category label transition.** The ratified label is Discoverability Intelligence Platform (ADR-003); the overhauled vision names the category Commercial Discoverability Observatory (VISION-001). Marketing leads with the Observatory as the category story; changing the ratified label is a controlled change requiring an ADR.
4. **Filing the vision set.** The vision documents live outside the repository, and their ADR numbers (ADR-012, ADR-013) collide with existing entries in `DECISIONS.md`. Filing them canonically needs a numbering and location decision (single source of truth, ADR-001).
