# Business Recommendation Research URL Catalogue
## Australia, United States, United Kingdom and Canada

**Version:** 1.0  
**Prepared:** 27 July 2026  
**Purpose:** Candidate discovery, identity verification, credential checking, regulatory checks, reputation research, local relevance, technical proof and adverse-signal research for a business recommendation engine.

---

## Important limitations

This is a **curated, practical catalogue of high-value public reference points**, not a literal list of every directory, regulator, licensing board, association, review site or state/provincial database in four countries.

A literal “all known URLs” list would contain thousands of state, province, territory, county, city, profession and industry-specific systems and would become stale rapidly.

### URL status labels

| Label | Meaning |
|---|---|
| `GET template` | The search term can usually be passed in the URL. |
| `Stable landing page` | Open the page and enter the query manually. |
| `UI/POST only` | The form does not expose a dependable public GET query URL. Do not invent parameters. |
| `API` | Documented API or machine-readable endpoint; authentication or API key may be required. |
| `Search-engine fallback` | Uses an external search engine with a site restriction. |
| `Login/paywall possible` | Some details may require an account, payment or subscription. |
| `Scraping restricted` | Automated querying may be prohibited or rate-limited. |

### Placeholder convention

```text
{business_name}
{person_name}
{company_number}
{registration_number}
{profession}
{service}
{industry}
{suburb}
{city}
{state}
{province}
{postcode}
{zip}
{country}
{domain}
{phone}
{address}
{latitude}
{longitude}
```

URL-encode every substituted value:

```pseudocode
encoded_value = url_encode(value)
```

Example:

```text
"Lee Powell Accounting" -> Lee%20Powell%20Accounting
```

---

# 1. Cross-country discovery and corroboration

## 1.1 General web search

| Source | URL template | Status | Use |
|---|---|---|---|
| Google web | `https://www.google.com/search?q={business_name}%20{service}%20{location}` | GET template | Broad discovery |
| Google exact business | `https://www.google.com/search?q=%22{business_name}%22%20{location}` | GET template | Identity and mentions |
| Google site search | `https://www.google.com/search?q=site%3A{domain}%20{search_terms}` | GET template | Search a specific site |
| Google adverse terms | `https://www.google.com/search?q=%22{business_name}%22%20(complaint%20OR%20disciplinary%20OR%20lawsuit%20OR%20fraud%20OR%20scam)` | GET template | Red flags; allegations are not findings |
| Bing web | `https://www.bing.com/search?q={business_name}%20{service}%20{location}` | GET template | Independent discovery |
| Bing exact business | `https://www.bing.com/search?q=%22{business_name}%22%20{location}` | GET template | Identity corroboration |
| DuckDuckGo | `https://duckduckgo.com/?q={business_name}%20{service}%20{location}` | GET template | Additional discovery |

## 1.2 Maps and local business discovery

| Source | URL template | Status | Use |
|---|---|---|---|
| Google Maps text search | `https://www.google.com/maps/search/?api=1&query={service}%20near%20{location}` | GET template | Local candidates |
| Google Maps named business | `https://www.google.com/maps/search/?api=1&query={business_name}%20{location}` | GET template | Locate a candidate |
| Google Maps coordinates | `https://www.google.com/maps/search/?api=1&query={service}&query_place_id={google_place_id}` | Requires Place ID | Exact entity |
| Apple Maps | `https://maps.apple.com/?q={service}&near={location}` | GET template | Local corroboration |
| Bing Maps | `https://www.bing.com/maps?q={service}%20{location}` | GET template | Local corroboration |
| OpenStreetMap Nominatim | `https://nominatim.openstreetmap.org/search?q={address}&format=jsonv2&addressdetails=1&limit=10` | API | Geocoding; obey usage policy |
| Google Places API Text Search | `https://places.googleapis.com/v1/places:searchText` | API/POST | Structured candidates; API key and field mask required |
| Google Places API Details | `https://places.googleapis.com/v1/places/{place_id}` | API | Entity details; API key required |

## 1.3 Reviews and marketplace profiles

| Source | URL template | Status | Use |
|---|---|---|---|
| Yelp search | `https://www.yelp.com/search?find_desc={service}&find_loc={location}` | GET template | Reviews, discovery |
| Trustpilot search | `https://www.trustpilot.com/search?query={business_name}` | GET template | Company reviews |
| Better Business Bureau | `https://www.bbb.org/search?find_country=USA&find_text={business_name}` | GET template | US/Canada complaint and profile signals |
| Facebook search | `https://www.facebook.com/search/pages?q={business_name}` | Login may be required | Business presence |
| LinkedIn company search | `https://www.linkedin.com/search/results/companies/?keywords={business_name}` | Login possible | Company/team identity |
| LinkedIn people search | `https://www.linkedin.com/search/results/people/?keywords={person_name}%20{business_name}` | Login possible | Named practitioners |
| Glassdoor search | `https://www.glassdoor.com/Search/results.htm?keyword={business_name}` | Login/paywall possible | Employment signals |
| Indeed company search | `https://www.indeed.com/cmp?q={business_name}` | UI may vary | Employment signals |

**Rule:** Reviews support service-experience findings. They do not independently prove technical competence, clinical quality, legal skill or financial performance.

## 1.4 Website, domain and technical evidence

| Source | URL template | Status | Use |
|---|---|---|---|
| ICANN Lookup | `https://lookup.icann.org/en/lookup?name={domain}` | GET template | Domain registration |
| RDAP bootstrap | `https://rdap.org/domain/{domain}` | API | Registration data |
| Internet Archive | `https://web.archive.org/web/*/{domain}/*` | GET template | Historical claims/site longevity |
| Security headers | `https://securityheaders.com/?q={domain}&followRedirects=on` | GET template | Basic web security signal |
| Google PageSpeed API | `https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=https%3A%2F%2F{domain}&strategy=mobile&category=performance&category=accessibility&category=best-practices&category=seo&key={api_key}` | API | Technical site evidence |
| BuiltWith | `https://builtwith.com/{domain}` | Stable path | Technology stack; commercial |
| Wappalyzer lookup | `https://www.wappalyzer.com/lookup/{domain}/` | Stable path | Technology stack |
| crt.sh certificates | `https://crt.sh/?q=%25.{domain}&output=json` | API-like GET | Certificate/subdomain evidence |
| GitHub search | `https://github.com/search?q=%22{business_name}%22&type=repositories` | GET template | Technical footprint |
| GitHub domain search | `https://github.com/search?q={domain}&type=code` | GET template/login possible | Code references |
| Google indexed site pages | `https://www.google.com/search?q=site%3A{domain}` | GET template | Approximate discoverability |
| Google exact claims | `https://www.google.com/search?q=site%3A{domain}%20%22{claim_phrase}%22` | GET template | Locate first-party claims |

## 1.5 News, legal and adverse-event discovery

