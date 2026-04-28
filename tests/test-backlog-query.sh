#!/usr/bin/env bash
# Automated tests for backlog-query.sh
#
# Usage:
#   bash tests/test-backlog-query.sh      # Run all tests
#   bash tests/test-backlog-query.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-backlog-query.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUERY_SCRIPT="$TOOLKIT_DIR/cli/backlog/query.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"

    # Mirror the cli/backlog/ + .claude/schemas/backlog/ layout so the script's
    # relative path resolution works inside the temp dir.
    mkdir -p "$TEMP_DIR/cli/backlog/lib" "$TEMP_DIR/.claude/schemas/backlog"
    cp "$QUERY_SCRIPT" "$TEMP_DIR/cli/backlog/"
    cp "$TOOLKIT_DIR/cli/backlog/validate.sh" "$TEMP_DIR/cli/backlog/"
    cp "$TOOLKIT_DIR/cli/backlog/lib/schema.sh" "$TEMP_DIR/cli/backlog/lib/"
    cp "$TOOLKIT_DIR/.claude/schemas/backlog/task.schema.json" \
        "$TEMP_DIR/.claude/schemas/backlog/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Create a test BACKLOG.md with known content
create_test_backlog() {
    cat > "$TEMP_DIR/BACKLOG.md" << 'EOF'
# Project Backlog

## P0 - Critical

- **[TESTING]** Critical test task
    - **status**: `planned`
    - **scope**: `tests`

---

## P1 - High

- **[SKILLS]** High priority skill
    - **status**: `idea`
    - **scope**: `skills`

- **[AGENTS]** Blocked agent task
    - **status**: `blocked`
    - **scope**: `agents`
    - **relates-to**: `critical-test-task:depends-on`

---

## P2 - Medium

- **[TOOLKIT]** Medium toolkit task
    - **status**: `in-progress`
    - **scope**: `toolkit`
    - **branch**: `feature/toolkit-task`
    - **source**: `suggestions-box/test-project/issue.txt`
    - **references**: `path/to/code.sh`, `output/file.md`

---

## P99 - Nice to Have

- **[ICEBOX]** Nice-to-have idea task
    - **status**: `idea`
    - **scope**: `icebox`

EOF
}

run_query() {
    (cd "$TEMP_DIR" && bash cli/backlog/query.sh "$@" 2>&1)
}

# === Test Assertions ===

# Diagnostic helper: dump byte length + hex of the first ~200 bytes of a variable.
# Called from assertion failure branches to diagnose WSL2 flaky grep misses.
_dump_diag() {
    local label="$1"
    local data="$2"
    local byte_len
    byte_len=$(printf '%s' "$data" | wc -c)
    report_detail "[diag] $label byte length: $byte_len"
    report_detail "[diag] $label hex dump (first ~200 bytes):"
    printf '%s' "$data" | xxd | head -20 | while IFS= read -r line; do
        report_detail "  $line"
    done
}

expect_success() {
    local description="$1"
    shift
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: exit code 0"
        report_detail "Got: exit code $exit_code"
        report_detail "Output: ${output:-<empty>}"
    fi
}

expect_failure() {
    local description="$1"
    shift
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: non-zero exit code"
        report_detail "Got: exit code 0"
        report_detail "Output: ${output:-<empty>}"
    fi
}

expect_output() {
    local description="$1"
    local expected="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if echo "$output" | grep -qF -- "$expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output to contain: $expected"
        report_detail "Got: ${output:-<empty>}"
        _dump_diag "output" "$output"
        _dump_diag "expected" "$expected"
    fi
}

expect_not_output() {
    local description="$1"
    local not_expected="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if ! echo "$output" | grep -qF -- "$not_expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output does not contain: $not_expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output NOT to contain: $not_expected"
        report_detail "Got: ${output:-<empty>}"
        _dump_diag "output" "$output"
        _dump_diag "not_expected" "$not_expected"
    fi
}

expect_count() {
    local description="$1"
    local expected_count="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if echo "$output" | grep -qF -- "Found $expected_count task"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Found $expected_count task(s)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: Found $expected_count task(s)"
        report_detail "Got: ${output:-<empty>}"
        _dump_diag "output" "$output"
    fi
}

# === TESTS ===

