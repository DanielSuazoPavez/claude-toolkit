#!/bin/bash
# PostToolUse hook: track agent usage
#
# Settings.json:
#   "PostToolUse": [{"matcher": "Task", "hooks": [{"type": "command", "command": ".claude/hooks/track-agent-usage.sh"}]}]
#
# Note: Skill tracking is done via per-skill hooks (see track-skill-usage.sh)
#
# Configuration:
#   CLAUDE_TRACK_USAGE - enable tracking (default: 1, set to 0 to disable)
#   CLAUDE_USAGE_LOG - log file path (default: .claude/usage.log)
#
# Output format (append-only):
#   2026-01-25T10:45:00 agent code-reviewer
#
# Analyze usage:
#   cat .claude/usage.log | awk '{print $2, $3}' | sort | uniq -c | sort -rn
#
# Test:
#   echo '{"tool_input":{"subagent_type":"code-reviewer"}}' | .claude/hooks/track-usage.sh

[ "${CLAUDE_TRACK_USAGE:-1}" = "0" ] && exit 0

input=$(cat)
agent=$(echo "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
[ -n "$agent" ] && echo "$(date -Iseconds) agent $agent" >> "${CLAUDE_USAGE_LOG:-.claude/usage.log}"

exit 0
