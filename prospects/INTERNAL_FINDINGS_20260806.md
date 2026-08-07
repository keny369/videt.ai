# Internal findings, all ten targets

> **UPDATED 7 AUGUST after live consumer-surface checks. Two specimens failed and were replaced.**
> - **Trident:** the AIBB/CPBB fabrication did **not** reproduce on Claude Sonnet 5 live. That claim is withdrawn and must not be used. What appeared instead is more serious and is **restricted**, see the Trident section.
> - **Buyers Advocate:** the Hawthorn address did **not** reproduce. What appeared instead is stronger and is confirmed live. Hook changed from Wrong to Missing.
> - Both PDFs and both video segments have been rewritten accordingly.

**INTERNAL ONLY. Never sent, never quoted, never shown to a prospect.** 6 August 2026.

Evidence base: 212 API runs (206 clean) across GPT-5.5 and Claude Sonnet 5, both search arms, `operations/probe-harness/evidence/runs.jsonl`. Plus two consumer-surface runs on ChatGPT GPT-5.5 Light, 6 August. Plus manual verification against each firm's own site and ABN Lookup.

**Reading the grades.** SEND = verified finding, safe to approach. CHECK = candidate finding, needs 30 to 60 more minutes of source work first. WELL = performing well, use the contingency conversation, do not manufacture a problem.

| | Target | Cold mentions | Grade |
|---|---|---|---|
| 1 | Trident Business Sales | 6/59, pos 1-4 | **SEND** |
| 2 | Metropole Melbourne | 0/35 | **SEND** |
| 3 | Vision Brokers | 0/59 | **SEND** |
| 4 | Buyers Advocate | domain cited 15/35, entity unresolved | **SEND** |
| 5 | Expert Business Brokers | 0/59 cold | CHECK |
| 6 | Mercury | 5/59, pos 5-8 | CHECK |
| 7 | Melbourne Buyers Advocates | 0/35 cold, domain 9/35 | CHECK |
| 8 | Lloyds Business Brokers | 4/59, pos 2-4 | CHECK |
| 9 | Cate Bakos Property | 10/35, first 5 times | **WELL** |
| 10 | Concierge Buyers Advocates | 7/35, pos 4-7 | **WELL** |

**The universal opener, available to all ten**, is CONF-20260806-001: ChatGPT sourcing a Melbourne buyer's advocate answer partly from the City of Melbourne **Florida**, Florida tourism, an Illinois country club and a page about a dead British prime minister. It names no business, so it is safe with anyone.

---

## 1. Trident Business Sales — SEND, WITH A RESTRICTION

> **RESTRICTED USE, BINDING.** On 7 August 2026, Claude Sonnet 5 (live, claude.ai, search on) answered the entity probe about Trident by surfacing **serious unverified allegations about Brian Budd personally**, sourced from two ProductReview entries, and ran a search on his name plus "court charges". It stated plainly that it could not verify any of it. It also flagged that a LinkedIn profile it found relates to a different, US-based Brian Budd.
>
> **This is the single highest-materiality finding in the entire study and it must never be written down for anyone outside this file.** Not in the PDF, not in an email, not on camera, not in a deck, not in disguised form. Reasons: repeating unverified allegations about a named individual carries defamation exposure regardless of accuracy; Appendix C rule 9 and delivery guide Part 11 both forbid it; and it would be indefensible if it reached anyone but him.
>
> **How it is used:** the PDF and the video say only that something exists which we will not put in writing, and offer to show him privately with the screen in front of him. That is truthful, it is restrained, and it is a far stronger reason for him to take the call than any credential error would have been.
>
> **The AIBB/CPBB finding is withdrawn.** It did not reproduce live. Do not use it.

### Original API finding, superseded

**Principal:** Brian Budd, Director. Carlton VIC 3053. **Strongest single specimen in the study.**

**Presence.** Named in 6 of 59 broker answers, positions 1, 2, 2, 3, 4. When it appears it appears near the top. Absent from the consumer-surface run.

**The specimen. Confirmed.** Claude Sonnet 5, search on, credited Trident with:
> "Australian Institute of Business Brokers (AIBB)" and "Certified Practising Business Brokers (CPBB)"