| Source | URL template | Status | Use |
|---|---|---|---|
| Google News | `https://news.google.com/search?q=%22{business_name}%22&hl=en&gl={country_code}&ceid={country_code}%3Aen` | GET template | Recent reporting |
| Bing News | `https://www.bing.com/news/search?q=%22{business_name}%22` | GET template | Recent reporting |
| Google court/tribunal search | `https://www.google.com/search?q=%22{business_name}%22%20(site%3A.gov%20OR%20site%3A.gov.au%20OR%20site%3Agov.uk%20OR%20site%3Agc.ca)%20(court%20OR%20tribunal%20OR%20disciplinary)` | GET template | Find official records |
| CourtListener US | `https://www.courtlistener.com/?q=%22{business_name}%22&type=r&order_by=score%20desc` | GET template | US court opinions/dockets |
| CanLII Canada | `https://www.canlii.org/en/#search/text=%22{business_name}%22` | GET fragment; test before automation | Canadian decisions |
| BAILII UK | `https://www.bailii.org/cgi-bin/lucy_search_1.cgi?query=%22{business_name}%22` | GET template; interface may change | UK/Ireland decisions |
| AustLII Australia | `https://www.austlii.edu.au/cgi-bin/sinosrch.cgi?query=%22{business_name}%22&method=auto&meta=%2Fau` | GET template; verify | Australian decisions |

---

# 2. Australia

## 2.1 Core business identity and corporate records

| Source | URL template | Status | Evidence |
|---|---|---|---|
| ABN Lookup | `https://abr.business.gov.au/Search/ResultsActive?SearchText={business_name}` | GET pattern may redirect; validate | ABN, status, GST, entity type |
| ABN Lookup landing | `https://abr.business.gov.au/` | Stable landing page | Search name, ABN or ACN |
| ABN direct record | `https://abr.business.gov.au/ABN/View?id={abn_digits_only}` | GET template | Known ABN record |
| ABN Lookup web services | `https://abr.business.gov.au/Tools/WebServices` | API documentation | Machine validation |
| ASIC RegistryConnect beta | `https://service.asic.gov.au/companysearch/` | UI/POST only | Company search |
| ASIC registers index | `https://asic.gov.au/search` | Stable landing page | All ASIC registers |
| ASIC Connect | `https://asicconnect.asic.gov.au/public/faces/landingPage` | UI/session-driven | Companies/business names |
| ASIC professional registers | `https://connectonline.asic.gov.au/RegistrySearch/faces/landing/ProfessionalRegisters.jspx` | UI/session-driven | Licensees and professionals |
| ASIC published notices | `https://publishednotices.asic.gov.au/` | Stable landing page | Insolvency/external administration |
| ASIC banned/disqualified | `https://asic.gov.au/online-services/search-asic-registers/banned-and-disqualified/` | Stable landing page | Regulatory red flags |
| Data.gov.au ASIC datasets | `https://data.gov.au/data/dataset?organization=australian-securities-and-investments-commission-asic&q={business_name}` | GET template | Bulk/public datasets |
| ACNC Charity Register | `https://www.acnc.gov.au/charity/charities` | UI/POST/search app | Charity identity/status |
| ACNC API/data | `https://www.acnc.gov.au/tools/data` | Stable landing page | Charity data downloads |

## 2.2 Tax, accounting and financial advice

| Source | URL template | Status | Evidence |
|---|---|---|---|
| Tax Practitioners Board public register | `https://myprofile.tpb.gov.au/public-register/` | UI/POST only | Tax/BAS registration and sanctions |
| TPB near-you register | `https://myprofile.tpb.gov.au/public-register-find-practitioner/` | UI/geolocation | Nearby tax practitioners |
| TPB help | `https://www.tpb.gov.au/help-using-tpb-register` | Reference | Search fields and interpretation |
| ASIC Financial Advisers Register via Moneysmart | `https://moneysmart.gov.au/financial-advice/financial-advisers-register` | Stable landing page | Adviser history/authorisation |
| ASIC Australian Financial Services licensees | `https://connectonline.asic.gov.au/RegistrySearch/faces/landing/ProfessionalRegisters.jspx` | UI/POST only | AFS licences |
| APRA entity register | `https://www.apra.gov.au/register-of-authorised-deposit-taking-institutions` | Stable landing page | Regulated financial entities |
| CPA Australia Find a CPA | `https://www.cpaaustralia.com.au/find-a-cpa` | UI search | Membership/discovery |
| CA ANZ Find a Chartered Accountant | `https://www.charteredaccountantsanz.com/find-a-ca` | UI search | Membership/discovery |
| IPA Find an Accountant | `https://www.publicaccountants.org.au/find-an-accountant` | UI search | Membership/discovery |
| SMSF auditor register | `https://connectonline.asic.gov.au/RegistrySearch/faces/landing/ProfessionalRegisters.jspx` | UI/POST only | Registered SMSF auditors |

## 2.3 Health, dental, allied health and clinics

| Source | URL template | Status | Evidence |
|---|---|---|---|
| AHPRA practitioner registers | `https://www.ahpra.gov.au/Registration/Registers-of-Practitioners.aspx` | UI/POST only | Registration, conditions, profession |
| AHPRA tribunal decisions | `https://www.ahpra.gov.au/Resources/Tribunal-decisions.aspx` | Stable landing/search | Published decisions |
| Healthdirect service finder | `https://www.healthdirect.gov.au/australian-health-services` | UI search | Clinics/services |
| Medicare provider search | No comprehensive public named-provider register | N/A | Do not claim verification from Medicare |
| NDIS provider finder | `https://www.ndis.gov.au/participants/working-providers/find-registered-provider` | Stable landing/search | Registered NDIS providers |
| NDIS Commission compliance actions | `https://www.ndiscommission.gov.au/about/compliance-and-enforcement/compliance-actions` | Stable landing/search | Compliance findings |
| Australian Clinical Trials | `https://www.australianclinicaltrials.gov.au/anzctr-search` | UI search | Research claims |
| TGA ARTG search | `https://www.tga.gov.au/resources/artg` | UI search | Products/devices |
| TGA advertising compliance | `https://www.tga.gov.au/how-we-regulate/advertising/compliance-and-enforcement` | Stable landing | Advertising enforcement |

## 2.4 Lawyers, conveyancers and legal services

Australia has state and territory legal-profession registers. Do not use one state’s register for another jurisdiction.

| Jurisdiction/source | URL | Status |
|---|---|---|
| Victoria Legal Services Board register | `https://lsbc.vic.gov.au/register-of-lawyers` | UI search |
| Law Society of NSW solicitor search | `https://www.lawsociety.com.au/register-of-solicitors` | UI search |
| NSW Bar Association barrister search | `https://find-a-barrister.nswbar.asn.au/` | UI search |
| Queensland Law Society find a solicitor | `https://www.qls.com.au/Find-a-Solicitor` | UI search |
| Queensland Bar find a barrister | `https://qldbar.asn.au/baq/for-the-community/find-a-barrister` | UI search |
| Law Society of South Australia search | `https://www.lawsocietysa.asn.au/Public/Find_a_Lawyer.aspx` | UI search |
| Law Society of Western Australia find a lawyer | `https://www.lawsocietywa.asn.au/find-a-lawyer/` | UI search |
| Law Society of Tasmania find a lawyer | `https://lst.org.au/find-a-lawyer/` | UI search |
| ACT Law Society find a lawyer | `https://www.actlawsociety.asn.au/find-a-lawyer` | UI search |
| Law Society Northern Territory find a lawyer | `https://lawsocietynt.asn.au/find-a-lawyer/` | UI search |
| Federal Court judgments | `https://www.fedcourt.gov.au/digital-law-library/judgments/search` | UI search |
| AustLII | `https://www.austlii.edu.au/cgi-bin/sinosrch.cgi?query=%22{business_name}%22&method=auto&meta=%2Fau` | GET template |

