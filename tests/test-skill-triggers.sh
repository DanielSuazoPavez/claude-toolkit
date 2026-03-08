#!/bin/bash
# Test skill trigger accuracy across all skills with eval sets.
#
# Usage:
#   bash tests/test-skill-triggers.sh           # Test all skills with eval sets
#   bash tests/test-skill-triggers.sh -v        # Verbose mode
#   bash tests/test-skill-triggers.sh <skill>   # Test specific skill
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$PROJECT_ROOT/.claude/scripts/test-trigger.sh"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Parse args
VERBOSE=""
FILTER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose) VERBOSE="-v"; shift ;;
        *) FILTER="$1"; shift ;;
    esac
done

# Collect skills with eval sets
SKILLS=()
if [[ -n "$FILTER" ]]; then
    if [[ -f "$SKILLS_DIR/$FILTER/eval-triggers.json" ]]; then
        SKILLS=("$FILTER")
    else
        echo -e "${RED}ERROR${NC}: No eval-triggers.json found for '$FILTER'" >&2
        exit 1
    fi
else
    for eval_file in "$SKILLS_DIR"/*/eval-triggers.json; do
        [[ -f "$eval_file" ]] || continue
        skill_name=$(basename "$(dirname "$eval_file")")
        SKILLS+=("$skill_name")
    done
fi

if [[ ${#SKILLS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No skills with eval-triggers.json found${NC}"
    exit 0
fi

echo -e "${BOLD}Skill Trigger Tests${NC} (${#SKILLS[@]} skills)"
echo ""

# Run tests
TOTAL_SKILLS=0
PASSED_SKILLS=0
FAILED_SKILLS=0

for skill in "${SKILLS[@]}"; do
    ((TOTAL_SKILLS++))
    if bash "$ENGINE" "$skill" $VERBOSE; then
        ((PASSED_SKILLS++))
    else
        ((FAILED_SKILLS++))
    fi
done

# Summary
echo ""
echo -e "${BOLD}Results${NC}: $PASSED_SKILLS/$TOTAL_SKILLS skills passed"
if [[ "$FAILED_SKILLS" -gt 0 ]]; then
    echo -e "${RED}$FAILED_SKILLS skill(s) had trigger failures${NC}"
    exit 1
else
    echo -e "${GREEN}All trigger tests passed${NC}"
    exit 0
fi
