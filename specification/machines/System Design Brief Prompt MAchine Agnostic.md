# VIDET — Reality-Grounded Business Recommendation System Design Brief**

## **Primary objective**

Design a commercial system capable of answering and evaluating buyer-intent questions about businesses across many industries, locations and decision types.

The system should support questions such as:

- Who is the best accountant in a particular suburb?
- Recommend an AI consultant for a dental group.
- Which lawyer should a small business use for a shareholder dispute?
- Where is a safe cosmetic clinic nearby?
- Who installs sprung floors for dance studios?
- Is a named business reputable?
- Is a quoted price reasonable?
- Do I need a professional, or can I handle this myself?
- Which of three shortlisted businesses would you choose for a particular buyer?

The intended system is called **VIDET**.

Your primary task is to design how VIDET should work.

However, your design must be grounded in reality rather than an idealised or imaginary recommendation architecture.

------

# **Core instruction: default to reality**

Where your own model, search product, retrieval system or connected tools already perform any relevant part of this process, explain and use that real behaviour as an input to your design.

Examples include:

- query interpretation;
- web search;
- local or map search;
- candidate discovery;
- retrieval;
- source selection;
- reranking;
- citation generation;
- factual verification;
- entity resolution;
- recommendation ordering;
- handling of follow-up questions;
- uncertainty;
- current-information checks;
- professional-register searches;
- comparison of candidates.

Do not reinvent a hypothetical system when a real mechanism is known, documented, exposed or reasonably observable.

At the same time, do not imply that your own implementation is suitable for VIDET merely because it exists.

Evaluate it critically.

For every significant part of the proposed architecture, identify whether your recommendation is based on:

```text
DIRECTLY KNOWN
The behaviour is exposed to you or is part of the tools available in this interaction.

DOCUMENTED
The behaviour is publicly documented by your provider or tool provider.

OBSERVED PRODUCT BEHAVIOUR
The behaviour can be inferred with reasonable confidence from how the product operates.

REASONABLE ENGINEERING INFERENCE
The exact implementation is inaccessible, but this is a plausible functional explanation.

PROPOSED EXTERNAL DESIGN
This is your recommendation for VIDET, not a claim about your own internal implementation.

UNCERTAINTY
You cannot determine the answer confidently.

INACCESSIBLE PROPRIETARY DETAIL
The answer would require private code, weights, system prompts, ranking logic, training data or infrastructure to which you do not have access.
```

Never present a proposed external design as though it describes your own proprietary implementation.

Never fabricate:

- hidden ranking weights;
- confidence thresholds;
- source lists;
- internal search algorithms;
- model-routing rules;
- proprietary system prompts;
- training-data inclusion;
- undocumented APIs;
- hidden quality scores.

Do not claim to provide hidden chain-of-thought.

Provide concise functional explanations instead.

------

# **Part I — Reality check before architecture**

Before proposing the design, explain which parts of business recommendation your own model or product can actually perform today.

Address:

1. Query interpretation
2. Industry classification
3. Location interpretation
4. Candidate discovery
5. General web search
6. Maps or local-search access
7. Official-register access
8. Review access
9. Source-page inspection
10. Entity matching
11. Evidence comparison
12. Factual verification
13. Candidate scoring
14. Candidate ordering
15. Recommendation explanation
16. Follow-up reranking
17. Current opening-hours or availability checks
18. Price research
19. High-stakes or regulated-profession safeguards
20. Citation and evidence retention

For each capability, state:

- what is genuinely available;
- what is unavailable;
- what depends on the product surface or enabled tools;
- what is deterministic;
- what is model-generated;
- what is delegated to search, maps, APIs or external ranking systems;
- what is unknown.

Then explain which of those real capabilities should be reused, emulated, wrapped, tested or rejected in VIDET.

------

# **Part II — The fundamental design decision**

Determine what VIDET actually is.

Consider at least these possibilities:

### **Option A — Measurement system**

VIDET repeatedly asks existing AI assistants buyer-intent questions and measures:

- which businesses are mentioned;
- their order;
- citations;
- factual accuracy;
- recommendation consistency;
- shortlist collapse;
- response changes over time;
- visibility across models.

### **Option B — Independent recommendation engine**

VIDET discovers, verifies, scores and recommends businesses using its own evidence and policies.

### **Option C — Hybrid system**

VIDET separately:

1. measures how external assistants behave; and
2. operates its own evidence-based recommendation engine.

