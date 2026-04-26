#!/bin/bash
# PreToolUse hook: block writes to shell config, SSH files, and Claude settings
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
#     - Claude settings (mode-dependent): .claude/settings.json,
#       .claude/settings.local.json — hard-block under permission_mode=auto,
#       ask under default/acceptEdits/plan (legitimate user-driven edits exist)
#   Bash tool:
#     - Redirect/append (>, >>) to the above paths
#     - sed -i targeting the above paths
#     - mv ... targeting the above paths
#     - NOT read-only commands (grep, cat without redirect)
#
# Known unprotected vectors (documented gaps, not bugs):
#   - Symlink redirection (e.g. ln -s .claude/settings.json /tmp/x; write /tmp/x).
#     The Bash regex matches typed paths, not realpath-resolved targets. Adding
#     realpath() costs a fork per Write call; deferred until seen in the wild.
#   - Shell/python script edits (python -c "open('.claude/settings.local.json','w')...",
#     node -e ..., perl -e ...). The Bash regex hints don't introspect interpreter
#     bodies. Tracked as a follow-up backlog task.

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

    # Normalize a literal leading "~/" typed by the user to $HOME.
    # shellcheck disable=SC2088  # intentional literal-tilde match, not expansion
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

# Check if a path targets .claude/settings.json or .claude/settings.local.json.
# Matches both project-relative (.claude/settings.json) and absolute paths
# whose suffix is .claude/settings.json or .claude/settings.local.json.
# settings.template.json is intentionally NOT matched — it's a template that
# tooling legitimately rewrites; it has no live effect on Claude Code.
is_blocked_settings() {
    local filepath="$1"
    [[ "$filepath" =~ (^|/)\.claude/settings(\.local)?\.json$ ]]
}

# ============================================================
# match_config_edits — cheap predicate for the Bash branch
# ============================================================
# Returns 0 when $COMMAND contains a write-ish verb (>, >>, tee, sed -i, mv)
# near a config-file basename OR a home-dir hint. Deliberately broad —
# correctness beats optimization (see §4 of relevant-toolkit-hooks.md).
# Pure bash pattern matching — no forks, no jq, no git.
match_config_edits() {
    local CONFIG_HINT='(bashrc|bash_profile|bash_login|profile|zshrc|zprofile|zshenv|zlogin|gitconfig|authorized_keys|\.ssh/config|\.claude/settings(\.local)?\.json)'
    local VERB_HINT='(>>|[^>]>[^>]|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]])'
    [[ "$COMMAND" =~ $CONFIG_HINT ]] && [[ "$COMMAND" =~ $VERB_HINT ]]
}

