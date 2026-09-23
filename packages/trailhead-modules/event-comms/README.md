# trailhead-modules/event-comms

Salesforce metadata and supporting files for `trailhead-modules/event-comms`.

## Contents

- `main/default/` — deployable Salesforce metadata
- `manifest/package.xml` — metadata selection for retrieve and deploy operations
- `scripts/apex/` — anonymous Apex scripts
- `scripts/soql/` — reusable SOQL queries

Add the required metadata types and members to `manifest/package.xml` before the first retrieve.

Run from the repository root:

```bash
scripts/sf-package.sh retrieve trailhead-modules/event-comms <org-alias>
scripts/sf-package.sh deploy trailhead-modules/event-comms <org-alias> --dry-run
scripts/sf-package.sh deploy trailhead-modules/event-comms <org-alias>
```
