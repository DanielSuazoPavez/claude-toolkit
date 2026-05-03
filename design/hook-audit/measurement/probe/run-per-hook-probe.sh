#!/usr/bin/env bash
# Per-hook end-to-end timing probe.
#
# For each standardized hook, runs `bash <hook>.sh < <fixture>.json` N times in
# two modes:
#   smoke  — env -i + sandboxed sessions.db + traceability OFF (matches
#            tests/hooks/run-smoke.sh; no sqlite3 fork, no JSONL write)
#   real   — env -i + real (read-only) sessions.db + traceability ON
#            (one sqlite3 fork in _resolve_project_id; one jq -c fork in
#             _hook_log_timing EXIT trap; JSONL row written to tmp dir)
#
# Output (stdout, TSV): hook  outcome  mode  run  total_us
# Aggregate report (stderr): min / p50 / p90 / p95 / max per (hook, outcome, mode).
#
# Usage:
#   bash design/hook-audit/measurement/probe/run-per-hook-probe.sh [N]
#   N defaults to 30 (audit guidance: N≥30).
#
# Paired outcome fixtures (V21+): each hook is sampled with both a pass-outcome
# fixture and a non-pass-outcome (block/approve/error) fixture where the pair
# exists. Three exceptions ship pass-only fixtures (see HOOKS_AND_FIXTURES
# below): detect-session-start-truncation (block fixture deferred — depends on
# smoke-runner $HOME injection), log-permission-denied and log-tool-uses
# (logger hooks have no decision body — second fixture is malformed-stdin
# error path, treated as the non-pass outcome).
#
# Note: log-tool-uses, log-permission-denied, and detect-session-start-truncation
# are pure-logger / fire-once hooks. The EXIT trap row is the entirety of their
# work; "smoke" mode disables it, so smoke numbers underreport real-session for
# these hooks. Real mode is the meaningful column for them.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
FIXTURES_DIR="$REPO_ROOT/tests/hooks/fixtures"
SESSIONS_DB_REAL="${CLAUDE_TOOLKIT_PROBE_SESSIONS_DB:-$HOME/.claude/sessions.db}"
N="${1:-30}"

# (hook outcome fixture) triples — paired (block, pass) coverage where both
# fixtures exist. Skip dispatchers and session-context hooks; those are
# categories 02 and 03. Three exceptions are pass-only (see header note).
#
# Outcome label mirrors V20's branching: 'pass' selects the scope_miss budget;
# any other label (blocked/approved/error) selects scope_hit.
HOOKS_AND_FIXTURES=(
    "approve-safe-commands           approved approves-ls"
    "approve-safe-commands           pass     passes-non-allowlist-bash"
    "auto-mode-shared-steps          blocked  blocks-git-push-under-auto-mode"
    "auto-mode-shared-steps          pass     passes-noop-bash"
    "block-config-edits              blocked  blocks-edit-bashrc"
    "block-config-edits              pass     passes-edit-non-config-file"
    "block-credential-exfiltration   blocked  blocks-curl-with-token"
    "block-credential-exfiltration   pass     passes-curl-no-credentials"
    "block-dangerous-commands        blocked  blocks-rm-rf-root"
    "block-dangerous-commands        pass     passes-benign-ls"
    "detect-session-start-truncation pass     passes-untruncated"
    "enforce-make-commands           blocked  blocks-bare-pytest"
    "enforce-make-commands           pass     passes-make-test"
    "enforce-uv-run                  blocked  blocks-bare-python"
    "enforce-uv-run                  pass     passes-uv-run-python"
    "git-safety                      blocked  blocks-force-push-main"
    "git-safety                      pass     passes-git-status"
    "log-permission-denied           pass     logs-denied"
    "log-permission-denied           error    passes-on-malformed-stdin"
    "log-tool-uses                   pass     logs-bash"
    "log-tool-uses                   error    passes-on-malformed-stdin"
    "secrets-guard                   blocked  blocks-dotenv-grep"
    "secrets-guard                   pass     passes-grep-non-secret-path"
    "suggest-read-json               blocked  blocks-on-large-json"
    "suggest-read-json               pass     passes-on-nonexistent-json"
)

MODES=(smoke real)

