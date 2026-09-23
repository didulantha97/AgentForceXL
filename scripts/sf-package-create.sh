#!/usr/bin/env bash
# Create and register a source package directory in this Salesforce DX project.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/sf-package-create.sh <package-path>

Examples:
  scripts/sf-package-create.sh utilities
  scripts/sf-package-create.sh superbadges/agentforce-specialist

<package-path> is relative to packages/. It may be one folder or multiple
nested folders. Absolute paths, empty path segments, and ".." are not allowed.
EOF
  exit 1
}

[[ $# -eq 1 ]] || usage

PACKAGE_PATH="$1"
PROJECT_FILE="sfdx-project.json"

if [[ ! -f "$PROJECT_FILE" || ! -d packages ]]; then
  echo "Run this script from the repository root (sfdx-project.json was not found)." >&2
  exit 1
fi

if [[ -z "$PACKAGE_PATH" || "$PACKAGE_PATH" == /* || "$PACKAGE_PATH" == */ ||
      "$PACKAGE_PATH" == *//* || "$PACKAGE_PATH" == "." ||
      "$PACKAGE_PATH" == ".." || "$PACKAGE_PATH" == ../* ||
      "$PACKAGE_PATH" == */../* || "$PACKAGE_PATH" == */.. ]]; then
  echo "Invalid package path: $PACKAGE_PATH" >&2
  echo "Use a path relative to packages/, such as 'utilities' or 'superbadges/my-badge'." >&2
  exit 1
fi

if [[ ! "$PACKAGE_PATH" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]]; then
  echo "Invalid package path: $PACKAGE_PATH" >&2
  echo "Folder names may contain letters, numbers, dots, underscores, and hyphens." >&2
  exit 1
fi

PACKAGE_DIR="packages/$PACKAGE_PATH"

if [[ -e "$PACKAGE_DIR" ]]; then
  echo "Package directory already exists: $PACKAGE_DIR" >&2
  exit 1
fi

if node -e '
  const project = require("./sfdx-project.json");
  const packagePath = process.argv[1];
  process.exit((project.packageDirectories || []).some((entry) => entry.path === packagePath) ? 0 : 1);
' "$PACKAGE_DIR"; then
  echo "Package is already registered in $PROJECT_FILE: $PACKAGE_DIR" >&2
  exit 1
fi

API_VERSION="$(node -p 'require("./sfdx-project.json").sourceApiVersion || "67.0"')"

mkdir -p \
  "$PACKAGE_DIR/main/default" \
  "$PACKAGE_DIR/manifest" \
  "$PACKAGE_DIR/scripts/apex" \
  "$PACKAGE_DIR/scripts/soql"

touch \
  "$PACKAGE_DIR/main/default/.gitkeep" \
  "$PACKAGE_DIR/scripts/apex/.gitkeep" \
  "$PACKAGE_DIR/scripts/soql/.gitkeep"

printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<Package xmlns="http://soap.sforce.com/2006/04/metadata">' \
  "    <version>$API_VERSION</version>" \
  '</Package>' \
  > "$PACKAGE_DIR/manifest/package.xml"

printf '%s\n' \
  "# $PACKAGE_PATH" \
  '' \
  "Salesforce metadata and supporting files for \`$PACKAGE_PATH\`." \
  '' \
  '## Contents' \
  '' \
  '- `main/default/` — deployable Salesforce metadata' \
  '- `manifest/package.xml` — metadata selection for retrieve and deploy operations' \
  '- `scripts/apex/` — anonymous Apex scripts' \
  '- `scripts/soql/` — reusable SOQL queries' \
  '' \
  'Add the required metadata types and members to `manifest/package.xml` before the first retrieve.' \
  '' \
  'Run from the repository root:' \
  '' \
  '```bash' \
  "scripts/sf-package.sh retrieve $PACKAGE_PATH <org-alias>" \
  "scripts/sf-package.sh deploy $PACKAGE_PATH <org-alias> --dry-run" \
  "scripts/sf-package.sh deploy $PACKAGE_PATH <org-alias>" \
  '```' \
  > "$PACKAGE_DIR/README.md"

TEMP_PROJECT_FILE="${PROJECT_FILE}.tmp.$$"
trap 'rm -f "$TEMP_PROJECT_FILE"' EXIT

node - "$PACKAGE_DIR" "$PROJECT_FILE" "$TEMP_PROJECT_FILE" <<'NODE'
const fs = require('fs');
const [packagePath, projectFile, outputFile] = process.argv.slice(2);
const project = JSON.parse(fs.readFileSync(projectFile, 'utf8'));

if (!Array.isArray(project.packageDirectories)) {
  project.packageDirectories = [];
}

project.packageDirectories.push({ path: packagePath, default: false });
fs.writeFileSync(outputFile, `${JSON.stringify(project, null, 2)}\n`);
NODE

mv "$TEMP_PROJECT_FILE" "$PROJECT_FILE"
trap - EXIT

echo "Created and registered package: $PACKAGE_DIR"
echo "Next: edit $PACKAGE_DIR/manifest/package.xml, then run:"
echo "  scripts/sf-package.sh retrieve $PACKAGE_PATH <org-alias>"