Explain which model is commercially and technically defensible.

Do not blur measurement of external AI behaviour with construction of an ideal recommendation engine.

They are different systems with different truth claims.

------

# **Part III — Complete buyer-intent coverage**

VIDET must handle these nine question archetypes.

## **A. Recommendation**

Examples:

- Who is the best {business_type} in {place}?
- Recommend a {business_type} near {suburb}.
- Top three {business_type} businesses in {city}, and why?
- Who should I consider?

## **B. Problem-first**

Examples:

- My BAS is overdue and I am worried about penalties. Who can help?
- My website gets traffic but no enquiries. What should I do?
- My crown fell out on Saturday. Who is open nearby?
- Our builder became insolvent during construction. Who can take over?

The category may not appear explicitly in the question.

## **C. Attribute or niche**

Examples:

- Fixed-fee accountant
- Female practitioner
- Saturday appointments
- Speaks a particular language
- Works with trades
- NDIS-registered
- Sprung-floor specialist
- Experience with self-employed borrowers

## **D. Comparison**

Examples:

- Compare Business A with Business B.
- Give me three options with strengths and limitations.
- Which is better for a first-time buyer?

## **E. Validation**

Examples:

- Is {business} any good?
- Is it licensed?
- What do reviews say?
- Who owns or operates it?
- Does it actually specialise in the claimed service?

## **F. Selection criteria**

Examples:

- How do I choose?
- What should I look for?
- What questions should I ask?
- Which credentials matter?

## **G. Price and value**

Examples:

- What should this service cost?
- Is this quote reasonable?
- What is normally included?
- Which option is cheapest?
- Which represents the best value?

## **H. Urgency and logistics**

Examples:

- Open now
- Available Saturday
- Emergency service
- Can start this week
- Has current appointments or places

## **I. Hire-or-not**

Examples:

- Do I need this kind of professional?
- Can I do it myself?
- Should I use a broker or go directly to a bank?
- Should I use an agency, freelancer or employee?

Explain how each archetype changes:

- retrieval;
- evidence requirements;
- candidate generation;
- ranking;
- safety;
- response structure;
- need for current information;
- abstention thresholds.

------

# **Part IV — Required industries and business types**

The design must explicitly support the following.

## **Tier 1 — Multiplier verticals**

These businesses serve other businesses and may function as distribution or referral channels.

### **Accountants and bookkeepers**

Include:

- small-business accountants;
- tax agents;
- BAS agents;
- bookkeepers;
- Xero specialists;
- industry-specific accountants;
- business-sale advice;
- audit and dispute support.

### **Business coaches and consultants**

Include:

- growth coaches;
- management consultants;
- operational consultants;
- culture and leadership advisers;
- advisory boards;
- practical operators versus motivational coaches.

### **Marketing, web and branding businesses**

Include:

- digital marketing agencies;
- SEO companies;
- paid advertising specialists;
- web-design agencies;
- branding studios;
- freelancers;
- conversion-rate specialists;
- industry-specific agencies.

### **Business and commercial lawyers and conveyancers**

Include:

- contracts;
- disputes;
- debt recovery;
- partnerships and shareholder matters;
- business purchases;
- commercial property;
- conveyancing.

### **Mortgage and commercial-finance brokers**

Include:

- residential mortgages;
- self-employed borrowers;
- business lending;
- equipment finance;
- commercial property;
- rejected applications.

### **Insurance brokers**

Include:

- business insurance;
- professional indemnity;
- public liability;
- trade and clinic insurance;
- renewal reviews;
- specialist commercial risks.

### **IT providers and managed-service providers**

Include:

- small-business IT support;
- managed IT;
- cyber incidents;
- email compromise;
- cloud migration;
- infrastructure takeover;
- cybersecurity and compliance.

## **Tier 2 — High-value local verticals**

### **Financial planners and advisers**

Include:

- business owners;
- retirement planning;
- inheritances;
- fee-only advice;
- licensing and complaints;
- flat-fee versus asset-based charges.

### **Cosmetic clinics and medispas**

Include:

- cosmetic injectables;
- fillers;
- anti-wrinkle treatment;
- complication management;
- practitioner qualification;
- medical oversight;
- clinic safety.

### **Dentists and orthodontists**

Include:

- general dentistry;
- anxious patients;
- emergency treatment;
- paediatric dentistry;
- implants;
- orthodontics;
- invisible aligners;
- government-supported dental programs where relevant.

