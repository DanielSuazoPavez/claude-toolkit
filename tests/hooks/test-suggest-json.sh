#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== suggest-read-json.sh ==="
hook="suggest-read-json.sh"

# Should block (large JSON or unknown JSON)
expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' \
    "blocks unknown .json files"
expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/output.json"}}' \
    "blocks data .json files"

# Should allow (config files in allowlist)
expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' \
    "allows package.json"
expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/tsconfig.json"}}' \
    "allows tsconfig.json"
expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' \
    "allows non-json files"

print_summary
