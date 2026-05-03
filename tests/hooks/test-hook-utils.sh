#!/usr/bin/env bash
# Tests for .claude/hooks/lib/hook-utils.sh
#
# Covers (Shape A — in-process, source-the-lib):
#   - _now_ms: EPOCHREALTIME-padding fix + sane magnitude
#   - _strip_inert_content: heredoc, single/double-quoted, escaped quote, nested
#   - hook_feature_enabled: lessons / traceability / unknown branches
#   - hook_extract_quick_reference: missing / no-block / with-block / heading-stop / rule-stop
#
# Pattern matches tests/hooks/test-detection-registry.sh: source the lib once,
# call functions, assert. ~0 fork tax per case.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source under test.
source "$REPO_ROOT/.claude/hooks/lib/hook-utils.sh"

# ============================================================
# Tiny pass/fail wrappers — match test-detection-registry.sh shape
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
# _now_ms — EPOCHREALTIME padding fix + sane behavior
# ============================================================
report_section "=== _now_ms ==="

# Magnitude sanity: live result should be within a few seconds of `date +%s%3N`.
# Catches a regression that returned seconds (1000× small) or microseconds
# (1000× large).
expected_ms=$(date +%s%3N)
actual_ms=$(_now_ms)
diff=$(( actual_ms > expected_ms ? actual_ms - expected_ms : expected_ms - actual_ms ))
assert "_now_ms within 5000ms of date +%s%3N (live sanity)" \
    "[ \"$diff\" -lt 5000 ]"
assert "_now_ms returns at least 13 digits (year ≥ 2001 in ms)" "[ ${#actual_ms} -ge 13 ]"

# Monotonicity: successive calls must not go backwards.
m1=$(_now_ms); m2=$(_now_ms)
assert "_now_ms is non-decreasing across successive calls" "[ \"$m2\" -ge \"$m1\" ]"

# Padding fix: EPOCHREALTIME's frac has variable digit count. Without padding,
# a 1-digit frac like "5" would yield ${_frac:0:3} = "5" → off by 100×.
# Bash drops the dynamic property of EPOCHREALTIME once you assign to it, so
# inline-prefix assignment lets us pin the function against known fracs.
got=$(EPOCHREALTIME=1700000000.5 _now_ms)
assert_eq "1-digit frac '5' → +500ms (padded to '500000', first 3 = '500')" \
    "$got" "1700000000500"

got=$(EPOCHREALTIME=1700000000.50 _now_ms)
assert_eq "2-digit frac '50' → +500ms" "$got" "1700000000500"

got=$(EPOCHREALTIME=1700000000.500 _now_ms)
assert_eq "3-digit frac '500' → +500ms (unchanged by padding)" "$got" "1700000000500"

got=$(EPOCHREALTIME=1700000000.500000 _now_ms)
assert_eq "6-digit frac '500000' → +500ms (first 3 chars)" "$got" "1700000000500"

got=$(EPOCHREALTIME=1700000000.123456 _now_ms)
assert_eq "6-digit frac '123456' → +123ms" "$got" "1700000000123"

# Leading-zero frac: 10#091 must evaluate as base-10 (=91), not octal (error).
got=$(EPOCHREALTIME=1700000000.091 _now_ms)
assert_eq "leading-zero frac '091' → +91ms (no octal trap)" "$got" "1700000000091"

# Empty EPOCHREALTIME → date fallback path. Result should still be a sane ms.
got=$(EPOCHREALTIME= _now_ms)
assert "EPOCHREALTIME='' falls through to date +%s%3N" "[ ${#got} -ge 13 ]"

# ============================================================
# _strip_inert_content — heuristic boundaries
# ============================================================
# Function emits one space for an open quote, drops the body, one space for
# the close quote → quoted segment becomes 2 spaces regardless of body length.
# Heredoc opener line: prefix + 1 space (replacing the <<TAG marker); body
# and closing tag are dropped. $(...) trims the trailing newline.
report_section "=== _strip_inert_content ==="

# Single-quoted: "echo " (5 chars: 4 + sep) + 2 spaces (open+close).
got=$(_strip_inert_content "echo 'secret-payload'")
assert_eq "single-quoted content blanked" "$got" "echo   "

# Double-quoted: same shape as single.
got=$(_strip_inert_content 'echo "secret-payload"')
assert_eq "double-quoted content blanked" "$got" "echo   "

# Escaped double-quote inside double-quoted: \" does not close the string.
got=$(_strip_inert_content 'echo "a\"b"')
assert_eq "escaped double-quote inside double-quoted: stays inside" "$got" "echo   "

# Alternating single-quoted segments: 'a' + b + 'c' → "  b  " (2+1+2).
got=$(_strip_inert_content "echo 'a'b'c'")
assert_eq "alternating single-quoted segments leave bare text" "$got" "echo   b  "

# Nested: double-quote inside single-quoted is inert content, no state change.
got=$(_strip_inert_content "echo 'has \"inner\" quote'")
assert_eq "double-quote inside single-quoted treated as content" "$got" "echo   "

# Bare command: nothing to strip.
got=$(_strip_inert_content "ls -la /tmp")
assert_eq "bare command unchanged" "$got" "ls -la /tmp"

# Heredoc: opener line keeps prefix + 1 space marker; body + closer dropped.
heredoc_input='cat <<EOF
secret payload here
.env contents
EOF'
got=$(_strip_inert_content "$heredoc_input")
assert_eq "heredoc body and closing tag fully consumed" "$got" "cat  "

