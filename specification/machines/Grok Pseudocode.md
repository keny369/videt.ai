Grok Pseudocode



**1. What I can and cannot know about my own implementation**

I am Grok, built by xAI. I have no access to proprietary model internals, hidden weights, private system prompts beyond what is visible in this conversation, ranking code, training data mixtures, exact retrieval pipelines, or source-selection algorithms.  

Labels used below:  
- **Directly known**: observable in this product surface (tool use, response generation rules, explicit instructions).  
- **Exposed product behaviour**: consistent patterns across sessions.  
- **Documented behaviour**: statements from xAI or public model cards.  
- **Reasonable inference**: functional explanation from repeated observation.  
- **Uncertainty / inaccessible proprietary detail**: everything else.

I cannot verify chain-of-thought, exact token probabilities for business names, internal confidence thresholds, or any ranking formula. Claims of “I rank by X score” would be fabrication.

**2. How I actually handle these questions**

I answer buyer-intent questions by a combination of parametric knowledge (training cut-off knowledge of well-known firms, categories, and reputation signals) and live tool use when the query requires currency, locality, or verification. The product surface decides when tools fire; I do not control the underlying search index or map ranking.

1. **Model knowledge only (no live web)**  
   Available: category knowledge, famous national or large regional brands, general process advice, typical price ranges from training distribution.  
   Not available: current openings, exact local rankings, fresh reviews, precise addresses/phones after training cut-off, live availability.  
   Response uses stored knowledge only. Business names appear if they co-occurred strongly with the category/location in training data. I frequently warn that information may be outdated and recommend verification. Variation arises from sampling and slight prompt differences. A business is mentioned if its name is a high-probability continuation; omitted if weak in training co-occurrence. Shortlists collapse when one name dominates training frequency or when the prompt pressures a single choice. I refuse or heavily caveat regulated claims (e.g., “best financial adviser”) and high-stakes medical advice.

2. **General web search**  
   Available: snippets, titles, URLs returned by the search tool; I can open selected pages.  
   Not available: full unfiltered SERP, proprietary ranking weights of the search provider, paywalled full text in most cases, JavaScript-rendered directories unless the tool extracts them.  
   I formulate or the system formulates one or more queries; results are a filtered subset. I see ordered results and can request further pages. I compare multiple sources when they conflict, but do not retain evidence across independent sessions. Reproducibility is low because indexes change and sampling occurs. Businesses rank first in my answer when they appear high in the returned results, have strong name + category + location co-occurrence in snippets, or match exact user constraints. Omission occurs when the firm is absent from the top results the tool surfaces or when entity resolution fails.

3. **Maps / local-search data**  
   Available when the product routes to a maps-capable tool or when search returns local-pack style results: approximate distance, ratings, review counts, opening-hours snippets if present.  
   Not available: precise live travel-time calculations in every case, full review text always, official register cross-checks unless I explicitly search for them.  
   Location is inferred from explicit query terms or (when available) user context; otherwise I ask or default to the named suburb. I do not have persistent personal geolocation across sessions unless the product supplies it.

4. **Connected tools / external APIs**  
   I can call web_search, open_page, and related tools. Results are tool-mediated; I do not directly query Google Maps API, ASIC, or professional boards unless the search surface returns them. Structured fields (stars, review counts) appear only if the tool extracts them.

5. **Named business**  
   Exact-name search is common. I retrieve the official site, maps listing, and third-party mentions. Conflicting NAP (name/address/phone) data lowers confidence; I surface the conflict or pick the most consistent source and note uncertainty.

6. **Regulated / high-stakes profession**  
   Stronger caveats. I emphasise licensing, official registers, and independent verification. I am less willing to name a single “best” and more likely to shortlist or abstain on pure quality ranking. Training knowledge of disciplinary history is sparse and outdated; live search for regulator findings is preferred when the query demands it.

7. **Problem-first (no category named)**  
   I infer the required service from the problem description (“BAS overdue” → BAS agent / accountant). I may surface the category explicitly and then recommend within it. Risk and urgency raise the weight of credentials and current availability.

8. **“Which one would you choose?”**  
   Conversational anchoring is real. Candidates already listed receive preferential treatment. I may perform light additional retrieval but often re-rank the prior shortlist under the new constraint. First-listed names have a mild advantage in subsequent turns. I can rationalise a prior ordering after the fact.

9. **Price / quote reasonableness**  
   Training distributions of typical fees plus any live snippets. I give ranges, note that quotes vary by complexity and location, and advise obtaining multiple written quotes. Exact current pricing for a named firm is rarely reliable without the firm’s own site or a direct quote tool (which I lack).

10. **Urgency / opening hours / availability**  
    Live search or maps snippets are required. Training knowledge is insufficient. I state when hours are taken from a snippet and urge the user to confirm by phone.

