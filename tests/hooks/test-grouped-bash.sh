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

print_summary
