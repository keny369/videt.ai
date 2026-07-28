# VIDET Official Source Registry

**Generated:** 2026-07-27  
**Purpose:** Jurisdiction-specific public source catalogue for business discovery, identity, licensing, regulatory, disciplinary, court, pricing and reputation research.

## Access labels

- **GET template** — stable query parameters are shown where known.
- **Stable landing/UI** — use the official page and its form. Do not invent a GET query.
- **API** — documented machine endpoint; credentials, headers or rate limits may apply.
- **Directory/resolver** — official national directory pointing to jurisdiction regulators.
- **Paid/login** — some records or documents require payment or authentication.
- **Verify before automation** — landing page is useful, but forms, paths or terms may change.

## Placeholders

`{business_name}`, `{person_name}`, `{company_number}`, `{licence_number}`, `{profession}`, `{service}`, `{city}`, `{state}`, `{province}`, `{postcode}`, `{zip}`, `{domain}`

Always URL-encode inserted values. A landing-page URL is not permission to scrape it. Check terms, robots controls, rate limits and statutory reuse restrictions.

# United Kingdom — UK-wide and Nation-Specific Sources

## Shared cross-jurisdiction sources

| Category | Source | URL or template | Access |
|---|---|---|---|
| Web discovery | Google | `https://www.google.com/search?q={business_name}%20{service}%20{location}` | GET template |
| Exact entity search | Google | `https://www.google.com/search?q=%22{business_name}%22%20{location}` | GET template |
| Official-domain fallback | Google | `https://www.google.com/search?q=site%3A{official_domain}%20%22{business_name}%22` | GET template |
| Local discovery | Google Maps | `https://www.google.com/maps/search/?api=1&query={service}%20{location}` | GET template |
| Local corroboration | Apple Maps | `https://maps.apple.com/?q={service}&near={location}` | GET template |
| Reviews | Trustpilot | `https://www.trustpilot.com/search?query={business_name}` | GET template |
| Domain identity | ICANN lookup | `https://lookup.icann.org/en/lookup?name={domain}` | GET template |
| Domain identity | RDAP | `https://rdap.org/domain/{domain}` | API |
| Website history | Internet Archive | `https://web.archive.org/web/*/{domain}/*` | GET template |
| News | Google News | `https://news.google.com/search?q=%22{business_name}%22` | GET template |
| Technical footprint | GitHub | `https://github.com/search?q=%22{business_name}%22&type=repositories` | GET template/login may apply |
| Security headers | SecurityHeaders | `https://securityheaders.com/?q={domain}&followRedirects=on` | GET template |

## UK-wide company and professional sources

| Category | Source | URL/template | Access |
|---|---|---|---|
| Companies | Companies House | `https://find-and-update.company-information.service.gov.uk/search/companies?q={business_name}` | GET template |
| Company profile | Companies House | `https://find-and-update.company-information.service.gov.uk/company/{company_number}` | GET template |
| Officers | Companies House | `https://find-and-update.company-information.service.gov.uk/search/officers?q={person_name}` | GET template |
| Companies API | Companies House | `https://api.company-information.service.gov.uk/search/companies?q={business_name}&items_per_page=100&start_index=0` | API |
| Financial services | FCA Register | `https://register.fca.org.uk/s/` | UI |
| Doctors | GMC | `https://www.gmc-uk.org/registration-and-licensing/the-medical-register` | UI |
| Dentists | GDC | `https://olr.gdc-uk.org/SearchRegister` | UI |
| Allied health | HCPC | `https://www.hcpc-uk.org/check-the-register/` | UI |
| Nurses | NMC | `https://www.nmc.org.uk/registration/search-the-register/` | UI |
| Vets | RCVS | `https://findavet.rcvs.org.uk/find-a-vet-surgeon/` | UI |
| Architects | ARB | `https://architects-register.org.uk/` | UI |
| Surveyors | RICS | `https://www.ricsfirms.com/` | UI |
| Gas engineers | Gas Safe | `https://www.gassaferegister.co.uk/find-an-engineer-or-check-the-register/` | UI |
| Regulated professions | GOV.UK | `https://www.regulated-professions.service.gov.uk/professions/search` | Resolver |
| Insolvency practitioners | GOV.UK | `https://www.gov.uk/find-an-insolvency-practitioner` | UI |
| Legal decisions | BAILII | `https://www.bailii.org/cgi-bin/lucy_search_1.cgi?query=%22{business_name}%22` | GET template |
| Advertising rulings | ASA | `https://www.asa.org.uk/codes-and-rulings/rulings.html?search={business_name}` | GET pattern |
| Privacy enforcement | ICO | `https://ico.org.uk/action-weve-taken/?q={business_name}` | GET template |
| Competition cases | CMA | `https://www.gov.uk/cma-cases?keywords={business_name}` | GET template |

