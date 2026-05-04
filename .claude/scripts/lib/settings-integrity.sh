#!/usr/bin/env bash
# Settings integrity check (defense-in-depth for settings.json rewrites).
#
# Computes SHA-256 of .claude/settings.json and .claude/settings.local.json on
# session start, compares against the last-known hash stored at
# .claude/logs/settings-integrity.json. If the hash differs AND the working-tree
# content also differs from HEAD's committed blob, surfaces a warning — a
# legitimate edit goes through the user's editor and gets committed; an LLM
# rewrite via a missed runtime-hook bypass would not.
#
# Surfaces (not blocks) — the user decides. First run establishes baseline.
#
# Env: CLAUDE_TOOLKIT_SETTINGS_INTEGRITY (default "1", opt-out "0").
#
# Usage (from session-start.sh):
#   source "$(dirname "$0")/../scripts/lib/settings-integrity.sh"
#   settings_integrity_check    # prints warnings (if any) to stdout; otherwise silent

# Idempotency guard
if [ -n "${_SETTINGS_INTEGRITY_SOURCED:-}" ]; then
    return 0
fi
_SETTINGS_INTEGRITY_SOURCED=1

# State file lives under gitignored .claude/logs/ — per-machine, per-project.
_SETTINGS_INTEGRITY_STATE_FILE=".claude/logs/settings-integrity.json"

# Compute SHA-256 of a file. Empty string if file missing or sha256sum absent.
_settings_integrity_hash() {
    local file="$1"
    [ -f "$file" ] || { printf ''; return; }
    command -v sha256sum >/dev/null 2>&1 || { printf ''; return; }
    sha256sum "$file" 2>/dev/null | awk '{print $1}'
}

# Get the SHA-256 of the file's content as committed at HEAD. Empty if not
# tracked, no git, or path not in index.
_settings_integrity_head_hash() {
    local file="$1"
    command -v git >/dev/null 2>&1 || { printf ''; return; }
    # `git show HEAD:path` outputs the committed blob; pipe to sha256sum.
    # Suppress errors so untracked files just return empty.
    git show "HEAD:$file" 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}'
}

# Returns 0 if the path is tracked by git (in the index), 1 otherwise. Also
# returns 1 when git is unavailable or the path is outside a repo.
_settings_integrity_is_tracked() {
    local file="$1"
    command -v git >/dev/null 2>&1 || return 1
    git ls-files --error-unmatch -- "$file" >/dev/null 2>&1
}

# Read the stored hash for a path from the state file. Empty if absent.
_settings_integrity_load_stored() {
    local file="$1"
    [ -f "$_SETTINGS_INTEGRITY_STATE_FILE" ] || { printf ''; return; }
    command -v jq >/dev/null 2>&1 || { printf ''; return; }
    jq -r --arg p "$file" '.[$p] // ""' "$_SETTINGS_INTEGRITY_STATE_FILE" 2>/dev/null
}

# Persist a hash for a path to the state file (creates dir + file as needed).
_settings_integrity_store() {
    local file="$1" hash="$2"
    command -v jq >/dev/null 2>&1 || return 0
    mkdir -p "$(dirname "$_SETTINGS_INTEGRITY_STATE_FILE")" 2>/dev/null || return 0
    local tmp
    tmp=$(mktemp 2>/dev/null) || return 0
    if [ -f "$_SETTINGS_INTEGRITY_STATE_FILE" ]; then
        jq --arg p "$file" --arg h "$hash" '. + {($p): $h}' \
            "$_SETTINGS_INTEGRITY_STATE_FILE" > "$tmp" 2>/dev/null \
            && mv "$tmp" "$_SETTINGS_INTEGRITY_STATE_FILE" \
            || rm -f "$tmp"
    else
        jq -n --arg p "$file" --arg h "$hash" '{($p): $h}' > "$_SETTINGS_INTEGRITY_STATE_FILE" 2>/dev/null
    fi
}

# Check one settings file. Prints a warning line to stdout if drift detected
# without a covering commit; updates the stored hash to current state otherwise.
# Silent on first run (baseline), match (no change), and committed-change cases.
_settings_integrity_check_one() {
    local file="$1"
    [ -f "$file" ] || return 0
    local current stored head
    current=$(_settings_integrity_hash "$file")
    [ -z "$current" ] && return 0
    stored=$(_settings_integrity_load_stored "$file")

    # First run — establish baseline silently.
    if [ -z "$stored" ]; then
        _settings_integrity_store "$file" "$current"
        return 0
    fi

    # Hash matches — no change since last session.
    if [ "$stored" = "$current" ]; then
        return 0
    fi

    # Hash differs — check if the working-tree content matches HEAD (i.e. the
    # change is already committed). If it matches HEAD, a legitimate commit
    # happened; update the stored hash silently.
    head=$(_settings_integrity_head_hash "$file")
    if [ -n "$head" ] && [ "$head" = "$current" ]; then
        _settings_integrity_store "$file" "$current"
        return 0
    fi

    # Drift without a covering commit — surface the warning loud, but do NOT
    # update the stored hash. Subsequent sessions keep warning until the user
    # either commits the change or restores the file.
    if _settings_integrity_is_tracked "$file"; then
        echo "⚠ ${file} changed since last session without a commit. Review with: git diff -- ${file}"
    else
        # Untracked (e.g. gitignored .claude/settings.local.json) — `git diff`
        # would print nothing, so point the user at the file directly.
        echo "⚠ ${file} changed since last session (untracked, no committed baseline). Review the file directly: ${file}"
    fi
}

# Public entry point. Iterates the two settings files. No-op when opt-out.
settings_integrity_check() {
    [ "${CLAUDE_TOOLKIT_SETTINGS_INTEGRITY:-1}" = "1" ] || return 0
    _settings_integrity_check_one ".claude/settings.json"
    _settings_integrity_check_one ".claude/settings.local.json"
}
