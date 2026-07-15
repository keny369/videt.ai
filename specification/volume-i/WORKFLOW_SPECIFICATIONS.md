# Volume I Workflow Specifications

## Status

- Status: Draft for owner review
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Workflow Coverage

This document defines 18 canonical workflows using stable identifiers WF-001 through WF-018.

Every workflow includes:

- purpose and actors
- preconditions and triggers
- primary path
- alternate path
- failure path
- recovery path
- state transitions
- domain events
- authorization and security notes
- audit and observability notes
- acceptance criteria reference

## WF-001 Onboard Organization And Initial Project

- Identifier: WF-001
- Purpose: Establish an organization and first project with valid governance context.
- Actors: Organization Administrator
- Related Capabilities: CAP-001, CAP-002, CAP-003
- Trigger: User completes registration and starts onboarding.
- Preconditions: Registration is successful.
- Primary Path:
  1. Create organization in pending state.
  2. Apply baseline governance and role model.
  3. Create first project in draft state.
  4. Present onboarding completion and next-step guidance.
- Alternate Path: Organization exists and user is invited as admin; workflow skips organization creation and proceeds to project creation if authorized.
- Failure Path: Organization provisioning fails due to invalid policy setup.
- Recovery Path: User corrects required policy inputs and retries provisioning.
- State Transitions: Account.Pending -> Account.Active; Organization.Pending -> Organization.Active; Project.Draft.
- Domain Events: AccountActivated, OrganizationCreated, OrganizationActivated, ProjectCreated.
- Authorization: Requires administrator privileges in target tenant context.
- Security Notes: Enforce tenant boundary establishment before project creation.
- Audit and Observability: Emit correlation_id across account, organization, and project events.
- Acceptance Criteria: AC-WF-001

## WF-002 Activate Project Scope

- Identifier: WF-002
- Purpose: Transition project from draft to active when onboarding prerequisites are met.
- Actors: Organization Administrator, Marketing Operator
- Related Capabilities: CAP-003, CAP-004
- Trigger: User requests project activation.
- Preconditions: Project exists in draft with required metadata.
- Primary Path:
  1. Validate project metadata completeness.
  2. Validate at least one candidate source exists.
  3. Transition project to active state.
- Alternate Path: Project remains draft if source verification is not complete.
- Failure Path: Activation attempt blocked due to unmet policy checks.
- Recovery Path: Resolve missing requirements and re-attempt activation.
- State Transitions: Project.Draft -> Project.Active.
- Domain Events: ProjectActivated.
- Authorization: Administrator or delegated operator with activation right.
- Security Notes: Activation rights must be explicitly granted.
- Audit and Observability: Activation check outcomes logged with denial reasons.
- Acceptance Criteria: AC-WF-002

## WF-003 Verify Property Ownership Or Control

- Identifier: WF-003
- Purpose: Confirm tenant authority over a source before activation.
- Actors: Organization Administrator, Technical Implementer
- Related Capabilities: CAP-004, CAP-005, CAP-006
- Trigger: User submits verification evidence.
- Preconditions: Source registered and project context active.
- Primary Path:
  1. Validate evidence format and tenant context.
  2. Execute verification challenge.
  3. Mark source as verified on success.
- Alternate Path: Verification remains pending if asynchronous evidence channel is selected.
- Failure Path: Verification challenge fails or expires.
- Recovery Path: User submits updated evidence and retries within allowed window.
- State Transitions: Source.Proposed -> Source.Verified or Source.Disabled.
- Domain Events: SourceRegistered, SourceVerified, SourceDisabled.
- Authorization: Authorized project operator role required.
- Security Notes: Prevent unauthorized property binding.
- Audit and Observability: Persist verification evidence hash and decision trail.
- Acceptance Criteria: AC-WF-003

## WF-004 Manage Source Scope

- Identifier: WF-004
- Purpose: Maintain active source scope for crawling and evaluation.
- Actors: Marketing Operator, Technical Implementer
- Related Capabilities: CAP-006, CAP-007
- Trigger: Source add, update, disable, or remove request.
- Preconditions: Project active and at least one verified source exists.
- Primary Path:
  1. Validate source action request.
  2. Apply scope change under policy constraints.
  3. Persist source state and emit event.
