#!/bin/bash
# Hook: git-safety
# Event: PreToolUse (EnterPlanMode, Bash)
# Purpose: Block unsafe git operations — protected branch enforcement + remote-destructive commands
#
# Settings.json:
#   "PreToolUse": [{"matcher": "EnterPlanMode|Bash", "hooks": [{"type": "command", "command": ".claude/hooks/git-safety.sh"}]}]
#
# Config: PROTECTED_BRANCHES="^(main|master)$" (regex, customizable)
#
# Protections:
#   Protected branch enforcement:
#     - Block plan mode on protected branches
#     - Block git commit on protected branches
#   Remote-destructive (severe — irreversible):
#     - Force push to protected branches (--force, -f, --force-with-lease)
#     - git push --mirror
#     - Delete protected branch on remote (--delete or :branch syntax)
#   Remote-destructive (soft — risky):
#     - Force push to non-protected branches
#     - Delete any remote branch
#     - Cross-branch push (HEAD:other-branch)
#
# Test cases:
#   # On main branch:
#   echo '{"tool_name":"EnterPlanMode"}' | bash git-safety.sh
#   # Expected: {"decision":"block","reason":"..."} (plan mode on protected branch)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' | bash git-safety.sh
#   # Expected: {"decision":"block","reason":"..."} (commit on protected branch)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' | bash git-safety.sh
#   # Expected: block (force push to protected - severe)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' | bash git-safety.sh
#   # Expected: block (force push to protected, short flag - severe)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' | bash git-safety.sh
#   # Expected: block (force push to protected, trailing flag - severe)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}' | bash git-safety.sh
#   # Expected: block (force-with-lease to protected - severe)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push --mirror"}}' | bash git-safety.sh
#   # Expected: block (mirror push - severe)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin main"}}' | bash git-safety.sh
#   # Expected: block (delete protected remote branch - severe)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push origin :main"}}' | bash git-safety.sh
#   # Expected: block (delete protected remote branch, colon syntax - severe)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature"}}' | bash git-safety.sh
#   # Expected: block (force push to non-protected - soft)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin feature"}}' | bash git-safety.sh
#   # Expected: block (delete non-protected remote branch - soft)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:other-branch"}}' | bash git-safety.sh
#   # Expected: block (cross-branch push - soft, if not on other-branch)
#
#   # On feature branch:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feature"}}' | bash git-safety.sh
#   # Expected: (empty - allowed, normal push)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | bash git-safety.sh
#   # Expected: (empty - allowed, simple push)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feature"}}' | bash git-safety.sh
#   # Expected: (empty - allowed, -u is not -f)

set -euo pipefail

# Configurable protected branches (regex pattern)
PROTECTED_BRANCHES="${PROTECTED_BRANCHES:-^(main|master)$}"

INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

# Block helper — message text carries the tone difference (severe vs soft)
block() {
    echo "{\"decision\": \"block\", \"reason\": \"$1\\n\\nRun the command manually outside Claude if you really need this.\"}"
    exit 0
}

# --- Handle EnterPlanMode ---
if [[ "$TOOL_NAME" == "EnterPlanMode" ]]; then
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        exit 0
    fi

    BRANCH=$(git branch --show-current 2>/dev/null) || exit 0

    if [[ -z "$BRANCH" ]]; then
        cat <<'BLOCK'
{"decision":"block","reason":"You're in detached HEAD state. Create a feature branch first:\n\n  git checkout -b feat/<short-description>"}
BLOCK
        exit 0
    fi

    if [[ "$BRANCH" =~ $PROTECTED_BRANCHES ]]; then
        cat <<BLOCK
{"decision":"block","reason":"Create a feature branch first.\n\nYou're on '$BRANCH' (protected). Before entering plan mode:\n\n  git checkout -b feat/<short-description>\n\nBranch prefixes: feat/, fix/, refactor/, docs/, chore/"}
BLOCK
        exit 0
    fi

    exit 0
fi

