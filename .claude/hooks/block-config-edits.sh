#!/bin/bash
# PreToolUse hook: block writes to shell config and SSH files
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# Only the Bash branch participates in the dispatcher — Write/Edit branches
# stay in main (they'd need their own dispatcher — see grouped-write-guard
# backlog item if/when added).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone, narrowed to Write|Edit when dispatcher handles Bash):
#   "PreToolUse": [{"matcher": "Write|Edit|Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/block-config-edits.sh"}]}]
#
# Blocks:
#   Write/Edit tool:
#     - Shell configs: ~/.bashrc, ~/.bash_profile, ~/.bash_login, ~/.profile
#     - Zsh configs: ~/.zshrc, ~/.zprofile, ~/.zshenv, ~/.zlogin
#     - SSH files: ~/.ssh/authorized_keys, ~/.ssh/config
#     - Git config: ~/.gitconfig
#   Bash tool:
#     - Redirect/append (>, >>) to the above paths
#     - sed -i targeting the above paths
#     - mv ... targeting the above paths
#     - NOT read-only commands (grep, cat without redirect)

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# List of blocked config files (basenames and paths relative to home)
# Used for Write/Edit tool path matching
BLOCKED_CONFIGS=(
    ".bashrc"
    ".bash_profile"
    ".bash_login"
    ".profile"
    ".zshrc"
    ".zprofile"
    ".zshenv"
    ".zlogin"
    ".ssh/authorized_keys"
    ".ssh/config"
    ".gitconfig"
)

# Check if a path matches a blocked config file
is_blocked_config() {
    local filepath="$1"

    # Normalize ~ to $HOME
    if [[ "$filepath" == "~/"* ]]; then
        filepath="$HOME/${filepath#\~/}"
    fi

    for config in "${BLOCKED_CONFIGS[@]}"; do
        if [[ "$filepath" == "$HOME/$config" ]]; then
            return 0
        fi
    done
    return 1
}

# ============================================================
# match_config_edits — cheap predicate for the Bash branch
# ============================================================
# Returns 0 when $COMMAND contains a write-ish verb (>, >>, tee, sed -i, mv)
# near a config-file basename OR a home-dir hint. Deliberately broad —
# correctness beats optimization (see §4 of relevant-toolkit-hooks.md).
# Pure bash pattern matching — no forks, no jq, no git.
match_config_edits() {
    local CONFIG_HINT='(bashrc|bash_profile|bash_login|profile|zshrc|zprofile|zshenv|zlogin|gitconfig|authorized_keys|\.ssh/config)'
    local VERB_HINT='(>>|[^>]>[^>]|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]])'
    [[ "$COMMAND" =~ $CONFIG_HINT ]] && [[ "$COMMAND" =~ $VERB_HINT ]]
}

# ============================================================
# check_config_edits — guard body for the Bash branch
# ============================================================
# Assumes match_config_edits returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_config_edits() {
    # Home config path pattern: ~/.<config> or $HOME/.<config>
    # Requires explicit home dir prefix to prevent false positives from project paths or JSON payloads
    local CONFIGS='(\.(bashrc|bash_profile|bash_login|profile|zshrc|zprofile|zshenv|zlogin|gitconfig)|\.ssh/(authorized_keys|config))'
    local HOME_CONFIG="(~|\\\$HOME|\\\$\{HOME\})/$CONFIGS"

    # Block append (>>) to home config
    local APPEND_RE=">>.*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $APPEND_RE ]]; then
        _BLOCK_REASON="BLOCKED: Appending to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi

    # Block tee targeting home config files
    local TEE_RE="tee[[:space:]].*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $TEE_RE ]]; then
        _BLOCK_REASON="BLOCKED: Writing to shell/SSH/git config via tee risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi

    # Block sed -i targeting home config files
    local SED_RE="sed[[:space:]]+-i.*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $SED_RE ]]; then
        _BLOCK_REASON="BLOCKED: Editing shell/SSH/git config in-place risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi

    # Block mv targeting home config files
    local MV_RE="mv[[:space:]].*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $MV_RE ]]; then
        _BLOCK_REASON="BLOCKED: Moving file to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi

    return 0
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "block-config-edits" "PreToolUse"
    hook_require_tool "Write" "Edit" "Bash"

    # --- Handler: Write tool ---
    if [ "$TOOL_NAME" = "Write" ]; then
        local FILE_PATH
        FILE_PATH=$(hook_get_input '.tool_input.file_path')
        [ -z "$FILE_PATH" ] && exit 0

        if is_blocked_config "$FILE_PATH"; then
            hook_block "BLOCKED: Writing to shell/SSH/git config files risks persistent environment poisoning. Use project-level .envrc or local config instead."
        fi

        exit 0
    fi

    # --- Handler: Edit tool ---
    if [ "$TOOL_NAME" = "Edit" ]; then
        local FILE_PATH
        FILE_PATH=$(hook_get_input '.tool_input.file_path')
        [ -z "$FILE_PATH" ] && exit 0

        if is_blocked_config "$FILE_PATH"; then
            hook_block "BLOCKED: Editing shell/SSH/git config files risks persistent environment poisoning. Use project-level .envrc or local config instead."
        fi

        exit 0
    fi

    # --- Bash branch — delegate to match_/check_ ---
    if [ "$TOOL_NAME" = "Bash" ]; then
        COMMAND=$(hook_get_input '.tool_input.command')
        [ -z "$COMMAND" ] && exit 0

        _BLOCK_REASON=""
        if match_config_edits; then
            if ! check_config_edits; then
                hook_block "$_BLOCK_REASON"
            fi
        fi
        exit 0
    fi

    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
