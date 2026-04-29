#!/usr/bin/env bash
# Tests for .claude/hooks/lib/settings-permissions.sh
#
# Covers:
#   - settings_permissions_load: idempotency, jq parse, prefix extraction
#   - Bash() filter: Read/Edit/Glob/Skill/mcp__ entries are dropped
#   - Word-boundary alternation regex (anchored ^|space|;|&||)
#   - Path-form prefixes preserve trailing slash
#   - settings.local.json is INTENTIONALLY ignored (decision 1 of plan)
#   - Missing settings.json returns 1
#   - Empty permissions returns 1
#   - Re-sourcing the lib is a no-op
#
# Loader is fixture-driven: each block builds a tiny settings.json under a
# per-process temp dir and points the loader at it via
# CLAUDE_TOOLKIT_SETTINGS_JSON.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/.claude/hooks/lib/settings-permissions.sh"

# ============================================================
# Tiny pass/fail wrappers (mirror tests/hooks/test-detection-registry.sh)
# ============================================================
assert() {
    local desc="$1" cond="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$cond"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "condition failed: $cond"
    fi
}

assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "expected: $expected"
        report_detail "actual:   $actual"
    fi
}

# ============================================================
# Run the loader against a fixture in a fresh subshell.
# Captures all assertion-relevant globals into a name=value
# eval-able output on stdout (one global per line).
# ============================================================
run_loader() {
    local settings_path="$1"
    bash -c '
        export CLAUDE_TOOLKIT_SETTINGS_JSON="$1"
        # Disable the parent-process settings-permissions guard if any.
        unset _SETTINGS_PERMISSIONS_SOURCED
        source "'"$LIB"'"
        if settings_permissions_load 2>/dev/null; then
            echo "RC=0"
        else
            echo "RC=$?"
        fi
        echo "LOADED=$_SETTINGS_PERMISSIONS_LOADED"
        # Encode arrays as TSV; consumers split.
        printf "ALLOW="
        printf "%s\t" "${_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]:-}"
        printf "\n"
        printf "ASK="
        printf "%s\t" "${_SETTINGS_PERMISSIONS_ASK_PREFIXES[@]:-}"
        printf "\n"
        echo "RE_ALLOW=$_SETTINGS_PERMISSIONS_RE_ALLOW"
        echo "RE_ASK=$_SETTINGS_PERMISSIONS_RE_ASK"
    ' _ "$settings_path"
}

# Helper: parse a `KEY=value` line from run_loader output.
extract() {
    local key="$1" output="$2"
    printf '%s\n' "$output" | sed -n "s/^${key}=//p"
}

# Helper: write a settings.json with the given allow/ask arrays (jq-style).
# $1: target path. $2: allow JSON array. $3: ask JSON array.
write_settings() {
    local target="$1" allow="$2" ask="$3"
    cat > "$target" <<EOF
{
  "permissions": {
    "allow": $allow,
    "ask": $ask
  }
}
EOF
}

# ============================================================
# Case 1 — empty allow + ask → returns 1
# ============================================================
report_section "=== Case 1: empty permissions ==="
FX1=$(mktemp -d)
write_settings "$FX1/settings.json" '[]' '[]'
out=$(run_loader "$FX1/settings.json")
assert_eq "load returns 1 on empty permissions" "$(extract RC "$out")" "1"
assert_eq "_SETTINGS_PERMISSIONS_LOADED stays 0 on empty" "$(extract LOADED "$out")" "0"
trash-put "$FX1" 2>/dev/null || true

# ============================================================
# Case 2 — Bash(git status:*) prefix + word boundary
# ============================================================
report_section "=== Case 2: Bash(git status:*) word-boundary ==="
FX2=$(mktemp -d)
write_settings "$FX2/settings.json" '["Bash(git status:*)"]' '[]'
out=$(run_loader "$FX2/settings.json")
assert_eq "load returns 0" "$(extract RC "$out")" "0"
allow_tsv=$(extract ALLOW "$out")
assert_eq "single allow prefix extracted" "$allow_tsv" "$(printf 'git status\t')"
re_allow=$(extract RE_ALLOW "$out")
assert "regex matches 'git status -s'" "[[ 'git status -s' =~ ${re_allow} ]]"
assert "regex does NOT match 'git statusxxx' (word boundary)" \
    "! [[ 'git statusxxx' =~ ${re_allow} ]]"
trash-put "$FX2" 2>/dev/null || true

# ============================================================
# Case 3 — path-form prefix preserves trailing slash
# ============================================================
report_section "=== Case 3: Bash(./.claude/hooks/*) path form ==="
FX3=$(mktemp -d)
write_settings "$FX3/settings.json" '["Bash(./.claude/hooks/*)"]' '[]'
out=$(run_loader "$FX3/settings.json")
allow_tsv=$(extract ALLOW "$out")
assert_eq "path prefix retains trailing slash" "$allow_tsv" "$(printf './.claude/hooks/\t')"
trash-put "$FX3" 2>/dev/null || true

