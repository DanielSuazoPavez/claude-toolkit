#!/usr/bin/env bash
# Automated tests for backlog-query.sh (JSON-based)
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

# Create a test BACKLOG.json with known content (5 tasks)
create_test_backlog() {
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {
    "tests": "Automated testing and validation",
    "skills": "User-invocable skills",
    "agents": "Specialized task agents",
    "toolkit": "Core toolkit infrastructure",
    "icebox": "Deferred items"
  },
  "current_goal": "Test goal",
  "tasks": [
    {
      "id": "critical-test-task",
      "priority": "P0",
      "title": "Critical test task",
      "scope": ["tests"],
      "status": "planned"
    },
    {
      "id": "high-priority-skill",
      "priority": "P1",
      "title": "High priority skill",
      "scope": ["skills"],
      "status": "idea"
    },
    {
      "id": "blocked-agent-task",
      "priority": "P1",
      "title": "Blocked agent task",
      "scope": ["agents"],
      "status": "blocked",
      "relates_to": ["critical-test-task:depends-on"]
    },
    {
      "id": "medium-toolkit-task",
      "priority": "P2",
      "title": "Medium toolkit task",
      "scope": ["toolkit"],
      "status": "in-progress",
      "branch": "feature/toolkit-task",
      "source": "suggestions-box/test-project/issue.txt",
      "references": ["path/to/code.sh", "output/file.md"]
    },
    {
      "id": "nice-to-have-idea",
      "priority": "P99",
      "title": "Nice-to-have idea task",
      "scope": ["icebox"],
      "status": "idea"
    }
  ]
}
ENDJSON
}

run_query() {
    (cd "$TEMP_DIR" && bash cli/backlog/query.sh "$@" 2>&1)
}

# === Test Assertions ===

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
    local output exit_code

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
    local output exit_code

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
    local output exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if [[ "$output" == *"$expected"* ]]; then
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
    local output exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if [[ "$output" != *"$not_expected"* ]]; then
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
    local output exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if [[ "$output" == *"Found $expected_count task"* ]]; then
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

    expect_output "shows help with --help" "claude-toolkit backlog" --help
    expect_output "shows help with -h" "Read:" -h
    expect_output "help lists workflows" "Common workflows" --help

    teardown_test_env
}

test_no_backlog() {
    report_section "=== no BACKLOG.json ==="
    setup_test_env

    expect_failure "errors when BACKLOG.json not found"
    expect_output "shows error message" "BACKLOG.json not found"

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

    expect_output "P99 task visible by default" "Nice-to-have idea task"
    expect_count "lists all 5 without flag" "5"

    expect_count "excludes P99 (4 remain)" "4" --exclude-priority P99
    expect_not_output "hides P99 task" "Nice-to-have idea task" --exclude-priority P99

    expect_count "excludes P99,P2 (3 remain)" "3" --exclude-priority P99,P2
    expect_not_output "hides P2 task too" "Medium toolkit task" --exclude-priority P99,P2

    expect_count "accepts lowercase p99" "4" --exclude-priority p99

    expect_count "composes with priority subcommand" "2" --exclude-priority P99 priority P1

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

test_schema_subcommand() {
    report_section "=== schema subcommand ==="
    setup_test_env

    expect_success "schema subcommand exits 0" schema
    for f in id priority title status scope branch relates_to plan source references notes; do
        expect_output "schema lists $f" "$f" schema
    done
    for s in idea planned in-progress ready-for-pr pr-open blocked; do
        expect_output "schema lists status '$s'" "$s" schema
    done
    for p in P0 P1 P2 P3 P99; do
        expect_output "schema lists priority '$p'" "$p" schema
    done
    for k in depends-on independent-of supersedes split-from; do
        expect_output "schema lists kind '$k'" "$k" schema
    done

    teardown_test_env
}

test_relates_to_filter() {
    report_section "=== relates-to filter ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A", "b": "B", "c": "C", "d": "D"},
  "current_goal": "Test",
  "tasks": [
    {"id": "task-a", "priority": "P1", "title": "Task A", "scope": ["a"], "status": "planned",
     "relates_to": ["task-b:depends-on"]},
    {"id": "task-b", "priority": "P1", "title": "Task B", "scope": ["b"], "status": "planned"},
    {"id": "task-c", "priority": "P1", "title": "Task C", "scope": ["c"], "status": "idea",
     "relates_to": ["task-a:supersedes"]},
    {"id": "task-d", "priority": "P1", "title": "Task D", "scope": ["d"], "status": "idea",
     "relates_to": ["task-a:independent-of", "task-b:depends-on"]}
  ]
}
ENDJSON

    expect_count "depends-on kind finds 2" "2" relates-to depends-on
    expect_count "supersedes finds 1" "1" relates-to supersedes
    expect_count "independent-of finds 1" "1" relates-to independent-of
    expect_failure "errors without kind" relates-to

    expect_count "blocked finds 2 (depends-on relations)" "2" blocked
    expect_count "unblocked finds 2 (idea/planned without :depends-on)" "2" unblocked

    teardown_test_env
}