test_help() {
    report_section "=== --help ==="
    setup_test_env
    create_test_backlog

    expect_output "shows usage with --help" "Usage:" --help
    expect_output "shows usage with -h" "Usage:" -h

    teardown_test_env
}

test_no_backlog() {
    report_section "=== no BACKLOG.md ==="
    setup_test_env
    # Don't create BACKLOG.md

    expect_failure "errors when BACKLOG.md not found"
    expect_output "shows error message" "BACKLOG.md not found"

    teardown_test_env
}

test_list_all() {
    report_section "=== list all (default) ==="
    setup_test_env
    create_test_backlog

    expect_success "lists tasks without args"
    expect_output "shows P0 task" "Critical test task"
    expect_output "shows P1 task" "High priority skill"
    expect_output "shows P2 task" "Medium toolkit task"
    expect_count "finds 5 tasks" "5"

    teardown_test_env
}

test_filter_status() {
    report_section "=== status filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by status=planned" "Critical test task" status planned
    expect_count "finds 1 planned task" "1" status planned

    expect_output "filters by status=idea" "High priority skill" status idea
    expect_count "finds 2 idea tasks" "2" status idea

    expect_failure "errors without status value" status

    teardown_test_env
}

test_filter_priority() {
    report_section "=== priority filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by P0" "Critical test task" priority P0
    expect_count "finds 1 P0 task" "1" priority P0

    expect_output "filters by P1" "High priority skill" priority P1
    expect_count "finds 2 P1 tasks" "2" priority P1

    expect_output "handles lowercase" "Critical test task" priority p0

    expect_failure "errors without priority value" priority

    teardown_test_env
}

test_filter_scope() {
    report_section "=== scope filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by scope=skills" "High priority skill" scope skills
    expect_count "finds 1 skills task" "1" scope skills

    expect_output "filters by scope=toolkit" "Medium toolkit task" scope toolkit

    expect_failure "errors without scope value" scope

    teardown_test_env
}

test_blocked_unblocked() {
    report_section "=== blocked/unblocked ==="
    setup_test_env
    create_test_backlog

    expect_output "blocked shows tasks with depends-on" "Blocked agent task" blocked
    expect_count "finds 1 blocked task" "1" blocked

    expect_output "unblocked shows planned without depends" "Critical test task" unblocked
    expect_count "finds 3 unblocked tasks" "3" unblocked

    teardown_test_env
}

test_branch() {
    report_section "=== branch filter ==="
    setup_test_env
    create_test_backlog

    expect_output "shows tasks with branches" "Medium toolkit task" branch
    expect_count "finds 1 task with branch" "1" branch

    teardown_test_env
}

test_verbose() {
    report_section "=== verbose mode ==="
    setup_test_env
    create_test_backlog

    expect_output "verbose shows scope" "scope:" -v
    expect_output "verbose shows branch" "branch:" -v priority P2

    teardown_test_env
}

test_exclude_priority() {
    report_section "=== --exclude-priority filter ==="
    setup_test_env
    create_test_backlog

    # Baseline: P99 task is visible without the flag
    expect_output "P99 task visible by default" "Nice-to-have idea task"
    expect_count "lists all 5 without flag" "5"

    # Single-priority exclude
    expect_count "excludes P99 (4 remain)" "4" --exclude-priority P99
    expect_not_output "hides P99 task" "Nice-to-have idea task" --exclude-priority P99

    # Comma list
    expect_count "excludes P99,P2 (3 remain)" "3" --exclude-priority P99,P2
    expect_not_output "hides P2 task too" "Medium toolkit task" --exclude-priority P99,P2

    # Lowercase accepted
    expect_count "accepts lowercase p99" "4" --exclude-priority p99

    # Composes with subcommand filter: priority P1 still finds 2
    expect_count "composes with priority subcommand" "2" --exclude-priority P99 priority P1

    # Error when value missing
    expect_failure "errors without value" --exclude-priority

    teardown_test_env
}

test_unknown_command() {
    report_section "=== unknown command ==="
    setup_test_env
    create_test_backlog

    expect_failure "errors on unknown command" foobar
    expect_output "shows error message" "Unknown command" foobar

    teardown_test_env
}

# === Phase 7.2 — Schema, relates-to, source, drift detection ===

