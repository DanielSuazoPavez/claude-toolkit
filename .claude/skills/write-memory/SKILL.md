---
name: write-memory
description: Create a new memory file following project conventions. Use when user asks to save/write/create a memory. Keywords: remember this, save context, create memory, persist information.
---

# Write Memory Skill

## When to Use

Activate when user says:
- "write a memory about..."
- "save this as a memory"
- "create a memory for..."
- "remember this..."

## Category Decision Tree

```
Is this information stable for 6+ months?
├─ Yes → Is it project-wide architecture or core workflow?
│   ├─ Yes → `essential-`
│   └─ No → `relevant-`
│
└─ No → Is it tied to a specific feature branch?
    ├─ Yes → `branch-` (include date)
    └─ No → Is it a future implementation idea?
        ├─ Yes → `idea-` (needs explicit permission note)
        └─ No → Is it testing a new approach or A/B testing?
            ├─ Yes → `experimental-` (user on-demand only)
            └─ No → Consider if a memory is needed at all
```

### Quick Category Reference

| Category | Lifetime | Load Pattern | Example |
|----------|----------|--------------|---------|
| `essential-` | Permanent | Auto (session start) | Code style, architecture decisions |
| `relevant-` | Months | On-demand | API patterns, tool configurations |
| `branch-` | Days/weeks | On-demand | WIP context for feature-x |
| `idea-` | Until decided | User permission | Future refactoring plans |
| `experimental-` | Until proven | User on-demand ONLY | A/B testing behaviors |

## Instructions

1. **Read conventions**: Check `.claude/memories/essential-conventions-memory.md` for naming and format rules

2. **Determine category** (see `essential-conventions-memory.md` for full details):
   - `essential-` → Core, stable project info (auto-loaded at session start)
   - `relevant-` → Important context that may evolve (on-demand)
   - `branch-` → WIP context for a feature branch (on-demand, temporary)
   - `idea-` → Future implementation ideas (requires permission, temporary)
   - `experimental-` → Testing new approaches (user on-demand ONLY)

3. **Create file** with format: `{category}-{context}-{descriptive_name}.md`

4. **Include Quick Reference** as section 1 with `**ONLY READ WHEN:**` bullets

5. **Write content** based on what user wants to capture

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

- Use underscores in filenames: `relevant-opensearch-query_patterns.md`
- Branch memories include date: `branch-20260121-feature_name-context.md`
- Idea memories need: `**NOTE**: ONLY READ WITH USER EXPLICIT PERMISSION`
- Experimental memories: User must explicitly request loading (never auto-load or proactively read)

## Reference Examples

For format and structure examples, see existing memories:
- `essential-conventions-memory.md` - naming conventions and format rules
- `essential-conventions-code_style.md` - example of stable, permanent memory

## Edge Cases

### Content Spans Multiple Categories

When content could fit multiple categories:

1. **Determine primary purpose**: What's the main reason this exists?
2. **Split if distinct audiences**: Architecture decisions (essential) vs implementation details (relevant)
3. **Merge if tightly coupled**: Keep together if splitting would require cross-references

**Decision guide:**
- Same stability timeline? → Single memory, higher category wins
- Different stability? → Split into separate memories
- One part is WIP? → Branch memory for WIP, separate memory for stable parts

### When to Merge vs Split Memories

**Merge when:**
- Topics are always referenced together
- Combined content stays under 200 lines
- Single mental model covers both topics

**Split when:**
- Content exceeds 300 lines
- Topics have different update frequencies
- Different triggering contexts (Quick Reference would have unrelated bullets)

### Borderline Category Cases

| Situation | Resolution |
|-----------|------------|
| Stable pattern with WIP additions | Keep in `relevant-`, mark WIP sections |
| Branch work becoming permanent | Graduate from `branch-` to `relevant-` when merged |
| Idea that's been approved | Move from `idea-` to `branch-` or `relevant-` |
| Experimental that proved useful | Graduate to `relevant-` with cleanup |

## Pre-Save Validation Checklist

Before writing the memory file, verify:

- [ ] **Category correct?** Matches stability timeline (essential=permanent, relevant=months, branch=days)
- [ ] **Quick Reference exists?** Has `**ONLY READ WHEN:**` bullets
- [ ] **Filename format?** `{category}-{context}-{descriptive_name}.md` with underscores
- [ ] **No duplicate?** Check `.claude/memories/` for existing coverage
- [ ] **Under 300 lines?** Split if larger

## Common Mistakes: Worked Example

**Bad request:** "Remember that we're using PostgreSQL"

**Problem:** One-off fact, no actionable context, likely already in project config.

**Good correction:** "Create a memory about our PostgreSQL query patterns, including the pagination approach and how we handle JSON columns"

**Result:** `relevant-database-postgresql_patterns.md` with:
- Quick Reference: "ONLY READ WHEN: Writing database queries, debugging slow queries"
- Content: Pagination pattern, JSON operators, index usage guidelines

---

**Bad request:** "Save everything we discussed today"

**Problem:** Session dump, will be stale tomorrow, no focus.

**Good correction:** Use `/write-handoff` for session continuation, or identify the specific reusable pattern: "Create a memory about the retry logic pattern we designed"

## Anti-Patterns

| Pattern | Problem | Why | Fix |
|---------|---------|-----|-----|
| **One-off Info** | Memory for temporary facts | Pollutes memory space with ephemeral data that becomes stale | Use session handoff or inline comment |
| **Duplicate Memory** | Topic already has a memory | Creates sync issues and confusion about source of truth | Update existing memory instead |
| **No Quick Reference** | Full file must be loaded | Wastes context on irrelevant content, no filter mechanism | Always add Quick Reference section |
| **Wrong Category** | Using `essential-` for WIP | Auto-loads unstable content that may change or be deleted | Match category to stability |
| **Giant Memory** | 500+ lines, everything included | Hard to maintain, slow to scan, mixes concerns | Split into focused memories |
| **Vague Filename** | `relevant-notes.md` | Impossible to identify content without reading | Use descriptive, specific names |
