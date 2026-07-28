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

# United States — Federal and State Source Registry

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

## Federal and national source resolvers

| Category | Source | URL/template | Access |
|---|---|---|---|
| Public companies | SEC EDGAR | `https://www.sec.gov/edgar/search/#/q={business_name}` | UI/hash |
| SEC submissions | SEC | `https://data.sec.gov/submissions/CIK{cik_10_digits}.json` | API; User-Agent required |
| Federal contractors/exclusions | SAM.gov | `https://sam.gov/entity-information` / `https://sam.gov/search/?index=ex` | UI |
| Tax-exempt entities | IRS | `https://apps.irs.gov/app/eos/` | UI |
| Tax preparers | IRS | `https://irs.treasury.gov/rpo/rpo.jsf` | UI |
| Accountancy boards | NASBA | `https://nasba.org/stateboards/` | Resolver |
| CPA aggregation | CPAverify | `https://cpaverify.org/` | UI |
| Medical boards | FSMB | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolver |
| Lawyer licensing | ABA | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolver |
| Dental boards | AADB | `https://www.aadexam.org/state-boards` | Resolver |
| Real estate regulators | ARELLO | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolver |
| Contractor boards | NASCLA | `https://www.nascla.org/page/MemberAgencies` | Resolver |
| Investment advisers | SEC IAPD | `https://adviserinfo.sec.gov/` | UI |
| Brokers | FINRA BrokerCheck | `https://brokercheck.finra.org/` | UI |
| Mortgage professionals | NMLS | `https://www.nmlsconsumeraccess.org/` | UI |
| Insurance regulators | NAIC | `https://content.naic.org/state-insurance-departments` | Resolver |
| Health providers | NPI Registry | `https://npiregistry.cms.hhs.gov/search` | UI |
| NPI API | CMS | `https://npiregistry.cms.hhs.gov/api/?version=2.1&organization_name={business_name}&city={city}&state={state}&limit=200` | API |
| Health exclusions | HHS OIG | `https://exclusions.oig.hhs.gov/` | UI |
| Court opinions | CourtListener | `https://www.courtlistener.com/?q=%22{business_name}%22&type=r&order_by=score%20desc` | GET template |
| Federal dockets | PACER | `https://pacer.uscourts.gov/` | Login/paid |
| CFPB complaints | CFPB | `https://www.consumerfinance.gov/data-research/consumer-complaints/search/?searchField=all&searchText={business_name}` | GET template |
| FTC enforcement | FTC | `https://www.ftc.gov/legal-library/browse/cases-proceedings?search={business_name}` | GET pattern |
| Recalls | CPSC | `https://www.cpsc.gov/Recalls?search_combined_fields={business_name}` | GET template |
| State AGs | NAAG | `https://www.naag.org/find-my-ag/` | Resolver |
| State portals | USA.gov | `https://www.usa.gov/state-governments` | Resolver |

