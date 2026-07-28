# VOL3-INPUT — Module 2: Reality Graph, Entity Model & Source Registry

> **Status:** Volume III specification input — future/gated; enters canon only via the vision-set ADR (see `specification/machines/001 VOLUME_III_ARTIFACT_MAP.md`). **Nothing in this document is ratified.** Volume I/II are frozen; the ratified Product Architecture Manual is the single source of truth (ADR-001). This artifact is future/research-grade until filed by ADR. It EXTENDS the canonical vocabulary of `011 DOMAIN_MODEL.md`, `002 GLOSSARY.md` and `003 TERMINOLOGY.md`; it defines no competing dictionary. Where it names a candidate object that collides with a frozen term, the collision is flagged in-line and recorded in Open Questions for ADR resolution — it is **not** resolved here.

---

## 0. Reader's orientation

**What this module codifies.** The *subject-side* of the platform: the **Reality Graph** (ADR-012, Future) — the verifiable truth about a business and the world it operates in — together with the **Source Registry** subsystem that catalogues the surfaces from which reality is corroborated and against which machine perception is later checked. It is Module 2 of the Volume III artifact stack.

**Where it sits in the product intelligence model.** `governance/CUSTOMER_VALUE_CONSTITUTION.md` defines four graphs and a five-stage loop:

| Graph | Question it answers | This module |
|---|---|---|
| **Reality Graph** | What is verifiably true about the organisation, offerings, people, locations, capabilities, claims and supporting evidence? | **Codified here.** |
| **Perception Graph** | What do machine systems believe, state, cite, omit, misunderstand, contradict or recommend? | Adjacent (Module: measurement). Touched here only at the resolution seam (Assistant / Run / Mention). |
| **Gap Graph** | Where do reality and perception materially diverge? | Consumes this module; not defined here. |
| **Intelligence Graph** | What should be done, why, who owns it, with what measured outcome? | Consumes the findings taxonomy; not defined here. |

The loop is **OBSERVE → ASSESS → COMPARE → INTERVENE → LEARN**. This module is the machinery of **ASSESS** ("build a verifiable picture of the organisation and its digital reality") and supplies the ground truth without which **COMPARE** cannot mark a machine wrong.

**Design stance (binding on this document).**

1. **Provider/framework-neutral.** Rails 8 + PostgreSQL is the target stack, but the domain model here is persistence-agnostic per the `011 DOMAIN_MODEL.md` constraints. No framework classes, table names, queue names or vendor products are treated as domain concepts (DM-REQ-018). Graph-vs-relational persistence is an Open Question.
2. **Counts, not composites.** Per the machine consensus and the branding claim rules, there is **no composite "AI ranking score"** anywhere in this model. Where matching or authority needs a decision, it is a *documented decision function over counted, evidence-backed features* — never a blended magic number shown to a customer.
3. **Two clocks.** Retrieval-layer facts move in days–weeks and are re-measurable; parametric-memory facts move in training generations and are never promised (OD-010; `operations/AUTHORITY_ROADMAP.md`). Every Reality Graph fact and every Source is timestamped and revalidated; nothing about corpus-layer change is given a schedule.
4. **Evidence-backed or it does not exist.** Every non-trivial assertion in the Reality Graph carries provenance to Evidence (the frozen `evd_id` record) and a claim class. Unsupported assertions are `Claimed` at best, never `Verified`.

---

## 1. Vocabulary discipline and known collisions

This module obeys `003 TERMINOLOGY.md` Rule 1 (canonical names, no local aliases) and the standing governance rule "no dictionary beside 002/003". It reuses frozen terms exactly; it introduces **candidate** terms only where the subject-side concept has no frozen name, and it flags every collision.

### 1.1 Frozen terms reused unchanged

- **Organization** (`org_id`) — tenant boundary. The Reality Graph is authored *for* an Organization's Project(s); the Business the Reality Graph describes MAY be the Organization's own subject business.
- **Project** (`prj_id`) — the discoverability program boundary. A Reality Card is scoped to exactly one Project.
- **Source** (`src_id`) — **frozen meaning: "a configured input location within a Project used for crawl or ingestion scope."** This is a *customer-owned property URL*, not a reference surface. **This module never overloads `Source`.**
- **Evidence** (`evd_id`) — the immutable governed observation record; **Evidence Type is a CLOSED taxonomy** (ADR-017): `source_document`, `crawl_observation`, `parsed_content`, `external_measurement`, `verification_observation`, reserved `operator_attestation`. Reality Graph facts and Source health observations are backed by Evidence of these types **only**; this module invents no new Evidence Type (Artifact Map: Evidence Type extension = controlled Volume I change).
- **Evidence Provenance** — `source_system`, applicable `source_id`, collection method, collector/adapter version, observed/captured times, schema/policy versions. The Source Registry supplies the `source_system` identity for corroboration Evidence.
- **Citation** (`cit_id`) — **frozen meaning: "Evidence pointer linked to recommendation or AI output"**, governed by `citation-policy-v1`. **This module never overloads `Citation`.**
- **Issue** (`iss_id`) — the sole canonical customer-facing deficiency object (003 TERMINOLOGY). The findings taxonomy in §7 is research-grade input to the Gap Graph, not a redefinition of Issue.

### 1.2 Candidate terms introduced here (ADR-gated)

| Candidate term | Meaning in this module | Collides with | Disposition |
|---|---|---|---|
| **RegistrySource** (a.k.a. *Reference Surface*) | One catalogued surface in the Source Registry — a registry, regulator, map, review platform, technical check or directory. The ~393-surface catalogue is a set of RegistrySources. | Frozen **Source** (`src_id`, customer input location). | Candidate. Resolve at filing. **Never** written as bare "Source". |
| **SourceMention** | A reality-side edge: "reference surface Y asserts fact F about business X" (e.g. "ASIC lists ACME PTY LTD at address A"). | Frozen **Citation** (`cit_id`). | Candidate. Distinct from the answer-path Citation an assistant emits. |
| **Finding** | The research-sense classification of a non-pass observation (Absence, Conflation, …). Used per FUTURE-WORKFLOW-001. | Frozen **Issue** (003 forbids "finding" as an Issue variant). | **Known, unresolved** (governance). Recorded, not resolved. |
| **RealityCard** | The versioned ground-truth object that gates entity resolution (§5). | — (no frozen collision). | New; belongs to the Reality Graph. |

> **Governance note.** The Reality-side `Source`/`Citation`/`Finding` collisions are the same *class* of problem as the ADR-012/013 numbering collision and the Finding/Issue collision already logged in the Artifact Map. They are surfaced, not settled. A build agent MUST treat the candidate names as placeholders pending the vision-set ADR.

### 1.3 The AI-side objects (Assistant / Run / Mention)

`Assistant`, `Run` and `Mention` are **Perception Graph** objects. They appear in this module **only** at the resolution seam: a `Mention` (a business named in an assistant answer) must be *resolved to* a Reality Graph node before COMPARE can act, and that resolution is the entity-resolution machinery in §6. Their full field models belong to the measurement module and to FUTURE-WORKFLOW-001's Observation Contract; §4.4 gives only the boundary fields this module needs.

---

## 2. The Reality Graph — modeling approach

### 2.1 It is a property graph

The Reality Graph is modelled as a **directed, typed property graph**:

- **Nodes** carry a `node_type`, a canonical identifier, typed properties, and a per-node provenance/claim envelope.
- **Edges** are first-class, typed, directional, and themselves carry provenance and a claim class (an edge like *is-registered-with* is only as trustworthy as the Evidence behind it).
- The graph is **Project-scoped**: every node and edge belongs to exactly one Project (mirroring `Project → Source` 1-to-many ownership in 011). Cross-Project sharing of reference data (Regulator, Industry, RegistrySource) is handled by *reference nodes* (§2.4), not by cross-tenant edges.

Persistence is deliberately unspecified (Open Question): the model is expressible as a native graph store, as relational node/edge tables with adjacency, or as a hybrid. Nothing in this module may be read as mandating a storage engine (DM-REQ / 011 constraint: "Domain definitions MUST remain independent from framework internals").

### 2.2 Universal node envelope

Every Reality Graph node — regardless of `node_type` — carries this envelope, in addition to its type-specific properties:

