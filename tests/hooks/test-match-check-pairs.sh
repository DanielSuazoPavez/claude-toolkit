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

# ============================================================
# Hook-label → match_/check_ function-name dispatch table
# ============================================================
# Function names don't all match `match_<hook-label>` (e.g. credential_exfil,
# secrets_guard_read). The label is the test-facing identifier; the table
# resolves it to the real function names exposed by the sourced hook.
_match_fn_for() {
    case "$1" in
        auto-mode-shared-steps)        echo match_auto_mode_shared_steps ;;
        block-config-edits)            echo match_config_edits ;;
        block-credential-exfiltration) echo match_credential_exfil ;;
        block-dangerous-commands)      echo match_dangerous ;;
        enforce-make-commands)         echo match_make ;;
        enforce-uv-run)                echo match_uv ;;
        git-safety)                    echo match_git_safety ;;
        secrets-guard)                 echo match_secrets_guard ;;
        secrets-guard-read)            echo match_secrets_guard_read ;;
        secrets-guard-grep)            echo match_secrets_guard_grep ;;
        suggest-read-json)             echo match_suggest_read_json ;;
        *) echo "ERR_NO_MATCH_FN_FOR_$1" ;;
    esac
}
_check_fn_for() {
    case "$1" in
        auto-mode-shared-steps)        echo check_auto_mode_shared_steps ;;
        block-config-edits)            echo check_config_edits ;;
        block-credential-exfiltration) echo check_credential_exfil ;;
        block-dangerous-commands)      echo check_dangerous ;;
        enforce-make-commands)         echo check_make ;;
        enforce-uv-run)                echo check_uv ;;
        git-safety)                    echo check_git_safety ;;
        secrets-guard)                 echo check_secrets_guard ;;
        secrets-guard-read)            echo check_secrets_guard_read ;;
        secrets-guard-grep)            echo check_secrets_guard_grep ;;
        suggest-read-json)             echo check_suggest_read_json ;;
        *) echo "ERR_NO_CHECK_FN_FOR_$1" ;;
    esac
}

# ============================================================
# Local assertion helpers
# ============================================================
# Each helper:
#   1. Increments TESTS_RUN.
#   2. Calls the resolved function from the sourced hook directly.
#   3. Asserts on rc (and _BLOCK_REASON for check_block).
# Caller is responsible for clearing/setting input vars (COMMAND, FILE_PATH,
# GREP_PATH, GREP_GLOB, PERMISSION_MODE, _BLOCK_REASON) before invoking.

