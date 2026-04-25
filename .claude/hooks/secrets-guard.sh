#!/bin/bash
# PreToolUse hook: block reading secrets and credential files
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# Only the Bash branch participates in the dispatcher — Read/Grep branches
# stay in main (they'd need their own dispatcher — see grouped-read-guard).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Read|Bash|Grep", "hooks": [{"type": "command", "command": "bash .claude/hooks/secrets-guard.sh"}]}]
#
# Blocks:
#   Read tool:
#     - Files matching .env, .env.*, *.env (except .example files)
#     - SSH private keys (~/.ssh/id_* except *.pub), SSH config
#     - GPG directory (~/.gnupg/)
#     - Cloud credentials (~/.aws/credentials, ~/.aws/config)
#     - CLI tokens (~/.config/gh/hosts.yml, ~/.docker/config.json, ~/.kube/config)
#     - Package manager tokens (~/.npmrc, ~/.pypirc, ~/.gem/credentials)
#   Bash tool:
#     - cat .env, less .env, head .env, tail .env
#     - grep/rg/awk/sed targeting .env files
#     - source .env, . .env
#     - export $(cat .env)
#     - env, printenv (lists all env vars)
#     - cat/less/head/tail/grep/rg/awk/sed of credential files
#     - gpg --export-secret-keys
#   Grep tool:
#     - path targeting .env, .env.*, *.env files (except .example/.template)
#     - path targeting credential files (same set as Read tool)
#     - glob patterns: .env*, .env.*, *.env
#
# Allowlist:
#   - Files ending in .example (e.g., .env.example, .env.api.example)
#   - Files ending in .template (e.g., .env.template)
#   - SSH public keys (*.pub), known_hosts, authorized_keys
#   - Grep with .example/.template globs or paths
#
# Test cases: see tests/test-hooks.sh test_secrets_guard

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# --- Shared data and helpers (used by Read and Grep handlers in main) ---

# Blocked credential paths: "pattern:::description"
# Description is verb-neutral; callers prefix with "Reading"/"Searching"
BLOCKED_PATHS=(
    "$HOME/.ssh/config:::SSH config may expose hostnames, key paths, and proxy settings"
    "$HOME/.gnupg/:::GPG directory may expose private keys and trust data"
    "$HOME/.aws/credentials:::AWS credentials may expose access keys and secrets"
    "$HOME/.aws/config:::AWS config may expose access keys and secrets"
    "$HOME/.config/gh/hosts.yml:::GitHub CLI config may expose authentication tokens"
    "$HOME/.docker/config.json:::Docker config may expose registry authentication tokens"
    "$HOME/.kube/config:::kubeconfig may expose cluster credentials and tokens"
    "$HOME/.npmrc:::.npmrc may expose npm authentication tokens"
    "$HOME/.pypirc:::.pypirc may expose PyPI authentication tokens"
    "$HOME/.gem/credentials:::gem credentials may expose RubyGems API keys"
)

# Normalize a literal leading "~/" typed by the user to $HOME.
normalize_path() {
    local p="$1"
    # shellcheck disable=SC2088  # intentional literal-tilde match, not expansion
    if [[ "$p" == "~/"* ]]; then
        p="$HOME/${p#\~/}"
    fi
    echo "$p"
}

# Return block reason (stdout) for a sensitive .env filename, or empty to pass.
# Usage: reason=$(_env_file_block_reason <filename> <verb>)
#   verb: "Reading" or "Searching"
_env_file_block_reason() {
    local filename="$1" verb="$2"
    # Allow .example and .template files
    if [[ "$filename" =~ \.(example|template)$ ]]; then
        return 0
    fi
    # Block .env, .env.*, or *.env files
    if [[ "$filename" = ".env" ]] || [[ "$filename" =~ ^\.env\. ]] || [[ "$filename" =~ \.env$ ]]; then
        echo "BLOCKED: $verb .env file may expose secrets. Use the .example version as a reference instead."
    fi
}

