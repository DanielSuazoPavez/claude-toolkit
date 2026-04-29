#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== auto-mode-shared-steps.sh ==="
hook="auto-mode-shared-steps.sh"

# Helper: build payload with permission_mode set
mk() {
    local mode="$1" cmd="$2"
    jq -n --arg m "$mode" --arg c "$cmd" \
        '{tool_name:"Bash",tool_input:{command:$c},permission_mode:$m,session_id:"test"}'
}

batch_start "$hook"

# ============================================================
# No-op outside auto-mode
# ============================================================
batch_add allow "$(mk default 'git push -u origin feat/x')" \
    "no-op: git push under permission_mode=default"
batch_add allow "$(mk acceptEdits 'gh pr create --title x')" \
    "no-op: gh pr create under acceptEdits"
batch_add allow "$(mk plan 'gh api repos/foo/bar')" \
    "no-op: gh api under plan mode"
batch_add allow "$(mk '' 'git push')" \
    "no-op: empty permission_mode (treated as not-auto)"

# ============================================================
# Auto-mode: git push (any form)
# ============================================================
batch_add block "$(mk auto 'git push')" \
    "blocks bare git push under auto"
batch_add block "$(mk auto 'git push -u origin feat/x')" \
    "blocks git push -u origin feat/x under auto"
batch_add block "$(mk auto 'git push origin HEAD')" \
    "blocks git push origin HEAD under auto"
batch_add block "$(mk auto 'git push --tags')" \
    "blocks git push --tags under auto"
batch_add contains "$(mk auto 'git push')" \
    "Auto-mode shared-step gate" "block reason mentions gate"

# ============================================================
# Auto-mode: gh pr writes
# ============================================================
batch_add block "$(mk auto 'gh pr create --title foo --body bar')" \
    "blocks gh pr create"
batch_add block "$(mk auto 'gh pr merge 42')" \
    "blocks gh pr merge"
batch_add block "$(mk auto 'gh pr comment 42 --body hi')" \
    "blocks gh pr comment"
batch_add allow "$(mk auto 'gh pr view 42')" \
    "allows gh pr view (read)"
batch_add allow "$(mk auto 'gh pr list')" \
    "allows gh pr list (read)"
batch_add allow "$(mk auto 'gh pr diff 42')" \
    "allows gh pr diff (read)"

# ============================================================
# Auto-mode: gh issue / release / repo writes
# ============================================================
batch_add block "$(mk auto 'gh issue create --title foo')" \
    "blocks gh issue create"
batch_add allow "$(mk auto 'gh issue view 7')" \
    "allows gh issue view"
batch_add block "$(mk auto 'gh release create v1.0.0')" \
    "blocks gh release create"
batch_add block "$(mk auto 'gh repo create my-new-repo --public')" \
    "blocks gh repo create"
batch_add block "$(mk auto 'gh repo delete some/repo --yes')" \
    "blocks gh repo delete"
batch_add block "$(mk auto 'gh repo edit --description x')" \
    "blocks gh repo edit"
batch_add allow "$(mk auto 'gh repo view')" \
    "allows gh repo view"
batch_add allow "$(mk auto 'gh repo clone foo/bar')" \
    "allows gh repo clone"

# Cascade-and-permissions.ask reconciliation regressions (the cascade had
# 9 entries the old permissions.ask was missing — these must keep blocking
# both before and after the cascade-to-regex swap):
batch_add block "$(mk auto 'gh release download v1 --repo foo/bar')" \
    "blocks gh release download (cascade ⊃ ask reconciliation)"
batch_add block "$(mk auto 'gh repo deploy-key add ~/.ssh/id_ed25519.pub')" \
    "blocks gh repo deploy-key add"
batch_add block "$(mk auto 'gh repo unarchive foo/bar')" \
    "blocks gh repo unarchive"
batch_add block "$(mk auto 'gh repo sync')" \
    "blocks gh repo sync"
batch_add block "$(mk auto 'gh issue transfer 42 newrepo')" \
    "blocks gh issue transfer"
