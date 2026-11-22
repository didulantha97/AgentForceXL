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
#   scripts/pms-package.sh access <org> [--user <username>] [--role admin|staff]
#                                                        give a user the PMS permission sets: admin (default) = every admin set,
#                                                        staff = the PMS_Standard_User permission set group. Default user = the CLI user.
#                                                        Safe to re-run; works for packaged (namespaced) and source-deployed orgs.
#   scripts/pms-package.sh scratch [alias]               dev: scratch org with Core + Experience source
#
# Free / trial orgs (Dev Hubs expire, so everything must be redeployable fast):
#   scripts/pms-package.sh devhub <alias>                log in to a (new trial) Dev Hub, make it this project's default, verify it
#   scripts/pms-package.sh bootstrap <alias> [--scratch [--days N]] [--source | --version-core 04t.. --version-exp 04t..]
#                                            [--no-sample] [--tests] [--with-agent] [--i-know-this-org]
#                                                        full PMS into any org: deploy (or install), org-setup, permission sets,
#                                                        config import, demo data (baseline pack), smoke check. Safe to re-run.
#   scripts/pms-package.sh demo-data <alias> [--pack X] [--reset] [--status] [--i-know-this-org]
#                                                        load demo data (default pack: baseline), remove it again (--reset, pack or 'all'),
#                                                        or show what is loaded (--status). Packs: baseline, busy-weekend, overdue-wave,
#                                                        month-end, channel-incident, new-client. Never runs in production; needs an admin.
#   scripts/pms-package.sh config-export <alias>         save PMS configuration records to packages/pms/config-data/ (no secrets)
#   scripts/pms-package.sh config-import <alias> [--i-know-this-org]   load them into an org (objects that already have records are skipped)
#
# Environment:
#   PMS_DEVHUB   Dev Hub alias used for packages and scratch orgs
#                (default: this project's target-dev-hub, else ecaViaMetadata)
#   PMS_ORG_NS   Force the namespace the target org uses ('' for none); normally auto-detected

set -euo pipefail

DEVHUB="${PMS_DEVHUB:-}"
PROJECT_FILE="sfdx-project.json"
CORE="PMS Core"
EXPERIENCE="PMS Experience"
SCRATCH_DEF="packages/pms/config/pms-scratch-def.json"
BUILD_DIR="pms-build"
export SF_DISABLE_AUTOUPDATE=true

die() { echo "error: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 1; }

[[ -f "$PROJECT_FILE" ]] || die "run this from the repository root"
command -v sf >/dev/null || die "Salesforce CLI (sf) not found"

json() { node -e "$1" "${@:2}"; }

# Dev Hubs rotate (free trials expire): follow the project-local target-dev-hub unless PMS_DEVHUB is set.
if [[ -z "$DEVHUB" ]]; then
  DEVHUB=$(sf config get target-dev-hub --json 2>/dev/null |
    node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{console.log((JSON.parse(d).result||[])[0].value||"")}catch(e){}})' 2>/dev/null || true)
  DEVHUB="${DEVHUB:-ecaViaMetadata}"
fi

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
  licence_guard
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
  licence_guard
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

# Namespace the target org uses for PMS components. Source deploys into a plain org have none;
# scratch orgs and package installs use the project namespace. Callers may export PMS_ORG_NS.
org_ns() { echo "${PMS_ORG_NS-$(namespace)}"; }

# Detect the namespace actually in use by probing for a PMS object. Prints it ('' for none).
detect_org_ns() {
  local org="$1" ns
  if [[ -n "${PMS_ORG_NS+x}" ]]; then echo "$PMS_ORG_NS"; return 0; fi
  if sf sobject describe -s PMS_Site__c -o "$org" --json >/dev/null 2>&1; then echo ""; return 0; fi
  ns=$(namespace)
  if [[ -n "$ns" ]] && sf sobject describe -s "${ns}__PMS_Site__c" -o "$org" --json >/dev/null 2>&1; then
    echo "$ns"; return 0
  fi
  return 1
}

# Prints the target org's current sharing defaults of the two org-setup objects as JSON keyed by the
# un-namespaced API name. Prints nothing and returns 1 when they cannot be read.
owd_json() {
  local org="$1" ns="$2" pre="" out
  [[ -n "$ns" ]] && pre="${ns}__"
  out=$(sf data query -o "$org" --json -q "SELECT QualifiedApiName, InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('${pre}PMS_Booking__c','${pre}PMS_Invoice__c')" 2>/dev/null) || return 1
  json '
    const pre = process.argv[2], m = {};
    for (const r of JSON.parse(process.argv[1]).result.records) {
      if (r.InternalSharingModel && r.ExternalSharingModel) m[r.QualifiedApiName.slice(pre.length)] = { internal: r.InternalSharingModel, external: r.ExternalSharingModel };
    }
    if (Object.keys(m).length) console.log(JSON.stringify(m)); else process.exit(1);
  ' "$out" "$pre"
}