- Alternate Path: Scope change queued for review when policy requires approval.
- Failure Path: Requested source action violates boundary or entitlement policy.
- Recovery Path: User adjusts request to policy-compliant scope.
- State Transitions: Source.Verified <-> Source.Active; Source.Active -> Source.Disabled or Source.Removed.
- Domain Events: SourceActivated, SourceDisabled, SourceRemoved.
- Authorization: Project operator with source-management permissions.
- Security Notes: Source scope must not cross tenant boundaries.
- Audit and Observability: Full source lifecycle events recorded with actor identity.
- Acceptance Criteria: AC-WF-004

## WF-005 Execute Crawl And Ingestion

- Identifier: WF-005
- Purpose: Crawl active sources and ingest evidence artifacts.
- Actors: Automation scheduler, Marketing Operator
- Related Capabilities: CAP-007, CAP-008
- Trigger: Manual crawl request or scheduled run.
- Preconditions: Project active, source set active, entitlement valid.
- Primary Path:
  1. Queue crawl run with bounded policy limits.
  2. Start crawl and collect artifacts.
  3. Transition ingestion through queued and processing states.
  4. Mark crawl completed when ingestion reaches terminal success state.
- Alternate Path: Partial crawl executes when some sources are temporarily unavailable.
- Failure Path: Crawl or ingestion fails for critical segment.
- Recovery Path: Retry failed segments under controlled retry policy.
- State Transitions: Crawl.Queued -> Crawl.Running -> Crawl.Completed or Crawl.Failed; Ingestion.Queued -> Ingestion.Processing -> Ingestion.Complete or Ingestion.Failed.
- Domain Events: CrawlQueued, CrawlStarted, CrawlCompleted, CrawlFailed.
- Authorization: Trigger requires operator or scheduler authority.
- Security Notes: Crawler must respect legal and configured scope boundaries.
- Audit and Observability: Capture run_id, correlation_id, and source-level status.
- Acceptance Criteria: AC-WF-005

## WF-006 Process Parsing And Validation Pipeline

- Identifier: WF-006
- Purpose: Transform raw crawl artifacts into validated evaluation inputs.
- Actors: System automation
- Related Capabilities: CAP-008, CAP-009, CAP-010, CAP-011
- Trigger: Ingestion completion signal.
- Preconditions: Ingestion artifacts available and not quarantined.
- Primary Path:
  1. Parse collected artifacts.
  2. Validate structure and required fields.
  3. Persist normalized evidence entries.
  4. Mark evaluation input readiness.
- Alternate Path: Non-critical parse failures are recorded while pipeline continues.
- Failure Path: Critical parser failure prevents evaluation readiness.
- Recovery Path: Re-run parser for failed subset after issue correction.
- State Transitions: Ingestion.Complete -> Evaluation.PendingInputs -> Evaluation.Ready.
- Domain Events: IngestionCompleted, ParsingCompleted, EvaluationInputsReady.
- Authorization: Internal service role only.
- Security Notes: Input sanitation and untrusted content handling are mandatory.
- Audit and Observability: Parse error taxonomy and counts by source captured.
- Acceptance Criteria: AC-WF-006

## WF-007 Generate Findings From Checks

- Identifier: WF-007
- Purpose: Convert technical, content, and structured-data checks into findings.
- Actors: System automation
- Related Capabilities: CAP-009, CAP-010, CAP-011, CAP-013, CAP-014
- Trigger: Evaluation input readiness.
- Preconditions: Check definitions and model versions available.
- Primary Path:
  1. Execute check set.
  2. Bind check results to evidence references.
  3. Create or update findings with lifecycle state.
- Alternate Path: Low-confidence check outputs are marked review-required.
- Failure Path: Check execution interruption blocks finding publication.
- Recovery Path: Resume check execution from last consistent checkpoint.
- State Transitions: Evaluation.Ready -> Evaluation.Running -> Evaluation.Completed; Issue.Open creation for applicable findings.
- Domain Events: CheckResultCreated, IssueCreated, EvaluationCompleted.
- Authorization: Internal service role with tenant scoping.
- Security Notes: Ensure check outputs cannot access data outside tenant scope.
- Audit and Observability: Track check execution counts, confidence ranges, and failure reasons.
- Acceptance Criteria: AC-WF-007

