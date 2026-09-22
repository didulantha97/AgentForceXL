# Apex Callouts Superbadge

This package isolates all metadata and supporting files for the Apex Callouts
Superbadge. Do not place its components in `packages/default`.

## Contents

- `main/default/` — Superbadge metadata
- `manifest/` — package-specific retrieve and deploy manifests
- `scripts/apex/` — setup, verification, or sample anonymous Apex
- `scripts/soql/` — verification queries

The manifest is intentionally limited to `RewardsCalloutService`,
`WellnessJourneyRewardsBatch`, and `WorkshopTrigger`. Add other required
components explicitly instead of using broad `*` members.

Run commands from the repository root. The examples use the authenticated org
alias `sb-apex-call-org`.

## Retrieve

Retrieve the components listed in the package manifest:

```bash
sf project retrieve start \
  --manifest packages/superbadges/apex-callouts/manifest/package.xml \
  --target-org sb-apex-call-org
```

Alternatively, refresh all metadata already stored in this package:

```bash
sf project retrieve start \
  --source-dir packages/superbadges/apex-callouts/main/default \
  --target-org sb-apex-call-org
```

These are separate alternatives. Do not combine `--manifest` and
`--source-dir`. If `--source-dir` prints `Nothing retrieved`, confirm that the
directory contains real Salesforce metadata rather than only `.gitkeep`.

Salesforce CLI places newly discovered metadata in the package marked
`"default": true` in `sfdx-project.json`. If a new Superbadge component is not
represented locally, retrieve it, then move its source file and matching
`*-meta.xml` file from `packages/default/main/default` into this package. Once
the files are here, both commands above preserve their package location.

Use normal option names such as `--manifest`; do not type `\--manifest`. A
backslash belongs only at the end of a line when continuing the same shell
command.

## Validate and deploy

Validate first:

```bash
sf project deploy start \
  --source-dir packages/superbadges/apex-callouts/main/default \
  --target-org sb-apex-call-org \
  --dry-run \
  --test-level RunLocalTests
```

Deploy after validation succeeds:

```bash
sf project deploy start \
  --source-dir packages/superbadges/apex-callouts/main/default \
  --target-org sb-apex-call-org
```

To deploy only components named in the package manifest, use
`--manifest packages/superbadges/apex-callouts/manifest/package.xml` instead of
`--source-dir`.

## Test and run scripts

```bash
sf apex run test \
  --target-org sb-apex-call-org \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 10

sf apex run \
  --file packages/superbadges/apex-callouts/scripts/apex/<script>.apex \
  --target-org sb-apex-call-org

sf data query \
  --file packages/superbadges/apex-callouts/scripts/soql/<query>.soql \
  --target-org sb-apex-call-org
```

Replace the placeholder script and query names with real files. Keep challenge
notes or sample payloads in this package, but never commit org credentials,
session IDs, access tokens, or secrets used by callout authentication.
