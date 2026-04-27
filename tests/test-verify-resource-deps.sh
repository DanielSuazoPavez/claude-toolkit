#!/bin/bash
# Automated tests for verify-resource-deps.sh
#
# Usage:
#   bash tests/test-verify-resource-deps.sh      # Run all tests
#   bash tests/test-verify-resource-deps.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-verify-resource-deps.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY_SCRIPT="$TOOLKIT_DIR/.claude/scripts/verify-resource-deps.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"
    mkdir -p "$TEMP_DIR/.claude/scripts"
    cp "$VERIFY_SCRIPT" "$TEMP_DIR/.claude/scripts/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# === Helpers ===

create_skill() {
    local name="$1"
    local body="${2:-# $name skill}"
    mkdir -p "$TEMP_DIR/.claude/skills/$name"
    cat > "$TEMP_DIR/.claude/skills/$name/SKILL.md" << EOF
---
name: $name
description: Test skill $name
---

$body
EOF
}

create_agent() {
    local name="$1"
    mkdir -p "$TEMP_DIR/.claude/agents"
    cat > "$TEMP_DIR/.claude/agents/$name.md" << EOF
# $name agent
EOF
}

create_doc() {
    local name="$1"
    local body="${2:-# $name doc}"
    mkdir -p "$TEMP_DIR/.claude/docs"
    cat > "$TEMP_DIR/.claude/docs/$name.md" << EOF
$body
EOF
}

create_hook() {
    local name="$1"
    local body="${2:-#!/bin/bash}"
    mkdir -p "$TEMP_DIR/.claude/hooks"
    cat > "$TEMP_DIR/.claude/hooks/$name" << EOF
$body
EOF
}

create_settings() {
    local json="$1"
    mkdir -p "$TEMP_DIR/.claude"
    echo "$json" > "$TEMP_DIR/.claude/settings.json"
}

create_script() {
    local name="$1"
    mkdir -p "$TEMP_DIR/.claude/scripts"
    echo "#!/bin/bash" > "$TEMP_DIR/.claude/scripts/$name.sh"
}

create_manifest() {
    mkdir -p "$TEMP_DIR/.claude"
    printf '%s\n' "$@" > "$TEMP_DIR/.claude/MANIFEST"
}

run_verify() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/verify-resource-deps.sh 2>&1)
}

run_verify_exit_code() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/verify-resource-deps.sh >/dev/null 2>&1)
    echo $?
}