# ============================================================
# Case 4 — non-Bash entries are filtered
# ============================================================
report_section "=== Case 4: non-Bash entries filtered ==="
FX4=$(mktemp -d)
write_settings "$FX4/settings.json" \
    '["Bash(ls:*)", "Read(/**)", "Edit(/output/**)", "Glob(/**)", "Skill(*)", "mcp__context7__query-docs"]' \
    '[]'
out=$(run_loader "$FX4/settings.json")
allow_tsv=$(extract ALLOW "$out")
assert_eq "only the Bash entry survives" "$allow_tsv" "$(printf 'ls\t')"
trash-put "$FX4" 2>/dev/null || true

# ============================================================
# Case 5 — idempotent re-source
# ============================================================
report_section "=== Case 5: idempotent re-source ==="
FX5=$(mktemp -d)
write_settings "$FX5/settings.json" '["Bash(ls:*)"]' '[]'
# Source twice and verify _SETTINGS_PERMISSIONS_LOADED stays 1 and the array doesn't double.
double_out=$(bash -c '
    export CLAUDE_TOOLKIT_SETTINGS_JSON="$1"
    unset _SETTINGS_PERMISSIONS_SOURCED
    source "'"$LIB"'"
    settings_permissions_load 2>/dev/null
    n_before=${#_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]}
    # Force a second load attempt — the guard inside settings_permissions_load
    # should short-circuit when _SETTINGS_PERMISSIONS_LOADED is already 1.
    settings_permissions_load 2>/dev/null
    n_after=${#_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]}
    echo "BEFORE=$n_before"
    echo "AFTER=$n_after"
' _ "$FX5/settings.json")
assert_eq "second load() is no-op (count stable)" \
    "$(extract AFTER "$double_out")" "$(extract BEFORE "$double_out")"
trash-put "$FX5" 2>/dev/null || true

# ============================================================
# Case 6 — missing settings.json returns 1
# ============================================================
report_section "=== Case 6: missing settings.json ==="
FX6=$(mktemp -d)
out=$(run_loader "$FX6/does-not-exist.json" 2>/dev/null)
assert_eq "load returns 1 on missing file" "$(extract RC "$out")" "1"
assert_eq "_SETTINGS_PERMISSIONS_LOADED stays 0 on missing file" \
    "$(extract LOADED "$out")" "0"
trash-put "$FX6" 2>/dev/null || true

# ============================================================
# Case 7 — settings.local.json is intentionally ignored (decision 1)
# ============================================================
report_section "=== Case 7: settings.local.json is ignored ==="
FX7=$(mktemp -d)
write_settings "$FX7/settings.json" '["Bash(ls:*)"]' '[]'
write_settings "$FX7/settings.local.json" '["Bash(mv:*)"]' '[]'
out=$(run_loader "$FX7/settings.json")
allow_tsv=$(extract ALLOW "$out")
assert_eq "settings.local.json mv NOT in allow array" \
    "$allow_tsv" "$(printf 'ls\t')"
re_allow=$(extract RE_ALLOW "$out")
assert "regex does NOT match 'mv foo bar'" \
    "! [[ 'mv foo bar' =~ ${re_allow} ]]"
trash-put "$FX7" 2>/dev/null || true

# ============================================================
# Case 8 — both buckets populate, BASH_REMATCH[2] returns matched prefix
# ============================================================
report_section "=== Case 8: both buckets + BASH_REMATCH[2] ==="
FX8=$(mktemp -d)
write_settings "$FX8/settings.json" \
    '["Bash(ls:*)", "Bash(git status:*)"]' \
    '["Bash(gh pr create:*)", "Bash(curl:*)"]'
out=$(run_loader "$FX8/settings.json")
allow_tsv=$(extract ALLOW "$out")
ask_tsv=$(extract ASK "$out")
assert_eq "allow has 2 prefixes" "$allow_tsv" "$(printf 'ls\tgit status\t')"
assert_eq "ask has 2 prefixes" "$ask_tsv" "$(printf 'gh pr create\tcurl\t')"
re_ask=$(extract RE_ASK "$out")
# BASH_REMATCH[2] must yield the matched prefix.
cmd="gh pr create --title x"
if [[ "$cmd" =~ ${re_ask} ]]; then
    assert_eq "BASH_REMATCH[2] = 'gh pr create' on '$cmd'" "${BASH_REMATCH[2]}" "gh pr create"
else
    assert "regex matches '$cmd'" "false"
fi
trash-put "$FX8" 2>/dev/null || true

# ============================================================
# Case 9 — prefix containing an unhandled metacharacter is rejected
# ============================================================
report_section "=== Case 9: ERE-metachar prefix is rejected ==="
FX9=$(mktemp -d)
# Synthetic — manufactured, not realistic. The point is the audit fires.
write_settings "$FX9/settings.json" '["Bash(ls:*)", "Bash(foo+bar:*)"]' '[]'
out=$(run_loader "$FX9/settings.json" 2>/dev/null)
re_allow=$(extract RE_ALLOW "$out")
# `ls` survives; `foo+bar` is rejected and not in the regex.
assert "regex contains 'ls'" "[[ '$re_allow' == *'ls'* ]]"
assert "regex does NOT contain 'foo+bar'" "[[ '$re_allow' != *'foo+bar'* ]]"
trash-put "$FX9" 2>/dev/null || true

print_summary
