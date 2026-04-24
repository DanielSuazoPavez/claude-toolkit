# Docs Index

Reference documentation and prescriptive rules. Loaded at session start or on-demand.

## Essential Docs

Always loaded at session start:

| Doc | Status | Purpose |
|-----|--------|---------|
| `essential-conventions-code_style` | stable | Coding conventions, formatting, style guide |
| `essential-preferences-communication_style` | stable | Communication style preferences |

## Relevant Docs

| Doc | Status | Purpose |
|-----|--------|---------|
| `relevant-toolkit-context` | stable | Docs/memories boundary, naming conventions, categories |
| `relevant-toolkit-hooks` | stable | Hook authoring: match/check pattern, dual-mode trigger, outcomes |
| `relevant-toolkit-hooks_config` | stable | Hooks configuration and environment variables |
| `relevant-toolkit-permissions_config` | stable | Two-tier permissions convention: toolkit settings.json vs project settings.local.json |
| `relevant-toolkit-resource_frontmatter` | stable | Supported frontmatter fields for skills and agents |
| `relevant-workflow-backlog` | stable | BACKLOG.md schema: priority, categories, status values |
| `relevant-toolkit-resource_naming` | stable | Naming conventions for all resource types (skills, agents, memories, hooks) |
| `relevant-toolkit-artifacts` | stable | Output path + filename convention for runtime artifacts (skills/agents writing to `output/claude-toolkit/`) |
| `relevant-conventions-testing` | stable | Test structure, runners, and conventions |
| `relevant-toolkit-lessons` | stable | Lessons ecosystem: schema, tiers, tags, skills, hooks, CLI, lifecycle |
| `relevant-project-identity` | stable | What the toolkit is, resource roles, decision checklist |
| `relevant-toolkit-satellite-contracts` | stable | Advisory convention for satellite maintainers: expose agent-facing contracts via `<satellite> docs <contract>` so workshop skills don't carry drifting copies |
| `relevant-toolkit-satellite-consumers` | stable | Consumer-side convention for workshop skills that call satellite contracts: pointer file structure, failure ladder, invocation pattern |
| `relevant-philosophy-reducing_entropy` | stable | Philosophy on reducing codebase entropy |
