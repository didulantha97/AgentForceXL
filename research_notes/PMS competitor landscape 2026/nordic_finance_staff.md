# Nordic finance/compliance and staff-management requirements for a hotel + property management suite (as of 21 Nov 2026)

Scope note: Sweden first, then the other Nordic countries. I made 15 tool calls. Where a point comes from background knowledge and not from a source fetched in this session, it is marked **[unverified]** and kept under Inferences or Gaps, not Cited Findings.

## 1. Mandatory Swedish/Nordic compliance for hotels and landlords

### Takeaway

The firmest Swedish deadline is **1 January 2027**, the same month as go-live: every cash register in use must meet SKVFS 2021:17. Each register must be manufacturer-declared (tillverkardeklarerat), connected to a control unit or control system, registered with Skatteverket, and able to export its journal in XML. Any hotel POS or front-desk counter sale paid by card, cash or Swish is in scope unless the sale is invoiced. Other items are moving targets: VAT (accommodation 12%; food temporarily 6%), tourist taxes (Norway municipal 3% from 2027; Finland bill pending; Denmark shelved; none in Sweden), and e-invoicing (Peppol mandatory for Swedish public sector; ViDA cross-border B2B from 1 July 2030; Swedish domestic B2B mandate under inquiry, report due 30 Nov 2027).

### Cited Findings

**Kassaregisterlagen (cash register law)**

