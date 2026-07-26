# Customer Value Constitution

## Document Control

- Status: Accepted
- Version: 1.0.0
- Date: 2026-07-26
- Owner: Founder / Chief Product
- Classification: Governance — Product-Direction Authority
- Scope of Authority: Product-value prioritisation and launch-scope decisions

## Authority Statement

This document governs product-value prioritisation and launch-scope decisions.
It does not independently authorise implementation or override frozen technical,
security, workflow or governance contracts.

Specifically, this constitution **does not** override:

- frozen specifications (`specification/` Foundation 000–020 and Volume I/II);
- Architecture Decision Records ([../DECISIONS.md](../DECISIONS.md));
- `specification/automation/BUILD_STATE.json`;
- `specification/automation/BUILD_PLAN.yml`;
- `specification/automation/AUTONOMOUS_BUILD_CONTROLLER.md`;
- `specification/automation/AUTONOMY_POLICY.md`;
- security and privacy contracts (`specification/014 SECURITY_MODEL.md`,
  `specification/015 DATA_LIFECYCLE.md`);
- state models (`specification/016 STATE_MODEL.md`);
- workflow specifications (`specification/volume-i/WORKFLOW_SPECIFICATIONS.md`);
- accepted tranche contracts (`specification/volume-ii/contracts/`).

Where this document and any authoritative technical, security, workflow or
governance contract appear to conflict, the contract prevails and the conflict
is recorded for owner consideration. This document is revised to remain
product-direction guidance; the contract is not silently altered to match it.

**Authority distinction.** This constitution carries *product-prioritisation
authority* — it decides what customer value is worth building and in what order
before launch. It carries no *technical-implementation authority* — it cannot
authorise a tranche, clear a human gate, define a state transition, relax a
security or privacy control, or mark work complete. Those remain governed by the
contracts named above and by the repository's decision mechanism.

## Purpose

Preserve and enforce a durable product north star so that every proposed tranche,
feature or material addition before the S-09 launch boundary is measured against
customer value, not technical novelty. This document is the reference for
challenging scope, deferring low-value work, and keeping the build pointed at
first paid customer use.

## North Star

Videt is a commercial discoverability intelligence platform that reveals how
intelligent systems perceive a business, where that perception diverges from
verifiable reality, and what actions should be taken to improve it.

Videt is **not** positioned merely as SEO, GEO, or rank tracking. The central
customer questions are:

- Does AI see this business?
- Does AI understand it correctly?
- Does AI recommend it?
- What materially prevents stronger representation?
- What should the business do next?
- Did the intervention measurably change machine perception?

## The Customer-Value Loop

Every capability exists to advance one or more stages of this loop:

1. **OBSERVE** — Collect evidence about how intelligent systems access, interpret
   and represent the business.
2. **ASSESS** — Build a verifiable picture of the organisation and its digital
   reality.
3. **COMPARE** — Detect commercially material differences between business reality
   and machine perception.
4. **INTERVENE** — Prioritise and execute actions capable of closing those
   differences.
5. **LEARN** — Measure outcomes and improve future recommendations through
   accumulated evidence.

The thinnest complete customer-value loop touches all five stages for at least
one real customer, even if narrow. Depth in one stage without a path through the
others does not deliver customer value.

## The Product Intelligence Model

Value is produced by four graphs. Each proposed unit of work should state which
graph it advances.

- **Reality Graph** — What is verifiably true about the organisation, offerings,
  people, locations, capabilities, claims and supporting evidence.
- **Perception Graph** — What machine systems believe, state, cite, omit,
  misunderstand, contradict or recommend.
- **Gap Graph** — Where reality and perception materially diverge, including
  missing, misunderstood, outdated, contradicted, weakly supported or
  commercially limiting representations.
- **Intelligence Graph** — What should be done, why it matters, who owns it,
  through which channel, with what expected impact, evidence, status and measured
  outcome.

## Intended Experiences

- Executive Dashboard
- Gap Analysis
- Intervention Studio
- Intelligence Feed
- Reports and Exports

## Intended Outcomes

- be seen;
- be understood;
- be recommended;
- be tracked;
- improve machine visibility;
- strengthen representation in answers and recommendations;
- reduce material misrepresentation;
- identify commercially meaningful opportunities;
- create measurable commercial impact.

## Mandatory Product-Value Tests

Every proposed tranche, feature or material addition before the S-09 launch
boundary MUST answer "yes" to at least one of the following:

1. Does this allow the customer to discover something material that they could not
   reliably discover previously?
2. Does this make a recommendation materially more useful, credible, specific or
   actionable?
3. Does this improve the truth, completeness, freshness or confidence of the
   Reality Graph?
4. Does this reveal new or better-supported information about machine perception?
5. Does this identify a commercially meaningful difference between reality and
   perception?