## WF-008 Calculate Score From Findings

- Identifier: WF-008
- Purpose: Produce explainable score snapshots from governed findings and evidence.
- Actors: System automation
- Related Capabilities: CAP-012, CAP-015, CAP-018
- Trigger: Evaluation completed with findings.
- Preconditions: Required score inputs available.
- Primary Path:
  1. Collect findings eligible for scoring.
  2. Apply governed score model version.
  3. Persist score snapshot and movement attribution.
- Alternate Path: Score computed with partial component status when non-critical components are unavailable.
- Failure Path: Missing governed inputs prevent score snapshot generation.
- Recovery Path: Resolve missing inputs and rerun scoring for the evaluation.
- State Transitions: Evaluation.Completed -> ScoreSnapshot.Created.
- Domain Events: ScoreSnapshotCreated, ScoreRecalculated.
- Authorization: Internal service role.
- Security Notes: Score visibility controlled by role-based access.
- Audit and Observability: Persist score model version and delta explanation metadata.
- Acceptance Criteria: AC-WF-008

## WF-009 Generate Recommendations

- Identifier: WF-009
- Purpose: Generate actionable recommendations from findings and score context.
- Actors: System automation
- Related Capabilities: CAP-012, CAP-016, CAP-017
- Trigger: Score snapshot available and finding set stable.
- Preconditions: Citation-ready evidence exists for each candidate recommendation.
- Primary Path:
  1. Select findings requiring action.
  2. Generate recommendation artifacts with rationale and evidence links.
  3. Validate artifact schema and policy constraints.
- Alternate Path: AI-assisted generation fallback disabled; deterministic template path used.
- Failure Path: Artifact fails validation or lacks required evidence linkage.
- Recovery Path: Regenerate using fallback strategy with stricter constraints.
- State Transitions: Recommendation.Draft -> Recommendation.Published.
- Domain Events: RecommendationArtifactGenerated, RecommendationPublished, AIResponseRejected.
- Authorization: Internal service role for generation; operator role for publication control.
- Security Notes: Enforce AI safety and prompt integrity constraints.
- Audit and Observability: Log generation mode, model version, and validation outcomes.
- Acceptance Criteria: AC-WF-009

## WF-010 Prioritize And Publish Action Queue

- Identifier: WF-010
- Purpose: Produce prioritized execution queue for recommendations and report outcomes.
- Actors: Marketing Operator, Executive Buyer
- Related Capabilities: CAP-016, CAP-017, CAP-018, CAP-022
- Trigger: Recommendation publication completed.
- Preconditions: Recommendation set available.
- Primary Path:
  1. Apply impact, confidence, and effort factors.
  2. Compute priority ordering with rationale.
  3. Publish queue and optional report export.
- Alternate Path: Operator applies manual ordering adjustment with explicit reason capture.
- Failure Path: Prioritization fails due to incomplete factor set.
- Recovery Path: Backfill missing factors and recalculate priority.
- State Transitions: Recommendation.Published -> Recommendation.Prioritized.
- Domain Events: RecommendationPrioritized, ReportGenerated, ExportAvailable.
- Authorization: Operator role for prioritization and export.
- Security Notes: Manual overrides require actor attribution.
- Audit and Observability: Track ranking inputs and manual override events.
- Acceptance Criteria: AC-WF-010

## WF-011 Trigger Reassessment

- Identifier: WF-011
- Purpose: Re-run discovery evaluation to update findings and scores.
- Actors: Marketing Operator, Scheduler automation
- Related Capabilities: CAP-007, CAP-015, CAP-019, CAP-020
- Trigger: Scheduled interval or manual reassessment request.
- Preconditions: Active project and source scope.
- Primary Path:
  1. Queue reassessment run.
  2. Execute crawl, parsing, and evaluation pipeline.
  3. Publish updated score and findings.
- Alternate Path: Scope-limited reassessment for selected sources.
- Failure Path: Reassessment aborts due to pipeline failure.
- Recovery Path: Retry failed stages without duplicating completed stages.
- State Transitions: Reassessment.Pending -> Reassessment.Running -> Reassessment.Completed or Reassessment.Failed.
- Domain Events: ReassessmentTriggered, EvaluationCompleted, ScoreRecalculated.
- Authorization: Operator or scheduler permission required.
- Security Notes: Preserve tenant boundaries across historical run linking.
- Audit and Observability: Link reassessment runs to prior run_id lineage.
- Acceptance Criteria: AC-WF-011

