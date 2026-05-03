#!/usr/bin/env bash
# CC-HOOK: NAME: detect-session-start-truncation
# CC-HOOK: PURPOSE: Detect truncation of SessionStart attachment and warn the user once
# CC-HOOK: EVENTS: UserPromptSubmit
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=26, scope_hit=26
# CC-HOOK: OPT-IN: none
# CC-HOOK: SHIPS-IN: base
# CC-HOOK: RELATES-TO: session-start(informs)
#
# Session-start truncation detector
#
# Runs on UserPromptSubmit. Checks the transcript for the harness
# truncation marker (<persisted-output> + "Output too large") on
# a SessionStart attachment. Fires only once per session — creates
# a marker file to avoid re-checking on subsequent prompts.
#
# If truncation is found, emits a loud warning so the model knows
# essential docs may be incomplete.
#
# Settings.json placement:
#   hooks.UserPromptSubmit (no matcher needed — self-gates via marker file)

set -uo pipefail

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "detect-session-start-truncation" "UserPromptSubmit"
_HOOK_ACTIVE=true

# Fire-once guard: skip if we already checked this session
MARKER_DIR="/tmp/claude-truncation-check"
MARKER_FILE="$MARKER_DIR/$SESSION_ID"
if [ -f "$MARKER_FILE" ]; then
    # shellcheck disable=SC2034  # OUTCOME read by _hook_log_timing EXIT trap
    OUTCOME="pass"
    exit 0
fi
mkdir -p "$MARKER_DIR" 2>/dev/null
touch "$MARKER_FILE" 2>/dev/null

# Resolve transcript path
PROJECT_DIR_NAME=$(pwd | sed 's|/|-|g; s|^-||')
TRANSCRIPT="$HOME/.claude/projects/-${PROJECT_DIR_NAME}/${SESSION_ID}.jsonl"

if [ ! -f "$TRANSCRIPT" ]; then
    # shellcheck disable=SC2034  # OUTCOME read by _hook_log_timing EXIT trap
    OUTCOME="pass"
    exit 0
fi

# Look for the truncation marker on a SessionStart attachment
if grep -q '"hookEvent":"SessionStart"' "$TRANSCRIPT" && \
   grep '"hookEvent":"SessionStart"' "$TRANSCRIPT" | grep -q 'persisted-output'; then
    # shellcheck disable=SC2034  # read by _hook_log_timing EXIT trap
    OUTCOME="injected"
    # shellcheck disable=SC2034  # read by _hook_log_timing EXIT trap
    BYTES_INJECTED=0
    echo ""
    echo "=== SESSION START TRUNCATION DETECTED ==="
    echo "WARNING: SessionStart hook output was truncated by the harness (~10KB cap)."
    echo "Essential docs may NOT be fully loaded. Read them explicitly:"
    echo "  - .claude/docs/essential-conventions-code_style.md"
    echo "  - .claude/docs/essential-conventions-execution.md"
    echo "  - .claude/docs/essential-preferences-communication_style.md"
    echo ""
    echo "MANDATORY: Acknowledge this truncation in your first message."
else
    echo "[truncation-detector] no truncation detected — session start output was within cap"
fi

exit 0
