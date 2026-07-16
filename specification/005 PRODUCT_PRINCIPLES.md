# 005 PRODUCT_PRINCIPLES

## Document Control

- Status: Accepted baseline
- Version: 1.0.0
- Last updated: 2026-07-15
- Owner: Chief Product
- Reviewer: Chief Architect
- Classification: Canonical

## Purpose

Define product principles that govern roadmap, feature scope and customer value decisions.

## Scope

Applies to all product decisions including:

- roadmap prioritization
- packaging and pricing behavior
- feature acceptance
- release strategy
- customer outcome instrumentation

## Principle 1: Outcomes Over Outputs

Product success is measured by discoverability improvement and remediation completion, not by feature count.

## Principle 2: Explainable Recommendations

Users must understand why a recommendation exists before being asked to act on it.

## Principle 3: Prioritization Must Be Economic

Default issue sequencing must reflect impact, confidence and effort with explicit business rationale.

## Principle 4: Time-To-Value Must Be Short

A new customer should receive a baseline score and a prioritized action list quickly in first-run workflows.

## Principle 5: Actionability Is Mandatory

An Issue without a concrete next step is incomplete product behavior. `Finding` is a prohibited legacy synonym for a customer or product deficiency and MUST NOT appear in product behavior or customer output.

## Principle 6: Continuous Improvement Loop

The product must continuously close the loop between measurement, recommendation, action and re-measurement.

## Principle 7: Segment-Aware Defaults

Defaults should adapt to SMB, agency and enterprise operating realities without fragmenting core architecture.

## Principle 8: Trust Over Hype

Product claims, score changes and competitive comparisons must be evidence-backed and auditable.

## Principle 9: Non-Invasive By Default

The baseline product generates implementation artifacts and guidance but does not directly mutate customer production systems.

## Principle 10: Predictable Commercial Model

Packaging and pricing must map to visible customer value metrics and sustainable operational cost envelopes.

## Principle 11: Durable Core, Modular Expansion

Core platform capabilities must remain stable while specialized modules expand by clear interfaces.

## Principle 12: Explicit Non-Goals

Each major roadmap phase must document what is intentionally excluded to avoid diffusion.

## Prioritization Rubric

Use this rubric for roadmap ordering:

- customer impact magnitude
- confidence in value realization
- implementation complexity
- operational cost and risk
- strategic alignment with category position

## Product Acceptance Gate

A feature is release-ready only when all are true:

1. measurable customer outcome is defined
2. required data signals exist
3. recommendation and action path are complete
4. support and operations impact is understood
5. architecture and terminology compliance checks pass

## Product Anti-Patterns

Do not ship:

- diagnostics without action paths
- premium packaging features without durable value differentiation
- features that require hidden manual operations to function reliably
- features that redefine canonical terms locally

## Required Product Metrics

Each major capability must define:

- adoption metric
- outcome metric
- quality metric
- reliability metric

## Acceptance Criteria

1. product principles are explicit and decision-usable
2. prioritization and release gates are enforceable
3. anti-patterns and non-goals are documented

## References

- [002 GLOSSARY.md](002 GLOSSARY.md)
- [003 TERMINOLOGY.md](003 TERMINOLOGY.md)
- [004 DESIGN_PRINCIPLES.md](004 DESIGN_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007 ARCHITECTURE_PRINCIPLES.md)
- [009 DECISION_FRAMEWORK.md](009 DECISION_FRAMEWORK.md)
