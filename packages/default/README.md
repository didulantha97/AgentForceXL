# Default package

This is the workspace's default Salesforce DX package. Use it for general
metadata that does not belong to a Superbadge or another isolated project.

## Contents

- `main/default/` — deployable metadata
- `manifest/package.xml` — metadata selection for manifest operations
- `scripts/apex/` — anonymous Apex scripts
- `scripts/soql/` — reusable SOQL queries

Run every command below from the repository root and replace `dev-org` with the
correct authenticated org alias.

## Retrieve

For an initial or manifest-controlled retrieve:

```bash
sf project retrieve start \
  --manifest packages/default/manifest/package.xml \
  --target-org dev-org
```

After metadata exists locally, refresh those existing components with:

```bash
sf project retrieve start \
  --source-dir packages/default/main/default \
  --target-org dev-org
```

These are alternative commands: never combine `--manifest` and `--source-dir`.
Review all changed files after retrieval. Do not add Superbadge metadata here;
move a newly retrieved component to its registered Superbadge package if it
belongs there.

## Validate and deploy

```bash
sf project deploy start \
  --source-dir packages/default/main/default \
  --target-org dev-org \
  --dry-run \
  --test-level RunLocalTests

sf project deploy start \
  --source-dir packages/default/main/default \
  --target-org dev-org
```

To deploy only the manifest selection, replace `--source-dir ...` with:

```text
--manifest packages/default/manifest/package.xml
```

## Test and run scripts

```bash
sf apex run test \
  --target-org dev-org \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 10

sf apex run \
  --file packages/default/scripts/apex/hello.apex \
  --target-org dev-org

sf data query \
  --file packages/default/scripts/soql/account.soql \
  --target-org dev-org
```

Update `manifest/package.xml` when the package starts using additional metadata
types or when wildcard selection is too broad for a controlled deployment.
