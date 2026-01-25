---
name: write-memory
description: Create a new memory file following project conventions. Use when user asks to save/write/create a memory.
---

# Write Memory Skill

## Purpose

Create properly formatted memory files following project conventions.

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
        └─ No → Consider if a memory is needed at all
```

### Quick Category Reference

| Category | Lifetime | Example |
|----------|----------|---------|
| `essential-` | Permanent | Code style, architecture decisions |
| `relevant-` | Months | API patterns, tool configurations |
| `branch-` | Days/weeks | WIP context for feature-x |
| `idea-` | Until decided | Future refactoring plans |

## Instructions

1. **Read conventions**: Check `.claude/memories/essential-conventions-memory.md` for naming and format rules

2. **Determine category**:
   - `essential-` → Core, stable project info (architecture, workflows)
   - `relevant-` → Important context that may evolve
   - `branch-` → WIP context for a feature branch (temporary)
   - `idea-` → Future implementation ideas (temporary)

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

## Reference Examples

For format and structure examples, see existing memories:
- `essential-conventions-memory.md` - naming conventions and format rules
- `essential-conventions-code_style.md` - example of stable, permanent memory

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **One-off Info** | Memory for temporary facts | Use session handoff or inline comment |
| **Duplicate Memory** | Topic already has a memory | Update existing memory instead |
| **No Quick Reference** | Full file must be loaded | Always add Quick Reference section |
| **Wrong Category** | Using `essential-` for WIP | Match category to stability |
| **Giant Memory** | 500+ lines, everything included | Split into focused memories |
