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
│   ├── agents/helpagent/           # Help agent
│   ├── binance/                    # Binance market-data agent
│   ├── superbadges/apex-callouts/  # Apex Callouts Superbadge
│   └── trailhead-modules/          # Trailhead module work
├── scripts/
│   ├── sf-agentforce.sh            # Agents, prompts, topics, actions (one component at a time)
│   ├── sf-package.sh               # Retrieve/deploy a whole package
│   └── sf-package-create.sh        # Create a new package directory
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

## Cheat sheet

Run everything from the repository root. Replace `my-org` with your org alias
(`sf org list` shows them).

| I want to…                                    | Command                                                               |
| --------------------------------------------- | --------------------------------------------------------------------- |
| See agents, Agent Script, topics, prompts     | `scripts/sf-agentforce.sh list my-org`                                |
| Pull an agent (Bot, planner, topics, actions) | `scripts/sf-agentforce.sh retrieve agent My_Agent my-org`             |
| Pull an Agent Script (`.agent`) bundle        | `scripts/sf-agentforce.sh retrieve agent-script My_Agent my-org`      |
| Pull a prompt template                        | `scripts/sf-agentforce.sh retrieve prompt My_Prompt my-org`           |
| Check a deploy without saving                 | `scripts/sf-agentforce.sh deploy prompt My_Prompt my-org --dry-run`   |
| Deploy one component                          | `scripts/sf-agentforce.sh deploy prompt My_Prompt my-org`             |
| Publish Agent Script as a live agent          | `scripts/sf-agentforce.sh publish My_Agent my-org`                    |
| Activate / deactivate an agent                | `scripts/sf-agentforce.sh activate My_Agent my-org` (or `deactivate`) |
| Delete a component (org **and** project)      | `scripts/sf-agentforce.sh delete prompt My_Prompt my-org`             |
| Delete a whole agent                          | `scripts/sf-agentforce.sh delete agent My_Agent my-org`               |
| Only add/remove a line in package.xml         | `scripts/sf-agentforce.sh add topic My_Topic --package binance`       |
| Retrieve/deploy a whole package               | `scripts/sf-package.sh retrieve binance my-org`                       |
| Create a new package                          | `scripts/sf-package-create.sh agents/my-agent`                        |

Every command prints its help with `scripts/sf-agentforce.sh help`.

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

### Agentforce: `scripts/sf-agentforce.sh`

Use this script for agents, Agent Script bundles, topics, actions, prompt
templates, or any single component. It works on one component at a time and
keeps `manifest/package.xml` up to date for you.

```text
scripts/sf-agentforce.sh <command> <type> <name> <org> [options]
```

**Commands**

| Command                        | What it does                                                                    | Updates package.xml |
| ------------------------------ | ------------------------------------------------------------------------------- | ------------------- |
| `list <org> [type]`            | Lists agents (with active/inactive versions), bundles, topics, actions, prompts | –                   |
| `retrieve <type> <name> <org>` | Pulls the component into the project                                            | Adds it             |
| `deploy <type> <name> <org>`   | Pushes the local component to the org                                           | Adds it             |
| `delete <type> <name> <org>`   | Deletes it from the org **and** the local project (asks you to confirm)         | Removes it          |
| `publish <name> <org>`         | Publishes an Agent Script bundle so it becomes a new agent version              | –                   |
| `activate <name> <org>`        | Activates the latest version of an agent (`--version <n>` to choose one)        | –                   |
| `deactivate <name> <org>`      | Deactivates an agent (needed before you change or delete it)                    | –                   |
| `add <type> <name>`            | Adds a line to a manifest without contacting the org                            | Adds it             |
| `remove <type> <name>`         | Removes a line from a manifest without contacting the org                       | Removes it          |
| `types`                        | Shows every supported type                                                      | –                   |

**Types** (short name → metadata type). Any other value is passed through as a
metadata type name, e.g. `ExternalServiceRegistration`.

