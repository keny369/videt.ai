# 004 DESIGN_PRINCIPLES

## Document Control

- Status: Accepted baseline
- Version: 1.0.0
- Last updated: 2026-07-15
- Owner: Chief UX
- Reviewer: Chief Architect
- Classification: Canonical

## Purpose

Define non-negotiable design principles for all user-facing experiences across Project F1.

## Scope

Applies to:

- information architecture
- interaction design
- visual communication
- accessibility
- reporting and data visualization
- content and microcopy

## Principle 1: Decision Velocity Over Dashboard Density

Design must reduce time-to-decision, not maximize on-screen metrics.

Implications:

- surface priority and next action before secondary diagnostics
- default views should answer what changed, why it matters and what to do next

## Principle 2: Explainability Before Automation

Every recommendation must be intelligible before being actionable.

Implications:

- each issue view includes rationale, evidence and expected outcome
- confidence and uncertainty must be visible to users

## Principle 3: Progressive Disclosure

Complexity is revealed in layers so users start with essentials and drill down only when needed.

Implications:

- executive and operator views differ by depth, not by contradictory data
- advanced detail never blocks baseline understanding

## Principle 4: Consistent Mental Models

The same concept must look and behave consistently across all surfaces.

Implications:

- one canonical representation for score, issue severity, confidence and status
- avoid local component metaphors that redefine core entities

## Principle 5: Actionability At Point Of Insight

Insights must be paired with concrete next actions where they are displayed.

Implications:

- no orphan analytics views without remediation guidance
- remediation artifacts are directly accessible from issue context

## Principle 6: Accessibility Is A Primary Constraint

Accessibility is a design requirement, not a post-release retrofit.

Minimum baseline:

- keyboard accessibility for all interactive workflows
- semantic structure for assistive technologies
- adequate color contrast and non-color state indicators
- readable typography and clear focus states

## Principle 7: Trustworthy Visual Language

Visual hierarchy must communicate confidence and risk honestly.

Implications:

- do not exaggerate minor changes with alarmist visuals
- uncertainty and model limitations must be represented explicitly

## Principle 8: Comparative Context By Default

Scores and trends should be presented with relevant context.

Implications:

- include baseline and trend deltas when showing current score
- show benchmark context where available and statistically meaningful

## Principle 9: Mobile-Operational Readiness

Core user tasks must remain possible on mobile without loss of comprehension.

Implications:

- prioritize summary and action views for constrained screens
- maintain legibility of score and issue states at small viewports

## Principle 10: Content Precision

Language must be specific, operational and measurable.

Implications:

- replace vague labels with action-specific labels
- avoid ambiguous CTAs such as optimize or improve without scope

## Data Visualization Rules

- visual encodings must preserve comparability across time periods
- chart axes and units must always be explicit
- changes in score must expose contributing factors
- color should never be the sole signal for state

## Interaction Rules

- destructive actions require explicit confirmation
- state transitions must be visible and reversible when possible
- long-running operations require progress state and completion feedback

## Design Review Checklist

1. Is the primary user decision obvious within five seconds?
2. Is the associated action available without navigation detours?
3. Are confidence and uncertainty visible?
4. Is accessibility baseline satisfied?
5. Is terminology consistent with [003 TERMINOLOGY.md](003 TERMINOLOGY.md)?

## Acceptance Criteria

1. principles are explicit, testable and cross-functional
2. accessibility and explainability are first-order constraints
3. every principle includes operational implications

## References

- [000 OVERVIEW.md](000 OVERVIEW.md)
- [003 TERMINOLOGY.md](003 TERMINOLOGY.md)
- [005 PRODUCT_PRINCIPLES.md](005 PRODUCT_PRINCIPLES.md)
- [010 DOCUMENT_STANDARDS.md](010 DOCUMENT_STANDARDS.md)
