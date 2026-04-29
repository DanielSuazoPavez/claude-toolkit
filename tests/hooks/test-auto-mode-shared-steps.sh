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
# Auto-mode: benign curl/wget passes
# ============================================================
batch_add allow "$(mk auto 'curl https://docs.python.org/3/')" \
    "allows curl to docs (no auth, not api.github.com)"
batch_add allow "$(mk auto 'curl -O https://example.com/file.tar.gz')" \
    "allows simple curl download"
batch_add allow "$(mk auto 'wget https://example.com/x')" \
    "allows simple wget"

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

print_summary
