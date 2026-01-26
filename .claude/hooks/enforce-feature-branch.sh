#!/bin/bash
# Hook: enforce-feature-branch
# Event: PreToolUse (EnterPlanMode)
# Purpose: Block plan mode on main/master - create feature branch first
#
# Test commands:
#   Should block:
#     cd /tmp && git init test-repo && cd test-repo && git checkout -b main && \
#     echo '{"tool_name":"EnterPlanMode"}' | /path/to/enforce-feature-branch.sh
#
#   Should allow:
#     cd /tmp/test-repo && git checkout -b feature/test && \
#     echo '{"tool_name":"EnterPlanMode"}' | /path/to/enforce-feature-branch.sh
#
# settings.json:
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "EnterPlanMode",
#         "hooks": [{"type": "command", "command": ".claude/hooks/enforce-feature-branch.sh"}]
#       }]
#     }
#   }
#
# Bypass: ALLOW_PLAN_ON_MAIN=1
# Config: PROTECTED_BRANCHES="^(main|master|develop)$" (regex)

set -euo pipefail

# Configurable protected branches (regex pattern)
PROTECTED_BRANCHES="${PROTECTED_BRANCHES:-^(main|master)$}"

INPUT=$(cat)

# Bypass check
if [[ "${ALLOW_PLAN_ON_MAIN:-}" == "1" ]]; then
    exit 0
fi

# Early exit for non-matching tools
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
if [[ "$TOOL_NAME" != "EnterPlanMode" ]]; then
    exit 0
fi

# Check if in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    exit 0  # Not a git repo, allow
fi

# Get current branch
BRANCH=$(git branch --show-current 2>/dev/null) || exit 0

# Handle detached HEAD (empty branch name)
if [[ -z "$BRANCH" ]]; then
    cat <<'BLOCK'
{"decision":"block","reason":"You're in detached HEAD state. Create a feature branch first:\n\n  git checkout -b feature/<short-description>"}
BLOCK
    exit 0
fi

# Block if on protected branch
if [[ "$BRANCH" =~ $PROTECTED_BRANCHES ]]; then
    cat <<BLOCK
{"decision":"block","reason":"Create a feature branch first.\n\nYou're on '$BRANCH' (protected). Before entering plan mode:\n\n  git checkout -b feature/<short-description>\n\nBranch prefixes: feature/, fix/, refactor/, docs/, chore/"}
BLOCK
    exit 0
fi

# Allow - on a feature branch
exit 0
