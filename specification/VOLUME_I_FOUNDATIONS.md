# Volume I - Strategic Foundations

## Document Control

- Status: Active strategic umbrella
- Foundation Version: 1.0
- Owner: Chief Architect
- Last updated: 2026-07-16
- Depends on: [000 OVERVIEW.md](000%20OVERVIEW.md), [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md), [002 GLOSSARY.md](002%20GLOSSARY.md), [003 TERMINOLOGY.md](003%20TERMINOLOGY.md), [004 DESIGN_PRINCIPLES.md](004%20DESIGN_PRINCIPLES.md), [005 PRODUCT_PRINCIPLES.md](005%20PRODUCT_PRINCIPLES.md), [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md), [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md), [008 AI_PRINCIPLES.md](008%20AI_PRINCIPLES.md), [009 DECISION_FRAMEWORK.md](009%20DECISION_FRAMEWORK.md), [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md), [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md), [012 SYSTEM_BOUNDARIES.md](012%20SYSTEM_BOUNDARIES.md), [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md), [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md), [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md), [016 STATE_MODEL.md](016%20STATE_MODEL.md), [017 ERROR_MODEL.md](017%20ERROR_MODEL.md), [018 OBSERVABILITY.md](018%20OBSERVABILITY.md), [019 VERSIONING.md](019%20VERSIONING.md), [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md), [../CLAUDE.md](../CLAUDE.md), [../governance/PROJECT_CONSTITUTION.md](../governance/PROJECT_CONSTITUTION.md), [../DECISIONS.md](../DECISIONS.md), [../research/000-initial-concept.md](../research/000-initial-concept.md)

## Purpose

Define the strategic architecture of Project F1 so all downstream product, UX, system and implementation decisions inherit from one consistent business and product model.

## Scope

This volume defines:

- mission-to-market translation
- customer and segment architecture
- product value architecture and capability boundaries
- Discoverability Score conceptual model
- pricing and commercial model baseline
- strategic non-goals and constraints

Canonical implementation-ready detail for Volume I is defined in the decomposed specification set:

- [volume-i/INDEX.md](volume-i/INDEX.md)
- [volume-i/PRODUCT_DEFINITION.md](volume-i/PRODUCT_DEFINITION.md)
- [volume-i/CAPABILITY_MODEL.md](volume-i/CAPABILITY_MODEL.md)
- [volume-i/WORKFLOW_SPECIFICATIONS.md](volume-i/WORKFLOW_SPECIFICATIONS.md)
- [volume-i/PRODUCT_RULES.md](volume-i/PRODUCT_RULES.md)
- [volume-i/SCORE_EVIDENCE_MODEL.md](volume-i/SCORE_EVIDENCE_MODEL.md)
- [volume-i/ACCEPTANCE_AND_TEST_MAPPING.md](volume-i/ACCEPTANCE_AND_TEST_MAPPING.md)
- [volume-i/TRACEABILITY_MATRIX.md](volume-i/TRACEABILITY_MATRIX.md)
- [volume-i/OWNER_DECISION_REGISTER.md](volume-i/OWNER_DECISION_REGISTER.md)
- [volume-i/INDEPENDENT_REVIEW.md](volume-i/INDEPENDENT_REVIEW.md)

This volume does not define:

- detailed UI interaction design
- physical schema and migrations
- service-to-service technical contracts
- implementation-level test plans

Those are specified in Volumes II to V.

## Background

Search behavior is shifting from ranked links toward AI-generated answers and zero-click surfaces. Businesses now compete for discoverability in both classical search engines and AI assistants.

Most SEO tools diagnose problems but fail to produce implementation-ready actions for mixed technical and non-technical teams. Project F1 addresses this by combining measurement, prioritization and actionable remediation artifacts in one operating model.

## Business Rationale

### Strategic Thesis

Project F1 is a Discoverability Intelligence Platform, not a generic SEO audit product. The platform exists to help organizations become discoverable across all high-intent digital answer surfaces.

