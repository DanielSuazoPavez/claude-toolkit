#!/usr/bin/env bash
# Shared setup for hook tests.
#
# Sourced by tests/hooks/test-*.sh and the legacy tests/test-hooks.sh.
# Sets HOOKS_DIR and redirects CLAUDE_ANALYTICS_HOOKS_DIR to a per-process
# temp directory so ~/claude-analytics/hook-logs/ is never touched by the
# suite. Each sourcing process gets its own dir, so parallel runners don't
# contend.

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"

TEST_HOOKS_DIR="$(mktemp -d -t claude-toolkit-hooks-XXXXXX)"
export CLAUDE_ANALYTICS_HOOKS_DIR="$TEST_HOOKS_DIR"
# Convenience aliases for assertions in test files.
export TEST_INVOCATIONS_JSONL="$TEST_HOOKS_DIR/invocations.jsonl"
export TEST_SURFACE_LESSONS_JSONL="$TEST_HOOKS_DIR/surface-lessons-context.jsonl"
export TEST_SESSION_START_JSONL="$TEST_HOOKS_DIR/session-start-context.jsonl"
# Point the read-only hooks.db path at a non-existent file so tests don't
# accidentally read the user's real ~/claude-analytics/hooks.db. Tests that need to
# exercise the dedup path (which reads hooks.db.surface_lessons_context) set
# CLAUDE_ANALYTICS_HOOKS_DB themselves to a fixture DB.
export CLAUDE_ANALYTICS_HOOKS_DB="$TEST_HOOKS_DIR/nonexistent-hooks.db"
# bash resets traps in subshells, so `( ... )` blocks (e.g. the cd-into-tempdir
# pattern in test-git-safety.sh) don't fire this on subshell exit — the dir
# survives until the parent process exits via print_summary.
trap 'rm -rf "$TEST_HOOKS_DIR"' EXIT
