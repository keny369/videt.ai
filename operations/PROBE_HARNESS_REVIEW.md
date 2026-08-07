# How well did the script work?

Plain-language review of the probe harness after its first full run. 6 August 2026. Written for Lee, not for clients.

---

## What it did, in one paragraph

It asked two AI models (GPT-5.5 and Claude Sonnet 5) eleven questions about Melbourne buyer's advocates and business brokers, plus one question about each of your ten target businesses. It asked each question several times, once with web search on and once with it off, and it did the whole thing twice over on two different models. That came to **212 separate conversations and about 570 API calls, finished in roughly 40 minutes for about $40**. Doing the same by hand would have taken a week.

Then a second, separate AI read every answer and turned it into a spreadsheet-like record: which businesses were named, in what order, what country they were placed in, who was said to run them, what qualifications they were credited with, and which web pages were cited.

---

## The headline: it worked, but it is a search tool, not a verdict

The script is very good at finding **candidates**. It is not capable of telling you whether a candidate is true. That distinction turned out to be the whole game.

**About half of what looked like a finding turned out to be the AI being right.** I checked each one against the company's own website or the government ABN register. Examples:

- The AI gave an ABN for Concierge Buyers Advocates. Their own website shows no ABN, so it looked invented. **It was correct.**
- The AI named Mercury's staff. It looked like an invented team. **All real people.**
- The AI called Daniel Callegari a Managing Director at Expert Business Brokers. I had recorded that he wasn't one. **He is. I was wrong, because I had trusted a third-party directory over the company's own page.**

That last one is worth dwelling on, because I made exactly the mistake your product exists to catch. It is the best possible argument for the checking step: **without it, you would have sent a business a report accusing an AI of getting something wrong when the AI had it right.** That is the one mistake you cannot recover from with a prospect.

---

## What it found, sorted into five categories

### Category 1: Invisible. The business is simply never mentioned

The clearest and most sellable result. Two targets:

- **Metropole Melbourne.** Named in **0 of 35** answers. The name "Yardney" appeared **0 of 35** times. Yet when asked about them directly, the AI described them accurately and at length, including the correct Brighton address. So the machines *know* them perfectly well and never *reach* for them. Known but not retrievable.
- **Vision Brokers and Advisors.** **0 of 59**. Neither the name nor the web address appeared once.

### Category 2: Named, but wrongly described

- **Trident Business Sales.** Claude credited them with membership of the Australian Institute of Business Brokers and a CPBB certification. Their own About page claims **REIV only** and says nothing about either. **Confirmed invented credential.** In a category where buyers choose on credentials, this is the most serious class of error there is.
- **Buyers Advocate.** Claude placed them in **Hawthorn**, citing ZoomInfo as its source. Their real address is **Kew**. A wrong fact with a cited source attached, which is the hardest kind for anyone to catch.
- **Mercury.** The people are real but the **job titles are invented**. Their website gives no formal titles to anyone; the AI confidently assigned "Founder & Managing Business Broker".

### Category 3: Invented people

- **Expert Business Brokers.** Claude named a staff member called **"Toorang"**. No such person appears on their site. Every other name it gave was real, which is what makes this dangerous: one fiction sitting inside five facts, in the same confident sentence.

### Category 4: The business can't be found because its name is its category

Three targets are called things a customer would type as a search term rather than a company name: **Buyers Advocate**, **Melbourne Buyers Advocates**, **Expert Business Brokers**. The script couldn't reliably tell whether "buyers advocate" in an answer meant the company or the job. Neither can the AI. When asked about Buyers Advocate directly, **5 of 8 runs said "I don't know"** — about the business whose website was the **single most-cited source in the entire study**, appearing in 15 of 35 answers. The machines read their content constantly and cannot identify them.

### Category 5: Doing well

- **Cate Bakos Property.** Named in 10 of 35 answers and **listed first five times**. She is the answer to the question. Her staff names came back correct.
- **Concierge Buyers Advocates.** Named 7 of 35 despite publishing no principal and no address anywhere on their site.