batch_add block "$(mk auto 'gh issue pin 42')" \
    "blocks gh issue pin"
batch_add block "$(mk auto 'gh issue lock 42')" \
    "blocks gh issue lock"

# Network egress under auto-mode: curl/wget are in permissions.ask, so
# the auto-mode hook blocks the classifier from auto-approving them.
# Reading online belongs in interactive mode where the `ask` entries
# prompt the user. No leftmost-match bypass to worry about anymore —
# every match in permissions.ask is in scope under auto-mode.
batch_add block "$(mk auto 'curl https://x && gh pr create --title y')" \
    "blocks curl-then-gh-pr-create chain"
batch_add block "$(mk auto 'wget https://x; gh release create v1')" \
    "blocks wget-then-gh-release-create chain"
batch_add block "$(mk auto 'curl https://x | gh secret set FOO')" \
    "blocks curl-pipe-gh-secret-set chain"

# ============================================================
# Auto-mode: gh secret/variable/workflow/auth
# ============================================================
batch_add block "$(mk auto 'gh secret set FOO --body bar')" \
    "blocks gh secret set"
batch_add block "$(mk auto 'gh variable set FOO --body bar')" \
    "blocks gh variable set"
batch_add block "$(mk auto 'gh workflow run deploy.yml')" \
    "blocks gh workflow run"
batch_add block "$(mk auto 'gh auth login')" \
    "blocks gh auth login"
batch_add block "$(mk auto 'gh ssh-key add ~/.ssh/id_ed25519.pub')" \
    "blocks gh ssh-key add"

# ============================================================
# Auto-mode: gh api (any — full restrictive)
# ============================================================
batch_add block "$(mk auto 'gh api repos/foo/bar')" \
    "blocks gh api (read) — full restrictive"
batch_add block "$(mk auto 'gh api -X POST repos/foo/bar/issues -f title=x')" \
    "blocks gh api -X POST"
batch_add block "$(mk auto 'gh api graphql -f query=foo')" \
    "blocks gh api graphql"

# ============================================================
# Auto-mode: curl/wget — api.github.com host
# ============================================================
batch_add block "$(mk auto 'curl https://api.github.com/user')" \
    "blocks curl to api.github.com"
batch_add block "$(mk auto 'wget https://api.github.com/user -O out')" \
    "blocks wget to api.github.com"

# ============================================================
# Auto-mode: curl/wget — Authorization header (any host)
# ============================================================
batch_add block "$(mk auto 'curl -H "Authorization: token ghp_abc" https://internal.example/api')" \
    "blocks curl with Authorization: token"
batch_add block "$(mk auto 'curl -H "Authorization: Bearer x" https://api.example.com/v1')" \
    "blocks curl with Authorization: Bearer"
batch_add block "$(mk auto "curl -H 'authorization: Basic abc=' https://x.com")" \
    "blocks curl with lowercase authorization: Basic"

# ============================================================
# Auto-mode: curl/wget always blocks (network egress out of scope)
# ============================================================
# Reading online belongs in interactive mode where Bash(curl:*) /
# Bash(wget:*) in permissions.ask prompts the user. Under auto-mode
# the hook blocks the classifier from auto-approving them — no
# carve-outs.
batch_add block "$(mk auto 'curl https://docs.python.org/3/')" \
    "blocks bare curl (network egress not allowed under auto-mode)"
batch_add block "$(mk auto 'curl -O https://example.com/file.tar.gz')" \
    "blocks simple curl download"
batch_add block "$(mk auto 'wget https://example.com/x')" \
    "blocks simple wget"

# ============================================================
# Auto-mode: unrelated commands pass
# ============================================================
batch_add allow "$(mk auto 'ls -la')" \
    "allows ls under auto"
batch_add allow "$(mk auto 'git status')" \
    "allows git status under auto"
batch_add allow "$(mk auto 'git pull')" \
    "allows git pull under auto"
batch_add allow "$(mk auto 'make check')" \
    "allows make check under auto"

# ============================================================
# False-positive avoidance: tokens inside quoted/heredoc content
# ============================================================
batch_add allow "$(mk auto 'echo "to push run: git push"')" \
    "allows git push inside double-quoted string under auto"

