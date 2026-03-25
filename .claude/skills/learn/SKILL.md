---
name: learn
description: Capture a lesson from this session. Use when the user says "remember this", "learn this", "save this lesson", "don't forget", "note this for next time", "keep this in mind", or asks to capture a correction, pattern, convention, or gotcha.
argument-hint: "[topic-hint]"
allowed-tools: Read, Bash(claude-toolkit lessons:*), Bash(sqlite3:*)
---

# Learn

Capture a lesson from the current session. Lightweight — identify, format, write.

**See also:** `/manage-lessons` (lifecycle: promote, archive, crystallize after capture), `claude-toolkit lessons` (CLI), `session-start.sh` hook (nudges for manage-lessons)

## When to Use

- User explicitly asks to remember/save something
- After a correction that should persist across sessions
- When a project-specific pattern or gotcha is discovered

## When NOT to Use

- Trivial corrections (typos, wrong variable name in a one-off)
- Things already documented in CLAUDE.md or memories
- General knowledge (not project-specific)

## Process

1. **Search** for duplicates — check existing lessons via FTS
2. **Infer** tags and draft one-line lesson text
3. **Present** the proposed lesson (tags + text) — write unless user objects
4. **Write** to lessons.db with full metadata

No evaluation rubrics, no multi-round iteration. Propose → write.

### Duplicate & Recurring Detection

Before writing, search existing lessons:

```bash
claude-toolkit lessons search "<key phrase from lesson>" --limit 5
```

- If an existing lesson says essentially the same thing → **skip**, tell the user it already exists
- If a similar lesson exists (same topic, different angle) → **write** and add the `recurring` tag

### Tags

Tags replace the old fixed categories. Assign one category-equivalent tag plus any relevant domain tags:

**Category-equivalent tags** (pick one):

| Tag | When to Use |
|-----|-------------|
| `correction` | Claude did something wrong, user corrected it |
| `pattern` | Recurring approach or idiom in this project |
| `convention` | Project-specific naming, structure, or style rule |
| `gotcha` | Non-obvious behavior, surprising edge case, or trap |

**Domain tags** (add as relevant): `git`, `hooks`, `skills`, `memories`, `permissions`, `resources`, `testing`

### Presenting the Proposal

```
Proposed lesson:
- Tags: <category-tag>, <domain-tag1>, <domain-tag2>
- Lesson: <one-line actionable rule>
```

Then write immediately unless the user objects or asks for changes.

### Writing to lessons.db

The `add` subcommand handles ID generation, project/branch detection, and domain tag inference:

```bash
claude-toolkit lessons add \
  --text "<lesson text>" \
  --tags "<category-tag>,<extra-tag1>,<extra-tag2>"
```

The command auto-detects project name and git branch, generates a unique ID, and infers additional domain tags from the lesson text.

If duplicate detection flagged `recurring`, include it in tags:

```bash
claude-toolkit lessons add \
  --text "<lesson text>" \
  --tags "<category-tag>,recurring,<extra-tags>"
```

## Quality Heuristic

> Would this help a future session avoid repeating the same mistake? If yes → save. If no → skip.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Lesson inflation | Saving trivial corrections | Only save lessons that apply to future sessions |
| Vague lessons | "Be more careful with imports" | Specific: "Use absolute imports in the `api/` package" |
| Duplicates | Same lesson saved twice | Search existing lessons before proposing |
| Tag confusion | Everything is `correction` | Match category tag to what happened |
