# Volume I Owner Decision Register

## Status

- Status: Open owner decisions
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Purpose

Capture unresolved owner-level decisions required to finalize Volume I without silently resolving policy choices.

Each decision includes:

- identifier
- decision statement
- source reference
- owner
- deadline
- ADR trigger
- options
- recommendation
- default behavior until decision
- affected capabilities, workflows, rules, and acceptance criteria

## Open Decisions

### OD-001 Verification Method Set

- Decision: Which verification methods are approved for source ownership or control verification in baseline scope.
- Source Reference: [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md), [../014 SECURITY_MODEL.md](../014%20SECURITY_MODEL.md)
- Owner: Chief Architect
- Deadline: 2026-08-01
- ADR Trigger: Before Volume IV acceptance.
- Options:
  1. DNS record verification only.
  2. DNS plus HTTP file verification.
  3. DNS, HTTP file, and meta-tag verification.
- Recommendation: Option 2 to balance operational simplicity and customer onboarding friction.
- Default Behavior Until Decision: Permit DNS and HTTP file methods only; block other methods.
- Impacted Artifacts: CAP-005, WF-003, PRULE-005, PRULE-020, AC-CAP-005, AC-WF-003.

### OD-002 Discoverability Score Weight Distribution

- Decision: Final weight distribution across score pillars.
- Source Reference: [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md), [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- Owner: Chief Product
- Deadline: 2026-08-15
- ADR Trigger: Before Volume V commercial architecture acceptance.
- Options:
  1. Equal pillar weighting.
  2. Product-priority weighted distribution by pillar.
  3. Segment-adaptive weighting model with policy constraints.
- Recommendation: Option 2 with explicit versioned policy and controlled change management.
- Default Behavior Until Decision: Preserve existing conceptual scoring chain and disallow implicit weighting changes.
- Impacted Artifacts: CAP-015, WF-008, PRULE-025, AC-CAP-015, AC-WF-008, AC-SM-002.

### OD-003 Confidence Band Definitions For Prioritization

- Decision: Canonical confidence-band thresholds used by recommendation prioritization.
- Source Reference: [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- Owner: Chief Product
- Deadline: 2026-08-15
- ADR Trigger: Before Volume V commercial architecture acceptance.
- Options:
  1. Three-band model (Low, Medium, High).
  2. Four-band model (Low, Medium, High, Very High).
  3. Numeric confidence value with displayed bands.
- Recommendation: Option 3 to preserve precision internally and maintain user-facing interpretability.
- Default Behavior Until Decision: Use provisional three-band display while storing underlying confidence metadata.
- Impacted Artifacts: CAP-015, CAP-017, WF-008, WF-010, PRULE-025, PRULE-028, AC-CAP-017.

### OD-004 Notification Channel Baseline

- Decision: Which outbound channels are in baseline support scope for actionable notifications.
- Source Reference: [../012 SYSTEM_BOUNDARIES.md](../012%20SYSTEM_BOUNDARIES.md), [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md)
- Owner: Chief Product
- Deadline: 2026-08-20
- ADR Trigger: Before Volume IV acceptance test finalization.
- Options:
  1. In-app notifications only.
  2. In-app plus email.
  3. In-app, email, and webhook callbacks.
- Recommendation: Option 2 to satisfy broad usability without expanding external integration complexity.
- Default Behavior Until Decision: Deliver in-app and email; defer webhook support.
- Impacted Artifacts: CAP-021, WF-014, PRULE-034, AC-CAP-021, AC-WF-014.

### OD-005 Provisional Quality Threshold Finalization

- Decision: Final values and acceptance gates for provisional quality attributes.
- Source Reference: [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- Owner: Mixed by requirement owner in QA register
- Deadline: Varies by QA requirement (2026-08-15 through 2026-08-30)
- ADR Trigger: Required before corresponding volume acceptance gates listed in 013.
- Options:
  1. Accept provisional thresholds as final.
  2. Adjust selected thresholds based on measured baseline telemetry.
  3. Redefine threshold model by service class with separate acceptance gates.
- Recommendation: Option 2 with explicit metric baseline review and documented deltas.
- Default Behavior Until Decision: Treat values as provisional constraints for planning and do not convert into hard failure gates in implementation acceptance until owner-approved.
- Impacted Artifacts: CAP-007, CAP-015, WF-005, WF-008, PRULE-008, PRULE-024, PRULE-025, AC-CAP-007, AC-CAP-015, AC-WF-005, AC-WF-008.
- Sub-Decisions:
  - OD-005A (QA-REQ-001 Availability): Owner Chief Rails, deadline 2026-08-15.
  - OD-005B (QA-REQ-002 Reliability): Owner Chief Rails, deadline 2026-08-15.
  - OD-005C (QA-REQ-003 RTO): Owner Chief Security, deadline 2026-08-20.
  - OD-005D (QA-REQ-004 RPO): Owner Chief Rails, deadline 2026-08-20.
  - OD-005E (QA-REQ-005 API Latency): Owner Chief Rails, deadline 2026-08-20.
  - OD-005F (QA-REQ-006 Background Latency): Owner Chief Rails, deadline 2026-08-25.
  - OD-005G (QA-REQ-007 Throughput): Owner Chief Architect, deadline 2026-08-25.
  - OD-005H (QA-REQ-009 Cost Constraint): Owner Chief Product, deadline 2026-08-30.

### OD-006 Entitlement Enforcement And Grace Policy

- Decision: Hard-block versus grace policy for out-of-plan operations.
- Source Reference: [../012 SYSTEM_BOUNDARIES.md](../012%20SYSTEM_BOUNDARIES.md), [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- Owner: Chief Product
- Deadline: 2026-08-22
- ADR Trigger: Before commercial packaging finalization.
- Options:
  1. Immediate hard block at limit.
  2. Time-bound grace window with warning and escalation.
  3. Progressive degradation model by operation type.
- Recommendation: Option 2 for operational continuity with explicit governance controls.
- Default Behavior Until Decision: Enforce hard block for high-cost operations and warning-first behavior for low-cost operations as policy defaults.
- Impacted Artifacts: CAP-024, WF-015, PRULE-039, PRULE-040, AC-CAP-024, AC-WF-015.

## Decision Resolution Protocol

1. Owner records selected option and rationale in this document.
2. If ADR trigger condition is met, create or update ADR entry in [../../DECISIONS.md](../../DECISIONS.md).
3. Update impacted CAP, WF, PRULE, acceptance, and traceability references in the same change set.
4. Update control-plane documents if sequencing or readiness gates change.

## Dependencies

- [INDEX.md](INDEX.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
- [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md)
- [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- [../../DECISIONS.md](../../DECISIONS.md)

## Change Control

Any decision update MUST preserve decision identifier stability and update all impacted references listed in the impacted artifacts section for the decision.
