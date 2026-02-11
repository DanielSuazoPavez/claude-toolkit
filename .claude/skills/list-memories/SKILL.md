---
name: list-memories
description: List available memories with their Quick Reference summaries. Use to discover relevant context without loading full files into conversation. Keywords: memory, context, preview, discover, scan, index.
allowed-tools: Bash(for f in *)
---

# List Memories

Preview available memories without loading full content.

## Instructions

Run this command to extract only Quick Reference sections:

```bash
for f in .claude/memories/*.md; do
  echo "### $(basename "$f" .md)"
  awk '/^## .*Quick Reference/{found=1; next} found && /^## /{exit} found' "$f" 2>/dev/null
  echo "---"
done
```

## Example Output

```
### essential-conventions
- Use conventional commits: feat|fix|docs|refactor
- Run tests before committing
- Keep functions under 50 lines
---
### relevant-testing
- Use pytest for all tests
- Mocks go in conftest.py
- Coverage minimum: 80%
---
### branch-feature-auth
- Implementing OAuth2 flow
- Blocked: waiting for API keys
---
```

## Error Handling

| Condition | What Happens | Action |
|-----------|--------------|--------|
| Empty memories directory | No output | Inform user: "No memories found" |
| Memory missing Quick Reference | Empty section shown | Skip silently or note missing |
| Directory doesn't exist | Glob fails silently | Create `.claude/memories/` first |

If the command produces no output, check:
1. Does `.claude/memories/` directory exist?
2. Are there any `.md` files in it?
3. Do the files have `## Quick Reference` sections?

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