## WF-012 Compare Historical Results

- Identifier: WF-012
- Purpose: Present prior-versus-current discoverability outcomes with attributable deltas.
- Actors: Executive Buyer, Marketing Operator
- Related Capabilities: CAP-014, CAP-015, CAP-019, CAP-020
- Trigger: User opens historical comparison view.
- Preconditions: Two or more completed evaluations available.
- Primary Path:
  1. Retrieve baseline and comparison runs.
  2. Compute score, issue, and recommendation deltas.
  3. Render attributable trend narrative.
- Alternate Path: User selects custom date range for non-consecutive run comparison.
- Failure Path: Comparison blocked due to incompatible or missing baseline data.
- Recovery Path: User selects valid run pair or system rebuilds comparison index.
- State Transitions: No domain entity transition required; read-model generation lifecycle.
- Domain Events: ComparisonGenerated.
- Authorization: Viewer role with historical data permission.
- Security Notes: Historical access restricted by tenant scope.
- Audit and Observability: Log query latency and selected baseline references.
- Acceptance Criteria: AC-WF-012

## WF-013 Manage Roles And Access Policies

- Identifier: WF-013
- Purpose: Administer role assignment and access policy updates.
- Actors: Organization Administrator, Security Operator
- Related Capabilities: CAP-001, CAP-002, CAP-024
- Trigger: Admin modifies role or policy configuration.
- Preconditions: Organization active and actor has policy-management rights.
- Primary Path:
  1. Validate role change request.
  2. Apply policy update.
  3. Re-evaluate session and permission contexts.
- Alternate Path: Role update staged for approval when dual-control required.
- Failure Path: Update blocked due to policy conflict or insufficient privilege.
- Recovery Path: Submit corrected policy set or obtain required approval.
- State Transitions: RoleAssignment.Pending -> RoleAssignment.Active; AccessPolicy.Draft -> AccessPolicy.Active.
- Domain Events: RoleGranted, RoleRevoked, PolicyUpdated.
- Authorization: Security-sensitive privileges required.
- Security Notes: Enforce least privilege and immutable audit logs.
- Audit and Observability: Record actor, policy diff, and enforcement timestamp.
- Acceptance Criteria: AC-WF-013

## WF-014 Deliver Notifications

- Identifier: WF-014
- Purpose: Dispatch notifications based on defined lifecycle and failure events.
- Actors: System automation, Support Operator
- Related Capabilities: CAP-021
- Trigger: Event routing policy identifies notification condition.
- Preconditions: Notification policy and recipient mapping configured.
- Primary Path:
  1. Build notification payload from event and context.
  2. Apply recipient authorization and channel policy.
  3. Dispatch notification and persist delivery status.
- Alternate Path: Delayed delivery channel used when immediate channel unavailable.
- Failure Path: Dispatch fails for all channels.
- Recovery Path: Retry with backoff and escalate to support queue.
- State Transitions: Notification.Pending -> Notification.Sent or Notification.Failed.
- Domain Events: NotificationSent, NotificationDeliveryFailed.
- Authorization: Internal service role for dispatch; admin role for policy changes.
- Security Notes: Sensitive payload redaction and recipient verification mandatory.
- Audit and Observability: Track delivery latency and failure rate by channel.
- Acceptance Criteria: AC-WF-014

## WF-015 Enforce Entitlements

- Identifier: WF-015
- Purpose: Gate operations based on plan limits and entitlements.
- Actors: System automation, Billing Operator
- Related Capabilities: CAP-024, CAP-025
- Trigger: User action requires entitlement check.
- Preconditions: Active plan and current usage counters exist.
- Primary Path:
  1. Evaluate operation against plan constraints.
  2. Allow operation when within limits.
  3. Update usage counters.
- Alternate Path: Soft-limit warning issued before hard block threshold.
- Failure Path: Operation blocked due to entitlement violation.
- Recovery Path: Upgrade plan or reduce usage and retry action.
- State Transitions: EntitlementEvaluation.Allowed or EntitlementEvaluation.Blocked.
- Domain Events: EntitlementChecked, EntitlementViolationDetected.
- Authorization: Server-side enforcement only.
- Security Notes: No client-side trust for entitlement decisions.
- Audit and Observability: Persist entitlement decision with limit snapshot.
- Acceptance Criteria: AC-WF-015