6. Does this improve the customer's ability to prioritise, execute, verify or
   measure an intervention?
7. Does this strengthen the evidence chain, measurement trust or
   action-to-outcome learning loop necessary to deliver customer value?

If the answer to all seven is "no", the work MUST be challenged before inclusion
in the pre-launch scope.

## Necessary Enabling Work

Some work creates value indirectly but remains mandatory. It is not exempt from
justification: it MUST state which customer-facing capability it makes safe,
credible or operable. This category includes:

- security;
- privacy;
- tenant isolation;
- evidence integrity;
- immutability;
- reliability;
- idempotency;
- concurrency correctness;
- retention and erasure;
- regulatory or contractual compliance;
- provider-independent boundaries;
- operational recovery;
- trustworthy measurement.

Enabling work that cannot name the customer-facing capability it protects should
be challenged on the same terms as any feature.

## Mandatory Tranche Value Statement

Every planned tranche MUST include one of the following, completed honestly:

> "After this tranche, the customer can now __________, which they could not
> reliably do before."

or:

> "After this tranche, Videt can now produce a materially better recommendation
> because __________."

If neither can be completed honestly, the tranche MUST state the unavoidable
reason it is required before launch (typically a Necessary Enabling Work
justification naming the capability it protects).

## Launch Discipline

The pre-launch scope FAVOURS:

- the thinnest complete customer-value loop;
- verifiable, evidence-backed results over theatrical scores;
- evidence over assertion;
- explicit confidence and uncertainty;
- decision-useful gaps;
- implementable recommendations;
- measurable interventions;
- repeated observation over one-off novelty scans;
- customer-visible proof over architecture theatre;
- bounded and reliable operation;
- direct movement toward paid customer use.

The pre-launch scope CHALLENGES or DEFERS:

- cosmetic dashboard breadth;
- excessive chart variants;
- generic SEO-suite parity;
- abstractions justified only by hypothetical future use;
- unsupported predictive scoring;
- speculative machine learning;
- autonomous production changes before trust and controls exist;
- public marketplaces;
- large partner ecosystems;
- enterprise breadth not required by the launch cohort;
- work that improves technical elegance without improving safety, truth,
  operability or customer value.

## Commercial Truth Standard

Videt must never make unsupported claims. In particular:

- do not claim causal revenue improvement without supporting evidence;
- distinguish observed change from inferred impact;
- expose sampling and provider variability;
- state confidence and limitations;
- preserve evidence and provenance;
- prefer measured truth over persuasive certainty.

A customer-facing deficiency is represented as an `Issue` with a concrete next
step, per `specification/005 PRODUCT_PRINCIPLES.md` (Principle 5). The legacy term
`Finding` is prohibited in product behaviour and customer output. "Evidence" and
"observation" refer to collected material about reality and perception, not to a
deficiency.

## Relationship to Authoritative Contracts

This constitution operationalises, for the pre-launch window, the accepted product
principles already frozen in the manual. It is downstream of and consistent with:

- [PROJECT_CONSTITUTION.md](PROJECT_CONSTITUTION.md) — mission and governance rules;
- `specification/005 PRODUCT_PRINCIPLES.md` — canonical product principles;
- `specification/009 DECISION_FRAMEWORK.md` — how decisions are made and recorded;
- [QUALITY_STANDARD.md](QUALITY_STANDARD.md) — quality gates.

It adds no new technical, security, state or workflow meaning. It restates
existing principles as an enforceable pre-launch prioritisation lens and adds the
Mandatory Product-Value Tests and Tranche Value Statement as gates on *scope
selection only*. Acceptance of any tranche remains governed by the frozen
contracts and the repository's decision mechanism.

## References

- [../CLAUDE.md](../CLAUDE.md)
- [PROJECT_CONSTITUTION.md](PROJECT_CONSTITUTION.md)
- [QUALITY_STANDARD.md](QUALITY_STANDARD.md)
- [WORKFLOW.md](WORKFLOW.md)
- [../DECISIONS.md](../DECISIONS.md) — ADR-048 records the establishment of this document
- [../specification/INDEX.md](../specification/INDEX.md)
- [../specification/005 PRODUCT_PRINCIPLES.md](../specification/005%20PRODUCT_PRINCIPLES.md)
- [../specification/009 DECISION_FRAMEWORK.md](../specification/009%20DECISION_FRAMEWORK.md)
- [../ROADMAP.md](../ROADMAP.md)

## Document History

- 1.0.0 — 2026-07-26 — Established at the WF-003 completion boundary (integration
  tip `c286423`, tag `backup/wf-003-complete`), ahead of S-06–S-09 launch-scope
  planning. Recorded as ADR-048.
