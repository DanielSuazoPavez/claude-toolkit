# Claude Code Rules (.claude/rules/)

Source: https://code.claude.com/docs/en/memory

## What They Are

Modular, topic-specific instruction files. Alternative to putting everything in CLAUDE.md.

## How They Work

- Markdown files in `.claude/rules/` (supports subdirectories recursively)
- Loaded automatically as project memory, **same priority as CLAUDE.md**
- Supports YAML frontmatter with `paths` field for path-scoping
- Rules without `paths` are unconditional (apply globally)

## Path-Specific Rules (the unique part)

```markdown
---
paths:
  - "src/api/**/*.ts"
---
# API Development Rules
Always validate input parameters...
```

Only activates when Claude works with files matching those globs. Supports:
- `**/*.ts` — all TS files anywhere
- `src/**/*` — all files in src/
- `src/**/*.{ts,tsx}` — brace expansion
- `{src,lib}/**/*.ts` — multiple directories

## User-Level Rules

- `~/.claude/rules/` for personal rules across all projects
- Loaded before project rules (project rules override on conflict)

## Best Practices (official docs)

- One topic per file (`testing.md`, `api-design.md`, `security.md`)
- Descriptive filenames
- Use `paths` sparingly — only when rules truly apply to specific file types
- Subdirectories for grouping (`frontend/`, `backend/`)

## Comparison to Our Setup

| | CLAUDE.md | Rules | Our Memories |
|---|---|---|---|
| Loading | Always at startup | Always (unconditional) or on file interaction (path-scoped) | On-demand via hook/manual |
| Scope | Single file, project-wide | Modular files, optionally path-scoped | Modular files, manually loaded |
| Priority | Same | Same as CLAUDE.md | Injected into context |
| Path-awareness | No | Yes (glob frontmatter) | No |

## Why It's Interesting

Path-scoping is the differentiator. Rules that only fire when touching certain files — neither CLAUDE.md nor memories do this. Could replace some of our conditional memory loading with automatic, file-aware activation.
