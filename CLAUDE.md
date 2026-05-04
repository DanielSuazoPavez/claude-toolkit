# CLAUDE.md

## Project Overview

Claude Toolkit — a **resource workshop** for Claude Code. Authors and distributes skills, agents, hooks, and docs to downstream projects (consumers and satellites) via `claude-toolkit sync`. The workshop supplies resources; it does not orchestrate downstream projects. See `.claude/docs/relevant-project-identity.md` for the full identity.

## Quick Start

```bash
make check                                     # Run tests and validations
make test                                      # Run tests only
make backlog                                   # Show backlog (prefer over reading BACKLOG.json directly)
claude-toolkit backlog id <task-id>             # Query specific backlog task by id
```

### CLI Quick Reference

`claude-toolkit` is the toolkit's own CLI — used here for backlog/lessons/docs queries. Run `claude-toolkit <cmd> --help` for details.

- `claude-toolkit backlog <cmd>` — query/mutate backlog (e.g. `backlog summary`, `backlog id <task-id>`, `backlog next`, `backlog status`, `backlog priority`, `backlog scope`, `backlog add`, `backlog update`, `backlog move`, `backlog remove`, `backlog render`)
- `claude-toolkit lessons <cmd>` — manage lessons (e.g. `lessons search <query>`, `lessons list`, `lessons health`)
- `claude-toolkit docs [name]` — list or emit workshop agent-facing contracts
- `claude-toolkit eval <cmd>` — query evaluation status (`stale`, `unevaluated`, `above`, `type`)
- `claude-toolkit send <path>` — send a resource or issue to another project's suggestions-box
- `claude-toolkit sync` — sync workshop resources to a downstream project
- `claude-toolkit validate` — check toolkit configuration in current project

## Key Principles