## 2.5 Real estate, property and finance

Licensing is state/territory based.

| Source | URL | Status |
|---|---|---|
| Victoria public register search | `https://registers.consumer.vic.gov.au/` | UI search |
| NSW Fair Trading licence check | `https://verify.licence.nsw.gov.au/home/Property` | UI search |
| Queensland licence search | `https://www.qld.gov.au/law/laws-regulated-industries-and-accountability/queensland-laws-and-regulations/fair-trading-services-programs-and-resources/fair-trading-services/licence-check` | Stable landing/UI |
| SA CBS occupational licence search | `https://secure.cbs.sa.gov.au/OccLicPubReg/LicenceSearch.php` | UI search |
| WA licence search | `https://www.commerce.wa.gov.au/consumer-protection/licence-search` | Stable landing/UI |
| Tasmania occupational licensing | `https://www.cbos.tas.gov.au/topics/licensing-and-registration/search-licence-registers` | Stable landing/UI |
| ACT licence search | `https://www.accesscanberra.act.gov.au/s/public-registers` | UI search |
| NT licence search | `https://nt.gov.au/industry/licences` | Directory |
| Domain agent search | `https://www.domain.com.au/real-estate-agents/search/?q={suburb}` | GET pattern; commercial |
| realestate.com.au agent search | `https://www.realestate.com.au/find-agent/?source=agent-search&suburb={suburb}` | GET pattern; commercial |

## 2.6 Builders, architects, trades and specialist flooring

| Source | URL | Status |
|---|---|---|
| Architects Accreditation Council register links | `https://aaca.org.au/registration-as-an-architect/architect-registers/` | National directory to state registers |
| Australian Institute of Architects find an architect | `https://www.architecture.com.au/explore/find-an-architect` | UI search |
| VIC practitioner search | `https://www.vba.vic.gov.au/tools/find-practitioner` | UI search |
| NSW contractor licence check | `https://verify.licence.nsw.gov.au/home/Trades` | UI search |
| QLD QBCC licence search | `https://www.qbcc.qld.gov.au/licence-search` | UI search |
| WA building services register | `https://www.commerce.wa.gov.au/building-and-energy/find-registered-building-service-provider` | UI search |
| SA occupational licence register | `https://secure.cbs.sa.gov.au/OccLicPubReg/LicenceSearch.php` | UI search |
| TAS licence registers | `https://www.cbos.tas.gov.au/topics/licensing-and-registration/search-licence-registers` | UI search |
| ACT public registers | `https://www.accesscanberra.act.gov.au/s/public-registers` | UI search |
| Standards Australia search | `https://store.standards.org.au/search?search={standard_or_topic}` | GET template; documents paid |
| NATSPEC product partners | `https://www.natspec.com.au/` | Site search/manual |
| Master Builders Australia | `https://masterbuilders.com.au/` | Navigate to state member search |
| Housing Industry Association directory | `https://hia.com.au/find-a-member` | UI search |
| Google exact specialty | `https://www.google.com/search?q=%22sprung%20floor%22%20installer%20{location}` | GET template |
| Manufacturer-authorised installers | `https://www.google.com/search?q=site%3A{manufacturer_domain}%20(authorised%20OR%20certified)%20installer%20{location}` | Search-engine fallback |

## 2.7 Childcare, education and aged care

| Source | URL | Status |
|---|---|---|
| Starting Blocks childcare finder | `https://www.startingblocks.gov.au/find-child-care` | UI search |
| ACECQA national registers | `https://www.acecqa.gov.au/resources/national-registers` | UI/data |
| My School | `https://www.myschool.edu.au/` | UI search |
| CRICOS provider/course search | `https://cricos.education.gov.au/` | UI search |
| My Aged Care provider search | `https://www.myagedcare.gov.au/find-a-provider` | UI search |
| Aged Care Quality Commission decisions | `https://www.agedcarequality.gov.au/consumers/non-compliance` | UI/search |

## 2.8 Complaints, competition, privacy and consumer protection

| Source | URL | Status |
|---|---|---|
| ACCC media/enforcement search | `https://www.accc.gov.au/search?query={business_name}` | GET template |
| Product Safety recalls | `https://www.productsafety.gov.au/recalls?search={business_name}` | GET pattern; verify |
| OAIC decisions/search | `https://www.oaic.gov.au/search?query={business_name}` | GET pattern |
| Australian Financial Complaints Authority decisions | `https://service02.afca.org.au/fossic_search/` | UI search |
| Advertising Standards case reports | `https://adstandards.com.au/case-reports` | UI search |
| Scamwatch | `https://www.scamwatch.gov.au/` | Information; not a complete entity register |

---

# 3. United States

## 3.1 Core company identity

There is no single national registry for all US companies. Search the incorporating state’s Secretary of State or equivalent registry.

| Source | URL | Status |
|---|---|---|
| USA.gov state business portal directory | `https://www.usa.gov/state-business` | Directory |
| SEC company search | `https://www.sec.gov/edgar/search/#/q={business_name}` | GET fragment; public issuers/filers |
| SEC submissions API | `https://data.sec.gov/submissions/CIK{cik_10_digits}.json` | API; User-Agent required |
| SEC company facts API | `https://data.sec.gov/api/xbrl/companyfacts/CIK{cik_10_digits}.json` | API |
| SAM.gov entity information | `https://sam.gov/entity-information` | UI search |
| SAM.gov exclusions | `https://sam.gov/search/?index=ex` | GET landing/filter state may be client-side |
| USAspending recipient search | `https://www.usaspending.gov/search/?hash={generated_filter_hash}` | Client-generated; use API instead |
| USAspending API | `https://api.usaspending.gov/api/v2/search/spending_by_award/` | API/POST |
| IRS tax-exempt search | `https://apps.irs.gov/app/eos/` | UI search |
| IRS tax-exempt guidance | `https://www.irs.gov/charities-non-profits/search-for-tax-exempt-organizations` | Stable landing |
| OpenCorporates | `https://opencorporates.com/companies?q={business_name}&jurisdiction_code=us` | GET template; third party |

### Selected high-volume official state registries

