#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== git-safety.sh ==="
hook="git-safety.sh"

# Create temp git repo for testing
temp_dir=$(mktemp -d)
counters_file=$(mktemp)

# Run in subshell (needed for cd into temp git repo)
# Write counters to temp file so parent can read them back
(
    cd "$temp_dir"
    HOOKS_DIR="$OLDPWD/$HOOKS_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "initial"

    # Test on main branch
    git checkout -q -b main 2>/dev/null || git checkout -q main

    # --- Protected branch enforcement ---

    expect_block "$hook" '{"tool_name":"EnterPlanMode"}' \
        "blocks EnterPlanMode on main"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "blocks git commit on main"

    expect_allow "$hook" "$(jq -n --arg cmd 'echo "run: git commit -m foo"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "allows git commit word inside double-quoted string on main"
    expect_allow "$hook" "$(jq -n --arg cmd $'cat <<EOF\nremember: git commit works on feature branches\nEOF' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "allows git commit inside heredoc body on main"

    # Switch to feature branch
    git checkout -q -b feature/test

    expect_allow "$hook" '{"tool_name":"EnterPlanMode"}' \
        "allows EnterPlanMode on feature branch"

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "allows git commit on feature branch"

    # --- Severe: force push to protected branch ---

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
        "blocks force push to main (--force)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
        "not reversible" "severe: force push to protected (--force)"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' \
        "blocks force push to main (-f)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' \
        "not reversible" "severe: force push to protected (-f)"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' \
        "blocks force push to main (trailing --force)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' \
        "not reversible" "severe: force push to protected (trailing)"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}' \
        "blocks force-with-lease to main"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}' \
        "not reversible" "severe: force-with-lease to protected"

    # --- Severe: git push --mirror ---

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror"}}' \
        "blocks git push --mirror"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror"}}' \
        "not reversible" "severe: mirror push"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror origin"}}' \
        "blocks git push --mirror with remote"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror origin"}}' \
        "not reversible" "severe: mirror push with remote"

    # --- Severe: delete protected branch on remote ---

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin main"}}' \
        "blocks delete main (--delete)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin main"}}' \
        "not reversible" "severe: delete protected (--delete main)"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :main"}}' \
        "blocks delete main (colon syntax)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :main"}}' \
        "not reversible" "severe: delete protected (colon main)"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin master"}}' \
        "blocks delete master (--delete)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin master"}}' \
        "not reversible" "severe: delete protected (--delete master)"

    # --- Soft: force push to non-protected branch ---

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature-branch"}}' \
        "blocks force push to non-protected branch"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature-branch"}}' \
        "rewrites remote history" "soft: force push non-protected"

    # --- Soft: delete any remote branch ---

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin feature-branch"}}' \
        "blocks delete non-protected remote branch (--delete)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin feature-branch"}}' \
        "removes it for all" "soft: delete non-protected (--delete)"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :feature-branch"}}' \
        "blocks delete non-protected remote branch (colon)"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :feature-branch"}}' \
        "removes it for all" "soft: delete non-protected (colon)"

    # --- Soft: cross-branch push ---

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:other-branch"}}' \
        "blocks cross-branch push"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:other-branch"}}' \
        "accidentally overwrite" "soft: cross-branch push"

    # --- Allow: safe operations ---

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
        "allows simple push"

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
        "allows non-force push to main"

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feature"}}' \
        "allows push -u (not -f)"

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/test"}}' \
        "allows normal push to feature branch"

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/test:feature/test"}}' \
        "allows refspec push to same branch"

    # --- Passthrough ---

    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"test.txt"}}' \
        "allows non-Bash/non-EnterPlanMode tools"

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
        "allows non-git bash commands"

    # --- Detached HEAD state ---

    git checkout --detach HEAD 2>/dev/null

    expect_block "$hook" '{"tool_name":"EnterPlanMode"}' \
        "blocks EnterPlanMode in detached HEAD"
    expect_contains "$hook" '{"tool_name":"EnterPlanMode"}' \
        "detached HEAD" "detached HEAD: EnterPlanMode"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "blocks git commit in detached HEAD"
    expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "detached HEAD" "detached HEAD: git commit"

    # --- Master branch protection ---

    git checkout -q -b master 2>/dev/null

    expect_block "$hook" '{"tool_name":"EnterPlanMode"}' \
        "blocks EnterPlanMode on master"

    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "blocks git commit on master"

    echo "$TESTS_RUN $TESTS_PASSED $TESTS_FAILED" > "$counters_file"
)

read -r sub_run sub_passed sub_failed < "$counters_file"
TESTS_RUN=$((TESTS_RUN + sub_run))
TESTS_PASSED=$((TESTS_PASSED + sub_passed))
TESTS_FAILED=$((TESTS_FAILED + sub_failed))

rm -rf "$temp_dir" "$counters_file"

# --- Non-git directory tests (separate subshell) ---
nogit_dir=$(mktemp -d)
nogit_counters=$(mktemp)

(
    cd "$nogit_dir"
    HOOKS_DIR="$OLDPWD/$HOOKS_DIR"

    expect_allow "$hook" '{"tool_name":"EnterPlanMode"}' \
        "allows EnterPlanMode outside git repo"

    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "allows git commit outside git repo"

    echo "$TESTS_RUN $TESTS_PASSED $TESTS_FAILED" > "$nogit_counters"
)

read -r sub_run sub_passed sub_failed < "$nogit_counters"
TESTS_RUN=$((TESTS_RUN + sub_run))
TESTS_PASSED=$((TESTS_PASSED + sub_passed))
TESTS_FAILED=$((TESTS_FAILED + sub_failed))
rm -rf "$nogit_dir" "$nogit_counters"

print_summary