assert_exit_0() {
    local desc="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    local exit_code
    exit_code=$(run_verify_exit_code)
    if [ "$exit_code" = "0" ]; then
        report_pass "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        report_fail "$desc (expected exit 0, got $exit_code)"
        report_detail "Output: $(run_verify)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_exit_1() {
    local desc="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    local exit_code
    exit_code=$(run_verify_exit_code)
    if [ "$exit_code" = "1" ]; then
        report_pass "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        report_fail "$desc (expected exit 1, got $exit_code)"
        report_detail "Output: $(run_verify)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_contains() {
    local desc="$1"
    local pattern="$2"
    local output="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q "$pattern"; then
        report_pass "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        report_fail "$desc (pattern '$pattern' not found)"
        report_detail "Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_not_contains() {
    local desc="$1"
    local pattern="$2"
    local output="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! echo "$output" | grep -q "$pattern"; then
        report_pass "$desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        report_fail "$desc (pattern '$pattern' unexpectedly found)"
        report_detail "Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================================
# Section 1: settings.json → hooks
# ============================================================

report_section "=== 1. settings.json → hooks: valid commands ==="

setup_test_env
create_hook "my-hook.sh" "#!/bin/bash\necho hook"
create_settings '{"hooks":{"PreToolUse":[{"command":"bash .claude/hooks/my-hook.sh"}]}}'
OUTPUT=$(run_verify)
assert_exit_0 "Valid hook commands → exit 0"
assert_output_contains "Reports valid hook count" "All 1 hook commands resolve" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 1. settings.json → hooks: broken command ==="

setup_test_env
create_settings '{"hooks":{"PreToolUse":[{"command":"bash .claude/hooks/nonexistent.sh"}]}}'
OUTPUT=$(run_verify)
assert_exit_1 "Broken hook command → exit 1"
assert_output_contains "Reports broken hook" "Broken hook command" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 1. settings.json → hooks: no settings.json ==="

setup_test_env
OUTPUT=$(run_verify)
assert_exit_0 "No settings.json → exit 0"
assert_output_contains "Reports skipped" "Skipped: settings.json not found" "$OUTPUT"
teardown_test_env

# ============================================================
# Section 2: Hooks → skills
# ============================================================

report_section "=== 2. Hooks → skills: valid ref ==="

setup_test_env
create_skill "my-skill"
create_hook "test-hook.sh" '#!/bin/bash\n# Use `/my-skill` here'
OUTPUT=$(run_verify)
assert_exit_0 "Valid skill ref in hook → exit 0"
assert_output_contains "Reports valid skill refs" "skill references in hooks are valid" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 2. Hooks → skills: broken ref ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/hooks"
cat > "$TEMP_DIR/.claude/hooks/test-hook.sh" << 'HOOKEOF'
#!/bin/bash
# Use `/missing-skill` here
HOOKEOF
OUTPUT=$(run_verify)
assert_exit_1 "Broken skill ref in hook → exit 1"
assert_output_contains "Reports broken skill" "references skill 'missing-skill'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 2. Hooks → skills: builtin command ignored ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/hooks"
cat > "$TEMP_DIR/.claude/hooks/test-hook.sh" << 'HOOKEOF'
#!/bin/bash
# Use `/clear` and `/help` here
HOOKEOF
OUTPUT=$(run_verify)
assert_exit_0 "Builtin commands in hook → exit 0"
assert_output_not_contains "No error for builtins" "references skill 'clear'" "$OUTPUT"
teardown_test_env

# ============================================================
# Section 3: Skills → agents
# ============================================================

report_section "=== 3. Skills → agents: subagent_type= pattern ==="

setup_test_env
create_agent "my-agent"
create_skill "agent-skill" 'Use subagent_type=my-agent for this task'
mkdir -p "$TEMP_DIR/.claude/agents"
OUTPUT=$(run_verify)
assert_exit_0 "subagent_type=name → exit 0"
assert_output_contains "Reports valid agent refs" "agent references in skills are valid" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 3. Skills → agents: backtick agent pattern ==="

setup_test_env
create_agent "review-agent"
mkdir -p "$TEMP_DIR/.claude/skills/bt-skill"
cat > "$TEMP_DIR/.claude/skills/bt-skill/SKILL.md" << 'SKILLEOF'
---
name: bt-skill
description: Test
---

Launch the `review-agent` agent to handle this.
SKILLEOF
OUTPUT=$(run_verify)
assert_exit_0 "backtick agent pattern → exit 0"
teardown_test_env

# ---

report_section "=== 3. Skills → agents: path pattern ==="

setup_test_env
create_agent "path-agent"
create_skill "path-skill" 'See agents/path-agent for details'
OUTPUT=$(run_verify)
assert_exit_0 "agents/name path pattern → exit 0"
teardown_test_env

# ---

report_section "=== 3. Skills → agents: broken ref ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/agents"
create_skill "broken-agent-skill" 'Use subagent_type=nonexistent-agent here'
OUTPUT=$(run_verify)
assert_exit_1 "Broken agent ref → exit 1"
assert_output_contains "Reports broken agent" "references agent 'nonexistent-agent'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 3. Skills → agents: general-purpose skipped ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/agents"
create_skill "gp-skill" 'Use subagent_type=general-purpose here'
OUTPUT=$(run_verify)
assert_exit_0 "general-purpose agent → exit 0"
assert_output_not_contains "No error for general-purpose" "references agent 'general-purpose'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 3. Skills → agents: allowlisted ref ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/agents"
mkdir -p "$TEMP_DIR/.claude/skills/create-agent"
cat > "$TEMP_DIR/.claude/skills/create-agent/SKILL.md" << 'SKILLEOF'
---
name: create-agent
description: Test
---

Example: subagent_type=migration-reviewer
SKILLEOF
OUTPUT=$(run_verify)
assert_exit_0 "Allowlisted create-agent:migration-reviewer → exit 0"
assert_output_not_contains "No error for allowlisted" "references agent 'migration-reviewer'" "$OUTPUT"
teardown_test_env

# ============================================================
# Section 4: Skills → skills
# ============================================================

report_section "=== 4. Skills → skills: valid ref ==="

setup_test_env
create_skill "target-skill"
create_skill "source-skill" 'Use `/target-skill` for this'
OUTPUT=$(run_verify)
assert_exit_0 "Valid skill→skill ref → exit 0"
assert_output_contains "Reports valid skill→skill refs" "skill→skill references are valid" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 4. Skills → skills: broken ref ==="

setup_test_env
create_skill "lonely-skill" 'Use `/nonexistent-skill` here'
OUTPUT=$(run_verify)
assert_exit_1 "Broken skill→skill ref → exit 1"
assert_output_contains "Reports broken skill ref" "references skill 'nonexistent-skill'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 4. Skills → skills: self-ref ignored ==="

setup_test_env
create_skill "self-skill" 'Use `/self-skill` recursively'
OUTPUT=$(run_verify)
assert_exit_0 "Self-referencing skill → exit 0"
assert_output_not_contains "No error for self-ref" "references skill 'self-skill'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 4. Skills → skills: placeholder ignored ==="

setup_test_env
create_skill "placeholder-skill" 'Use `/skill-name` as placeholder'
OUTPUT=$(run_verify)
assert_exit_0 "Placeholder /skill-name → exit 0"
assert_output_not_contains "No error for placeholder" "references skill 'skill-name'" "$OUTPUT"
teardown_test_env

# ============================================================
# Section 5: Skills → scripts
# ============================================================

report_section "=== 5. Skills → scripts: valid ref ==="

setup_test_env
create_script "my-helper"
create_skill "script-skill" 'Run `.claude/scripts/my-helper.sh` for this'
OUTPUT=$(run_verify)
assert_exit_0 "Valid script ref → exit 0"
assert_output_contains "Reports valid script refs" "script references in skills are valid" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 5. Skills → scripts: broken ref ==="

setup_test_env
create_skill "broken-script-skill" 'Run `.claude/scripts/nonexistent-script.sh` here'
OUTPUT=$(run_verify)
assert_exit_1 "Broken script ref → exit 1"
assert_output_contains "Reports broken script" "references script" "$OUTPUT"
teardown_test_env

# ============================================================
# Section 6: Docs → docs
# ============================================================

report_section "=== 6. Docs → docs: valid cross-ref ==="

setup_test_env
create_doc "essential-foo" 'Reference to `essential-bar` here'
create_doc "essential-bar" '# Bar doc'
OUTPUT=$(run_verify)
assert_exit_0 "Valid doc cross-ref → exit 0"
assert_output_contains "Reports valid doc refs" "doc cross-references are valid" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 6. Docs → docs: broken cross-ref ==="

setup_test_env
create_doc "essential-source" 'Reference to `essential-missing` here'
OUTPUT=$(run_verify)
assert_exit_1 "Broken doc cross-ref → exit 1"
assert_output_contains "Reports broken doc" "references doc 'essential-missing'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 6. Docs → docs: self-ref ignored ==="

setup_test_env
create_doc "essential-self" 'Reference to `essential-self` here'
OUTPUT=$(run_verify)
assert_exit_0 "Self-referencing doc → exit 0"
assert_output_not_contains "No error for self-ref" "references doc 'essential-self'" "$OUTPUT"
teardown_test_env

# ============================================================
# Section 7: Docs → skills
# ============================================================

report_section "=== 7. Docs → skills: valid ref ==="

setup_test_env
create_skill "doc-target"
create_doc "essential-with-skill" 'Use `/doc-target` skill here'
OUTPUT=$(run_verify)
assert_exit_0 "Valid skill ref in doc → exit 0"
assert_output_contains "Reports valid doc→skill refs" "skill references in docs are valid" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 7. Docs → skills: broken ref ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/skills"
create_doc "essential-broken-skill" 'Use `/no-such-skill` here'
OUTPUT=$(run_verify)
assert_exit_1 "Broken skill ref in doc → exit 1"
assert_output_contains "Reports broken skill ref in doc" "references skill 'no-such-skill'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== 7. Docs → skills: builtin ignored ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/skills"
create_doc "essential-with-builtin" 'Use `/help` and `/clear` commands'
OUTPUT=$(run_verify)
assert_exit_0 "Builtin commands in doc → exit 0"
assert_output_not_contains "No error for builtins" "references skill 'help'" "$OUTPUT"
teardown_test_env

# ============================================================
# Integration tests
# ============================================================

report_section "=== Integration: all valid (happy path) ==="

setup_test_env
create_hook "full-hook.sh" '#!/bin/bash\n# Use `/full-skill` here'
create_skill "full-skill" 'Use subagent_type=full-agent and `.claude/scripts/full-helper.sh` and `/other-skill`'
create_skill "other-skill"
create_agent "full-agent"
create_script "full-helper"
create_doc "essential-alpha" 'See `essential-beta` and `/full-skill`'
create_doc "essential-beta" '# Beta'
create_settings '{"hooks":{"PreToolUse":[{"command":"bash .claude/hooks/full-hook.sh"}]}}'
OUTPUT=$(run_verify)
assert_exit_0 "Full happy path → exit 0"
assert_output_contains "Reports all valid" "All resource dependencies are valid" "$OUTPUT"
teardown_test_env

# ---

report_section "=== Integration: multiple broken refs ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/agents"
mkdir -p "$TEMP_DIR/.claude/skills"
create_skill "multi-broken" 'Use subagent_type=missing-agent and `/missing-other`'
create_doc "essential-multi-broken" 'See `essential-gone` and `/missing-doc-skill`'
OUTPUT=$(run_verify)
assert_exit_1 "Multiple broken refs → exit 1"
assert_output_contains "Reports error count" "broken dependency reference" "$OUTPUT"
teardown_test_env

# ---

report_section "=== Integration: empty project ==="

setup_test_env
OUTPUT=$(run_verify)
assert_exit_0 "Empty project → exit 0"
teardown_test_env

# ---

report_section "=== Integration: MANIFEST mode ==="

setup_test_env
# Create resources — some in MANIFEST, some not
create_skill "manifest-skill" 'Use subagent_type=manifest-agent here'
create_skill "unmanifested-skill" 'Use subagent_type=missing-agent here'
create_agent "manifest-agent"
mkdir -p "$TEMP_DIR/.claude/agents"
# Create MANIFEST listing only manifest-skill (no index files → MANIFEST mode activates)
create_manifest ".claude/skills/manifest-skill/" ".claude/agents/manifest-agent.md"
# Do NOT create docs/indexes/SKILLS.md so MANIFEST mode activates
OUTPUT=$(run_verify)
assert_exit_0 "MANIFEST mode → exit 0 (unmanifested refs are warnings)"
assert_output_contains "MANIFEST mode active" "MANIFEST mode" "$OUTPUT"
# The unmanifested-skill references missing-agent but it's not in MANIFEST, so it's skipped entirely
assert_output_not_contains "Unmanifested skill not checked" "references agent 'missing-agent'" "$OUTPUT"
teardown_test_env

# ---

report_section "=== Integration: MANIFEST mode scope-skip ==="

setup_test_env
create_skill "scoped-skill" 'Use subagent_type=external-agent here'
mkdir -p "$TEMP_DIR/.claude/agents"
# MANIFEST includes the skill but NOT the agent it references
create_manifest ".claude/skills/scoped-skill/"
OUTPUT=$(run_verify)
assert_exit_0 "MANIFEST scope-skip → exit 0 (not error)"
assert_output_contains "Reports scope-skipped" "scope-skipped" "$OUTPUT"
teardown_test_env

# ---

report_section "=== Integration: real toolkit ==="

TESTS_RUN=$((TESTS_RUN + 1))
REAL_OUTPUT=$(cd "$TOOLKIT_DIR" && bash .claude/scripts/verify-resource-deps.sh 2>&1)
REAL_EXIT=$?
if [ "$REAL_EXIT" = "0" ]; then
    report_pass "Real toolkit validates successfully"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Real toolkit validation failed"
    report_detail "Output: $REAL_OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ============================================================
print_summary