### Why This Category

- demand is moving from keyword ranking optimization to answer-surface visibility
- AI assistants increasingly mediate user discovery journeys
- teams need decision-ready remediation, not raw diagnostics

### Value Proposition

Primary promise: Become the answer.

The platform must answer three customer questions with evidence:

1. Why are we not being found?
2. What should we fix first?
3. Exactly how do we fix it?

### Economic Logic

- recurring subscription model aligned to ongoing visibility monitoring
- multi-seat and multi-domain expansion path for agencies and enterprise teams
- retention driven in Volume I by weekly score movement and issue closure; competitive tracking is a later Growth expansion and is not a baseline behavior

## Functional Specification

### Product Definition

Project F1 provides continuous discoverability intelligence across search engines and AI assistants by:

1. crawling and evaluating customer web properties
2. scoring discoverability across standardized pillars
3. prioritizing issues by impact and effort
4. generating implementation-ready remediation artifacts
5. monitoring the customer's own trend movement; competitor selection, collection, comparison, positioning, and alerts require a later explicit capability contract and are not Volume I behavior

### Target Segments

Primary segments:

- small and medium businesses with limited internal SEO capacity
- digital agencies managing multiple client domains
- in-house marketing and growth teams at mid-market and enterprise companies

Secondary segment:

- consultants delivering discoverability improvement programs

### User Roles

- Executive Buyer: cares about commercial outcomes, trend direction and risk.
- Marketing Operator: cares about issue priority, content and channel actions.
- Technical Implementer: cares about exact implementation guidance and validation.

### Jobs To Be Done

- diagnose discoverability gaps with confidence
- sequence remediation by business impact
- ship technical and content fixes faster
- prove improvement with periodic score and trend evidence

### Core Workflow Architecture

- Domain onboarding: input domain and crawl settings.
- Evidence collection: crawl pages, metadata and structural signals.
- Evaluation: run standards checks and model-based analysis.
- Scoring: compute pillar and overall Discoverability Score.
- Prioritization: rank issues by impact, confidence and effort.
- Remediation generation: produce platform-specific instructions and code artifacts.
- Monitoring: re-run on schedule and report movement.

### Discoverability Score Architecture (Conceptual)

The Discoverability Score is a normalized 0 to 100 score composed of seven pillars.

Pillars:

- Technical Integrity
- Search Presence
- AI Presence
- Authority Signals
- Trust Signals
- Content Quality
- Local Presence

Conceptual formula:

Overall Score = sum(weight[pillar] x pillar_score[pillar])

Architecture constraints:

- each pillar score must be explainable to end users
- score changes must be attributable to specific issue deltas
- weighting model must be versioned and auditable

### Issue Prioritization Model (Conceptual)

Every issue includes:

- problem statement
- user-visible impact
- confidence level
- estimated remediation effort
- expected score effect
- implementation artifact options

Initial artifact types:

- Rails patch guidance
- WordPress snippet guidance
- Shopify configuration guidance
- LLM prompt templates for developer tooling

### Commercial Packaging Baseline

Planned packaging:

- Free: single scan baseline report
- Starter: recurring monitoring for one domain
- Growth: planned competitor and AI visibility expansion; this packaging label grants no Volume I competitor behavior or entitlement
- Agency: multi-domain and client management model
- Enterprise: custom contracts, controls and support

Packaging constraints:

- each tier must map to distinct operational cost envelopes
- pricing model must align with value metric and usage behavior

## Technical Specification

Volume I defines technical boundaries that downstream architecture must satisfy.

All boundaries in this chapter are subordinate to the immutable foundations 000 through 020 and must use canonical terms and principles from those documents.

Volume II and downstream specification work MUST remain paused until this volume is accepted.

### System Boundaries

- Platform generates recommendations and implementation artifacts.
- Platform does not directly write to customer production systems in initial scope.
- Platform may ingest customer-provided evidence and third-party data via explicit integrations.

### Data Boundaries