| State | Official search URL |
|---|---|
| California | `https://bizfileonline.sos.ca.gov/search/business` |
| New York | `https://apps.dos.ny.gov/publicInquiry/` |
| Texas | `https://mycpa.cpa.state.tx.us/coa/` |
| Florida | `https://search.sunbiz.org/Inquiry/CorporationSearch/ByName` |
| Delaware | `https://icis.corp.delaware.gov/Ecorp/EntitySearch/NameSearch.aspx` |
| Illinois | `https://apps.ilsos.gov/businessentitysearch/` |
| Pennsylvania | `https://file.dos.pa.gov/search/business` |
| Ohio | `https://businesssearch.ohiosos.gov/` |
| Georgia | `https://ecorp.sos.ga.gov/BusinessSearch` |
| Massachusetts | `https://corp.sec.state.ma.us/CorpWeb/CorpSearch/CorpSearch.aspx` |
| Washington | `https://ccfs.sos.wa.gov/#/BusinessSearch` |
| Colorado | `https://www.sos.state.co.us/biz/BusinessEntityCriteriaExt.do` |
| Arizona | `https://ecorp.azcc.gov/EntitySearch/Index` |
| North Carolina | `https://www.sosnc.gov/online_services/search/by_title/_Business_Registration` |
| Virginia | `https://cis.scc.virginia.gov/EntitySearch/Index` |
| Michigan | `https://cofs.lara.state.mi.us/SearchApi/Search/Search` |
| New Jersey | `https://www.njportal.com/DOR/BusinessNameSearch/Search/BusinessName` |
| Maryland | `https://egov.maryland.gov/BusinessExpress/EntitySearch` |
| Tennessee | `https://tnbear.tn.gov/Ecommerce/FilingSearch.aspx` |
| Nevada | `https://esos.nv.gov/EntitySearch/OnlineEntitySearch` |

For all other states, resolve the official registry from the relevant `.gov` Secretary of State, corporation commission, revenue department or licensing department website.

## 3.2 Accounting, tax, finance and insurance

| Source | URL | Status |
|---|---|---|
| IRS Directory of Federal Tax Return Preparers | `https://irs.treasury.gov/rpo/rpo.jsf` | UI search |
| CPAverify | `https://cpaverify.org/` | UI search; participating boards |
| NASBA state board directory | `https://nasba.org/stateboards/` | Directory |
| SEC Investment Adviser Public Disclosure | `https://adviserinfo.sec.gov/` | UI search |
| FINRA BrokerCheck | `https://brokercheck.finra.org/search/genericsearch/grid` | UI search |
| NMLS Consumer Access | `https://www.nmlsconsumeraccess.org/` | UI search |
| NAIC state insurance department directory | `https://content.naic.org/state-insurance-departments` | Directory |
| CFP Board verify | `https://www.cfp.net/verify-a-cfp-professional` | UI search |
| CFTC BASIC | `https://www.nfa.futures.org/basicnet/` | UI search |
| FDIC BankFind | `https://banks.data.fdic.gov/bankfind-suite/bankfind` | UI/API available |
| FDIC BankFind API | `https://banks.data.fdic.gov/bankfind-suite/api/` | API docs |

## 3.3 Health, dental and clinics

| Source | URL | Status |
|---|---|---|
| NPI Registry | `https://npiregistry.cms.hhs.gov/search` | UI search |
| NPPES API | `https://npiregistry.cms.hhs.gov/api/?version=2.1&organization_name={business_name}&city={city}&state={state}&limit=200` | API |
| Individual NPPES search | `https://npiregistry.cms.hhs.gov/api/?version=2.1&first_name={first_name}&last_name={last_name}&state={state}&limit=200` | API |
| Medicare Care Compare doctors | `https://www.medicare.gov/care-compare/?providerType=Physician` | UI search |
| Medicare Care Compare hospitals | `https://www.medicare.gov/care-compare/?providerType=Hospital` | UI search |
| CMS data catalogue | `https://data.cms.gov/search?keywords={business_name}` | GET template |
| HHS OIG exclusions | `https://exclusions.oig.hhs.gov/` | UI search |
| Open Payments | `https://openpaymentsdata.cms.gov/` | UI/data/API |
| FDA warning letters | `https://www.fda.gov/inspections-compliance-enforcement-and-criminal-investigations/compliance-actions-and-activities/warning-letters` | UI search |
| State medical boards | `https://www.fsmb.org/contact-a-state-medical-board/` | Directory |
| State dental boards | `https://www.aadexam.org/state-boards` | Directory |
| Psychology boards | `https://www.asppb.net/page/BdContactNewPG` | Directory |

## 3.4 Lawyers and legal services

| Source | URL | Status |
|---|---|---|
| ABA lawyer licensing directory | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | State directory |
| California attorney search | `https://apps.calbar.ca.gov/attorney/LicenseeSearch/QuickSearch` | UI search |
| New York attorney search | `https://iapps.courts.state.ny.us/attorneyservices/search` | UI search |
| Texas attorney search | `https://www.texasbar.com/AM/Template.cfm?Section=Find_A_Lawyer&Template=/Customsource/MemberDirectory/Search_form_client_main.cfm` | UI search |
| Florida attorney search | `https://www.floridabar.org/directories/find-mbr/` | UI search |
| Illinois lawyer search | `https://www.iardc.org/lawyersearch.asp` | UI search |
| CourtListener | `https://www.courtlistener.com/?q=%22{business_name}%22&type=r&order_by=score%20desc` | GET template |
| PACER | `https://pacer.uscourts.gov/` | Login/pay-per-use |
| RECAP archive | `https://www.courtlistener.com/recap/` | Public subset |

## 3.5 Real estate, construction and trades

| Source | URL | Status |
|---|---|---|
| ARELLO regulator directory | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | State/province directory |
| NMLS Consumer Access | `https://www.nmlsconsumeraccess.org/` | Mortgage professionals |
| HUD contractor search | `https://www.hud.gov/lenderlist` | FHA lender search |
| State contractor boards | `https://www.nascla.org/page/MemberAgencies` | Directory |
| California contractor licence | `https://www.cslb.ca.gov/OnlineServices/CheckLicenseII/CheckLicense.aspx` | UI search |
| Florida licence search | `https://www.myfloridalicense.com/wl11.asp` | UI search |
| Texas licence search hub | `https://www.tdlr.texas.gov/LicenseSearch/` | UI search |
| HomeAdvisor | `https://www.homeadvisor.com/c.html?task.doSearch=&query={service}&location={zip}` | Commercial; URL may change |
| Angi | `https://www.angi.com/companylist/{city}/{service}.htm` | Commercial/path-dependent |
| Houzz professionals | `https://www.houzz.com/professionals/query/{service}/{location}` | Commercial |
| Google specialty search | `https://www.google.com/search?q=%22{service}%22%20installer%20{city}%20{state}` | GET template |

## 3.6 Education, childcare and care services

| Source | URL | Status |
|---|---|---|
| Child Care search | `https://childcare.gov/consumer-education/find-child-care` | State directory |
| College Scorecard | `https://collegescorecard.ed.gov/search/?search={institution_name}` | GET template |
| College Scorecard API | `https://api.data.gov/ed/collegescorecard/v1/schools?school.name={institution_name}&api_key={api_key}` | API |
| Medicare Care Compare nursing homes | `https://www.medicare.gov/care-compare/?providerType=NursingHome` | UI search |
| State education agency directory | `https://www2.ed.gov/about/contacts/state/index.html` | Directory |

## 3.7 Complaints, enforcement and government contracting

