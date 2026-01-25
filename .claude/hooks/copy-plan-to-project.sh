#!/bin/bash
# PostToolUse hook: copy plan files from ~/.claude/plans/ to project
#
# Settings.json:
#   "PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/copy-plan-to-project.sh"}]}]
#
# Configuration:
#   CLAUDE_PLANS_DIR - target directory (default: docs/plans)
#   CLAUDE_SKIP_PLAN_COPY=1 - disable copying (for testing)
#
# Triggers on Write in plan mode for files in ~/.claude/plans/
# Renames files based on plan title: "# Plan: Add Feature" -> 2026-01-24_1430_add-feature.md
#
# Test (requires a plan file with "# Plan: Test Title" header):
#   echo '# Plan: Test Title' > /tmp/test-plan.md
#   echo '{"permission_mode":"plan","tool_name":"Write","tool_input":{"file_path":"/tmp/.claude/plans/test.md"}}' | ./copy-plan-to-project.sh
#   # Expected: copies to docs/plans/YYYY-MM-DD_HHMM_test-title.md

# Skip if disabled
[ -n "$CLAUDE_SKIP_PLAN_COPY" ] && exit 0

# Configuration
PLANS_DIR="${CLAUDE_PLANS_DIR:-docs/plans}"

input=$(cat)

# Parse JSON - exit gracefully if jq fails
mode=$(echo "$input" | jq -r '.permission_mode // empty' 2>/dev/null) || exit 0
tool=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# Only act on Write in plan mode, for files in ~/.claude/plans/
if [[ "$mode" == "plan" && "$tool" == "Write" && "$file_path" == *"/.claude/plans/"* ]]; then
  # Check source file exists
  if [[ ! -f "$file_path" ]]; then
    echo "Warning: Plan file not found: $file_path" >&2
    exit 0
  fi

  # Create project plans directory if needed
  mkdir -p "$PLANS_DIR"

  # Extract title from "# Plan: <title>" header
  title=$(grep -m1 '^# Plan:' "$file_path" | sed 's/^# Plan: *//')
  timestamp=$(date +%Y-%m-%d_%H%M)

  if [[ -n "$title" ]]; then
    # Convert title to slug: lowercase, replace spaces/special chars with hyphens
    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    new_filename="${timestamp}_${slug}.md"
  else
    # Fallback: timestamp + original filename
    new_filename="${timestamp}_$(basename "$file_path")"
  fi

  # Copy plan to project with new name
  if cp "$file_path" "$PLANS_DIR/$new_filename" 2>/dev/null; then
    echo "Plan copied to project: $PLANS_DIR/$new_filename"
  else
    echo "Warning: Failed to copy plan to $PLANS_DIR/$new_filename" >&2
  fi
fi

exit 0
