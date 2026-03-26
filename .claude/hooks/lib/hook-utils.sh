#!/bin/bash
# Shared hook utilities — sourced by all hooks for standardized
# initialization, outcome handling, and execution logging.
#
# Dual-write: TSV file (hook-timing.log) + SQLite (claude-hook-logs.db).
# DB write is optional — silently skipped if db doesn't exist.
#
# TSV format (12 columns):
#   session_id | invocation_id | timestamp | project | hook_event | hook_name | tool_name | section | duration_ms | outcome | bytes_injected | is_test
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
INVOCATION_ID=""
SESSION_ID=""
PROJECT=""
HOOK_START_MS=0
OUTCOME="pass"
BYTES_INJECTED=0
TOTAL_BYTES_INJECTED=0
HOOK_LOG_FILE=""
HOOK_LOG_DB="$HOME/.claude/claude-hook-logs.db"
IS_TEST=0  # 1 when invoked by test harness (CLAUDE_HOOK_TEST=1)
_HOOK_ACTIVE=false  # true once hook_require_tool matches (or for SessionStart)

# ============================================================
# hook_init HOOK_NAME HOOK_EVENT
# ============================================================
hook_init() {
    HOOK_NAME="$1"
    HOOK_EVENT="$2"
    HOOK_INPUT=$(cat)
    INPUT="$HOOK_INPUT"  # backward compat
    INVOCATION_ID="$$-$(date +%s)"
    PROJECT="$(basename "$PWD")"
    HOOK_START_MS=$(date +%s%3N)
    OUTCOME="pass"
    BYTES_INJECTED=0
    TOTAL_BYTES_INJECTED=0
    HOOK_LOG_FILE=".claude/logs/hook-timing.log"
    mkdir -p ".claude/logs" 2>/dev/null || true
    SESSION_ID=$(cat ".claude/logs/.session-id" 2>/dev/null || echo "unknown")
    IS_TEST=$([ "${CLAUDE_HOOK_TEST:-0}" = "1" ] && echo 1 || echo 0)
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
    local bytes ts
    bytes=$(printf '%s' "$content" | wc -c)
    ts=$(date -Iseconds)
    TOTAL_BYTES_INJECTED=$(( TOTAL_BYTES_INJECTED + bytes ))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$SESSION_ID" "$INVOCATION_ID" "$ts" "$PROJECT" \
        "$HOOK_EVENT" "$HOOK_NAME" "$TOOL_NAME" "$section" \
        "0" "pass" "$bytes" "$IS_TEST" \
        >> "$HOOK_LOG_FILE" 2>/dev/null || true
    _hook_log_db "INSERT INTO hook_logs (session_id, invocation_id, timestamp, project, hook_event, hook_name, tool_name, section, duration_ms, outcome, bytes_injected, is_test)
    VALUES ('$SESSION_ID', '$INVOCATION_ID', '$ts', '$(_sql_escape "$PROJECT")', '$HOOK_EVENT', '$HOOK_NAME', '$(_sql_escape "$TOOL_NAME")', '$(_sql_escape "$section")', 0, 'pass', $bytes, $IS_TEST);"
}

# ============================================================
# _sql_escape VALUE  (internal — escape single quotes for SQL)
# ============================================================
_sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# ============================================================
# _hook_log_db SQL  (internal — insert into claude-hook-logs.db)
# ============================================================
_hook_log_db() {
    [ -f "$HOOK_LOG_DB" ] || return 0
    printf '%s\n' "$1" | sqlite3 "$HOOK_LOG_DB" 2>/dev/null || true
}

# ============================================================
# hook_log_context RAW_CONTEXT KEYWORDS MATCH_COUNT MATCHED_IDS
# ============================================================
hook_log_context() {
    local raw_context="$1"
    local keywords="$2"
    local match_count="$3"
    local matched_ids="$4"
    _hook_log_db "INSERT INTO surface_lessons_context (session_id, invocation_id, timestamp, project, tool_name, raw_context, keywords, match_count, matched_lesson_ids, is_test)
    VALUES ('$SESSION_ID', '$INVOCATION_ID', '$(date -Iseconds)', '$(_sql_escape "$PROJECT")', '$(_sql_escape "$TOOL_NAME")', '$(_sql_escape "$raw_context")', '$(_sql_escape "$keywords")', $match_count, '$matched_ids', $IS_TEST);"
}

# ============================================================
# _hook_log_timing  (internal — EXIT trap)
# ============================================================
_hook_log_timing() {
    # Skip logging if hook never matched a tool (early exit from hook_require_tool)
    [ "$_HOOK_ACTIVE" = true ] || return 0
    local end_ms ts
    end_ms=$(date +%s%3N)
    ts=$(date -Iseconds)
    local duration_ms=$(( end_ms - HOOK_START_MS ))
    local bytes=$BYTES_INJECTED
    if [ "$TOTAL_BYTES_INJECTED" -gt 0 ] 2>/dev/null; then
        bytes=$TOTAL_BYTES_INJECTED
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$SESSION_ID" "$INVOCATION_ID" "$ts" "$PROJECT" \
        "$HOOK_EVENT" "$HOOK_NAME" "$TOOL_NAME" "" \
        "$duration_ms" "$OUTCOME" "$bytes" "$IS_TEST" \
        >> "$HOOK_LOG_FILE" 2>/dev/null || true
    _hook_log_db "INSERT INTO hook_logs (session_id, invocation_id, timestamp, project, hook_event, hook_name, tool_name, section, duration_ms, outcome, bytes_injected, is_test)
    VALUES ('$SESSION_ID', '$INVOCATION_ID', '$ts', '$(_sql_escape "$PROJECT")', '$HOOK_EVENT', '$HOOK_NAME', '$(_sql_escape "$TOOL_NAME")', '', $duration_ms, '$OUTCOME', $bytes, $IS_TEST);"
}