# Return block reason (stdout) for a credential-path match, or empty to pass.
# Usage: reason=$(_credential_path_block_reason <normalized_path> <verb>)
#   verb: "Reading" or "Searching"
_credential_path_block_reason() {
    local norm_path="$1" verb="$2"

    for entry in "${BLOCKED_PATHS[@]}"; do
        local pattern="${entry%%:::*}"
        local message="${entry##*:::}"
        if [[ "$norm_path" == "$pattern" ]] || [[ "$pattern" == */ && ( "$norm_path" == "$pattern"* || "$norm_path/" == "$pattern" ) ]]; then
            echo "BLOCKED: $verb $message."
            return 0
        fi
    done

    # SSH private keys (allow .pub files)
    if [[ "$norm_path" == "$HOME/.ssh/id_"* ]] && [[ "$norm_path" != *".pub" ]]; then
        echo "BLOCKED: $verb SSH private key. Private keys should never be exposed to AI tools."
    fi
}

# Thin wrappers preserving the pre-existing exit-on-block contract used by main().
# WARNING: May call exit 0 or hook_block() — must run in main shell, not a subshell.
check_env_file() {
    local reason
    reason=$(_env_file_block_reason "$1" "$2")
    [ -n "$reason" ] && hook_block "$reason"
}

check_credential_path() {
    local reason
    reason=$(_credential_path_block_reason "$1" "$2")
    [ -n "$reason" ] && hook_block "$reason"
}

# ============================================================
# match_/check_ pairs for the grouped-read-guard dispatcher
# ============================================================
# Contract: dispatcher sets FILE_PATH (Read) or GREP_PATH/GREP_GLOB (Grep)
# before calling match_; check_ returns 0=pass, 1=block (sets _BLOCK_REASON).
#
# Broad regex shared between match_*_read and match_*_grep — cheap predicate
# covering every credential-path hint we block. Actual decision lives in check_.
_SECRETS_MATCH_RE='\.env($|\.|/)|\.ssh/id_|\.gnupg|\.aws/|\.kube/|\.config/gh|\.docker/|\.npmrc|\.pypirc|\.gem/|\.git/config$'

# Credential-shape regex for embedded user:secret in remote URLs.
# Matches `user:pass@host` style — short passwords are still secrets.
_REMOTE_CRED_RE='[A-Za-z0-9._-]+:[^@/[:space:]]+@'

# Resolve remote URL(s) for a git target and return 0 if any embeds a credential.
# Usage: _git_dir_has_credential_remote <worktree|.git-dir|.git/config-path>
# Treats anything we can't parse as "no credential" — never spurious blocks.
_git_dir_has_credential_remote() {
    local target="$1" url
    local -a git_args config_args
    [ -n "$target" ] || return 1
    if [ -f "$target" ] && [[ "$target" == *"/.git/config" || "$target" == ".git/config" ]]; then
        # Read the config file directly — works without a worktree.
        git_args=()
        config_args=(--file "$target")
    elif [ -d "$target/.git" ] || [ -d "$target" ]; then
        git_args=(-C "$target")
        config_args=()
    else
        return 1
    fi
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        if [[ "$url" =~ $_REMOTE_CRED_RE ]]; then
            return 0
        fi
    done < <(git "${git_args[@]}" config "${config_args[@]}" --get-regexp '^remote\..*\.url$' 2>/dev/null | awk '{print $2}')
    return 1
}

match_secrets_guard_read() {
    [ -n "$FILE_PATH" ] || return 1
    local base norm
    base=$(basename "$FILE_PATH")
    norm=$(normalize_path "$FILE_PATH")
    [[ "$base" =~ $_SECRETS_MATCH_RE ]] || [[ "$norm" =~ $_SECRETS_MATCH_RE ]]
}

