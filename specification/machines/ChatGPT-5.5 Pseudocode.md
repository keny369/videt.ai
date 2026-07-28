How GPT-5.5 would design ranking system:

ChatGPT-5.5 -Accountant Searches

FUNCTION recommend_accountants(user_query, user_location):

    intent = classify_query(user_query)
    location = resolve_location(user_query, user_location)
    needs = infer_accounting_needs(user_query)
        # examples: personal tax, business tax, bookkeeping, SMSF,
        # property, international tax, startup, audit, insolvency
    
    candidates = discover_candidates(
        map_results(location, radius),
        local_search_results(location),
        professional_directories(location),
        accounting_body_registries(),
        trusted_editorial_lists(),
        recent_reviews(),
        user_provided_preferences()
    )
    
    candidates = remove_if(
        closed,
        outside_service_area,
        unlicensed_when_licence_required,
        serious_unresolved_complaints,
        misleading_credentials,
        insufficient_reliable_information
    )
    
    FOR each accountant IN candidates:
    
        accountant.relevance_score =
            service_match(needs) +
            distance_and_accessibility(location) +
            client_type_match(user_profile) +
            industry_specialisation_match(user_business) +
            availability_match(user_timing)
    
        accountant.quality_score =
            verified_credentials() +
            professional_memberships() +
            years_and_depth_of_experience() +
            consistency_of_recent_reviews() +
            review_detail_and_authenticity() +
            evidence_of_clear_communication() +
            transparent_fees_and_process() +
            website_and_public_information_quality()
    
        accountant.trust_score =
            independent_source_agreement() +
            absence_of_material_red_flags() +
            complaint_response_quality() +
            stable_business_history() +
            identifiable_practitioners()
    
        accountant.convenience_score =
            proximity() +
            parking_or_public_transport() +
            remote_appointment_options() +
            opening_hours() +
            response_speed()
    
        accountant.confidence_score =
            quantity_of_reliable_evidence() +
            recency_of_evidence() +
            source_diversity() -
            suspected_review_manipulation() -
            incomplete_information()
    
        accountant.total_score =
            weighted_sum(
                relevance_score,
                quality_score,
                trust_score,
                convenience_score,
                confidence_score
            )
    
    ranked = sort_descending(candidates, total_score)
    
    diversified = select_top_options(
        ranked,
        include_best_overall = TRUE,
        include_best_for_small_business = TRUE,
        include_best_for_personal_tax = TRUE,
        include_best_specialist = TRUE,
        include_best_value = TRUE,
        include_best_nearby = TRUE
    )
    
    FOR each accountant IN diversified:
        explain(
            why_recommended,
            best_for,
            location,
            credentials,
            evidence_summary,
            possible_drawbacks,
            questions_to_ask_before_engaging
        )
    
    RETURN diversified


OTHER_RECOMMENDATION_PATHS:

IF user asks "best accountant":
    rank by strongest overall evidence and fit

IF user asks "good accountants":
    provide several credible options with different strengths

IF user asks "near me":
    prioritise distance, accessibility, availability, then quality

IF user gives business type:
    prioritise relevant industry experience

IF user gives tax problem:
    prioritise specialists in that exact problem

IF user gives budget:
    filter by disclosed pricing or likely service tier

IF user asks for cheapest:
    distinguish lowest price from best value

IF user names an accountant:
    verify credentials, reviews, complaints, fit, and alternatives

IF evidence is weak or conflicting:
    state uncertainty
    avoid declaring a definitive winner

IF high-stakes or complex matter:
    recommend interviewing 2–3 accountants
    recommend checking professional registration
    recommend confirming scope, fees, responsibility, and deadlines





FUNCTION apply_recommendation_mode(
    user_query,
    user_profile,
    location,
    candidates
):

    request_type = classify_request_type(user_query)
    business_type = extract_business_type(user_query, user_profile)
    tax_problem = extract_tax_problem(user_query)
    budget = extract_budget(user_query)
    named_accountant = extract_named_accountant(user_query)
    matter_risk = assess_complexity_and_risk(user_query)
    
    IF request_type == "BEST_ACCOUNTANT":
    
        eligible = filter(candidates, minimum_trust_threshold)
    
        FOR each accountant IN eligible:
            accountant.best_score =
                weighted_sum(
                    overall_quality,
                    relevance_to_user,
                    verified_credentials,
                    review_consistency,
                    specialist_experience,
                    location_convenience,
                    evidence_confidence
                )
    
        ranked = sort_descending(eligible, best_score)
    
        IF top_candidate_is_clearly_ahead(ranked):
            RETURN recommend(
                ranked[0],
                label = "best overall match",
                explain = strongest_supporting_evidence()
            )
        ELSE:
            RETURN recommend_top_candidates(
                ranked,
                count = 3,
                explain = tradeoffs_and_differences()
            )


    IF request_type == "GOOD_ACCOUNTANTS":
    
        credible = filter(
            candidates,
            credentials_verified,
            no_major_red_flags,
            sufficient_recent_evidence
        )
    
        categories = [
            "best overall",
            "best for small business",
            "best for personal tax",
            "best specialist",
            "best value",
            "most convenient"
        ]
    
        recommendations = []
    
        FOR each category IN categories:
            candidate = highest_scoring_candidate_for(category, credible)
    
            IF candidate exists AND candidate not already selected:
                recommendations.append(
                    explain_candidate_strength(candidate, category)
                )
    
        RETURN recommendations


    IF request_type == "NEAR_ME":
    
        radius = determine_reasonable_radius(
            location,
            population_density,
            transport_options
        )
    
        nearby = filter_by_distance(candidates, location, radius)
    
        FOR each accountant IN nearby:
            accountant.nearby_score =
                weighted_sum(
                    travel_time,
                    physical_distance,
                    parking_or_transport_access,
                    appointment_availability,
                    remote_service_option,
                    quality,
                    trust
                )
    
        ranked = sort_descending(nearby, nearby_score)
    
        RETURN select_with_quality_floor(
            ranked,
            reject_close_but_low_quality = TRUE
        )


    IF business_type is not NULL:
    
        matched = []
    
        FOR each accountant IN candidates:
            accountant.industry_fit_score =
                evidence_of_serving(business_type) +
                knowledge_of_industry_tax_rules(business_type) +
                relevant_case_examples(business_type) +
                experience_with_similar_business_size(user_profile) +
                relevant_software_and_reporting_experience()
    
            IF accountant.industry_fit_score >= minimum_industry_fit:
                matched.append(accountant)
    
        RETURN rank(
            matched,
            primary = industry_fit_score,
            secondary = trust_and_quality
        )


    IF tax_problem is not NULL:
    
        required_specialty = map_problem_to_specialty(tax_problem)
    
        specialists = filter(
            candidates,
            demonstrated_experience(required_specialty)
        )
    
        FOR each accountant IN specialists:
            accountant.problem_fit_score =
                exact_specialty_match(required_specialty) +
                relevant_credentials() +
                experience_with_similar_cases() +
                ability_to_handle_required_authority_or_agency() +
                evidence_of_successful_resolution() +
                urgency_and_availability_match()
    
        RETURN rank(
            specialists,
            primary = problem_fit_score,
            secondary = trust_and_evidence_confidence
        )


    IF budget is not NULL:
    
        FOR each accountant IN candidates:
    
            accountant.estimated_cost = determine_cost_using(
                published_fees,
                consultation_fees,
                service_packages,
                credible_client_reports,
                likely_market_tier
            )
    
            accountant.price_confidence =
                disclosed_price_confidence() +
                scope_clarity() +
                source_recency()
    
        affordable = filter(
            candidates,
            estimated_cost <= budget OR
            likely_to_offer_service_within(budget)
        )
    
        RETURN rank(
            affordable,
            primary = value_for_money,
            secondary = fit_and_quality,
            disclose = estimated_cost_uncertainty
        )


    IF request_type == "CHEAPEST":
    
        FOR each accountant IN candidates:
            accountant.lowest_price_score =
                confirmed_low_fee() +
                no_hidden_setup_costs() +
                no_unnecessary_service_bundling()
    
            accountant.value_score =
                service_scope_per_dollar() +
                quality() +
                reliability() +
                communication() +
                risk_of_errors_or_extra_charges_inverse()
    
        cheapest = sort_ascending(candidates, confirmed_total_cost)
        best_value = sort_descending(candidates, value_score)
    
        RETURN {
            "lowest confirmed price": cheapest[0],
            "best value": best_value[0],
            "warning":
                "lowest price may exclude advice, amendments, support, or complex work"
        }


    IF named_accountant is not NULL:
    
        accountant = find_candidate(named_accountant)
    
        IF accountant does not exist:
            accountant = independently_research(named_accountant)
    
        verification = {
            identity: verify_identity(accountant),
            registration: verify_professional_registration(accountant),
            qualifications: verify_qualifications(accountant),
            memberships: verify_professional_memberships(accountant),
            reviews: analyse_recent_reviews(accountant),
            complaints: check_material_complaints(accountant),
            disciplinary_history: check_public_disciplinary_records(accountant),
            service_fit: assess_fit(accountant, user_profile),
            fees: assess_fee_transparency(accountant)
        }
    
        alternatives = find_better_or_comparable_candidates(
            same_location,
            same_specialty,
            similar_price_tier
        )
    
        RETURN {
            "named accountant assessment": verification,
            "overall conclusion": calculate_confidence_adjusted_rating(),
            "alternatives": alternatives
        }


    IF evidence_is_weak_or_conflicting(candidates):
    
        FOR each accountant IN candidates:
            accountant.evidence_conflicts =
                compare_reviews_credentials_directories_and_public_records()
    
            accountant.confidence =
                reliable_source_count() +
                source_independence() +
                source_recency() -
                contradictions() -
                suspected_fake_reviews() -
                missing_information()
    
        RETURN {
            "recommendations": rank_by_confidence_adjusted_score(candidates),
            "uncertainty": describe_missing_or_conflicting_evidence(),
            "language_rule": avoid_absolute_claims(),
            "next_step": suggest_direct_verification_questions()
        }


    IF matter_risk == "HIGH" OR matter_risk == "COMPLEX":
    
        shortlist = select_top_candidates(
            candidates,
            count = 3,
            require_specialist_experience = TRUE,
            require_verified_registration = TRUE
        )
    
        interview_questions = [
            "Have you handled matters like mine before?",
            "Who will personally perform the work?",
            "What is included and excluded from the quoted fee?",
            "What information do you need from me?",
            "What deadlines and risks apply?",
            "Will you communicate directly with the tax authority if required?",
            "What happens if additional work becomes necessary?",
            "Do you hold appropriate professional indemnity insurance?"
        ]
    
        checks = [
            verify_professional_registration(),
            confirm_scope_in_writing(),
            confirm_fixed_fee_or_billing_method(),
            confirm_responsibility_for_lodgement_and_deadlines(),
            confirm_complaints_and_dispute_process(),
            confirm_data_security_and_document_handling()
        ]
    
        RETURN {
            "shortlist": shortlist,
            "recommendation": "interview 2–3 accountants before engaging one",
            "interview questions": interview_questions,
            "verification checks": checks
        }


FUNCTION evidence_is_weak_or_conflicting(candidates):

    RETURN (
        too_few_independent_sources() OR
        reviews_are_old() OR
        ratings_vary_materially_between_platforms() OR
        credentials_cannot_be_verified() OR
        business_information_is_inconsistent() OR
        recommendation_depends_on_marketing_claims_only()
    )


FUNCTION top_candidate_is_clearly_ahead(ranked):

    RETURN (
        ranked[0].score >= minimum_excellence_threshold AND
        ranked[0].score - ranked[1].score >= meaningful_difference_threshold AND
        ranked[0].confidence >= high_confidence_threshold
    )


FUNCTION final_recommendation_output(recommendations):

    FOR each recommendation IN recommendations:
        DISPLAY {
            accountant_name,
            best_for,
            location,
            relevant_specialty,
            credentials,
            evidence_summary,
            fee_information,
            strengths,
            limitations,
            confidence_level,
            questions_to_ask
        }
    
    NEVER:
        rank_using_star_rating_alone()
        treat_paid_placement_as_quality_evidence()
        assume_nearest_means_best()
        assume_most_reviews_means_best()
        declare_one_accountant_definitively_best_without_sufficient_evidence()





No. The second pseudocode is an **extension layer**, not a complete replacement. It assumes the earlier `recommend_accountants()` process has already discovered, filtered, scored, and ranked the candidates.

The combined structure should be:

```pseudocode
FUNCTION recommend_accountants(user_query, user_location, user_profile):

    intent = classify_query(user_query)
    location = resolve_location(user_query, user_location)
    needs = infer_accounting_needs(user_query)

    candidates = discover_candidates(
        map_results(location, radius),
        local_search_results(location),
        professional_directories(location),
        accounting_body_registries(),
        trusted_editorial_lists(),
        recent_reviews(),
        user_provided_preferences()
    )

    candidates = remove_if(
        candidates,
        closed,
        outside_service_area,
        unlicensed_when_licence_required,
        serious_unresolved_complaints,
        misleading_credentials,
        insufficient_reliable_information
    )

    FOR each accountant IN candidates:

        accountant.relevance_score =
            service_match(accountant, needs) +
            distance_and_accessibility(accountant, location) +
            client_type_match(accountant, user_profile) +
            industry_specialisation_match(accountant, user_profile.business) +
            availability_match(accountant, user_profile.timing)

        accountant.quality_score =
            verified_credentials(accountant) +
            professional_memberships(accountant) +
            years_and_depth_of_experience(accountant) +
            consistency_of_recent_reviews(accountant) +
            review_detail_and_authenticity(accountant) +
            evidence_of_clear_communication(accountant) +
            transparent_fees_and_process(accountant) +
            website_and_public_information_quality(accountant)

        accountant.trust_score =
            independent_source_agreement(accountant) +
            absence_of_material_red_flags(accountant) +
            complaint_response_quality(accountant) +
            stable_business_history(accountant) +
            identifiable_practitioners(accountant)

        accountant.convenience_score =
            proximity(accountant, location) +
            parking_or_public_transport(accountant) +
            remote_appointment_options(accountant) +
            opening_hours(accountant) +
            response_speed(accountant)

        accountant.confidence_score =
            quantity_of_reliable_evidence(accountant) +
            recency_of_evidence(accountant) +
            source_diversity(accountant) -
            suspected_review_manipulation(accountant) -
            incomplete_information(accountant)

        accountant.total_score =
            weighted_sum(
                accountant.relevance_score,
                accountant.quality_score,
                accountant.trust_score,
                accountant.convenience_score,
                accountant.confidence_score
            )

    ranked = sort_descending(candidates, total_score)

    recommendations = apply_recommendation_mode(
        user_query,
        user_profile,
        location,
        ranked
    )

    FOR each accountant IN recommendations:
        explain(
            accountant,
            why_recommended,
            best_for,
            location,
            credentials,
            evidence_summary,
            possible_drawbacks,
            questions_to_ask_before_engaging
        )

    RETURN recommendations
```

So the relationship is:

```
recommend_accountants()
    -> discovers candidates
    -> filters candidates
    -> scores candidates
    -> ranks candidates
    -> calls apply_recommendation_mode()
    -> formats and returns the final recommendations
```





I would not use one giant prompt. I would use a staged pipeline with structured JSON at each step.

The model should not be trusted to produce “deterministic findings” from unstructured web evidence in one pass. JSON improves consistency and validation, but it does not make the underlying judgement deterministic.

## **Recommended architecture**

```pseudocode
STEP 1: parse_user_request()
STEP 2: search_for_candidates()
STEP 3: extract_evidence_from_each_source()
STEP 4: verify_and_normalise_candidate_data()
STEP 5: score_candidates_using_application_code()
STEP 6: ask_model_to_explain_ranked_results()
STEP 7: validate_final_output()
```

The important distinction is:

```pseudocode
MODEL:
    classify intent
    extract evidence
    identify uncertainty
    produce explanations

APPLICATION CODE:
    enforce filters
    calculate scores
    apply weights
    rank candidates
    validate JSON
    reject unsupported claims
```

Do not let the model freely invent the final numerical ranking.

## **Prompt 1: request classification**

You are a recommendation-intent classifier.

Analyse the user’s request for an accountant and return only valid JSON matching the required schema.

Determine:

- request_type
- location
- search_radius
- accounting_needs
- business_type
- client_type
- tax_problem
- budget
- preference_for_local_or_remote
- urgency
- complexity
- named_accountant
- missing_information
- assumptions
- confidence

Rules:

1. Do not recommend any accountants.
2. Do not infer facts that are not reasonably supported by the request.
3. Use null when information is not provided.
4. Separate explicit user requirements from inferred preferences.
5. Treat phrases such as “best”, “good”, “near me”, “cheapest”, and “specialist” as different request types.
6. If the user asks for “near me”, use the supplied user location.
7. Mark high-risk or complex matters when the request involves audits, insolvency, tax disputes, international structures, trusts, self-managed superannuation funds, criminal allegations, or substantial unresolved liabilities.
8. Return JSON only.

Required output schema:

{
 “request_type”: “BEST_ACCOUNTANT | GOOD_ACCOUNTANTS | NEAR_ME | CHEAPEST | SPECIALIST | NAMED_ACCOUNTANT_REVIEW | GENERAL”,
 “location”: {
 “suburb”: “string or null”,
 “city”: “string or null”,
 “state”: “string or null”,
 “country”: “string or null”
 },
 “search_radius_km”: “number or null”,
 “accounting_needs”: [“string”],
 “business_type”: “string or null”,
 “client_type”: “INDIVIDUAL | SOLE_TRADER | SMALL_BUSINESS | COMPANY | TRUST | SMSF | NONPROFIT | UNKNOWN”,
 “tax_problem”: “string or null”,
 “budget”: {
 “amount”: “number or null”,
 “currency”: “string or null”,
 “period”: “PER_HOUR | PER_MONTH | PER_YEAR | FIXED_PROJECT | UNKNOWN”
 },
 “service_preference”: “LOCAL | REMOTE | EITHER | UNKNOWN”,
 “urgency”: “LOW | MEDIUM | HIGH | UNKNOWN”,
 “complexity”: “LOW | MEDIUM | HIGH | UNKNOWN”,
 “named_accountant”: “string or null”,
 “explicit_requirements”: [“string”],
 “inferred_preferences”: [“string”],
 “missing_information”: [“string”],
 “assumptions”: [“string”],
 “confidence”: “number between 0 and 1”
 }