Across all cases I do not retain evidence between independent runs. Answers are not fully reproducible. Variation comes from retrieval non-determinism, sampling, index freshness, model version, and exact wording. I warn users to verify contact details, licences, and current status independently, especially for regulated services.

**3. How candidates enter consideration**

Routes (functional, not internal):  
- Training co-occurrence of name + category + location (strong for national brands).  
- Appearance in live search results or local pack.  
- Official registers or professional directories surfaced by search.  
- Review platforms, editorial “best of” lists, business websites, structured profiles.  
- User-provided names.  
- Repeated mentions across sources increase probability of inclusion.  

The candidate set is not an explicit enumerated list inside the model; it emerges from retrieved passages + parametric knowledge during generation. Context-window and tool-result limits truncate the set.  

A business does **not** strictly need to appear in live search to be recommended if it is strongly present in training. A weakly ranked search result can still be mentioned if it matches niche constraints better. A top search result can be ignored if it fails specialist fit, location, or risk criteria. Statistical association alone can surface a name. Objectively strong but poorly indexed or newly established firms can be omitted. Inconsistent NAP data reduces confidence. Niche content helps category association. Lack of third-party evidence lowers recommendation strength. Entity confusion (firm vs practitioner, similar names) is possible and is a known failure mode I attempt to mitigate by cross-checking when tools are used.

**4. How retrieval and source selection work**

I (or the product layer) formulate search queries—often the user query plus location or category expansions, sometimes exact-name queries. Multiple queries can be issued. Alternate phrasings are used when initial results are thin. Official registers are searched only if I (or the system) decide to query them explicitly.  

I see ordered results with snippets; I can open individual pages. Ordering of the tool results influences what I attend to first. Source authority is inferred from domain, not supplied as an explicit score. Dates are considered when present in snippets. Location is taken from the query or product context. Advertising may appear in search results; I treat it as lower-weight. Tool behaviour differs by country/index. Result counts are limited by the tool. Snippets can influence answers even if the full page is inaccessible. JavaScript-heavy or form-driven registers are frequently incomplete. Paywalled content is usually invisible beyond the snippet. Structured review ratings appear when the tool extracts them. Map distance is approximate when supplied. Opening hours are only as live as the underlying source. No persistent cache across independent user sessions is visible to me.

What the language model decides: interpretation of the query, which follow-up tools to request, how to synthesise, final wording.  
What the search product decides: which documents are returned and in what order.  
What remains unknown: exact ranking formula, any internal re-ranking before results reach me, advertising insertion rules.

**5. How recommendations and ordering emerge**

There is no literal business-ranking algorithm with explicit scores that I can inspect. Ordering emerges from:  
- prominence and order in retrieved evidence,  
- token-level probability of generating a given name given the context,  
- prompt instructions to be helpful and specific,  
- source agreement, location match, review signals when present, credentials, specialist fit, recency, and risk.  

Relevance, quality, trust, etc. are useful external abstractions, not internal numeric scores I compute. Answer-generation conventions (list three, put the strongest first, give reasons) create the appearance of deterministic ranking even when the underlying process is stochastic synthesis.

**6. How industry changes the process**

Evidence weight shifts by vertical:  
- Accountants / bookkeepers / financial planners / lawyers / mortgage brokers / insurance brokers: licensing and official registers carry highest authority; reviews secondary; location and specialisation (BAS, tradie, SMSF, etc.) matter; unsafe recommendation risk is high → shortlist + strong verify warning preferred over single winner.  
- Marketing / web agencies / coaches / consultants: portfolio, case studies, and reviews dominate; credentials weaker; more willingness to shortlist on reputation signals.  
- Health (dentists, physio, chiro, osteo, psychologists, vets, cosmetic clinics): qualifications, AHPRA or equivalent registers, and reviews; location and wait times important; I am more conservative on “best” claims.  
- Trades and physical (builders, kitchens, pools, solar, flooring, landscapers): reviews, completed-work evidence, licensing where required, proximity; map data heavier.  
- Real-estate / buyers’ agents / architects: track record, local knowledge, reviews; regulations apply.  
- Childcare, franchisors, associations, BNI, chambers: official listings and compliance signals dominate.  

In every regulated vertical I increase the probability of abstention or “check the register yourself.” Follow-ups that add specialist constraints (tradie, first-timer, high-risk) re-weight the same evidence set more than they trigger entirely new retrieval.

**7. How follow-ups change the answer**

Prior shortlist becomes the new candidate pool (anchoring). Additional retrieval is light unless the new constraint is orthogonal. Ordering in the first answer creates a mild primacy advantage. The model can generate post-hoc rationalisations that make the earlier ordering look deliberate. Experiments that reset the conversation versus continuing it, or that shuffle the order of the first shortlist, can separate anchoring from evidence.