test_source_filter() {
    report_section "=== source filter ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "task-a", "priority": "P1", "title": "From session", "scope": ["a"], "status": "idea",
     "source": "session/abc123"},
    {"id": "task-b", "priority": "P1", "title": "From suggestions", "scope": ["a"], "status": "idea",
     "source": "suggestions-box/claude-sessions/file.txt"},
    {"id": "task-c", "priority": "P1", "title": "No source", "scope": ["a"], "status": "idea"}
  ]
}
ENDJSON

    expect_count "source 'session/abc' finds 1" "1" source 'session/abc'
    expect_count "source 'claude-sessions' finds 1" "1" source claude-sessions
    expect_count "source 'suggestions-box' finds 1" "1" source suggestions-box
    expect_failure "errors without pattern" source

    expect_output "id lookup shows source" "source: session/abc123" id task-a

    teardown_test_env
}

test_references_field() {
    report_section "=== references field ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "task-a", "priority": "P1", "title": "With references", "scope": ["a"], "status": "idea",
     "references": ["path/code.sh", "output/file.md"]}
  ]
}
ENDJSON

    expect_output "id lookup shows references" "references: path/code.sh,output/file.md" id task-a

    teardown_test_env
}

# === Filter validation ===

test_filter_validation() {
    report_section "=== filter arg validation ==="
    setup_test_env
    create_test_backlog

    expect_failure "rejects invalid priority value" priority P7
    expect_output "explains valid priorities" "valid: P0" priority P7

    expect_failure "rejects invalid status value" status garbage
    expect_output "explains valid statuses" "valid: idea" status garbage

    expect_failure "rejects unknown scope" scope nonexistent
    expect_output "explains valid scopes" "valid:" scope nonexistent

    expect_failure "rejects invalid relates-to kind" relates-to bogus
    expect_output "explains valid kinds" "depends-on" relates-to bogus

    teardown_test_env
}

# === id command exit code ===

test_id_exit_code() {
    report_section "=== id non-zero exit on miss ==="
    setup_test_env
    create_test_backlog

    expect_success "id exits 0 when found" id critical-test-task
    expect_failure "id exits non-zero when missing" id no-such-task
    expect_output "id reports missing task" "not found" id no-such-task

    teardown_test_env
}

# === --json flag ===

test_json_flag() {
    report_section "=== --json output ==="
    setup_test_env
    create_test_backlog

    local output
    output=$(run_query --json priority P0)

    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | jq -e . >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "--json emits valid JSON"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "--json emits valid JSON"
        report_detail "Got: ${output:-<empty>}"
    fi

    expect_not_output "--json suppresses count footer" "Found" --json priority P0
    expect_not_output "--json suppresses formatted brackets" "[planned" --json priority P0
    expect_output "--json emits id" "critical-test-task" --json priority P0

    teardown_test_env
}

# === next command ===

test_next() {
    report_section "=== next subcommand ==="
    setup_test_env
    create_test_backlog

    expect_output "next returns top P0 task" "Critical test task" next
    expect_count "next defaults to 1" "1" next
    expect_count "next 3 returns 3 unblocked" "3" next 3
    expect_not_output "next skips blocked tasks" "Blocked agent task" next 5
    expect_failure "next rejects non-numeric arg" next abc
    expect_failure "next rejects zero" next 0

    expect_output "next composes with --exclude-priority" "High priority skill" next --exclude-priority P0

    teardown_test_env
}

# === Mutation tests ===

test_add() {
    report_section "=== add subcommand ==="
    setup_test_env
    create_test_backlog

    expect_output "add creates task" "Added task" add --id new-task --priority P2 --title "New task" --scope tests
    expect_output "added task is queryable" "New task" id new-task
    expect_output "added task has status idea" "idea" id new-task

    expect_failure "add rejects duplicate id" add --id critical-test-task --priority P2 --title "Dup" --scope tests
    expect_failure "add rejects invalid priority" add --id another --priority P7 --title "Bad" --scope tests
    expect_failure "add rejects invalid scope" add --id another --priority P2 --title "Bad" --scope nonexistent
    expect_failure "add requires all fields" add --id only-id

    teardown_test_env
}

