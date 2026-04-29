#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== suggest-read-json.sh ==="
hook="suggest-read-json.sh"

batch_start "$hook"

# Should block (large JSON or unknown JSON)
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' \
    "blocks unknown .json files"
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/project/output.json"}}' \
    "blocks data .json files"

# Should allow (config files in allowlist)
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' \
    "allows package.json"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/tsconfig.json"}}' \
    "allows tsconfig.json"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' \
    "allows non-json files"

batch_run

print_summary
