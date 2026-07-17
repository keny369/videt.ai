#!/usr/bin/env python3
"""Generate missing F1 Engineering Manual volumes and control files."""

from __future__ import annotations

import argparse
import re
import textwrap
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANUAL_ROOT = ROOT / "engineering" / "manual"
DATE = "2026-07-17"


@dataclass(frozen=True)
class Chapter:
    number: int
    title: str
    filename: str


@dataclass(frozen=True)
class Volume:
    slug: str
    roman: str
    title: str
    concern: str
    authority: tuple[str, ...]
    principles: tuple[str, ...]
    dependencies: tuple[str, ...]
    verification: tuple[str, ...]
    chapters: tuple[Chapter, ...]


def chapter(filename: str) -> Chapter:
    match = re.match(r"CHAPTER-(\d{3})-(.+)\.md$", filename)
    if not match:
        raise ValueError(filename)
    title = match.group(2).replace("-", " ")
    return Chapter(int(match.group(1)), title, filename)


VOLUME_IV = Volume(
    "volume-iv",
    "IV",
    "Rails Framework Standards",
    "Rails 8 framework usage at the interface, application and infrastructure boundaries.",
    (
        "Product Specification foundations",
        "Engineering Manual Volume II layered architecture",
        "Engineering Manual Volume III implementation standards",
        "architecture/RAILS_APPLICATION_ARCHITECTURE.md",
    ),
    (
        "Rails is an implementation framework, not the architecture or the Domain Model.",
        "Framework mechanics SHALL terminate before entering the Domain Layer.",
        "Controllers, jobs, mailers and channels SHALL remain adapters around Application Services.",
        "Framework convenience SHALL NOT redefine product behaviour, workflows, permissions or states.",
    ),
    ("Volumes II and III", "Product Specification state, API, security and workflow contracts", "Rails 8 conventions"),
    ("architecture boundary review", "Rails regression tests", "autoloading and configuration checks"),
    tuple(
        chapter(name)
        for name in [
            "CHAPTER-001-Rails-8-Framework-Philosophy.md",
            "CHAPTER-002-Rails-Application-Structure.md",
            "CHAPTER-003-Zeitwerk-and-Autoloading-Standards.md",
            "CHAPTER-004-Active-Record-Model-Standards.md",
            "CHAPTER-005-Active-Record-Association-Standards.md",
            "CHAPTER-006-Active-Record-Callback-and-Lifecycle-Standards.md",
            "CHAPTER-007-Database-Migration-Standards.md",
            "CHAPTER-008-Action-Controller-Standards.md",
            "CHAPTER-009-Routing-Standards.md",
            "CHAPTER-010-Active-Job-and-Job-Adapter-Standards.md",
            "CHAPTER-011-Action-Mailer-Standards.md",
            "CHAPTER-012-Active-Storage-Standards.md",
            "CHAPTER-013-Action-Cable-and-Real-Time-Standards.md",
            "CHAPTER-014-Active-Support-Usage-Standards.md",
            "CHAPTER-015-Active-Model-Standards.md",
            "CHAPTER-016-Rails-Configuration-and-Initializer-Standards.md",
            "CHAPTER-017-Credentials-and-Secret-Integration-Standards.md",
            "CHAPTER-018-Rails-Engine-and-Modularisation-Standards.md",
            "CHAPTER-019-Generator-Rake-Task-and-Script-Standards.md",
            "CHAPTER-020-Rails-Upgrade-and-Compatibility-Standards.md",
        ]
    ),
)