assert_match_hit() {
    local label="$1" desc="$2"
    local fn; fn=$(_match_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$fn"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=0 (match), got rc=$?"
    fi
}

assert_match_miss() {
    local label="$1" desc="$2"
    local fn; fn=$(_match_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! "$fn"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=1 (no match), got rc=0"
    fi
}

assert_check_pass() {
    local label="$1" desc="$2"
    local fn; fn=$(_check_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    _BLOCK_REASON=""
    if "$fn"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=0 (pass), got rc=1"
        report_detail "_BLOCK_REASON: ${_BLOCK_REASON:-<empty>}"
    fi
}

assert_check_block() {
    local label="$1" reason_substr="$2" desc="$3"
    local fn; fn=$(_check_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    _BLOCK_REASON=""
    if "$fn"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=1 (block), got rc=0"
        return
    fi
    if [[ "$_BLOCK_REASON" == *"$reason_substr"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
        log_verbose "_BLOCK_REASON contained: $reason_substr"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected _BLOCK_REASON to contain: $reason_substr"
        report_detail "Got: ${_BLOCK_REASON:-<empty>}"
    fi
}

# ============================================================
# enforce-make-commands
# ============================================================
report_section "enforce-make-commands"

COMMAND="ls -la"
assert_match_miss enforce-make-commands "match_make misses on ls"

COMMAND="echo hello"
assert_match_miss enforce-make-commands "match_make misses on echo"

COMMAND="uv run pytest tests/foo.py"
assert_match_hit  enforce-make-commands "match_make hits on targeted pytest"
assert_check_pass enforce-make-commands "check_make passes on targeted pytest run"

COMMAND="pytest"
assert_match_hit   enforce-make-commands "match_make hits on bare pytest"
assert_check_block enforce-make-commands "make test" "check_make blocks bare pytest with make-test hint"

COMMAND="pre-commit run --all-files"
assert_check_block enforce-make-commands "make lint" "check_make blocks pre-commit with make-lint hint"

# ============================================================
# enforce-uv-run
# ============================================================
report_section "enforce-uv-run"

COMMAND="ls -la"
assert_match_miss enforce-uv-run "match_uv misses on ls"

# Heredoc body containing `python` is blanked by _strip_inert_content,
# so the predicate must NOT fire — protects against false positives on
# heredoc/quoted bodies.
COMMAND='cat <<EOF
this is python code
EOF'
assert_match_miss enforce-uv-run "match_uv misses when python is only inside a heredoc body"

COMMAND='echo "running python script"'
assert_match_miss enforce-uv-run "match_uv misses when python is only inside double-quoted string"

COMMAND="uv run python script.py"
assert_match_hit  enforce-uv-run "match_uv hits on uv run python"
assert_check_pass enforce-uv-run "check_uv passes when uv run is present"

COMMAND="python script.py"
assert_match_hit   enforce-uv-run "match_uv hits on bare python"
assert_check_block enforce-uv-run "uv run python" "check_uv blocks bare python with uv-run hint"

COMMAND="python3 -m pytest"
assert_check_block enforce-uv-run "uv run python" "check_uv blocks bare python3 with uv-run hint"

# ============================================================
# suggest-read-json
# ============================================================
report_section "suggest-read-json"

# Predicate fires only on .json suffix
FILE_PATH="/tmp/data.txt"
assert_match_miss suggest-read-json "match_suggest_read_json misses on .txt"

# Allowlisted basename — predicate fires, check passes
FILE_PATH="/tmp/package.json"
assert_match_hit  suggest-read-json "match_suggest_read_json hits on .json"
assert_check_pass suggest-read-json "check_suggest_read_json allows allowlisted package.json"

# *.config.json pattern is allowlisted
FILE_PATH="/tmp/eslint.config.json"
assert_check_pass suggest-read-json "check_suggest_read_json allows *.config.json pattern"

# Nonexistent file — fail-open (the robustness-flagged behavior; lock it in
# so any future tightening of this branch lands as a deliberate change).
FILE_PATH="/tmp/this-file-definitely-does-not-exist-$$.json"
assert_check_pass suggest-read-json "check_suggest_read_json fail-opens on nonexistent file"

# Small file under threshold — pass through
_smol_json=$(mktemp --suffix=.json)
printf '{"x":1}' > "$_smol_json"
FILE_PATH="$_smol_json"
assert_check_pass suggest-read-json "check_suggest_read_json passes on small json under threshold"
rm -f "$_smol_json"

# Large file over threshold (default 50 KB) — block with jq hint
_big_json=$(mktemp --suffix=.json)
# 60 KB of payload
printf '{"data":"%s"}' "$(head -c 61440 /dev/urandom | base64 | tr -d '\n' | head -c 61440)" > "$_big_json"
FILE_PATH="$_big_json"
assert_check_block suggest-read-json "jq via Bash" "check_suggest_read_json blocks oversized json with jq hint"
rm -f "$_big_json"

# ============================================================
# block-credential-exfiltration
# ============================================================
report_section "block-credential-exfiltration"

COMMAND="ls -la"
assert_match_miss block-credential-exfiltration "match_credential_exfil misses on ls"

COMMAND="git status"
assert_match_miss block-credential-exfiltration "match_credential_exfil misses on git status"

# GitHub PAT in argument — canonical exfil shape
COMMAND='curl -H "Authorization: token ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"'
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on ghp_ token"
assert_check_block block-credential-exfiltration "Credential-shaped" "check_credential_exfil blocks ghp_ token in args"

# AWS access key
COMMAND="aws s3 ls --profile leak AKIAIOSFODNN7EXAMPLE"
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on AKIA access key"
assert_check_block block-credential-exfiltration "Credential-shaped" "check_credential_exfil blocks AKIA key"

# Authorization header literal
COMMAND='curl -H "Authorization: Bearer xyz"'
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on Authorization: Bearer header"

# Credential env-var ref
COMMAND='curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user'
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on \$GITHUB_TOKEN ref"

# ============================================================
# auto-mode-shared-steps
# ============================================================
# Predicate is purely PERMISSION_MODE == "auto"; check_ runs the
# settings-derived permissions.ask regex on the stripped command.
# Tests assume settings.json contains `Bash(git push:*)` (loaded at
# source-time by settings_permissions_load).
report_section "auto-mode-shared-steps"

PERMISSION_MODE="default"
COMMAND="git push origin main"
assert_match_miss auto-mode-shared-steps "match_ misses when permission_mode != auto (default)"

PERMISSION_MODE="acceptEdits"
assert_match_miss auto-mode-shared-steps "match_ misses when permission_mode != auto (acceptEdits)"

PERMISSION_MODE="plan"
assert_match_miss auto-mode-shared-steps "match_ misses when permission_mode != auto (plan)"

PERMISSION_MODE="auto"
assert_match_hit  auto-mode-shared-steps "match_ hits when permission_mode == auto"

# auto + non-publishing command → check passes
COMMAND="ls -la"
assert_check_pass auto-mode-shared-steps "check_ passes on non-publishing command under auto"

# auto + git push → check blocks; trigger captured into reason
COMMAND="git push origin feature"
assert_check_block auto-mode-shared-steps "git push" "check_ blocks git push under auto, captures trigger"

# Quoted-string mention is blanked by _strip_inert_content — must NOT block
COMMAND='echo "to push run: git push"'
assert_check_pass auto-mode-shared-steps "check_ does not block git push mentioned only inside a quoted string"

print_summary