- From 1 January 2027, a business's cash register must meet SKVFS 2021:17. It must be manufacturer-declared and connected to a control unit (kontrollenhet) or control system (kontrollsystem). If it has a journal memory, it must be able to produce registrations in XML. Usage rules are in SKVFS 2021:18, control units in SKVFS 2016:1 and control systems in SKVFS 2020:9 — [Skatteverket: Kassaregister](https://www.skatteverket.se/foretag/drivaforetag/kassaregister)
- Businesses that take cash or card payments, including electronic payments such as Swish, must record those sales in a cash register. The register must be reported to Skatteverket before use, through its e-service — [Skatteverket](https://www.skatteverket.se/foretag/drivaforetag/kassaregister); [Så här anmäler du kassaregister](https://skatteverket.se/foretag/drivaforetag/kassaregister/saharanmalerdukassaregister)
- Skatteverket does not test whether a manufacturer-declared register meets the requirements; the manufacturer is responsible. Skatteverket can make unannounced inspections and can ask to see the control codes for each receipt — [Skatteverket tillsyns- och kontrollbesök](https://www.skatteverket.se/foretag/drivaforetag/kassaregister/tillsynsochkontrollbesok)
- Exemptions:
  - Invoiced sales are not covered ("kassaregisterkravet inte gäller fakturerad försäljning"). A cash invoice issued at payment must still meet bookkeeping rules.
  - Businesses with cash and card sales of at most 4 prisbasbelopp including VAT per year are exempt; that is SEK 236,800 for 2026.
  - Other exempt activities: taxi, distance sales, unstaffed or automated sales, tax-exempt entities and some gambling.
  - Accommodation is **not** listed as exempt.
  - Source: [Skatteverket: Vissa verksamheter är undantagna](https://www.skatteverket.se/foretag/drivaforetag/kassaregister/vissaverksamheterarundantagnafrankravetpakassaregister)
- Skatteverket published an inquiry into a review of the cash register rules (dated 16 March 2026), so the rules may change after 2027 — [Skatteverket utredning PDF](https://skatteverket.se/download/18.70685bee19c85dd5dd02aeb/1773751310702/utredning-om-en-oversyn-av-reglerna-om-kassaregister.pdf)
- Mews launched Mews POS in Sweden, which posts transactions to the PMS automatically. This suggests competitors treat a Swedish-compliant POS as table stakes — [Mews community](https://community.mews.com/mews-pos-restaurant-operations-90/mews-pos-is-now-live-in-sweden-3115)

**VAT (Sweden)**

- Hotel and camping accommodation is taxed at 12%, as are restaurant and café services — [Skatteverket VAT rates](https://www.skatteverket.se/servicelankar/otherlanguages/inenglish/businessesandemployers/declaringtaxesbusinesses/vat/vatratesongoodsandservices.4.676f4884175c97df419255d.html)
- Food VAT is temporarily cut from 12% to 6% from **1 April 2026 to 31 December 2027**. Eat-in restaurant service stays at 12%; takeaway food falls to 6%. Alcohol and tap water are excluded; bottled water is included — [Riksdagen](https://www.riksdagen.se/en/news/articles/2026/feb/25/temporarily-reduced-vat-on-food_cmsd274f5ec-c794-4c1f-8eaf-7811a27dfcb5en/); [KPMG](https://kpmg.com/us/en/taxnewsflash/news/2026/04/sweden-temporary-reduced-vat-rate-food-bottled-water.html); [vatcalc](https://vatcalc.com/sweden/sweden-halves-food-vat-to-6-till-dec-2027)

**Tourist / city tax**

- **Norway:**
  - The visitor contribution is municipal and optional, at a fixed 3% of the accommodation price before VAT.
  - There is no nationwide tax.
  - As of September 2026, five municipalities had submitted plans: Tromsø, Lyngen, Karlsøy, Vågan and Stranda.
  - Tromsø has voted to introduce it from 2027, subject to government approval.
  - Sources: [Visit Norway](https://www.visitnorway.com/travel-trade/visitor-contribution-accommodation-tax/); [Life in Norway](https://www.lifeinnorway.net/?p=86767)
  - Start date conflict: Life in Norway says municipalities can levy from 2027 (the law took effect 1 July 2026), while [BlogTo](https://www.blogto.com/travel/2026/04/norway-tax-canada-travel/) says the charge "kicks in" 1 July 2026. The 2027 municipal start is more consistent.
- **Denmark:** A DKK 20 per night charge for Copenhagen and Aarhus was missing from the government's 2027 finance bill (October 2026) and its legislative programme, so it appears shelved. A separate cruise passenger tax of DKK 200 per call has been proposed — [Life in Norway, Nordic roundup](https://www.lifeinnorway.net/?p=86767); [Seatrade Cruise](https://www.seatrade-cruise.com/ports-destinations/denmark-s-cruise-tax-threatens-baltic-ports-industry-warns)
- **Finland:** The Finance Ministry is drafting a law to let municipalities levy 2–5% of the accommodation price before VAT. It is still in the legislative process — [Fodor's](https://www.fodors.com/world/europe/finland/experiences/news/finland-tourist-tax-proposal-could-raise-travel-costs-for-visitors)
- **Sweden:** I found no national or municipal tourist tax. Some municipalities have argued for one — [Life in Norway](https://www.lifeinnorway.net/?p=86767)

**E-invoicing / Peppol / ViDA**

- B2G e-invoicing in Sweden has been mandatory since 2019. B2B is not mandatory — [Chift](https://www.chift.eu/blog/the-accounting-software-landscape-in-sweden-a-2026-guide-for-saas-vendors); [ecosio](https://ecosio.com/en/compliance/sweden/e-invoicing/)
- ViDA: structured e-invoices and digital reporting are required for intra-EU cross-border B2B from **1 July 2030**, replacing EC Sales Lists — [Forvis Mazars](https://www.forvismazars.com/se/en/services/tax/indirect-taxes/sweden-vat-in-the-digital-age-vida); [TrueCommerce](https://www.truecommerce.com/en-gb/blog/vida-e-invoicing-requirements/)
- Sweden appointed a special investigator in February 2026 to examine a domestic mandate, with a final report due by **30 November 2027**. No implementation date has been published. Format expectations are Peppol BIS Billing 3.0 / EN 16931. Peppol responsibilities were moving to Upphandlingsmyndigheten (March 2026) — [Comarch](https://www.comarch.com/trade-and-services/data-management/legal-regulation-changes/sweden-launches-official-inquiry-into-mandatory-e-invoicing-implementation/); [vatcalc](https://www.vatcalc.com/sweden/sweden-progresses-mandatory-e-invoicing/); [ecosio](https://ecosio.com/en/compliance/sweden/e-invoicing/)

**NIS2**

- Sweden's Cybersecurity Act (2025:1506) and Ordinance (2025:1507) entered into force on **15 January 2026**, replacing the NIS Act (2018:1174).
  - Scope is the NIS2 Annex I and II sectors, for medium-sized or larger entities established in Sweden.
  - Incident reporting has applied from 15 January 2026; registration is with the Swedish Civil Defence and Resilience Agency (Myndigheten för civilt försvar).
  - Sources: [Energimyndigheten](https://www.energimyndigheten.se/en/news/2026/new-cybersecurity-act-enters-into-force-in-sweden/); [Deloitte](https://www.deloitte.com/se/sv/services/legal/perspectives/nis2-now-in-force.html); [Lindahl](https://www.lindahl.se/en/expertise/national-security-trade-control/new-cybersecurity-act-implementation-of-the-nis2-directive-in-swedish-law/)

### Inferences

- **Mandatory for the January 2027 Swedish launch:** a cash-register-compliant POS and front-desk payment flow, or a deliberate design where all guest sales go through invoices.
  - A Salesforce-native folio that takes card or Swish at checkout counts as a "kassaregister" use case. Either the suite is manufacturer-declared and integrates with a certified control unit or cloud control system, or it hands POS to a certified third party (Mews POS, Caspeco, Trivec, etc.) and imports the Z-reports.
  - The second path is far less risky for January 2027. Becoming a manufacturer-declared register is a regulatory product in its own right.
- **Tax engine:** VAT needs per-line rates (12% accommodation, 12% eat-in, 6% takeaway food until 31 Dec 2027, 25% alcohol and most other services **[unverified 25% default; standard Swedish rate]**) with effective-dated rate tables. The food rate reverts on 1 Jan 2028.
- City tax is **not** needed for Sweden. A configurable "percentage of net accommodation price, per municipality" engine covers Norway (3%) and future Finland (2–5%). It is a nice-to-have for 2027 and needed when the first Norwegian client lands in Tromsø, Lofoten or Stranda.
- Peppol e-invoicing is **mandatory only when billing Swedish public-sector customers** (e.g., municipalities booking rooms, allmännyttan as a customer). The usual route is an access point via Fortnox, Visma, Pagero or InExchange, not building one. Cross-border B2B (for example, corporate accounts in other EU states) becomes mandatory 1 July 2030.
- NIS2: accommodation is not, to my knowledge, an Annex I/II sector **[unverified]**, so most hotels are out of scope. Larger landlords may be in scope through district heating or energy subsectors, and as an ISV/cloud provider the vendor may face supply-chain security questionnaires. Treat it as a security-posture selling point, not a feature.
- **[unverified background]**
  - GDPR applies fully: guest data, passport/ID data, staff data, Article 30 records, data subject requests and retention.
  - Swedish Bokföringslagen requires accounting records to be kept for 7 years, which drives audit-trail and immutable-folio requirements.
  - PCI DSS v4.0.1 future-dated requirements became mandatory on 31 March 2025. A Salesforce PMS should never store PAN data and should use PSP tokenisation (Adyen/Stripe/Nexi) to stay at SAQ A / A-EP.
- **[unverified background]** Hyreslagen (Jordabalken chapter 12) shapes landlord features: written lease terms, notice periods, rent negotiation via Hyresgästföreningen (förhandlingsordning), utility/indexed rent changes, and deposit handling. Rent invoices are invoiced sales, so the cash register law does not apply to rent.

### Gaps

- I could not confirm whether Skatteverket treats hotel room sales settled at reception by card as cash-register sales, or whether a hotel folio closed with a receipt counts as a "cash invoice". The exemption page is silent on accommodation. Skatteverket or a kassaregister specialist should confirm.
- The difference between a hardware "kontrollenhet" and a cloud "kontrollsystem" (SKVFS 2020:9) was not explained on the pages fetched. This matters for a cloud/Salesforce architecture.
- I did not fetch primary sources for SIE4 (SIE-gruppen spec), PCI DSS, GDPR guidance from IMY, BankID, or hyreslagen.
- The final status of Norway's municipal approvals for 2027 has not been confirmed.

## 2. Accounting systems: market share in Sweden/Nordics and APIs

### Takeaway

Fortnox dominates the Swedish SME market (about 600k customers, about 37% estimated share). Visma is the clear second, with eEkonomi now rebranded "Visma Spiris" and Visma Net for larger customers. Mid-market and chains use Microsoft Dynamics (Business Central), Unit4 and Xledger. An integration-first priority list for Sweden is: **SIE4 export (universal) → Fortnox API → Visma (Spiris/eAccounting + Visma Net) → Business Central**. Xero and QuickBooks have negligible Swedish share.

### Cited Findings

- Fortnox had 612,000 customers in Q1 2025 (585,000 at Q3 2024), with an estimated 37% share of Swedish companies, associations and organisations (Placera estimate, date unclear) — [search summary of Fortnox/Realtid reporting](https://www.realtid.se/bors-finans/68-procent-upp-fortnox/); [Fortnox about](https://www.fortnox.se/about-us/)
- EQT made a bid for Fortnox (Realtid) — [Realtid](https://www.realtid.se/spara-placera/eqts-bud-pa-fortnox-en-exitmojlighet-for-aktieagarna/)
- Freja eID is being added for roughly half a million Fortnox customers. This shows Fortnox's ecosystem reach and an e-ID alternative to BankID — [Inderes/Freja release](https://www.inderes.fi/sv/releases/freja-eid-group-frejas-e-legitimation-laggs-till-for-runt-en-halv-miljon-fortnox-kunder)
- Visma group reported 2.4 million customers in 2025, with Nordic/European customers up 22% — [Pleo blog summary](https://blog.pleo.io/se/bokforingsprogram) (group figure, not eEkonomi-specific)
- Swedish landscape according to Chift (a vendor marketing piece, survey of 67 Swedish respondents):
  - Fortnox is the market leader; it is "often cited as present in 80% or more of firms with five or more employees".
  - Visma Spiris (formerly eEkonomi) is the second ecosystem.
  - Microsoft Dynamics, Unit4 and Xledger serve mid-market and larger companies.
  - Björn Lundén and Hogia are accountant-facing; Finago (formerly 24SevenOffice) is growing; SpeedLedger serves small firms.
  - Sweden has about 1.2M SMEs; Srf konsulterna has about 7,000 members serving about 330,000 companies.
  - Source: [Chift](https://www.chift.eu/blog/the-accounting-software-landscape-in-sweden-a-2026-guide-for-saas-vendors)
- Fortnox maintains an integration marketplace and an accounting-firm portal (Fortnox Access) — [Fortnox integrationer](https://www.fortnox.se/kopplingar/integrationer?categoryId=10); [Fortnox Access](https://www.fortnox.se/byra/fortnox-access)

### Inferences

- **[unverified background]**
  - Fortnox offers a REST API with OAuth2. It requires a Fortnox integration-partner agreement and listing in its marketplace, and customers need the right Fortnox licence for API access.
  - Visma eAccounting/Spiris has a REST API via the Visma Developer Portal; Visma Net has its own ERP API.
  - Business Central exposes OData/REST APIs.
  - SIE4 is the de facto Swedish file format for exchanging verifications and balances. Every Swedish accounting system imports it, so a SIE4 export of daily revenue journals is the cheapest universal integration and works with PE Accounting, Bokio, Björn Lundén and others.
- A hotel PMS usually posts daily summarised journals (revenue by account and VAT code, payments by tender, city ledger/AR) instead of individual invoices. GL-mapping rules (product → account + VAT code + cost centre/project) are therefore a mandatory core feature, whatever connector is used.
- Multi-client ISV: Norway's market is Visma-heavy (Tripletex, Visma eAccounting, PowerOffice), and Denmark has e-conomic (Visma) and Dinero **[unverified]**. Abstract the GL connector behind one interface.

### Gaps

- No verified 2026 customer count for Fortnox, and no Swedish share figures for Visma Spiris, Bokio, PE Accounting, Business Central or Unit4.
- API terms (fees, partner requirements, rate limits) were not verified from developer docs in this session.
- Hotel-specific accounting usage (which system Swedish hotels actually use) was not found. Larger chains (Scandic, Strawberry) are believed to run ERP-class systems, but this is unverified.

## 3. Payment providers in Nordic hospitality and property

### Takeaway

Adyen and Stripe are the gateways that modern PMSs (Mews) embed. Nexi (which owns the former Nets) is the incumbent Nordic acquirer and terminal provider. Swish is ubiquitous in Sweden but weakly supported in hotel PMSs, which is a possible differentiator. For landlords, rent collection runs on Bankgirot/Autogiro direct debit and OCR-referenced bankgiro payments, not cards.

### Cited Findings

- Mews integrates with two gateways, Adyen and Stripe, and only one can run at a time. Mews Payments is embedded in its PMS/POS. Mews Financial Services B.V. holds an EMI licence — [Mews help: payment integrations](https://mewssystems.freshdesk.com/support/solutions/articles/31000129943-payment-integrations); [Mews Payments](https://mews.com/en/products/payments)
- Mews users have requested Swish as a payment method; the post notes Swish is available via partners such as Klarna or Adyen. It is a feature request, not a shipped feature — [Mews feedback forum](https://feedback.mews.com/forums/955604-payments/suggestions/47715086-swish-payment-method)
- Adyen markets PMS-integrated hotel payments with 200+ local payment methods — [Adyen hospitality](https://www.adyen.com/industries/hospitality)
- Nexi's hospitality offering covers terminals, SoftPOS, e-commerce and alternative payment methods — [Nexi hospitality](https://nexigroup.com/en/business/large-corporate/payment-acceptance/hospitality)
- Swish payments count as electronic payments that must be recorded in a cash register — [Skatteverket](https://www.skatteverket.se/foretag/drivaforetag/kassaregister)

### Inferences

- Recommended targets:
  - **Adyen** first: Salesforce has an Adyen-based Salesforce Payments path, it supports pre-auth/incremental auth/tokenisation for hotels, and Swish/Klarna/MobilePay/Vipps are available as methods. **[unverified that Salesforce Payments covers PMS-style card-on-file flows]**
  - **Nexi** for clients locked into existing Nordic acquiring contracts.
  - **Swish** directly or via Adyen.
  - **Autogiro/Bankgirot** for rent.
  - Klarna and Trustly matter more for direct-booking web checkout than at the front desk.
- MobilePay (Denmark/Finland) and Vipps (Norway), now merged as Vipps MobilePay, are the Swish equivalents for the other Nordic countries **[unverified merger detail]**.

### Gaps

- I found no market-share data for hotel acquiring in Sweden, and no confirmation of Nexi–Mews, Planet, Worldline/Bambora or Trustly integrations with Nordic PMSs.
- I did not verify Bankgirot/Autogiro API access or the post-2025 migration of Bankgirot clearing into the Riksbank's RIX-INST/P27 landscape.

## 4. Staff management / workforce tools used by Nordic hotels: build or integrate?

### Takeaway

Scheduling, time and attendance, and payroll-export is a crowded, mature category, led by Nordic-origin vendors: Quinyx (Swedish), Planday (Danish, owned by Xero), Caspeco (Swedish, also POS), Personalkollen (Swedish), and Tamigo (Danish). They handle Swedish collective agreements (Visita–Unionen/HRF, OB supplements) and payroll exports (Fortnox Lön, Hogia, Visma Lön). Hotel operations tools (hotelkit, Flexkeeping, Optii) cost about $200–500 per month per property and integrate with major PMSs. **Recommendation: integrate for rostering, time and attendance, and payroll. Build only the PMS-adjacent operational layer** (housekeeping/maintenance task checklists driven by room status, mobile offline task app, operational KPIs). Those depend on reservation data, and Salesforce Field Service/mobile offline covers them natively.

### Cited Findings

- Quinyx says it connects scheduling, payroll, HR, POS and business systems "into one seamless data flow". It is API-first, and it argues that combining workforce data with PMS, RMS and POS data gives the best view of hotel staffing demand — [Quinyx integrations](https://www.quinyx.com/workforce-management/integrations); [Quinyx blog](https://www.quinyx.com/blog/data-driven-hotel-staffing)
- Planday imports daily revenue from Mews in near-real time. HotelTechReport notes the Mews integration hasn't been verified by Planday — [Planday integrations](https://planday.com/integrations); [Mews marketplace: Planday](https://mews.com/en/products/marketplace/planday)
- Caspeco serves restaurants, bars, nightclubs, hotels and entertainment venues. Personalkollen offers staff and payroll systems for hotels, restaurants and retail — [businesswith.se comparison](https://businesswith.se/jamfor-system/quinyx-vs-caspeco-personal/); [CB Insights](https://www.cbinsights.com/compare/caspeco-vs-personalkollen)
- Housekeeping/operations app pricing (aggregator figures; they conflict and are unverified with vendors):
  - Flexkeeping: about $400 per month (HotelTechReport) or from $95 per user per month (Capterra).
  - hotelkit: about $200 per month, with 41 verified integration partners including Oracle, Mews and Stayntouch.
  - Optii: about $500 per month, with 12 verified partners including Opera.
  - Sources: [HotelTechReport Flexkeeping](https://hoteltechreport.com/operations/housekeeping-software/flexkeeping-housekeeping); [HotelTechReport hotelkit vs Optii](https://hoteltechreport.com/compare/flexkeeping-housekeeping-vs-hotelkit-housekeeping); [Capterra](https://www.capterra.com/p/198674/Flekeeping/); [SoftwareFinder](https://softwarefinder.com/hotel-management/flexkeeping)
- Flexkeeping is listed in the Apaleo app store, showing open-API PMSs integrate with it — [Apaleo store](https://store.apaleo.com/apps/flexkeeping)

### Inferences

- **Mandatory:**
  - Role-based access (Salesforce profiles and permission sets).
  - An audit trail of who changed folios, rates and payments (Field History, Shield/Event Monitoring as an option).
  - Housekeeping and maintenance task assignment tied to room status.
- **Nice-to-have, or integrate:**
  - Rostering and time and attendance. In Sweden this is collective-agreement-driven and already well served.
  - Payroll export. Swedish payroll runs in Fortnox Lön, Visma Lön, Hogia and Caspeco **[unverified list]**, and the PAXml payroll-transaction format is the common export **[unverified]**.
- **Integration priority:** Quinyx (enterprise chains), Caspeco and Personalkollen (Swedish hotel-restaurant SMBs), and Planday (Nordic SMB; Xero-owned). Push forecast occupancy, arrivals and departures, and F&B covers to them so they can do demand-based scheduling. Pull labour cost back for KPIs (cost per occupied room, minutes per room cleaned).
- **Mobile offline:** Salesforce mobile app offline / Field Service mobile can deliver housekeeping checklists. That is a differentiator against standalone tools that need another login.

### Gaps

- No verified list prices for Quinyx, Planday, Caspeco, Personalkollen or Tamigo, and no current Flowhospitality data.
- I found no source listing which PMSs each workforce vendor integrates with, beyond Planday–Mews and hotelkit's PMS partners.
- I did not verify Swedish collective agreement (Gröna Riks / Visita) scheduling rules or Arbetstidslagen record-keeping duties from primary sources.

## 5. Swedish/Nordic hospitality and property market data

### Takeaway

Sweden recorded 70.8 million commercial guest nights in 2025 (up 2.5%; about 26% foreign). The rental market is large: about 1.6 million rental apartments in multi-family buildings, of which about 846,000 are public housing (allmännyttan) across roughly 322 municipal companies. That is a sizeable property management segment for a Salesforce-native suite. I could not verify a hotel count or the chain-versus-independent split.

### Cited Findings

- 2025: 70.8 million guest nights in Sweden, about 26% foreign — [Tillväxtverket Inkvartering 2025](https://tillvaxtverket.se/download/18.7cc6aa6319e368565ec2786e/1779173282252/Inkvartering_2025.pdf); described as commercial guest nights, up 2.5% — [Realtid](https://www.realtid.se/perfectweekend/hotellen-vaxer-igen-svensk-turism-fortsatter-uppat/)
- West Sweden: about 8.2 million guest nights in hotels, holiday villages and hostels, up 5.4% (a record) — [Västsverige](https://www.vastsverige.com/turistradet-vastsverige/Artiklar/inkvarteringsstatistik-2025/)
- SCB accommodation statistics cover hotels, holiday villages, youth hostels, campsites and commercially rented private cottages and apartments: guest nights, capacity and occupancy — [SCB](https://www.scb.se/en/finding-statistics/statistics-by-subject-area/business-activities-and-foreign-trade/tourism/accommodation-statistics/)
- Realtid reports a "hotel boom" driven by tourism, defence and property investment — [Realtid](https://www.realtid.se/perfectweekend/hotellboom-i-sverige-turister-forsvar-och-fastigheter-driver-marknaden/)
- Norway hit record guest nights in 2025 — [SSB](https://www.ssb.no/transport-og-reiseliv/reiseliv/statistikk/overnattingar/artikler/rekordmange-overnattingar-i-2025)
- Public housing: about 846,000 apartments at the end of 2025, just under 41% of rental housing and about 16% of all dwellings, growing by about 4,100 in 2025 — [Boverket](https://www.boverket.se/sv/samhallsplanering/bostadsmarknad/bostadsmarknaden/bostadsmarknadsenkaten/kommunernas-verktyg/allmannyttan/)
- About 1.6 million apartments are rental (hyresrätter) and about 1.1 million are bostadsrätter (58%/42% of apartments in multi-family buildings) — [SCB Bostadsbeståndet 2025-12-31](https://www.scb.se/hitta-statistik/statistik-efter-amne/boende-bebyggelse-och-mark/bostader-och-boende/bostadsbestand/pong/statistiknyhet/bostadsbestandet-31-december-2025/)
- Sveriges Allmännytta has 322 municipal and 11 private housing companies, with about 1 million rental homes. Its scope differs from Boverket's definition — [Sveriges Allmännytta](https://via.tt.se/pressrum/sverigesallmannytta?publisherId=3235805)
- Allmännyttan's maintenance backlog is estimated at SEK 686 billion — [Sveriges Allmännytta press release](https://via.tt.se/pressmeddelande/4445474/allmannyttans-underhallsskuld-uppgar-till-686-miljarder-kronor?lang=sv)

### Inferences

- Allmännyttan companies are public bodies, which has three consequences:
  - Their purchasing goes through LOU (public procurement).
  - Suppliers invoicing them must use Peppol.
  - They are exempt from the cash register requirement as tax-exempt entities (municipal entities are listed as exempt; companies owned by municipalities may differ **[unverified]**).
- The SEK 686bn maintenance backlog argues for strong maintenance and work-order features in the property module.
- Selling to them means public tenders, which favours Peppol and accessibility/GDPR certification.

### Gaps

- Number of hotels in Sweden, chain versus independent share, and growth in serviced apartments and aparthotels: not found in this session (check Visita "Den svenska logimarknaden", SCB capacity tables, Benchmarking Alliance).
- Property management software market size in Sweden: not found.