### **Allied health and wellness**

Include:

- physiotherapy;
- chiropractic;
- osteopathy;
- naturopathy;
- psychology;
- mental-health-plan availability;
- referrals;
- comparative modality questions.

### **Veterinarians**

Include:

- general vets;
- emergency vets;
- exotic animals;
- anxious pets;
- desexing;
- poisoning and urgent cases.

### **Buyers’ agents and real estate agents**

Include:

- first-home buyers;
- auction support;
- suburb-specific selling agents;
- property-type fit;
- recent comparable results;
- fees;
- local track record.

### **Architects and building designers**

Include:

- residential architecture;
- renovation and extensions;
- heritage homes;
- building designers;
- draftspersons;
- project fees;
- portfolios.

### **Custom and commercial builders**

Include:

- custom homes;
- commercial construction;
- licence and insurance checks;
- delay and completion risk;
- insolvency history;
- disputes;
- incomplete projects.

### **High-end and specialist trades**

Include:

- timber flooring;
- engineered flooring;
- commercial flooring;
- sprung floors;
- pools;
- kitchens;
- solar;
- landscaping;
- specialist installation;
- remedial work;
- cost-per-unit questions.

### **Childcare and early education**

Include:

- centre comparison;
- current places;
- educational philosophy;
- national quality ratings;
- inspection and compliance information;
- local availability.

## **Tier 3 — Referral machines and channel structures**

Include:

- franchisors;
- industry associations;
- professional bodies;
- BNI chapters;
- chambers of commerce;
- buying groups;
- dealer networks;
- manufacturer installer networks;
- membership communities.

These are not ordinary local-service recommendations.

They require channel-partner and fan-out scoring.

------

# **Part V — Universal versus industry-specific design**

Separate the system into:

```pseudocode
UNIVERSAL PIPELINE
    query understanding
    entity extraction
    location interpretation
    candidate discovery
    evidence collection
    evidence provenance
    entity resolution
    contradiction detection
    confidence calculation
    audit logging
    output validation

INDUSTRY POLICY
    required licences
    relevant regulators
    appropriate evidence
    high-risk exclusions
    specialist-fit criteria
    review usefulness
    price comparability
    geography importance
    practitioner-versus-firm distinction
    outcome evidence
    red flags

QUERY POLICY
    best
    good
    near me
    cheapest
    best value
    specialist
    urgent
    comparison
    named-business validation
    hire-or-not
    referral partner
    channel partner
```

Explain what absolutely must not be universalised.

------

# **Part VI — Architecture**

Design the full architecture from user question to final answer.

At minimum include:

```pseudocode
receive_question()

classify_question_archetype()

extract:
    business_category
    problem
    service
    location
    buyer_type
    urgency
    budget
    constraints
    niche_attributes
    named_entities

load_industry_policy()

load_query_policy()

determine_current_information_requirements()

construct_discovery_plan()

discover_candidates()

resolve_candidate_entities()

collect_evidence()

verify_required_registrations()

separate:
    company
    office
    practitioner
    brand
    franchise
    network

normalise_facts()

detect_conflicts()

calculate_evidence_confidence()

apply_hard_exclusions()

calculate_features()

score_in_deterministic_code()

apply_risk_adjustments()

rank_candidates()

apply_diversity_rules()

decide:
    single winner
    shortlist
    insufficient evidence
    clarification
    urgent safety response

generate_explanation()

validate_every_claim_against_evidence()

store_replay_record()

return_answer()
```

Identify which functions should be:

- deterministic application code;
- LLM classification;
- LLM extraction;
- search engine;
- maps provider;
- database operation;
- external API;
- human review;
- prohibited from autonomous use.

------

# **Part VII — Candidate discovery**

Explain how VIDET should find candidates.

Include:

- general web search;
- maps and local search;
- government business registries;
- professional registers;
- licensing boards;
- industry associations;
- accreditation bodies;
- manufacturer directories;
- review platforms;
- official business websites;
- directories;
- trade portals;
- case studies;
- news;
- courts and tribunals;
- disciplinary findings;
- government enforcement;
- procurement records;
- professional profiles;
- LinkedIn;
- GitHub;
- domain and website history;
- structured data;
- opening-hours data;
- pricing pages;
- portfolios;
- local publications.

For each source class, state:

- what it can establish;
- what it cannot establish;
- authority level;
- freshness;
- automation restrictions;
- likely failure modes.

