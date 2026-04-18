#!/bin/bash
# Parallel hook test runner.
#
# Usage:
#   bash tests/run-hook-tests.sh              # all tests, parallel
#   bash tests/run-hook-tests.sh -q           # quiet (summary + failures only)
#   bash tests/run-hook-tests.sh -v           # verbose
#   bash tests/run-hook-tests.sh <substring>  # run files whose names contain <substring>
#
# Env:
#   HOOK_TEST_JOBS — override parallelism (default: nproc)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR_TESTS="$SCRIPT_DIR/hooks"
LOG_DIR="$SCRIPT_DIR/.logs"

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

# Forward mode flag to children
CHILD_FLAG=""
[ "$QUIET" = "1" ] && CHILD_FLAG="-q"
[ "$VERBOSE" = "1" ] && CHILD_FLAG="-v"

JOBS="${HOOK_TEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"

mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/*.log "$LOG_DIR"/*.exit 2>/dev/null || true

# Collect files
files=()
for f in "$HOOKS_DIR_TESTS"/test-*.sh; do
    [ -f "$f" ] || continue
    if [ -n "$FILTER" ]; then
        case "$(basename "$f")" in
            *"$FILTER"*) files+=("$f") ;;
        esac
    else
        files+=("$f")
    fi
done

if [ "${#files[@]}" -eq 0 ]; then
    echo "No test files matched${FILTER:+ filter '$FILTER'}" >&2
    exit 1
fi

# Wrapper: runs one file, captures output + exit code.
run_one() {
    local file="$1"
    local base
    base="$(basename "$file" .sh)"
    local start end
    start=$(date +%s.%N 2>/dev/null || date +%s)
    bash "$file" $CHILD_FLAG > "$LOG_DIR/$base.log" 2>&1
    local ec=$?
    end=$(date +%s.%N 2>/dev/null || date +%s)
    echo "$ec" > "$LOG_DIR/$base.exit"
    # Duration (seconds, one decimal)
    awk -v s="$start" -v e="$end" 'BEGIN{printf "%.1f\n", e - s}' > "$LOG_DIR/$base.dur"
}
export -f run_one
export LOG_DIR CHILD_FLAG

printf '%s\n' "${files[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

# Aggregate
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

total=${#files[@]}
passed=0
failed_files=()

for f in "${files[@]}"; do
    base="$(basename "$f" .sh)"
    ec="$(cat "$LOG_DIR/$base.exit" 2>/dev/null || echo 1)"
    dur="$(cat "$LOG_DIR/$base.dur" 2>/dev/null || echo '?')"
    if [ "$ec" = "0" ]; then
        passed=$((passed + 1))
        echo -e "  ${GREEN}✓${NC} $base.sh (${dur}s)"
    else
        failed_files+=("$base")
        echo -e "  ${RED}✗${NC} $base.sh (${dur}s)"
    fi
done

if [ "${#failed_files[@]}" -gt 0 ]; then
    echo ""
    echo "=== Failing file output ==="
    for base in "${failed_files[@]}"; do
        echo ""
        echo "--- $base.sh ---"
        cat "$LOG_DIR/$base.log"
    done
fi

echo ""
echo "$passed/$total files passed"

if [ "${#failed_files[@]}" -gt 0 ]; then
    exit 1
fi
exit 0
