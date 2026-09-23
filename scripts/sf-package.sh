#!/usr/bin/env bash
# Retrieve or deploy a single package's metadata against a chosen org, without
# having to remember which sf flags and paths apply to which package.
#
# Usage:
#   scripts/sf-package.sh retrieve <package> <org-alias> [--manifest] [--dry-run]
#   scripts/sf-package.sh deploy   <package> <org-alias> [--manifest] [--dry-run] [--test-level <level>]
#
# <package> is a path relative to packages/, e.g. "default" or
# "superbadges/apex-callouts".
#
# Retrieve mode selection (matches packages/README.md's documented model):
#   - If packages/<package>/main/default is empty (first retrieve for this
#     package) or --manifest is passed, retrieves using
#     packages/<package>/manifest/package.xml.
#   - Otherwise refreshes only the components already in
#     packages/<package>/main/default via --source-dir.
#   A manifest selects WHAT to retrieve, not WHERE it lands: a component that
#   already exists in another package directory returns there, not here. If
#   that happens, `git mv` the file and its *-meta.xml into this package, then
#   future retrieves for it can use --source-dir.
#
# Deploy mode selection:
#   - Defaults to --source-dir packages/<package>/main/default (deploy
#     everything in the package).
#   - --manifest deploys only the components listed in the package manifest.
#   - --dry-run performs a validation-only deploy (adds --test-level
#     RunLocalTests unless --test-level is given explicitly).

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/sf-package.sh retrieve <package> <org-alias> [--manifest] [--dry-run]
  scripts/sf-package.sh deploy   <package> <org-alias> [--manifest] [--dry-run] [--test-level <level>]

Examples:
  scripts/sf-package.sh retrieve superbadges/apex-callouts sb-apex-call-org
  scripts/sf-package.sh retrieve default dev-org --manifest
  scripts/sf-package.sh deploy superbadges/apex-callouts sb-apex-call-org --dry-run
  scripts/sf-package.sh deploy default dev-org --test-level RunSpecifiedTests
EOF
  exit 1
}

[[ $# -ge 3 ]] || usage

ACTION="$1"
PACKAGE="$2"
ORG="$3"
shift 3

FORCE_MANIFEST=false
DRY_RUN=false
TEST_LEVEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      FORCE_MANIFEST=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --test-level)
      TEST_LEVEL="${2:?--test-level requires a value}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

case "$ACTION" in
  retrieve|deploy) ;;
  *) echo "Action must be 'retrieve' or 'deploy', got '$ACTION'" >&2; usage ;;
esac

PACKAGE_DIR="packages/$PACKAGE"
MAIN_DIR="$PACKAGE_DIR/main/default"
MANIFEST="$PACKAGE_DIR/manifest/package.xml"

if [[ ! -d "$PACKAGE_DIR" ]]; then
  echo "Package not found: $PACKAGE_DIR" >&2
  echo "Available packages:" >&2
  find packages -mindepth 1 -maxdepth 3 -type d -name manifest | sed 's#/manifest$##; s#^#  #' >&2
  exit 1
fi

if [[ "$ACTION" == "retrieve" ]]; then
  USE_MANIFEST=false
  if $FORCE_MANIFEST; then
    USE_MANIFEST=true
  elif [[ ! -d "$MAIN_DIR" ]] || [[ -z "$(ls -A "$MAIN_DIR" 2>/dev/null)" ]]; then
    echo "No existing metadata in $MAIN_DIR yet; using manifest for the first retrieve."
    USE_MANIFEST=true
  fi

  if $USE_MANIFEST; then
    [[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }
    echo "Retrieving '$MANIFEST' from '$ORG'..."
    sf project retrieve start --manifest "$MANIFEST" --target-org "$ORG"
    echo
    echo "Note: components that already exist in another package directory are" \
         "refreshed there, not moved here. If something you expected in" \
         "'$PACKAGE_DIR' landed elsewhere, 'git mv' it (and its *-meta.xml)" \
         "into $MAIN_DIR, then use --source-dir on future retrieves."
  else
    echo "Refreshing existing metadata in '$MAIN_DIR' from '$ORG'..."
    sf project retrieve start --source-dir "$MAIN_DIR" --target-org "$ORG"
  fi

elif [[ "$ACTION" == "deploy" ]]; then
  DEPLOY_ARGS=(--target-org "$ORG")

  if $FORCE_MANIFEST; then
    [[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }
    DEPLOY_ARGS+=(--manifest "$MANIFEST")
  else
    DEPLOY_ARGS+=(--source-dir "$MAIN_DIR")
  fi

  if $DRY_RUN; then
    DEPLOY_ARGS+=(--dry-run --test-level "${TEST_LEVEL:-RunLocalTests}")
  elif [[ -n "$TEST_LEVEL" ]]; then
    DEPLOY_ARGS+=(--test-level "$TEST_LEVEL")
  fi

  if $DRY_RUN; then
    echo "Deploying '$PACKAGE_DIR' to '$ORG' (dry run)..."
  else
    echo "Deploying '$PACKAGE_DIR' to '$ORG'..."
  fi
  sf project deploy start "${DEPLOY_ARGS[@]}"
fi
