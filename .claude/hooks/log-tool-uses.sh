#!/usr/bin/env bash
# CC-HOOK: NAME: log-tool-uses
# CC-HOOK: PURPOSE: Log every tool invocation to invocations.jsonl
# CC-HOOK: EVENTS: PostToolUse
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: traceability
# CC-HOOK: SHIPS-IN: base
# CC-HOOK: RELATES-TO: surface-lessons(informs)
#
# PostToolUse logger: records every tool invocation to invocations.jsonl
# with full stdin (including duration_ms and tool_response) for
# downstream idle-time classification in claude-sessions.
#
# Settings.json:
#   "PostToolUse": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/log-tool-uses.sh"}]}]
#
# Pure logger — no stdout output. The EXIT trap in hook-utils.sh writes
# one invocation row (with full stdin embedded) to invocations.jsonl
# when traceability is enabled.

set -uo pipefail
source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "log-tool-uses" "PostToolUse"

# shellcheck disable=SC2034  # TOOL_NAME is read by _hook_log_timing EXIT trap
TOOL_NAME=$(hook_get_input '.tool_name')

_HOOK_ACTIVE=true

exit 0