# Deploys org-setup. Returns 0 ok, 1 setup error, 2 an unreplaced __PMS_ token is in the payload,
# 3 the deploy itself failed (log in $BUILD_DIR/org-setup-<part>.log).
org_setup_run() {
  local org="$1" with_agent="${2:-false}" part ns user_json dir
  ns=$(org_ns)
  # Sites and networks need a site admin and email sender in the target org: use the CLI user.
  user_json=$(sf org display user -o "$org" --json 2>/dev/null) || { echo "cannot read the user of $org" >&2; return 1; }
  export PMS_ADMIN_USERNAME PMS_ADMIN_EMAIL
  PMS_ADMIN_USERNAME=$(json 'console.log(JSON.parse(process.argv[1]).result.username)' "$user_json") || return 1
  PMS_ADMIN_EMAIL=$(json 'console.log(JSON.parse(process.argv[1]).result.email || "")' "$user_json") || return 1
  local parts=(main)
  [[ "$with_agent" == true ]] && parts+=(agent)
  mkdir -p "$BUILD_DIR"
  for part in "${parts[@]}"; do
    dir="$BUILD_DIR/org-setup-$part"
    # Keep the org's current sharing defaults (the Access Console may have made them Private).
    PMS_OWD_JSON=""
    if [[ "$part" == main ]]; then
      PMS_OWD_JSON=$(owd_json "$org" "$ns") || echo "warning: cannot read current sharing defaults of $org; skipping the Booking/Invoice object definitions so the defaults are not reset" >&2
    fi
    export PMS_OWD_JSON
    node packages/pms/scripts/namespace-org-setup.js "$ns" "$part" "$dir" || return 1
    if grep -rEl '__PMS_[A-Z_]+__' "$dir" >&2; then
      echo "error: unreplaced __PMS_*__ token(s) in the files above; refusing to deploy org-setup/$part" >&2
      return 2
    fi
    echo "Deploying org-setup/$part to $org..."
    sf project deploy start -d "$dir" -o "$org" -w 60 2>&1 | tee "$BUILD_DIR/org-setup-$part.log" || return 3
  done
  echo "Assigning PMS permission sets to the site guest users..."
  sed "s/__NAMESPACE__/$ns/" packages/pms/scripts/apex/assign-guest-permsets.apex >"$BUILD_DIR/assign-guest-permsets.apex"
  sf apex run -o "$org" -f "$BUILD_DIR/assign-guest-permsets.apex" | grep -E "Compiled|Executed|PMS guest|Error" || true
  echo "Publish the sites once: Setup > Digital Experiences > All Sites > Builder > Publish."
}

cmd_org_setup() {
  local org="${1:-}"; shift || true
  [[ -n "$org" ]] || die "usage: org-setup <org> [--with-agent]"
  local with_agent=false rc=0
  [[ "${1:-}" == "--with-agent" ]] && with_agent=true
  org_setup_run "$org" "$with_agent" || rc=$?
  case "$rc" in
    0) ;;
    2) die "org-setup payload still contains __PMS_ tokens" ;;
    3) die "org-setup deploy failed$(licence_hint "$BUILD_DIR/org-setup-main.log")" ;;
    *) die "org-setup failed" ;;
  esac
}

# Trial and Developer Edition orgs differ in Experience Cloud / community licences and features.
licence_hint() {
  [[ -f "$1" ]] || return 0
  if grep -Eiq 'licen[sc]e|Digital Experience|Communit|Experience Cloud|Network|enableNetworks|not available|feature' "$1"; then
    echo " (looks like this org lacks Experience Cloud / community licences or features: sites, networks and portal profiles cannot deploy here; Core and Experience still work)"
  fi
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
  # The package post-install scripts already give the installer their sets; this covers the rest (idempotent).
  cmd_access "$org" --role admin || echo "warning: some permission sets could not be assigned (see above)" >&2
  echo "PMS is installed in $org."
}

cmd_scratch() {
  local alias="${1:-pms-scratch}"
  sf org create scratch -f "$SCRATCH_DEF" -a "$alias" -v "$DEVHUB" -y 7 -w 30
  sf project deploy start -d packages/pms/core -o "$alias" -w 60
  sf project deploy start -d packages/pms/experience -o "$alias" -w 60
  cmd_org_setup "$alias"
  cmd_access "$alias" --role admin || echo "warning: some permission sets could not be assigned (see above)" >&2
  echo "Scratch org $alias is ready: sf org open -o $alias"
}

# ---------------------------------------------------------------------------------------------
# Free / trial org workflow: devhub, bootstrap, config-export, config-import
# ---------------------------------------------------------------------------------------------

CONFIG_DATA_DIR="packages/pms/config-data"
CONFIG_TOOL="packages/pms/scripts/config-data.js"
DEMO_APEX="packages/pms/scripts/apex/demo-data.apex"
# Admin = every set an administrator needs (kept in step with ADMIN_SETS in packages/pms/scripts/access-audit.js
# and the install handlers). Not listed on purpose: portal / guest-site sets, and the Hide_* sets the access engine hands out.
PMS_PERMSETS=(
  PMS_Core_Admin PMS_App_Access PMS_Access_Manager PMS_Channex PMS_Dynamic_Pricing PMS_Rent_Review
  PMS_Experience_Access PMS_Payment_Integration PMS_Payment_Gateway PMS_Stripe_Access PMS_Dunning PMS_Guarantees PMS_Customer_Portal_Management PMS_Partner_Management
)
PMS_STAFF_GROUP=PMS_Standard_User
ACCESS_ADDED=0; ACCESS_HAD=0; ACCESS_SKIPPED=""

