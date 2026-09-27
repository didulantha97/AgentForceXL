#!/usr/bin/env bash
# Retrieve, deploy, delete, publish and activate Agentforce metadata (agents,
# Agent Script bundles, topics, actions, prompt templates, ...) one component
# at a time, and keep each package's manifest/package.xml in sync.
#
# Run `scripts/sf-agentforce.sh help` for usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/lib/agentforce-helper.js"
cd "$REPO_ROOT"

usage() {
  cat <<'EOF'
Agentforce helper: one command per task, manifests updated for you.

USAGE
  scripts/sf-agentforce.sh <command> [arguments] [options]

COMMANDS
  list       <org> [type]                 Show what exists in the org
  retrieve   <type> <name> <org>          Pull a component into the project
  deploy     <type> <name> <org>          Push a local component to the org
  delete     <type> <name> <org>          Delete from the org AND the project
  publish    <agent-script-name> <org>    Publish an Agent Script bundle as an agent
  activate   <agent> <org>                Activate an agent (latest version by default)
  deactivate <agent> <org>                Deactivate an agent
  add        <type> <name>                Only add the component to package.xml
  remove     <type> <name>                Only remove the component from package.xml
  types                                   Show the supported <type> names

OPTIONS
  --package <path>     Manifest to update, relative to packages/ (e.g. binance,
                       agents/helpagent). retrieve/deploy default: the package
                       the files live in. add/remove default: default.
  --dry-run            deploy: validate only. delete: show/validate only.
  --yes                delete: skip the confirmation prompt.
  --no-manifest        retrieve/deploy: don't touch package.xml.
  --version <n>        activate: version number to activate.
  --test-level <lvl>   deploy: NoTestRun | RunSpecifiedTests | RunLocalTests | RunAllTestsInOrg
  --tests <names>      deploy: test classes for RunSpecifiedTests (space-separated, quoted)

EXAMPLES
  scripts/sf-agentforce.sh list ecaViaMetadata
  scripts/sf-agentforce.sh retrieve agent Binance_Agent ecaViaMetadata --package binance
  scripts/sf-agentforce.sh retrieve prompt Summarize_Account ecaViaMetadata
  scripts/sf-agentforce.sh deploy agent-script Binance_Agent ecaViaMetadata --dry-run
  scripts/sf-agentforce.sh publish Binance_Agent ecaViaMetadata
  scripts/sf-agentforce.sh delete prompt Old_Template ecaViaMetadata
  scripts/sf-agentforce.sh add topic My_Topic --package agents/helpagent
EOF
}

types_help() {
  cat <<'EOF'
Friendly type      Metadata type              Notes
-----------------  -------------------------  ------------------------------------------
agent              Agent (Bot + everything)   Bot, versions, planner, topics, actions
agent-script       AiAuthoringBundle          The .agent file (new Agentforce builder)
bot                Bot                        Agent container only
planner            GenAiPlannerBundle         Agent reasoning config (<Agent>_v<N>)
topic              GenAiPlugin
action             GenAiFunction
prompt             GenAiPromptTemplate        Prompt Builder template
prompt-activation  GenAiPromptTemplateActv
flow               Flow
apex               ApexClass
lwc                LightningComponentBundle
permset            PermissionSet
<anything else>    used as-is                 e.g. ExternalServiceRegistration, NamedCredential

Names are API names. Use * as the name to retrieve every component of a type.
Note: for "agent", a name ending in _<number> means that version
(Binance_Agent_3 = version 3 of Binance_Agent). Use Name_* for all versions.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

resolve_type() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    agent | agents) echo Agent ;;
    agent-script | agentscript | script | authoring-bundle | aiauthoringbundle) echo AiAuthoringBundle ;;
    bot) echo Bot ;;
    planner | genaiplannerbundle) echo GenAiPlannerBundle ;;
    topic | topics | genaiplugin) echo GenAiPlugin ;;
    action | actions | genaifunction) echo GenAiFunction ;;
    prompt | prompts | prompt-template | genaiprompttemplate) echo GenAiPromptTemplate ;;
    prompt-activation | genaiprompttemplateactv) echo GenAiPromptTemplateActv ;;
    flow) echo Flow ;;
    apex | class | apexclass) echo ApexClass ;;
    lwc | lightningcomponentbundle) echo LightningComponentBundle ;;
    permset | permission-set | permissionset) echo PermissionSet ;;
    *) echo "$1" ;;
  esac
}