| Source | URL | Status |
|---|---|---|
| FTC enforcement cases | `https://www.ftc.gov/legal-library/browse/cases-proceedings?search={business_name}` | GET pattern |
| CFPB complaints | `https://www.consumerfinance.gov/data-research/consumer-complaints/search/?searchField=all&searchText={business_name}` | GET template |
| CFPB API | `https://www.consumerfinance.gov/data-research/consumer-complaints/search/api/v1/?company={business_name}&size=100` | API; verify current syntax |
| CPSC recalls | `https://www.cpsc.gov/Recalls?search_combined_fields={business_name}` | GET template |
| OSHA establishment search | `https://www.osha.gov/ords/imis/establishment.html` | UI search |
| EPA ECHO | `https://echo.epa.gov/facilities/facility-search` | UI/API |
| SAM exclusions | `https://sam.gov/search/?index=ex` | UI search |
| BBB | `https://www.bbb.org/search?find_country=USA&find_text={business_name}` | Third party/non-government |
| State AG directory | `https://www.naag.org/find-my-ag/` | Directory |

---

# 4. United Kingdom

## 4.1 Core company identity

| Source | URL | Status |
|---|---|---|
| Companies House search | `https://find-and-update.company-information.service.gov.uk/search/companies?q={business_name}` | GET template |
| Companies House officers | `https://find-and-update.company-information.service.gov.uk/search/officers?q={person_name}` | GET template |
| Companies House disqualified officers | `https://find-and-update.company-information.service.gov.uk/search/disqualified-officers?q={person_name}` | GET template |
| Companies House company record | `https://find-and-update.company-information.service.gov.uk/company/{company_number}` | GET template |
| Companies House API search | `https://api.company-information.service.gov.uk/search/companies?q={business_name}&items_per_page=100&start_index=0` | API; Basic Auth/API key |
| Companies House API profile | `https://api.company-information.service.gov.uk/company/{company_number}` | API |
| Companies House filing history | `https://api.company-information.service.gov.uk/company/{company_number}/filing-history?items_per_page=100&start_index=0` | API |
| Companies House officers API | `https://api.company-information.service.gov.uk/company/{company_number}/officers?items_per_page=100&start_index=0` | API |
| Charity Commission England/Wales | `https://register-of-charities.charitycommission.gov.uk/charity-search` | UI search |
| OSCR Scotland charity search | `https://www.oscr.org.uk/about-charities/search-the-register/register-search/` | UI search |
| Charity Commission NI | `https://www.charitycommissionni.org.uk/charity-search/` | UI search |

## 4.2 Accounting, finance and insurance

| Source | URL | Status |
|---|---|---|
| FCA Financial Services Register | `https://register.fca.org.uk/s/` | UI search |
| FCA Firm Checker | `https://www.fca.org.uk/consumers/financial-services-register` | Stable landing |
| ICAEW firm/member search | `https://find.icaew.com/` | UI search |
| ACCA member/firms directory | `https://www.accaglobal.com/gb/en/member/find-an-accountant.html` | UI search |
| CIMA member verification | `https://www.aicpa-cima.com/resources/landing/find-a-cima-accountant` | UI search |
| ICAS find a CA | `https://www.icas.com/find-a-ca` | UI search |
| Financial Ombudsman decisions | `https://www.financial-ombudsman.org.uk/decisions-case-studies/ombudsman-decisions/search?BusinessName={business_name}` | GET pattern; verify |
| Insolvency Service register | `https://www.gov.uk/search-bankruptcy-insolvency-register` | Stable landing |
| Insolvency practitioner directory | `https://www.gov.uk/find-an-insolvency-practitioner` | UI search |

## 4.3 Health, dental and clinics

| Source | URL | Status |
|---|---|---|
| General Medical Council register | `https://www.gmc-uk.org/registration-and-licensing/the-medical-register` | UI search |
| General Dental Council register | `https://olr.gdc-uk.org/SearchRegister` | UI search |
| HCPC register | `https://www.hcpc-uk.org/check-the-register/` | UI search |
| Nursing and Midwifery Council | `https://www.nmc.org.uk/registration/search-the-register/` | UI search |
| General Chiropractic Council | `https://www.gcc-uk.org/search-the-register` | UI search |
| General Osteopathic Council | `https://www.osteopathy.org.uk/register-search/` | UI search |
| CQC provider search | `https://www.cqc.org.uk/search/all?query={business_name}&location-query-contain={location}` | GET template |
| NHS service search | `https://www.nhs.uk/service-search/` | UI search |
| NHS dentists | `https://www.nhs.uk/service-search/find-a-dentist` | UI search |
| Care Inspectorate Scotland | `https://www.careinspectorate.com/index.php/care-services` | UI search |
| Regulation and Quality Improvement Authority NI | `https://www.rqia.org.uk/what-we-do/register/services/` | UI search |
| Healthcare Inspectorate Wales | `https://www.hiw.org.uk/find-service` | UI search |
| MHRA products | `https://products.mhra.gov.uk/` | UI search |

## 4.4 Lawyers and legal services

| Source | URL | Status |
|---|---|---|
| Solicitors Regulation Authority | `https://www.sra.org.uk/consumers/register/` | UI search |
| Law Society Find a Solicitor | `https://solicitors.lawsociety.org.uk/` | UI search |
| Bar Standards Board barrister search | `https://www.barstandardsboard.org.uk/for-the-public/search-a-barristers-record.html` | UI search |
| Legal Ombudsman decisions | `https://www.legalombudsman.org.uk/information-centre/data-centre/ombudsman-decision-data/` | Data/search |
| Council for Licensed Conveyancers | `https://www.clc-uk.org.uk/consumers/find-a-licensed-conveyancer/` | UI search |
| Law Society of Scotland solicitor search | `https://www.lawscot.org.uk/find-a-solicitor/` | UI search |
| Faculty of Advocates | `https://www.advocates.org.uk/advocates` | UI directory |
| Law Society Northern Ireland | `https://www.lawsoc-ni.org/solicitors-directory` | UI search |
| BAILII | `https://www.bailii.org/cgi-bin/lucy_search_1.cgi?query=%22{business_name}%22` | GET template |

## 4.5 Real estate, construction and professions

| Source | URL | Status |
|---|---|---|
| Propertymark find an expert | `https://www.propertymark.co.uk/find-an-expert.html` | UI search |
| Property Ombudsman agents | `https://www.tpos.co.uk/find-a-member` | UI search |
| Property Redress Scheme | `https://www.theprs.co.uk/consumer/members/` | UI search |
| Architects Registration Board | `https://architects-register.org.uk/` | UI search |
| RIBA find an architect | `https://www.architecture.com/find-an-architect` | UI search |
| RICS find a surveyor | `https://www.ricsfirms.com/` | UI search |
| Gas Safe Register | `https://www.gassaferegister.co.uk/find-an-engineer-or-check-the-register/` | UI search |
| NICEIC contractor search | `https://niceic.com/find-a-tradesperson/` | UI search |
| TrustMark tradespeople | `https://www.trustmark.org.uk/homeowner/find-a-tradesperson` | UI search |
| Federation of Master Builders | `https://www.fmb.org.uk/find-a-builder.html` | UI search |
| Planning Portal | `https://www.planningportal.co.uk/` | Local planning links |
| UKAS accredited organisations | `https://www.ukas.com/find-an-organisation/` | UI search |
| BSI standards search | `https://knowledge.bsigroup.com/search?query={standard_or_topic}` | GET template/login/paywall possible |

