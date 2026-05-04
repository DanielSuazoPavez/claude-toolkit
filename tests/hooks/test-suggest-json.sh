#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

report_section "=== suggest-read-json.sh ==="
hook="suggest-read-json.sh"

# Real big file for the block-on-large-json case (60 KiB > 50 KiB threshold)
tmp_big=$(mktemp --suffix=.json)
trap 'rm -f "$tmp_big"' EXIT
head -c $((60 * 1024)) /dev/urandom > "$tmp_big"

batch_start "$hook"

# Should allow (nonexistent .json — Read will surface the natural not-found error)
batch_add allow "$(mk_pre_tool_use_payload Read /project/data.json)" \
    "allows nonexistent .json (Read will surface the natural error)"
batch_add allow "$(mk_pre_tool_use_payload Read /project/output.json)" \
    "allows nonexistent .json data files"

# Should block (real file, over size threshold)
batch_add block "$(mk_pre_tool_use_payload Read "$tmp_big")" \
    "blocks real .json file over size threshold"

# Should allow (config files in allowlist — early exit before existence check)
batch_add allow "$(mk_pre_tool_use_payload Read /project/package.json)" \
    "allows package.json"
batch_add allow "$(mk_pre_tool_use_payload Read /project/tsconfig.json)" \
    "allows tsconfig.json"
batch_add allow "$(mk_pre_tool_use_payload Read /project/config.yaml)" \
    "allows non-json files"

batch_run

print_summary