# Helper: write a custom BACKLOG.md (one task per call, append mode after first).
write_test_backlog() {
    local body="$1"
    cat > "$TEMP_DIR/BACKLOG.md" <<EOF
# Project Backlog

## P1 - High

$body
EOF
}

# Helper: run validate.sh, capture stdout+stderr.
run_validate() {
    (cd "$TEMP_DIR" && bash cli/backlog/validate.sh BACKLOG.md 2>&1) || true
}

# Helper: check that validator output contains a substring.
expect_validator_output() {
    local description="$1"
    local expected="$2"
    local body="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    write_test_backlog "$body"
    local output
    output=$(run_validate)

    if echo "$output" | grep -qF -- "$expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output to contain: $expected"
        report_detail "Got: ${output:-<empty>}"
        _dump_diag "output" "$output"
        _dump_diag "expected" "$expected"
    fi
}

# Helper: check validator output does NOT contain a substring.
expect_validator_silent() {
    local description="$1"
    local not_expected="$2"
    local body="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    write_test_backlog "$body"
    local output
    output=$(run_validate)

    if ! echo "$output" | grep -qF -- "$not_expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output NOT to contain: $not_expected"
        report_detail "Got: ${output:-<empty>}"
        _dump_diag "output" "$output"
        _dump_diag "not_expected" "$not_expected"
    fi
}

test_schema_subcommand() {
    report_section "=== schema subcommand ==="
    setup_test_env
    # No BACKLOG.md needed — schema runs without one.

    expect_success "schema subcommand exits 0" schema
    # Every schema field appears
    for f in status scope branch relates-to plan source references notes; do
        expect_output "schema lists $f" "$f" schema
    done
    # Every status value appears
    for s in idea planned in-progress ready-for-pr pr-open blocked; do
        expect_output "schema lists status '$s'" "$s" schema
    done
    # Every relates-to kind appears
    for k in depends-on independent-of supersedes split-from; do
        expect_output "schema lists kind '$k'" "$k" schema
    done

    teardown_test_env
}

test_relates_to_filter() {
    report_section "=== relates-to filter ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.md" <<'EOF'
# Project Backlog

## P1 - High

- **[A]** Task A (`task-a`)
    - **status**: `planned`
    - **relates-to**: `task-b:depends-on`

- **[B]** Task B (`task-b`)
    - **status**: `planned`

- **[C]** Task C (`task-c`)
    - **status**: `idea`
    - **relates-to**: `task-a:supersedes`

- **[D]** Task D (`task-d`)
    - **status**: `idea`
    - **relates-to**: `task-a:independent-of`, `task-b:depends-on`
EOF

    expect_count "depends-on kind finds 2" "2" relates-to depends-on
    expect_count "supersedes finds 1" "1" relates-to supersedes
    expect_count "independent-of finds 1" "1" relates-to independent-of
    expect_failure "errors without kind" relates-to

    # blocked/unblocked use the new column 8 with :depends-on suffix
    expect_count "blocked finds 2 (depends-on relations)" "2" blocked
    expect_count "unblocked finds 2 (idea/planned without :depends-on)" "2" unblocked

    teardown_test_env
}

test_source_filter() {
    report_section "=== source filter ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.md" <<'EOF'
# Project Backlog

## P1 - High

- **[A]** From session (`task-a`)
    - **status**: `idea`
    - **source**: `session/abc123`

- **[B]** From suggestions (`task-b`)
    - **status**: `idea`
    - **source**: `suggestions-box/claude-sessions/file.txt`

- **[C]** No source (`task-c`)
    - **status**: `idea`
EOF

    # Pattern is a substring/regex via awk — 'session' would also match
    # 'claude-sessions', so use the discriminating prefix 'session/abc'.
    expect_count "source 'session/abc' finds 1" "1" source 'session/abc'
    expect_count "source 'claude-sessions' finds 1" "1" source claude-sessions
    expect_count "source 'suggestions-box' finds 1" "1" source suggestions-box
    expect_failure "errors without pattern" source

    # Verbose 'id' lookup shows source line
    expect_output "id lookup shows source" "source: session/abc123" id task-a

    teardown_test_env
}

test_references_field() {
    report_section "=== references field ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.md" <<'EOF'
# Project Backlog

## P1 - High

- **[A]** With references (`task-a`)
    - **status**: `idea`
    - **references**: `path/code.sh`, `output/file.md`
EOF

    expect_output "id lookup shows references" "references: path/code.sh,output/file.md" id task-a

    teardown_test_env
}

