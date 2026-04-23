#!/usr/bin/env bash
# Statusline capture wrapper — intercepts Claude Code statusline JSON payload,
# appends the raw JSON to a single JSONL file, and forwards the original
# payload to the downstream powerline command unchanged.
#
# No field extraction here — the Python indexer handles all parsing.
#
# FAIL-SAFE: If jq, disk, or any extraction step fails, the original stdin
# is still forwarded so the statusline never breaks.

set -euo pipefail

SNAPSHOTS_DIR="${HOME}/.claude/usage-snapshots"
SNAPSHOTS_FILE="${SNAPSHOTS_DIR}/snapshots.jsonl"
POWERLINE_VERSION="${CLAUDE_TOOLKIT_POWERLINE_VERSION:-1.25.1}"
POWERLINE_CMD="npx -y @owloops/claude-powerline@${POWERLINE_VERSION} --config=.claude/claude-powerline.json"

# 1. Read full stdin into a variable
INPUT="$(cat)"

# 2. Append raw payload with timestamp (errors suppressed, backgrounded).
# Traceability opt-in: skip capture entirely when CLAUDE_TOOLKIT_TRACEABILITY != "1".
# Powerline forward below is unaffected — statusline renders the same either way.
if [[ "${CLAUDE_TOOLKIT_TRACEABILITY:-0}" == "1" ]]; then
    {
        mkdir -p "${SNAPSHOTS_DIR}" 2>/dev/null || true

        # Add a timestamp and write the full raw payload as one JSON line
        CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
        STAMPED="$(printf '%s' "${INPUT}" | jq -c --arg ts "$CAPTURED_AT" '. + {captured_at: $ts}' 2>/dev/null)" || true
        if [[ -n "${STAMPED}" ]]; then
            printf '%s\n' "${STAMPED}" >> "${SNAPSHOTS_FILE}" 2>/dev/null || true
        fi
    } &
fi

# 3. Always forward original stdin to powerline (the critical path)
printf '%s' "${INPUT}" | ${POWERLINE_CMD}