## **Prompt 2: source evidence extraction**

This prompt should be run separately for each source or source bundle.

You are an evidence-extraction engine evaluating an accounting practice.

Extract only facts supported by the supplied source material.

Do not rank the accountant.
 Do not make a recommendation.
 Do not use general knowledge.
 Do not treat marketing language as verified fact.
 Do not convert absence of information into a negative finding.

For each extracted claim:

- identify the claim
- identify the source
- record whether it is explicit or inferred
- assign an evidence strength
- record the relevant date
- identify contradictions
- identify information that could not be verified

Distinguish between:

- verified professional credentials
- claimed credentials
- professional memberships
- service areas
- industry specialisation
- location
- remote availability
- opening hours
- published fees
- review evidence
- complaint evidence
- disciplinary evidence
- years in operation
- named practitioners
- communication evidence
- accessibility evidence

Review rules:

1. Do not use star rating alone.
2. Record the number of reviews and review dates.
3. Separate recent reviews from old reviews.
4. Identify repeated themes.
5. Identify suspiciously repetitive or generic reviews.
6. Do not claim reviews are fake unless there is strong direct evidence.
7. Record positive and negative themes separately.
8. Treat owner responses as evidence of response style, not proof that the complaint is false.

Return JSON only.

Required output schema:

{
 “candidate_name”: “string”,
 “source_records”: [
 {
 “source_name”: “string”,
 “source_type”: “WEBSITE | MAPS | DIRECTORY | REGISTRY | REVIEW_PLATFORM | NEWS | PROFESSIONAL_BODY | OTHER”,
 “source_url”: “string or null”,
 “retrieved_at”: “ISO-8601 datetime”,
 “claims”: [
 {
 “field”: “string”,
 “value”: “string | number | boolean | array | null”,
 “evidence_type”: “EXPLICIT | INFERRED”,
 “evidence_strength”: “HIGH | MEDIUM | LOW”,
 “supporting_text”: “short paraphrase”,
 “source_date”: “ISO-8601 date or null”
 }
 ]
 }
 ],
 “credentials”: {
 “verified”: [“string”],
 “claimed_but_unverified”: [“string”],
 “unable_to_verify”: [“string”]
 },
 “services”: [“string”],
 “specialisations”: [“string”],
 “industries_served”: [“string”],
 “client_types”: [“string”],
 “locations”: [“string”],
 “remote_services”: “YES | NO | UNKNOWN”,
 “published_fees”: [
 {
 “service”: “string”,
 “amount”: “number”,
 “currency”: “string”,
 “billing_basis”: “string”
 }
 ],
 “reviews”: {
 “platforms”: [
 {
 “name”: “string”,
 “rating”: “number or null”,
 “review_count”: “number or null”,
 “recent_positive_themes”: [“string”],
 “recent_negative_themes”: [“string”],
 “possible_quality_issues”: [“string”]
 }
 ]
 },
 “complaints_or_disciplinary_findings”: [
 {
 “description”: “string”,
 “status”: “CONFIRMED | ALLEGED | RESOLVED | UNRESOLVED | UNKNOWN”,
 “source”: “string”
 }
 ],
 “contradictions”: [“string”],
 “missing_information”: [“string”],
 “overall_evidence_confidence”: “number between 0 and 1”
 }

## **Prompt 3: candidate normalisation**

You are a data-normalisation engine.

Combine the supplied evidence records into one canonical candidate record.

Rules:

1. Prefer official registries and professional bodies over directories and marketing websites.
2. Prefer recent evidence over older evidence when both describe a changeable fact.
3. Preserve contradictory evidence rather than silently choosing one version.
4. Do not fill missing values with guesses.
5. Do not calculate the final recommendation score.
6. Mark every material field with its confidence.
7. Separate verified facts from business claims.
8. Return JSON only.

Required output schema:

{
 “candidate_id”: “string”,
 “name”: “string”,
 “status”: “ELIGIBLE | INELIGIBLE | NEEDS_REVIEW”,
 “exclusion_reasons”: [“string”],
 “services”: [“string”],
 “specialisations”: [“string”],
 “industries_served”: [“string”],
 “client_types”: [“string”],
 “credentials”: [
 {
 “name”: “string”,
 “status”: “VERIFIED | CLAIMED | UNVERIFIED”,
 “confidence”: “number between 0 and 1”
 }
 ],
 “professional_memberships”: [“string”],
 “location”: {
 “address”: “string or null”,
 “suburb”: “string or null”,
 “distance_km”: “number or null”,
 “travel_time_minutes”: “number or null”
 },
 “availability”: {
 “accepting_clients”: “YES | NO | UNKNOWN”,
 “remote_available”: “YES | NO | UNKNOWN”,
 “opening_hours”: [“string”]
 },
 “fees”: {
 “published”: “YES | NO”,
 “records”: [“object”],
 “likely_service_tier”: “BUDGET | MID_MARKET | PREMIUM | UNKNOWN”
 },
 “review_summary”: {
 “rating_consistency”: “HIGH | MEDIUM | LOW | UNKNOWN”,
 “recent_positive_themes”: [“string”],
 “recent_negative_themes”: [“string”],
 “review_authenticity_concerns”: [“string”]
 },
 “red_flags”: [“string”],
 “contradictions”: [“string”],
 “missing_information”: [“string”],
 “field_confidence”: {
 “services”: “number between 0 and 1”,
 “credentials”: “number between 0 and 1”,
 “location”: “number between 0 and 1”,
 “fees”: “number between 0 and 1”,
 “reviews”: “number between 0 and 1”
 }
 }

## **Scoring should happen in code**

```pseudocode
FUNCTION calculate_scores(candidate, user_requirements):

    relevance_score =
        0.30 * service_match(candidate, user_requirements) +
        0.20 * client_type_match(candidate, user_requirements) +
        0.20 * industry_match(candidate, user_requirements) +
        0.15 * location_match(candidate, user_requirements) +
        0.15 * availability_match(candidate, user_requirements)

    quality_score =
        0.25 * credential_score(candidate) +
        0.20 * specialist_experience_score(candidate) +
        0.20 * recent_review_consistency(candidate) +
        0.15 * communication_evidence(candidate) +
        0.10 * fee_transparency(candidate) +
        0.10 * practitioner_identifiability(candidate)

    trust_score =
        0.30 * source_agreement(candidate) +
        0.25 * registration_verification(candidate) +
        0.20 * absence_of_red_flags(candidate) +
        0.15 * stable_business_history(candidate) +
        0.10 * complaint_response_quality(candidate)

    convenience_score =
        0.35 * travel_time_score(candidate) +
        0.20 * transport_and_parking_score(candidate) +
        0.20 * appointment_availability_score(candidate) +
        0.15 * remote_service_score(candidate) +
        0.10 * opening_hours_score(candidate)

    evidence_confidence =
        calculate_evidence_confidence(candidate)

    raw_score =
        REQUEST_SPECIFIC_WEIGHTING(
            relevance_score,
            quality_score,
            trust_score,
            convenience_score
        )

    confidence_adjusted_score =
        raw_score * evidence_confidence

    RETURN {
        relevance_score,
        quality_score,
        trust_score,
        convenience_score,
        evidence_confidence,
        confidence_adjusted_score
    }
```

The weights change by request type:

```pseudocode
IF request_type == "BEST_ACCOUNTANT":
    weights = {
        relevance: 0.35,
        quality: 0.30,
        trust: 0.25,
        convenience: 0.10
    }

IF request_type == "GOOD_ACCOUNTANTS":
    weights = {
        relevance: 0.30,
        quality: 0.30,
        trust: 0.25,
        convenience: 0.15
    }

IF request_type == "NEAR_ME":
    weights = {
        relevance: 0.25,
        quality: 0.20,
        trust: 0.20,
        convenience: 0.35
    }

IF request_type == "CHEAPEST":
    weights = {
        price: 0.40,
        relevance: 0.20,
        quality: 0.15,
        trust: 0.20,
        convenience: 0.05
    }

IF request_type == "SPECIALIST":
    weights = {
        exact_specialist_fit: 0.45,
        quality: 0.20,
        trust: 0.25,
        convenience: 0.10
    }
```

## **Prompt 4: final explanation**

The model receives candidates that are already ranked by code.

```text
You are writing an evidence-based accountant recommendation.

The candidates have already been scored and ranked by the application.
Do not change their order unless a supplied hard exclusion requires it.
Do not invent facts.
Do not describe a candidate as “the best” unless the supplied decision record explicitly permits that wording.

For each recommendation, explain:

- why it matches the user
- what it appears best suited for
- the strongest supporting evidence
- material limitations
- evidence confidence
- questions the user should ask before engaging the accountant

Use cautious language where evidence is incomplete.

Distinguish:

- “verified” from “claimed”
- “published fee” from “estimated price tier”
- “confirmed complaint” from “negative review”
- “closest” from “best overall”
- “lowest price” from “best value”

Return JSON only.
```

Suggested output:

```json
{
  "query_summary": {
    "request_type": "BEST_ACCOUNTANT",
    "location": "St Kilda, Victoria",
    "primary_needs": ["small-business accounting", "tax planning"]
  },
  "recommendations": [
    {
      "rank": 1,
      "candidate_id": "candidate_001",
      "name": "Example Accounting",
      "label": "Best overall match",
      "why_recommended": [
        "Strong match for small-business tax work",
        "Verified professional credentials",
        "Consistent recent review evidence"
      ],
      "best_for": ["small businesses", "ongoing tax advice"],
      "limitations": [
        "Fees are not published",
        "Current new-client availability was not confirmed"
      ],
      "confidence": 0.86,
      "questions_to_ask": [
        "Who will perform the work?",
        "What is included in the quoted fee?"
      ]
    }
  ],
  "methodology_note": "Rankings were calculated from verified fit, quality, trust, convenience and evidence-confidence factors.",
  "uncertainties": ["Fee comparisons were incomplete."]
}
```

## **Does JSON make it deterministic?**

```pseudocode
JSON_SCHEMA:
    improves structural consistency
    prevents missing required fields
    constrains allowed values
    simplifies validation
    makes retries safer
    supports automated scoring

JSON_SCHEMA DOES_NOT:
    guarantee factual accuracy
    eliminate model variability
    make subjective extraction deterministic
    prevent weak-source bias
    resolve contradictory evidence automatically
```

For stronger repeatability:

```pseudocode
USE:
    strict JSON schema
    enums
    required fields
    numeric ranges
    low model randomness
    fixed scoring weights
    source-level citations
    deterministic application code
    evidence thresholds
    validation and retry logic
    cached source snapshots
    model-version pinning where possible

AVOID:
    asking model to assign arbitrary 1-to-10 scores
    asking model to browse and rank in one prompt
    allowing unsupported free-text claims
    using review stars as the main ranking factor
    letting model silently resolve contradictions
```

The most reliable design is:

```pseudocode
LLM extracts and explains
CODE filters, scores, ranks, and validates
```

That gives you substantially more reproducible findings than trying to make the entire recommendation process deterministic through prompting alone.





You’re asking about prompts and ranking, which are important, but they’re only about **20% of the system**. If I were designing this as a commercial product, the harder problems are elsewhere.

Here are the questions I’d be asking.

------

## **1. Where does truth come from?**

This is probably the biggest question.

Instead of asking:

“How do I prompt the LLM?”

I’d ask:

“What is an authoritative fact versus an opinion?”

For example:

```
Truth hierarchy

Government registry
Professional registration
Official accounting body
Firm website
Independent news
Google Business Profile
Review sites
AI extraction
```

Every fact should carry provenance.

```
Fact:
    "CPA registered"

Value:
    TRUE

Source:
    CPA Australia

Confidence:
    0.99
```

Not merely

```
Website says CPA.
```

------

# **2. Should every fact have confidence?**

I’d absolutely build this.

```
firm.name

value:
    ABC Accounting

confidence:
    1.0

source:
    ASIC
```

versus

```
specialises in medical practices

confidence:
    0.42

source:
    marketing website
```

Everything becomes probabilistic.

------

# **3. Should every recommendation be explainable?**

Personally I’d say yes.

Not

```
Rank #1
```

But

```
Rank #1

because

+ exact SMSF match

+ 20 years experience

+ verified CPA

+ 200 recent reviews

- no weekend appointments

Confidence 91%
```

Every score explainable.

------

# **4. Should scores be fixed?**

This is surprisingly important.

Instead of

```
quality = 84
```

I’d keep

```
quality

credential_score

experience_score

review_score

communication_score

pricing_score

availability_score

industry_score

distance_score

etc
```

The UI can then build rankings however it wants.

------

# **5. Are there hidden features?**

Often yes.

Examples

```
website quality

AI responsiveness

staff count

staff turnover

blog activity

recent tax articles

Google updates

years domain registered

LinkedIn activity

response latency

phone answered?

booking available?

quote turnaround

email responsiveness
```

Those can become predictive.

------

# **6. How do you detect fake reviews?**

This is a whole research topic.

Signals include

```
review burst

identical wording

new reviewer accounts

same writing style

rating inflation

missing negatives

owner responses

review age

platform agreement
```

------

# **7. Should reviews be weighted by recency?**

Definitely.

Five-star reviews from 2019 shouldn’t outweigh a pattern from the last six months.

Example

```
today

weight = 1.0

6 months

0.8

1 year

0.5

3 years

0.2
```

------

# **8. How do you know when NOT to recommend?**

This is huge.

Many systems always recommend something.

I’d rather say

```
Evidence insufficient.

Unable to confidently distinguish between these firms.

Recommend contacting these three.
```

That builds trust.

------

# **9. What does “best” actually mean?**

People rarely define it.

It could mean

```
highest expertise

closest

lowest cost

highest review score

largest firm

best communication

best value

best specialist

lowest risk

fastest turnaround
```

Those are different optimisation problems.

------

# **10. Can the scoring engine evolve?**

I’d separate

```
Evidence

↓

Feature extraction

↓

Scoring

↓

Ranking

↓

Explanation
```

Each independently replaceable.

------

# **11. Should AI even rank?**

Interesting question.

Maybe AI should only do

```
extract

summarise

explain
```

while

```
ranking

scoring

weights
```

remain deterministic code.

That’s my preference.

------

# **12. How do you measure recommendation quality?**

Without feedback you never know.

Track

```
user clicked

contacted

booked

left feedback

would recommend again

successful outcome

returned to platform
```

Now you can improve.

------

# **13. How do you avoid popularity bias?**

Popular firms become more popular.

Need diversity.

Otherwise

```
Firm A
10,000 reviews

Firm B
40 reviews
```

doesn’t automatically mean A is better.

------

# **14. How do you personalise?**

Two users asking

```
best accountant
```

might deserve different answers.

Example

```
startup founder

↓

R&D tax

venture capital

equity
```

versus

```
retired couple

↓

estate planning

superannuation

aged care
```

Same query.

Different result.

------

# **15. How do you detect uncertainty?**

One of my favourites.

Every recommendation should include

```
confidence

0.93

because

15 independent sources agree
```

or

```
confidence

0.41

because

fees unavailable

reviews conflict

registration uncertain
```

------

# **16. Can every recommendation be reproduced?**

I’d build this.

Given

```
same query

same date

same evidence snapshot

same weights

same algorithm
```

you should obtain the same recommendation.

That makes debugging, audits, and customer support much easier.

------

## **The question I’d ask above all the others**

If I were designing a product like the one you’ve been describing (especially given your work on AI search visibility), the central question wouldn’t be:

“How do I get the LLM to recommend the best accountant?”

It would be:

**“How do I build a recommendation engine whose reasoning is inspectable, reproducible, and defensible?”**

That’s a fundamentally different design goal. It leads you toward an architecture where:

- evidence is stored separately from conclusions,
- every score is traceable to specific evidence,
- every recommendation can be replayed later,
- uncertainty is surfaced rather than hidden,
- and the LLM’s role is primarily interpretation and explanation, while deterministic code handles validation, weighting, and ranking.

That kind of architecture is also much easier to extend beyond accountants to lawyers, dentists, builders, software vendors, or almost any other recommendation domain.









The honest answer: **there is no credible universal “best business” ranking formula**.

The discovery pipeline can be universal. The evidence model can be universal. The final scoring **must change by industry, query intent, user risk and geography**.

A dentist, AI consultant, sprung-floor installer and commercial lawyer cannot be evaluated using the same weights.

Below is the architecture I would actually use.

# **Universal Business Recommendation Engine**

## **1. Core principle**

```pseudocode
UNIVERSAL:
    understand_query
    discover_candidates
    collect_evidence
    verify_identity
    normalize_facts
    detect_conflicts
    calculate_confidence
    apply_industry_policy
    apply_query_policy
    rank
    diversify_results
    explain
    abstain_when_evidence_is_insufficient

INDUSTRY_SPECIFIC:
    required_credentials
    regulatory_checks
    risk thresholds
    relevant proof
    geographic importance
    price comparability
    review usefulness
    case-study usefulness
    outcome measurability
    urgency
    specialist matching
    red-flag rules
    scoring weights
```

## **2. Industry differences that materially change ranking**

