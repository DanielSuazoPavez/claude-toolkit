#!/usr/bin/env bash
# JSONL row emission for hook traceability.
#
# Extracted from hook-utils.sh as part of the hook framework refactor (C3,
# sequencing item 1). Do not source this file directly — source hook-utils.sh,
# which sources this file and sets the globals these functions read
# (SESSION_ID, INVOCATION_ID, PROJECT, _HOOK_TIMESTAMP, HOOK_LOG_DIR, OUTCOME,
# BYTES_INJECTED, TOTAL_BYTES_INJECTED, HOOK_SOURCE, HOOK_NAME, HOOK_EVENT,
# TOOL_NAME, CALL_ID, HOOK_INPUT, HOOK_START_MS, _HOOK_ACTIVE,
# _HOOK_INPUT_VALID).

# Idempotency guard: safe to source multiple times. Functions are stateless;
# the guard avoids re-defining them when the dispatcher and a sourced hook
# both pull in hook-utils.sh.
if [ -n "${_HOOK_LOGGING_SOURCED:-}" ]; then
    return 0
fi
_HOOK_LOGGING_SOURCED=1

# ============================================================
# _hook_log_jsonl FILENAME JSON_LINE  (internal — append one JSON line)
# ============================================================
# Gated on traceability. Lazy-creates HOOK_LOG_DIR on first write.
# Each call appends one line; for typical row sizes (< PIPE_BUF / 4KB on
# Linux) a single >> append is atomic. The EXIT-trap row may be larger
# when stdin is embedded; concurrent writers are rare here (one hook
# process per invocation), so interleaving risk is negligible in practice.
_hook_log_jsonl() {
    hook_feature_enabled traceability || return 0
    local file="$1"
    local line="$2"
    mkdir -p "$HOOK_LOG_DIR" 2>/dev/null || return 0
    printf '%s\n' "$line" >> "$HOOK_LOG_DIR/$file" 2>/dev/null || true
}

# Sibling writer for the smoketest branch. Bypasses the traceability gate —
# smoke fixtures need a row regardless of feature flags. Lazy-creates the
# log dir like _hook_log_jsonl does.
_hook_log_jsonl_unguarded() {
    local file="$1"
    local line="$2"
    mkdir -p "$HOOK_LOG_DIR" 2>/dev/null || return 0
    printf '%s\n' "$line" >> "$HOOK_LOG_DIR/$file" 2>/dev/null || true
}

