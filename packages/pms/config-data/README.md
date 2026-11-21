# PMS configuration data

Configuration records exported from a configured PMS org, so a new free trial or
Developer Edition org can get the same setup. Written by
`scripts/pms-package.sh config-export <org>` and loaded by `config-import <org>`
(and by `bootstrap`). Until the first export this folder only holds this file.

| File                         | Records                                                           |
| ---------------------------- | ----------------------------------------------------------------- |
| `plan.json`                  | Import order and reference mapping (`sf data import tree --plan`) |
| `01-PMS_Dunning_Policy__c`   | Dunning policies                                                  |
| `02-PMS_Payment_Policy__c`   | Payment policies                                                  |
| `03-PMS_Site__c`             | Sites (no manager, owner account or Channex sync state)           |
| `04-PMS_Space_Type__c`       | Room / space types                                                |
| `05-PMS_Rate_Plan__c`        | Rate plans                                                        |
| `06-PMS_Pricing_Strategy__c` | Dynamic pricing strategies (no last-run state)                    |
| `07-PMS_Pricing_Factor__c`   | Pricing factors                                                   |
| `08-PMS_Channel_Mapping__c`  | Channex rate plan / room type mappings                            |
| `09-PMS_Index_Value__c`      | Rent index values                                                 |
| `10-PMS_Access_Team__c`      | Access teams (no members or member count)                         |
| `11-PMS_Access_Rule__c`      | Access rules                                                      |
| `12-PMS_Settings__c`         | Org-wide PMS Settings (Channex flags only)                        |

Only objects that have records appear. Files hold no namespace; the script adds the
target org's namespace on import and strips it on export. Lookups between these
objects are stored as `@reference` ids, so import them with the plan, not one by one.

PMS Module and PMS Access Object custom metadata are part of the Core source and
deploy with it, so they are not exported.

## What is never exported

- Transactional data: bookings, charges, invoices, payments, dunning events, channel logs.
- Secrets and org-specific values: `PMS_Settings__c.Webhook_Secret__c`,
  `Checkout_Return_URL__c`, `Public_Pay_URL__c`, Stripe and Channex credentials
  (named credentials hold those). Anything whose field name looks like a key, token,
  secret or password is stripped on export even if it is added to the query later.
  Set these by hand in each new org (see `packages/pms/README.md`).
- Record types, owners and users (not portable between orgs).

## Re-importing

`config-import` skips any object that already has records in the target org (with a
warning), and also skips objects that point at a skipped one. It never duplicates.
To reload an object, delete its records in the target org first.
