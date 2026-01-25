#!/bin/bash
# UserPromptSubmit hook: inject essential memories at session start
#
# Settings.json:
#   "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/session-start.sh"}]}]
#
# Environment:
#   CLAUDE_MEMORIES_DIR - memories directory (default: .claude/memories)
#
# Requires: essential-*.md files in memories directory
#
# Test (manual):
#   cd /path/to/project && bash .claude/hooks/session-start.sh
#   # Expected: outputs essential memories, other memories list, git context

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
    cat "$f"
    echo ""
  fi
done

# === AVAILABLE MEMORIES ===
echo "=== OTHER MEMORIES AVAILABLE ==="
ls -1 "$MEMORIES_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/.md$//' | grep -v "^essential-" || echo "(none)"
echo ""
echo "Run /list-memories for Quick Reference summaries, or read specific files when relevant."

# === GIT CONTEXT ===
echo ""
echo "=== GIT CONTEXT ==="
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$MAIN_BRANCH" ] && MAIN_BRANCH="main"
echo "Main: $MAIN_BRANCH"

# === ACKNOWLEDGMENT ===
ESSENTIAL_COUNT=$(ls -1 "$MEMORIES_DIR"/essential-*.md 2>/dev/null | wc -l)
echo ""
echo "=== SESSION START ==="
echo "Loaded $ESSENTIAL_COUNT essential memories. Acknowledge with a brief greeting."

exit 0
