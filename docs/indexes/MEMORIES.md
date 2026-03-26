# Memories Index

Organic context — project identity, user preferences, ideas. Loaded on-demand.

See also: `docs/indexes/DOCS.md` for reference documentation (rules, conventions, configs).

## Relevant Memories

| Memory | Status | Purpose |
|--------|--------|---------|
| `relevant-context-professional_profile` | stable | Data engineering role, stack, tools, and current trajectory |

## Memory Categories

See `relevant-toolkit-context` (in `.claude/docs/`) for full category definitions, naming conventions, and the docs/memories boundary.

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