check_secrets_guard_read() {
    local reason norm
    norm=$(normalize_path "$FILE_PATH")
    reason=$(_env_file_block_reason "$(basename "$FILE_PATH")" "Reading")
    if [ -n "$reason" ]; then
        _BLOCK_REASON="$reason"
        return 1
    fi
    reason=$(_credential_path_block_reason "$norm" "Reading")
    if [ -n "$reason" ]; then
        _BLOCK_REASON="$reason"
        return 1
    fi
    # .git/config — block only when an embedded credential is present.
    if [[ "$norm" =~ \.git/config$ ]] && _git_dir_has_credential_remote "$norm"; then
        _BLOCK_REASON="BLOCKED: This repository's remote URL embeds a credential. Reading .git/config would put a token in your context. Use \`git branch --show-current\` for the branch, the push-output hint for PR URLs, or ask the user."
        return 1
    fi
    return 0
}

match_secrets_guard_grep() {
    [ -n "$GREP_PATH" ] || [ -n "$GREP_GLOB" ] || return 1
    [ -n "$GREP_PATH" ] && [[ "$GREP_PATH" =~ $_SECRETS_MATCH_RE ]] && return 0
    [ -n "$GREP_GLOB" ] && [[ "$GREP_GLOB" =~ \.env ]] && return 0
    return 1
}

check_secrets_guard_grep() {
    local reason
    if [ -n "$GREP_PATH" ]; then
        reason=$(_env_file_block_reason "$(basename "$GREP_PATH")" "Searching")
        if [ -n "$reason" ]; then
            _BLOCK_REASON="$reason"
            return 1
        fi
        reason=$(_credential_path_block_reason "$(normalize_path "$GREP_PATH")" "Searching")
        if [ -n "$reason" ]; then
            _BLOCK_REASON="$reason"
            return 1
        fi
    fi
    if [ -n "$GREP_GLOB" ]; then
        # Allow .example/.template globs first
        if [[ "$GREP_GLOB" =~ \.(example|template)$ ]]; then
            return 0
        fi
        if [[ "$GREP_GLOB" == ".env" ]] || \
           [[ "$GREP_GLOB" == ".env*" ]] || \
           [[ "$GREP_GLOB" == ".env.*" ]] || \
           [[ "$GREP_GLOB" == "*.env" ]]; then
            _BLOCK_REASON="BLOCKED: Grep glob pattern targets .env files which may expose secrets."
            return 1
        fi
    fi
    return 0
}

# ============================================================
# match_secrets_guard — cheap predicate for the Bash branch
# ============================================================
# Returns 0 when $COMMAND contains any token that could trigger a check:
# a read-like verb, env/printenv, source/., gpg, or a credential-path hint.
# Pure bash pattern matching — no forks, no jq, no git.
# Deliberately broad to preserve false-positive semantics.
match_secrets_guard() {
    local stripped re raw_re
    stripped=$(_strip_inert_content "$COMMAND")
    re='(^|[[:space:];&|])(cat|less|head|tail|more|grep|rg|awk|sed|source|\.|env|printenv|export|gpg|git)([[:space:]]|$)|\.env|\.ssh/id_|\.aws/|\.kube/|\.config/gh|\.docker/|\.npmrc|\.pypirc|\.gem/|\.git/config'
    [[ "$stripped" =~ $re ]] && return 0
    # Credential-shaped env var refs survive only in $_raw — strip blanks them.
    raw_re='echo[[:space:]]+.*\$\{?[A-Z][A-Z0-9_]*'
    [[ "$COMMAND" =~ $raw_re ]]
}