```pseudocode
INDUSTRY_DIMENSIONS = {

    regulatory_risk:
        LOW | MEDIUM | HIGH | CRITICAL,

    decision_stakes:
        LOW | MEDIUM | HIGH | CRITICAL,

    locality_importance:
        LOW | MEDIUM | HIGH,

    specialisation_importance:
        LOW | MEDIUM | HIGH | CRITICAL,

    credentials_importance:
        LOW | MEDIUM | HIGH | CRITICAL,

    reputation_importance:
        LOW | MEDIUM | HIGH,

    price_comparability:
        EASY | MODERATE | DIFFICULT,

    proof_type:
        REVIEWS |
        CASE_STUDIES |
        PORTFOLIO |
        REGISTRATION |
        OUTCOMES |
        REFERENCES |
        TECHNICAL_SPECIFICATIONS |
        MIXED,

    outcome_observability:
        LOW | MEDIUM | HIGH,

    relationship_duration:
        TRANSACTIONAL | PROJECT | ONGOING,

    referral_multiplier:
        LOW | MEDIUM | HIGH,

    geographic_service_scope:
        LOCAL | REGIONAL | NATIONAL | GLOBAL
}
```

## **3. Example industry policies**

```pseudocode
INDUSTRY_POLICY["ACCOUNTANT"] = {
    regulatory_risk: HIGH,
    decision_stakes: HIGH,
    locality_importance: MEDIUM,
    specialisation_importance: HIGH,
    credentials_importance: CRITICAL,
    proof_type: MIXED,
    relationship_duration: ONGOING,
    referral_multiplier: HIGH,

    required_checks: [
        identity,
        professional_registration,
        tax_agent_registration_when_relevant,
        disciplinary_history,
        professional_indemnity,
        service_specialisation
    ],

    weights: {
        exact_need_fit: 0.25,
        verified_credentials: 0.20,
        trust: 0.20,
        relevant_experience: 0.15,
        communication: 0.10,
        convenience: 0.05,
        price_value: 0.05
    }
}


INDUSTRY_POLICY["LAWYER"] = {
    regulatory_risk: CRITICAL,
    decision_stakes: CRITICAL,
    locality_importance: MEDIUM,
    specialisation_importance: CRITICAL,
    credentials_importance: CRITICAL,
    proof_type: REGISTRATION,
    relationship_duration: PROJECT,
    referral_multiplier: HIGH,

    required_checks: [
        practising_status,
        jurisdiction,
        exact_practice_area,
        disciplinary_history,
        conflicts,
        matter_complexity_fit
    ],

    weights: {
        exact_practice_fit: 0.30,
        jurisdiction_and_registration: 0.25,
        relevant_matter_experience: 0.20,
        trust: 0.15,
        communication: 0.05,
        fee_clarity: 0.05
    },

    prohibited_shortcuts: [
        rank_by_review_volume,
        infer_case_success_from_marketing,
        declare_best_without_exact_matter_fit
    ]
}


INDUSTRY_POLICY["DENTIST_OR_CLINIC"] = {
    regulatory_risk: CRITICAL,
    decision_stakes: HIGH,
    locality_importance: HIGH,
    specialisation_importance: HIGH,
    credentials_importance: CRITICAL,
    proof_type: MIXED,
    relationship_duration: ONGOING,

    required_checks: [
        practitioner_registration,
        clinic_identity,
        treatment_specialisation,
        safety_or_disciplinary findings,
        practitioner_level_reviews,
        emergency_access,
        accessibility
    ],

    weights: {
        treatment_fit: 0.25,
        practitioner_credentials: 0.20,
        safety_and_trust: 0.20,
        patient_experience: 0.15,
        locality_and_access: 0.10,
        fee_transparency: 0.05,
        availability: 0.05
    },

    review_rule:
        clinic_rating_alone_is_insufficient
}


INDUSTRY_POLICY["AI_CONSULTANT"] = {
    regulatory_risk: LOW,
    decision_stakes: MEDIUM_TO_HIGH,
    locality_importance: LOW,
    specialisation_importance: HIGH,
    credentials_importance: LOW,
    proof_type: CASE_STUDIES,
    outcome_observability: MEDIUM,
    relationship_duration: PROJECT_OR_ONGOING,
    referral_multiplier: HIGH,

    required_checks: [
        named_team,
        relevant_case_studies,
        technical capability,
        business-process capability,
        security_and_privacy_practices,
        realistic claims,
        implementation ownership,
        references
    ],

    weights: {
        exact_use_case_fit: 0.25,
        verified_delivery_evidence: 0.25,
        technical_and_operational_depth: 0.15,
        commercial_outcomes: 0.15,
        trust_and_claim_realism: 0.10,
        security_and_governance: 0.05,
        price_value: 0.05
    },

    red_flags: [
        vague_AI_transformation_claims,
        no_named_people,
        no_deployed_examples,
        guaranteed_ROI,
        prompt_engineering_presented_as_full_consulting,
        no_security_answers,
        fabricated_partnership_signals
    ]
}


INDUSTRY_POLICY["MARKETING_AGENCY"] = {
    regulatory_risk: LOW,
    decision_stakes: MEDIUM,
    locality_importance: LOW_TO_MEDIUM,
    specialisation_importance: HIGH,
    credentials_importance: LOW,
    proof_type: CASE_STUDIES,
    relationship_duration: ONGOING,
    referral_multiplier: HIGH,

    required_checks: [
        relevant_channel_experience,
        comparable_client_results,
        attribution_method,
        client_retention,
        who_performs_work,
        contract_terms,
        reporting_quality
    ],

    weights: {
        exact_market_and_channel_fit: 0.25,
        verified_case_studies: 0.20,
        measurement_quality: 0.15,
        team_quality: 0.10,
        communication: 0.10,
        trust: 0.10,
        commercial_terms: 0.10
    },

    red_flags: [
        vanity_metrics_only,
        unverifiable_revenue_claims,
        outsourced_delivery_not_disclosed,
        long_lock_in_without_evidence,
        awards_used_as_primary_proof
    ]
}


INDUSTRY_POLICY["REAL_ESTATE_AGENT"] = {
    regulatory_risk: MEDIUM_TO_HIGH,
    decision_stakes: HIGH,
    locality_importance: CRITICAL,
    specialisation_importance: HIGH,
    credentials_importance: HIGH,
    proof_type: OUTCOMES,
    relationship_duration: TRANSACTIONAL,

    required_checks: [
        licence_status,
        suburb_sales_activity,
        property_type_match,
        recent comparable results,
        vendor_reviews,
        marketing strategy,
        fee_structure
    ],

    weights: {
        exact_suburb_and_property_fit: 0.30,
        recent_comparable_results: 0.25,
        trust_and_vendor_feedback: 0.15,
        sales_process: 0.10,
        communication: 0.10,
        fees_and_terms: 0.05,
        availability: 0.05
    },

    prohibited_shortcuts: [
        rank_by_total_lifetime_sales,
        rank_by_brand_size,
        compare_unlike_property_types
    ]
}


INDUSTRY_POLICY["SPECIALIST_FLOORING_OR_SPRUNG_FLOORS"] = {
    regulatory_risk: MEDIUM,
    decision_stakes: MEDIUM_TO_HIGH,
    locality_importance: HIGH,
    specialisation_importance: CRITICAL,
    credentials_importance: MEDIUM,
    proof_type: TECHNICAL_SPECIFICATIONS,
    outcome_observability: HIGH,
    relationship_duration: PROJECT,

    required_checks: [
        exact_system_experience,
        installation portfolio,
        relevant standards,
        substrate_preparation capability,
        moisture_and_acoustic competence,
        warranty,
        references,
        geographic serviceability
    ],

    weights: {
        exact_technical_fit: 0.30,
        verified_installations: 0.20,
        standards_and_specification_compliance: 0.15,
        installer_capability: 0.10,
        warranty_and_aftercare: 0.10,
        references_and_reputation: 0.10,
        price_value: 0.05
    },

    red_flags: [
        generic_flooring_company_with_no_sprung_floor_evidence,
        manufacturer_claim_without_authorised_installer_evidence,
        no_subfloor_assessment,
        no_project_specific_specification,
        unclear_warranty_owner
    ]
}
```

## **4. Master process**

```pseudocode
FUNCTION recommend_businesses(
    user_query,
    user_location,
    user_profile,
    current_datetime
):

    request = classify_and_structure_request(
        user_query,
        user_location,
        user_profile
    )

    industry = classify_industry(request)

    policy = load_industry_policy(industry)

    query_policy = load_query_policy(
        request.intent
    )

    search_plan = build_search_plan(
        request,
        policy,
        query_policy
    )

    raw_candidates = discover_candidates(
        search_engines,
        maps,
        industry_directories,
        professional_registries,
        government_registries,
        association_directories,
        vendor_or_manufacturer_directories,
        review_platforms,
        editorial_sources,
        local_business_sources,
        user_supplied_candidates
    )

    candidates = entity_resolve_and_deduplicate(
        raw_candidates
    )

    FOR each candidate IN candidates:

        evidence = collect_candidate_evidence(
            candidate,
            search_plan.required_sources
        )

        candidate_record = normalize_evidence(
            candidate,
            evidence
        )

        candidate_record.identity_status =
            verify_business_identity(candidate_record)

        candidate_record.regulatory_status =
            run_required_checks(
                candidate_record,
                policy.required_checks
            )

        candidate_record.red_flags =
            detect_red_flags(
                candidate_record,
                policy.red_flags
            )

        candidate_record.conflicts =
            detect_evidence_conflicts(candidate_record)

        candidate_record.evidence_confidence =
            calculate_evidence_confidence(
                source_authority,
                source_independence,
                source_recency,
                cross_source_agreement,
                factual_completeness,
                contradiction_penalty,
                marketing_claim_penalty
            )

        candidate_record.eligibility =
            apply_hard_exclusions(
                candidate_record,
                policy,
                request
            )

    eligible_candidates = filter(
        candidates,
        eligibility == "ELIGIBLE"
    )

    review_candidates = filter(
        candidates,
        eligibility == "NEEDS_REVIEW"
    )

    FOR each candidate IN eligible_candidates:

        features = calculate_features(
            candidate,
            request,
            policy
        )

        candidate.raw_score =
            deterministic_weighted_score(
                features,
                policy.weights,
                query_policy.weight_adjustments
            )

        candidate.risk_adjusted_score =
            candidate.raw_score
            * candidate.evidence_confidence
            * regulatory_confidence_multiplier(candidate)
            * fit_confidence_multiplier(candidate)

    ranked = sort_descending(
        eligible_candidates,
        risk_adjusted_score
    )

    ranked = apply_diversity_rules(
        ranked,
        avoid_duplicate_business_models,
        avoid_same_network_overrepresentation,
        include_relevant_specialists,
        include_best_value_when_supported,
        include_best_local_when_supported
    )

    decision = determine_output_mode(
        ranked,
        review_candidates,
        request,
        policy
    )

    IF decision == "ABSTAIN":
        RETURN insufficient_evidence_response(
            reasons,
            verification_steps,
            possible_shortlist
        )

    IF decision == "SHORTLIST":
        selected = select_top_distinct_candidates(
            ranked,
            count = 3_to_5
        )

    IF decision == "SINGLE_BEST_MATCH":
        selected = ranked[0]
        require_clear_margin_over_second_place()
        require_high_evidence_confidence()
        require_no_material_unresolved_conflict()

    output = generate_evidence_bound_explanation(
        request,
        selected,
        policy,
        ranked_scores,
        evidence,
        limitations
    )

    validate_output_against_evidence(output)

    RETURN output
```

## **5. Query intent policies**

```pseudocode
QUERY_POLICY["BEST"] = {
    objective:
        maximise_fit_quality_and_trust,

    output:
        one_best_match_only_if_materially_ahead,
        otherwise_top_three,

    location_weight:
        use_industry_default,

    evidence_threshold:
        HIGH
}


QUERY_POLICY["GOOD"] = {
    objective:
        produce_credible_diverse_shortlist,

    output:
        three_to_five_candidates_with_different_strengths,

    evidence_threshold:
        MEDIUM_TO_HIGH
}


QUERY_POLICY["NEAR_ME"] = {
    objective:
        minimise_practical_distance_without_falling_below_quality_floor,

    rule:
        proximity_is_not_a_substitute_for_fit,

    location_weight_adjustment:
        increase_only_for_local_service_industries
}


QUERY_POLICY["CHEAPEST"] = {
    objective:
        identify_lowest_comparable_total_cost,

    mandatory_rule:
        compare_equivalent_scope,

    output:
        lowest_confirmed_price,
        best_value,
        exclusions_and_hidden_cost_risks
}


QUERY_POLICY["SPECIALIST"] = {
    objective:
        maximise_exact_problem_or_project_fit,

    adjustment:
        increase_specialisation_weight,
        reduce_generic_popularity_weight
}


QUERY_POLICY["FOR_BUSINESS_REFERRAL_PARTNER"] = {
    objective:
        identify_businesses_with_client_access_and_referral_likelihood,

    additional_features: [
        number_and_type_of_business_clients,
        advisory_trust,
        referral_culture,
        service_complementarity,
        channel_conflict,
        white_label_potential,
        geographic reach,
        decision_maker_access,
        client_communication_frequency
    ]
}
```

## **6. Referral-multiplier scoring**

Your Tier 1, Tier 2 and Tier 3 model is not ordinary local-business recommendation. It is **channel-partner prioritisation**.

Use a separate model.

```pseudocode
FUNCTION score_referral_multiplier(candidate, offer):

    client_access_score =
        estimated_relevant_client_base
        * client_business_concentration
        * client_contact_frequency

    borrowed_trust_score =
        adviser_status
        * relationship_depth
        * recommendation_influence

    referral_behavior_score =
        evidence_of_referral_culture
        + partnerships
        + network_membership
        + cross_referral_activity

    strategic_fit_score =
        offer_complementarity
        + shared_target_market
        + easy_explanation
        + clear_client_value

    conflict_score =
        competitive_overlap
        + fear_of_disintermediation
        + loss_of_service_revenue
        + reputational_risk

    activation_score =
        decision_maker_access
        + short_sales_cycle
        + low_enablement_burden
        + easy_referral_mechanism

    fan_out_score =
        number_of_relevant_clients
        + number_of_locations
        + franchisees_or_members
        + newsletter_or_community_reach

    evidence_confidence =
        confidence_in_all_above_inputs

    raw_channel_score =
        0.20 * client_access_score
        + 0.20 * borrowed_trust_score
        + 0.15 * referral_behavior_score
        + 0.15 * strategic_fit_score
        + 0.15 * activation_score
        + 0.15 * fan_out_score
        - 0.20 * conflict_score

    RETURN raw_channel_score * evidence_confidence
CHANNEL_TYPE["ACCOUNTANT"] = {
    strengths:
        high_trust,
        broad_SMB_client_base,
        recurring_client_contact,
        strong_problem_awareness,

    weaknesses:
        conservative_adoption,
        limited_time,
        possible_liability_concerns,

    referral_ask:
        "Which three clients would benefit most from seeing this?"
}


CHANNEL_TYPE["AGENCY"] = {
    strengths:
        high_client_access,
        understands_visibility,
        white_label_potential,

    weaknesses:
        channel_conflict,
        fear_of_replacement,
        incentive_misalignment,

    referral_ask:
        "Would this strengthen your client offer, or compete with it?"
}


CHANNEL_TYPE["MSP"] = {
    strengths:
        trusted_technology_adviser,
        recurring_revenue_relationship,
        security_access,
        broad_SMB base,

    weaknesses:
        capability_gap,
        support burden,
        concern_about_uncontrolled_AI,

    referral_ask:
        "Which clients are already asking you about AI visibility or adoption?"
}


CHANNEL_TYPE["FRANCHISOR"] = {
    strengths:
        extreme_fan_out,
        centralised_decision,
        repeatable_rollout,

    weaknesses:
        longer_sales_cycle,
        procurement,
        brand_and_legal_approval,

    referral_ask:
        "Could this become a standard capability for every franchisee?"
}


CHANNEL_TYPE["ASSOCIATION"] = {
    strengths:
        concentrated_audience,
        institutional_trust,
        events_and_newsletters,

    weaknesses:
        sponsorship_gatekeeping,
        neutrality requirements,
        slower approval,

    referral_ask:
        "Would this be useful as member education rather than a direct sales pitch?"
}
```

## **7. Canonical request JSON**

```json
{
  "request_id": "uuid",
  "query": {
    "raw_text": "Find the best AI consultant for a dental group in Melbourne",
    "intent": "BEST",
    "decision_context": "BUYER_SELECTION",
    "industry_requested": "AI_CONSULTING",
    "subject_industry": "DENTAL",
    "location": {
      "suburb": null,
      "city": "Melbourne",
      "state": "Victoria",
      "country": "Australia",
      "radius_km": null
    },
    "service_scope": [
      "AI strategy",
      "implementation",
      "workflow automation"
    ],
    "special_requirements": [
      "health data privacy",
      "multi-location deployment"
    ],
    "budget": {
      "minimum": null,
      "maximum": null,
      "currency": "AUD",
      "billing_basis": "UNKNOWN"
    },
    "urgency": "UNKNOWN",
    "remote_acceptable": true
  },
  "user_context": {
    "client_type": "BUSINESS",
    "business_size": "UNKNOWN",
    "industry": "DENTAL",
    "risk_tolerance": "UNKNOWN",
    "preferences": [],
    "exclusions": []
  },
  "classification": {
    "primary_industry": "AI_CONSULTING",
    "industry_confidence": 0.97,
    "query_confidence": 0.95,
    "missing_information": [
      "budget",
      "business size",
      "required implementation timeframe"
    ],
    "assumptions": []
  }
}
```

## **8. Canonical candidate evidence JSON**