| Field | Type | Req | Notes |
|---|---|---|---|
| `node_id` | opaque string (ULID/UUID) | ✔ | Immutable, globally unique within its namespace (DM-REQ-005). Namespace per type (§3). |
| `node_type` | enum | ✔ | One of the §3 types. |
| `project_id` | `prj_id` | ✔ | Owning Project. |
| `organization_id` | `org_id` | ✔ | Denormalised tenant label for audit/telemetry (DM-REQ-006). |
| `canonical` | bool | ✔ | `true` for the single canonical node of its kind in the Reality Card; `false` for observed/confusable variants. |
| `claim_class` | enum | ✔ | Truth & Claims class of the node's *existence/identity* assertion (§2.5). |
| `confidence_band` | enum | ✔ | OD-003 confidence band label. **Not** a numeric composite. |
| `evidence_ids` | `evd_id[]` | ✔ (≥1 unless `claim_class=Inferred/Estimated`) | Backing Evidence records. |
| `source_of_truth` | enum | ✔ | `reality_card` \| `client_asserted` \| `surface_observed` \| `derived`. |
| `first_observed_at` | UTC ts | ✔ | |
| `last_verified_at` | UTC ts | ✔ | Drives the revalidation clock (§8, §11). |
| `valid_from` / `valid_to` | UTC ts / null | ✔ / — | Temporal validity (supports Temporal-Hallucination detection: "closed since 2024"). |
| `version` | int | ✔ | Optimistic-concurrency + audit; nodes are versioned, not overwritten silently. |
| `superseded_by` | `node_id` \| null | — | Set when a node is corrected/merged. |
| `layer` | enum | ✔ | `retrieval` \| `corpus` \| `n/a` — which clock governs change to this fact (two-clock rule). |

**Envelope invariants** (test-validated per DM-REQ-004):

- `RG-INV-01` A node with `claim_class ∈ {Verified, Corroborated}` MUST reference ≥1 `evidence_id`.
- `RG-INV-02` A node with `canonical = true` MUST be reachable from its Project's RealityCard (§5).
- `RG-INV-03` `last_verified_at ≥ first_observed_at`; `valid_to`, if set, `≥ valid_from`.
- `RG-INV-04` Exactly one `canonical = true` node per (Project, identity-key) — e.g. one canonical Business, one canonical primary Location; enforced by entity resolution (§6).

### 2.3 Universal edge envelope

| Field | Type | Req | Notes |
|---|---|---|---|
| `edge_id` | opaque string | ✔ | Immutable. |
| `edge_type` | enum | ✔ | §4 relationship catalogue. |
| `from_id` / `to_id` | `node_id` | ✔ | Directional. |
| `project_id` | `prj_id` | ✔ | |
| `claim_class` | enum | ✔ | Class of the *relationship* assertion. |
| `confidence_band` | enum | ✔ | OD-003 band. |
| `evidence_ids` | `evd_id[]` | ✔ (as RG-INV-01) | |
| `registry_source_id` | RegistrySource id \| null | — | If the edge is a SourceMention (surface asserts the relationship). |
| `valid_from` / `valid_to` | UTC ts / null | ✔ / — | Temporal validity of the relationship. |
| `version` | int | ✔ | |

### 2.4 Reference nodes vs Project-scoped nodes

Two families of node exist:

- **Project-scoped subject nodes** — Business, Practitioner, Company, Brand, Franchise, Office, Location, Service, Review, SourceMention. Authored per Project; carry the full envelope.
- **Reference nodes** — Regulator, Licence *type*, Industry, RegistrySource. These describe the shared world (e.g. "AHPRA", "NAICS 541611", "ASIC company search surface"). They are maintained centrally, versioned, and *referenced* by Project-scoped nodes via edges. A Project never mutates a reference node; it links to it. (This mirrors the frozen distinction between tenant data and platform reference data.)

### 2.5 Claim classes (from the planned Truth & Claims Specification)

Every node and edge is stamped with a claim class. The class set is the Truth & Claims Specification's proposed set (Artifact Map §"accepted new artifact"): **Verified · Corroborated · Claimed · Inferred · Estimated · Opinion · Allegation · Finding of a court or regulator · Marketing Claim · AI-generated Summary.** Per-class producer/evidence/display rules are that specification's job; this module only *consumes* the classes and enforces:

- `RG-CLAIM-01` `Verified` requires ≥1 Evidence from a RegistrySource whose `authoritative_for` covers the asserted fact class (§8.4) — e.g. registration number is `Verified` only against the register that issues it.
- `RG-CLAIM-02` `Corroborated` requires ≥2 independent RegistrySources of differing category agreeing.
- `RG-CLAIM-03` `Allegation` and `Marketing Claim` MUST NOT be promoted to `Verified` by volume; they never gate entity resolution and never appear as fact (encodes catalogue §9 "treat_an_allegation_as_a_finding" prohibition and Authority-Spoofing defence).
- `RG-CLAIM-04` `Finding of a court or regulator` is the only class that carries adverse-record weight, and only with source (delivery guide Part 11.3).

---

## 3. Entity ontology — node catalogue

Each node type below lists its identifier namespace, purpose, and type-specific properties (the universal envelope §2.2 is implied and not repeated). Enumerations are given inline. All namespaces are candidate (`rg_*`) pending the numbering ADR.

### 3.1 Business  *(namespace `rg_biz`)*

The subject entity: the trading business a Project is about. Distinct from Company (the legal vehicle) and Practitioner (a person). Corresponds to the manual Reality Card "Identity" + "Canonical NAP".

| Property | Type | Req | Notes |
|---|---|---|---|
| `legal_name` | string | ✔ | As registered. |
| `trading_names` | string[] | ✔ | All observed trading/DBA names; feeds confusable detection. |
| `entity_form` | enum | ✔ | `sole_trader` \| `partnership` \| `company` \| `trust` \| `franchise_unit` \| `other`. |
| `primary_industry_id` | Industry ref | ✔ | Edge *operates-in-industry*. |
| `secondary_industry_ids` | Industry ref[] | — | |
| `canonical_nap` | NAP object | ✔ | The ONE correct name/address/phone/website (§5.2). |
| `website_canonical` | URL | ✔ | Post-canonicalisation (one domain; see AUTHORITY_ROADMAP canonical-domain fix). |
| `website_variants` | URL[] | — | Duplicates/aliases that split equity (e.g. `lumenlever.com` vs `lumenandlever.com`). |
| `gst_status` | enum | — | Jurisdiction tax-registration flag. |
| `operating_status` | enum | ✔ | `active` \| `dormant` \| `ceased` \| `unknown`. Drives Temporal-Hallucination checks. |
| `service_area_policy` | ServiceArea object | ✔ | Suburbs/regions served AND explicitly *not* served (§5, feeds Geographic-Boundary-Breach control). |

### 3.2 Practitioner  *(namespace `rg_prac`)*

A named person delivering a regulated or reputationally-load-bearing service (the firm-vs-practitioner split that the machines name as a routine conflation seed).

| Property | Type | Req | Notes |
|---|---|---|---|
| `full_name` | string | ✔ | As on the register (KnowledgeSourceAlignment target). |
| `name_variants` | string[] | — | |
| `role_titles` | string[] | — | e.g. "Medical Director", "Principal". |
| `individual_registrations` | Licence ref[] | vertical-dependent | Edge *holds-licence*. Required where the vertical is register-gated (§9). |
| `page_url` | URL | — | The practitioner page that should match the register (Reality Card "People"). |
| `is_named_on_site` | bool | ✔ | Whether a matching practitioner page exists (gap if false in regulated verticals). |

### 3.3 Company  *(namespace `rg_co`)*

The legal/corporate vehicle (company number, incorporation). Separated from Business so that *Company record proves existence, not competence* (catalogue §9).

| Property | Type | Req | Notes |
|---|---|---|---|
| `company_number` | string | ✔ | ACN/ABN / CRN / EIN / Companies House number — jurisdiction-typed. |
| `number_scheme` | enum | ✔ | `ABN` \| `ACN` \| `UK_CRN` \| `US_EIN` \| `CA_BN` \| `other`. |
| `jurisdiction` | ISO region | ✔ | |
| `incorporation_date` | date | — | |
| `registered_office` | Address | — | |
| `status_on_register` | enum | ✔ | `registered` \| `deregistered` \| `strike_off_pending` \| `external_admin` \| `unknown`. |

### 3.4 Brand  *(namespace `rg_brand`)*

A market-facing brand/mark that may span multiple Businesses/Companies or be a sub-brand. Distinguishes the name people search from the legal entity.

