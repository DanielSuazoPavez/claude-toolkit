---
name: manage-lessons
description: Review and manage lesson lifecycle. Use when the user says "manage lessons", "review lessons", "promote lessons", "clean up lessons", "prune lessons", or when session-start nudge suggests it.
allowed-tools: Bash(uv run scripts/lessons/db.py:*), Bash(sqlite3:*), Read, Write
---

# Manage Lessons

Review lessons and work toward crystallization, absorption, and pruning.

**See also:** `/learn` (capture new lessons), `scripts/lessons/db.py` (DB layer and CLI), `session-start.sh` hook (nudges for this skill)

## When to Use

- Session-start nudge suggests it (threshold days elapsed)
- User wants to review accumulated lessons
- Before a project milestone (clean signal for next phase)

## Process

### 1. Health Check

```bash
uv run scripts/lessons/db.py health
```

Review: active count, tier distribution, warnings, time since last run.

### 2. Cluster Detection

```bash
uv run scripts/lessons/db.py clusters
```

Identify lessons orbiting the same themes. Propose crystallization for pairs/groups that express the same underlying pattern.

### 3. Walk Through Clusters

For each cluster, decide with the user:

- **Crystallize** — merge into a single, sharper lesson:
  ```bash
  uv run scripts/lessons/db.py crystallize \
    --ids "ID1,ID2" \
    --text "Crystallized lesson text" \
    --tags "tag1,tag2"
  ```
  Sources are deactivated, new lesson created as `key` tier.

- **Absorb** — the pattern is already enforced by a resource:
  ```bash
  uv run scripts/lessons/db.py absorb --id "ID" --into "hook:git-safety"
  ```
  Lesson deactivated, `absorbed_into` recorded.

- **Skip** — not ready to crystallize yet.

### 4. Walk Through Recent Lessons

```bash
uv run scripts/lessons/db.py list --tier recent --active
```

For each recent lesson, present and ask:

```
Lesson: <text>
  ID: <id> | Date: <date> | Tags: <tags> | Branch: <branch>

  → promote (move to key — validated, eligible for surfacing)
  → absorb (already in a resource — record and deactivate)
  → deactivate (no longer relevant — searchable only)
  → delete (remove entirely)
  → skip (leave as recent)
```

Execute decisions:

**Promote:**
```bash
sqlite3 ~/.claude/lessons.db "UPDATE lessons SET tier='key', promoted='$(date +%Y-%m-%d)' WHERE id='<ID>';"
```

**Deactivate:**
```bash
sqlite3 ~/.claude/lessons.db "UPDATE lessons SET active=0 WHERE id='<ID>';"
```

**Delete:**
```bash
sqlite3 ~/.claude/lessons.db "DELETE FROM lessons WHERE id='<ID>';"
```

Wait for user decision on each one. Don't batch.

### 5. Tag Hygiene

```bash
uv run scripts/lessons/db.py tag-hygiene
```

Address reported issues:
- Orphaned tags → delete or add lessons
- Tags without keywords → add keywords so hooks can surface them
- Deprecated tags still in use → migrate lessons to canonical tag

### 6. Record Completion

```bash
uv run scripts/lessons/db.py set-meta last_manage_run "$(date -Iseconds)"
```

Show final state:

```bash
uv run scripts/lessons/db.py health
```

## Crystallization Guide

Crystallization isn't just "merge 3 lessons into 1." The end state of a mature pattern is that it **leaves the lessons system** and becomes a toolkit resource.

```
raw lessons → crystallized lesson → absorbed into resource → deactivated
```

| Signal | Action |
|--------|--------|
| 3+ lessons circling same theme | Crystallize into one sharper lesson |
| Lesson matches an existing hook/skill | Absorb — record and deactivate |
| Lesson is specific to a closed branch | Deactivate unless pattern is general |
| Lesson has been key for 30+ days | Check: still needed, or absorbed? |

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Promoting everything | Defeats the tier system | Only promote lessons that apply broadly |
| Skipping all | Accumulates noise | At minimum, address clusters |
| Deleting without reading | Losing valuable signal | Read each lesson before deciding |
| Ignoring tag hygiene | Tags lose surfacing value | Clean up keywords and orphans |
