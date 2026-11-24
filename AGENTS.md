# PMS development — agent routing

Hand work to the cheapest agent that can do it. The main session plans and coordinates; it should not read large files or dump org metadata itself.

| Task                                         | Agent           | Model  |
| -------------------------------------------- | --------------- | ------ |
| Find where something is in code              | explorer        | haiku  |
| What's built vs. left (org vs. docs)         | pms-auditor     | haiku  |
| Update project docs                          | docs-updater    | haiku  |
| Plan a new feature / change an existing one  | feature-planner | sonnet |
| Write Apex / triggers / LWC / metadata files | apex-dev        | sonnet |
| Apply changes in a Salesforce org via MCP    | org-deployer    | sonnet |
| Write and run tests                          | test-writer     | sonnet |
| Security / limits / booking & payment review | reviewer        | opus   |

## Standard flows

**Status check:** pms-auditor → summarise to user.

**New feature or update:** feature-planner → user approves plan → apex-dev and/or org-deployer (sandbox) → test-writer → reviewer → fix → docs-updater.

**Small config change:** org-deployer (sandbox) → docs-updater.

## Rules

- Production changes need explicit user approval each time.
- Pass agents only what they need (item names, plan step), not full history.
- Ask agents for short reports: tables and summaries, not raw output.
- Use opus (reviewer) only for review, before deploy.
