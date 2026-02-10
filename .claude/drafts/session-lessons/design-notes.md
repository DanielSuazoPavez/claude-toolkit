# session-lessons — Design Notes

## Goal

Frictionless learning capture across sessions. Minimal prototype to observe what we actually get — knowledge or noise. Start JSON flat file, graduate to SQLite only if volume/search demands it.

## Core Question

"Are the lessons we capture valuable or just noise?" — we need data to answer this. Ship the capture mechanism, analyze later.

## Architecture: Prototype (JSON File)

### Components

1. **`Stop` hook** — scans Claude's response for `[LEARN]` tags, appends to `learned.json`
2. **`session-start.sh` addition** — surfaces recent learnings at session start
3. **`learned.json`** — per-project JSON file, two-layer structure

### Two-Layer Structure

```json
{
  "recent": [
    {
      "date": "2026-02-10",
      "category": "correction",
      "text": "Always use pl.LazyFrame for files over 100MB — eager mode OOMs on staging",
      "branch": "feature/data-pipeline"
    }
  ],
  "key": [
    {
      "date": "2026-02-08",
      "category": "pattern",
      "text": "Auth middleware goes in src/middleware/auth.py, not in route files",
      "promoted": "2026-02-10"
    }
  ]
}
```

- **`recent`** — raw capture, append-only. Auto-surfaced at session start. Pruned regularly.
- **`key`** — curated, promoted from recent after review. Persistent until absorbed into a memory/skill/convention and removed.

### Lifecycle

```
Capture → Recent → Review → Promote or Delete
                              ↓
                          Key Learnings → Absorb into memory/skill/convention → Remove
```

### Capture Flow

```
Claude responds with [LEARN] tag
    → Stop hook fires
    → Parses tag: [LEARN] category: Lesson text
    → Appends entry to learned.json .recent array
    → Next session: session-start.sh reads recent + key entries via jq
```

### `[LEARN]` Tag Format

```
[LEARN] category: One-line lesson
```

Categories (start simple, expand if patterns emerge):
- `correction` — mistake I made and the fix
- `pattern` — project-specific pattern discovered
- `convention` — implicit convention made explicit
- `gotcha` — non-obvious behavior or edge case

### Stop Hook Design

```
Trigger: Stop
Behavior:
  1. Read Claude's response from hook input
  2. Grep for lines matching [LEARN]
  3. If found, parse category + text
  4. Read existing learned.json (or initialize empty structure)
  5. Append new entry to .recent with date and current branch
  6. Write back via jq
  7. Exit 0 (non-blocking, never fails the response)
```

Key constraints:
- **Silent** — no output to stdout (would appear as hook feedback)
- **Fast** — pure bash + jq, no heavy dependencies
- **Append-only** — never modifies existing entries during capture
- **Safe writes** — write to temp file, then mv (atomic)

### Session-Start Addition

Add to existing `session-start.sh`:

```bash
# === LESSONS ===
LEARNED_FILE="learned.json"
if [ -f "$LEARNED_FILE" ]; then
    KEY_LESSONS=$(jq -r '.key[]? | "- [\(.category)] \(.text)"' "$LEARNED_FILE" 2>/dev/null)
    RECENT_LESSONS=$(jq -r '.recent[-5:][]? | "- [\(.category)] \(.text)"' "$LEARNED_FILE" 2>/dev/null)
    if [ -n "$KEY_LESSONS" ] || [ -n "$RECENT_LESSONS" ]; then
        echo "=== LESSONS ==="
        [ -n "$KEY_LESSONS" ] && echo "Key:" && echo "$KEY_LESSONS"
        [ -n "$RECENT_LESSONS" ] && echo "Recent:" && echo "$RECENT_LESSONS"
        echo ""
    fi
fi
```

### Querying (jq examples)

```bash
# All corrections
jq '.recent[] | select(.category == "correction")' learned.json

# Lessons from a specific branch
jq '.recent[] | select(.branch == "feature/data-pipeline")' learned.json

# Count by category
jq '[.recent[].category] | group_by(.) | map({(.[0]): length}) | add' learned.json

# Key learnings only
jq '.key[]' learned.json
```

### Pruning / Promoting

Manual for now (via jq or a future `/lessons` skill):

```bash
# Promote entry at index 3 from recent to key
jq '.key += [.recent[3] + {promoted: "2026-02-10"}] | .recent |= del(.[3])' learned.json

# Clear all recent entries older than 7 days
jq --arg cutoff "2026-02-03" '.recent |= map(select(.date >= $cutoff))' learned.json
```

## Analysis Phase (Post-Prototype)

After running across projects for a few weeks:

1. **Collect** learned.json files from deployed projects
2. **Categorize** — what percentage is transferable vs project-specific?
3. **Pattern detection** — are there repeated corrections? → signal skill/convention gaps
4. **Signal-to-noise** — what percentage of entries survive pruning?
5. **Decide** — JSON sufficient, or graduate to SQLite + FTS5?

### Signals That Warrant SQLite Upgrade
- More than ~50 entries per project
- Need to search across projects
- FTS5 full-text search would actually get used

### Signals That JSON Is Enough
- Entries stay under ~30 per project
- jq is sufficient for querying
- Most value comes from key learnings + last few recent entries

## What This Is NOT

- Not a session handoff mechanism (that's `write-handoff`)
- Not a memory system replacement (memories are curated, lessons are raw capture)
- Not permanent storage — recent entries get pruned, key entries get absorbed upstream

## Promotion Path

Valuable lessons get promoted through layers:
1. `recent` → `key` (survives pruning, worth remembering)
2. `key` → toolkit memory or skill improvement (transferable patterns)
3. `key` → project CLAUDE.md or memory (project conventions)
4. Repeated corrections → signal to fix the source (skill, convention, or habit)

## Open Questions

- Should the hook also capture from `[CORRECTION]` tags (explicit self-corrections)?
- How many recent lessons to surface at session start? 5? All?
- Should there be a `/lessons` skill for managing entries (prune, promote, search)? Or just jq one-liners?
- Should `learned.json` be gitignored or committed? (project-specific learnings might be useful for team, but also noisy)