- canonical entities include Account, Project, Source, Document, Crawl, Evaluation, Issue, ScoreSnapshot and RecommendationArtifact
- check results are evaluation outputs, not top-level canonical entities in the foundation domain model
- score and recommendation generations must be traceable to source evidence
- every model that affects scoring must be versioned

### AI Boundaries

- LLM usage is constrained to explanation, prioritization and artifact generation
- model outputs require deterministic guardrails and policy checks before user delivery
- prompt and model version must be stored with generated artifacts

### Security And Compliance Boundaries

- least-privilege access model by role and organization boundary
- no implicit source-control or production write permissions
- audit trail required for score changes and generated artifacts

### Engineering Baseline Boundaries

Target stack remains:

- Rails 8
- PostgreSQL
- Hotwire
- Tailwind
- Redis
- Sidekiq

Any deviation requires ADR approval in [../DECISIONS.md](../DECISIONS.md).

## Acceptance Criteria

Volume I is accepted when all criteria below are true:

1. category positioning, customer segments and value proposition are unambiguous
2. Discoverability Score pillars and conceptual weighting constraints are defined
3. core workflow is defined end-to-end from onboarding to monitoring
4. pricing baseline and value logic are documented
5. strategic non-goals and boundaries are explicit
6. cross-references to constitution, governance and ADRs are complete
7. decomposed Volume I documents under [volume-i/INDEX.md](volume-i/INDEX.md) are synchronized and traceable
8. unresolved owner-level decisions are explicitly recorded in [volume-i/OWNER_DECISION_REGISTER.md](volume-i/OWNER_DECISION_REGISTER.md)

## Dependencies

- [INDEX.md](INDEX.md)
- [volume-i/INDEX.md](volume-i/INDEX.md)
- [../ROADMAP.md](../ROADMAP.md)
- [../PROJECT_STATE.md](../PROJECT_STATE.md)
- [../governance/QUALITY_STANDARD.md](../governance/QUALITY_STANDARD.md)

## Risks

- Risk: score model over-complexity reduces explainability.
  Mitigation: enforce pillar-level explainability and versioned weighting.

- Risk: AI output quality variance introduces unreliable remediation guidance.
  Mitigation: require evidence-linked prompts, validation checks and human-readable rationale.

- Risk: broad segment coverage dilutes product focus.
  Mitigation: prioritize shared jobs-to-be-done and maintain strict non-goals.

## Strategic Non-Goals

- becoming a generic web analytics replacement
- directly deploying fixes to customer production without explicit architecture update
- maximizing feature count before reliability and explainability targets are met

## Future Evolution

Planned expansion after baseline architecture validation:

- predictive discoverability risk forecasting
- vertical-specific scoring profiles
- competitor selection, tracking, intelligence, positioning, alerts, and benchmarking models
- deeper enterprise governance controls

## References

- [000 OVERVIEW.md](000%20OVERVIEW.md)
- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [002 GLOSSARY.md](002%20GLOSSARY.md)
- [003 TERMINOLOGY.md](003%20TERMINOLOGY.md)
- [004 DESIGN_PRINCIPLES.md](004%20DESIGN_PRINCIPLES.md)
- [005 PRODUCT_PRINCIPLES.md](005%20PRODUCT_PRINCIPLES.md)
- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [008 AI_PRINCIPLES.md](008%20AI_PRINCIPLES.md)
- [009 DECISION_FRAMEWORK.md](009%20DECISION_FRAMEWORK.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)
- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [012 SYSTEM_BOUNDARIES.md](012%20SYSTEM_BOUNDARIES.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)
- [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md)
- [../CLAUDE.md](../CLAUDE.md)
- [../governance/PROJECT_CONSTITUTION.md](../governance/PROJECT_CONSTITUTION.md)
- [../governance/QUALITY_STANDARD.md](../governance/QUALITY_STANDARD.md)
- [../DECISIONS.md](../DECISIONS.md)
- [../research/000-initial-concept.md](../research/000-initial-concept.md)
