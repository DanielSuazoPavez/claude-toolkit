---
name: create-memory
description: Create a new memory file following project conventions. Use when user asks to save/write/create a memory. Keywords: remember this, save context, create memory, persist information.
allowed-tools: Read, Write, Glob
---

# Write Memory Skill

## When to Use

Activate when user says:
- "write a memory about..."
- "save this as a memory"
- "create a memory for..."
- "remember this..."

## Decision: Memory or Something Else?

```
Is this prescriptive rules or reference documentation?
├─ Yes → `.claude/docs/` (not memories — see relevant-toolkit-context)
│
└─ No → Is this organic context (who you are, what's happening, preferences)?
    ├─ Yes → Memory in `.claude/memories/`
    └─ No → Consider if a memory is needed at all
```

For branch WIP context, use a date prefix: `YYYYMMDD-{branch}-{context}.md`

**See also:** `/evaluate-memory` (quality gate), `/list-memories` (check for duplicates), `/create-skill` (for procedures), `/create-hook` (for enforcement), `/create-agent` (for behavioral specialists), `relevant-conventions-naming`

## Instructions

1. **Check for duplicates**: List `.claude/memories/` to see existing memories
2. **Choose a name**: Plain descriptive name with underscores — `professional_profile.md`, `user.md`, `postgresql_patterns.md`
3. **Include Quick Reference** as section 1 with `**ONLY READ WHEN:**` bullets
4. **Write content** based on what user wants to capture

## File Format

```markdown
# Title

## 1. Quick Reference

**ONLY READ WHEN:**
- [Specific triggering context]
- User explicitly asks about [topic]

Brief description.

---

## 2. Main Content

[Detailed content here]
```

## Notes

- Use underscores in filenames: `opensearch_query_patterns.md`
- Branch WIP memories include date: `20260121-feature_name-context.md`
- No category prefixes — memories are just named files

## Reference Examples

For format and structure examples, see existing docs (same Quick Reference pattern):
- `.claude/docs/relevant-toolkit-context.md` - naming conventions, docs/memories boundary
- `.claude/docs/essential-conventions-code_style.md` - example of well-structured Quick Reference

## When to Merge vs Split Memories

**Merge when:**
- Topics are always referenced together
- Combined content stays under 200 lines
- Single mental model covers both topics

**Split when:**
- Content exceeds 300 lines
- Topics have different update frequencies
- Different triggering contexts (Quick Reference would have unrelated bullets)

## Pre-Save Validation Checklist

Before writing the memory file, verify:

- [ ] **Not a doc?** Rules/conventions → `.claude/docs/`, not memories
- [ ] **Quick Reference exists?** Has `**ONLY READ WHEN:**` bullets
- [ ] **Descriptive name?** Plain `snake_case` name, no prefixes
- [ ] **No duplicate?** List `.claude/memories/` to check
- [ ] **Under 300 lines?** Split if larger

### Quality Gate

Run `/evaluate-memory` on the result:
- **Target: 85%**
- If below target, iterate on the weakest dimensions

## Common Mistakes: Worked Example

**Bad request:** "Remember that we're using PostgreSQL"

**Problem:** One-off fact, no actionable context, likely already in project config.

**Good correction:** "Create a memory about our PostgreSQL query patterns, including the pagination approach and how we handle JSON columns"

**Result:** `postgresql_patterns.md` with:
- Quick Reference: "ONLY READ WHEN: Writing database queries, debugging slow queries"
- Content: Pagination pattern, JSON operators, index usage guidelines

---

**Bad request:** "Save everything we discussed today"

**Problem:** Session dump, will be stale tomorrow, no focus.

**Good correction:** Use `/write-handoff` for session continuation, or identify the specific reusable pattern: "Create a memory about the retry logic pattern we designed"

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **One-off Info** | Ephemeral data that becomes stale | Use session handoff or inline comment |
| **Duplicate Memory** | Topic already has a memory | Update existing memory instead |
| **No Quick Reference** | Full file must be loaded to assess relevance | Always add Quick Reference section |
| **Giant Memory** | 500+ lines, mixes concerns | Split into focused memories |
| **Vague Filename** | `notes.md` — impossible to identify | Use descriptive, specific names |
