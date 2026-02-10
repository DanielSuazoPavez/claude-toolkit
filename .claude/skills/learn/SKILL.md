---
name: learn
description: Capture a lesson from this session. Use when the user says "remember this", "learn this", "save this lesson", "don't forget", "note this for next time", "keep this in mind", or asks to capture a correction, pattern, convention, or gotcha.
---

# Learn

Capture a lesson from the current session to avoid repeating mistakes in future sessions.

## When to Use

- User explicitly asks to remember/save something
- After a correction that should persist across sessions
- When a project-specific pattern or gotcha is discovered

## When NOT to Use

- Trivial corrections (typos, wrong variable name in a one-off)
- Things already documented in CLAUDE.md or memories
- General knowledge (not project-specific)

## Process

1. **Identify the lesson** — what was wrong, what's the correct behavior?
2. **Pick category**: `correction` | `pattern` | `convention` | `gotcha`
3. **Check for duplicates** — read `learned.json` if it exists, skip if already captured
4. **Format as one-line actionable rule** — specific, not vague
5. **Present to user** for approval, modification, or rejection
6. **On approval**, write to `learned.json` via jq

### Formatting the Proposal

Present the lesson like this:

```
Proposed lesson:
- Category: <category>
- Lesson: <one-line actionable rule>

Save this lesson? (approve / modify / reject)
```

### Writing to learned.json

Initialize if missing:

```bash
[ ! -f learned.json ] && echo '{"recent":[],"key":[]}' > learned.json
```

Append to `recent` array:

```bash
jq --arg date "$(date +%Y-%m-%d)" \
   --arg cat "<category>" \
   --arg text "<lesson text>" \
   --arg branch "$(git branch --show-current 2>/dev/null || echo 'unknown')" \
   --arg project "$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")" \
   '.recent += [{"date": $date, "category": $cat, "text": $text, "branch": $branch, "project": $project}]' \
   learned.json > learned.json.tmp && mv learned.json.tmp learned.json
```

## Lesson Quality Heuristic

> Would this help a future session avoid repeating the same mistake? If yes → save. If no → skip.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Lesson inflation | Saving trivial corrections | Only save lessons that apply to future sessions |
| Vague lessons | "Be more careful with imports" | Specific: "Use absolute imports in the `api/` package" |
| Duplicates | Same lesson saved twice | Check `learned.json` before proposing |
| Category confusion | Everything is `correction` | Match category to what happened |

## Categories

| Category | When to Use |
|----------|-------------|
| `correction` | Claude did something wrong, user corrected it |
| `pattern` | Recurring approach or idiom in this project |
| `convention` | Project-specific naming, structure, or style rule |
| `gotcha` | Non-obvious behavior, surprising edge case, or trap |