# ============================================================
# hook_log_section SECTION_NAME CONTENT
# ============================================================
hook_log_section() {
    local section="$1"
    local content="$2"
    local bytes=${#content}
    TOTAL_BYTES_INJECTED=$(( TOTAL_BYTES_INJECTED + bytes ))
    hook_feature_enabled traceability || return 0
    _ensure_project
    local line
    line=$(jq -c -n \
        --arg kind "section" \
        --arg session_id "$SESSION_ID" \
        --arg invocation_id "$INVOCATION_ID" \
        --arg timestamp "$_HOOK_TIMESTAMP" \
        --arg project "$PROJECT" \
        --arg hook_event "$HOOK_EVENT" \
        --arg hook_name "$HOOK_NAME" \
        --arg tool_name "$TOOL_NAME" \
        --arg section "$section" \
        --argjson bytes_injected "$bytes" \
        --arg source "$HOOK_SOURCE" \
        --arg call_id "$CALL_ID" \
        '{kind:$kind, session_id:$session_id, invocation_id:$invocation_id, timestamp:$timestamp, project:$project, hook_event:$hook_event, hook_name:$hook_name, tool_name:$tool_name, section:$section, duration_ms:0, outcome:"pass", bytes_injected:$bytes_injected, source:$source, call_id:$call_id}' \
        2>/dev/null) || return 0
    _hook_log_jsonl "invocations.jsonl" "$line"
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
    hook_feature_enabled traceability || return 0
    _ensure_project
    local line
    line=$(jq -c -n \
        --arg kind "substep" \
        --arg session_id "$SESSION_ID" \
        --arg invocation_id "$INVOCATION_ID" \
        --arg timestamp "$_HOOK_TIMESTAMP" \
        --arg project "$PROJECT" \
        --arg hook_event "$HOOK_EVENT" \
        --arg hook_name "$HOOK_NAME" \
        --arg tool_name "$TOOL_NAME" \
        --arg section "$name" \
        --argjson duration_ms "$duration_ms" \
        --arg outcome "$outcome" \
        --argjson bytes_injected "$bytes" \
        --arg source "$HOOK_SOURCE" \
        --arg call_id "$CALL_ID" \
        '{kind:$kind, session_id:$session_id, invocation_id:$invocation_id, timestamp:$timestamp, project:$project, hook_event:$hook_event, hook_name:$hook_name, tool_name:$tool_name, section:$section, duration_ms:$duration_ms, outcome:$outcome, bytes_injected:$bytes_injected, source:$source, call_id:$call_id}' \
        2>/dev/null) || return 0
    _hook_log_jsonl "invocations.jsonl" "$line"
}

# ============================================================
# hook_log_context RAW_CONTEXT KEYWORDS MATCH_COUNT MATCHED_IDS
# ============================================================
hook_log_context() {
    local raw_context="$1"
    local keywords="$2"
    local match_count="$3"
    local matched_ids="$4"
    hook_feature_enabled traceability || return 0
    _ensure_project
    # Defensive: --argjson requires a clean integer; strip whitespace and
    # default to 0 if upstream produced anything weird.
    match_count="${match_count//[[:space:]]/}"
    [[ "$match_count" =~ ^[0-9]+$ ]] || match_count=0
    local line
    line=$(jq -c -n \
        --arg kind "context" \
        --arg session_id "$SESSION_ID" \
        --arg invocation_id "$INVOCATION_ID" \
        --arg timestamp "$_HOOK_TIMESTAMP" \
        --arg project "$PROJECT" \
        --arg hook_name "$HOOK_NAME" \
        --arg tool_name "$TOOL_NAME" \
        --arg raw_context "$raw_context" \
        --arg keywords "$keywords" \
        --argjson match_count "$match_count" \
        --arg matched_lesson_ids "$matched_ids" \
        '{kind:$kind, session_id:$session_id, invocation_id:$invocation_id, timestamp:$timestamp, project:$project, hook_name:$hook_name, tool_name:$tool_name, raw_context:$raw_context, keywords:$keywords, match_count:$match_count, matched_lesson_ids:$matched_lesson_ids}' \
        2>/dev/null) || return 0
    _hook_log_jsonl "surface-lessons-context.jsonl" "$line"
}

# ============================================================
# hook_log_session_start_context GIT_BRANCH MAIN_BRANCH CWD
# ============================================================
# Records the structured git/cwd payload observed at each session-start hook
# firing (startup / resume / clear / compact). Consumed by the sessions
# projector to seed state_changes baselines with the real starting branch
# instead of emitting from_value=NULL on first observation.
hook_log_session_start_context() {
    local git_branch="$1"
    local main_branch="$2"
    local cwd="$3"
    hook_feature_enabled traceability || return 0
    _ensure_project
    local line
    line=$(jq -c -n \
        --arg kind "session_start_context" \
        --arg session_id "$SESSION_ID" \
        --arg invocation_id "$INVOCATION_ID" \
        --arg timestamp "$_HOOK_TIMESTAMP" \
        --arg project "$PROJECT" \
        --arg hook_name "$HOOK_NAME" \
        --arg source "$HOOK_SOURCE" \
        --arg git_branch "$git_branch" \
        --arg main_branch "$main_branch" \
        --arg cwd "$cwd" \
        '{kind:$kind, session_id:$session_id, invocation_id:$invocation_id, timestamp:$timestamp, project:$project, hook_name:$hook_name, source:$source, git_branch:$git_branch, main_branch:$main_branch, cwd:$cwd}' \
        2>/dev/null) || return 0
    _hook_log_jsonl "session-start-context.jsonl" "$line"
}

# ============================================================
# _hook_log_timing  (internal — EXIT trap)
# ============================================================
# Emits one `kind: invocation` row per hook firing with the full stdin
# payload attached. Stdin is embedded as a parsed object when valid JSON
# (the common path) or as a raw string fallback when hook_init flagged
# the input as unparseable.
# ============================================================
# _hook_log_smoketest  (internal — emits one kind:smoketest row)
# ============================================================
# Called from _hook_log_timing when CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1.
# Writes to smoketest.jsonl (separate from invocations.jsonl) so analytics
# consumers reading invocations.jsonl never see test rows.
_hook_log_smoketest() {
    local end_ms ts duration_ms
    end_ms=$(_now_ms)
    ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    duration_ms=$(( end_ms - HOOK_START_MS ))
    local fixture="${CLAUDE_TOOLKIT_HOOK_FIXTURE:-}"
    local line
    line=$(jq -c -n \
        --arg kind "smoketest" \
        --arg session_id "smoketest" \
        --arg invocation_id "smoketest-${HOOK_NAME}-${fixture}" \
        --arg timestamp "$ts" \
        --arg project "(test)" \
        --arg hook_event "$HOOK_EVENT" \
        --arg hook_name "$HOOK_NAME" \
        --arg tool_name "${TOOL_NAME:-}" \
        --argjson duration_ms "$duration_ms" \
        --arg outcome "$OUTCOME" \
        --argjson bytes_injected "${BYTES_INJECTED:-0}" \
        --arg decision_json "${_HOOK_RECORDED_DECISION:-}" \
        --arg fixture "$fixture" \
        '{kind:$kind, session_id:$session_id, invocation_id:$invocation_id, timestamp:$timestamp, project:$project, hook_event:$hook_event, hook_name:$hook_name, tool_name:$tool_name, duration_ms:$duration_ms, outcome:$outcome, bytes_injected:$bytes_injected, decision_json:$decision_json, fixture:$fixture}' \
        2>/dev/null) || return 0
    _hook_log_jsonl_unguarded "smoketest.jsonl" "$line"
}

_hook_log_timing() {
    # Emit HOOK_PERF TOTAL before the _HOOK_ACTIVE guard — perf timing
    # is orthogonal to hook logging and should cover early exits too.
    if [ "${CLAUDE_TOOLKIT_HOOK_PERF:-}" = "1" ]; then
        local _perf_end_ms
        _perf_end_ms=$(_now_ms)
        printf 'HOOK_PERF\tTOTAL\t%d\n' "$(( _perf_end_ms - HOOK_START_MS ))" >&2
    fi
    # Smoketest branch — fires regardless of _HOOK_ACTIVE and traceability so
    # fixtures that early-exit via hook_require_tool still emit a row.
    if [ "${CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT:-}" = "1" ]; then
        _hook_log_smoketest
        return 0
    fi
    # Skip logging if hook never matched a tool (early exit from hook_require_tool)
    [ "$_HOOK_ACTIVE" = true ] || return 0
    hook_feature_enabled traceability || return 0
    _ensure_project
    local end_ms ts
    end_ms=$(_now_ms)
    ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    local duration_ms=$(( end_ms - HOOK_START_MS ))
    local bytes=$BYTES_INJECTED
    if [ "$TOTAL_BYTES_INJECTED" -gt 0 ] 2>/dev/null; then
        bytes=$TOTAL_BYTES_INJECTED
    fi
    local line
    if [ "$_HOOK_INPUT_VALID" = true ]; then
        line=$(printf '%s' "$HOOK_INPUT" | jq -c \
            --arg kind "invocation" \
            --arg session_id "$SESSION_ID" \
            --arg invocation_id "$INVOCATION_ID" \
            --arg timestamp "$ts" \
            --arg project "$PROJECT" \
            --arg hook_event "$HOOK_EVENT" \
            --arg hook_name "$HOOK_NAME" \
            --arg tool_name "$TOOL_NAME" \
            --argjson duration_ms "$duration_ms" \
            --arg outcome "$OUTCOME" \
            --argjson bytes_injected "$bytes" \
            --arg source "$HOOK_SOURCE" \
            --arg call_id "$CALL_ID" \
            '{kind:$kind, session_id:$session_id, invocation_id:$invocation_id, timestamp:$timestamp, project:$project, hook_event:$hook_event, hook_name:$hook_name, tool_name:$tool_name, section:"", duration_ms:$duration_ms, outcome:$outcome, bytes_injected:$bytes_injected, source:$source, call_id:$call_id, stdin:.}' \
            2>/dev/null) || return 0
    else
        line=$(jq -c -n \
            --arg kind "invocation" \
            --arg session_id "$SESSION_ID" \
            --arg invocation_id "$INVOCATION_ID" \
            --arg timestamp "$ts" \
            --arg project "$PROJECT" \
            --arg hook_event "$HOOK_EVENT" \
            --arg hook_name "$HOOK_NAME" \
            --arg tool_name "$TOOL_NAME" \
            --argjson duration_ms "$duration_ms" \
            --arg outcome "$OUTCOME" \
            --argjson bytes_injected "$bytes" \
            --arg source "$HOOK_SOURCE" \
            --arg call_id "$CALL_ID" \
            --arg stdin_raw "$HOOK_INPUT" \
            '{kind:$kind, session_id:$session_id, invocation_id:$invocation_id, timestamp:$timestamp, project:$project, hook_event:$hook_event, hook_name:$hook_name, tool_name:$tool_name, section:"", duration_ms:$duration_ms, outcome:$outcome, bytes_injected:$bytes_injected, source:$source, call_id:$call_id, stdin_raw:$stdin_raw}' \
            2>/dev/null) || return 0
    fi
    _hook_log_jsonl "invocations.jsonl" "$line"
}