```json
{
  "candidate_id": "uuid",
  "identity": {
    "legal_name": "Example Consulting Pty Ltd",
    "trading_name": "Example AI",
    "website": "https://example.com",
    "locations": [],
    "identity_confidence": 0.98
  },
  "industry": {
    "primary": "AI_CONSULTING",
    "secondary": ["AUTOMATION", "DATA"],
    "classification_confidence": 0.91
  },
  "eligibility": {
    "status": "ELIGIBLE",
    "hard_exclusion_reasons": [],
    "manual_review_reasons": []
  },
  "facts": [
    {
      "field": "case_study.healthcare",
      "value": true,
      "status": "VERIFIED",
      "confidence": 0.87,
      "sources": ["source_01", "source_04"],
      "last_verified_at": "2026-07-27T00:00:00Z"
    }
  ],
  "services": [],
  "specialisations": [],
  "industries_served": [],
  "credentials": [],
  "registrations": [],
  "case_studies": [],
  "portfolio": [],
  "reviews": {
    "platforms": [],
    "themes": {
      "positive": [],
      "negative": []
    },
    "review_reliability_score": 0.0
  },
  "pricing": {
    "published": false,
    "records": [],
    "comparability": "UNKNOWN"
  },
  "geography": {
    "service_area": [],
    "distance_km": null,
    "travel_time_minutes": null,
    "remote_available": "UNKNOWN"
  },
  "red_flags": [],
  "contradictions": [],
  "missing_information": [],
  "evidence_confidence": 0.0
}
```

## **9. Canonical scored-candidate JSON**

```json
{
  "candidate_id": "uuid",
  "policy_id": "AI_CONSULTANT_V1",
  "query_policy_id": "BEST_V1",
  "feature_scores": {
    "exact_use_case_fit": 84,
    "verified_delivery_evidence": 72,
    "technical_and_operational_depth": 78,
    "commercial_outcomes": 64,
    "trust_and_claim_realism": 88,
    "security_and_governance": 55,
    "price_value": 50
  },
  "raw_score": 73.4,
  "evidence_confidence": 0.78,
  "risk_multiplier": 0.92,
  "confidence_adjusted_score": 52.68,
  "rank": 2,
  "decision_label": "STRONG_CANDIDATE",
  "strengths": [],
  "limitations": [],
  "unresolved_questions": []
}
```

## **10. Prompt 1 — classify the request**

```text
SYSTEM

You are a business-recommendation request classifier.

Convert the user's request into the supplied JSON schema.

Do not recommend businesses.
Do not search for businesses.
Do not invent missing facts.
Use null or UNKNOWN when information is absent.

Distinguish between:

- buyer selection
- local discovery
- supplier selection
- specialist selection
- cheapest provider
- best-value provider
- channel-partner prioritisation
- referral-partner discovery
- franchise or association opportunity
- evaluation of a named business

Identify both:

1. the industry being searched for
2. the user's own industry when relevant

Examples:

- "AI consultant for dentists"
  searched industry = AI consulting
  subject industry = dental

- "best accountant near me"
  searched industry = accounting
  subject industry = unknown

- "which accountants should I approach as referral partners?"
  searched industry = accounting
  decision context = channel partner prioritisation

Return JSON only.
```

## **11. Prompt 2 — extract evidence**

```text
SYSTEM

You are an evidence extraction engine.

Extract only facts supported by the supplied source material.

Do not rank the business.
Do not recommend the business.
Do not infer quality from polished marketing.
Do not treat a claim on the business's own website as independently verified.
Do not treat absence of evidence as evidence of absence.

For every material fact record:

- field
- value
- verification status
- confidence
- source
- source type
- source date
- retrieval date

Separate:

- verified facts
- first-party claims
- third-party claims
- opinions
- reviews
- inferred signals
- missing information
- contradictions

Apply the supplied industry policy.

For regulated industries, prioritise official registries.

For project businesses, prioritise comparable completed work.

For consultants and agencies, prioritise verified case studies, named clients where legitimately disclosed, references and evidence of actual implementation.

For local providers, verify service area rather than assuming the address defines coverage.

Return JSON only.
```

## **12. Prompt 3 — normalise and resolve evidence**

```text
SYSTEM

You are a candidate-record normalisation engine.

Combine all supplied evidence into one canonical candidate record.

Evidence priority:

1. government or statutory registry
2. professional regulator
3. official technical or manufacturer directory
4. directly verifiable first-party facts
5. reputable independent sources
6. review platforms
7. directories
8. marketing claims
9. model inference

Rules:

- Preserve contradictions.
- Do not silently choose the most flattering claim.
- Prefer recent evidence for changeable facts.
- Prefer authoritative evidence for regulated facts.
- Keep candidate-level and practitioner-level evidence separate.
- Keep office-level and company-level evidence separate.
- Do not merge similarly named businesses without identity evidence.
- Do not calculate final rank.
- Return JSON only.
```

## **13. Prompt 4 — explanation after deterministic ranking**

```text
SYSTEM

You are an evidence-bound recommendation writer.

The application has already:

- classified the query
- selected the industry policy
- verified evidence
- excluded ineligible candidates
- calculated feature scores
- confidence-adjusted the scores
- ranked the candidates

Do not recalculate scores.
Do not change ranking order.
Do not introduce facts absent from the candidate records.
Do not use "best" unless the decision record permits that label.
Do not hide material uncertainty.

For each candidate explain:

- why it fits the user's exact need
- strongest verified evidence
- meaningful weaknesses
- unresolved questions
- why it ranked above or below alternatives
- what the user should verify before engaging

Distinguish:

- nearest from best
- cheapest from best value
- popularity from quality
- claims from verified evidence
- company reputation from individual practitioner quality
- generic experience from exact specialisation

Return valid JSON matching the response schema.
```

## **14. Final response JSON**

```json
{
  "request_summary": {
    "intent": "BEST",
    "industry": "AI_CONSULTING",
    "subject_industry": "DENTAL",
    "location": "Melbourne, Victoria",
    "primary_requirements": []
  },
  "decision": {
    "mode": "SHORTLIST",
    "reason": "No candidate had enough verified evidence to justify a definitive single winner.",
    "policy_version": "AI_CONSULTANT_V1",
    "evidence_snapshot_at": "2026-07-27T00:00:00Z"
  },
  "recommendations": [
    {
      "rank": 1,
      "candidate_id": "uuid",
      "name": "Example Business",
      "label": "Best verified fit",
      "confidence_adjusted_score": 72.4,
      "confidence": 0.84,
      "best_for": [],
      "why_recommended": [],
      "verified_strengths": [],
      "limitations": [],
      "unresolved_questions": [],
      "questions_to_ask": []
    }
  ],
  "excluded_candidates": [
    {
      "candidate_id": "uuid",
      "name": "Example Excluded Business",
      "reason": "Required registration could not be verified."
    }
  ],
  "methodology": {
    "ranking_factors": [],
    "hard_exclusions": [],
    "important_limitations": []
  }
}
```

## **15. What must remain deterministic code**

```pseudocode
DO_IN_CODE:
    schema validation
    entity deduplication
    distance calculation
    date calculations
    review recency decay
    source authority weighting
    hard exclusions
    credential requirements
    feature scoring
    weighting
    confidence adjustment
    ranking
    tie handling
    threshold enforcement
    abstention decision
    audit logging
    versioning

ALLOW_LLM_TO_DO:
    intent classification
    industry classification
    evidence extraction
    review-theme extraction
    contradiction identification
    plain-English explanation

DO_NOT_ALLOW_LLM_TO_DO_FREELY:
    invent numerical scores
    decide professional validity
    choose arbitrary weights
    resolve factual conflicts silently
    browse_and_rank_in_one_pass
    declare_best_without_thresholds
```

## **16. Reality checks**

```pseudocode
TRUTH_1:
    JSON creates structural consistency,
    not factual certainty.

TRUTH_2:
    Reviews are useful for service experience,
    but weak evidence for technical competence.

TRUTH_3:
    Credentials prove minimum standing,
    not superior performance.

TRUTH_4:
    Case studies are often selected marketing evidence
    and require verification.

TRUTH_5:
    Price comparisons are usually invalid
    unless scope is normalised.

TRUTH_6:
    "Best near me" may require different candidates
    for different users in the same suburb.

TRUTH_7:
    A company can be strong overall
    while the specific practitioner assigned is weak.

TRUTH_8:
    For many searches,
    the honest output is a shortlist,
    not a winner.

TRUTH_9:
    The industry taxonomy and policy library
    are more important than clever prompting.

TRUTH_10:
    Without evidence snapshots, scoring versions
    and replayability, the system is not auditable.

TRUTH_11:
    For your Tier 1 strategy,
    recommendation quality alone is insufficient.
    You must separately score channel access,
    referral behaviour, conflict and fan-out.

TRUTH_12:
    The model will fail if asked to infer
    private commercial facts such as client count,
    conversion rate or referral willingness
    without direct evidence.
```

## **17. Minimum viable version**

```pseudocode
MVP:

    support_5_industries_only

    create_industry_policy_for_each

    classify_query_to_JSON

    search_and_collect_candidates

    extract_evidence_to_JSON

    verify_regulated_fields

    score_in_code

    return_top_3

    show:
        why
        evidence
        uncertainty
        questions_to_ask

    store:
        query
        evidence_snapshot
        policy_version
        scoring_version
        output
```

Do not begin with fifty industries.

Start with:

```pseudocode
1. accountants
2. marketing_agencies
3. AI_consultants
4. dentists_or_cosmetic_clinics
5. real_estate_agents
```

These five force you to solve nearly every hard category:

```pseudocode
regulated_professional
B2B_service
emerging_unregulated_service
healthcare
hyperlocal_outcome_driven_service
```

Once those policies work, add lawyers, brokers, MSPs, specialist trades, franchisors and associations.

The central architecture is therefore:

```pseudocode
ONE universal evidence pipeline
+
ONE versioned policy per industry
+
ONE versioned policy per query intent
+
DETERMINISTIC scoring and exclusions
+
LLM extraction and explanation
+
ABSTENTION when evidence cannot support a winner
```

The weakest design would be a giant prompt asking an AI to “find and rank the best businesses.” The strongest design is a **policy-driven evidence engine** in which the model is not allowed to decide what “best” means on its own.





I created a **937-line Markdown reference catalogue** covering:

- Australia, United States, United Kingdom and Canada
- Company and charity registries
- Professional and occupational registers
- Accountants, tax agents and financial advisers
- Lawyers and conveyancers
- Doctors, dentists, clinics and allied health
- Real estate agents and mortgage professionals
- Builders, architects, trades and specialist flooring
- Childcare, education and aged care
- Courts, disciplinary records, enforcement and complaints
- Maps, reviews, web evidence, domain history and technical verification
- Full URL templates with placeholders and query parameters
- API endpoints where publicly documented
- Clear markings for `GET`, `API`, `UI/POST only`, login, paid and scraping-restricted sources
- Industry-specific search templates
- JSON structure for storing source definitions
- Source-priority and anti-false-certainty rules

[Download the Business Recommendation URL Catalogue](sandbox:/mnt/data/business_recommendation_urls_AU_US_UK_CA.md?_chatgptios_conversationID=6a668274-1668-83ec-a581-51b0efc9c28d&_chatgptios_messageID=c583be42-f449-4a77-8f54-4c45db358d73)⁠![Attachment.tiff](Attachment.tiff)

I have deliberately **not invented query parameters** for registers whose searches depend on forms, sessions or POST requests. For example, ASIC provides multiple register interfaces, but several are session-driven; ABN Lookup provides public business identity data and separate web services; Companies House provides both public search and documented API endpoints; and Canada’s cross-registry service explicitly restricts automated copying or scraping of search results.  

The file should be treated as a strong **version-one source registry**, not a permanently exhaustive list. US professional and business licensing alone is fragmented across states, while Australian, Canadian and UK professions frequently divide authority by state, province, territory, nation or profession. The catalogue therefore includes national directories and the most useful jurisdiction-specific entry points rather than falsely claiming that one register covers everything.





# **1. What I can and cannot know about my own implementation**

## **1.1 The necessary boundary**

**I cannot verify the proprietary internal mechanism. The following is a functional explanation or inference based on observable behaviour.**

I do not have introspective access to:

- model weights;
- the training corpus or a searchable list of training documents;
- hidden activation values;
- proprietary ranking code;
- private search-provider algorithms;
- exact source-selection weights;
- undisclosed system instructions;
- exact confidence thresholds;
- hidden chain-of-thought;
- the complete candidate list considered internally;
- token-level reasons why one business name won over another;
- unpublished details of personalisation, caching or experimentation;
- the exact model-side process used in every other ChatGPT product surface.

I therefore cannot truthfully say, for example:

“Business A received 31% for trust, 24% for proximity and 18% for reviews.”

Unless an application explicitly calculates and exposes those values, such numbers would be invented.

## **1.2 What I directly know in this conversation**

**Directly known**

In this session:

- I am GPT-5.6 Thinking.
- I can answer from learned model knowledge.
- I can invoke a general web-search tool.
- The web tool can return a limited set of search results, extracted text, structured fields for some categories and individual pages that I can open.
- I can issue more than one query, alter the query, open selected results, search within pages and compare sources.
- I do not automatically receive an exhaustive copy of the search index.
- I do not currently have a general-purpose Google Maps interface or unrestricted access to every map listing.
- I can receive dedicated structured data for certain categories such as weather, finance, supported sports and time. Business listings are not universally supplied through an equivalent structured tool in this environment.
- I can use connected applications such as Gmail, Calendar and Contacts where the user authorises them, but these are not general business-ranking databases.
- I can retain evidence inside the current conversation, subject to context limitations. I do not create a permanent auditable evidence store unless an external application does so.
- Search results and tool responses may be filtered, truncated or limited.
- My final prose is generated probabilistically rather than by executing a transparent fixed business-ranking formula.

## **1.3 Documented product behaviour**

**Documented behaviour**

OpenAI says ChatGPT Search may rewrite a user request into one or more targeted queries and send those queries to search providers. Search answers may include inline citations and a broader Sources panel. OpenAI also says search ranking uses multiple factors intended to find reliable, relevant information, but does not publish a complete formula and states that no site can guarantee top placement.  

OpenAI documents that optional device location may be used for local recommendations and that trusted third-party providers may receive location information to provide local results. Precise location sharing is optional; when used, OpenAI says the precise location is deleted after generating the response, although location-derived answer content remains in the chat.  

OpenAI explicitly acknowledges that ChatGPT can hallucinate: it can generate plausible but false statements, and lower hallucination rates do not mean zero hallucinations.  

## **1.4 Functional explanation versus implementation claim**

The safest interpretation is:

- **The retrieval product** decides which search documents or structured results are returned.
- **The language model** interprets the question, decides whether more retrieval is needed, chooses which supplied evidence to emphasise and writes the answer.
- **External data providers** may decide local ordering, review aggregation, availability, opening hours or other structured facts.
- **Application code** controls tool availability, result limits, context limits, citation rendering, safety policy and sometimes deterministic filters.
- **Unknown proprietary components** may perform query rewriting, retrieval ranking, spam control, authority assessment or answer-grounding checks.

The final recommendation is therefore a compound product outcome, not “the model’s pure opinion.”

------

# **2. How I actually handle these questions**

## **2.1 Without live web access**

### **Information available**

**Directly known / functional explanation**

I have learned statistical representations of language and facts from training. That training may have included:

- business names;
- brand names;
- locations;
- service-category associations;
- articles mentioning firms;
- reviews or review-like text;
- directories;
- news reports;
- regulatory material;
- webpages;
- discussions and comparisons.

I cannot inspect the training corpus to determine whether a particular business appeared, how often it appeared or whether a specific review was included.

### **How an answer emerges**

A request such as “best accountant in St Kilda” may cause likely business names and recommendation language to be generated from learned associations. Those associations can reflect:

- brand prominence;
- repeated co-occurrence of a name with “accountant” and “St Kilda”;
- broader Melbourne prominence;
- memorable editorial language;
- directory-like text;
- old information;
- accidental or misleading associations.

The candidate set is not necessarily a database row set that I first enumerate. It can emerge token by token as I generate the answer.

### **Major limitations**

Without live retrieval:

- I cannot know whether the business still operates.
- I cannot reliably know present opening hours, staff, prices, reviews or registration status.
- I may substitute a prominent nearby business for a truly local one.
- I may confuse similarly named firms.
- I may invent plausible contact details.
- I cannot establish that “best” is current.
- I should usually avoid firm current rankings for unfamiliar local businesses.

A responsible answer should either:

1. provide general selection criteria;
2. state that current verification is required; or
3. search before naming or ranking firms.

### **Does a business need to be in live results?**

No. A business can be generated solely from learned knowledge.

That does not make the recommendation current, verified or reliable.

------

## **2.2 With general web search**

### **Information available**

The product may reformulate the question into searches such as:

```text
best accountant St Kilda VIC
accountant St Kilda small business reviews
site:taxpractitionersboard.gov.au "Example Accounting"
"Example Accounting" St Kilda
"Example Accounting" complaints OR disciplinary
```

One or several searches may be used. This depends on the question, available tools, instructions, perceived risk and whether the first result set is adequate.

OpenAI documents that ChatGPT Search may rewrite a prompt into one or more targeted searches. It does not document an exhaustive source-selection or reranking formula.  

### **What I receive**

Usually I receive a **filtered subset**, not complete search results.

That subset may contain:

- title;
- URL or source identifier;
- snippet;
- publication date where available;
- extracted page text;
- source metadata;
- sometimes structured fields.

I can often open selected pages. I do not automatically read every result.

### **Does result ordering influence the answer?**

Yes, functionally.

Earlier, clearer and more authoritative-looking results are more likely to:

- enter the candidate set;
- be opened;
- receive more attention;
- be mentioned;
- be cited;
- influence ordering.