## England

| Evidence class | Official entry point | Notes |
|---|---|---|
| Solicitors | `https://www.sra.org.uk/consumers/register/` | SRA register |
| Solicitor discovery | `https://solicitors.lawsociety.org.uk/` | Law Society directory |
| Barristers | `https://www.barstandardsboard.org.uk/for-the-public/search-a-barristers-record.html` | Regulatory record |
| Conveyancers | `https://www.clc-uk.org.uk/consumers/find-a-licensed-conveyancer/` | CLC |
| Health/care providers | `https://www.cqc.org.uk/search/all?query={business_name}&location-query-contain={location}` | GET template |
| Childcare/schools | `https://reports.ofsted.gov.uk/search?q={business_name}&location={location}` | GET template |
| Estate-agent redress | `https://www.tpos.co.uk/find-a-member` and `https://www.theprs.co.uk/consumer/members/` | Membership, not quality |
| Builders/trades | `https://www.trustmark.org.uk/homeowner/find-a-tradesperson` | Scheme membership |

## Scotland

| Evidence class | Official entry point | Notes |
|---|---|---|
| Solicitors | `https://www.lawscot.org.uk/find-a-solicitor/` | Law Society of Scotland |
| Advocates | `https://www.advocates.org.uk/advocates` | Faculty directory |
| Care providers | `https://www.careinspectorate.com/index.php/care-services` | Inspection search |
| Charities | `https://www.oscr.org.uk/about-charities/search-the-register/register-search/` | OSCR |
| Schools | `https://education.gov.scot/inspection-and-review/find-an-inspection-report/` | Inspection reports |
| Courts | `https://www.scotcourts.gov.uk/search-judgments/` | Judgments |

## Wales

| Evidence class | Official entry point | Notes |
|---|---|---|
| Solicitors/barristers | England-and-Wales SRA/BSB sources above | Shared jurisdiction |
| Care providers | `https://careinspectorate.wales/find-care-service` | Care Inspectorate Wales |
| Healthcare | `https://www.hiw.org.uk/find-service` | Healthcare Inspectorate Wales |
| Education workforce | `https://www.ewc.wales/site/index.php/en/registration/search-the-register.html` | Register |
| Schools | `https://www.estyn.gov.wales/inspection-reports` | Inspection reports |

## Northern Ireland

| Evidence class | Official entry point | Notes |
|---|---|---|
| Solicitors | `https://www.lawsoc-ni.org/solicitors-directory` | Law Society NI |
| Barristers | `https://www.barofni.com/page/barristers` | Bar directory |
| Care/health services | `https://www.rqia.org.uk/what-we-do/register/services/` | RQIA |
| Charities | `https://www.charitycommissionni.org.uk/charity-search/` | Charity Commission NI |
| Education | `https://www.etini.gov.uk/publications/type/inspection-report` | Inspection reports |
| Courts | `https://www.judiciaryni.uk/judicial-decisions` | Decisions |
| Consumer protection | `https://www.nidirect.gov.uk/articles/consumerline` | Guidance/complaints |
