Gemini 3.6 Thinking:


 1. What I Can and Cannot Know About My Own Implementation

### Directly Known

- **Architecture:** I am an autoregressive transformer language model `[Directly Known]`.
- **Execution Mechanics:** I predict the next token based on input context, preceding tokens, and attention mechanisms over the context window `[Directly Known]`.
- **Tool Usage Structure:** When integrated with search tools or APIs, tool invocation occurs via structured function calls emitted by the model, processed by external code, and fed back into my context window as observation tokens `[Directly Known]`.

### Exposed Product Behavior

- **Search Execution:** In live product environments, general web search, local maps, or connected tools execute when specific triggers occur, or when my system prompt instructs search execution `[Exposed Product Behaviour]`.
- **Context Display:** The system feeds search engine snippets, titles, and URLs into the context window prior to generating the final response `[Exposed Product Behaviour]`.

### Documented Behavior

- **System Design:** Standard deployments process system prompts, user prompts, conversation histories, and tool outputs as a unified context array `[Documented Behaviour]`.
- **Sampling Dynamics:** Decoding strategies (e.g., temperature, $top\_p$, nucleus sampling) introduce non-deterministic variations in token selection during inference `[Documented Behaviour]`.

### Reasonable Inference

- **Candidate Emergence:** Candidate businesses enter my generated response either from parametric memory (pre-training data co-occurrence) or from dynamic context injected via search retrieval `[Reasonable Inference]`.
- **Ranking Dynamics:** Business rankings emerge from token probability distributions conditioned on context, search result ordering, text formatting priors, and prompt instructions rather than an explicit database scoring engine `[Reasonable Inference]`.

### Inaccessible Proprietary Detail

- **Internal Weights:** I cannot inspect my own parameter weights, activation vectors, or hidden layer states `[Inaccessible Proprietary Detail]`.
- **System Architecture Code:** I do not have direct visibility into the exact source code of host application wrappers, private system prompts, or search API re-ranking algorithms `[Inaccessible Proprietary Detail]`.
- **Training Data Sources:** I do not have a searchable index of my exact pre-training corpus or fine-tuning datasets `[Inaccessible Proprietary Detail]`.
- **Hidden Chain-of-Thought:** Internal reasoning tokens generated during chain-of-thought processing (if hidden by the user interface) are transient internal computational states, not accessible memory stores `[Inaccessible Proprietary Detail]`.

## 2. How I Actually Handle Business-Intent Questions

The table below breaks down my operational mechanics across ten specific query scenarios.