Where your own product uses any equivalent real retrieval method, compare it directly with the proposed VIDET approach.

------

# **Part VIII — Evidence and provenance model**

Design a canonical evidence structure.

Every material fact should retain:

```json
{
  "field": "registration.status",
  "value": "current",
  "entity_scope": "individual_practitioner",
  "verification_status": "verified",
  "source_type": "professional_regulator",
  "source_name": "Example regulator",
  "source_url": "https://example.gov/register/...",
  "retrieved_at": "ISO-8601",
  "source_published_at": null,
  "confidence": 0.98,
  "expires_at": null,
  "contradicted_by": [],
  "notes": null
}
```

Explain:

- field-level confidence;
- source authority;
- source independence;
- recency;
- cross-source agreement;
- contradiction penalties;
- marketing-claim penalties;
- expiry;
- revalidation.

Design schemas for:

1. Request
2. Search plan
3. Source definition
4. Candidate
5. Entity identity
6. Practitioner
7. Location
8. Fact
9. Review evidence
10. Registration
11. Case study
12. Pricing evidence
13. Contradiction
14. Red flag
15. Feature scores
16. Recommendation decision
17. Final response
18. Audit and replay record

------

# **Part IX — Entity resolution**

Explain how the system avoids confusing:

- two similarly named businesses;
- a company and its trading name;
- a franchise and an individual location;
- a firm and a practitioner;
- a former practitioner and a current practitioner;
- parent and subsidiary;
- similarly named professionals;
- an old address and current address;
- a dissolved entity and an active successor.

Use identifiers such as:

- company number;
- ABN or equivalent;
- registration number;
- domain;
- address;
- phone;
- practitioner number;
- map place identifier;
- official licence record.

Show entity-resolution pseudocode and confidence rules.

------

# **Part X — Industry policies**

Create concrete policy examples for every required industry.

For each policy include:

```json
{
  "industry": "string",
  "regulatory_risk": "low | medium | high | critical",
  "decision_stakes": "low | medium | high | critical",
  "locality_importance": "low | medium | high | critical",
  "specialisation_importance": "low | medium | high | critical",
  "required_checks": [],
  "hard_exclusions": [],
  "important_features": [],
  "review_role": "string",
  "price_comparability": "easy | moderate | difficult",
  "preferred_output": "winner | shortlist | abstain",
  "red_flags": [],
  "weights": {}
}
```

Do not reuse one generic policy with renamed fields.

Explain why each industry differs.

------

# **Part XI — Channel and multiplier scoring**

Create a separate model for Tier 1 and Tier 3 channel opportunities.

Assess:

- number of relevant clients or members;
- client concentration;
- frequency of client contact;
- level of borrowed trust;
- influence over purchasing decisions;
- evidence of referral behaviour;
- partnership culture;
- service complementarity;
- competitive conflict;
- white-label suitability;
- sales-cycle length;
- implementation burden;
- fan-out;
- geographic reach;
- centralised purchasing;
- newsletter or event access;
- member engagement;
- decision-maker accessibility.

Provide pseudocode and JSON for:

- accountant referral partner;
- marketing-agency partner;
- managed-service-provider partner;
- franchisor;
- professional association;
- BNI chapter;
- chamber of commerce.

Keep channel suitability separate from service-provider quality.

------

# **Part XII — Ranking and scoring**

Answer directly:

- Should the LLM assign numerical scores?
- Which scores should be deterministic?
- What should be a hard exclusion?
- How should missing evidence affect ranking?
- How should source confidence affect scores?
- How should a recent licence issue affect ranking?
- How should reviews be decayed by age?
- How should review volume be normalised?
- How should popularity bias be controlled?
- How should local proximity be treated?
- When should specialist fit outweigh popularity?
- When should the system refuse to name a winner?
- What margin should justify a single recommendation?
- How should ties and near-ties be shown?

Do not invent fake scientific precision.

Where precise values lack evidence, propose configurable policy values and explain that they require empirical validation.

------

# **Part XIII — Reviews**

Design a review model that distinguishes:

- service experience;
- communication;
- punctuality;
- billing;
- outcome claims;
- technical competence;
- clinical results;
- legal outcomes;
- suspicious review patterns;
- owner responses;
- review recency;
- platform reliability;
- practitioner-specific reviews;
- branch-specific reviews.

Explain which review inferences are legitimate and which are not.

------

