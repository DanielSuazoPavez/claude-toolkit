#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== git-safety.sh ==="
hook="git-safety.sh"

temp_dir=$(mktemp -d)
counters_file=$(mktemp)

(
    cd "$temp_dir"
    HOOKS_DIR="$OLDPWD/$HOOKS_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "initial"

    # ---------- Protected branch (main): only commit/plan-mode protections ----------
    git checkout -q -b main 2>/dev/null || git checkout -q main

    batch_start "$hook"
    batch_add block '{"tool_name":"EnterPlanMode"}' \
        "blocks EnterPlanMode on main"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "blocks git commit on main"
    batch_add allow "$(jq -n --arg cmd 'echo "run: git commit -m foo"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "allows git commit word inside double-quoted string on main"
    batch_add allow "$(jq -n --arg cmd $'cat <<EOF\nremember: git commit works on feature branches\nEOF' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "allows git commit inside heredoc body on main"
    batch_run

    # ---------- Feature branch: push variants + plan-mode/commit allows ----------
    git checkout -q -b feature/test

    batch_start "$hook"
    batch_add allow '{"tool_name":"EnterPlanMode"}' \
        "allows EnterPlanMode on feature branch"
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "allows git commit on feature branch"

    # Severe: force push to protected
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
        "blocks force push to main (--force)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
        "not reversible" "severe: force push to protected (--force)"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' \
        "blocks force push to main (-f)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' \
        "not reversible" "severe: force push to protected (-f)"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' \
        "blocks force push to main (trailing --force)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' \
        "not reversible" "severe: force push to protected (trailing)"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}' \
        "blocks force-with-lease to main"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}' \
        "not reversible" "severe: force-with-lease to protected"

    # Severe: git push --mirror
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push --mirror"}}' \
        "blocks git push --mirror"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push --mirror"}}' \
        "not reversible" "severe: mirror push"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push --mirror origin"}}' \
        "blocks git push --mirror with remote"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push --mirror origin"}}' \
        "not reversible" "severe: mirror push with remote"

    # Severe: delete protected branch on remote
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin main"}}' \
        "blocks delete main (--delete)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin main"}}' \
        "not reversible" "severe: delete protected (--delete main)"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push origin :main"}}' \
        "blocks delete main (colon syntax)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push origin :main"}}' \
        "not reversible" "severe: delete protected (colon main)"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin master"}}' \
        "blocks delete master (--delete)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin master"}}' \
        "not reversible" "severe: delete protected (--delete master)"

    # Soft: force push to non-protected branch
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature-branch"}}' \
        "blocks force push to non-protected branch"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature-branch"}}' \
        "rewrites remote history" "soft: force push non-protected"

    # Soft: delete any remote branch
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin feature-branch"}}' \
        "blocks delete non-protected remote branch (--delete)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin feature-branch"}}' \
        "removes it for all" "soft: delete non-protected (--delete)"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push origin :feature-branch"}}' \
        "blocks delete non-protected remote branch (colon)"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push origin :feature-branch"}}' \
        "removes it for all" "soft: delete non-protected (colon)"

    # Soft: cross-branch push
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:other-branch"}}' \
        "blocks cross-branch push"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:other-branch"}}' \
        "accidentally overwrite" "soft: cross-branch push"

    # Allow: safe operations (run on feature/test branch — matches original behavior)
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
        "allows simple push"
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
        "allows non-force push to main"
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feature"}}' \
        "allows push -u (not -f)"
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/test"}}' \
        "allows normal push to feature branch"
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/test:feature/test"}}' \
        "allows refspec push to same branch"

    # Passthrough
    batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"test.txt"}}' \
        "allows non-Bash/non-EnterPlanMode tools"
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
        "allows non-git bash commands"
    batch_run

    # ---------- Detached HEAD ----------
    git checkout --detach HEAD 2>/dev/null

    batch_start "$hook"
    batch_add block '{"tool_name":"EnterPlanMode"}' \
        "blocks EnterPlanMode in detached HEAD"
    batch_add contains '{"tool_name":"EnterPlanMode"}' \
        "detached HEAD" "detached HEAD: EnterPlanMode"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "blocks git commit in detached HEAD"
    batch_add contains '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "detached HEAD" "detached HEAD: git commit"
    batch_run

    # ---------- master branch ----------
    git checkout -q -b master 2>/dev/null

    batch_start "$hook"
    batch_add block '{"tool_name":"EnterPlanMode"}' \
        "blocks EnterPlanMode on master"
    batch_add block '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "blocks git commit on master"
    batch_run

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

    batch_start "$hook"
    batch_add allow '{"tool_name":"EnterPlanMode"}' \
        "allows EnterPlanMode outside git repo"
    batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
        "allows git commit outside git repo"
    batch_run

    echo "$TESTS_RUN $TESTS_PASSED $TESTS_FAILED" > "$nogit_counters"
)

read -r sub_run sub_passed sub_failed < "$nogit_counters"
TESTS_RUN=$((TESTS_RUN + sub_run))
TESTS_PASSED=$((TESTS_PASSED + sub_passed))
TESTS_FAILED=$((TESTS_FAILED + sub_failed))
rm -rf "$nogit_dir" "$nogit_counters"

print_summary