test_relates_to_edge_cases() {
    report_section "=== relates-to edge cases (validator) ==="
    setup_test_env

    # Single value, no comma — accepted.
    expect_validator_silent "single value parses cleanly" "malformed" \
        "- **[A]** A (\`a\`)
    - **relates-to**: \`b:supersedes\`"

    # Trailing comma — accepted (empty token dropped).
    expect_validator_silent "trailing comma silently dropped" "malformed" \
        "- **[A]** A (\`a\`)
    - **relates-to**: \`b:supersedes\`, \`c:depends-on\`,"

    # Invalid kind — error.
    expect_validator_output "invalid kind errors" "malformed relates-to token" \
        "- **[A]** A (\`a\`)
    - **relates-to**: \`b:bogus-kind\`"

    # Missing kind (no colon) — error.
    expect_validator_output "missing :kind errors" "malformed relates-to token" \
        "- **[A]** A (\`a\`)
    - **relates-to**: \`bare-id\`"

    # Missing id (colon at start) — error.
    expect_validator_output "missing id errors" "malformed relates-to token" \
        "- **[A]** A (\`a\`)
    - **relates-to**: \`:depends-on\`"

    teardown_test_env
}

test_legacy_depends_on_warning() {
    report_section "=== legacy depends-on field (validator) ==="
    setup_test_env

    # Field with the old name (correctly hyphenated) → warn with migration hint.
    expect_validator_output "depends-on field warns with migration hint" \
        "field 'depends-on' removed" \
        "- **[A]** A (\`a\`)
    - **depends-on**: \`other-task\`"

    teardown_test_env
}

test_typo_detection() {
    report_section "=== typo detection (validator) ==="
    setup_test_env

    # 'depends on' (space) → error pointing at depends-on AND the migration.
    expect_validator_output "depends on (space) errors with did-you-mean" \
        "did you mean 'depends-on'" \
        "- **[A]** A (\`a\`)
    - **depends on**: \`other\`"

    # Typo of a still-valid field — error: did you mean.
    expect_validator_output "typo of valid field errors" \
        "did you mean 'relates-to'" \
        "- **[A]** A (\`a\`)
    - **relates to**: \`b:depends-on\`"

    # Pure unknown field (no space typo) — warn, not error.
    expect_validator_output "unknown field warns" \
        "warn" \
        "- **[A]** A (\`a\`)
    - **bogus-field**: \`x\`"

    teardown_test_env
}

test_legacy_scope_format() {
    report_section "=== legacy single-pair scope format (validator + parser) ==="
    setup_test_env

    # Validator warns on legacy form.
    expect_validator_output "legacy scope warns" "legacy" \
        "- **[A]** A (\`a\`)
    - **scope**: \`x, y\`"

    # Parser still tokenizes both forms identically.
    cat > "$TEMP_DIR/BACKLOG.md" <<'EOF'
# Project Backlog

## P1 - High

- **[A]** Legacy form (`task-a`)
    - **status**: `idea`
    - **scope**: `x, y`

- **[B]** Canonical form (`task-b`)
    - **status**: `idea`
    - **scope**: `x`, `y`
EOF
    # `scope x` should match both
    expect_count "scope filter matches both legacy and canonical" "2" scope x

    teardown_test_env
}

test_canonical_scope_format() {
    report_section "=== canonical per-value scope format (validator) ==="
    setup_test_env

    expect_validator_silent "canonical scope is silent" "legacy" \
        "- **[A]** A (\`a\`)
    - **scope**: \`x\`, \`y\`"

    teardown_test_env
}

# === RUN TESTS ===
echo "Running backlog-query tests..."
echo "Script: $QUERY_SCRIPT"

test_help
test_no_backlog
test_list_all
test_filter_status
test_filter_priority
test_filter_scope
test_blocked_unblocked
test_branch
test_verbose
test_exclude_priority
test_unknown_command

# Phase 7.2 — schema-driven additions
test_schema_subcommand
test_relates_to_filter
test_source_filter
test_references_field
test_relates_to_edge_cases
test_legacy_depends_on_warning
test_typo_detection
test_legacy_scope_format
test_canonical_scope_format

print_summary
