#!/usr/bin/env bash
# Tests for detect-session-start-truncation.sh — covers all four branches:
#   (a) truncation present  → loud warning + marker created
#   (b) truncation absent   → "no truncation" message
#   (c) marker pre-exists   → silent pass (fire-once)
#   (d) transcript missing  → silent pass
#
# Isolation:
#   - Override $HOME to a fresh mktemp dir (transcript fixtures live under it).
#   - Use unique per-case SESSION_ID so marker files at /tmp/claude-truncation-check/
#     never collide between cases or with other test runs.
#   - Cleanup: per-case markers explicitly removed; per-test $HOME removed
#     via EXIT trap. NEVER `rm -rf` the global /tmp/claude-truncation-check/
#     directory — other processes may share it.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

report_section "=== detect-session-start-truncation.sh ==="
hook="detect-session-start-truncation.sh"

# Per-test isolated $HOME — fresh directory the hook writes its transcript-lookup
# under. Cleaned up via EXIT trap.
TEST_HOME=$(mktemp -d -t trunc-test-XXXXXX)
export HOME="$TEST_HOME"

# Per-case markers we'll create at /tmp/claude-truncation-check/$sid — track them
# so the EXIT trap can clean only ours.
declare -a MARKERS_TO_CLEAN=()

cleanup() {
    for m in "${MARKERS_TO_CLEAN[@]}"; do
        rm -f "$m"
    done
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

# Resolve the project-dir name the hook will compute from $(pwd)
PROJECT_DIR_NAME=$(pwd | sed 's|/|-|g; s|^-||')
TRANSCRIPT_DIR="$TEST_HOME/.claude/projects/-${PROJECT_DIR_NAME}"
mkdir -p "$TRANSCRIPT_DIR"

run_hook() {
    local sid="$1"
    mk_user_prompt_submit_payload "$sid" hi "$(pwd)" \
        | "$HOOKS_DIR/$hook" 2>/dev/null
}

# --- Case (a): truncation present ---
sid_a="trunc-test-$$-$(date +%s%N)-a"
MARKERS_TO_CLEAN+=("/tmp/claude-truncation-check/$sid_a")
cat > "$TRANSCRIPT_DIR/$sid_a.jsonl" <<EOF
{"hookEvent":"SessionStart","content":"<persisted-output>Output too large; truncated...</persisted-output>"}
EOF

out_a=$(run_hook "$sid_a")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$out_a" == *"=== SESSION START TRUNCATION DETECTED ==="* ]] && \
   [[ "$out_a" == *"MANDATORY: Acknowledge"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "(a) truncation present: emits loud warning"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "(a) truncation present: warning missing"
    report_detail "stdout: $out_a"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "/tmp/claude-truncation-check/$sid_a" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "(a) truncation present: marker file created"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "(a) truncation present: marker file missing"
fi

# --- Case (b): truncation absent ---
sid_b="trunc-test-$$-$(date +%s%N)-b"
MARKERS_TO_CLEAN+=("/tmp/claude-truncation-check/$sid_b")
cat > "$TRANSCRIPT_DIR/$sid_b.jsonl" <<EOF
{"hookEvent":"SessionStart","content":"normal session start payload, no marker"}
EOF

out_b=$(run_hook "$sid_b")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$out_b" == *"[truncation-detector] no truncation"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "(b) truncation absent: emits no-truncation message"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "(b) truncation absent: unexpected stdout"
    report_detail "stdout: $out_b"
fi

# --- Case (c): marker pre-exists (fire-once guard) ---
sid_c="trunc-test-$$-$(date +%s%N)-c"
MARKERS_TO_CLEAN+=("/tmp/claude-truncation-check/$sid_c")
mkdir -p /tmp/claude-truncation-check
touch "/tmp/claude-truncation-check/$sid_c"
# Transcript would trigger truncation, but the marker should short-circuit
cat > "$TRANSCRIPT_DIR/$sid_c.jsonl" <<EOF
{"hookEvent":"SessionStart","content":"<persisted-output>Output too large</persisted-output>"}
EOF

out_c=$(run_hook "$sid_c")
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$out_c" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "(c) marker pre-exists: silent pass (fire-once)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "(c) marker pre-exists: unexpected stdout"
    report_detail "stdout: $out_c"
fi

# --- Case (d): missing transcript ---
sid_d="trunc-test-$$-$(date +%s%N)-d"
MARKERS_TO_CLEAN+=("/tmp/claude-truncation-check/$sid_d")
# Deliberately do NOT create the transcript file under $TRANSCRIPT_DIR

out_d=$(run_hook "$sid_d")
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$out_d" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "(d) transcript missing: silent pass"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "(d) transcript missing: unexpected stdout"
    report_detail "stdout: $out_d"
fi

print_summary