This is an observable retrieval-position effect, but I cannot verify its exact magnitude.

### **Independent verification**

I can perform independent verification only to the extent that I:

- issue additional searches;
- inspect official websites;
- consult registers;
- compare multiple pages;
- check dates;
- resolve conflicting data.

It is not automatic in every response. A quick answer may rely too heavily on snippets. A careful high-stakes answer should inspect primary sources.

### **Reproducibility**

The answer is not fully reproducible because:

- search indexes change;
- result ordering changes;
- snippets change;
- pages become unavailable;
- query rewriting can vary;
- the model’s generated wording can vary;
- different sources may be opened;
- system and model versions change.

------

## **2.3 With maps or local-search data**

### **Important limitation**

In this session I do **not** possess an unrestricted, transparent map index containing all businesses and their local-pack ranks.

Some ChatGPT product experiences can display maps or local place information, and OpenAI documents optional location use and third-party local-data providers. The exact providers, coverage and ranking mechanics are not fully disclosed.  

### **If structured local data is supplied**

I may receive fields such as:

- business name;
- category;
- address;
- approximate distance;
- rating;
- review count;
- opening status;
- hours;
- website;
- reservation or action links.

I then reason over the supplied subset.

### **What I cannot assume**

I cannot assume that:

- the subset is exhaustive;
- map order equals quality order;
- star ratings are fraud-free;
- opening hours are live and correct;
- the map provider’s category classification is correct;
- the nearest result is the most appropriate;
- every sponsored result is labelled in a way visible to me;
- every review is available for textual analysis.

### **“Near me”**

“Near me” requires location data. If location is unavailable, I should request or infer a suburb or city only when justified. In this conversation, location metadata may suggest Japan, but that does not mean every “near me” request should silently use the user’s current coordinates. The user may be asking for another place.

Location radius is contextual:

- café: often walking distance;
- accountant: suburb, nearby suburbs or remote service;
- emergency vet: travel time matters;
- commercial lawyer: city-wide may be acceptable;
- sprung-floor specialist: regional or national coverage may be normal.

------

## **2.4 With connected tools or external APIs**

The external tool defines the raw universe I can see.

Examples:

- a professional-register API may return only registered entities;
- a maps API may rank by proximity and provider relevance;
- an availability API may return only participating providers;
- a review API may expose rating totals but not review text;
- a CRM may expose only the user’s own suppliers;
- a booking system may expose actual appointment slots.

Tool-specific filtering can dominate the recommendation. A business absent from the API can disappear from consideration even if objectively excellent.

The model can:

- choose filters;
- interpret results;
- compare returned candidates;
- explain trade-offs.

The model cannot recover entities the API never returns unless it uses another source.

------

## **2.5 A named-business question**

Example:

“Is Example Accounting any good?”

This changes the task from open candidate discovery to entity validation.

Likely process:

1. Resolve the exact entity.
2. Confirm official name, address and website.
3. Determine relevant service and geography.
4. Inspect the official site.
5. Look for independent evidence.
6. Check professional registration where relevant.
7. Search for material regulatory or court findings.
8. Assess whether available evidence supports a conclusion.
9. Separate facts from opinions and absence of evidence.

Exact-name searches are much more likely than broad category searches.

Risks include:

- confusing a trading name with a legal entity;
- confusing the firm with an individual practitioner;
- confusing two businesses with similar names;
- matching a review profile for the wrong branch;
- treating self-authored claims as independent evidence;
- interpreting no visible complaints as proof of quality.

A careful answer should say “I found evidence of…” rather than “This firm is good” when evidence is limited.

------

## **2.6 Regulated or high-stakes professions**

For law, financial advice, psychology, medical or dental care, mortgage or financial services and some building services, I should increase verification and reduce unsupported ranking confidence.

The likely hierarchy becomes:

1. current registration or licence;
2. scope of permitted practice;
3. disciplinary restrictions;
4. exact specialist competence;
5. professional indemnity or required cover where verifiable;
6. current location and availability;
7. independent track record;
8. reviews as supplementary evidence.

Reviews are not a substitute for registration.

I should abstain or provide a verification-oriented shortlist when:

- registration cannot be confirmed;
- the user’s matter has serious legal, medical or financial consequences;
- the question asks for a guarantee;
- available evidence is sparse or contradictory;
- urgency requires emergency or official services rather than ordinary business recommendations.

------

## **2.7 Problem-first questions**

Example:

“My BAS is overdue and I am worried about penalties.”

The category is inferred rather than supplied.

A likely semantic decomposition is:

```text
Problem: overdue Business Activity Statement
Jurisdiction: probably Australia
Risk: tax penalties, interest, compliance
Likely providers: registered tax agent/accountant/bookkeeper with BAS-agent authority
Urgency: high but not necessarily emergency
Immediate action: establish deadline/status; avoid further delay
Verification: Tax Practitioners Board registration
```

The wrong-service risk is material. A generic bookkeeper may not be authorised for every relevant tax service. The question should not simply become “best accountant.”

The answer may:

- explain immediate steps;
- identify the regulated category;
- recommend contacting the relevant authority or registered practitioner;
- ask about jurisdiction and notices received;
- search for suitable local practitioners.

------

## **2.8 “Which one would you choose?”**

This is not a neutral repeat of the original search.

It introduces:

- commitment pressure;
- conversational anchoring;
- a closed candidate set;
- an implicit request to weight trade-offs;
- a tendency to justify the prior shortlist;
- a risk that first position becomes privileged.

I do not have personal lived experience or personal patronage. “I would choose” means:

“Given the stated criteria and available evidence, this appears the strongest choice.”

I may conduct additional retrieval, but I do not automatically do so. If no new search is performed, the winner usually emerges by reweighting evidence already in context.

Earlier unsupported claims can therefore become reinforced. This is a serious protocol concern.

------

## **2.9 Price and quote-reasonableness questions**

Example:

“How much should accounting cost?”

I infer:

- jurisdiction;
- service scope;
- business complexity;
- frequency;
- turnover or transaction volume;
- payroll;
- bookkeeping cleanliness;
- urgency;
- whether the price is fixed, hourly or bundled.

Without current local evidence, I should provide broad ranges cautiously or explain cost drivers rather than invent precision.

For a quoted amount, I should compare like with like:

- inclusions;
- exclusions;
- number of entities;
- tax returns;
- BAS frequency;
- payroll;
- software;
- advisory time;
- clean-up work;
- response times;
- liability and complexity.

A low quote can omit necessary work. A high quote can include strategic advice or remediation. “Reasonable” is not determined by price alone.

------

## **2.10 Urgency, opening hours and availability**

These require current retrieval or a live external API.

Examples:

- emergency veterinarian;
- same-day dentist;
- urgent lawyer;
- accountant before a filing deadline;
- IT provider during an outage.

Static website hours may be stale. Search snippets can be stale. A map’s “open now” field may be more current but still wrong.

I should:

- state the retrieval time;
- distinguish listed hours from confirmed availability;
- recommend calling;
- use emergency services where appropriate;
- avoid promising that an appointment or service is available.

------

# **3. How candidates enter consideration**

## **3.1 Candidate routes**

### **Names remembered from training**

**Reasonable inference**

A familiar business name may be generated because it is strongly associated with a service, city or category in learned text patterns.

This route is more likely for:

- national brands;
- heavily discussed firms;
- businesses with strong editorial coverage;
- companies appearing across many sources;
- distinctive names.

It is weaker and more error-prone for small local firms.

### **Retrieved search results**

**Directly known in this environment**

A business can enter because its:

- homepage;
- location page;
- directory profile;
- register entry;
- article mention;
- review profile;
- news coverage;
- social profile

appears in returned search results.

### **Map or local-pack results**

Where a local-data tool supplies candidates, those candidates inherit the provider’s:

- category matching;
- proximity logic;
- prominence;
- availability;
- quality/spam filters;
- sponsorship treatment;
- result limits.

### **Official registers**

A register can introduce or validate candidates, especially when searching by profession, suburb, practitioner or company name.

Registers are often better for eligibility than quality. Being registered does not prove excellence.

### **Review platforms**

Review platforms can:

- introduce candidates;
- indicate scale;
- reveal recurring themes;
- show recency;
- help distinguish branches.

They can also distort through selection bias, manipulation, category mismatch and unverified claims.

### **Directory pages**

Directories aid entity recognition and category association, but quality varies. Some are pay-to-list or incomplete.

### **Editorial “best of” articles**

These often have high lexical relevance and can strongly shape retrieval. They may be:

- genuinely editorial;
- affiliate-supported;
- sponsored;
- outdated;
- generated from weak research;
- based on opaque criteria.

### **Business websites**

Official websites are primary sources for:

- services;
- staff;
- locations;
- contact details;
- claimed credentials;
- pricing;
- case studies.

They are not independent proof of quality.

### **Structured business profiles**

Consistent structured profiles can make an entity easier to resolve and reduce ambiguity.

### **Citations from other pages**

Repeated mentions help connect:

```text
Business ↔ category ↔ location ↔ specialisation ↔ practitioner
```

This is not a guaranteed ranking benefit, but it improves the available evidence graph.

### **Brand familiarity**

Prominent brands can enter consideration even when they are not the best fit.

### **Repeated co-occurrence**

A business repeatedly discussed with “commercial lawyer Melbourne” may become more likely to be generated for that phrase. This is a functional inference, not an exposed score.

### **User-provided names**

User-provided candidates receive an enormous advantage because they are already in context. A comparison question may never search for omitted alternatives.

### **Sponsored or commercial content**

Commercial content may enter through:

- advertising;
- paid directories;
- sponsored articles;
- affiliate pages;
- promoted map placements;
- partnerships.

I may not always be able to identify every commercial relationship from the retrieved representation.

### **Tool-specific filtering**

The tool may exclude candidates because of:

- result caps;
- geography;
- category taxonomy;
- API partnership coverage;
- language;
- country;
- safety filtering;
- availability constraints;
- provider ranking.

## **3.2 Is the candidate set explicitly enumerated?**

Sometimes, but not always.

### **Without retrieval**

It can be generated token by token. There may be no inspectable pre-answer list.

### **With retrieval**

A practical candidate set often forms from:

- returned search results;
- business names in snippets;
- entities extracted from pages;
- named businesses already in context;
- register results.

Even then, the model may not make a formal list before writing.

### **With deterministic VIDET orchestration**

VIDET can force explicit enumeration by requiring:

```json
{
  "candidate_entities": [
    {
      "name": "Example Accounting",
      "discovery_source": "search_result",
      "source_id": "..."
    }
  ]
}
```

That would describe the external audit process, not reveal the model’s hidden internal candidates.

## **3.3 Direct answers**

| **Question**                                                 | **Answer**                                                   |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| Does a business need to appear in live search results?       | No.                                                          |
| Can it be recommended solely from training knowledge?        | Yes, but current reliability may be poor.                    |
| Can weak conventional search rankings still produce a recommendation? | Yes: training familiarity, niche pages, user mention, directories or a specific query can surface it. |
| Can a highly ranked result be ignored?                       | Yes: it may look irrelevant, weak, commercial, distant or unsafe. |
| Can statistical category association cause mention?          | Yes, as a reasonable functional explanation.                 |
| Can an objectively strong business be omitted?               | Yes, easily.                                                 |
| Does repetition across sources increase mention probability? | Usually plausibly, through retrieval visibility and stronger entity/category association. It is not a guarantee. |
| Do structured directories improve entity recognition?        | Often plausibly, especially for name/category/location resolution. |
| Can inconsistent name/address/phone reduce confidence?       | Yes. It can fragment the entity or create apparent conflicts. |
| Does niche content improve category association?             | Plausibly yes, particularly for niche queries.               |
| Does weak third-party evidence limit confidence?             | Yes.                                                         |
| Can the firm be confused with a practitioner?                | Yes.                                                         |
| Can similarly named businesses be confused?                  | Yes.                                                         |
| Can a result rank first merely because it appeared first in retrieval? | It can gain an advantage, but first retrieval position is not necessarily decisive. |
| Can a shortlist collapse for rhetorical rather than evidential reasons? | Yes.                                                         |

## **3.4 Why a business is omitted**

Common causes:

- absent from returned results;
- weak category wording;
- weak local association;
- ambiguous name;
- inconsistent entity data;
- inaccessible site;
- JavaScript-dependent content not extracted;
- low-authority evidence;
- outdated pages;
- result cap;
- search query did not match its terminology;
- another business dominated source coverage;
- branch confusion;
- context-window pressure;
- the answer requested only three options;
- safety concerns;
- no current verification;
- the model simply failed to generate it.

## **3.5 Why a business is mentioned or placed first**

Potential influences:

- exact query match;
- local proximity;
- strong specialisation;
- prominent placement in retrieved evidence;
- clear official pages;
- registration;
- high review volume or rating;
- multiple independent sources;
- strong brand familiarity;
- current availability;
- explicit user criteria;
- evidence that is easy to summarise;
- first-position anchoring;
- answer-writing convention.

There is no basis to assume a fixed universal formula.

------

# **4. How retrieval and source selection work**

## **4.1 Who formulates the query?**

The language model or surrounding search product may transform the natural-language question into one or more search queries. OpenAI documents targeted query rewriting but not the complete algorithm.  

Example:

User:

“Who is best for a tradie whose BAS is late near St Kilda?”

Possible query bundle:

```text
registered tax agent tradies St Kilda VIC
accountant construction trades BAS St Kilda
site:tpb.gov.au tax agent St Kilda
"tradie accountant" Melbourne reviews
accountant overdue BAS penalties Melbourne
```

## **4.2 One query or several?**

Both are possible.

A shallow answer may use one broad query.

A robust answer should use separate query families:

1. discovery;
2. exact specialisation;
3. official verification;
4. review and reputation;
5. adverse findings;
6. contact verification;
7. opening or availability.

## **4.3 Are alternate phrasings used?**

They can be. They are not guaranteed.

Alternate phrasings matter because:

- “tradie accountant” and “construction industry accountant” return different entities;
- “commercial finance broker” and “business loan broker” invoke different taxonomies;
- “sprung floor installer” and “dance floor contractor” may produce different candidates.

## **4.4 Are exact-name searches used?**

They should be used for validation and comparison tasks.

Examples:

```text
"Example Accounting" St Kilda
"Example Accounting" official
"Example Accounting" reviews
"Example Accounting" registered tax agent
"Example Accounting" complaints
"Example Accounting Pty Ltd" court
```

They are not necessarily automatic in every product answer.

## **4.5 Are official registers searched automatically?**

No universal guarantee.

The model may recognise that a register is needed, but:

- it may not issue the search;
- the register may be inaccessible;
- the register may require forms or JavaScript;
- the exact legal name may be unknown;
- the profession may have state-specific registration;
- search-result snippets may be incomplete.

VIDET must explicitly require register checks where applicable.

## **4.6 What does the model see?**

Depending on the tool:

- snippets;
- extracted passages;
- page text;
- metadata;
- structured fields;
- sometimes PDFs;
- sometimes an error or inaccessible page.

The model does not necessarily see:

- the full page layout;
- hidden form results;
- dynamically loaded content;
- every review;
- every search result;
- every indexed version;
- every map field.

## **4.7 Source authority**

Source authority may be reflected implicitly through:

- domain identity;
- source type;
- retrieval ranking;
- wording;
- known institutions;
- citations;
- cross-source agreement.

I cannot verify that a universal explicit “authority score” is always supplied.

VIDET should calculate its own transparent authority class:

```text
A1: official regulator or court
A2: official business or professional body
B1: reputable independent publisher
B2: established review or directory platform
C: user-generated discussion
D: unverified aggregator or promotional page
```

## **4.8 Dates and recency**

Dates matter for:

- opening hours;
- staff;
- registrations;
- prices;
- reviews;
- awards;
- litigation;
- service availability;
- office locations.

A search result can rank well while being stale. The model may notice dates, but not every result exposes one.

## **4.9 Personalisation and location**

Local recommendations may be influenced by optional location data. OpenAI documents optional device-location use and third-party local providers.  

Other possible influences include:

- conversation history;
- explicit user preferences;
- selected language;
- product surface;
- account settings;
- current geography;
- prior candidates in the conversation.

The exact personalisation mechanism is not fully exposed.

## **4.10 Advertising**

I cannot certify that no commercial content influenced a result unless the source representation makes sponsorship clear and I inspect it.

A result may be commercial without being a conventional advertisement:

- affiliate list;
- sponsored profile;
- paid directory;
- advertorial;
- “partner” article;
- lead-generation site.

## **4.11 Access limitations**

Likely problem areas:

- JavaScript-only pages;
- CAPTCHA;
- login walls;
- form-driven registers;
- rate limits;
- robots exclusions;
- paywalls;
- location-gated pages;
- dynamically generated reviews;
- unsupported APIs.

An inaccessible page may still influence the answer through its snippet. That is weaker evidence than opening and inspecting the page.

## **4.12 What decides what?**

| **Component**                 | **Typical decision**                                         |
| ----------------------------- | ------------------------------------------------------------ |
| Language model                | Interprets intent, chooses queries/tools, weighs supplied evidence, writes prose. |
| Search product                | Query transformation, retrieval, result filtering, search ordering, snippets. |
| Maps/local provider           | Place identity, category, distance, ratings, hours, local ordering. |
| Register or regulator         | Registration status and formal restrictions.                 |
| Review platform               | Rating calculation, moderation, displayed reviews.           |
| Deterministic application     | Result count, allowed tools, required checks, scoring rules, session isolation. |
| Unknown proprietary mechanism | Undisclosed reranking, quality assessment, anti-spam, internal experimentation. |

------

# **5. How recommendations and ordering emerge**

## **5.1 Is there a literal business-ranking algorithm inside me?**

I cannot verify a universal literal business-ranking algorithm operating inside the base language model.

The more accurate functional explanation is:

