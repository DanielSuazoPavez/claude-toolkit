#!/usr/bin/env bash
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

# Size-based fixtures — must exist on disk before batching.
_tmp=$(mktemp); small_json="${_tmp}.json"; mv "$_tmp" "$small_json"
echo '{"a":1}' > "$small_json"
_tmp=$(mktemp); large_json="${_tmp}.json"; mv "$_tmp" "$large_json"
head -c 102400 /dev/zero | tr '\0' 'a' > "$large_json"

# --- Base: full hook set ---
batch_start "$hook"

# secrets_guard_read — env/credential blocks
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/tmp/.env"}}' \
    "[base] blocks .env via secrets_guard_read"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/tmp/.env.example"}}' \
    "[base] allows .env.example"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_rsa\"}}" \
    "[base] blocks SSH private key"
batch_add allow "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_rsa.pub\"}}" \
    "[base] allows SSH public key"

# suggest_read_json — allowlist + size threshold
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' \
    "[base] allows package.json (allowlist)"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' \
    "[base] allows nonexistent .json (Read will surface the natural error)"
batch_add allow "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$small_json\"}}" \
    "[base] allows small .json (under threshold)"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$large_json\"}}" \
    "[base] blocks large .json (over threshold)"

# Grep matcher should be ignored by this dispatcher (Read-only).
batch_add allow '{"tool_name":"Grep","tool_input":{"path":"/project/.env"}}' \
    "[base] Grep passes through (not this dispatcher's matcher)"

batch_run

rm -f "$small_json" "$large_json"

# --- Distribution tolerance: drop suggest-read-json from sim ---
sim_dir=$(mktemp -d)
cp -r "$HOOKS_DIR"/. "$sim_dir/"
rm -f "$sim_dir/suggest-read-json.sh"

prev_hooks_dir="$HOOKS_DIR"
HOOKS_DIR="$sim_dir"

_tmp=$(mktemp); large_json="${_tmp}.json"; mv "$_tmp" "$large_json"
head -c 102400 /dev/zero | tr '\0' 'a' > "$large_json"

batch_start "$hook"

batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/tmp/.env"}}' \
    "[sim] secrets_guard_read still blocks .env"
batch_add allow "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$large_json\"}}" \
    "[sim] large .json passes (suggest-read-json absent)"

batch_run

rm -f "$large_json"
HOOKS_DIR="$prev_hooks_dir"
rm -rf "$sim_dir"

print_summary