# **Part XIV — Price and quote-reasonableness questions**

Design how VIDET handles:

- published prices;
- indicative ranges;
- fixed fees;
- hourly rates;
- project fees;
- retainers;
- percentage fees;
- commissions;
- cost per square metre;
- treatment packages;
- inclusions and exclusions;
- taxes;
- disbursements;
- material quality;
- geographic differences;
- urgency premiums.

A price comparison must normalise equivalent scope.

Show a price-normalisation schema and pseudocode.

Explain what to do when prices are not publicly available.

------

# **Part XV — Problem-first and hire-or-not questions**

Design a diagnostic routing layer.

Examples:

- overdue BAS;
- cyber incident;
- missing crown;
- construction defect;
- unpaid commercial debt;
- business partner dispute;
- recurring headaches;
- dog ate chocolate;
- rejected loan;
- website traffic without enquiries.

The system must:

1. identify the probable service category;
2. detect urgency or safety concerns;
3. avoid pretending to diagnose beyond available evidence;
4. determine whether self-help is appropriate;
5. identify when multiple professionals are required;
6. recommend the correct order of engagement.

Explain how your own model currently handles comparable routing, if known, and where VIDET needs stronger deterministic safeguards.

------

# **Part XVI — Follow-up chains and shortlist collapse**

Design handling for:

- Which would you choose?
- Which is best for a tradie?
- Which is best for a family with young children?
- Why those three?
- Which is safest?
- Which is best value?
- Any I should avoid?
- Give me their contact details.

The system must distinguish:

- genuine persona-specific reranking;
- conversational anchoring;
- first-position bias;
- unsupported rationalisation;
- additional retrieval;
- unchanged evidence with changed weights.

Store every follow-up decision as a new decision record linked to the original evidence snapshot.

------

# **Part XVII — Controls**

The protocol includes two required controls.

## **Wrong-service control**

Ask for a service the assessed business does not offer.

Purpose:

- detect indiscriminate brand insertion;
- detect entity over-association;
- measure false-positive recommendation behaviour.

## **Wrong-area control**

Ask for the exact service in an area the business does not serve.

Purpose:

- distinguish genuine geographic association from broad pattern matching;
- measure unsupported local presence;
- test service-area understanding.

Design:

- control generation;
- expected behaviour;
- scoring;
- false-positive thresholds;
- interpretation.

------

# **Part XVIII — Measurement of external AI assistants**

Design the experiment used to evaluate existing assistants.

Each selected question should be run:

- at least three times per assistant;
- in fresh sessions;
- across at least two days;
- with one follow-up chain per session.

Critique whether three runs are enough.

Measure:

- mention frequency;
- recommendation position;
- first-place frequency;
- citation frequency;
- citation authority;
- factual correctness;
- contact-detail correctness;
- category fit;
- location fit;
- source consistency;
- shortlist overlap;
- shortlist-collapse winner;
- refusal or abstention;
- wrong-service false positives;
- wrong-area false positives;
- run-to-run agreement;
- model-to-model agreement.

Account for:

- model version;
- product surface;
- web-enabled status;
- user location;
- personalisation;
- session history;
- date and time;
- search freshness.

Provide formulas and data schemas.

------

# **Part XIX — Prompts**

Provide production-quality prompts for:

1. Request classification
2. Problem-first category routing
3. Industry classification
4. Query-policy selection
5. Search-plan generation
6. Evidence extraction
7. Review-theme extraction
8. Entity matching
9. Evidence normalisation
10. Contradiction detection
11. Registration interpretation
12. Case-study verification
13. Price normalisation
14. Red-flag classification
15. Recommendation explanation
16. Shortlist comparison
17. Follow-up reranking explanation
18. Abstention
19. External-assistant response evaluation
20. Remediation recommendation generation

Use constrained JSON outputs where useful.

Explain what JSON can and cannot make deterministic.

------

# **Part XX — Source catalogue and URL system**

Design a source registry for Australia, the United States, the United Kingdom and Canada.

Each source definition should contain:

```json
{
  "source_id": "string",
  "country": "AU | US | UK | CA | GLOBAL",
  "jurisdiction": null,
  "industry": [],
  "source_category": "string",
  "source_name": "string",
  "base_url": "string",
  "query_template": "string or null",
  "access_method": "GET | POST_UI | API | LOGIN | PAID",
  "authoritative_for": [],
  "not_authoritative_for": [],
  "automation_status": "permitted | restricted | prohibited | unknown",
  "requires_api_key": false,
  "last_verified_at": "ISO-8601",
  "parser_version": "string",
  "fallback_search_template": "string or null"
}
```

