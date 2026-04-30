#!/usr/bin/env bash
# Walk every fixture under tests/hooks/fixtures/<hook>/ and invoke run-smoke.sh
# for each. Sequential — output stays readable; parallelizable later if it
# becomes a bottleneck.
#
# Usage:
#   bash tests/hooks/run-smoke-all.sh        # verbose
#   bash tests/hooks/run-smoke-all.sh -q     # quiet (summary only)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="${CLAUDE_TOOLKIT_FIXTURES_DIR:-$REPO_ROOT/tests/hooks/fixtures}"
RUNNER="${CLAUDE_TOOLKIT_SMOKE_RUNNER:-$REPO_ROOT/tests/hooks/run-smoke.sh}"

QUIET=0
for arg in "$@"; do
    case "$arg" in
        -q|--quiet) QUIET=1 ;;
    esac
done

pass=0
fail=0
runner_err=0
failed_lines=()

for d in "$FIXTURES_DIR"/*/; do
    [ -d "$d" ] || continue
    hook="$(basename "$d")"
    case "$hook" in
        _*) continue ;;   # _templates and any other reference dir
    esac
    for j in "$d"*.json; do
        [ -f "$j" ] || continue
        stem="$(basename "$j" .json)"
        [ -f "$d$stem.expect" ] || continue
        out=$(bash "$RUNNER" "$hook" "$stem" 2>&1)
        rc=$?
        case "$rc" in
            0) pass=$((pass + 1)); [ "$QUIET" = "0" ] && echo "$out" ;;
            1) fail=$((fail + 1)); failed_lines+=("$out") ;;
            *) runner_err=$((runner_err + 1)); failed_lines+=("$out") ;;
        esac
    done
done

if [ "${#failed_lines[@]}" -gt 0 ]; then
    echo ""
    echo "=== Failures ==="
    printf '%s\n' "${failed_lines[@]}"
fi

total=$((pass + fail + runner_err))
echo ""
echo "Smoke: $pass/$total passed${runner_err:+, $runner_err runner error(s)}"

[ "$fail" -eq 0 ] && [ "$runner_err" -eq 0 ]