org_authed() { sf org display -o "$1" --json >/dev/null 2>&1; }

# Runs the demo data template once (action: load | reset | status) and prints its PMS_DEMO| lines without the prefix.
# The class is reached through the global PMS_DemoDataApi (a System.Callable), so this also works in installed-package orgs.
# usage: demo_apex <alias> <ns> <action> <pack>      (pack is validated by the caller: [a-z-]+)
demo_apex() {
  local alias="$1" ns="$2" action="$3" pack="$4" log="$BUILD_DIR/demo-data.log"
  mkdir -p "$BUILD_DIR"
  sed -e "s/@@NS@@/$ns/" -e "s/@@ACTION@@/$action/" -e "s/@@PACK@@/$pack/" "$DEMO_APEX" >"$BUILD_DIR/demo-data.apex" || return 1
  if ! sf apex run -o "$alias" -f "$BUILD_DIR/demo-data.apex" >"$log" 2>&1; then
    echo "error: the demo data script failed (see $log)" >&2
    grep -E 'Error|error' "$log" | head -5 >&2 || true
    return 1
  fi
  sed -e 's/&#124;/|/g' "$log" | sed -n 's/^.*|DEBUG|PMS_DEMO|//p'
}

# Opts a Developer Edition / trial org in to demo data (PMS_Settings__c.Demo_Data_Allowed__c on the org-default record).
# Only call this for an org that has passed org_guard. Prints a warning and returns 1 if it could not be set.
demo_optin() {
  local alias="$1" ns="$2" out
  out=$(demo_apex "$alias" "$ns" allow all) || { echo "warning: could not switch demo data on for $alias" >&2; return 1; }
  grep -q '^message|Demo data allowed' <<<"$out" || { echo "warning: demo data was not switched on for $alias: $(sed -n 's/^error|//p;s/^message|//p' <<<"$out" | head -1)" >&2; return 1; }
}

# Waits until no demo data job is running (loads and resets run in the background, one step per job).
# usage: demo_wait <alias> <ns> [max-seconds]       returns 0 when idle, 1 on timeout or error
demo_wait() {
  local alias="$1" ns="$2" max="${3:-900}" waited=0 out
  while ((waited < max)); do
    sleep 10; waited=$((waited + 10))
    out=$(demo_apex "$alias" "$ns" status all) || return 1
    if grep -q '^status|allowed=true|busy=false' <<<"$out"; then return 0; fi
    printf '.' >&2
  done
  echo >&2
  return 1
}

# Prints what is loaded: one line per pack.
demo_print_status() {
  local out="$1"
  printf '%s\n' "$out" | awk -F'|' '
    $1 == "status" { print "Demo data status: " $2 ", " $3 ", " $4 ($5 != "" ? " (" $5 ")" : ""); next }
    $1 == "pack"   { printf "  %-18s %-10s %6s records  %s\n", $2, $3, $4, $5 }
    $1 == "error"  { print "error: " $2 }'
}

# Safety net for anything that deploys or writes data: only scratch orgs, trials and Developer Edition orgs.
# Production-like orgs and the protected alias are always refused; other orgs (sandboxes) need --i-know-this-org.
# usage: org_guard <alias> <override: true|false>
org_guard() {
  local alias="$1" override="${2:-false}" out verdict
  if [[ "$alias" == "agentforce-org-nov" ]]; then
    die "refusing: '$alias' is protected and can never be bootstrapped or loaded with PMS config/sample data"
  fi
  out=$(sf data query -o "$alias" --json -q "SELECT IsSandbox, OrganizationType, TrialExpirationDate FROM Organization" 2>/dev/null) ||
    die "cannot read Organization of '$alias': refusing to touch an org I cannot classify"
  verdict=$(json '
    try {
      const r = JSON.parse(process.argv[1]).result.records[0];
      const trial = r.TrialExpirationDate != null;
      const de = r.OrganizationType === "Developer Edition";
      if (trial || de) console.log("ok");
      else if (r.IsSandbox === false) console.log("deny:production-like org (" + r.OrganizationType + ")");
      else console.log("confirm:sandbox (" + r.OrganizationType + ")");
    } catch (e) { console.log("deny:unreadable Organization record"); }
  ' "$out") || verdict="deny:unreadable Organization record"
  case "$verdict" in
    ok) return 0 ;;
    deny:*) die "refusing '$alias': ${verdict#deny:}. This can never be overridden." ;;
    confirm:*)
      [[ "$override" == true ]] && return 0
      die "refusing '$alias': ${verdict#confirm:} is not a scratch org, trial or Developer Edition org. Re-run with --i-know-this-org to proceed." ;;
  esac
}