## 4.6 Education, childcare and social care

| Source | URL | Status |
|---|---|---|
| Ofsted reports | `https://reports.ofsted.gov.uk/search?q={business_name}&location={location}` | GET template |
| Get Information About Schools | `https://get-information-schools.service.gov.uk/Search?SelectedTab=Establishments&SearchQuery={institution_name}` | GET template |
| Care Quality Commission | `https://www.cqc.org.uk/search/all?query={business_name}` | GET template |
| Find postgraduate teacher training | `https://find-teacher-training-courses.service.gov.uk/` | UI search |

## 4.7 Enforcement, complaints and advertising

| Source | URL | Status |
|---|---|---|
| Competition and Markets Authority cases | `https://www.gov.uk/cma-cases?keywords={business_name}` | GET template |
| Advertising Standards Authority rulings | `https://www.asa.org.uk/codes-and-rulings/rulings.html?search={business_name}` | GET pattern |
| ICO action we've taken | `https://ico.org.uk/action-weve-taken/?q={business_name}` | GET template |
| HSE notices | `https://resources.hse.gov.uk/notices/` | UI search |
| HSE prosecutions | `https://resources.hse.gov.uk/convictions/` | UI search |
| GOV.UK court/tribunal decisions | `https://www.gov.uk/employment-tribunal-decisions?keywords={business_name}` | GET template |
| Financial Conduct Authority warnings | `https://www.fca.org.uk/news/search-results?search={business_name}` | GET pattern |

---

# 5. Canada

## 5.1 Core company identity

Canada has federal and provincial/territorial corporations. A federal search alone is incomplete.

| Source | URL | Status |
|---|---|---|
| Corporations Canada federal search | `https://ised-isde.canada.ca/cc/lgcy/fdrlCrpSrch.html?lang=eng` | UI search |
| New federal search interface | `https://ised-isde.canada.ca/cc/web/isc/srch` | UI search |
| Canada Business Registries | `https://ised-isde.canada.ca/cbr-rec/en/search?source=dn.ca` | UI search; scraping restricted |
| Canada Business Registries result template | `https://ised-isde.canada.ca/cbr-rec/en/search/results?search={business_name}` | GET template; automated copying prohibited |
| Ontario Business Registry | `https://www.ontario.ca/page/ontario-business-registry` | Stable landing/login/search |
| BC OrgBook | `https://orgbook.gov.bc.ca/en/home` | UI/API |
| BC OrgBook API | `https://orgbook.gov.bc.ca/api/v4/search/topic?q={business_name}` | API; verify current version |
| Alberta registry information | `https://www.alberta.ca/find-corporation-details` | Stable landing; registry agent may be required |
| Quebec enterprise register | `https://www.registreentreprises.gouv.qc.ca/REQNA/GR/GR03/GR03A71.RechercheRegistre.MVC/GR03A71` | UI search |
| Saskatchewan ISC business search | `https://www.isc.ca/CorporateRegistry/Findanexistingbusiness/Pages/default.aspx` | Stable landing |
| Manitoba Companies Office | `https://companiesoffice.gov.mb.ca/` | UI search |
| Nova Scotia Registry | `https://beta.novascotia.ca/search-business-or-non-profit-information-filed-registry-joint-stock-companies` | Stable landing/UI |
| New Brunswick corporate registry | `https://www2.snb.ca/content/snb/en/sites/corporate-registry.html` | Stable landing/UI |
| Newfoundland registry | `https://cado.eservices.gov.nl.ca/CadoInternet/Company/CompanyMain.aspx` | UI search |
| PEI business registry | `https://www.princeedwardisland.ca/en/service/search-the-pei-business-corporate-registry` | Stable landing/UI |
| Yukon corporate registry | `https://ycor-reey.gov.yk.ca/` | UI search |
| NWT corporate registries | `https://www.justice.gov.nt.ca/en/corporate-registries/` | Stable landing |
| Nunavut legal registries | `https://www.gov.nu.ca/en/justice/legal-registries` | Stable landing |
| OpenCorporates Canada | `https://opencorporates.com/companies?q={business_name}&jurisdiction_code=ca` | Third party |

## 5.2 Accounting, finance and insurance

Professional accounting regulation is largely provincial.

| Source | URL | Status |
|---|---|---|
| CPA Canada provincial bodies | `https://www.cpacanada.ca/the-cpa-profession/about-cpa-canada/provincial-and-regional-bodies` | Directory |
| CPA Ontario member directory | `https://myportal.cpaontario.ca/s/member-directory` | UI search |
| CPA BC member search | `https://www.bccpa.ca/member-practice-regulation/member-firm-directories/` | UI/directory |
| CPA Alberta member directory | `https://www.cpaalberta.ca/Protecting-the-Public/Find-a-CPA` | UI search |
| CPA Quebec order directory | `https://cpaquebec.ca/en/find-a-cpa/` | UI search |
| CIRO AdvisorReport | `https://advisorreport.ciro.ca/` | UI search |
| Canadian Securities Administrators registration search | `https://info.securities-administrators.ca/nrsmobile/nrssearch.aspx` | UI search |
| OSFI regulated entities | `https://www.osfi-bsif.gc.ca/en/supervision/regulated-institutions` | Lists/registers |
| FCAC enforcement decisions | `https://www.canada.ca/en/financial-consumer-agency/services/industry/commissioner-decisions.html` | Stable landing/search |
| Mortgage Broker Regulators' Council | `https://www.mbrcc.ca/` | Resolve provincial regulator |
| Insurance regulators directory | `https://www.ccir-ccrra.org/` | Resolve provincial regulator |

## 5.3 Health, dental and clinics

Licensing is provincial/territorial. Search the regulator for the province where the professional practises.

| Source | URL | Status |
|---|---|---|
| Medical Council of Canada regulatory authorities | `https://mcc.ca/about/partner-organizations/medical-regulatory-authorities/` | Directory |
| Royal College directory | `https://rclogin.royalcollege.ca/webcenter/portal/rcdirectory_en` | UI search |
| Ontario physicians CPSO | `https://doctors.cpso.on.ca/` | UI search |
| BC physicians CPSBC | `https://www.cpsbc.ca/public/registrant-directory` | UI search |
| Alberta physicians CPSA | `https://search.cpsa.ca/` | UI search |
| Quebec physicians CMQ | `https://www.cmq.org/en/directory-physicians` | UI search |
| Ontario dentists RCDSO | `https://www.rcdso.org/en-ca/find-a-dentist` | UI search |
| BC dentists BCCOHP | `https://oralhealthbc.ca/public-protection/registrant-lookup/` | UI search |
| Alberta dentists CDSA | `https://www.cdsab.ca/find-a-dentist/` | UI search |
| Ontario health facility inspections | `https://www.ontario.ca/page/health-care-facility-complaints` | Reference; regulator-specific |
| Health Canada recalls | `https://recalls-rappels.canada.ca/en/search/site?search_api_fulltext={business_name}` | GET template |
| Health Canada drug/product database | `https://health-products.canada.ca/dpd-bdpp/index-eng.jsp` | UI search |
| Clinical Trials Database | `https://health-products.canada.ca/ctdb-bdec/index-eng.jsp` | UI search |

