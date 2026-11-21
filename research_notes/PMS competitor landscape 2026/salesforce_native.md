# Salesforce-native / Salesforce-centric competitors: hotel PMS and property management (as of Nov 2026)

Method note: about 15 web searches and fetches. Most evidence comes from vendor sites, trade press (Hospitality Net, Hotel Tech Report) and aggregator listings (sfapps.info, Capterra). I could not read AppExchange listing pages directly, so ratings and review counts come from sfapps.info (Sept 2026), which I did not check against AppExchange. Older items are flagged.

## 1. Hospitality products on Salesforce: which are real PMS vs. sales & catering / CRM?

### Takeaway

Only one vendor clearly sells a Salesforce-native hotel PMS: Booking Ninjas. It is small, has thin public proof and does not document night audit or folios. The strong Salesforce-native hospitality players (Thynk, Amadeus Delphi) do sales & catering, groups and CRM only, and connect to an external PMS. Mews, Hapi and Oracle are PMS vendors or integration layers that connect to Salesforce; they are not native.

### Cited Findings

**Booking Ninjas (US; the only Salesforce-native PMS)**

- Calls itself the "first & only full-featured property management system (PMS) built natively on Salesforce". This is the vendor's own claim, and its AppExchange listing describes it as Salesforce-native — [Booking Ninjas](https://www.bookingninjas.com/solutions/hospitality/hotel)
- Hotel modules it lists: reservation management (guests, dates, room assignment, status, charges, stay history), invoice management (room charges, deposits, taxes, add-ons, refunds, balances), front desk, booking engine, rate control, reporting. Housekeeping is only mentioned as coordination around room status. **Night audit and folios are not mentioned**. Accounting appears only as a link to "Accounting Integrations" — [Booking Ninjas hotel page](https://www.bookingninjas.com/solutions/hospitality/hotel)
- Published pricing: Core from $400/month for 1–50 bookable units. Above 50 units: +$8/unit/month (51–100), +$6 (101–250), +$5 (251–500), volume pricing for 501+. Channel Manager is +$100/month per property (up to 50 connections and 100 channel reservations/month). Add-ons: Guest Portal +$100, POS +$100 per location, Communication Hub +$100, Door Lock +$7.50 per door. Implementation is extra, and "Third-party and Salesforce costs may apply" — [Booking Ninjas hotel page](https://www.bookingninjas.com/solutions/hospitality/hotel)
- Older or conflicting aggregator prices: $14.25–$19 per room/month, $17 per unit/month, a free tier for 1–5 units with a $499 implementation fee, and "$85 flat/month" — [SaasWorthy](https://www.saasworthy.com/product/booking-ninjas), [Capterra CA](https://www.capterra.ca/reviews/144189/booking-ninjas), [Capterra](https://www.capterra.com/p/144189/Booking-Ninjas/). On AppExchange it appears as "Modern Property Management System (PMS)", from $95/user/month, rated 5.0 with 5+ reviews — [sfapps.info](https://www.sfapps.info/top-salesforce-real-estate-apps/)
- Little social proof: 4 reviews on Capterra US, none on G2 — [Capterra](https://www.capterra.com/p/144189/Booking-Ninjas/), [G2](https://www.g2.com/products/booking-ninjas)
- Its own case studies admit that one early hotel implementation (CTY Group) "did not reach production go-live". Other cases: Goulding's Monument Valley (rooms, villas, campground) and Billings Hotel & Convention Center (conference space, e-signature). The "solutions prototyped for" brands are labelled "illustrative" with no client status — [Booking Ninjas hotel page](https://www.bookingninjas.com/solutions/hospitality/hotel)
- AI is not included by default and is "separately scoped". The site links to an Agentforce page but gives no detail — [Booking Ninjas hotel page](https://www.bookingninjas.com/solutions/hospitality/hotel)
- It also markets itself for property management, rentals and tenant portals beyond hotels — [Booking Ninjas blog](https://www.bookingninjas.com/blog/transform-property-management-with-salesforce-powered-pms)

**Thynk (sales, groups and events platform; not a PMS)**

- Describes itself as a "Hospitality Commercial Platform – powered by Salesforce" that unifies B2B sales, groups, meetings and events — [Hospitality Net](https://www.hospitalitynet.org/organization/17023251/thynk)
- Modules: Meetings & Events (sales & catering, BEO/docs), Group Bookings (integrated with the PMS), B2B Sales, Inquiries & Distribution, Thynk Direct booking engine (rooms and event space), Hospitality CRM, Analytics, Connect. No reservations, folios or night audit. It integrates with Mews, Protel, Sihot and Oracle. Claims "2,500+ hotel & venue leaders". Named brands: Rotana, Design Hotels, Barrière, Generator, Maritim, Doyle Collection, Club Quarters, Lopesan, Harry's Home, Chatrium, Staypineapple. **Pricing not published** — [thynk.cloud](https://thynk.cloud/)
- Ranked #3 of 15 in Hotel Sales Software, and #2 hotel sales software in the 2026 HotelTechAwards — [Hotel Tech Report](https://hoteltechreport.com/meetings-and-events/group-sales/thynkcloud)
- Joined the Agentforce Partner Network with a "Hospitality AI Sales Agent" that speeds up RFP and lead responses and proposes alternative dates and services. It launches first as an assistant for sales teams and the group desk — [Hospitality Net](https://hospitalitynet.org/news/4124787.html)
- Recent deals: Sonesta (global sales organization), Cvent partnership (Oct 2024), Meetingselect corporate RFP integration (about Oct 2026), new Chief Sales Officer — [Sonesta](https://www.hospitalitynet.org/news/4127659.html), [Cvent](https://www.hospitalitynet.org/news/4124404.html), [Meetingselect](https://www.hospitalitynet.org/news/4134854/thynk-partners-with-meetingselect-to-connect-hotels-with-global-corporate-rfp-demand), [CSO](https://www.hospitalitynet.org/news/4133779/thynk-appoints-chief-sales-officer-and-attracts-industry-leaders-across-hospitality-and-venues)
- Customer outcome: Lamington Group / Second Nature booking conversion rose 6% from 2025 to 2026 — [Hotel Tech Report](https://hoteltechreport.com/zh/success-stories/meetings-and-events/thynk/lamington-group-second-nature)
- Strong in the Middle East (Dur Hospitality, Ishraq, Rotana) and Europe (Maritim, Barrière, Doyle) — [Dur](https://www.hospitalitynet.org/news/4112747.html), [Ishraq](https://www.hospitalitynet.org/opinion/4108741.html), [thynk.cloud](https://thynk.cloud/)

**Amadeus Delphi (enterprise sales & catering on Salesforce; not a PMS)**

- Amadeus calls Delphi "the hotel sales and catering standard, built on the industry-leading Salesforce CRM", running on Einstein 1 Platform / Lightning. It has 30+ partner integrations (June 2024 sheet) and "5,500+ organizations since 2014" (undated) — [Amadeus Delphi](https://amadeus-hospitality.com/sales-catering-software/delphi/), [sales sheet 2024](https://connect.amadeus-hospitality.com/hubfs/Enhanced_Delphi_Experience_Sales_Sheet_June2024.pdf)
- Used by Accor and IHG (Delphi + MeetingBroker) — [Accor](https://amadeus.com/en/newsroom/press-releases/accor-expands-delphi-sales-and-catering), [IHG](https://www.amadeus-hospitality.com/sales-catering-software/delphi-meeting-broker-for-ihg-hotels-resorts-worldwide/)
- History: Newmarket first built Delphi.fdc on Force.com for boutique and midscale venues (old item) — [Hospitality Upgrade](https://www.hospitalityupgrade.com/news/newmarket-international-delivers-delphi-on-salesforcecoms-forcecom-platform-to-bring-the-hospitality-industry-into-the-cloud)
- Separately, Amadeus chose the Salesforce Platform and Agentforce for a new **Hotel Service Center** product (Service Cloud + Amadeus ACRS/iHotelier). The release is about late 2025 — [Hospitality Net](https://www.hospitalitynet.org/news/4125958/amadeus-collaborates-with-salesforce-on-next-generation-hotel-service-center-solution)

**Connectors (PMS stays outside Salesforce)**

- Mews for Salesforce on AppExchange links Mews PMS and Salesforce CRM in real time, set up "in just a few hours". The press release is older (undated in results, probably 2020–2022) — [Hospitality Net](https://www.hospitalitynet.org/news/4111279/mews-announces-mews-for-salesforce-on-salesforce-appexchange-the-worlds-leading-enterprise-cloud-marketplace), [Mews](https://www.mews.com/en/press/mews-announces-mews-for-salesforce-on-salesforce-appexchange-the-worlds-leading-enterprise-cloud-marketplace)
- Hapi-Connect is a native Salesforce package with two-way sync of reservations and guest/company profiles from PMSs (older item) — [Hapi on Medium](https://medium.com/hapicloud/salesforce-com-and-hospitality-get-connected-with-hapis-newly-released-appexchange-app-173392c86ea3)
- Oracle OPERA Cloud connects through the Oracle Hospitality Integration Platform. A 2026 PMS API study scored Mews, Apaleo, OPERA Cloud, Beds24 and Cloudbeds at 73.3 or above for API openness, and on-prem OPERA 5 at 26.3 — [Hospitality Net 2026 PMS API study](https://www.hospitalitynet.org/news/4134549/the-2026-pms-api-study)
- No vendor-confirmed Salesforce Data Cloud connector was found for Mews, Apaleo or OPERA — same searches as above
- Mews (Unfold 2026) now unifies PMS, RMS, messaging, automations and AR on a single data model, sold as a "hospitality operating system" — [Hospitality Net](https://www.hospitalitynet.org/news/4132634/mews-unveils-the-operating-system-for-hospitality)

### Inferences

- The serious competitors for Salesforce-native hotel deals are Thynk and Delphi at the commercial layer. They are likely to be partners (sales & catering above our PMS) or competitors for the "hotel CRM" budget, not for the PMS core. Thynk already integrates with Mews/Protel/Sihot/Oracle, so a Thynk-to-our-PMS integration could be a channel.
- Booking Ninjas is the only like-for-like rival. Its pricing (about $400–500/month for a 50-room property plus Salesforce licences) sets a public reference point. Its weak proof (failed go-live admitted, few reviews, no documented night audit) suggests the "full PMS on Salesforce" spot is effectively open.
- A real hotel buyer's default is still Mews, OPERA, Apaleo or Protel plus a Salesforce connector. Our pitch has to beat "best-of-breed PMS + Thynk/Delphi + Salesforce", not just other native apps.

### Gaps

- "Hotelforce": no product by that name was found.
- AppExchange ratings for Thynk, Delphi and Mews for Salesforce could not be retrieved.
- Thynk's pricing and Delphi's current pricing are not public.
- Whether Mews for Salesforce is still actively maintained in 2026 is unconfirmed.
- Revinate, Cendyn and other hotel CRMs with Salesforce links were not researched within the call budget.

## 2. Property management and real estate products on Salesforce

### Takeaway

Real-estate apps on Salesforce are mostly brokerage and CRE CRMs: Propertybase Salesforce Edition, Rethink (Buildout) and Ascendix. A smaller group of native property, lease and rent management apps exists (REDA, Powerhouse, Wunderbricks, TrackMe, Synergy, Booking Ninjas), but each has very few reviews (1–10). Nobody native dominates residential or commercial lease operations with accounting. Integrators often advise keeping the ledger and rent in Yardi or AppFolio and using Salesforce as the CRM layer.

### Cited Findings

Below is the AppExchange snapshot as reported by [sfapps.info (Sept 2026)](https://www.sfapps.info/top-salesforce-real-estate-apps/). It was not checked against AppExchange.

| App                               | Vendor                       | Scope                                        | Price                    | Rating (reviews) |
| --------------------------------- | ---------------------------- | -------------------------------------------- | ------------------------ | ---------------- |
| Propertybase Real Estate Platform | Propertybase / Lone Wolf     | Brokerage CRM, transactions, IDX sites       | $79/user/mo, min 10      | 4.75 (363+)      |
| Rethink CRE                       | Buildout                     | CRE CRM, deals, property                     | $159/user/mo             | 4.8 (210+)       |
| REDA                              | REDA One LLC (Princeton, NJ) | CRM + leasing + PM + accounting              | $135/user/mo             | 5.0 (10+)        |
| Modern PMS                        | Booking Ninjas               | Hospitality & rentals                        | $95/user/mo              | 5.0 (5+)         |
| Powerhouse                        | Powerhouse                   | Rent collection, leases, owner/tenant portal | €250/company/mo + portal | 5.0 (4+)         |
| Wunderbricks                      | Wunderbricks Nederland BV    | Property/lease/asset mgmt incl. maintenance  | €295/user/mo             | 5.0 (1+)         |
| Synergy App                       | Intempus                     | Leasing + showing scheduling                 | Free                     | 5.0 (4+)         |
| TrackMe                           | Selsoft                      | Leases, maintenance, billing                 | $300/user/yr             | none             |
| Property Strength                 | Cloudsteer                   | Developer sales/bookings CRM+ERP             | $150/user/mo             | 5.0 (4+)         |
| Real Properties                   | Real Intelligence            | Property/facility/event mgmt                 | Quote                    | 5.0 (2+)         |
| HomeKeeper                        | Grounded Solutions           | Affordable housing programs                  | $2,500/org/yr            | 5.0 (5)          |
| REMSUITE                          | REMSUITE (AU)                | CRM + trust accounting                       | A$89/user/mo             | none             |

- Propertybase Salesforce Edition is a managed package sold by Lone Wolf, which acquired Propertybase in 2021. Propertybase GO (not on Salesforce) was renamed Lone Wolf Front Office (Aug 2024). Lone Wolf is reportedly a Vista Equity portfolio company, and reviewers flag its post-acquisition roadmap as "in flux" — [Propertybase by Lone Wolf](https://propertybase.lwolf.com/), [Gappsy review 2026](https://www.gappsy.com/tools/propertybase/), [Assistantstead](https://assistantstead.com/blog/lone-wolf-crm-explained-relationships-front-office-liondesk/)
- REDA is a Salesforce ISV/OEM that combines CRM, ERP and PM: leads, leasing, resident portal, maintenance and real-estate accounting. It claims multilingual, multi-currency and local compliance support. No named European customers were found — [GetApp](https://www.getapp.com/real-estate-property-software/a/reda/), [Slashdot](https://slashdot.org/software/p/REDA-One/), [reda.one](https://reda.one/)
- Wunderbricks (Netherlands) calls itself "the first SaaS property management platform (OEM partner) built on Salesforce.com". It is the only EU-based native PM vendor found — [builtworld](https://builtworld.com/company/wunderbricks)
- Native Rent (AppExchange) presents itself as an all-in-one rental management platform with a free trial — [AppExchange PDF](https://appexchange.salesforce.com/image_host/62c2f4fc-027c-409d-b27a-e82e5a356431.pdf)
- Ascendix publishes Salesforce property-management and CRE guidance and products (AscendixRE CRM). Its details were not verified in this pass — [Ascendix blog](https://ascendix.com/blog/salesforce-property-management/)
- Integrator view: Salesforce "doesn't have a separate package for property management". Yardi, AppFolio, Buildium and Rent Manager stay the system of record for rent and ledger, synced into Salesforce — [bkonect](https://bkonect.com/blog/salesforce-for-property-management/), [Folio3](https://crm.folio3.com/blog/salesforce-for-property-management/)
- Common DIY pattern: Service Cloud cases for maintenance requests, an Experience Cloud tenant portal, and Agentforce for after-hours triage. One guide suggests AI triage pays off at about 5,000–10,000 units — [Minuscule](https://www.minusculetechnologies.com/blogs/salesforce-service-cloud-property-management-real-estate), [sfapps.info implementation guide](https://www.sfapps.info/salesforce-real-estate-implementation/)
- Equipment-leasing apps (Cloud Maven Lease Management, Ascent Rental ERP) are not for real-estate leasing — [Cloud Maven](https://cloudmaveninc.com/products/lease-management), [Ascent Rental](https://appexchange.salesforce.com/appxListingDetail?listingId=a0N30000008ZDH5EAO)

### Inferences

- Review counts show that native PM apps have only small traction. Only the CRMs (Propertybase, Rethink) have hundreds of reviews. A well-built native lease + rent + maintenance + accounting module would face fragmented, small competitors.
- Per-user pricing is the norm for real-estate apps ($79–$159/user/month). Booking Ninjas prices per unit. This gives us room to choose per-unit/per-room pricing that suits operators with few users and many units.
- No vendor found combines hotel PMS with residential/commercial leasing, apart from Booking Ninjas' loose "rentals" claim.

### Gaps

- No Salesforce-native "Lightning Rentals" or Rhino-type product was confirmed.
- No Yardi-to-Salesforce connector details were found.
- Powerhouse vendor details (country, customers) were not found.
- European/Nordic customer names for REDA and Wunderbricks were not found.

## 3. Pricing, geography, customers, ratings, 2025–26 releases, AI use (cross-vendor summary)

### Takeaway

Public pricing exists only for Booking Ninjas and the real-estate apps. Thynk and Delphi are quote-only and enterprise-focused. AI/Agentforce activity is concentrated in Thynk (Hospitality AI Sales Agent) and Amadeus (Service Center). European presence is strong for Thynk, weak or unverified for all native PM apps. No Nordic Salesforce-native hotel or property vendor was found.

### Cited Findings

- Thynk's Agentforce Hospitality AI Sales Agent (RFP/lead response, alternative dates) — [Hospitality Net](https://hospitalitynet.org/news/4124787.html)
- Amadeus Service Center on Salesforce Platform + Agentforce — [Hospitality Net](https://www.hospitalitynet.org/news/4125958/amadeus-collaborates-with-salesforce-on-next-generation-hotel-service-center-solution)
- Booking Ninjas: AI is "separately scoped", not productized — [Booking Ninjas](https://www.bookingninjas.com/solutions/hospitality/hotel)
- Nordic search found Salesforce consultancies (Axenon in Stockholm, part of NoA; Inlead in Norway; Salient) and Nordic hotel property owners (Pandox, Nordic Property Management, CapMan). None was linked to a Salesforce-native PMS — [Axenon AppExchange](https://appexchange.salesforce.com/appxConsultingListingDetail?listingId=a0N3A00000EFmNxUAL), [LBB on NoA/Inlead](https://lbbonline.com/news/noa-acquires-leading-salesforce-partner-in-norway-inlead), [Pandox](https://en.wikipedia.org/wiki/Pandox)
- Booking Ninjas offers 28 language versions of its site but names no target markets — [Booking Ninjas](https://www.bookingninjas.com/solutions/hospitality/hotel)

### Inferences

- Nordic consultancies like Axenon are possible implementation partners or channels rather than competitors.
- Pandox, CapMan and Nordic Property Management are examples of Nordic hotel-real-estate owners who might value combined hotel + property functions.

### Gaps

- AppExchange ratings for Thynk and Delphi were not retrievable.
- I found no reliable 2026 release notes for Booking Ninjas, REDA or Wunderbricks.

## 4. What Salesforce itself offers (2025–2026) and the risk it builds a PMS

### Takeaway

Salesforce sells a "hospitality CRM" built on Agentforce + Data 360 (Data Cloud) + Service/Marketing Cloud. It pulls data from the PMS rather than replacing it, and publishes demo apps (Sunshine Trails, Coral Cloud Resorts). I found no industry cloud for hospitality or real estate with a reservations/folio data model, and no hospitality-specific Agentforce launch at Dreamforce 2025. Salesforce's big hotel deals (Minor, Choice, Wyndham, Amadeus) all sit on top of third-party PMSs. Near-term risk that Salesforce builds a PMS looks low. The bigger risk is that Salesforce and its SIs keep pushing the "best-of-breed PMS + Data 360" pattern.

### Cited Findings

- Salesforce hospitality page: an AI concierge powered by Agentforce for guests and staff; "Connect all of your data sources from PMS to loyalty" into unified profiles; agents summarize cases — [Salesforce Hospitality](https://www.salesforce.com/travel-hospitality-transportation/hospitality/)
- Data 360 + Agentforce hospitality sample app "Sunshine Trails" (fictional chain): reservation booking agent, upsell at check-in, digital key welcome text — [Salesforce sample app](https://www.salesforce.com/data/resources/sample-app-hospitality/)
- Trailhead "Coral Cloud Resorts" employee agents handle reservations and excursions and create maintenance/housekeeping cases (training scenario) — [Trailhead](https://trailhead.salesforce.com/content/learn/modules/use-employee-agents-to-get-work-done/welcome-to-coral-cloud-resorts)
- Minor Hotels (Apr 9 2026): global data and AI platform with Google Cloud, Salesforce, OneTrust and Deloitte. Agentforce Marketing and Data 360 handle guest comms and segmentation across 640+ properties, with full deployment in 2026 — [Salesforce press release](https://www.salesforce.com/ap/news/press-releases/2026/04/09/minor-hotels-unveils-global-data-and-ai-platform-to-power-next-generation-guest-experience/), [Hotel Management](https://www.hotelmanagement.net/tech/minor-hotels-launches-global-data-ai-platform)
- Choice Hotels (May 7 2026) cites its Agentforce relationship for AI agents across sales, service, marketing and operations — [Choice Hotels](https://media.choicehotels.com/2026-05-07-Choice-Hotels-International-Unveils-New-Technologies-and-AI-Powered-Solutions-to-Help-Owners-Capture-More-Demand-and-Operational-Excellence)
- Wyndham uses Data Cloud to unify reservation, loyalty and CRM data for service (older case study) — [Salesforce](https://www.salesforce.com/news/stories/how-data-cloud-powers-agentforce/)
- Engine (travel platform, Apr 2026): Agentforce handles 50% of chat cases, and handle time fell 15% — [Salesforce](https://www.salesforce.com/news/press-releases/2026/04/15/engine-powers-travel-experiences-with-agentforce-slack/)
- Dreamforce 2025 (Oct 14–16): searches found no hospitality-specific product announcement — [Perficient](https://blogs.perficient.com/2025/07/01/so-youre-going-to-dreamforce-2025-heres-everything-you-need-to-know/)
- Real estate: no dedicated Salesforce real-estate cloud. Partners build it from Sales/Service/Experience Cloud + Agentforce — [Codleo](https://www.codleo.com/blog/salesforce-real-estate), [Ascendix guide](https://ascendix.com/blog/salesforce-real-estate/)
- Unverified secondary claim: on Sept 3 2026 Salesforce introduced Agentforce Sales/Service/Industries editions at $195/$395/$550 per user/month. Sources conflict, so check before using — [hyphenxsolutions](https://hyphenxsolutions.com/Blog/salesforce-for-real-estate-2026/), [Cyntexa](https://cyntexa.com/blog/salesforce-for-real-estate/)

### Inferences

- Salesforce's model is "PMS stays outside, Salesforce owns guest data and engagement". A native PMS fits that story well: there is no Data 360 ingestion gap, because reservations and stays are already Salesforce records that Agentforce can act on.
- Salesforce partners with PMS vendors and with Amadeus (Delphi, Service Center), so it is unlikely to build a transactional PMS with night audit, fiscal compliance and channel management. Treat it as low risk but monitor it, for example any "Hospitality" add-on to Consumer Goods/Retail clouds or a standard data model for stays.
- Salesforce licence costs on top of the app price are a structural disadvantage against standalone PMSs (Mews, Apaleo). Booking Ninjas explicitly lists them as extra.

### Gaps

- The Salesforce hospitality page gave no pricing and no standard object model for reservations.
- I could not confirm whether any Industries Cloud includes hospitality-specific objects as of late 2026.

## 5. Gaps no Salesforce-native vendor fills well (where we can win)

### Takeaway

No Salesforce-native vendor publicly documents a full hotel PMS core (folios, night audit, fiscal close) together with channel manager, accounting and staff. None is Nordic or has proven Nordic compliance. None credibly combines hotel stays with long-stay, residential or commercial leasing in one data model. Those three overlaps are the open space.

### Cited Findings

- Booking Ninjas lists no night audit or folios, and accounting appears only as integrations — [Booking Ninjas](https://www.bookingninjas.com/solutions/hospitality/hotel)
- Thynk and Delphi are sales & catering/commercial only and depend on an external PMS — [thynk.cloud](https://thynk.cloud/), [Amadeus Delphi](https://amadeus-hospitality.com/sales-catering-software/delphi/)
- Native PM apps have 0–10 reviews each. Only REDA claims accounting plus PM — [sfapps.info](https://www.sfapps.info/top-salesforce-real-estate-apps/)
- The only EU-based native PM vendor found is Wunderbricks (Netherlands). No Nordic native vendor was found — [builtworld](https://builtworld.com/company/wunderbricks); Nordic search above
- Integrators advise keeping rent and the ledger outside Salesforce, so native accounting is seen as a weak spot — [bkonect](https://bkonect.com/blog/salesforce-for-property-management/)

### Inferences

- Openings: (1) a native PMS with real night audit, folio and AR plus a channel manager such as Channex; (2) Nordic compliance (Swedish VAT, SIE export, Swedish accounting integrations, Swedish cash-register/kassaregister rules where relevant); (3) one platform for hotel, aparthotel/long-stay and residential/commercial leases; (4) native Agentforce/Data 360 use with no connector, which Salesforce's own marketing already promotes; (5) partnering with Thynk/Delphi for sales & catering instead of competing.
- Threats: Booking Ninjas' low list price; best-of-breed PMSs (Mews, a Nordic-origin-friendly European player, plus Apaleo and OPERA) with open APIs and Salesforce connectors; Salesforce licence cost stacking.

### Gaps

- I did not verify Nordic fiscal/compliance needs (for example Skatteverket kassaregister rules for hotels) in this pass.
- Booking Ninjas' undocumented features (night audit) might exist without being on its marketing pages. Check by demo or AppExchange listing.
