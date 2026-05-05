#!/usr/bin/env bash
# Orchestrates the four `make check` phases (test, lint-bash, validate, hooks-smoke),
# capturing each into a per-phase log and printing a compact summary block.
#
# Usage:
#   bash .claude/scripts/check-runner.sh         # summarized (default)
#   bash .claude/scripts/check-runner.sh -v      # verbose, full output streamed live
#
# Exit codes:
#   0 — all phases passed
#   1 — one or more phases failed
#
# Environment overrides (used by tests; default to the real make-check phase commands):
#   CHECK_PHASE_TEST_CMD          (default: bash tests/run-all.sh -q)
#   CHECK_PHASE_LINT_CMD          (default: <lint-bash equivalent>)
#   CHECK_PHASE_VALIDATE_CMD      (default: bash .claude/scripts/validate-all.sh)
#   CHECK_PHASE_HOOKS_SMOKE_CMD   (default: bash tests/hooks/run-smoke-all.sh -q)
#   CHECK_PHASE_LOG_DIR           (default: output/claude-toolkit/test-runs)
#   CHECK_PHASE_TEST_DUR_DIR      (default: tests/.logs/all)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
    esac
done

LINT_DEFAULT_CMD='shellcheck -S warning .claude/hooks/*.sh .claude/hooks/lib/*.sh .claude/scripts/*.sh cli/backlog/*.sh cli/eval/*.sh cli/indexes/*.sh'

TEST_CMD="${CHECK_PHASE_TEST_CMD:-bash tests/run-all.sh -q}"
LINT_CMD="${CHECK_PHASE_LINT_CMD:-$LINT_DEFAULT_CMD}"
VALIDATE_CMD="${CHECK_PHASE_VALIDATE_CMD:-bash .claude/scripts/validate-all.sh}"
HOOKS_SMOKE_CMD="${CHECK_PHASE_HOOKS_SMOKE_CMD:-bash tests/hooks/run-smoke-all.sh -q}"

LOG_DIR="${CHECK_PHASE_LOG_DIR:-output/claude-toolkit/test-runs}"
TEST_DUR_DIR="${CHECK_PHASE_TEST_DUR_DIR:-tests/.logs/all}"

