#!/bin/bash
# Tests for format-raiz-changelog.sh
#
# Usage:
#   bash tests/test-raiz-changelog.sh           # Run all tests
#   bash tests/test-raiz-changelog.sh -q        # Quiet mode (summary + failures only)
#   bash tests/test-raiz-changelog.sh -v        # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMAT_SCRIPT="$TOOLKIT_DIR/.github/scripts/format-raiz-changelog.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Assertion Helpers ===

assert_contains() {
    local description="$1"
    local output="$2"
    local pattern="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -qF "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output to contain: $pattern"
    fi
}

assert_not_contains() {
    local description="$1"
    local output="$2"
    local pattern="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    if ! echo "$output" | grep -qF "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output NOT to contain: $pattern"
    fi
}

assert_exit_zero() {
    local description="$1"
    local actual="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$actual" -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected exit 0, got $actual"
    fi
}

assert_exit_nonzero() {
    local description="$1"
    local actual="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$actual" -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected non-zero exit, got 0"
    fi
}

# === Runner Helpers ===

TEMP_DIR=""

# Default: captures stdout, stderr flows to test output (visible on failure).
run_fmt() {
    FORMAT_RAIZ_PROJECT_ROOT="$TEMP_DIR" bash "$FORMAT_SCRIPT" "$@"
}

# Explicit opt-in: captures stderr to file for tests that assert on error messages.
run_fmt_stderr() {
    FORMAT_RAIZ_PROJECT_ROOT="$TEMP_DIR" bash "$FORMAT_SCRIPT" "$@" 2>"$TEMP_DIR/stderr"
}

# === Fixture Setup ===

setup_fixtures() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Temp dir: $TEMP_DIR"

    # VERSION
    echo "1.3.0" > "$TEMP_DIR/VERSION"

    # MANIFEST
    mkdir -p "$TEMP_DIR/dist/raiz"
    cat > "$TEMP_DIR/dist/raiz/MANIFEST" << 'MANIFEST_EOF'
# Test manifest
skills/alpha-skill/
agents/beta-agent.md
hooks/gamma-hook.sh
hooks/lib/hook-utils.sh
docs/essential-conventions-delta_doc.md
MANIFEST_EOF

    # CHANGELOG
    cat > "$TEMP_DIR/CHANGELOG.md" << 'CHANGELOG_EOF'
# Changelog

## [1.3.0] - 2026-04-01 - Alpha skill & hook improvements

### Added
- **skills**: `/alpha-skill` — new brainstorm mode for structured exploration
- **docs**: added getting-started guide for onboarding

### Changed
- **hooks**: `gamma-hook` now validates JSON input before processing
- **config**: reorganized powerline layout to 2 lines

### Removed
- **workflow**: deprecated `[skip-raiz]` commit flag

## [1.2.0] - 2026-03-15 - Agent upgrades

### Changed
- **agents**: `beta-agent` — phased investigation protocol, model bumped to opus
- **config**: pruned git segment from powerline display

### Fixed
- **hooks**: `gamma-hook` session-start race condition with `.session-id` relay

## [1.1.0] - 2026-03-01 - Entity & edge cases

### Added
- **skills**: `/alpha-skill` supports `--hierarchical` flag for nested `<tree>` output
- **agents**: `beta-agent` handles R&D queries with <context> tags

### Fixed
- **toolkit**: unrelated bugfix in sync command

## [1.0.5] - 2026-02-15 - Config-only changes

### Changed
- **config**: updated powerline theme colors
- **makefile**: simplified help target

## [0.9.0] - 2026-02-01 - Initial release

### Added
- **skills**: `/alpha-skill` — initial implementation
CHANGELOG_EOF
}

teardown_fixtures() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    TEMP_DIR=""
}

# === Tests ===

echo "Running raiz changelog tests..."
echo "Format script: $FORMAT_SCRIPT"

# --- Entry extraction ---

report_section "=== Entry extraction ==="
setup_fixtures

# 1. First version extracted
out=$(run_fmt 1.3.0 --raw 2>/dev/null) || true
assert_contains "first version: header" "$out" "## [1.3.0]"
assert_contains "first version: has matching content" "$out" "alpha-skill"

