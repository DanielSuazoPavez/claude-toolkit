---
name: learn
metadata: { type: knowledge }
description: Capture a lesson from this session. Use when the user says "remember this", "learn this", "save this lesson", "don't forget", "note this for next time", "keep this in mind", or asks to capture a correction, pattern, convention, or gotcha.
argument-hint: "[topic-hint]"
compatibility: sqlite3
allowed-tools: Read, Bash(claude-toolkit lessons:*), Bash(sqlite3:*)
---

# Learn

Capture a lesson from the current session. Lightweight — identify, format, write.

**See also:** `/manage-lessons` (lifecycle: promote, archive, crystallize after capture), `relevant-toolkit-lessons` doc (full ecosystem reference), `claude-toolkit lessons` (CLI)

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
2. **Infer** tags, scope, and draft one-line lesson text
3. **Present** the proposed lesson (tags + scope + text) — write unless user objects
4. **Write** to lessons.db with full metadata

### Scope

Default: `global` (surfaces in all projects). Use `project` when the lesson is specific to this project's codebase and would not help other projects (e.g., "this repo uses X pattern for Y").

No evaluation rubrics, no multi-round iteration. Propose → write.

### Duplicate & Recurring Detection

Before writing, search existing lessons:

```bash
claude-toolkit lessons search "<key phrase from lesson>" --limit 5
```

- If an existing lesson covers the exact same point with no new angle → **skip**, tell the user it already exists
- Otherwise, if a similar lesson exists (same topic, different angle, or same mistake recurring) → **write** and add the `recurring` tag. Bias toward capturing — `/manage-lessons` handles crystallization and dedup later

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
- Scope: <global|project>
- Lesson: <one-line actionable rule>
```

Then write immediately unless the user objects or asks for changes.

### Writing to lessons.db

The `add` subcommand handles ID generation, project/branch detection, and domain tag inference:

```bash
claude-toolkit lessons add \
  --text "<lesson text>" \
  --tags "<category-tag>,<extra-tag1>,<extra-tag2>" \
  --scope <global|project>
```

The command auto-detects project name and git branch, generates a unique ID, and infers additional domain tags from the lesson text. Omit `--scope` for global (default).

If duplicate detection flagged `recurring`, include it in tags:

```bash
claude-toolkit lessons add \
  --text "<lesson text>" \
  --tags "<category-tag>,recurring,<extra-tags>" \
  --scope <global|project>
```

## Quality Heuristic

> Would this help a future session avoid repeating the same mistake? If yes → save. If no → skip.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Lesson inflation | Saving trivial corrections | Only save lessons that apply to future sessions |
| Vague lessons | "Be more careful with imports" | Specific: "Use absolute imports in the `api/` package" |
| Duplicate suppression | Skipping a lesson because a similar one exists | Add `recurring` tag — crystallization handles merging, not the capture step |
| Tag confusion | Everything is `correction` | Match category tag to what happened |
