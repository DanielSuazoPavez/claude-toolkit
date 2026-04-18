#!/bin/bash
# Performance harness for session-start hook
#
# Runs the actual hook with HOOK_PERF=1 to get per-phase timing.
# No reimplemented logic — single source of truth.
#
# Usage:
#   bash tests/perf-session-start.sh              # Run with defaults
#   bash tests/perf-session-start.sh -n 10        # 10 iterations
#   bash tests/perf-session-start.sh -v           # Show per-iteration detail

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
DOCS_DIR="${CLAUDE_DOCS_DIR:-.claude/docs}"
LESSONS_DB="$HOME/.claude/lessons.db"
ITERATIONS=5

# --- Args ---
VERBOSE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -n) ITERATIONS="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

# --- Colors ---
BOLD='\033[1m'
DIM='\033[2m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# ============================================================
# Run hook with HOOK_PERF=1, parse phase timings from stderr
# ============================================================
# Returns phase timings AND a WALL_CLOCK line measured from outside the hook.
run_hook_with_perf() {
    local perf_output wall_start wall_end
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local _no_dot="${EPOCHREALTIME/./}"
        wall_start="${_no_dot:0:13}"
    else
        wall_start=$(date +%s%3N)
    fi
    # Capture all output (stderr has perf lines), filter by HOOK_PERF prefix
    perf_output=$(HOOK_PERF=1 bash "$HOOKS_DIR/session-start.sh" < /dev/null 2>&1 >/dev/null)
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local _no_dot="${EPOCHREALTIME/./}"
        wall_end="${_no_dot:0:13}"
    else
        wall_end=$(date +%s%3N)
    fi
    echo "$perf_output" | while IFS=$'\t' read -r prefix phase ms; do
        [ "$prefix" = "HOOK_PERF" ] && printf '%s\t%s\n' "$phase" "$ms"
    done
    printf 'WALL_CLOCK\t%d\n' "$(( wall_end - wall_start ))"
}

# ============================================================
# Run benchmarks
# ============================================================
printf "${BOLD}Session-start performance harness${NC}\n"
printf "Iterations: %d | DB: %s\n" "$ITERATIONS" "$LESSONS_DB"
printf "Docs: %s\n\n" "$DOCS_DIR"

# Check prerequisites
if [ ! -d "$DOCS_DIR" ]; then
    echo "ERROR: docs dir not found at $DOCS_DIR"
    exit 1
fi

essential_count=$(ls -1 "$DOCS_DIR"/essential-*.md 2>/dev/null | wc -l)
printf "Essential docs: %s\n" "$essential_count"

if [ -f "$LESSONS_DB" ]; then
    active_lessons=$(sqlite3 "$LESSONS_DB" "SELECT count(*) FROM lessons WHERE active=1;" 2>/dev/null)
    printf "Active lessons: %s\n" "$active_lessons"
else
    printf "lessons.db: not found (lesson phases will be skipped)\n"
fi
echo ""

# Collect phase timings across iterations
declare -A phase_totals=()
declare -A phase_counts=()

for ((i=1; i<=ITERATIONS; i++)); do
    while IFS=$'\t' read -r phase ms; do
        phase_totals[$phase]=$(( ${phase_totals[$phase]:-0} + ms ))
        phase_counts[$phase]=$(( ${phase_counts[$phase]:-0} + 1 ))
    done < <(run_hook_with_perf)

    if [ "$VERBOSE" = 1 ]; then
        printf "${DIM}  iter %d: total=%dms${NC}\n" \
            "$i" "${phase_totals[TOTAL]:-0}"
    fi
done

# Print phase averages
phases=("hook_init" "session_id" "essential_docs" "docs_guidance" "git_context" "toolkit_version" "lessons" "nudge" "acknowledgment")
for phase in "${phases[@]}"; do
    count=${phase_counts[$phase]:-0}
    [ "$count" -eq 0 ] && continue
    avg=$(( ${phase_totals[$phase]} / count ))
    bar=""
    for ((b=0; b<avg && b<50; b++)); do bar+="█"; done
    printf "  %-22s %4dms %s\n" "$phase" "$avg" "$bar"
done

# Totals
echo ""
if [ "${phase_counts[TOTAL]:-0}" -gt 0 ]; then
    total_avg=$(( ${phase_totals[TOTAL]} / ${phase_counts[TOTAL]} ))
    printf "  ${YELLOW}%-22s %4dms${NC}  ${DIM}(inside hook)${NC}\n" "TOTAL" "$total_avg"
fi
if [ "${phase_counts[WALL_CLOCK]:-0}" -gt 0 ]; then
    wall_avg=$(( ${phase_totals[WALL_CLOCK]} / ${phase_counts[WALL_CLOCK]} ))
    printf "  ${GREEN}%-22s %4dms${NC}  ${DIM}(process start → exit)${NC}\n" "WALL_CLOCK" "$wall_avg"
fi
echo ""
