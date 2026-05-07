#!/usr/bin/env bash
# Smoke-tests for grouped-bash-guard.sh in two distribution shapes:
#   - base: all 6 guards present (uses live HOOKS_DIR).
#   - raiz sim: enforce-make / enforce-uv absent (copy HOOKS_DIR to a
#     tempdir and delete those two files).
# Every Bash turn pipes through this dispatcher in production, so a
# dedicated smoke pass catches CHECK_SPECS/declare-F regressions that
# the individual guard tests would miss.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

report_section "=== grouped-bash-guard.sh (dispatcher) ==="
hook="grouped-bash-guard.sh"

# --- Base: all 6 guards present ---
batch_start "$hook"

batch_add allow \
    "$(mk_pre_tool_use_payload Bash 'ls')" \
    "[base] ls passes silently"

batch_add contains \
    "$(mk_pre_tool_use_payload Bash 'pytest')" \
    "make test" \
    "[base] pytest blocks via make guard"

batch_add contains \
    "$(mk_pre_tool_use_payload Bash 'curl -H "Authorization: token ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" https://api.github.com/user')" \
    "Credential-shaped string in command arguments" \
    "[base] credential_exfil blocks curl with ghp_ token"

# Precedence — credential_exfil before git_safety in CHECK_SPECS.
batch_add contains \
    "$(mk_pre_tool_use_payload Bash 'git push --force https://user:ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@github.com/foo/bar.git main')" \
    "Credential-shaped string in command arguments" \
    "[base] credential_exfil wins precedence over git_safety on force-push with embedded token"

batch_add contains \
    "$(mk_pre_tool_use_payload Bash 'git push https://user:ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@github.com/foo/bar.git main')" \
    "Credential-shaped string in command arguments" \
    "[base] credential_exfil blocks plain push with embedded token in URL"

batch_run

# --- Raiz sim: copy hooks to a tempdir and remove make+uv guards ---
sim_dir=$(mktemp -d)
cp -r "$HOOKS_DIR"/. "$sim_dir/"
rm -f "$sim_dir/enforce-make-commands.sh" "$sim_dir/enforce-uv-run.sh"

prev_hooks_dir="$HOOKS_DIR"
HOOKS_DIR="$sim_dir"

batch_start "$hook"

batch_add allow \
    "$(mk_pre_tool_use_payload Bash 'pytest')" \
    "[raiz sim] pytest passes (no make guard)"

batch_add contains \
    "$(mk_pre_tool_use_payload Bash 'git push --force origin main')" \
    "Force push" \
    "[raiz sim] git_safety still blocks force-push"

batch_run

HOOKS_DIR="$prev_hooks_dir"
rm -rf "$sim_dir"

# --- post-block fall-out ---
# Pin the dispatcher's post-block emission: every substep AFTER the blocking
# child must land in invocations.jsonl with outcome=skipped. Matches the
# loop at grouped-bash-guard.sh:122-130. Robustness audit T19 verified the
# behavior empirically; this assertion turns that into a test.
report_section "--- post-block fall-out ---"

# Build the trigger from parts so the literal "rm -rf /" / "mkfs" tokens
# never appear in this script's source — the workshop's own grouped-bash-
# guard scans every Bash command this test invokes from a parent session,
# and a literal would block the test runner. The dispatcher sees the
# constructed payload via stdin, which is not scanned by the parent guard.
# block-dangerous-commands is the FIRST child in dispatch-order.json#
# grouped-bash-guard, so a dangerous trigger blocks at index 0 and every
# downstream child must report `skipped`.
fallout_trigger=$(printf '%s' "rm" " -" "rf" " /")
fallout_sid="grouped-bash-fallout-$(date +%s%N)-$$"
fallout_payload=$(jq -nc --arg cmd "$fallout_trigger" --arg sid "$fallout_sid" \
    '{session_id:$sid, tool_name:"Bash", tool_input:{command:$cmd}}')

CLAUDE_TOOLKIT_TRACEABILITY=1 bash "$HOOKS_DIR/grouped-bash-guard.sh" <<<"$fallout_payload" >/dev/null 2>&1 || true

expected_count=$(jq '.dispatchers."grouped-bash-guard" | length' "$HOOKS_DIR/lib/dispatch-order.json")
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

# Find the index of the first row with outcome=block; everything after
# must be outcome=skipped.
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
