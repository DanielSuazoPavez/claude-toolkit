#!/usr/bin/env bash
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

# Forward mode flags to children
CHILD_FLAGS=()
[ "$QUIET" = "1" ] && CHILD_FLAGS+=(-q)
[ "$VERBOSE" = "1" ] && CHILD_FLAGS+=(-v)

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
# CHILD_FLAGS is serialized via CHILD_FLAGS_STR (space-joined) because exported
# bash arrays don't survive the xargs → subshell boundary.
run_one() {
    local file="$1"
    local base
    base="$(basename "$file" .sh)"
    local start end
    start=$(date +%s.%N 2>/dev/null || date +%s)
    # shellcheck disable=SC2086  # intentional word-split on flags
    bash "$file" $CHILD_FLAGS_STR > "$LOG_DIR/$base.log" 2>&1
    local ec=$?
    end=$(date +%s.%N 2>/dev/null || date +%s)
    echo "$ec" > "$LOG_DIR/$base.exit"
    awk -v s="$start" -v e="$end" 'BEGIN{printf "%.1f\n", e - s}' > "$LOG_DIR/$base.dur"
}
export -f run_one
CHILD_FLAGS_STR="${CHILD_FLAGS[*]}"
export LOG_DIR CHILD_FLAGS_STR

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
        if [ -f "$LOG_DIR/$base.log" ]; then
            cat "$LOG_DIR/$base.log"
        else
            echo "(no log captured — process likely killed mid-run)"
        fi
    done
fi

echo ""
echo "$passed/$total files passed"

if [ "${#failed_files[@]}" -gt 0 ]; then
    exit 1
fi
exit 0