# Heredoc with quoted tag (<<'EOF'): same result, tag-quoting is lexical only.
heredoc_q="cat <<'EOF'
\$VAR not expanded but irrelevant
EOF"
got=$(_strip_inert_content "$heredoc_q")
assert_eq "heredoc with quoted tag <<'EOF' consumed" "$got" "cat  "

# Heredoc with dash (<<-EOF): closing tag may be tab-indented.
heredoc_dash="cat <<-EOF
	indented body
	EOF"
got=$(_strip_inert_content "$heredoc_dash")
assert_eq "heredoc <<-EOF strips tab-indented closer" "$got" "cat  "

# Real-world: commit message containing .env should not leak the path token.
# .env.local lives inside the double-quoted string → blanked to 2 spaces.
got=$(_strip_inert_content 'git commit -m "remove .env.local references"')
assert_eq "commit message: .env.local inside quotes is blanked" \
    "$got" "git commit -m   "

# ============================================================
# hook_feature_enabled — three branches
# ============================================================
report_section "=== hook_feature_enabled ==="

# lessons branch: enabled
CLAUDE_TOOLKIT_LESSONS=1 hook_feature_enabled lessons
rc=$?
assert_eq "lessons=1 → enabled (rc 0)" "$rc" "0"

# lessons branch: disabled (unset)
unset CLAUDE_TOOLKIT_LESSONS
hook_feature_enabled lessons
rc=$?
assert_eq "lessons unset → disabled (rc 1)" "$rc" "1"

# lessons branch: explicit "0" → disabled
CLAUDE_TOOLKIT_LESSONS=0 hook_feature_enabled lessons
rc=$?
assert_eq "lessons=0 → disabled (rc 1)" "$rc" "1"

# lessons branch: arbitrary truthy string → still disabled (only "1" enables)
CLAUDE_TOOLKIT_LESSONS=true hook_feature_enabled lessons
rc=$?
assert_eq "lessons=true → disabled (only literal '1' enables)" "$rc" "1"
unset CLAUDE_TOOLKIT_LESSONS

# traceability branch
CLAUDE_TOOLKIT_TRACEABILITY=1 hook_feature_enabled traceability
rc=$?
assert_eq "traceability=1 → enabled" "$rc" "0"

unset CLAUDE_TOOLKIT_TRACEABILITY
hook_feature_enabled traceability
rc=$?
assert_eq "traceability unset → disabled" "$rc" "1"

# Unknown feature → rc 1
hook_feature_enabled unknown-feature
rc=$?
assert_eq "unknown feature returns rc 1" "$rc" "1"

# Empty arg → rc 1
hook_feature_enabled ""
rc=$?
assert_eq "empty feature arg returns rc 1" "$rc" "1"

# ============================================================
# hook_extract_quick_reference — file paths and stop conditions
# ============================================================
report_section "=== hook_extract_quick_reference ==="

QR_TMP="$(mktemp -d -t hook-utils-qr-XXXXXX)"
trap 'rm -rf "$QR_TMP"' EXIT

# Missing file → empty output, rc 0 (no stderr noise per header contract).
got=$(hook_extract_quick_reference "$QR_TMP/does-not-exist.md" 2>&1)
assert_eq "missing file → empty output" "$got" ""

# File with no Quick Reference block → empty.
cat >"$QR_TMP/no-block.md" <<'MD'
# Title
Some content but no Quick Reference heading.
## 2. Other Section
Body.
MD
got=$(hook_extract_quick_reference "$QR_TMP/no-block.md")
assert_eq "file without Quick Reference block → empty" "$got" ""

# File with a Quick Reference block → block is included with heading.
cat >"$QR_TMP/with-block.md" <<'MD'
# Title

## 1. Quick Reference

This is the body.
- bullet 1
- bullet 2

## 2. Next Section

Other content.
MD
got=$(hook_extract_quick_reference "$QR_TMP/with-block.md")
# Block ends at next "## " heading. Awk prints the heading line and everything
# until (but not including) the "## 2." line.
assert "with-block: includes Quick Reference heading" \
    "echo \"\$got\" | grep -q '^## 1\\. Quick Reference\$'"
assert "with-block: includes body content" \
    "echo \"\$got\" | grep -q 'This is the body'"
assert "with-block: includes bullets" \
    "echo \"\$got\" | grep -q '^- bullet 1\$'"
assert "with-block: stops before next ## heading" \
    "! echo \"\$got\" | grep -q 'Next Section'"

# Stop at "---" rule (alternative terminator).
cat >"$QR_TMP/rule-stop.md" <<'MD'
## 1. Quick Reference

Body line.

---

After the rule should not appear.
MD
got=$(hook_extract_quick_reference "$QR_TMP/rule-stop.md")
assert "rule-stop: includes body before rule" \
    "echo \"\$got\" | grep -q 'Body line'"
assert "rule-stop: excludes content after ---" \
    "! echo \"\$got\" | grep -q 'After the rule'"

# Block at EOF (no terminator) → all remaining content emitted.
cat >"$QR_TMP/eof-block.md" <<'MD'
## 1. Quick Reference

Body until EOF.
MD
got=$(hook_extract_quick_reference "$QR_TMP/eof-block.md")
assert "eof-block: emits content through EOF" \
    "echo \"\$got\" | grep -q 'Body until EOF'"

print_summary