| Property | Type | Req | Notes |
|---|---|---|---|
| `brand_name` | string | ✔ | |
| `owns_domains` | URL[] | — | |
| `trademark_refs` | string[] | — | Registered-mark numbers where relevant. |

### 3.5 Franchise  *(namespace `rg_fr`)*

A franchisor/franchise system; individual outlets are Business nodes with `entity_form=franchise_unit` linked *is-unit-of* → Franchise. Captures the "branch confusion is an Entity Conflation seed" case.

| Property | Type | Req | Notes |
|---|---|---|---|
| `system_name` | string | ✔ | |
| `franchisor_company_id` | Company ref | — | |
| `unit_count_declared` | int | — | |

### 3.6 Office / Location  *(namespaces `rg_off`, `rg_loc`)*

- **Location** — a physical place (address + geo). Reference-quality, may be shared conceptually but is Project-scoped for provenance.
- **Office** — an operational presence at a Location (a Business occupies an Office at a Location). Separating them lets one Location host multiple Offices (co-located firms — another conflation seed) and lets a Business have service-area coverage without a physical Office.

**Location properties:** `formatted_address`, `address_components{unit,street,suburb,locality,region,postcode,country}`, `geo{lat,lng,precision}`, `google_place_id?`, `apple_maps_id?`. **Office properties:** `location_id` (ref), `is_primary` (bool), `opening_hours` (structured), `phone`, `listing_ownership_claimed` (bool per platform).

### 3.7 Regulator  *(reference node, namespace `rg_reg`)*

An authority that registers/licenses/disciplines. Reference data derived from and linked to RegistrySources.

| Property | Type | Req | Notes |
|---|---|---|---|
| `regulator_name` | string | ✔ | e.g. AHPRA, TPB, ASIC, SRA, state bar. |
| `jurisdiction` | ISO region | ✔ | |
| `regulated_professions` | Industry ref[] | ✔ | Which verticals it gates. |
| `register_surface_ids` | RegistrySource id[] | ✔ | The surface(s) where its register lives. |
| `disciplinary_surface_ids` | RegistrySource id[] | — | Tribunal/banned-and-disqualified surfaces. |

### 3.8 Licence  *(namespace `rg_lic`; type is reference, instance is Project-scoped)*

A concrete registration/licence held by a Business or Practitioner. **The register-gate object.**

| Property | Type | Req | Notes |
|---|---|---|---|
| `licence_type_ref` | reference | ✔ | e.g. "Registered Tax Agent", "AHPRA MED registration", "Builder Licence (VIC)". |
| `regulator_id` | Regulator ref | ✔ | |
| `licence_number` | string | ✔ | The number-with-evidence (Reality Card "registrations with numbers"). |
| `holder_id` | Business \| Practitioner ref | ✔ | |
| `status` | enum | ✔ | `current` \| `expired` \| `suspended` \| `cancelled` \| `conditions` \| `unknown`. |
| `valid_from`/`valid_to` | date | — | Registration currency ≠ membership currency (catalogue §9). |
| `verified_against_surface_id` | RegistrySource id | ✔ (for `Verified`) | Must be the issuing register (RG-CLAIM-01). |

### 3.9 Service  *(namespace `rg_svc`)*

A service line the Business genuinely offers, **mapped to the page that describes it** (Reality Card item 4; "no page = a gap already").

| Property | Type | Req | Notes |
|---|---|---|---|
| `service_name` | string | ✔ | In buyer language, not internal jargon. |
| `buyer_phrases` | string[] | ✔ | The literal phrases buyers use (feeds ContentClarification + phrase-lattice, AUTHORITY_ROADMAP §Phase 1.3). |
| `page_url` | URL \| null | ✔ | Null = content gap Finding candidate (Absence). |
| `page_indexed` | bool | — | From `site:` check. |
| `is_offered` | bool | ✔ | `false` variants seed the wrong-service control. |
| `industry_id` | Industry ref | — | |

### 3.10 Industry  *(reference node, namespace `rg_ind`)*

The vertical taxonomy. Anchors the per-vertical evidence policy (§9) and regulator mapping.

| Property | Type | Req | Notes |
|---|---|---|---|
| `industry_label` | string | ✔ | e.g. "Accountants & bookkeepers". |
| `taxonomy_code` | string | — | NAICS/ANZSIC/SIC where mapped. |
| `regulation_class` | enum | ✔ | `register_gated` \| `licence_gated` \| `membership_signalled` \| `unregulated` (§9). |
| `evidence_policy_id` | VerticalEvidencePolicy ref | ✔ | Versioned policy object. |
| `question_archetype_set` | ref | — | Links to QUESTION_BANK archetypes for this vertical. |

### 3.11 RegistrySource  *(reference node — the Source Registry entry; see §8 for the full subsystem)*

The candidate-named catalogue entry. Summarised here as a node so the ontology is complete; the full lifecycle/adapter model is §8.

### 3.12 SourceMention  *(edge-bearing node, candidate; §4)*

"RegistrySource Y asserts fact F about node X." Modelled as a reified edge (a node when it needs its own provenance/claim/temporal fields). Distinct from the frozen Citation.

### 3.13 Review  *(namespace `rg_rev`)*

An aggregate review-profile fact about a Business on a specific platform listing (not individual review text — that is not republished; delivery guide Part 11).

| Property | Type | Req | Notes |
|---|---|---|---|
| `platform` | enum | ✔ | `google` \| `yelp` \| `trustpilot` \| `bbb` \| `industry_specific` \| `other`. |
| `listing_id` | string | ✔ | The exact listing the Business owns (branch confusion seed). |
| `count` | int | — | Count only. |
| `recency` | date | — | Most-recent review date. |
| `owner_response_rate` | enum/band | — | Band, not a score. |
| `lands_on_correct_listing` | bool | ✔ | `false` → Entity-Conflation candidate. |

`RG-REV-01` Review facts are `claim_class ∈ {Claimed, Corroborated}` and **never** `Verified` competence; "review stars ≠ outcome quality" (catalogue §9; delivery guide "reviews support service-experience findings only").

### 3.14 Boundary nodes — Assistant / Run / Mention  *(Perception-side; §4.4)*

Included for the resolution seam only. Full models are the measurement module's / FUTURE-WORKFLOW-001's.

---

## 4. Relationship catalogue (edges)

### 4.1 Structural edges (subject-internal)

| `edge_type` | from → to | Cardinality | Constraint |
|---|---|---|---|
| `operates-as-company` | Business → Company | many→many | A Business may trade through ≥1 Company; historical companies retained with `valid_to`. |
| `trades-under-brand` | Business → Brand | many→many | |
| `is-unit-of` | Business → Franchise | many→1 | `entity_form=franchise_unit`. |
| `has-office` | Business → Office | 1→many | ≥1 for a physically-located Business. |
| `office-at` | Office → Location | many→1 | |
| `employs-practitioner` | Business → Practitioner | 1→many | |
| `offers-service` | Business → Service | 1→many | ≥1 for an active Business. |
| `serves-area` | Business → Location/region | 1→many | Positive coverage; complement = `does-not-serve` for controls. |
| `operates-in-industry` | Business → Industry | many→many | Exactly one `is_primary=true`. |

### 4.2 Authority edges (subject ↔ world; register-gated)

| `edge_type` | from → to | Constraint |
|---|---|---|
| `holds-licence` | Business/Practitioner → Licence | Licence `status` governs claim class; expired ⇒ not `Verified`. |
| `licence-issued-by` | Licence → Regulator | |
| `regulated-by` | Business/Practitioner → Regulator | Derived from industry `regulation_class`. |
| `member-of-association` | Business/Practitioner → association (as RegistrySource) | Membership ≠ licensing (RG-CLAIM / catalogue §9). |

### 4.3 Corroboration edges (SourceMention)

| `edge_type` | from → to | Notes |
|---|---|---|
| `mentioned-by` | Business/Practitioner → RegistrySource | Reified as SourceMention; carries `asserted_fact`, `asserted_value`, `agrees_with_canonical` (bool), `registry_source_id`, claim class, `observed_at`. This is the atom of NAP-consistency corroboration and of the entity-resolution feature vector (§6). |
| `has-review-profile` | Business → Review | |
| `duplicate-of` | Business → Business | Points a confusable/duplicate node at the canonical; `duplicate_kind ∈ {stale_listing, branch, similar_name, alias_domain}`. |
| `confusable-with` | Business → Business/Practitioner | The confusable-entity registry edge (§5.4) — the entity-resolution gate's watchlist. |