These two get an honest "you're performing well" conversation, not a problem pitch.

---

## The biggest single lesson

**The API and the actual ChatGPT app are different systems, and the difference is not academic.**

The script ran the geography experiment 24 times: "who are the best business brokers in Melbourne?" versus the same question with "Australia" added. It returned **zero** American firms. On that evidence I told you the Florida hook was dead.

Then I opened your real ChatGPT and asked one question about buyer's advocates. Among the sources it used were:

- the **City of Melbourne, Florida** government website
- the **Melbourne, Florida** tourism board
- **Royal Melbourne Country Club in Long Grove, Illinois**
- a **GOV.UK page about Lord Melbourne**, a British prime minister who died in 1848

Every link carried ChatGPT's own tracking tag, so there is no doubt the product served them. Full write-up in `operations/captures/CONF-20260806-001.md`.

**The script said clean. The product was contaminated.** One consumer check overturned 24 automated runs. That is the strongest evidence you will ever get for the two-surface rule in your runsheet, and it is now the best sales specimen you own, because it names no business and can be checked live on camera in one click.

---

## What the script did badly

**1. It threw away the follow-up answers at first.** I only noticed because Claude reported zero cited sources while 31 URLs sat in the raw data. Fixed mid-run, but the first records are missing that structure.

**2. It over-counted named businesses.** It listed "AIBB", "REBAA" and "Localsearch" as if they were companies. They're an industry body, an industry body and a directory. Two or three per answer, obvious on sight, but it inflates any "how many firms" number.

**3. It can't match generic names.** For three of your ten targets, the automated counting is simply unusable and has to be done by eye.

**4. It measured the wrong tier at first.** "GPT-5.5 Instant" turned out not to be an API model name at all, and my first guess at the API setting was rejected. The harness caught it and wrote it down rather than hiding it, but I had to throw away the first two records.

**5. It cannot verify anything.** Every real finding above required me to open a website. That is the slow part and it is not automatable with confidence.

---

## What to improve, in priority order

**1. Add a consumer-surface checklist to every null result.** The single most valuable change. A "nothing found" from the script now means "nothing found by the script", which we know is not the same thing. One manual check before anything is written off.

**2. Filter industry bodies and directories out of the entity count.** A short list of known non-companies (AIBB, REBAA, REIV, PIPA, Localsearch, SEEK, Flippa, bsale) would fix the over-counting in ten minutes.

**3. Capture the source panel, not just the answer.** The best finding of the day was in the *sources*, not the text. The API harness collects URLs but the consumer product's source list is richer and is where the contamination was visible. Any consumer run should have its source list read and saved.

**4. Weight the sample toward the controls.** The fabrication test produced a clean result at only 12 runs. It is now a primary hook and deserves 5 repeats rather than 3.

**5. Keep both search arms.** Every fabrication happened with search **off**: GPT-5.5 described a business that does not exist in **6 of 6** search-off runs and **1 of 6** with search on. Claude abstained **12 times out of 12**. Dropping the search-off arm to save money would have hidden the cleanest result in the study.

**6. Record the exact product configuration.** Your ChatGPT on the web is forced into a **Business seat** on **GPT-5.6 Sol** by default, not consumer GPT-5.5. Selecting 5.5 works but **resets every time you start a new chat**. Any consumer run needs the model, the effort setting and the seat type written down, or it isn't comparable to anything.

---

## Was it worth it?

Yes, decisively. $40 and 40 minutes produced: two confirmed absences, one confirmed invented credential, one confirmed invented person, one confirmed wrong address with a cited source, and a clear ranking of which of your ten prospects has a story worth telling. It also produced four candidate findings that died under checking, which cost nothing and prevented four embarrassing emails.

The honest framing for your own use: **the script does the searching, you do the knowing.** It turns a week of clicking into forty minutes, and then hands you a shortlist that still has to be checked by a human before a word of it goes to a prospect. That is not a limitation to fix. That is the product.
