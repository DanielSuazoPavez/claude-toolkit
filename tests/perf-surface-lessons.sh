#!/usr/bin/env bash
# Performance harness for surface-lessons hook
#
# Runs the actual hook with CLAUDE_TOOLKIT_HOOK_PERF=1 to get per-phase timing.
# No reimplemented logic — single source of truth.
#
# Usage:
#   bash tests/perf-surface-lessons.sh              # Run synthetic cases
#   bash tests/perf-surface-lessons.sh --replay      # Replay real inputs from surface-lessons-context.jsonl
#   bash tests/perf-surface-lessons.sh --replay -n 3 # Replay with 3 iterations
#   bash tests/perf-surface-lessons.sh -n 10         # 10 iterations per case
#   bash tests/perf-surface-lessons.sh -v            # Show per-iteration detail

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
LESSONS_DB="$HOME/.claude/lessons.db"
HOOKS_LOG_DIR="${CLAUDE_ANALYTICS_HOOKS_DIR:-$HOME/claude-analytics/hook-logs}"
SURFACE_JSONL="$HOOKS_LOG_DIR/surface-lessons-context.jsonl"
ITERATIONS=5
REPLAY=0

# --- Args ---
VERBOSE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -n) ITERATIONS="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        --replay) REPLAY=1; shift ;;
        *) shift ;;
    esac
done

# --- Colors ---
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# --- Synthetic test inputs ---
# Each entry: "description|json_input"
SYNTHETIC_CASES=(
    'git commit (match expected)|{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: something\""}}'
    'ls -la (no match expected)|{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    'read hook file (match expected)|{"tool_name":"Read","tool_input":{"file_path":"/project/.claude/hooks/foo.sh"}}'
    'read random file (no match)|{"tool_name":"Read","tool_input":{"file_path":"/project/src/utils/helpers.py"}}'
    'long command (many keywords)|{"tool_name":"Bash","tool_input":{"command":"git merge --no-ff feature/hook-permissions-test && make check && pytest tests/"}}'
    'wrong tool (early exit)|{"tool_name":"Glob","tool_input":{"pattern":"**/*.sh"}}'
)

# --- Build replay cases from surface-lessons-context.jsonl ---
build_replay_cases() {
    local cases=()
    if [ ! -f "$SURFACE_JSONL" ]; then
        echo "WARNING: surface-lessons-context.jsonl not found at $SURFACE_JSONL — no replay cases available" >&2
        return
    fi

    # Pull distinct (tool_name, raw_context) pairs from real sessions, ordered
    # by keyword count desc, capped at 10. jq does the dedupe + ordering.
    while IFS=$'\t' read -r tool_name raw_context keyword_count match_count; do
        # Build JSON input matching what the hook expects
        local json_input desc
        desc="${raw_context:0:60}"
        [ ${#raw_context} -gt 60 ] && desc="${desc}..."
        desc="[replay] ${tool_name}: ${desc} (${keyword_count} kw, ${match_count} matches)"

        # Escape raw_context for JSON
        local escaped_context
        escaped_context=$(printf '%s' "$raw_context" | jq -Rs '.')

        case "$tool_name" in
            Bash)
                json_input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":${escaped_context}}}"
                ;;
            Read|Write|Edit)
                json_input="{\"tool_name\":\"${tool_name}\",\"tool_input\":{\"file_path\":${escaped_context}}}"
                ;;
            *)
                continue
                ;;
        esac

        cases+=("${desc}|${json_input}")
    done < <(jq -r '
        select(.kind == "context" and (.tool_name | IN("Bash","Read","Write","Edit")))
        | { tool_name, raw_context,
            keyword_count: ((.keywords | split(",") | length)),
            match_count }
        | [.tool_name, .raw_context, .keyword_count, .match_count]
        | @tsv
    ' "$SURFACE_JSONL" 2>/dev/null \
        | sort -u \
        | sort -t$'\t' -k3 -n -r \
        | head -n10)

    printf '%s\n' "${cases[@]}"
}

