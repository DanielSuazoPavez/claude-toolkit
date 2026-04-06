# CLAUDE.md

## Project Overview

Claude Toolkit - curated Claude Code configuration with skills, agents, hooks, and docs templates.

## Quick Start

```bash
make check                                     # Run tests and validations
make test                                      # Run tests only
make backlog                                   # Show backlog (prefer over reading BACKLOG.md directly)
claude-toolkit backlog id <task-id>             # Query specific backlog task by id
```

## Key Principles

- **Plan before building**: Use plan mode for non-trivial tasks, even when they look simple at first glance
- **Merge with --no-ff**: Always use `git merge --no-ff` to preserve branch history
- **Remove done tasks from backlog**: When a backlog task is completed, delete it entirely — don't strikethrough or leave it with a DONE marker
- **Capture lessons aggressively**: When you notice a correction, gotcha, pattern, or convention worth preserving, use `/learn` without hesitation. Bias toward capturing — pruning and crystallization happen later via `/manage-lessons`
- **No sudo access**: Don't run sudo commands — provide shell commands for the user to run manually when elevated privileges are needed
- **Verify before stating**: Don't state how a system works without checking the code first — read the actual implementation rather than assuming from names or conventions

## Structure

```
.claude/
├── skills/     # User-invocable skills (/skill-name)
├── agents/     # Specialized task agents
├── hooks/      # Automation hooks
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

- Docs-only changes (backlog, design docs, exploration): `[Unreleased]` section, no version bump
- Code/resource changes: version bump + changelog entry under version
- When adding a version entry, fold any existing `[Unreleased]` changes into it
- **Raiz notification on version bump**: The publish-raiz workflow auto-detects raiz-relevant changes by trimming changelog entries against the MANIFEST — no manual flagging needed. To customize the Telegram message:
    1. Run `.github/scripts/format-raiz-changelog.sh <version>` to preview the auto-trimmed output
    2. If the message needs refinement, generate with `--html --out dist/raiz/changelog/<version>.html`, edit by hand, and commit with the version bump
    3. CI picks up the override file if it exists, otherwise auto-generates from the changelog

## When You're Done

- Run `make check` to run all tests and validations
- Verify skill/agent changes work with real tests

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
- `make backlog` — Show current priorities (use instead of reading BACKLOG.md directly)
- `.claude/docs/relevant-toolkit-lessons.md` — Lessons ecosystem reference (schema, tiers, tags, CLI, lifecycle)