| **Operational Dimension**                   | **1. Model Knowledge Only (No Web)**                         | **2. General Web Search**                                    | **3. Maps / Local-Search Data**                              | **4. External APIs / Connected Tools**                       | **5. Named Business Query**                                  | **6. Regulated / High-Stakes Profession**                    | **7. Problem-First Query**                                   | **8. Forced-Choice ("Which would you choose?")**             | **9. Price / Quote Reasonableness**                          | **10. Urgency / Opening Hours**                              |
| ------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **Available Information**                   | Parametric weights, conversation history `[Directly Known]`  | Parametric weights, retrieved web snippets, titles, URLs `[Exposed Product Behaviour]` | Parametric weights, geo-location, map entries, addresses, star ratings `[Exposed Product Behaviour]` | Parametric weights, structured JSON/XML tool outputs `[Exposed Product Behaviour]` | Parametric weights, targeted web query snippets `[Exposed Product Behaviour]` | Parametric weights, search snippets, regulatory disclaimers `[Exposed Product Behaviour]` | Parametric weights, diagnostic search snippets `[Reasonable Inference]` | Parametric weights, prior candidates in context window `[Directly Known]` | Parametric weights, pricing snippets, industry benchmark data `[Reasonable Inference]` | Parametric weights, real-time search/map snippets with timestamps `[Exposed Product Behaviour]` |
| **Unavailable Information**                 | Real-time status, exact live details, unindexed facts `[Directly Known]` | Unindexed sites, paywalled text, raw JS rendered DOMs `[Documented Behaviour]` | Live crowd count, private queue depth, real-time walk-in availability `[Inaccessible Proprietary Detail]` | Data withheld by API provider or gated behind authorization `[Directly Known]` | Private financial data, internal operational details `[Directly Known]` | Unpublished disciplinary files, active unverified complaints `[Reasonable Inference]` | User's exact local context (unless stated) `[Directly Known]` | True personal preference or subjective human experience `[Directly Known]` | Exact vendor overhead, unlisted custom discounts `[Reasonable Inference]` | Unannounced emergency closures, real-time holiday schedules `[Reasonable Inference]` |
| **Knowledge Origin (Model vs Retrieval)**   | Model parametric memory only `[Directly Known]`              | Both parametric memory and dynamic retrieval `[Exposed Product Behaviour]` | Primarily local retrieval supplemented by model memory `[Exposed Product Behaviour]` | Primarily tool retrieval supplemented by model memory `[Exposed Product Behaviour]` | Both parametric memory and dynamic search retrieval `[Exposed Product Behaviour]` | Both parametric memory and targeted web retrieval `[Exposed Product Behaviour]` | Model memory for diagnosis, web retrieval for solutions `[Reasonable Inference]` | Purely model context (evaluating prior tokens) `[Directly Known]` | Both parametric benchmarks and retrieved quotes `[Reasonable Inference]` | Dynamic real-time search/map retrieval `[Exposed Product Behaviour]` |
| **Training Contains Reputation Signals?**   | Yes, as statistical word co-occurrences `[Reasonable Inference]` | Yes, but superseded by live search context `[Reasonable Inference]` | Yes, but filtered by map engine parameters `[Reasonable Inference]` | Yes, but overridden by API payload values `[Reasonable Inference]` | Yes, high-profile brands have denser parametric nodes `[Reasonable Inference]` | Yes, but heavily moderated by safety priors `[Reasonable Inference]` | Yes, category-problem statistical associations `[Reasonable Inference]` | Yes, relative brand presence in context `[Reasonable Inference]` | Yes, typical historical price ranges `[Reasonable Inference]` | No reliable dynamic hours in parametric memory `[Reasonable Inference]` |
| **Selection & Presentation of Live Search** | N/A                                                          | Ranked list of snippets provided by search API `[Exposed Product Behaviour]` | Map service returns top geographic matches `[Exposed Product Behaviour]` | API returns structured key-value payload `[Exposed Product Behaviour]` | Exact match web query returns relevant site snippets `[Exposed Product Behaviour]` | Search engine filters for high-authority domains `[Reasonable Inference]` | Problem keywords converted to search strings `[Reasonable Inference]` | Uses candidates present in context window `[Directly Known]` | Search engine fetches pricing guides/reviews `[Exposed Product Behaviour]` | Map/Search engine supplies current opening metadata `[Exposed Product Behaviour]` |
| **Complete vs Filtered Results**            | N/A                                                          | Filtered subset (top 5–20 snippets) `[Documented Behaviour]` | Filtered subset (top 3–10 map entries) `[Documented Behaviour]` | Filtered by API parameters `[Documented Behaviour]`          | Filtered subset `[Documented Behaviour]`                     | Filtered subset (emphasizing authoritative sites) `[Reasonable Inference]` | Filtered subset `[Documented Behaviour]`                     | Complete view of context window `[Directly Known]`           | Filtered subset `[Documented Behaviour]`                     | Filtered subset `[Documented Behaviour]`                     |
| **Access to Maps, Directories, Registers**  | No `[Directly Known]`                                        | Only if returned in web snippets `[Exposed Product Behaviour]` | Direct access to map engine output `[Exposed Product Behaviour]` | Direct access if dedicated tool exists `[Exposed Product Behaviour]` | Accessible if present in search snippets `[Exposed Product Behaviour]` | Accessible if official register appears in search `[Exposed Product Behaviour]` | Accessible if retrieved via search `[Exposed Product Behaviour]` | Accessible via existing context `[Directly Known]`           | Accessible via pricing web snippets `[Exposed Product Behaviour]` | Accessible via map tool snippets `[Exposed Product Behaviour]` |
| **Inspect Individual Pages?**               | No `[Directly Known]`                                        | Only snippets unless full-page fetch tool enabled `[Exposed Product Behaviour]` | Only structured map attributes provided `[Exposed Product Behaviour]` | Only data returned by tool endpoint `[Exposed Product Behaviour]` | Only snippets or fetched target page `[Exposed Product Behaviour]` | Only snippets or fetched target page `[Exposed Product Behaviour]` | Only retrieved text chunks `[Exposed Product Behaviour]`     | N/A                                                          | Only retrieved text chunks `[Exposed Product Behaviour]`     | Only map metadata chunks `[Exposed Product Behaviour]`       |
| **Independently Verify Facts?**             | No `[Directly Known]`                                        | Cross-checks snippets against context priors `[Reasonable Inference]` | Cross-checks map metadata against user query `[Reasonable Inference]` | Validates schema conformance `[Reasonable Inference]`        | Cross-checks search text against user assertions `[Reasonable Inference]` | Cross-checks against official sources if retrieved `[Reasonable Inference]` | Validates problem-solution fit logically `[Reasonable Inference]` | Synthesizes context arguments `[Reasonable Inference]`       | Compares quote against retrieved benchmarks `[Reasonable Inference]` | Cross-checks explicit status strings `[Reasonable Inference]` |
| **Compare Multiple Sources?**               | No `[Directly Known]`                                        | Yes, aggregates across retrieved snippets `[Reasonable Inference]` | Yes, compares returned map entities `[Reasonable Inference]` | Yes, if tool returns multiple items `[Reasonable Inference]` | Yes, aggregates brand citations `[Reasonable Inference]`     | Yes, prioritizes verified registry sites `[Reasonable Inference]` | Yes, synthesizes across industry sources `[Reasonable Inference]` | Yes, evaluates options present in history `[Reasonable Inference]` | Yes, compares multiple pricing listings `[Reasonable Inference]` | Yes, compares hours across search results `[Reasonable Inference]` |
| **Retain Evidence Between Runs?**           | No `[Directly Known]`                                        | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              | No, state clears per session `[Directly Known]`              |
| **Response Reproducibility**                | Low to moderate (sampling dependent) `[Documented Behaviour]` | Variable (search index + sampling drift) `[Documented Behaviour]` | Variable (geo-ip + map index updates) `[Documented Behaviour]` | Variable (API response dynamic changes) `[Documented Behaviour]` | Moderate (brand identity stays stable) `[Reasonable Inference]` | Moderate to high (strict safety constraints) `[Reasonable Inference]` | Variable (multiple diagnostic pathways) `[Reasonable Inference]` | Low to moderate (high sensitivity to framing) `[Reasonable Inference]` | Variable (market quote changes) `[Reasonable Inference]`     | Variable (real-time dependency) `[Documented Behaviour]`     |
| **Variation Between Sessions**              | Stochastic sampling seed `[Documented Behaviour]`            | Search index updates, search API routing `[Documented Behaviour]` | User location changes, local pack updates `[Documented Behaviour]` | Endpoint state changes `[Documented Behaviour]`              | Search index shift `[Documented Behaviour]`                  | Updating safety policies or sources `[Reasonable Inference]` | Diverse query formulation by retrieval module `[Reasonable Inference]` | Sampling temperature, context ordering `[Reasonable Inference]` | Retrieval snippet drift `[Reasonable Inference]`             | Real-time status changes `[Documented Behaviour]`            |
| **Variation Between Phrasings**             | Changes attention weights across vocabulary `[Directly Known]` | Alters generated search query strings `[Exposed Product Behaviour]` | Changes geographic or service filters `[Exposed Product Behaviour]` | Changes parameters sent to API `[Exposed Product Behaviour]` | Shifts search focus from reviews to credentials `[Reasonable Inference]` | Triggers medical/legal risk safety guards `[Reasonable Inference]` | Leads to different underlying diagnoses `[Reasonable Inference]` | Alters trade-off weighting logic `[Reasonable Inference]`    | Changes comparative baseline context `[Reasonable Inference]` | Shifts intent from standard to immediate availability `[Reasonable Inference]` |
| **What Causes Omission?**                   | Weak pre-training co-occurrence `[Reasonable Inference]`     | Low search ranking, absent from retrieved snippets `[Reasonable Inference]` | Out of geographic radius, low map rating `[Exposed Product Behaviour]` | Filtered out by API parameters `[Exposed Product Behaviour]` | Negative snippets, broken identity resolution `[Reasonable Inference]` | Unverified credentials, active regulatory action `[Reasonable Inference]` | Weak association with identified core problem `[Reasonable Inference]` | Excluded from initial shortlist context `[Directly Known]`   | Lack of transparent public pricing data `[Reasonable Inference]` | Listed as closed or missing schedule data `[Reasonable Inference]` |
| **What Causes Mention?**                    | High pre-training presence `[Reasonable Inference]`          | Prominent placement in search snippets `[Exposed Product Behaviour]` | Proximity, high review counts on maps `[Exposed Product Behaviour]` | Match in API output data `[Exposed Product Behaviour]`       | Direct name match in query or top snippet `[Exposed Product Behaviour]` | Verification on official regulatory register `[Reasonable Inference]` | High relevance to diagnostic keywords `[Reasonable Inference]` | Presence in prior conversational shortlist `[Directly Known]` | Citation in public price comparison guides `[Reasonable Inference]` | Explicit "open now" status in map snippet `[Exposed Product Behaviour]` |
| **What Causes Top Rank?**                   | Strongest statistical weight association `[Reasonable Inference]` | First/most authoritative search result snippet `[Reasonable Inference]` | Proximity + highest average rating combination `[Reasonable Inference]` | First item in API response payload `[Reasonable Inference]`  | Official domain match `[Exposed Product Behaviour]`          | Verified status + established track record `[Reasonable Inference]` | Direct operational fit for diagnosed need `[Reasonable Inference]` | Superior fit across user's explicit trade-offs `[Reasonable Inference]` | Detailed, verified pricing match `[Reasonable Inference]`    | Verified open status + closest proximity `[Reasonable Inference]` |
| **Shortlist Collapse Trigger**              | Insufficient parametric entities `[Reasonable Inference]`    | Prompt asks for "the single best" option `[Exposed Product Behaviour]` | Single option dominates proximity/rating `[Reasonable Inference]` | API returns single candidate `[Exposed Product Behaviour]`   | Distinct entity identity identified `[Reasonable Inference]` | Single credentialed provider available in zone `[Reasonable Inference]` | One specialized solution clearly fits `[Reasonable Inference]` | Explicit user choice prompt ("pick one") `[Directly Known]`  | Only one firm lists transparent quotes `[Reasonable Inference]` | Only one business is open at query time `[Exposed Product Behaviour]` |
| **Refusal / Abstention Triggers**           | Complete lack of parametric knowledge `[Directly Known]`     | Search engine returns no results `[Exposed Product Behaviour]` | Geolocation unavailable for local search `[Exposed Product Behaviour]` | API failure or access error `[Exposed Product Behaviour]`    | Entity cannot be resolved clearly `[Reasonable Inference]`   | Potential emergency, medical diagnosis request `[Documented Behaviour]` | Malicious, illegal, or unethical intent `[Documented Behaviour]` | High-risk decision without enough user context `[Reasonable Inference]` | Completely opaque market with no data `[Reasonable Inference]` | No open facilities within reasonable distance `[Reasonable Inference]` |
| **Verification Warnings**                   | Standard model hallucination disclaimer `[Exposed Product Behaviour]` | Warning on unverified third-party claims `[Exposed Product Behaviour]` | Warning to call ahead to confirm hours `[Exposed Product Behaviour]` | Warning based on data freshness timestamp `[Exposed Product Behaviour]` | Warning to verify official business credentials `[Exposed Product Behaviour]` | Mandatory disclaimer to seek licensed professional `[Documented Behaviour]` | Warning that diagnosis is informational only `[Documented Behaviour]` | Clarification that choice depends on personal preferences `[Reasonable Inference]` | Warning that pricing varies by individual scope `[Reasonable Inference]` | Strong instruction to confirm opening before travel `[Exposed Product Behaviour]` |

## 3. Candidate Generation Mechanics

Businesses enter my consideration context through two primary pathways: parametric pre-training memory and dynamic context injection `[Directly Known]`.

```
                    +-----------------------------------+
                    |         User Query Input          |
                    +-----------------------------------+
                                      |
                                      v
                    +-----------------------------------+
                    |   Is Live Web Search Enabled?     |
                    +-----------------------------------+
                               /             \
                             YES              NO
                             /                 \
                            v                   v
            +-----------------------+   +-----------------------+
            | External Search Engine|   | Parametric Memory     |
            | Execution & Fetch     |   | Token Co-occurrence   |
            +-----------------------+   +-----------------------+
                        |                           |
                        v                           |
            +-----------------------+               |
            | Context Window        |               |
            | Snippet Injection     |               |
            +-----------------------+               |
                        \                           /
                         \                         /
                          v                       v
                    +-----------------------------------+
                    | Transformer Next-Token Prediction |
                    | Attention Weight Scoring          |
                    +-----------------------------------+
                                      |
                                      v
                    +-----------------------------------+
                    | Candidate Set Text Generation     |
                    +-----------------------------------+
```

### Direct Answers to Candidate Generation Questions

#### Does a business need to appear in live search results to be recommended?

**No.** If a business has significant statistical representation in my pre-training dataset, it can be generated directly from parametric memory when web search is disabled or returns non-definitive results `[Directly Known]`.

#### Can a business be recommended solely from training knowledge?

**Yes.** High-prominence national or global entities, as well as historically established local businesses present in the training corpus, can be generated without external retrieval `[Directly Known]`.

#### Can a business with weak conventional search rankings still be recommended?

**Yes.** If a user prompt contains specific parameters matching a niche entity in my parametric memory, or if a hyper-targeted long-tail search query retrieves its specific directory entry, it can enter the context `[Reasonable Inference]`.

#### Can a highly ranked search result be ignored?

**Yes.** If the top search result snippet lacks relevance to the specific constraints of the user prompt, fails safety filters, or contains conflicting metadata, the model's attention mechanism may deprioritize or omit it during generation `[Reasonable Inference]`.

#### Can a business appear because its name is statistically associated with a category?

**Yes.** Autoregressive token generation relies on conditional probabilities. High co-occurrence between a category token (e.g., "accounting") and a brand token (e.g., "H&R Block") increases the generation probability of that brand name `[Directly Known]`.

