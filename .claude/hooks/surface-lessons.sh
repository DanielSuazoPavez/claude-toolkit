#!/bin/bash
# PreToolUse hook: surface relevant lessons based on tool context
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Bash|Read|Write|Edit", "hooks": [{"type": "command", "command": "bash .claude/hooks/surface-lessons.sh", "timeout": 5000}]}]
#
# Pure bash+sqlite3 — no Python, no uv run. Fast path (~10ms).
#
# Reads tool context, extracts keywords, matches against tags.keywords
# in lessons.db, and injects matching active lessons as additionalContext.
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | bash .claude/hooks/surface-lessons.sh
#   # Expected: additionalContext JSON with git-tagged lessons (if any)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash .claude/hooks/surface-lessons.sh
#   # Expected: (empty — no matching tags)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/.claude/hooks/foo.sh"}}' | bash .claude/hooks/surface-lessons.sh
#   # Expected: additionalContext with hooks-tagged lessons

LESSONS_DB="$HOME/.claude/lessons.db"
[ -f "$LESSONS_DB" ] || exit 0

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "surface-lessons" "PreToolUse"
_hook_perf_probe "hook_init"

# Single jq call: extract tool_name + context (command or file_path)
read -r TOOL_NAME CONTEXT < <(echo "$HOOK_INPUT" | jq -r '[.tool_name, (.tool_input.command // .tool_input.file_path // "")] | @tsv' 2>/dev/null) || true
_hook_perf_probe "jq_parse"

# Tool match check (replaces hook_require_tool)
case "$TOOL_NAME" in
    Bash|Read|Write|Edit) _HOOK_ACTIVE=true ;;
    *) exit 0 ;;
esac
_hook_perf_probe "tool_match"

[ -z "$CONTEXT" ] && exit 0

# Tokenize context into words, lowercase, deduplicate
# Split on whitespace, slashes, dots, and other non-alphanumeric chars
WORDS=$(echo "$CONTEXT" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]_-' '\n' | sort -u)
_hook_perf_probe "tokenize"
[ -z "$WORDS" ] && exit 0

# Build SQL OR conditions matching context words against tag keywords
# Each tag has comma-separated keywords. Match if any context word
# appears as a substring in the keywords field.
# Also try without trailing 's' for basic plural handling.
CONDITIONS=""
for word in $WORDS; do
    # Skip very short words
    [ ${#word} -lt 3 ] && continue
    # Escape single quotes for SQL
    safe_word="${word//\'/\'\'}"
    if [ -n "$CONDITIONS" ]; then
        CONDITIONS="$CONDITIONS OR t.keywords LIKE '%${safe_word}%'"
    else
        CONDITIONS="t.keywords LIKE '%${safe_word}%'"
    fi
    # Try without trailing 's' for plural matching
    stripped="${safe_word%s}"
    if [ "$stripped" != "$safe_word" ] && [ ${#stripped} -ge 3 ]; then
        CONDITIONS="$CONDITIONS OR t.keywords LIKE '%${stripped}%'"
    fi
done
_hook_perf_probe "build_sql"

[ -z "$CONDITIONS" ] && exit 0

# Query matching active lessons (id + text in one query)
RESULTS=$(sqlite3 -separator '|' "$LESSONS_DB" "
    SELECT DISTINCT l.id, l.text
    FROM lessons l
    JOIN lesson_tags lt ON l.id = lt.lesson_id
    JOIN tags t ON lt.tag_id = t.id
    WHERE l.active = 1
      AND t.status = 'active'
      AND ($CONDITIONS)
    LIMIT 3;
" 2>/dev/null)
_hook_perf_probe "sqlite_query"

LESSONS=$(echo "$RESULTS" | cut -d'|' -f2-)
MATCHED_IDS=$(echo "$RESULTS" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//')
MATCH_COUNT=$(echo "$RESULTS" | grep -c . 2>/dev/null || echo "0")

# Log context for observability (even when no matches)
KEYWORD_LIST=$(echo "$WORDS" | tr '\n' ',' | sed 's/,$//')
hook_log_context "$CONTEXT" "$KEYWORD_LIST" "$MATCH_COUNT" "$MATCHED_IDS"

[ -z "$LESSONS" ] && exit 0

# Format as additionalContext — escape for JSON
ESCAPED=$(echo "$LESSONS" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n- /g')
_hook_perf_probe "format_output"

hook_inject "Relevant lessons:\\n- ${ESCAPED}"
