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

## Decision: Not Adopting (2026-03-08)

**Conclusion**: Rules don't add value over our current setup. Not adopting.

**Key insight**: Rules are just CLAUDE.md files with extra organization:
- **Unconditional rules** = our essential memories synced via hook (same effect, already working)
- **Path-scoped rules** = subfolder CLAUDE.md files (same on-demand loading, different location)
- The only difference is organizational — centralized in `.claude/rules/` vs distributed

**Why our approach is better for our use case**:
- Our memory system has categorized lifecycle (`essential`/`relevant`/`branch`/`idea`) — rules have no equivalent
- Hook-based loading gives selective, on-demand context — unconditional rules bloat context at startup
- We already sync essential memories to target projects, which is equivalent to syncing rules
- Migration would be trivial but provides no functional benefit

**If revisiting**: Migration is trivial — our memories map directly to rules files. Revisit only if Anthropic adds capabilities to rules that memories can't replicate (e.g., native conditional loading logic, priority ordering).
