#!/usr/bin/env bash
# CC-HOOK: NAME: git-safety
# CC-HOOK: PURPOSE: Block unsafe git operations on protected branches and remote-destructive ops
# CC-HOOK: EVENTS: PreToolUse(EnterPlanMode)
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: DISPATCH-FN: grouped-bash-guard=git_safety
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=47, scope_hit=87
# CC-HOOK: OPT-IN: none
#
# Hook: git-safety
# Event: PreToolUse (EnterPlanMode, Bash)
# Purpose: Block unsafe git operations — protected branch enforcement + remote-destructive commands
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# Only the Bash branch participates in the dispatcher — EnterPlanMode stays in main.
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json:
#   "PreToolUse": [{"matcher": "EnterPlanMode|Bash", "hooks": [{"type": "command", "command": ".claude/hooks/git-safety.sh"}]}]
#
# Config: CLAUDE_TOOLKIT_PROTECTED_BRANCHES="^(main|master)$" (regex, customizable)
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
# Test cases: see tests/test-hooks.sh test_git_safety

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# Configurable protected branches (regex pattern)
PROTECTED_BRANCHES="${CLAUDE_TOOLKIT_PROTECTED_BRANCHES:-^(main|master)$}"

# ============================================================
# match_git_safety — cheap predicate for the Bash branch
# ============================================================
# Returns 0 when $COMMAND looks like a git push or git commit.
# Pure bash pattern matching; no forks, no jq, no git calls.
# False positives are fine (check_ will no-op); false negatives are bugs.
match_git_safety() {
    local stripped
    stripped=$(_strip_inert_content "$COMMAND")
    [[ "$stripped" =~ (^|[[:space:];&|])git[[:space:]]+(push|commit)([[:space:]]|$) ]]
}

