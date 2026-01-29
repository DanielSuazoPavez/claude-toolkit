#!/bin/bash
# SessionStart hook: inject essential memories at session start
#
# Settings.json:
#   "SessionStart": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/session-start.sh"}]}]
#
# Environment:
#   CLAUDE_MEMORIES_DIR - memories directory (default: .claude/memories)
#
# Requires: essential-*.md files in memories directory
#
# Test cases:
#   # Normal operation (from project root with memories)
#   cd /path/to/project && bash .claude/hooks/session-start.sh
#   # Expected: outputs essential memories, other memories list, git context
#
#   # No memories directory
#   CLAUDE_MEMORIES_DIR=/nonexistent bash .claude/hooks/session-start.sh
#   # Expected: "Warning: /nonexistent not found..." then exits 0
#
#   # Empty memories (no essential-*.md files)
#   mkdir -p /tmp/empty-mem && CLAUDE_MEMORIES_DIR=/tmp/empty-mem bash .claude/hooks/session-start.sh
#   # Expected: outputs headers but "0 essential memories loaded"
#
#   # No git repo
#   cd /tmp && bash /path/to/.claude/hooks/session-start.sh
#   # Expected: Branch shows "unknown", Main shows "main" (fallback)

# Configuration
MEMORIES_DIR="${CLAUDE_MEMORIES_DIR:-.claude/memories}"

# Check we're in a project with memories
if [ ! -d "$MEMORIES_DIR" ]; then
    echo "Warning: $MEMORIES_DIR not found. Run from project root."
    exit 0
fi

# === ESSENTIAL CONTEXT (auto-injected) ===

# Output essential memories directly - these are always relevant
for f in "$MEMORIES_DIR"/essential-*.md; do
  if [ -f "$f" ]; then
    echo "=== $(basename "$f" .md) ==="
    if ! cat "$f" 2>/dev/null; then
      echo "(Error reading file - permission denied or corrupted)"
    fi
    echo ""
  fi
done

# === AVAILABLE MEMORIES ===
echo "=== OTHER MEMORIES AVAILABLE ==="
OTHER_MEMORIES=$(ls -1 "$MEMORIES_DIR"/*.md 2>/dev/null | xargs -r -n1 basename 2>/dev/null | sed 's/.md$//' | grep -v "^essential-")
[ -n "$OTHER_MEMORIES" ] && echo "$OTHER_MEMORIES" || echo "(none)"
echo ""
echo "Run /list-memories for Quick Reference summaries, or read specific files when relevant."

# === GIT CONTEXT ===
echo ""
echo "=== GIT CONTEXT ==="
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$MAIN_BRANCH" ] && MAIN_BRANCH="main"
echo "Main: $MAIN_BRANCH"

# === MEMORY GUIDANCE ===
echo ""
echo "If the user's request relates to a non-essential memory topic, use /list-memories to check Quick Reference summaries, then read relevant memories before proceeding."

# === ACKNOWLEDGMENT ===
ESSENTIAL_COUNT=$(ls -1 "$MEMORIES_DIR"/essential-*.md 2>/dev/null | wc -l)
echo ""
echo "=== SESSION START ==="
echo "$ESSENTIAL_COUNT essential memories loaded. Acknowledge briefly, mentioning the count."

exit 0
