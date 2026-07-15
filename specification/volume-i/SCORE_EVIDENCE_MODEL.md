# Volume I Score And Evidence Model

## Status

- Status: Draft for owner review
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Purpose

Define the canonical conceptual chain from evidence to checks, findings, score contribution, recommendations, prioritization, and reassessment.

This document intentionally avoids inventing numeric weights or unsupported formulas.

## Conceptual Chain

1. Evidence capture
2. Check execution
3. Finding creation
4. Score contribution attribution
5. Recommendation generation
6. Recommendation prioritization
7. Reassessment and supersession

## Conceptual Entities

### Evidence

- Identifier Pattern: EV-[run]-[sequence]
- Required Attributes:
  - evidence_id
  - project_id
  - source_id
  - capture_timestamp
  - evidence_type
  - provenance_reference
  - retention_class
  - tenant_id
- Guarantees:
  - Must be traceable to source and project context.
  - Must be accessible under policy controls for downstream explainability.

### Check Result

- Identifier Pattern: CHK-[check]-[run]-[sequence]
- Required Attributes:
  - check_result_id
  - check_definition_id
  - evidence_references
  - execution_status
  - confidence_metadata
  - produced_at
  - model_or_rule_version
- Guarantees:
  - Deterministic for deterministic input.
  - Carries confidence metadata when used by prioritization and recommendations.

### Finding

- Identifier Pattern: FIND-[project]-[sequence]
- Required Attributes:
  - finding_id
  - finding_type
  - severity_or_impact_band
  - confidence_band
  - state
  - evidence_links
  - first_seen
  - last_seen
  - supersedes_finding_id (optional)
- Guarantees:
  - Every published finding references at least one evidence item.
  - Supersession preserves historical chain.

### Score Contribution

- Identifier Pattern: SC-[snapshot]-[finding]
- Required Attributes:
  - score_snapshot_id
  - finding_id
  - contribution_direction
  - contribution_band
  - rationale_reference
  - model_version
- Guarantees:
  - Contributions are explainable through finding and evidence lineage.
  - Contribution semantics are versioned.

### Recommendation Artifact

- Identifier Pattern: REC-[project]-[sequence]
- Required Attributes:
  - recommendation_id
  - finding_references
  - expected_impact_band
  - implementation_guidance
  - rationale_reference
  - confidence_band
  - publication_state
- Guarantees:
  - Recommendations remain evidence-linked and actionable.

### Priority Decision

- Identifier Pattern: PRI-[snapshot]-[sequence]
- Required Attributes:
  - priority_id
  - recommendation_id
  - impact_factor_band
  - confidence_factor_band
  - effort_factor_band
  - computed_order
  - policy_version
  - override_reason (optional)
- Guarantees:
  - Ranking is reproducible for stable inputs and policy version.
  - Manual overrides require explicit reason capture.

### Reassessment Result

- Identifier Pattern: REA-[project]-[run]
- Required Attributes:
  - reassessment_id
  - prior_run_reference
  - current_run_reference
  - score_delta_summary
  - finding_supersession_summary
  - recommendation_status_delta
- Guarantees:
  - Historical continuity is preserved.
  - Deltas are attributable to run lineage and changes in findings or evidence.

## Allowed Transformations

- Evidence -> Check Result: allowed when evidence quality and policy constraints pass.
- Check Result -> Finding: allowed when check status and confidence meet publication criteria.
- Finding -> Score Contribution: allowed when finding state is score-eligible.
- Finding + Score Contribution -> Recommendation Artifact: allowed when recommendation constraints pass.
- Recommendation Artifact -> Priority Decision: allowed when impact, confidence, and effort factors are present.
- Reassessment Result -> Supersession: allowed when prior and current run lineage is available.

## Prohibited Transformations

- Evidence bypassing checks directly into score without documented rule.
- Recommendation publication without linked finding and evidence.
- Score modification without model version and contribution lineage.
- Reassessment output that deletes historical finding lineage.

## Alignment With Provisional Quality Thresholds

Quality thresholds in [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md) are provisional where marked and are treated as owner decisions in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md).

Volume I therefore defines conceptual constraints and required explainability controls without hard-coding final numeric acceptance values.

## Acceptance Criteria

- AC-SM-001: Chain completeness exists from evidence to recommendation for every published recommendation.
- AC-SM-002: Every score snapshot stores model version and attributable contribution records.
- AC-SM-003: Every finding has at least one evidence link.
- AC-SM-004: Reassessment supersession chain is queryable for historical comparison.

## Dependencies

- [INDEX.md](INDEX.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
- [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md)
- [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- [../016 STATE_MODEL.md](../016%20STATE_MODEL.md)

## Change Control

Any normative update MUST:

1. preserve conceptual chain integrity
2. update rule references and acceptance mappings
3. record owner decisions when unresolved threshold dependencies are introduced
