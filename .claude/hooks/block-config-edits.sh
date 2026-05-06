#!/usr/bin/env bash
# CC-HOOK: NAME: block-config-edits
# CC-HOOK: PURPOSE: Block writes to shell config, SSH files, and Claude settings
# CC-HOOK: EVENTS: PreToolUse(Write|Edit)
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: DISPATCH-FN: grouped-bash-guard=config_edits
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=58, scope_hit=76
# CC-HOOK: OPT-IN: none
#
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
# Settings-path coverage (.claude/settings.json, .claude/settings.local.json):
# default-deny — any write-shaped verb token (>, >>, tee, sed -i, mv, cp, install,
# dd, truncate, rsync, awk -i, chmod, chown, ln -s) appearing alongside the path
# in the stripped command blocks. Read-only verbs (cat, grep, jq, head, tail, wc,
# diff, ls, find, stat, file) referencing the path pass through. Symlink writes
# (creating a symlink to settings, or redirecting to a pre-existing symlink that
# resolves to settings) are caught via realpath -m, gated by match_ already firing.
# Interpreter bodies covered: python, bash, sh, ruby, perl, node — all -c/-e/<<.

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/detection-registry.sh"
detection_registry_load

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
    # Verb hint kept broad — once any of these appears alongside a config-shaped
    # path, check_ runs the precise filter. False positives are fine; false
    # negatives are bugs. See .claude/docs/relevant-toolkit-hooks.md §4.
    local VERB_HINT='(>>|[^>]>[^>]|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]]|cp[[:space:]]|install[[:space:]]|dd[[:space:]]|truncate[[:space:]]|rsync[[:space:]]|awk[[:space:]]+-i|chmod[[:space:]]|chown[[:space:]]|ln[[:space:]]+-s)'
    local INTERP_HINT='(python[0-9.]*|bash|sh|ruby|perl|node)[[:space:]]+(-c|-e|<<)'
    if [[ "$COMMAND" =~ $CONFIG_HINT ]]; then
        [[ "$COMMAND" =~ $VERB_HINT ]] || [[ "$COMMAND" =~ $INTERP_HINT ]]
        return
    fi
    # Symlink defense gate: fire match_ when a write-shaped verb is present,
    # so check_ can resolve symlink targets via realpath. The realpath fork
    # only happens for tokens that are actual symlinks ([ -L ]), so the
    # broadened match_ surface stays cheap in steady state. Confined to a
    # narrower subset than VERB_HINT (drop sed -i / mv-only / etc. that have
    # no symlink-trampoline angle in normal use).
    local SYMLINK_GATE='([^>]|^)>[[:space:]]|>>[[:space:]]|tee[[:space:]]|cp[[:space:]]|mv[[:space:]]'
    [[ "$COMMAND" =~ $SYMLINK_GATE ]]
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

    # Block writes to home config — kept per-verb because the home patterns
    # are anchored on ~/$HOME and the verb context ties the regex to actual
    # write operations rather than mere mentions of a config name.
    local APPEND_RE_HOME=">>.*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $APPEND_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Appending to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi
    local TEE_RE_HOME="tee[[:space:]].*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $TEE_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Writing to shell/SSH/git config via tee risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi
    local SED_RE_HOME="sed[[:space:]]+-i.*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $SED_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Editing shell/SSH/git config in-place risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi
    local MV_RE_HOME="mv[[:space:]].*$HOME_CONFIG"
    if [[ "$COMMAND" =~ $MV_RE_HOME ]]; then
        _BLOCK_REASON="BLOCKED: Moving file to shell/SSH/git config risks persistent environment poisoning. Use project-level .envrc or local config instead."
        return 1
    fi

    # ============================================================
    # Settings-path side: default-deny
    # ============================================================
    # If .claude/settings(.local)?.json appears in the stripped command (so
    # references inside quoted strings or heredoc bodies don't false-positive)
    # AND any write-shaped verb token also appears, block. Read-only verbs
    # (cat, grep, jq, head, tail, wc, diff, ls, find, stat, file) on settings
    # are common enough that the read-only allowlist is documented as the
    # invariant, not the verb list. New shell verbs that read but don't write
    # (e.g. bat, rg, eza) need an entry here when they show up — see the
    # hooks-readonly-verb-allowlist-audit backlog item.
    local SETTINGS_BARE='\.claude/settings(\.local)?\.json'
    if [[ "$COMMAND" =~ $SETTINGS_BARE ]]; then
        local SETTINGS_WRITE_VERB='(>>|>|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]]|cp[[:space:]]|install[[:space:]]|dd[[:space:]]|truncate[[:space:]]|rsync[[:space:]]|awk[[:space:]]+-i|chmod[[:space:]]|chown[[:space:]]|ln[[:space:]]+-s)'
        if [[ "$COMMAND" =~ $SETTINGS_WRITE_VERB ]]; then
            _BLOCK_REASON="$(_settings_reason 'Writing to')"
            return 1
        fi
    fi

    # Symlink defense — gated by the match_ hint so the realpath fork only
    # happens on commands that already look settings-shaped. Two angles:
    #   (a) `ln -s <target> <link>` where <target> resolves under .claude/
    #       settings — catches the symlink-creation step.
    #   (b) `... > <path>` (or >>, tee, etc.) where <path> exists as a symlink
    #       resolving under .claude/settings — catches write-through-symlink
    #       on a pre-existing trampoline.
    # Both conditions match against the raw command (we want literal token
    # paths, not stripped). realpath -m doesn't error on missing components.
    if command -v realpath >/dev/null 2>&1; then
        # (a) ln -s creation
        if [[ "$_raw" =~ ln[[:space:]]+-s[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            local _ln_target="${BASH_REMATCH[1]}" _ln_link="${BASH_REMATCH[2]}"
            local _resolved
            _resolved=$(realpath -m "$_ln_target" 2>/dev/null)
            if [[ "$_resolved" =~ /\.claude/settings(\.local)?\.json$ ]]; then
                _BLOCK_REASON="$(_settings_reason 'Creating symlink to')"
                return 1
            fi
            # Also catch `ln -s settings.json link-in-claude` (link side under .claude)
            _resolved=$(realpath -m "$_ln_link" 2>/dev/null)
            if [[ "$_resolved" =~ /\.claude/settings(\.local)?\.json$ ]]; then
                _BLOCK_REASON="$(_settings_reason 'Creating symlink at')"
                return 1
            fi
        fi
        # (b) write-through-symlink: scan tokens following >, >>, or following
        # tee/cp/mv/sed -i/etc., resolve them, block if they land on settings.
        # Cheap version: walk every whitespace-separated token in the raw cmd,
        # skip obvious non-paths, resolve, test.
        local _tok
        for _tok in $_raw; do
            # Skip flag-shaped and verb-shaped tokens; only test path-shaped.
            case "$_tok" in
                -*|*=*|'>'|'>>'|'<'|'|'|'&&'|';'|'&'|'||') continue ;;
            esac
            # Only test tokens that exist as a symlink — keeps fork count low.
            [ -L "$_tok" ] || continue
            local _resolved
            _resolved=$(realpath -m "$_tok" 2>/dev/null)
            if [[ "$_resolved" =~ /\.claude/settings(\.local)?\.json$ ]]; then
                _BLOCK_REASON="$(_settings_reason 'Writing through symlink to')"
                return 1
            fi
        done
    fi

    # Interpreter-body settings writes: python -c, bash -c, sh -c, ruby -e,
    # perl -e, node -e, plus heredoc forms for any of these. Runs against the
    # RAW command via the detection registry — _strip_inert_content blanks
    # quoted/heredoc bodies, which is exactly where interpreter payloads live.
    # Conjunction (interpreter token AND registered settings path) keeps the
    # false-positive surface small.
    local INTERP_RE='(python[0-9.]*|bash|sh|ruby|perl|node)[[:space:]]+(-c|-e|<<)'
    if [[ "$_raw" =~ $INTERP_RE ]] \
       && detection_registry_match path raw "$_raw" \
       && [ "$_REGISTRY_MATCHED_ID" = "claude-settings" ]; then
        _BLOCK_REASON="$(_settings_reason 'Editing via interpreter')"
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
# match_config_edits_path — predicate for the Write/Edit branches
# ============================================================
# Returns 0 when FILE_PATH targets a blocked shell/SSH/git config or a
# .claude/settings(.local)?.json. Mirrors the pair shape used by the Bash
# branch (match_config_edits / check_config_edits) so Shape A coverage and
# the framework's match→check contract apply uniformly across event surfaces.
match_config_edits_path() {
    is_blocked_config "$FILE_PATH" || is_blocked_settings "$FILE_PATH"
}

# ============================================================
# check_config_edits_path — guard body for the Write/Edit branches
# ============================================================
# Inputs (globals set by main()): FILE_PATH, VERB ("Writing"|"Editing"),
# PERMISSION_MODE.
# Returns 0 = pass, 1 = block (sets _BLOCK_REASON).
# For .claude/settings*.json paths, delegates to _settings_decision which
# exits via hook_block (auto-mode) or hook_ask (default/acceptEdits/plan).
# Shape A drives the home-config block path (rc=1) only — the settings
# branch is exercised end-to-end by Shape B (test-block-config.sh).
check_config_edits_path() {
    if is_blocked_config "$FILE_PATH"; then
        # Preserve exact wording per VERB — Write was "Writing to ..." while
        # Edit was "Editing ..." (no preposition); changing either would alter
        # observable behavior captured by Shape B fixtures.
        if [ "$VERB" = "Writing" ]; then
            _BLOCK_REASON="BLOCKED: Writing to shell/SSH/git config files risks persistent environment poisoning. Use project-level .envrc or local config instead."
        else
            _BLOCK_REASON="BLOCKED: $VERB shell/SSH/git config files risks persistent environment poisoning. Use project-level .envrc or local config instead."
        fi
        return 1
    fi
    if is_blocked_settings "$FILE_PATH"; then
        _settings_decision "$VERB"
    fi
    return 0
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "block-config-edits" "PreToolUse"
    hook_require_tool "Write" "Edit" "Bash"

    PERMISSION_MODE=$(hook_get_input '.permission_mode')

    # --- Handler: Write tool — delegate to match_/check_ ---
    if [ "$TOOL_NAME" = "Write" ]; then
        FILE_PATH=$(hook_get_input '.tool_input.file_path')
        [ -z "$FILE_PATH" ] && exit 0

        VERB="Writing"
        _BLOCK_REASON=""
        if match_config_edits_path; then
            if ! check_config_edits_path; then
                hook_block "$_BLOCK_REASON"
            fi
        fi
        exit 0
    fi

    # --- Handler: Edit tool — delegate to match_/check_ ---
    if [ "$TOOL_NAME" = "Edit" ]; then
        FILE_PATH=$(hook_get_input '.tool_input.file_path')
        [ -z "$FILE_PATH" ] && exit 0

        VERB="Editing"
        _BLOCK_REASON=""
        if match_config_edits_path; then
            if ! check_config_edits_path; then
                hook_block "$_BLOCK_REASON"
            fi
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