# 2. Middle version extracted
out=$(run_fmt 1.2.0 --raw 2>/dev/null) || true
assert_contains "middle version: header" "$out" "## [1.2.0]"
assert_contains "middle version: has matching content" "$out" "beta-agent"

# 3. Last version extracted
out=$(run_fmt 1.1.0 --raw 2>/dev/null) || true
assert_contains "last version: header" "$out" "## [1.1.0]"

# 4. Missing version → Skipping on stderr
rc=0; out=$(run_fmt_stderr 9.9.9 --raw) || rc=$?
assert_exit_zero "missing version exits 0" "$rc"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "missing version: Skipping on stderr" "$stderr_out" "Skipping v9.9.9: not found"

# 5. v prefix stripped
out=$(run_fmt v1.3.0 --raw 2>/dev/null) || true
assert_contains "v prefix stripped: resolves to 1.3.0" "$out" "## [1.3.0]"

# 6. latest resolves from VERSION
out=$(run_fmt latest --raw 2>/dev/null) || true
assert_contains "latest resolves from VERSION" "$out" "## [1.3.0]"

teardown_fixtures

# --- Raiz filtering (--raw output) ---

report_section "=== Raiz filtering (--raw output) ==="
setup_fixtures

out=$(run_fmt 1.3.0 --raw 2>/dev/null) || true

# 1. Keeps matching bullet (alpha-skill in Added)
assert_contains "keeps matching bullet: alpha-skill" "$out" '/alpha-skill`'

# 2. Keeps second matching bullet (gamma-hook in Changed)
assert_contains "keeps matching bullet: gamma-hook" "$out" "gamma-hook"

# 3. Drops non-matching bullets
assert_not_contains "drops non-matching: getting-started" "$out" "getting-started"
assert_not_contains "drops non-matching: powerline" "$out" "powerline"

# 4. Drops empty section entirely (Removed has zero matching bullets)
assert_not_contains "drops empty section: ### Removed" "$out" "### Removed"

# 5. Keeps sections with matches
assert_contains "keeps section: ### Added" "$out" "### Added"
assert_contains "keeps section: ### Changed" "$out" "### Changed"

# 6. Header always kept
first_line=$(echo "$out" | head -1)
assert_contains "header always kept" "$first_line" "## [1.3.0] - 2026-04-01 - Alpha skill & hook improvements"

teardown_fixtures

# --- Version range ---

report_section "=== Version range ==="
setup_fixtures

# 1. Multi-version range (1.1.0, 1.3.0] — exclusive start
out=$(run_fmt 1.3.0 --from 1.1.0 --raw 2>/dev/null) || true
assert_contains "range includes 1.3.0" "$out" "## [1.3.0]"
assert_contains "range includes 1.2.0" "$out" "## [1.2.0]"
assert_not_contains "range excludes 1.1.0" "$out" "## [1.1.0]"

# 2. Newest-first order
pos_130=$(echo "$out" | grep -n '## \[1.3.0\]' | head -1 | cut -d: -f1)
pos_120=$(echo "$out" | grep -n '## \[1.2.0\]' | head -1 | cut -d: -f1)
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "$pos_130" && -n "$pos_120" && "$pos_130" -lt "$pos_120" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "newest-first order: 1.3.0 before 1.2.0"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "newest-first order: 1.3.0 before 1.2.0"
    report_detail "1.3.0 at line ${pos_130:-?}, 1.2.0 at line ${pos_120:-?}"
fi

# 3. Same-version empty range
rc=0; out=$(run_fmt_stderr 1.2.0 --from 1.2.0 --raw) || rc=$?
assert_exit_zero "same-version range exits 0" "$rc"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "same-version range: no versions found" "$stderr_out" "no versions found"

# 4. Single version (no --from)
out=$(run_fmt 1.2.0 --raw 2>/dev/null) || true
assert_contains "single version: has 1.2.0" "$out" "## [1.2.0]"
assert_not_contains "single version: no 1.3.0" "$out" "## [1.3.0]"
assert_not_contains "single version: no 1.1.0" "$out" "## [1.1.0]"

