#!/bin/bash
# Shared setup for hook tests.
#
# Sourced by tests/hooks/test-*.sh and the legacy tests/test-hooks.sh.
# Sets HOOKS_DIR, enables CLAUDE_HOOK_TEST=1, and redirects HOOK_LOG_DB
# to a per-process temp SQLite file so ~/.claude/hooks.db is never
# touched by the suite. Each sourcing process gets its own DB, so
# parallel runners don't contend.

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
export CLAUDE_HOOK_TEST=1

TEST_HOOKS_DB="$(mktemp -t claude-toolkit-hooks-XXXXXX.db)"
rm -f "$TEST_HOOKS_DB"
if [ -f "$HOME/.claude/hooks.db" ]; then
    sqlite3 "$HOME/.claude/hooks.db" .schema | sqlite3 "$TEST_HOOKS_DB" 2>/dev/null || true
    # Tripwire: if the real DB exists but the clone produced no hook_logs table,
    # DB-dependent assertions will silently skip and we lose write-contract coverage.
    if ! sqlite3 "$TEST_HOOKS_DB" "SELECT 1 FROM hook_logs LIMIT 0" >/dev/null 2>&1; then
        echo "warning: hooks.db schema clone failed — DB-dependent assertions will skip" >&2
    fi
fi
export HOOK_LOG_DB="$TEST_HOOKS_DB"
# bash resets traps in subshells, so `( ... )` blocks (e.g. the cd-into-tempdir
# pattern in test-git-safety.sh) don't fire this on subshell exit — the DB
# survives until the parent process exits via print_summary.
trap 'rm -f "$TEST_HOOKS_DB"' EXIT
