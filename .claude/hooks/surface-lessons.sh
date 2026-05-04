#!/usr/bin/env bash
# CC-HOOK: NAME: surface-lessons
# CC-HOOK: PURPOSE: Surface relevant lessons based on tool context
# CC-HOOK: EVENTS: PreToolUse(Bash|Read|Write|Edit)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: lessons
# CC-HOOK: SHIPS-IN: base
#
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

LESSONS_DB="${CLAUDE_ANALYTICS_LESSONS_DB:-$HOME/claude-analytics/lessons.db}"
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

# Build CASE-sum terms: each context word contributes at most 1 to a tag's
# hit count. Require >= 2 distinct context-word hits against the same tag's
# keywords for the tag (and its lessons) to surface. A single-word match
# (e.g. `reset` alone against the `git` tag) is too coincidental; two
# distinct tokens from a tag's vocabulary is strong evidence the command
# is about that domain.
CASE_SUM=""
WORD_COUNT=0
for word in $WORDS; do
    [ ${#word} -lt 3 ] && continue
    safe_word="${word//\'/\'\'}"
    term="(CASE WHEN t.keywords LIKE '%${safe_word}%' THEN 1 ELSE 0 END)"
    if [ -n "$CASE_SUM" ]; then
        CASE_SUM="$CASE_SUM + $term"
    else
        CASE_SUM="$term"
    fi
    WORD_COUNT=$((WORD_COUNT + 1))
done
_hook_perf_probe "build_sql"

# Need at least 2 candidate words to possibly reach the 2-hit threshold.
[ "$WORD_COUNT" -lt 2 ] && exit 0

# Intra-session dedup: exclude lesson IDs already surfaced earlier in this session.
# Cross-DB read against hooks.db.surface_lessons_context — populated by the
# claude-sessions indexer (~1min lag from JSONL → DB). A lesson repeated within
# the same ingestion window is the accepted tradeoff for standardizing data
# ingestion downstream. Empty on first invocation or if hooks.db is absent,
# which degrades gracefully to "no dedup".
HOOKS_DB="${CLAUDE_ANALYTICS_HOOKS_DB:-$HOME/claude-analytics/hooks.db}"
NOT_IN_CLAUSE=""
if [ -f "$HOOKS_DB" ] && [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "unknown" ]; then
    SAFE_SESSION="${SESSION_ID//\'/\'\'}"
    SEEN_IDS=$(sqlite3 "$HOOKS_DB" "
        SELECT DISTINCT matched_lesson_ids
        FROM surface_lessons_context
        WHERE session_id = '${SAFE_SESSION}' AND match_count > 0;
    " 2>/dev/null | tr ',' '\n' | awk 'NF' | sort -u)
    if [ -n "$SEEN_IDS" ]; then
        QUOTED=""
        for id in $SEEN_IDS; do
            safe_id="${id//\'/\'\'}"
            QUOTED="${QUOTED:+$QUOTED,}'${safe_id}'"
        done
        NOT_IN_CLAUSE="AND l.id NOT IN ($QUOTED)"
    fi
fi
_hook_perf_probe "seen_lookup"

# Query matching active lessons (id + text in one query), scope-filtered
# SQL escaping via single-quote doubling: sqlite3 CLI has no bind-parameter flag,
# and $PROJECT comes from $PWD (local, user-owned) — not external input.
_ensure_project
SAFE_PROJECT="${PROJECT//\'/\'\'}"
RESULTS=$(sqlite3 -separator '|' "$LESSONS_DB" "
    WITH candidate_tags AS (
        SELECT t.id AS tag_id
        FROM tags t
        WHERE t.status = 'active'
        GROUP BY t.id
        HAVING ($CASE_SUM) >= 2
    )
    SELECT DISTINCT l.id, l.text
    FROM lessons l
    JOIN lesson_tags lt ON l.id = lt.lesson_id
    JOIN candidate_tags c ON lt.tag_id = c.tag_id
    WHERE l.active = 1
      AND (l.scope = 'global' OR (l.scope = 'project' AND l.project_id = '${SAFE_PROJECT}'))
      ${NOT_IN_CLAUSE}
    LIMIT 3;
" 2>/dev/null)
_hook_perf_probe "sqlite_query"

LESSONS=$(echo "$RESULTS" | cut -d'|' -f2-)
MATCHED_IDS=$(echo "$RESULTS" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//')
MATCH_COUNT=$(printf '%s\n' "$RESULTS" | grep -c . 2>/dev/null)
[ -z "$MATCH_COUNT" ] && MATCH_COUNT=0

# Log context for observability (even when no matches)
KEYWORD_LIST=$(echo "$WORDS" | tr '\n' ',' | sed 's/,$//')
hook_log_context "$CONTEXT" "$KEYWORD_LIST" "$MATCH_COUNT" "$MATCHED_IDS"

[ -z "$LESSONS" ] && exit 0

# Lessons opt-in: skip injection when disabled. Context logging above still
# runs (gated independently by traceability) so users can see what would match.
hook_feature_enabled lessons || exit 0

# Format as additionalContext — escape for JSON
ESCAPED=$(echo "$LESSONS" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n- /g')
_hook_perf_probe "format_output"

hook_inject "Relevant lessons:\\n- ${ESCAPED}"