# --- argument parsing --------------------------------------------------------
POSITIONAL=()
PACKAGE=""
DRY_RUN=false
YES=false
NO_MANIFEST=false
VERSION=""
TEST_LEVEL=""
TESTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package) PACKAGE="${2:?--package needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes | -y) YES=true; shift ;;
    --no-manifest) NO_MANIFEST=true; shift ;;
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --test-level) TEST_LEVEL="${2:?--test-level needs a value}"; shift 2 ;;
    --tests) TESTS="${2:?--tests needs a value}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    --*) die "Unknown option: $1 (run with 'help')" ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

[[ ${#POSITIONAL[@]} -gt 0 ]] || { usage; exit 1; }
COMMAND="${POSITIONAL[0]}"

need_args() {
  # need_args <count> <usage line>
  [[ ${#POSITIONAL[@]} -eq $(($1 + 1)) ]] || die "Usage: scripts/sf-agentforce.sh $2"
}

command -v sf >/dev/null || die "Salesforce CLI (sf) is not installed."
command -v node >/dev/null || die "Node.js is required."

if [[ -n "$PACKAGE" ]]; then
  PACKAGE="${PACKAGE#packages/}"
  PACKAGE="${PACKAGE%/}"
  [[ -d "packages/$PACKAGE" ]] || die "Package not found: packages/$PACKAGE"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# run_sf <json-out> <sf args...>: runs sf with --json; never aborts the script.
run_sf() {
  local out="$1"
  shift
  sf "$@" --json >"$out" 2>"$TMP_DIR/stderr" || true
}

manifest_for() {
  echo "packages/$1/manifest/package.xml"
}

# Add every component listed in an sf --json result to the right manifest.
update_manifests_from() {
  local json="$1" type name dir
  $NO_MANIFEST && return 0
  echo ""
  echo "Updating package.xml:"
  while IFS=$'\t' read -r type name dir; do
    [[ -n "$type" ]] || continue
    if [[ -n "$PACKAGE" ]]; then
      dir="packages/$PACKAGE"
    fi
    if [[ -z "$dir" ]]; then
      echo "  ? $type:$name is outside every package directory; skipped"
      continue
    fi
    node "$HELPER" manifest-add "$dir/manifest/package.xml" "$type" "$name"
  done < <(node "$HELPER" components "$json")
}

confirm() {
  # confirm <expected answer> <prompt>
  $YES && return 0
  [[ -t 0 ]] || die "Refusing to delete without confirmation. Re-run with --yes."
  local answer
  read -r -p "$2 " answer
  [[ "$answer" == "$1" ]] || die "Cancelled (you typed '$answer', expected '$1')."
}

# --- commands ----------------------------------------------------------------
cmd_list() {
  local org="${POSITIONAL[1]}" only="" t
  [[ ${#POSITIONAL[@]} -ge 3 ]] && only="$(resolve_type "${POSITIONAL[2]}")"

  if [[ -z "$only" || "$only" == "Agent" || "$only" == "Bot" ]]; then
    echo "== Agents (Bot) and version status"
    sf data query --target-org "$org" \
      --query "SELECT DeveloperName, MasterLabel, (SELECT VersionNumber, Status FROM BotVersions ORDER BY VersionNumber) FROM BotDefinition ORDER BY DeveloperName"
    [[ -n "$only" ]] && return 0
  fi

  local list_types=(AiAuthoringBundle GenAiPlannerBundle GenAiPlugin GenAiFunction GenAiPromptTemplate)
  [[ -n "$only" ]] && list_types=("$only")
  for t in "${list_types[@]}"; do
    echo ""
    echo "== $t"
    run_sf "$TMP_DIR/list.json" org list metadata --metadata-type "$t" --target-org "$org"
    node "$HELPER" names "$TMP_DIR/list.json" | sed 's/^/  /' | grep . || echo "  (none)"
  done
}

cmd_retrieve() {
  local type name org md
  type="$(resolve_type "${POSITIONAL[1]}")"
  name="${POSITIONAL[2]}"
  org="${POSITIONAL[3]}"
  md="$type:$name"

  echo "Retrieving $md from '$org'..."
  if [[ "$type" == "Agent" ]]; then
    echo "(an agent brings its Bot, versions, planner, topics and actions)"
  fi
  run_sf "$TMP_DIR/retrieve.json" project retrieve start --metadata "$md" --target-org "$org"
  node "$HELPER" report retrieve "$TMP_DIR/retrieve.json" || exit 1
  update_manifests_from "$TMP_DIR/retrieve.json"

  if [[ "$type" == "Agent" ]]; then
    echo ""
    echo "Tip: agents built with Agent Script also have a bundle. Pull it with:"
    echo "  scripts/sf-agentforce.sh retrieve agent-script ${name%%_[0-9]*} $org"
  fi
}

cmd_deploy() {
  local type name org md args
  type="$(resolve_type "${POSITIONAL[1]}")"
  name="${POSITIONAL[2]}"
  org="${POSITIONAL[3]}"
  md="$type:$name"

  args=(project deploy start --metadata "$md" --target-org "$org")
  $DRY_RUN && args+=(--dry-run)
  [[ -n "$TEST_LEVEL" ]] && args+=(--test-level "$TEST_LEVEL")
  local test_class
  for test_class in $TESTS; do args+=(--tests "$test_class"); done

  if $DRY_RUN; then
    echo "Validating (dry run) $md against '$org'..."
  else
    echo "Deploying $md to '$org'..."
  fi
  run_sf "$TMP_DIR/deploy.json" "${args[@]}"
  if ! node "$HELPER" report deploy "$TMP_DIR/deploy.json"; then
    if [[ "$type" == "Agent" || "$type" == "Bot" || "$type" == "GenAiPlannerBundle" ]]; then
      echo ""
      echo "Tip: an active agent can't be changed. Deactivate it first:"
      echo "  scripts/sf-agentforce.sh deactivate ${name%%_[0-9]*} $org"
    fi
    exit 1
  fi

  if $DRY_RUN; then
    echo "Dry run: nothing was saved and package.xml was not changed."
    return 0
  fi
  update_manifests_from "$TMP_DIR/deploy.json"

  if [[ "$type" == "AiAuthoringBundle" ]]; then
    echo ""
    echo "Next: turn the Agent Script into a live agent version with:"
    echo "  scripts/sf-agentforce.sh publish $name $org"
  fi
}

# delete_components <org> <Type:Name>...  (org + local project, one sf call)
delete_components() {
  local org="$1"
  shift
  local args=(project delete source --target-org "$org" --no-prompt) md
  for md in "$@"; do args+=(--metadata "$md"); done
  $DRY_RUN && args+=(--check-only)
  run_sf "$TMP_DIR/delete.json" "${args[@]}"
  node "$HELPER" report delete "$TMP_DIR/delete.json"
}

remove_from_manifests() {
  local md
  $DRY_RUN && return 0
  echo ""
  echo "Updating package.xml:"
  for md in "$@"; do
    if [[ -n "$PACKAGE" ]]; then
      node "$HELPER" manifest-remove "$(manifest_for "$PACKAGE")" "${md%%:*}" "${md#*:}"
    else
      node "$HELPER" manifest-remove-everywhere "${md%%:*}" "${md#*:}"
    fi
  done
}

org_names() {
  # org_names <org> <Type>: API names of that type in the org
  run_sf "$TMP_DIR/names.json" org list metadata --metadata-type "$2" --target-org "$1"
  node "$HELPER" names "$TMP_DIR/names.json"
}

agent_is_active() {
  run_sf "$TMP_DIR/active.json" data query --target-org "$1" \
    --query "SELECT Id FROM BotVersion WHERE BotDefinition.DeveloperName = '$2' AND Status = 'Active'"
  node -e 'const j=require(process.argv[1]); process.exit(j.result && j.result.totalSize > 0 ? 0 : 1)' \
    "$TMP_DIR/active.json"
}

cmd_delete_agent() {
  local name="$1" org="$2" n
  [[ "$name" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "Give the agent's exact API name (no wildcards)."

  echo "Looking up everything that belongs to agent '$name' in '$org'..."
  local bots=() bundles=() planners=()
  while read -r n; do [[ "$n" == "$name" ]] && bots+=("Bot:$n"); done < <(org_names "$org" Bot)
  [[ ${#bots[@]} -gt 0 ]] || die "Agent '$name' was not found in '$org'. Run: scripts/sf-agentforce.sh list $org agent"
  while read -r n; do
    [[ "$n" =~ ^${name}(_[0-9]+)?$ ]] && bundles+=("AiAuthoringBundle:$n")
  done < <(org_names "$org" AiAuthoringBundle)
  while read -r n; do
    [[ "$n" =~ ^${name}(_v[0-9]+)?$ ]] && planners+=("GenAiPlannerBundle:$n")
  done < <(org_names "$org" GenAiPlannerBundle)

  local active=false
  agent_is_active "$org" "$name" && active=true

  echo ""
  echo "Will delete from '$org' and from this project:"
  for n in ${bundles[@]+"${bundles[@]}"} "${bots[@]}" ${planners[@]+"${planners[@]}"}; do echo "  - $n"; done
  $active && echo "The agent is ACTIVE; it will be deactivated first."
  echo "Topics (GenAiPlugin) and actions (GenAiFunction) are kept because other"
  echo "agents may share them. Delete them separately if you no longer need them."

  if $DRY_RUN; then
    echo ""
    echo "Dry run: nothing was changed."
    return 0
  fi

  echo ""
  confirm "$name" "This cannot be undone. Type the agent name ($name) to confirm:"

  if $active; then
    echo "Deactivating $name..."
    run_sf "$TMP_DIR/deactivate.json" agent deactivate --api-name "$name" --target-org "$org"
    node -e 'const j=require(process.argv[1]); if (j.status !== 0) { console.log("  " + (j.message || "deactivate failed")); process.exit(1) }' \
      "$TMP_DIR/deactivate.json" || die "Could not deactivate $name."
  fi

  # Order matters: the Agent Script bundle references the Bot, and the Bot's
  # versions reference the planners.
  if [[ ${#bundles[@]} -gt 0 ]]; then
    echo "Step 1/3: deleting Agent Script bundles..."
    delete_components "$org" "${bundles[@]}" || die "Stopped. Nothing after step 1 was deleted."
  fi
  echo "Step 2/3: deleting the agent (Bot and its versions)..."
  delete_components "$org" "${bots[@]}" || die "Stopped at step 2. Check the errors above."
  if [[ ${#planners[@]} -gt 0 ]]; then
    echo "Step 3/3: deleting planners..."
    delete_components "$org" "${planners[@]}" || die "Stopped at step 3. Check the errors above."
  fi

  # Versioned bundle names (Name_3) don't match the local folder (Name).
  local dir
  for dir in packages/*/main/default/aiAuthoringBundles/"$name" packages/*/*/main/default/aiAuthoringBundles/"$name"; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
      echo "  Removed local folder $dir"
    fi
  done

  remove_from_manifests "Bot:$name" "AiAuthoringBundle:$name" \
    ${bundles[@]+"${bundles[@]}"} ${planners[@]+"${planners[@]}"}
}

cmd_delete() {
  local type name org md
  type="$(resolve_type "${POSITIONAL[1]}")"
  name="${POSITIONAL[2]}"
  org="${POSITIONAL[3]}"
  [[ "$name" != *"*"* ]] || die "Wildcards are not allowed for delete. Name one component."

  if [[ "$type" == "Agent" ]]; then
    cmd_delete_agent "$name" "$org"
    return
  fi

  md="$type:$name"
  if $DRY_RUN; then
    echo "Validating delete of $md in '$org' (nothing will change)..."
  else
    echo "About to delete $md from org '$org' and from this project."
    confirm "$name" "This cannot be undone. Type the name ($name) to confirm:"
  fi
  delete_components "$org" "$md" || {
    [[ "$type" == "GenAiPromptTemplate" ]] &&
      echo "Tip: a prompt template used by an agent action must be removed from that action first."
    exit 1
  }
  if $DRY_RUN; then
    echo "Dry run: nothing was changed."
    return 0
  fi
  remove_from_manifests "$md"
}

cmd_publish() {
  local name="${POSITIONAL[1]}" org="${POSITIONAL[2]}"
  echo "Publishing Agent Script bundle '$name' to '$org'..."
  sf agent publish authoring-bundle --api-name "$name" --target-org "$org"
  echo ""
  echo "Next: scripts/sf-agentforce.sh activate $name $org"
}

cmd_activate() {
  local name="${POSITIONAL[1]}" org="${POSITIONAL[2]}"
  if [[ -n "$VERSION" ]]; then
    sf agent activate --api-name "$name" --version "$VERSION" --target-org "$org"
  else
    echo "Activating the latest version of '$name' in '$org'..."
    run_sf "$TMP_DIR/activate.json" agent activate --api-name "$name" --target-org "$org"
    node -e 'const j=require(process.argv[1]); console.log(j.status === 0 ? "✔ Activated." : "✖ " + (j.message || "activate failed")); process.exit(j.status === 0 ? 0 : 1)' \
      "$TMP_DIR/activate.json"
  fi
}

cmd_deactivate() {
  local name="${POSITIONAL[1]}" org="${POSITIONAL[2]}"
  sf agent deactivate --api-name "$name" --target-org "$org"
}

cmd_manifest() {
  local action="$1" type name
  type="$(resolve_type "${POSITIONAL[1]}")"
  name="${POSITIONAL[2]}"
  [[ "$type" != "Agent" ]] ||
    die "'agent' is not a manifest type. Add 'bot' and 'planner' (or run retrieve, which adds everything)."
  node "$HELPER" "manifest-$action" "$(manifest_for "${PACKAGE:-default}")" "$type" "$name"
}

case "$COMMAND" in
  help) usage ;;
  types) types_help ;;
  list)
    [[ ${#POSITIONAL[@]} -ge 2 && ${#POSITIONAL[@]} -le 3 ]] || die "Usage: scripts/sf-agentforce.sh list <org> [type]"
    cmd_list
    ;;
  retrieve) need_args 3 "retrieve <type> <name> <org>"; cmd_retrieve ;;
  deploy) need_args 3 "deploy <type> <name> <org> [--dry-run]"; cmd_deploy ;;
  delete) need_args 3 "delete <type> <name> <org> [--dry-run] [--yes]"; cmd_delete ;;
  publish) need_args 2 "publish <agent-script-name> <org>"; cmd_publish ;;
  activate) need_args 2 "activate <agent> <org> [--version <n>]"; cmd_activate ;;
  deactivate) need_args 2 "deactivate <agent> <org>"; cmd_deactivate ;;
  add) need_args 2 "add <type> <name> [--package <path>]"; cmd_manifest add ;;
  remove) need_args 2 "remove <type> <name> [--package <path>]"; cmd_manifest remove ;;
  *) echo "Unknown command: $COMMAND" >&2; echo "" >&2; usage >&2; exit 1 ;;
esac
