#!/bin/bash
# Shared hook utilities — sourced by all hooks for standardized
# initialization, outcome handling, and execution logging.
#
# Idempotent: safe to source multiple times. Dispatcher flows source
# hook-utils once, then source hook files that also source hook-utils —
# the second source must not reset globals (hook_init has already run
# and populated HOOK_INPUT, SESSION_ID, etc.).

# Idempotency guard: if already sourced, skip re-initialization of globals
# and function definitions. Function re-definitions would be harmless, but
# the global resets below would clobber hook_init state.
if [ -n "${_HOOK_UTILS_SOURCED:-}" ]; then
    return 0
fi
_HOOK_UTILS_SOURCED=1
#
# Logs execution data to SQLite (hooks.db). Silently skipped if db doesn't exist.
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
HOOK_SOURCE=""   # SessionStart source: startup|resume|clear|compact, empty for other events
CALL_ID=""       # Per-call id: bare tool_use_id (Pre/PostToolUse) or agent_id (SubagentStop), empty otherwise. Tool-vs-agent is derived from hook_event, not a prefix.
PROJECT=""
HOOK_START_MS=0
OUTCOME="pass"
BYTES_INJECTED=0
TOTAL_BYTES_INJECTED=0
HOOK_LOG_DB="${HOOK_LOG_DB:-$HOME/.claude/hooks.db}"
_HOOK_ACTIVE=false  # true once hook_require_tool matches (or for SessionStart)
_HOOK_SQL_BATCH=""  # accumulated SQL statements, flushed once in EXIT trap