batch_run

# ============================================================
# Source-of-truth: hook reads settings.json permissions.ask via the
# settings-permissions loader. Drive CLAUDE_TOOLKIT_SETTINGS_JSON at
# fixture files to verify the list is genuinely sourced (not hardcoded).
# ============================================================
report_section "  --- Source-of-truth via CLAUDE_TOOLKIT_SETTINGS_JSON ---"

run_hook_with_settings() {
    local settings_path="$1" payload="$2"
    CLAUDE_TOOLKIT_SETTINGS_JSON="$settings_path" \
        bash .claude/hooks/auto-mode-shared-steps.sh <<< "$payload"
}

assert_block() {
    local desc="$1" out="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$out" == *'"decision": "block"'* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "expected block, got: $out"
    fi
}

assert_allow() {
    local desc="$1" out="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -z "$out" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "expected allow (silent), got: $out"
    fi
}

# Case 1 (positive): synthetic Bash(gh foo bar:*) in fixture's
# permissions.ask. The cascade never had this; only a settings-driven
# hook can block it.
SOT_FX1=$(mktemp -d)
cat > "$SOT_FX1/settings.json" <<'JSON'
{"permissions":{"allow":[],"ask":["Bash(gh foo bar:*)"]}}
JSON
out=$(run_hook_with_settings "$SOT_FX1/settings.json" "$(mk auto 'gh foo bar baz')")
assert_block "blocks synthetic 'gh foo bar baz' from fixture permissions.ask" "$out"
trash-put "$SOT_FX1" 2>/dev/null || true

# Case 2 (negative): fixture has no Bash(gh pr create:*). The hook must
# NOT block — proves the list is truly sourced from the env-var-pointed
# file (real settings.json HAS gh pr create, so an unsupervised reader
# would mis-read).
SOT_FX2=$(mktemp -d)
cat > "$SOT_FX2/settings.json" <<'JSON'
{"permissions":{"allow":[],"ask":[]}}
JSON
out=$(run_hook_with_settings "$SOT_FX2/settings.json" "$(mk auto 'gh pr create --title x')")
assert_allow "does NOT block 'gh pr create' when fixture omits it" "$out"
trash-put "$SOT_FX2" 2>/dev/null || true

# Case 3: settings.local.json is intentionally ignored. Only
# settings.local.json carries Bash(gh foo bar:*); settings.json is empty.
# Hook must NOT block.
SOT_FX3=$(mktemp -d)
cat > "$SOT_FX3/settings.json" <<'JSON'
{"permissions":{"allow":[],"ask":[]}}
JSON
cat > "$SOT_FX3/settings.local.json" <<'JSON'
{"permissions":{"allow":[],"ask":["Bash(gh foo bar:*)"]}}
JSON
out=$(run_hook_with_settings "$SOT_FX3/settings.json" "$(mk auto 'gh foo bar baz')")
assert_allow "does NOT block 'gh foo bar baz' when only settings.local.json has it" "$out"
trash-put "$SOT_FX3" 2>/dev/null || true

# Case 4: curl is in permissions.ask, so auto-mode blocks the classifier
# from auto-approving it — even a benign no-auth GET. Network egress
# belongs in interactive mode where the `ask` entry prompts.
SOT_FX4=$(mktemp -d)
cat > "$SOT_FX4/settings.json" <<'JSON'
{"permissions":{"allow":[],"ask":["Bash(curl:*)","Bash(wget:*)"]}}
JSON
out=$(run_hook_with_settings "$SOT_FX4/settings.json" "$(mk auto 'curl https://docs.python.org/3/')")
assert_block "blocks benign curl under auto-mode (in permissions.ask)" "$out"

# Case 5: wget mirrors curl
out=$(run_hook_with_settings "$SOT_FX4/settings.json" "$(mk auto 'wget https://example.com/file.zip')")
assert_block "blocks benign wget under auto-mode (in permissions.ask)" "$out"
trash-put "$SOT_FX4" 2>/dev/null || true

print_summary
