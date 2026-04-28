#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== block-config-edits.sh ==="
hook="block-config-edits.sh"

# Helper: build payload with permission_mode set (for Write/Edit ask-vs-block routing)
mk_write() {
    local mode="$1" path="$2"
    jq -nc --arg m "$mode" --arg p "$path" \
        '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},permission_mode:$m,session_id:"t"}'
}
mk_edit() {
    local mode="$1" path="$2"
    jq -nc --arg m "$mode" --arg p "$path" \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"},permission_mode:$m,session_id:"t"}'
}
mk_bash() {
    local cmd="$1"
    jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},session_id:"t"}'
}

# ============================================================
# Original coverage: shell/SSH/git config files (Write/Edit/Bash)
# ============================================================

# Should block Write
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"content\":\"test\"}}" \
    "blocks writing ~/.bashrc"
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.zshrc\",\"content\":\"test\"}}" \
    "blocks writing ~/.zshrc"
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/authorized_keys\",\"content\":\"test\"}}" \
    "blocks writing ~/.ssh/authorized_keys"
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.gitconfig\",\"content\":\"test\"}}" \
    "blocks writing ~/.gitconfig"

# Should block Edit
expect_block "$hook" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
    "blocks editing ~/.bashrc"

# Should block Bash write commands
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"export FOO=bar\" >> ~/.bashrc"}}' \
    "blocks appending to ~/.bashrc"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"tee -a ~/.zshrc"}}' \
    "blocks tee -a to ~/.zshrc"

# Should allow
expect_allow "$hook" '{"tool_name":"Write","tool_input":{"file_path":"/project/.bashrc","content":"test"}}' \
    "allows writing project-level .bashrc"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
    "allows normal bash commands"

# ============================================================
# Settings files (.claude/settings.json, .claude/settings.local.json)
# Mode-aware: ask in default/acceptEdits/plan, hard-block in auto.
# Each "tool surface that could reach the same target" pinned per the
# anti-rampage coverage convention (relevant-toolkit-hooks.md).
# ============================================================

# --- Write tool: settings paths under non-auto modes → ask ---
expect_ask "$hook" "$(mk_write default '.claude/settings.json')" \
    "asks on Write .claude/settings.json under default"
expect_ask "$hook" "$(mk_write acceptEdits '.claude/settings.json')" \
    "asks on Write .claude/settings.json under acceptEdits"
expect_ask "$hook" "$(mk_write plan '.claude/settings.json')" \
    "asks on Write .claude/settings.json under plan"
expect_ask "$hook" "$(mk_write default '.claude/settings.local.json')" \
    "asks on Write .claude/settings.local.json under default"
expect_ask "$hook" "$(mk_write '' '.claude/settings.local.json')" \
    "asks on Write .claude/settings.local.json under empty mode (treated as not-auto)"

# --- Write tool: settings paths under auto → block ---
expect_block "$hook" "$(mk_write auto '.claude/settings.json')" \
    "blocks Write .claude/settings.json under auto"
expect_block "$hook" "$(mk_write auto '.claude/settings.local.json')" \
    "blocks Write .claude/settings.local.json under auto"
expect_contains "$hook" "$(mk_write auto '.claude/settings.json')" \
    "BLOCKED (auto-mode)" "auto-mode block reason mentions auto-mode"

# --- Edit tool: same matrix ---
expect_ask "$hook" "$(mk_edit default '.claude/settings.json')" \
    "asks on Edit .claude/settings.json under default"
expect_ask "$hook" "$(mk_edit default '.claude/settings.local.json')" \
    "asks on Edit .claude/settings.local.json under default"
expect_block "$hook" "$(mk_edit auto '.claude/settings.json')" \
    "blocks Edit .claude/settings.json under auto"
expect_block "$hook" "$(mk_edit auto '.claude/settings.local.json')" \
    "blocks Edit .claude/settings.local.json under auto"

# --- Absolute path targets ---
expect_ask "$hook" "$(mk_write default '/project/.claude/settings.json')" \
    "asks on Write absolute path ending in .claude/settings.json"
expect_block "$hook" "$(mk_write auto '/project/.claude/settings.local.json')" \
    "blocks Write absolute path ending in .claude/settings.local.json under auto"

