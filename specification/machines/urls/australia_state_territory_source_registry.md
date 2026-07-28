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

# Australia — Commonwealth and State/Territory Sources

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

## Commonwealth sources

| Category | Source | URL | Access |
|---|---|---|---|
| Business identity | ABN Lookup | `https://abr.business.gov.au/` | Stable landing/UI |
| Known ABN | ABN record | `https://abr.business.gov.au/ABN/View?id={abn_digits_only}` | GET template |
| Companies/business names | ASIC Registry Search | `https://service.asic.gov.au/companysearch/` | UI/session-driven |
| Professional registers | ASIC | `https://asic.gov.au/online-services/search-asic-registers/professional-registers-search/` | Stable landing/UI |
| Insolvency notices | ASIC Published Notices | `https://publishednotices.asic.gov.au/` | UI |
| Tax/BAS agents | Tax Practitioners Board | `https://myprofile.tpb.gov.au/public-register/` | UI/POST |
| Health practitioners | AHPRA | `https://www.ahpra.gov.au/Registration/Registers-of-Practitioners.aspx` | UI/POST |
| Financial advisers | Moneysmart/ASIC | `https://moneysmart.gov.au/financial-advice/financial-advisers-register` | UI |
| Charities | ACNC | `https://www.acnc.gov.au/charity/charities` | UI |
| NDIS providers | NDIS | `https://www.ndis.gov.au/participants/working-providers/find-registered-provider` | UI |
| Competition/enforcement | ACCC search | `https://www.accc.gov.au/search?query={business_name}` | GET template |
| Privacy actions | OAIC | `https://www.oaic.gov.au/search?query={business_name}` | GET pattern |
| Legal decisions | AustLII | `https://www.austlii.edu.au/cgi-bin/sinosrch.cgi?query=%22{business_name}%22&method=auto&meta=%2Fau` | GET template |
| Architects | AACA register directory | `https://aaca.org.au/registration-as-an-architect/architect-registers/` | Directory |
| Childcare quality | ACECQA | `https://www.acecqa.gov.au/resources/national-registers` | UI/data |
| Childcare discovery | Starting Blocks | `https://www.startingblocks.gov.au/find-child-care` | UI |
| Aged care | My Aged Care | `https://www.myagedcare.gov.au/find-a-provider` | UI |

## Australian Capital Territory (ACT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://www.accesscanberra.act.gov.au/s/public-registers` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://www.actlawsociety.asn.au/find-a-lawyer` | Professional directory/register |
| Builders/trades | `https://www.accesscanberra.act.gov.au/s/public-registers` | Licence/practitioner search |
| Real estate/property | `https://www.accesscanberra.act.gov.au/s/public-registers` | Licence/register search |
| Courts/decisions | `https://www.courts.act.gov.au/` | Official judgments or court portal |
| Consumer/enforcement | `https://www.accesscanberra.act.gov.au/consumer-rights` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

## New South Wales (NSW)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://verify.licence.nsw.gov.au/` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://www.lawsociety.com.au/register-of-solicitors` | Professional directory/register |
| Builders/trades | `https://verify.licence.nsw.gov.au/home/Trades` | Licence/practitioner search |
| Real estate/property | `https://verify.licence.nsw.gov.au/home/Property` | Licence/register search |
| Courts/decisions | `https://www.caselaw.nsw.gov.au/` | Official judgments or court portal |
| Consumer/enforcement | `https://www.fairtrading.nsw.gov.au/` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

## Northern Territory (NT)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://nt.gov.au/industry/licences` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://lawsocietynt.asn.au/find-a-lawyer/` | Professional directory/register |
| Builders/trades | `https://nt.gov.au/property/building-and-development/building-practitioners-and-certifiers/search-the-building-practitioners-register` | Licence/practitioner search |
| Real estate/property | `https://nt.gov.au/industry/licences/real-estate-agent-licence` | Licence/register search |
| Courts/decisions | `https://supremecourt.nt.gov.au/decisions` | Official judgments or court portal |
| Consumer/enforcement | `https://consumeraffairs.nt.gov.au/` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

