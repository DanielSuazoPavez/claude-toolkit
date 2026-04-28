#!/usr/bin/env bash
# Validates that session-start.sh output stays under the harness payload cap
#
# Runs session-start.sh and measures stdout byte count against thresholds.
# Claude Code 2.1.119+ caps SessionStart hook output at ~10,240 bytes;
# exceeding it causes silent truncation (model misses mandatory tail content).
#
# Usage:
#   bash .claude/scripts/validate-session-start-cap.sh
#
# Environment:
#   SESSION_START_WARN_BYTES - warn threshold (default: 9500, ~93% of cap)
#   SESSION_START_FAIL_BYTES - fail threshold (default: 10000, ~98% of cap)
#
# Exit codes:
#   0 - Under warn threshold
#   1 - Over fail threshold
#   2 - Over warn threshold (warning only — still exits 0 for CI, printed as warning)

WARN_BYTES="${SESSION_START_WARN_BYTES:-9500}"
FAIL_BYTES="${SESSION_START_FAIL_BYTES:-10000}"
CAP_BYTES=10240

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

HOOK=".claude/hooks/session-start.sh"

if [ ! -f "$HOOK" ]; then
    echo -e "${RED}FAIL${NC}: $HOOK not found"
    exit 1
fi

OUTPUT=$(bash "$HOOK" 2>/dev/null)
BYTE_COUNT=${#OUTPUT}

echo "Session-start payload size: ${BYTE_COUNT} bytes"
echo "  Warn threshold: ${WARN_BYTES} bytes"
echo "  Fail threshold: ${FAIL_BYTES} bytes"
echo "  Harness cap:    ${CAP_BYTES} bytes"

if [ "$BYTE_COUNT" -ge "$FAIL_BYTES" ]; then
    echo -e "${RED}FAIL${NC}: session-start output (${BYTE_COUNT}B) exceeds fail threshold (${FAIL_BYTES}B)"
    echo "Reduce payload size — harness will truncate at ~${CAP_BYTES}B"
    exit 1
elif [ "$BYTE_COUNT" -ge "$WARN_BYTES" ]; then
    echo -e "${YELLOW}WARN${NC}: session-start output (${BYTE_COUNT}B) approaching cap (warn at ${WARN_BYTES}B)"
    exit 0
else
    echo -e "${GREEN}PASS${NC}: session-start output within safe range"
    exit 0
fi
