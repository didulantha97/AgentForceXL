#!/usr/bin/env bash
# Build, release and install the PMS managed 2GP packages.
#
#   PMS Core        packages/pms/core        data model, services, apps, internal UI
#   PMS Experience  packages/pms/experience  portals, public booking, Stripe, agent actions
#                                            (depends on PMS Core)
#   org-setup       packages/pms/org-setup   not packageable (Experience sites, guest/portal
#                                            profiles, role, sharing rules, Concierge agent);
#                                            deployed after install by the `org-setup` command
#
# Usage (from the repository root):
#   scripts/pms-package.sh create <namespace>            one-time: link namespace + create both packages
#   scripts/pms-package.sh version [core|experience|all] build a new beta version (runs Apex tests)
#   scripts/pms-package.sh promote [core|experience|all] release the latest beta (needed for production installs)
#   scripts/pms-package.sh links                         print one-click install URLs for the latest versions
#   scripts/pms-package.sh install <org> [--beta] [--with-agent]
#                                                        install Core + Experience, deploy org-setup,
#                                                        assign PMS permission sets to the admin
#   scripts/pms-package.sh org-setup <org> [--with-agent] deploy only the org-setup metadata
#   scripts/pms-package.sh scratch [alias]               dev: scratch org with Core + Experience source
#
# Environment:
#   PMS_DEVHUB   Dev Hub alias that owns the packages (default: ecaViaMetadata)

set -euo pipefail

DEVHUB="${PMS_DEVHUB:-ecaViaMetadata}"
PROJECT_FILE="sfdx-project.json"
CORE="PMS Core"
EXPERIENCE="PMS Experience"
SCRATCH_DEF="packages/pms/config/pms-scratch-def.json"
BUILD_DIR="pms-build"
export SF_DISABLE_AUTOUPDATE=true

die() { echo "error: $*" >&2; exit 1; }
usage() { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

[[ -f "$PROJECT_FILE" ]] || die "run this from the repository root"
command -v sf >/dev/null || die "Salesforce CLI (sf) not found"

json() { node -e "$1" "${@:2}"; }

namespace() {
  json 'console.log(require("./sfdx-project.json").namespace || "")'
}

packages_for() {
  case "${1:-all}" in
    core) echo "$CORE" ;;
    experience) echo "$EXPERIENCE" ;;
    all) printf '%s\n%s\n' "$CORE" "$EXPERIENCE" ;;
    *) die "unknown package '$1' (use core, experience or all)" ;;
  esac
}

# Latest version id (04t...) of a package. $2 = "released" to require a promoted version.
latest_version() {
  local pkg="$1" want="${2:-any}" out
  out=$(sf package version list -v "$DEVHUB" -p "$pkg" --order-by CreatedDate --json 2>/dev/null) ||
    die "could not list versions of $pkg"
  json '
    const want = process.argv[2];
    const rows = (JSON.parse(process.argv[1]).result || [])
      .filter((r) => want !== "released" || r.IsReleased);
    if (!rows.length) process.exit(3);
    console.log(rows[rows.length - 1].SubscriberPackageVersionId);
  ' "$out" "$want" || die "$pkg has no ${want/any/} version yet"
}

install_url() { echo "https://login.salesforce.com/packaging/installPackage.apexp?p0=$1"; }

cmd_create() {
  local ns="${1:-}"
  [[ "$ns" =~ ^[A-Za-z][A-Za-z0-9]{0,14}$ ]] || die "usage: create <namespace> (the prefix registered in your namespace org)"
  json '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync("sfdx-project.json"));
    p.namespace = process.argv[1];
    fs.writeFileSync("sfdx-project.json", JSON.stringify(p, null, 2) + "\n");
  ' "$ns"
  echo "Namespace '$ns' set in $PROJECT_FILE."
  local pkg path
  for pkg in "$CORE" "$EXPERIENCE"; do
    if json 'process.exit((require("./sfdx-project.json").packageAliases || {})[process.argv[1]] ? 0 : 1)' "$pkg"; then
      echo "$pkg already exists in packageAliases; skipping."
      continue
    fi
    path=$([[ "$pkg" == "$CORE" ]] && echo packages/pms/core || echo packages/pms/experience)
    echo "Creating managed package $pkg ($path) in Dev Hub $DEVHUB..."
    sf package create -v "$DEVHUB" -n "$pkg" -t Managed -r "$path" \
      -d "$(json 'console.log(require("./sfdx-project.json").packageDirectories.find(d=>d.package===process.argv[1]).versionDescription)' "$pkg")"
  done
  echo "Done. Commit $PROJECT_FILE: it now holds the package ids (0Ho...)."
}