test_move() {
    report_section "=== move subcommand ==="
    setup_test_env
    create_test_backlog

    expect_output "move changes priority" "Moved task" move critical-test-task P99
    expect_output "task is at new priority" "P99" priority P99

    expect_failure "move rejects unknown task" move nonexistent P1
    expect_failure "move rejects invalid priority" move critical-test-task P7

    teardown_test_env
}

test_update() {
    report_section "=== update subcommand ==="
    setup_test_env
    create_test_backlog

    expect_output "update changes status" "Updated task" update high-priority-skill --status planned
    expect_output "status was updated" "planned" id high-priority-skill
    expect_output "update sets branch" "Updated task" update high-priority-skill --branch fix/x
    expect_output "branch was set" "branch: fix/x" id high-priority-skill
    expect_output "update accepts multiple fields" "Updated task" update high-priority-skill --notes "hello" --plan plan/x.md
    expect_output "notes was set" "notes: hello" id high-priority-skill
    expect_output "plan was set" "plan: plan/x.md" id high-priority-skill

    # Empty value deletes the field
    expect_output "empty branch deletes field" "Updated task" update high-priority-skill --branch ""
    expect_not_output "branch field is gone" "branch: fix/x" id high-priority-skill

    expect_failure "update rejects unknown task" update nonexistent --status planned
    expect_failure "update rejects invalid status" update high-priority-skill --status garbage
    expect_failure "update rejects unknown field" update high-priority-skill --bogus value
    expect_failure "update requires at least one field" update high-priority-skill
    expect_failure "update requires id" update

    teardown_test_env
}

test_remove() {
    report_section "=== remove subcommand ==="
    setup_test_env
    create_test_backlog

    expect_count "starts with 5 tasks" "5"
    expect_output "remove deletes task" "Removed task" remove nice-to-have-idea
    expect_count "now has 4 tasks" "4"
    expect_not_output "removed task gone" "Nice-to-have idea task"

    expect_output "remove warns on referenced task" "Warning" remove critical-test-task

    expect_failure "remove rejects unknown task" remove nonexistent

    teardown_test_env
}

test_render() {
    report_section "=== render subcommand ==="
    setup_test_env
    create_test_backlog

    local output
    output=$(run_query render "$TEMP_DIR/rendered.md")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$TEMP_DIR/rendered.md" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "render creates output file"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "render creates output file"
        report_detail "File not found: $TEMP_DIR/rendered.md"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF "Auto-generated from BACKLOG.json" "$TEMP_DIR/rendered.md" 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "render includes auto-generated header"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "render includes auto-generated header"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF "Critical test task" "$TEMP_DIR/rendered.md" 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "render includes task titles"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "render includes task titles"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF "## P0 - Critical" "$TEMP_DIR/rendered.md" 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "render includes priority headers"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "render includes priority headers"
    fi

    teardown_test_env
}

# === Validation tests ===

run_validate() {
    (cd "$TEMP_DIR" && bash cli/backlog/validate.sh BACKLOG.json 2>&1) || true
}

expect_validator_output() {
    local description="$1"
    local expected="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(run_validate)

    if [[ "$output" == *"$expected"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output to contain: $expected"
        report_detail "Got: ${output:-<empty>}"
        _dump_diag "output" "$output"
    fi
}

test_validate_valid() {
    report_section "=== validation: valid backlog ==="
    setup_test_env
    create_test_backlog

    expect_validator_output "valid backlog passes" "valid"

    teardown_test_env
}

test_validate_duplicate_id() {
    report_section "=== validation: duplicate id ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "dup", "priority": "P1", "title": "First", "scope": ["a"], "status": "idea"},
    {"id": "dup", "priority": "P1", "title": "Second", "scope": ["a"], "status": "idea"}
  ]
}
ENDJSON

    expect_validator_output "duplicate id detected" "duplicate id"

    teardown_test_env
}

test_validate_invalid_priority() {
    report_section "=== validation: invalid priority ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "bad", "priority": "P7", "title": "Bad", "scope": ["a"], "status": "idea"}
  ]
}
ENDJSON

    expect_validator_output "invalid priority detected" "invalid priority"

    teardown_test_env
}

test_validate_invalid_status() {
    report_section "=== validation: invalid status ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "bad", "priority": "P1", "title": "Bad", "scope": ["a"], "status": "bogus"}
  ]
}
ENDJSON

    expect_validator_output "invalid status detected" "invalid status"

    teardown_test_env
}

