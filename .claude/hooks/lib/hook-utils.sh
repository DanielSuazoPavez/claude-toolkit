#!/usr/bin/env bash
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
# Logs execution data as JSONL under $HOOK_LOG_DIR. Silently skipped when
# traceability is disabled.
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
# shellcheck disable=SC2034  # _HOOK_RECORDED_DECISION read in hook-logging.sh smoketest branch
_HOOK_RECORDED_DECISION=""
# shellcheck disable=SC2034  # HOOK_LOG_DIR read in hook-logging.sh
HOOK_LOG_DIR="${CLAUDE_ANALYTICS_HOOKS_DIR:-$HOME/claude-analytics/hook-logs}"
_HOOK_ACTIVE=false  # true once hook_require_tool matches (or for SessionStart)
_HOOK_INPUT_VALID=true  # false when stdin failed jq empty in hook_init

# Logging functions (hook_log_*, _hook_log_jsonl, _hook_log_timing) live in
# the sibling lib so the framework refactor can evolve the JSONL row shape
# (smoketest kind, decision capture) without churning init/decision callers.
# Sourced after globals so logging functions see them in scope. Many globals
# above are read only by hook-logging.sh — shellcheck can't see across the
# source boundary, hence the SC2034 disables at re-assignment sites below.
source "$(dirname "${BASH_SOURCE[0]}")/hook-logging.sh"

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
# _resolve_project_id
# ============================================================
# Resolve canonical project_id for the current $PWD via sessions.db.project_paths.
# When sessions.db is absent, fall back to basename (standalone deployment).
# When sessions.db is present but the encoded dir isn't registered, emit one
# stderr notice and return empty — soft failure so hooks don't crash sessions.
# An empty PROJECT means project-scoped scope filters won't match (global
# lessons still surface).
_resolve_project_id() {
    local sessions_db="${CLAUDE_ANALYTICS_SESSIONS_DB:-$HOME/.claude/sessions.db}"
    if [ ! -f "$sessions_db" ]; then
        basename "$PWD"
        return
    fi
    local encoded="-${PWD#/}"
    encoded="${encoded//\//-}"
    local pid
    pid=$(sqlite3 "file:${sessions_db}?mode=ro" \
        "SELECT project_id FROM project_paths WHERE dir_name = '${encoded//\'/\'\'}';" \
        2>/dev/null)
    if [ -n "$pid" ]; then
        printf '%s' "$pid"
        return
    fi
    echo "hook: project not registered in sessions.db.project_paths (dir_name=${encoded}); project-scoped lessons won't match" >&2
    printf ''
}