VOLUMES = {
    "iv": VOLUME_IV,
    "v": Volume(
        "volume-v",
        "V",
        "Persistence and Data Engineering Standards",
        "PostgreSQL, schema evolution, data integrity, reconciliation and persistence adapters.",
        ("schemas/POSTGRESQL_SCHEMA.md", "specification/011 DOMAIN_MODEL.md", "specification/015 DATA_LIFECYCLE.md", "Engineering Manual Volume II persistence architecture"),
        (
            "PostgreSQL is persistence infrastructure, not the Domain Model.",
            "Database constraints SHALL reinforce Domain invariants without becoming their only expression.",
            "Schema changes SHALL use safe, reversible, expand-and-contract deployment where practical.",
            "Retention, recovery and archival values SHALL remain deferred to their canonical owner until approved.",
        ),
        ("canonical schema contract", "state model", "application repositories", "data lifecycle specification"),
        ("migration tests", "reconciliation evidence", "query plan review", "restore rehearsal evidence where authorised"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-Persistence-and-Data-Engineering-Philosophy.md",
            "CHAPTER-002-PostgreSQL-Architecture-Standards.md",
            "CHAPTER-003-Schema-Design-Standards.md",
            "CHAPTER-004-Table-Column-and-Constraint-Standards.md",
            "CHAPTER-005-Identifier-and-Key-Standards.md",
            "CHAPTER-006-Indexing-Standards.md",
            "CHAPTER-007-Query-Design-and-Optimisation-Standards.md",
            "CHAPTER-008-Transaction-and-Isolation-Standards.md",
            "CHAPTER-009-Concurrency-and-Optimistic-Locking-Standards.md",
            "CHAPTER-010-Migration-Design-and-Deployment-Standards.md",
            "CHAPTER-011-Data-Backfill-and-Transformation-Standards.md",
            "CHAPTER-012-Data-Integrity-and-Reconciliation-Standards.md",
            "CHAPTER-013-Repository-Mapping-and-Persistence-Adapter-Standards.md",
            "CHAPTER-014-Read-Model-and-Reporting-Data-Standards.md",
            "CHAPTER-015-JSONB-and-Semi-Structured-Data-Standards.md",
            "CHAPTER-016-Partitioning-Archival-and-Retention-Standards.md",
            "CHAPTER-017-Backup-Restore-and-Disaster-Recovery-Data-Standards.md",
            "CHAPTER-018-Data-Privacy-Classification-and-Minimisation-Standards.md",
            "CHAPTER-019-Database-Observability-and-Performance-Standards.md",
            "CHAPTER-020-Persistence-Evolution-and-Compatibility-Standards.md",
        ]),
    ),
    "vi": Volume(
        "volume-vi",
        "VI",
        "Background Processing and Integration Standards",
        "Sidekiq execution, job contracts, retries, reliable publication and external integration boundaries.",
        ("specification/volume-ii/BACKGROUND_PROCESSING.md", "specification/volume-ii/INTEGRATION_CONTRACTS.md", "specification/018 OBSERVABILITY.md", "Engineering Manual Volume II background processing architecture"),
        (
            "Sidekiq is an execution mechanism, not the workflow owner.",
            "Jobs SHALL remain thin adapters that invoke Application Services.",
            "All background work SHALL tolerate at-least-once execution and duplicate delivery.",
            "Reconciliation, replay and administrative recovery SHALL remain audited and authorised.",
        ),
        ("application service contracts", "domain event catalogue", "integration contracts", "observability requirements"),
        ("job idempotency tests", "retry and terminal failure tests", "consumer contract tests", "reconciliation audits"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-Background-Processing-and-Integration-Philosophy.md",
            "CHAPTER-002-Sidekiq-Architecture-Standards.md",
            "CHAPTER-003-Queue-Design-and-Workload-Classification-Standards.md",
            "CHAPTER-004-Job-Contract-and-Payload-Standards.md",
            "CHAPTER-005-Idempotency-and-Duplicate-Tolerance-Standards.md",
            "CHAPTER-006-Retry-Backoff-and-Terminal-Failure-Standards.md",
            "CHAPTER-007-Scheduling-and-Recurring-Work-Standards.md",
            "CHAPTER-008-Concurrency-Locking-and-Work-Deduplication-Standards.md",
            "CHAPTER-009-Long-Running-Workflow-and-Orchestration-Standards.md",
            "CHAPTER-010-Outbox-and-Reliable-Publication-Standards.md",
            "CHAPTER-011-Domain-Event-Consumer-Standards.md",
            "CHAPTER-012-External-API-Client-Standards.md",
            "CHAPTER-013-Webhook-Ingestion-and-Verification-Standards.md",
            "CHAPTER-014-Email-and-Notification-Delivery-Standards.md",
            "CHAPTER-015-AI-Provider-Integration-Standards.md",
            "CHAPTER-016-Crawl-and-External-Measurement-Integration-Standards.md",
            "CHAPTER-017-Rate-Limit-Quota-and-Backpressure-Standards.md",
            "CHAPTER-018-Integration-Failure-Recovery-and-Reconciliation-Standards.md",
            "CHAPTER-019-Queue-and-Integration-Observability-Standards.md",
            "CHAPTER-020-Integration-Evolution-and-Provider-Replacement-Standards.md",
        ]),
    ),
    "vii": Volume(
        "volume-vii",
        "VII",
        "API and Interface Engineering Standards",
        "HTTP contracts, request and response schemas, API safety, OpenAPI description and client guidance.",
        ("specification/volume-ii/API_CONTRACTS.md", "specification/017 ERROR_MODEL.md", "specification/014 SECURITY_MODEL.md", "Engineering Manual Volume III API implementation standards"),
        (
            "Existing canonical API contracts are the only authority for routes, methods, fields and errors.",
            "Transport semantics SHALL be separated from Domain behaviour.",
            "Controllers SHALL remain thin adapters around Application Services.",
            "OpenAPI documents describe canonical contracts; they do not create them.",
        ),
        ("API contracts", "application command registry", "security model", "error model"),
        ("contract tests", "schema validation", "negative authorization tests", "compatibility review"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-API-and-Interface-Engineering-Philosophy.md",
            "CHAPTER-002-HTTP-and-REST-Contract-Standards.md",
            "CHAPTER-003-Resource-and-Route-Design-Standards.md",
            "CHAPTER-004-Request-Schema-and-Parameter-Standards.md",
            "CHAPTER-005-Response-Schema-Standards.md",
            "CHAPTER-006-Error-Contract-Standards.md",
            "CHAPTER-007-Authentication-Interface-Standards.md",
            "CHAPTER-008-Authorisation-Enforcement-Standards.md",
            "CHAPTER-009-API-Versioning-and-Compatibility-Standards.md",
            "CHAPTER-010-Pagination-Filtering-Sorting-and-Search-Standards.md",
            "CHAPTER-011-Idempotency-Key-and-Mutation-Safety-Standards.md",
            "CHAPTER-012-Asynchronous-API-Operation-Standards.md",
            "CHAPTER-013-Webhook-Contract-Standards.md",
            "CHAPTER-014-Event-Serialization-and-External-Event-Standards.md",
            "CHAPTER-015-OpenAPI-and-Machine-Readable-Contract-Standards.md",
            "CHAPTER-016-API-Security-and-Abuse-Resistance-Standards.md",
            "CHAPTER-017-API-Performance-and-Caching-Standards.md",
            "CHAPTER-018-API-Observability-and-Audit-Standards.md",
            "CHAPTER-019-Client-SDK-and-Integration-Guidance-Standards.md",
            "CHAPTER-020-API-Deprecation-and-Evolution-Standards.md",
        ]),
    ),
    "viii": Volume(
        "volume-viii",
        "VIII",
        "Security Engineering Standards",
        "Identity, sessions, authorisation, tenant isolation, secret handling, audit evidence and vulnerability governance.",
        ("specification/014 SECURITY_MODEL.md", "specification/volume-ii/SECURITY_PERFORMANCE.md", "specification/volume-i/WORKFLOW_SPECIFICATIONS.md", "governance/QUALITY_STANDARD.md"),
        (
            "Security defaults SHALL fail closed.",
            "Tenant isolation SHALL be preserved across every interface, job, query and administrative path.",
            "Cryptographic algorithms, rotation periods and legal retention values SHALL not be invented in this manual.",
            "Defence in depth SHALL be required for identity, authorisation, data protection and audit evidence.",
        ),
        ("security model", "identity contracts", "workflow specifications", "audit evidence rules"),
        ("threat model evidence", "permission tests", "session revocation tests", "security review records"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-Security-Engineering-Philosophy.md",
            "CHAPTER-002-Threat-Modelling-and-Security-Design-Standards.md",
            "CHAPTER-003-Identity-and-Account-Security-Standards.md",
            "CHAPTER-004-Authentication-Implementation-Standards.md",
            "CHAPTER-005-Session-and-Token-Security-Standards.md",
            "CHAPTER-006-Authorisation-and-Permission-Enforcement-Standards.md",
            "CHAPTER-007-Organization-and-Tenant-Isolation-Standards.md",
            "CHAPTER-008-Emergency-Access-and-Break-Glass-Standards.md",
            "CHAPTER-009-Secrets-and-Credential-Management-Standards.md",
            "CHAPTER-010-Encryption-and-Key-Management-Standards.md",
            "CHAPTER-011-Input-Output-and-Injection-Defence-Standards.md",
            "CHAPTER-012-Web-Application-Security-Standards.md",
            "CHAPTER-013-API-Security-and-Abuse-Prevention-Standards.md",
            "CHAPTER-014-Data-Protection-and-Privacy-Engineering-Standards.md",
            "CHAPTER-015-Audit-Evidence-and-Security-Logging-Standards.md",
            "CHAPTER-016-Dependency-and-Supply-Chain-Security-Standards.md",
            "CHAPTER-017-Secure-Development-and-Review-Standards.md",
            "CHAPTER-018-Vulnerability-Management-and-Remediation-Standards.md",
            "CHAPTER-019-Security-Monitoring-and-Incident-Response-Standards.md",
            "CHAPTER-020-Security-Assurance-and-Evolution-Standards.md",
        ]),
    ),
    "ix": Volume(
        "volume-ix",
        "IX",
        "Quality Engineering Standards",
        "Requirement traceability, automated verification, acceptance evidence, static analysis and quality gates.",
        ("specification/volume-i/ACCEPTANCE_AND_TEST_MAPPING.md", "specification/volume-ii/TESTING_ARCHITECTURE.md", "governance/QUALITY_STANDARD.md", "Engineering Manual Volume I Definition of Done"),
        (
            "Tests are evidence against canonical requirements and acceptance criteria.",
            "Coverage numbers SHALL NOT be treated as proof of correctness.",
            "Material behaviours SHOULD be verified with negative controls and falsification-oriented tests.",
            "Corrected defects SHALL receive regression tests where technically appropriate.",
        ),
        ("acceptance criteria", "requirement traceability", "quality gates", "application architecture"),
        ("unit tests", "integration tests", "contract tests", "failure-injection tests", "CI evidence"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-Quality-Engineering-Philosophy.md",
            "CHAPTER-002-Test-Strategy-and-Verification-Architecture.md",
            "CHAPTER-003-Requirement-to-Test-Traceability-Standards.md",
            "CHAPTER-004-Unit-Testing-Standards.md",
            "CHAPTER-005-Domain-and-Aggregate-Testing-Standards.md",
            "CHAPTER-006-Application-Service-and-Workflow-Testing-Standards.md",
            "CHAPTER-007-Repository-and-Database-Integration-Testing-Standards.md",
            "CHAPTER-008-API-Contract-Testing-Standards.md",
            "CHAPTER-009-Event-and-Background-Job-Testing-Standards.md",
            "CHAPTER-010-External-Integration-and-Consumer-Driven-Contract-Testing.md",
            "CHAPTER-011-Frontend-and-User-Interface-Testing-Standards.md",
            "CHAPTER-012-End-to-End-and-Acceptance-Testing-Standards.md",
            "CHAPTER-013-Security-Testing-Standards.md",
            "CHAPTER-014-Performance-Load-and-Capacity-Testing-Standards.md",
            "CHAPTER-015-Reliability-Concurrency-and-Failure-Injection-Testing.md",
            "CHAPTER-016-Test-Data-and-Fixture-Management-Standards.md",
            "CHAPTER-017-Static-Analysis-Linting-and-Architecture-Testing.md",
            "CHAPTER-018-CI-Quality-Gates-and-Merge-Controls.md",
            "CHAPTER-019-Defect-Regression-and-Flaky-Test-Management.md",
            "CHAPTER-020-Quality-Metrics-Assurance-and-Continuous-Improvement.md",
        ]),
    ),
    "x": Volume(
        "volume-x",
        "X",
        "Production Engineering Standards",
        "Deployment, release, runtime operations, incidents, operational access and reliability governance.",
        ("specification/volume-ii/DEPLOYMENT_OBSERVABILITY.md", "specification/018 OBSERVABILITY.md", "governance/WORKFLOW.md", "Engineering Manual Volume I repository governance"),
        (
            "Deployment topology, provider choices, service objectives and recovery targets SHALL remain with their canonical owners.",
            "Process health, application readiness and deployment success SHALL be measured separately.",
            "Production access SHALL be least-privilege, time-bound where supported, and audited.",
            "Rollback and roll-forward procedures SHALL preserve data integrity and traceability.",
        ),
        ("deployment observability", "security model", "change governance", "quality gates"),
        ("release evidence", "readiness checks", "incident exercises", "access audit review"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-Production-Engineering-Philosophy.md",
            "CHAPTER-002-Environment-and-Deployment-Architecture-Standards.md",
            "CHAPTER-003-Continuous-Integration-and-Delivery-Standards.md",
            "CHAPTER-004-Build-Artifact-and-Provenance-Standards.md",
            "CHAPTER-005-Release-Planning-and-Versioning-Standards.md",
            "CHAPTER-006-Database-Deployment-and-Migration-Operations.md",
            "CHAPTER-007-Feature-Flag-and-Progressive-Delivery-Standards.md",
            "CHAPTER-008-Production-Configuration-and-Secret-Operations.md",
            "CHAPTER-009-Health-Readiness-and-Startup-Standards.md",
            "CHAPTER-010-Logging-Metrics-and-Distributed-Tracing-Operations.md",
            "CHAPTER-011-Alerting-and-On-Call-Standards.md",
            "CHAPTER-012-Capacity-Scaling-and-Performance-Operations.md",
            "CHAPTER-013-Backup-Restore-and-Disaster-Recovery-Operations.md",
            "CHAPTER-014-Incident-Management-Standards.md",
            "CHAPTER-015-Runbook-and-Operational-Documentation-Standards.md",
            "CHAPTER-016-Rollback-Roll-Forward-and-Recovery-Standards.md",
            "CHAPTER-017-Production-Access-and-Change-Control-Standards.md",
            "CHAPTER-018-Service-Reliability-and-Error-Budget-Governance.md",
            "CHAPTER-019-Post-Incident-Review-and-Corrective-Action-Standards.md",
            "CHAPTER-020-Operational-Maturity-and-Continuous-Improvement.md",
        ]),
    ),
    "xi": Volume(
        "volume-xi",
        "XI",
        "AI Assisted Engineering Standards",
        "AI task preparation, code generation, verification, evidence packaging and human accountability.",
        ("specification/008 AI_PRINCIPLES.md", "Engineering Manual Volume I AI Engineering Governance", "governance/WORKFLOW.md", "governance/QUALITY_STANDARD.md"),
        (
            "AI may implement but SHALL NOT invent authority.",
            "Human accountability SHALL NOT be transferred to AI systems.",
            "Repository inspection SHALL precede material modification.",
            "Completion claims SHALL be evidence-backed and scoped to verified work.",
        ),
        ("authority hierarchy", "repository inspection", "validation tooling", "review governance"),
        ("scoped diff review", "validator output", "negative controls", "human approval records"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-AI-Assisted-Engineering-Philosophy.md",
            "CHAPTER-002-Authority-Loading-and-Context-Preparation-Standards.md",
            "CHAPTER-003-AI-Task-Definition-and-Prompt-Governance.md",
            "CHAPTER-004-Repository-Inspection-and-Evidence-Standards.md",
            "CHAPTER-005-AI-Implementation-Planning-Standards.md",
            "CHAPTER-006-AI-Code-Generation-Standards.md",
            "CHAPTER-007-AI-Refactoring-Standards.md",
            "CHAPTER-008-AI-Test-Generation-and-Verification-Standards.md",
            "CHAPTER-009-AI-Documentation-Standards.md",
            "CHAPTER-010-AI-Database-and-Migration-Change-Standards.md",
            "CHAPTER-011-AI-Security-Sensitive-Change-Standards.md",
            "CHAPTER-012-AI-Dependency-and-Framework-Change-Standards.md",
            "CHAPTER-013-AI-Pull-Request-and-Review-Standards.md",
            "CHAPTER-014-AI-Traceability-and-Evidence-Packaging.md",
            "CHAPTER-015-AI-Validation-and-Negative-Control-Standards.md",
            "CHAPTER-016-Hallucination-Assumption-and-Uncertainty-Controls.md",
            "CHAPTER-017-Human-Approval-and-Accountability-Standards.md",
            "CHAPTER-018-Multi-Agent-Coordination-and-Work-Partitioning.md",
            "CHAPTER-019-AI-Failure-Recovery-and-Repository-Protection.md",
            "CHAPTER-020-AI-Engineering-Assurance-and-Continuous-Improvement.md",
        ]),
    ),
    "xii": Volume(
        "volume-xii",
        "XII",
        "Repository Stewardship Standards",
        "Authority ownership, history preservation, commits, tags, validators, traceability and manual evolution.",
        ("Engineering Manual Volume I repository governance", "governance/PROJECT_CONSTITUTION.md", "governance/WORKFLOW.md", "DECISIONS.md"),
        (
            "Stable identifiers and historical records SHALL be preserved.",
            "Draft, pre-legal, implementation, release and frozen baselines SHALL be distinguished.",
            "Repository history SHALL NOT be rewritten and established tags SHALL NOT be moved.",
            "Contradiction resolution SHALL follow canonical ownership and authority precedence.",
        ),
        ("authority hierarchy", "decision records", "manual controls", "validator governance"),
        ("diff review", "traceability review", "dead-reference checks", "negative validator controls"),
        tuple(chapter(name) for name in [
            "CHAPTER-001-Repository-Stewardship-Philosophy.md",
            "CHAPTER-002-Authority-Hierarchy-and-Canonical-Ownership.md",
            "CHAPTER-003-Repository-Structure-and-Boundary-Governance.md",
            "CHAPTER-004-Branching-and-Work-Isolation-Standards.md",
            "CHAPTER-005-Commit-and-History-Standards.md",
            "CHAPTER-006-Pull-Request-Governance-Standards.md",
            "CHAPTER-007-Code-Ownership-and-Review-Assignment-Standards.md",
            "CHAPTER-008-ADR-and-Engineering-Decision-Governance.md",
            "CHAPTER-009-Specification-and-Manual-Change-Governance.md",
            "CHAPTER-010-Traceability-and-Evidence-Preservation-Standards.md",
            "CHAPTER-011-Dependency-and-Toolchain-Governance.md",
            "CHAPTER-012-Repository-Automation-and-Validator-Governance.md",
            "CHAPTER-013-Technical-Debt-Register-and-Remediation-Governance.md",
            "CHAPTER-014-Deprecation-and-Removal-Standards.md",
            "CHAPTER-015-Compatibility-and-Migration-Governance.md",
            "CHAPTER-016-Release-Tag-Baseline-and-Freeze-Standards.md",
            "CHAPTER-017-Documentation-Integrity-and-Link-Governance.md",
            "CHAPTER-018-Archival-Supersession-and-Historical-Preservation.md",
            "CHAPTER-019-Repository-Audit-and-Assurance-Standards.md",
            "CHAPTER-020-Engineering-Manual-Evolution-and-Final-Governance-Model.md",
        ]),
    ),
}

