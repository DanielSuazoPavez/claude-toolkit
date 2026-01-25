---
name: list-memories
description: List available memories with their Quick Reference summaries. Use to discover relevant context without loading full files into conversation.
allowed-tools: Bash(for f in *)
---

# List Memories

Preview available memories without loading full content.

## Instructions

Run this command to extract only Quick Reference sections:

```bash
for f in .claude/memories/*.md; do
  echo "### $(basename "$f" .md)"
  sed -n '/^## .*Quick Reference/,/^## /{/^## .*Quick Reference/d;/^## /d;p}' "$f" 2>/dev/null
  echo "---"
done
```

## Decision Tree: What to Load

```
What am I doing?
├─ Quick question about project?
│   └─ Read Quick References only, don't load full files
├─ New feature or significant work?
│   ├─ Load: essential-* (always)
│   ├─ Load: relevant-* for affected area
│   └─ Skip: idea-*, branch-* (unless continuing that branch)
├─ Bug fix?
│   ├─ Load: essential-*
│   └─ Load: only the area with the bug
├─ Continuing branch work?
│   └─ Load: branch-* for that specific branch
└─ Exploring an idea?
    └─ Load: idea-* (only with explicit permission)
```

### Loading Priority

| Priority | Category | When |
|----------|----------|------|
| 1 | `essential-*` | Always load these |
| 2 | `relevant-*` (area) | Only if touching that area |
| 3 | `branch-*` | Only if continuing that branch |
| 4 | `idea-*` | Only with explicit user permission |

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Load Everything** | Wastes context on irrelevant info | Use Quick Reference to filter |
| **Skip Essential** | Make mistakes the memory prevents | Always check essential-* |
| **Ignore Quick Reference** | Load full file for one fact | Read summary first |
| **Stale Branch Memories** | Loading old branch context | Check if branch still active |

## After Running

Based on Quick References, load only relevant full memories:
```
Read .claude/memories/<memory-name>.md
```
