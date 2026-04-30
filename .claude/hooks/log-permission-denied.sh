#!/usr/bin/env bash
# CC-HOOK: NAME: log-permission-denied
# CC-HOOK: PURPOSE: Log auto-mode classifier denials to invocations.jsonl
# CC-HOOK: EVENTS: PermissionDenied
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: traceability
#
# PermissionDenied hook: log auto-mode classifier denials for analytics
#
# Settings.json:
#   "PermissionDenied": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/log-permission-denied.sh"}]}]
#
# Pure logger — no stdout output, denial stands. The EXIT trap in
# hook-utils.sh writes one invocation row (with full stdin embedded)
# to invocations.jsonl when traceability is enabled.
#
# Unblocks claude-sessions' auto-mode-classifier-observability:
# cross-join hook_logs.PermissionDenied with tool_calls.tool_use_id
# for deny-count, classifier latency, and reason histograms.

set -uo pipefail
source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "log-permission-denied" "PermissionDenied"

# shellcheck disable=SC2034  # TOOL_NAME is read by _hook_log_timing EXIT trap
TOOL_NAME=$(hook_get_input '.tool_name')

# hook_init only auto-activates for SessionStart; other events need
# hook_require_tool, which we skip because we want all tools.
_HOOK_ACTIVE=true

exit 0
