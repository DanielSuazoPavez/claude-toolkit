#!/bin/bash
# SessionStart hook: inject essential docs at session start
#
# Settings.json:
#   "SessionStart": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/session-start.sh"}]}]
#
# Environment:
#   CLAUDE_DOCS_DIR     - docs directory (default: .claude/docs)
#   CLAUDE_MEMORIES_DIR - memories directory (default: .claude/memories)
#
# Requires: essential-*.md files in docs and/or memories directory
#
# Test cases:
#   # Normal operation (from project root with memories)
#   cd /path/to/project && bash .claude/hooks/session-start.sh
#   # Expected: outputs essential memories, other memories list, git context
#
#   # No memories directory
#   CLAUDE_MEMORIES_DIR=/nonexistent bash .claude/hooks/session-start.sh
#   # Expected: "Warning: /nonexistent not found..." then exits 0
#
#   # Empty memories (no essential-*.md files)
#   mkdir -p /tmp/empty-mem && CLAUDE_MEMORIES_DIR=/tmp/empty-mem bash .claude/hooks/session-start.sh
#   # Expected: outputs headers but "0 essential memories loaded"
#
#   # No git repo
#   cd /tmp && bash /path/to/.claude/hooks/session-start.sh
#   # Expected: Branch shows "unknown", Main shows "main" (fallback)

# Configuration
DOCS_DIR="${CLAUDE_DOCS_DIR:-.claude/docs}"
MEMORIES_DIR="${CLAUDE_MEMORIES_DIR:-.claude/memories}"

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "session-start" "SessionStart"

# Write session ID for other hooks to read
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    _dir="${CLAUDE_ENV_FILE%/*}"
    SESSION_ID="${_dir##*/}"
else
    SESSION_ID="unknown-${EPOCHSECONDS:-$(date +%Y%m%d_%H%M%S)}"
fi
echo "$SESSION_ID" > ".claude/logs/.session-id"

# Check we're in a project with docs or memories
if [ ! -d "$DOCS_DIR" ] && [ ! -d "$MEMORIES_DIR" ]; then
    echo "Warning: neither $DOCS_DIR nor $MEMORIES_DIR found. Run from project root."
    exit 0
fi

# === ESSENTIAL CONTEXT (auto-injected) ===

# Output essential docs — these are always relevant
ESSENTIAL_OUT=""
ESSENTIAL_COUNT=0
for dir in "$DOCS_DIR"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/essential-*.md; do
    if [ -f "$f" ]; then
      ESSENTIAL_COUNT=$((ESSENTIAL_COUNT + 1))
      _name="${f##*/}"
      _name="${_name%.md}"
      _content=$(cat "$f" 2>/dev/null) || _content="(Error reading file - permission denied or corrupted)"
      ENTRY_CONTENT="=== ${_name} ===
${_content}
"
      hook_log_section "essential:${_name}" "$ENTRY_CONTENT"
      ESSENTIAL_OUT="${ESSENTIAL_OUT}${ENTRY_CONTENT}"
    fi
  done
done
printf '%s' "$ESSENTIAL_OUT"

# === MEMORY GUIDANCE ===
GUIDANCE_OUT="Use /list-memories to discover available context when the task relates to a non-essential memory topic."
hook_log_section "guidance" "$GUIDANCE_OUT"
echo ""
echo "$GUIDANCE_OUT"

# === GIT CONTEXT ===
_raw=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) && MAIN_BRANCH="${_raw##refs/remotes/origin/}" || MAIN_BRANCH=""
[ -z "$MAIN_BRANCH" ] && MAIN_BRANCH="main"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
GIT_OUT="=== GIT CONTEXT ===
Branch: $CURRENT_BRANCH
Main: $MAIN_BRANCH"
hook_log_section "git" "$GIT_OUT"
echo ""
echo "$GIT_OUT"