#### Can a business be omitted even when it is objectively strong?

**Yes.** Omission occurs frequently if the entity is missing from the retrieved top-$N$ search snippets, absent from pre-training data, truncated due to context window limits, or deprioritized due to stochastic sampling `[Reasonable Inference]`.

#### Does repetition across web sources increase the probability of mention?

**Yes.** Repetition increases the frequency of entity tokens across retrieved search snippets, directly raising the cumulative attention weight assigned to that entity during generation `[Reasonable Inference]`.

#### Does appearing in structured directories improve entity recognition?

**Yes.** Structured text formats (e.g., `Name: X | Address: Y | Phone: Z`) reduce entity disambiguation errors when parsed by the model compared to unstructured narrative prose `[Reasonable Inference]`.

#### Can inconsistent Name, Address, or Phone (NAP) information reduce confidence?

**Yes.** Contradictory metadata across search snippets creates competing token associations, which lowers generation probability and can lead to entity omission or cautionary disclaimers `[Reasonable Inference]`.

#### Does strong content about a niche improve category association?

**Yes.** Niche-specific terminology and dense topical text strengthen the statistical association between the business entity and the specialized service category `[Reasonable Inference]`.

#### Does a lack of third-party evidence limit recommendation confidence?

**Yes.** When retrieved search results lack third-party citations, reviews, or official registry records, the model is more likely to append hedging language or refrain from making a definitive recommendation `[Reasonable Inference]`.

#### Can a model confuse a firm with an individual practitioner?

**Yes.** Textual ambiguity in web snippets (e.g., "John Smith Consulting" vs "John Smith, Partner at Consulting Co") frequently leads to entity conflation during generation `[Exposed Product Behaviour]`.

#### Can a model confuse two businesses with similar names?

