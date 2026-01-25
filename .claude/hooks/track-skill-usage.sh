#!/bin/bash
# UserPromptSubmit hook: track skill usage from /skill-name invocations
#
# Settings.json:
#   "UserPromptSubmit": [{"hooks": [{"type": "command", "command": ".claude/hooks/track-skill-usage.sh"}]}]
#
# Configuration:
#   CLAUDE_TRACK_USAGE - enable tracking (default: 1, set to 0 to disable)
#   CLAUDE_USAGE_LOG - log file path (default: .claude/usage.log)
#
# Test:
#   echo '{"prompt":"/list-memories"}' | .claude/hooks/track-skill-usage.sh

[ "${CLAUDE_TRACK_USAGE:-1}" = "0" ] && exit 0

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null) || exit 0

# Match /skill-name at start of prompt (with optional args)
if [[ "$prompt" =~ ^/([a-z][a-z0-9-]*) ]]; then
  skill="${BASH_REMATCH[1]}"
  echo "$(date -Iseconds) skill $skill" >> "${CLAUDE_USAGE_LOG:-.claude/usage.log}"
fi

exit 0
