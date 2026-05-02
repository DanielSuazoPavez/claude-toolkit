#!/usr/bin/env bash
# Per-lib source-cost probe hook.
#
# Sources `lib/$1.sh` (after sourcing `lib/hook-utils.sh` if $1 is itself
# something that depends on hook-utils.sh — e.g. detection-registry.sh
# requires _strip_inert_content). Emits PROBE_T markers around the source
# call so the runner can isolate per-lib parse cost from bash startup.
#
# Modes:
#   $1 = baseline                  → no source, just bash startup + exit
#   $1 = hook-utils                → source hook-utils.sh (which transitively sources hook-logging.sh)
#   $1 = detection-registry        → source hook-utils.sh, then detection-registry.sh
#   $1 = settings-permissions      → source hook-utils.sh, then settings-permissions.sh
#
# Why hook-utils as a prereq for the others: the auxiliary libs depend on
# functions defined in hook-utils.sh (detection-registry uses _strip_inert_content;
# settings-permissions doesn't strictly need it but matches real-session order).
# Subtract the hook-utils baseline to get the marginal lib cost.
#
# Output (stderr):
#   PROBE_T0=<EPOCHREALTIME>   first line, before any source
#   PROBE_T1=<EPOCHREALTIME>   after lib source(s)

set -u
LIB="${1:-baseline}"
HERE="$(dirname "$0")"

printf 'PROBE_T0=%s\n' "$EPOCHREALTIME" >&2

case "$LIB" in
    baseline)
        # No-op — measure bash startup floor.
        ;;
    hook-utils)
        source "$HERE/lib/hook-utils.sh"
        ;;
    detection-registry)
        source "$HERE/lib/hook-utils.sh"
        source "$HERE/lib/detection-registry.sh"
        ;;
    settings-permissions)
        source "$HERE/lib/hook-utils.sh"
        source "$HERE/lib/settings-permissions.sh"
        ;;
    detection-registry-loaded)
        # Source + run the one-shot loader to measure full ready-to-match cost.
        source "$HERE/lib/hook-utils.sh"
        source "$HERE/lib/detection-registry.sh"
        detection_registry_load >/dev/null 2>&1 || true
        ;;
    settings-permissions-loaded)
        # Source + run the loader. Requires CLAUDE_TOOLKIT_SETTINGS_JSON env.
        source "$HERE/lib/hook-utils.sh"
        source "$HERE/lib/settings-permissions.sh"
        settings_permissions_load >/dev/null 2>&1 || true
        ;;
    *)
        echo "per-lib-source-hook: unknown lib: $LIB" >&2
        exit 2
        ;;
esac

printf 'PROBE_T1=%s\n' "$EPOCHREALTIME" >&2
exit 0
