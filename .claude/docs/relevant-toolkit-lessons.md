# Lessons Ecosystem Reference

## 1. Quick Reference

**ONLY READ WHEN:**
- Working with lessons (creating, managing, surfacing)
- Debugging lesson-related hooks or CLI commands
- Understanding lesson lifecycle or schema

Reference for the lessons system: database schema, tiers, tags, skills, hooks, CLI, and lifecycle.

**Opt-in:** The lessons ecosystem is opt-in per project via `CLAUDE_TOOLKIT_LESSONS` in the `env` block of `.claude/settings.json` (`"1"` to enable, `"0"` or absent to disable). Disabled means `session-start.sh` skips the lessons block and ack count, and `surface-lessons.sh` skips injection (context logging still runs, gated separately by `CLAUDE_TOOLKIT_TRACEABILITY`). `lessons.db` always lives globally at `~/.claude/lessons.db` — the flag gates *reading from it* in hooks, not its existence. CLI (`claude-toolkit lessons`) and skills (`/learn`, `/manage-lessons`) are not gated — they operate on the db regardless.

**See also:** `/learn` skill, `/manage-lessons` skill, `relevant-toolkit-hooks_config` for hook triggers and the full env block schema

---

## 2. Architecture Overview

Lessons are actionable rules captured during sessions and surfaced contextually in future sessions. The system has four integration points:

| Component | Role |
|-----------|------|
| `claude-toolkit lessons` CLI | CRUD operations on `lessons.db` |
| `/learn` skill | Captures new lessons during sessions |
| `/manage-lessons` skill | Curates lessons (promote, crystallize, absorb, deactivate) |
| `session-start.sh` hook | Surfaces key + recent lessons at session start |
| `surface-lessons.sh` hook | Injects relevant lessons just-in-time on tool use |

---

## 3. Database

**Location:** `~/.claude/lessons.db` (global, shared across projects)

**Engine:** SQLite with WAL mode and foreign keys enabled.

### Schema

```
projects          1──∞  lessons  ∞──∞  tags
                              │              (via lesson_tags)
                              │
                        lessons_fts    (FTS5 virtual table, trigger-synced)

metadata          key-value store for system state
```

**Core tables:**

| Table | Key columns | Notes |
|-------|-------------|-------|
| `projects` | `id`, `name` | Auto-ID, unique name |
| `tags` | `name`, `status`, `keywords`, `lesson_count` | Status: active / deprecated / merged |
| `lessons` | `id`, `tier`, `active`, `scope`, `text`, `branch` | ID format: `{project}_{YYYYMMDD}T{HHMM}_{NNN}` |
| `lesson_tags` | `lesson_id`, `tag_id` | Many-to-many junction |
| `metadata` | `key`, `value` | Tracks `last_manage_run`, `nudge_threshold_days` |
| `lessons_fts` | `text` | FTS5 with `unicode61 tokenchars '-_./~'` |

**Scope column on `lessons`:** `scope` — `global` (default, surfaces in all projects) or `project` (only surfaces in the originating project). Hooks filter by scope + project name.

**Lifecycle columns on `lessons`:** `crystallized_from`, `absorbed_into`, `promoted`, `archived` — track lineage as lessons mature.

---

## 4. Tiers

Lessons progress through tiers as they're validated:

```
recent  →  key  →  historical (or absorbed/deactivated)
```

| Tier | Meaning | Surfacing |
|------|---------|-----------|
| `recent` | Newly captured, unvalidated | Last 5 shown at session start |
| `key` | Promoted, validated | All shown at session start (with tags) |
| `historical` | Archived, searchable only | Not surfaced automatically |

---

## 5. Tags

Two kinds of tags, assigned when a lesson is created:

**Category tags** (exactly one per lesson):

| Tag | When to use |
|-----|-------------|
| `correction` | Claude did something wrong, user corrected |
| `pattern` | Recurring approach or idiom |
| `convention` | Project-specific rule |
| `gotcha` | Non-obvious behavior or edge case |

**Domain tags** (zero or more, inferred from lesson text keywords):

`git`, `hooks`, `skills`, `docs`, `permissions`, `resources`, `testing`

**Special tag:** `recurring` — added when a near-duplicate exists, signals reinforcement.

Tags have a `keywords` field used by `surface-lessons.sh` to match tool context against lessons. Tag status can be `active`, `deprecated`, or `merged`.

