#!/usr/bin/env bash
# === GENERATED FILE — do not edit ===
# Source: lib/dispatch-order.json + headers from .claude/hooks/*.sh
# Generator: scripts/hook-framework/render-dispatcher.sh
# Regenerate: make hooks-render
# ====================================
CHECK_SPECS=(
    "dangerous:block-dangerous-commands.sh"
    "destructive_sql:block-destructive-sql.sh"
    "auto_mode_shared_steps:auto-mode-shared-steps.sh"
    "credential_exfil:block-credential-exfiltration.sh"
    "git_safety:git-safety.sh"
    "secrets_guard:secrets-guard.sh"
    "config_edits:block-config-edits.sh"
    "make:enforce-make-commands.sh"
    "uv:enforce-uv-run.sh"
)
CHECKS=()
hook_dir="$(dirname "$0")"
for spec in "${CHECK_SPECS[@]}"; do
    name="${spec%%:*}"
    file="${spec#*:}"
    src="$hook_dir/$file"
    [ -f "$src" ] || continue
    # shellcheck source=/dev/null
    source "$src"
    if declare -F "match_$name" >/dev/null && declare -F "check_$name" >/dev/null; then
        CHECKS+=("$name")
    else
        hook_log_substep "check_${name}_missing_match_check" 0 "skipped" 0
    fi
done
