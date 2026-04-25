#!/bin/bash
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

# ============================================================
# No-op outside auto-mode
# ============================================================
expect_allow "$hook" "$(mk default 'git push -u origin feat/x')" \
    "no-op: git push under permission_mode=default"
expect_allow "$hook" "$(mk acceptEdits 'gh pr create --title x')" \
    "no-op: gh pr create under acceptEdits"
expect_allow "$hook" "$(mk plan 'gh api repos/foo/bar')" \
    "no-op: gh api under plan mode"
expect_allow "$hook" "$(mk '' 'git push')" \
    "no-op: empty permission_mode (treated as not-auto)"

# ============================================================
# Auto-mode: git push (any form)
# ============================================================
expect_block "$hook" "$(mk auto 'git push')" \
    "blocks bare git push under auto"
expect_block "$hook" "$(mk auto 'git push -u origin feat/x')" \
    "blocks git push -u origin feat/x under auto"
expect_block "$hook" "$(mk auto 'git push origin HEAD')" \
    "blocks git push origin HEAD under auto"
expect_block "$hook" "$(mk auto 'git push --tags')" \
    "blocks git push --tags under auto"
expect_contains "$hook" "$(mk auto 'git push')" \
    "Auto-mode shared-step gate" "block reason mentions gate"

# ============================================================
# Auto-mode: gh pr writes
# ============================================================
expect_block "$hook" "$(mk auto 'gh pr create --title foo --body bar')" \
    "blocks gh pr create"
expect_block "$hook" "$(mk auto 'gh pr merge 42')" \
    "blocks gh pr merge"
expect_block "$hook" "$(mk auto 'gh pr comment 42 --body hi')" \
    "blocks gh pr comment"
expect_allow "$hook" "$(mk auto 'gh pr view 42')" \
    "allows gh pr view (read)"
expect_allow "$hook" "$(mk auto 'gh pr list')" \
    "allows gh pr list (read)"
expect_allow "$hook" "$(mk auto 'gh pr diff 42')" \
    "allows gh pr diff (read)"

# ============================================================
# Auto-mode: gh issue / release / repo writes
# ============================================================
expect_block "$hook" "$(mk auto 'gh issue create --title foo')" \
    "blocks gh issue create"
expect_allow "$hook" "$(mk auto 'gh issue view 7')" \
    "allows gh issue view"
expect_block "$hook" "$(mk auto 'gh release create v1.0.0')" \
    "blocks gh release create"
expect_block "$hook" "$(mk auto 'gh repo create my-new-repo --public')" \
    "blocks gh repo create"
expect_block "$hook" "$(mk auto 'gh repo delete some/repo --yes')" \
    "blocks gh repo delete"
expect_block "$hook" "$(mk auto 'gh repo edit --description x')" \
    "blocks gh repo edit"
expect_allow "$hook" "$(mk auto 'gh repo view')" \
    "allows gh repo view"
expect_allow "$hook" "$(mk auto 'gh repo clone foo/bar')" \
    "allows gh repo clone"

# ============================================================
# Auto-mode: gh secret/variable/workflow/auth
# ============================================================
expect_block "$hook" "$(mk auto 'gh secret set FOO --body bar')" \
    "blocks gh secret set"
expect_block "$hook" "$(mk auto 'gh variable set FOO --body bar')" \
    "blocks gh variable set"
expect_block "$hook" "$(mk auto 'gh workflow run deploy.yml')" \
    "blocks gh workflow run"
expect_block "$hook" "$(mk auto 'gh auth login')" \
    "blocks gh auth login"
expect_block "$hook" "$(mk auto 'gh ssh-key add ~/.ssh/id_ed25519.pub')" \
    "blocks gh ssh-key add"

# ============================================================
# Auto-mode: gh api (any — full restrictive)
# ============================================================
expect_block "$hook" "$(mk auto 'gh api repos/foo/bar')" \
    "blocks gh api (read) — full restrictive"
expect_block "$hook" "$(mk auto 'gh api -X POST repos/foo/bar/issues -f title=x')" \
    "blocks gh api -X POST"
expect_block "$hook" "$(mk auto 'gh api graphql -f query=foo')" \
    "blocks gh api graphql"

# ============================================================
# Auto-mode: curl/wget — api.github.com host
# ============================================================
expect_block "$hook" "$(mk auto 'curl https://api.github.com/user')" \
    "blocks curl to api.github.com"
expect_block "$hook" "$(mk auto 'wget https://api.github.com/user -O out')" \
    "blocks wget to api.github.com"

# ============================================================
# Auto-mode: curl/wget — Authorization header (any host)
# ============================================================
expect_block "$hook" "$(mk auto 'curl -H "Authorization: token ghp_abc" https://internal.example/api')" \
    "blocks curl with Authorization: token"
expect_block "$hook" "$(mk auto 'curl -H "Authorization: Bearer x" https://api.example.com/v1')" \
    "blocks curl with Authorization: Bearer"
expect_block "$hook" "$(mk auto "curl -H 'authorization: Basic abc=' https://x.com")" \
    "blocks curl with lowercase authorization: Basic"

# ============================================================
# Auto-mode: benign curl/wget passes
# ============================================================
expect_allow "$hook" "$(mk auto 'curl https://docs.python.org/3/')" \
    "allows curl to docs (no auth, not api.github.com)"
expect_allow "$hook" "$(mk auto 'curl -O https://example.com/file.tar.gz')" \
    "allows simple curl download"
expect_allow "$hook" "$(mk auto 'wget https://example.com/x')" \
    "allows simple wget"

# ============================================================
# Auto-mode: unrelated commands pass
# ============================================================
expect_allow "$hook" "$(mk auto 'ls -la')" \
    "allows ls under auto"
expect_allow "$hook" "$(mk auto 'git status')" \
    "allows git status under auto"
expect_allow "$hook" "$(mk auto 'git pull')" \
    "allows git pull under auto"
expect_allow "$hook" "$(mk auto 'make check')" \
    "allows make check under auto"

# ============================================================
# False-positive avoidance: tokens inside quoted/heredoc content
# ============================================================
# 'git push' inside an echo string is content, not a command
expect_allow "$hook" "$(mk auto 'echo "to push run: git push"')" \
    "allows git push inside double-quoted string under auto"

print_summary