teardown_fixtures

# --- HTML conversion ---

report_section "=== HTML conversion ==="
setup_fixtures

# Tests 1-5 use version 1.3.0
out=$(run_fmt 1.3.0 --html 2>/dev/null) || true

# 1. Emoji + project header
assert_contains "emoji + project header" "$out" "🔄 <b>claude-toolkit-raiz</b> v1.3.0"

# 2. Date and description in italics
assert_contains "date+description italics" "$out" "<i>2026-04-01 — Alpha skill & hook improvements</i>"

# 3. Resource group headers bold
assert_contains "resource group: skills header" "$out" "<b>Skills</b>"
assert_contains "resource group: hooks header" "$out" "<b>Hooks</b>"

# 4. Bold prefix stripped, bullet has • prefix
assert_contains "bullet has dot prefix: skill" "$out" "• <code>/alpha-skill</code>"
assert_not_contains "no inline resource bold" "$out" "<b>skills</b>:"

# 5. Backtick to code tag
assert_contains "backtick to code tag" "$out" "<code>"

# 6. HTML entity escaping (version 1.1.0 has <tree>, <context>, R&D)
out_11=$(run_fmt 1.1.0 --html 2>/dev/null) || true
assert_contains "HTML escaping: angle brackets" "$out_11" "&lt;tree&gt;"
assert_contains "HTML escaping: ampersand" "$out_11" "R&amp;D"

# 7. Single version has date line
assert_contains "single version: date line" "$out" "<i>2026-04-01"

# 8. Bullet has • prefix for hook too
assert_contains "bullet has dot prefix: hook" "$out" "• "

teardown_fixtures

# --- Consolidated format (range) ---

report_section "=== Consolidated format (range) ==="
setup_fixtures

out=$(run_fmt 1.3.0 --from 1.1.0 --html 2>/dev/null) || true

# 1. Range header format
assert_contains "range header: from version" "$out" "v1.1.0 →"
assert_contains "range header: to version" "$out" "→ v1.3.0"

# 2. Range has no date line
assert_not_contains "range: no date line" "$out" "<i>"

# 3. Cross-version grouping: bullets from 1.2.0 and 1.3.0 under resource types
assert_contains "cross-version: alpha-skill from 1.3.0" "$out" "alpha-skill"
assert_contains "cross-version: beta-agent from 1.2.0" "$out" "beta-agent"
assert_contains "cross-version: agents header" "$out" "<b>Agents</b>"

# 4. No per-version emoji headers in consolidated HTML
assert_not_contains "no per-version emoji header" "$out" "claude-toolkit-raiz</b> v1.2.0"

teardown_fixtures

# --- Override files ---

report_section "=== Override files ==="
setup_fixtures

# 1. --override flag uses file as-is (early exit, no trimming)
override_tmp="$TEMP_DIR/manual-override.html"
echo "<b>Manual msg</b>" > "$override_tmp"
out=$(run_fmt 1.3.0 --override "$override_tmp" 2>/dev/null) || true
assert_contains "--override uses file as-is" "$out" "<b>Manual msg</b>"

# 2. --override missing file errors
rc=0; out=$(run_fmt_stderr 1.3.0 --override /nonexistent) || rc=$?
assert_exit_nonzero "--override missing file exits nonzero" "$rc"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "--override missing file: error message" "$stderr_out" "override file not found"

# 3. Auto-detected override replaces HTML
mkdir -p "$TEMP_DIR/dist/raiz/changelog"
echo '<b>Custom override</b> for v1.2.0' > "$TEMP_DIR/dist/raiz/changelog/1.2.0.html"
out=$(run_fmt 1.2.0 --html 2>/dev/null) || true
assert_contains "auto-override replaces HTML" "$out" "Custom override"

# 4. Auto-detected override: trimmed still generated for raw
out=$(run_fmt 1.2.0 --raw 2>/dev/null) || true
assert_contains "auto-override: raw still has header" "$out" "## [1.2.0]"
assert_contains "auto-override: raw still has trimmed content" "$out" "beta-agent"

# Clean up auto-override for remaining tests
rm -rf "$TEMP_DIR/dist/raiz/changelog"

