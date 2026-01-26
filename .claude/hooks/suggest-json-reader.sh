#!/bin/bash
# PreToolUse hook: suggest /read-json skill for JSON files
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash .claude/hooks/suggest-json-reader.sh"}]}]
#
# Environment:
#   ALLOW_JSON_READ=1  - bypass completely (allow all raw JSON reads)
#   JSON_READ_WARN=1   - warn instead of block (educational mode)
#   JSON_SIZE_THRESHOLD_KB - size threshold in KB (default: 50). Files smaller than this are allowed.
#   ALLOW_JSON_PATTERNS - comma-separated filenames to always allow (default: package.json,tsconfig.json,composer.json,*.config.json)
#
# Blocks:
#   - Large .json files (> threshold)
#   - Excludes common config files by default
#
# Reason:
#   JSON files can be large; /read-json uses jq for efficient querying
#
# Test cases:
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' | ./suggest-json-reader.sh
#   # Expected: {"decision":"block","reason":"..."} (if file > threshold)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' | ./suggest-json-reader.sh
#   # Expected: (empty - allowed, in default allowlist)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' | ./suggest-json-reader.sh
#   # Expected: (empty - allowed, not json)

# Allowlist: skip if explicitly allowed
[ -n "$ALLOW_JSON_READ" ] && exit 0

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

# Default allowed patterns (common small config files)
DEFAULT_PATTERNS="package.json,package-lock.json,tsconfig.json,jsconfig.json,composer.json,manifest.json,.prettierrc.json,.eslintrc.json,turbo.json,vercel.json,nest-cli.json,angular.json,nx.json"
ALLOWED_PATTERNS="${ALLOW_JSON_PATTERNS:-$DEFAULT_PATTERNS}"

# Check if filename matches an allowed pattern
IFS=',' read -ra PATTERNS <<< "$ALLOWED_PATTERNS"
for pattern in "${PATTERNS[@]}"; do
    # Support wildcard patterns like *.config.json
    if [[ "$pattern" == *"*"* ]]; then
        # Convert glob to regex: *.config.json -> .*\.config\.json
        regex_pattern=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
        if [[ "$FILENAME" =~ ^${regex_pattern}$ ]]; then
            exit 0
        fi
    elif [[ "$FILENAME" == "$pattern" ]]; then
        exit 0
    fi
done

# Check file size if file exists
SIZE_THRESHOLD_KB="${JSON_SIZE_THRESHOLD_KB:-50}"
if [ -f "$FILE_PATH" ]; then
    FILE_SIZE_KB=$(( $(stat -c%s "$FILE_PATH" 2>/dev/null || stat -f%z "$FILE_PATH" 2>/dev/null || echo 0) / 1024 ))
    if [ "$FILE_SIZE_KB" -lt "$SIZE_THRESHOLD_KB" ]; then
        exit 0
    fi
fi

# Build message
MESSAGE="Use \`/read-json\` skill for JSON files. It uses jq for efficient querying instead of loading entire files. Set ALLOW_JSON_READ=1 to bypass."

# Warn mode: output suggestion but don't block
if [ -n "$JSON_READ_WARN" ]; then
    echo "{\"decision\": \"allow\", \"message\": \"$MESSAGE\"}"
    exit 0
fi

# Block mode (default)
echo "{\"decision\": \"block\", \"reason\": \"$MESSAGE\"}"
exit 0
