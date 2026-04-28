#!/usr/bin/env bash
#
# Backlog schema loader. Source from validate.sh, query.sh, and the schema
# subcommand. Provides a small set of jq-backed accessors over
# .claude/schemas/backlog/task.schema.json.
#
# Functions are prefixed bsl_ (BackLog Schema Loader) for grep-ability.
#
# Source contract: callers source this file and immediately call bsl_load_schema
# to set BSL_SCHEMA_PATH. If the schema is missing or malformed, bsl_load_schema
# prints a diagnostic to stderr and exits 1 — schema corruption is a hard
# failure, never a silent fallback.

# Resolve the schema path relative to this file's location so callers don't
# have to pass it. lib/schema.sh -> ../../../.claude/schemas/backlog/task.schema.json
_bsl_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BSL_SCHEMA_PATH="${BSL_SCHEMA_PATH:-${_bsl_dir}/../../../.claude/schemas/backlog/task.schema.json}"
unset _bsl_dir

bsl_load_schema() {
    if [[ ! -f "$BSL_SCHEMA_PATH" ]]; then
        echo "error: backlog schema not found at $BSL_SCHEMA_PATH" >&2
        return 1
    fi
    if ! jq -e . "$BSL_SCHEMA_PATH" >/dev/null 2>&1; then
        local jq_err
        jq_err=$(jq . "$BSL_SCHEMA_PATH" 2>&1 >/dev/null)
        echo "error: backlog schema malformed at $BSL_SCHEMA_PATH: $jq_err" >&2
        return 1
    fi
}

# bsl_field_names — one field name per line, in document order.
# Uses keys_unsorted to preserve schema-defined order (NOT alphabetical).
bsl_field_names() {
    jq -r '.properties | keys_unsorted[]' "$BSL_SCHEMA_PATH"
}

# bsl_status_values — one value per line, in enum order.
bsl_status_values() {
    jq -r '.properties.status.enum[]' "$BSL_SCHEMA_PATH"
}

# bsl_priority_values — one value per line, in enum order.
bsl_priority_values() {
    jq -r '.properties.priority.enum[]' "$BSL_SCHEMA_PATH"
}

# bsl_relates_to_kinds — one kind per line, document order.
# Extracts from the items.pattern alternation group: "...:(a|b|c)$".
bsl_relates_to_kinds() {
    jq -r '.properties.relates_to.items.pattern' "$BSL_SCHEMA_PATH" \
        | sed -nE 's/.*\(([^)]+)\).*/\1/p' \
        | tr '|' '\n'
}

# bsl_field_description <name> — description text for one field, no trailing newline.
bsl_field_description() {
    local name="$1"
    jq -r --arg n "$name" '.properties[$n].description // empty' "$BSL_SCHEMA_PATH"
}

# bsl_field_is_multi <name> — exit 0 if field is multi-valued (array), else exit 1.
bsl_field_is_multi() {
    local name="$1"
    local t
    t=$(jq -r --arg n "$name" '.properties[$n].type // empty' "$BSL_SCHEMA_PATH")
    [[ "$t" == "array" ]]
}
