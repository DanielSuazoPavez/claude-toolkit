#!/usr/bin/env bash
# Shared test helpers for bash test suites
#
# Usage:
#   source "$(dirname "$0")/lib/test-helpers.sh"
#   parse_test_args "$@"
#   ... run tests using report_pass / report_fail / report_detail ...
#   print_summary

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Counters ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# --- Mode flags ---
VERBOSE="${VERBOSE:-0}"
QUIET="${QUIET:-0}"

# --- Section header buffer (for quiet mode) ---
_PENDING_SECTION=""

# Parse -q / -v flags. Sets QUIET and VERBOSE.
# Remaining args are stored in TEST_ARGS array for the caller.
TEST_ARGS=()
parse_test_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quiet) QUIET=1; shift ;;
            -v|--verbose) VERBOSE=1; shift ;;
            *) TEST_ARGS+=("$1"); shift ;;
        esac
    done
}

# Buffer a section header. In quiet mode, only printed if a failure follows.
# In normal/verbose mode, printed immediately.
report_section() {
    if [ "$QUIET" = "1" ]; then
        _PENDING_SECTION="$1"
    else
        echo ""
        echo "$1"
    fi
}

# Flush buffered section header (called before printing a failure)
_flush_section() {
    if [ -n "$_PENDING_SECTION" ]; then
        echo ""
        echo "$_PENDING_SECTION"
        _PENDING_SECTION=""
    fi
}

# Print a PASS line (suppressed in quiet mode)
report_pass() {
    local description="$1"
    if [ "$QUIET" != "1" ]; then
        echo -e "  ${GREEN}PASS${NC}: $description"
    fi
}

# Print a FAIL line (always shown, flushes section header first)
report_fail() {
    local description="$1"
    _flush_section
    echo -e "  ${RED}FAIL${NC}: $description"
}

# Print indented detail (always shown — used after report_fail)
report_detail() {
    echo "    $1"
}

# Print only in verbose mode
log_verbose() {
    [ "$VERBOSE" = "1" ] && echo "  $*"
}

# --- Hook expectation helpers ---
# These drive a hook script by piping JSON to it and asserting on output.
# They rely on $HOOKS_DIR (set by hook-test-setup.sh or by the caller).

# Expects output to contain '"decision": "block"'
expect_block() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: $output"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: block decision"
        report_detail "Got: ${output:-<empty>}"
    fi
}

# Expects empty output or an explicit allow decision
expect_allow() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if [ -z "$output" ] || echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"allow"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:-<empty>}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: empty or allow decision"
        report_detail "Got: $output"
    fi
}

# Expects PermissionRequest approval (decision.behavior: allow)
expect_approve() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if echo "$output" | grep -q '"behavior"[[:space:]]*:[[:space:]]*"allow"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: $output"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: decision.behavior allow"
        report_detail "Got: ${output:-<empty>}"
    fi
}

# Expects PreToolUse ask decision (permissionDecision: ask)
expect_ask() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if echo "$output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: $output"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: permissionDecision ask"
        report_detail "Got: ${output:-<empty>}"
    fi
}

# Expects empty output (hook stayed silent — no approval)
expect_silent() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if [ -z "$output" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: <empty>"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: <empty>"
        report_detail "Got: $output"
    fi
}

