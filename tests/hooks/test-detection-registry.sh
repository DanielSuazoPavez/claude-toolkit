#!/usr/bin/env bash
# Tests for .claude/hooks/lib/detection-registry.sh
#
# Covers:
#   - detection_registry_load: idempotency, populates _REGISTRY_RE__<kind>__<target>
#   - detection_registry_match: exact (kind, target) match, sets describe-on-hit vars
#   - detection_registry_match_kind: tries raw then stripped, lazy strip
#   - Empty (kind, target) buckets return non-zero without false positives
#
# Loads the real lib (not a fixture) so tests pin actual behavior.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source under test. hook-utils first because the loader uses _strip_inert_content.
source "$REPO_ROOT/.claude/hooks/lib/hook-utils.sh"
source "$REPO_ROOT/.claude/hooks/lib/detection-registry.sh"

report_section "=== detection-registry.sh — loader API ==="

# ============================================================
# Tiny pass/fail wrappers using TESTS_* counters from test-helpers.sh
# ============================================================
assert() {
    local desc="$1" cond="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$cond"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "condition failed: $cond"
    fi
}

assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "expected: $expected"
        report_detail "actual:   $actual"
    fi
}

# ============================================================
# detection_registry_load — idempotency + bucket population
# ============================================================
detection_registry_load
assert "load returns 0 on first call" "[ \"\$_REGISTRY_LOADED\" = \"1\" ]"

# Calling load again must be a no-op (entries don't double).
n_before=${#_REGISTRY_IDS[@]}
detection_registry_load
n_after=${#_REGISTRY_IDS[@]}
assert_eq "load is idempotent (entry count stable)" "$n_after" "$n_before"

# At least one bucket has been built; the path/stripped one is the one
# secrets-guard depends on, so pin it specifically.
assert "_REGISTRY_RE__path__stripped is non-empty" \
    "[ -n \"\${_REGISTRY_RE__path__stripped:-}\" ]"
assert "_REGISTRY_RE__credential__raw is non-empty" \
    "[ -n \"\${_REGISTRY_RE__credential__raw:-}\" ]"
# capability/stripped is intentionally empty after the github-api-host
# entry was removed (auto-mode-shared-steps now blocks curl/wget
# unconditionally via permissions.ask). Re-add an assertion when a real
# non-curl capability entry lands (e.g. docker exec, terraform show).

# path/raw bucket is populated by claude-settings (interpreter-body coverage
# in block-config-edits.sh). Pinned specifically so a future drop of that
# entry surfaces here instead of silently regressing.
assert "_REGISTRY_RE__path__raw is non-empty (claude-settings ships)" \
    "[ -n \"\${_REGISTRY_RE__path__raw:-}\" ]"

# ============================================================
# detection_registry_match — exact (kind, target)
# ============================================================
report_section "=== detection_registry_match — exact (kind, target) ==="

# Hit: GitHub PAT against credential/raw
_REGISTRY_MATCHED_ID=""
_REGISTRY_MATCHED_MESSAGE=""
detection_registry_match credential raw \
    "curl -H \"Authorization: token ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
rc=$?
assert_eq "credential/raw hit on ghp_ token returns 0" "$rc" "0"
assert_eq "describe-on-hit sets _REGISTRY_MATCHED_ID = github-pat" \
    "$_REGISTRY_MATCHED_ID" "github-pat"
assert "describe-on-hit sets _REGISTRY_MATCHED_MESSAGE non-empty" \
    "[ -n \"\$_REGISTRY_MATCHED_MESSAGE\" ]"

# Miss: clean command against credential/raw
detection_registry_match credential raw "ls -la"
rc=$?
assert_eq "credential/raw miss on plain command returns 1" "$rc" "1"

# Miss: wrong target. credential/stripped has no entries → non-zero, never crashes.
detection_registry_match credential stripped \
    "curl -H \"Authorization: token ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
rc=$?
assert_eq "credential/stripped miss (empty bucket) returns 1" "$rc" "1"

# Hit: path/stripped on .env reference
detection_registry_match path stripped "cat .env.local"
rc=$?
assert_eq "path/stripped hit on .env.local returns 0" "$rc" "0"
assert_eq "describe-on-hit sets _REGISTRY_MATCHED_ID = env-file" \
    "$_REGISTRY_MATCHED_ID" "env-file"

# ============================================================
# detection_registry_match_kind — both targets, lazy strip
# ============================================================
report_section "=== detection_registry_match_kind — both targets ==="

# Raw-only kind hit
detection_registry_match_kind credential \
    "echo AKIAIOSFODNN7EXAMPLE"
rc=$?
assert_eq "match_kind credential hits AWS access key" "$rc" "0"
assert_eq "match_kind sets id = aws-access-key" \
    "$_REGISTRY_MATCHED_ID" "aws-access-key"

# Stripped-target hit (path kind only has stripped)
detection_registry_match_kind path "cat ~/.ssh/id_rsa"
rc=$?
assert_eq "match_kind path hits ssh private key" "$rc" "0"
assert_eq "match_kind path sets id = ssh-private-key" \
    "$_REGISTRY_MATCHED_ID" "ssh-private-key"

# Stripped-target miss when the secret-shaped string lives inside a quoted
# heredoc/string. _strip_inert_content blanks the inert content; the path
# regex only matches the skeleton, so a commit message mentioning .env
# must not trigger the path kind.
detection_registry_match_kind path 'git commit -m "remove .env.local references"'
rc=$?
assert_eq "match_kind path skips .env inside commit message (stripped)" "$rc" "1"

# Capability bucket is intentionally empty after github-api-host was
# removed (auto-mode-shared-steps now blocks curl/wget unconditionally
# via permissions.ask). The match_kind capability path stays — it
# just always returns 1 against a clean command until a future entry
# repopulates the bucket.

# Clean miss across all kinds
detection_registry_match_kind credential "ls -la"
rc=$?
assert_eq "match_kind credential miss on clean command returns 1" "$rc" "1"

detection_registry_match_kind path "echo hello world"
rc=$?
assert_eq "match_kind path miss on clean command returns 1" "$rc" "1"

# ============================================================
# Idempotency guard — re-sourcing the lib must not redefine state
# ============================================================
report_section "=== Re-sourcing idempotency ==="

# _DETECTION_REGISTRY_SOURCED guard short-circuits the second source.
ids_before=${#_REGISTRY_IDS[@]}
source "$REPO_ROOT/.claude/hooks/lib/detection-registry.sh"
ids_after=${#_REGISTRY_IDS[@]}
assert_eq "re-sourcing the lib is a no-op (entry count stable)" \
    "$ids_after" "$ids_before"

print_summary