# ============================================================
# hook_init HOOK_NAME HOOK_EVENT
# ============================================================
hook_init() {
    HOOK_NAME="$1"
    HOOK_EVENT="$2"
    
    # Skip stdin read when invoked from a TTY (manual debugging) — otherwise `cat` blocks forever.
    if [[ -t 0 ]]; then
        HOOK_INPUT=""
    else
        HOOK_INPUT=$(cat)
    fi
    # shellcheck disable=SC2034  # INPUT is read by sourcing hooks/scripts (statusline-capture.sh, tests)
    INPUT="$HOOK_INPUT"
    # shellcheck disable=SC2034  # INVOCATION_ID/PROJECT/OUTCOME/*BYTES_INJECTED read in hook-logging.sh
    INVOCATION_ID="$$-${EPOCHSECONDS:-$(date +%s)}"
    # shellcheck disable=SC2034
    PROJECT="$(_resolve_project_id)"
    # Capture timestamp once, reuse in all logging.
    # Millisecond precision — multiple hook rows within a single turn land in
    # the same second, and ms lets us order them chronologically.
    _HOOK_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    HOOK_START_MS=$(_now_ms)
    # shellcheck disable=SC2034
    OUTCOME="pass"
    # shellcheck disable=SC2034
    BYTES_INJECTED=0
    # shellcheck disable=SC2034
    TOTAL_BYTES_INJECTED=0

    # Single jq invocation extracts all stdin fields hooks care about, joined
    # by SOH (\x01) — a control byte that cannot appear in legitimate values.
    # Replaces 4-5 separate forks (validate + session_id + tool_use_id +
    # agent_id + source). Validation is implicit: jq exit != 0 means malformed.
    local _hook_init_rc _hook_init_line _tid _aid
    _hook_init_line=$(printf '%s' "$HOOK_INPUT" | jq -r '
        (.session_id // "unknown") + "" +
        (.tool_use_id // "") + "" +
        (.agent_id // "") + "" +
        (.source // "") + "" +
        (.tool_name // "")
    ' 2>/dev/null)
    _hook_init_rc=$?
    # shellcheck disable=SC2034  # SESSION_ID/HOOK_SOURCE read in hook-logging.sh; _HOOK_INIT_TOOL_NAME used by hook_require_tool
    IFS=$'\x01' read -r SESSION_ID _tid _aid HOOK_SOURCE _HOOK_INIT_TOOL_NAME <<<"$_hook_init_line"
    : "${SESSION_ID:=unknown}"

    if [ "$_hook_init_rc" -ne 0 ]; then
        OUTCOME="error"
        SESSION_ID="unknown"
        _HOOK_INPUT_VALID=false
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

    # shellcheck disable=SC2034  # CALL_ID read in hook-logging.sh
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
    fi
    trap '_hook_log_timing' EXIT
}

# ============================================================
# _hook_perf_probe PHASE_NAME
# ============================================================
# Emits "HOOK_PERF\t<phase>\t<delta_ms>" to stderr when CLAUDE_TOOLKIT_HOOK_PERF=1.
# Delta = time since last probe (or since HOOK_START_MS for first call).
# No-op when unset — zero overhead (short-circuit on first test).
_HOOK_PERF_LAST_MS=0
_hook_perf_probe() {
    [ "${CLAUDE_TOOLKIT_HOOK_PERF:-}" = "1" ] || return 0
    local now_ms
    now_ms=$(_now_ms)
    local prev="${_HOOK_PERF_LAST_MS:-$HOOK_START_MS}"
    [ "$prev" -eq 0 ] && prev="$HOOK_START_MS"
    local delta=$(( now_ms - prev ))
    _HOOK_PERF_LAST_MS="$now_ms"
    printf 'HOOK_PERF\t%s\t%d\n' "$1" "$delta" >&2
}

# ============================================================
# hook_extract_quick_reference FILE_PATH
# ============================================================
# Emits the "## 1. Quick Reference" block (heading included) up to the next
# top-level "## " heading or "---" rule. Empty output if file missing or block
# absent. No stderr noise — caller decides fallback.
hook_extract_quick_reference() {
    local file="$1"
    [ -f "$file" ] || return 0
    awk '
        /^## 1\. Quick Reference/ { in_qr=1; print; next }
        in_qr && /^---[[:space:]]*$/ { exit }
        in_qr && /^## [0-9]/ { exit }
        in_qr { print }
    ' "$file"
}

# ============================================================
# hook_feature_enabled FEATURE
# ============================================================
# Ecosystems are opt-in per project via env vars set in settings.json:
#   CLAUDE_TOOLKIT_LESSONS=1       enables lessons (surface-lessons, session-start lessons, /learn, /manage-lessons)
#   CLAUDE_TOOLKIT_TRACEABILITY=1  enables hooks.db logging + usage-snapshots capture
# Unset or any value other than "1" → disabled. Callers should early-return.
hook_feature_enabled() {
    case "$1" in
        lessons)      [ "${CLAUDE_TOOLKIT_LESSONS:-0}" = "1" ] ;;
        traceability) [ "${CLAUDE_TOOLKIT_TRACEABILITY:-0}" = "1" ] ;;
        *) return 1 ;;
    esac
}

# ============================================================
# hook_require_tool TOOL1 [TOOL2 ...]
# ============================================================
hook_require_tool() {
    # tool_name was already extracted in hook_init via the consolidated jq call.
    TOOL_NAME="${_HOOK_INIT_TOOL_NAME:-}"
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
    local json="{\"decision\": \"block\", \"reason\": \"$reason\"}"
    if [ "${CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT:-}" = "1" ]; then
        _HOOK_RECORDED_DECISION="$json"
        exit 0
    fi
    echo "$json"
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
    local json
    if [ "$HOOK_EVENT" = "PermissionRequest" ]; then
        json="{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}"
    else
        json="{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"permissionDecision\":\"allow\",\"permissionDecisionReason\":\"$reason\"}}"
    fi
    if [ "${CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT:-}" = "1" ]; then
        _HOOK_RECORDED_DECISION="$json"
        exit 0
    fi
    echo "$json"
    exit 0
}

# ============================================================
# hook_ask REASON
# ============================================================
# Emits a PreToolUse permission-decision asking Claude Code to prompt the user.
# Use when a tool call should not be silently blocked (legitimate use exists)
# but also should not run without explicit user confirmation. Distinct from
# hook_block (no user prompt, hard refusal) and hook_approve (no prompt, allow).
hook_ask() {
    OUTCOME="asked"
    local reason="$1"
    reason="${reason//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    local json="{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"$reason\"}}"
    if [ "${CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT:-}" = "1" ]; then
        _HOOK_RECORDED_DECISION="$json"
        exit 0
    fi
    echo "$json"
    exit 0
}

# ============================================================
# hook_inject CONTEXT_STRING
# ============================================================
# CONTEXT_STRING must already be JSON-escaped by the caller.
hook_inject() {
    # shellcheck disable=SC2034  # OUTCOME/BYTES_INJECTED read in hook-logging.sh
    OUTCOME="injected"
    local context="$1"
    # shellcheck disable=SC2034
    BYTES_INJECTED=${#context}
    local json="{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"additionalContext\":\"$context\"}}"
    if [ "${CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT:-}" = "1" ]; then
        _HOOK_RECORDED_DECISION="$json"
        exit 0
    fi
    echo "$json"
    exit 0
}

