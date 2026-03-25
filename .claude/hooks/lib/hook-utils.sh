#!/bin/bash
# Shared hook utilities — sourced by all hooks for standardized
# initialization, outcome handling, and execution logging.
#
# Log format (TSV, 10 columns) consumed by claude-sessions analytics:
#   session_id | timestamp | project | hook_event | hook_name | tool_name | section | duration_ms | outcome | bytes_injected
#
# Usage:
#   source "$(dirname "$0")/lib/hook-utils.sh"
#   hook_init "hook-name" "PreToolUse"
#   hook_require_tool "Bash" "Read"
#   COMMAND=$(hook_get_input '.tool_input.command')
#   hook_block "reason"

# --- Globals (set by hook_init) ---
HOOK_INPUT=""
INPUT=""  # backward compat alias
HOOK_NAME=""
HOOK_EVENT=""
TOOL_NAME=""
SESSION_ID=""
PROJECT=""
HOOK_START_MS=0
OUTCOME="pass"
BYTES_INJECTED=0
TOTAL_BYTES_INJECTED=0
HOOK_LOG_FILE=""
_HOOK_ACTIVE=false  # true once hook_require_tool matches (or for SessionStart)

# ============================================================
# hook_init HOOK_NAME HOOK_EVENT
# ============================================================
hook_init() {
    HOOK_NAME="$1"
    HOOK_EVENT="$2"
    HOOK_INPUT=$(cat)
    INPUT="$HOOK_INPUT"  # backward compat
    SESSION_ID="$$-$(date +%s)"
    PROJECT="$(basename "$PWD")"
    HOOK_START_MS=$(date +%s%3N)
    OUTCOME="pass"
    BYTES_INJECTED=0
    TOTAL_BYTES_INJECTED=0
    HOOK_LOG_FILE=".claude/logs/hook-timing.log"
    mkdir -p ".claude/logs" 2>/dev/null || true
    # SessionStart hooks don't call hook_require_tool, so mark active immediately
    if [ "$HOOK_EVENT" = "SessionStart" ]; then
        _HOOK_ACTIVE=true
    fi
    trap '_hook_log_timing' EXIT
}

# ============================================================
# hook_require_tool TOOL1 [TOOL2 ...]
# ============================================================
hook_require_tool() {
    TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
    local match=false
    for expected in "$@"; do
        if [ "$TOOL_NAME" = "$expected" ]; then
            match=true
            break
        fi
    done
    if [ "$match" = false ]; then
        exit 0
    fi
    _HOOK_ACTIVE=true
}

# ============================================================
# hook_get_input JQ_PATH
# ============================================================
hook_get_input() {
    echo "$HOOK_INPUT" | jq -r "$1 // \"\"" 2>/dev/null || echo ""
}

# ============================================================
# hook_block REASON
# ============================================================
hook_block() {
    OUTCOME="blocked"
    local reason="$1"
    # Escape backslashes first, then double quotes for JSON
    reason="${reason//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    echo "{\"decision\": \"block\", \"reason\": \"$reason\"}"
    exit 0
}

# ============================================================
# hook_approve REASON
# ============================================================
hook_approve() {
    OUTCOME="approved"
    local reason="$1"
    reason="${reason//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"permissionDecision\":\"allow\",\"permissionDecisionReason\":\"$reason\"}}"
    exit 0
}

# ============================================================
# hook_inject CONTEXT_STRING
# ============================================================
# CONTEXT_STRING must already be JSON-escaped by the caller.
hook_inject() {
    OUTCOME="injected"
    local context="$1"
    BYTES_INJECTED=${#context}
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"additionalContext\":\"$context\"}}"
    exit 0
}

# ============================================================
# hook_log_section SECTION_NAME CONTENT
# ============================================================
hook_log_section() {
    local section="$1"
    local content="$2"
    local bytes
    bytes=$(printf '%s' "$content" | wc -c)
    TOTAL_BYTES_INJECTED=$(( TOTAL_BYTES_INJECTED + bytes ))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$SESSION_ID" "$(date -Iseconds)" "$PROJECT" \
        "$HOOK_EVENT" "$HOOK_NAME" "$TOOL_NAME" "$section" \
        "0" "pass" "$bytes" \
        >> "$HOOK_LOG_FILE" 2>/dev/null || true
}

# ============================================================
# _hook_log_timing  (internal — EXIT trap)
# ============================================================
_hook_log_timing() {
    # Skip logging if hook never matched a tool (early exit from hook_require_tool)
    [ "$_HOOK_ACTIVE" = true ] || return 0
    local end_ms
    end_ms=$(date +%s%3N)
    local duration_ms=$(( end_ms - HOOK_START_MS ))
    local bytes=$BYTES_INJECTED
    if [ "$TOTAL_BYTES_INJECTED" -gt 0 ] 2>/dev/null; then
        bytes=$TOTAL_BYTES_INJECTED
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$SESSION_ID" "$(date -Iseconds)" "$PROJECT" \
        "$HOOK_EVENT" "$HOOK_NAME" "$TOOL_NAME" "" \
        "$duration_ms" "$OUTCOME" "$bytes" \
        >> "$HOOK_LOG_FILE" 2>/dev/null || true
}
