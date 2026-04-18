#!/bin/bash
# Unified top-level test runner.
#
# Dispatches all top-level bash suites in parallel, plus pytest as one unit.
# Emits a single summary with failing-file logs dumped after.
#
# Usage:
#   bash tests/run-all.sh              # all suites, parallel
#   bash tests/run-all.sh -q           # quiet
#   bash tests/run-all.sh -v           # verbose
#   bash tests/run-all.sh <substring>  # filter by basename substring
#
# Env:
#   TEST_JOBS — override parallelism (default: nproc)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$SCRIPT_DIR/.logs/all"

QUIET=0
VERBOSE=0
FILTER=""
for arg in "$@"; do
    case "$arg" in
        -q|--quiet) QUIET=1 ;;
        -v|--verbose) VERBOSE=1 ;;
        *) FILTER="$arg" ;;
    esac
done

CHILD_FLAGS=()
[ "$QUIET" = "1" ] && CHILD_FLAGS+=(-q)
[ "$VERBOSE" = "1" ] && CHILD_FLAGS+=(-v)

JOBS="${TEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"

mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/*.log "$LOG_DIR"/*.exit "$LOG_DIR"/*.dur 2>/dev/null || true

# Collect top-level test-*.sh files (exclude hooks/ and perf-*.sh)
entries=()  # format: "<label>|<command>"
for f in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .sh)"
    if [ -n "$FILTER" ]; then
        case "$base" in
            *"$FILTER"*) ;;
            *) continue ;;
        esac
    fi
    entries+=("$base|bash $f")
done

# run-hook-tests.sh as one aggregate unit
if [ -z "$FILTER" ] || [[ "run-hook-tests" == *"$FILTER"* ]]; then
    entries+=("run-hook-tests|bash $SCRIPT_DIR/run-hook-tests.sh")
fi

# pytest as one unit
if [ -z "$FILTER" ] || [[ "pytest" == *"$FILTER"* ]]; then
    entries+=("pytest|uv run pytest -q")
fi

if [ "${#entries[@]}" -eq 0 ]; then
    echo "No test suites matched${FILTER:+ filter '$FILTER'}" >&2
    exit 1
fi

run_one() {
    local entry="$1"
    local label="${entry%%|*}"
    local cmd="${entry#*|}"
    local start end
    start=$(date +%s.%N 2>/dev/null || date +%s)
    # shellcheck disable=SC2086  # intentional word-split on flags + cmd
    (cd "$REPO_ROOT" && eval "$cmd $CHILD_FLAGS_STR") > "$LOG_DIR/$label.log" 2>&1
    local ec=$?
    end=$(date +%s.%N 2>/dev/null || date +%s)
    echo "$ec" > "$LOG_DIR/$label.exit"
    awk -v s="$start" -v e="$end" 'BEGIN{printf "%.1f\n", e - s}' > "$LOG_DIR/$label.dur"
}
export -f run_one
CHILD_FLAGS_STR="${CHILD_FLAGS[*]}"
export LOG_DIR CHILD_FLAGS_STR REPO_ROOT

printf '%s\n' "${entries[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

total=${#entries[@]}
passed=0
failed_labels=()

for entry in "${entries[@]}"; do
    label="${entry%%|*}"
    ec="$(cat "$LOG_DIR/$label.exit" 2>/dev/null || echo 1)"
    dur="$(cat "$LOG_DIR/$label.dur" 2>/dev/null || echo '?')"
    if [ "$ec" = "0" ]; then
        passed=$((passed + 1))
        echo -e "  ${GREEN}✓${NC} $label (${dur}s)"
    else
        failed_labels+=("$label")
        echo -e "  ${RED}✗${NC} $label (${dur}s)"
    fi
done

if [ "${#failed_labels[@]}" -gt 0 ]; then
    echo ""
    echo "=== Failing suite output ==="
    for label in "${failed_labels[@]}"; do
        echo ""
        echo "--- $label ---"
        cat "$LOG_DIR/$label.log"
    done
fi

echo ""
echo "$passed/$total files passed"

if [ "${#failed_labels[@]}" -gt 0 ]; then
    exit 1
fi
exit 0