## 5.4 Lawyers and legal services

| Province/territory | URL | Status |
|---|---|---|
| Federation of Law Societies directory | `https://flsc.ca/about-us/our-members-canadas-law-societies/` | National directory |
| Ontario Lawyer and Paralegal Directory | `https://lso.ca/public-resources/finding-a-lawyer-or-paralegal/lawyer-and-paralegal-directory` | UI search |
| Law Society of BC | `https://www.lawsociety.bc.ca/working-with-lawyers/finding-a-lawyer/` | UI search |
| Law Society of Alberta | `https://lsa.memberpro.net/main/body.cfm` | UI search |
| Barreau du Québec directory | `https://www.barreau.qc.ca/en/directory-lawyers/` | UI search |
| Law Society of Saskatchewan | `https://www.lawsociety.sk.ca/find-a-lawyer/` | UI search |
| Law Society of Manitoba | `https://lawsociety.mb.ca/for-the-public/finding-a-lawyer/` | UI search |
| Nova Scotia Barristers' Society | `https://members.nsbs.org/LawyerSearch` | UI search |
| Law Society of New Brunswick | `https://lsbnb.alinityapp.com/Client/PublicDirectory` | UI search |
| Law Society of Newfoundland and Labrador | `https://lsnl.ca/lawyer-search/` | UI search |
| Law Society of PEI | `https://lawsocietypei.ca/find-a-lawyer/` | UI search |
| Yukon Law Society | `https://lawsocietyyukon.com/find-a-lawyer/` | UI search |
| Law Society NWT | `https://lawsociety.nt.ca/lawyer-directory/` | UI search |
| Law Society Nunavut | `https://www.lawsociety.nu.ca/en/lawyer-directory` | UI search |
| CanLII | `https://www.canlii.org/en/#search/text=%22{business_name}%22` | Public legal search |

## 5.5 Real estate, construction and trades

| Source | URL | Status |
|---|---|---|
| Real Estate Council of Ontario | `https://registrantsearch.reco.on.ca/` | UI search |
| BC Financial Services Authority licence search | `https://www.bcfsa.ca/public-resources/real-estate/find-professional` | UI search |
| Real Estate Council of Alberta | `https://www.reca.ca/consumers/tools-resources/licensee-search/` | UI search |
| OACIQ Quebec broker search | `https://www.oaciq.com/en/find-broker` | UI search |
| Saskatchewan real estate commission | `https://www.srec.ca/consumer-info/find-a-registrant/` | UI search |
| Manitoba Securities Commission real estate | `https://realestate.mb.ca/registrant-search/` | UI search |
| NSREC licence search | `https://www.nsrec.ns.ca/consumer-resources/licensee-search` | UI search |
| ARELLO regulator directory | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | US/Canada directory |
| Ontario skilled trades public register | `https://www.skilledtradesontario.ca/public-register/` | UI search |
| BC contractor licence search | `https://www.bchousing.org/licensing-consumer-services/licence-registry` | UI search |
| Quebec RBQ licence holders | `https://www.pes.rbq.gouv.qc.ca/RegistreLicences` | UI search |
| Red Seal trade search | `https://www.red-seal.ca/eng/trades/tr.1d.2s_l.3st.shtml` | Trade standards, not individual licence |
| Canadian architectural regulators | `https://roac.ca/` | Resolve provincial regulator |
| RAIC firm directory | `https://raic.org/find-an-architect` | UI search |

## 5.6 Childcare, education and care

| Source | URL | Status |
|---|---|---|
| Ontario child care search | `https://www.earlyyears.edu.gov.on.ca/LCCWWeb/childcare/search.xhtml` | UI search |
| BC child care map | `https://maps.gov.bc.ca/ess/hm/ccf/` | Map/UI |
| Alberta child care lookup | `https://www.humanservices.alberta.ca/oldfusion/ChildCareLookup.cfm` | UI search |
| Quebec childcare locator | `https://www.laplace0-5.com/` | UI search |
| Universities Canada member search | `https://univcan.ca/universities/member-universities/` | Directory |
| Long-term care Ontario | `https://www.ontario.ca/page/long-term-care-home-finder` | UI search |
| Health authority/provider search | Province-specific | Resolve by province |

## 5.7 Complaints, competition, privacy and enforcement

| Source | URL | Status |
|---|---|---|
| Competition Bureau cases | `https://competition-bureau.canada.ca/en/deceptive-marketing-practices/cases-and-outcomes` | Searchable table |
| Competition Bureau site search | `https://competition-bureau.canada.ca/en/search/node?keys={business_name}` | GET template |
| Office of Privacy Commissioner findings | `https://www.priv.gc.ca/en/opc-actions-and-decisions/investigations/` | UI search |
| Health Canada recalls | `https://recalls-rappels.canada.ca/en/search/site?search_api_fulltext={business_name}` | GET template |
| Canadian Legal Information Institute | `https://www.canlii.org/en/#search/text=%22{business_name}%22` | Legal decisions |
| Better Business Bureau Canada | `https://www.bbb.org/search?find_country=CAN&find_text={business_name}` | Third party |
| Provincial consumer offices | `https://ised-isde.canada.ca/site/office-consumer-affairs/en/information-canadian-consumers/provincial-and-territorial-consumer-affairs-offices` | Directory |

---

# 6. Industry-specific discovery query templates

These supplement, but never replace, official registers.

## 6.1 Accountants and bookkeepers

```text
https://www.google.com/search?q={profession}%20{specialisation}%20{location}
https://www.google.com/search?q=%22{business_name}%22%20(CPA%20OR%20chartered%20OR%20tax%20agent)
https://www.google.com/search?q=%22{business_name}%22%20(complaint%20OR%20disciplinary%20OR%20sanction)
https://www.google.com/maps/search/?api=1&query={specialisation}%20accountant%20{location}
```

Mandatory corroboration:

```pseudocode
verify_business_identity()
verify_tax_agent_status_if_tax_advice()
verify_professional_membership_if_claimed()
check_public_disciplinary_information()
```

## 6.2 AI consultants

```text
https://www.google.com/search?q=%22{business_name}%22%20AI%20case%20study
https://www.google.com/search?q=site%3A{domain}%20(case%20study%20OR%20client%20OR%20implementation%20OR%20security)
https://github.com/search?q=%22{business_name}%22&type=repositories
https://www.linkedin.com/search/results/people/?keywords={business_name}%20AI
https://www.google.com/search?q=%22{business_name}%22%20(privacy%20OR%20security%20OR%20ISO%2027001%20OR%20SOC%202)
```

Mandatory checks:

```pseudocode
identify_named_delivery_team()
verify_case_study_client_where_possible()
separate_strategy_from_implementation()
check_security_and_data_handling_claims()
search_for_real_deployments_not_only_content_marketing()
```

## 6.3 Marketing, web and branding agencies

