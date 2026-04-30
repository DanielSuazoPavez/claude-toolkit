#!/usr/bin/env bash
# CC-HOOK: NAME: block-dangerous-commands
# CC-HOOK: PURPOSE: Block rm -rf /, fork bombs, mkfs, and dd commands
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none
#
# PreToolUse hook: block dangerous bash commands
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/block-dangerous-commands.sh"}]}]
#
# Blocks:
#   - rm -rf / or rm -rf /* (root deletion)
#   - rm -rf ~ or rm -rf $HOME (home deletion)
#   - rm -rf . or rm -rf $(pwd) (project directory deletion)
#   - Fork bombs: :(){ :|:& };: and variants
#   - mkfs commands (format filesystems)
#   - dd to /dev/sda or similar (disk overwrite)
#   - chmod -R 777 / (dangerous permissions)
#   - > /dev/sda (disk overwrite via redirect)
#   - sudo commands (cannot work — no interactive password prompt)
#
# Also detects these patterns when hidden via:
#   - Subshells: $(rm -rf /), `rm -rf /`
#   - Eval: eval "rm -rf /"
#   - Shell wrappers: bash -c "rm -rf /", sh -c "rm -rf /"

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# ============================================================
# match_dangerous — cheap predicate
# ============================================================
# Returns 0 when $COMMAND contains a token that any check below could
# trip on. Deliberately broad — false positives OK, false negatives bugs.
# Pure bash — no forks, no jq, no git.
match_dangerous() {
    # Token hints covering: rm, mkfs, dd, chmod, sudo, /dev/, fork-bomb
    # operator `(){`, shell-wrapper obfuscators, and redirect/pipe patterns
    # that could carry hidden destructive commands.
    local re='(^|[[:space:];&|`(])(rm|mkfs|mkfs\.[a-z0-9]+|dd|chmod|sudo|eval|bash|sh)([[:space:]]|$)|/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z])|:\(\)|\.\(\)|bomb\(\)|\$\(|`'
    [[ "$COMMAND" =~ $re ]]
}

# ============================================================
# check_dangerous — guard body
# ============================================================
# Assumes match_dangerous returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_dangerous() {
    # Normalize command to expose hidden dangerous commands:
    # - Strip subshell wrappers: $(...) and backticks
    # - Strip eval prefix
    # - Strip shell wrappers: bash -c, sh -c
    # - Strip surrounding quotes from arguments
    local CMD="$COMMAND"
    CMD=$(echo "$CMD" | sed 's/\$(\([^)]*\))/\1/g')
    CMD=$(echo "$CMD" | sed 's/`\([^`]*\)`/\1/g')
    CMD=$(echo "$CMD" | sed 's/\beval\b//g')
    CMD=$(echo "$CMD" | sed 's/\bbash -c\b//g')
    CMD=$(echo "$CMD" | sed 's/\bsh -c\b//g')
    CMD=$(echo "$CMD" | sed "s/[\"']//g")

    if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]/(\ |\*|$) ]] || \
       [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]/(\ |\*|$) ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on root directory. This would destroy the entire filesystem."
        return 1
    fi
    if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]] || \
       [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on home directory. This would destroy all user data."
        return 1
    fi
    if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]\.(\ |$) ]] || \
       [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]\.(\ |$) ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on current directory. This would destroy the entire project."
        return 1
    fi
    if [[ "$CMD" =~ rm[[:space:]].*-.*r.*f ]] && \
       [[ "$CMD" == *'$(pwd)'* || "$CMD" == *'$PWD'* || "$CMD" == *'${PWD}'* || "$CMD" == *'pwd'* ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on current directory. This would destroy the entire project."
        return 1
    fi
    # Fork-bomb check uses COMMAND (original) — normalization could mangle the syntax
    if [[ "$COMMAND" =~ :\(\)[[:space:]]*\{.*:\|:.*\} ]] || \
       [[ "$COMMAND" =~ \.\(\)[[:space:]]*\{.*\.\|\..*\} ]] || \
       [[ "$COMMAND" =~ bomb\(\)[[:space:]]*\{.*bomb.*\|.*bomb.*\} ]]; then
        _BLOCK_REASON="BLOCKED: Fork bomb detected. This would crash the system by exhausting resources."
        return 1
    fi
    if [[ "$CMD" =~ mkfs(\.[a-z0-9]+)?[[:space:]] ]]; then
        _BLOCK_REASON="BLOCKED: mkfs command detected. This would format a filesystem and destroy data."
        return 1
    fi
    if [[ "$CMD" =~ dd[[:space:]].*of=/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
        _BLOCK_REASON="BLOCKED: dd to disk device detected. This would overwrite the disk."
        return 1
    fi
    if [[ "$CMD" =~ \>[[:space:]]*/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
        _BLOCK_REASON="BLOCKED: Redirect to disk device detected. This would overwrite the disk."
        return 1
    fi
    if [[ "$CMD" =~ chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/(\ |$) ]] || \
       [[ "$CMD" =~ chmod[[:space:]]+777[[:space:]]+-R[[:space:]]+/(\ |$) ]]; then
        _BLOCK_REASON="BLOCKED: chmod -R 777 / detected. This would make all files world-writable."
        return 1
    fi
    if [[ "$CMD" =~ (^|;|&&|\|\|)[[:space:]]*sudo[[:space:]] ]]; then
        _BLOCK_REASON="BLOCKED: sudo commands cannot work in this environment — no interactive password prompt available."
        return 1
    fi
    return 0
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "block-dangerous-commands" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_dangerous; then
        if ! check_dangerous; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
