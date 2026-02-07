#!/bin/bash
# Runs all validation scripts and reports combined pass/fail
#
# Usage:
#   bash scripts/validate-all.sh
#
# Exit codes:
#   0 - All validations passed
#   1 - One or more validations failed

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILURES=0

echo "Running all validations..."
echo ""

# --- Resource indexes ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: validate-resources-indexed.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPTS_DIR/validate-resources-indexed.sh"
if [ $? -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Resource dependencies ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: verify-resource-deps.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPTS_DIR/verify-resource-deps.sh"
if [ $? -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Summary ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAILURES -eq 0 ]; then
    echo -e "\033[0;32mAll validations passed.\033[0m"
    exit 0
else
    echo -e "\033[0;31m$FAILURES validation(s) failed.\033[0m"
    exit 1
fi