### 4.4 Resolution-seam edges (Reality ↔ Perception)

| `edge_type` | from → to | Notes |
|---|---|---|
| `resolves-to` | Mention → Business/Practitioner/Company/null | The output of entity resolution (§6). `null` (unresolved) or a confusable target is itself a Finding. |
| `named-in-run` | Mention → Run | A Run is one fresh-session observation (FUTURE-WORKFLOW-001 Observation Contract; delivery guide Part 12 run log). |
| `run-of-assistant` | Run → Assistant | Assistant = provider+model label as *observed*, never introspected internals. |

**Boundary field minimums** (full model elsewhere): `Assistant{provider, model_label_observed, search_capability}`; `Run{run_id, project_id, assistant_id, question_id, question_class(A–I/control), location_form, search_arm(on/off/unknown), session_fresh(bool), observed_at, screenshot_ref, defective(bool,reason)}`; `Mention{mention_id, run_id, surface_text_verbatim, asserted_name, asserted_facts[], position_rank}`.

`RG-SEAM-01` A `resolves-to` edge MUST record the entity-resolution `match_state` (§6) and its feature evidence; a Mention that resolves to a `confusable-with` target is flagged **Entity Conflation** (§7).

---

## 5. The Reality Card — codified

The **RealityCard** is the versioned ground-truth object for a Project. It is *the entity-resolution gate*: nothing an assistant says can be scored wrong without it (delivery guide Part 3, "non-negotiable"; synthesis §7.2). It is the manual seed of the Reality Graph and the durable output of ASSESS. It is not a document — it is a materialised, addressable projection over the canonical (`canonical=true`) Reality Graph nodes plus four gate structures.

### 5.1 RealityCard object

| Field | Type | Req | Notes |
|---|---|---|---|
| `reality_card_id` | `rg_card` | ✔ | |
| `project_id` | `prj_id` | ✔ | One active RealityCard per Project. |
| `subject_business_id` | Business ref | ✔ | The canonical Business. |
| `version` | int | ✔ | Bumped on any gate change; prior versions retained (before/after pictures, report §9.3). |
| `completeness` | CompletenessReport | ✔ | Per-section filled/missing, as *counts* (no composite %). |
| `built_at` / `built_by` | UTC ts / actor | ✔ | |
| `nap` | NAP object | ✔ | §5.2. |
| `registrations` | Licence ref[] | ✔ | §5.3 — with numbers + evidence. |
| `service_map` | ServiceMapEntry[] | ✔ | §5.5 — service → page. |
| `confusables` | ConfusableEntry[] | ✔ | §5.4 — the registry that makes Conflation detectable. |
| `locations_and_area` | ServiceArea | ✔ | Served AND not-served. |
| `people` | Practitioner ref[] | vertical-dep | Named practitioners + individual registrations. |
| `review_profiles` | Review ref[] | ✔ | The exact listings owned. |
| `hours`, `socials` | structured | — | |

`RC-INV-01` A RealityCard is **gate-complete** only when `nap`, `registrations` (for register-gated industries), `service_map`, `confusables` and `locations_and_area` are present; entity resolution (§6) MUST run in *degraded* mode against a non-gate-complete card and MUST label its outputs `Inferred`.

### 5.2 Canonical NAP  *(the entity-resolution gate, primary)*

```
NAP := {
  name:      { legal_name, primary_trading_name, all_trading_names[] },
  address:   { formatted, components{...}, geo{lat,lng} },
  phone:     { e164, display, all_numbers[] },
  website:   { canonical_url, variant_urls[] }
}
```

The NAP is the *asserted* truth ("as the client asserts it", delivery guide Part 3.2). Its purpose is consistency comparison: every SourceMention's `asserted_value` is diffed against canonical NAP → NAP-consistency is the Tier-1 signal ("the entity-resolution gate", synthesis §3). Inconsistent NAP across surfaces is the root cause the machines name for omission and conflation.

### 5.3 Registrations-with-numbers

Each entry is a Licence node with `licence_number` and `verified_against_surface_id` pointing at the issuing register RegistrySource. `RC-REG-01`: a registration asserted without a number, or verified only against a non-issuing surface (a directory, a membership body), is `claim_class ≤ Claimed` and MUST NOT be presented as `Verified` (encodes "membership ≠ licensing", "directory ≠ regulatory verification"). This is the Authority-Spoofing defence at the data layer.

### 5.4 Confusable-entity registry  *(what makes Entity Conflation detectable)*

```
ConfusableEntry := {
  confusable_id,
  kind:            enum(similar_name | firm_vs_practitioner | old_trading_name |
                        co_located | same_franchise_branch | homograph | other),
  entity_ref:      Business|Practitioner|Company node (may be non-canonical),
  distinguishers:  string[]   // the facts that separate them (address, ABN, suburb)
  probe_question:  string     // the similar-name control ("Is {X} the same as {client}?")
}
```

The confusable registry is the *watchlist* for §6 conflation detection and the source of the mandatory similar-name control probe (delivery guide Part 5.5). `RC-CONF-01`: every confusable MUST carry ≥1 distinguisher, else conflation cannot be adjudicated.

### 5.5 Services → page mapping

```
ServiceMapEntry := { service_ref, buyer_phrases[], page_url|null, page_indexed?, gap_reason? }
```

`page_url = null` OR `page_indexed = false` is a first-class content gap (Absence Finding candidate; ContentClarification intervention). This is the deterministic bridge from Reality Card to the Readiness Audit Layer-4 checks and to the fix library.

---

## 6. Entity resolution

Entity resolution is the operation that (a) collapses observed variants to canonical nodes, (b) detects conflation with confusables, and (c) resolves assistant Mentions to Reality Graph nodes. It is the gate the machines identify as decisive ("entity resolvability is the gate", synthesis §2.2).

### 6.1 Inputs

- A **candidate** = a name+facts bundle to resolve: either a SourceMention (from a RegistrySource) or a Mention (from an assistant Run), or an inbound observed listing.
- The **RealityCard** of the Project (canonical NAP, registrations, confusables, locations).

### 6.2 Identity feature vector (counted, not blended)

Resolution compares candidate to canonical on a fixed set of **identity features**, each yielding a discrete verdict `{agree, disagree, absent}`:

| Feature | Agreement rule |
|---|---|
| `name_exact` | Normalised name equals canonical legal/trading name. |
| `name_fuzzy` | Token-set / edit-distance within a declared threshold (records *near*-matches — the similar-name danger zone). |
| `registration_number` | Exact match on any canonical `licence_number`/`company_number` — the **strongest** identity feature. |
| `phone_e164` | Match on any canonical phone. |
| `domain` | Match on canonical or variant domain. |
| `address_geo` | Address components / geo within tolerance. |
| `practitioner_name` | Named person matches a canonical Practitioner. |
| `industry` | Category consistent with primary/secondary industry. |

Normalisation (casefold, punctuation strip, legal-suffix strip, phone→E.164, domain→registrable) is applied first. **No feature is weighted into a single number.** The output is a *tuple of counted agreements/disagreements*.

### 6.3 Decision function → match state

The decision is a documented function over the tuple, **not** a composite score shown to anyone:

```
match_state(candidate, card):
  strong := registration_number.agree OR (domain.agree AND phone.agree)
  hard_conflict := registration_number.disagree
                   OR (address_geo.disagree AND phone.disagree AND domain.disagree)

  if hard_conflict:                         return CONFLATED_RISK
  if strong AND no disagreements:           return RESOLVED
  if name_exact.agree AND ≥1 corroborating (phone|domain|address|reg): return RESOLVED
  if name_fuzzy.agree AND matches a ConfusableEntry: return CONFLATION_SUSPECTED
  if name_fuzzy.agree AND ≥1 corroborating: return PROBABLE
  if only name_fuzzy.agree:                 return AMBIGUOUS
  else:                                      return UNRESOLVED
```

**States** and their consequences:

| `match_state` | Meaning | Consequence |
|---|---|---|
| `RESOLVED` | Confident single-entity match | Link `resolves-to` canonical; claim per evidence. |
| `PROBABLE` | Likely, corroborated but not strong | Link with `confidence_band` reduced; flag for review. |
| `AMBIGUOUS` | Name-only match | Do NOT link as canonical; abstain ("could not distinguish"). |
| `CONFLATION_SUSPECTED` | Matches a confusable's danger zone | Raise **Entity Conflation** Finding; require distinguisher check. |
| `CONFLATED_RISK` | Contradictory identity numbers | Quarantine; never present as the client. |
| `UNRESOLVED` | No sufficient match | Absence/coverage gap; not a fact about the client. |

`ER-INV-01` A candidate MUST NOT be written as a canonical fact about the subject unless `match_state ∈ {RESOLVED, PROBABLE}`; `PROBABLE` carries a reduced band and a review flag. `ER-INV-02` `registration_number.disagree` always dominates name agreement (encodes "merge_same_named_entities_without_identity_matching = NEVER", catalogue §9). `ER-INV-03` A Mention resolving to a `confusable-with` node is emitted as an **Entity Conflation** Finding with the verbatim surface text and the contradicted RealityCard field (delivery guide Part 7).

### 6.4 Conflation detection (proactive)

Independently of any single candidate, resolution runs a **conflation sweep**: for each ConfusableEntry, it checks whether any surface/mention has attached the confusable's facts to the subject (or vice-versa). Detected cross-contamination (a competitor's address on the subject's listing; firm facts on a practitioner) is an Entity Conflation Finding. This is the productised form of the machines' named failure mode.

### 6.5 Abstention discipline

`ER-INV-04` When resolution is `AMBIGUOUS`/`UNRESOLVED`, the platform **abstains** ("we could not distinguish X from Y on this sample") rather than guessing — the honesty behaviour the machines endorse and the delivery-guide language law mandates. Abstention is a reportable state, not a silent drop.

---

## 7. The findings taxonomy (Reality→Gap output; research-grade)

Every non-pass resolution/observation is classified as exactly one **Finding** class (candidate term; Finding/Issue collision noted). These are the adopted VIDET audit finding categories (synthesis §5; delivery guide Part 7). They are *inputs to the Gap Graph*, not a redefinition of the frozen `Issue`.

| Finding class | Reality-side trigger | Detector |
|---|---|---|
| **Absence** | Served intent (Service `is_offered=true`) with no/weak presence | Coverage of canonical Services vs Mentions |
| **Entity Conflation** | Facts merged with a `confusable-with` node | §6 (`CONFLATION_SUSPECTED`/`CONFLATED_RISK`) |
| **Temporal Hallucination** | Asserted value contradicts a node with `valid_to` in past (old address, closed status, expired Licence) | Node temporal validity vs assertion |
| **Geographic Boundary Breach** | Presence in a `does-not-serve` area, or absence in a `serves-area` | ServiceArea vs Mention location |
| **Authority Spoofing** | `Marketing Claim`/directory/membership treated as regulatory | Claim class vs `authoritative_for` |
| **Anchoring Fragility** | Present but collapses/inverts under follow-up | Perception-side; needs RealityCard to name the true competitor set |
| **Defective Observation** | Run-failure (fabricated business, unresolvable collision, unsupported registration, wrong contact-as-fact, unsupporting citation) | Quarantined, reported, never averaged |

`FIND-INV-01` Every Finding carries: verbatim machine/surface text, Run/SourceMention reference, date, assistant/surface, and the RealityCard field it contradicts (delivery guide Part 7). `FIND-INV-02` Defective Observations are reported as their own class, never silently averaged into a rate.

---

## 8. The Source Registry subsystem

The Source Registry is a **first-class subsystem** and the genuinely-new artifact of this module (Artifact Map layer 4). It catalogues the surfaces machines actually read and the surfaces the platform uses to corroborate reality — the ~393-surface inventory (`business_recommendation_urls_AU_US_UK_CA.md`, 406 catalogued rows across AU/US/UK/CA + GLOBAL) turned into a typed, versioned, lifecycle-managed catalogue. It maps to **ADR-012's provider-adapter pattern**: each RegistrySource is fronted by an adapter that knows how to reach, parse and normalise it.

### 8.1 RegistrySource object model

| Field | Type | Req | Notes |
|---|---|---|---|
| `registry_source_id` | `rg_src` (candidate) | ✔ | Immutable. **Not** `src_id` (frozen Source). |
| `name` | string | ✔ | e.g. "ASIC Registry Search", "AHPRA Register", "Google Maps text search". |
| `country` | enum | ✔ | `AU` \| `US` \| `UK` \| `CA` \| `GLOBAL` (extensible per OD-011 markets). |
| `jurisdiction` | string\|null | ✔ | State/territory/province where sub-national. |
| `category` | enum | ✔ | `BUSINESS_REGISTRY` \| `PROFESSIONAL_REGISTER` \| `LICENSING` \| `COURTS` \| `ENFORCEMENT` \| `REVIEWS` \| `MAPS` \| `PORTFOLIO` \| `TECHNICAL` \| `DISCOVERY` \| `NEWS` \| `ASSOCIATION` \| `SOCIAL` \| `AGGREGATOR`. |
| `purpose` | enum[] | ✔ | `candidate_discovery` \| `identity_verification` \| `credential_check` \| `regulatory_check` \| `reputation` \| `local_relevance` \| `technical_proof` \| `adverse_signal`. |
| `base_url` | URL | ✔ | |
| `query_template` | string\|null | ✔ | GET template with placeholders, or null for UI-only. |
| `fallback_query` | string\|null | — | Search-engine fallback with site restriction. |
| `access_mode` | enum | ✔ | `GET` \| `STABLE_UI` \| `POST_UI` \| `API` \| `LOGIN` \| `PAID` \| `DIRECTORY`. |
| `auth` | AuthSpec | ✔ | `{requires_login, requires_api_key, requires_payment}`. |
| `automation_status` | enum | ✔ | `permitted` \| `restricted` \| `prohibited` \| `unknown` — the ToS/robots gate. |
| `rate_limit_notes` | string\|null | — | |
| `authoritative_for` | fact-class[] | ✔ | What this surface *proves* (e.g. `[registration_status, licence_number]`). |
| `not_authoritative_for` | fact-class[] | ✔ | What it must NOT be treated as proving (e.g. `[professional_competence]`). |
| `authority_rank` | enum | ✔ | Position in the source-priority ladder (§8.3) — an ordinal label, not a numeric weight. |
| `industry_scope` | Industry ref[] | — | Verticals this surface serves. |
| `parser_ref` | ParserAdapter ref | ✔ (if automatable) | The adapter that reads it (§8.5). |
| `parser_version` | semver | ✔ (if parser_ref) | |
| `health` | HealthState | ✔ | §8.6. |
| `revalidation` | RevalidationPolicy | ✔ | §8.7. |
| `lifecycle_state` | enum | ✔ | §8.2. |
| `last_verified_at` | date | ✔ | |
| `source_version` | int | ✔ | Versioned definition (catalogue §11: "store as versioned source definitions, not hard-coded"). |
| `notes` | string\|null | — | |

### 8.2 RegistrySource lifecycle (state machine)

```
                 promote                 degrade (health/ToS)
  CANDIDATE ───────────────▶ ACTIVE ──────────────────▶ DEGRADED
      │  \                     │  ▲                          │
      │   \ reject             │  │ recover                  │ retire
      ▼    ▼                   │  └──────────────────────────┘
  REJECTED (never used)        │ quarantine (ToS/legal)
                               ▼
                          QUARANTINED ──── retire ───▶ RETIRED
```

| State | Meaning | Usable? |
|---|---|---|
| `CANDIDATE` | Catalogued, not yet verified/parsed | No (manual only). |
| `ACTIVE` | Verified, adapter healthy, ToS permits its access mode | Yes, per `automation_status`. |
| `DEGRADED` | Health-check failing / parser stale / partial | Read with warning; results flagged low-confidence. |
| `QUARANTINED` | ToS/robots/legal block or automation prohibited | Manual, human-scale only; no automated collector. |
| `RETIRED` | Surface dead/superseded | Historical Evidence retained; no new reads. |
| `REJECTED` | Evaluated and excluded | Never used. |

`SR-INV-01` A RegistrySource with `automation_status ∈ {prohibited}` OR `lifecycle_state=QUARANTINED` MUST NOT be read by any automated collector; only manual, human-scale access is permitted (encodes catalogue §9 "automate_a_registry_that_explicitly_prohibits_automated_search = NEVER", delivery guide Part 11.6, and the OD-010/ToS gate). `SR-INV-02` Retirement is non-destructive: Evidence collected while a RegistrySource was ACTIVE remains valid and provenance-linked to the RegistrySource version in force at collection time.

