# PMS commercial control plan (v3, 21 Nov 2026)

**Launch model (decided 21 Nov):**

- **Pilot launch on 1 Jan 2027.** Customers install the managed package into their own Salesforce org by private link and get 3 months free.
- **From about 1 April,** each customer pays on the plan they choose (monthly, annual or one-time setup).
- **Pilot clock:** built into the 1 Jan version. Full access for 90 days from install, then a licence key is needed.
- **Licence service and purchase website:** needed by late March, not by 1 Jan.
- **Permanent Dev Hub before 1 Jan:** pilot customers install a promoted version, so the Dev Hub that owns it must outlive the pilot. Use a free Developer Edition org and register the namespace by 4 Dec. Rotating trial Dev Hubs stay fine for scratch and dev orgs.

Decisions made by the owner on 21 Nov:

- No Partner Program yet; we join later.
- Dev Hubs are free trial orgs. When one expires, a new trial takes over.
- Free orgs are created when needed. We must always be able to deploy the full product and its configuration into them.
- No clients yet. Clients will buy through our own website, which comes later. They buy their own Salesforce org and licences, and we tell them what they need before they buy.
- Pricing is the recommended proposal, held in configuration and switched on when we are ready.
- After a failed payment, the default grace period is 30 days. It is configurable and adjusts automatically from each client's payment history.

## 0. Rotating trial Dev Hubs: what works and what doesn't

| Phase                         | Rotating trial Dev Hub | Why                                                                                                                                                                                                                                                                                        |
| ----------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Development, no clients (now) | OK                     | We deploy source into scratch, trial and Developer Edition orgs. No package versions need to survive.                                                                                                                                                                                      |
| First paying client onwards   | Not OK                 | A managed package belongs to the Dev Hub that created it. If that Dev Hub expires, we cannot ship upgrades or fixes to clients who already installed it. A package created in a new Dev Hub is a different package, even under the same namespace, so it cannot upgrade existing installs. |

**Rule:** before the first managed package version goes to a client, choose one Dev Hub that never expires.

- If we still have not joined the Partner Program, a free **Developer Edition** org is free and does not expire while it is used regularly.
- Later we can join the Partner Program. Whether the packages can then move to the Partner Business Org needs checking with Salesforce (moving a package to another Dev Hub is a support request, if it is offered at all; verify).
- The namespace must be registered in a free Developer Edition org that we also keep. A namespace can be linked to more than one Dev Hub.

Until then, the rotation path is:

1. Create a new trial.
2. Run `pms-package.sh devhub <alias>`.
3. Run `pms-package.sh bootstrap <org>` for each work org.
4. Before any org expires, run `config-export` and commit.

## A. Free-org tooling (in build)

| Command                           | What it does                                                                                                                                                                                                                                          |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `devhub <alias>`                  | Logs in to the new trial, sets it as the project's Dev Hub, checks that Dev Hub is enabled, and shows the expiry date and the steps to enable it or link the namespace                                                                                |
| `bootstrap <alias> [--scratch]`   | Deploys Core and Experience (from source by default), then sites and portals with token replacement, permission sets, config, sample data, optional tests and a smoke check. Safe to re-run. Warns and continues if the org lacks community licences. |
| `config-export` / `config-import` | Saves PMS configuration records to `packages/pms/config-data/` in git and reloads them. Secrets are never exported.                                                                                                                                   |

## B. Licence and feature control without the Partner Program

Salesforce's License Management App and Feature Management App need the Partner Program. Until we join, we use our own **signed licence key**. We can switch to Salesforce's apps later without changing the modules, because they only ever ask `PMS_Entitlements`.

**Signed licence key.** Our licence service signs a small token with our private key. The package verifies it with the public key built into Core (`Crypto.verify`), so the client cannot forge or edit it. The token contains:

| Field               | Purpose                                                                          |
| ------------------- | -------------------------------------------------------------------------------- |
| `orgId`             | Must match `UserInfo.getOrganizationId()`, so a key can't be copied between orgs |
| `edition`           | Start, Pro or Enterprise                                                         |
| `modules`           | Hotel, Property, Finance, Staff, AI                                              |
| `caps`              | Max rooms, max units, max portal users                                           |
| `validUntil`        | Paid-up period                                                                   |
| `graceDays`         | Calculated per client by the licence service (see below)                         |
| `issuedAt`, `keyId` | Lets the token expire and our signing key change                                 |

- **Storage:** a protected custom setting in Core, invisible to subscriber admins.
- **Renewal:** a daily scheduled job fetches the latest token from our licence endpoint. An admin can also paste a token into PMS Settings if the endpoint can't be reached.
- **`PMS_Entitlements`** (Core, `@NamespaceAccessible`): every trigger, job, callout, AI action and LWC tab asks it whether a module is on, what its caps are, and the current state. Results are cached per transaction.

