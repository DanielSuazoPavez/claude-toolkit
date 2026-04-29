#!/usr/bin/env bash
# Runs all validation scripts and reports combined pass/fail
#
# Usage:
#   bash .claude/scripts/validate-all.sh
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

# --- Hook-utils sourcing ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: validate-hook-utils.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPTS_DIR/validate-hook-utils.sh"
if [ $? -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
fi
echo ""

# --- External tool dependencies ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: verify-external-deps.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPTS_DIR/verify-external-deps.sh"
echo ""

# --- Settings template ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: validate-settings-template.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPTS_DIR/validate-settings-template.sh"
if [ $? -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Detection registry ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: validate-detection-registry.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPTS_DIR/validate-detection-registry.sh"
if [ $? -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Session-start payload cap ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: validate-session-start-cap.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPTS_DIR/validate-session-start-cap.sh"
if [ $? -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Dist manifest existence (workshop-only; absent in consumer syncs) ---
if [ -f "$SCRIPTS_DIR/validate-dist-manifests.sh" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: validate-dist-manifests.sh"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "$SCRIPTS_DIR/validate-dist-manifests.sh"
    if [ $? -ne 0 ]; then
        FAILURES=$((FAILURES + 1))
    fi
    echo ""
fi

# --- Summary ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAILURES -eq 0 ]; then
    echo -e "\033[0;32mAll validations passed.\033[0m"
    exit 0
else
    echo -e "\033[0;31m$FAILURES validation(s) failed.\033[0m"
    exit 1
fi
