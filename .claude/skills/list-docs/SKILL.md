---
name: list-docs
metadata: { type: command }
description: List available docs with their Quick Reference summaries. Use to discover relevant context without loading full files into conversation. Keywords: docs, context, preview, discover, scan, list docs.
allowed-tools: Bash(for f in .claude/docs/*)
---

# List Docs

Preview available docs without loading full content.

**See also:** `/create-docs` (create new docs), `relevant-toolkit-context` doc (naming conventions and categories)

Memories (organic context) live in `.claude/memories/` — use `ls .claude/memories/` to browse. Memories have no structured listing skill; they're just files.

## Instructions

### Standard: Quick Reference summaries

```bash
for f in .claude/docs/*.md; do
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

Use when triaging stale docs or debugging missing content:

```bash
for f in .claude/docs/*.md; do
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
| Empty docs directory | No output from loop | Tell user: "No docs found in `.claude/docs/`" |
| Doc missing Quick Reference | `[no Quick Reference section]` shown | File may be malformed — check it has a `## Quick Reference` or `## 1. Quick Reference` heading |
| Doc has frontmatter but no body | Only `[no Quick Reference section]` shown | Likely a stub — read the file to check |
| Directory doesn't exist | Glob expands literally | Create `.claude/docs/` first |

## After Running

Based on Quick References, load only the docs relevant to current work:

```
Read .claude/docs/<doc-name>.md
```

Essential docs (`essential-*`) are auto-loaded at session start. Relevant docs (`relevant-*`) are on-demand — discovered via this skill or loaded by user request.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Load Everything** | Wastes context on irrelevant info | Use Quick Reference to filter |
| **Skip Essential** | Miss conventions the doc enforces | Essential docs are auto-loaded, but verify they loaded |
| **Ignore Quick Reference** | Load full file for one fact | Read summary first |
| **Confuse Docs with Memories** | Looking for organic context here | Memories are in `.claude/memories/`, not `.claude/docs/` |
