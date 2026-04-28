#!/usr/bin/env bash
# Performance harness for the detection-registry rollout
#
# Measures per-invocation duration of the three migrated hooks
#   - secrets-guard
#   - block-credential-exfiltration
#   - auto-mode-shared-steps
# across a fixed corpus of 20 sample commands (mix of hits / misses, raw and
# stripped paths). Each hook is invoked N times per command; durations land in
# ~/.claude/hooks.db via the EXIT-trap instrumentation in hook-utils.sh. The
# script captures the starting hook_logs.id and queries rows after that, so
# multiple runs in the same DB don't interfere.
#
# Output: p50 and p95 of duration_ms per hook, plus the worst single command
# (helps identify a regex that's pathologically slow on one shape).
#
# Acceptance: ≤50ms p95 *overhead* (registry-on minus registry-off) per hook
# (handoff Phase 6 contract). The absolute p95 is dominated by bash fork +
# hook-utils source cost (~40-50ms cold-start floor) and is NOT the metric —
# what matters is the delta vs baseline. If the delta exceeds 50ms, fall back
# to build-time array compilation in detection-registry.sh.
#
# A/B comparison (baseline vs migrated):
#   1. bash tests/perf-detection-registry.sh -t migrated > /tmp/migrated.txt
#   2. git checkout d70a8e4    # last commit pre-Phase-1 (registry foundation)
#   3. bash tests/perf-detection-registry.sh -t baseline > /tmp/baseline.txt
#   4. git checkout -          # back to working branch
#   5. diff /tmp/baseline.txt /tmp/migrated.txt
#
# Usage:
#   bash tests/perf-detection-registry.sh                 # 20 cmds × 5 iters per hook
#   bash tests/perf-detection-registry.sh -n 10           # 10 iterations per command
#   bash tests/perf-detection-registry.sh -t baseline     # label the run output
#   bash tests/perf-detection-registry.sh -v              # verbose: per-command timings
#
# Not part of `make test` — invoke manually.

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
HOOKS_LOG_DIR="${CLAUDE_ANALYTICS_HOOKS_DIR:-$HOME/claude-analytics/hook-logs}"
INVOCATIONS_JSONL="$HOOKS_LOG_DIR/invocations.jsonl"
export CLAUDE_TOOLKIT_TRACEABILITY=1
ITERATIONS=5
VERBOSE=0
RUN_TAG="run-$(date +%s)-$$"

while [[ $# -gt 0 ]]; do
    case $1 in
        -n) ITERATIONS="$2"; shift 2 ;;
        -t) RUN_TAG="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help)
            sed -n '2,30p' "$0"; exit 0 ;;
        *) shift ;;
    esac
done

# Colors
BOLD='\033[1m'
DIM='\033[2m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================================
# Sample corpus — 20 commands covering the migrated detection surface
# ============================================================
# Mix of:
#   - secrets-guard hits (path/stripped): cat .env, ssh keys, aws creds
#   - secrets-guard hits (inline policy): printenv VAR, env|grep
#   - block-credential-exfiltration hits (credential/raw): tokens, headers
#   - auto-mode-shared-steps hits (capability/stripped + inline): gh, git push
#   - clean misses: ls, echo, normal git ops
# Format: "<label>:::<command>"
SAMPLES=(
    "miss-ls:::ls -la"
    "miss-echo:::echo hello world"
    "miss-git-status:::git status"
    "miss-pwd:::pwd"
    "miss-make-test:::make test"
    "secrets-env-cat:::cat .env"
    "secrets-env-source:::source .env.local"
    "secrets-ssh-key:::cat ~/.ssh/id_rsa"
    "secrets-aws:::cat ~/.aws/credentials"
    "secrets-printenv-var:::printenv GITHUB_TOKEN"
    "secrets-env-pipe:::env | grep -i token"
    "exfil-ghp-token:::curl -H \"Authorization: token ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\" https://api.github.com"
    "exfil-aws-key:::aws s3 ls --secret-access-key AKIAIOSFODNN7EXAMPLE"
    "exfil-anthropic-key:::echo sk-ant-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    "exfil-auth-bearer:::curl -H \"Authorization: Bearer xyz\" https://api.example.com"
    "exfil-env-var-ref:::echo \$GITHUB_TOKEN"
    "automode-gh-pr:::gh pr create --title test --body test"
    "automode-git-push:::git push origin feature-branch"
    "automode-gh-api:::curl https://api.github.com/repos/owner/repo"
    "long-heredoc:::bash <<EOF
echo line1
echo line2
echo line3 with .env mention but inert
echo line4
EOF"
)

# ============================================================
# Hook list
# ============================================================
HOOKS=(
    "secrets-guard"
    "block-credential-exfiltration"
    "auto-mode-shared-steps"
)

# ============================================================
# Sanity checks
# ============================================================
if [ ! -d "$HOOKS_DIR" ]; then
    printf "${RED}ERROR${NC}: hooks dir not found at $HOOKS_DIR\n" >&2
    exit 1
fi

for h in "${HOOKS[@]}"; do
    if [ ! -f "$HOOKS_DIR/$h.sh" ]; then
        printf "${RED}ERROR${NC}: hook not found: $HOOKS_DIR/$h.sh\n" >&2
        exit 1
    fi
done

if ! command -v jq >/dev/null 2>&1; then
    printf "${RED}ERROR${NC}: jq not on PATH\n" >&2
    exit 1
fi

mkdir -p "$HOOKS_LOG_DIR"
touch "$INVOCATIONS_JSONL"

