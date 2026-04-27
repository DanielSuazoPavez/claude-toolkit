#!/bin/bash
# End-to-end: sync the real toolkit into a fresh fixture, then run validators
# and the diagnose script as a consumer would.
#
# Catches drift like consumer-validate-paths: validators referencing toolkit-source
# paths, scripts that ship but require resources outside .claude/, MANIFEST gaps.
#
# Usage:
#   bash tests/test-sync-then-validate.sh
#   bash tests/test-sync-then-validate.sh -q
#   bash tests/test-sync-then-validate.sh -v

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_SCRIPT="$TOOLKIT_DIR/bin/claude-toolkit"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

TEMP_DIR=""

setup() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Fixture: $TEMP_DIR"
    mkdir -p "$TEMP_DIR/project"
    (
        cd "$TEMP_DIR/project"
        TOOLKIT_DIR="$TOOLKIT_DIR" bash "$CLI_SCRIPT" sync --force >/dev/null 2>&1
    )
    # Bootstrap settings.json from template — validators that compare settings vs
    # template otherwise fail with "Missing: .claude/settings.json", which is a
    # user-bootstrap concern, not a sync-correctness concern.
    cp "$TEMP_DIR/project/.claude/templates/settings.template.json" \
       "$TEMP_DIR/project/.claude/settings.json"
}

teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Run a script in the fixture and assert it exits 0
expect_script_passes() {
    local description="$1"
    local script="$2"
    shift 2

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    local exit_code
    output=$(cd "$TEMP_DIR/project" && bash "$script" "$@" 2>&1) && exit_code=0 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected exit code 0, got $exit_code"
        report_detail "Output:"
        echo "$output" | sed 's/^/      /'
    fi
}

# Assert a path exists in the fixture
expect_fixture_path() {
    local description="$1"
    local path="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -e "$TEMP_DIR/project/$path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Missing in fixture: $path"
    fi
}

# === Tests ===

report_section "=== sync ships expected resource trees ==="
setup
expect_fixture_path "scripts/ shipped"  ".claude/scripts/validate-all.sh"
expect_fixture_path "schemas/ shipped"  ".claude/schemas/hooks/detection-registry.schema.json"
expect_fixture_path "MANIFEST written"  ".claude/MANIFEST"

report_section "=== validate-all.sh passes against synced fixture ==="
expect_script_passes "validate-all.sh exits 0 in consumer fixture" \
    .claude/scripts/validate-all.sh

report_section "=== individual validators referenced by validate-all.sh ==="
# These each sanity-check a single validator's path assumptions.
expect_script_passes "validate-detection-registry.sh (schema must ship)" \
    .claude/scripts/validate-detection-registry.sh
expect_script_passes "validate-resources-indexed.sh (MANIFEST mode)" \
    .claude/scripts/validate-resources-indexed.sh

report_section "=== setup-toolkit-diagnose runs against synced fixture ==="
# Diagnose script exits 0 when no critical issues; we tolerate any exit code as
# long as it doesn't crash with a syntax/path error. The report itself is what
# we care about — assert it ran to completion.
TESTS_RUN=$((TESTS_RUN + 1))
diag_output=$(cd "$TEMP_DIR/project" && bash .claude/scripts/setup-toolkit-diagnose.sh 2>&1) || true
if echo "$diag_output" | grep -q "===SUMMARY:END==="; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "diagnose ran to completion (SUMMARY block present)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "diagnose did not produce a summary"
    report_detail "Output tail:"
    echo "$diag_output" | tail -10 | sed 's/^/      /'
fi

teardown

report_section "=== orphan detection catches stale toolkit-owned files ==="
# Simulate a consumer whose previous sync left a script that's now in EXCLUDE.
# Diagnose should report it as ORPHAN.
setup
echo "echo stale" > "$TEMP_DIR/project/.claude/scripts/__stale_test_script.sh"
chmod +x "$TEMP_DIR/project/.claude/scripts/__stale_test_script.sh"

TESTS_RUN=$((TESTS_RUN + 1))
diag_output=$(cd "$TEMP_DIR/project" && bash .claude/scripts/setup-toolkit-diagnose.sh 2>&1) || true
if echo "$diag_output" | grep -q "ORPHAN: scripts/__stale_test_script.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "diagnose flags stale script as ORPHAN"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "diagnose missed stale script"
    report_detail "Output tail:"
    echo "$diag_output" | tail -15 | sed 's/^/      /'
fi
teardown

print_summary