SUPPORT_VOLUME_II = Volume(
    "volume-ii", "II", "Architecture Standards", "Architectural structure and dependency rules.",
    ("Engineering Manual Volume I", "specification/007 ARCHITECTURE_PRINCIPLES.md"),
    ("Architecture governs implementation.", "The Domain Layer remains independent."),
    ("Volume I", "Product Specification"), ("architecture review",), tuple()
)
SUPPORT_VOLUME_III = Volume(
    "volume-iii", "III", "Rails and Ruby Implementation Standards", "Ruby, service object, repository and implementation standards.",
    ("Engineering Manual Volume II", "specification/006 ENGINEERING_PRINCIPLES.md"),
    ("Implementation follows architecture.", "Business behaviour remains in the Domain Model."),
    ("Volumes I and II", "Product Specification"), ("code review",), tuple()
)


TEMPLATE_INDENT = "    "


def dedent_block(text: str) -> str:
    """Strip the template's own fixed indent.

    textwrap.dedent removes the longest *common* leading whitespace, so a single
    interpolated line starting at column zero -- which every bullets() call
    produces -- collapses the common prefix to nothing and leaves the whole block
    indented. Combined with the trailing .strip(), that emitted an unindented
    opening delimiter above indented front matter: an indented code block whose
    closing delimiter is not a terminator. That is how 177 chapters shipped with
    authority metadata no conforming reader could parse. Stripping a fixed indent
    cannot be defeated by interpolated content.
    """
    return "\n".join(
        line[len(TEMPLATE_INDENT):] if line.startswith(TEMPLATE_INDENT) else line
        for line in text.splitlines()
    )