cmd_version() {
  local pkg out id
  while IFS= read -r pkg; do
    echo "Building a new version of $pkg (runs all Apex tests, can take 15-40 min)..."
    out=$(sf package version create -v "$DEVHUB" -p "$pkg" --installation-key-bypass \
      --code-coverage --wait 120 --json 2>/dev/null) || true
    id=$(json '
      const r = JSON.parse(process.argv[1]);
      if (r.status !== 0 || !r.result || !r.result.SubscriberPackageVersionId) {
        console.error(r.message || JSON.stringify(r.result || r, null, 2));
        process.exit(1);
      }
      console.log(r.result.SubscriberPackageVersionId);
    ' "$out") || die "version create failed for $pkg"
    echo "$pkg: $id"
    echo "  beta install link (sandbox/scratch only): $(install_url "$id" | sed 's/login\./test./')"
  done < <(packages_for "${1:-all}")
  echo "Commit $PROJECT_FILE: it now holds the new version aliases."
}

cmd_promote() {
  local pkg id
  while IFS= read -r pkg; do
    id=$(latest_version "$pkg")
    echo "Promoting $pkg $id to released..."
    sf package version promote -v "$DEVHUB" -p "$id" --no-prompt
  done < <(packages_for "${1:-all}")
}

cmd_links() {
  local pkg id
  for pkg in "$CORE" "$EXPERIENCE"; do
    if id=$(latest_version "$pkg" released 2>/dev/null); then
      echo "$pkg (released): $(install_url "$id")"
    elif id=$(latest_version "$pkg" 2>/dev/null); then
      echo "$pkg (beta, sandboxes only): $(install_url "$id" | sed 's/login\./test./')"
    else
      echo "$pkg: no versions yet (run: scripts/pms-package.sh version)"
    fi
  done
  echo "Install PMS Core first, then PMS Experience. Then run: scripts/pms-package.sh org-setup <org>"
}

cmd_org_setup() {
  local org="${1:-}"; shift || true
  [[ -n "$org" ]] || die "usage: org-setup <org> [--with-agent]"
  local with_agent=false part ns
  [[ "${1:-}" == "--with-agent" ]] && with_agent=true
  ns=$(namespace)
  # Sites and networks need a site admin and email sender in the target org: use the CLI user.
  local user_json
  user_json=$(sf org display user -o "$org" --json 2>/dev/null) || die "cannot read the user of $org"
  export PMS_ADMIN_USERNAME PMS_ADMIN_EMAIL
  PMS_ADMIN_USERNAME=$(json 'console.log(JSON.parse(process.argv[1]).result.username)' "$user_json")
  PMS_ADMIN_EMAIL=$(json 'console.log(JSON.parse(process.argv[1]).result.email || "")' "$user_json")
  local parts=(main)
  $with_agent && parts+=(agent)
  for part in "${parts[@]}"; do
    node packages/pms/scripts/namespace-org-setup.js "$ns" "$part" "$BUILD_DIR/org-setup-$part"
    echo "Deploying org-setup/$part to $org..."
    sf project deploy start -d "$BUILD_DIR/org-setup-$part" -o "$org" -w 60
  done
  echo "Assigning PMS permission sets to the site guest users..."
  mkdir -p "$BUILD_DIR"
  sed "s/__NAMESPACE__/$ns/" packages/pms/scripts/apex/assign-guest-permsets.apex >"$BUILD_DIR/assign-guest-permsets.apex"
  sf apex run -o "$org" -f "$BUILD_DIR/assign-guest-permsets.apex" | grep -E "Compiled|Executed|PMS guest|Error" || true
  echo "Publish the sites once: Setup > Digital Experiences > All Sites > Builder > Publish."
}

cmd_install() {
  local org="${1:-}"; shift || true
  [[ -n "$org" ]] || die "usage: install <org> [--beta] [--with-agent]"
  local want=released agent_flag="" pkg id
  for arg in "$@"; do
    case "$arg" in
      --beta) want=any ;;
      --with-agent) agent_flag="--with-agent" ;;
      *) die "unknown option $arg" ;;
    esac
  done
  for pkg in "$CORE" "$EXPERIENCE"; do
    id=$(latest_version "$pkg" "$want")
    echo "Installing $pkg ($id) into $org..."
    sf package install -o "$org" -p "$id" --security-type AdminsOnly --no-prompt -w 60 -b 30
  done
  cmd_org_setup "$org" $agent_flag
  local ps
  for ps in PMS_App_Access PMS_Core_Admin PMS_Experience_Access; do
    sf org assign permset -o "$org" -n "$ps" >/dev/null 2>&1 &&
      echo "Assigned $ps to the admin user." ||
      echo "Could not assign $ps (already assigned?)."
  done
  echo "PMS is installed in $org."
}

cmd_scratch() {
  local alias="${1:-pms-scratch}"
  sf org create scratch -f "$SCRATCH_DEF" -a "$alias" -v "$DEVHUB" -y 7 -w 30
  sf project deploy start -d packages/pms/core -o "$alias" -w 60
  sf project deploy start -d packages/pms/experience -o "$alias" -w 60
  cmd_org_setup "$alias"
  sf org assign permset -o "$alias" -n PMS_App_Access -n PMS_Core_Admin -n PMS_Experience_Access
  echo "Scratch org $alias is ready: sf org open -o $alias"
}

case "${1:-}" in
  create) shift; cmd_create "$@" ;;
  version) shift; cmd_version "$@" ;;
  promote) shift; cmd_promote "$@" ;;
  links) shift; cmd_links ;;
  install) shift; cmd_install "$@" ;;
  org-setup) shift; cmd_org_setup "$@" ;;
  scratch) shift; cmd_scratch "$@" ;;
  *) usage ;;
esac
