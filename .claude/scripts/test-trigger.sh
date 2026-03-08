#!/bin/bash
# Test whether a skill triggers correctly on natural language prompts.
#
# Usage:
#   bash .claude/scripts/test-trigger.sh <skill-name>
#   bash .claude/scripts/test-trigger.sh <skill-name> -v    # verbose
#   bash .claude/scripts/test-trigger.sh <skill-name> --dry-run  # show queries only
#   bash .claude/scripts/test-trigger.sh <skill-name> --save-transcripts  # keep stream output
#
# Requires:
#   - claude CLI authenticated
#   - Skill installed with eval-triggers.json in its directory
#
# Exit codes:
#   0 - All queries matched expected trigger behavior
#   1 - One or more queries failed
#   2 - Missing eval set or skill not found

set -uo pipefail

SKILL_NAME="${1:-}"
VERBOSE=0
DRY_RUN=0
SAVE_TRANSCRIPTS=0
TIMEOUT=60

# Parse remaining args
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose) VERBOSE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --save-transcripts) SAVE_TRANSCRIPTS=1; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$SKILL_NAME" ]]; then
    echo "Usage: test-trigger.sh <skill-name> [-v] [--dry-run] [--timeout N]" >&2
    exit 2
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/.claude/skills/$SKILL_NAME"
EVAL_FILE="$SKILL_DIR/eval-triggers.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_verbose() {
    [[ "$VERBOSE" = "1" ]] && echo -e "  $*" >&2
}

# Validate inputs
if [[ ! -d "$SKILL_DIR" ]]; then
    echo -e "${RED}ERROR${NC}: Skill '$SKILL_NAME' not found at $SKILL_DIR" >&2
    exit 2
fi

if [[ ! -f "$EVAL_FILE" ]]; then
    echo -e "${RED}ERROR${NC}: No eval-triggers.json found for '$SKILL_NAME'" >&2
    exit 2
fi

# Check claude CLI is available
if ! command -v claude &>/dev/null; then
    echo -e "${RED}ERROR${NC}: 'claude' CLI not found in PATH" >&2
    exit 2
fi

# Check jq is available
if ! command -v jq &>/dev/null; then
    echo -e "${RED}ERROR${NC}: 'jq' not found in PATH" >&2
    exit 2
fi

