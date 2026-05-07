#!/usr/bin/env bash
# Single source of truth for the dual-mode (match_/check_) hook set.
#
# Contract: every entry here ships a `match_<name>` predicate and a
# `check_<name>` guard body. The dispatcher (grouped-bash-guard,
# grouped-read-guard) runs match_ first; check_ runs only when match_
# returns true; check_ returns 1 ⇒ must set _BLOCK_REASON.
#
# Consumers:
#   - tests/hooks/test-match-check-pairs.sh — Shape A in-process pair tests.
#   - .claude/scripts/hook-framework/validate.sh (V21) — static contract check
#     that every `return 1` inside a check_<name> body has a `_BLOCK_REASON=`
#     assignment above it within the same function body.
#
# This file answers "which hooks expose match_/check_ pairs and what are
# they called?" — a different question from "which dispatcher routes which
# hook in what order?", which lives in lib/dispatch-order.json. Do not merge.

# Hook label → hook-file basename (no .sh). Sourcing every entry from this
# map gives both the test file and the validator one loop instead of N
# hard-coded `source` lines.
# shellcheck disable=SC2034  # consumed by sourcing scripts (test-match-check-pairs.sh, validate.sh V21)
declare -A DUAL_MODE_HOOKS=(
    [auto-mode-shared-steps]=auto-mode-shared-steps
    [block-config-edits]=block-config-edits
    [block-credential-exfiltration]=block-credential-exfiltration
    [block-dangerous-commands]=block-dangerous-commands
    [block-destructive-sql]=block-destructive-sql
    [enforce-make-commands]=enforce-make-commands
    [enforce-uv-run]=enforce-uv-run
    [git-safety]=git-safety
    [secrets-guard]=secrets-guard
    [suggest-read-json]=suggest-read-json
)

# Hook-label → match_ function name. Function names don't all follow
# `match_<hook-label>` (e.g. credential_exfil, secrets_guard_read), so the
# table resolves the label to the real function exposed by the hook.
# Multiple labels may share a hook file (block-config-edits has Bash + path
# pairs; secrets-guard has Bash + Read + Grep pairs; git-safety has Bash +
# planmode pairs).
# shellcheck disable=SC2034  # consumed by sourcing scripts (test-match-check-pairs.sh, validate.sh V21)
declare -A MATCH_FN=(
    [auto-mode-shared-steps]=match_auto_mode_shared_steps
    [block-config-edits]=match_config_edits
    [block-config-edits-path]=match_config_edits_path
    [block-credential-exfiltration]=match_credential_exfil
    [block-dangerous-commands]=match_dangerous
    [block-destructive-sql]=match_destructive_sql
    [enforce-make-commands]=match_make
    [enforce-uv-run]=match_uv
    [git-safety]=match_git_safety
    [git-safety-planmode]=match_git_safety_planmode
    [secrets-guard]=match_secrets_guard
    [secrets-guard-read]=match_secrets_guard_read
    [secrets-guard-grep]=match_secrets_guard_grep
    [suggest-read-json]=match_suggest_read_json
)

# shellcheck disable=SC2034  # consumed by sourcing scripts (test-match-check-pairs.sh, validate.sh V21)
declare -A CHECK_FN=(
    [auto-mode-shared-steps]=check_auto_mode_shared_steps
    [block-config-edits]=check_config_edits
    [block-config-edits-path]=check_config_edits_path
    [block-credential-exfiltration]=check_credential_exfil
    [block-dangerous-commands]=check_dangerous
    [block-destructive-sql]=check_destructive_sql
    [enforce-make-commands]=check_make
    [enforce-uv-run]=check_uv
    [git-safety]=check_git_safety
    [git-safety-planmode]=check_git_safety_planmode
    [secrets-guard]=check_secrets_guard
    [secrets-guard-read]=check_secrets_guard_read
    [secrets-guard-grep]=check_secrets_guard_grep
    [suggest-read-json]=check_suggest_read_json
)