### 8.3 Source-priority ladder (authority ordering)

`authority_rank` is an **ordinal** drawn from the catalogue §8 priority list (highest first). It orders evidence authority; it is not summed or averaged.

```
1  statutory_registry
2  government_licensing_register
3  professional_regulator
4  court_or_tribunal_record
5  government_enforcement_database
6  official_accreditation_register
7  official_company_filing
8  independently_verifiable_project_record
9  reputable_news_source
10 first_party_website
11 professional_association_directory
12 map_profile
13 review_platform
14 commercial_directory
15 social_media
16 unverified_aggregator
```

`SR-INV-03` For any fact class, a `Verified` claim requires Evidence from a RegistrySource whose `authority_rank` is at or above the fact class's floor (e.g. licence status floor = `professional_regulator`; company existence floor = `official_company_filing`) AND whose `authoritative_for` covers the fact. Directory/review/social surfaces (ranks 11–16) can raise `Corroborated`/`Claimed`, never `Verified` credentials.

### 8.4 Authoritative-for / not-authoritative-for (fact-class gating)

Each RegistrySource declares the fact classes it can and cannot prove. Fact classes include: `entity_existence`, `registration_status`, `licence_number`, `licence_currency`, `disciplinary_record`, `court_finding`, `nap_component`, `service_experience`, `technical_signal`, `local_presence`, `professional_competence` (which **no** surface may claim to prove). This encodes the catalogue §9 false-certainty rules as data: `not_authoritative_for` on a company registry includes `professional_competence`; on a review platform includes `outcome_quality`; on a membership directory includes `licence_currency`.

### 8.5 Provider-adapter contract (ADR-012 pattern)

Each automatable RegistrySource is fronted by a **ParserAdapter** implementing a neutral contract (framework-agnostic; Rails service-object realisation is an implementation detail):

```
interface ProviderAdapter {
  fetch(query_params) -> RawResponse            // honours access_mode, auth, rate limits
  parse(RawResponse)  -> StructuredRecords[]    // versioned parser; returns typed facts
  normalise(records)  -> CanonicalFacts[]       // to Reality Graph fact classes
  health_check()      -> HealthResult           // §8.6
  capabilities()      -> { access_mode, automation_status, fact_classes }
}
```

`SR-INV-04` An adapter MUST NOT invent query parameters for UI-only forms (`access_mode ∈ {STABLE_UI, POST_UI}` ⇒ no synthesised GET params; catalogue §9 "invent_query_parameters_for_UI_only_forms = NEVER"). `SR-INV-05` Every fact an adapter emits carries the `registry_source_id` + `parser_version` into Evidence Provenance (`source_system`), so a later parser regression is traceable and re-runnable.

### 8.6 Health checks

```
HealthState := {
  status: enum(healthy | slow | changed_layout | blocked | dead),
  last_check_at, last_success_at,
  consecutive_failures: int,
  signal: enum(http_status | selector_present | record_shape | ToS_marker)
}
```

`SR-INV-06` `consecutive_failures ≥ threshold` OR `status ∈ {changed_layout, blocked, dead}` transitions the RegistrySource to `DEGRADED`/`QUARANTINED` and flags all facts sourced since `last_success_at` for re-verification. Layout-change detection is the parser-rot early-warning (parser versioning couples to it).

### 8.7 Revalidation schedule

```
RevalidationPolicy := {
  cadence: enum(on_use | daily | weekly | monthly | quarterly | on_change_signal),
  max_staleness_days: int,
  clock_layer: enum(retrieval | corpus)      // retrieval surfaces revalidate fast; corpus never promised
}
```

`SR-INV-07` A RegistrySource whose `last_verified_at` exceeds `max_staleness_days` is `DEGRADED` until re-verified. Registers/maps/reviews are retrieval-layer (fast cadence); nothing in the registry schedules corpus-layer change (two-clock rule).

### 8.8 Rules against false certainty (encoded)

The catalogue §9 prohibitions are encoded as registry-level invariants, restated as a checklist a build agent MUST satisfy:

1. `SR-INV-04` no invented UI params.
2. `SR-INV-03` company record ⇏ competence; membership ⇏ licensing; directory ⇏ regulatory verification; review stars ⇏ outcome quality (all via `not_authoritative_for` + `authority_rank` floors).
3. `RG-CLAIM-03` allegation ⇏ finding.
4. `ER-INV-02` no same-name merge without identity matching.
5. absence from one database ⇏ nonexistence (`UNRESOLVED` ≠ negative fact; requires ≥2 authoritative surfaces before a negative existence claim).
6. `SR-INV-01` never automate a prohibited registry.
7. no publication of sensitive personal detail unnecessary to the recommendation (delivery guide Part 11; adverse records handled verbally first).

---

## 9. Per-vertical evidence policies (versioned policy objects)

