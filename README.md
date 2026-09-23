# AgentForceXL Salesforce DX workspace

This repository is a Salesforce DX workspace for general development and
Superbadge projects. Each project is isolated in its own package directory so
its metadata, manifests, scripts, and documentation stay together.

## Repository layout

```text
.
├── config/                         # Scratch-org definition
├── packages/
│   ├── default/                    # General development (default package)
│   └── superbadges/
│       └── apex-callouts/          # Apex Callouts Superbadge
└── sfdx-project.json               # Salesforce DX project configuration
```

See [packages/README.md](packages/README.md) for the package convention and
links to package-specific instructions.

## Prerequisites

- Salesforce CLI (`sf`)
- A Salesforce org or a Dev Hub with permission to create scratch orgs
- Node.js and npm for formatting, linting, and LWC tests
- VS Code with the Salesforce Extension Pack (recommended)

Verify the tools:

```bash
sf version
node --version
npm --version
```

## Initial setup

Run commands from the repository root.

```bash
npm install
sf org login web --alias dev-org --set-default
sf org list
```

Use a meaningful alias in place of `dev-org`. Commands in this guide always
include `--target-org` so it is clear which org is affected.

### Optional: create a scratch org

First authenticate a Dev Hub, then create the scratch org:

```bash
sf org login web --alias dev-hub --set-default-dev-hub
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias agentforcexl-scratch \
  --duration-days 30 \
  --set-default
```

Open an authenticated org with:

```bash
sf org open --target-org dev-org
```

## Work with a package

Choose one package and use its paths consistently. The examples below use the
general package; each package README contains ready-to-run commands for that
package.

Create a new top-level or nested package directory with:

```bash
scripts/sf-package-create.sh utilities
scripts/sf-package-create.sh superbadges/my-superbadge
```

The script creates the standard package folders and starter files and registers
the new non-default package in `sfdx-project.json`.

### Quick path: `scripts/sf-package.sh`

For day-to-day retrieve/deploy against a specific package and org, use the
wrapper script instead of typing out `sf project retrieve/deploy start` by
hand. It picks the right flags for you:

```bash
# Retrieve: uses the manifest on the first retrieve (empty package), then
# --source-dir automatically once the package has metadata locally.
scripts/sf-package.sh retrieve superbadges/apex-callouts sb-apex-call-org
scripts/sf-package.sh retrieve default dev-org

# Force a manifest-based retrieve (e.g. to pull a newly added component)
scripts/sf-package.sh retrieve superbadges/apex-callouts sb-apex-call-org --manifest

# Deploy the whole package (default), or only the manifest's components
scripts/sf-package.sh deploy superbadges/apex-callouts sb-apex-call-org
scripts/sf-package.sh deploy default dev-org --manifest

# Validate only, without saving to the org
scripts/sf-package.sh deploy superbadges/apex-callouts sb-apex-call-org --dry-run
scripts/sf-package.sh deploy default dev-org --dry-run --test-level RunSpecifiedTests
```

Run `scripts/sf-package.sh` with no arguments to see usage and the list of
available packages. The same "manifest selects components, not their
destination" rule below still applies — see the raw `sf` commands if you need
more control than the script exposes.

### Retrieve metadata

There are two separate retrieve modes. Do not put `--manifest` and
`--source-dir` in the same command.

Use the package manifest for the initial retrieve or to retrieve a defined set
of components:

```bash
sf project retrieve start \
  --manifest packages/default/manifest/package.xml \
  --target-org dev-org
```

After components exist locally, use the source directory to refresh only those
components:

```bash
sf project retrieve start \
  --source-dir packages/default/main/default \
  --target-org dev-org
```

Important: a manifest selects components, not their destination package.
Existing components normally return to their registered location; a new
component is written to `packages/default`, because it is the default package.
For the first retrieve of a non-default package, use its manifest, inspect the
result, and move each complete component—including its `*-meta.xml` file—from
`packages/default/main/default` into that package. All later retrieves can use
the non-default package's `--source-dir`.

Shell syntax matters: place one unescaped `--option` on each line, put `\` only
at the end of a continued line, and never paste two `sf` commands together.
Avoid `--ignore-conflicts` unless overwriting local changes is intentional.

### Deploy metadata

Deploy everything in one package:

```bash
sf project deploy start \
  --source-dir packages/default/main/default \
  --target-org dev-org
```

Deploy only the components listed in its manifest:

```bash
sf project deploy start \
  --manifest packages/default/manifest/package.xml \
  --target-org dev-org
```

Validate a deployment without saving changes to the org:

```bash
sf project deploy start \
  --source-dir packages/default/main/default \
  --target-org dev-org \
  --dry-run \
  --test-level RunLocalTests
```

### Run Apex tests

```bash
sf apex run test \
  --target-org dev-org \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 10
```

Run one test class with `--tests AccountServiceTest` and
`--test-level RunSpecifiedTests`.

### Run package scripts

```bash
sf apex run \
  --file packages/default/scripts/apex/hello.apex \
  --target-org dev-org

sf data query \
  --file packages/default/scripts/soql/account.soql \
  --target-org dev-org
```

## Quality checks

```bash
npm run prettier:verify
npm run lint
npm run test:unit
```

`npm run lint` and `npm run test:unit` are most relevant when the repository
contains Aura or Lightning Web Components. Apex tests run in a Salesforce org,
not through npm.

## Development rules

- Put metadata only in a registered package's `main/default/` directory.
- Keep each package's manifests and scripts inside that package.
- Include the matching `*-meta.xml` file with Apex classes, triggers, and other
  metadata that requires one.
- Never store credentials, access tokens, `.sf/`, `.sfdx/`, or `node_modules/`
  in source control.
- Retrieve before starting work when the org might contain newer changes.
- Validate and run relevant tests before deploying to a shared or production
  org.
- Review the target org alias before every retrieve or deploy.

## Troubleshooting

Check authentication and defaults:

```bash
sf org list
sf config list
```

If the CLI reports a source conflict, compare the local and org versions before
choosing which one should win. If metadata appears in the wrong package after a
retrieve, move the complete component and its metadata file into the intended
package, then verify that only one copy exists.

Local Salesforce cache directories can be rebuilt and are intentionally
ignored. Do not treat `.sf/` or `.sfdx/` as project source.

## References

- [Salesforce CLI command reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Salesforce DX project configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm)
- [Salesforce VS Code extensions](https://developer.salesforce.com/tools/vscode/)
