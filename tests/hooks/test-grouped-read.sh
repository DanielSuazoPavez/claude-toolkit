#!/bin/bash
# Smoke-tests for grouped-read-guard.sh — folds secrets-guard (Read branch)
# and suggest-read-json into one Read-matcher process. Grep stays on
# standalone secrets-guard.sh (not folded here).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== grouped-read-guard.sh (dispatcher) ==="
hook="grouped-read-guard.sh"

# secrets_guard_read — env/credential blocks
expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/tmp/.env"}}' \
    "[base] blocks .env via secrets_guard_read"
expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/tmp/.env.example"}}' \
    "[base] allows .env.example"
expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_rsa\"}}" \
    "[base] blocks SSH private key"
expect_allow "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_rsa.pub\"}}" \
    "[base] allows SSH public key"

# suggest_read_json — allowlist + size threshold
expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' \
    "[base] allows package.json (allowlist)"
expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' \
    "[base] blocks unknown .json (non-existent file treated as large)"

# Size-based: small real file should pass, large real file should block.
small_json=$(mktemp --suffix=.json)
echo '{"a":1}' > "$small_json"
expect_allow "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$small_json\"}}" \
    "[base] allows small .json (under threshold)"
large_json=$(mktemp --suffix=.json)
head -c 102400 /dev/zero | tr '\0' 'a' > "$large_json"
expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$large_json\"}}" \
    "[base] blocks large .json (over threshold)"
rm -f "$small_json" "$large_json"

# Grep matcher should be ignored by this dispatcher (Read-only).
expect_allow "$hook" '{"tool_name":"Grep","tool_input":{"path":"/project/.env"}}' \
    "[base] Grep passes through (not this dispatcher's matcher)"

# Distribution tolerance: copy hooks to tempdir, remove suggest-read-json;
# secrets_guard_read still blocks, large .json now passes.
sim_dir=$(mktemp -d)
cp -r "$HOOKS_DIR"/. "$sim_dir/"
rm -f "$sim_dir/suggest-read-json.sh"

prev_hooks_dir="$HOOKS_DIR"
HOOKS_DIR="$sim_dir"

expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/tmp/.env"}}' \
    "[sim] secrets_guard_read still blocks .env"
large_json=$(mktemp --suffix=.json)
head -c 102400 /dev/zero | tr '\0' 'a' > "$large_json"
expect_allow "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$large_json\"}}" \
    "[sim] large .json passes (suggest-read-json absent)"
rm -f "$large_json"

HOOKS_DIR="$prev_hooks_dir"
rm -rf "$sim_dir"

print_summary