Their own About page states: *"We are members of the Real Estate Institute of Victoria (REIV), and undertake continuous professional development."* Brian Budd's listed credentials are Director, O I E C, CEA (REIV). **No AIBB. No CPBB. Verified 6 August against their own page.**

Class: authority spoofing. Materiality high: business brokers are chosen on accreditation, and AIBB membership is the sector's main trust signal. A buyer acting on that answer believes Trident holds a credential it does not claim.

**Second, smaller finding.** Two runs reported the same rating, "4.4 stars from 14 reviews", but attributed it to **different sources**: one said Birdeye, one said Google. Same number, two provenances. Illustrates that citation is reconstructed, not retrieved.

**Approach.** Lead with the credential. He is REIV and proud of it; being handed a body he never joined is the kind of error a professional finds personally irritating, which is what gets a reply.

**Risk.** Do not say the AI "claimed he lied". Say it credited him with a membership his own site does not claim. Do not speculate about why.

---

## 2. Metropole Melbourne — SEND

**Principal:** Michael Yardney (group founder). Level 2, 181 Bay Street, Brighton VIC 3186.

**The finding. Confirmed and clean.**
- Named in **0 of 35** buyer's advocate answers.
- The word "Yardney" appears in **0 of 35**.
- Their Melbourne URL cited **0 of 35**.
- Absent from the consumer-surface run too.

**And yet**, when asked about them directly, the machines described them fully and correctly: founded 1979, offices in Melbourne, Sydney and Brisbane, the exact Brighton address, and a nine-person team list including Mark Creedon as CEO and the two Melbourne buyer's agents.

**This is the cleanest "known but not retrievable" case on the list.** The information exists. It is accurate. It is never reached for. For a man who has built one of Australia's largest property content operations, that is the entire pitch in one sentence, and it is a sentence he will feel.

**Approach.** He is a publisher. He will grasp the retrieval-versus-knowledge distinction in one line, faster than anyone else on this list. Lead with "0 of 35" and the fact that the machines describe him accurately when asked.

**Risk.** Group versus office. Metropole the group is national; you measured the Melbourne question. Say "Metropole Melbourne" and "the Melbourne question" every time, never "Metropole is invisible".

---

## 3. Vision Brokers and Advisors — SEND

**Principal:** none named on their own site. Dan Levitus appears on their socials without a stated title. Head office North Sydney; Melbourne office 305/566 St Kilda Road.

**The finding. Total absence, plus invented specifics.**
- **0 of 59** broker answers. Name and domain both. The only target with a clean zero on every measure.
- Absent from the consumer-surface run.

**When primed, the machines produced three mutually inconsistent ABNs** across runs:
- VISION BROKERS MELBOURNE PTY LTD, ABN 96 677 751 594
- Vision Brokers Pty Ltd, ABN 57 253 499 371
- Vision Brokers Australia Pty Ltd, ABN 29 657 400 783

They cannot all describe the same entity in the same answer set. One run also gave a Sydney address of "Level 32, 101 Miller Street" against the real "Level 25, 100 Mount Street", and produced people not on their site: Tony Selak, Daniel Kogan, Joel Willis, George Sabados, plus bare first names "Lara" and "Ralph".

**Approach.** Absence plus incoherence. The strongest version pairs "you were named zero times in 59 answers" with "and when asked directly, it gave three different ABNs for you".

**Risk.** **Verify each ABN on ABN Lookup before quoting any of them.** At least one may be correct. Quoting a correct ABN as invented is the failure mode that ends the meeting. Also: they are a Sydney-headquartered firm, so "invisible in Melbourne" is fair but "invisible" alone is not.

---

## 4. Buyers Advocate — SEND

**Principal:** Leigh McConnon, Managing Director. 12/1153-1157 Burke Road, Kew VIC 3101. Business founded 1992, he took ownership 2007.

**The finding. The most structurally interesting result in the study.**

Their domain, `buyersadvocate.com.au`, is the **single most-cited source in the entire 212-run study**, appearing in 15 of 35 buyer's advocate answers and 19 runs overall. They publish the "Top 10 Best Buyers Agents in Melbourne" article the machines lean on.