# ============================================================
# check_git_safety — guard body for the Bash branch
# ============================================================
# Assumes match_git_safety returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_git_safety() {
    # Strip heredoc/quoted content once — all regexes below match the skeleton.
    local _raw="$COMMAND"
    local COMMAND
    COMMAND=$(_strip_inert_content "$_raw")
    # === git push checks ===
    if echo "$COMMAND" | grep -qE '(^|[;&|]\s*)git\s+push'; then

        # Detect force flags anywhere in the push command
        local IS_FORCE=false
        if echo "$COMMAND" | grep -qE 'git\s+push\b.*(\s--force\b|\s--force-with-lease\b|\s-f\b)'; then
            IS_FORCE=true
        fi

        # --- Severe: git push --mirror ---
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--mirror'; then
            _BLOCK_REASON="git push --mirror overwrites the entire remote repository, deleting all branches and tags not in your local copy. This is not reversible.\n\nRun the command manually outside Claude if you really need this."
            return 1
        fi

        # Extract push target ref from command
        # Strip flags to get positional args: <remote> <refspec>
        local PUSH_ARGS PUSH_REF=""
        PUSH_ARGS=$(echo "$COMMAND" | sed -nE 's/.*(^|[;&|]\s*)git\s+push\s+(.*)/\2/p' | sed -E 's/\s*--?[a-zA-Z][-a-zA-Z]*//g; s/^\s+//; s/\s+/ /g')
        if [[ "$PUSH_ARGS" =~ [^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
            PUSH_REF="${BASH_REMATCH[1]}"
        fi
        # Handle refspec: HEAD:main or local-branch:main → extract target
        if [[ "$PUSH_REF" == *:* ]]; then
            PUSH_REF="${PUSH_REF##*:}"
        fi

        # --- Severe: force push to protected branch ---
        if [[ "$IS_FORCE" == true && -n "$PUSH_REF" && "$PUSH_REF" =~ $PROTECTED_BRANCHES ]]; then
            _BLOCK_REASON="Force push to '$PUSH_REF' would rewrite shared history and can cause permanent data loss for collaborators. This is not reversible.\n\nRun the command manually outside Claude if you really need this."
            return 1
        fi

        # --- Severe: delete protected branch on remote ---
        # Pattern 1: git push --delete <remote> <branch>
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--delete'; then
            local DELETE_BRANCH
            DELETE_BRANCH=$(echo "$COMMAND" | sed -nE 's/.*git\s+push\s+.*--delete\s+\S+\s+(\S+).*/\1/p')
            if [[ -n "$DELETE_BRANCH" && "$DELETE_BRANCH" =~ $PROTECTED_BRANCHES ]]; then
                _BLOCK_REASON="Deleting '$DELETE_BRANCH' from remote would destroy the primary branch for all collaborators. This is not reversible.\n\nRun the command manually outside Claude if you really need this."
                return 1
            fi
        fi
        # Pattern 2: git push <remote> :<branch>
        if echo "$COMMAND" | grep -qE 'git\s+push\s+\S+\s+:[a-zA-Z]'; then
            local COLON_BRANCH
            COLON_BRANCH=$(echo "$COMMAND" | sed -nE 's/.*git\s+push\s+\S+\s+:(\S+).*/\1/p')
            if [[ -n "$COLON_BRANCH" && "$COLON_BRANCH" =~ $PROTECTED_BRANCHES ]]; then
                _BLOCK_REASON="Deleting '$COLON_BRANCH' from remote would destroy the primary branch for all collaborators. This is not reversible.\n\nRun the command manually outside Claude if you really need this."
                return 1
            fi
        fi

        # --- Soft: force push to non-protected branch ---
        if [[ "$IS_FORCE" == true ]]; then
            _BLOCK_REASON="Force pushing rewrites remote history. Collaborators pulling this branch will get conflicts.\n\nRun the command manually outside Claude if you really need this."
            return 1
        fi

        # --- Soft: delete any remote branch ---
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--delete'; then
            _BLOCK_REASON="Deleting a remote branch removes it for all collaborators.\n\nRun the command manually outside Claude if you really need this."
            return 1
        fi
        if echo "$COMMAND" | grep -qE 'git\s+push\s+\S+\s+:[a-zA-Z]'; then
            _BLOCK_REASON="Deleting a remote branch removes it for all collaborators.\n\nRun the command manually outside Claude if you really need this."
            return 1
        fi

        # --- Soft: cross-branch push ---
        if echo "$COMMAND" | grep -qE 'git\s+push\s+.*\S+:\S+'; then
            local REFSPEC TARGET_BRANCH CURRENT_BRANCH
            REFSPEC=$(echo "$COMMAND" | sed -nE 's/.*git\s+push\s+[^;|&]*\s+(\S+:\S+).*/\1/p')
            TARGET_BRANCH="${REFSPEC##*:}"
            CURRENT_BRANCH=$(git branch --show-current 2>/dev/null) || true
            if [[ -n "$TARGET_BRANCH" && -n "$CURRENT_BRANCH" && "$TARGET_BRANCH" != "$CURRENT_BRANCH" ]]; then
                _BLOCK_REASON="Pushing to '$TARGET_BRANCH' while on '$CURRENT_BRANCH'. This can accidentally overwrite another branch.\n\nRun the command manually outside Claude if you really need this."
                return 1
            fi
        fi
    fi

    # === git commit check ===
    if echo "$COMMAND" | grep -qE '(^|[;&|]\s*)git\s+commit'; then
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            return 0
        fi

        local BRANCH
        BRANCH=$(git branch --show-current 2>/dev/null) || return 0

        if [[ -z "$BRANCH" ]]; then
            _BLOCK_REASON="You're in detached HEAD state. Create a feature branch before committing:\n\n  git checkout -b feat/<short-description>"
            return 1
        fi

        if [[ "$BRANCH" =~ $PROTECTED_BRANCHES ]]; then
            _BLOCK_REASON="Cannot commit directly to '$BRANCH'.\n\nCreate a feature branch first:\n\n  git checkout -b feat/<short-description>\n\nThen commit your changes there.\n\nNote: Do not chain git checkout and git commit in a single command — the hook checks the branch at execution time."
            return 1
        fi
    fi

    return 0
}

# ============================================================
# match_git_safety_planmode — predicate for the EnterPlanMode branch
# ============================================================
# Returns 0 when cwd is inside a git repo (the only condition under which
# check_ might block). Forks `git rev-parse` once — same fork the inline
# branch already did, just relocated. EnterPlanMode is a rare per-session
# event so per-call cost dominates throughput; folding into match_git_safety
# (Bash) isn't useful — input shapes differ.
match_git_safety_planmode() {
    git rev-parse --git-dir >/dev/null 2>&1
}

# ============================================================
# check_git_safety_planmode — guard body for the EnterPlanMode branch
# ============================================================
# Assumes match_git_safety_planmode returned true (we're in a git repo).
# Sets _BLOCK_REASON on block. Returns 0 = pass, 1 = block.
# Block conditions:
#   - Detached HEAD (empty current branch) — feature branch needed before plan.
#   - Current branch matches PROTECTED_BRANCHES.
check_git_safety_planmode() {
    local BRANCH
    BRANCH=$(git branch --show-current 2>/dev/null) || return 0

    if [[ -z "$BRANCH" ]]; then
        _BLOCK_REASON="You're in detached HEAD state. Create a feature branch first:\n\n  git checkout -b feat/<short-description>"
        return 1
    fi

    if [[ "$BRANCH" =~ $PROTECTED_BRANCHES ]]; then
        _BLOCK_REASON="Create a feature branch first.\n\nYou're on '$BRANCH' (protected). Before entering plan mode:\n\n  git checkout -b feat/<short-description>\n\nBranch prefixes: feat/, fix/, refactor/, docs/, chore/"
        return 1
    fi

    return 0
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "git-safety" "PreToolUse"
    hook_require_tool "EnterPlanMode" "Bash"

    # --- EnterPlanMode branch — delegate to match_/check_ ---
    if [[ "$TOOL_NAME" == "EnterPlanMode" ]]; then
        _BLOCK_REASON=""
        if match_git_safety_planmode; then
            if ! check_git_safety_planmode; then
                hook_block "$_BLOCK_REASON"
            fi
        fi
        exit 0
    fi

    # --- Bash branch — delegate to match_/check_ ---
    if [[ "$TOOL_NAME" == "Bash" ]]; then
        COMMAND=$(hook_get_input '.tool_input.command')
        [ -z "$COMMAND" ] && exit 0

        _BLOCK_REASON=""
        if match_git_safety; then
            if ! check_git_safety; then
                hook_block "$_BLOCK_REASON"
            fi
        fi
        exit 0
    fi

    # Other tools — allow
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
