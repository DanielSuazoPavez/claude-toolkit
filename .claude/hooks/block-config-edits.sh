#!/bin/bash
# PreToolUse hook: block writes to shell config and SSH files
#
# Settings.json:
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

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

# Helper function to block with reason
block() {
    echo "{\"decision\": \"block\", \"reason\": \"$1\"}"
    exit 0
}

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

# Handle Write tool
if [ "$TOOL_NAME" = "Write" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
    [ -z "$FILE_PATH" ] && exit 0

    if is_blocked_config "$FILE_PATH"; then
        block "BLOCKED: Writing to shell/SSH/git config files risks persistent environment poisoning. Use project-level .envrc or local config instead."
    fi

    exit 0
fi

# Handle Edit tool
if [ "$TOOL_NAME" = "Edit" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
    [ -z "$FILE_PATH" ] && exit 0

    if is_blocked_config "$FILE_PATH"; then
        block "BLOCKED: Editing shell/SSH/git config files risks persistent environment poisoning. Use project-level .envrc or local config instead."
    fi

    exit 0
fi

# Handle Bash tool
if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
    [ -z "$COMMAND" ] && exit 0

    # Home config path pattern: ~/.<config> or $HOME/.<config>
    # Requires explicit home dir prefix to prevent false positives from project paths or JSON payloads
    CONFIGS='(\.(bashrc|bash_profile|bash_login|profile|zshrc|zprofile|zshenv|zlogin|gitconfig)|\.ssh/(authorized_keys|config))'
    HOME_CONFIG="(~|\\\$HOME|\\\$\{HOME\})/$CONFIGS"

    # Block append (>>) to home config
    APPEND_RE=">>.*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $APPEND_RE ]]; then
        block "BLOCKED: Appending to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
    fi

    # Block tee targeting home config files
    TEE_RE="tee[[:space:]].*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $TEE_RE ]]; then
        block "BLOCKED: Writing to shell/SSH/git config via tee risks persistent environment poisoning. Use project-level .envrc or local config instead."
    fi

    # Block sed -i targeting home config files
    SED_RE="sed[[:space:]]+-i.*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $SED_RE ]]; then
        block "BLOCKED: Editing shell/SSH/git config in-place risks persistent environment poisoning. Use project-level .envrc or local config instead."
    fi

    # Block mv targeting home config files
    MV_RE="mv[[:space:]].*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $MV_RE ]]; then
        block "BLOCKED: Moving file to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
    fi

    exit 0
fi

exit 0