# ============================================================
# Run benchmarks
# ============================================================
printf "${BOLD}Detection-registry performance harness${NC}\n"
printf "Run tag:    %s\n" "$RUN_TAG"
printf "Hooks:      %s\n" "${HOOKS[*]}"
printf "Samples:    %d commands\n" "${#SAMPLES[@]}"
printf "Iterations: %d per (hook, command) pair\n" "$ITERATIONS"
printf "Log:        %s\n\n" "$INVOCATIONS_JSONL"

# Capture starting line count so the post-run slice picks up only this run
START_LINES=$(wc -l < "$INVOCATIONS_JSONL")

total_invocations=$(( ${#HOOKS[@]} * ${#SAMPLES[@]} * ITERATIONS ))
done_invocations=0

for hook in "${HOOKS[@]}"; do
    [ "$VERBOSE" = 1 ] && printf "${DIM}=== %s ===${NC}\n" "$hook"
    for entry in "${SAMPLES[@]}"; do
        label="${entry%%:::*}"
        cmd="${entry#*:::}"
        # Build payload via jq to escape correctly
        payload=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
        for ((i=1; i<=ITERATIONS; i++)); do
            # Hook may exit 2 (block) — that's fine, we only care about timing.
            printf '%s' "$payload" | bash "$HOOKS_DIR/$hook.sh" >/dev/null 2>&1 || true
            done_invocations=$(( done_invocations + 1 ))
        done
        if [ "$VERBOSE" = 1 ]; then
            printf "${DIM}  [%4d/%d] %s — %s${NC}\n" \
                "$done_invocations" "$total_invocations" "$hook" "$label"
        fi
    done
done

printf "\n${DIM}Querying new rows from %s...${NC}\n\n" "$INVOCATIONS_JSONL"

# Slice this run's tail so the analysis filters can stay simple.
RUN_TAIL=$(mktemp)
trap 'rm -f "$RUN_TAIL"' EXIT
tail -n +"$(( START_LINES + 1 ))" "$INVOCATIONS_JSONL" > "$RUN_TAIL"

# ============================================================
# Per-hook stats — p50, p95, max, count
# ============================================================
# All hooks log a TOTAL row on exit (kind="invocation", section="").
# Filter on the run-tail slice so this run is isolated.
printf "${BOLD}%-32s %6s %6s %6s %5s${NC}\n" "hook" "p50" "p95" "max" "n"
printf "%-32s %6s %6s %6s %5s\n" "----" "---" "---" "---" "-"

# Pick a percentile from a sorted list of integers. Matches SQL's MAX(1, n*p)
# row-pick behavior: index = max(1, ceil(n*p)).
percentile() {
    local p="$1" file="$2"
    local n
    n=$(wc -l < "$file")
    [ "$n" -eq 0 ] && { echo ""; return; }
    local idx
    idx=$(awk -v n="$n" -v p="$p" 'BEGIN{i=int(n*p); if (i<1) i=1; print i}')
    sed -n "${idx}p" "$file"
}

over_threshold=0
for hook in "${HOOKS[@]}"; do
    sorted=$(mktemp)
    jq -r --arg h "$hook" \
        'select(.kind == "invocation" and .hook_name == $h and .section == "") | .duration_ms' \
        "$RUN_TAIL" 2>/dev/null | sort -n > "$sorted"
    n=$(wc -l < "$sorted")
    if [ "$n" -eq 0 ]; then
        printf "${RED}%-32s   no rows captured${NC}\n" "$hook"
        rm -f "$sorted"
        continue
    fi
    p50=$(percentile 0.50 "$sorted")
    p95=$(percentile 0.95 "$sorted")
    mx=$(tail -n1 "$sorted")
    rm -f "$sorted"
    color="$GREEN"
    [ "${p95:-0}" -gt 50 ] && { color="$RED"; over_threshold=1; }
    printf "${color}%-32s %6s %6s %6s %5s${NC}\n" \
        "$hook" "${p50:-?}" "${p95:-?}" "${mx:-?}" "${n:-?}"
done

# ============================================================
# Worst-offender report — slowest single invocation per hook
# ============================================================
echo ""
printf "${BOLD}Slowest single invocations (top 5)${NC}\n"
hooks_filter=$(printf '"%s",' "${HOOKS[@]}")
hooks_filter="[${hooks_filter%,}]"
printf "%-32s  %4s  %s\n" "hook" "ms" "outcome"
jq -r --argjson hooks "$hooks_filter" \
    'select(.kind == "invocation" and .section == "" and (.hook_name | IN($hooks[]))) | [.hook_name, .duration_ms, .outcome] | @tsv' \
    "$RUN_TAIL" 2>/dev/null \
    | sort -t$'\t' -k2 -n -r \
    | head -n5 \
    | awk -F'\t' '{printf "%-32s  %4s  %s\n", $1, $2, $3}'

# ============================================================
# Verdict
# ============================================================
echo ""
printf "${BOLD}Note:${NC} absolute p95 includes ~40-50ms bash fork + source overhead.\n"
printf "The registry-overhead acceptance is on the ${BOLD}delta${NC} vs a baseline run\n"
printf "(see header comment for the A/B procedure). A 50ms+ absolute p95 by itself\n"
printf "is not a regression signal.\n"
if [ "$over_threshold" = 1 ]; then
    printf "${YELLOW}⚠ Absolute p95 > 50ms on at least one hook — diff against a baseline\n"
    printf "  run to know whether the registry contributed.${NC}\n"
fi
