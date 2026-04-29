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

batch_start "$hook"

# Should block Write
batch_add block "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"content\":\"test\"}}" \
    "blocks writing ~/.bashrc"
batch_add block "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.zshrc\",\"content\":\"test\"}}" \
    "blocks writing ~/.zshrc"
batch_add block "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/authorized_keys\",\"content\":\"test\"}}" \
    "blocks writing ~/.ssh/authorized_keys"
batch_add block "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.gitconfig\",\"content\":\"test\"}}" \
    "blocks writing ~/.gitconfig"

# Should block Edit
batch_add block "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
    "blocks editing ~/.bashrc"

# Should block Bash write commands
batch_add block '{"tool_name":"Bash","tool_input":{"command":"echo \"export FOO=bar\" >> ~/.bashrc"}}' \
    "blocks appending to ~/.bashrc"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"tee -a ~/.zshrc"}}' \
    "blocks tee -a to ~/.zshrc"

# Should allow
batch_add allow '{"tool_name":"Write","tool_input":{"file_path":"/project/.bashrc","content":"test"}}' \
    "allows writing project-level .bashrc"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
    "allows normal bash commands"

# ============================================================
# Settings files (.claude/settings.json, .claude/settings.local.json)
# Mode-aware: ask in default/acceptEdits/plan, hard-block in auto.
# Each "tool surface that could reach the same target" pinned per the
# anti-rampage coverage convention (relevant-toolkit-hooks.md).
# ============================================================

# --- Write tool: settings paths under non-auto modes → ask ---
batch_add ask "$(mk_write default '.claude/settings.json')" \
    "asks on Write .claude/settings.json under default"
batch_add ask "$(mk_write acceptEdits '.claude/settings.json')" \
    "asks on Write .claude/settings.json under acceptEdits"
batch_add ask "$(mk_write plan '.claude/settings.json')" \
    "asks on Write .claude/settings.json under plan"
batch_add ask "$(mk_write default '.claude/settings.local.json')" \
    "asks on Write .claude/settings.local.json under default"
batch_add ask "$(mk_write '' '.claude/settings.local.json')" \
    "asks on Write .claude/settings.local.json under empty mode (treated as not-auto)"

# --- Write tool: settings paths under auto → block ---
batch_add block "$(mk_write auto '.claude/settings.json')" \
    "blocks Write .claude/settings.json under auto"
batch_add block "$(mk_write auto '.claude/settings.local.json')" \
    "blocks Write .claude/settings.local.json under auto"
batch_add contains "$(mk_write auto '.claude/settings.json')" \
    "BLOCKED (auto-mode)" "auto-mode block reason mentions auto-mode"

# --- Edit tool: same matrix ---
batch_add ask "$(mk_edit default '.claude/settings.json')" \
    "asks on Edit .claude/settings.json under default"
batch_add ask "$(mk_edit default '.claude/settings.local.json')" \
    "asks on Edit .claude/settings.local.json under default"
batch_add block "$(mk_edit auto '.claude/settings.json')" \
    "blocks Edit .claude/settings.json under auto"
batch_add block "$(mk_edit auto '.claude/settings.local.json')" \
    "blocks Edit .claude/settings.local.json under auto"

# --- Absolute path targets ---
batch_add ask "$(mk_write default '/project/.claude/settings.json')" \
    "asks on Write absolute path ending in .claude/settings.json"
batch_add block "$(mk_write auto '/project/.claude/settings.local.json')" \
    "blocks Write absolute path ending in .claude/settings.local.json under auto"

# --- Bash branch: write verbs targeting settings (always block — Bash has no ask path) ---
batch_add block "$(mk_bash 'echo {} >> .claude/settings.local.json')" \
    "blocks Bash >> .claude/settings.local.json"
batch_add block "$(mk_bash 'tee .claude/settings.json < input')" \
    "blocks Bash tee .claude/settings.json"
batch_add block "$(mk_bash 'sed -i s/foo/bar/ .claude/settings.local.json')" \
    "blocks Bash sed -i .claude/settings.local.json"
batch_add block "$(mk_bash 'mv /tmp/x .claude/settings.json')" \
    "blocks Bash mv to .claude/settings.json"
batch_add block "$(mk_bash 'cat /tmp/x > .claude/settings.local.json')" \
    "blocks Bash single-redirect > .claude/settings.local.json"

# --- Default-deny: additional write-shaped verbs targeting settings ---
batch_add block "$(mk_bash 'cp /tmp/x .claude/settings.json')" \
    "blocks Bash cp /tmp/x .claude/settings.json"
batch_add block "$(mk_bash 'cp -f /tmp/x .claude/settings.json')" \
    "blocks Bash cp -f /tmp/x .claude/settings.json"
batch_add block "$(mk_bash 'install /tmp/x .claude/settings.json')" \
    "blocks Bash install /tmp/x .claude/settings.json"
batch_add block "$(mk_bash 'dd if=/tmp/x of=.claude/settings.json')" \
    "blocks Bash dd of=.claude/settings.json"
batch_add block "$(mk_bash 'truncate -s 0 .claude/settings.json')" \
    "blocks Bash truncate .claude/settings.json"
batch_add block "$(mk_bash 'awk -i inplace BEGIN{print} .claude/settings.json')" \
    "blocks Bash awk -i inplace .claude/settings.json"
