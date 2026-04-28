#!/usr/bin/env bash
# Automated tests for evaluation-query.sh
#
# Usage:
#   bash tests/test-evaluation-query.sh      # Run all tests
#   bash tests/test-evaluation-query.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-evaluation-query.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUERY_SCRIPT="$TOOLKIT_DIR/cli/eval/query.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"

    # Create mock cli/eval structure and copy script
    mkdir -p "$TEMP_DIR/cli/eval"
    cp "$QUERY_SCRIPT" "$TEMP_DIR/cli/eval/"

    # Create mock resource dirs
    mkdir -p "$TEMP_DIR/.claude/skills/mock-skill"
    echo "# Mock Skill" > "$TEMP_DIR/.claude/skills/mock-skill/SKILL.md"

    mkdir -p "$TEMP_DIR/.claude/hooks"
    echo "#!/usr/bin/env bash" > "$TEMP_DIR/.claude/hooks/mock-hook.sh"

    mkdir -p "$TEMP_DIR/.claude/docs"
    echo "# Mock Doc" > "$TEMP_DIR/.claude/docs/mock-doc.md"

    mkdir -p "$TEMP_DIR/.claude/agents"
    echo "# Mock Agent" > "$TEMP_DIR/.claude/agents/mock-agent.md"

    # Create docs/indexes dir
    mkdir -p "$TEMP_DIR/docs/indexes"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Compute md5 hash matching what the script does: md5sum file | cut -c1-8
get_hash() {
    md5sum "$1" 2>/dev/null | cut -c1-8
}

# Create evaluations.json with controlled data
# Uses actual hashes from mock files for stale detection testing
create_test_evaluations() {
    local skill_hash
    skill_hash=$(get_hash "$TEMP_DIR/.claude/skills/mock-skill/SKILL.md")
    # mock-hook gets a mismatched hash (stale)
    # mock-doc is not in evaluations.json (unevaluated)

    cat > "$TEMP_DIR/docs/indexes/evaluations.json" << EOF
{
    "skills": {
        "evaluate_skill": "/evaluate-skill",
        "resources": {
            "mock-skill": {
                "file_hash": "$skill_hash",
                "date": "2026-03-20",
                "type": "knowledge",
                "score": 95,
                "max": 100,
                "percentage": 95.0,
                "dimensions": {
                    "D1": 18,
                    "D2": 14,
                    "D3": 13
                }
            }
        }
    },
    "hooks": {
        "evaluate_skill": "/evaluate-hook",
        "resources": {
            "mock-hook": {
                "file_hash": "00000000",
                "date": "2026-03-15",
                "type": "safety",
                "score": 75,
                "max": 100,
                "percentage": 75.0,
                "dimensions": {
                    "D1": 15,
                    "D2": 10
                }
            }
        }
    },
    "docs": {
        "evaluate_skill": "/evaluate-docs",
        "resources": {}
    },
    "agents": {
        "evaluate_skill": "/evaluate-agent",
        "resources": {
            "mock-agent": {
                "file_hash": "00000000",
                "date": "2026-03-10",
                "type": "behavioral",
                "score": 55,
                "max": 100,
                "percentage": 55.0,
                "dimensions": {
                    "D1": 10,
                    "D2": 8
                }
            }
        }
    }
}
EOF
}

run_query() {
    (cd "$TEMP_DIR" && bash cli/eval/query.sh "$@" 2>&1)
}

# === Test Assertions ===

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
        echo "    Expected: exit code 0"
        echo "    Got: exit code $exit_code"
        echo "    Output: ${output:-<empty>}"
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
        echo "    Expected: non-zero exit code"
        echo "    Got: exit code 0"
        echo "    Output: ${output:-<empty>}"
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
        echo "    Expected output to contain: $expected"
        echo "    Got: ${output:-<empty>}"
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
        echo "    Expected output NOT to contain: $not_expected"
        echo "    Got: ${output:-<empty>}"
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

    if echo "$output" | grep -qF -- "Found $expected_count "; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Found $expected_count"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected: Found $expected_count ..."
        echo "    Got: ${output:-<empty>}"
    fi
}

# === TESTS ===

test_missing_eval_file() {
    report_section "=== missing evaluations.json ==="
    setup_test_env
    # Don't create evaluations.json

    expect_failure "errors when evaluations.json not found"
    expect_output "shows error message" "evaluations.json not found"

    teardown_test_env
}

test_list_default() {
    report_section "=== list all (default) ==="
    setup_test_env
    create_test_evaluations

    expect_success "lists resources without args"
    expect_output "shows skill resource" "mock-skill"
    expect_output "shows hook resource" "mock-hook"
    expect_output "shows agent resource" "mock-agent"
    expect_count "finds 3 evaluated resources" "3 evaluated"

    teardown_test_env
}

test_type_filter() {
    report_section "=== type filter ==="
    setup_test_env
    create_test_evaluations

    expect_output "type skills shows mock-skill" "mock-skill" type skills
    expect_not_output "type skills hides mock-hook" "mock-hook" type skills
    expect_not_output "type skills hides mock-agent" "mock-agent" type skills
    expect_count "type skills finds 1 resource" "1 evaluated" type skills

    expect_output "type agents shows mock-agent" "mock-agent" type agents
    expect_not_output "type agents hides mock-skill" "mock-skill" type agents

    teardown_test_env
}