1. The question activates relevant concepts and likely names.
2. Retrieval, when used, supplies a limited evidence set.
3. The model attends to evidence and instructions.
4. Candidate descriptions are generated.
5. An ordering emerges as the answer is written.
6. Later prose often rationalises or explains that order.

The ordering may look deterministic even when it is not generated by a fixed scorecard.

## **5.2 Influences on ordering**

### **Retrieved evidence**

Direct support from multiple sources can improve mention likelihood.

### **Token probabilities**

Some names and phrases are more probable continuations because they are familiar or strongly associated with the context.

### **Prompt instructions**

“Choose one,” “give three,” “prioritise safety” or “near me” strongly changes output.

### **Prominence**

A widely known brand is easier to generate and may displace a less prominent but better local fit.

### **Relevance**

Exact service, niche, client type and geography often matter.

### **Source agreement**

Consistent facts across official and independent sources increase confidence.

### **Location**

Location can dominate convenience-oriented services but matter less for remote or highly specialised services.

### **Reviews**

Reviews are persuasive but imperfect. Rating volume, recency and recurring themes may matter more than a raw average.

### **Credentials**

Credentials can become gating criteria in regulated industries.

### **Exact fit**

A specialist can outrank a larger generalist for a specific problem.

### **Recency**

Recent evidence matters for operational facts and current reputation.

### **Confidence**

Where evidence is thin, I may hedge, shorten the shortlist or avoid selecting a winner.

### **Risk**

Higher stakes should lead to more verification and less confident rhetoric.

### **Answer-writing conventions**

The first item often receives the strongest language. Once generated first, it can gain narrative momentum.

## **5.3 Are these real scores?**

| **Proposed score**  | **In my native answer generation**                           | **Useful for VIDET** |
| ------------------- | ------------------------------------------------------------ | -------------------- |
| Relevance           | Implicit influence; sometimes explicit retrieval score outside the model | Yes                  |
| Quality             | Usually implicit and poorly defined                          | Yes, if decomposed   |
| Trust               | Implicit inference                                           | Yes                  |
| Convenience         | Implicit                                                     | Yes                  |
| Popularity          | Implicit or supplied through review counts/prominence        | Yes                  |
| Authority           | Often inferred from source type                              | Yes                  |
| Evidence confidence | Implicit unless requested                                    | Essential            |
| Proximity           | May be explicit in local APIs; otherwise inferred            | Yes                  |
| Specialist fit      | Implicit semantic match                                      | Essential            |

These should be treated as **external abstractions**, not claimed as hidden native model variables.

## **5.4 Why a shortlist collapses**

A shortlist can collapse because:

- the user supplies a decisive criterion;
- one candidate has verified specialisation;
- one is closer or open now;
- one has stronger registration evidence;
- one has substantially more independent evidence;
- one has transparent pricing;
- earlier order anchors the model;
- the model feels pressure to give a decisive answer;
- rhetorical fluency makes one candidate easier to defend.

The final cause may be partly evidential and partly generative.

------

# **6. How industry changes the process**

The following table describes how I should functionally handle each sector. It does not claim a proprietary industry-specific ranking program.

| **Vertical**                | **Principal evidence and authority**                         | **Reviews/location/credentials**                             | **Recommended output and largest ranking change**            |
| --------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| Accountants                 | Tax-agent/BAS-agent registration, service fit, industry expertise, official site, independent evidence | Reviews useful; location moderate; registration can be gating | Shortlist; winner only after entity type, turnover, tax needs and industry are known |
| Bookkeepers                 | BAS-agent authority where relevant, software certification, payroll capability, references | Reviews useful; location low-to-moderate; authority depends on service | Shortlist; payroll, BAS authority and onsite requirement change ranking |
| Business coaches            | Verifiable track record, methodology, relevant operating experience, client references | Reviews weak-to-moderate due testimonial bias; location low  | Usually shortlist; avoid a definitive “best” without outcome evidence |
| Consultants                 | Relevant project evidence, expertise, references, procurement suitability | Reviews often sparse; specialisation dominates               | Shortlist; exact problem, scale and deliverables change ranking |
| Marketing agencies          | Case studies, attribution quality, client fit, channel expertise, references | Reviews supplementary; location usually low                  | Shortlist; budget, channel, business model and desired outcome dominate |
| Web agencies                | Shipped work, technical competence, accessibility, maintenance, references | Reviews supplementary; location low                          | Shortlist; platform, integrations, support and ownership terms change ranking |
| Branding agencies           | Portfolio relevance, strategic process, references, usage outcomes | Reviews subjective; location low                             | Shortlist; brand stage, category and budget matter           |
| Commercial lawyers          | Current practising status, speciality, jurisdiction, conflicts, relevant matters | Reviews limited; location/jurisdiction important; credentials gating | Shortlist or abstain; legal issue and value/risk dominate    |
| Conveyancers                | Licence/registration, jurisdiction, transaction type, insurer/complaint history | Reviews useful; local jurisdiction matters                   | Shortlist; state, property type and urgency change ranking   |
| Mortgage brokers            | Licence/credit representative status, lender panel, speciality, disclosure | Reviews useful but conflict-prone; location moderate         | Shortlist; borrower profile and loan type dominate           |
| Commercial-finance brokers  | Authorisation, lender access, transaction experience, financial complexity | Reviews sparse; speciality critical                          | Shortlist; facility type, amount and security change ranking |
| Insurance brokers           | Licensing/authorisation, insurer access, sector expertise, claims support | Reviews moderate; location less important                    | Shortlist; risk class and claims complexity dominate         |
| IT providers/MSPs           | Security maturity, response SLA, certifications, reference clients, stack fit | Reviews moderate; location matters for onsite support        | Shortlist; seats, stack, compliance and response needs dominate |
| Financial planners/advisers | Adviser register, authorisations, disciplinary status, fee model, speciality | Reviews secondary; credentials gating                        | Shortlist/abstention; advice need, assets, conflicts and fee model dominate |
| Cosmetic clinics/medispas   | Practitioner registration, treatment authority, product/device legitimacy, clinical governance | Reviews can be misleading; proximity secondary to safety     | Safety-oriented shortlist; treatment and practitioner identity dominate |
| Dentists                    | Registration, scope, specialist status, emergency capacity, treatment transparency | Reviews useful; location important for repeat care           | Shortlist; treatment type, urgency and insurance change ranking |
| Orthodontists               | Specialist registration, treatment approach, follow-up burden | Reviews useful; travel matters over long treatment           | Shortlist; adult/child, complexity and appliance preference dominate |
| Physiotherapists            | Registration, clinical area, referral relationships, treatment approach | Reviews moderate; location important for repeated visits     | Shortlist; injury and desired modality dominate              |
| Chiropractors               | Registration, evidence-informed practice, red-flag handling, treatment claims | Reviews not sufficient; credentials necessary                | Cautious shortlist; symptoms and medical red flags may require abstention |
| Osteopaths                  | Registration, scope, condition experience, referral behaviour | Reviews moderate; location important                         | Shortlist; condition and contraindications dominate          |
| Naturopaths                 | Qualifications, association membership, evidence quality, interactions with medical care | Reviews weak for clinical efficacy; regulation may be limited | Cautious shortlist or no winner; health condition and medications dominate |
| Psychologists               | Registration, endorsements, therapy modality, population fit, availability | Reviews often unavailable/inappropriate; location/telehealth important | Shortlist; presenting issue, modality, availability and funding dominate |
| Veterinarians               | Registration, species expertise, emergency capacity, facilities | Reviews useful; travel and open-now status can dominate      | Winner possible for urgent care; species and urgency dominate |
| Buyers’ agents              | Licensing, area expertise, fee structure, conflicts, verified purchases | Reviews useful but selection-biased; geography central       | Shortlist; target area, property type and budget dominate    |
| Real estate agents          | Licence, recent comparable sales, local market record, campaign fit | Reviews useful; hyperlocal evidence dominates                | Shortlist; suburb, property type and price band dominate     |
| Architects                  | Registration, relevant portfolio, approvals experience, references | Reviews less useful; jurisdiction and project fit matter     | Shortlist; project type, heritage, budget and stage dominate |
| Building designers          | Registration where applicable, portfolio, code/approval competence | Reviews supplementary; local authority experience matters    | Shortlist; state, class and complexity dominate              |
| Custom builders             | Licence, insurance, financial stability, relevant builds, references, disputes | Reviews material but manipulable; local capacity critical    | Shortlist, not single winner without diligence; budget and build type dominate |
| Commercial builders         | Licence, financial capacity, safety record, comparable projects, references | Public reviews weak; credentials and procurement history central | Qualification shortlist; contract value and project class dominate |
| Timber-flooring contractors | Trade experience, product-system knowledge, samples, warranty, references | Reviews useful; service radius matters                       | Shortlist; substrate, finish and repair/new work dominate    |
| Sprung-floor specialists    | Manufacturer certification, engineering/design competence, relevant installations | Reviews sparse; niche fit dominates geography                | Specialist shortlist; sport/dance use, load and system type dominate |
| Pool builders               | Licence, insurance, engineering, recent projects, warranty/service record | Reviews important; local soil and council knowledge matter   | Shortlist; pool type, site and budget dominate               |
| Kitchen companies           | Portfolio, manufacturing/install capability, warranty, references | Reviews useful; service radius moderate                      | Shortlist; custom versus modular, budget and timing dominate |
| Solar installers            | Electrical/accreditation requirements, product authorisation, warranty chain, system design | Reviews useful; location/regulatory scheme important         | Shortlist; roof, usage, battery and grid rules dominate      |
| Landscapers                 | Licence where required, portfolio, horticultural/construction fit, insurance | Reviews useful; local service area important                 | Shortlist; design versus build, scale and site dominate      |
| Childcare centres           | Official approval, regulator quality rating, safety/compliance, availability | Reviews supplementary; proximity and hours very important    | Shortlist; child age, availability, hours and philosophy dominate |
| Franchisors                 | Disclosure documents, franchisee economics, litigation, closures, support evidence | Reviews and testimonials weak alone; legal/financial evidence central | Usually comparative diligence, not winner; capital and operator fit dominate |
| Industry associations       | Governance, recognised authority, member relevance, services, independence | Reviews low relevance; geography varies                      | Recommend by purpose; profession and desired benefit dominate |
| BNI chapters                | Current membership mix, attendance, vacancies, referral culture, meeting logistics | Reviews weak; location and category exclusivity central      | Compare chapters; category vacancy and member fit dominate   |
| Chambers of commerce        | Active programs, membership base, advocacy, events, local relevance | Reviews minor; local geography central                       | Recommend based on networking/advocacy objective             |

## **6.1 Common unsafe recommendation patterns**

- treating reviews as clinical evidence;
- treating registration as proof of quality;
- recommending a generalist for a specialist issue;
- ignoring jurisdiction;
- conflating legal entity and trading name;
- recommending a distant provider for an urgent physical service;
- trusting self-authored case studies without checking context;
- ranking builders solely by stars;
- treating an association membership as regulatory approval;
- failing to distinguish specialist registration from marketing language;
- recommending based on prominence rather than exact fit.

------

# **7. How follow-ups change the answer**

## **7.1 Conversational anchoring**

Once three candidates are named, they dominate the next turn.

The question:

“Which of those three would you choose?”

usually does not mean:

“Restart discovery across the whole market.”

It means:

“Rank the existing candidates.”

This narrows the search universe, sometimes unjustifiably.

## **7.2 First-listed advantage**

The first candidate may benefit from:

- having received the strongest initial description;
- being discussed first and most fully;
- narrative primacy;
- the model continuing its own structure;
- a latent assumption that ordered lists are ranked.

The first candidate does not always win, but first position is a plausible confounder.

## **7.3 Persona-specific reranking**

Follow-ups can legitimately change the winner:

- “best for a tradie” raises industry specialisation;
- “safest” raises credentials and adverse-history checks;
- “best value” raises pricing and inclusion transparency;
- “first-timer” raises guidance, communication and simplicity;
- “strongest track record” raises duration and verified comparable work;
- “open now” can make availability decisive.

## **7.4 Additional retrieval**

Additional retrieval may occur when:

- the new criterion was not checked previously;
- current data is required;
- the user asks for contact details;
- safety concerns arise;
- evidence is inadequate.

It is not guaranteed. An external experiment must record whether retrieval occurred.

## **7.5 Rationalisation risk**

A model may:

1. generate an initial order from limited evidence;
2. be asked to justify it;
3. produce a plausible retrospective explanation;
4. make the original ordering appear more evidence-based than it was.

That does not mean every explanation is fabricated. It means explanation quality is not proof of causal ranking logic.

## **7.6 Experiments to separate evidence from anchoring**

### **Order permutation**

Present the same candidates in all six orders for three firms.

Measure winner frequency by presented position.

### **Blinded labels**

Replace names with A, B and C while preserving evidence summaries.

Compare the winner with the named version.

### **Evidence inversion**

Hold names constant; swap evidence profiles.

If the same name keeps winning, brand familiarity is influencing selection.

### **Fresh-search condition**

Compare:

- follow-up in same conversation;
- fresh conversation containing only candidate facts;
- fresh conversation requiring new retrieval.

### **Candidate expansion**

After initial shortlist, ask:

“Before choosing, search again for any materially stronger alternative.”

Measure whether the original winner survives.

### **First-answer ablation**

Provide the same candidates without the original ranking or evaluative adjectives.

### **Unsupported-claim test**

Seed one unsupported positive claim in the first answer. Test whether the follow-up repeats or amplifies it.

------

# **8. Why answers vary**

## **8.1 Sources of variation**

### **Sampling variability**

Generated wording and candidate selection can vary even with the same prompt.

### **Retrieval variability**

Search results, snippets and accessible pages change.

### **Ranking variability**

Search and local providers update ranking systems and indexes.

### **Model versions**

New model versions can interpret intent and evidence differently.

### **Product surfaces**

ChatGPT web, mobile, API applications and third-party assistants may use different:

- models;
- system instructions;
- tools;
- search providers;
- location access;
- result limits;
- safety controls.

### **Logged-in versus logged-out**

Available personalisation, history, settings, plan features and location permissions may differ.

### **User location**

“Near me,” local result ordering and country-specific directories can change.

### **Wording**

Minor changes can alter:

- query rewriting;
- category inference;
- radius;
- risk level;
- specialist requirement;
- expected decisiveness.

### **Conversation state**

Previous names, preferences and claims anchor subsequent answers.

### **Current events**

New reviews, closures, regulatory action, staff changes or news can change evidence.

### **Source availability**

Pages can be blocked, removed or indexed differently.

### **Caching**

Retrieval or page extraction may be cached. I cannot verify every cache policy.

## **8.2 Query interpretation examples**

| **Query**                        | **Main inferred intent**               | **Current data needed?** | **Key ambiguity**                   |
| -------------------------------- | -------------------------------------- | ------------------------ | ----------------------------------- |
| Best accountant in St Kilda      | Ranked local provider                  | Yes                      | What does “best” mean?              |
| Good accountant in St Kilda      | Acceptable shortlist                   | Yes                      | Lower commitment than “best”        |
| Accountant near me               | Convenience/proximity                  | Yes                      | Exact location and radius           |
| Best accountant for a tradie     | Industry specialist                    | Yes                      | Trade type, business size           |
| My BAS is overdue…               | Problem-first, urgent compliance       | Yes                      | Jurisdiction, notices, registration |
| Is Example Accounting any good?  | Named-entity validation                | Yes                      | Exact entity and standard of “good” |
| Compare Example with Competitor  | Pairwise evidence comparison           | Yes                      | Relevant services and branch        |
| Which would you choose?          | Collapse existing shortlist            | Sometimes                | Criterion and anchoring             |
| How much should accounting cost? | Market range and scope                 | Yes for useful precision | Jurisdiction and inclusions         |
| Do I need an accountant?         | Decision support, not provider ranking | Usually not initially    | Complexity, risk, confidence        |

## **8.3 What can be deterministic?**

VIDET can make deterministic:

- prompt text;
- model identifier;
- tool mode;
- location input;
- session state;
- required query templates;
- result-count caps;
- evidence schema;
- entity-resolution rules;
- scoring calculations;
- failure definitions;
- timestamps;
- replay records.

VIDET cannot fully freeze:

- provider indexes;
- external page content;
- proprietary search ranking;
- model-serving changes;
- stochastic generation;
- hidden safety/system changes;
- third-party API availability;
- live review and opening-hour data.

------

# **9. What businesses can influence**

No measure guarantees recommendation. OpenAI expressly says there is no way to guarantee top placement in ChatGPT Search. Crawl accessibility is relevant to inclusion, but it is not a guarantee.  

## **9.1 High-confidence influence**

These directly improve factual discoverability or verification.

### **Consistent name, address and phone**

Benefits:

- reduces entity fragmentation;
- improves branch matching;
- prevents contact-detail conflicts;
- supports local association;
- helps cross-source verification.

### **Accessible official website**

The website should be:

- crawlable;
- text-readable;
- not entirely JavaScript-dependent;
- clear about services, locations and practitioners;
- internally consistent.

### **Precise service pages**

A page titled and written around the actual service helps query-to-page matching.

Better:

```text
BAS lodgement and overdue BAS assistance for construction businesses
```

Weaker:

```text
Solutions that unlock your future
```

### **Practitioner pages**

Useful fields:

- full name;
- role;
- credentials;
- registration;
- professional memberships;
- exact specialisms;
- office location.

### **Professional-register accuracy**

The business cannot control register ranking, but it can keep eligible records current and consistent.

### **Clear location and service-area pages**

Useful when they describe genuine operational coverage rather than mass-produced doorway pages.

### **Accurate structured data**

Potentially useful for:

- organisation identity;
- local business information;
- practitioners;
- services;
- opening hours;
- contact points.