| Short name                       | Metadata type                                                    | What it is                                        |
| -------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------- |
| `agent`                          | Bot + all its parts                                              | Agent, its versions, planner, topics, and actions |
| `agent-script`                   | `AiAuthoringBundle`                                              | The `.agent` file from the new Agentforce builder |
| `bot`                            | `Bot`                                                            | Agent container only                              |
| `planner`                        | `GenAiPlannerBundle`                                             | Agent reasoning config, named `<Agent>_v<N>`      |
| `topic`                          | `GenAiPlugin`                                                    | Topic                                             |
| `action`                         | `GenAiFunction`                                                  | Agent action                                      |
| `prompt`                         | `GenAiPromptTemplate`                                            | Prompt Builder template                           |
| `prompt-activation`              | `GenAiPromptTemplateActv`                                        | Prompt template activation                        |
| `flow`, `apex`, `lwc`, `permset` | `Flow`, `ApexClass`, `LightningComponentBundle`, `PermissionSet` | Things actions usually call                       |

**Options**

| Option               | Used with        | Meaning                                                               |
| -------------------- | ---------------- | --------------------------------------------------------------------- |
| `--package <path>`   | all              | Manifest to update, e.g. `binance` or `agents/helpagent`              |
| `--dry-run`          | deploy, delete   | Validate only; nothing changes in the org, project, or package.xml    |
| `--yes`              | delete           | Skip the confirmation prompt                                          |
| `--no-manifest`      | retrieve, deploy | Don't touch package.xml                                               |
| `--version <n>`      | activate         | Version to activate                                                   |
| `--test-level <lvl>` | deploy           | `NoTestRun`, `RunSpecifiedTests`, `RunLocalTests`, `RunAllTestsInOrg` |
| `--tests "<A> <B>"`  | deploy           | Test classes for `RunSpecifiedTests`                                  |

**Which package.xml is updated?** For `retrieve` and `deploy`, it is the
manifest of the package the files live in: a component under
`packages/binance/...` goes into `packages/binance/manifest/package.xml`. Pass
`--package` to choose one yourself. `add` and `remove` use `default` unless
you pass `--package`. `delete` removes the component from every manifest that
lists it. Existing formatting and comments are kept, and entries already
covered by `<members>*</members>` are left alone.

**Typical Agent Script workflow**

```bash
scripts/sf-agentforce.sh retrieve agent-script My_Agent my-org   # 1. pull the .agent file
# 2. edit packages/<pkg>/main/default/aiAuthoringBundles/My_Agent/My_Agent.agent
scripts/sf-agentforce.sh deploy agent-script My_Agent my-org --dry-run   # 3. validate
scripts/sf-agentforce.sh deploy agent-script My_Agent my-org             # 4. save the bundle
scripts/sf-agentforce.sh publish My_Agent my-org                         # 5. create a new agent version
scripts/sf-agentforce.sh activate My_Agent my-org                        # 6. make it live
scripts/sf-agentforce.sh retrieve agent My_Agent my-org                  # 7. pull the generated Bot/planner/topics
```

**Good to know**

- An **active agent can't be changed or deleted**. Run `deactivate` first. For
  `delete agent`, the script deactivates the agent for you.
- `delete agent My_Agent` removes, in this order: the Agent Script bundles
  (`My_Agent_1`, `My_Agent_2`, …), the Bot with all its versions, and the
  planners (`My_Agent_v1`, …). Topics and actions are **kept** because other
  agents may share them. Run `delete agent My_Agent my-org --dry-run` first to
  see the exact list.
- `delete` always asks you to type the name to confirm, unless you pass `--yes`.
  Deletes from the org can't be undone. Local files can be restored with git.
- If a delete is blocked by something that uses the component (for example, a
  flow that calls an Apex class), the script prints Salesforce's reason. Remove
  that usage first.
- For `agent`, a name ending in `_<number>` means a version:
  `Binance_Agent_3` is version 3 of `Binance_Agent`. Use `Binance_Agent_*` for
  all versions.
- A brand-new component (one not in the project yet) is retrieved into
  `packages/default`. Move it with `git mv` if it belongs to another package,
  then run `scripts/sf-agentforce.sh add <type> <name> --package <pkg>`.

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
