# binance

Salesforce metadata and supporting files for `binance`.

## Contents

- `main/default/` — deployable Salesforce metadata
- `manifest/package.xml` — metadata selection for retrieve and deploy operations
- `scripts/apex/` — anonymous Apex scripts
- `scripts/soql/` — reusable SOQL queries

The package contains the Binance credentials, integration permission set, ticker
Apex data/action classes and tests, and the Agentforce rich-output LWC.

Run from the repository root:

```bash
scripts/sf-package.sh retrieve binance <org-alias>
scripts/sf-package.sh deploy binance <org-alias> --dry-run
scripts/sf-package.sh deploy binance <org-alias>
```