TMP_DIR="$LOG_DIR/.tmp"
mkdir -p "$LOG_DIR" "$TMP_DIR"
rm -f "$TMP_DIR"/*.log "$TMP_DIR"/*.exit "$TMP_DIR"/*.dur 2>/dev/null || true

LOG="$LOG_DIR/$(date +%Y%m%d_%H%M%S).log"
: > "$LOG"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# run_phase <label> <command>
# Captures output to $TMP_DIR/<label>.log, exit code to .exit, duration to .dur.
# In verbose mode, tees live to console.
run_phase() {
    local label="$1"
    local cmd="$2"
    local phase_log="$TMP_DIR/$label.log"
    local start end ec dur

    start=$(date +%s.%N 2>/dev/null || date +%s)
    if [ "$VERBOSE" = "1" ]; then
        echo ""
        echo "=== $label ==="
        # shellcheck disable=SC2086 # intentional word splitting on $cmd
        bash -c "$cmd" 2>&1 | tee "$phase_log"
        ec=${PIPESTATUS[0]}
    else
        # shellcheck disable=SC2086
        bash -c "$cmd" > "$phase_log" 2>&1
        ec=$?
    fi
    end=$(date +%s.%N 2>/dev/null || date +%s)
    dur=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.1f", e - s}')

    echo "$ec" > "$TMP_DIR/$label.exit"
    echo "$dur" > "$TMP_DIR/$label.dur"

    {
        echo ""
        echo "=== $label (exit=$ec, ${dur}s) ==="
        strip_ansi < "$phase_log"
    } >> "$LOG"
}

# Phases run sequentially (independent but cheap to be deterministic for failure dumps)
run_phase test "$TEST_CMD"
run_phase lint-bash "$LINT_CMD"
run_phase validate "$VALIDATE_CMD"
run_phase hooks-smoke "$HOOKS_SMOKE_CMD"

# --- Aggregate ---
phase_ec() { cat "$TMP_DIR/$1.exit" 2>/dev/null || echo 1; }
phase_dur() { cat "$TMP_DIR/$1.dur" 2>/dev/null || echo "?"; }

EC_TEST=$(phase_ec test)
EC_LINT=$(phase_ec lint-bash)
EC_VALIDATE=$(phase_ec validate)
EC_SMOKE=$(phase_ec hooks-smoke)

mark() {
    if [ "$1" = "0" ]; then
        printf "${GREEN}✓${NC}"
    else
        printf "${RED}✗${NC}"
    fi
}

# --- Phase summaries ---

# tests: parse "<passed>/<total> files passed" from log; pick slowest .dur file
test_summary() {
    local log="$TMP_DIR/test.log" line counts slowest_label slowest_dur
    line=$(grep -E '^[0-9]+/[0-9]+ files passed' "$log" 2>/dev/null | tail -1)
    counts=${line%% files passed*}
    [ -z "$counts" ] && counts="?/?"

    local slowest_part=""
    if [ -d "$TEST_DUR_DIR" ]; then
        local pair
        pair=$(for f in "$TEST_DUR_DIR"/*.dur; do
            [ -f "$f" ] || continue
            local lbl d
            lbl=$(basename "$f" .dur)
            d=$(cat "$f" 2>/dev/null || echo 0)
            printf '%s %s\n' "$d" "$lbl"
        done 2>/dev/null | sort -gr | head -1)
        if [ -n "$pair" ]; then
            slowest_dur=${pair%% *}
            slowest_label=${pair##* }
            slowest_part=", slowest: $slowest_label ${slowest_dur}s"
        fi
    fi

    if [ "$EC_TEST" = "0" ]; then
        printf '%s tests       %s files (%ss%s)\n' "$(mark "$EC_TEST")" "$counts" "$(phase_dur test)" "$slowest_part"
    else
        printf '%s tests       %s files passed (%ss)\n' "$(mark "$EC_TEST")" "$counts" "$(phase_dur test)"
    fi
}

lint_summary() {
    if [ "$EC_LINT" = "0" ]; then
        printf '%s lint-bash   passed (%ss)\n' "$(mark "$EC_LINT")" "$(phase_dur lint-bash)"
    else
        printf '%s lint-bash   failed (%ss)\n' "$(mark "$EC_LINT")" "$(phase_dur lint-bash)"
    fi
}

validate_summary() {
    local log="$TMP_DIR/validate.log" total
    total=$(grep -c '^Running: ' "$log" 2>/dev/null || echo 0)
    total=${total//[^0-9]/}
    [ -z "$total" ] && total=0

    local passed
    if [ "$EC_VALIDATE" = "0" ]; then
        passed="$total"
    else
        local failed_line failed
        failed_line=$(grep -Eo '^[[:space:]]*[0-9]+ validation\(s\) failed\.' "$log" 2>/dev/null | tail -1)
        failed=${failed_line%% validation*}
        failed=${failed//[^0-9]/}
        [ -z "$failed" ] && failed=1
        passed=$((total - failed))
    fi

    local warn_count warn_part="" warn_line
    warn_count=$(grep -cE '^.{0,8}WARN' "$log" 2>/dev/null || echo 0)
    warn_count=${warn_count//[^0-9]/}
    [ -z "$warn_count" ] && warn_count=0
    if [ "$warn_count" -gt 0 ]; then
        warn_line=$(grep -nE '^.{0,8}WARN' "$log" 2>/dev/null | head -1 | cut -d: -f1)
        warn_part=" (${warn_count} warning"
        [ "$warn_count" -gt 1 ] && warn_part="${warn_part}s"
        warn_part="${warn_part} — see log line ${warn_line:-?})"
    fi

    if [ "$EC_VALIDATE" = "0" ]; then
        printf '%s validate    %s/%s validators (%ss)%s\n' "$(mark "$EC_VALIDATE")" "$passed" "$total" "$(phase_dur validate)" "$warn_part"
    else
        printf '%s validate    %s/%s validators passed (%ss)%s\n' "$(mark "$EC_VALIDATE")" "$passed" "$total" "$(phase_dur validate)" "$warn_part"
    fi
}

smoke_summary() {
    local log="$TMP_DIR/hooks-smoke.log" line counts
    line=$(grep -E '^Smoke: [0-9]+/[0-9]+ passed' "$log" 2>/dev/null | tail -1)
    counts=${line#Smoke: }
    counts=${counts%% passed*}
    [ -z "$counts" ] && counts="?/?"

    if [ "$EC_SMOKE" = "0" ]; then
        printf '%s hooks-smoke %s fixtures (%ss)\n' "$(mark "$EC_SMOKE")" "$counts" "$(phase_dur hooks-smoke)"
    else
        printf '%s hooks-smoke %s fixtures passed (%ss)\n' "$(mark "$EC_SMOKE")" "$counts" "$(phase_dur hooks-smoke)"
    fi
}

ANY_FAIL=0
for ec in "$EC_TEST" "$EC_LINT" "$EC_VALIDATE" "$EC_SMOKE"; do
    [ "$ec" = "0" ] || ANY_FAIL=1
done

# In verbose mode, the live output already printed; just tack on a footer.
if [ "$VERBOSE" = "1" ]; then
    total_dur=$(awk -v a="$(phase_dur test)" -v b="$(phase_dur lint-bash)" -v c="$(phase_dur validate)" -v d="$(phase_dur hooks-smoke)" \
        'BEGIN{printf "%.1f", a+b+c+d}')
    echo ""
    echo "=== completed in ${total_dur}s — full log: $LOG ==="
    [ "$ANY_FAIL" = "0" ] && exit 0 || exit 1
fi

# Default summarized mode
echo ""
test_summary
lint_summary
validate_summary
smoke_summary

# Failure dumps
if [ "$ANY_FAIL" = "1" ]; then
    for label in test lint-bash validate hooks-smoke; do
        ec=$(phase_ec "$label")
        if [ "$ec" != "0" ]; then
            echo ""
            echo -e "${RED}=== $label failed ===${NC}"
            cat "$TMP_DIR/$label.log"
        fi
    done
fi

total_dur=$(awk -v a="$(phase_dur test)" -v b="$(phase_dur lint-bash)" -v c="$(phase_dur validate)" -v d="$(phase_dur hooks-smoke)" \
    'BEGIN{printf "%.1f", a+b+c+d}')
echo ""
echo "total: ${total_dur}s   full log: $LOG"

[ "$ANY_FAIL" = "0" ] && exit 0 || exit 1