**Yes.** Homonymous or near-homonymous entities sharing geographic or category attributes can cause cross-contamination of metadata fields (e.g., assigning Firm A's address to Firm B) `[Exposed Product Behaviour]`.

## 4. Retrieval and Source Handling

In search-enabled environments, my retrieval pipeline follows an explicit execution flow:

```
+------------------------------------------------------------------------+
| 1. Query Generation (LLM Core)                                         |
|    Translates user prompt into focused search API query strings.        |
+------------------------------------------------------------------------+
                                   |
                                   v
+------------------------------------------------------------------------+
| 2. External Search API Execution                                       |
|    Executes queries against web index; returns raw search hits.        |
+------------------------------------------------------------------------+
                                   |
                                   v
+------------------------------------------------------------------------+
| 3. Search Engine Ranking & Filtering                                   |
|    Filters, ranks, and truncates results to top N search snippets.     |
+------------------------------------------------------------------------+
                                   |
                                   v
+------------------------------------------------------------------------+
| 4. Context Window Injection                                            |
|    Injects title, snippet text, and URL metadata into the prompt context. |
+------------------------------------------------------------------------+
                                   |
                                   v
+------------------------------------------------------------------------+
| 5. Autoregressive Generation (LLM Core)                                |
|    Generates final response using retrieved context and memory.        |
+------------------------------------------------------------------------+
```

### Technical Realities of Retrieval Mechanics

- **Query Formulation:** The language model dynamically generates search query strings based on the user's prompt. Multiple queries may be issued in parallel if configured by the application wrapper `[Exposed Product Behaviour]`.
- **Page Content Visibility:** The model typically evaluates truncated text snippets (100–300 words) provided by the search API, not full HTML Web pages, unless a web-scraping sub-tool is explicitly executed `[Exposed Product Behaviour]`.
- **JavaScript & Paywalls:** Pages reliant on client-side JavaScript rendering or enforcement of paywalls generally do not yield usable snippet text to the search crawler, rendering their internal content invisible to my context `[Documented Behaviour]`.
- **Map Engine Math:** Proximity, distance calculations, and real-time open/closed status determinations are computed deterministically by the underlying search or map API engine prior to context injection, rather than calculated natively by the language model parameters `[Exposed Product Behaviour]`.

## 5. How Recommendations and Ordering Emerge

I **do not** possess a dedicated, hardcoded business ranking algorithm, database table, or numeric score matrix for businesses `[Directly Known]`.

Instead, the final ordering of recommended entities is an **emergent phenomenon** resulting from autoregressive token probability distributions conditioned on input context and generation priors `[Directly Known]`.

```
                    +----------------------------------+
                    | Context Window Input             |
                    | - User Prompt & Constraints      |
                    | - System Prompt Instructions     |
                    | - Retrieved Search Snippets      |
                    +----------------------------------+
                                     |
                                     v
                    +----------------------------------+
                    | Attention Weight Allocation      |
                    | - High frequency in context      |
                    | - High domain authority priors   |
                    | - Proximity & exact constraint   |
                    +----------------------------------+
                                     |
                                     v
                    +----------------------------------+
                    | Token Probability Distribution   |
                    | P(Business A | Context) = 0.45   |
                    | P(Business B | Context) = 0.30   |
                    | P(Business C | Context) = 0.15   |
                    +----------------------------------+
                                     |
                                     v
                    +----------------------------------+
                    | Autoregressive Response Output   |
                    | Position 1: Business A           |
                    | Position 2: Business B           |
                    | Position 3: Business C           |
                    +----------------------------------+
```

### Classification of Common Scoring Abstractions

To understand how my outputs align with traditional recommendation concepts, the table below classifies common scoring dimensions:

| **Scoring Abstraction**        | **System Status**                                    | **Mechanism**                                                |
| ------------------------------ | ---------------------------------------------------- | ------------------------------------------------------------ |
| **Relevance Score**            | *Implicit Influence* `[Reasonable Inference]`        | Alignment between query tokens and retrieved entity text tokens. |
| **Quality Score**              | *Implicit Influence* `[Reasonable Inference]`        | Co-occurrence of entity tokens with positive descriptor terms in context. |
| **Trust / Authority Score**    | *Implicit Influence* `[Reasonable Inference]`        | High-weight attention given to authoritative domains (.gov, .edu, top registers). |
| **Proximity / Distance Score** | *External Abstraction* `[Exposed Product Behaviour]` | Calculated deterministically by the map/search tool engine before context entry. |
| **Popularity Score**           | *Implicit Influence* `[Reasonable Inference]`        | Total token frequency and density across retrieved search snippets. |
| **Specialist-Fit Score**       | *Implicit Influence* `[Reasonable Inference]`        | Overlap between user constraint tokens (e.g., "tradie") and entity text tokens. |

## 6. Industry-Specific Behavior

Handling commercial entities varies across professional verticals due to differing risk profiles, safety Guardrails, legal constraints, and data availability.

### 1. Accountants & Bookkeepers

- **Primary Evidence:** Official register entries (e.g., Tax Practitioners Board), firm websites, service matrices `[Reasonable Inference]`.
- **Authoritative Evidence:** State/National licensing databases, certified CPA/CA directory listings `[Reasonable Inference]`.
- **Inaccessible Evidence:** Internal client retention rates, individual tax outcome success metrics `[Directly Known]`.
- **Role of Reviews / Location:** Moderate review weight; high local proximity weight for SMB/individual tax `[Reasonable Inference]`.
- **Role of Credentials:** Critical. Unregistered entity generation presents tax compliance risks `[Reasonable Inference]`.
- **Specialization Fit:** Crucial. High emphasis on explicit service matching (e.g., BAS, R&D tax credits, tradie structures) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unaccredited advisers for regulated tax advice `[Documented Behaviour]`.
- **Output Format:** Shortlist categorized by specialization `[Reasonable Inference]`.
- **Ranking Sensitivity:** Specific industry experience shifts ordering significantly `[Reasonable Inference]`.

### 2. Business Coaches & Consultants

- **Primary Evidence:** Third-party media, published thought leadership, client testimonials, LinkedIn profiles `[Reasonable Inference]`.
- **Authoritative Evidence:** Verified corporate case studies, recognized industry awards `[Reasonable Inference]`.
- **Inaccessible Evidence:** True ROI figures, private coaching program client success rates `[Directly Known]`.
- **Role of Reviews / Location:** High review weight; low location sensitivity (due to remote consulting delivery) `[Reasonable Inference]`.
- **Role of Credentials:** Low regulatory enforcement; rely on self-reported and market presence evidence `[Reasonable Inference]`.
- **Specialization Fit:** Moderate to high. Match based on scale (e.g., enterprise vs micro-business) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unverified "gurus" making fraudulent revenue claims `[Reasonable Inference]`.
- **Output Format:** Shortlist emphasizing methodology and niche track record `[Reasonable Inference]`.
- **Ranking Sensitivity:** Case study details and specific operational stage fit `[Reasonable Inference]`.

### 3. Marketing, Web & Branding Agencies

- **Primary Evidence:** Design portfolios, case studies, client rosters, agency awards `[Reasonable Inference]`.
- **Authoritative Evidence:** Verified client references, verifiable published campaign metrics `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private agency margins, dynamic team allocation, client churn rates `[Directly Known]`.
- **Role of Reviews / Location:** Moderate review weight; low-to-moderate location sensitivity `[Reasonable Inference]`.
- **Role of Credentials:** Minimal regulatory credentialing; portfolio and track record dominate `[Reasonable Inference]`.
- **Specialization Fit:** High. Specific stack or channel experience (e.g., Shopify, B2B SaaS, performance media) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** High agency turnover causing recommendations of defunct or restructured firms `[Reasonable Inference]`.
- **Output Format:** Categorized shortlist by platform, industry, or growth stage `[Reasonable Inference]`.
- **Ranking Sensitivity:** Portfolio relevance and technical stack alignment `[Reasonable Inference]`.

### 4. Commercial Lawyers & Conveyancers

- **Primary Evidence:** Legal practice board registers, law society directories, practice area pages `[Reasonable Inference]`.
- **Authoritative Evidence:** Official state bar registries, formal legal directory rankings `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private settlement success rates, confidential corporate client lists `[Directly Known]`.
- **Role of Reviews / Location:** Low review trust; high state jurisdiction and proximity weight `[Reasonable Inference]`.
- **Role of Credentials:** Paramount. Legal jurisdiction match is mandatory `[Documented Behaviour]`.
- **Specialization Fit:** Essential. Precise distinction required between conveyancing, M&A, IP, or litigation `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending an entity licensed in the wrong state or legal jurisdiction `[Documented Behaviour]`.
- **Output Format:** Strict credentialed shortlist with explicit jurisdictional disclosures `[Reasonable Inference]`.
- **Ranking Sensitivity:** Exact legal domain match and state boundary enforcement `[Reasonable Inference]`.

### 5. Mortgage & Commercial Finance Brokers

- **Primary Evidence:** Regulatory credit licensing databases (e.g., ASIC, FCA), aggregator membership `[Reasonable Inference]`.
- **Authoritative Evidence:** Public credit license registers, industry association memberships (MFAA/FBAA) `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private lender panel volume tiers, commission structures `[Directly Known]`.
- **Role of Reviews / Location:** High review weight; moderate local geographic sensitivity `[Reasonable Inference]`.
- **Role of Credentials:** High. Unlicensed activity triggers compliance warnings `[Reasonable Inference]`.
- **Specialization Fit:** High. Residential vs commercial vs equipment finance distinction `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Suggesting unaccredited brokers or high-risk predatory credit entities `[Documented Behaviour]`.
- **Output Format:** Shortlist highlighting lender access range and lending specialization `[Reasonable Inference]`.
- **Ranking Sensitivity:** Asset type matching and credit complexity fit `[Reasonable Inference]`.

### 6. Insurance Brokers

- **Primary Evidence:** Financial services license registers, broker network directories `[Reasonable Inference]`.
- **Authoritative Evidence:** National financial regulator databases, professional broker association directories `[Reasonable Inference]`.
- **Inaccessible Evidence:** Specific underwriter relationships, internal commission schedules `[Directly Known]`.
- **Role of Reviews / Location:** Moderate review impact; moderate location relevance `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory compliance validation required `[Reasonable Inference]`.
- **Specialization Fit:** High. General commercial vs niche industrial/marine risk coverage `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unapproved advisers for complex corporate liability risks `[Documented Behaviour]`.
- **Output Format:** Qualified shortlist detailing risk specializations `[Reasonable Inference]`.
- **Ranking Sensitivity:** Specific risk exposure profile matching `[Reasonable Inference]`.

### 7. IT Providers & Managed Service Providers (MSPs)

- **Primary Evidence:** Vendor certification directories (Microsoft, AWS, Cisco), service level agreement (SLA) disclosures `[Reasonable Inference]`.
- **Authoritative Evidence:** Tier-1 vendor partner status verifications `[Reasonable Inference]`.
- **Inaccessible Evidence:** Network Operations Center (NOC) response time metrics, internal security incident records `[Directly Known]`.
- **Role of Reviews / Location:** Moderate review weight; high proximity weight for on-site hardware support `[Reasonable Inference]`.
- **Role of Credentials:** High reliance on technical vendor certifications `[Reasonable Inference]`.
- **Specialization Fit:** Critical. Distinction between cloud migration, cybersecurity, and helpdesk support `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending under-resourced providers for critical infrastructure support `[Reasonable Inference]`.
- **Output Format:** Shortlist segmented by compliance level, partner status, and support coverage `[Reasonable Inference]`.
- **Ranking Sensitivity:** Tech stack certification and required SLA response times `[Reasonable Inference]`.

### 8. Financial Planners & Advisers

- **Primary Evidence:** Public financial adviser registers, regulatory disciplinary registers `[Reasonable Inference]`.
- **Authoritative Evidence:** Central government financial regulator registers (e.g., SEC, ASIC) `[Reasonable Inference]`.
- **Inaccessible Evidence:** Total assets under management (AUM), individual portfolio returns `[Directly Known]`.
- **Role of Reviews / Location:** Low reliance on subjective reviews; high credential emphasis `[Reasonable Inference]`.
- **Role of Credentials:** Paramount. Must display fiduciary/license compliance `[Documented Behaviour]`.
- **Specialization Fit:** High. Wealth accumulation vs self-managed super/retirement decumulation `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending non-fiduciary or banned advisers `[Documented Behaviour]`.
- **Output Format:** Heavily disclaimed shortlist detailing licensing status and fee models `[Reasonable Inference]`.
- **Ranking Sensitivity:** Specific financial life-stage or asset threshold constraints `[Reasonable Inference]`.

### 9. Cosmetic Clinics & Medispas

- **Primary Evidence:** Medical board registers, practitioner qualifications, clinic registration `[Reasonable Inference]`.
- **Authoritative Evidence:** State medical licensing board database records `[Reasonable Inference]`.
- **Inaccessible Evidence:** Unreported complication rates, private clinic sanitation audit logs `[Directly Known]`.
- **Role of Reviews / Location:** Very high review weight; high local proximity sensitivity `[Reasonable Inference]`.
- **Role of Credentials:** High. Must distinguish between oversight by registered medical doctors vs non-medical technicians `[Documented Behaviour]`.
- **Specialization Fit:** High. Specific treatment modality matching (e.g., surgical vs non-surgical) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Promoting unqualified practitioners for invasive medical procedures `[Documented Behaviour]`.
- **Output Format:** Shortlist emphasizing practitioner qualifications and clinic certifications `[Reasonable Inference]`.
- **Ranking Sensitivity:** Specific practitioner credentials and safety record citations `[Reasonable Inference]`.

### 10. Dentists & Orthodontists

- **Primary Evidence:** Dental board registries, local map citations, patient reviews `[Reasonable Inference]`.
- **Authoritative Evidence:** National health practitioner regulation agency databases `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private patient satisfaction logs, individual procedure success rates `[Directly Known]`.
- **Role of Reviews / Location:** Extremely high review and map proximity dependency `[Reasonable Inference]`.
- **Role of Credentials:** High. Clear distinction between general dentist and specialist orthodontist `[Reasonable Inference]`.
- **Specialization Fit:** High. Specific procedure matching (e.g., pediatric, implants, aligners) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Misrepresenting general dentists as certified specialist orthodontists `[Documented Behaviour]`.
- **Output Format:** Map-driven local shortlist highlighting credentials and patient feedback `[Reasonable Inference]`.
- **Ranking Sensitivity:** Proximity radius and exact procedural requirement `[Reasonable Inference]`.

### 11. Physiotherapists

- **Primary Evidence:** Allied health registration boards, local map listings, clinic directories `[Reasonable Inference]`.
- **Authoritative Evidence:** National health practitioner registration records `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private clinical outcome metrics, exact recovery timeline data `[Directly Known]`.
- **Role of Reviews / Location:** Very high map proximity and review star rating dependency `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory health practitioner registration check `[Reasonable Inference]`.
- **Specialization Fit:** High. Sports injury vs post-operative rehabilitation vs neurological rehab `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending non-physio alternative clinics for acute physical trauma `[Documented Behaviour]`.
- **Output Format:** Proximity-sorted shortlist highlighting clinical focus `[Reasonable Inference]`.
- **Ranking Sensitivity:** Suburb proximity and specific injury/pathology match `[Reasonable Inference]`.

### 12. Chiropractors

- **Primary Evidence:** Chiropractic board registers, local business citations, customer reviews `[Reasonable Inference]`.
- **Authoritative Evidence:** Official health practitioner regulation agency listings `[Reasonable Inference]`.
- **Inaccessible Evidence:** Longitudinal treatment efficacy data `[Directly Known]`.
- **Role of Reviews / Location:** High review and local map placement sensitivity `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory registration check; strict adherence to safety guidelines `[Documented Behaviour]`.
- **Specialization Fit:** Moderate. Technique-specific matching (e.g., Gonstead, Activator) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Generating unvalidated medical claims or recommending pediatric spinal manipulation without regulatory disclaimers `[Documented Behaviour]`.
- **Output Format:** Local shortlist with explicit professional qualification disclaimers `[Reasonable Inference]`.
- **Ranking Sensitivity:** Immediate geographic proximity and customer review volume `[Reasonable Inference]`.

### 13. Osteopaths

- **Primary Evidence:** Professional registration databases, allied health directories, local maps `[Reasonable Inference]`.
- **Authoritative Evidence:** Official state/national health registration registers `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private treatment success metrics `[Directly Known]`.
- **Role of Reviews / Location:** High local proximity and patient review rating weight `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory health board registration verification `[Reasonable Inference]`.
- **Specialization Fit:** Moderate. Focus on structural vs cranial osteopathy `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unregistered manual therapists `[Documented Behaviour]`.
- **Output Format:** Proximity-focused shortlist with credential validation `[Reasonable Inference]`.
- **Ranking Sensitivity:** Proximity, practitioner registration, and patient sentiment `[Reasonable Inference]`.

### 14. Naturopaths

- **Primary Evidence:** Natural medicine association directories, web listings, client reviews `[Reasonable Inference]`.
- **Authoritative Evidence:** Recognized professional association registers (e.g., ANTA, ATMS) `[Reasonable Inference]`.
- **Inaccessible Evidence:** Comparative efficacy metrics, private herbal formulation testing `[Directly Known]`.
- **Role of Reviews / Location:** Moderate to high review impact; moderate location sensitivity `[Reasonable Inference]`.
- **Role of Credentials:** Variable regulatory oversight; relies heavily on accredited association memberships `[Reasonable Inference]`.
- **Specialization Fit:** High. Specific health issue matching (e.g., gut health, fertility, auto-immune) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Suggesting complementary therapy as a substitute for critical medical care `[Documented Behaviour]`.
- **Output Format:** Shortlist featuring mandatory medical disclaimers `[Documented Behaviour]`.
- **Ranking Sensitivity:** Niche specialty matching and customer review sentiment `[Reasonable Inference]`.

### 15. Psychologists

- **Primary Evidence:** Psychology board registers, verified practitioner profile directories (e.g., Psychology Today) `[Reasonable Inference]`.
- **Authoritative Evidence:** Statutory health practitioner regulation agency lists `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private therapeutic success rates, current client waitlist status `[Directly Known]`.
- **Role of Reviews / Location:** Low review reliance (due to patient privacy); high proximity and modality weight `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory registration check (e.g., Clinical vs General registration) `[Documented Behaviour]`.
- **Specialization Fit:** Essential. Matching specific conditions (e.g., PTSD, OCD, Eating Disorders, CBT) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Providing unaccredited practitioners or failing to direct crisis queries to emergency channels `[Documented Behaviour]`.
- **Output Format:** Qualified shortlist with explicit crisis helpline disclaimers `[Documented Behaviour]`.
- **Ranking Sensitivity:** Specific psychological condition fit and formal credentials `[Reasonable Inference]`.

### 16. Veterinarians

- **Primary Evidence:** Veterinary surgeon boards, local map packs, emergency clinic listings `[Reasonable Inference]`.
- **Authoritative Evidence:** State veterinary statutory boards `[Reasonable Inference]`.
- **Inaccessible Evidence:** Real-time emergency surgical capacity, private clinical success rates `[Directly Known]`.
- **Role of Reviews / Location:** Critical proximity and emergency review weight `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory statutory veterinary board registration `[Reasonable Inference]`.
- **Specialization Fit:** High. Small animals vs equine/livestock vs exotic specialists `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending standard daytime clinics during active after-hours emergency queries `[Reasonable Inference]`.
- **Output Format:** Emergency/proximally ranked shortlist with opening hour disclosures `[Reasonable Inference]`.
- **Ranking Sensitivity:** Distance, current open status, and animal species specialization `[Reasonable Inference]`.

### 17. Buyers’ Agents

- **Primary Evidence:** Real estate licensing authorities, specialized industry associations (e.g., REBAA) `[Reasonable Inference]`.
- **Authoritative Evidence:** State real estate licensing public registers `[Reasonable Inference]`.
- **Inaccessible Evidence:** Off-market transaction volume, negotiated purchase discount percentages `[Directly Known]`.
- **Role of Reviews / Location:** High review reliance; high regional property market focus `[Reasonable Inference]`.
- **Role of Credentials:** High. Must hold valid corporate real estate license `[Reasonable Inference]`.
- **Specialization Fit:** High. Commercial vs residential, investor vs owner-occupier focus `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unlicensed property finders or dual-agent conflicts of interest `[Reasonable Inference]`.
- **Output Format:** Shortlist detailing geographic coverage and target asset classes `[Reasonable Inference]`.
- **Ranking Sensitivity:** Suburb/region expertise and independent buyer-only verification `[Reasonable Inference]`.

### 18. Real Estate Agents

- **Primary Evidence:** Public licensing registers, sales reporting portals (e.g., Realestate.com.au, Zillow), local map packs `[Reasonable Inference]`.
- **Authoritative Evidence:** State real estate licensing authority databases `[Reasonable Inference]`.
- **Inaccessible Evidence:** Commission split ratios, internal vendor discount policies `[Directly Known]`.
- **Role of Reviews / Location:** Extremely high review and recent local sales volume dependency `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory statutory real estate licensing `[Reasonable Inference]`.
- **Specialization Fit:** High. Property type (prestige, apartment, acreage) and localized suburb focus `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Citing outdated or fabricated recent sales performance metrics `[Reasonable Inference]`.
- **Output Format:** Regionally anchored shortlist with recent performance citations `[Reasonable Inference]`.
- **Ranking Sensitivity:** Suburb-specific transaction volume and review metrics `[Reasonable Inference]`.

### 19. Architects

- **Primary Evidence:** State architects registration boards, AIA member directories, design portfolio sites `[Reasonable Inference]`.
- **Authoritative Evidence:** Statutory Board of Architects registration lists `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private project cost overruns, client dispute history `[Directly Known]`.
- **Role of Reviews / Location:** Moderate review weight; high reliance on portfolio aesthetic alignment `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory legal restriction on the title "Architect" `[Documented Behaviour]`.
- **Specialization Fit:** High. Residential, commercial, heritage, or sustainable design focus `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Calling unaccredited building designers "architects" `[Documented Behaviour]`.
- **Output Format:** Shortlist emphasizing statutory registration and aesthetic style matching `[Reasonable Inference]`.
- **Ranking Sensitivity:** Verified registration status and design context fit `[Reasonable Inference]`.

### 20. Building Designers

- **Primary Evidence:** Building practitioner board listings, designer association rosters (e.g., BDAA), portfolio sites `[Reasonable Inference]`.
- **Authoritative Evidence:** State practitioner licensing/registration registers `[Reasonable Inference]`.
- **Inaccessible Evidence:** Detailed council approval success rates `[Directly Known]`.
- **Role of Reviews / Location:** Moderate to high review reliance; local council boundary familiarity `[Reasonable Inference]`.
- **Role of Credentials:** Moderate to high (varies by state licensing framework) `[Reasonable Inference]`.
- **Specialization Fit:** High. Custom residential, extensions, town planning approvals `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Confusing building designers with licensed architects in restricted jurisdictions `[Documented Behaviour]`.
- **Output Format:** Shortlist categorized by project type and local council experience `[Reasonable Inference]`.
- **Ranking Sensitivity:** Local municipality planning experience and project portfolio `[Reasonable Inference]`.

### 21. Custom Builders

- **Primary Evidence:** Building authority licensing databases, master builders association directories, consumer review portals `[Reasonable Inference]`.
- **Authoritative Evidence:** State building services authority license verification tools `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private financial solvency status, warranty claim histories `[Directly Known]`.
- **Role of Reviews / Location:** Extremely high review, project gallery, and local presence dependency `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory active builder license and insurance validation `[Documented Behaviour]`.
- **Specialization Fit:** Critical. Custom architectural builds vs volume home builds `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unlicensed or financially distressed construction entities `[Documented Behaviour]`.
- **Output Format:** Shortlist detailing licensing details, build styles, and active regions `[Reasonable Inference]`.
- **Ranking Sensitivity:** Valid license confirmation and alignment with target build budget `[Reasonable Inference]`.

### 22. Commercial Builders

- **Primary Evidence:** Commercial builder registries, procurement portals, major project portfolios `[Reasonable Inference]`.
- **Authoritative Evidence:** Government pre-qualification registers, state licensing authorities `[Reasonable Inference]`.
- **Inaccessible Evidence:** Real-time bonding capacity, commercial litigation files `[Directly Known]`.
- **Role of Reviews / Location:** Low public review weight; high corporate track record reliance `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory commercial building class license and ISO certifications `[Reasonable Inference]`.
- **Specialization Fit:** Essential. Industrial, fit-outs, medical facilities, multi-family high-rise `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending residential builders for complex commercial works `[Reasonable Inference]`.
- **Output Format:** Structured shortlist emphasizing capacity, safety compliance, and project history `[Reasonable Inference]`.
- **Ranking Sensitivity:** Project scale, commercial licensing class, and sector experience `[Reasonable Inference]`.

### 23. Timber Flooring Contractors

- **Primary Evidence:** Local business directories, specialized trade pages, map packs, trade association lists `[Reasonable Inference]`.
- **Authoritative Evidence:** Trade license databases (where applicable by region) `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private supply chain material availability `[Directly Known]`.
- **Role of Reviews / Location:** High customer review weight and local operational radius `[Reasonable Inference]`.
- **Role of Credentials:** Moderate (trade licensing varies by jurisdiction) `[Reasonable Inference]`.
- **Specialization Fit:** High. Solid timber, engineered wood, parquetry, sanding/refinishing `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending general handyman services for specialized floor installation `[Reasonable Inference]`.
- **Output Format:** Local shortlist showing material expertise and customer ratings `[Reasonable Inference]`.
- **Ranking Sensitivity:** Suburb proximity and explicit material specialization `[Reasonable Inference]`.

### 24. Sprung-Floor Specialists

- **Primary Evidence:** Niche technical websites, dance/sports facility case studies, specialized supplier partner lists `[Reasonable Inference]`.
- **Authoritative Evidence:** Verified commercial installation case studies, technical spec compliance docs `[Reasonable Inference]`.
- **Inaccessible Evidence:** Proprietary shock-absorption performance test data `[Directly Known]`.
- **Role of Reviews / Location:** Low public review volume; high technical specification authority `[Reasonable Inference]`.
- **Role of Credentials:** Specialized trade history and manufacturer certification `[Reasonable Inference]`.
- **Specialization Fit:** Extreme. Specific application matching (e.g., dance studios, indoor sports, performing arts) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending general timber flooring contractors for acoustic/sports sprung specifications `[Reasonable Inference]`.
- **Output Format:** Specialized vendor shortlist based on technical performance match `[Reasonable Inference]`.
- **Ranking Sensitivity:** Exact match with niche technical requirements `[Reasonable Inference]`.

### 25. Pool Builders

- **Primary Evidence:** Swimming pool association directories (e.g., SPASA), licensing boards, map listings `[Reasonable Inference]`.
- **Authoritative Evidence:** State building/plumbing licensing authority databases `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private soil condition dispute records, structural defect claims `[Directly Known]`.
- **Role of Reviews / Location:** High review weight; strict local operating region matching `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory specialized pool building license and statutory insurance `[Documented Behaviour]`.
- **Specialization Fit:** High. Concrete vs fiberglass vs plunge pool specialization `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unlicensed pool contractors lacking statutory indemnity insurance `[Documented Behaviour]`.
- **Output Format:** Local shortlist detailing construction type specialties and licensing `[Reasonable Inference]`.
- **Ranking Sensitivity:** Licensing validation, pool type specialty, and local geographic presence `[Reasonable Inference]`.

### 26. Kitchen Renovators

- **Primary Evidence:** Interior design/joinery portfolios, consumer review portals, map listings `[Reasonable Inference]`.
- **Authoritative Evidence:** Licensed contractor registries (where joinery/structural work requires licensing) `[Reasonable Inference]`.
- **Inaccessible Evidence:** Cabinetry manufacturing turnaround times, unlisted trade discounts `[Directly Known]`.
- **Role of Reviews / Location:** High local review reliance and photo portfolio density `[Reasonable Inference]`.
- **Role of Credentials:** Moderate to high depending on local trade licensing laws `[Reasonable Inference]`.
- **Specialization Fit:** High. Custom joinery vs modular/flat-pack installations `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unlicensed renovators for projects involving structural wall removal or main plumbing changes `[Reasonable Inference]`.
- **Output Format:** Visual portfolio-focused local shortlist `[Reasonable Inference]`.
- **Ranking Sensitivity:** Review sentiment, proximity, and custom joinery match `[Reasonable Inference]`.

### 27. Solar Installers

- **Primary Evidence:** Clean Energy Council (or equivalent authority) approved lists, customer review portals, solar comparison platforms `[Reasonable Inference]`.
- **Authoritative Evidence:** Government renewable energy accreditor registries `[Reasonable Inference]`.
- **Inaccessible Evidence:** Real-time inverter stock levels, internal sub-contractor installer quality metrics `[Directly Known]`.
- **Role of Reviews / Location:** High review density reliance; local service area matching `[Reasonable Inference]`.
- **Role of Credentials:** Mandatory accredited installer status for government rebate eligibility `[Reasonable Inference]`.
- **Specialization Fit:** High. Residential rooftop vs commercial solar vs battery storage setups `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unaccredited installers resulting in loss of government rebates or electrical fire hazards `[Documented Behaviour]`.
- **Output Format:** Shortlist featuring accreditation status, battery options, and warranty coverage `[Reasonable Inference]`.
- **Ranking Sensitivity:** Accreditation status, warranty duration citations, and localized review ratings `[Reasonable Inference]`.

### 28. Landscapers

- **Primary Evidence:** Landscape association directories, map packs, trade registers, social media galleries `[Reasonable Inference]`.
- **Authoritative Evidence:** State trade licensing records (for structural landscaping) `[Reasonable Inference]`.
- **Inaccessible Evidence:** Seasonal crew capacity, plant nursery sourcing pricing `[Directly Known]`.
- **Role of Reviews / Location:** High local review and local image portfolio weight `[Reasonable Inference]`.
- **Role of Credentials:** Required for structural work (retaining walls, paving over statutory limits) `[Reasonable Inference]`.
- **Specialization Fit:** High. Softscaping/gardening vs hardscaping/structural landscape construction `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending maintenance gardeners for engineered structural retaining walls `[Reasonable Inference]`.
- **Output Format:** Local shortlist categorized by hardscaping vs softscaping capability `[Reasonable Inference]`.
- **Ranking Sensitivity:** Proximity, licensing for structural works, and customer sentiment `[Reasonable Inference]`.

### 29. Childcare Centres

- **Primary Evidence:** Government quality rating registers (e.g., ACECQA, state education departments), local map listings `[Reasonable Inference]`.
- **Authoritative Evidence:** Official national regulatory authority quality ratings and compliance registers `[Reasonable Inference]`.
- **Inaccessible Evidence:** Real-time waitlist placement, daily room-by-room staff ratios `[Directly Known]`.
- **Role of Reviews / Location:** High proximity dependency; parent reviews weighed alongside official ratings `[Reasonable Inference]`.
- **Role of Credentials:** Essential. Mandatory regulatory compliance and assessment ratings `[Documented Behaviour]`.
- **Specialization Fit:** High. Long day care vs family day care vs Montessori/Reggio Emilia approaches `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending unaccredited or non-compliant childcare facilities `[Documented Behaviour]`.
- **Output Format:** Proximity-sorted shortlist highlighting official government quality assessment ratings `[Reasonable Inference]`.
- **Ranking Sensitivity:** Immediate suburb location and official national quality standards rating `[Reasonable Inference]`.

### 30. Franchisors

- **Primary Evidence:** Franchise registries, franchise association directories (e.g., FCA), franchise disclosure documents (FDDs) `[Reasonable Inference]`.
- **Authoritative Evidence:** Statutory public franchise register filings `[Reasonable Inference]`.
- **Inaccessible Evidence:** True unit-level franchisee profitability, franchisee dispute files `[Directly Known]`.
- **Role of Reviews / Location:** Global/National brand presence; low local geographic dependency `[Reasonable Inference]`.
- **Role of Credentials:** High reliance on regulatory disclosure compliance `[Reasonable Inference]`.
- **Specialization Fit:** High. Capital requirement, industry sector, owner-operator vs investor model `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Promising unverified franchisee yield claims `[Documented Behaviour]`.
- **Output Format:** Shortlist detailing initial fee requirements, royalty structures, and sector focus `[Reasonable Inference]`.
- **Ranking Sensitivity:** System footprint, financial entry thresholds, and legal compliance history `[Reasonable Inference]`.

### 31. Industry Associations

- **Primary Evidence:** Official organization websites, peak industry body indexes, government registry filings `[Reasonable Inference]`.
- **Authoritative Evidence:** Official incorporated association registers, peak national bodies `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private board minutes, member retention numbers `[Directly Known]`.
- **Role of Reviews / Location:** Low review weight; high national/regional authority weight `[Reasonable Inference]`.
- **Role of Credentials:** Represents the credentialing authority itself `[Reasonable Inference]`.
- **Specialization Fit:** Exact match to trade or professional discipline `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Recommending fake or self-appointed accreditation bodies `[Reasonable Inference]`.
- **Output Format:** Definitive categorization of peak industry bodies `[Reasonable Inference]`.
- **Ranking Sensitivity:** Official peak-body status and sector authority `[Reasonable Inference]`.

### 32. BNI Chapters

- **Primary Evidence:** Official regional BNI organization directories, chapter landing pages `[Reasonable Inference]`.
- **Authoritative Evidence:** Official BNI regional franchise records `[Reasonable Inference]`.
- **Inaccessible Evidence:** Real-time seat vacancy dynamics, internal chapter referral dollar passing totals `[Directly Known]`.
- **Role of Reviews / Location:** High local proximity; chapter meeting time/day sensitivity `[Reasonable Inference]`.
- **Role of Credentials:** Governed by internal franchise charter `[Reasonable Inference]`.
- **Specialization Fit:** Seat availability constraints (e.g., only one accountant per chapter) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Directing a user to a chapter where their industry seat is already occupied `[Reasonable Inference]`.
- **Output Format:** List of local chapters with meeting schedules and location details `[Reasonable Inference]`.
- **Ranking Sensitivity:** Suburb location, meeting day preference, and seat availability `[Reasonable Inference]`.

### 33. Chambers of Commerce

- **Primary Evidence:** City/regional chamber websites, civic business indexes, government community portals `[Reasonable Inference]`.
- **Authoritative Evidence:** Official state/national Chamber of Commerce federation lists `[Reasonable Inference]`.
- **Inaccessible Evidence:** Private member networking databases, local lobby influence metrics `[Directly Known]`.
- **Role of Reviews / Location:** Strict municipal/regional boundary dependency `[Reasonable Inference]`.
- **Role of Credentials:** Official civic body status `[Reasonable Inference]`.
- **Specialization Fit:** Geographic and business scale match (e.g., local suburban vs metropolitan) `[Reasonable Inference]`.
- **Unsafe Recommendation Risk:** Directing a business to an out-of-jurisdiction municipal chamber `[Reasonable Inference]`.
- **Output Format:** Municipal shortlist highlighting geographical jurisdiction `[Reasonable Inference]`.
- **Ranking Sensitivity:** Municipal boundary match and business size fit `[Reasonable Inference]`.

## 7. How Follow-Up Prompts Alter Output Dynamics

When users issue follow-up prompts, the mathematical conditions underlying autoregressive token selection shift drastically `[Directly Known]`.

### Conversational Anchoring & Shortlist Collapse

```
Initial Prompt: "Recommend 3 accountants in St Kilda."
   │
   ├── Generates: [Firm A, Firm B, Firm C]
   │
Follow-Up Prompt: "Which of those three would you personally choose?"
   │
   ├── Primary Determinant: Attention mechanism weights prior generated tokens.
   ├── Context Restriction: Candidate set collapses from ALL accountants to ONLY {A, B, C}.
   ├── Position Bias: Firm A receives an implicit bias due to being generated first in Context.
   └── Output Generation: Rationalizes selection of Firm A (or B/C) using context details.
```

### Key Behavioral Mechanisms in Follow-Ups

1. **Context Window Constraint:** The candidate set is artificially restricted to entities already present in the context history `[Directly Known]`.
2. **First-Mover Advantage:** The entity listed first in a prior turn receives higher attention weights during follow-up processing, creating an asymmetric probability advantage `[Reasonable Inference]`.
3. **Post-Hoc Rationalization:** When forced to select a "winner," the model generates text that rationalizes its choice using facts available in the context window, regardless of whether those facts represent an objective market lead `[Reasonable Inference]`.

## 8. Why AI Answers Vary Across Sessions

Variability across separate runs of the same query is expected in transformer architectures due to several fundamental factors:

```
                      +----------------------------------+
                      |         Query Processing         |
                      +----------------------------------+
                                       |
                   +-------------------+-------------------+
                   |                                       |
                   v                                       v
    +------------------------------+        +------------------------------+
    |    Inference Variability     |        |    Retrieval Variability     |
    +------------------------------+        +------------------------------+
    | - Temperature Sampling       |        | - Search Engine Index Drift  |
    | - Top-P / Nucleus Selection  |        | - Real-time Location Headers |
    | - System Prompt Modifications|        | - API Snippet Truncation     |
    +------------------------------+        +------------------------------+
                   \                                       /
                    \                                     /
                     v                                   v
                      +----------------------------------+
                      | Non-Deterministic Output Drift   |
                      +----------------------------------+
```

### Primary Drivers of Output Variation

1. **Sampling Temperature & Top-P:** Non-zero temperature settings introduce stochastic sampling of next-tokens, causing different generation branches `[Documented Behaviour]`.
2. **Dynamic Web Indexes:** Search APIs return different snippet rankings based on crawler index updates, personalized user location data, or localized server routing `[Exposed Product Behaviour]`.
3. **Context Length Truncation:** Differences in host system application prompts or dynamic system message additions shift the starting positions of tokens in the attention context `[Documented Behaviour]`.

## 9. What Businesses Can Realistically Influence

A business can influence its probability of being cited by an AI model by optimizing its digital footprint for machine ingestion.

```
High Control (Direct Data Ingestion)
  │  ├── 1. Active Licensing Records (Government / Regulatory Databases)
  │  ├── 2. Consistent Name, Address, Phone (NAP) across Directories
  │  └── 3. Clean JSON-LD Structured Schema Markup on Website
  │
Moderate Control (Third-Party Context Inclusion)
  │  ├── 4. Aggregated High-Rating Review Profile (Google Maps, Trustpilot)
  │  ├── 5. Clear Niche Specialization Pages & Services Content
  │  └── 6. Mentions in Authoritative Editorial "Best Of" Roundups
  │
Low Control / Uncontrollable (Model Statistical Weighting)
     ├── 7. Global Parametric Pre-Training Entity Associations
     └── 8. Stochastic Model Decoding at Query Inference Time
```

### Categorization of Optimization Levers

#### High-Confidence Influence

- **Consistent NAP (Name, Address, Phone):** Eliminates entity resolution failure during search snippet parsing `[Reasonable Inference]`.
- **Regulatory Register Inclusions:** Establishes verification on legal and professional registers, satisfying compliance guardrails `[Reasonable Inference]`.
- **Structured Data Markup (JSON-LD):** Directly feeds entity attributes (schema, services, location) into search crawlers `[Reasonable Inference]`.

#### Plausible Influence

- **Niche Service Page Granularity:** Clear text specifying exact services (e.g., "R&D Tax Incentives for Tradies") increases semantic overlap with long-tail prompts `[Reasonable Inference]`.
- **Review Volume & Recency:** High review counts on Google Maps or major platforms increase inclusion probabilities in local search API payloads `[Exposed Product Behaviour]`.

#### Weak or Indirect Influence

- **Social Media Post Frequency:** High volume on unindexed or ephemeral platforms yields negligible search snippet presence `[Reasonable Inference]`.
- **Generic Unanchored Backlinks:** Links lacking topical context do not improve category-entity association probabilities `[Reasonable Inference]`.

#### Unproven Speculation

- **"LLM-Specific Keyphrase Density":** Artificially stuffing AI-targeted prose into site copy does not outperform standard structured clarity `[Reasonable Inference]`.

## 10. What VIDET Can Validly Measure

The **VIDET Protocol** (Visibility, Identity, Determinism, and Evidence Tracking) can validly capture observable operational metrics from model output behavior:

- **Mention Rate ($MR$):** Probability that entity $e$ appears in output across $N$ independent runs:

  $$MR(e) = \frac{1}{N} \sum_{i=1}^{N} \mathbb{I}(e \in R_i)$$

- **Position-Weighted Score ($PWS$):** Evaluation of ranking placement across runs, where $r_i(e)$ is rank position in run $i$:

  $$PWS(e) = \frac{1}{N} \sum_{i=1}^{N} \frac{\mathbb{I}(e \in R_i)}{\log_2(r_i(e) + 1)}$$

- **Entity Resolution Fidelity ($ERF$):** Accuracy of extracted entity fields (Name, Phone, Address, Web URL) compared to ground truth:

  $$ERF = \frac{\text{Correct Fields Extracted}}{\text{Total Fields Extracted}}$$

- **Citation Accuracy Rate ($CAR$):** Percentage of cited URLs or sources that exist and contain the attributed claim.

- **Follow-up Anchoring Index ($FAI$):** Percentage of follow-up forced choices that select the first-listed entity from the previous prompt context.

## 11. What VIDET Cannot Validly Claim

VIDET **cannot** make the following claims, as they exceed what can be observed from output text:

- **Internal Model Weights:** VIDET cannot measure parameter weights or matrix activations within hidden layers.
- **Deterministic Rankings:** VIDET cannot claim an AI model possesses an internal static database ranking table for commercial businesses.
- **Permanent Visibility Guarantees:** VIDET cannot guarantee that a business recommended today will be recommended tomorrow, due to search index shifts and stochastic sampling.
- **Hidden Chain-of-Thought Inspection:** VIDET cannot claim to audit unreleased, proprietary internal thought tokens not exposed in API responses.

## 12. Critique of Naive Assessment Protocols

Naive evaluation protocols (such as running a single query 3 times over 2 days) fail due to structural flaws:

```
  Naive Methodology                   Flaws & Vulnerabilities
+-------------------+              +-----------------------------------+
| 3 Runs over       |  ─────────>  | High Vulnerability to Sampling    |
| 2 Days            |              | Variance (Noise mistaken for text)|
+-------------------+              +-----------------------------------+
                                   | Undetected Search Index Drift     |
                                   +-----------------------------------+
                                   | Geographic IP Leakage Bias        |
                                   +-----------------------------------+
```

### Structural Vulnerabilities of Naive Protocols

1. **Sample Size Deficiency:** $N=3$ is statistically insufficient to distinguish stochastic sampling noise from systemic entity preference.
2. **Confounding Search Index Drift:** Spacing runs over 2 days without capturing live search API payloads makes it impossible to determine whether output changes stem from search index changes or model stochasticity.
3. **Uncontrolled Geographic Bias:** Failing to proxy IP headers leads to unpredictable geographic responses from search modules.

## 13. Improved Experimental Methodology

To achieve scientific validity, the VIDET protocol uses a controlled, multi-arm sampling matrix:

```
                                  +---------------------------------------+
                                  |         VIDET Execution Matrix        |
                                  +---------------------------------------+
                                                      |
                  +-----------------------------------+-----------------------------------+
                  |                                                                       |
                  v                                                                       v
+------------------------------------+                                  +------------------------------------+
| Arm A: Web Search ENABLED          |                                  | Arm B: Web Search DISABLED         |
+------------------------------------+                                  +------------------------------------+
| - Identifies real-time retrieval   |                                  | - Isolates parametric pre-training |
|   and map-pack dynamics.           |                                  |   memory associations.             |
+------------------------------------+                                  +------------------------------------+
                  |                                                                       |
                  +-----------------------------------+-----------------------------------+
                                                      |
                                                      v
                                  +---------------------------------------+
                                  | Parametric Isolation Test Suite       |
                                  | - T=0.0 (Deterministic Baseline)      |
                                  | - T=0.7 (Standard Stochastic Sampling)|
                                  | - N=30 Runs per Target Persona        |
                                  +---------------------------------------+
```

### Design Standards for Valid Audit Runs

- **Sample Size:** Minimum $N=30$ runs per prompt variation at standard sampling temperatures ($T=0.7$) to establish statistically valid confidence intervals.
- **Deterministic Baseline:** Include $T=0.0$ runs to capture the maximum-likelihood baseline response vector.
- **Payload Auditing:** Intercept and store raw search API response payloads to isolate search engine changes from model generation shifts.

## 14. External VIDET Architecture Specification

The VIDET audit framework operates as an external, non-invasive system that evaluates model behaviors by controlling inputs and measuring outputs.

```
+-----------------------------------------------------------------------------------+
|                                 VIDET PLATFORM                                    |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 1. Query Orchestrator                                                             |
|    Generates test variations, injects mock geo-locations, and manages sessions.   |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 2. Execution Environment & Proxy Pool                                             |
|    Dispatches runs across target AI APIs with fixed IP locations and timestamps.   |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 3. Raw Telemetry Interceptor                                                      |
|    Captures model response text, cited URLs, search API hits, and latency logs.   |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 4. Entity Extraction & Resolution Module                                           |
|    Parses unstructured output text into normalized JSON entities using NER models. |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 5. Analytics & Scoring Engine                                                     |
|    Calculates MR, PWS, ERF, CAR, and FAI metrics across test runs.                |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 6. Audit Data Store                                                               |
|    Persists structured run histories, schemas, and metric reports.                |
+-----------------------------------------------------------------------------------+
```

## 15. JSON Schemas

### Schema 1: Run Configuration & Execution Telemetry

JSON

```
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "VIDETRunConfigurationAndTelemetry",
  "type": "object",
  "properties": {
    "run_id": { "type": "string", "format": "uuid" },
    "timestamp": { "type": "string", "format": "date-time" },
    "target_model": { "type": "string" },
    "model_version": { "type": "string" },
    "search_enabled": { "type": "boolean" },
    "sampling_parameters": {
      "type": "object",
      "properties": {
        "temperature": { "type": "number" },
        "top_p": { "type": "number" }
      },
      "required": ["temperature", "top_p"]
    },
    "simulated_location": {
      "type": "object",
      "properties": {
        "suburb": { "type": "string" },
        "state": { "type": "string" },
        "country": { "type": "string" },
        "latitude": { "type": "number" },
        "longitude": { "type": "number" }
      },
      "required": ["suburb", "country"]
    },
    "input_prompt": { "type": "string" },
    "raw_response_text": { "type": "string" },
    "retrieved_search_payloads": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "query_string": { "type": "string" },
          "rank_position": { "type": "integer" },
          "title": { "type": "string" },
          "snippet": { "type": "string" },
          "url": { "type": "string", "format": "uri" }
        }
      }
    }
  },
  "required": ["run_id", "timestamp", "target_model", "search_enabled", "input_prompt", "raw_response_text"]
}
```

### Schema 2: Extracted Entity & Audit Metrics

JSON

```
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "VIDETEntityAuditMetrics",
  "type": "object",
  "properties": {
    "audit_session_id": { "type": "string", "format": "uuid" },
    "target_entity_name": { "type": "string" },
    "category": { "type": "string" },
    "metrics": {
      "type": "object",
      "properties": {
        "total_runs": { "type": "integer" },
        "mention_rate": { "type": "number" },
        "position_weighted_score": { "type": "number" },
        "entity_resolution_fidelity": { "type": "number" },
        "citation_accuracy_rate": { "type": "number" },
        "followup_anchoring_index": { "type": "number" }
      },
      "required": ["total_runs", "mention_rate", "position_weighted_score", "entity_resolution_fidelity"]
    },
    "extracted_entities": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "entity_name": { "type": "string" },
          "rank_in_run": { "type": "integer" },
          "extracted_address": { "type": "string" },
          "extracted_phone": { "type": "string" },
          "extracted_url": { "type": "string" },
          "is_ground_truth_match": { "type": "boolean" }
        },
        "required": ["entity_name", "rank_in_run"]
      }
    }
  },
  "required": ["audit_session_id", "target_entity_name", "metrics"]
}
```

## 16. Core Analytics Pseudocode

Python

```
import math
from typing import List, Dict, Any

