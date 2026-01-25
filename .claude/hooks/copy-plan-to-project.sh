#!/bin/bash
# PostToolUse hook: copy plan files from ~/.claude/plans/ to project
#
# Settings.json:
#   "PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/copy-plan-to-project.sh"}]}]
#
# Configuration:
#   CLAUDE_PLANS_DIR - target directory (default: docs/plans)
#
# Triggers on Write in plan mode for files in ~/.claude/plans/
# Renames files based on plan title: "# Plan: Add Feature" -> 2026-01-24_1430_add-feature.md

# Configuration
PLANS_DIR="${CLAUDE_PLANS_DIR:-docs/plans}"

input=$(cat)
mode=$(echo "$input" | jq -r '.permission_mode // empty')
tool=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Only act on Write in plan mode, for files in ~/.claude/plans/
if [[ "$mode" == "plan" && "$tool" == "Write" && "$file_path" == *"/.claude/plans/"* ]]; then
  # Create project plans directory if needed
  mkdir -p "$PLANS_DIR"

  # Extract title from "# Plan: <title>" header
  title=$(grep -m1 '^# Plan:' "$file_path" | sed 's/^# Plan: *//')

  if [[ -n "$title" ]]; then
    # Convert title to slug: lowercase, replace spaces/special chars with hyphens
    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    timestamp=$(date +%Y-%m-%d_%H%M)
    new_filename="${timestamp}_${slug}.md"
  else
    # Fallback to original filename if no title found
    new_filename=$(basename "$file_path")
  fi

  # Copy plan to project with new name
  if cp "$file_path" "$PLANS_DIR/$new_filename" 2>/dev/null; then
    echo "Plan copied to project: $PLANS_DIR/$new_filename"
  else
    echo "Warning: Failed to copy plan to $PLANS_DIR/$new_filename" >&2
  fi
fi

exit 0