# Licence placeholder guard: never build a package version with the unconfigured licence key.
licence_guard() {
  local f="packages/pms/core/main/default/customMetadata/PMS_Licensing.Default.md-meta.xml"
  if grep -q 'REPLACE_' "$f"; then
    die "$f still contains REPLACE_ placeholders. Generate the production keypair and paste the public key and key id as described in packages/pms/docs/Licensing.md, then retry."
  fi
  if [[ -n "${PMS_LICENCE_PRIVATE_KEY:-}" ]]; then
    # Sign a test payload with the owner's private key and verify it with the public key that ships in the package.
    node -e '
      const crypto = require("crypto"), fs = require("fs");
      const xml = fs.readFileSync(process.argv[1], "utf8");
      const m = xml.match(/<field>Public_Key__c<\/field>\s*<value[^>]*>([^<]*)<\/value>/);
      if (!m) { console.error("Public_Key__c not found in " + process.argv[1]); process.exit(2); }
      try {
        const pub = crypto.createPublicKey({ key: Buffer.from(m[1].replace(/\s+/g, ""), "base64"), format: "der", type: "spki" });
        const priv = crypto.createPrivateKey(fs.readFileSync(process.argv[2]));
        const msg = Buffer.from("pms-licence-guard-" + Date.now(), "ascii");
        const ok = crypto.verify("sha256", msg, pub, crypto.sign("sha256", msg, priv));
        process.exit(ok ? 0 : 1);
      } catch (e) { console.error(e.message); process.exit(3); }
    ' "$f" "$PMS_LICENCE_PRIVATE_KEY" ||
      die "PMS_LICENCE_PRIVATE_KEY does not match Public_Key__c in $f (or a key could not be read). Packaging with this public key would make every issued licence key invalid."
    echo "Licence guard: PMS_LICENCE_PRIVATE_KEY matches the packaged public key."
  else
    echo "warning: PMS_LICENCE_PRIVATE_KEY is not set, so the packaged public key was NOT checked against your private key. Export it and re-run to be sure." >&2
  fi
}

# Query helper: prints one JSON array of records for a SOQL query (empty array on error).
soql_records() {
  local out
  out=$(sf data query -o "$1" --json -q "$2" 2>/dev/null) || { echo "[]"; return 1; }
  json 'console.log(JSON.stringify(JSON.parse(process.argv[1]).result.records))' "$out"
}

# Assigns the PMS permission sets (role admin) or the Standard User group (role staff) to a user. Idempotent.
# Sets that do not exist in the org (for example Experience not deployed) are skipped and listed, not failures.
# Sets ACCESS_ADDED / ACCESS_HAD / ACCESS_SKIPPED. Returns 1 if the user is missing or an assignment failed.
# usage: access_assign <org> <username> <admin|staff>
access_assign() {
  local org="$1" username="$2" role="$3" ns nsq uid recs have names items item id n rc=0
  ACCESS_ADDED=0; ACCESS_HAD=0; ACCESS_SKIPPED=""
  [[ "$username" =~ ^[A-Za-z0-9._%+@-]+$ ]] || { echo "error: odd characters in username '$username'" >&2; return 1; }
  ns=$(detect_org_ns "$org") || ns=$(org_ns)
  nsq="NamespacePrefix = null"; [[ -n "$ns" ]] && nsq="NamespacePrefix = '$ns'"
  recs=$(soql_records "$org" "SELECT Id, IsActive FROM User WHERE Username = '$username'") || return 1
  uid=$(json 'const r = JSON.parse(process.argv[1]); if (!r.length || !r[0].IsActive) process.exit(1); console.log(r[0].Id)' "$recs") ||
    { echo "error: no active user '$username' in $org" >&2; return 1; }
  have=$(soql_records "$org" "SELECT PermissionSetId, PermissionSetGroupId FROM PermissionSetAssignment WHERE AssigneeId = '$uid'") || return 1
  if [[ "$role" == staff ]]; then
    recs=$(soql_records "$org" "SELECT Id, DeveloperName, Status FROM PermissionSetGroup WHERE DeveloperName = '$PMS_STAFF_GROUP' AND $nsq") || return 1
    items=$(json 'console.log(JSON.parse(process.argv[1]).map((g) => g.Id + ":" + g.DeveloperName + ":" + g.Status).join(" "))' "$recs")
    if [[ -z "$items" ]]; then
      echo "error: permission set group $PMS_STAFF_GROUP not found in $org (deploy or install PMS Experience first)" >&2
      return 1
    fi
    for item in $items; do
      id=${item%%:*}
      if json 'process.exit(JSON.parse(process.argv[1]).some((a) => a.PermissionSetGroupId === process.argv[2]) ? 0 : 1)' "$have" "$id"; then
        ACCESS_HAD=$((ACCESS_HAD + 1))
      elif sf data create record -o "$org" -s PermissionSetAssignment -v "AssigneeId=$uid PermissionSetGroupId=$id" >/dev/null 2>&1; then
        ACCESS_ADDED=$((ACCESS_ADDED + 1))
        if [[ "$item" == *:Failed ]]; then echo "warning: group $PMS_STAFF_GROUP is in status Failed; re-deploy it" >&2; fi
      else
        echo "error: could not assign group $PMS_STAFF_GROUP" >&2; rc=1
      fi
    done
    return $rc
  fi
  names=$(printf "'%s'," "${PMS_PERMSETS[@]}"); names=${names%,}
  recs=$(soql_records "$org" "SELECT Id, Name FROM PermissionSet WHERE Name IN ($names) AND $nsq") || return 1
  for n in "${PMS_PERMSETS[@]}"; do
    id=$(json 'const r = JSON.parse(process.argv[1]).find((p) => p.Name === process.argv[2]); console.log(r ? r.Id : "")' "$recs" "$n")
    if [[ -z "$id" ]]; then
      ACCESS_SKIPPED+="${ACCESS_SKIPPED:+ }$n"
    elif json 'process.exit(JSON.parse(process.argv[1]).some((a) => a.PermissionSetId === process.argv[2]) ? 0 : 1)' "$have" "$id"; then
      ACCESS_HAD=$((ACCESS_HAD + 1))
    elif sf data create record -o "$org" -s PermissionSetAssignment -v "AssigneeId=$uid PermissionSetId=$id" >/dev/null 2>&1; then
      ACCESS_ADDED=$((ACCESS_ADDED + 1))
    else
      echo "error: could not assign $n" >&2; rc=1
    fi
  done
  return $rc
}