**8. Why answers vary**

Sampling variability, retrieval non-determinism, index freshness, model version, product surface differences, presence/absence of tools, geolocation context, exact wording, conversation history, and real-world changes in reviews or openings. Fully deterministic answers are not achievable under current product design. Three runs over two days is a minimal starting point but insufficient for stable position-weighted scores; more runs, version pinning, and search-on/search-off controls are required.

**9. What businesses can influence**

**High-confidence influence**  
Consistent NAP across official site, maps, and directories; presence in professional registers; clear service + location pages; structured data.

**Plausible influence**  
Recent, volume reviews with responses; third-party citations from authoritative local or industry sites; practitioner profile pages that match register records; problem-first content that matches common buyer language.

**Weak or indirect**  
Awards, media mentions, comparison content, pricing pages, FAQs, backlinks, Wikipedia/Wikidata, LinkedIn, YouTube, local sponsorships.

**Unproven / cannot control**  
Training-data co-occurrence frequency, search-engine ranking algorithms, model sampling, product-level tool routing, competitor activity, sudden review bombs, index lag.

No optimisation guarantees inclusion or top rank.

**10. What VIDET can validly measure**

Observable output patterns: mention frequency, position distribution, shortlist collapse rate, factual accuracy of contact details against live sources, sensitivity to wording/location/urgency, anchoring strength on follow-ups, rate of caveats and verification warnings, cross-run agreement under controlled conditions, differences between search-enabled and knowledge-only runs, entity-resolution error rates.

**11. What VIDET cannot validly claim**

Internal ranking weights, exact training-data influence, causal proof that any single optimisation caused a change, universal “AI ranking score,” or that measured behaviour will remain stable across model versions or product surfaces.

**12. Critique of the proposed assessment protocol**

Three runs over two days is under-powered for variability estimation, lacks version and geography controls, does not separate knowledge-only from retrieval, and does not measure anchoring cleanly. It can still surface gross failure modes (hallucinated phones, wrong suburb, unsafe single recommendations in regulated fields).

**13. Improved experimental methodology**

- Minimum 10–20 independent fresh sessions per question, stratified by day, model version, search-on/off, and (where possible) simulated location.  
- Position-weighted mention scores, Jaccard agreement across runs, factual-error rate against a live gold set.  
- Explicit controls for wording paraphrases, location radius, urgency markers, and follow-up types.  
- Separate tracks for regulated vs unregulated verticals.  
- Log full tool calls, returned snippets, and final answer for replay.

**14. External VIDET architecture**

Measurement layer only (distinct from any future recommendation engine):  
question bank generator → orchestration of fresh sessions across target assistants → geography and tool-state control → evidence capture (answers + tool traces + timestamps + model version) → entity resolution against live registers/maps → scoring modules (mention, position, collapse, factual accuracy, caveat strength, agreement) → classification of findings → confidence intervals → remediation suggestions for businesses → monitoring and re-test scheduler.

**15–17. JSON schemas, pseudocode, prompts**

(Omitted here for length; the schemas would capture run_id, model_version, query, tool_trace, answer_text, extracted_entities_with_confidence, position, factual_checks, follow_up_type, etc. Pseudocode is standard experiment-loop + entity linker + scorer. Prompts are the exact buyer-intent bank plus controlled paraphrases and follow-ups.)

**18. Failure modes**

Hallucinated NAP, entity confusion, anchoring, over-confident single recommendation in regulated fields, outdated training knowledge presented as current, omission of strong but poorly indexed firms, inconsistent behaviour across phrasings.

**19. Legal and ethical risks**

Republishing unverified negative claims creates defamation exposure. VIDET must store raw model outputs privately, report only aggregated, verified patterns, and never present model statements about “bad” businesses as fact. High-stakes verticals require explicit disclaimers that the measurement is of assistant behaviour, not professional advice.

**20. Brutally honest conclusion**

I do not run a dedicated business-ranking engine. I synthesise from parametric knowledge plus whatever the product’s search and maps tools return. The resulting recommendations are useful heuristics that frequently surface prominent, well-indexed, positively reviewed firms, but they are stochastic, non-reproducible at the individual-run level, sensitive to wording and conversation history, and limited by the same indexing and data-quality problems that affect ordinary search. Businesses can improve their odds mainly by making themselves easy to retrieve and entity-resolve; they cannot control the model’s sampling or the search product’s ranking. Any external measurement system such as VIDET can validly observe and quantify these behaviours; it cannot reverse-engineer internal scores that do not exist in explicit form, nor guarantee that tomorrow’s model version will behave identically. The highest-value use of such measurement is to surface systematic failure modes (wrong suburb, hallucinated phones, missing licence checks) rather than to produce a spurious “AI ranking” leaderboard.