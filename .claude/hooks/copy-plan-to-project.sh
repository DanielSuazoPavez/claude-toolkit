#!/bin/bash
# PostToolUse hook: copy plan files from ~/.claude/plans/ to project
#
# Settings.json:
#   "PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/copy-plan-to-project.sh"}]}]
#
# Environment:
#   CLAUDE_PLANS_DIR - target directory (default: .claude/plans)
#
# Triggers on Write in plan mode for files in any .claude/plans/ path
# Renames files based on plan title using slug generation:
#   "# Plan: Add User Auth" -> 2026-01-24_1430_add-user-auth.md
#
# Slug algorithm: lowercase -> replace non-alphanumeric with hyphen -> dedupe hyphens -> trim
#
# Test cases:
#   # Setup: create temp plan file
#   echo '# Plan: Test Title' > /tmp/test-plan.md
#
#   echo '{"permission_mode":"plan","tool_name":"Write","tool_input":{"file_path":"/tmp/.claude/plans/test.md"}}' | \
#     bash copy-plan-to-project.sh
#   # Expected output: Plan copied to project: .claude/plans/YYYY-MM-DD_HHMM_test-title.md (if file exists)
#
#   echo '{"permission_mode":"default","tool_name":"Write","tool_input":{"file_path":"/tmp/other.md"}}' | ./copy-plan-to-project.sh
#   # Expected: (empty - not plan mode)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.md"}}' | ./copy-plan-to-project.sh
#   # Expected: (empty - wrong tool)

INPUT=$(cat)

# Parse JSON and validate structure - exit gracefully if jq fails or fields missing
MODE=$(echo "$INPUT" | jq -r '.permission_mode // ""' 2>/dev/null) || exit 0
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0

# Early exit: must be Write tool in plan mode
[ "$TOOL" != "Write" ] && exit 0
[ "$MODE" != "plan" ] && exit 0

# Early exit: must be a plan file path
[[ "$FILE_PATH" != *"/.claude/plans/"* ]] && exit 0

# Configuration
PLANS_DIR="${CLAUDE_PLANS_DIR:-.claude/plans}"

# Check source file exists
if [[ ! -f "$FILE_PATH" ]]; then
    echo "Warning: Plan file not found: $FILE_PATH" >&2
    exit 0
fi

# Create project plans directory if needed
mkdir -p "$PLANS_DIR"

# Extract title from "# Plan: <title>" header
TITLE=$(grep -m1 '^# Plan:' "$FILE_PATH" | sed 's/^# Plan: *//')
TIMESTAMP=$(date +%Y-%m-%d_%H%M)

# Generate slug from title, or fallback to original filename
if [[ -n "$TITLE" ]]; then
    # Slug: lowercase, non-alphanumeric to hyphen, dedupe hyphens, trim edges
    SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-\|-$//g')
    NEW_FILENAME="${TIMESTAMP}_${SLUG}.md"
else
    NEW_FILENAME="${TIMESTAMP}_$(basename "$FILE_PATH")"
fi

# Copy plan to project with new name
if cp "$FILE_PATH" "$PLANS_DIR/$NEW_FILENAME" 2>/dev/null; then
    echo "Plan copied to project: $PLANS_DIR/$NEW_FILENAME"
else
    echo "Warning: Failed to copy plan to $PLANS_DIR/$NEW_FILENAME" >&2
fi

exit 0
