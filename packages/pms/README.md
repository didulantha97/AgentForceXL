# PMS: property, hotel, practice and project management

PMS ships to client orgs as two **managed second-generation (2GP) packages**,
plus a small set of org metadata that Salesforce does not allow in packages.

| Folder        | What it is                              | Contents                                                                                                                                                               |
| ------------- | --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `core/`       | Package **PMS Core**                    | 40 objects, Apex services, triggers and batch jobs, internal LWCs (room grid, Gantt, booking wizard…), 5 apps, FlexiPages, reports, `PMS_App_Access`, `PMS_Core_Admin` |
| `experience/` | Package **PMS Experience** (needs Core) | Customer, partner and public-booking portal LWCs and controllers, guest check-in, Stripe checkout and webhook, agent actions and flows, portal permission sets         |
| `org-setup/`  | Not packageable; deployed after install | `main/`: 3 Experience sites, the Payments site, guest/portal profiles, `PMS_Admin` role, sharing rules. `agent/`: PMS Concierge Agentforce agent                       |
| `manifest/`   | Retrieve manifest for the source org    | Everything above, by name                                                                                                                                              |
| `config/`     | Scratch/build org shape                 | Experience Cloud + Customer Community Plus + Partner Community licences                                                                                                |

The Dev Hub that owns the packages is **ecaViaMetadata** (override with `PMS_DEVHUB`).

## Deliver PMS to a client org

**Option A, with clicks (client admin):**

1. Open the **PMS Core** install link, choose _Install for Admins Only_, and install.
2. Open the **PMS Experience** install link and install.
3. Your team runs `scripts/pms-package.sh org-setup <client-alias>` to create the
   sites, profiles, role and sharing rules. Add `--with-agent` if the org has
   Agentforce.

Get the current links with `scripts/pms-package.sh links`.

**Option B, one command (your team, client org authorised in the CLI):**

```bash
sf org login web -a client-acme
scripts/pms-package.sh install client-acme            # released versions
scripts/pms-package.sh install client-acme --beta     # latest beta, sandboxes only
```

This installs both packages, deploys org-setup, gives the Booking site's guest
user its permission sets, and assigns `PMS_App_Access`, `PMS_Core_Admin` and
`PMS_Experience_Access` to the admin.

**After either option**, in the client org:

- Publish each site once: Setup > Digital Experiences > All Sites > Builder > Publish.
- Enter the Stripe secret key: Setup > Named Credentials > External Credentials >
  Stripe API > StripePrincipal. Then fill in **PMS Settings** (webhook secret and
  checkout return URL).
- Assign the `PMS_Standard_User` permission set group to staff:
  `scripts/pms-package.sh access <org> --user <username> --role staff`
  (`--role admin`, the default, assigns every admin permission set). The package post-install
  scripts already give the installing admin `PMS_Core_Admin` + `PMS_App_Access` (Core) and the
  Experience admin sets; add-on sets (Access Manager, Channex, Dynamic Pricing, Rent Review) need
  `access <org> --role admin`.
- Audit access from source at any time: `node packages/pms/scripts/access-audit.js [--check]`.

## Free orgs (trial Dev Hubs, Developer Edition, scratch)

Dev Hubs and trial orgs expire, so the full PMS and its configuration can be rebuilt
in any org with source deploy; package install is optional. Run from the repo root.

| Situation                           | Command                                                                                                                   |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| A new trial org becomes the Dev Hub | `scripts/pms-package.sh devhub <alias>` (logs in, sets it as default, verifies, prints expiry)                            |
| Need a working PMS in a new org     | `scripts/pms-package.sh bootstrap <alias>` for a trial/DE org (it logs you in), or `bootstrap <alias> --scratch --days 7` |
| Same, from released packages        | `bootstrap <alias> --version-core 04t... --version-exp 04t...`                                                            |
| Before an org expires               | `scripts/pms-package.sh config-export <alias>`, then commit `packages/pms/config-data/`                                   |

`bootstrap` deploys Core then Experience, runs org-setup, assigns the three PMS permission
sets, imports `config-data/`, loads sample data (`--no-sample` to skip), optionally runs the
PMS Apex tests (`--tests`) and finishes with a smoke check. It is safe to re-run. Trial and
Developer Edition orgs may lack Experience Cloud or community licences: org-setup then
reports a warning and Core and Experience are still deployed. A new Dev Hub does not own the
old packages; run `create` and `version` again if you need installable packages.

## Release a new version

```bash
scripts/pms-package.sh version          # builds Core, then Experience (runs all Apex tests)
scripts/pms-package.sh install my-sandbox --beta   # test the beta
scripts/pms-package.sh promote          # release, so production orgs can install it
git add sfdx-project.json && git commit -m "chore: PMS 1.x"   # keeps the version aliases
```

Bump `versionNumber` in `sfdx-project.json` for each release (`1.1.0.NEXT`,
`2.0.0.NEXT`…). Experience depends on `PMS Core 1.0.0.LATEST`; change that when
Core's major or minor version changes. Released managed versions are permanent,
so test betas in a sandbox before promoting.

## One-time setup

1. **Register a namespace.** In a separate free Developer Edition org (not the Dev
   Hub), go to Setup > Package Manager > Namespace Settings, then Edit and choose a
   prefix such as `pmsx`. The prefix is permanent and appears on every PMS
   object (`pmsx__PMS_Booking__c`).
2. **Link it to the Dev Hub.** Log in to ecaViaMetadata, open the App Launcher,
   go to Namespace Registries, click Link, and log in as the namespace org.
3. **Create the packages:**

   ```bash
   scripts/pms-package.sh create pmsx
   git add sfdx-project.json && git commit -m "chore: create PMS packages"
   ```

## Development

```bash
scripts/pms-package.sh scratch pms-dev   # scratch org with Core, Experience and org-setup from source
sf project deploy start -d packages/pms/core -o pms-dev
```

Keep the package boundary: **Core must never reference Experience** (classes,
LWCs, permission sets, layouts). If Experience code calls a Core class, that
class and the members it uses must be `@NamespaceAccessible`. `@AuraEnabled`
members cannot carry that annotation, so pass them through a method instead.
Experience tests use `PMS_ExperienceTestFactory`, a copy of the Core test
factory, because `@isTest` classes cannot be shared across packages.

## Refreshing from the source org

The solution was built in `agentforce-org-nov`. **That org expires on
2026-12-08**, so this repository is now the source of truth. To pull changes
from another org, retrieve into a scratch folder and copy the files into the
right package:

```bash
sf project retrieve start --manifest packages/pms/manifest/package.xml -o <org> --output-dir pms-retrieve-tmp
```

## Known differences from the source org

- Apps assign the Hotel and Property site record pages per app, not per profile.
  Profile-based assignments can't be packaged.
- Profiles in `org-setup` carry only licence and login settings. All object,
  field and class access comes from the packaged permission sets.
- The `New Note` action was removed from the Invoice layout so installs work in
  orgs without Notes enabled.
- The Concierge agent is deployed as metadata from `org-setup/agent`. To ship it
  inside a package, convert it to an agent template with `sf agent generate template`.