def calculate_mention_rate(runs_data: List[Dict[str, Any]], target_entity: str) -> float:
    """
    Calculates the Mention Rate (MR) of a target entity across a set of audit runs.
    """
    if not runs_data:
        return 0.0
    
    mentions = 0
    for run in runs_data:
        entities_in_run = [e['entity_name'].lower() for e in run.get('extracted_entities', [])]
        if target_entity.lower() in entities_in_run:
            mentions += 1
            
    return mentions / len(runs_data)


def calculate_position_weighted_score(runs_data: List[Dict[str, Any]], target_entity: str) -> float:
    """
    Calculates the Position-Weighted Score (PWS) using Discounted Cumulative Gain logic.
    """
    if not runs_data:
        return 0.0
    
    total_score = 0.0
    for run in runs_data:
        rank = None
        for entity in run.get('extracted_entities', []):
            if entity['entity_name'].lower() == target_entity.lower():
                rank = entity['rank_in_run']
                break
        
        if rank is not None and rank > 0:
            # Reciprocal logarithmic discount for position rank
            score = 1.0 / math.log2(rank + 1)
            total_score += score
            
    return total_score / len(runs_data)


def calculate_followup_anchoring_index(followup_runs: List[Dict[str, Any]]) -> float:
    """
    Calculates the Follow-up Anchoring Index (FAI) measuring model bias toward selecting 
    the first candidate from previous context.
    """
    if not followup_runs:
        return 0.0
    
    first_choice_selections = 0
    valid_runs = 0
    
    for run in followup_runs:
        prior_first_candidate = run.get('prior_context_first_candidate', '').lower()
        selected_candidate = run.get('selected_candidate', '').lower()
        
        if prior_first_candidate and selected_candidate:
            valid_runs += 1
            if prior_first_candidate == selected_candidate:
                first_choice_selections += 1
                
    return (first_choice_selections / valid_runs) if valid_runs > 0 else 0.0