**And when asked directly who they are, 5 of 8 runs said they did not know.**

The machines read their content constantly and cannot identify them as a business. Their name is their category, so they are a source rather than an entity.

**Second finding. Confirmed.** Claude Sonnet 5, search on, placed them in **"Melbourne (Hawthorn, VIC per ZoomInfo)"**. Their own About page states Kew VIC 3101. A wrong location, with a source named for it. Class: citation misattribution plus geographic error. This is the Clutch pattern: the link works, which is why nobody checks.

**Consumer surface.** Named 6th of 6, described as *"Good benchmark even if you don't hire them"*. Positioned as a reference source, not a provider. That is the same finding showing up in the recommendation itself.

**Approach.** "You are the most-quoted source in this category and the machines still can't tell a buyer who you are." That is a genuinely novel thing to be told.

**Risk.** Do not overstate. They *are* named in some answers. The claim is that they are cited far more than they are recommended, and that when asked directly the machines often can't place them.

---

## 5. Expert Business Brokers — CHECK

**Principals:** Sam Vasli **and** Daniel Callegari, both "Business Sales Specialist & Managing Director". Ground Floor, 470 St Kilda Road, Melbourne VIC 3004.

**Correction to our own record.** The target list said "both MDs". I wrongly overrode that from a ZoomInfo profile. **Their own site confirms both hold the title.** The original list was right. Do not repeat my version to anyone.

**Presence.** 0 of 59 cold. Generic name, so automated matching is unreliable and the raw-text count is contaminated by the ordinary word "expert" (21 of 59). Absent from the consumer-surface run.

**The specimen. Confirmed.** Claude Sonnet 5 named a team member **"Toorang"**. No such person appears on their site. Every other name it gave (Sam, Daniel Callegari, Nikki, George, Reza) is real. One fiction inside five facts, same sentence, same confident tone.

**Still to check before sending:** whether the qualifications attributed (MAppFin, BCom, CA, DipFP, Certified Business Valuer) match what each person actually claims. High yield if any are misassigned between people.

**Approach.** Thin marketing, so pain may not register. Rank last. Use as the control on whether measured absence alone converts.

---

## 6. Mercury Business Sales and Valuation — CHECK

**People:** Camil Talj, Gabrielle Zhang, Judy, Azgan, Dana all appear on their own site. Greenwood Business Park, Burwood VIC 3125.

**Presence.** 5 of 59, positions 5 to 8. **Named 5th on the consumer-surface run.** The best-performing broker on your list.

**Correction to our own record.** I hypothesised the machines had invented Mercury's team. **They had not.** Every person named is real. That candidate finding is dead.

**What survives.** Their site assigns **no formal job titles to anyone**. The machines confidently assigned them: "Gabrielle Zhang, Founder & Managing Business Broker", "Camil Talj, Senior Business Broker". Class: attribute invention, roles. Real people, invented hierarchy.

Two runs also gave **conflicting ABNs**: "ABN 97 622 999 259" and "ABN registered from 5 April 2024". And "Fred Zheng, Registered Business Valuer" does not appear on their site.

**Still to check:** the two ABNs on ABN Lookup, whether Fred Zheng exists anywhere, and the AIBB and registered-valuer claims against the AIBB directory.

**Approach.** They are performing reasonably. The honest pitch is "you are being described with a leadership structure you never published", not "you're invisible".

---

## 7. Melbourne Buyers Advocates — CHECK

**Principal:** none designated. Team of four named: Paul Garson, Garvin Pereira, Jason Bell-Davey, Daniel Rees. 1612 High Street, Glen Iris VIC 3146. ABN 59 874 798 373.

**Presence.** 0 of 35 cold by name matching, but the name is the category so this is unusable. Their domain was cited in 9 of 35. Absent from the consumer-surface run.

**Candidate findings, all needing verification:**
- "Paul Garson conveyancing practice established Adelaide 1989"
- "founder of Stonnington Conveyancing"
- "Councillor of the Australian Institute of Conveyancers (Victorian Division) for 8 years"
- "Garvin Pereira A.A.I.C., M.R.E.I."