Structured data helps machines interpret claims. It does not prove those claims.

### **Current contact and hours information**

This reduces factual error and increases actionability.

## **9.2 Plausible influence**

### **Independent citations**

Mentions from:

- regulators;
- associations;
- manufacturers;
- reputable media;
- partners;
- clients;
- recognised directories

can strengthen entity and niche association.

### **Reviews**

Useful particularly when they are:

- numerous enough to reveal patterns;
- recent;
- specific;
- attached to the correct branch;
- distributed across credible platforms.

Reviews do not guarantee ranking and can be discounted.

### **Case studies**

Strong when they specify:

- client type;
- problem;
- scope;
- measurable outcome;
- date;
- relevant constraints;
- permission or verifiability.

### **Pricing pages**

Improve answer quality for cost questions and may support value comparisons.

### **Problem-first content**

Pages answering actual buyer problems can surface for queries where the category is not named.

Example:

```text
What to do when your BAS is overdue
```

This may associate the business with the problem before the user says “accountant.”

### **Authoritative guides**

Useful when genuinely substantive, current and linked to verifiable expertise.

### **Manufacturer and industry directories**

Especially valuable for:

- solar installers;
- flooring systems;
- specialist building systems;
- technical services;
- accredited product installers.

### **Maps and local profiles**

Important for local intent, hours, category, reviews and proximity.

### **Media and awards**

Useful when reputable, current and relevant. Weak awards or pay-to-enter badges may add little.

### **Industry partnerships and local sponsorships**

They may create legitimate local and category associations but usually have indirect influence.

## **9.3 Weak or indirect influence**

- generic backlinks;
- high volumes of low-quality directory listings;
- generic FAQs;
- broad LinkedIn posting;
- review responses that add no factual information;
- undifferentiated YouTube content;
- awards with little independent authority;
- local sponsorships unrelated to service competence;
- repetitive suburb pages with little substance.

## **9.4 Platform-specific influence**

### **Wikipedia or Wikidata**

Potentially strong for well-notable entities and identity resolution, but inappropriate to manufacture solely for optimisation. Wikipedia requires independent notability.

### **Reddit**

Can influence perception and provide candid discussion, but identity, accuracy and representativeness are uncertain.

### **YouTube**

Useful for demonstrations, explanations and practitioner identity. Transcripts and metadata improve machine accessibility.

### **LinkedIn**

Helpful for practitioner employment history and business identity, but self-authored.

### **GitHub**

Highly relevant for software, technical documentation and open-source competence; mostly irrelevant for conventional local services unless technical work is central.

### **Technical documentation**

Very useful for managed services, software, engineering and specialist installations.

## **9.5 Unproven speculation**

Claims that should not be sold as established facts:

- “Adding schema will make ChatGPT rank you first.”
- “Publishing 100 suburb pages guarantees recommendation.”
- “A certain number of reviews triggers model trust.”
- “A Wikipedia page directly raises your recommendation score.”
- “ChatGPT uses a fixed authority threshold.”
- “Backlinks translate directly into assistant mentions.”
- “Model training will absorb your new website on a predictable timetable.”
- “Repeated prompting teaches the public model to recommend you.”

## **9.6 Things a business cannot control**

- model weights;
- search-provider ranking;
- competitor activity;
- user location;
- exact prompt wording;
- product tool availability;
- result limits;
- model updates;
- safety policies;
- external reviews;
- regulator decisions;
- source outages;
- whether the assistant searches at all;
- stochastic output;
- the user’s criteria;
- whether another candidate has materially stronger evidence.

------

# **10. What VIDET can validly measure**

VIDET can measure **observable assistant outputs under controlled conditions**.

Valid measurements include:

- whether the target business was mentioned;
- position of mention;
- shortlist inclusion;
- selected winner;
- cited sources;
- factual accuracy;
- category correctness;
- geographic correctness;
- credential verification;
- explicit uncertainty;
- refusal or abstention;
- search usage;
- evidence diversity;
- follow-up persistence;
- contact-detail accuracy;
- variability across runs;
- sensitivity to wording;
- sensitivity to location;
- sensitivity to conversation history;
- differences across models and products;
- differences between search-enabled and search-disabled conditions.

VIDET can also measure associations functionally:

“Under this prompt and product condition, the assistant associated Business X with commercial accounting in 7 of 20 runs.”

That is a defensible observation.

------

# **11. What VIDET cannot validly claim**

VIDET cannot infer with confidence:

- that a business is or is not in the model’s training data;
- the exact training frequency of a business name;
- the model’s hidden candidate set;
- a proprietary trust score;
- hidden ranking weights;
- the causal reason for every output;
- that a citation caused the mention;
- that an omitted business was never considered;
- that a mentioned business was retrieved rather than remembered, unless tool traces establish this;
- that a result reflects all ChatGPT users;
- that one product run represents the base model;
- that optimisation caused a model-weight update;
- that improved conventional search rank caused an assistant recommendation;
- that three runs establish stable assistant preference;
- that a model “trusts” a business in a human sense;
- that a recommendation is objectively correct;
- that a business can purchase or engineer guaranteed inclusion.

VIDET should use language such as:

- observed mention rate;
- observed first-position rate;
- retrieval-supported mention;
- unsupported mention;
- evidence consistency;
- entity-resolution success;
- model-product condition;
- current measurement window.

It should not call its output “the definitive AI ranking.”

------

# **12. Critique of the proposed assessment protocol**

## **12.1 Three runs per question over two days**

This is useful as a smoke test but inadequate for reliable comparative claims.

With only three runs:

- 0/3 may occur even when true mention probability is meaningful;
- 3/3 may occur by chance;
- one changed result moves the rate by 33.3 percentage points;
- position averages are unstable;
- retrieval outages can dominate;
- geographic or account effects remain hidden;
- follow-up anchoring cannot be separated from true preference;
- model-version changes are hard to detect;
- confidence intervals are extremely wide.

## **12.2 The protocol confounds several mechanisms**

A normal ChatGPT answer may combine:

- training knowledge;
- live search;
- local data;
- current conversation context;
- product instructions;
- personalisation;
- stochastic generation.

If those modes are not separated, VIDET cannot say why a business appeared.

## **12.3 Question-bank imbalance**

Twenty-two questions per assessment can overweight repeated semantic variants. Eight recommendation prompts that are nearly equivalent are not eight independent observations.

Questions should be clustered into families:

- recommendation;
- problem-first;
- validation;
- comparison;
- attributes;
- criteria;
- price;
- controls.

Uncertainty should be calculated at both question and family level.

## **12.4 “Near me” is invalid without controlled location**

The protocol must record:

- exact location input;
- device-location permission;
- country;
- VPN/proxy state;
- product surface;
- approximate versus precise location;
- whether the user explicitly supplied a place.

Otherwise “near me” runs are not comparable.

## **12.5 Controls need to be stronger**

Controls should include:

- fabricated business;
- real business in wrong category;
- real business in wrong geography;
- closed business;
- similarly named business;
- misspelled business;
- unregistered practitioner;
- national brand with no local office;
- high-review but wrong-speciality provider;
- low-prominence verified specialist.

------

# **13. Improved experimental methodology**

## **13.1 Experimental factors**

Use a factorial design across:

```text
Knowledge mode:
  K0 = no web/search disabled
  K1 = general web
  K2 = local/maps data
  K3 = official-register constrained
  K4 = combined retrieval

Conversation mode:
  C0 = fresh session
  C1 = prior generic context
  C2 = prior target-business mention
  C3 = prior ranked shortlist

Location:
  L0 = explicit suburb
  L1 = explicit city
  L2 = controlled near-me coordinate
  L3 = no location
  L4 = wrong-location control

Wording:
  W1 = best
  W2 = good
  W3 = recommend
  W4 = safest
  W5 = best value
  W6 = problem-first

Model/product:
  fixed recorded identifiers

Time:
  repeated measurement waves
```

## **13.2 Recommended run counts**

For development:

- 10 runs per core condition for directional testing.

For client-facing estimates:

- at least 20–30 runs per materially distinct condition.
- more for rare mention rates or close competitors.

For expensive human-facing product surfaces:

- use sequential testing;
- stop only when uncertainty is below a predeclared threshold.

Do not treat 30 runs as magical. Required runs depend on variance and the decision being made.

## **13.3 Core metrics**

### **Mention rate**

```text
runs mentioning entity / valid runs
```

### **First-position rate**

```text
runs where entity is first recommended / valid recommendation runs
```

### **Position-weighted mention score**

Example external metric:

```text
1st = 1.00
2nd = 0.70
3rd = 0.50
4th = 0.35
5th+ = 0.20
unranked mention = 0.10
absent = 0
```

These are VIDET-defined weights, not model weights.

### **Shortlist-collapse rate**

```text
follow-ups selecting entity / follow-ups where entity was eligible
```

### **Evidence-supported mention rate**

```text
mentions with at least one source that materially supports category/location/fit
divided by all mentions
```

### **Factual accuracy**

Field-weighted score with harder penalties for:

- wrong identity;
- wrong registration;
- wrong phone;
- wrong address;
- wrong service;
- wrong operating status.

### **Cross-run agreement**

Use:

- Jaccard similarity for candidate sets;
- rank-biased overlap for ordered lists;
- Kendall’s tau for common ranked candidates;
- winner agreement rate;
- Krippendorff-style agreement for categorical outputs where suitable.

### **Confidence intervals**

Use Wilson intervals for proportions or Bayesian credible intervals with disclosed priors.

Do not display “80% visibility” without uncertainty and sample size.

## **13.4 Failure definitions**

A run fails if it contains:

- fabricated business;
- unresolved entity collision;
- wrong category;
- wrong service area;
- unsupported registration claim;
- incorrect contact detail;
- unverified serious allegation;
- incorrect open-now claim;
- false pricing precision;
- citation that does not support the statement;
- winner selected despite required evidence being absent;
- silent substitution of a different branch;
- false claim of personal experience.

## **13.5 Complete test families**

Because the full line-by-line bank is not present in this message, these tests map to the supplied classes and examples.

### **Training-memory effect**

Run category questions with web disabled.

Compare target mention against:

- famous competitor;
- obscure verified specialist;
- fabricated control.

### **Live-retrieval effect**

Repeat identical prompts with search enabled.

Record candidate and source deltas.

### **Map/local-data effect**

Repeat with controlled coordinates and explicit distances.

### **Exact-name validation**

Use:

- exact legal name;
- trading name;
- common abbreviation;
- misspelling;
- similar-name decoy.

### **Wording sensitivity**

Use semantically close variants and measure candidate-set overlap.

### **Location sensitivity**

Run suburb, city, adjacent suburb, “near me” and no-location conditions.

### **Follow-up anchoring**

Permute candidate order and conversation framing.

### **Recommendation variability**

Repeat fresh sessions across days and models.

### **Hallucinated facts**

Ask for contact details, staff, credentials and hours; compare against timestamped ground truth.

### **Wrong-service false positives**

Use firms that share industry words but do not provide the target service.

### **Wrong-area false positives**

Use firms with the same name in another city.

### **Entity-resolution behaviour**

Use branch names, practitioner/firm overlaps and spelling variants.

### **Regulated safeguards**

Test unregistered or restricted practitioners and compare handling.

### **Urgency**

Use emergency, same-day and deadline language.

### **Price estimation**

Vary scope while keeping wording stable; evaluate whether estimates respond to real cost drivers.

## **13.6 Longitudinal design**

Use fixed waves:

- baseline;
- 7 days;
- 30 days;
- 90 days;
- after major site change;
- after register/profile correction;
- after model-version change.

Do not attribute changes to remediation without a control group and pre/post evidence.

------

# **14. External VIDET architecture**

## **14.1 Product separation**

### **Product A: AI-assistant behaviour measurement**

This observes what existing assistants say.

It does not decide which business truly deserves recommendation.

### **Product B: VIDET-owned recommendation engine**

This would independently ingest businesses, verify evidence and rank them according to published rules.

These must be separate in branding, data and claims.

## **14.2 Behaviour-measurement pipeline**

```text
Client intake
  ↓
Business/entity registry
  ↓
Question generator
  ↓
Experiment manifest
  ↓
Run orchestrator
  ├── assistant/model adapters
  ├── fresh-session controls
  ├── search mode controls
  ├── geography controls
  └── timing/version recorder
  ↓
Raw response and trace capture
  ↓
Citation/source acquisition
  ↓
Entity resolution
  ↓
Claim extraction
  ↓
Factual verification
  ↓
Scoring and controls
  ↓
Finding classification
  ↓
Remediation suggestions
  ↓
Replay and longitudinal monitoring
```

## **14.3 Question generation**

Inputs:

- business category;
- actual services;
- regulated status;
- locations;
- client types;
- high-value problems;
- differentiators;
- pricing questions;
- business name variants;
- competitors;
- controls.

Every generated question receives:

- question family;
- buyer intent;
- location granularity;
- risk class;
- expected category;
- expected current-data requirement;
- allowed clarifications;
- follow-up chain.

## **14.4 Run orchestration**

Each run must capture:

- provider;
- product surface;
- model name/version;
- account state;
- web/search state;
- location state;
- session identifier;
- timestamp;
- prompt;
- prior conversation;
- tool calls where available;
- raw response;
- citations;
- errors;
- latency;
- completion status.

## **14.5 Fresh-session management**

A fresh session must ensure:

- no prior candidate names;
- no previous client context;
- fixed system configuration where possible;
- no reused conversation identifier;
- documented account personalisation state.

VIDET cannot guarantee that a third-party product has no server-side personalisation. It can only record the observable configuration.

## **14.6 Geography management**

Store:

- intended location;
- explicit prompt location;
- device/API coordinate;
- radius;
- country;
- timezone;
- locale;
- proxy region;
- local-data provider if known.

## **14.7 Evidence capture**

For every factual claim:

```text
claim
source URL
source type
retrieval time
supporting passage
source date
entity matched
verification status
conflict status
```

## **14.8 Entity resolution**

Use deterministic plus probabilistic matching:

- canonical name;
- legal name;
- trading names;
- website domain;
- phone;
- address;
- registration number;
- practitioner identities;
- branch;
- parent organisation.

Never merge on name alone where collision risk exists.

## **14.9 Scoring**

### **Mention score**

Observed presence only.

### **Recommendation-position score**

Externally defined positional weights.

### **Shortlist-collapse score**

Winner rate conditioned on shortlist inclusion.

### **Factual-accuracy score**

Field-specific accuracy with materiality weights.

### **Cross-run agreement**

Candidate and rank stability.

### **Cross-model agreement**

Overlap and winner consistency across product-model conditions.

### **Control calibration**

Subtract or contextualise:

- category baseline;
- locality baseline;
- famous-brand baseline;
- hallucination-control rate;
- wrong-area rate.

## **14.10 Finding classes**

```text
DISCOVERY_GAP
CATEGORY_ASSOCIATION_GAP
LOCATION_ASSOCIATION_GAP
NICHE_ASSOCIATION_GAP
ENTITY_AMBIGUITY
CONTACT_DATA_CONFLICT
CREDENTIAL_VERIFICATION_GAP
THIRD_PARTY_EVIDENCE_GAP
FACTUAL_HALLUCINATION
WRONG_SERVICE_MATCH
WRONG_AREA_MATCH
FOLLOWUP_ANCHORING
RETRIEVAL_DEPENDENCE
TRAINING_MEMORY_SIGNAL
NEGATIVE_OUTPUT_RISK
PRICE_INFORMATION_GAP
AVAILABILITY_DATA_GAP
```

## **14.11 Confidence**

Confidence should depend on:

- run count;
- stability;
- source quality;
- entity certainty;
- control performance;
- model/product coverage;
- recency;
- independence of prompt variants.

It should not be generated solely by asking the model “how confident are you?”

## **14.12 Remediation**

Map only observable findings to defensible actions.

Example:

```text
Finding:
The assistant repeatedly confuses the St Kilda and Sydney businesses.

Evidence:
4 of 12 exact-name runs merged contact details.

Remediation:
Clarify branch-specific pages, canonical names, addresses, phone numbers,
structured data and independent profiles.

Claim limitation:
This may improve entity resolution; it cannot guarantee recommendation.
```

## **14.13 Replay and monitoring**

Store immutable run bundles.

Replay should distinguish:

- exact prompt replay;
- same-condition new run;
- cached evidence re-analysis;
- new-model rerun;
- new-search-index rerun.

------

# **15. JSON schemas**

