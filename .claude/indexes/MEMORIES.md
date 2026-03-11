# Memories Index

Memory templates for project context. Customize for your project.

## Essential Memories

Always loaded at session start:

| Memory | Status | Purpose |
|--------|--------|---------|
| `essential-conventions-code_style` | stable | Coding conventions, formatting, style guide |
| `essential-conventions-memory` | stable | Memory naming conventions and categories |
| `essential-preferences-communication_style` | stable | Communication style preferences |
| `essential-toolkit-identity` | stable | What the toolkit is, resource roles, decision checklist |

## Relevant Memories

| Memory | Status | Purpose |
|--------|--------|---------|
| `relevant-conventions-backlog_schema` | stable | BACKLOG.md schema: priority, categories, status values |
| `relevant-workflow-branch_development` | stable | Branch-based development workflow |
| `relevant-workflow-task_completion` | stable | Task completion checklist |
| `relevant-reference-hooks_config` | stable | Hooks configuration and environment variables |
| `relevant-toolkit-resource_frontmatter` | stable | Supported frontmatter fields for skills and agents |
| `relevant-conventions-testing` | stable | Test structure, runners, and conventions |

## Philosophy

| Memory | Status | Purpose |
|--------|--------|---------|
| `relevant-philosophy-reducing_entropy` | stable | Philosophy on reducing codebase entropy |

## Personal

| Memory | Status | Purpose |
|--------|--------|---------|
| `personal-preferences-casual_communication_style` | stable | Casual conversation mode for meta-discussions |
| `personal-context-user` | stable | Personal context (cats, board games, Chilean game scene, misc preferences) |

## Memory Categories

See `essential-conventions-memory` for full category definitions, naming conventions, and Quick Reference patterns.

## Creating Memories

Use `/create-memory` to create properly formatted memories, or manually:

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
