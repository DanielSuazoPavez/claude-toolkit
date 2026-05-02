#!/usr/bin/env bash
# No-op probe hook for measurement experiments.
#
# Emits PROBE_T<phase>=<EPOCHREALTIME> to stderr at three points:
#   PROBE_T0 — first line of script (before sourcing hook-utils.sh)
#   PROBE_T1 — after sourcing hook-utils.sh, before hook_init
#   PROBE_T2 — after hook_init returns
#
# Combined with the wall-clock brackets the runner records around `bash hook.sh`,
# this gives:
#   bash_startup_us = T0 - wall_start
#   source_us       = T1 - T0
#   init_us         = T2 - T1
#   exit_us         = wall_end - T2
#
# Body is intentionally empty — measure init, not work.

# Capture as early as possible. EPOCHREALTIME is a bash builtin (no fork).
printf 'PROBE_T0=%s\n' "$EPOCHREALTIME" >&2

source "$(dirname "$0")/lib/hook-utils.sh"
printf 'PROBE_T1=%s\n' "$EPOCHREALTIME" >&2

hook_init "noop-probe" "PreToolUse"
printf 'PROBE_T2=%s\n' "$EPOCHREALTIME" >&2

exit 0