batch_add block "$(mk_bash 'rsync /tmp/x .claude/settings.json')" \
    "blocks Bash rsync /tmp/x .claude/settings.json"
batch_add block "$(mk_bash 'chmod 666 .claude/settings.json')" \
    "blocks Bash chmod .claude/settings.json"

# --- Interpreter-bodied settings writes (in scope: python, bash, sh) ---
batch_add block "$(mk_bash 'python -c "open('"'"'.claude/settings.local.json'"'"','"'"'w'"'"').write(x)"')" \
    "blocks Bash python -c writing .claude/settings.local.json (double-quoted body)"
batch_add block "$(mk_bash 'python -c '"'"'open(".claude/settings.json","w").write(x)'"'"'')" \
    "blocks Bash python -c writing .claude/settings.json (single-quoted body)"
batch_add block "$(mk_bash 'bash -c '"'"'echo {} > .claude/settings.local.json'"'"'')" \
    "blocks Bash bash -c redirecting to .claude/settings.local.json"
batch_add block "$(mk_bash 'sh -c "echo {} > .claude/settings.json"')" \
    "blocks Bash sh -c redirecting to .claude/settings.json"
batch_add block "$(mk_bash $'python <<PYEOF\nopen(".claude/settings.local.json","w").write(x)\nPYEOF')" \
    "blocks Bash python heredoc writing .claude/settings.local.json"
batch_add block "$(mk_bash 'python3 -c "open('"'"'.claude/settings.json'"'"','"'"'w'"'"').write(x)"')" \
    "blocks Bash python3 -c writing .claude/settings.json (versioned binary)"

# --- Interpreter-bodied settings writes — extended set (ruby/perl/node) ---
batch_add block "$(mk_bash 'ruby -e "File.write('"'"'.claude/settings.json'"'"', x)"')" \
    "blocks ruby -e writing .claude/settings.json"
batch_add block "$(mk_bash 'node -e "require('"'"'fs'"'"').writeFileSync('"'"'.claude/settings.json'"'"', '"'"'{}'"'"')"')" \
    "blocks node -e writing .claude/settings.json"
batch_add block "$(mk_bash 'perl -e "open F,\">\",\".claude/settings.json\"; print F \"{}\""')" \
    "blocks perl -e writing .claude/settings.json"

# --- Negatives: legitimate read-only / no-interpreter ---
batch_add allow "$(mk_bash 'echo see .claude/settings.json for config')" \
    "allows echo mentioning .claude/settings.json (no interpreter -c/<<)"

# --- Negatives: settings path appears only as quoted data (false-positive guard) ---
batch_add allow "$(mk_bash $'jq -nc --arg p \'.claude/settings.json\' \'$p\'')" \
    "allows jq with .claude/settings.json inside single-quoted arg"

# --- Symlink defense: creating symlink targeting settings ---
batch_add block "$(mk_bash 'ln -s .claude/settings.json /tmp/sneaky')" \
    "blocks Bash ln -s targeting .claude/settings.json"
batch_add block "$(mk_bash 'ln -s /tmp/x .claude/settings.json')" \
    "blocks Bash ln -s with link side at .claude/settings.json"

# --- Symlink write-through (defense-in-depth): blocked when match_ fires
# (i.e. the command also mentions settings literally OR uses an in-scope
# verb like cp/mv/tee). A symlink-only redirect (`echo > /tmp/link`) where
# the LLM never created the link is a different threat model — the symlink-
# creation step (above) is the load-bearing defense; pre-existing rogue
# links would have been planted outside this session. ---
_SYMLINK_TMP=$(mktemp -d)
ln -s "$_SYMLINK_TMP/.claude/settings.json" "$_SYMLINK_TMP/sneaky-link"
batch_add block "$(mk_bash "cp /tmp/x $_SYMLINK_TMP/sneaky-link")" \
    "blocks Bash cp through pre-existing symlink resolving to .claude/settings.json"

# --- Block-reason verb sanity ---
batch_add contains "$(mk_bash 'python -c "open('"'"'.claude/settings.local.json'"'"','"'"'w'"'"').write(x)"')" \
    "Editing via interpreter" "block reason names interpreter verb"

# --- Negatives: legitimate non-settings paths ---
batch_add allow "$(mk_write default 'output/x.json')" \
    "allows Write output/x.json"
batch_add allow "$(mk_write auto 'output/x.json')" \
    "allows Write output/x.json under auto (not a settings file)"
batch_add allow "$(mk_edit default '.claude/settings.template.json')" \
    "allows Edit settings.template.json (template, not live)"
batch_add allow "$(mk_write default '.claude/skills/foo/SKILL.md')" \
    "allows Write to skills under .claude/"

# --- Negatives: read-only Bash on settings (Bash branch only blocks writes) ---
batch_add allow "$(mk_bash 'cat .claude/settings.json')" \
    "allows Bash cat .claude/settings.json (read-only)"
batch_add allow "$(mk_bash 'jq . .claude/settings.local.json')" \
    "allows Bash jq read of .claude/settings.local.json"
batch_add allow "$(mk_bash 'grep permissions .claude/settings.json')" \
    "allows Bash grep on .claude/settings.json"

batch_run

print_summary
