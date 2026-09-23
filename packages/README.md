# Package directory guide

Every project in this workspace is self-contained. Use `default/` for general
work and create one directory under `superbadges/` for each Superbadge.

## Available packages

| Package                     | Purpose                        | Documentation                                                              |
| --------------------------- | ------------------------------ | -------------------------------------------------------------------------- |
| `default`                   | General Salesforce development | [default/README.md](default/README.md)                                     |
| `superbadges/apex-callouts` | Apex Callouts Superbadge       | [superbadges/apex-callouts/README.md](superbadges/apex-callouts/README.md) |

## Standard package structure

```text
<package>/
├── main/default/     # Deployable Salesforce metadata
├── manifest/         # Retrieve/deploy manifests
├── scripts/
│   ├── apex/         # Anonymous Apex scripts
│   └── soql/         # SOQL query files
└── README.md          # Purpose and package-specific commands
```

Only `main/default/` is deployable source. The manifest, scripts, notes, sample
payloads, and other support files belong at the package root, outside
`main/default/`.

## Add a package

Create and register a package with the scaffold script. The path is relative to
`packages/` and can contain one folder or nested folders:

```bash
scripts/sf-package-create.sh utilities
scripts/sf-package-create.sh superbadges/<name>
```

The script creates `main/default/`, `manifest/package.xml`, `scripts/apex/`,
`scripts/soql/`, and a package README. It also adds the package to
`packageDirectories` in the root `sfdx-project.json` with `"default": false`.

After creation:

1. Add the required metadata types and members to `manifest/package.xml`.
2. Customize the generated README with package-specific commands or notes.
3. Run `sf project list ignored --json` to catch misplaced or ignored files.

There must be exactly one package with `"default": true`. New Superbadge
packages should not be made the default because newly retrieved components can
otherwise become mixed with general project metadata.

## Package workflow

Run commands from the repository root. The easiest way to retrieve or deploy
a package is `scripts/sf-package.sh` from the repo root:

```bash
scripts/sf-package.sh retrieve <package> <org-alias> [--manifest]
scripts/sf-package.sh deploy   <package> <org-alias> [--manifest] [--dry-run] [--test-level <level>]
```

It automatically uses the manifest for a package's first retrieve (when
`main/default` is empty) and `--source-dir` afterward, and defaults deploy to
the whole package unless `--manifest` is passed. See the root
[README.md](../README.md#quick-path-scriptssf-packagesh) for more examples.
The raw `sf` commands below explain what the script does under the hood, for
cases the script doesn't cover.

For a package that already contains metadata, refresh its existing components
with:

```bash
sf project retrieve start \
  --source-dir packages/<package>/main/default \
  --target-org <org-alias>
```

`--source-dir` cannot discover components when the directory is empty. For the
first retrieve, create a narrow `manifest/package.xml` and run this as a
separate command:

```bash
sf project retrieve start \
  --manifest packages/<package>/manifest/package.xml \
  --target-org <org-alias>
```

Do not combine `--manifest` with `--source-dir`. New components retrieved for a
non-default package can initially land in `packages/default/main/default`.
Move the source file and its matching `*-meta.xml` file to the intended package,
then use `--source-dir` for future retrievals.

Validate and deploy with:

```bash

# Validate without changing the org
sf project deploy start \
  --source-dir packages/<package>/main/default \
  --target-org <org-alias> \
  --dry-run \
  --test-level RunLocalTests

# Deploy the package
sf project deploy start \
  --source-dir packages/<package>/main/default \
  --target-org <org-alias>
```

Replace `<package>` with `default` or `superbadges/<name>`. Review the package
README before using a manifest because its component selection is
package-specific.