# ============================================================
# check_config_edits — guard body for the Bash branch
# ============================================================
# Assumes match_config_edits returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_config_edits() {
    # Path detection runs against the stripped command skeleton — same convention
    # as secrets-guard and the registry's path/stripped target. This prevents
    # false positives from settings paths appearing as data inside heredocs or
    # 'single-quoted' strings (e.g. `jq -nc --arg p '.claude/settings.json' ...`).
    # The home-config patterns above are anchor-prefixed (~/$HOME) which makes
    # them naturally robust to data appearance, but settings paths are project-
    # relative and would false-positive without stripping.
    local _raw="$COMMAND"
    local COMMAND
    COMMAND=$(_strip_inert_content "$_raw")

    # Home config path pattern: ~/.<config> or $HOME/.<config>
    # Requires explicit home dir prefix to prevent false positives from project paths or JSON payloads
    local CONFIGS='(\.(bashrc|bash_profile|bash_login|profile|zshrc|zprofile|zshenv|zlogin|gitconfig)|\.ssh/(authorized_keys|config))'
    local HOME_CONFIG="(~|\\\$HOME|\\\$\{HOME\})/$CONFIGS"

    # Settings path: bare segment, used in patterns where the verb-side regex
    # already provides the left boundary (consuming a space). All settings
    # patterns below pre-supply that boundary themselves.
    local SETTINGS_BARE='\.claude/settings(\.local)?\.json'

    # Block append (>>) to home config or settings
    local APPEND_RE_HOME=">>.*$HOME_CONFIG"
    local APPEND_RE_SETTINGS=">>[[:space:]]+$SETTINGS_BARE"
    if [[ "$COMMAND" =~ $APPEND_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Appending to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi
    if [[ "$COMMAND" =~ $APPEND_RE_SETTINGS ]]; then
        _BLOCK_REASON="$(_settings_reason 'Appending to')"
        return 1
    fi

    # Block tee targeting home config or settings.
    # tee branch covers both `tee FILE` and `tee -a FILE`/`tee -a -- FILE`.
    local TEE_RE_HOME="tee[[:space:]].*$HOME_CONFIG"
    local TEE_RE_SETTINGS="tee[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*$SETTINGS_BARE"
    if [[ "$COMMAND" =~ $TEE_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Writing to shell/SSH/git config via tee risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi
    if [[ "$COMMAND" =~ $TEE_RE_SETTINGS ]]; then
        _BLOCK_REASON="$(_settings_reason 'Writing via tee to')"
        return 1
    fi

    # Block sed -i targeting home config or settings
    local SED_RE_HOME="sed[[:space:]]+-i.*$HOME_CONFIG"
    local SED_RE_SETTINGS="sed[[:space:]]+-i.*[[:space:]]$SETTINGS_BARE"
    if [[ "$COMMAND" =~ $SED_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Editing shell/SSH/git config in-place risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi
    if [[ "$COMMAND" =~ $SED_RE_SETTINGS ]]; then
        _BLOCK_REASON="$(_settings_reason 'Editing in-place')"
        return 1
    fi

    # Block mv targeting home config or settings
    local MV_RE_HOME="mv[[:space:]].*$HOME_CONFIG"
    local MV_RE_SETTINGS="mv[[:space:]].*[[:space:]]$SETTINGS_BARE"
    if [[ "$COMMAND" =~ $MV_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Moving file to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi
    if [[ "$COMMAND" =~ $MV_RE_SETTINGS ]]; then
        _BLOCK_REASON="$(_settings_reason 'Moving file to')"
        return 1
    fi

    # Block single-redirect (>) to settings — covers `cat foo > .claude/settings.local.json`.
    # Lead char [^>] (or start) ensures we don't double-match >> here.
    local SINGLE_REDIR_RE_SETTINGS='([^>]|^)>[[:space:]]+'"$SETTINGS_BARE"
    if [[ "$COMMAND" =~ $SINGLE_REDIR_RE_SETTINGS ]]; then
        _BLOCK_REASON="$(_settings_reason 'Redirecting output to')"
        return 1
    fi

    return 0
}

# Compose a settings-targeted block reason. The Bash branch always blocks
# (no ask path from inside a Bash command — the user can re-run the command
# themselves if they want it to happen). Mode-aware ask vs block lives in
# the Write/Edit branches in main(), where the tool surface allows it.
_settings_reason() {
    local verb="$1"
    echo "BLOCKED: $verb .claude/settings*.json from a Bash command bypasses Claude Code's settings-edit confirmation. Edit via the Edit tool (you'll be asked to confirm), or run the command yourself outside this session."
}

# ============================================================
# _settings_decision VERB
# ============================================================
# Routes the Write/Edit settings-edit decision based on permission_mode:
#   - auto              → hard-block (matches the auto-mode rampage threat —
#                         disableAllHooks: true is the canonical bypass)
#   - default/acceptEdits/plan → ask (settings have legitimate edit flows;
#                         the user is the human checkpoint)
# Reads PERMISSION_MODE global parsed by main(). VERB is "Writing" or "Editing".
_settings_decision() {
    local verb="$1"
    if [ "$PERMISSION_MODE" = "auto" ]; then
        hook_block "BLOCKED (auto-mode): $verb .claude/settings*.json under permission_mode=auto. Settings edits can disable safety hooks (e.g. disableAllHooks: true) or override permissions.ask rules — exactly the scope drift auto-mode does not gate. Stop and report to the user; they can switch out of auto-mode and re-approve."
    fi
    hook_ask "$verb .claude/settings*.json — confirm this is intentional. Settings can disable safety hooks or change permissions; the change persists across sessions."
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "block-config-edits" "PreToolUse"
    hook_require_tool "Write" "Edit" "Bash"

    PERMISSION_MODE=$(hook_get_input '.permission_mode')

    # --- Handler: Write tool ---
    if [ "$TOOL_NAME" = "Write" ]; then
        local FILE_PATH
        FILE_PATH=$(hook_get_input '.tool_input.file_path')
        [ -z "$FILE_PATH" ] && exit 0

        if is_blocked_config "$FILE_PATH"; then
            hook_block "BLOCKED: Writing to shell/SSH/git config files risks persistent environment poisoning. Use project-level .envrc or local config instead."
        fi

        if is_blocked_settings "$FILE_PATH"; then
            _settings_decision "Writing"
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

        if is_blocked_settings "$FILE_PATH"; then
            _settings_decision "Editing"
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
