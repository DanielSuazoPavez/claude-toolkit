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

# Parse input — exit gracefully if jq fails
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

# Extract context based on tool type
CONTEXT=""
case "$TOOL_NAME" in
    Bash)
        CONTEXT=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
        ;;
    Read|Write|Edit)
        CONTEXT=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
        ;;
    *)
        exit 0
        ;;
esac

[ -z "$CONTEXT" ] && exit 0

# Tokenize context into words, lowercase, deduplicate
# Split on whitespace, slashes, dots, and other non-alphanumeric chars
WORDS=$(echo "$CONTEXT" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]_-' '\n' | sort -u)
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
    safe_word=$(echo "$word" | sed "s/'/''/g")
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

[ -z "$CONDITIONS" ] && exit 0

# Query matching active lessons
LESSONS=$(sqlite3 "$LESSONS_DB" "
    SELECT DISTINCT l.text
    FROM lessons l
    JOIN lesson_tags lt ON l.id = lt.lesson_id
    JOIN tags t ON lt.tag_id = t.id
    WHERE l.active = 1
      AND t.status = 'active'
      AND ($CONDITIONS)
    LIMIT 3;
" 2>/dev/null)

[ -z "$LESSONS" ] && exit 0

# Format as additionalContext — escape for JSON
ESCAPED=$(echo "$LESSONS" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n- /g')

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Relevant lessons:\\n- ${ESCAPED}\"}}"
exit 0
