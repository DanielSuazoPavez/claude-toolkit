#!/bin/bash
# Hook: anti-rationalization
# Event: Stop
# Purpose: Detect cop-out phrases in Claude's responses and nudge to reconsider
#
# Settings.json:
#   "Stop": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/anti-rationalization.sh"}]}]
#
# Input (stdin JSON):
#   transcript_path - path to conversation JSONL
#   stop_hook_active - true if already continuing from a previous stop hook
#
# Test cases:
#   # With stop_hook_active=true (loop prevention):
#   echo '{"stop_hook_active":true,"transcript_path":"/tmp/test.jsonl"}' | bash anti-rationalization.sh
#   # Expected: silent exit 0
#
#   # With no cop-out phrases in transcript:
#   echo '{"role":"assistant","content":[{"text":"Fixed the bug by updating the parser."}]}' > /tmp/test.jsonl
#   echo '{"stop_hook_active":false,"transcript_path":"/tmp/test.jsonl"}' | bash anti-rationalization.sh
#   # Expected: silent exit 0
#
#   # With cop-out phrase in transcript:
#   echo '{"role":"assistant","content":[{"text":"This is out of scope for this change."}]}' > /tmp/test.jsonl
#   echo '{"stop_hook_active":false,"transcript_path":"/tmp/test.jsonl"}' | bash anti-rationalization.sh
#   # Expected: JSON block with matched phrase

set -euo pipefail

INPUT=$(cat)

# Loop prevention: if already continuing from a stop hook, let Claude stop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Get transcript path
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Get last assistant message from transcript JSONL
# Transcript is JSONL — scan from the end for the last assistant message
LAST_ASSISTANT=$(tac "$TRANSCRIPT_PATH" | while IFS= read -r line; do
    role=$(echo "$line" | jq -r '.role // ""' 2>/dev/null) || continue
    if [ "$role" = "assistant" ]; then
        echo "$line"
        break
    fi
done)

if [ -z "$LAST_ASSISTANT" ]; then
    exit 0
fi

# Extract text content
CONTENT_TEXT=$(echo "$LAST_ASSISTANT" | jq -r '
    if .content | type == "array" then
        [.content[] | select(.type == "text" or (has("text") and (has("type") | not))) | .text] | join("\n")
    elif .content | type == "string" then
        .content
    else
        ""
    end
' 2>/dev/null)

if [ -z "$CONTENT_TEXT" ]; then
    exit 0
fi

# Combined regex for cop-out / rationalization phrases
PATTERN='out of scope|beyond the scope|outside the scope|not in scope|leave (this|that|it) (for|to|as) a follow.?up|left as a follow.?up|address (this|that|it) (later|in a follow.?up|separately)|defer (this|that|it) (to|for)|future (PR|commit|task|change|iteration)|separate (PR|task|issue|ticket)|pre.?existing (issue|problem|bug|error|behavior)|this is a known (issue|problem|bug|limitation)|already (broken|buggy|failing) before|not (caused|introduced) by (this|my|our|the) change|unrelated to (this|my|our|the) change|too (many|complex|complicated|difficult|involved) to (fix|address|resolve|handle|change)|would require (significant|substantial|major|extensive) (refactor|rewrite|changes|rework)|diminishing returns|I.ll (skip|leave|omit|not (address|fix|handle|change|modify|update))|I will (skip|leave|omit|not (address|fix|handle|change|modify|update))|won.t (address|fix|handle|change|modify|update|touch)|choosing not to|decided not to|not worth (fixing|addressing|changing)'

# Match against cop-out patterns (case-insensitive, first match only)
MATCHED=$(echo "$CONTENT_TEXT" | grep -ioE "$PATTERN" | head -1 || true)

if [ -z "$MATCHED" ]; then
    exit 0
fi

# Block with constructive nudge
jq -n --arg matched "$MATCHED" '{
    decision: "block",
    reason: ("Rationalization detected in your response.\n\nMatched: \"" + $matched + "\"\n\nBefore stopping, reconsider:\n- If the user explicitly asked to defer this, explain that and continue.\n- If this is genuinely out of scope, explain WHY concretely — not just \"out of scope.\"\n- Otherwise, attempt the fix now. The user can always reject it.\n\nDo the work or justify specifically why not.")
}'