# === TOOLKIT VERSION ===
ACTIONABLE_ITEMS=""
if [ -f ".claude-toolkit-version" ] && command -v claude-toolkit &>/dev/null; then
    PROJECT_VER=$(<.claude-toolkit-version) 2>/dev/null || PROJECT_VER=""
    TOOLKIT_VER=$(claude-toolkit version 2>/dev/null)
    if [ -n "$TOOLKIT_VER" ] && [ -n "$PROJECT_VER" ] && [ "$PROJECT_VER" != "$TOOLKIT_VER" ]; then
        TOOLKIT_OUT="=== TOOLKIT VERSION ===
Project: $PROJECT_VER → Toolkit: $TOOLKIT_VER — run \`make claude-toolkit-sync\` then /setup-toolkit"
        hook_log_section "toolkit" "$TOOLKIT_OUT"
        echo ""
        echo "$TOOLKIT_OUT"
        ACTIONABLE_ITEMS="${ACTIONABLE_ITEMS}\n- Toolkit version mismatch: $PROJECT_VER → $TOOLKIT_VER (run \`make claude-toolkit-sync\`)"
    fi
fi

# === LESSONS ===
LESSONS_DB="$HOME/.claude/lessons.db"
LEARNED_FILE=".claude/learned.json"

if [ -f "$LESSONS_DB" ]; then
    # SQLite path — CURRENT_BRANCH already set in git context section
    SAFE_BRANCH="${CURRENT_BRANCH//\'/\'\'}"

    # Single sqlite3 call for all lesson data — row prefix disambiguates result sets
    KEY_LESSONS=""
    RECENT_LESSONS=""
    BRANCH_LESSONS=""
    DAYS_SINCE=-1
    THRESHOLD_DAYS=7
    ACTIVE_COUNT=0
    _LAST_MANAGE_EXISTS=0

    _DB_RESULT=$(sqlite3 -separator '|' "$LESSONS_DB" "
SELECT 'K|' || '- [' || GROUP_CONCAT(t.name, ',') || '] ' || l.text
  FROM lessons l
  LEFT JOIN lesson_tags lt ON lt.lesson_id = l.id
  LEFT JOIN tags t ON t.id = lt.tag_id
  WHERE l.tier = 'key' AND l.active = 1
  GROUP BY l.id ORDER BY l.date DESC;
SELECT 'R|' || '- ' || l.text
  FROM lessons l WHERE l.tier = 'recent' AND l.active = 1
  ORDER BY l.date DESC LIMIT 5;
SELECT 'B|' || '- ' || l.text
  FROM lessons l WHERE l.tier = 'recent' AND l.active = 1
  AND l.branch = '${SAFE_BRANCH}'
  ORDER BY l.date DESC;
SELECT 'M|' || CAST(COALESCE(julianday('now') - julianday(value), -1) AS INTEGER)
  FROM metadata WHERE key = 'last_manage_run';
SELECT 'T|' || COALESCE(value, '7')
  FROM metadata WHERE key = 'nudge_threshold_days';
SELECT 'C|' || COUNT(*) FROM lessons WHERE active = 1;
" 2>/dev/null)

    while IFS='|' read -r _prefix _rest; do
        case "$_prefix" in
            K) KEY_LESSONS+="${_rest}"$'\n' ;;
            R) RECENT_LESSONS+="${_rest}"$'\n' ;;
            B) BRANCH_LESSONS+="${_rest}"$'\n' ;;
            M) DAYS_SINCE="${_rest}"; [ "$DAYS_SINCE" -ge 0 ] 2>/dev/null && _LAST_MANAGE_EXISTS=1 ;;
            T) THRESHOLD_DAYS="${_rest}" ;;
            C) ACTIVE_COUNT="${_rest}" ;;
        esac
    done <<< "$_DB_RESULT"

    # Trim trailing newlines
    KEY_LESSONS="${KEY_LESSONS%$'\n'}"
    RECENT_LESSONS="${RECENT_LESSONS%$'\n'}"
    BRANCH_LESSONS="${BRANCH_LESSONS%$'\n'}"

    if [ -n "$KEY_LESSONS" ] || [ -n "$RECENT_LESSONS" ]; then
        LESSONS_OUT="=== LESSONS ==="
        [ -n "$KEY_LESSONS" ] && LESSONS_OUT="$LESSONS_OUT
Key:
$KEY_LESSONS"
        [ -n "$RECENT_LESSONS" ] && LESSONS_OUT="$LESSONS_OUT
Recent:
$RECENT_LESSONS"
        [ -n "$BRANCH_LESSONS" ] && LESSONS_OUT="$LESSONS_OUT
This branch:
$BRANCH_LESSONS"
        hook_log_section "lessons" "$LESSONS_OUT"
        echo ""
        echo "$LESSONS_OUT"
    fi

    # Nudge logic — days_since computed in SQL via julianday()
    NUDGE=""
    if [ "$_LAST_MANAGE_EXISTS" = 1 ] && [ "$DAYS_SINCE" -ge 0 ] 2>/dev/null; then
        if [ "$DAYS_SINCE" -ge "$THRESHOLD_DAYS" ] 2>/dev/null; then
            NUDGE="${DAYS_SINCE}d since last /manage-lessons"
        fi
    else
        NUDGE="never run /manage-lessons"
    fi

    if [ -n "$NUDGE" ]; then
        echo "⚠ $NUDGE ($ACTIVE_COUNT active lessons). Consider running /manage-lessons"
        ACTIONABLE_ITEMS="${ACTIONABLE_ITEMS}\n- $NUDGE ($ACTIVE_COUNT active lessons) — run /manage-lessons"
    fi
    echo ""

elif [ -f "$LEARNED_FILE" ]; then
    # Fallback — learned.json still exists but no lessons.db
    echo ""
    echo "=== LESSONS ==="
    echo "⚠ MANDATORY: lessons.db not found but learned.json exists. Ask the user to run \`claude-toolkit lessons migrate\` to upgrade lessons to SQLite. Do NOT skip this — surface it immediately at session start."
    ACTIONABLE_ITEMS="${ACTIONABLE_ITEMS}\n- lessons.db missing — run \`claude-toolkit lessons migrate\` to upgrade from learned.json"

    # Legacy jq path
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
    KEY_LESSONS=$(jq -r '[.lessons[]? | select(.tier == "key")] | .[] | "- [\(.category)] \(.text)"' "$LEARNED_FILE" 2>/dev/null)
    RECENT_LESSONS=$(jq -r '[.lessons[]? | select(.tier == "recent")] | .[-5:][] | "- [\(.category)] \(.text)"' "$LEARNED_FILE" 2>/dev/null)
    [ -n "$KEY_LESSONS" ] && echo "Key:" && echo "$KEY_LESSONS"
    [ -n "$RECENT_LESSONS" ] && echo "Recent:" && echo "$RECENT_LESSONS"
    echo ""
fi

# === ACKNOWLEDGMENT ===
# ESSENTIAL_COUNT already set by the memory loop above
LESSON_COUNT=0
if [ -f "$LESSONS_DB" ]; then
    # ACTIVE_COUNT already set by the combined query above
    LESSON_COUNT="${ACTIVE_COUNT:-0}"
elif [ -f "$LEARNED_FILE" ]; then
    LESSON_COUNT=$(jq '.lessons | length' "$LEARNED_FILE" 2>/dev/null || echo 0)
fi
echo ""
echo "=== SESSION START ==="
ACK_MSG="$ESSENTIAL_COUNT essential memories loaded"
[ "$LESSON_COUNT" -gt 0 ] && ACK_MSG="$ACK_MSG, $LESSON_COUNT lessons noted"
if [ -n "$ACTIONABLE_ITEMS" ]; then
    echo "MANDATORY: Your FIRST message to the user MUST acknowledge: $ACK_MSG. Then surface these actionable items — do NOT skip or bury them:"
    echo -e "$ACTIONABLE_ITEMS"
else
    echo "MANDATORY: Your FIRST message to the user MUST acknowledge: $ACK_MSG. Do NOT skip this or bury it in other output."
fi

exit 0