- **Plan before building**: Use plan mode for non-trivial tasks, even when they look simple at first glance
- **User owns shared-state ops**: Claude does not merge to main, push, open pull requests, or push tags. `/draft-pr` is also user-invoked — it generates the description, the user opens the PR. Wrap-up ends at the handoff. When the user merges, they use `git merge --no-ff` to preserve branch history.
- **Backlog via CLI only**: Never read `BACKLOG.json` or `BACKLOG.md` directly — use `claude-toolkit backlog <cmd>` for all queries and mutations. For bulk edits the CLI doesn't cover, use `jq` on `BACKLOG.json` directly
- **Remove done tasks from backlog**: When a backlog task is completed, remove it via `claude-toolkit backlog remove <id>` — don't leave it with a DONE marker
- **Capture lessons aggressively**: When you notice a correction, gotcha, pattern, or convention worth preserving, use `/learn` without hesitation. Bias toward capturing — pruning and crystallization happen later via `/manage-lessons`
- **No sudo access**: Don't run sudo commands — provide shell commands for the user to run manually when elevated privileges are needed
- **Verify before stating**: Don't state how a system works without checking the code first — read the actual implementation rather than assuming from names or conventions
- **Verification is `make check`, invoked bare**: Default verification after implementation is `make check`. Do NOT pipe through `head`/`tail`/`grep` or other filters — the full output is what you need. If it fails, read the complete output before re-running. `make check` here = `make test` + `make validate` (no lint target in this repo — it's bash-first; see `.claude/docs/essential-conventions-code_style.md` §4 for the full convention)

## Structure

```
.claude/
├── skills/     # User-invocable skills (/skill-name)
├── agents/     # Specialized task agents
├── hooks/      # Automation hooks
├── scripts/    # Workshop-internal tooling — validators, diagnostics, cron; a subset ships (see docs/indexes/SCRIPTS.md)
├── docs/       # Internal docs — conventions, configs, rules (synced to projects via distributions)
└── memories/   # Organic context (project identity, user preferences, auto-memory)
docs/
├── indexes/    # Resource indexes and evaluation scores
└── ...         # User-facing docs — getting started, curated resources (synced to project root)
output/
└── claude-toolkit/  # Generated artifacts (analysis, reviews, sessions, plans, etc.)
```

**`docs/` vs `.claude/docs/`**: Both sync to projects but land in different places. `.claude/docs/` stays inside `.claude/` (agent context — loaded by session-start, referenced by skills). `docs/` copies to the project root (user-facing — getting started guides, reference material). When adding documentation, pick the location by audience: agent-facing → `.claude/docs/`, user-facing → `docs/`.

## Resource Indexes

Summary and status of all resources:

- `docs/indexes/SKILLS.md` - All skills with status and descriptions
- `docs/indexes/AGENTS.md` - All agents with status, descriptions, and tools
- `docs/indexes/HOOKS.md` - All hooks with triggers and configuration
- `docs/indexes/DOCS.md` - All docs (reference documentation, rules, conventions)
- `docs/indexes/evaluations.json` - Quality scores, grades, and improvement suggestions

## Changelog

The version bump is the user's call. `/wrap-up` analyzes the branch, proposes a bump, and waits for confirmation before editing version/changelog files. Two orthogonal dimensions inform the proposal:

1. **Code vs docs-only** — drives the bump suggestion.
   - Code change (anything under `cli/`, `.claude/hooks/`, `.claude/skills/`, `.claude/agents/`, `.claude/scripts/`, `tests/`, etc. — including workshop-internal code): suggest a bump (Patch default; Minor for new features; Major for breaking) + changelog entry under that version.
   - Docs-only (BACKLOG, design notes, exploration, prose-only edits to CHANGELOG/README): suggest no bump, fold into `[Unreleased]` → `### Notes`.
2. **Consumed vs workshop-internal** — shapes the changelog body and release-notes channels (does not gate the bump).
   - Consumed = anything reachable by a downstream project via `claude-toolkit sync` (base manifest), or via any other distribution profile, or via `claude-toolkit send`. Resources, shipped docs, CLI behavior, etc. — all forms of "leaves the workshop".
   - Workshop-internal = stays in this repo (e.g., `tests/`, `design/`, `output/`, internal scripts not declared in any dist).
3. **Raiz sidecar** — a specific consumer cut. Required on every version bump:
   - Change reaches raiz consumers (in `dist/raiz/MANIFEST` or covered by base sync that raiz inherits) → write `dist/raiz/changelog/<version>.json` describing the user-visible change.
   - Otherwise (consumed by other dists but not raiz, or workshop-internal only) → write the sidecar with `skip: true`.

Workshop-internal code is still code — it bumps. "Consumed" is broader than "raiz consumers"; the sidecar speaks only for the raiz subset.

When adding a version entry, fold any existing `[Unreleased]` content into it and clear `[Unreleased]`.

## When You're Done

- Run `make check` to run all tests and validations
- Verify skill/agent changes work with real tests
- **Raiz message check** (version bumps only): preview the Telegram notification — see `dist/raiz/CLAUDE.md` for the command and override path.

## Suggestions Box

`suggestions-box/` — inbox for resources and issues sent from other projects via `claude-toolkit send`. Organized by source project. Triage with "check suggestions" — see `suggestions-box/CLAUDE.md` for the full workflow.

## Codebase Orientation

Read these before exploring the codebase:

1. `.claude/docs/codebase-explorer/` — versioned architecture reports (ARCHITECTURE.md, STACK.md, STRUCTURE.md, INTEGRATIONS.md). Read the latest version first.
2. `docs/indexes/` — resource indexes for skills, agents, hooks, docs, and evaluations
3. `cli/CLAUDE.md` — CLI module structure (mixed Python + shell)
4. `dist/CLAUDE.md` — distribution profiles (base vs raiz) and how publishing works
5. `tests/CLAUDE.md` — test file map, runners, shared helpers

## See Also

- `README.md` — Full documentation, CLI usage, sync workflow
- `make backlog` — Show current priorities (uses `claude-toolkit backlog` CLI)
- `.claude/docs/relevant-toolkit-lessons.md` — Lessons ecosystem reference (schema, tiers, tags, CLI, lifecycle)