test_stale() {
    report_section "=== stale detection ==="
    setup_test_env
    create_test_evaluations

    # mock-skill has matching hash (not stale)
    # mock-hook has hash 00000000 (stale — different from actual file hash)
    # mock-agent has hash 00000000 (stale — different from actual file hash)
    expect_success "stale command succeeds"
    expect_output "detects stale mock-hook" "mock-hook" stale
    expect_output "detects stale mock-agent" "mock-agent" stale
    expect_not_output "mock-skill is not stale" "mock-skill" stale

    teardown_test_env
}

test_stale_none() {
    report_section "=== no stale resources ==="
    setup_test_env

    # Create evaluations with correct hashes for all resources
    local skill_hash hook_hash agent_hash doc_hash
    skill_hash=$(get_hash "$TEMP_DIR/.claude/skills/mock-skill/SKILL.md")
    hook_hash=$(get_hash "$TEMP_DIR/.claude/hooks/mock-hook.sh")
    agent_hash=$(get_hash "$TEMP_DIR/.claude/agents/mock-agent.md")
    doc_hash=$(get_hash "$TEMP_DIR/.claude/docs/mock-doc.md")

    cat > "$TEMP_DIR/docs/indexes/evaluations.json" << EOF
{
    "skills": { "resources": { "mock-skill": { "file_hash": "$skill_hash", "date": "2026-03-20", "score": 95, "max": 100, "percentage": 95.0 } } },
    "hooks": { "resources": { "mock-hook": { "file_hash": "$hook_hash", "date": "2026-03-20", "score": 75, "max": 100, "percentage": 75.0 } } },
    "docs": { "resources": { "mock-doc": { "file_hash": "$doc_hash", "date": "2026-03-20", "score": 80, "max": 100, "percentage": 80.0 } } },
    "agents": { "resources": { "mock-agent": { "file_hash": "$agent_hash", "date": "2026-03-20", "score": 55, "max": 100, "percentage": 55.0 } } }
}
EOF

    expect_output "no stale resources message" "No stale resources" stale

    teardown_test_env
}

test_unevaluated() {
    report_section "=== unevaluated detection ==="
    setup_test_env
    create_test_evaluations

    # mock-doc is on disk but not in evaluations.json docs.resources
    expect_success "unevaluated command succeeds"
    expect_output "detects unevaluated mock-doc" "mock-doc" unevaluated
    expect_output "suggests evaluate skill" "/evaluate-docs" unevaluated

    teardown_test_env
}

test_unevaluated_all_present() {
    report_section "=== all resources evaluated ==="
    setup_test_env

    local skill_hash
    skill_hash=$(get_hash "$TEMP_DIR/.claude/skills/mock-skill/SKILL.md")

    cat > "$TEMP_DIR/docs/indexes/evaluations.json" << EOF
{
    "skills": { "resources": { "mock-skill": { "file_hash": "$skill_hash", "date": "2026-03-20", "score": 95, "max": 100, "percentage": 95.0 } } },
    "hooks": { "resources": { "mock-hook": { "file_hash": "abc", "date": "2026-03-20", "score": 75, "max": 100, "percentage": 75.0 } } },
    "docs": { "resources": { "mock-doc": { "file_hash": "abc", "date": "2026-03-20", "score": 80, "max": 100, "percentage": 80.0 } } },
    "agents": { "resources": { "mock-agent": { "file_hash": "abc", "date": "2026-03-20", "score": 55, "max": 100, "percentage": 55.0 } } }
}
EOF

    expect_output "all evaluated message" "All resources evaluated" unevaluated

    teardown_test_env
}

test_above() {
    report_section "=== above threshold ==="
    setup_test_env
    create_test_evaluations

    # Scores: mock-skill=95%, mock-hook=75%, mock-agent=55%
    expect_output "above 85 shows mock-skill" "mock-skill" above 85
    expect_not_output "above 85 hides mock-hook" "mock-hook" above 85
    expect_output "above 85 finds 1 resource" "1 resource(s)" above 85

    expect_output "above 70 shows mock-skill" "mock-skill" above 70
    expect_output "above 70 shows mock-hook" "mock-hook" above 70
    expect_not_output "above 70 hides mock-agent" "mock-agent" above 70
    expect_output "above 70 finds 2 resources" "2 resource(s)" above 70

    expect_output "above 100 finds 0 resources" "0 resource(s)" above 100

    # Default threshold (85)
    expect_output "above default shows mock-skill" "mock-skill" above
    expect_not_output "above default hides mock-hook" "mock-hook" above

    teardown_test_env
}

test_verbose() {
    report_section "=== verbose mode ==="
    setup_test_env
    create_test_evaluations

    expect_output "verbose shows dimension scores" "D1:" -v
    expect_output "verbose shows dimension for specific type" "D2:" -v type skills

    teardown_test_env
}

test_help() {
    report_section "=== --help ==="
    setup_test_env
    create_test_evaluations

    expect_output "shows usage with --help" "Usage:" --help
    expect_output "shows usage with -h" "Usage:" -h

    teardown_test_env
}

test_unknown_command() {
    report_section "=== unknown command ==="
    setup_test_env
    create_test_evaluations

    expect_failure "errors on unknown command" foobar
    expect_output "shows error message" "Unknown command" foobar

    teardown_test_env
}

# === RUN TESTS ===
echo "Running evaluation-query tests..."
echo "Script: $QUERY_SCRIPT"

test_missing_eval_file
test_list_default
test_type_filter
test_stale
test_stale_none
test_unevaluated
test_unevaluated_all_present
test_above
test_verbose
test_help
test_unknown_command

print_summary
