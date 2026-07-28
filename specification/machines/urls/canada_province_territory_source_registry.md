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

# Canada — Federal, Provincial and Territorial Sources

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

## Federal and national resolvers

| Category | Source | URL | Access |
|---|---|---|---|
| Multi-jurisdiction business search | Canada Business Registries | `https://ised-isde.canada.ca/cbr-rec/en/search` | UI; reuse restrictions |
| Federal corporations | Corporations Canada | `https://ised-isde.canada.ca/cc/web/isc/srch` | UI |
| Financial institutions | OSFI | `https://www.osfi-bsif.gc.ca/en/supervision/regulated-institutions` | Lists/registers |
| Securities registrants | CSA | `https://info.securities-administrators.ca/nrsmobile/nrssearch.aspx` | UI |
| Investment dealers/advisers | CIRO | `https://advisorreport.ciro.ca/` | UI |
| Lawyers | Federation of Law Societies | `https://flsc.ca/about-us/our-members-canadas-law-societies/` | Resolver |
| Medical regulators | Medical Council of Canada | `https://mcc.ca/about/partner-organizations/medical-regulatory-authorities/` | Resolver |
| Real estate regulators | ARELLO | `https://www.arello.org/index.cfm/resources/regulatory-agencies/` | Directory |
| Competition cases | Competition Bureau | `https://competition-bureau.canada.ca/en/search/node?keys={business_name}` | GET template |
| Product recalls | Health Canada | `https://recalls-rappels.canada.ca/en/search/site?search_api_fulltext={business_name}` | GET template |
| Legal decisions | CanLII | `https://www.canlii.org/en/#search/text=%22{business_name}%22` | UI/hash |
| Privacy findings | OPC | `https://www.priv.gc.ca/en/opc-actions-and-decisions/investigations/` | UI |
| Consumer offices | ISED | `https://ised-isde.canada.ca/site/office-consumer-affairs/en/information-canadian-consumers/provincial-and-territorial-consumer-affairs-offices` | Directory |

