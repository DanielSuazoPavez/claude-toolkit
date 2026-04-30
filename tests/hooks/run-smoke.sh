#!/usr/bin/env bash
# Smoke runner for one fixture: replays <fixture>.json through the hook in a
# sandboxed env, captures the kind:smoketest JSONL row, and asserts against
# <fixture>.expect.
#
# Usage:
#   bash tests/hooks/run-smoke.sh <hook-name> <fixture-name> [--report <path>]
#
# Exit codes:
#   0  all .expect assertions hold
#   1  outcome mismatch (one line per failure on stderr)
#   2  runner error (missing fixture, no row written, unknown .expect key)
#
# Env overrides:
#   CLAUDE_TOOLKIT_HOOKS_DIR     hooks dir (default: .claude/hooks)
#   CLAUDE_TOOLKIT_FIXTURES_DIR  fixtures root (default: tests/hooks/fixtures)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HOOKS_DIR="${CLAUDE_TOOLKIT_HOOKS_DIR:-$REPO_ROOT/.claude/hooks}"
FIXTURES_DIR="${CLAUDE_TOOLKIT_FIXTURES_DIR:-$REPO_ROOT/tests/hooks/fixtures}"

# shellcheck source=tests/lib/test-helpers.sh
source "$REPO_ROOT/tests/lib/test-helpers.sh"

usage() {
    echo "Usage: $0 <hook-name> <fixture-name> [--report <path>]" >&2
    exit 2
}

[ "$#" -ge 2 ] || usage
HOOK="$1"
FIXTURE="$2"
shift 2
REPORT_PATH=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --report)
            REPORT_PATH="${2:-}"
            [ -z "$REPORT_PATH" ] && { echo "--report requires a path" >&2; exit 2; }
            shift 2
            ;;
        *) echo "unknown arg: $1" >&2; usage ;;
    esac
done

HOOK_PATH="$HOOKS_DIR/$HOOK.sh"
FIXTURE_DIR="$FIXTURES_DIR/$HOOK"
FIXTURE_JSON="$FIXTURE_DIR/$FIXTURE.json"
FIXTURE_EXPECT="$FIXTURE_DIR/$FIXTURE.expect"

[ -f "$HOOK_PATH" ]      || { echo "runner: hook not found: $HOOK_PATH" >&2; exit 2; }
[ -f "$FIXTURE_JSON" ]   || { echo "runner: fixture stdin not found: $FIXTURE_JSON" >&2; exit 2; }
[ -f "$FIXTURE_EXPECT" ] || { echo "runner: fixture .expect not found: $FIXTURE_EXPECT" >&2; exit 2; }

tmpdir=$(mktemp -d -t claude-toolkit-smoke-XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/fakehome"

# Run the hook in a sanitised env. env -i strips inherited CLAUDE_* vars;
# we re-export only the allowlist needed for the harness + sandboxed paths.
env -i \
    PATH="$PATH" HOME="$tmpdir/fakehome" USER="${USER:-smoke}" \
    LANG="${LANG:-C.UTF-8}" TZ="${TZ:-UTC}" \
    CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1 \
    CLAUDE_TOOLKIT_HOOK_FIXTURE="$FIXTURE" \
    CLAUDE_ANALYTICS_HOOKS_DIR="$tmpdir/hook-logs" \
    CLAUDE_ANALYTICS_HOOKS_DB="$tmpdir/nonexistent-hooks.db" \
    CLAUDE_ANALYTICS_SESSIONS_DB="$tmpdir/nonexistent-sessions.db" \
    CLAUDE_TOOLKIT_HOOKS_DB_DIR="$tmpdir" \
    CLAUDE_TOOLKIT_LESSONS=0 \
    CLAUDE_TOOLKIT_TRACEABILITY=0 \
    bash "$HOOK_PATH" < "$FIXTURE_JSON" > "$tmpdir/stdout" 2> "$tmpdir/stderr"

ROW_FILE="$tmpdir/hook-logs/smoketest.jsonl"
if [ ! -s "$ROW_FILE" ]; then
    echo "runner: no smoketest row written by $HOOK / $FIXTURE — check that the hook calls hook_init" >&2
    [ -s "$tmpdir/stderr" ] && { echo "--- hook stderr ---" >&2; cat "$tmpdir/stderr" >&2; }
    exit 2
fi

if [ -n "$REPORT_PATH" ]; then
    cp "$ROW_FILE" "$REPORT_PATH"
fi

# Parse .expect line-by-line. Each non-empty, non-# line is key=value.
failures=0
fail() {
    echo "  FAIL [$HOOK/$FIXTURE]: $1" >&2
    failures=$((failures + 1))
}

while IFS= read -r line || [ -n "$line" ]; do
    # Strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in
        \#*) continue ;;
    esac
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in
        outcome)
            actual=$(jq -r '.outcome // ""' "$ROW_FILE" 2>/dev/null)
            [ "$actual" = "$val" ] || fail "outcome: expected '$val', got '$actual'"
            ;;
        hook_event)
            actual=$(jq -r '.hook_event // ""' "$ROW_FILE" 2>/dev/null)
            [ "$actual" = "$val" ] || fail "hook_event: expected '$val', got '$actual'"
            ;;
        hook_name)
            actual=$(jq -r '.hook_name // ""' "$ROW_FILE" 2>/dev/null)
            [ "$actual" = "$val" ] || fail "hook_name: expected '$val', got '$actual'"
            ;;
        tool_name)
            actual=$(jq -r '.tool_name // ""' "$ROW_FILE" 2>/dev/null)
            [ "$actual" = "$val" ] || fail "tool_name: expected '$val', got '$actual'"
            ;;
        decision_json_contains)
            actual=$(jq -r '.decision_json // ""' "$ROW_FILE" 2>/dev/null)
            case "$actual" in
                *"$val"*) ;;
                *) fail "decision_json_contains: '$val' not found in '$actual'" ;;
            esac
            ;;
        bytes_injected_min)
            actual=$(jq -r '.bytes_injected // 0' "$ROW_FILE" 2>/dev/null)
            if ! [ "${actual:-0}" -ge "$val" ] 2>/dev/null; then
                fail "bytes_injected_min: expected >= $val, got $actual"
            fi
            ;;
        duration_ms_max)
            # V19 ignores; V20 uses. Runner accepts the key for forward-compat.
            ;;
        *)
            echo "runner: unknown .expect key: '$key' in $FIXTURE_EXPECT" >&2
            exit 2
            ;;
    esac
done < "$FIXTURE_EXPECT"

if [ "$failures" -gt 0 ]; then
    report_fail "$HOOK / $FIXTURE ($failures failure(s))"
    exit 1
fi
report_pass "$HOOK / $FIXTURE"
exit 0