## Alabama (AL)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://arc-sos.state.al.us/CGI/CORPNAME.MBR/INPUT` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve AL board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve AL board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve AL licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve AL dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve AL regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve AL department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve AL attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Alaska (AK)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.commerce.alaska.gov/cbp/main/Search/Entities` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve AK board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve AK board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve AK licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve AK dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve AK regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve AK department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve AK attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Arizona (AZ)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://ecorp.azcc.gov/EntitySearch/Index` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve AZ board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve AZ board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve AZ licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve AZ dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve AZ regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve AZ department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve AZ attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Arkansas (AR)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.sos.arkansas.gov/corps/search_all.php` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve AR board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve AR board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve AR licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve AR dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve AR regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve AR department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve AR attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## California (CA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://bizfileonline.sos.ca.gov/search/business` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve CA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve CA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve CA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve CA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve CA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve CA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve CA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Colorado (CO)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.sos.state.co.us/biz/BusinessEntityCriteriaExt.do` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve CO board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve CO board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve CO licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve CO dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve CO regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve CO department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve CO attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Connecticut (CT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://service.ct.gov/business/s/onlinebusinesssearch` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve CT board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve CT board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve CT licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve CT dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve CT regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve CT department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve CT attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Delaware (DE)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://icis.corp.delaware.gov/Ecorp/EntitySearch/NameSearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve DE board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve DE board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve DE licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve DE dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve DE regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve DE department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve DE attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Florida (FL)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://search.sunbiz.org/Inquiry/CorporationSearch/ByName` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve FL board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve FL board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve FL licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve FL dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve FL regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve FL department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve FL attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Georgia (GA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://ecorp.sos.ga.gov/BusinessSearch` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve GA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve GA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve GA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve GA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve GA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve GA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve GA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Hawaii (HI)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://hbe.ehawaii.gov/documents/search.html` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve HI board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve HI board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve HI licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve HI dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve HI regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve HI department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve HI attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Idaho (ID)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://sosbiz.idaho.gov/search/business` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve ID board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve ID board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve ID licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve ID dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve ID regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve ID department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve ID attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Illinois (IL)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://apps.ilsos.gov/businessentitysearch/` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve IL board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve IL board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve IL licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve IL dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve IL regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve IL department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve IL attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Indiana (IN)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://bsd.sos.in.gov/publicbusinesssearch` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve IN board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve IN board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve IN licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve IN dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve IN regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve IN department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve IN attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Iowa (IA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://sos.iowa.gov/search/business/search.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve IA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve IA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve IA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve IA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve IA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve IA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve IA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Kansas (KS)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.sos.ks.gov/eforms/BusinessEntity/Search.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve KS board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve KS board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve KS licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve KS dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve KS regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve KS department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve KS attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Kentucky (KY)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://web.sos.ky.gov/bussearchnprofile/search.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve KY board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve KY board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve KY licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve KY dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve KY regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve KY department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve KY attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Louisiana (LA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://coraweb.sos.la.gov/CommercialSearch/CommercialSearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve LA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve LA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve LA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve LA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve LA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve LA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve LA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Maine (ME)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://apps3.web.maine.gov/nei-sos-icrs/ICRS` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve ME board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve ME board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve ME licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve ME dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve ME regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve ME department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve ME attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Maryland (MD)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://egov.maryland.gov/BusinessExpress/EntitySearch` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve MD board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve MD board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve MD licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve MD dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve MD regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve MD department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve MD attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Massachusetts (MA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://corp.sec.state.ma.us/CorpWeb/CorpSearch/CorpSearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve MA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve MA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve MA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve MA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve MA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve MA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve MA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Michigan (MI)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://cofs.lara.state.mi.us/SearchApi/Search/Search` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve MI board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve MI board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve MI licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve MI dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve MI regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve MI department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve MI attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Minnesota (MN)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://mblsportal.sos.state.mn.us/Business/Search` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve MN board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve MN board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve MN licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve MN dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve MN regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve MN department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve MN attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Mississippi (MS)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://corp.sos.ms.gov/corp/portal/c/page/corpBusinessIdSearch/portal.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve MS board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve MS board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve MS licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve MS dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve MS regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve MS department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve MS attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Missouri (MO)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://bsd.sos.mo.gov/BusinessEntity/BESearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve MO board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve MO board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve MO licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve MO dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve MO regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve MO department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve MO attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Montana (MT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://biz.sosmt.gov/search/business` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve MT board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve MT board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve MT licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve MT dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve MT regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve MT department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve MT attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Nebraska (NE)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.nebraska.gov/sos/corp/corpsearch.cgi` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve NE board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve NE board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve NE licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve NE dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve NE regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve NE department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve NE attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Nevada (NV)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://esos.nv.gov/EntitySearch/OnlineEntitySearch` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve NV board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve NV board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve NV licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve NV dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve NV regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve NV department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve NV attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## New Hampshire (NH)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://quickstart.sos.nh.gov/online/BusinessInquire` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve NH board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve NH board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve NH licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve NH dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve NH regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve NH department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve NH attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## New Jersey (NJ)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.njportal.com/DOR/BusinessNameSearch/Search/BusinessName` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve NJ board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve NJ board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve NJ licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve NJ dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve NJ regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve NJ department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve NJ attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## New Mexico (NM)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://enterprise.sos.nm.gov/search/business` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve NM board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve NM board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve NM licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve NM dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve NM regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve NM department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve NM attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## New York (NY)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://apps.dos.ny.gov/publicInquiry/` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve NY board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve NY board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve NY licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve NY dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve NY regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve NY department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve NY attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## North Carolina (NC)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.sosnc.gov/online_services/search/by_title/_Business_Registration` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve NC board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve NC board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve NC licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve NC dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve NC regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve NC department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve NC attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## North Dakota (ND)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://firststop.sos.nd.gov/search/business` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve ND board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve ND board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve ND licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve ND dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve ND regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve ND department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve ND attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Ohio (OH)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://businesssearch.ohiosos.gov/` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve OH board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve OH board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve OH licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve OH dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve OH regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve OH department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve OH attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Oklahoma (OK)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.sos.ok.gov/corp/corpInquiryFind.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve OK board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve OK board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve OK licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve OK dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve OK regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve OK department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve OK attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Oregon (OR)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://egov.sos.state.or.us/br/pkg_web_name_srch_inq.login` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve OR board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve OR board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve OR licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve OR dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve OR regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve OR department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve OR attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Pennsylvania (PA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://file.dos.pa.gov/search/business` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve PA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve PA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve PA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve PA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve PA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve PA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve PA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Rhode Island (RI)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://business.sos.ri.gov/CorpWeb/CorpSearch/CorpSearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve RI board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve RI board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve RI licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve RI dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve RI regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve RI department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve RI attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## South Carolina (SC)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://businessfilings.sc.gov/BusinessFiling/Entity/Search` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve SC board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve SC board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve SC licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve SC dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve SC regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve SC department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve SC attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## South Dakota (SD)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://sosenterprise.sd.gov/BusinessServices/Business/FilingSearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve SD board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve SD board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve SD licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve SD dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve SD regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve SD department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve SD attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Tennessee (TN)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://tnbear.tn.gov/Ecommerce/FilingSearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve TN board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve TN board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve TN licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve TN dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve TN regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve TN department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve TN attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Texas (TX)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://mycpa.cpa.state.tx.us/coa/` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve TX board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve TX board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve TX licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve TX dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve TX regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve TX department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve TX attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Utah (UT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://secure.utah.gov/bes/` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve UT board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve UT board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve UT licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve UT dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve UT regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve UT department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve UT attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Vermont (VT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://bizfilings.vermont.gov/online/BusinessInquire` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve VT board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve VT board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve VT licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve VT dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve VT regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve VT department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve VT attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Virginia (VA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://cis.scc.virginia.gov/EntitySearch/Index` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve VA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve VA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve VA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve VA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve VA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve VA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve VA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Washington (WA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://ccfs.sos.wa.gov/#/BusinessSearch` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve WA board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve WA board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve WA licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve WA dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve WA regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve WA department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve WA attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## West Virginia (WV)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://apps.wv.gov/SOS/BusinessEntitySearch/` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve WV board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve WV board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve WV licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve WV dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve WV regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve WV department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve WV attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Wisconsin (WI)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://www.wdfi.org/apps/CorpSearch/Search.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve WI board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve WI board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve WI licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve WI dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve WI regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve WI department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve WI attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## Wyoming (WY)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://wyobiz.wyo.gov/Business/FilingSearch.aspx` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve WY board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve WY board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve WY licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve WY dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve WY regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve WY department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve WY attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