# --- Bash branch: write verbs targeting settings (always block — Bash has no ask path) ---
expect_block "$hook" "$(mk_bash 'echo {} >> .claude/settings.local.json')" \
    "blocks Bash >> .claude/settings.local.json"
expect_block "$hook" "$(mk_bash 'tee .claude/settings.json < input')" \
    "blocks Bash tee .claude/settings.json"
expect_block "$hook" "$(mk_bash 'sed -i s/foo/bar/ .claude/settings.local.json')" \
    "blocks Bash sed -i .claude/settings.local.json"
expect_block "$hook" "$(mk_bash 'mv /tmp/x .claude/settings.json')" \
    "blocks Bash mv to .claude/settings.json"
expect_block "$hook" "$(mk_bash 'cat /tmp/x > .claude/settings.local.json')" \
    "blocks Bash single-redirect > .claude/settings.local.json"

# --- Interpreter-bodied settings writes (in scope: python, bash, sh) ---
expect_block "$hook" "$(mk_bash 'python -c "open('"'"'.claude/settings.local.json'"'"','"'"'w'"'"').write(x)"')" \
    "blocks Bash python -c writing .claude/settings.local.json (double-quoted body)"
expect_block "$hook" "$(mk_bash 'python -c '"'"'open(".claude/settings.json","w").write(x)'"'"'')" \
    "blocks Bash python -c writing .claude/settings.json (single-quoted body)"
expect_block "$hook" "$(mk_bash 'bash -c '"'"'echo {} > .claude/settings.local.json'"'"'')" \
    "blocks Bash bash -c redirecting to .claude/settings.local.json"
expect_block "$hook" "$(mk_bash 'sh -c "echo {} > .claude/settings.json"')" \
    "blocks Bash sh -c redirecting to .claude/settings.json"
expect_block "$hook" "$(mk_bash $'python <<PYEOF\nopen(".claude/settings.local.json","w").write(x)\nPYEOF')" \
    "blocks Bash python heredoc writing .claude/settings.local.json"
expect_block "$hook" "$(mk_bash 'python3 -c "open('"'"'.claude/settings.json'"'"','"'"'w'"'"').write(x)"')" \
    "blocks Bash python3 -c writing .claude/settings.json (versioned binary)"

# --- Negatives: out-of-scope interpreters NOT blocked (deferred per scope) ---
expect_allow "$hook" "$(mk_bash 'ruby -e "File.write('"'"'.claude/settings.json'"'"', x)"')" \
    "allows ruby -e (out of scope, deferred)"
expect_allow "$hook" "$(mk_bash 'node -e "fs.writeFileSync('"'"'.claude/settings.json'"'"', x)"')" \
    "allows node -e (out of scope, deferred)"

# --- Negatives: legitimate read-only / no-interpreter ---
expect_allow "$hook" "$(mk_bash 'echo see .claude/settings.json for config')" \
    "allows echo mentioning .claude/settings.json (no interpreter -c/<<)"

# --- Block-reason verb sanity ---
expect_contains "$hook" "$(mk_bash 'python -c "open('"'"'.claude/settings.local.json'"'"','"'"'w'"'"').write(x)"')" \
    "Editing via interpreter" "block reason names interpreter verb"

# --- Negatives: legitimate non-settings paths ---
expect_allow "$hook" "$(mk_write default 'output/x.json')" \
    "allows Write output/x.json"
expect_allow "$hook" "$(mk_write auto 'output/x.json')" \
    "allows Write output/x.json under auto (not a settings file)"
expect_allow "$hook" "$(mk_edit default '.claude/settings.template.json')" \
    "allows Edit settings.template.json (template, not live)"
expect_allow "$hook" "$(mk_write default '.claude/skills/foo/SKILL.md')" \
    "allows Write to skills under .claude/"

# --- Negatives: read-only Bash on settings (Bash branch only blocks writes) ---
expect_allow "$hook" "$(mk_bash 'cat .claude/settings.json')" \
    "allows Bash cat .claude/settings.json (read-only)"
expect_allow "$hook" "$(mk_bash 'jq . .claude/settings.local.json')" \
    "allows Bash jq read of .claude/settings.local.json"
expect_allow "$hook" "$(mk_bash 'grep permissions .claude/settings.json')" \
    "allows Bash grep on .claude/settings.json"

print_summary
