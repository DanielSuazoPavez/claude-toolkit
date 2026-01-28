# Memories Index

Memory templates for project context. Customize for your project.

## Essential Memories

Always loaded at session start:

| Memory | Status | Purpose |
|--------|--------|---------|
| `essential-conventions-code_style` | stable | Coding conventions, formatting, style guide |
| `essential-conventions-memory` | stable | Memory naming conventions and categories |
| `essential-preferences-communication_style` | stable | Communication style preferences |
| `essential-workflow-branch_development` | stable | Branch-based development workflow |
| `essential-workflow-task_completion` | stable | Task completion checklist |

## Relevant Memories

| Memory | Status | Purpose |
|--------|--------|---------|
| `relevant-conventions-backlog_schema` | stable | BACKLOG.md schema: priority, categories, status values |
| `relevant-reference-commands` | stable | CLI and Make commands reference |
| `relevant-reference-hooks_config` | beta | Hooks configuration and environment variables |

## Philosophy

| Memory | Status | Purpose |
|--------|--------|---------|
| `relevant-philosophy-reducing_entropy` | alpha | Philosophy on reducing codebase entropy |

## Experimental

| Memory | Status | Purpose |
|--------|--------|---------|
| `experimental-preferences-casual_communication_style` | stable | Casual conversation mode for meta-discussions |

## Memory Categories

### `essential` (Permanent)
- Core, stable project information
- **Format**: `essential-{context}-{descriptive_name}`
- Loaded automatically at session start

### `relevant` (Long-term)
- Important context that may evolve
- **Format**: `relevant-{context}-{descriptive_name}`

### `branch` (Temporary)
- Work-in-progress context for a feature branch
- **Format**: `branch-{YYYYMMDD}-{branch_name}-{context}`
- Delete after branch is merged

### `idea` (Temporary)
- Future implementation ideas
- **Format**: `idea-{YYYYMMDD}-{context}-{plan_idea}`

## Creating Memories

Use `/write-memory` to create properly formatted memories, or manually:

1. Create file in `.claude/memories/`
2. Follow naming convention for category
3. Include Quick Reference section at top:

```markdown
# Memory Title

## Quick Reference

**ONLY READ WHEN:** [specific trigger]

---

[Full content below]
```

## Listing Memories

Use `/list-memories` to see all available memories with their Quick Reference summaries.