Do not invent GET parameters for session-driven or POST-only registers.

Explain:

- URL health checks;
- parser monitoring;
- terms-of-service compliance;
- robots restrictions;
- rate limiting;
- source retirement;
- manual revalidation.

------

# **Part XXI — Reproducibility and audit**

Every recommendation should be replayable using:

- raw user question;
- structured request;
- model and prompt versions;
- search queries;
- retrieved source identifiers;
- source snapshots;
- extraction results;
- industry-policy version;
- query-policy version;
- feature values;
- scoring version;
- exclusions;
- ranking;
- explanation;
- validation outcome.

Explain what cannot be perfectly reproduced because of:

- live search changes;
- model nondeterminism;
- unavailable pages;
- map changes;
- review changes;
- external API behaviour.

------

# **Part XXII — Safety, legal and ethical risk**

Address:

- medical urgency;
- legal information versus legal advice;
- financial advice;
- defamatory implications;
- allegations versus findings;
- negative-review republication;
- outdated disciplinary records;
- identity confusion;
- fabricated credentials;
- price misrepresentation;
- sponsored placement;
- undisclosed commercial incentives;
- discrimination through protected-attribute filtering;
- privacy;
- geolocation;
- practitioner safety;
- right of correction;
- business appeals.

Design a correction and dispute process.

------

# **Part XXIII — Commercial implementation**

Propose:

- databases;
- search indexes;
- vector search where genuinely useful;
- relational schemas;
- queues;
- browser or retrieval workers;
- API services;
- caching;
- deduplication;
- observability;
- testing;
- security;
- human-review workflows;
- costs;
- staged rollout.

Separate:

### **Minimum viable product**

A small set of industries and jurisdictions.

### **Production system**

Broad industry and country support.

### **Unnecessary over-engineering**

Features that should not be built initially.

Recommend the first five industries and explain why.

------

# **Part XXIV — Critique your own design**

Spend at least 25% of the response attacking the proposed architecture.

Identify:

- assumptions that may be false;
- components that will be too expensive;
- data sources that will be inaccessible;
- legal risks;
- unreliable evidence;
- scoring that creates fake objectivity;
- industries where recommendation cannot be responsibly automated;
- places where human review remains necessary;
- parts better performed by external search providers;
- parts that should not be built;
- commercial risks;
- reasons VIDET may fail.

For each criticism, state whether it requires:

- redesign;
- limitation disclosure;
- empirical testing;
- human review;
- abandonment.

------

# **Required response format**

Use this order:

1. Reality check: what your own model or product genuinely does
2. What VIDET is and is not
3. Architecture overview
4. Universal pipeline
5. Query policies
6. Industry policies
7. Candidate discovery
8. Evidence and provenance
9. Entity resolution
10. Scoring and ranking
11. Price handling
12. Problem-first routing
13. Channel-partner model
14. External-assistant measurement
15. Controls and follow-ups
16. JSON schemas
17. Pseudocode
18. Prompts
19. Source-registry design
20. Audit and replay
21. Safety and legal risks
22. Implementation roadmap
23. Cost and complexity
24. Critique
25. Brutally honest conclusion

------

# **Final standard**

Do not optimise for elegance at the expense of truth.

Do not produce a clean fantasy architecture that depends on data, APIs, certainty or internal model access that does not exist.

Prefer, in this order:

```text
1. Real exposed capability
2. Documented product behaviour
3. Observable behaviour
4. Existing official data or API
5. Proven engineering method
6. Clearly labelled inference
7. Clearly labelled proposed design
```

When reality is incomplete or inconvenient, expose the limitation instead of designing around it rhetorically.

The correct answer may include:

- this cannot be known;
- this cannot be reliably automated;
- this source cannot be lawfully scraped;
- this ranking cannot be objectively justified;
- a shortlist is more defensible than a winner;
- human verification is required;
- the evidence is insufficient;
- the feature should not be built.

The goal is not to make VIDET appear sophisticated.

The goal is to design the most truthful, defensible and commercially useful system that can actually be built.

This structure makes **design the primary task**, but forces the model to begin with its real capabilities and reuse them where appropriate. It also prevents a common failure: describing a speculative ideal system and quietly presenting it as though that were how the model itself already works.