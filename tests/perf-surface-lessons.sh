#!/bin/bash
# Performance harness for surface-lessons hook
#
# Measures each phase of execution to identify bottlenecks.
# Runs the hook multiple times with different inputs and reports
# per-phase timing breakdown.
#
# Usage:
#   bash tests/perf-surface-lessons.sh              # Run synthetic cases
#   bash tests/perf-surface-lessons.sh --replay      # Replay real inputs from hooks.db
#   bash tests/perf-surface-lessons.sh --replay -n 3 # Replay with 3 iterations
#   bash tests/perf-surface-lessons.sh -n 10         # 10 iterations per case
#   bash tests/perf-surface-lessons.sh -v            # Show per-iteration detail

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
LESSONS_DB="$HOME/.claude/lessons.db"
HOOKS_DB="$HOME/.claude/hooks.db"
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

# --- Build replay cases from hooks.db ---
build_replay_cases() {
    local cases=()
    if [ ! -f "$HOOKS_DB" ]; then
        echo "WARNING: hooks.db not found at $HOOKS_DB — no replay cases available" >&2
        return
    fi

    # Pull distinct (tool_name, raw_context) pairs from real sessions (non-test)
    # Truncate long contexts for description, keep full context for JSON build
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
    done < <(sqlite3 -separator $'\t' "$HOOKS_DB" "
        SELECT tool_name, raw_context,
               length(keywords) - length(replace(keywords, ',', '')) + 1 AS keyword_count,
               match_count
        FROM surface_lessons_context
        WHERE session_id NOT IN (
            SELECT DISTINCT session_id FROM hook_logs WHERE is_test = 1
        )
        GROUP BY tool_name, raw_context
        ORDER BY keyword_count DESC
        LIMIT 10;
    " 2>/dev/null)

    # If no non-test data, fall back to all data
    if [ ${#cases[@]} -eq 0 ]; then
        while IFS=$'\t' read -r tool_name raw_context keyword_count match_count; do
            local json_input desc escaped_context
            desc="${raw_context:0:60}"
            [ ${#raw_context} -gt 60 ] && desc="${desc}..."
            desc="[replay] ${tool_name}: ${desc} (${keyword_count} kw, ${match_count} matches)"
            escaped_context=$(printf '%s' "$raw_context" | jq -Rs '.')

            case "$tool_name" in
                Bash)
                    json_input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":${escaped_context}}}"
                    ;;
                Read|Write|Edit)
                    json_input="{\"tool_name\":\"${tool_name}\",\"tool_input\":{\"file_path\":${escaped_context}}}"
                    ;;
                *) continue ;;
            esac
            cases+=("${desc}|${json_input}")
        done < <(sqlite3 -separator $'\t' "$HOOKS_DB" "
            SELECT tool_name, raw_context,
                   length(keywords) - length(replace(keywords, ',', '')) + 1 AS keyword_count,
                   match_count
            FROM surface_lessons_context
            GROUP BY tool_name, raw_context
            ORDER BY keyword_count DESC
            LIMIT 10;
        " 2>/dev/null)
    fi

    printf '%s\n' "${cases[@]}"
}

# ============================================================
# Phase-instrumented version of the hook
# ============================================================
# Runs the hook logic step-by-step, measuring each phase.
# Outputs TSV: phase\tduration_ms
run_instrumented() {
    local input="$1"
    local t0 t1 t2 t3 t4 t5 t6 t7

    # --- Phase 0: baseline (date call cost) ---
    t0=$(date +%s%N)
    t1=$(date +%s%N)

    # --- Phase 1: stdin + jq parse ---
    TOOL_NAME=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null) || true
    t2=$(date +%s%N)

    # --- Phase 2: tool match check ---
    local matched=false
    case "$TOOL_NAME" in
        Bash|Read|Write|Edit) matched=true ;;
    esac
    if [ "$matched" = false ]; then
        t3=$(date +%s%N)
        printf "date_overhead\t%d\n" $(( (t1 - t0) / 1000000 ))
        printf "stdin_jq_parse\t%d\n" $(( (t2 - t1) / 1000000 ))
        printf "tool_match\t%d\n" $(( (t3 - t2) / 1000000 ))
        printf "TOTAL\t%d\n" $(( (t3 - t0) / 1000000 ))
        return
    fi
    t3=$(date +%s%N)

    # --- Phase 3: extract context ---
    local context=""
    case "$TOOL_NAME" in
        Bash) context=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) ;;
        Read|Write|Edit) context=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null) ;;
    esac
    t4=$(date +%s%N)

    # --- Phase 4: tokenize + build SQL ---
    local words conditions="" safe_word stripped
    words=$(echo "$context" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]_-' '\n' | sort -u)
    for word in $words; do
        [ ${#word} -lt 3 ] && continue
        safe_word=$(echo "$word" | sed "s/'/''/g")
        if [ -n "$conditions" ]; then
            conditions="$conditions OR t.keywords LIKE '%${safe_word}%'"
        else
            conditions="t.keywords LIKE '%${safe_word}%'"
        fi
        stripped="${safe_word%s}"
        if [ "$stripped" != "$safe_word" ] && [ ${#stripped} -ge 3 ]; then
            conditions="$conditions OR t.keywords LIKE '%${stripped}%'"
        fi
    done
    t5=$(date +%s%N)

    # --- Phase 5: sqlite3 query ---
    local results=""
    if [ -n "$conditions" ]; then
        results=$(sqlite3 -separator '|' "$LESSONS_DB" "
            SELECT DISTINCT l.id, l.text
            FROM lessons l
            JOIN lesson_tags lt ON l.id = lt.lesson_id
            JOIN tags t ON lt.tag_id = t.id
            WHERE l.active = 1
              AND t.status = 'active'
              AND ($conditions)
            LIMIT 3;
        " 2>/dev/null) || true
    fi
    t6=$(date +%s%N)

    # --- Phase 6: format output + logging overhead ---
    local match_count=0 keyword_list escaped
    if [ -n "$results" ]; then
        match_count=$(echo "$results" | grep -c . 2>/dev/null || echo "0")
        local lessons
        lessons=$(echo "$results" | cut -d'|' -f2-)
        escaped=$(echo "$lessons" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n- /g')
    fi
    keyword_list=$(echo "$words" | tr '\n' ',' | sed 's/,$//')
    t7=$(date +%s%N)

    # --- Output phase timings ---
    printf "date_overhead\t%d\n" $(( (t1 - t0) / 1000000 ))
    printf "stdin_jq_parse\t%d\n" $(( (t2 - t1) / 1000000 ))
    printf "tool_match\t%d\n" $(( (t3 - t2) / 1000000 ))
    printf "context_extract\t%d\n" $(( (t4 - t3) / 1000000 ))
    printf "tokenize_sql\t%d\n" $(( (t5 - t4) / 1000000 ))
    printf "sqlite3_query\t%d\n" $(( (t6 - t5) / 1000000 ))
    printf "format_output\t%d\n" $(( (t7 - t6) / 1000000 ))
    printf "TOTAL\t%d\n" $(( (t7 - t0) / 1000000 ))
}

# ============================================================
# Also time the actual hook end-to-end for comparison
# ============================================================
run_actual_hook() {
    local input="$1"
    local t0 t1
    t0=$(date +%s%N)
    echo "$input" | CLAUDE_HOOK_TEST=1 bash "$HOOKS_DIR/surface-lessons.sh" >/dev/null 2>&1
    t1=$(date +%s%N)
    echo $(( (t1 - t0) / 1000000 ))
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
    printf "${BOLD}Mode: replay (real inputs from hooks.db)${NC}\n\n"
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
    actual_total=0

    for ((i=1; i<=ITERATIONS; i++)); do
        # Instrumented run
        while IFS=$'\t' read -r phase ms; do
            phase_totals[$phase]=$(( ${phase_totals[$phase]:-0} + ms ))
            phase_counts[$phase]=$(( ${phase_counts[$phase]:-0} + 1 ))
        done < <(run_instrumented "$input")

        # Actual hook run
        actual_ms=$(run_actual_hook "$input")
        actual_total=$((actual_total + actual_ms))

        if [ "$VERBOSE" = 1 ]; then
            printf "${DIM}  iter %d: instrumented=%dms actual=%dms${NC}\n" \
                "$i" "${phase_totals[TOTAL]:-0}" "$actual_ms"
        fi
    done

    # Print phase averages
    # Ordered list of phases (to control output order)
    phases=("date_overhead" "stdin_jq_parse" "tool_match" "context_extract" "tokenize_sql" "sqlite3_query" "format_output")
    for phase in "${phases[@]}"; do
        count=${phase_counts[$phase]:-0}
        [ "$count" -eq 0 ] && continue
        avg=$(( ${phase_totals[$phase]} / count ))
        bar=""
        for ((b=0; b<avg && b<50; b++)); do bar+="█"; done
        printf "  %-18s %4dms %s\n" "$phase" "$avg" "$bar"
    done

    # Totals
    instrumented_avg=0
    if [ "${phase_counts[TOTAL]:-0}" -gt 0 ]; then
        instrumented_avg=$(( ${phase_totals[TOTAL]} / ${phase_counts[TOTAL]} ))
    fi
    actual_avg=$((actual_total / ITERATIONS))
    overhead=$((actual_avg - instrumented_avg))

    printf "  ${YELLOW}%-18s %4dms${NC}\n" "INSTRUMENTED" "$instrumented_avg"
    printf "  ${GREEN}%-18s %4dms${NC}\n" "ACTUAL_HOOK" "$actual_avg"
    if [ "$overhead" -gt 0 ]; then
        printf "  ${DIM}%-18s %4dms (hook_init + logging + EXIT trap)${NC}\n" "OVERHEAD" "$overhead"
    fi
    echo ""

    # Clean up associative arrays for next test case
    unset phase_totals phase_counts
done
