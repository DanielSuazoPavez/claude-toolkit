#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== suggest-read-json.sh ==="
hook="suggest-read-json.sh"

# Real big file for the block-on-large-json case (60 KiB > 50 KiB threshold)
tmp_big=$(mktemp --suffix=.json)
trap 'rm -f "$tmp_big"' EXIT
head -c $((60 * 1024)) /dev/urandom > "$tmp_big"

batch_start "$hook"

# Should allow (nonexistent .json — Read will surface the natural not-found error)
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' \
    "allows nonexistent .json (Read will surface the natural error)"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/output.json"}}' \
    "allows nonexistent .json data files"

# Should block (real file, over size threshold)
batch_add block "$(jq -n --arg p "$tmp_big" '{tool_name:"Read",tool_input:{file_path:$p}}')" \
    "blocks real .json file over size threshold"

# Should allow (config files in allowlist — early exit before existence check)
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' \
    "allows package.json"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/tsconfig.json"}}' \
    "allows tsconfig.json"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' \
    "allows non-json files"

batch_run

print_summary