The machines agree that **regulated verticals invert the evidence hierarchy** (synthesis §2.4): registers gate everything, reviews are secondary, abstention/shortlists replace single winners; unregulated verticals lean on portfolios, case studies and reviews. This is captured as a **VerticalEvidencePolicy** — a versioned policy object per Industry (Artifact Map layer 5; the repo's existing versioned-policy idiom, e.g. `check-catalog-v1`).

### 9.1 VerticalEvidencePolicy object

| Field | Type | Req | Notes |
|---|---|---|---|
| `policy_id` | `rg_vep` | ✔ | |
| `industry_id` | Industry ref | ✔ | |
| `policy_version` | semver | ✔ | Immutable once issued; new evidence ⇒ new version (never overwrite). |
| `regulation_class` | enum | ✔ | `register_gated` \| `licence_gated` \| `membership_signalled` \| `unregulated`. |
| `required_registers` | RegistrySource id[] | ✔ | The register(s) that gate the vertical (e.g. TPB, AHPRA, state bar, VBA/QBCC, ASIC FAR). Empty for unregulated. |
| `evidence_hierarchy` | fact-class ordering | ✔ | Ordered list — the vertical's authority ranking (inverted for regulated). |
| `abstention_rule` | enum | ✔ | `shortlist_and_abstain` (regulated) \| `single_or_shortlist` (unregulated). |
| `required_practitioner_registration` | bool | ✔ | Whether individual Practitioner Licences are mandatory (health/legal/advice = true). |
| `red_flag_surfaces` | RegistrySource id[] | ✔ | Layer-6 adverse surfaces for the vertical (AustLII, banned-&-disqualified, AFCA, AHPRA tribunal…). |
| `question_archetypes` | ref | ✔ | QUESTION_BANK archetypes selected for this vertical. |
| `disclaimer_required` | bool | ✔ | Regulated verticals carry the "measurement of assistant behaviour, not professional advice" disclaimer (delivery guide Part 11.4). |
| `derived_from_pilot` | bool | ✔ | `true` once written from pilot data (v1 seeds are `false`, marked provisional). |

### 9.2 The regulated-vs-unregulated inversion

| Class | Gate | Reviews | Winner shape | Practitioner reg | Example verticals |
|---|---|---|---|---|---|
| `register_gated` | Register presence + currency is decisive | Secondary | Shortlist + abstain | Required | Accountants/tax (TPB), financial advice (ASIC FAR/AFS), health (AHPRA), legal (bar/law society) |
| `licence_gated` | Occupational licence decisive | Secondary | Shortlist | Business or individual | Builders/trades (VBA/QBCC/NSW Fair Trading), real estate/buyers agents, childcare (ACECQA/NDIS) |
| `membership_signalled` | Membership corroborates, doesn't gate | Meaningful | Shortlist/single | Optional | Brokers (MFAA/FBAA), some consultants |
| `unregulated` | Portfolio/case studies/reviews dominate | Primary | Single or shortlist | n/a | Agencies, coaches, IT/MSP, most trades marketing |

`VEP-INV-01` For a `register_gated`/`licence_gated` Industry, entity resolution and any recommendation-readiness assessment MUST require a `current` Licence (Business or Practitioner per policy) before any credential is presented as `Verified`; absence/expiry is a first-class Finding, not a downgrade of a score. `VEP-INV-02` Policies are versioned and immutable; a report cites the exact `policy_version` in force at assessment (reproducibility; Artifact Map "versioned policies"). `VEP-INV-03` Seed policies (`derived_from_pilot=false`) are provisional and MUST be labelled as such until rewritten from pilot data.

---

## 10. JSON Schemas (Draft 2020-12 style; provider-neutral)

> These are candidate contracts. Field names use the module's candidate namespaces; enums mirror §3/§8/§9. They intentionally reference frozen types (`evd_id`, `prj_id`, `org_id`) without redefining them.

### 10.1 Reality Graph entity (node)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "reality-graph-node-v0",
  "type": "object",
  "required": ["node_id","node_type","project_id","organization_id","canonical",
               "claim_class","confidence_band","source_of_truth",
               "first_observed_at","last_verified_at","version","layer","properties"],
  "properties": {
    "node_id": { "type": "string" },
    "node_type": { "enum": ["Business","Practitioner","Company","Brand","Franchise",
                            "Office","Location","Regulator","Licence","Service",
                            "Industry","RegistrySource","SourceMention","Review"] },
    "project_id": { "type": "string", "pattern": "^prj_" },
    "organization_id": { "type": "string", "pattern": "^org_" },
    "canonical": { "type": "boolean" },
    "claim_class": { "enum": ["Verified","Corroborated","Claimed","Inferred","Estimated",
                              "Opinion","Allegation","CourtOrRegulatorFinding",
                              "MarketingClaim","AISummary"] },
    "confidence_band": { "type": "string", "description": "OD-003 band label; NOT a numeric composite" },
    "evidence_ids": { "type": "array", "items": { "type": "string", "pattern": "^evd_" } },
    "source_of_truth": { "enum": ["reality_card","client_asserted","surface_observed","derived"] },
    "layer": { "enum": ["retrieval","corpus","n/a"] },
    "valid_from": { "type": ["string","null"], "format": "date-time" },
    "valid_to":   { "type": ["string","null"], "format": "date-time" },
    "first_observed_at": { "type": "string", "format": "date-time" },
    "last_verified_at":  { "type": "string", "format": "date-time" },
    "version": { "type": "integer", "minimum": 1 },
    "superseded_by": { "type": ["string","null"] },
    "properties": { "type": "object", "description": "type-specific per §3" }
  },
  "allOf": [
    { "if": { "properties": { "claim_class": { "enum": ["Verified","Corroborated"] } } },
      "then": { "required": ["evidence_ids"],
                "properties": { "evidence_ids": { "minItems": 1 } } } }
  ]
}
```

### 10.2 RegistrySource (Source Registry entry)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "registry-source-v0",
  "type": "object",
  "required": ["registry_source_id","name","country","category","purpose","base_url",
               "access_mode","auth","automation_status","authoritative_for",
               "not_authoritative_for","authority_rank","health","revalidation",
               "lifecycle_state","last_verified_at","source_version"],
  "properties": {
    "registry_source_id": { "type": "string", "pattern": "^rg_src_" },
    "name": { "type": "string" },
    "country": { "enum": ["AU","US","UK","CA","GLOBAL"] },
    "jurisdiction": { "type": ["string","null"] },
    "category": { "enum": ["BUSINESS_REGISTRY","PROFESSIONAL_REGISTER","LICENSING","COURTS",
                          "ENFORCEMENT","REVIEWS","MAPS","PORTFOLIO","TECHNICAL","DISCOVERY",
                          "NEWS","ASSOCIATION","SOCIAL","AGGREGATOR"] },
    "purpose": { "type": "array", "items": { "enum": ["candidate_discovery","identity_verification",
                 "credential_check","regulatory_check","reputation","local_relevance",
                 "technical_proof","adverse_signal"] } },
    "base_url": { "type": "string", "format": "uri" },
    "query_template": { "type": ["string","null"] },
    "fallback_query": { "type": ["string","null"] },
    "access_mode": { "enum": ["GET","STABLE_UI","POST_UI","API","LOGIN","PAID","DIRECTORY"] },
    "auth": { "type": "object",
      "required": ["requires_login","requires_api_key","requires_payment"],
      "properties": {
        "requires_login": { "type": "boolean" },
        "requires_api_key": { "type": "boolean" },
        "requires_payment": { "type": "boolean" } } },
    "automation_status": { "enum": ["permitted","restricted","prohibited","unknown"] },
    "rate_limit_notes": { "type": ["string","null"] },
    "authoritative_for": { "type": "array", "items": { "type": "string" } },
    "not_authoritative_for": { "type": "array", "items": { "type": "string" } },
    "authority_rank": { "enum": ["statutory_registry","government_licensing_register",
      "professional_regulator","court_or_tribunal_record","government_enforcement_database",
      "official_accreditation_register","official_company_filing",
      "independently_verifiable_project_record","reputable_news_source","first_party_website",
      "professional_association_directory","map_profile","review_platform","commercial_directory",
      "social_media","unverified_aggregator"] },
    "industry_scope": { "type": "array", "items": { "type": "string" } },
    "parser_ref": { "type": ["string","null"] },
    "parser_version": { "type": ["string","null"] },
    "health": { "type": "object",
      "required": ["status","last_check_at","consecutive_failures"],
      "properties": {
        "status": { "enum": ["healthy","slow","changed_layout","blocked","dead"] },
        "last_check_at": { "type": "string", "format": "date-time" },
        "last_success_at": { "type": ["string","null"], "format": "date-time" },
        "consecutive_failures": { "type": "integer", "minimum": 0 } } },
    "revalidation": { "type": "object",
      "required": ["cadence","max_staleness_days","clock_layer"],
      "properties": {
        "cadence": { "enum": ["on_use","daily","weekly","monthly","quarterly","on_change_signal"] },
        "max_staleness_days": { "type": "integer", "minimum": 0 },
        "clock_layer": { "enum": ["retrieval","corpus"] } } },
    "lifecycle_state": { "enum": ["CANDIDATE","ACTIVE","DEGRADED","QUARANTINED","RETIRED","REJECTED"] },
    "last_verified_at": { "type": "string", "format": "date" },
    "source_version": { "type": "integer", "minimum": 1 },
    "notes": { "type": ["string","null"] }
  },
  "allOf": [
    { "if": { "properties": { "automation_status": { "const": "prohibited" } } },
      "then": { "description": "SR-INV-01: no automated collector; manual only" } },
    { "if": { "properties": { "access_mode": { "enum": ["STABLE_UI","POST_UI"] } } },
      "then": { "properties": { "query_template": { "const": null },
                "description": "SR-INV-04: no invented GET params for UI-only forms" } } }
  ]
}
```

### 10.3 RealityCard

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "reality-card-v0",
  "type": "object",
  "required": ["reality_card_id","project_id","subject_business_id","version",
               "nap","service_map","confusables","locations_and_area","completeness","built_at"],
  "properties": {
    "reality_card_id": { "type": "string", "pattern": "^rg_card_" },
    "project_id": { "type": "string", "pattern": "^prj_" },
    "subject_business_id": { "type": "string", "pattern": "^rg_biz_" },
    "version": { "type": "integer", "minimum": 1 },
    "nap": { "type": "object",
      "required": ["name","address","phone","website"],
      "properties": {
        "name": { "type": "object", "required": ["legal_name","primary_trading_name"] },
        "address": { "type": "object", "required": ["formatted"] },
        "phone": { "type": "object", "required": ["e164"] },
        "website": { "type": "object", "required": ["canonical_url"] } } },
    "registrations": { "type": "array", "items": { "type": "string", "pattern": "^rg_lic_" } },
    "service_map": { "type": "array", "items": {
      "type": "object", "required": ["service_ref","buyer_phrases","page_url"],
      "properties": {
        "service_ref": { "type": "string" },
        "buyer_phrases": { "type": "array", "items": { "type": "string" }, "minItems": 1 },
        "page_url": { "type": ["string","null"] },
        "page_indexed": { "type": ["boolean","null"] },
        "gap_reason": { "type": ["string","null"] } } } },
    "confusables": { "type": "array", "items": {
      "type": "object", "required": ["confusable_id","kind","entity_ref","distinguishers"],
      "properties": {
        "kind": { "enum": ["similar_name","firm_vs_practitioner","old_trading_name",
                          "co_located","same_franchise_branch","homograph","other"] },
        "distinguishers": { "type": "array", "minItems": 1, "items": { "type": "string" } },
        "probe_question": { "type": ["string","null"] } } } },
    "locations_and_area": { "type": "object",
      "required": ["serves","does_not_serve"],
      "properties": {
        "serves": { "type": "array", "items": { "type": "string" } },
        "does_not_serve": { "type": "array", "items": { "type": "string" } } } },
    "people": { "type": "array", "items": { "type": "string", "pattern": "^rg_prac_" } },
    "completeness": { "type": "object", "description": "per-section filled/missing COUNTS, no composite %" },
    "built_at": { "type": "string", "format": "date-time" }
  }
}
```

### 10.4 VerticalEvidencePolicy

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "vertical-evidence-policy-v0",
  "type": "object",
  "required": ["policy_id","industry_id","policy_version","regulation_class",
               "required_registers","evidence_hierarchy","abstention_rule",
               "required_practitioner_registration","red_flag_surfaces",
               "disclaimer_required","derived_from_pilot"],
  "properties": {
    "policy_id": { "type": "string", "pattern": "^rg_vep_" },
    "industry_id": { "type": "string", "pattern": "^rg_ind_" },
    "policy_version": { "type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$" },
    "regulation_class": { "enum": ["register_gated","licence_gated","membership_signalled","unregulated"] },
    "required_registers": { "type": "array", "items": { "type": "string", "pattern": "^rg_src_" } },
    "evidence_hierarchy": { "type": "array", "items": { "type": "string" },
      "description": "ordered fact classes; inverted for regulated verticals" },
    "abstention_rule": { "enum": ["shortlist_and_abstain","single_or_shortlist"] },
    "required_practitioner_registration": { "type": "boolean" },
    "red_flag_surfaces": { "type": "array", "items": { "type": "string", "pattern": "^rg_src_" } },
    "question_archetypes": { "type": ["string","null"] },
    "disclaimer_required": { "type": "boolean" },
    "derived_from_pilot": { "type": "boolean" }
  }
}
```