# ============================================================
# _now_ms
# ============================================================
# Current time in milliseconds. Uses EPOCHREALTIME (bash 5.0+, no fork)
# with fallback to `date +%s%3N`.
#
# EPOCHREALTIME format is "sec.frac" — frac has variable digit count
# depending on platform/load. Naive `${EPOCHREALTIME/./}:0:13` assumes
# 6 microsecond digits and silently returns a ~10× small value when
# frac is shorter, producing negative durations downstream.
_now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local _sec="${EPOCHREALTIME%.*}"
        local _frac="${EPOCHREALTIME#*.}"
        printf -v _frac '%-6s' "$_frac"
        _frac="${_frac// /0}"
        echo $(( _sec * 1000 + 10#${_frac:0:3} ))
    else
        date +%s%3N
    fi
}

# ============================================================
# _strip_inert_content COMMAND
# ============================================================
# Returns the "command skeleton" of COMMAND — content that bash would treat as
# data rather than executable tokens is blanked to a single space so downstream
# regexes can still match whitespace boundaries without matching inert text.
#
# Strips (in order):
#   1. Heredoc bodies: <<[-]?['\"]?TAG...TAG (tag may be quoted, e.g. <<'EOF')
#      The entire body between the opening line and the closing tag becomes
#      one space. Closing tag matches bash rules: at start of a line, alone.
#   2. Single-quoted strings: '...'  (no escapes inside single quotes in bash)
#   3. Double-quoted strings: "..."  (handles escaped \" inside)
#
# Why: both secrets-guard and enforce-uv-run match regexes against the raw
# $COMMAND string. Commit messages and heredoc bodies routinely contain
# tokens like `python` or `.env.local` that trip the guards even though no
# command is actually being run on them. Stripping inert content fixes the
# false positives without rewriting every regex.
#
# Heuristic limits: doesn't handle nested/escaped edge cases perfectly. Good
# enough for a guard meant to catch obvious mistakes, not adversaries.
#
# Usage:
#   stripped=$(_strip_inert_content "$COMMAND")
#   [[ "$stripped" =~ $SOME_RE ]]
_strip_inert_content() {
    local cmd="$1"
    local out=""
    local line rest tag body
    # --- Pass 1: strip heredocs line-by-line ---
    # A heredoc starts with <<[-]?TAG on some line; body runs until a line
    # that is exactly TAG (with optional leading tabs if <<- was used).
    while IFS= read -r line || [ -n "$line" ]; do
        # Detect heredoc opener: <<[-]?['"]?TAG['"]?
        if [[ "$line" =~ \<\<(-?)([\'\"]?)([A-Za-z_][A-Za-z0-9_]*)([\'\"]?) ]]; then
            local dash="${BASH_REMATCH[1]}"
            tag="${BASH_REMATCH[3]}"
            # Emit the opener line with the heredoc marker replaced by a space
            # so regex anchors (\s, ^, etc.) still work at the boundary.
            local prefix="${line%%<<*}"
            out+="${prefix} "$'\n'
            # Consume body until closing tag
            while IFS= read -r body || [ -n "$body" ]; do
                local check="$body"
                # With <<- bash strips leading tabs from the closing tag
                [ -n "$dash" ] && check="${check#"${check%%[! 	]*}"}"
                if [ "$check" = "$tag" ]; then
                    break
                fi
            done
            continue
        fi
        out+="${line}"$'\n'
    done <<< "$cmd"
    # --- Pass 2: strip quoted strings ---
    # Walk char-by-char tracking quote state. Blank out content inside
    # '...' and "..." (preserving the quote chars so boundaries remain).
    local i ch state=""
    local result=""
    local len=${#out}
    for (( i=0; i<len; i++ )); do
        ch="${out:i:1}"
        if [ -z "$state" ]; then
            if [ "$ch" = "'" ] || [ "$ch" = '"' ]; then
                state="$ch"
                result+=" "
                continue
            fi
            result+="$ch"
        else
            # In a quoted string: blank content, watch for closer.
            # Double-quote honors backslash escape; single-quote does not.
            if [ "$state" = '"' ] && [ "$ch" = '\' ] && [ $((i+1)) -lt $len ]; then
                i=$((i+1))
                continue
            fi
            if [ "$ch" = "$state" ]; then
                state=""
                result+=" "
                continue
            fi
            # Content inside quotes — drop
        fi
    done
    echo "$result"
}

# ============================================================
# hook_init HOOK_NAME HOOK_EVENT
# ============================================================
hook_init() {
    HOOK_NAME="$1"
    HOOK_EVENT="$2"
    HOOK_INPUT=$(cat)
    # shellcheck disable=SC2034  # INPUT is read by sourcing hooks/scripts (statusline-capture.sh, tests)
    INPUT="$HOOK_INPUT"
    INVOCATION_ID="$$-${EPOCHSECONDS:-$(date +%s)}"
    PROJECT="$(basename "$PWD")"
    # Capture timestamp once, reuse in all logging.
    # Millisecond precision — multiple hook rows within a single turn land in
    # the same second, and ms lets us order them chronologically.
    _HOOK_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    HOOK_START_MS=$(_now_ms)
    OUTCOME="pass"
    BYTES_INJECTED=0
    TOTAL_BYTES_INJECTED=0

    # Validate stdin is parseable JSON — malformed input means nothing
    # downstream is reliable (tool_name, session_id, tool_input).
    if ! echo "$HOOK_INPUT" | jq empty 2>/dev/null; then
        OUTCOME="error"
        SESSION_ID="unknown"
        case "$HOOK_EVENT" in
            PreToolUse)
                # Safety hooks must fail-closed: block rather than silently pass
                _HOOK_ACTIVE=true
                trap '_hook_log_timing' EXIT
                hook_block "hook $HOOK_NAME received malformed stdin — blocking as safety precaution"
                ;;
            SessionStart)
                echo "Warning: $HOOK_NAME received malformed stdin — hook output may be incomplete" >&2
                ;;
            # PermissionRequest: exit 0 → user gets normal permission prompt (fail-open)
        esac
        # For non-PreToolUse events, continue with best effort
    fi

    SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

    local _tid _aid
    _tid=$(echo "$HOOK_INPUT" | jq -r '.tool_use_id // ""' 2>/dev/null)
    _aid=$(echo "$HOOK_INPUT" | jq -r '.agent_id // ""' 2>/dev/null)
    if [ -n "$_tid" ]; then
        CALL_ID="$_tid"
    elif [ -n "$_aid" ]; then
        CALL_ID="$_aid"
    else
        CALL_ID=""
    fi

    # SessionStart hooks don't call hook_require_tool, so mark active immediately
    if [ "$HOOK_EVENT" = "SessionStart" ]; then
        _HOOK_ACTIVE=true
        HOOK_SOURCE=$(echo "$HOOK_INPUT" | jq -r '.source // ""' 2>/dev/null || echo "")
    fi
    trap '_hook_log_timing' EXIT
}

# ============================================================
# _hook_perf_probe PHASE_NAME
# ============================================================
# Emits "HOOK_PERF\t<phase>\t<delta_ms>" to stderr when HOOK_PERF=1.
# Delta = time since last probe (or since HOOK_START_MS for first call).
# No-op when unset — zero overhead (short-circuit on first test).
_HOOK_PERF_LAST_MS=0
_hook_perf_probe() {
    [ "${HOOK_PERF:-}" = "1" ] || return 0
    local now_ms
    now_ms=$(_now_ms)
    local prev="${_HOOK_PERF_LAST_MS:-$HOOK_START_MS}"
    [ "$prev" -eq 0 ] && prev="$HOOK_START_MS"
    local delta=$(( now_ms - prev ))
    _HOOK_PERF_LAST_MS="$now_ms"
    printf 'HOOK_PERF\t%s\t%d\n' "$1" "$delta" >&2
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
    if [ "$HOOK_EVENT" = "PermissionRequest" ]; then
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}"
    else
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"permissionDecision\":\"allow\",\"permissionDecisionReason\":\"$reason\"}}"
    fi
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
    local bytes=${#content}
    TOTAL_BYTES_INJECTED=$(( TOTAL_BYTES_INJECTED + bytes ))
    _hook_log_db "INSERT INTO hook_logs (session_id, invocation_id, timestamp, project, hook_event, hook_name, tool_name, section, duration_ms, outcome, bytes_injected, source, call_id)
    VALUES ('$SESSION_ID', '$INVOCATION_ID', '$_HOOK_TIMESTAMP', '$(_sql_escape "$PROJECT")', '$HOOK_EVENT', '$HOOK_NAME', '$(_sql_escape "$TOOL_NAME")', '$(_sql_escape "$section")', 0, 'pass', $bytes, '$(_sql_escape "$HOOK_SOURCE")', '$(_sql_escape "$CALL_ID")');"
}

# ============================================================
# hook_log_substep NAME DURATION_MS OUTCOME [BYTES_INJECTED]
# ============================================================
# Records one sub-step row for grouped hooks (e.g. grouped-bash-guard).
# OUTCOME: pass | block | approve | inject | skipped | not_applicable
#   - skipped: predecessor blocked, this check didn't run (duration 0)
#   - not_applicable: match_ predicate returned false, check body skipped
#     by design (duration = predicate cost)
# See .claude/docs/relevant-toolkit-hooks.md §5 for full outcome semantics.
hook_log_substep() {
    local name="$1"
    local duration_ms="$2"
    local outcome="$3"
    local bytes="${4:-0}"
    if [ "$outcome" = "inject" ] 2>/dev/null; then
        TOTAL_BYTES_INJECTED=$(( TOTAL_BYTES_INJECTED + bytes ))
    fi
    _hook_log_db "INSERT INTO hook_logs (session_id, invocation_id, timestamp, project, hook_event, hook_name, tool_name, section, duration_ms, outcome, bytes_injected, source, call_id)
    VALUES ('$SESSION_ID', '$INVOCATION_ID', '$_HOOK_TIMESTAMP', '$(_sql_escape "$PROJECT")', '$HOOK_EVENT', '$HOOK_NAME', '$(_sql_escape "$TOOL_NAME")', '$(_sql_escape "$name")', $duration_ms, '$(_sql_escape "$outcome")', $bytes, '$(_sql_escape "$HOOK_SOURCE")', '$(_sql_escape "$CALL_ID")');"
}

# ============================================================
# _sql_escape VALUE  (internal — escape single quotes for SQL)
# ============================================================
_sql_escape() {
    printf '%s' "${1//\'/\'\'}"
}

# ============================================================
# _hook_log_db SQL  (internal — insert into claude-hook-logs.db)
# ============================================================
_hook_log_db() {
    [ -f "$HOOK_LOG_DB" ] || return 0
    _HOOK_SQL_BATCH="${_HOOK_SQL_BATCH}${1}
"
}

# Flush all accumulated SQL in one sqlite3 call
_hook_flush_db() {
    [ -f "$HOOK_LOG_DB" ] || return 0
    [ -z "$_HOOK_SQL_BATCH" ] && return 0
    printf '%s' "$_HOOK_SQL_BATCH" | sqlite3 "$HOOK_LOG_DB" 2>/dev/null || true
    _HOOK_SQL_BATCH=""
}

# ============================================================
# hook_log_context RAW_CONTEXT KEYWORDS MATCH_COUNT MATCHED_IDS
# ============================================================
hook_log_context() {
    local raw_context="$1"
    local keywords="$2"
    local match_count="$3"
    local matched_ids="$4"
    _hook_log_db "INSERT INTO surface_lessons_context (session_id, invocation_id, timestamp, project, tool_name, raw_context, keywords, match_count, matched_lesson_ids)
    VALUES ('$SESSION_ID', '$INVOCATION_ID', '$_HOOK_TIMESTAMP', '$(_sql_escape "$PROJECT")', '$(_sql_escape "$TOOL_NAME")', '$(_sql_escape "$raw_context")', '$(_sql_escape "$keywords")', $match_count, '$matched_ids');"
}

# ============================================================
# _hook_log_timing  (internal — EXIT trap)
# ============================================================
_hook_log_timing() {
    # Emit HOOK_PERF TOTAL before the _HOOK_ACTIVE guard — perf timing
    # is orthogonal to hook logging and should cover early exits too.
    if [ "${HOOK_PERF:-}" = "1" ]; then
        local _perf_end_ms
        _perf_end_ms=$(_now_ms)
        printf 'HOOK_PERF\tTOTAL\t%d\n' "$(( _perf_end_ms - HOOK_START_MS ))" >&2
    fi
    # Skip logging if hook never matched a tool (early exit from hook_require_tool)
    [ "$_HOOK_ACTIVE" = true ] || return 0
    local end_ms ts
    end_ms=$(_now_ms)
    ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    local duration_ms=$(( end_ms - HOOK_START_MS ))
    local bytes=$BYTES_INJECTED
    if [ "$TOTAL_BYTES_INJECTED" -gt 0 ] 2>/dev/null; then
        bytes=$TOTAL_BYTES_INJECTED
    fi
    _hook_log_db "INSERT INTO hook_logs (session_id, invocation_id, timestamp, project, hook_event, hook_name, tool_name, section, duration_ms, outcome, bytes_injected, source, call_id)
    VALUES ('$SESSION_ID', '$INVOCATION_ID', '$ts', '$(_sql_escape "$PROJECT")', '$HOOK_EVENT', '$HOOK_NAME', '$(_sql_escape "$TOOL_NAME")', '', $duration_ms, '$OUTCOME', $bytes, '$(_sql_escape "$HOOK_SOURCE")', '$(_sql_escape "$CALL_ID")');"
    _hook_flush_db
}