## WF-016 Export Reports And Data

- Identifier: WF-016
- Purpose: Generate and deliver authorized export packages.
- Actors: Marketing Operator, Executive Buyer, Technical Implementer
- Related Capabilities: CAP-022, CAP-025
- Trigger: Authorized export request submitted.
- Preconditions: Exportable artifacts available and policy constraints satisfied.
- Primary Path:
  1. Validate export scope and recipient permissions.
  2. Generate export package.
  3. Publish secure retrieval option.
- Alternate Path: Export queued for asynchronous completion when data volume is large.
- Failure Path: Export generation fails or policy denies request.
- Recovery Path: Narrow scope or correct policy mismatch and retry.
- State Transitions: Export.Pending -> Export.Available -> Export.Expired or Export.Revoked.
- Domain Events: ExportRequested, ExportAvailable, ExportRevoked.
- Authorization: Requester must hold export permission in tenant scope.
- Security Notes: Signed access and expiration policy required.
- Audit and Observability: Track requester, scope, and retrieval events.
- Acceptance Criteria: AC-WF-016

## WF-017 Handle Incident And Recovery

- Identifier: WF-017
- Purpose: Detect and respond to operational incidents affecting workflows.
- Actors: Support Operator, Security Operator
- Related Capabilities: CAP-008, CAP-013, CAP-021, CAP-023
- Trigger: Error budget breach, service degradation, or incident declaration.
- Preconditions: Incident signal detected by observability controls.
- Primary Path:
  1. Correlate incident across workflow telemetry.
  2. Classify severity and impact scope.
  3. Execute approved recovery playbook.
  4. Verify service restoration and close incident.
- Alternate Path: Temporary mitigation applied while root-cause fix is pending.
- Failure Path: Recovery actions fail to restore service.
- Recovery Path: Escalate to emergency response and initiate fallback mode.
- State Transitions: Incident.Open -> Incident.Mitigated -> Incident.Resolved.
- Domain Events: IncidentRaised, IncidentMitigated, IncidentResolved.
- Authorization: Incident response roles required for privileged actions.
- Security Notes: Break-glass actions require dual control and high-fidelity audit trails.
- Audit and Observability: Record timeline, decisions, and affected workflows.
- Acceptance Criteria: AC-WF-017

## WF-018 Investigate And Audit Security Or Compliance Events

- Identifier: WF-018
- Purpose: Support forensic investigation and compliance evidence production.
- Actors: Security Operator, Chief Security
- Related Capabilities: CAP-023
- Trigger: Security anomaly, compliance inquiry, or formal audit request.
- Preconditions: Relevant logs and evidence retention windows active.
- Primary Path:
  1. Collect correlated audit and observability records.
  2. Reconstruct event chain.
  3. Produce investigation summary with findings and required actions.
- Alternate Path: Partial evidence scenario documented with confidence limits.
- Failure Path: Missing logs prevent complete reconstruction.
- Recovery Path: Execute gap remediation and update control requirements.
- State Transitions: Investigation.Open -> Investigation.Reported -> Investigation.Closed.
- Domain Events: SecurityInvestigationOpened, SecurityInvestigationClosed.
- Authorization: Restricted to security roles with explicit investigation rights.
- Security Notes: Preserve chain-of-custody and evidentiary integrity.
- Audit and Observability: Full access trail for all investigation queries and exports.
- Acceptance Criteria: AC-WF-018

## Dependencies

- [INDEX.md](INDEX.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [ACCEPTANCE_AND_TEST_MAPPING.md](ACCEPTANCE_AND_TEST_MAPPING.md)
- [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md)
- [../016 STATE_MODEL.md](../016%20STATE_MODEL.md)
- [../017 ERROR_MODEL.md](../017%20ERROR_MODEL.md)
- [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md)

## Change Control

Any normative workflow change MUST:

1. preserve identifier stability
2. update related capabilities and product rules
3. update acceptance criteria mappings
4. update traceability rows and owner decision references where applicable