test_validate_missing_status() {
    report_section "=== validation: missing status ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "bad", "priority": "P1", "title": "Bad", "scope": ["a"]}
  ]
}
ENDJSON

    expect_validator_output "missing status detected" "missing required field 'status'"

    teardown_test_env
}

test_validate_missing_required() {
    report_section "=== validation: missing required fields ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"priority": "P1", "title": "No id", "scope": ["a"], "status": "idea"},
    {"id": "no-scope", "priority": "P1", "title": "No scope", "status": "idea"}
  ]
}
ENDJSON

    expect_validator_output "missing id detected" "missing required field 'id'"
    expect_validator_output "missing scope detected" "missing required field 'scope'"

    teardown_test_env
}

test_validate_malformed_relates_to() {
    report_section "=== validation: malformed relates_to ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "bad", "priority": "P1", "title": "Bad", "scope": ["a"], "status": "idea",
     "relates_to": ["bogus-kind"]}
  ]
}
ENDJSON

    expect_validator_output "malformed relates_to detected" "malformed relates_to token"

    teardown_test_env
}

test_validate_priority_inversion() {
    report_section "=== validation: priority inversion warn ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "urgent", "priority": "P0", "title": "Urgent", "scope": ["a"], "status": "planned",
     "relates_to": ["lazy:depends-on"]},
    {"id": "lazy", "priority": "P3", "title": "Lazy", "scope": ["a"], "status": "idea"},
    {"id": "ok", "priority": "P2", "title": "OK", "scope": ["a"], "status": "planned",
     "relates_to": ["urgent:depends-on"]}
  ]
}
ENDJSON

    expect_validator_output "warns on inversion" "depends-on 'lazy' which is lower priority"
    expect_validator_output "names dependent priority" "urgent (P0)"

    # The OK task (P2 -> depends-on P0) should NOT trigger a warn
    local output
    output=$(run_validate)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$output" != *"ok (P2): depends-on 'urgent'"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "no warn when depending on higher priority"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "no warn when depending on higher priority"
        report_detail "Output unexpectedly contains the warn"
    fi

    teardown_test_env
}

test_validate_unknown_scope() {
    report_section "=== validation: unknown scope ==="
    setup_test_env
    cat > "$TEMP_DIR/BACKLOG.json" << 'ENDJSON'
{
  "scopes": {"a": "A"},
  "current_goal": "Test",
  "tasks": [
    {"id": "bad", "priority": "P1", "title": "Bad", "scope": ["nonexistent"], "status": "idea"}
  ]
}
ENDJSON

    expect_validator_output "unknown scope warned" "scope 'nonexistent' not in scopes"

    teardown_test_env
}

# === Summary sort test ===

test_summary_sorted() {
    report_section "=== summary priority sort ==="
    setup_test_env
    create_test_backlog

    local output
    output=$(run_query summary)

    TESTS_RUN=$((TESTS_RUN + 1))
    local p0_line p1_line p2_line p99_line
    p0_line=$(echo "$output" | grep -n "P0:" | head -1 | cut -d: -f1)
    p1_line=$(echo "$output" | grep -n "P1:" | head -1 | cut -d: -f1)
    p2_line=$(echo "$output" | grep -n "P2:" | head -1 | cut -d: -f1)
    p99_line=$(echo "$output" | grep -n "P99:" | head -1 | cut -d: -f1)

    if [[ $p0_line -lt $p1_line && $p1_line -lt $p2_line && $p2_line -lt $p99_line ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "summary priorities sorted P0→P1→P2→P99"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "summary priorities sorted P0→P1→P2→P99"
        report_detail "Lines: P0=$p0_line P1=$p1_line P2=$p2_line P99=$p99_line"
        report_detail "Output: $output"
    fi

    teardown_test_env
}

# === RUN TESTS ===
echo "Running backlog-query tests..."
echo "Script: $QUERY_SCRIPT"

# Core query tests
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

# Schema-driven
test_schema_subcommand
test_relates_to_filter
test_source_filter
test_references_field

# Filter validation + new read commands
test_filter_validation
test_id_exit_code
test_json_flag
test_next

# Mutations
test_add
test_move
test_update
test_remove
test_render

# Validation
test_validate_valid
test_validate_duplicate_id
test_validate_invalid_priority
test_validate_invalid_status
test_validate_missing_status
test_validate_missing_required
test_validate_malformed_relates_to
test_validate_priority_inversion
test_validate_unknown_scope

# Summary sort fix
test_summary_sorted

print_summary