# Read eval set
QUERY_COUNT=$(jq '.queries | length' "$EVAL_FILE")
if [[ "$QUERY_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}SKIP${NC}: $SKILL_NAME — no queries in eval set" >&2
    exit 0
fi

# Set up transcript directory if saving
TRANSCRIPT_DIR=""
if [[ "$SAVE_TRANSCRIPTS" = "1" ]]; then
    TRANSCRIPT_DIR="$PROJECT_ROOT/.claude/output/trigger-tests/$SKILL_NAME/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$TRANSCRIPT_DIR"
fi

echo -e "${CYAN}Testing${NC}: $SKILL_NAME ($QUERY_COUNT queries)"

if [[ "$DRY_RUN" = "1" ]]; then
    jq -r '.queries[] | "\(.should_trigger | if . then "SHOULD" else "SHOULD NOT" end) trigger: \(.query)"' "$EVAL_FILE"
    exit 0
fi

# Check if a stream-json output file contains a Skill tool invocation for the given skill.
# Looks for the tool_use pattern: "name":"Skill" followed by "skill":"<name>" in the input.
# This avoids false positives from the word appearing in Claude's text response.
check_trigger() {
    local file="$1"
    local skill="$2"

    [[ -s "$file" ]] || return 1

    # Look for lines containing "Skill" as a tool name (tool_use event)
    # Then check if the skill parameter matches nearby in the stream
    # The stream-json format puts tool name and input in separate events, so we need both:
    #   1. A content_block_start with "name":"Skill"
    #   2. An input_json_delta containing "skill":"<name>"
    grep -q '"name"[[:space:]]*:[[:space:]]*"Skill"' "$file" 2>/dev/null || return 1
    grep -q "\"skill\"[[:space:]]*:[[:space:]]*\"$skill\"" "$file" 2>/dev/null || return 1
    return 0
}

# Test a single query. Returns 0 if skill trigger detection matches expected behavior.
# Streams claude -p output line-by-line, killing early on trigger detection or timeout.
test_query() {
    local query="$1"
    local should_trigger="$2"
    local skill_name="$3"
    local query_index="$4"
    local triggered=false
    local tmpfile
    tmpfile=$(mktemp)

    # Run claude -p in background, stream output to tmpfile
    # Unset CLAUDECODE to allow nested claude -p invocations
    # Use --kill-after to ensure cleanup even if process ignores SIGTERM
    CLAUDECODE= timeout --kill-after=5 "$TIMEOUT" claude -p "$query" \
        --output-format stream-json \
        --verbose \
        2>/dev/null > "$tmpfile" &
    local pid=$!

    # Poll the output file for skill trigger detection.
    # We need to match the specific pattern where "Skill" is a tool_use name
    # AND our skill name appears as the "skill" parameter value.
    # Pattern in stream-json: {"skill":"learn"} inside a tool_use with name "Skill"
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if check_trigger "$tmpfile" "$skill_name"; then
            triggered=true
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            break
        fi
        sleep 1
        ((elapsed++))
    done

    # Wait for process to finish if still running
    wait "$pid" 2>/dev/null

    # Final check on complete output
    if [[ "$triggered" = "false" ]] && [[ -s "$tmpfile" ]]; then
        if check_trigger "$tmpfile" "$skill_name"; then
            triggered=true
        fi
    fi

    # Save or clean up transcript
    if [[ -n "$TRANSCRIPT_DIR" ]]; then
        local label="should_trigger"
        [[ "$should_trigger" = "false" ]] && label="should_not_trigger"
        local result_label="PASS"
        if [[ "$should_trigger" = "true" && "$triggered" = "false" ]] || \
           [[ "$should_trigger" = "false" && "$triggered" = "true" ]]; then
            result_label="FAIL"
        fi
        cp "$tmpfile" "$TRANSCRIPT_DIR/q${query_index}_${label}_${result_label}.json"
    fi
    rm -f "$tmpfile"

    if [[ "$should_trigger" = "true" && "$triggered" = "true" ]]; then
        return 0  # Correct: expected trigger, got trigger
    elif [[ "$should_trigger" = "false" && "$triggered" = "false" ]]; then
        return 0  # Correct: expected no trigger, got no trigger
    else
        return 1  # Mismatch
    fi
}

# Run all queries
PASSED=0
FAILED=0
FAILURES=()

for i in $(seq 0 $((QUERY_COUNT - 1))); do
    query=$(jq -r ".queries[$i].query" "$EVAL_FILE")
    should_trigger=$(jq -r ".queries[$i].should_trigger" "$EVAL_FILE")
    notes=$(jq -r ".queries[$i].notes // \"\"" "$EVAL_FILE")

    expected_label="trigger"
    [[ "$should_trigger" = "false" ]] && expected_label="no trigger"

    log_verbose "Query $((i+1))/$QUERY_COUNT: \"$query\" (expect: $expected_label)"

    if test_query "$query" "$should_trigger" "$SKILL_NAME" "$((i+1))"; then
        ((PASSED++))
        log_verbose "${GREEN}PASS${NC}"
    else
        ((FAILED++))
        FAILURES+=("$(printf '  %s (expected %s)%s' "$query" "$expected_label" "${notes:+ — $notes}")")
        log_verbose "${RED}FAIL${NC}"
    fi
done

# Report
TOTAL=$((PASSED + FAILED))
if [[ "$FAILED" -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${NC}: $PASSED/$TOTAL queries matched"
else
    echo -e "  ${RED}FAIL${NC}: $PASSED/$TOTAL passed, $FAILED failed"
    for failure in "${FAILURES[@]}"; do
        echo -e "    ${RED}✗${NC} $failure"
    done
fi

if [[ -n "$TRANSCRIPT_DIR" ]]; then
    echo -e "  Transcripts: $TRANSCRIPT_DIR"
fi

exit "$( [[ "$FAILED" -eq 0 ]] && echo 0 || echo 1 )"