## District of Columbia (DC)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business entity search | `https://corponline.dcp.com/` | Official registry; UI/session behaviour may vary |
| CPA/accountancy | `https://nasba.org/stateboards/` | Resolve DC board; use CPAverify where participating |
| Physicians | `https://www.fsmb.org/contact-a-state-medical-board/` | Resolve DC board and complaint channel |
| Lawyers | `https://www.americanbar.org/groups/legal_services/flh-home/flh-lawyer-licensing/` | Resolve DC licensing authority |
| Dentists | `https://www.aadexam.org/state-boards` | Resolve DC dental board |
| Real estate | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Resolve DC regulator |
| Contractors/builders | `https://www.nascla.org/page/MemberAgencies` | Resolve state board where statewide licensing applies |
| Mortgage professionals | `https://www.nmlsconsumeraccess.org/` | Nationwide record |
| Insurance | `https://content.naic.org/state-insurance-departments` | Resolve DC department |
| Consumer/enforcement | `https://www.naag.org/find-my-ag/` | Resolve DC attorney general |
| Childcare | `https://childcare.gov/consumer-education/find-child-care` | Resolve state inspection/licensing system |

**State caveat:** county and municipal licensing can supplement or replace statewide licensing for contractors, trades, childcare, health facilities and local businesses. Query the relevant official county/city portal where state coverage is incomplete.