teardown_fixtures

# --- Multi-version output ---

report_section "=== Multi-version output ==="
setup_fixtures

# 1. Combines versions
out=$(run_fmt 1.3.0 --from 1.1.0 --html 2>/dev/null) || true
assert_contains "combines versions: has 1.3.0" "$out" "v1.3.0"
assert_contains "range header format" "$out" "v1.1.0 →"

# 2. Skips version with no matches (1.0.5 has only non-matching config/makefile bullets)
# Range (0.9.0, 1.1.0] includes 1.1.0 (has matches) and 1.0.5 (no matches → skipped)
rc=0; out=$(run_fmt_stderr 1.1.0 --from 0.9.0 --raw) || rc=$?
assert_contains "skips no-match version: has 1.1.0" "$out" "## [1.1.0]"
assert_not_contains "skips no-match version: no 1.0.5 in output" "$out" "## [1.0.5]"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "skips no-match version: Skipping on stderr" "$stderr_out" "Skipping v1.0.5: no raiz-relevant changes"

# 3. All versions skipped exits clean (1.0.5 alone has zero matches)
rc=0; out=$(run_fmt_stderr 1.0.5 --raw) || rc=$?
assert_exit_zero "all-skipped exits 0" "$rc"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "all-skipped: message on stderr" "$stderr_out" "no raiz-relevant changes"

teardown_fixtures

# --- Output modes ---

report_section "=== Output modes ==="
setup_fixtures

# 1. --raw: no HTML tags
out=$(run_fmt 1.3.0 --raw 2>/dev/null) || true
assert_not_contains "--raw: no <b> tags" "$out" "<b>"
assert_not_contains "--raw: no <i> tags" "$out" "<i>"

# 2. --html: no markdown headers
out=$(run_fmt 1.3.0 --html 2>/dev/null) || true
assert_not_contains "--html: no ## [" "$out" "## ["
assert_not_contains "--html: no ### " "$out" "### "

# 3. --out writes to file
run_fmt 1.3.0 --html --out "$TEMP_DIR/out.html" 2>/dev/null || true
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$TEMP_DIR/out.html" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "--out creates file"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "--out creates file"
fi
file_contents=$(cat "$TEMP_DIR/out.html")
assert_contains "--out file has content" "$file_contents" "v1.3.0"

# 4. Default mode has stats
out=$(run_fmt 1.3.0 2>/dev/null) || true
assert_contains "default: has Stats header" "$out" "=== Stats ==="
assert_contains "default: has bullet lines" "$out" "bullet lines"
assert_contains "default: has Message length" "$out" "Message length"

teardown_fixtures

# --- Edge cases ---

report_section "=== Edge cases ==="

# 1. Empty changelog
setup_fixtures
echo "" > "$TEMP_DIR/CHANGELOG.md"
rc=0; out=$(run_fmt_stderr 1.3.0 --raw) || rc=$?
assert_exit_zero "empty changelog exits 0" "$rc"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "empty changelog: Skipping on stderr" "$stderr_out" "Skipping"
teardown_fixtures

# 2. No args shows usage
setup_fixtures
rc=0; out=$(run_fmt_stderr) || rc=$?
assert_exit_nonzero "no args exits nonzero" "$rc"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "no args: shows usage" "$stderr_out" "Usage:"
teardown_fixtures

# 3. Unknown flag errors
setup_fixtures
rc=0; out=$(run_fmt_stderr 1.3.0 --bogus) || rc=$?
assert_exit_nonzero "unknown flag exits nonzero" "$rc"
stderr_out=$(cat "$TEMP_DIR/stderr")
assert_contains "unknown flag: error message" "$stderr_out" "Unknown flag"
teardown_fixtures

# 4. Trailing whitespace stripped
setup_fixtures
out=$(run_fmt 1.3.0 --raw 2>/dev/null) || true
last_line=$(echo "$out" | tail -1)
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "${last_line// /}" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "trailing whitespace stripped: last line non-empty"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "trailing whitespace stripped: last line non-empty"
    report_detail "Last line is blank or whitespace-only"
fi
teardown_fixtures

print_summary
