#!/usr/bin/env bash
# Per-child source-cost probe hook.
#
# Sources lib/hook-utils.sh once (so its parse cost is excluded from the
# per-child measurement), then iterates the child file list for the named
# dispatcher in CHECK_SPECS order, bracketing each `source` with EPOCHREALTIME
# markers. The runner reads the markers from stderr.
#
# Why this shape: the dispatcher's `for spec in CHECK_SPECS; do source ...`
# loop runs in a single bash process. Idempotency guards on hook-utils.sh /
# detection-registry.sh / settings-permissions.sh make re-source calls inside
# children no-op for the lib *body*, but bash still has to parse the child's
# top-level statements (the source calls themselves, the function declarations
# the dispatcher checks via `declare -F`, etc.). That parse cost is what this
# probe measures.
#
# Usage: bash per-child-source-hook.sh <dispatcher>
# Output (stderr):
#   CHILD_T=<dispatcher>\t<child.sh>\t<delta_us>
#   ... one line per child, in CHECK_SPECS order.

set -u
DISPATCHER="${1:?usage: $0 <dispatcher>}"
HERE="$(dirname "$0")"

case "$DISPATCHER" in
    grouped-bash-guard)
        children=(
            block-dangerous-commands.sh
            auto-mode-shared-steps.sh
            block-credential-exfiltration.sh
            git-safety.sh
            secrets-guard.sh
            block-config-edits.sh
            enforce-make-commands.sh
            enforce-uv-run.sh
        )
        ;;
    grouped-read-guard)
        children=(
            secrets-guard.sh
            suggest-read-json.sh
        )
        ;;
    *)
        echo "per-child-source-hook: unknown dispatcher: $DISPATCHER" >&2
        exit 2
        ;;
esac

# Source hook-utils.sh once so its ~2.5ms parse cost is paid before measurement
# starts. Children all source it first thing — the idempotency guard makes that
# call cheap, which is the cost we want to measure here.
# shellcheck source=lib/hook-utils.sh
source "$HERE/lib/hook-utils.sh"

_ts_us() {
    local _sec="${EPOCHREALTIME%.*}"
    local _frac="${EPOCHREALTIME#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

# The dispatcher's source loop expects child files in `$(dirname "$0")` —
# under the dispatcher entrypoint, that's the hooks dir. Children reference
# their lib via `$(dirname "${BASH_SOURCE[0]}")/lib/...`, which resolves to
# the directory of the file being sourced. Symlink each child file into a
# scratch dir alongside a `lib` symlink that points at the probe's lib dir
# (which itself symlinks to .claude/hooks/lib). That keeps the children's
# `source "$(dirname "${BASH_SOURCE[0]}")/lib/..."` resolution working.
#
# Cheaper alternative: source children directly from .claude/hooks/, which
# already has lib/ next to it. Use that path — no scratch dir needed.
HOOKS_DIR="$(cd "$HERE/../../../../.claude/hooks" && pwd)"

for child in "${children[@]}"; do
    src="$HOOKS_DIR/$child"
    if [ ! -f "$src" ]; then
        echo "per-child-source-hook: missing child $src" >&2
        continue
    fi
    t0=$(_ts_us)
    # shellcheck source=/dev/null
    source "$src"
    t1=$(_ts_us)
    printf 'CHILD_T=%s\t%s\t%d\n' "$DISPATCHER" "$child" "$(( t1 - t0 ))" >&2
done

exit 0