```text
https://www.google.com/search?q={service}%20agency%20{industry}%20{location}
https://www.google.com/search?q=site%3A{domain}%20(case%20study%20OR%20results%20OR%20portfolio)
https://www.google.com/search?q=%22{business_name}%22%20(client%20OR%20campaign%20OR%20award)
https://www.google.com/search?q=%22{business_name}%22%20(complaint%20OR%20review%20OR%20lawsuit)
```

Mandatory checks:

```pseudocode
normalise_claimed_results()
check_attribution_method()
confirm_who_performs_delivery()
check_contract_lock_in()
distinguish_awards_from_outcomes()
```

## 6.4 Lawyers

```text
https://www.google.com/search?q={practice_area}%20lawyer%20{location}
https://www.google.com/search?q=%22{lawyer_name}%22%20{jurisdiction}%20lawyer
https://www.google.com/search?q=%22{business_name}%22%20{practice_area}%20case
```

Mandatory checks:

```pseudocode
verify_current_practising_status()
verify_jurisdiction()
verify_exact_practice_area()
check_public_discipline()
never_infer_win_rate_from_search_results()
```

## 6.5 Clinics, dentists and allied health

```text
https://www.google.com/maps/search/?api=1&query={treatment}%20{location}
https://www.google.com/search?q=%22{practitioner_name}%22%20{profession}%20{location}
https://www.google.com/search?q=%22{clinic_name}%22%20(inspection%20OR%20disciplinary%20OR%20sanction)
```

Mandatory checks:

```pseudocode
verify_individual_practitioner()
verify_clinic_or_facility_separately()
match_specialisation_to_treatment()
treat_reviews_as_experience_not_clinical_outcome_proof()
```

## 6.6 Real estate agents

```text
https://www.google.com/search?q={suburb}%20{property_type}%20real%20estate%20agent
https://www.google.com/search?q=%22{agent_name}%22%20{agency_name}%20{location}
https://www.google.com/search?q=%22{agent_name}%22%20sold%20{property_type}%20{suburb}
```

Mandatory checks:

```pseudocode
verify_licence()
match_exact_suburb()
match_property_type_and_price_band()
use_recent_comparable_activity()
do_not_rank_by_total_lifetime_sales_alone()
```

## 6.7 Builders, architects and specialist flooring

```text
https://www.google.com/search?q=%22{service}%22%20{location}%20installer
https://www.google.com/search?q=%22{business_name}%22%20(project%20OR%20portfolio%20OR%20specification)
https://www.google.com/search?q=site%3A{manufacturer_domain}%20%22{business_name}%22
https://www.google.com/search?q=%22{business_name}%22%20(warranty%20OR%20defect%20OR%20tribunal)
```

For sprung floors:

```text
https://www.google.com/search?q=%22sprung%20floor%22%20installer%20{location}
https://www.google.com/search?q=%22sprung%20floor%22%20{business_name}
https://www.google.com/search?q=site%3A{manufacturer_domain}%20installer%20{country}
https://www.google.com/search?q=%22{business_name}%22%20(dance%20OR%20sports%20OR%20performance)%20floor
```

Mandatory checks:

```pseudocode
verify_exact_system_experience()
verify_installed_project_references()
identify_standard_or_performance_specification()
verify_subfloor_and_moisture competence()
verify_warranty_issuer()
```

---

# 7. Search query construction

```pseudocode
FUNCTION build_search_urls(request):

    encoded_business = url_encode(request.business_name)
    encoded_service = url_encode(request.service)
    encoded_location = url_encode(request.location)
    encoded_person = url_encode(request.person_name)

    RETURN {
        discovery:
            "https://www.google.com/search?q=" +
            encoded_service + "%20" + encoded_location,

        maps:
            "https://www.google.com/maps/search/?api=1&query=" +
            encoded_service + "%20" + encoded_location,

        exact_business:
            "https://www.google.com/search?q=%22" +
            encoded_business + "%22%20" + encoded_location,

        official_site_search:
            "https://www.google.com/search?q=site%3A" +
            official_domain + "%20%22" + encoded_business + "%22",

        adverse_search:
            "https://www.google.com/search?q=%22" +
            encoded_business +
            "%22%20(complaint%20OR%20disciplinary%20OR%20sanction%20OR%20lawsuit)",

        practitioner_search:
            "https://www.google.com/search?q=%22" +
            encoded_person + "%22%20%22" + encoded_business + "%22"
    }
```

---

# 8. Source priority

```pseudocode
SOURCE_PRIORITY = [
    statutory_registry,
    government_licensing_register,
    professional_regulator,
    court_or_tribunal_record,
    government_enforcement_database,
    official_accreditation_register,
    official_company_filing,
    independently_verifiable_project_record,
    reputable_news_source,
    first_party_website,
    professional_association_directory,
    map_profile,
    review_platform,
    commercial_directory,
    social_media,
    unverified_aggregator
]
```

---

# 9. Rules against false certainty

```pseudocode
NEVER:

    invent_query_parameters_for_UI_only_forms()

    assume_a_company_record_proves_professional_competence()

    assume_professional_membership_equals_current_licensing()

    treat_a_directory_listing_as_regulatory_verification()

    treat_review_stars_as_outcome_quality()

    treat_an_allegation_as_a_finding()

    treat_absence_from_one_database_as_nonexistence()

    merge_same_named_entities_without_identity_matching()

    automate_a_registry_that_explicitly_prohibits_automated_search()

    publish_sensitive_personal_details_unnecessary_to_the_recommendation()
```

---

# 10. Recommended implementation fields

```json
{
  "source_id": "string",
  "country": "AU | US | UK | CA | GLOBAL",
  "jurisdiction": "string or null",
  "category": "BUSINESS_REGISTRY | PROFESSIONAL_REGISTER | LICENSING | REVIEWS | COURTS | ENFORCEMENT | MAPS | PORTFOLIO | TECHNICAL",
  "name": "string",
  "base_url": "string",
  "query_template": "string or null",
  "access_mode": "GET | POST_UI | API | LOGIN | PAID",
  "automation_permitted": "YES | NO | UNKNOWN | RESTRICTED",
  "authoritative_for": ["string"],
  "not_authoritative_for": ["string"],
  "requires_api_key": false,
  "requires_login": false,
  "rate_limit_notes": "string or null",
  "last_verified_at": "ISO-8601 date",
  "fallback_query": "string or null"
}
```

---

# 11. Final implementation recommendation

Store URLs as versioned source definitions rather than hard-coding them throughout the application.

```pseudocode
source_registry/
    global.yml
    australia.yml
    united_states.yml
    united_kingdom.yml
    canada.yml

FOR each source:
    retain:
        source_version
        last_verified_at
        query_method
        terms_or_robot_restrictions
        parser_version
        fallback_search
```

Run automated link-health checks, but do not automatically submit search forms unless the source permits it.

```pseudocode
WEEKLY:
    check_HTTP_status(base_url)
    detect_redirects()
    detect_title_or_form_changes()
    flag_parser_breakage()

QUARTERLY:
    manually_reverify_high_authority_sources()
    update_industry_policy()
    archive_deprecated_endpoints()
```
