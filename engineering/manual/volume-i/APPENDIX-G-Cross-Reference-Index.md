---
title: Appendix G — Cross-Reference Index
identifier: EM-I-APP-G
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix G — Cross-Reference Index

## Purpose

This appendix provides the canonical cross-reference index for **Engineering Manual – Volume I**.

Its purpose is to allow engineers, reviewers, architects and AI coding agents to quickly determine the governing authority for any engineering topic.

This appendix is normative.

Where multiple chapters discuss a topic, the chapter identified as the **Primary Authority** SHALL prevail.

---

# G1. Authority Hierarchy

| Priority | Authority                      | Description                        |
| -------- | ------------------------------ | ---------------------------------- |
| 1        | Product Specification          | Defines required product behaviour |
| 2        | Engineering Manual             | Defines implementation standards   |
| 3        | Architectural Decision Records | Defines architectural decisions    |
| 4        | Repository Source Code         | Implements approved behaviour      |
| 5        | Operational Documentation      | Supports production operations     |

No lower authority may contradict a higher authority.

---

# G2. Topic Index

| Engineering Topic         | Primary Authority | Supporting References   |
| ------------------------- | ----------------- | ----------------------- |
| Engineering Philosophy    | EM-I-001          | EM-I-005                |
| Engineering Objectives    | EM-I-002          | Product Specification   |
| Authority Hierarchy       | EM-I-003          | Product Specification   |
| Normative Language        | EM-I-004          | Documentation Standards |
| Engineering Principles    | EM-I-005          | Architecture            |
| Architectural Integrity   | EM-I-006          | ADRs                    |
| Repository Governance     | EM-I-007          | EM-I-008                |
| Branch Strategy           | EM-I-008          | Repository Governance   |
| Pull Requests             | EM-I-009          | Code Review             |
| Definition of Done        | EM-I-010          | Quality Gates           |
| Code Review               | EM-I-011          | Pull Requests           |
| ADR Governance            | EM-I-012          | Traceability            |
| Engineering Risk          | EM-I-013          | Security                |
| Documentation Standards   | EM-I-014          | Repository Governance   |
| Requirement Traceability  | EM-I-015          | Product Specification   |
| AI Engineering Governance | EM-I-016          | Repository Governance   |
| Engineering Metrics       | EM-I-017          | Quality Engineering     |
| Technical Debt            | EM-I-018          | Continuous Improvement  |
| Engineering Ethics        | EM-I-019          | Repository Governance   |
| Continuous Improvement    | EM-I-020          | Engineering Metrics     |

---

# G3. Repository Governance Map

| Repository Activity  | Governing Chapter |
| -------------------- | ----------------- |
| Repository Structure | EM-I-007          |
| Branch Naming        | EM-I-008          |
| Pull Requests        | EM-I-009          |
| Merge Approval       | EM-I-011          |
| Repository Labels    | APP-E             |
| Traceability         | EM-I-015          |
| Documentation        | EM-I-014          |
| Version Control      | EM-I-007          |

---

# G4. Engineering Lifecycle Map

| Lifecycle Stage | Governing Authority         |
| --------------- | --------------------------- |
| Idea            | Product Specification       |
| Design          | Product Specification + ADR |
| Architecture    | ADR + EM-I                  |
| Implementation  | Engineering Manual          |
| Review          | EM-I-009 / EM-I-011         |
| Validation      | EM-I-017                    |
| Release         | EM-X                        |
| Production      | EM-X                        |
| Maintenance     | EM-I-018                    |
| Improvement     | EM-I-020                    |

---

# G5. Engineering Responsibility Matrix

| Responsibility           | Primary Authority     |
| ------------------------ | --------------------- |
| Product Behaviour        | Product Specification |
| Architecture             | ADRs                  |
| Implementation Standards | Engineering Manual    |
| Coding Standards         | Engineering Manual    |
| Repository Governance    | EM-I                  |
| Security Standards       | Volume VIII           |
| Testing Standards        | Volume IX             |
| Operations               | Volume X              |

---

# G6. AI Governance Map

| AI Activity        | Governing Authority |
| ------------------ | ------------------- |
| Code Generation    | EM-I-016            |
| Documentation      | EM-I-014            |
| Review Assistance  | EM-I-011            |
| Repository Changes | EM-I-007            |
| Architecture       | EM-I-012            |
| Traceability       | EM-I-015            |
| Testing            | Volume IX           |

---

# G7. Review Matrix

| Review Type          | Governing Chapter |
| -------------------- | ----------------- |
| Code Review          | EM-I-011          |
| Pull Request Review  | EM-I-009          |
| Documentation Review | EM-I-014          |
| Security Review      | Volume VIII       |
| Architecture Review  | EM-I-012          |
| Operational Review   | Volume X          |

---

# G8. Appendix Index

| Appendix   | Purpose                |
| ---------- | ---------------------- |
| Appendix A | Engineering Checklists |
| Appendix B | Pull Request Template  |
| Appendix C | ADR Template           |
| Appendix D | Definition of Ready    |
| Appendix E | Repository Taxonomy    |
| Appendix F | Engineering Glossary   |
| Appendix G | Cross-Reference Index  |
| Appendix H | Version History        |
| Appendix I | Change Log             |

---

# G9. Engineering Manual Navigation

```
Engineering Manual

├── Volume I
│   ├── Governance
│   ├── Repository
│   ├── Standards
│   ├── AI Governance
│   └── Appendices
│
├── Volume II
│   Architecture
│
├── Volume III
│   Rails 8
│
├── Volume IV
│   Domain Implementation
│
├── Volume V
│   Infrastructure
│
├── Volume VI
│   APIs
│
├── Volume VII
│   Frontend
│
├── Volume VIII
│   Security
│
├── Volume IX
│   Quality Engineering
│
└── Volume X
    Production Operations
```

---

# G10. Maintenance

This cross-reference index SHALL be updated whenever:

- a new chapter is added;
- a chapter identifier changes;
- authority ownership changes;
- new Engineering Manual volumes are introduced.

Broken references SHALL be treated as engineering governance defects.

---

# Compliance

This appendix forms part of the normative Engineering Manual.

Every Engineering Manual chapter SHALL remain discoverable through this index.

Repository tooling MAY use this index to automate navigation, validation and engineering assistance.

---

# Cross References

- Entire Engineering Manual
- Product Specification
- Architectural Decision Records