## Queensland (QLD)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://www.qld.gov.au/law/laws-regulated-industries-and-accountability/queensland-laws-and-regulations/fair-trading-services-programs-and-resources/fair-trading-services/licence-check` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://www.qls.com.au/Find-a-Solicitor` | Professional directory/register |
| Builders/trades | `https://www.qbcc.qld.gov.au/licence-search` | Licence/practitioner search |
| Real estate/property | `https://www.qld.gov.au/law/laws-regulated-industries-and-accountability/queensland-laws-and-regulations/fair-trading-services-programs-and-resources/fair-trading-services/licence-check` | Licence/register search |
| Courts/decisions | `https://www.sclqld.org.au/caselaw` | Official judgments or court portal |
| Consumer/enforcement | `https://www.qld.gov.au/law/fair-trading` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

## South Australia (SA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://secure.cbs.sa.gov.au/OccLicPubReg/LicenceSearch.php` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://www.lawsocietysa.asn.au/Public/Find_a_Lawyer.aspx` | Professional directory/register |
| Builders/trades | `https://secure.cbs.sa.gov.au/OccLicPubReg/LicenceSearch.php` | Licence/practitioner search |
| Real estate/property | `https://secure.cbs.sa.gov.au/OccLicPubReg/LicenceSearch.php` | Licence/register search |
| Courts/decisions | `https://www.courts.sa.gov.au/judgments/` | Official judgments or court portal |
| Consumer/enforcement | `https://www.cbs.sa.gov.au/` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

## Tasmania (TAS)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://www.cbos.tas.gov.au/topics/licensing-and-registration/search-licence-registers` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://lst.org.au/find-a-lawyer/` | Professional directory/register |
| Builders/trades | `https://www.cbos.tas.gov.au/topics/licensing-and-registration/search-licence-registers` | Licence/practitioner search |
| Real estate/property | `https://www.cbos.tas.gov.au/topics/licensing-and-registration/search-licence-registers` | Licence/register search |
| Courts/decisions | `https://www.supremecourt.tas.gov.au/decisions/` | Official judgments or court portal |
| Consumer/enforcement | `https://www.cbos.tas.gov.au/` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

## Victoria (VIC)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://registers.consumer.vic.gov.au/` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://lsbc.vic.gov.au/register-of-lawyers` | Professional directory/register |
| Builders/trades | `https://www.vba.vic.gov.au/tools/find-practitioner` | Licence/practitioner search |
| Real estate/property | `https://registers.consumer.vic.gov.au/` | Licence/register search |
| Courts/decisions | `https://www.austlii.edu.au/cgi-bin/viewdb/au/cases/vic/` | Official judgments or court portal |
| Consumer/enforcement | `https://www.consumer.vic.gov.au/` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

## Western Australia (WA)

| Evidence class | Official entry point | Access/notes |
|---|---|---|
| Business identity | `https://abr.business.gov.au/` | Commonwealth ABN identity; ASIC separately for companies |
| Occupational licences | `https://www.commerce.wa.gov.au/consumer-protection/licence-search` | Stable landing/UI; profession-specific forms |
| Solicitors/lawyers | `https://www.lawsocietywa.asn.au/find-a-lawyer/` | Professional directory/register |
| Builders/trades | `https://www.commerce.wa.gov.au/building-and-energy/find-registered-building-service-provider` | Licence/practitioner search |
| Real estate/property | `https://www.commerce.wa.gov.au/consumer-protection/licence-search` | Licence/register search |
| Courts/decisions | `https://www.supremecourt.wa.gov.au/J/judgments.aspx` | Official judgments or court portal |
| Consumer/enforcement | `https://www.commerce.wa.gov.au/consumer-protection` | Complaints, warnings and licence context |
| Childcare | `https://www.startingblocks.gov.au/find-child-care` | National finder plus ACECQA quality data |

**Health:** use AHPRA nationally, then state health-department or tribunal sources for facility and enforcement evidence.  
**Accountants/tax agents:** use ABN/ASIC identity, TPB registration and claimed professional-body membership separately.  
**Financial services:** use ASIC professional registers and the Financial Advisers Register.  
**Architects:** resolve the relevant state registration board from AACA.