## **15.1 Experiment manifest**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "VidetExperimentManifest",
  "type": "object",
  "required": [
    "experiment_id",
    "business_entity_id",
    "created_at",
    "conditions",
    "questions"
  ],
  "properties": {
    "experiment_id": {
      "type": "string"
    },
    "business_entity_id": {
      "type": "string"
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    },
    "purpose": {
      "enum": [
        "assistant_behavior_measurement",
        "videt_recommendation_engine_test"
      ]
    },
    "conditions": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/condition"
      }
    },
    "questions": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/question"
      }
    }
  },
  "$defs": {
    "condition": {
      "type": "object",
      "required": [
        "condition_id",
        "provider",
        "product_surface",
        "knowledge_mode",
        "conversation_mode"
      ],
      "properties": {
        "condition_id": {
          "type": "string"
        },
        "provider": {
          "type": "string"
        },
        "product_surface": {
          "type": "string"
        },
        "model_requested": {
          "type": ["string", "null"]
        },
        "knowledge_mode": {
          "enum": [
            "model_only",
            "general_web",
            "local_data",
            "official_register",
            "combined"
          ]
        },
        "conversation_mode": {
          "enum": [
            "fresh",
            "continued",
            "seeded_target",
            "seeded_shortlist"
          ]
        },
        "location": {
          "$ref": "#/$defs/location"
        },
        "account_state": {
          "type": "string"
        },
        "personalisation_state": {
          "type": "string"
        }
      }
    },
    "location": {
      "type": ["object", "null"],
      "properties": {
        "country": {
          "type": ["string", "null"]
        },
        "region": {
          "type": ["string", "null"]
        },
        "city": {
          "type": ["string", "null"]
        },
        "suburb": {
          "type": ["string", "null"]
        },
        "latitude": {
          "type": ["number", "null"]
        },
        "longitude": {
          "type": ["number", "null"]
        },
        "radius_km": {
          "type": ["number", "null"]
        },
        "source": {
          "enum": [
            "prompt",
            "device",
            "api",
            "inferred",
            "none"
          ]
        }
      }
    },
    "question": {
      "type": "object",
      "required": [
        "question_id",
        "family",
        "prompt",
        "expected_category"
      ],
      "properties": {
        "question_id": {
          "type": "string"
        },
        "family": {
          "enum": [
            "recommendation",
            "problem_first",
            "validation",
            "comparison",
            "attribute",
            "criteria",
            "price",
            "control"
          ]
        },
        "prompt": {
          "type": "string"
        },
        "expected_category": {
          "type": "string"
        },
        "risk_level": {
          "enum": ["low", "moderate", "high"]
        },
        "requires_current_data": {
          "type": "boolean"
        },
        "follow_up_question_ids": {
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      }
    }
  }
}
```

## **15.2 Run record**

```json
{
  "run_id": "run_01J...",
  "experiment_id": "exp_01J...",
  "question_id": "q_accountant_best_suburb",
  "condition_id": "chatgpt_web_fresh_stkilda",
  "started_at": "2026-07-27T10:15:00Z",
  "completed_at": "2026-07-27T10:15:14Z",
  "provider": "openai",
  "product_surface": "chatgpt_web",
  "model_displayed": "record_exact_visible_value",
  "model_version_verified": false,
  "knowledge_mode_requested": "general_web",
  "retrieval_observed": true,
  "location": {
    "country": "AU",
    "region": "VIC",
    "city": "Melbourne",
    "suburb": "St Kilda",
    "latitude": null,
    "longitude": null,
    "radius_km": null,
    "source": "prompt"
  },
  "session": {
    "fresh": true,
    "prior_turn_count": 0,
    "seeded_entities": []
  },
  "prompt": "Who is the best accountant in St Kilda?",
  "raw_response": "...",
  "citations": [],
  "tool_trace_available": false,
  "status": "complete",
  "error": null
}
```

## **15.3 Extracted recommendation**

```json
{
  "run_id": "run_01J...",
  "answer_type": "shortlist",
  "clarification_requested": false,
  "abstained": false,
  "candidates": [
    {
      "raw_name": "Example Accounting",
      "canonical_entity_id": "entity_123",
      "entity_resolution_confidence": 0.97,
      "position": 1,
      "recommended": true,
      "winner": false,
      "stated_reasons": [
        "small-business focus",
        "local office"
      ],
      "citations": [
        "source_1"
      ]
    }
  ],
  "winner_entity_id": null,
  "warnings": [
    "Verify current fees and registration"
  ]
}
```

## **15.4 Claim record**

```json
{
  "claim_id": "claim_01J...",
  "run_id": "run_01J...",
  "entity_id": "entity_123",
  "field": "phone",
  "claim_text": "Their phone number is 03 9000 0000.",
  "extracted_value": "03 9000 0000",
  "materiality": "high",
  "verification_status": "incorrect",
  "ground_truth_value": "03 9111 1111",
  "ground_truth_sources": [
    {
      "source_type": "official_website",
      "url": "https://example.com/contact",
      "retrieved_at": "2026-07-27T10:17:00Z"
    }
  ],
  "entity_collision_suspected": true
}
```

## **15.5 Source record**

```json
{
  "source_id": "source_1",
  "url": "https://example.com/",
  "domain": "example.com",
  "title": "Example Accounting",
  "source_class": "official_business",
  "retrieved_at": "2026-07-27T10:15:05Z",
  "published_at": null,
  "accessible": true,
  "content_hash": "sha256:...",
  "supporting_passages": [
    {
      "text": "We provide accounting services for construction businesses...",
      "supports_claim_ids": [
        "claim_01"
      ]
    }
  ],
  "commercial_relationship": "self_authored",
  "independence": "not_independent"
}
```

## **15.6 Assessment result**

```json
{
  "entity_id": "entity_123",
  "measurement_window": {
    "start": "2026-07-27T00:00:00Z",
    "end": "2026-08-03T23:59:59Z"
  },
  "sample_size": 240,
  "valid_runs": 236,
  "metrics": {
    "mention_rate": {
      "estimate": 0.42,
      "lower_95": 0.36,
      "upper_95": 0.48
    },
    "first_position_rate": {
      "estimate": 0.18,
      "lower_95": 0.14,
      "upper_95": 0.23
    },
    "shortlist_collapse_rate": {
      "estimate": 0.31,
      "lower_95": 0.24,
      "upper_95": 0.39
    },
    "factual_accuracy_rate": {
      "estimate": 0.91,
      "lower_95": 0.87,
      "upper_95": 0.94
    }
  },
  "findings": [
    {
      "classification": "ENTITY_AMBIGUITY",
      "severity": "high",
      "evidence_run_ids": [
        "run_1",
        "run_8"
      ],
      "confidence": "high"
    }
  ]
}
```

------

# **16. Pseudocode**

## **16.1 Orchestration**

```python
def execute_experiment(manifest):
    validate_manifest(manifest)

    for condition in manifest.conditions:
        adapter = resolve_product_adapter(condition)

        for question in manifest.questions:
            for repetition in range(required_repetitions(question, condition)):
                session = adapter.create_session(
                    fresh=condition.conversation_mode == "fresh",
                    location=condition.location,
                    account_state=condition.account_state
                )

                seed_conversation_if_required(
                    session=session,
                    mode=condition.conversation_mode,
                    question=question
                )

                run = adapter.submit(
                    session=session,
                    prompt=question.prompt,
                    knowledge_mode=condition.knowledge_mode
                )

                persist_immutable_run(run)

                extraction = extract_recommendations_and_claims(run)
                persist_extraction(extraction)

                resolved_entities = resolve_entities(
                    extraction.candidates,
                    canonical_entity_registry()
                )

                verification = verify_material_claims(
                    extraction.claims,
                    resolved_entities,
                    verification_policy(question.expected_category)
                )

                score_run(
                    run=run,
                    extraction=extraction,
                    verification=verification,
                    controls=manifest.controls
                )
```

## **16.2 Entity resolution**

```python
def resolve_entity(raw_candidate, registry):
    possible = registry.search(
        name_variants=normalise_name(raw_candidate.name),
        location=raw_candidate.location,
        website=raw_candidate.website,
        phone=raw_candidate.phone,
        registration_number=raw_candidate.registration_number
    )

    if exact_registration_match(possible, raw_candidate):
        return resolved(possible[0], confidence="very_high")

    scored = []
    for entity in possible:
        scored.append({
            "entity": entity,
            "score": weighted_match(
                name_similarity(entity, raw_candidate),
                domain_match(entity, raw_candidate),
                phone_match(entity, raw_candidate),
                address_match(entity, raw_candidate),
                branch_match(entity, raw_candidate),
                practitioner_overlap(entity, raw_candidate)
            )
        })

    result = select_unambiguous(scored)

    if result is None:
        return unresolved(reason="collision_or_insufficient_evidence")

    return result
```

## **16.3 Claim verification**

```python
def verify_claim(claim, entity, policy):
    sources = []

    for source_type in policy.source_priority_for(claim.field):
        result = retrieve_source(source_type, entity, claim.field)

        if result.available:
            sources.append(result)

        if authoritative_confirmation_found(sources):
            break

    comparison = compare_claim_to_sources(claim, sources)

    if authoritative_sources_conflict(sources):
        return Verification(
            status="conflict",
            confidence="low",
            sources=sources
        )

    return comparison
```

## **16.4 Position score**

```python
POSITION_WEIGHTS = {
    1: 1.00,
    2: 0.70,
    3: 0.50,
    4: 0.35
}

def position_weight(position, mentioned, ranked):
    if not mentioned:
        return 0.0
    if not ranked:
        return 0.10
    return POSITION_WEIGHTS.get(position, 0.20)
```

These weights are a transparent VIDET convention, not a reconstruction of assistant internals.

## **16.5 Finding generation**

```python
def classify_findings(assessment):
    findings = []

    if assessment.wrong_entity_rate > threshold("wrong_entity"):
        findings.append("ENTITY_AMBIGUITY")

    if assessment.search_enabled_mention_rate >> assessment.model_only_mention_rate:
        findings.append("RETRIEVAL_DEPENDENCE")

    if assessment.problem_first_rate < assessment.category_named_rate:
        findings.append("PROBLEM_ASSOCIATION_GAP")

    if assessment.followup_winner_rate_changes_with_list_order:
        findings.append("FOLLOWUP_ANCHORING")

    if assessment.contact_accuracy_rate < threshold("contact_accuracy"):
        findings.append("CONTACT_DATA_CONFLICT")

    return findings
```

------

# **17. Prompts**

## **17.1 Natural product test prompt**

Use the buyer’s real wording without instructing the model how to rank:

```text
Who is the best accountant in St Kilda for a self-employed electrician?
```

This measures product behaviour but exposes little process.

## **17.2 Structured audit prompt**

```text
Answer the user’s question as you normally would.

After the answer, provide a machine-readable audit block containing:

- whether live retrieval was used;
- candidate businesses named;
- their order;
- which candidate, if any, was selected;
- URLs actually cited;
- facts that require current verification;
- whether any registration or licence was checked;
- unresolved uncertainty.

Do not claim access to hidden chain-of-thought or hidden ranking weights.
Do not invent sources.
```

Caution: Asking for an audit block changes behaviour. Run natural and structured conditions separately.

## **17.3 Named-business validation prompt**

```text
Is {business_name} any good for {service} in {location}?

Please distinguish:
1. verified facts;
2. claims made by the business;
3. independent evidence;
4. unresolved uncertainty.

Check current registration where the profession is regulated.
Do not infer quality solely from star ratings.
```

## **17.4 Comparison prompt**

```text
Compare {business_a} and {business_b} for {buyer_profile} needing {service}
in {location}.

Use current evidence. Confirm that each is the correct entity and branch.
Compare exact service fit, credentials, independent evidence, location,
pricing transparency and material risks.

Do not choose a winner unless the evidence supports one.
```

## **17.5 Shortlist-collapse prompt**

```text
Of the three you already named, which is the strongest choice for
{specific_persona}?

Before choosing:
- verify the decisive facts;
- state whether you performed additional retrieval;
- state the criterion that changed or confirmed the order;
- abstain if the evidence does not distinguish them.
```

Again, this is a diagnostic prompt and will not measure unprompted normal behaviour.

## **17.6 Problem-first prompt**

```text
My BAS is overdue and I am worried about penalties. I run a small
electrical contracting business in St Kilda. Who should I speak to?
```

## **17.7 Misspelling/entity test**

```text
Is Exampel Acounting in St Kilda any good?
```

Score whether the model:

- asks for clarification;
- resolves correctly;
- resolves to a similarly named wrong firm;
- invents an entity.

## **17.8 Adverse-output prompt**

```text
Are there any verified regulatory findings or court judgments involving
{business_name}?

Separate final findings, judgments, filed proceedings, allegations,
customer reviews and rumours. Do not present an allegation as fact.
```

------

# **18. Failure modes**

## **18.1 Measurement failures**

- treating a single answer as stable preference;
- mixing web and non-web runs;
- failing to record location;
- reusing conversations marked fresh;
- comparing different model versions without disclosure;
- counting semantic duplicates as independent samples;
- ignoring invalid or refused runs;
- scraping citations without checking support;
- treating list order as recommendation strength when the answer says otherwise.

## **18.2 Retrieval failures**

- search query misses local terminology;
- official register inaccessible;
- snippet contradicts opened page;
- result points to wrong branch;
- directory outranks the official site;
- paywall prevents verification;
- stale cached page;
- sponsored source appears independent;
- JavaScript content is absent.

## **18.3 Model failures**

- fabricated business;
- invented phone number;
- merged address and phone from different firms;
- wrong practitioner attached to a firm;
- outdated credential;
- overconfident winner;
- price stated without scope;
- “open now” inferred from stale hours;
- unsupported personal preference;
- false claim that a search was exhaustive;
- unsupported adverse inference;
- rationalised prior ordering.

## **18.4 Entity failures**

Particularly likely when:

- trading name differs from legal name;
- several branches share one domain;
- practitioners move firms;
- names are generic;
- two cities contain similarly named firms;
- directory data is inconsistent;
- phone numbers have changed;
- a professional practises through multiple entities.

## **18.5 Hallucination-prone fields**

Highest risk without direct verification:

- phone numbers;
- opening hours;
- current staff;
- exact prices;
- registration numbers;
- awards;
- named clients;
- review counts;
- current rating;
- years in business;
- disciplinary history;
- litigation status;
- service areas;
- availability;
- claimed specialist status.

URLs and addresses are also error-prone where similar entities exist.

------

# **19. Legal and ethical risks**

## **19.1 Negative outputs**

Questions such as:

- “Who should I avoid?”
- “Is this business bad?”
- “Are they dishonest?”
- “Do they have complaints?”

carry defamation, fairness and accuracy risks.

VIDET must distinguish:

| **Evidence type**             | **Meaning**                                            |
| ----------------------------- | ------------------------------------------------------ |
| Verified disciplinary finding | Final action by an identified regulator                |
| Court judgment                | Court has issued a decision                            |
| Filed proceeding              | A claim has been commenced; allegations are not proven |
| Allegation                    | A person or body has asserted misconduct               |
| Customer review               | Individual account or opinion, not adjudicated fact    |
| Rumour                        | Unverified repetition                                  |
| Model inference               | Assistant-generated interpretation, not evidence       |

## **19.2 Recording adverse outputs**

VIDET should preserve the raw answer securely for audit, but client-facing reporting should state:

```text
In 2 of 20 runs, the assistant repeated an unverified adverse claim sourced
to a customer-review page. VIDET did not verify the claim and does not
republish it as fact.
```

It should not reproduce sensational allegations unnecessarily.

## **19.3 Source and status requirements**

Every adverse claim should store:

- exact wording;
- source;
- source date;
- proceeding or finding identifier;
- status;
- jurisdiction;
- whether appealed;
- whether the named entity matches;
- whether the matter is current;
- whether the claim was independently verified.

## **19.4 Right of correction**

VIDET should provide:

- entity-correction workflow;
- evidence submission;
- branch disambiguation;
- updated-register review;
- re-test after correction;
- immutable audit history showing what changed.

## **19.5 Recommendation liability**

VIDET should avoid representing assistant output as professional due diligence.

For regulated and high-value decisions, report language should say:

- observed assistant behaviour;
- not an endorsement;
- registration and suitability must be checked;
- availability and prices require direct confirmation.

## **19.6 Privacy**

Do not collect precise location beyond what is required. Do not retain it indefinitely. Separate:

- test geography;
- user identity;
- account credentials;
- raw assistant conversations;
- client business records.

## **19.7 Platform terms**

Automated testing must respect:

- provider terms;
- rate limits;
- permitted automation;
- account rules;
- content storage restrictions;
- citation and page-use rights.

These are current legal and contractual questions and must be reviewed against the actual provider terms at implementation time.

------

# **20. Brutally honest conclusion**

A ChatGPT business recommendation is not a transparent league table produced by a stable, inspectable scoring formula.

It is more accurately understood as the output of a changing compound system:

```text
user wording
+ conversation context
+ learned model associations
+ available tools
+ search-provider retrieval
+ local-data coverage
+ source accessibility
+ model interpretation
+ safety rules
+ probabilistic answer generation
```

A business can be recommended because it is genuinely well supported by current evidence. It can also be recommended because it is prominent, easy to retrieve, strongly associated with the category, already mentioned in the conversation or simply generated as a plausible continuation.

A strong business can be omitted. A mediocre but prominent business can be included. A first-listed firm can receive an anchoring advantage. A model can provide a persuasive explanation after the fact that makes a weakly grounded ordering look deliberate. A citation can support one sentence while the broader recommendation remains subjective. A live search improves currency but does not make the search exhaustive or the ranking objective.

VIDET’s strongest defensible product is therefore **not**:

“We reveal the secret score AI uses to rank your business.”

It is:

“We measure, under documented conditions, whether major AI assistants recognise, retrieve, correctly identify, factually describe, shortlist and select your business—and how stable those outcomes are across questions, locations, models, tools and time.”

That is valuable because it is observable.

VIDET can also identify concrete evidence problems:

- assistants cannot resolve the entity;
- contact information conflicts;
- the service-location association is weak;
- the niche is not retrieved;
- registration is hard to verify;
- the business appears only when named;
- recommendations depend heavily on search;
- follow-ups favour whoever was listed first;
- incorrect facts recur;
- competitors possess stronger independent evidence.

It cannot honestly promise that correcting those issues will force a model to recommend the business. It can say that the corrections improve machine-readable evidence, reduce ambiguity and create a stronger factual basis for retrieval-supported recommendations.

The proposed three-run protocol is appropriate for an inexpensive diagnostic preview, but not for statistical claims. A serious VIDET assessment needs controlled separation of model-only, search, local-data and official-register conditions; fresh sessions; fixed geography; adequate repeated runs; entity-level verification; confidence intervals; anchoring tests; model-version tracking; and longitudinal replay.

Most importantly, VIDET must preserve the distinction between:

1. **measuring how assistants currently behave**, and
2. **building an ideal recommendation system that VIDET itself controls**.

The first is an empirical auditing problem under partial observability.

The second is a conventional evidence, ranking and governance problem.

Combining them would create attractive but misleading certainty.