_now_us() {
    local _sec="${EPOCHREALTIME%.*}"
    local _frac="${EPOCHREALTIME#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

run_one() {
    local hook="$1" fixture="$2" mode="$3"
    local hook_path="$HOOKS_DIR/$hook.sh"
    local fixture_json="$FIXTURES_DIR/$hook/$fixture.json"
    local tmp; tmp=$(mktemp -d -t per-hook-probe-XXXXXX)
    mkdir -p "$tmp/fakehome" "$tmp/hook-logs"
    : > "$tmp/lessons.db"

    local sessions_db_arg traceability_arg
    if [ "$mode" = "real" ]; then
        sessions_db_arg="$SESSIONS_DB_REAL"
        traceability_arg=1
    else
        sessions_db_arg="$tmp/nonexistent-sessions.db"
        traceability_arg=0
    fi

    local wall_start wall_end
    wall_start=$(_now_us)

    # Same env-isolation contract as tests/hooks/run-smoke.sh, with the two
    # mode-dependent knobs (sessions.db path + traceability) varied.
    env -i \
        PATH="$PATH" HOME="$tmp/fakehome" USER="${USER:-probe}" \
        LANG="${LANG:-C.UTF-8}" TZ="${TZ:-UTC}" \
        CLAUDE_TOOLKIT_HOOK_FIXTURE="$fixture" \
        CLAUDE_ANALYTICS_HOOKS_DIR="$tmp/hook-logs" \
        CLAUDE_ANALYTICS_HOOKS_DB="$tmp/nonexistent-hooks.db" \
        CLAUDE_ANALYTICS_SESSIONS_DB="$sessions_db_arg" \
        CLAUDE_ANALYTICS_LESSONS_DB="$tmp/lessons.db" \
        CLAUDE_TOOLKIT_HOOKS_DB_DIR="$tmp" \
        CLAUDE_TOOLKIT_LESSONS=0 \
        CLAUDE_TOOLKIT_TRACEABILITY="$traceability_arg" \
            bash "$hook_path" < "$fixture_json" >/dev/null 2>/dev/null

    wall_end=$(_now_us)
    rm -rf "$tmp"
    echo $(( wall_end - wall_start ))
}

# Warmup — one iteration per (hook, outcome, mode) triple, results discarded.
for triple in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook outcome fixture <<<"$triple"
    for mode in "${MODES[@]}"; do
        run_one "$hook" "$fixture" "$mode" >/dev/null || {
            echo "warmup failed for $hook/$outcome/$mode" >&2
            exit 1
        }
    done
done

# Header.
printf 'hook\toutcome\tmode\trun\ttotal_us\n'

declare -A SAMPLES
for triple in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook outcome fixture <<<"$triple"
    for mode in "${MODES[@]}"; do
        SAMPLES["$hook|$outcome|$mode"]=""
    done
done

for triple in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook outcome fixture <<<"$triple"
    for mode in "${MODES[@]}"; do
        for ((i=1; i<=N; i++)); do
            us=$(run_one "$hook" "$fixture" "$mode") || exit 1
            printf '%s\t%s\t%s\t%d\t%d\n' "$hook" "$outcome" "$mode" "$i" "$us"
            SAMPLES["$hook|$outcome|$mode"]+="$us "
        done
    done
done

percentile() {
    local p="$1"; shift
    local sorted; sorted=$(printf '%s\n' "$@" | sort -n)
    local count; count=$(echo "$sorted" | wc -l)
    local idx=$(( (p * count + 99) / 100 ))
    [ "$idx" -lt 1 ] && idx=1
    [ "$idx" -gt "$count" ] && idx="$count"
    echo "$sorted" | sed -n "${idx}p"
}

stats() {
    local label="$1"; shift
    local n=$#
    local min p50 p90 p95 max
    min=$(percentile 0   "$@")
    p50=$(percentile 50  "$@")
    p90=$(percentile 90  "$@")
    p95=$(percentile 95  "$@")
    max=$(percentile 100 "$@")
    printf '%-50s  n=%-4d  min=%-7d  p50=%-7d  p90=%-7d  p95=%-7d  max=%-7d\n' \
        "$label" "$n" "$min" "$p50" "$p90" "$p95" "$max" >&2
}

echo "" >&2
echo "=== Per-hook total wall-clock (microseconds) ===" >&2
for triple in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook outcome fixture <<<"$triple"
    for mode in "${MODES[@]}"; do
        # shellcheck disable=SC2086
        stats "$hook/$outcome ($mode)" ${SAMPLES["$hook|$outcome|$mode"]}
    done
done
