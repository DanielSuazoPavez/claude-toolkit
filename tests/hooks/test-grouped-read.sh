#!/usr/bin/env bash
# Smoke-tests for grouped-read-guard.sh — folds secrets-guard (Read branch)
# and suggest-read-json into one Read-matcher process. Grep stays on
# standalone secrets-guard.sh (not folded here).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
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
batch_add block "$(mk_pre_tool_use_payload Read /tmp/.env)" \
    "[base] blocks .env via secrets_guard_read"
batch_add allow "$(mk_pre_tool_use_payload Read /tmp/.env.example)" \
    "[base] allows .env.example"
batch_add block "$(mk_pre_tool_use_payload Read "$HOME/.ssh/id_rsa")" \
    "[base] blocks SSH private key"
batch_add allow "$(mk_pre_tool_use_payload Read "$HOME/.ssh/id_rsa.pub")" \
    "[base] allows SSH public key"

# suggest_read_json — allowlist + size threshold
batch_add allow "$(mk_pre_tool_use_payload Read /project/package.json)" \
    "[base] allows package.json (allowlist)"
batch_add allow "$(mk_pre_tool_use_payload Read /project/data.json)" \
    "[base] allows nonexistent .json (Read will surface the natural error)"
batch_add allow "$(mk_pre_tool_use_payload Read "$small_json")" \
    "[base] allows small .json (under threshold)"
batch_add block "$(mk_pre_tool_use_payload Read "$large_json")" \
    "[base] blocks large .json (over threshold)"

# Grep matcher should be ignored by this dispatcher (Read-only).
batch_add allow "$(mk_pre_tool_use_payload Grep '' path '/project/.env')" \
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

batch_add block "$(mk_pre_tool_use_payload Read /tmp/.env)" \
    "[sim] secrets_guard_read still blocks .env"
batch_add allow "$(mk_pre_tool_use_payload Read "$large_json")" \
    "[sim] large .json passes (suggest-read-json absent)"

batch_run

rm -f "$large_json"
HOOKS_DIR="$prev_hooks_dir"
rm -rf "$sim_dir"

# --- post-block fall-out ---
# Pin the dispatcher's post-block emission: every substep AFTER the
# blocking child must land in invocations.jsonl with outcome=skipped.
# Matches the loop at grouped-read-guard.sh:94-102. Read-side has only 2
# children, so this assertion pins exactly 1 `skipped` row — still catches
# a regression that breaks the fall-out loop entirely. Symmetry with the
# bash-side assertion is worth keeping. secrets-guard is the FIRST child
# in dispatch-order.json#grouped-read-guard, so reading .env blocks at
# index 0 and suggest-read-json downstream must report `skipped`.
report_section "--- post-block fall-out ---"

fallout_sid="grouped-read-fallout-$(date +%s%N)-$$"
fallout_payload=$(mk_pre_tool_use_payload Read /tmp/.env \
    | jq -c --arg sid "$fallout_sid" '.session_id = $sid')

CLAUDE_TOOLKIT_TRACEABILITY=1 bash "$HOOKS_DIR/grouped-read-guard.sh" <<<"$fallout_payload" >/dev/null 2>&1 || true

expected_count=$(jq '.dispatchers."grouped-read-guard" | length' "$HOOKS_DIR/lib/dispatch-order.json")
substep_rows=$(grep -F "$fallout_sid" "$TEST_INVOCATIONS_JSONL" 2>/dev/null \
    | jq -c 'select(.kind == "substep")' 2>/dev/null)
substep_count=$(printf '%s\n' "$substep_rows" | grep -c . || true)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$substep_count" = "$expected_count" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "post-block: substep row count == dispatcher child count ($expected_count)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "post-block: substep row count mismatch"
    report_detail "Expected $expected_count rows, got $substep_count"
    report_detail "Rows: $substep_rows"
fi

block_idx=$(printf '%s\n' "$substep_rows" | awk 'BEGIN{i=0} /"outcome":"block"/{print i; exit} {i++}')
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "$block_idx" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "post-block: blocking substep emitted with outcome=block (index $block_idx)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "post-block: no substep row had outcome=block"
    report_detail "Rows: $substep_rows"
fi

TESTS_RUN=$((TESTS_RUN + 1))
post_block_outcomes=$(printf '%s\n' "$substep_rows" \
    | awk -v idx="${block_idx:-0}" 'NR > idx+1 {print}' \
    | jq -r '.outcome' 2>/dev/null)
post_block_non_skipped=$(printf '%s\n' "$post_block_outcomes" | grep -v -x "skipped" | grep -v -x "" || true)
if [ -z "$post_block_non_skipped" ] && [ -n "$post_block_outcomes" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "post-block: every substep after the block has outcome=skipped"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "post-block: substep(s) after the block did not have outcome=skipped"
    report_detail "Outcomes after block: $post_block_outcomes"
fi

print_summary
