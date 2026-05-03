#!/usr/bin/env bash
# Shape A test layer for the 9 dual-mode hooks: source each hook, call
# match_*/check_* in-process, assert on rc + _BLOCK_REASON. ~0ms per case
# (no fork). Locks in the predicate boundary and the predicate-vs-check
# contract that grouped-bash-guard / grouped-read-guard rely on, alongside
# the existing Shape B end-to-end coverage.
#
# Plan: backlog hook-audit-01-shape-a-match-check-pairs.
# Background: design/hook-audit/01-standardized/testability.md.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"

source "$SCRIPT_DIR/../lib/test-helpers.sh"
parse_test_args "$@"

# Source the 9 dual-mode hooks. Each hook's `if [[ "${BASH_SOURCE[0]}" ==
# "${0}" ]]; then main "$@"; fi` guard means main() does NOT fire on source.
# Confirmed by inspection of every dual-mode hook file.
source "$HOOKS_DIR/auto-mode-shared-steps.sh"
source "$HOOKS_DIR/block-config-edits.sh"
source "$HOOKS_DIR/block-credential-exfiltration.sh"
source "$HOOKS_DIR/block-dangerous-commands.sh"
source "$HOOKS_DIR/enforce-make-commands.sh"
source "$HOOKS_DIR/enforce-uv-run.sh"
source "$HOOKS_DIR/git-safety.sh"
source "$HOOKS_DIR/secrets-guard.sh"
source "$HOOKS_DIR/suggest-read-json.sh"

print_summary