**Master switch:** a protected custom metadata setting `Enforcement_Enabled` ships **off**. With it off, the package runs with every module on: development, demos and first pilots. We turn it on in a package version when billing starts. Dev mode is always on in scratch and test contexts.

| State                              | Behaviour                                                                                                                     |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Trial                              | Full access until `validUntil`, with a banner                                                                                 |
| Active                             | Normal                                                                                                                        |
| Grace (`validUntil` + `graceDays`) | Normal, with a warning banner counting down the days                                                                          |
| Suspended                          | No new bookings, rooms, units or channel pushes. Check-out, refunds, payments for in-house guests and data export still work. |
| Module off                         | Tab hidden, API blocked, jobs skipped. Data is kept.                                                                          |

## C. Grace period (configurable and automatic)

The defaults below are held in our licence service config, never in the client org:

| Payment history (last 12 invoices) | Grace                               |
| ---------------------------------- | ----------------------------------- |
| New client, or no late payments    | **30 days** (default, configurable) |
| 1–2 invoices paid late             | 21 days                             |
| 3+ late, or any earlier suspension | 10 days                             |
| Manual override per client         | Any value                           |

- The score is recalculated whenever a payment succeeds or fails.
- The resulting `graceDays` goes into the next token.
- Every threshold and day count is configurable.
- Banners and emails go out at 30, 14, 7 and 1 days before suspension.

## D. Client prerequisites and notice before purchase

- `packages/pms/config/prerequisites.json` lists, per module: Salesforce edition (Enterprise or Unlimited; Professional only after the security review, verify), staff user licences, Experience Cloud licences per portal, Agentforce/Data Cloud credits for AI, the client's own Stripe account, domains, and that Channex is included.
- The purchase website shows this checklist for the modules chosen before checkout, and the order confirmation repeats it.
- `pms-package.sh check <org>` and a post-install banner list anything the client's org is missing.

## E. Billing and the purchase website (later; switch-on by config)

Flow:

1. Website (choose edition and modules, see the prerequisites)
2. Stripe Checkout or Billing (monthly, annual or one-time setup)
3. Licence service issues the token for the client's org ID
4. Client receives the install link, installs, and the daily job fetches the token
5. Stripe webhooks for paid, failed or cancelled payments update `validUntil` and the grace score, and the next token reflects them

**Hosting the licence service:** a small serverless API on a free tier, next to the website, holding the signing key, plans and grace config.

**Revenue share:** not applicable while we sell outside AppExchange. Re-check when we join the Partner Program.

## F. Price list (recommended; stored as config, live when billing is switched on)

| Edition    | Hotel (per room/month)             | Property (per object/month) | Includes                                                                                                                                       |
| ---------- | ---------------------------------- | --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Start      | SEK 69, min SEK 1,900 per property | SEK 12, min SEK 1,200       | Core PMS or leases, booking engine, portals, Channex, SIE4, basic AI                                                                           |
| Pro        | SEK 99, min SEK 2,900              | SEK 18, min SEK 1,900       | Start, plus Swedish money flows (Fortnox/Visma, Swish, Autogiro, OCR, Peppol, BankID), groups, city ledger, locks, POS, workforce integrations |
| Enterprise | Quote (from SEK 129)               | Quote (from SEK 25)         | Pro, plus portfolio, public API, Data Cloud 360, AI pricing, SLA                                                                               |

- **Annual prepay:** 2 months free.
- **Setup:** SEK 15,000 (Start), SEK 35,000 (Pro), quoted for Enterprise.
- **Migration:** fixed price per project.
- **Early adopters:** 30% off for 24 months for the first 10 clients.
- **Payments:** no margin taken.
- **Heavy AI use:** passed through at the client's consumption cost.

Benchmarks are in reports/PMS competitor landscape 2026.md.

## Build order

| Step  | What                                                                                               | Days             |
| ----- | -------------------------------------------------------------------------------------------------- | ---------------- |
| 1     | Free-org tooling (A)                                                                               | 6 (in build)     |
| 2     | `PMS_Entitlements`, signed-token check, master switch off, dev mode, tests                         | 6                |
| 3     | Hook entitlements into handlers, jobs, callouts, AI and tabs, with suspended behaviour             | 5                |
| 4     | Prerequisites file, `check` command, post-install banner                                           | 6                |
| 5     | Licence service (token issuing, grace scoring, renewal endpoint)                                   | 6                |
| 6     | Purchase website, Stripe Billing and webhooks                                                      | Separate project |
| Later | Join the Partner Program, choose a permanent Dev Hub, optionally move to Salesforce's licence apps | —                |