## Alberta (AB)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.alberta.ca/find-corporation-details` | Provincial/territorial registry or official access page |
| Lawyers | `https://www.lawsociety.ab.ca/public/lawyer-referral/find-a-lawyer/` | Law society register/directory |
| Physicians/health resolver | `https://search.cpsa.ca/` | Physician register or licensing portal |
| Real estate | `https://www.reca.ca/consumers/tools-resources/licensee-search/` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.alberta.ca/lookup-a-licensed-business` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## British Columbia (BC)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.bcregistry.gov.bc.ca/` | Provincial/territorial registry or official access page |
| Lawyers | `https://www.lawsociety.bc.ca/working-with-lawyers/finding-a-lawyer/` | Law society register/directory |
| Physicians/health resolver | `https://www.cpsbc.ca/public/registrant-directory` | Physician register or licensing portal |
| Real estate | `https://www.bcfsa.ca/public-resources/real-estate/find-professional` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.bchousing.org/licensing-consumer-services/licence-registry` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Manitoba (MB)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://companiesoffice.gov.mb.ca/` | Provincial/territorial registry or official access page |
| Lawyers | `https://lawsociety.mb.ca/for-the-public/finding-a-lawyer/` | Law society register/directory |
| Physicians/health resolver | `https://cpsm.mb.ca/physician-directory` | Physician register or licensing portal |
| Real estate | `https://realestate.mb.ca/registrant-search/` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.gov.mb.ca/consumerinfo/` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## New Brunswick (NB)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www2.snb.ca/content/snb/en/sites/corporate-registry.html` | Provincial/territorial registry or official access page |
| Lawyers | `https://lsbnb.alinityapp.com/Client/PublicDirectory` | Law society register/directory |
| Physicians/health resolver | `https://cpsnb.org/en/physician-search` | Physician register or licensing portal |
| Real estate | `https://fcnb.ca/en/real-estate` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www2.snb.ca/content/snb/en/sites/consumer-affairs.html` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Newfoundland and Labrador (NL)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://cado.eservices.gov.nl.ca/CadoInternet/Company/CompanyMain.aspx` | Provincial/territorial registry or official access page |
| Lawyers | `https://lsnl.ca/lawyer-search/` | Law society register/directory |
| Physicians/health resolver | `https://cpsnl.ca/physician-search/` | Physician register or licensing portal |
| Real estate | `https://www.gov.nl.ca/dgsnl/realestate/` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.gov.nl.ca/dgsnl/consumer/` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Northwest Territories (NT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.justice.gov.nt.ca/en/corporate-registries/` | Provincial/territorial registry or official access page |
| Lawyers | `https://lawsociety.nt.ca/lawyer-directory/` | Law society register/directory |
| Physicians/health resolver | `https://www.hss.gov.nt.ca/en/services/professional-licensing` | Physician register or licensing portal |
| Real estate | `https://www.justice.gov.nt.ca/en/real-estate-licensing/` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.maca.gov.nt.ca/en/services/consumer-affairs` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Nova Scotia (NS)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://beta.novascotia.ca/search-business-or-non-profit-information-filed-registry-joint-stock-companies` | Provincial/territorial registry or official access page |
| Lawyers | `https://members.nsbs.org/LawyerSearch` | Law society register/directory |
| Physicians/health resolver | `https://cpsnsphysiciansearch.azurewebsites.net/` | Physician register or licensing portal |
| Real estate | `https://www.nsrec.ns.ca/consumer-resources/licensee-search` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://beta.novascotia.ca/programs-and-services/consumer-affairs` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Nunavut (NU)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.gov.nu.ca/en/justice/legal-registries` | Provincial/territorial registry or official access page |
| Lawyers | `https://www.lawsociety.nu.ca/en/lawyer-directory` | Law society register/directory |
| Physicians/health resolver | `https://www.gov.nu.ca/en/health/health-professional-licensing` | Physician register or licensing portal |
| Real estate | `https://www.gov.nu.ca/en/community-and-government-services/consumer-affairs` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.gov.nu.ca/en/community-and-government-services/consumer-affairs` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Ontario (ON)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.ontario.ca/page/ontario-business-registry` | Provincial/territorial registry or official access page |
| Lawyers | `https://lso.ca/public-resources/finding-a-lawyer-or-paralegal/lawyer-and-paralegal-directory` | Law society register/directory |
| Physicians/health resolver | `https://doctors.cpso.on.ca/` | Physician register or licensing portal |
| Real estate | `https://registrantsearch.reco.on.ca/` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.skilledtradesontario.ca/public-register/` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Prince Edward Island (PE)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.princeedwardisland.ca/en/service/search-the-pei-business-corporate-registry` | Provincial/territorial registry or official access page |
| Lawyers | `https://lawsocietypei.ca/find-a-lawyer/` | Law society register/directory |
| Physicians/health resolver | `https://cpspei.ca/physician-search/` | Physician register or licensing portal |
| Real estate | `https://www.princeedwardisland.ca/en/information/justice-and-public-safety/real-estate-salespersons-and-agents` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.princeedwardisland.ca/en/topic/consumer-services` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Quebec (QC)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.registreentreprises.gouv.qc.ca/REQNA/GR/GR03/GR03A71.RechercheRegistre.MVC/GR03A71` | Provincial/territorial registry or official access page |
| Lawyers | `https://www.barreau.qc.ca/en/directory-lawyers/` | Law society register/directory |
| Physicians/health resolver | `https://www.cmq.org/en/directory-physicians` | Physician register or licensing portal |
| Real estate | `https://www.oaciq.com/en/find-broker` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://www.pes.rbq.gouv.qc.ca/RegistreLicences` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Saskatchewan (SK)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://www.isc.ca/CorporateRegistry/Findanexistingbusiness/Pages/default.aspx` | Provincial/territorial registry or official access page |
| Lawyers | `https://www.lawsociety.sk.ca/find-a-lawyer/` | Law society register/directory |
| Physicians/health resolver | `https://www.cps.sk.ca/imis/CPSS/Physician_Summary/Physician_Profile.aspx` | Physician register or licensing portal |
| Real estate | `https://www.srec.ca/consumer-info/find-a-registrant/` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://fcaa.gov.sk.ca/consumers-investors-pension-plan-members/consumers` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

## Yukon (YT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business/corporate registry | `https://ycor-reey.gov.yk.ca/` | Provincial/territorial registry or official access page |
| Lawyers | `https://lawsocietyyukon.com/find-a-lawyer/` | Law society register/directory |
| Physicians/health resolver | `https://yukon.ca/en/doing-business/professional-licensing` | Physician register or licensing portal |
| Real estate | `https://yukon.ca/en/doing-business/licensing/real-estate-professional-licence` | Regulator/licence search or official guidance |
| Trades/building/consumer | `https://yukon.ca/en/consumer-services` | Register, licensing portal or consumer regulator |

**Additional profession checks:** resolve dentists, psychologists, veterinarians, accountants, mortgage brokers, insurance agents, architects and childcare providers through the province’s statutory regulator. Never treat a federal corporation record as proof of a provincial professional licence.

