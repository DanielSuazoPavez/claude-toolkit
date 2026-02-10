#!/bin/bash
# Hook: capture-lesson
# Event: Stop
# Purpose: Detect [LEARN] tags in Claude's responses and prompt for lesson capture
#
# Settings.json:
#   "Stop": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/capture-lesson.sh"}]}]
#
# Input (stdin JSON):
#   transcript_path - path to conversation JSONL
#   stop_hook_active - true if already continuing from a previous stop hook
#
# Test cases:
#   # With stop_hook_active=true (loop prevention):
#   echo '{"stop_hook_active":true,"transcript_path":"/tmp/test.jsonl"}' | bash capture-lesson.sh
#   # Expected: silent exit 0
#
#   # With no [LEARN] tag in transcript:
#   echo '{"role":"assistant","content":[{"text":"normal response"}]}' > /tmp/test.jsonl
#   echo '{"stop_hook_active":false,"transcript_path":"/tmp/test.jsonl"}' | bash capture-lesson.sh
#   # Expected: silent exit 0
#
#   # With [LEARN] tag in transcript:
#   echo '{"role":"assistant","content":[{"text":"Fixed it. [LEARN] correction: Always use --no-ff for merges in this repo"}]}' > /tmp/test.jsonl
#   echo '{"stop_hook_active":false,"transcript_path":"/tmp/test.jsonl"}' | bash capture-lesson.sh
#   # Expected: JSON block with extracted lesson

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

# Extract text content and check for [LEARN] tags
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

# Extract [LEARN] tags: format is [LEARN] category: lesson text
LESSONS=$(echo "$CONTENT_TEXT" | grep -oP '\[LEARN\]\s*\w+:\s*.+' || true)

if [ -z "$LESSONS" ]; then
    exit 0
fi

# Format extracted lessons for the reason message
FORMATTED=""
while IFS= read -r lesson; do
    # Strip the [LEARN] prefix
    clean=$(echo "$lesson" | sed 's/^\[LEARN\]\s*//')
    FORMATTED="${FORMATTED}  - ${clean}\n"
done <<< "$LESSONS"

# Block and hand control back to Claude for user confirmation
jq -n --arg lessons "$FORMATTED" '{
    decision: "block",
    reason: ("Detected lesson(s) in your response:\n" + $lessons + "\nPresent each lesson to the user for confirmation. For approved lessons, write to learned.json using the /learn skill process (initialize file if needed, append to recent array with date, category, text, branch).")
}'