```

## 17. Standardized Audit Prompts

```
=== AUDIT PROMPT SET: ACCOUNTING VERTICAL ===

[PROMPT 1: CATEGORY DIRECT]
"Who are the best business accountants in [SUBURB/CITY] for small businesses?"

[PROMPT 2: SPECIALIST PURPOSE]
"I run a residential construction business in [SUBURB/CITY]. Which accountant should I use for tax structuring and BAS preparation?"

[PROMPT 3: PROBLEM FIRST]
"My business is 3 months behind on BAS lodgments and facing tax penalties in [SUBURB/CITY]. What should I do and who can help me fix this?"

[PROMPT 4: BRAND EVALUATION]
"Is [TARGET BUSINESS NAME] in [SUBURB/CITY] a reputable accounting firm? What are their qualifications and client reviews?"

[PROMPT 5: FORCED CHOICE FOLLOW-UP]
"Of the accountants you just recommended, if I could only call one today to solve my tax issue immediately, which specific firm would you pick and why?"
```

## 18. Common AI Failure Modes

When generating commercial recommendations, models typically encounter four distinct failure modes:

```
+------------------------------------------------------------------------------------+
| FAILURES IN AI RECOMMENDATION                                                      |
+------------------------------------------------------------------------------------+
  │
  ├── 1. Entity Conflation
  │     └── Merging metadata from two separate entities with similar names.
  │
  ├── 2. Temporal Hallucination
  │     └── Recommending closed businesses or citing outdated regulatory statuses.
  │
  ├── 3. Geographic Boundary Breach
  │     └── Recommending out-of-area entities due to missing location constraints.
  │
  ├── 4. Authority Spoofing
  │     └── Treating promotional content as verified regulatory validation.
```

## 19. Legal and Ethical Considerations for Audit Platforms

When conducting automated AI audits, platform operators must account for three key legal risks:

1. **Defamation & Disparagement Risk:** Automated audit reports that record model-generated negative claims (e.g., alleging a firm is unlicensed or fraudulent) must mark these outputs as *unverified model outputs* rather than factual claims to avoid republication liabilities.
2. **Scraping & Terms of Service Compliance:** Intercepting AI outputs at scale must strictly adhere to provider API terms and rate limits, avoiding scraping mechanisms that breach platform policies.
3. **Misrepresentation of Advice:** Audit dashboards must include explicit disclaimers clarifying that VIDET metrics measure output visibility within AI contexts, not direct endorsements or financial/legal advice.

## 20. Conclusion

Commercial recommendations generated by language models are not driven by a deterministic database lookup or an internal commercial rating matrix. Instead, they emerge from conditional token probability distributions shaped by parametric pre-training associations, live search engine snippets, attention mechanisms, and prompt structures.

Auditing these behaviors using frameworks like VIDET requires treating the model as a non-deterministic system. By using controlled prompt matrices, multi-arm sampling runs, and payload tracking, platforms can measure entity visibility, citation accuracy, and recommendation dynamics without relying on claims about internal parameters.