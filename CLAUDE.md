# CLAUDE.md

## Project Overview

Claude Toolkit - curated Claude Code configuration with skills, agents, hooks, and memory templates.

## Quick Start

```bash
claude-toolkit sync /path/to/project  # Sync config into a project
```

## Key Principles

1. **Read before modifying**: Understand existing skills/agents before changes
2. **Test skills**: After modifying a skill, test it with a real invocation
3. **Follow conventions**: Use existing patterns from similar skills/agents
4. **Merge with --no-ff**: Always use `git merge --no-ff` to preserve branch history

## Structure

```
.claude/
├── skills/     # User-invocable skills (/skill-name)
├── agents/     # Specialized task agents
├── hooks/      # Automation hooks
├── memories/   # Memory templates
├── indexes/    # Resource indexes and evaluation scores
└── output/     # Generated artifacts (analysis, reviews, sessions, etc.)
```

## Resource Indexes

Summary and status of all resources:

- `.claude/indexes/SKILLS.md` - All skills with status and descriptions
- `.claude/indexes/AGENTS.md` - All agents with status, descriptions, and tools
- `.claude/indexes/HOOKS.md` - All hooks with triggers and configuration
- `.claude/indexes/MEMORIES.md` - All memories with categories and purposes
- `.claude/indexes/evaluations.json` - Quality scores, grades, and improvement suggestions

## Changelog

- Docs-only changes (backlog, design docs, exploration): `[Unreleased]` section, no version bump
- Code/resource changes: version bump + changelog entry under version

## When You're Done

- Run `make check` to run all tests and validations
- Verify skill/agent changes work with real tests

## Suggestions Box

`suggestions-box/` — inbox for resources and issues sent from other projects via `claude-toolkit send`. Organized by source project. Triage with "check suggestions" — see `suggestions-box/CLAUDE.md` for the full workflow.

## See Also

- `README.md` - Full documentation
- `.claude/memories/` - Memory templates