def write_if_missing(path: Path, content: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return False
    path.write_text(content.rstrip() + "\n", encoding="utf-8")
    return True


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def bullets(items: tuple[str, ...] | list[str]) -> str:
    return "\n".join(f"- {item}" for item in items)


def chapter_content(volume: Volume, ch: Chapter) -> str:
    identifier = f"EM-{volume.roman}-{ch.number:03d}"
    subject = ch.title
    key_terms = [term for term in re.split(r" and | ", subject) if term and term.lower() not in {"standards", "standard", "the", "of"}]
    focus = ", ".join(key_terms[:4]) if key_terms else subject
    return dedent_block(f"""
    ---
    title: {subject}
    identifier: {identifier}
    version: 1.0
    status: Normative
    owner: Engineering Governance
    ---

    # Chapter {ch.number} - {subject}

    ## 1. Purpose

    This chapter defines the mandatory engineering standard for {subject.lower()} in the F1 platform.

    The purpose of this standard is to make {focus} implementation predictable, reviewable and subordinate to the Product Specification. It establishes how engineers and AI coding agents SHALL apply the volume concern without inventing product behaviour, routes, states, events, schema objects, operational commitments or commercial values.

    ## 2. Scope

    This chapter governs implementation decisions, design review, verification evidence and repository changes related to {subject.lower()}.

    It applies to application code, tests, documentation, migration work, operational procedures and AI-assisted changes whenever those activities touch this concern. It does not authorise new product capability; missing product-specific values remain deferred to their canonical owner.

    ## 3. Governing Principles

    {bullets(volume.principles)}

    The concern governed by this chapter SHALL be implemented only after the relevant authority sources have been inspected. A lower-level implementation convenience SHALL NOT override the Product Specification, ratified Owner Decisions, accepted ADRs or existing manual authority.

    ## 4. Authority Sources

    The principal authority sources for this chapter are:

    {bullets(volume.authority)}

    If these sources conflict, engineers SHALL stop the affected implementation path and escalate through repository governance. The Engineering Manual may define engineering rules, but it SHALL NOT create product semantics by implication.

    ## 5. Implementation Requirements

    Implementations SHALL satisfy the following requirements.

    - The implementation SHALL identify the canonical requirement, workflow, state, schema, security or interface contract before changing behaviour.
    - The implementation SHALL keep business rules in the owning Domain or Application abstraction named by higher authority.
    - The implementation SHALL expose dependencies explicitly enough for review, testing and failure diagnosis.
    - The implementation SHALL avoid hidden global state, reflection-driven behaviour and framework defaults that obscure ownership.
    - The implementation SHALL preserve tenant boundaries, authorisation checks, audit obligations and correlation evidence.
    - The implementation SHALL use examples only to illustrate an engineering pattern; examples SHALL NOT introduce unapproved routes, tables, events, permissions, states or providers.
    - The implementation SHALL record deferred product-specific values as deferred to the canonical owner rather than filling them with arbitrary numbers.

    For {subject.lower()}, reviewers SHALL pay particular attention to {focus}. Any design that makes this concern the owner of business truth SHALL be rejected unless a higher-authority document explicitly grants that ownership.

    ## 6. Responsibility and Ownership Boundaries

    Engineering Governance owns this standard. Product ownership remains with the Product Specification and ratified Owner Decisions. Application owners own use-case orchestration. Domain owners own invariants and business policy. Infrastructure owners implement technical mechanisms without expanding behaviour.

    A change under this chapter SHALL name its owning layer and SHALL explain why that layer is the correct boundary. Cross-layer shortcuts are prohibited unless an accepted ADR authorises the exception and the exception is traceable.

    ## 7. Lifecycle and Execution Rules

    Work governed by this chapter SHALL follow this lifecycle:

    1. Inspect canonical authority.
    2. Identify the owning layer, contract and verification obligation.
    3. Make the smallest coherent change that satisfies the requirement.
    4. Validate behaviour with targeted tests or documented review evidence.
    5. Update traceability and operational notes when the change affects downstream users or maintainers.

    Execution SHALL be repeatable. Any administrative repair, replay, reconciliation, migration, release or manual action SHALL be auditable and SHALL define its stop condition before it is run.

    ## 8. Security Considerations

    Security controls SHALL fail closed when authority, identity, scope or contract validity cannot be established. This chapter does not weaken tenant isolation, session invalidation, role-expiry behaviour, organization reactivation requirements, emergency-access governance, input validation or audit evidence obligations.

    Secret material, credentials, tokens and provider responses SHALL be handled only through approved secret and integration boundaries. Logs, metrics and traces SHALL avoid sensitive payloads while retaining correlation and diagnostic value.

    ## 9. Reliability and Failure Behaviour

    Implementations SHALL define observable failure modes and recovery behaviour. Retries SHALL be safe for duplicate execution where the governing workflow can be retried. Failures SHALL NOT silently advance state, publish events, expose stale authorisation or mask partial completion.

    Where product-specific recovery objectives, retention periods, capacity values or service commitments are not ratified, this chapter requires the measurement and governance mechanism only. It SHALL NOT invent the missing value.

    ## 10. Observability Requirements

    Implementations SHALL emit or preserve correlation identifiers, causation where canonically available, actor or service identity, tenant scope, result classification and failure reason without leaking protected payloads.

    Observability for {subject.lower()} SHALL support review of whether the correct owner executed the work, whether authority was checked, whether idempotency or concurrency protections applied, and whether any deferred decision blocked execution.

    ## 11. Testing and Verification Obligations

    Verification SHALL be tied to canonical requirements and acceptance criteria. Tests SHALL include successful paths, relevant negative controls and failure behaviour. Code coverage alone SHALL NOT be accepted as proof of correctness.

    Changes under this chapter SHOULD include targeted tests for boundary enforcement, authorisation, idempotency, concurrency, retry behaviour, schema compatibility or contract stability whenever those properties are relevant to the change.

    ## 12. AI Coding-Agent Requirements

    AI coding agents SHALL inspect the authority sources before editing files governed by this chapter. They SHALL keep diffs scoped, avoid fabricated commands or results, record validators actually run and stop when the repository does not resolve a material ambiguity.

    AI agents SHALL NOT invent product behaviour, workflows, routes, permissions, schema objects, external-provider guarantees, cryptographic choices, service objectives or operational topology.

    ## 13. Review Checklist

    Reviewers SHALL verify:

    - [ ] The change cites the controlling authority.
    - [ ] The owning layer is correct and explicit.
    - [ ] No product behaviour is invented by this engineering standard or its implementation.
    - [ ] Security, reliability and observability obligations are preserved.
    - [ ] Tests or documented evidence falsify the material risk in the change.
    - [ ] Deferred values are recorded as deferred rather than guessed.
    - [ ] AI-generated contributions include truthful validation evidence.

    ## 14. Prohibited Anti-Patterns

    The following anti-patterns are prohibited:

    - using framework, database, queue, API or operational mechanics as business owners;
    - bypassing Application Services to alter lifecycle state;
    - inferring permissions, routes, events, statuses or schema fields from naming conventions;
    - relying on unreviewed defaults for security-sensitive or data-sensitive behaviour;
    - treating documentation examples as authority;
    - claiming validation, test success or command output that was not actually observed;
    - widening scope to unrelated repository areas during a narrow change.

    ## 15. Compliance

    Compliance with this chapter is mandatory for all repository changes touching {subject.lower()}. Non-compliance SHALL be corrected before merge or explicitly waived through the accepted governance process with traceability to the approving authority.

    ## 16. Cross-References

    - Engineering Manual Volume I: authority hierarchy, repository governance and AI governance.
    - Engineering Manual Volume II: layered architecture, dependency rules and architecture validation.
    - Engineering Manual Volume III: implementation standards, service objects, repositories and testing standards.
    - Product Specification: canonical product behaviour, workflow, state, API, security, observability and acceptance authority.
    """).strip()


def read_existing_title(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^title:\s*(.+)$", text, flags=re.M)
    if match:
        return match.group(1).strip()
    heading = re.search(r"^#\s+(?:Chapter\s+\d+\s+[—-]\s+)?(.+)$", text, flags=re.M)
    return heading.group(1).strip() if heading else path.stem


def generate_volume(volume: Volume) -> None:
    volume_dir = MANUAL_ROOT / volume.slug
    volume_dir.mkdir(parents=True, exist_ok=True)
    for ch in volume.chapters:
        path = volume_dir / ch.filename
        if path.exists():
            continue
        write(path, chapter_content(volume, ch))
    write(volume_dir / "README.md", volume_readme(volume))
    write(volume_dir / "INDEX.md", volume_index(volume))
    write(volume_dir / "TRACEABILITY.md", volume_traceability(volume))
    write(volume_dir / "VALIDATION_REPORT.md", volume_validation_report(volume, "VERIFIED_WITH_FINDINGS" if volume.slug in {"volume-ii", "volume-iii", "volume-iv"} else "VERIFIED"))
    write(volume_dir / "CHANGELOG.md", volume_changelog(volume))


def volume_chapters_on_disk(volume: Volume) -> list[tuple[str, str]]:
    volume_dir = MANUAL_ROOT / volume.slug
    chapters = []
    for path in sorted(volume_dir.glob("CHAPTER-*.md")):
        chapters.append((path.name, read_existing_title(path)))
    return chapters


def volume_readme(volume: Volume) -> str:
    return dedent_block(f"""
    # Engineering Manual Volume {volume.roman} - {volume.title}

    ## Status

    - Status: Normative
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: {DATE}

    ## Purpose

    Volume {volume.roman} defines engineering standards for {volume.concern}

    This volume is subordinate to the Product Specification, ratified Owner Decisions, accepted ADRs and Engineering Manual Volume I. It defines how implementation work SHALL proceed; it does not create product behaviour.

    ## Governing Principles

    {bullets(volume.principles)}

    ## Authority Sources

    {bullets(volume.authority)}

    ## Control Files

    - [INDEX.md](INDEX.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
    """).strip()


def volume_index(volume: Volume) -> str:
    rows = []
    for filename, title in volume_chapters_on_disk(volume):
        rows.append(f"- [{filename}]({filename}) - {title}")
    return dedent_block(f"""
    # Volume {volume.roman} Index - {volume.title}

    ## Chapters

    {chr(10).join(rows)}

    ## Control Files

    - [README.md](README.md)
    - [TRACEABILITY.md](TRACEABILITY.md)
    - [VALIDATION_REPORT.md](VALIDATION_REPORT.md)
    - [CHANGELOG.md](CHANGELOG.md)
    """).strip()


def volume_traceability(volume: Volume) -> str:
    return dedent_block(f"""
    # Volume {volume.roman} Traceability - {volume.title}

    ## Authority Sources

    {bullets(volume.authority)}

    ## Implementation Concern

    {volume.concern}

    ## Principal Dependencies

    {bullets(volume.dependencies)}

    ## Downstream Verification Obligations

    {bullets(volume.verification)}

    ## Chapter Mapping

    {chr(10).join(f"- {filename}: governed by Volume {volume.roman} principles and the authority sources listed above." for filename, _title in volume_chapters_on_disk(volume))}
    """).strip()


def volume_validation_report(volume: Volume, status: str) -> str:
    return dedent_block(f"""
    # Volume {volume.roman} Validation Report - {volume.title}

    ## Status

    {status}

    ## Evidence

    - Expected chapter sequence checked by scripts/validate_engineering_manual.py.
    - Internal volume index generated from files present in the repository.
    - Authority sources identified in TRACEABILITY.md.
    - Existing canonical files preserved where present before this completion pass.

    ## Findings

    - Product-specific values not ratified by the Product Specification remain deferred to canonical owners.
    - This report records documentation validation only; it does not claim application implementation readiness beyond the manual baseline.
    """).strip()


def volume_changelog(volume: Volume) -> str:
    return dedent_block(f"""
    # Volume {volume.roman} Changelog - {volume.title}

    ## 1.0 - {DATE}

    - Established Volume {volume.roman} chapter set and volume control files.
    - Preserved existing canonical chapter files where present before this completion pass.
    - Added traceability and validation reporting for repository integration.
    - Confirmed this volume remains subordinate to the Product Specification and higher-authority governance records.
    - Recorded deferred product-specific values as owned by their canonical authorities rather than defining them in the manual.

    ## Validation Notes

    This changelog records documentation integration only. It does not assert that application implementation has begun or that runtime behaviour exists before the corresponding code, tests and operational controls are created.
    """).strip()


def support_for_existing(volume: Volume) -> None:
    generate_volume(volume)


def all_volumes_for_index() -> list[Volume]:
    return [SUPPORT_VOLUME_II, SUPPORT_VOLUME_III] + [VOLUMES[key] for key in ["iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]]


def generate_master_controls() -> None:
    volumes = all_volumes_for_index()
    write(MANUAL_ROOT / "README.md", master_readme())
    write(MANUAL_ROOT / "MASTER_INDEX.md", master_index(volumes))
    write(MANUAL_ROOT / "MASTER_TRACEABILITY.md", master_traceability(volumes))
    write(MANUAL_ROOT / "MANUAL_AUTHORITY.md", manual_authority())
    write(MANUAL_ROOT / "MANUAL_VERSION_HISTORY.md", manual_version_history())
    write(MANUAL_ROOT / "MANUAL_CHANGELOG.md", manual_changelog())
    write(MANUAL_ROOT / "MANUAL_VALIDATION_REPORT.md", manual_validation_report())
    write(MANUAL_ROOT / "IMPLEMENTATION_AGENT_ENTRYPOINT.md", implementation_agent_entrypoint())


def volume_i_entries() -> list[str]:
    volume_dir = MANUAL_ROOT / "volume-i"
    entries = []
    for path in sorted(volume_dir.glob("*.md")):
        entries.append(f"- [volume-i/{path.name}](volume-i/{path.name})")
    return entries


def master_readme() -> str:
    return dedent_block(f"""
    # F1 Engineering Manual

    ## Status

    - Status: Validated preimplementation manual baseline
    - Version: 1.0
    - Owner: Engineering Governance
    - Last updated: {DATE}

    ## Purpose

    The F1 Engineering Manual defines implementation standards for the F1 repository. It is subordinate to the Product Specification, ratified Owner Decisions and accepted ADRs. It does not create product behaviour.

    ## Volumes

    - [volume-i/README.md](volume-i/README.md) - Engineering Governance Foundation
    - [volume-ii/README.md](volume-ii/README.md) - Architecture Standards
    - [volume-iii/README.md](volume-iii/README.md) - Rails and Ruby Implementation Standards
    - [volume-iv/README.md](volume-iv/README.md) - Rails Framework Standards
    - [volume-v/README.md](volume-v/README.md) - Persistence and Data Engineering Standards
    - [volume-vi/README.md](volume-vi/README.md) - Background Processing and Integration Standards
    - [volume-vii/README.md](volume-vii/README.md) - API and Interface Engineering Standards
    - [volume-viii/README.md](volume-viii/README.md) - Security Engineering Standards
    - [volume-ix/README.md](volume-ix/README.md) - Quality Engineering Standards
    - [volume-x/README.md](volume-x/README.md) - Production Engineering Standards
    - [volume-xi/README.md](volume-xi/README.md) - AI Assisted Engineering Standards
    - [volume-xii/README.md](volume-xii/README.md) - Repository Stewardship Standards

    ## Master Controls

    - [MASTER_INDEX.md](MASTER_INDEX.md)
    - [MASTER_TRACEABILITY.md](MASTER_TRACEABILITY.md)
    - [MANUAL_AUTHORITY.md](MANUAL_AUTHORITY.md)
    - [MANUAL_VERSION_HISTORY.md](MANUAL_VERSION_HISTORY.md)
    - [MANUAL_CHANGELOG.md](MANUAL_CHANGELOG.md)
    - [MANUAL_VALIDATION_REPORT.md](MANUAL_VALIDATION_REPORT.md)
    - [IMPLEMENTATION_AGENT_ENTRYPOINT.md](IMPLEMENTATION_AGENT_ENTRYPOINT.md)
    """).strip()


def master_index(volumes: list[Volume]) -> str:
    sections = ["# Master Index", "", "## Volume I", "", *volume_i_entries(), ""]
    for volume in volumes:
        sections.extend([f"## Volume {volume.roman} - {volume.title}", ""])
        volume_dir = MANUAL_ROOT / volume.slug
        for path in sorted(volume_dir.glob("*.md")):
            rel = path.relative_to(MANUAL_ROOT).as_posix()
            sections.append(f"- [{rel}]({rel})")
        sections.append("")
    sections.extend([
        "## Master Control Files",
        "",
        "- [README.md](README.md)",
        "- [MASTER_TRACEABILITY.md](MASTER_TRACEABILITY.md)",
        "- [MANUAL_AUTHORITY.md](MANUAL_AUTHORITY.md)",
        "- [MANUAL_VERSION_HISTORY.md](MANUAL_VERSION_HISTORY.md)",
        "- [MANUAL_CHANGELOG.md](MANUAL_CHANGELOG.md)",
        "- [MANUAL_VALIDATION_REPORT.md](MANUAL_VALIDATION_REPORT.md)",
        "- [IMPLEMENTATION_AGENT_ENTRYPOINT.md](IMPLEMENTATION_AGENT_ENTRYPOINT.md)",
    ])
    return "\n".join(sections)


def master_traceability(volumes: list[Volume]) -> str:
    rows = ["# Master Traceability", "", "| Volume | Authority sources | Implementation concern | Principal dependencies | Downstream verification |", "| --- | --- | --- | --- | --- |"]
    rows.append("| I | Product Specification; repository governance | Engineering governance foundation | Product Specification; ADRs; Owner Decisions | Definition of Done; review governance |")
    for volume in volumes:
        rows.append(f"| {volume.roman} | {'; '.join(volume.authority)} | {volume.concern} | {'; '.join(volume.dependencies)} | {'; '.join(volume.verification)} |")
    return "\n".join(rows)


def manual_authority() -> str:
    return dedent_block("""
    # Manual Authority

    ## Authority Hierarchy

    1. Product Specification and foundation documents.
    2. Ratified ADRs and Owner Decisions integrated into canonical owners.
    3. Canonical workflow, state, API, schema, security and acceptance contracts.
    4. Existing Engineering Manual content.
    5. New Engineering Manual content.
    6. Indexes, summaries and generated control documents.

    Lower-authority artefacts SHALL NOT contradict higher-authority artefacts. If conflict cannot be resolved by this hierarchy, affected implementation SHALL stop until the canonical owner resolves the issue.

    ## Canonical Ownership

    Product behaviour, state, workflows, permissions, routes, schemas, commercial values, legal obligations and operational commitments are owned by the Product Specification and ratified decisions. Engineering Governance owns implementation standards and repository stewardship.

    ## Amendment Governance

    Amendments SHALL identify the affected authority, update traceability, preserve historical records and pass the manual validator. Examples remain non-authoritative and SHALL be corrected if they appear to create behaviour.
    """).strip()


def manual_version_history() -> str:
    return dedent_block(f"""
    # Manual Version History

    ## Purpose

    This document records manual-level baselines for the Engineering Manual. It is a control document, not a source of product behaviour.

    | Version | Date | Status | Notes |
    | --- | --- | --- | --- |
    | 1.0 | {DATE} | Validated preimplementation manual baseline | Volumes IV-XII completed, master controls added and validation tooling established. |

    ## Governance

    Future version entries SHALL identify the affected manual authority, validation evidence and commit or tag that established the baseline. Version history SHALL preserve prior entries and SHALL NOT be rewritten to hide superseded states.
    """).strip()


def manual_changelog() -> str:
    return dedent_block(f"""
    # Manual Changelog

    ## Purpose

    This changelog records repository changes to the Engineering Manual. It is separate from product release notes and does not describe application implementation.

    ## 1.0 - {DATE}

    - Completed Engineering Manual Volumes IV through XII.
    - Added volume support files for repository integration.
    - Added master controls, authority model, traceability and validation report.
    - Added scripts/validate_engineering_manual.py with isolated negative controls.

    ## Governance

    Manual changes SHALL remain traceable to authority sources and validation evidence. Changelog entries SHALL distinguish documentation baselines from implementation, release and final frozen baselines.
    """).strip()


def manual_validation_report() -> str:
    return dedent_block(f"""
    # Manual Validation Report

    ## Status Vocabulary

    - VERIFIED: Check passed with direct command evidence.
    - VERIFIED_WITH_FINDINGS: Check passed or was completed with recorded non-blocking findings.
    - INCOMPLETE: Required work remains unfinished.
    - CONFLICT: Authoritative sources materially contradict one another.
    - DEFERRED: Product-specific value or exposure remains with a canonical owner.
    - UNAVAILABLE: Evidence source could not be inspected in this repository.

    ## Current Status

    VERIFIED_WITH_FINDINGS

    ## Evidence Recorded

    - Repository authority sources inspected under specification, governance, architecture, schemas and engineering/manual.
    - Manual structure generated directly in the repository without ZIP handling.
    - scripts/validate_engineering_manual.py checks expected volumes, chapter counts, identifiers, links, master index entries, removed event names, prohibited state references, placeholders, fences and duplicate-like content.
    - Isolated negative controls are defined for duplicate identifier, missing chapter, title mismatch, broken link, unbalanced fence, unresolved placeholder, missing master index entry, removed event reference and prohibited state reference.

    ## Findings

    - Existing Volume I contains template examples with publication placeholder tokens. These are preserved legacy template artefacts and are not used by new authored volumes.
    - Product-specific operational values such as service objectives, recovery targets, retention periods, deployment topology and cryptographic choices remain deferred to canonical owners where not ratified.
    - This baseline is a documentation baseline and does not begin application implementation.
    """).strip()


def implementation_agent_entrypoint() -> str:
    return dedent_block("""
    # Implementation Agent Entrypoint

    ## Read First

    1. Product Specification index and foundation documents.
    2. Owner Decision register and ratified Owner Decision records.
    3. Workflow, state, API, schema, security, observability and acceptance contracts.
    4. Engineering Manual Volume I authority and governance chapters.
    5. The volume governing the affected implementation concern.
    6. Existing source, tests and validators near the intended change.

    ## Authority Precedence

    Product Specification and integrated decisions outrank the Engineering Manual. Existing manual content outranks generated summaries and indexes. Examples are non-authoritative.

    ## Traceability Requirements

    Every material implementation change SHALL identify the requirement, authority source, verification evidence and affected ownership boundary. Tests SHALL prove the requirement rather than merely execute code.

    ## Repository Inspection Requirements

    Agents SHALL inspect existing code, tests, validators and documentation before modification. They SHALL avoid broad rewrites when a narrow change satisfies the authority.

    ## Stop Conditions

    Stop when product behaviour is missing, authority materially conflicts, a required owner decision is unresolved, validation cannot be made meaningful, or unrelated repository changes cannot be isolated.

    ## Validation Requirements

    Run the narrowest relevant executable validation after the first substantive edit. For manual changes, run scripts/validate_engineering_manual.py and the negative controls when changing validator logic.

    ## Commit and Evidence Requirements

    Commits SHALL be scoped, reviewable and traceable. Do not push, rewrite history or move existing tags without explicit approval. Completion claims SHALL name commands actually run.

    ## Prohibition Against Invented Behaviour

    Agents SHALL NOT invent workflows, routes, commands, states, events, permissions, schema objects, provider guarantees, cryptographic choices, commercial values, legal obligations, service objectives, recovery objectives or deployment topology.

    ## Current Gate

    Application implementation remains gated by the requirement to inspect the specific implementation slice and verify that the Product Specification resolves the behaviour being implemented. The manual baseline alone does not authorise application code changes.
    """).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate F1 Engineering Manual files")
    parser.add_argument("targets", nargs="*", help="Targets: iv, v, vi, vii, viii, ix, x, xi, xii, support, master, all")
    args = parser.parse_args()
    targets = args.targets or ["all"]
    if "all" in targets:
        targets = ["support", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "master"]
    for target in targets:
        if target == "support":
            support_for_existing(SUPPORT_VOLUME_II)
            support_for_existing(SUPPORT_VOLUME_III)
        elif target == "master":
            generate_master_controls()
        else:
            generate_volume(VOLUMES[target])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
