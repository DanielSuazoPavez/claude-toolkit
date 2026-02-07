# Backlog Schema Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Adding or modifying items in BACKLOG.md
- Reviewing backlog structure
- User explicitly asks about backlog format

Defines the schema for BACKLOG.md: priority sections, entry format, ids, metadata fields, and status values.

---

## 2. Section Hierarchy

```markdown
# Project Backlog

## Current Goal
<!-- What the project is focused on right now and why -->

## Scope Definitions        ← optional (standard format only)
| Scope | Description |
|-------|-------------|
<!-- Replace with project-appropriate scope areas -->

---

## P0 - Critical
## P1 - High
## P2 - Medium
## P100 - Nice to Have

---

## Graveyard
<!-- Abandoned items with reason: - description — reason -->
```

---

## 3. Entry Format

**Two formats supported:**

### Minimal format
```markdown
- Task description (`kebab-case-id`)
```

### Standard format
```markdown
- **[CATEGORY]** Task description (`kebab-case-id`)
    - **status**: `status-value`
    - **scope**: `Area1, Area2`
    - **branch**: `feat/branch-name`
    - **depends-on**: `other-task-id`
    - **plan**: `.claude/plans/plan-file.md`
    - **notes**: Additional context
```

**Rules:**
- Every item **must** have a kebab-case id in backtick-parens at end of title
- Ids are manual, short, descriptive (e.g., `cli-validation`, `type-registry`)
- No Completed section — done items are removed from the backlog
- Graveyard keeps abandoned items with a reason
- All metadata fields are optional
- `scope` values should match entries in Scope Definitions table (when present)

---

## 4. Metadata Fields

| Field | Purpose |
|-------|---------|
| `status` | Current state (see status values below) |
| `scope` | Technical areas involved (comma-separated) |
| `branch` | Git branch name |
| `depends-on` | Task id(s) that must complete first |
| `plan` | Path to plan file |
| `notes` | Free text context |

---

## 5. Status Values

| Status | Meaning |
|--------|---------|
| `idea` | Not yet scoped |
| `planned` | Scoped, ready to start |
| `in-progress` | Active work, has branch |
| `ready-for-pr` | Code complete, PR not yet created |
| `pr-open` | PR created, awaiting review |
| `blocked` | Waiting on dependency or external |

**Typical flow:** `idea` → `planned` → `in-progress` → `ready-for-pr` → `pr-open` → merged (remove from backlog)

---

## 6. Priority Guidelines

| Priority | Criteria |
|----------|----------|
| P0 | Blocking production or critical workflows |
| P1 | High business value, active development |
| P2 | Important but not urgent, clear scope |
| P100 | Nice-to-have, future improvements |
| Graveyard | Abandoned or superseded (with reason) |

---

## 7. Tooling

Query and validate backlogs with scripts in `projects/scripts/`:

```bash
backlog-query.sh                    # List all tasks
backlog-query.sh --path FILE        # Use specific file
backlog-query.sh summary            # Counts by priority/status
backlog-query.sh validate           # Validate format
backlog-query.sh id <task-id>       # Lookup by id
backlog-query.sh priority P1        # Filter by priority
backlog-query.sh status in-progress # Filter by status
backlog-query.sh blocked            # Tasks with dependencies
backlog-query.sh unblocked          # Actionable tasks
```