# ============================================================
# Run hook with CLAUDE_TOOLKIT_HOOK_PERF=1, parse phase timings from stderr
# ============================================================
# Returns phase timings AND a WALL_CLOCK line measured from outside the hook.
run_hook_with_perf() {
    local input="$1"
    local perf_output wall_start wall_end
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local _no_dot="${EPOCHREALTIME/./}"
        wall_start="${_no_dot:0:13}"
    else
        wall_start=$(date +%s%3N)
    fi
    # Capture all output (stderr has perf lines), filter by HOOK_PERF prefix
    perf_output=$(echo "$input" | CLAUDE_TOOLKIT_HOOK_PERF=1 bash "$HOOKS_DIR/surface-lessons.sh" 2>&1 >/dev/null)
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
printf "${BOLD}Surface-lessons performance harness${NC}\n"
printf "Iterations: %d | DB: %s\n\n" "$ITERATIONS" "$LESSONS_DB"

# Check prerequisites
if [ ! -f "$LESSONS_DB" ]; then
    echo "ERROR: lessons.db not found at $LESSONS_DB"
    exit 1
fi

active_lessons=$(sqlite3 "$LESSONS_DB" "SELECT count(*) FROM lessons WHERE active=1;" 2>/dev/null)
active_tags=$(sqlite3 "$LESSONS_DB" "SELECT count(*) FROM tags WHERE status='active';" 2>/dev/null)
printf "Active lessons: %s | Active tags: %s\n\n" "$active_lessons" "$active_tags"

# Build test cases
TEST_CASES=()
if [ "$REPLAY" = 1 ]; then
    printf "${BOLD}Mode: replay (real inputs from surface-lessons-context.jsonl)${NC}\n\n"
    while IFS= read -r line; do
        [ -n "$line" ] && TEST_CASES+=("$line")
    done < <(build_replay_cases)
    if [ ${#TEST_CASES[@]} -eq 0 ]; then
        echo "No replay cases found — falling back to synthetic"
        TEST_CASES=("${SYNTHETIC_CASES[@]}")
    fi
else
    printf "${BOLD}Mode: synthetic${NC}\n\n"
    TEST_CASES=("${SYNTHETIC_CASES[@]}")
fi

for test_entry in "${TEST_CASES[@]}"; do
    description="${test_entry%%|*}"
    input="${test_entry#*|}"

    printf "${CYAN}=== %s ===${NC}\n" "$description"

    # Collect phase timings across iterations
    declare -A phase_totals=()
    declare -A phase_counts=()

    for ((i=1; i<=ITERATIONS; i++)); do
        while IFS=$'\t' read -r phase ms; do
            phase_totals[$phase]=$(( ${phase_totals[$phase]:-0} + ms ))
            phase_counts[$phase]=$(( ${phase_counts[$phase]:-0} + 1 ))
        done < <(run_hook_with_perf "$input")

        if [ "$VERBOSE" = 1 ]; then
            printf "${DIM}  iter %d: total=%dms${NC}\n" \
                "$i" "${phase_totals[TOTAL]:-0}"
        fi
    done

    # Print phase averages
    phases=("hook_init" "jq_parse" "tool_match" "tokenize" "build_sql" "sqlite_query" "format_output")
    for phase in "${phases[@]}"; do
        count=${phase_counts[$phase]:-0}
        [ "$count" -eq 0 ] && continue
        avg=$(( ${phase_totals[$phase]} / count ))
        bar=""
        for ((b=0; b<avg && b<50; b++)); do bar+="█"; done
        printf "  %-18s %4dms %s\n" "$phase" "$avg" "$bar"
    done

    # Totals
    if [ "${phase_counts[TOTAL]:-0}" -gt 0 ]; then
        total_avg=$(( ${phase_totals[TOTAL]} / ${phase_counts[TOTAL]} ))
        printf "  ${YELLOW}%-18s %4dms${NC}  ${DIM}(inside hook)${NC}\n" "TOTAL" "$total_avg"
    fi
    if [ "${phase_counts[WALL_CLOCK]:-0}" -gt 0 ]; then
        wall_avg=$(( ${phase_totals[WALL_CLOCK]} / ${phase_counts[WALL_CLOCK]} ))
        printf "  ${GREEN}%-18s %4dms${NC}  ${DIM}(process start → exit)${NC}\n" "WALL_CLOCK" "$wall_avg"
    fi
    echo ""

    # Clean up associative arrays for next test case
    unset phase_totals phase_counts
done