These are unusually specific, which cuts both ways: highly checkable, and quite likely true. **Check all four before approaching.**

**Structural finding, already solid.** A direct competitor's homepage title is literally "Melbourne Buyers Advocates". Two firms on your own list compete for the same string. That is a retrievability problem you can explain without any error claim.

---

## 8. Lloyds Business Brokers — CHECK

**Principal:** Garry Stephensen, Managing Director and Licensee. Operating since 1984.

**Presence.** 4 of 59, positions 2, 2, 4. Absent from the consumer-surface run.

**Candidate findings:**
- Two runs placed them in **Elsternwick VIC 3185**. Not verified against their site. **Check first.**
- One run described Garry Stephensen as "Managing Director and Licensee, **Greater Brisbane Area**". Placing the principal in the wrong state is high-materiality if wrong.
- AFSL 526061 and "Corporate Authorised Representative under AP Lloyds Pty Ltd" appeared consistently. Checkable on the ASIC register.
- "Rudy Weber, founding Director" and "John Wayland, Senior Associate" need confirming.
- One run gave **no people at all** and self-reported `inferring_from_name_and_category`, meaning it was generating plausible filler.

**No Lloyds Bank or Lloyd's of London conflation appeared.** The predicted famous-name collision did not materialise. Record that as a null.

---

## 9. Cate Bakos Property — WELL

**Principal:** Cate Bakos. Melbourne inner-west.

**Presence. Dominant.** 10 of 35, **first-listed five times**. Named second on the consumer-surface run. 5 of 6 direct probes self-reported `know_this_specific_business`. She is the answer to this question.

**Accuracy is good.** All five staff names the machines gave (Renee Berger, Jade Barnden, Lynn Tran, Emma Mace, Christopher Sybenga) appear on her site with matching roles.

**Two claims worth checking, not yet findings:**
- "Former President of REBAA". Not stated on the About page checked. May well be true elsewhere. **Do not call this fabricated without checking her full site and REBAA's.**
- "5.0 rating from 418 reviews". Not on the page checked. Very specific, so likely sourced from somewhere real.
- Award described as "Your Investment Property Top Buyer's Agent of 2018" in one run against the site's own 2018 award wording. Worth a look.

**Approach.** This is the Appendix F contingency, verbatim: *"That's one answer, today, phrased one way."* The honest pitch to the category leader is fragility, not absence: she is first five times out of ten appearances, and absent from 25 of 35 answers. The person with the most to lose from drift is the person currently winning.

---

## 10. Concierge Buyers Advocates — WELL

**Principal:** none named on their own site. No address published since going mobile in 2020.

**Presence.** 7 of 35, positions 4, 4, 4, 7, 7. Performing respectably.

**Correction to our own record.** I predicted any principal or ABN a machine gave for them would be invention by definition, since their site names nobody. **Wrong.** The ABN given, 83 314 486 634, is **correct**: trading name Concierge Buyers Advocates, entity "The Trustee for The Limls Family Trust", VIC. "Rayson Lim" is consistent with that trust name. The machines went to the register and got it right.

**What remains interesting, not damaging.** The machines assembled a principal, a founding year, staff first names ("Timmie", "Ed") and a "99.5% success rate" from sources outside their control, including a Trustpilot review one run cited by name. Their own site supplies none of it.

**Approach.** Not a problem pitch. The honest conversation: everything the machines say about who runs your business comes from third parties, because you publish nothing. That is a controllable exposure, and it is a fix rather than a fault.

**Do not** tell them their ABN was invented. It wasn't.

---

## Standing rules for all ten

1. **Nothing goes out that is not verified against the firm's own site or a government register.** Four candidate findings died today. Assume more will.
2. **Every claim carries its N, its date and its surface.** "In 35 sampled answers on 6 August 2026, on ChatGPT and Claude."
3. **API results are never described as "ChatGPT said".** Only the two consumer runs may be described that way.
4. **Competitors named factually and never characterised.** Appendix C rule 9.
5. **One specimen per report.** One with proof beats three with assertion.
