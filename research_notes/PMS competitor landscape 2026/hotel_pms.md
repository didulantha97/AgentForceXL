# Hotel PMS and Short-Term-Rental Competitor Landscape (benchmark as of Nov 2026)

Scope: Oracle OPERA Cloud, Mews, Cloudbeds, Apaleo, Protel (Planet), Stayntouch, Shiji Daylight PMS (formerly Shiji Enterprise Platform), Infor HMS, Guesty, Hostaway, and Nordic PMS (VisBook, Sirvoy, Hotellinx, Strawberry's choice). Research date: 2026-11-21. About 20 searches; the trade press and vendor releases are primary sources where possible. Third-party pricing pages (often written by competing vendors) are flagged.

Notation: **[V]** = vendor-reported claim. **[3P]** = third-party estimate. **[unverified]** = analyst background knowledge that was NOT confirmed by a source in this session. Treat [unverified] items as hypotheses to check.

---

## 1. Core features per vendor

### Takeaway

Every enterprise and upper-mid PMS (OPERA Cloud, Shiji Daylight, Infor HMS, Protel, Stayntouch, Mews) covers the full core: reservations, folios, night audit, groups, AR, housekeeping, and multi-property. The vendors now compete on embedded payments, mobile housekeeping, embedded RMS and messaging, and AI. Mews finished its "all-in-one" stack in May 2026 (RMS, messaging, automations, AR). Cloudbeds remains the independent/SMB all-in-one. Apaleo stays deliberately thin at the core and pushes channel manager, booking engine and more out to its marketplace.

### Cited Findings

- **Mews**: launched five products at UNFOLD 2026 (Amsterdam, 27 May 2026). These were Mews RMS (embedded dynamic pricing, "150M pricing calculations daily", automatic rate push), Guest Messaging (a unified WhatsApp/SMS/OTA/email inbox with reservation context and a native autonomous "Mews Agent"), Automations (templates, visual builder, or natural-language workflows), Accounts Receivable (B2B invoice-to-cash, auto-invoicing at billing closure, "100% automated reconciliation"), and one confidential launch. Mews claims an average 13.7% revenue uplift per sqm from the RMS **[V]**. — [Hospitality Net](https://www.hospitalitynet.org/news/4132634/mews-unveils-the-operating-system-for-hospitality)
- Mews pitches this as an "AI-native operating system" unifying PMS, RMS, messaging, automations and AR on one data model, and cites a 476% three-year ROI from IDC research **[V]**. — [Hospitality Net](https://www.hospitalitynet.org/news/4132634/mews-unveils-the-operating-system-for-hospitality)
- Mews launched Mews Business Intelligence (embedded analytics) on 15 Apr 2026, with 1,000 early customers. — [Hospitality Net via search summary](https://www.hospitalitynet.org/news/4132634/mews-unveils-the-operating-system-for-hospitality); [Travel Tech News](https://www.traveltechtalent.com/insights/travel-tech-news-mews-embeds-ai-into-the-pms-again-2026-06-23)
- At Strawberry, Mews runs Operations, Multi-Property, Guest Journey (online check-in) and Mews Payments. The group averages 15 active integrations per hotel and uses the Mews Open API to build bespoke connections. — [Mews press](https://www.mews.com/en/press/strawberry-completes-rollout-of-mews-across-portfolio-of-230-hotels)
- **Oracle OPERA Cloud**: OPERA Cloud Assistant (16 Jun 2026) adds AI-assisted room assignment (using reservation details, preferences, stay history and operational parameters), AI-generated rate-code descriptions, natural-language operational guidance, AI translation of configuration content, and revenue/staff-efficiency tools. — [Oracle press release](https://www.oracle.com/news/announcement/new-ai-capabilities-in-oracle-opera-cloud-supercharge-hotel-operations-2026-06-16/); [Skift](https://skift.com/2026/06/16/oracle-opera-cloud-ai-assistant-rooms-rates-2026/)
- **Cloudbeds**: Signals was announced in Sep 2025 as the "first foundation AI model for hotels" using causal AI **[V]**. Ask Signals is a conversational interface over unified reservations, revenue, distribution, payments, guest and marketing data, introduced in the Spring Release (May 2026). Sources disagree on status: launched (Lodging) vs early pilot (Travolution). — [Hotel Management](https://www.hotelmanagement.net/property-management/cloudbeds-launches-conversational-ai-tool-operations-revenue-insights); [Travolution](https://www.travolution.com/en/article/cloudbeds-launches-ask-signals-a-conversational-ai-interface-for-hotels); [Lodging Magazine](https://lodgingmagazine.com/cloudbeds-debuts-new-conversational-ai-interface/)
- Cloudbeds guest messaging is a separate product (Cloudbeds Guest Experience, formerly Whistle). Signals is back-office revenue/marketing AI. — [Vertize (dated, ~early 2026)](https://www.vertize.io/blog/ai-and-cloudbeds-what-signals-covers-what-it-doesnt-and-how-to-close-the-gap); [Roommaster (competitor)](https://www.roommaster.com/blog/cloudbeds-pricing)
- Cloudbeds weakness: a G2 reviewer reports "there isn't a good way to handle corporate billing accounts" (a city-ledger/AR gap). Capterra reviewers also cite missing automated billing. — [G2](https://www.g2.com/products/cloudbeds/reviews?page=2); [Capterra](https://www.capterra.com/p/158839/Cloudbeds/reviews/)
- **Apaleo**: an API-first core. Channel managers, booking engines and other apps are third-party marketplace apps, billed separately by each provider. — [Hotelminder](https://www.hotelminder.com/partner=Apaleo); [Roommaster (competitor)](https://www.roommaster.com/alternatives/mews-vs-apaleo)
- **Shiji Daylight PMS**: AWS-hosted, single-instance multi-tenant, microservices and micro-frontends. Targets mid-market to enterprise groups. — [Roommaster (competitor)](https://www.roommaster.com/blog/shiji-alternatives). Other features:
  - A housekeeping mobile app with per-room tasks. — [Shiji press](https://www.shijigroup.com/press-news/shiji-unifies-housekeeping-workflows-with-tasks-per-room-in-daylight-pms-mobile-app)
  - "Full fiscal compliance" across 36 countries. — [Shiji press](https://www.shijigroup.com/press-news/shijis-daylight-pms-expands-across-449-cities-and-36-countries-with-full-fiscal-compliance)
  - A full-stack offer that pairs Daylight PMS with Infrasys POS. — [Shiji press](https://www.shijigroup.com/press-news/hospitality-x-redefines-hotel-operations-through-shiji-full-stack-adoption)
- **Infor HMS**: a cloud enterprise PMS for large hotels and chains, with back-office links into the Infor ERP suite. — [Roommaster/hotelminder comparison](http://www.hotelminder.com/best-hotel-property-management-systems)
- **Protel (Planet)**: protel Cloud PMS is offered as cloud or on-premise. It is strong in DACH and Central Europe and has a public Open API and sandbox. — [Chatlyn top-10](https://chatlyn.com/en/blog/top-10-pms-software/). Other points:
  - Planet integrates payments: one card authorisation covers the whole stay **[V]**. — [Mews vs Protel page](https://www.mews.com/en/compare/mews-vs-protel)
  - Third-party tools and payment systems can be accessed from inside Protel Cloud. — [Planet news](https://www.weareplanet.com/news/planet-enhances-protel-cloud-pms-empower-hoteliers-greater-integration-efficiency-and-control)
  - The Jan 2026 newsletter lists incremental work on reporting, rates, payments, invoices and guest journey. — [Planet newsletter](https://www.weareplanet.com/newsletter/protel-pms-february)
- **Stayntouch**: a cloud, mobile-first PMS. 2026 release "Stayntouch 2.0" was cited alongside a Laasie loyalty integration (30 Jun 2026). — [Hotel-Online](https://www.hotel-online.com/news/laasie-and-stayntouch-announce-strategic-integration-to-power-next-generation-hotel-loyalty-experiences)
  - It handles large full-service hotels: Imperial London Hotels completed a seven-property migration that included the 1,379-room Royal National, described as the largest hotel in Western Europe (25 Sep 2026). — [PR Newswire](http://www.prnewswire.com/news-releases/stayntouch-powers-full-pms-migration-across-imperial-london-hotels-including-the-largest-hotel-in-western-europe-302890420.html)
- **Guesty (STR)**: ReplyAI Autopilot and AI Task Creation (Apr 2026). Agent Hub, a coordinated multi-agent system, launched Jun 2026. A first AI agent for revenue management. A PriceOptimizer add-on. — [Barchart/press](https://www.barchart.com/story/news/36414565/guesty-unveils-first-ai-agent-for-revenue-management-as-it-accelerates-multi-agent-ai-product-strategy); [ShortTermRentalz](https://shorttermrentalz.com/news/guesty-launches-ai-agent-for-revenue-management/); [Yespress](https://yespress.io/guesty)
- **Hostaway (STR)**: AI-assist draft replies and a beta auto-reply. Own booking engine. — [aitoolsbakery](https://aitoolsbakery.com/blog/hostaway-review/); [symplehost](https://www.symplehost.ai/en/blog/guesty-vs-hostaway-vs-lodgify)
- **VisBook (Nordic)**: a PMS with modules for accommodation, conference, spa and restaurant. — [Lyra comparison](https://lyrasystem.com/en/insights/hotel-and-campsite-pms-comparison/)
- **Sirvoy (Swedish)**: targets small hotels, B&Bs and hostels. It "can feel too basic" for larger or complex hotels. — [Lyra comparison](https://lyrasystem.com/en/insights/hotel-and-campsite-pms-comparison/)

### Inferences

- **Feature matrix [unverified, analyst background; confirm before publishing].** Y = native, P = partner/marketplace, L = limited.

| Capability                       | OPERA Cloud             | Mews                          | Cloudbeds                  | Apaleo               | Protel     | Stayntouch         | Shiji Daylight     | Infor HMS     | Guesty                      | Hostaway           | VisBook               | Sirvoy |
| -------------------------------- | ----------------------- | ----------------------------- | -------------------------- | -------------------- | ---------- | ------------------ | ------------------ | ------------- | --------------------------- | ------------------ | --------------------- | ------ |
| Reservations / multi-property    | Y                       | Y                             | Y                          | Y                    | Y          | Y                  | Y                  | Y             | Y (listings)                | Y (listings)       | Y                     | L      |
| Folios / split billing / routing | Y                       | Y                             | Y                          | Y                    | Y          | Y                  | Y                  | Y             | L                           | L                  | Y                     | L      |
| Night audit                      | Y (auto)                | Y (auto, continuous)          | Y                          | Y (auto)             | Y          | Y                  | Y                  | Y             | n/a                         | n/a                | Y                     | L      |
| Groups / blocks                  | Y (strong)              | Y                             | Y (basic)                  | Y                    | Y          | Y                  | Y                  | Y             | L                           | L                  | Y                     | L      |
| City ledger / AR                 | Y                       | Y (new AR May 2026)           | L (cited gap)              | Y                    | Y          | Y                  | Y                  | Y             | n/a                         | n/a                | Y                     | L      |
| Mobile housekeeping              | Y                       | Y                             | Y                          | P                    | Y          | Y                  | Y (confirmed)      | Y             | Y (tasks)                   | Y                  | Y                     | L      |
| Online check-in / kiosk          | Y                       | Y                             | Y                          | P                    | Y/P        | Y (strong)         | Y                  | P             | Y                           | Y                  | Y/P                   | L      |
| Mobile key                       | P                       | P                             | P                          | P                    | P          | Y/P                | P                  | P             | P (smart locks)             | P                  | P                     | —      |
| Embedded payments                | Y (OPI/Oracle Payments) | Y (Mews Payments, terminals)  | Y (Cloudbeds Payments)     | Y (Apaleo Pay/Adyen) | Y (Planet) | Y (Stayntouch Pay) | Y (Shiji Payments) | P             | Y                           | Y                  | P (Nets etc.)         | P      |
| Revenue management               | P (+ Oracle RMS add-on) | Y (Mews RMS, 2026)            | Y (PIE / Signals)          | P                    | P          | P                  | P                  | P             | Y (PriceOptimizer/AI agent) | P (PriceLabs etc.) | P                     | —      |
| Channel manager                  | P (+ OXI/HTNG)          | P (+ Mews channel mgr add-on) | Y (native, a key strength) | P                    | P          | P                  | P                  | P             | Y                           | Y                  | Y/P                   | Y      |
| GDS                              | Y (native)              | P                             | Y (via CM)                 | P                    | P          | P                  | Y                  | Y             | —                           | —                  | —                     | —      |
| POS                              | Y (Simphony)            | Y (Mews POS)                  | P                          | P                    | P          | P                  | Y (Infrasys)       | Y (Infor POS) | —                           | —                  | Y (restaurant module) | —      |
| Door locks                       | P                       | P                             | P                          | P                    | P          | P                  | P                  | P             | P                           | P                  | P                     | P      |

- Native channel manager plus booking engine is what made Cloudbeds win the independent segment. Native POS plus payments is what made Mews win full-service mid-scale in Europe. Groups/AR depth plus GDS is what keeps OPERA in chains.
- With Mews' 2026 RMS and AR launches, the "PMS + RMS + messaging + payments + AR on one data model" bundle is now the reference architecture. A new entrant has to match it or integrate it convincingly.

### Gaps

- No verified per-vendor feature grid from a single independent source. The HTR comparison pages exist but were not fetched.
- I found no sources for Hotellinx features. VisBook's payments and channel-manager details were not confirmed.
- I could not confirm OPERA's native vs partner status for mobile key or kiosk in 2026.

---

## 2. Pricing models

### Takeaway

List prices are mostly hidden. The cloud-PMS range for the core is about **€8 to $17 per room per month**, rising to **$15–25+ per room per month** with RMS, POS, payments and messaging. Payments margin is a major hidden revenue line: Mews card fees of about 2.8% are reported by users. Enterprise vendors (Oracle, Shiji, Infor) are quote-only. STR platforms charge per listing plus booking-engine fees.

### Cited Findings

- **Apaleo**: core from about €8–9 per room per month. One source says a minimum of €400/year, another says a €400/month minimum (the sources conflict). Marketplace apps are billed separately. — [Hotelminder](https://www.hotelminder.com/partner=Apaleo); [Roommaster (competitor)](https://www.roommaster.com/alternatives/mews-vs-apaleo); [hoteltech.review](https://hoteltech.review/apaleo-pms-review-2026)
- **Mews**: does not publish prices. Estimates range from $8–15 per room per month (core), with an Essentials entry tier of about $300/month. Another source says about $17 per room per month, and a boutique guide says €9 per room per month. With RMS, POS and payments the cost is $15–25+ per room per month **[3P, inconsistent]**. — [Roommaster (competitor)](https://www.roommaster.com/blog/mews-pricing); [hoteltechinsight](https://hoteltechinsight.com/pms-vs/mews-vs-apaleo/); [FluxPMS (competitor)](https://fluxpms.com/vs-mews)
- Mews payments: Capterra and Trustpilot users report card processing at about 2.8% per transaction. Processing runs through a Mews master account, which makes disputes and reconciliation harder. One user reports a terminal (PDQ) request triggered a new contract with higher fees. — [Capterra](https://www.capterra.com/p/145487/Mews-Commander/reviews/); [Trustpilot](https://www.trustpilot.com/review/mews.com)
- **Cloudbeds**: no public price. Estimates:
  - About $15 per room per month entry, with per-property minimums. — [hoteltechinsight](https://hoteltechinsight.com/pms/cloudbeds/)
  - $150/month for 10 units, $500 for 50, and $900 for 100. — [PMScompare](https://www.pmscompare.com/pms/cloudbeds)
  - $200–1,000/month. — [CostBench](https://costbench.com/software/hotel-management/cloudbeds/)
  - Fully loaded, $18–25+ per room per month. — [Roommaster (competitor)](https://www.roommaster.com/blog/cloudbeds-pricing)
- **Oracle OPERA Cloud**: quote-only. OPERA Cloud Assistant AI features come at **no additional cost** to existing customers. — [Oracle](https://www.oracle.com/news/announcement/new-ai-capabilities-in-oracle-opera-cloud-supercharge-hotel-operations-2026-06-16/)
- **Shiji**: an enterprise agreement, pricing not published. — [Roommaster](https://www.roommaster.com/blog/shiji-alternatives)
- **Infor HMS**: sales-led, with no self-serve tiers. — [xpay.sh](https://www.xpay.sh/saas-pricing/infor-hms/)
- **Protel/Planet**: the PMS and Planet card processing can be decoupled. "They're your vendor for Protel PMS, but have nothing to do with setting your credit card processing rates." — [Merchant Cost Consulting](https://merchantcostconsulting.com/lower-credit-card-processing-fees/planet-payments-protel-pms-review/)
- **Guesty**: the Lite tier starts at $9 per listing per month, though other sources say $16 annual or $23 monthly, and some report a 1–1.9% booking fee on Lite. Pro (4–199 listings) and Enterprise are quote-only. — [hostport](https://hostport.co/blog/best-guesty-alternatives); [dupple](https://dupple.com/reviews/guesty)
- **Hostaway**: no published subscription price. A $500 onboarding fee. Third-party estimates are $25–50 per listing per month plus 1.8% on direct-booking-engine bookings. — [aitoolsbakery](https://aitoolsbakery.com/blog/hostaway-review/); [thehoststack](https://thehoststack.com/hostaway-vs-guesty/)
- **Sirvoy**: HTR lists it as popular in Sweden, the US and Canada. A low-cost SMB tool (exact price not captured). — [HTR Sirvoy](https://hoteltechreport.com/operations/property-management-systems/sirvoy)

### Inferences

- Pricing is opaque across the category. A **transparent, published per-room price** (with AI included, following Oracle's "no extra cost" precedent) is a cheap differentiator.
- Payments are where incumbents (Mews, Cloudbeds, Planet, Shiji) make margin. For a Salesforce-native suite, being **payment-provider-agnostic** (Adyen, Nets/Nexi, Stripe, Swedbank Pay) answers a common Mews complaint.
- Salesforce licence costs per user will sit on top of a per-room fee. The total cost has to stay competitive with the €8–25 per room per month band, or the product must be positioned on CRM/group/B2B value that standalone PMSs lack.

### Gaps

- No verified current Mews, Cloudbeds or Oracle list prices. All per-room figures are third-party, and several come from competing PMS vendors' blogs.
- No pricing found for VisBook, Hotellinx, Stayntouch or Protel subscriptions.

---

## 3. Integration marketplace size and API posture

### Takeaway

Mews (1,000+ Marketplace integrations) and Stayntouch (1,400+ integrations claimed by a third party, free API certification) lead on volume. Infor claims 700+. Apaleo leads on API-first philosophy and launched the first "AI Agent Hub" marketplace. Oracle relies on OHIP (Oracle Hospitality Integration Platform) [unverified count].

### Cited Findings

- Mews Marketplace has 1,000+ integrations, described as "hospitality's biggest app store" **[V]**. The 1,000th certified partner (Dayuse) dates to 2023, so the current number is likely higher but unpublished. — [Hospitality Net](https://www.hospitalitynet.org/news/4119400.html); [Mews Marketplace](https://www.mews.com/en/products/marketplace); [Mews community](https://community.mews.com/mews-marketplace-85/introduction-to-mews-marketplace-custom-connectivity-with-1-000-integrations-2891)
- Stayntouch: 1,400+ integrations and free API certification **[3P]**. — [Chatlyn top-10](https://chatlyn.com/en/blog/top-10-pms-software/); [Stayntouch integrations](https://www.stayntouch.com/integrations/)
- Infor HMS: over 700 existing integrations **[3P]**. — [xpay.sh](https://www.xpay.sh/saas-pricing/infor-hms/)
- Apaleo Agent Hub, launched around early 2025: a vendor-neutral marketplace to build, find and share AI agents. Launch agents included an email booking agent (Lobby), corporate sales and digital-twin agents (Triple), and a CRM/guest agent (TheNew Group). — [Apaleo blog](https://apaleo.com/blog/apaleo-news/apaleo-unveils-agent-hub); [PhocusWire](https://www.phocuswire.com/apaleo-agent-hub-ai-travel-marketplace)
- Protel: public Open API and sandbox. — [Chatlyn](https://chatlyn.com/en/blog/top-10-pms-software/)
- Strawberry's experience: about 15 active integrations per hotel, plus custom builds on the Mews Open API. — [Mews press](https://www.mews.com/en/press/strawberry-completes-rollout-of-mews-across-portfolio-of-230-hotels)

### Inferences

- Integration breadth is a moat that a 2027 entrant cannot match on day one. A Salesforce-native product should instead use the **AppExchange ecosystem and the Salesforce integration platform (MuleSoft, Flow, Agentforce)** and prioritise roughly 15 must-have Nordic integrations, matching Strawberry's average:
  - a channel manager (e.g. Channex, already built)
  - payments
  - door locks (ASSA ABLOY/Vingcard, Salto)
  - POS
  - accounting (Fortnox/Visma)
  - an RMS
  - messaging
  - BI
- Apaleo's agent-marketplace concept maps naturally onto Agentforce agents. This is a possible differentiator: "agents that act on PMS + CRM data in one org".

### Gaps

- No verified Apaleo Store app count. No OPERA OHIP partner count. No Cloudbeds marketplace count found in this session.

---

## 4. AI features, launches, funding and M&A (2025–2026)

### Takeaway

2026 is the year of "agentic PMS". Mews raised $300M explicitly for agentic AI and shipped Mews Agent in messaging. Oracle bundled AI at no cost. Cloudbeds built a hotel foundation model (Signals) plus a conversational layer. Guesty and Apaleo run multi-agent "hubs". Consolidation continues in STR (Guesty bought Smily).

### Cited Findings

- **Mews**: a $300M Series D led by EQT Growth with Atomico and HarbourVest, at a $2.5B valuation, up from $1.2B in Mar 2024. Announced 22 Jan 2026, with the funds aimed at agentic AI that coordinates pricing, staffing and guest services. — [Skift](https://skift.com/2026/01/22/mews-raises-300-million-series-d-2-5-billion-valuation/); [Tech.eu](https://tech.eu/2026/01/22/mews-raises-300m-to-accelerate-ai-powered-hospitality-operations)
  - Mews now has 15,000 customers in 85 countries **[V]**. — [Hospitality Net](https://www.hospitalitynet.org/news/4132634/mews-unveils-the-operating-system-for-hospitality)
  - Mews launched Mews BI (Apr 2026), then RMS, Messaging with Mews Agent, Automations and AR (May 2026). — same sources as above
- **Oracle**: OPERA Cloud Assistant (16 Jun 2026), free for existing customers. Wyndham runs 2,100+ properties on OPERA Cloud. — [Oracle](https://www.oracle.com/news/announcement/new-ai-capabilities-in-oracle-opera-cloud-supercharge-hotel-operations-2026-06-16/); [ERP Today](https://erp.today/oracle-opera-cloud-assistant-ai-hotel-operations/)
- **Cloudbeds**: Signals causal-AI foundation model (Sep 2025) and Ask Signals conversational AI (May 2026, pilot/launch). — [Hotelminder](https://www.hotelminder.com/cloudbeds-launches-signals-ai-platform-for-hotels); [Travolution](https://www.travolution.com/en/article/cloudbeds-launches-ask-signals-a-conversational-ai-interface-for-hotels)
- **Apaleo**: Agent Hub (around early 2025). Last round was a €20M Series B (Nov 2024), with total funding of about $31M and about 98 employees (May 2026) **[3P Tracxn]**. — [Apaleo blog](https://apaleo.com/blog/apaleo-news/apaleo-unveils-agent-hub); [Tracxn](https://tracxn.com/d/companies/apaleo/__8rUfl7s1eLsf5u7nkhH1-QgKcYDGiLQrjrCWNWCplTQ)
- **Guesty**:
  - Acquired Smily (formerly BookingSync, a French PMS and channel manager), completed 17 Sep 2026. — [Guesty press](https://www.guesty.com/press/guesty-acquires-smily-deepening-its-investment-in-frances-booming-short-term-rental-market/); [Dealroom](https://dealroom.co/news/151488-guesty-buys-frances-smily-to-expand-in-9b-rental-market/)
  - Launched ReplyAI Autopilot (Apr 2026) and Agent Hub (Jun 2026). "40 specialized agents live" and "300+ features shipped in 2026" **[V]**. — [Yespress](https://yespress.io/guesty); [Barchart](https://www.barchart.com/story/news/36414565/guesty-unveils-first-ai-agent-for-revenue-management-as-it-accelerates-multi-agent-ai-product-strategy)
  - Last funding was a $130M Series F (Apr 2024). — [Skift](https://skift.com/2024/04/10/guesty-raises-130-million-for-global-expansion-acquisitions-and-ai/)
- **Hostaway**: $365M round led by General Atlantic (with PSG), 17 Dec 2024, at a $925M post-money valuation. Total funding about $543M. — [hellohosty / search summary](https://hellohosty.com/news-insights/guesty-vs-hostaway/) (secondary; verify against press release)
- **Shiji Daylight 2026 wins**:
  - Kempinski selected Daylight (4 Aug 2026).
  - JUFA Hotels: 61 European hotels with Amadeus iHotelier.
  - Coral Sea Hotels (8 Jun 2026).
  - 440+ cities in 36 countries (15 Jun 2026).
  - A 100+ hotel rollout for one group in two months.
  - Sources: [Shiji Kempinski](https://www.shijigroup.com/press-news/shijis-daylight-pms-selected-by-kempinski-hotels-to-elevate-luxury-guest-experiences); [Shiji JUFA](https://www.shijigroup.com/press-news/jufa-hotels-selects-shiji-daylight-pms-and-amadeus-ihotelier-r-to-power-the-future-of-family-focused-hospitality-across-61-european-hotels); [Shiji 36 countries](https://www.shijigroup.com/press-news/shijis-daylight-pms-expands-across-449-cities-and-36-countries-with-full-fiscal-compliance); [Shiji 100+ rollout](https://es.shijigroup.com/press-news/shiji-sets-new-benchmark-with-100-hotel-pms-rollout-for-a-single-group-completed-in-two-months)
- **Stayntouch**: still owned by MCR, with no 2026 M&A. Customer wins include Regency (Feb 2026), Storey (Apr 2026) and Imperial London (Sep 2026). — [Hotel Management](https://www.hotelmanagement.net/property-management/stayntouch-selected-regency-hotel-management-pms-deployment); [PR Newswire](http://www.prnewswire.com/news-releases/stayntouch-powers-full-pms-migration-across-imperial-london-hotels-including-the-largest-hotel-in-western-europe-302890420.html)
- **Planet/Protel**: Planet acquired Protel and rebranded. It later bought XN PMS Ltd (the UK/GCC Protel distributor), while Xn protel Systems remained independent. — [Merchant Cost Consulting](https://merchantcostconsulting.com/lower-credit-card-processing-fees/planet-payments-protel-pms-review/)

### Inferences

- "Agentic" claims are mostly guest messaging autopilot, conversational analytics, and RMS autopilot. True cross-system autonomous operations remain aspirational (the Skift headline frames Mews as needing "to prove AI can run hotel operations").
- Agentforce on Salesforce gives an entrant a credible agent story on the same data as CRM, service and marketing. That is a stronger narrative than bolt-on messaging bots, but it must ship concrete use cases (upsell, group RFP handling, guest messaging, AR chasing) to compete with Mews Agent and Guesty's 40 agents.

### Gaps

- No Cloudbeds funding or layoff news found. No Infor HMS 2026 AI announcements found. No Hostaway 2026 AI launch details verified.

---

## 5. Market share, segment focus, Nordic presence

### Takeaway

**Mews is the dominant modern cloud PMS in the Nordics**: Strawberry (formerly Nordic Choice), about 230 hotels, migrated fully by Jun 2024. **VisBook** is the strongest Nordic-native independent PMS, with about 900–1,250 customers. OPERA and Infor hold chain and legacy positions. Sirvoy covers the micro/SMB end in Sweden. Cloudbeds leads globally for independents (HTR #1). Oracle leads chains.

### Cited Findings

- Strawberry (formerly Nordic Choice Hotels): about 230 hotels and 9,000 employees on Mews, with full rollout announced Jun 2024. Rollout ran at five hotels per week in 2023. Chosen for flexibility, scalability and security. Brands include Comfort, Quality, Clarion, Clarion Collection and about 50 independents. — [Mews press](https://www.mews.com/en/press/strawberry-completes-rollout-of-mews-across-portfolio-of-230-hotels); [Hospitality Investor 2023](https://www.hospitalityinvestor.com/technology/2023-hotel-technology-review-cloud-migration-and-personalisation)
- Strawberry uses Event Temple for group sales/events (125 hotels by Jan 2024). — [Hotel Technology News](https://hoteltechnologynews.com/2024/01/strawberry-hotels-achieve-major-milestone-with-launch-of-their-125th-hotel-property-on-event-temple/)
- VisBook is gaining share in Sweden and the Nordics. Its customer counts conflict:
  - over 900 customers (Swedish About page) — [VisBook](https://visbook.se/about-us/)
  - over 1,000 Nordic customers (news) — [VisBook news](https://visbook.com/news/)
  - about 1,250 hotels — [Sweeply](https://getsweeply.com/articles/hotel-software-nordic-properties)
  - Swedish sales "more than doubled" in recent years **[V]**.
- Swedish VisBook customers include Excellence Hotels and IKEA Hotell. Common Nordic PMSs are Mews, OPERA Cloud, Infor and VisBook. — [Sweeply](https://getsweeply.com/articles/hotel-software-nordic-properties); also case study [Åhus Seaside](https://visbook.com/the-hotel-system-that-could-meet-all-ahus-seasides-needs/)
- Sirvoy: Swedish, for small properties, popular in Sweden, the US and Canada. — [HTR](https://hoteltechreport.com/operations/property-management-systems/sirvoy); [Lyra](https://lyrasystem.com/en/insights/hotel-and-campsite-pms-comparison/)
- HTR 2026: Cloudbeds is #1 in Hotel Management Software, recommended by 91% of 1,273 hoteliers in 32 countries. HTR's PMS category covers 345 products and 9,410 hoteliers. HTR scores **[3P restated]**: Cloudbeds 4.6 (1,261 reviews), OPERA Cloud 4.6 (761), Stayntouch 4.7 (381). — [HTR PMS list](https://hoteltechreport.com/news/best-hotel-pms-software); [iTechGuides](https://www.itechguides.com/best-hotel-pms-in-2026-pricing-reviews-demo/)
- HTR's PMS buyer's guide is sponsored and hosted by Mews (a bias caveat). — [Mews/HTR guide](https://www.mews.com/en/resources/research/htr-buyers-guide-by-mews)
- Segments:
  - **Oracle**: chains and enterprise (Wyndham 2,100+ properties). — [Oracle](https://www.oracle.com/news/announcement/new-ai-capabilities-in-oracle-opera-cloud-supercharge-hotel-operations-2026-06-16/)
  - **Shiji**: mid-to-enterprise groups and luxury (Kempinski).
  - **Stayntouch**: US select- and full-service management companies, now expanding into the UK.
  - **Protel**: DACH and Central Europe.
  - **Mews**: 15,000 customers in 85 countries, mainly Europe, and expanding in North America.
  - **Guesty/Hostaway**: STR and professional property managers. Guesty is expanding in Europe through Smily (France).

### Inferences

- In Sweden, the realistic incumbent displacement targets are VisBook (independents, conference/spa hotels, a natural fit for a CRM-heavy Salesforce offer), legacy OPERA 5 and Infor sites, and groups unhappy with Mews payments or support.
- The Strawberry win shows Nordic chains will migrate quickly (five hotels/week) when the vendor is credible, but it also means the largest Nordic group is locked into Mews for years.

### Gaps

- No Nordic market-share data was found for any vendor. Hotellinx (Finland) returned no results in this session. No data on Scandic's PMS (Scandic is believed to be on OPERA/in-house [unverified]), Thon, or Elite Hotels. No Swedish data for Bookboost (a guest CRM/messaging tool, not a PMS [unverified]).

---

## 6. Common customer complaints (openings for a new entrant)

### Takeaway

Across Mews and Cloudbeds, the recurring pain points are **post-onboarding support quality** (slow, ticket-closing, generic AI answers), **payment fees and reconciliation opacity**, and **weak B2B/corporate billing (city ledger)**. These play directly to Salesforce strengths: Service Cloud support, B2B accounts and AR.

### Cited Findings

- Mews:
  - Support deteriorates after the 30-day onboarding. Tickets are closed without answers. The AI assistant gives "generic ChatGPT-style answers". Some users say this has improved recently. — [Capterra](https://www.capterra.com/p/145487/Mews-Commander/reviews/); [Trustpilot](https://uk.trustpilot.com/review/mews.com?page=2)
  - Card fees of about 2.8%, payments deducted on the invoice date rather than the due date, high cross-border fees, master-account processing complicating disputes and reconciliation, and unclear fees. — [Capterra](https://www.capterra.com/p/145487/Mews-Commander/reviews/); [G2](https://www.g2.com/products/mews/reviews)
  - Complicated setup and workflow, weak business bookings and invoices, and booking-engine availability display issues. — [Capterra](https://www.capterra.com/p/145487/Mews-Commander/reviews/)
  - Sample sizes are small: G2 has about 32 reviews and Trustpilot about 40–96 per country page.
- Cloudbeds:
  - Slow email support on urgent issues and a lack of human support. — [Capterra](https://www.capterra.com/p/158839/Cloudbeds/reviews/); [Trustpilot](https://nl.trustpilot.com/review/cloudbeds.com)
  - No good corporate-billing-account handling. — [G2](https://www.g2.com/products/cloudbeds/reviews?page=2)
  - Billing and payment issues. — [Trustpilot](https://uk.trustpilot.com/review/cloudbeds.com?page=4)
  - Complaints about onboarding, reporting and UI.
  - Counterpoint: Capterra 4.3 (358 reviews), customer service 4.0. GetApp says support is fast and 24/7 (a conflict).
- Sirvoy: too basic for larger or complex hotels. — [Lyra](https://lyrasystem.com/en/insights/hotel-and-campsite-pms-comparison/)
- Apaleo: total cost and complexity grow because core apps such as the channel manager and booking engine are bought separately from marketplace vendors. — [Hotelminder](https://www.hotelminder.com/partner=Apaleo)
- Hostaway: no transparent pricing, plus a $500 onboarding fee. — [aitoolsbakery](https://aitoolsbakery.com/blog/hostaway-review/)

### Inferences

Openings for a Salesforce-native entrant:

1. B2B/corporate accounts, contracts, group RFPs and AR on the CRM account object.
2. Transparent payments with merchant choice and clean reconciliation into ERP (Fortnox/Visma).
3. Named, local-language (Swedish) human support with SLAs.
4. Configurability without code (Flow).
5. One data model for guest CRM, marketing and service, which standalone PMSs lack.

Legacy OPERA/Infor complaints (UI complexity, implementation cost) are likely but were not verified this session.

### Gaps

- OPERA Cloud, Shiji, Infor, Stayntouch, Apaleo and Guesty complaint themes were not researched in depth. The HTR review pages were not fetched.

---

## 7. Table stakes for a 2027 hotel PMS vs differentiators

### Takeaway

By 2027, buyers will expect a cloud multi-property PMS with embedded payments, mobile housekeeping, online check-in, a certified channel manager, an open API and marketplace, and _some_ AI (messaging and room or rate assistance), with that AI free or bundled. Differentiation is shifting to unified data, agentic automation, B2B/AR depth, payments transparency, and support.

### Cited Findings

- Oracle bundles its AI at no extra cost, which sets a price-anchor expectation that basic AI is included. — [Oracle](https://www.oracle.com/news/announcement/new-ai-capabilities-in-oracle-opera-cloud-supercharge-hotel-operations-2026-06-16/)
- Mews now ships PMS, RMS, messaging, automations, AR, BI, payments and POS on one data model. — [Hospitality Net](https://www.hospitalitynet.org/news/4132634/mews-unveils-the-operating-system-for-hospitality)
- Shiji advertises "full fiscal compliance" in 36 countries as a selling point. Nordic fiscal and SIE accounting export requirements are equivalent table stakes locally. — [Shiji](https://www.shijigroup.com/press-news/shijis-daylight-pms-expands-across-449-cities-and-36-countries-with-full-fiscal-compliance)
- HTR's buying-decision analysis for 2026 (the Hospitality Net opinion piece "Inside the Hotelier's PMS Shortlist") exists but was not fetched. — [Hospitality Net](https://www.hospitalitynet.org/opinion/4129296/inside-the-hoteliers-pms-shortlist-what-really-drives-buying-decisions-in-2026)

### Inferences

**Table stakes (2027):**

- Reservations
- Rate plans and restrictions (MinLOS, CTA/CTD, stop-sell)
- Folios with split and routing
- Automated night audit
- Groups/blocks
- City ledger/AR
- Mobile housekeeping
- Guest profiles
- Online check-in/out
- Embedded payments (tokenisation, PCI scope reduction, terminals, pay-by-link)
- Channel manager (native or certified)
- Booking engine
- Multi-property
- Open REST API
- GDPR, and Swedish fiscal/bookkeeping rules (SIE export, kassaregister if POS)
- AI messaging assist

**Differentiators:**

- Agentic AI acting across PMS, CRM and service (Agentforce)
- Embedded RMS
- Unified guest CRM and marketing
- B2B/MICE sales and events in the same system (Strawberry needed Event Temple for this)
- Payment-provider choice
- Transparent pricing
- Local support
- Aparthotel/long-stay billing (a bridge to Guesty/Hostaway-type STR features)
- Kiosk and mobile key via partners such as ASSA ABLOY

A Salesforce-native suite's strongest wedge is **groups/MICE, corporate accounts and AR, and CRM/loyalty**: areas where Mews, Cloudbeds and Apaleo either outsource (Event Temple and similar) or are weak (Cloudbeds corporate billing). It should match Mews on payments and messaging basics.

### Gaps

- No independent 2026 survey quantifying which features buyers rank highest was retrieved. The HTR "PMS shortlist" article was not fetched.
- No data on Salesforce-native PMS competitors (e.g., existing AppExchange hotel apps) in this session. This deserves a separate check.
