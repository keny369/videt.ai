# Foundation Section Mappings

## Purpose

Provide explicit section mappings for foundation documents that use stricter or legacy section structures while remaining compliant with PM-REQ-007 and DOC-REQ-001 through DOC-REQ-003.

## Scope

This registry applies to foundation documents with non-uniform section layouts.

## Canonical Policy References

- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)

## Mapping Registry

### 000 OVERVIEW

- Title: H1 title
- Status: Document Control
- Authority: Foundational Hierarchy and Canonical Source Rules
- Purpose: Purpose
- Scope: What This Repository Is and What This Repository Is Not
- Dependencies: References
- Definitions: Canonical term control inherited from [002 GLOSSARY.md](002%20GLOSSARY.md)
- Assumptions: Mission Alignment and Architectural Thesis
- Constraints: Strategic Constraints and Canonical Source Rules
- Normative Requirements: Canonical Source Rules and Change Governance
- Decisions: Architectural Thesis
- Non-goals: What This Repository Is Not
- Risks: Covered through Strategic Constraints and Change Governance
- Verification: Acceptance Criteria
- Open Questions: Not applicable for top-level orientation document; open questions are maintained in domain-specific foundation documents
- Related Documents: References
- Change Control: Change Governance

### 002 GLOSSARY

- Title: H1 title
- Status: Document Control
- Authority: Canonical classification in Document Control and glossary governance language
- Purpose: Purpose
- Scope: Scope
- Dependencies: References
- Definitions: Glossary Terms
- Assumptions: Canonical term ownership assumptions are embedded in Scope and Definition Governance
- Constraints: Definition Governance
- Normative Requirements: Definition Governance rules
- Decisions: Lexical authority decision embedded in Purpose and Scope
- Non-goals: Scope excludes naming-convention ownership, delegated to [003 TERMINOLOGY.md](003%20TERMINOLOGY.md)
- Risks: Terminology drift risk controlled through Definition Governance
- Verification: Acceptance Criteria
- Open Questions: Not applicable for lexical baseline document; unresolved domain questions belong in domain foundation documents
- Related Documents: References
- Change Control: Definition Governance

### 003 TERMINOLOGY

- Title: H1 title
- Status: Document Control
- Authority: Canonical classification in Document Control
- Purpose: Purpose
- Scope: Scope
- Dependencies: References
- Definitions: Terminology Rules and Canonical Terms table
- Assumptions: Scope and Rule sections assume cross-document terminology reuse
- Constraints: Rule 1 through Rule 10
- Normative Requirements: Terminology Rules
- Decisions: Numbering and Identifier Policy plus Change Governance
- Non-goals: Tone and Voice Requirements excludes marketing language in technical specs
- Risks: High-risk term drift covered by Canonical Terms and Disallowed Variants
- Verification: Acceptance Criteria
- Open Questions: Not applicable for terminology policy baseline; unresolved terminology disputes are escalated through ADR process
- Related Documents: References
- Change Control: Change Governance

### 004 DESIGN_PRINCIPLES

- Title: H1 title
- Status: Document Control
- Authority: Canonical classification in Document Control
- Purpose: Purpose
- Scope: Scope
- Dependencies: References
- Definitions: Principle statements and section-specific implications
- Assumptions: Principle implications assume decision-support UX workflow model
- Constraints: Principle statements and Data Visualization Rules plus Interaction Rules
- Normative Requirements: Design principles and checklist requirements
- Decisions: Principle set defines accepted design decision baseline
- Non-goals: Scope excludes non-user-facing implementation concerns
- Risks: Accessibility and explainability controls embedded in principles
- Verification: Design Review Checklist and Acceptance Criteria
- Open Questions: Not applicable in baseline principle set; unresolved decisions are handled via product and architecture ADR flow
- Related Documents: References
- Change Control: Change controlled through ADR and terminology governance references

### 005 PRODUCT_PRINCIPLES

- Title: H1 title
- Status: Document Control
- Authority: Canonical classification in Document Control
- Purpose: Purpose
- Scope: Scope
- Dependencies: References
- Definitions: Principle headings and Prioritization Rubric terminology
- Assumptions: Scope and principles assume documentation-first non-invasive baseline
- Constraints: Product principles, acceptance gate, and anti-patterns
- Normative Requirements: Product Acceptance Gate and Required Product Metrics
- Decisions: Principle set and prioritization rubric
- Non-goals: Explicit Non-Goals principle and Product Anti-Patterns
- Risks: Anti-pattern controls and acceptance gate constraints
- Verification: Product Acceptance Gate and Acceptance Criteria
- Open Questions: Not applicable for baseline principles; unresolved commercial trade-offs are managed in Volume I and ADRs
- Related Documents: References
- Change Control: Change controlled through decision framework and ADR policy

### 008 AI_PRINCIPLES

- Title: H1 title
- Status: Document Control
- Authority: Canonical classification in Document Control
- Purpose: Purpose
- Scope: Scope
- Dependencies: References
- Definitions: Principle statements and AI Workflow Requirements
- Assumptions: Scope assumptions for LLM workflows and provider portability
- Constraints: AI principles and AI Release Gate
- Normative Requirements: AI Workflow Requirements and AI Release Gate
- Decisions: Principle set defines AI governance baseline
- Non-goals: Non-invasive execution and provider portability constraints prohibit autonomous production mutation in baseline
- Risks: AI Risk Categories
- Verification: Acceptance Criteria and release gate checks
- Open Questions: Not applicable in baseline AI principle layer; unresolved AI thresholds are tracked in [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- Related Documents: References
- Change Control: Decision framework and ADR policy in related references

### 009 DECISION_FRAMEWORK

- Title: H1 title
- Status: Document Control
- Authority: Canonical classification in Document Control
- Purpose: Purpose
- Scope: Scope
- Dependencies: References
- Definitions: Decision Types and Reversibility Classification
- Assumptions: Decision SLAs and post-decision review windows
- Constraints: Required Decision Process and ADR Threshold
- Normative Requirements: Required Decision Process, ADR Threshold, and Anti-Patterns
- Decisions: Decision Rights and Escalation Policy
- Non-goals: Anti-Patterns and scope boundaries for decision process
- Risks: Anti-Patterns and escalation controls
- Verification: Acceptance Criteria and post-decision review checkpoints
- Open Questions: Not applicable for framework baseline; unresolved questions are captured in decision records and ADRs
- Related Documents: References
- Change Control: ADR threshold and post-decision review requirements

## Governance Notes

- This registry MUST be updated in the same change set as any mapped foundation document changes.
- If a mapped section becomes materially weak, remediation MUST be tracked through ADR and follow-up tasks.
