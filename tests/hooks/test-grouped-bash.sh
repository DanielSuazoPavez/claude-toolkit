#!/bin/bash
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
parse_test_args "$@"

report_section "=== grouped-bash-guard.sh (dispatcher) ==="
hook="grouped-bash-guard.sh"

# Base: benign command passes (all 6 guards present, none match).
expect_allow "$hook" \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    "[base] ls passes silently"

# Base: make guard blocks pytest.
expect_contains "$hook" \
    '{"tool_name":"Bash","tool_input":{"command":"pytest"}}' \
    "make test" \
    "[base] pytest blocks via make guard"

# Raiz sim: copy hooks to a tempdir and remove make+uv guards.
sim_dir=$(mktemp -d)
cp -r "$HOOKS_DIR"/. "$sim_dir/"
rm -f "$sim_dir/enforce-make-commands.sh" "$sim_dir/enforce-uv-run.sh"

prev_hooks_dir="$HOOKS_DIR"
HOOKS_DIR="$sim_dir"

# Raiz sim: pytest no longer blocks (make guard absent from CHECKS).
expect_allow "$hook" \
    '{"tool_name":"Bash","tool_input":{"command":"pytest"}}' \
    "[raiz sim] pytest passes (no make guard)"

# Raiz sim: git_safety still blocks force-push.
expect_contains "$hook" \
    '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
    "Force push" \
    "[raiz sim] git_safety still blocks force-push"

HOOKS_DIR="$prev_hooks_dir"
rm -rf "$sim_dir"

print_summary