---

## 6. Skills

### `/learn` — Capture a lesson

1. Searches for duplicates via FTS (`claude-toolkit lessons search`)
2. Infers category + domain tags
3. Presents proposal to user for confirmation
4. Writes to `lessons.db` via `claude-toolkit lessons add`

Bias: toward capturing. Dedup happens later via `/manage-lessons`.

### `/manage-lessons` — Curate lessons

Runs periodically (nudged after 7 days). Steps:

1. **Health check** — `claude-toolkit lessons health`
2. **Cluster detection** — `claude-toolkit lessons clusters` (lessons sharing 2+ tags)
3. **Walk clusters** — crystallize, absorb, or skip
4. **Walk recent lessons** — promote, absorb, deactivate, or delete
5. **Tag hygiene** — `claude-toolkit lessons tag-hygiene`
6. **Record completion** — sets `last_manage_run` metadata

**Crystallize:** merge 2+ related lessons into one sharper `key`-tier lesson; sources deactivated.

**Absorb:** lesson already enforced by a resource (hook, doc, etc.); lesson deactivated with `absorbed_into` recorded.

---

## 7. Hooks

### `session-start.sh` (SessionStart)

Loads lessons at session start in a single SQL query with row-prefix disambiguation:

- `K` — key-tier lessons (with tags)
- `R` — recent-tier lessons (last 5)
- `B` — branch-specific lessons
- `M` — days since last `/manage-lessons` run
- `T` — nudge threshold (default: 7 days)
- `C` — active lesson count

**Output format:**
```
=== LESSONS ===
Key:
- [gotcha,git] Don't force-push to shared branches
Recent:
- Use pathlib over os.path
This branch:
- Branch-specific lesson text
```

**Scope filtering:** Both hooks filter by `scope` — project-scoped lessons only surface when the current project name matches. Global lessons surface everywhere.

**Nudge logic:** suggests `/manage-lessons` if threshold exceeded or never run.

**Legacy fallback:** if `lessons.db` missing but `.claude/learned.json` exists, displays migration alert.

### `surface-lessons.sh` (PreToolUse)

Fires on `Bash|Read|Write|Edit` tool calls. Extracts keywords from command/file path, matches against `tags.keywords`, injects up to 3 matching active lessons as `additionalContext`.

- Pure bash + sqlite3, ~10ms
- Basic plural handling (strips trailing 's')
- Skips words shorter than 3 characters
- Logs keyword matches to `surface-lessons.jsonl` (`kind: context` rows)

---

## 8. CLI Commands

Entry point: `claude-toolkit lessons` (dispatches to `ct-lessons` Python script).

```bash
# CRUD
claude-toolkit lessons add --text "lesson" --tags "gotcha,git" [--scope project]
claude-toolkit lessons search "keyword" [--limit N]
claude-toolkit lessons list [--tier recent|key|historical] [--active] [--tags t1,t2] [--project P] [--scope global|project]
claude-toolkit lessons summary

# Management
claude-toolkit lessons crystallize --ids "ID1,ID2" --text "merged text" --tags "tag1,tag2"
claude-toolkit lessons absorb --id "ID" --into "hook:git-safety"
claude-toolkit lessons tags
claude-toolkit lessons clusters [--min-shared N]
claude-toolkit lessons tag-hygiene
claude-toolkit lessons health

# System
claude-toolkit lessons migrate [--json-path PATH]   # Import from learned.json
claude-toolkit lessons set-meta KEY VALUE

# Global option
claude-toolkit lessons --db PATH ...                 # Override database path
```

---

## 9. Backup

Script: `.claude/scripts/cron/backup-lessons-db.sh`

- Copies `lessons.db` to `~/backups/claude-lessons/lessons_YYYYMMDD_HHMMSS.db`
- 30-day retention with auto-prune
- Intended as hourly cron: `30 * * * * /path/to/backup-lessons-db.sh`

---

## 10. Lifecycle Summary

```
capture (/learn)
    ↓
recent tier (unvalidated, surfaced at start)
    ↓
/manage-lessons
    ├── promote → key tier (validated, always surfaced)
    ├── crystallize → new key lesson (sources deactivated)
    ├── absorb → deactivated (enforced by resource)
    ├── deactivate → historical (searchable only)
    └── delete → removed
```
