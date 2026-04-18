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

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# ============================================================
# match_/check_ pair for the grouped-read-guard dispatcher
# ============================================================
# Contract: dispatcher sets FILE_PATH before calling match_.
# check_ returns 0=pass, 1=block (sets _BLOCK_REASON).

match_suggest_read_json() {
    [ -n "$FILE_PATH" ] || return 1
    [[ "$FILE_PATH" =~ \.json$ ]]
}

check_suggest_read_json() {
    local filename
    filename=$(basename "$FILE_PATH")

    # Allowed config files (common small files that don't need jq)
    local ALLOWED_FILES="package.json,package-lock.json,tsconfig.json,jsconfig.json,composer.json,manifest.json,.prettierrc.json,.eslintrc.json,turbo.json,vercel.json,nest-cli.json,angular.json,nx.json"
    local IFS=','
    local -a patterns
    read -ra patterns <<< "$ALLOWED_FILES"
    for pattern in "${patterns[@]}"; do
        if [[ "$filename" == "$pattern" ]]; then
            return 0
        fi
    done

    # Also allow *.config.json pattern
    if [[ "$filename" =~ \.config\.json$ ]]; then
        return 0
    fi

    # Check file size if file exists
    local size_threshold_kb="${JSON_SIZE_THRESHOLD_KB:-50}"
    if [ -f "$FILE_PATH" ]; then
        local file_size_kb
        file_size_kb=$(( $(stat -c%s "$FILE_PATH" 2>/dev/null || stat -f%z "$FILE_PATH" 2>/dev/null || echo 0) / 1024 ))
        if [ "$file_size_kb" -lt "$size_threshold_kb" ]; then
            return 0
        fi
    fi

    _BLOCK_REASON="Use \`/read-json\` skill for JSON files — it uses jq for efficient querying instead of loading entire files."
    return 1
}

main() {
    hook_init "suggest-read-json" "PreToolUse"
    hook_require_tool "Read"

    FILE_PATH=$(hook_get_input '.tool_input.file_path')
    [ -z "$FILE_PATH" ] && exit 0

    _BLOCK_REASON=""
    if match_suggest_read_json; then
        if ! check_suggest_read_json; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
