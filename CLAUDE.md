# CLAUDE.md

## Project Overview

Claude Toolkit - curated Claude Code configuration with skills, agents, hooks, and memory templates.

## Quick Start

```bash
./install.sh /path/to/project  # Install into a project
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
└── memories/   # Memory templates
```

## Resource Indexes

Summary and status of all resources:

- `.claude/SKILLS.md` - All skills with status and descriptions
- `.claude/AGENTS.md` - All agents with status, descriptions, and tools
- `.claude/HOOKS.md` - All hooks with triggers and configuration
- `.claude/MEMORIES.md` - All memories with categories and purposes
- `.claude/evaluations.json` - Quality scores, grades, and improvement suggestions

## When You're Done

- Run `scripts/validate-resources-indexed.sh` to check all resources are indexed
- Verify skill/agent changes work with real tests

## See Also

- `README.md` - Full documentation
- `.claude/memories/` - Memory templates