# --- Handle Bash ---
if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

    # === git push checks ===
    if echo "$COMMAND" | grep -qE '(^|[;&|]\s*)git\s+push'; then

        # Detect force flags anywhere in the push command
        IS_FORCE=false
        if echo "$COMMAND" | grep -qE 'git\s+push\b.*(\s--force\b|\s--force-with-lease\b|\s-f\b)'; then
            IS_FORCE=true
        fi

        # --- Severe: git push --mirror ---
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--mirror'; then
            block "git push --mirror overwrites the entire remote repository, deleting all branches and tags not in your local copy. This is not reversible."
        fi

        # Extract push target ref from command
        # Strip flags to get positional args: <remote> <refspec>
        PUSH_ARGS=$(echo "$COMMAND" | sed -nE 's/.*(^|[;&|]\s*)git\s+push\s+(.*)/\2/p' | sed -E 's/\s*--?[a-zA-Z][-a-zA-Z]*//g; s/^\s+//; s/\s+/ /g')
        PUSH_REF=""
        if [[ "$PUSH_ARGS" =~ [^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
            PUSH_REF="${BASH_REMATCH[1]}"
        fi
        # Handle refspec: HEAD:main or local-branch:main → extract target
        if [[ "$PUSH_REF" == *:* ]]; then
            PUSH_REF="${PUSH_REF##*:}"
        fi

        # --- Severe: force push to protected branch ---
        if [[ "$IS_FORCE" == true && -n "$PUSH_REF" && "$PUSH_REF" =~ $PROTECTED_BRANCHES ]]; then
            block "Force push to '$PUSH_REF' would rewrite shared history and can cause permanent data loss for collaborators. This is not reversible."
        fi

        # --- Severe: delete protected branch on remote ---
        # Pattern 1: git push --delete <remote> <branch>
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--delete'; then
            DELETE_BRANCH=$(echo "$COMMAND" | sed -nE 's/.*git\s+push\s+.*--delete\s+\S+\s+(\S+).*/\1/p')
            if [[ -n "$DELETE_BRANCH" && "$DELETE_BRANCH" =~ $PROTECTED_BRANCHES ]]; then
                block "Deleting '$DELETE_BRANCH' from remote would destroy the primary branch for all collaborators. This is not reversible."
            fi
        fi
        # Pattern 2: git push <remote> :<branch>
        if echo "$COMMAND" | grep -qE 'git\s+push\s+\S+\s+:[a-zA-Z]'; then
            COLON_BRANCH=$(echo "$COMMAND" | sed -nE 's/.*git\s+push\s+\S+\s+:(\S+).*/\1/p')
            if [[ -n "$COLON_BRANCH" && "$COLON_BRANCH" =~ $PROTECTED_BRANCHES ]]; then
                block "Deleting '$COLON_BRANCH' from remote would destroy the primary branch for all collaborators. This is not reversible."
            fi
        fi

        # --- Soft: force push to non-protected branch ---
        if [[ "$IS_FORCE" == true ]]; then
            block "Force pushing rewrites remote history. Collaborators pulling this branch will get conflicts."
        fi

        # --- Soft: delete any remote branch ---
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--delete'; then
            block "Deleting a remote branch removes it for all collaborators."
        fi
        if echo "$COMMAND" | grep -qE 'git\s+push\s+\S+\s+:[a-zA-Z]'; then
            block "Deleting a remote branch removes it for all collaborators."
        fi

        # --- Soft: cross-branch push ---
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*\S+:\S+'; then
            REFSPEC=$(echo "$COMMAND" | sed -nE 's/.*git\s+push\s+[^;|&]*\s+(\S+:\S+).*/\1/p')
            TARGET_BRANCH="${REFSPEC##*:}"
            CURRENT_BRANCH=$(git branch --show-current 2>/dev/null) || true
            if [[ -n "$TARGET_BRANCH" && -n "$CURRENT_BRANCH" && "$TARGET_BRANCH" != "$CURRENT_BRANCH" ]]; then
                block "Pushing to '$TARGET_BRANCH' while on '$CURRENT_BRANCH'. This can accidentally overwrite another branch."
            fi
        fi
    fi

    # === git commit check (existing) ===
    if echo "$COMMAND" | grep -qE '(^|[;&|]\s*)git\s+commit'; then
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            exit 0
        fi

        BRANCH=$(git branch --show-current 2>/dev/null) || exit 0

        if [[ -z "$BRANCH" ]]; then
            cat <<'BLOCK'
{"decision":"block","reason":"You're in detached HEAD state. Create a feature branch before committing:\n\n  git checkout -b feat/<short-description>"}
BLOCK
            exit 0
        fi

        if [[ "$BRANCH" =~ $PROTECTED_BRANCHES ]]; then
            cat <<BLOCK
{"decision":"block","reason":"Cannot commit directly to '$BRANCH'.\n\nCreate a feature branch first:\n\n  git checkout -b feat/<short-description>\n\nThen commit your changes there.\n\nNote: Do not chain git checkout and git commit in a single command — the hook checks the branch at execution time."}
BLOCK
            exit 0
        fi
    fi

    exit 0
fi

# Other tools - allow
exit 0