cmd_access() {
  local org="${1:-}"; shift || true
  [[ -n "$org" && "$org" != --* ]] || die "usage: access <org> [--user <username>] [--role admin|staff]"
  local user="" role=admin
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) shift; user="${1:-}"; [[ -n "$user" ]] || die "--user needs a username" ;;
      --role) shift; role="${1:-}"; [[ "$role" == admin || "$role" == staff ]] || die "--role must be admin or staff" ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  [[ "$org" != "agentforce-org-nov" ]] || die "refusing: '$org' is protected"
  org_authed "$org" || die "org '$org' is not authenticated (sf org login web -a $org)"
  if [[ -z "$user" ]]; then
    user=$(sf org display user -o "$org" --json 2>/dev/null) || die "cannot read the CLI user of $org"
    user=$(json 'console.log(JSON.parse(process.argv[1]).result.username)' "$user") || die "cannot read the CLI user of $org"
  fi
  local rc=0
  access_assign "$org" "$user" "$role" || rc=$?
  echo "PMS access ($role) for $user in $org: added $ACCESS_ADDED, already had $ACCESS_HAD${ACCESS_SKIPPED:+; not in this org (skipped): $ACCESS_SKIPPED}."
  if [[ "$role" == staff ]]; then
    echo "Staff = permission set group $PMS_STAFF_GROUP (read-only policies/config/logs, no delete on financial records)."
  fi
  return $rc
}

