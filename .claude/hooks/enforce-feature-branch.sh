#!/bin/bash
# Hook: enforce-feature-branch
# Event: PreToolUse (EnterPlanMode, Bash)
# Purpose: Block plan mode and git commits on main/master - create feature branch first
#
# Test commands:
#   Should block EnterPlanMode on main:
#     cd /tmp && git init test-repo && cd test-repo && git checkout -b main && \
#     echo '{"tool_name":"EnterPlanMode"}' | /path/to/enforce-feature-branch.sh
#
#   Should block git commit on main:
#     echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' | \
#     /path/to/enforce-feature-branch.sh
#
#   Should allow on feature branch:
#     cd /tmp/test-repo && git checkout -b feature/test && \
#     echo '{"tool_name":"EnterPlanMode"}' | /path/to/enforce-feature-branch.sh
#
# settings.json:
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "EnterPlanMode|Bash",
#         "hooks": [{"type": "command", "command": ".claude/hooks/enforce-feature-branch.sh"}]
#       }]
#     }
#   }
#
# Bypass: ALLOW_PLAN_ON_MAIN=1 (for EnterPlanMode)
#         ALLOW_COMMIT_ON_MAIN=1 (for git commit)
# Config: PROTECTED_BRANCHES="^(main|master|develop)$" (regex)

set -euo pipefail

# Configurable protected branches (regex pattern)
PROTECTED_BRANCHES="${PROTECTED_BRANCHES:-^(main|master)$}"

INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

# Handle EnterPlanMode
if [[ "$TOOL_NAME" == "EnterPlanMode" ]]; then
    # Bypass check
    if [[ "${ALLOW_PLAN_ON_MAIN:-}" == "1" ]]; then
        exit 0
    fi

    # Check if in a git repo
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        exit 0  # Not a git repo, allow
    fi

    # Get current branch
    BRANCH=$(git branch --show-current 2>/dev/null) || exit 0

    # Handle detached HEAD
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

    exit 0
fi

# Handle Bash - check for git commit
if [[ "$TOOL_NAME" == "Bash" ]]; then
    # Bypass check
    if [[ "${ALLOW_COMMIT_ON_MAIN:-}" == "1" ]]; then
        exit 0
    fi

    # Get command
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

    # Check if command contains git commit (but not in a comment or string context)
    # Match: git commit, git commit -m, git commit --amend, etc.
    if ! echo "$COMMAND" | grep -qE '(^|[;&|]\s*)git\s+commit'; then
        exit 0  # Not a git commit, allow
    fi

    # Check if in a git repo
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        exit 0  # Not a git repo, allow
    fi

    # Get current branch
    BRANCH=$(git branch --show-current 2>/dev/null) || exit 0

    # Handle detached HEAD
    if [[ -z "$BRANCH" ]]; then
        cat <<'BLOCK'
{"decision":"block","reason":"You're in detached HEAD state. Create a feature branch before committing:\n\n  git checkout -b feature/<short-description>"}
BLOCK
        exit 0
    fi

    # Block if on protected branch
    if [[ "$BRANCH" =~ $PROTECTED_BRANCHES ]]; then
        cat <<BLOCK
{"decision":"block","reason":"Cannot commit directly to '$BRANCH'.\n\nCreate a feature branch first:\n\n  git checkout -b feature/<short-description>\n\nThen commit your changes there."}
BLOCK
        exit 0
    fi

    exit 0
fi

# Other tools - allow
exit 0
