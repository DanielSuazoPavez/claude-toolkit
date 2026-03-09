---
name: list-memories
type: command
description: List available memories with their Quick Reference summaries. Use to discover relevant context without loading full files into conversation. Keywords: memory, context, preview, discover, scan, index.
allowed-tools: Bash(for f in .claude/memories/*)
---

# List Memories

Preview available memories without loading full content.

**See also:** `/create-memory` (create new memories), `essential-conventions-memory` memory (naming conventions and categories)

## Instructions

### Standard: Quick Reference summaries

```bash
for f in .claude/memories/*.md; do
  name=$(basename "$f" .md)
  echo "### $name"
  content=$(awk '/^## .*Quick Reference/{found=1; next} found && /^## /{exit} found' "$f" 2>/dev/null | sed '/^---$/d' | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
  if [ -z "$content" ]; then
    echo "[no Quick Reference section]"
  else
    echo "$content"
  fi
  echo "---"
done
```

### Verbose: with file sizes and last-modified dates

Use when triaging stale memories or debugging missing content:

```bash
for f in .claude/memories/*.md; do
  name=$(basename "$f" .md)
  size=$(wc -l < "$f")
  modified=$(date -r "$f" +%Y-%m-%d 2>/dev/null || stat -c %y "$f" 2>/dev/null | cut -d' ' -f1)
  echo "### $name  (${size} lines, modified ${modified})"
  content=$(awk '/^## .*Quick Reference/{found=1; next} found && /^## /{exit} found' "$f" 2>/dev/null | sed '/^---$/d' | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
  if [ -z "$content" ]; then
    echo "[no Quick Reference section]"
  else
    echo "$content"
  fi
  echo "---"
done
```

## Error Handling

| Condition | What Happens | Action |
|-----------|--------------|--------|
| Empty memories directory | No output from loop | Tell user: "No memories found in `.claude/memories/`" |
| Memory missing Quick Reference | `[no Quick Reference section]` shown | File may be malformed — check it has a `## Quick Reference` or `## 1. Quick Reference` heading |
| Memory has frontmatter but no body | Only `[no Quick Reference section]` shown | Likely a stub — read the file to check |
| Directory doesn't exist | Glob expands literally | Create `.claude/memories/` first |

## After Running

Based on Quick References, load only the memories relevant to current work:

```
Read .claude/memories/<memory-name>.md
```

**Loading priority** is defined in `essential-conventions-memory` — see the Memory Categories table for category lifetimes and load patterns. Short version: `essential-*` always, `relevant-*` when touching that area, `branch-*` only for that branch, `personal-*`/`idea-*` only with explicit user permission.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Load Everything** | Wastes context on irrelevant info | Use Quick Reference to filter |
| **Skip Essential** | Miss conventions the memory enforces | Always check essential-* |
| **Ignore Quick Reference** | Load full file for one fact | Read summary first |
| **Stale Branch Memories** | Loading context for merged/abandoned branches | Use verbose mode to check dates |