---

## 11. Integration with the wider platform

- **Reality → Gap.** Canonical Reality Graph nodes + the findings taxonomy (§7) are the ground truth the COMPARE stage diffs Perception against. A Finding is a Gap-Graph input; it becomes a customer-facing `Issue` (frozen) only through the Evaluation → Issue pathway (011), not by this module's fiat.
- **Source → Evidence/Provenance.** Every corroboration or health observation from a RegistrySource is written as Evidence with a CLOSED-taxonomy Evidence Type (`crawl_observation`/`parsed_content`/`source_document`/`external_measurement`/`verification_observation`), with the RegistrySource id + `parser_version` in Evidence Provenance (`source_system`). No new Evidence Type is created (ADR-017).
- **OD-010 gate.** Any *external measurement* (querying assistants; automated fetch of RegistrySources beyond human-scale) is gated by the OD-010 Measurement Set decision and the counsel ToS/robots analysis. The Reality Graph and RegistrySource *models* are buildable now; their automated collectors are not authorised until that decision lands. Manual, human-scale capture (the concierge Reality Card) is the interim producer.
- **Two clocks, everywhere.** `layer` on nodes and `clock_layer` on revalidation policies keep retrieval-layer facts (fast, re-measurable) and corpus-layer facts (slow, never promised) separated at the data level. No customer-facing surface may attach a schedule to a corpus-layer change.
- **Codification bridge.** The delivery-guide Part-12 log shapes (run/audit/fix) are the manual-era projections of these objects: audit-log rows → RegistrySource observations + SourceMentions; run-log rows → Run/Mention + resolution; fix-log rows → the intervention plans the Intelligence Graph will own. Twenty concierge clients logged this way seed the first Reality Graph and calibrate the confidence bands.

---

## 12. Acceptance criteria

A future implementation of Module 2 is conformant when:

1. **Ontology completeness.** Every node type in §3 and every edge type in §4 is representable with its full envelope; the property-graph model is persistence-agnostic (no framework/table/queue leaks; DM-REQ-018).
2. **Evidence backing.** No node/edge with `claim_class ∈ {Verified, Corroborated}` exists without ≥1 `evd_id` (RG-INV-01); every corroboration Evidence carries `registry_source_id` + `parser_version` in provenance (SR-INV-05). Automated tests validate each invariant (DM-REQ-004/012).
3. **Reality Card gate.** A RealityCard is gate-complete only with NAP + registrations (for register-gated verticals) + service_map + confusables + service-area (RC-INV-01); entity resolution runs in labelled *degraded/Inferred* mode against an incomplete card.
4. **Entity resolution.** The §6.3 decision function is implemented as a *counted-feature function*, not a composite score; `registration_number.disagree` dominates name agreement (ER-INV-02); confusable danger-zone matches raise Entity-Conflation Findings (ER-INV-03); ambiguous/unresolved states abstain rather than guess (ER-INV-04).
5. **No composite scores.** Nowhere does a customer-facing surface present a blended entity/authority/ranking number; confidence is an OD-003 band label + counts (branding claim rule; synthesis §4).
6. **Source Registry as data.** The ~393 catalogued surfaces load as versioned RegistrySource records with category/purpose/access_mode/authority_rank/`authoritative_for`/`not_authoritative_for`/lifecycle/health/revalidation; retirement is non-destructive (SR-INV-02).
7. **Automation gate honoured.** No automated collector reads a `prohibited`/`QUARANTINED` RegistrySource; UI-only surfaces get no synthesised GET params (SR-INV-01/04). This holds pending OD-010.
8. **False-certainty rules encoded.** All seven catalogue §9 prohibitions are enforced by registry/claim invariants (§8.8), including "membership ≠ licensing", "review stars ≠ competence", "allegation ≠ finding", "absence-from-one-db ≠ nonexistence".
9. **Vertical policies versioned.** Each pilot Industry has a VerticalEvidencePolicy with immutable `policy_version`; register-gated verticals require a `current` Licence before any `Verified` credential (VEP-INV-01); seed (non-pilot-derived) policies are labelled provisional.
10. **Two-clock integrity.** Every node/policy declares its clock layer; no corpus-layer change is scheduled or promised anywhere in the model or its outputs.
11. **Findings integrity.** Every Finding carries verbatim text + reference + date + assistant/surface + contradicted RealityCard field; Defective Observations are their own class, never averaged (FIND-INV-01/02).
12. **Vocabulary discipline.** The document/model never overloads frozen `Source`/`Citation`/`Issue`; candidate terms (RegistrySource, SourceMention, Finding, RealityCard) are used exactly and flagged; no new Evidence Type is introduced.

---

## 13. Open questions (ADR-gated — resolve before build)

1. **Reality-side `Source` collision.** The ontology's reference-surface concept collides with the frozen platform `Source` (`src_id`). Candidate: **RegistrySource**. ADR decision at vision-set filing.
2. **Reality-side `Citation` collision.** Reality-side "surface asserts fact about business" collides with frozen `Citation` (`cit_id`, `citation-policy-v1`). Candidate: **SourceMention**. ADR decision.
3. **Finding vs Issue.** Carried unresolved per governance (known collision). Recorded, not resolved.
4. **ADR-012 / ADR-013 numbering collision.** Vision-set ADR-012 (Reality Graph) / ADR-013 (Genesis) collide with accepted ADR-012 (Foundation Baseline) / ADR-013 (Diagram Authority). Filing must renumber.
5. **Entity-resolution thresholds & OD-003 alignment.** The `name_fuzzy` distance threshold and the state cutoffs are documented as a decision function but need exact values and mapping to OD-003 confidence bands — owner ruling required. (They must remain counted-feature functions, never composite scores.)
6. **Source Registry automation gate.** Which `access_mode`/`automation_status` combinations the platform may auto-fetch, and when, is gated by OD-010 + counsel's ToS/robots analysis. `prohibited` surfaces are manual indefinitely.
7. **Persistence model.** Native graph store vs relational adjacency vs hybrid for the Reality Graph — architecture ADR at Phase 2.
8. **Vertical policy authorship.** Which verticals get v1 canonical VerticalEvidencePolicies, written from pilot data (layer 5), and who owns the seed→pilot rewrite.
9. **Claim-class binding.** Reconcile this module's `claim_class` usage to the planned Truth & Claims Specification (which is drafted at filing and constrains all of Volume III).
10. **Regulator/Licence reference data.** Authoritative seed for Regulator nodes and licence-number formats per jurisdiction/vertical, with a maintained-dataset owner — partially derivable from the country source registries but currently unowned.
