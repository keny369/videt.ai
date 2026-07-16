# Changelog

## 2026-07-16

- corrected DEF-V1-001 by replacing impossible exactly-once Mailgun delivery implications with at-least-once application attempts, durable local submission deduplication, explicit provider-acceptance uncertainty, resend suppression, read-only reconciliation, duplicate-tolerant user behavior, acknowledged administrative replay, terminal known-failure behavior, and complete Audit Evidence
- corrected DEF-V1-002 by defining existing-Account sign-in through a purpose-bound managed-identity receipt, exact Organization and lifecycle/assurance checks, current authorization-context initialization, independent concurrent Sessions, deterministic destination selection, audited failures, and no framework-specific authentication choice
- corrected DEF-V1-003 by retaining manual reassessment and permitting scheduled reassessment only through an active Project policy with an explicit anchored cadence input, exact due-slot identity, active-run conflict suppression, inactive-scope skipping, outage coalescing, no entitlement-derived cadence, no schedule-only customer Notification, and auditable decisions
- corrected DEF-V1-004 by making atomic WF-001 self-service the sole baseline BillingEntity creation path, linking the initial Plan Assignment before activation, requiring exactly one current nonclosed entity per Organization, defining provider-independent bootstrap and closure/retention behavior, and adding no invoice or payment entity
- corrected DEF-V1-005 by establishing Evidence, Evidence Type, Evidence Source, Evidence Payload, Evidence Provenance, Evidence Classification, Measurement Evidence, Verification Evidence, and Audit Evidence as the sole canonical vocabulary and removing conflicting aliases across foundation, Volume I, and diagrams
- corrected DEF-V1-006 by aligning CAP-019 and its acceptance/traceability contracts to the frozen deterministic structured-only dashboard/history baseline with no AI narrative, placeholder, presentation region, hidden enablement, or AI-provider call
- added ADR-017 for the six demonstrated post-freeze defect corrections, paused further Volume II expansion, and retained only the two existing Volume II drafts with reference-level alignment
- resolved the final dashboard/history ambiguity by prohibiting AI-generated narrative, narrative placeholders and AI-provider calls in accepted Volume I while requiring complete deterministic structured responses
- completed the final Volume I acceptance and closure pass without beginning Volume II
- accepted Volume I as the behavioural baseline after making every pending owner decision deterministic and classifying its exact downstream blocking impact
- recorded OD-010 as a complete customer-facing numeric-score and external-measurement production gate, and OD-011 as a production customer-data and contractual-retention gate; neither blocks Volume II
- aligned onboarding, invitation, effective-permission, lifecycle, retention, logical-envelope, Check catalogue, acceptance, traceability, terminology, diagrams, and control-plane contracts
- defined the Volume II implementation-facing boundary and preserved its pause until the accepted Volume I change set is committed and tagged
- decomposed Volume I into canonical implementation-ready specification set under specification/volume-i
- added product definition with stable PR-REQ identifiers and foundation-aligned boundaries
- added capability model with CAP-001 through CAP-025 and explicit dependency/acceptance mapping
- added workflow specifications WF-001 through WF-018 with primary, alternate, failure, and recovery paths
- added product rule catalog PRULE-001 through PRULE-042 with source references and verification intent
- added conceptual score and evidence chain model from evidence through reassessment without invented numeric formulas
- added acceptance and planned test-type mapping across capabilities, workflows, and score model criteria
- added Volume I traceability matrix linking requirements, capabilities, workflows, rules, acceptance, and verification
- added canonical owner decision register OD-001 through OD-006 baseline set including provisional 013 quality threshold handling
- added independent multi-role review record with findings, resolutions, and residual risks
- updated control-plane docs to treat specification/volume-i/INDEX.md as canonical Volume I detail set while preserving Volume II pause gate
- resolved OD-004 objectively to baseline in-app plus email notification channels
- converted unresolved owner decisions to decision-ready briefs with explicit approval wording and latest-responsible decision points
- added domain-model owner decisions for citation linkage scope and billing-entity decomposition scope
- added scoring owner decision for disputed Issue score eligibility and synchronized scoring behavior artifacts
- corrected objective traceability defects in Volume I product-rule source requirement references
- added explicit Volume I acceptance checklist with pass and blocked conditions in specification/volume-i/INDEX.md

## 2026-07-15

- upgraded repository control documents: README, ROADMAP, PROJECT_STATE, DECISIONS
- expanded manual navigation and domain coverage map in specification/INDEX.md
- authored initial Product Architecture Manual Volume I
- aligned research baseline with canonical manual authority model
- extended immutable foundation layer from 000-010 to 000-020
- authored canonical foundation documents 011 through 020
- established canonical diagrams for system context, domain model, containers, components, AI pipeline, and data lifecycle
- added architecture fitness-function catalog and governance policy
- added constitutional TDD and documentation-as-code policies
- added foundation traceability matrix and dependency graph governance
- declared foundation baseline version 1.0 with controlled change policy
- completed architecture review consistency corrections across governance, terminology, and traceability
- added centralized foundation section mapping registry for structural conformance
- added ADR-014 and ADR-015 for mapping governance and canonical event naming alignment
- added ADR-016 to preserve authority precedence under intra-foundation dependency cycles
- synchronized volume, domain, observability, and container diagram terminology
