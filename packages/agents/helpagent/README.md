# agents/helpagent

Salesforce metadata and supporting files for `agents/helpagent`.

## Contents

- `main/default/` — deployable Salesforce metadata
- `manifest/package.xml` — metadata selection for retrieve and deploy operations
- `scripts/apex/` — anonymous Apex scripts
- `scripts/soql/` — reusable SOQL queries

Add the required metadata types and members to `manifest/package.xml` before the first retrieve.

Run from the repository root:

```bash
scripts/sf-package.sh retrieve agents/helpagent <org-alias>
scripts/sf-package.sh deploy agents/helpagent <org-alias> --dry-run
scripts/sf-package.sh deploy agents/helpagent <org-alias>
```
