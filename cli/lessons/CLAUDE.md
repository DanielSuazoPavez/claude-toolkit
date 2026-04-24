# cli/lessons/

SQLite-backed lessons store and CLI (`claude-toolkit lessons`) for managing cross-project actionable rules. Schema ownership lives in claude-sessions (`schemas/lessons.yaml`); this module keeps a byte-compatible `INIT_SQL` for runtime bootstrap and provides the CRUD + lifecycle commands.

## Lifecycle Commands

Commands are grouped by lifecycle stage.

| Stage | Command | Purpose |
|-------|---------|---------|
| capture | `add` | Insert a new lesson (auto-infers domain tags from text) |
| capture | `migrate` | Import from legacy `.claude/learned.json` |
| inspect | `get <id>` | Full detail for a single lesson |
| inspect | `list` | Filter by tier, active, tags, project, scope |
| inspect | `search <query>` | FTS5 full-text search over lesson text |
| inspect | `summary` | Counts by tier and tag |
| inspect | `health` | Health report with warnings |
| cluster/merge | `clusters` | Find lessons sharing 2+ tags (crystallization candidates) |
| cluster/merge | `crystallize` | Merge source lessons into one `key`-tier lesson; sources deactivated |
| cluster/merge | `absorb` | Mark a lesson as absorbed into a resource (hook/skill); deactivates |
| promote/retire | `promote --id <ID>` | Move a lesson to `key` tier (sets `promoted=today`) |
| promote/retire | `deactivate --id <ID>` | Clear `active` flag — lesson is searchable but not surfaced |
| maintain | `tags` | Tag registry with counts and status |
| maintain | `tag-hygiene` | Report orphaned tags, missing keywords, deprecated-in-use |
| maintain | `set-meta KEY VALUE` | Upsert a metadata key-value (e.g., `last_manage_run`) |

Deletions are intentionally **not** exposed as a CLI subcommand — real deletions happen outside the lifecycle surface.

## DB Path

Default: `~/.claude/lessons.db` (global, not per-project).

Override via env var: `CLAUDE_ANALYTICS_LESSONS_DB=/path/to/lessons.db` (picked up at module import in `db.py:37`).

Or per-invocation: `claude-toolkit lessons --db /path/to/lessons.db <subcommand>`.

## See Also

- `.claude/skills/manage-lessons/SKILL.md` — interactive lifecycle driver (routes all lifecycle ops through this CLI)
- `.claude/docs/relevant-toolkit-lessons.md` — ecosystem reference (tiers, tags, schema)
- `cli/CLAUDE.md` — parent CLI overview and wiring