# ============================================================
# check_secrets_guard — guard body for the Bash branch
# ============================================================
# Assumes match_secrets_guard returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_secrets_guard() {
    # Strip heredoc/quoted content once — all regexes below match the skeleton.
    # Capture the outer $COMMAND first, then shadow with the stripped version.
    local _raw="$COMMAND"
    local COMMAND
    COMMAND=$(_strip_inert_content "$_raw")

    # Targeted env-var echo via double-quoted interpolation:
    # `_strip_inert_content` blanks "${VAR}" content, so we check raw first.
    # Single-quoted '$VAR' is not interpolation — exclude.
    local CRED_VAR_RE='([A-Z][A-Z0-9_]*(_TOKEN|_SECRET|_API_KEY|_PASSWORD|_PASS)|GH_TOKEN|GITHUB_TOKEN|ANTHROPIC_API_KEY|OPENAI_API_KEY|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)'
    if [[ "$_raw" =~ echo[[:space:]]+\"[^\"]*\$\{?${CRED_VAR_RE} ]]; then
        _BLOCK_REASON="BLOCKED: Echoing a credential-shaped env var puts a secret in your context. Reference the var name in code instead of printing its value."
        return 1
    fi
    # Block commands that read .env files (.env, .env.local, .env.production, prod.env, etc.)
    # Allow: .env.example, .env.template
    local ENV_FILE_RE='\.env(\.[a-zA-Z0-9_]+)?'
    local ENV_SUFFIX_RE='[a-zA-Z0-9_]+\.env'
    local ENV_ALLOW_RE='\.(example|template)$'
    local MATCHED

    # cat/less/head/tail/more .env* or *.env
    if [[ "$COMMAND" =~ (cat|less|head|tail|more)[[:space:]]+(.*[[:space:]])?(${ENV_FILE_RE}|${ENV_SUFFIX_RE})([[:space:]]|$) ]]; then
        MATCHED="${BASH_REMATCH[0]}"
        if [[ ! "$MATCHED" =~ $ENV_ALLOW_RE ]]; then
            _BLOCK_REASON="BLOCKED: Reading .env file may expose secrets. Use the .example version as a reference instead."
            return 1
        fi
    fi

    # grep/rg/awk/sed .env* or *.env
    if [[ "$COMMAND" =~ (grep|rg|awk|sed)[[:space:]]+(.*[[:space:]])?(${ENV_FILE_RE}|${ENV_SUFFIX_RE})([[:space:]]|$) ]]; then
        MATCHED="${BASH_REMATCH[0]}"
        if [[ ! "$MATCHED" =~ $ENV_ALLOW_RE ]]; then
            _BLOCK_REASON="BLOCKED: Reading .env file may expose secrets. Use the .example version as a reference instead."
            return 1
        fi
    fi

    # source .env* or . .env*
    if [[ "$COMMAND" =~ (source|\.[[:space:]])[[:space:]]+.*(${ENV_FILE_RE}|${ENV_SUFFIX_RE})([[:space:]]|$) ]]; then
        MATCHED="${BASH_REMATCH[0]}"
        if [[ ! "$MATCHED" =~ $ENV_ALLOW_RE ]]; then
            _BLOCK_REASON="BLOCKED: Sourcing .env file may expose secrets. Use the .example version as a reference instead."
            return 1
        fi
    fi

    # export $(cat .env*) or similar patterns
    if [[ "$COMMAND" =~ export[[:space:]]+.*\$\(.*(${ENV_FILE_RE}|${ENV_SUFFIX_RE}) ]]; then
        MATCHED="${BASH_REMATCH[0]}"
        if [[ ! "$MATCHED" =~ $ENV_ALLOW_RE ]]; then
            _BLOCK_REASON="BLOCKED: Exporting from .env file may expose secrets. Use the .example version as a reference instead."
            return 1
        fi
    fi

    # Standalone 'env' command that lists all environment variables
    # Block: env, env | grep, env > file
    # Allow: env VAR=val command (sets env for a command, doesn't list vars)
    if [[ "$COMMAND" =~ ^env([[:space:]]*$|[[:space:]]*[\|>]) ]]; then
        _BLOCK_REASON="BLOCKED: 'env' command exposes all environment variables including secrets."
        return 1
    fi

    # Block printenv (lists environment variables)
    if [[ "$COMMAND" =~ ^printenv([[:space:]]|$) ]]; then
        _BLOCK_REASON="BLOCKED: 'printenv' command exposes environment variables including secrets."
        return 1
    fi

    # Block commands reading credential files
    # (.*[[:space:]])? allows intermediate args (e.g., grep -r KEY ~/.aws/credentials)
    # [^[:space:]]* matches within a single path argument (prevents matching across heredocs)
    local READ_CMDS='(cat|less|head|tail|more|grep|rg|awk|sed)'
    local SSH_KEY_RE="${READ_CMDS}[[:space:]]+(.*[[:space:]])?[^[:space:]]*\.ssh/id_([^[:space:]]*)"
    if [[ "$COMMAND" =~ $SSH_KEY_RE ]]; then
        MATCHED="${BASH_REMATCH[3]}"
        if [[ "$MATCHED" != *".pub" ]]; then
            _BLOCK_REASON="BLOCKED: Reading SSH private key via shell. Private keys should never be exposed."
            return 1
        fi
    fi

    local AWS_RE="${READ_CMDS}[[:space:]]+(.*[[:space:]])?[^[:space:]]*\.aws/(credentials|config)"
    if [[ "$COMMAND" =~ $AWS_RE ]]; then
        _BLOCK_REASON="BLOCKED: Reading AWS credentials via shell may expose access keys."
        return 1
    fi

    local KUBE_RE="${READ_CMDS}[[:space:]]+(.*[[:space:]])?[^[:space:]]*\.kube/config"
    if [[ "$COMMAND" =~ $KUBE_RE ]]; then
        _BLOCK_REASON="BLOCKED: Reading kubeconfig via shell may expose cluster credentials."
        return 1
    fi

    local GH_RE="${READ_CMDS}[[:space:]]+(.*[[:space:]])?[^[:space:]]*\.config/gh/hosts\.yml"
    if [[ "$COMMAND" =~ $GH_RE ]]; then
        _BLOCK_REASON="BLOCKED: Reading GitHub CLI tokens via shell."
        return 1
    fi

    local DOCKER_RE="${READ_CMDS}[[:space:]]+(.*[[:space:]])?[^[:space:]]*\.docker/config\.json"
    if [[ "$COMMAND" =~ $DOCKER_RE ]]; then
        _BLOCK_REASON="BLOCKED: Reading Docker registry auth via shell."
        return 1
    fi

    local PKG_RE="${READ_CMDS}[[:space:]]+(.*[[:space:]])?[^[:space:]]*\.(npmrc|pypirc)"
    local GEM_RE="${READ_CMDS}[[:space:]]+(.*[[:space:]])?[^[:space:]]*\.gem/credentials"
    if [[ "$COMMAND" =~ $PKG_RE ]] || [[ "$COMMAND" =~ $GEM_RE ]]; then
        _BLOCK_REASON="BLOCKED: Reading package manager tokens via shell."
        return 1
    fi

    # Block GPG secret key export
    local GPG_RE='gpg[[:space:]].*--export-secret-keys'
    if [[ "$COMMAND" =~ $GPG_RE ]]; then
        _BLOCK_REASON="BLOCKED: Exporting GPG secret keys is not allowed."
        return 1
    fi

    # Targeted env-var echo / printenv / piped grep — credential-shaped names.
    # Match $VAR or ${VAR} where VAR ends in _TOKEN/_SECRET/_API_KEY/_PASSWORD/_PASS
    # or is a well-known literal (GH_TOKEN, GITHUB_TOKEN, ANTHROPIC_API_KEY, etc.).
    local CRED_VAR_RE='([A-Z][A-Z0-9_]*(_TOKEN|_SECRET|_API_KEY|_PASSWORD|_PASS)|GH_TOKEN|GITHUB_TOKEN|ANTHROPIC_API_KEY|OPENAI_API_KEY|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)'
    if [[ "$COMMAND" =~ echo[[:space:]]+.*\$\{?${CRED_VAR_RE} ]]; then
        _BLOCK_REASON="BLOCKED: Echoing a credential-shaped env var puts a secret in your context. Reference the var name in code instead of printing its value."
        return 1
    fi
    if [[ "$COMMAND" =~ (^|[[:space:];&|])printenv[[:space:]]+${CRED_VAR_RE} ]]; then
        _BLOCK_REASON="BLOCKED: 'printenv VAR' on a credential-shaped env var puts a secret in your context."
        return 1
    fi
    # env|printenv piped to grep filtering for credential-ish keywords.
    if [[ "$COMMAND" =~ (^|[[:space:];&|])(env|printenv)[[:space:]]*\|[[:space:]]*grep[[:space:]] ]]; then
        if [[ "$COMMAND" =~ grep[[:space:]]+([^|]*[[:space:]])?[\'\"]?-?[iE]*[[:space:]]*[\'\"]?(token|secret|key|pass|api[_-]?key) ]]; then
            _BLOCK_REASON="BLOCKED: Piping env/printenv into grep for credential keywords puts secrets in your context."
            return 1
        fi
    fi

    # Tokenized remote URL reads — block only when an embedded credential exists.
    # Surface: git remote -v, git remote show, git config (--get|--list|-l) on remote.*.url
    # or any remote.*.url access; cat/grep/etc on .git/config.
    local REMOTE_SURFACE_RE='git[[:space:]]+remote[[:space:]]+(-v|show|get-url)|git[[:space:]]+config[[:space:]]+([^|;&]*[[:space:]])?(--get(-regexp)?[[:space:]]+remote\.|--list|-l\b|remote\.)|\.git/config'
    if [[ "$COMMAND" =~ $REMOTE_SURFACE_RE ]]; then
        # Resolve from cwd — the command runs there.
        if _git_dir_has_credential_remote "$PWD"; then
            _BLOCK_REASON="BLOCKED: This repository's remote URL embeds a credential. Reading it would put a token in your context. Use \`git branch --show-current\` for the branch, the push-output hint for PR URLs, or ask the user."
            return 1
        fi
    fi

    return 0
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "secrets-guard" "PreToolUse"
    hook_require_tool "Read" "Grep" "Bash"

    # --- Handler: Read tool ---
    if [ "$TOOL_NAME" = "Read" ]; then
        local FILE_PATH
        FILE_PATH=$(hook_get_input '.tool_input.file_path')
        [ -z "$FILE_PATH" ] && exit 0

        check_env_file "$(basename "$FILE_PATH")" "Reading"
        local NORM
        NORM=$(normalize_path "$FILE_PATH")
        check_credential_path "$NORM" "Reading"
        # .git/config — block only when an embedded credential is present.
        if [[ "$NORM" =~ \.git/config$ ]] && _git_dir_has_credential_remote "$NORM"; then
            hook_block "BLOCKED: This repository's remote URL embeds a credential. Reading .git/config would put a token in your context. Use \`git branch --show-current\` for the branch, the push-output hint for PR URLs, or ask the user."
        fi

        exit 0
    fi

    # --- Handler: Grep tool ---
    if [ "$TOOL_NAME" = "Grep" ]; then
        local GREP_PATH GREP_GLOB
        GREP_PATH=$(hook_get_input '.tool_input.path')
        GREP_GLOB=$(hook_get_input '.tool_input.glob')

        if [ -n "$GREP_PATH" ]; then
            check_env_file "$(basename "$GREP_PATH")" "Searching"
            check_credential_path "$(normalize_path "$GREP_PATH")" "Searching"
        fi

        # Check if glob pattern targets .env files
        if [ -n "$GREP_GLOB" ]; then
            # Allow .example/.template globs first
            if [[ "$GREP_GLOB" =~ \.(example|template)$ ]]; then
                exit 0
            fi
            # Block globs that target .env files
            if [[ "$GREP_GLOB" == ".env" ]] || \
               [[ "$GREP_GLOB" == ".env*" ]] || \
               [[ "$GREP_GLOB" == ".env.*" ]] || \
               [[ "$GREP_GLOB" == "*.env" ]]; then
                hook_block "BLOCKED: Grep glob pattern targets .env files which may expose secrets."
            fi
        fi

        exit 0
    fi

    # --- Bash branch — delegate to match_/check_ ---
    if [ "$TOOL_NAME" = "Bash" ]; then
        COMMAND=$(hook_get_input '.tool_input.command')
        [ -z "$COMMAND" ] && exit 0

        _BLOCK_REASON=""
        if match_secrets_guard; then
            if ! check_secrets_guard; then
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