# Expects output to contain a string
expect_contains() {
    local hook="$1"
    local input="$2"
    local expected="$3"
    local description="$4"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if [[ "$output" == *"$expected"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected to contain: $expected"
        report_detail "Got: ${output:-<empty>}"
    fi
}

# --- Batch execution helpers ---
# Run multiple hook assertions in parallel, then evaluate results in order.
#
# Usage:
#   batch_start "$hook"
#   batch_add block "$input1" "description1"
#   batch_add allow "$input2" "description2"
#   batch_add contains "$input3" "expected_pattern" "description3"
#   batch_run
#
# Each batch_add call collects a test case. batch_run fires all hook
# invocations in parallel (BATCH_JOBS, default nproc), then checks
# results sequentially — counters and output ordering are preserved.

_BATCH_HOOK=""
_BATCH_DIR=""
_BATCH_COUNT=0
declare -a _BATCH_TYPES=()
declare -a _BATCH_INPUTS=()
declare -a _BATCH_DESCS=()
declare -a _BATCH_EXTRAS=()

batch_start() {
    _BATCH_HOOK="$1"
    _BATCH_COUNT=0
    _BATCH_TYPES=()
    _BATCH_INPUTS=()
    _BATCH_DESCS=()
    _BATCH_EXTRAS=()
    _BATCH_DIR=$(mktemp -d)
}

batch_add() {
    local type="$1" input desc extra=""
    if [ "$type" = "contains" ]; then
        input="$2"; extra="$3"; desc="$4"
    else
        input="$2"; desc="$3"
    fi
    _BATCH_TYPES+=("$type")
    _BATCH_INPUTS+=("$input")
    _BATCH_DESCS+=("$desc")
    _BATCH_EXTRAS+=("$extra")
    _BATCH_COUNT=$((_BATCH_COUNT + 1))
}

batch_run() {
    local jobs="${BATCH_JOBS:-$(nproc 2>/dev/null || echo 4)}"
    local hook_path="$HOOKS_DIR/$_BATCH_HOOK"
    local i

    # Write each input to a file and run all hook invocations in parallel
    for ((i = 0; i < _BATCH_COUNT; i++)); do
        printf '%s' "${_BATCH_INPUTS[$i]}" > "$_BATCH_DIR/in.$i"
    done

    # Generate runner script: reads input file, runs hook, writes output file
    local runner="$_BATCH_DIR/run.sh"
    cat > "$runner" << 'RUNNER_EOF'
#!/usr/bin/env bash
idx="$1"; hook="$2"; dir="$3"
output=$("$hook" < "$dir/in.$idx" 2>/dev/null) || true
printf '%s' "$output" > "$dir/out.$idx"
RUNNER_EOF
    chmod +x "$runner"

    seq 0 $((_BATCH_COUNT - 1)) | xargs -P "$jobs" -I{} bash "$runner" {} "$hook_path" "$_BATCH_DIR"

    # Evaluate results in order
    for ((i = 0; i < _BATCH_COUNT; i++)); do
        local type="${_BATCH_TYPES[$i]}"
        local desc="${_BATCH_DESCS[$i]}"
        local extra="${_BATCH_EXTRAS[$i]}"
        local output
        output=$(cat "$_BATCH_DIR/out.$i" 2>/dev/null) || true

        TESTS_RUN=$((TESTS_RUN + 1))
        local passed=false

        case "$type" in
            block)
                if echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
                    passed=true
                fi
                ;;
            allow)
                if [ -z "$output" ] || echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"allow"'; then
                    passed=true
                fi
                ;;
            approve)
                if echo "$output" | grep -q '"behavior"[[:space:]]*:[[:space:]]*"allow"'; then
                    passed=true
                fi
                ;;
            ask)
                if echo "$output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'; then
                    passed=true
                fi
                ;;
            silent)
                if [ -z "$output" ]; then
                    passed=true
                fi
                ;;
            contains)
                if [[ "$output" == *"$extra"* ]]; then
                    passed=true
                fi
                ;;
        esac

        if [ "$passed" = true ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            report_pass "$desc"
            log_verbose "    Output: ${output:-<empty>}"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            report_fail "$desc"
            case "$type" in
                block)    report_detail "Expected: block decision" ;;
                allow)    report_detail "Expected: empty or allow decision" ;;
                approve)  report_detail "Expected: decision.behavior allow" ;;
                ask)      report_detail "Expected: permissionDecision ask" ;;
                silent)   report_detail "Expected: <empty>" ;;
                contains) report_detail "Expected to contain: $extra" ;;
            esac
            report_detail "Got: ${output:-<empty>}"
        fi
    done

    rm -rf "$_BATCH_DIR"
    _BATCH_COUNT=0
}

# Print summary and exit with appropriate code
print_summary() {
    echo ""
    echo "=== Summary ==="
    echo -e "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
    exit 0
}
