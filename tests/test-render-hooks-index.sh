#!/usr/bin/env bash
# Tests for `claude-toolkit indexes render hooks` — the V12 generator that
# regenerates the HOOKS.md summary table from CC-HOOK headers + dispatch-order.json#index_order.
#
# Driven by an isolated fixture tree assembled per-test under a tmpdir.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDERER="$REPO_ROOT/cli/indexes/query.sh"

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# --- Build a self-contained fixture tree under $1 ---
# Args: <tmp_root> <hook1_purpose>
_build_fixture() {
    local root="$1"
    local hook1_purpose="${2:-Sample guard}"

    mkdir -p "$root/hooks/lib"
    cat > "$root/hooks/sample-guard.sh" <<EOF
#!/usr/bin/env bash
# CC-HOOK: NAME: sample-guard
# CC-HOOK: PURPOSE: $hook1_purpose
# CC-HOOK: EVENTS: PreToolUse(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none

exit 0
EOF
    cat > "$root/hooks/sample-multi.sh" <<'EOF'
#!/usr/bin/env bash
# CC-HOOK: NAME: sample-multi
# CC-HOOK: PURPOSE: Hook with pipe-alternation events
# CC-HOOK: EVENTS: PreToolUse(Write|Edit)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: lessons

exit 0
EOF
    cat > "$root/hooks/lib/dispatch-order.json" <<'EOF'
{
  "version": 1,
  "dispatchers": {},
  "index_order": [
    "sample-guard",
    "sample-multi"
  ]
}
EOF
}

_render() {
    local root="$1"
    local md="$root/HOOKS.md"
    [ -f "$md" ] || cat > "$md" <<'EOF'
# Test Hooks Index

<!-- BEGIN: hooks-table -->
<!-- END: hooks-table -->
EOF
    CLAUDE_TOOLKIT_HOOKS_DIR="$root/hooks" \
    CLAUDE_TOOLKIT_HOOKS_INDEX_MD="$md" \
        bash "$RENDERER" render hooks 2>/dev/null
}

# === T1: error when sentinels missing ===
report_section "render errors when sentinels are absent"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
_build_fixture "$TMP"
echo "# No sentinels here" > "$TMP/HOOKS.md"
ERR=$(CLAUDE_TOOLKIT_HOOKS_DIR="$TMP/hooks" \
      CLAUDE_TOOLKIT_HOOKS_INDEX_MD="$TMP/HOOKS.md" \
      bash "$RENDERER" render hooks 2>&1)
EC=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EC" != "0" ] && echo "$ERR" | grep -qF "BEGIN: hooks-table"; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "missing sentinels triggers error"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "missing sentinels triggers error"
    report_detail "exit=$EC"
    report_detail "stderr: $ERR"
fi
rm -rf "$TMP"; trap - EXIT

# === T2: ordering follows index_order ===
report_section "table rows follow index_order"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
_build_fixture "$TMP"
_render "$TMP" >/dev/null
# Extract the two row hooks in order.
ROWS=$(sed -nE 's/^.*\| `([^`]+\.sh)` \|.*$/\1/p' "$TMP/HOOKS.md" | tr '\n' ',')
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$ROWS" = "sample-guard.sh,sample-multi.sh," ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "rows ordered: sample-guard, sample-multi"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "rows ordered correctly"
    report_detail "rows='$ROWS'"
fi
rm -rf "$TMP"; trap - EXIT

# === T3: row shape preserves validate-resources-indexed.sh regex ===
report_section "row shape preserves '| \`hook.sh\` |' regex"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
_build_fixture "$TMP"
_render "$TMP" >/dev/null
# Same regex used by validate-resources-indexed.sh:269
COUNT=$(sed -nE 's/^.*\| `([^`]+\.sh)` \|.*$/\1/p' "$TMP/HOOKS.md" | wc -l)
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$COUNT" = "2" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "regex captures all 2 hook names"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "regex captures all 2 hook names"
    report_detail "count=$COUNT"
fi
rm -rf "$TMP"; trap - EXIT

# === T4: pipe in EVENTS becomes \| in markdown cell ===
report_section "pipe-alternation events escaped as \\| in cell"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
_build_fixture "$TMP"
_render "$TMP" >/dev/null
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qF 'PreToolUse (Write\|Edit)' "$TMP/HOOKS.md"; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "Write|Edit rendered as Write\\|Edit"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "Write|Edit rendered as Write\\|Edit"
    report_detail "table:"
    sed -n '/BEGIN: hooks-table/,/END: hooks-table/p' "$TMP/HOOKS.md" >&2
fi
rm -rf "$TMP"; trap - EXIT

# === T5: OPT-IN: none → em dash; named values verbatim ===
report_section "OPT-IN none → em dash, named verbatim"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
_build_fixture "$TMP"
_render "$TMP" >/dev/null
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qF '| sample-guard.sh' "$TMP/HOOKS.md" 2>/dev/null || grep -qF '`sample-guard.sh`' "$TMP/HOOKS.md"; then
    # Look for the em dash specifically in the sample-guard row.
    if grep -qE '^\| `sample-guard\.sh`.*\| — \|' "$TMP/HOOKS.md" \
       && grep -qE '^\| `sample-multi\.sh`.*\| lessons \|' "$TMP/HOOKS.md"; then
        TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "OPT-IN none → —; lessons verbatim"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "OPT-IN none → —; lessons verbatim"
        report_detail "table:"
        sed -n '/BEGIN: hooks-table/,/END: hooks-table/p' "$TMP/HOOKS.md" >&2
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "table written"
fi
rm -rf "$TMP"; trap - EXIT

# === T6: --check returns 0 when fresh, 1 when drifted ===
report_section "--check exits 0 on match, 1 on drift"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
_build_fixture "$TMP"
_render "$TMP" >/dev/null

CLAUDE_TOOLKIT_HOOKS_DIR="$TMP/hooks" \
CLAUDE_TOOLKIT_HOOKS_INDEX_MD="$TMP/HOOKS.md" \
    bash "$RENDERER" render hooks --check >/dev/null 2>&1
EC1=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EC1" = "0" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "--check exits 0 on match"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "--check exits 0 on match"
    report_detail "exit=$EC1"
fi

# Drift the on-disk file.
sed -i 's|Sample guard|Mutated description|' "$TMP/HOOKS.md"
CLAUDE_TOOLKIT_HOOKS_DIR="$TMP/hooks" \
CLAUDE_TOOLKIT_HOOKS_INDEX_MD="$TMP/HOOKS.md" \
    bash "$RENDERER" render hooks --check >/dev/null 2>&1
EC2=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EC2" = "1" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "--check exits 1 on drift"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "--check exits 1 on drift"
    report_detail "exit=$EC2"
fi
rm -rf "$TMP"; trap - EXIT

# === T7: validate_hooks catches disk/index_order mismatch ===
report_section "validate_hooks errors on disk/index_order mismatch"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
_build_fixture "$TMP"
# Drop one hook from index_order while leaving the .sh on disk.
cat > "$TMP/hooks/lib/dispatch-order.json" <<'EOF'
{
  "version": 1,
  "dispatchers": {},
  "index_order": ["sample-guard"]
}
EOF
ERR=$(CLAUDE_TOOLKIT_HOOKS_DIR="$TMP/hooks" \
      bash "$RENDERER" validate hooks 2>&1)
EC=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EC" = "1" ] && echo "$ERR" | grep -qF "sample-multi"; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "validate flags missing index_order entry"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "validate flags missing index_order entry"
    report_detail "exit=$EC"
    report_detail "stderr: $ERR"
fi
rm -rf "$TMP"; trap - EXIT

print_summary
