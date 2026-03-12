---
name: learn
description: Capture a lesson from this session. Use when the user says "remember this", "learn this", "save this lesson", "don't forget", "note this for next time", "keep this in mind", or asks to capture a correction, pattern, convention, or gotcha.
---

# Learn

Capture a lesson from the current session. Lightweight — identify, format, write.

## When to Use

- User explicitly asks to remember/save something
- After a correction that should persist across sessions
- When a project-specific pattern or gotcha is discovered

## When NOT to Use

- Trivial corrections (typos, wrong variable name in a one-off)
- Things already documented in CLAUDE.md or memories
- General knowledge (not project-specific)

## Process

1. **Read** `.claude/learned.json` — check for duplicates and detect recurring patterns
2. **Infer** category and draft one-line lesson text
3. **Present** the proposed lesson (category + text) — write unless user objects
4. **Write** to `.claude/learned.json` with full metadata

No evaluation rubrics, no multi-round iteration. Propose → write.

### Duplicate & Recurring Detection

Before writing, check existing lessons:
- If an existing lesson says essentially the same thing → **skip**, tell the user it already exists
- If a similar lesson exists (same topic, different angle) → **write** with `recurring` flag auto-set

### Categories

| Category | When to Use |
|----------|-------------|
| `correction` | Claude did something wrong, user corrected it |
| `pattern` | Recurring approach or idiom in this project |
| `convention` | Project-specific naming, structure, or style rule |
| `gotcha` | Non-obvious behavior, surprising edge case, or trap |

### Presenting the Proposal

```
Proposed lesson:
- Category: <category>
- Lesson: <one-line actionable rule>
```

Then write immediately unless the user objects or asks for changes.

### Writing to .claude/learned.json

**Schema reference**: `.claude/schemas/lesson.schema.json`

Initialize if missing:

```bash
[ ! -f .claude/learned.json ] && echo '{"lessons":[]}' > .claude/learned.json
```

Generate the ID — format `{project}_{YYYYMMDD}T{HHMM}_{NNN}`:

```bash
PROJECT="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
TIMESTAMP="$(date +%Y%m%dT%H%M)"
PREFIX="${PROJECT}_${TIMESTAMP}"
# Find next sequential suffix for this prefix
EXISTING=$(jq -r --arg p "$PREFIX" '.lessons[].id | select(startswith($p))' .claude/learned.json 2>/dev/null | wc -l)
NNN=$(printf "%03d" $((EXISTING + 1)))
ID="${PREFIX}_${NNN}"
```

Append the lesson:

```bash
jq --arg id "$ID" \
   --arg date "$(date +%Y-%m-%d)" \
   --arg cat "<category>" \
   --arg text "<lesson text>" \
   --arg branch "$(git branch --show-current 2>/dev/null || echo 'unknown')" \
   --arg project "$PROJECT" \
   '.lessons += [{"id": $id, "date": $date, "category": $cat, "flags": [], "tier": "recent", "text": $text, "branch": $branch, "project": $project, "promoted": null, "archived": null}]' \
   .claude/learned.json > .claude/learned.json.tmp && mv .claude/learned.json.tmp .claude/learned.json
```

If duplicate detection flagged `recurring`, add the flag:

```bash
jq --arg id "$ID" \
   '.lessons |= map(if .id == $id then .flags += ["recurring"] | .flags |= unique else . end)' \
   .claude/learned.json > .claude/learned.json.tmp && mv .claude/learned.json.tmp .claude/learned.json
```

## Quality Heuristic

> Would this help a future session avoid repeating the same mistake? If yes → save. If no → skip.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Lesson inflation | Saving trivial corrections | Only save lessons that apply to future sessions |
| Vague lessons | "Be more careful with imports" | Specific: "Use absolute imports in the `api/` package" |
| Duplicates | Same lesson saved twice | Check existing lessons before proposing |
| Category confusion | Everything is `correction` | Match category to what happened |
