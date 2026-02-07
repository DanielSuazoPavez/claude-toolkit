#!/bin/bash
# PreToolUse hook: suggest /read-json skill for JSON files
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash .claude/hooks/suggest-read-json.sh"}]}]
#
# Environment:
#   JSON_SIZE_THRESHOLD_KB - size threshold in KB (default: 50). Files smaller than this are allowed.
#
# Blocks:
#   - Large .json files (> threshold)
#   - Excludes common config files by default
#
# Reason:
#   JSON files can be large; /read-json uses jq for efficient querying
#
# Test cases:
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' | bash suggest-read-json.sh
#   # Expected: {"decision":"block","reason":"..."} (if file > threshold)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' | bash suggest-read-json.sh
#   # Expected: (empty - allowed, in allowlist)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/small.json"}}' | bash suggest-read-json.sh
#   # Expected: (empty - allowed, under threshold)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' | bash suggest-read-json.sh
#   # Expected: (empty - not json)

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
if [ "$TOOL_NAME" != "Read" ]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

# Check if file ends with .json
if [[ ! "$FILE_PATH" =~ \.json$ ]]; then
    exit 0
fi

# Get filename for pattern matching
FILENAME=$(basename "$FILE_PATH")

# Allowed config files (common small files that don't need jq)
ALLOWED_FILES="package.json,package-lock.json,tsconfig.json,jsconfig.json,composer.json,manifest.json,.prettierrc.json,.eslintrc.json,turbo.json,vercel.json,nest-cli.json,angular.json,nx.json"

# Check if filename matches an allowed file
IFS=',' read -ra PATTERNS <<< "$ALLOWED_FILES"
for pattern in "${PATTERNS[@]}"; do
    if [[ "$FILENAME" == "$pattern" ]]; then
        exit 0
    fi
done

# Also allow *.config.json pattern
if [[ "$FILENAME" =~ \.config\.json$ ]]; then
    exit 0
fi

# Check file size if file exists
SIZE_THRESHOLD_KB="${JSON_SIZE_THRESHOLD_KB:-50}"
if [ -f "$FILE_PATH" ]; then
    FILE_SIZE_KB=$(( $(stat -c%s "$FILE_PATH" 2>/dev/null || stat -f%z "$FILE_PATH" 2>/dev/null || echo 0) / 1024 ))
    if [ "$FILE_SIZE_KB" -lt "$SIZE_THRESHOLD_KB" ]; then
        exit 0
    fi
fi

# Block — suggest /read-json
echo "{\"decision\": \"block\", \"reason\": \"Use \`/read-json\` skill for JSON files — it uses jq for efficient querying instead of loading entire files.\"}"
exit 0
