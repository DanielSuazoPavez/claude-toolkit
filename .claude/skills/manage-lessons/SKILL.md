---
name: manage-lessons
description: Review and manage lesson lifecycle. Use when the user says "manage lessons", "review lessons", "promote lessons", "clean up lessons", "prune lessons", or when session-start nudge suggests it.
---

# Manage Lessons

Review `recent` lessons and decide their fate: promote, archive, delete, or flag.

## When to Use

- Session-start nudge suggests it (10+ recent, recurring flags)
- User wants to review accumulated lessons
- Before a project milestone (clean signal for next phase)

## Process

### 1. List Current State

Run the summary first:

```bash
.claude/scripts/lessons-query.sh summary
```

Then list recent lessons:

```bash
.claude/scripts/lessons-query.sh tier recent
```

### 2. Walk Through Each Lesson

For each `recent` lesson, present it and ask the user to decide:

```
Lesson: [category] <text>
  ID: <id> | Date: <date> | Branch: <branch>

  → promote (move to key — always loaded)
  → archive (move to historical — searchable only)
  → delete (remove entirely)
  → flag recurring (mark as repeat offender)
  → skip (leave as recent)
```

Wait for user decision on each one. Don't batch — each lesson deserves individual consideration.

### 3. Execute Decisions

**Promote** — set tier to `key`, record promoted date:

```bash
jq --arg id "<ID>" --arg date "$(date +%Y-%m-%d)" \
   '.lessons |= map(if .id == $id then .tier = "key" | .promoted = $date else . end)' \
   .claude/learned.json > .claude/learned.json.tmp && mv .claude/learned.json.tmp .claude/learned.json
```

**Archive** — set tier to `historical`, record archived date:

```bash
jq --arg id "<ID>" --arg date "$(date +%Y-%m-%d)" \
   '.lessons |= map(if .id == $id then .tier = "historical" | .archived = $date else . end)' \
   .claude/learned.json > .claude/learned.json.tmp && mv .claude/learned.json.tmp .claude/learned.json
```

**Delete** — remove the entry:

```bash
jq --arg id "<ID>" \
   '.lessons |= map(select(.id != $id))' \
   .claude/learned.json > .claude/learned.json.tmp && mv .claude/learned.json.tmp .claude/learned.json
```

**Flag recurring** — add the recurring flag:

```bash
jq --arg id "<ID>" \
   '.lessons |= map(if .id == $id then .flags += ["recurring"] | .flags |= unique else . end)' \
   .claude/learned.json > .claude/learned.json.tmp && mv .claude/learned.json.tmp .claude/learned.json
```

### 4. Show Final State

After all decisions are made, show the updated summary:

```bash
.claude/scripts/lessons-query.sh summary
```

## Key Lessons Can Be Absorbed

If a `key` lesson has been fully absorbed into a memory, skill, or CLAUDE.md convention, it can be archived or deleted. Mention this when reviewing `key` lessons.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Promoting everything | Defeats the tier system | Only promote lessons that apply broadly and repeatedly |
| Deleting without reading | Losing potentially valuable signal | Read each lesson before deciding |
| Skipping all | Accumulates noise | At minimum, flag obvious recurring ones |
