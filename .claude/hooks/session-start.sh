#!/bin/bash

# === ESSENTIAL CONTEXT (auto-injected) ===

# Output essential memories directly - these are always relevant
for f in .claude/memories/essential-*.md; do
  if [ -f "$f" ]; then
    echo "=== $(basename "$f" .md) ==="
    cat "$f"
    echo ""
  fi
done

# === AVAILABLE MEMORIES ===
echo "=== OTHER MEMORIES AVAILABLE ==="
ls -1 .claude/memories/*.md 2>/dev/null | xargs -n1 basename | sed 's/.md$//' | grep -v "^essential-" || echo "(none)"
echo ""
echo "Run /list-memories for Quick Reference summaries, or read specific files when relevant."

# === GIT CONTEXT ===
echo ""
echo "=== GIT CONTEXT ==="
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo "Main: main"

# === ACKNOWLEDGMENT ===
echo ""
echo "=== SESSION START ==="
echo "Acknowledge this hook ran successfully with a brief greeting."

exit 0