cmd_devhub() {
  local alias="${1:-}"
  [[ -n "$alias" ]] || die "usage: devhub <alias>"
  sf org login web --alias "$alias" --set-default-dev-hub || die "login failed"
  # Project-local (no --global): lands in .sf/config.json, which is git-ignored.
  sf config set target-dev-hub="$alias" >/dev/null || die "could not set target-dev-hub"
  echo "Default Dev Hub for this project: $alias (.sf/config.json)"

  if sf data query -q "SELECT Id FROM ScratchOrgInfo LIMIT 1" -o "$alias" --json >/dev/null 2>&1; then
    echo "Dev Hub check: OK ($alias can create scratch orgs and packages)."
  else
    cat >&2 <<EOF

Dev Hub check FAILED: $alias is not a Dev Hub (ScratchOrgInfo is not queryable).
To enable it:
  1. Open the org: sf org open -o $alias
  2. Setup > quick find "Dev Hub" > Dev Hub.
  3. Switch "Enable Dev Hub" on (it cannot be switched off again), wait a minute, then re-run:
       scripts/pms-package.sh devhub $alias
If you publish managed packages under a namespace (project namespace: '$(namespace)'):
  4. In this Dev Hub: App Launcher > Namespace Registries > Link Namespace, and sign in to the
     namespace org. Packages belong to the Dev Hub that created them, so a new Dev Hub must run
     'create' again (and build new versions) before 'install' by version works.
EOF
    exit 1
  fi

  local out exp
  out=$(sf data query -o "$alias" --json -q "SELECT TrialExpirationDate, OrganizationType, IsSandbox FROM Organization" 2>/dev/null) || out=""
  exp=$(json '
    try {
      const r = JSON.parse(process.argv[1]).result.records[0];
      console.log(r.TrialExpirationDate ? "expires " + r.TrialExpirationDate : "no trial expiry (" + r.OrganizationType + ")");
    } catch (e) { console.log("unknown"); }
  ' "$out") || exp="unknown"
  echo "Org expiry: $exp"
  echo "Next: scripts/pms-package.sh bootstrap <alias> --scratch   (or an existing org)"
}

# --- bootstrap helpers -----------------------------------------------------------------------
BS_NAMES=(); BS_STATUS=(); BS_DETAIL=(); BS_RC=0; BS_NOTE=""

bs_step() { # name status [detail]
  BS_NAMES+=("$1"); BS_STATUS+=("$2"); BS_DETAIL+=("${3:-}")
  [[ "$2" == FAIL ]] && BS_RC=1
  return 0
}

bs_summary() {
  local i
  echo
  echo "PMS bootstrap summary"
  printf '%-14s %-6s %s\n' STEP RESULT DETAIL
  printf '%-14s %-6s %s\n' -------------- ------ ------
  for ((i = 0; i < ${#BS_NAMES[@]}; i++)); do
    printf '%-14s %-6s %s\n' "${BS_NAMES[$i]}" "${BS_STATUS[$i]}" "${BS_DETAIL[$i]}"
  done
}

package_installed() { # org 04t...
  local out
  out=$(sf package installed list -o "$1" --json 2>/dev/null) || return 1
  json 'process.exit((JSON.parse(process.argv[1]).result || []).some((p) => (p.SubscriberPackageVersion || p).Id === process.argv[2] || p.SubscriberPackageVersionId === process.argv[2]) ? 0 : 1)' "$out" "$2"
}

# The bs_* steps run inside `if`, where `set -e` does not apply: they return explicit statuses.
bs_assign_permsets() {
  local org="$1" user
  user=$(sf org display user -o "$org" --json 2>/dev/null) || return 1
  user=$(json 'console.log(JSON.parse(process.argv[1]).result.username)' "$user") || return 1
  access_assign "$org" "$user" admin || return 1
  BS_NOTE="assigned $ACCESS_ADDED, already had $ACCESS_HAD${ACCESS_SKIPPED:+, not in org: $ACCESS_SKIPPED}"
}

bs_run_tests() {
  local org="$1" ns="$2" f n args=()
  for f in packages/pms/core/main/default/classes/*.cls packages/pms/experience/main/default/classes/*.cls; do
    grep -qi '@isTest' "$f" || continue
    n=$(basename "$f" .cls)
    args+=(-n "${ns:+$ns.}$n")
  done
  [[ ${#args[@]} -gt 0 ]] || return 1
  local out="$BUILD_DIR/apex-tests.log"
  mkdir -p "$BUILD_DIR"
  # --synchronous is not allowed for many classes; retry once to absorb UNABLE_TO_LOCK_ROW flakes.
  if sf apex run test -o "$org" --test-level RunSpecifiedTests "${args[@]}" --code-coverage -r human -w 60 >"$out" 2>&1; then
    BS_TEST_NOTE="$(grep -E 'Pass Rate|Org Wide Coverage' "$out" | tr -s ' ' | paste -sd ';' -)"
    return 0
  fi
  if grep -q 'UNABLE_TO_LOCK_ROW' "$out"; then
    echo "Retrying tests once (UNABLE_TO_LOCK_ROW)..."
    if sf apex run test -o "$org" --test-level RunSpecifiedTests "${args[@]}" --code-coverage -r human -w 60 >"$out" 2>&1; then
      BS_TEST_NOTE="$(grep -E 'Pass Rate|Org Wide Coverage' "$out" | tr -s ' ' | paste -sd ';' -) (after retry)"
      return 0
    fi
  fi
  BS_TEST_NOTE="$(grep -E 'Fail Rate|Tests Ran|Fail ' "$out" | head -3 | tr -s ' ' | paste -sd ';' -) - full log: $out"
  return 1
}

bs_smoke() {
  local org="$1" ns="$2" pre obj q out n detail=""
  pre="${ns:+${ns}__}"
  for obj in PMS_Site__c PMS_Space__c PMS_Rate_Plan__c PMS_Booking__c PMS_Payment_Policy__c PMS_Module__mdt PMS_Settings__c; do
    out=$(sf data query -o "$org" --json -q "SELECT COUNT() FROM ${pre}${obj}" 2>/dev/null) || { echo "smoke: cannot query ${pre}${obj}" >&2; return 1; }
    n=$(json 'console.log(JSON.parse(process.argv[1]).result.totalSize)' "$out") || return 1
    detail+="${obj%__*}=$n "
  done
  q="SELECT COUNT() FROM ApexClass WHERE Name = 'PMS_CreateBookingAction'"
  [[ -n "$ns" ]] && q="$q AND NamespacePrefix = '$ns'"
  out=$(sf data query -o "$org" --json -q "$q" 2>/dev/null) || return 1
  n=$(json 'console.log(JSON.parse(process.argv[1]).result.totalSize)' "$out") || return 1
  [[ "$n" -ge 1 ]] || { echo "smoke: PMS Experience classes not found" >&2; return 1; }
  BS_NOTE="${detail}experience=ok"
}

cmd_bootstrap() {
  local alias="${1:-}"; shift || true
  [[ -n "$alias" && "$alias" != --* ]] || die "usage: bootstrap <alias> [--scratch [--days N]] [--source | --version-core 04t.. --version-exp 04t..] [--no-sample] [--tests] [--with-agent]"
  local scratch=false days=7 mode=source vcore="" vexp="" sample=true tests=false agent=false override=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scratch) scratch=true ;;
      --days) shift; days="${1:-}"; [[ "$days" =~ ^[0-9]+$ && "$days" -ge 1 && "$days" -le 30 ]] || die "--days must be 1-30" ;;
      --source) mode=source ;;
      --version-core) shift; vcore="${1:-}"; mode=install ;;
      --version-exp) shift; vexp="${1:-}"; mode=install ;;
      --no-sample) sample=false ;;
      --tests) tests=true ;;
      --with-agent) agent=true ;;
      --i-know-this-org) override=true ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  if [[ "$mode" == install ]]; then
    [[ "$vcore" =~ ^04t[A-Za-z0-9]{12,15}$ && "$vexp" =~ ^04t[A-Za-z0-9]{12,15}$ ]] ||
      die "install mode needs both --version-core 04t... and --version-exp 04t..."
  fi

  # 1. The org: existing/authenticated, a new scratch org (from the current Dev Hub), or a trial / DE login.
  if org_authed "$alias"; then
    bs_step org OK "$alias already authenticated; not recreated"
  elif $scratch; then
    echo "Creating scratch org $alias from Dev Hub $DEVHUB ($days days)..."
    if sf org create scratch -f "$SCRATCH_DEF" -a "$alias" -v "$DEVHUB" -y "$days" -w 30; then
      bs_step org OK "scratch org created ($days days)"
    else
      bs_step org FAIL "scratch create failed (is $DEVHUB a live Dev Hub? run: devhub <alias>)"
    fi
  else
    echo "$alias is not authenticated; logging in..."
    if sf org login web --alias "$alias" && org_authed "$alias"; then
      bs_step org OK "logged in"
    else
      bs_step org FAIL "login failed"
    fi
  fi
  if [[ $BS_RC -ne 0 ]]; then bs_summary; exit 1; fi
  # Refuse before deploying anything into a production-like org (also covers an already-authenticated alias).
  org_guard "$alias" "$override"

  # 2. PMS Core, then PMS Experience.
  local pkg id deployed=true
  if [[ "$mode" == source ]]; then
    # A scratch org inherits the project namespace; a plain trial / Developer Edition org has none.
    if $scratch; then unset PMS_ORG_NS; else export PMS_ORG_NS=""; fi
    echo "Deploying PMS Core source..."
    if sf project deploy start -d packages/pms/core -o "$alias" -w 60; then bs_step core OK source; else bs_step core FAIL "source deploy failed"; deployed=false; fi
    if $deployed; then
      echo "Deploying PMS Experience source..."
      if sf project deploy start -d packages/pms/experience -o "$alias" -w 60; then bs_step experience OK source; else bs_step experience FAIL "source deploy failed"; deployed=false; fi
    fi
  else
    export PMS_ORG_NS="${PMS_ORG_NS-$(namespace)}"
    [[ -n "$PMS_ORG_NS" ]] || echo "warning: no namespace in $PROJECT_FILE; assuming the packages have none" >&2
    for pkg in core:"$vcore" experience:"$vexp"; do
      id="${pkg#*:}"
      if package_installed "$alias" "$id"; then
        bs_step "${pkg%%:*}" OK "$id already installed"
      elif sf package install -o "$alias" -p "$id" --security-type AdminsOnly --no-prompt -w 60 -b 30; then
        bs_step "${pkg%%:*}" OK "installed $id"
      else
        bs_step "${pkg%%:*}" FAIL "install of $id failed"; deployed=false; break
      fi
    done
  fi
  if ! $deployed; then bs_summary; exit 1; fi

  local ns rc=0
  ns=$(detect_org_ns "$alias") || { bs_step namespace FAIL "PMS objects not found in $alias after deploy"; bs_summary; exit 1; }
  export PMS_ORG_NS="$ns"

  # 3. org-setup (sites, networks, profiles, role, sharing rules). Needs Experience Cloud.
  org_setup_run "$alias" "$agent" || rc=$?
  case "$rc" in
    0) bs_step org-setup OK "sites, profiles, role, sharing rules" ;;
    2) bs_step org-setup FAIL "unreplaced __PMS_ token in payload (see output above)" ;;
    3) bs_step org-setup WARN "deploy failed$(licence_hint "$BUILD_DIR/org-setup-main.log"); continuing with Core + Experience" ;;
    *) bs_step org-setup WARN "could not run; continuing" ;;
  esac

  # 4. Permission sets for the running admin.
  if bs_assign_permsets "$alias"; then
    bs_step permsets OK "$BS_NOTE"
  else
    bs_step permsets WARN "could not assign all admin permission sets (run: scripts/pms-package.sh access $alias)"
  fi

  # 5. Configuration records.
  rc=0
  node "$CONFIG_TOOL" import "$alias" "$CONFIG_DATA_DIR" "$ns" "$BUILD_DIR/config-import" || rc=$?
  case "$rc" in
    0) bs_step config OK "imported from $CONFIG_DATA_DIR" ;;
    10) bs_step config SKIP "nothing to import (no files, or records already exist)" ;;
    *) bs_step config WARN "import failed (see output above)" ;;
  esac

  # 6. Demo data: the baseline pack (loads in the background; does nothing if it is already loaded).
  if $sample; then
    org_guard "$alias" "$override" # demo data is never loaded where deploying is refused
    local dout dmsg
    demo_optin "$alias" "$ns" || true # Developer Edition / trial orgs need the opt-in; the guard above vetted this org
    if dout=$(demo_apex "$alias" "$ns" load baseline); then
      dmsg=$(printf '%s\n' "$dout" | sed -n 's/^message|//p' | head -1)
      case "$dmsg" in
        Loading*)
          echo "Loading the baseline demo data (runs in the background, a few minutes)..."
          if demo_wait "$alias" "$ns" 900; then
            dout=$(demo_apex "$alias" "$ns" status all) || dout=""
            if printf '%s\n' "$dout" | grep -q '^pack|baseline|DONE|'; then
              bs_step sample-data OK "baseline pack: every module"
            else
              bs_step sample-data WARN "baseline did not finish (run: demo-data $alias --status)"
            fi
          else
            bs_step sample-data WARN "still loading or failed (run: demo-data $alias --status)"
          fi ;;
        *already\ loaded*) bs_step sample-data SKIP "baseline demo data already loaded" ;;
        *) bs_step sample-data WARN "${dmsg:-no answer from the demo data script} (log: $BUILD_DIR/demo-data.log)" ;;
      esac
    else
      bs_step sample-data WARN "script failed (see $BUILD_DIR/demo-data.log)"
    fi
  else
    bs_step sample-data SKIP "--no-sample"
  fi

  # 7. Apex tests (PMS test classes only).
  if $tests; then
    if bs_run_tests "$alias" "$ns"; then bs_step apex-tests OK "$BS_TEST_NOTE"; else bs_step apex-tests FAIL "$BS_TEST_NOTE"; fi
  fi

  # 8. Smoke check.
  if bs_smoke "$alias" "$ns"; then bs_step smoke OK "$BS_NOTE"; else bs_step smoke FAIL "PMS objects not queryable"; fi

  bs_summary
  echo
  echo "Still manual: publish the sites; enter the Stripe key and PMS Settings (see packages/pms/README.md). Open: sf org open -o $alias"
  exit "$BS_RC"
}

cmd_config_export() {
  local org="${1:-}"
  [[ -n "$org" ]] || die "usage: config-export <alias>"
  local ns
  ns=$(detect_org_ns "$org") || die "PMS is not deployed in $org"
  node "$CONFIG_TOOL" export "$org" "$CONFIG_DATA_DIR" "$ns" "$BUILD_DIR/config-export"
  echo "Review and commit $CONFIG_DATA_DIR."
}

cmd_config_import() {
  local org="${1:-}"
  [[ -n "$org" ]] || die "usage: config-import <alias> [--i-know-this-org]"
  local ns rc=0 override=false
  [[ "${2:-}" == "--i-know-this-org" ]] && override=true
  org_guard "$org" "$override"
  ns=$(detect_org_ns "$org") || die "PMS is not deployed in $org"
  node "$CONFIG_TOOL" import "$org" "$CONFIG_DATA_DIR" "$ns" "$BUILD_DIR/config-import" || rc=$?
  [[ $rc -eq 0 || $rc -eq 10 ]] || die "config import failed"
}

cmd_demo_data() {
  local alias="${1:-}"; shift || true
  local usage_msg="usage: demo-data <alias> [--pack <name>] [--reset] [--status] [--i-know-this-org]"
  [[ -n "$alias" && "$alias" != --* ]] || die "$usage_msg"
  local pack="" action=load override=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pack) shift; pack="${1:-}"; [[ -n "$pack" ]] || die "--pack needs a name. $usage_msg" ;;
      --reset) action=reset ;;
      --status) action=status ;;
      --i-know-this-org) override=true ;;
      *) die "unknown option $1. $usage_msg" ;;
    esac
    shift
  done
  if [[ -z "$pack" ]]; then
    if [[ "$action" == reset ]]; then die "--reset needs --pack <name> (or --pack all). $usage_msg"; fi
    pack=baseline
  fi
  [[ "$pack" =~ ^[a-z][a-z-]{1,30}$ ]] || die "invalid pack name '$pack'"
  org_guard "$alias" "$override"
  local ns out msg
  ns=$(detect_org_ns "$alias") || die "PMS is not deployed in $alias"

  [[ "$action" == status ]] || demo_optin "$alias" "$ns" || true # org_guard vetted this org
  out=$(demo_apex "$alias" "$ns" "$action" "$pack") || exit 1
  if [[ "$action" == status ]]; then
    demo_print_status "$out"
    return 0
  fi
  msg=$(printf '%s\n' "$out" | sed -n 's/^message|//p' | head -1)
  [[ -n "$msg" ]] || die "no answer from the demo data script (see $BUILD_DIR/demo-data.log)"
  echo "$msg"
  case "$msg" in
    Refused*|Unknown*) exit 1 ;;
    Loading*|Removing*)
      echo "Working in the background (one step per job). Waiting..."
      if demo_wait "$alias" "$ns" 1800; then
        echo
        demo_print_status "$(demo_apex "$alias" "$ns" status all)"
      else
        echo
        echo "Still running, or the status could not be read. Check later with: scripts/pms-package.sh demo-data $alias --status" >&2
        exit 1
      fi ;;
  esac
}

case "${1:-}" in
  create) shift; cmd_create "$@" ;;
  version) shift; cmd_version "$@" ;;
  promote) shift; cmd_promote "$@" ;;
  links) shift; cmd_links ;;
  install) shift; cmd_install "$@" ;;
  org-setup) shift; cmd_org_setup "$@" ;;
  access) shift; cmd_access "$@" ;;
  scratch) shift; cmd_scratch "$@" ;;
  devhub) shift; cmd_devhub "$@" ;;
  bootstrap) shift; cmd_bootstrap "$@" ;;
  demo-data) shift; cmd_demo_data "$@" ;;
  config-export) shift; cmd_config_export "$@" ;;
  config-import) shift; cmd_config_import "$@" ;;
  *) usage ;;
esac
