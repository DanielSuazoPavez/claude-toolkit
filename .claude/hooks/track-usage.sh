#!/bin/bash
# PostToolUse hook: track skill and agent usage
#
# Settings.json:
#   "PostToolUse": [
#     {"matcher": "Skill", "hooks": [{"type": "command", "command": ".claude/hooks/track-usage.sh"}]},
#     {"matcher": "Task", "hooks": [{"type": "command", "command": ".claude/hooks/track-usage.sh"}]}
#   ]
#
# Configuration:
#   CLAUDE_TRACK_USAGE - enable tracking (default: 1, set to 0 to disable)
#   CLAUDE_USAGE_LOG - log file path (default: .claude/usage.log)
#
# Output format (append-only):
#   2026-01-25T10:30:00 skill commit
#   2026-01-25T10:45:00 agent code-reviewer
#
# Analyze usage:
#   cat .claude/usage.log | awk '{print $2, $3}' | sort | uniq -c | sort -rn
#
# Test:
#   echo '{"tool_name":"Skill","tool_input":{"skill":"commit"}}' | .claude/hooks/track-usage.sh
#   echo '{"tool_name":"Task","tool_input":{"subagent_type":"code-reviewer"}}' | .claude/hooks/track-usage.sh

# Skip if disabled (default: enabled)
[ "${CLAUDE_TRACK_USAGE:-1}" = "0" ] && exit 0

# Configuration
USAGE_LOG="${CLAUDE_USAGE_LOG:-.claude/usage.log}"

input=$(cat)

# Parse JSON - exit gracefully if jq fails
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

timestamp=$(date -Iseconds)

case "$tool_name" in
  Skill)
    skill=$(echo "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null) || exit 0
    [ -n "$skill" ] && echo "$timestamp skill $skill" >> "$USAGE_LOG"
    ;;
  Task)
    agent=$(echo "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
    [ -n "$agent" ] && echo "$timestamp agent $agent" >> "$USAGE_LOG"
    ;;
esac

exit 0
