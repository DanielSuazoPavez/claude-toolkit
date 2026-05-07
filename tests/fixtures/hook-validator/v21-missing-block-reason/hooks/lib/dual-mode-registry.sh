#!/usr/bin/env bash
# Fixture registry for V21 test — minimal subset.

# shellcheck disable=SC2034
declare -A DUAL_MODE_HOOKS=(
    [broken]=broken-guard
    [compliant]=compliant-guard
)

# shellcheck disable=SC2034
declare -A MATCH_FN=(
    [broken]=match_broken
    [compliant]=match_compliant
)

# shellcheck disable=SC2034
declare -A CHECK_FN=(
    [broken]=check_broken
    [compliant]=check_compliant
)
