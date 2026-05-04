#!/usr/bin/env bash
# Shared JSON fixture builders for hook tests.
#
# One helper per hook event. PreToolUse dispatches on tool name to shape
# tool_input. All helpers emit single-line JSON to stdout, built with
# `jq -n --arg` so embedded quotes/backticks/newlines/$()/heredocs are
# escaped correctly. See tests/CLAUDE.md for the rationale.

# PreToolUse: shapes tool_input by tool. Default session_id="test".
# permission_mode is only included when explicitly passed.
#
# Bash:  mk_pre_tool_use_payload Bash  <command>          [permission_mode] [session_id]
# Read:  mk_pre_tool_use_payload Read  <file_path>        [session_id]
# Write: mk_pre_tool_use_payload Write <file_path> <content> [permission_mode] [session_id]
# Edit:  mk_pre_tool_use_payload Edit  <file_path> <old> <new> [permission_mode] [session_id]
mk_pre_tool_use_payload() {
    local tool="$1"; shift
    case "$tool" in
        Bash)
            local cmd="$1" pm="${2-}" sid="${3-test}"
            if [ -n "$pm" ]; then
                jq -nc --arg c "$cmd" --arg m "$pm" --arg s "$sid" \
                    '{tool_name:"Bash",tool_input:{command:$c},permission_mode:$m,session_id:$s}'
            else
                jq -nc --arg c "$cmd" --arg s "$sid" \
                    '{tool_name:"Bash",tool_input:{command:$c},session_id:$s}'
            fi
            ;;
        Read)
            local path="$1" sid="${2-test}"
            jq -nc --arg p "$path" --arg s "$sid" \
                '{tool_name:"Read",tool_input:{file_path:$p},session_id:$s}'
            ;;
        Write)
            local path="$1" content="$2" pm="${3-}" sid="${4-test}"
            if [ -n "$pm" ]; then
                jq -nc --arg p "$path" --arg c "$content" --arg m "$pm" --arg s "$sid" \
                    '{tool_name:"Write",tool_input:{file_path:$p,content:$c},permission_mode:$m,session_id:$s}'
            else
                jq -nc --arg p "$path" --arg c "$content" --arg s "$sid" \
                    '{tool_name:"Write",tool_input:{file_path:$p,content:$c},session_id:$s}'
            fi
            ;;
        Edit)
            local path="$1" old="$2" new="$3" pm="${4-}" sid="${5-test}"
            if [ -n "$pm" ]; then
                jq -nc --arg p "$path" --arg o "$old" --arg n "$new" --arg m "$pm" --arg s "$sid" \
                    '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n},permission_mode:$m,session_id:$s}'
            else
                jq -nc --arg p "$path" --arg o "$old" --arg n "$new" --arg s "$sid" \
                    '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n},session_id:$s}'
            fi
            ;;
        *)
            echo "mk_pre_tool_use_payload: unknown tool '$tool'" >&2
            return 2
            ;;
    esac
}

# PostToolUse: all 7 args required; pass empty strings for fields you
# don't care about. tool_input/tool_response are passed as JSON strings
# (already-typed sub-objects in callers).
mk_post_tool_use_payload() {
    local sid="$1" tool="$2" input_json="$3" response_json="$4" tuid="$5" dur="$6" cwd="$7"
    jq -nc \
        --arg s "$sid" \
        --arg t "$tool" \
        --argjson i "$input_json" \
        --argjson r "$response_json" \
        --arg u "$tuid" \
        --argjson d "$dur" \
        --arg c "$cwd" \
        '{session_id:$s,tool_name:$t,tool_input:$i,tool_response:$r,tool_use_id:$u,duration_ms:$d,hook_event_name:"PostToolUse",cwd:$c}'
}

# SessionStart. source only included when passed (non-empty).
# Default session_id="test".
mk_session_start_payload() {
    local source="${1-}" sid="${2-test}"
    if [ -n "$source" ]; then
        jq -nc --arg src "$source" --arg s "$sid" \
            '{hook_event_name:"SessionStart",source:$src,session_id:$s}'
    else
        jq -nc --arg s "$sid" \
            '{hook_event_name:"SessionStart",session_id:$s}'
    fi
}

# PermissionDenied. cwd defaults to /tmp (matches existing fixtures).
# tool_input passed as JSON string.
mk_permission_denied_payload() {
    local sid="$1" tool="$2" input_json="$3" tuid="$4" pm="$5" cwd="${6-/tmp}"
    jq -nc \
        --arg s "$sid" \
        --arg t "$tool" \
        --argjson i "$input_json" \
        --arg u "$tuid" \
        --arg m "$pm" \
        --arg c "$cwd" \
        '{session_id:$s,tool_name:$t,tool_input:$i,tool_use_id:$u,permission_mode:$m,hook_event_name:"PermissionDenied",cwd:$c}'
}

# UserPromptSubmit. cwd defaults to current directory.
mk_user_prompt_submit_payload() {
    local sid="$1" prompt="$2" cwd="${3-$(pwd)}"
    jq -nc --arg s "$sid" --arg p "$prompt" --arg c "$cwd" \
        '{session_id:$s,hook_event_name:"UserPromptSubmit",prompt:$p,cwd:$c}'
}
