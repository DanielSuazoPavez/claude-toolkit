#!/usr/bin/env bash
# Shape A test layer for the 9 dual-mode hooks: source each hook, call
# match_*/check_* in-process, assert on rc + _BLOCK_REASON. ~0ms per case
# (no fork). Locks in the predicate boundary and the predicate-vs-check
# contract that grouped-bash-guard / grouped-read-guard rely on, alongside
# the existing Shape B end-to-end coverage.
#
# Plan: backlog hook-audit-01-shape-a-match-check-pairs.
# Background: design/hook-audit/01-standardized/testability.md.
#
# Note for future contributors: this layer does NOT call hook_init on any
# sourced hook. main() in production calls it; the match_/check_ functions
# themselves don't depend on HOOK_INPUT / SESSION_ID / _HOOK_INIT_TOOL_NAME.
# If you add a check_ that reads any hook_init-populated global, this layer
# will exercise a different code path than production — add a fixture for
# those globals here OR keep the new check_ free of init dependencies.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"

source "$SCRIPT_DIR/../lib/test-helpers.sh"
parse_test_args "$@"

# Source the 9 dual-mode hooks. Each hook's `if [[ "${BASH_SOURCE[0]}" ==
# "${0}" ]]; then main "$@"; fi` guard means main() does NOT fire on source.
# Confirmed by inspection of every dual-mode hook file.
source "$HOOKS_DIR/auto-mode-shared-steps.sh"
source "$HOOKS_DIR/block-config-edits.sh"
source "$HOOKS_DIR/block-credential-exfiltration.sh"
source "$HOOKS_DIR/block-dangerous-commands.sh"
source "$HOOKS_DIR/enforce-make-commands.sh"
source "$HOOKS_DIR/enforce-uv-run.sh"
source "$HOOKS_DIR/git-safety.sh"
source "$HOOKS_DIR/secrets-guard.sh"
source "$HOOKS_DIR/suggest-read-json.sh"

# ============================================================
# Hook-label → match_/check_ function-name dispatch table
# ============================================================
# Function names don't all match `match_<hook-label>` (e.g. credential_exfil,
# secrets_guard_read). Tables resolve a label to the real function names
# exposed by the sourced hook. Associative arrays are used so callers can
# read the value as ${MATCH_FN[label]} — direct variable read, no command
# substitution and no fork (~3× faster than echo $(_fn_for label) at the
# scale of ~80 cases × 2 lookups each).
declare -A MATCH_FN=(
    [auto-mode-shared-steps]=match_auto_mode_shared_steps
    [block-config-edits]=match_config_edits
    [block-config-edits-path]=match_config_edits_path
    [block-credential-exfiltration]=match_credential_exfil
    [block-dangerous-commands]=match_dangerous
    [enforce-make-commands]=match_make
    [enforce-uv-run]=match_uv
    [git-safety]=match_git_safety
    [secrets-guard]=match_secrets_guard
    [secrets-guard-read]=match_secrets_guard_read
    [secrets-guard-grep]=match_secrets_guard_grep
    [suggest-read-json]=match_suggest_read_json
)
declare -A CHECK_FN=(
    [auto-mode-shared-steps]=check_auto_mode_shared_steps
    [block-config-edits]=check_config_edits
    [block-config-edits-path]=check_config_edits_path
    [block-credential-exfiltration]=check_credential_exfil
    [block-dangerous-commands]=check_dangerous
    [enforce-make-commands]=check_make
    [enforce-uv-run]=check_uv
    [git-safety]=check_git_safety
    [secrets-guard]=check_secrets_guard
    [secrets-guard-read]=check_secrets_guard_read
    [secrets-guard-grep]=check_secrets_guard_grep
    [suggest-read-json]=check_suggest_read_json
)

# ============================================================
# Local assertion helpers
# ============================================================
# Each helper:
#   1. Increments TESTS_RUN.
#   2. Calls the resolved function from the sourced hook directly.
#   3. Asserts on rc (and _BLOCK_REASON for check_block).
# Caller is responsible for clearing/setting input vars (COMMAND, FILE_PATH,
# GREP_PATH, GREP_GLOB, PERMISSION_MODE, _BLOCK_REASON) before invoking.

assert_match_hit() {
    local label="$1" desc="$2"
    local fn="${MATCH_FN[$label]}"
    local rc
    TESTS_RUN=$((TESTS_RUN + 1))
    "$fn"; rc=$?
    if [ "$rc" -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=0 (match), got rc=$rc"
    fi
}

assert_match_miss() {
    local label="$1" desc="$2"
    local fn="${MATCH_FN[$label]}"
    local rc
    TESTS_RUN=$((TESTS_RUN + 1))
    "$fn"; rc=$?
    if [ "$rc" -ne 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc!=0 (no match), got rc=0"
    fi
}

assert_check_pass() {
    local label="$1" desc="$2"
    local fn="${CHECK_FN[$label]}"
    local rc
    TESTS_RUN=$((TESTS_RUN + 1))
    _BLOCK_REASON=""
    "$fn"; rc=$?
    if [ "$rc" -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=0 (pass), got rc=$rc"
        report_detail "_BLOCK_REASON: ${_BLOCK_REASON:-<empty>}"
    fi
}

assert_check_block() {
    local label="$1" reason_substr="$2" desc="$3"
    local fn="${CHECK_FN[$label]}"
    local rc
    TESTS_RUN=$((TESTS_RUN + 1))
    _BLOCK_REASON=""
    "$fn"; rc=$?
    if [ "$rc" -eq 0 ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc!=0 (block), got rc=0"
        return
    fi
    if [[ "$_BLOCK_REASON" == *"$reason_substr"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
        log_verbose "_BLOCK_REASON contained: $reason_substr"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected _BLOCK_REASON to contain: $reason_substr"
        report_detail "Got: ${_BLOCK_REASON:-<empty>}"
    fi
}

# xfail-style skip: announce a known-deferred case with a note pointing at
# the backlog id that would resolve it. No assertion, no counter touch — the
# case is here to make the gap visible in test output, not to fail/pass.
TESTS_SKIPPED=0
report_skip() {
    local desc="$1" note="$2"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    if [ "$QUIET" != "1" ]; then
        echo -e "  ${YELLOW}SKIP${NC}: $desc"
        echo "    ($note)"
    fi
}

# Reset every input-var the predicates and checks consume, so a stale value
# from one section can't false-positive in the next. Call at the top of each
# per-hook section (cheap; just clears six variables).
_reset_inputs() {
    COMMAND=""
    FILE_PATH=""
    GREP_PATH=""
    GREP_GLOB=""
    PERMISSION_MODE=""
    VERB=""
    _BLOCK_REASON=""
}

# xfail probe: run an assertion that we EXPECT to fail today (the bug exists).
# When the bug is fixed the assertion will start "succeeding" → flip the SKIP
# to a FAIL with a note, alerting the contributor that the xfail must be
# converted to a real assert_match_hit (or whatever the now-correct shape is)
# and the backlog item closed. Same dispatch table as the real assertions.
xfail_match_hit() {
    local label="$1" backlog_id="$2" desc="$3"
    local fn="${MATCH_FN[$label]}"
    local rc
    "$fn"; rc=$?
    if [ "$rc" -ne 0 ]; then
        # Bug still present (predicate misses where it should hit) — expected.
        report_skip "$desc (xfail)" "see backlog: $backlog_id"
    else
        # Bug fixed — flag so contributor converts xfail into a real assertion.
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "XFAIL UNEXPECTEDLY PASSED: $desc"
        report_detail "$fn returned 0 (predicate now hits) — convert to assert_match_hit"
        report_detail "and close backlog: $backlog_id"
    fi
}

# ============================================================
# enforce-make-commands
# ============================================================
_reset_inputs
report_section "enforce-make-commands"

COMMAND="ls -la"
assert_match_miss enforce-make-commands "match_make misses on ls"

COMMAND="echo hello"
assert_match_miss enforce-make-commands "match_make misses on echo"

COMMAND="uv run pytest tests/foo.py"
assert_match_hit  enforce-make-commands "match_make hits on targeted pytest"
assert_check_pass enforce-make-commands "check_make passes on targeted pytest run"

COMMAND="pytest"
assert_match_hit   enforce-make-commands "match_make hits on bare pytest"
assert_check_block enforce-make-commands "make test" "check_make blocks bare pytest with make-test hint"

COMMAND="pre-commit run --all-files"
assert_check_block enforce-make-commands "make lint" "check_make blocks pre-commit with make-lint hint"

# ============================================================
# enforce-uv-run
# ============================================================
_reset_inputs
report_section "enforce-uv-run"

COMMAND="ls -la"
assert_match_miss enforce-uv-run "match_uv misses on ls"

# Heredoc body containing `python` is blanked by _strip_inert_content,
# so the predicate must NOT fire — protects against false positives on
# heredoc/quoted bodies.
COMMAND='cat <<EOF
this is python code
EOF'
assert_match_miss enforce-uv-run "match_uv misses when python is only inside a heredoc body"

COMMAND='echo "running python script"'
assert_match_miss enforce-uv-run "match_uv misses when python is only inside double-quoted string"

COMMAND="uv run python script.py"
assert_match_hit  enforce-uv-run "match_uv hits on uv run python"
assert_check_pass enforce-uv-run "check_uv passes when uv run is present"

COMMAND="python script.py"
assert_match_hit   enforce-uv-run "match_uv hits on bare python"
assert_check_block enforce-uv-run "uv run python" "check_uv blocks bare python with uv-run hint"

COMMAND="python3 -m pytest"
assert_check_block enforce-uv-run "uv run python" "check_uv blocks bare python3 with uv-run hint"

# ============================================================
# suggest-read-json
# ============================================================
_reset_inputs
report_section "suggest-read-json"

# Predicate fires only on .json suffix
FILE_PATH="/tmp/data.txt"
assert_match_miss suggest-read-json "match_suggest_read_json misses on .txt"

# Allowlisted basename — predicate fires, check passes
FILE_PATH="/tmp/package.json"
assert_match_hit  suggest-read-json "match_suggest_read_json hits on .json"
assert_check_pass suggest-read-json "check_suggest_read_json allows allowlisted package.json"

# *.config.json pattern is allowlisted
FILE_PATH="/tmp/eslint.config.json"
assert_check_pass suggest-read-json "check_suggest_read_json allows *.config.json pattern"

# Nonexistent file — fail-open (the robustness-flagged behavior; lock it in
# so any future tightening of this branch lands as a deliberate change).
FILE_PATH="/tmp/this-file-definitely-does-not-exist-$$.json"
assert_check_pass suggest-read-json "check_suggest_read_json fail-opens on nonexistent file"

# Small file under threshold — pass through
_smol_json=$(mktemp --suffix=.json)
printf '{"x":1}' > "$_smol_json"
FILE_PATH="$_smol_json"
assert_check_pass suggest-read-json "check_suggest_read_json passes on small json under threshold"
rm -f "$_smol_json"

# Large file over threshold (default 50 KB) — block with jq hint
_big_json=$(mktemp --suffix=.json)
# 60 KB of payload
printf '{"data":"%s"}' "$(head -c 61440 /dev/urandom | base64 | tr -d '\n' | head -c 61440)" > "$_big_json"
FILE_PATH="$_big_json"
assert_check_block suggest-read-json "jq via Bash" "check_suggest_read_json blocks oversized json with jq hint"
rm -f "$_big_json"

# ============================================================
# block-credential-exfiltration
# ============================================================
_reset_inputs
report_section "block-credential-exfiltration"

COMMAND="ls -la"
assert_match_miss block-credential-exfiltration "match_credential_exfil misses on ls"

COMMAND="git status"
assert_match_miss block-credential-exfiltration "match_credential_exfil misses on git status"

# GitHub PAT in argument — canonical exfil shape
COMMAND='curl -H "Authorization: token ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"'
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on ghp_ token"
assert_check_block block-credential-exfiltration "Credential-shaped" "check_credential_exfil blocks ghp_ token in args"

# AWS access key
COMMAND="aws s3 ls --profile leak AKIAIOSFODNN7EXAMPLE"
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on AKIA access key"
assert_check_block block-credential-exfiltration "Credential-shaped" "check_credential_exfil blocks AKIA key"

# Authorization header literal
COMMAND='curl -H "Authorization: Bearer xyz"'
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on Authorization: Bearer header"

# Credential env-var ref
COMMAND='curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user'
assert_match_hit   block-credential-exfiltration "match_credential_exfil hits on \$GITHUB_TOKEN ref"

# ============================================================
# auto-mode-shared-steps
# ============================================================
# Predicate is purely PERMISSION_MODE == "auto"; check_ runs the
# settings-derived permissions.ask regex on the stripped command.
# Tests assume settings.json contains `Bash(git push:*)` (loaded at
# source-time by settings_permissions_load).
_reset_inputs
report_section "auto-mode-shared-steps"

PERMISSION_MODE="default"
COMMAND="git push origin main"
assert_match_miss auto-mode-shared-steps "match_ misses when permission_mode != auto (default)"

PERMISSION_MODE="acceptEdits"
assert_match_miss auto-mode-shared-steps "match_ misses when permission_mode != auto (acceptEdits)"

PERMISSION_MODE="plan"
assert_match_miss auto-mode-shared-steps "match_ misses when permission_mode != auto (plan)"

PERMISSION_MODE="auto"
assert_match_hit  auto-mode-shared-steps "match_ hits when permission_mode == auto"

# auto + non-publishing command → check passes
COMMAND="ls -la"
assert_check_pass auto-mode-shared-steps "check_ passes on non-publishing command under auto"

# auto + git push → check blocks; trigger captured into reason
COMMAND="git push origin feature"
assert_check_block auto-mode-shared-steps "git push" "check_ blocks git push under auto, captures trigger"

# Quoted-string mention is blanked by _strip_inert_content — must NOT block
COMMAND='echo "to push run: git push"'
assert_check_pass auto-mode-shared-steps "check_ does not block git push mentioned only inside a quoted string"

# ============================================================
# block-config-edits  (Bash branch)
# ============================================================
# Write/Edit branches now route through match_config_edits_path /
# check_config_edits_path — covered separately in the
# block-config-edits-path section below.
_reset_inputs
report_section "block-config-edits (Bash branch)"

COMMAND="ls -la"
assert_match_miss block-config-edits "match_config_edits misses on ls"

COMMAND="echo hello world"
assert_match_miss block-config-edits "match_config_edits misses on echo"

# Append to ~/.bashrc — block
COMMAND='echo "alias ll=ls" >> ~/.bashrc'
assert_match_hit   block-config-edits "match_config_edits hits on >> ~/.bashrc"
assert_check_block block-config-edits "shell/SSH/git config" "check_config_edits blocks append to ~/.bashrc"

# sed -i on ~/.zshrc — block
COMMAND='sed -i s/foo/bar/ ~/.zshrc'
assert_check_block block-config-edits "shell/SSH/git config" "check_config_edits blocks sed -i on ~/.zshrc"

# mv into ~/.gitconfig — block
COMMAND='mv /tmp/cfg ~/.gitconfig'
assert_check_block block-config-edits "shell/SSH/git config" "check_config_edits blocks mv into ~/.gitconfig"

# Bare write to .claude/settings.json — block
COMMAND='echo {} > .claude/settings.json'
assert_check_block block-config-edits ".claude/settings" "check_config_edits blocks bare write to .claude/settings.json"

# ============================================================
# block-config-edits  (Write/Edit pair)
# ============================================================
# Pair: match_config_edits_path / check_config_edits_path. Drives the home
# config-block branch (rc=1, _BLOCK_REASON set). The .claude/settings*.json
# branch goes through _settings_decision which exits via hook_block/hook_ask
# — that path is exercised by Shape B (test-block-config.sh) instead, since
# Shape A runs sourced and an exit would terminate the test process.
_reset_inputs
report_section "block-config-edits (Write/Edit pair)"

FILE_PATH="/tmp/notes.txt"
assert_match_miss block-config-edits-path "match_config_edits_path misses on unrelated path"

FILE_PATH="$HOME/.bashrc"
VERB="Writing"
assert_match_hit   block-config-edits-path "match_config_edits_path hits on ~/.bashrc"
assert_check_block block-config-edits-path "Writing to shell/SSH/git" "check_config_edits_path blocks Write to ~/.bashrc"

FILE_PATH="$HOME/.zshrc"
VERB="Editing"
assert_check_block block-config-edits-path "Editing shell/SSH/git" "check_config_edits_path blocks Edit on ~/.zshrc"

FILE_PATH="$HOME/.ssh/authorized_keys"
VERB="Writing"
assert_check_block block-config-edits-path "Writing to shell/SSH/git" "check_config_edits_path blocks Write to ~/.ssh/authorized_keys"

FILE_PATH="$HOME/.gitconfig"
VERB="Editing"
assert_check_block block-config-edits-path "Editing shell/SSH/git" "check_config_edits_path blocks Edit on ~/.gitconfig"

# Predicate fires on settings paths too (superset of check_) — match-only
# assertion since check_ would exit through _settings_decision.
FILE_PATH=".claude/sett""ings.json"
assert_match_hit block-config-edits-path "match_config_edits_path hits on .claude/settings.json (settings branch covered by Shape B)"

# ============================================================
# git-safety  (Bash branch only)
# ============================================================
# EnterPlanMode branch runs inline in main() — out of scope here, tracked as
# hook-audit-01-git-safety-enterplanmode-pair.
_reset_inputs
report_section "git-safety"

COMMAND="ls -la"
assert_match_miss git-safety "match_git_safety misses on ls"

COMMAND="git status"
assert_match_miss git-safety "match_git_safety misses on git status (only push|commit gate)"

# Normal push to a feature branch — predicate hits, check passes
COMMAND="git push origin feature"
assert_match_hit  git-safety "match_git_safety hits on git push"
assert_check_pass git-safety "check_git_safety passes on plain feature-branch push"

# Force push to main — severe block
COMMAND="git push --force origin main"
assert_check_block git-safety "Force push to 'main'" "check_git_safety blocks force push to main"

# git push --mirror — severe block (overwrites remote)
COMMAND="git push --mirror origin"
assert_check_block git-safety "--mirror" "check_git_safety blocks git push --mirror"

# Delete protected branch via --delete
COMMAND="git push --delete origin main"
assert_check_block git-safety "Deleting 'main'" "check_git_safety blocks --delete on main"

# Delete protected branch via :branch syntax
COMMAND="git push origin :main"
assert_check_block git-safety "Deleting 'main'" "check_git_safety blocks :main delete syntax"

# ============================================================
# block-dangerous-commands
# ============================================================
_reset_inputs
report_section "block-dangerous-commands"

COMMAND="ls -la"
assert_match_miss block-dangerous-commands "match_dangerous misses on ls"

COMMAND="rm -rf /"
assert_match_hit   block-dangerous-commands "match_dangerous hits on rm -rf /"
assert_check_block block-dangerous-commands "rm -rf on root" "check_dangerous blocks rm -rf /"

COMMAND="mkfs.ext4 /dev/sda1"
assert_check_block block-dangerous-commands "mkfs" "check_dangerous blocks mkfs.ext4"

COMMAND="dd if=/dev/zero of=/dev/sda bs=1M"
assert_check_block block-dangerous-commands "dd to disk device" "check_dangerous blocks dd to /dev/sda"

COMMAND=':(){ :|:& };:'
assert_check_block block-dangerous-commands "Fork bomb" "check_dangerous blocks fork bomb"

COMMAND="sudo apt-get install foo"
assert_check_block block-dangerous-commands "sudo" "check_dangerous blocks sudo"

COMMAND="chmod -R 777 /"
assert_check_block block-dangerous-commands "chmod -R 777" "check_dangerous blocks chmod -R 777 /"

# Interleaved-quote evasion: `'r'm -rf /` collapses to `rm -rf /` only
# after bash re-joins the three quoted segments. match_dangerous now
# pre-strips quotes (mirroring check_dangerous's normalization) so the
# predicate stays a superset of the check. Sibling to the closed
# hook-audit-01-block-dangerous-quote-predicate (2.81.5), which widened
# the predicate's preceding-character alternation for `echo 'rm -rf /'`.
COMMAND="'r'm -rf /"
assert_match_hit block-dangerous-commands \
                 "match_dangerous on quote-evaded 'r'm -rf /"
assert_check_block block-dangerous-commands "rm -rf on root" \
                   "check_dangerous blocks quote-evaded 'r'm -rf /"

# ============================================================
# secrets-guard  (3 pairs: _read, _grep, base Bash)
# ============================================================
# The _git_dir_has_credential_remote branch (called from check_secrets_guard
# and check_secrets_guard_read) is intentionally NOT exercised here — it
# requires a real git config with an embedded user:pass URL. Shape B already
# covers it via a temp git repo fixture; running it from Shape A would
# either need a stub or a fork to mutate cwd, which defeats the purpose of
# the layer. Resolves the second Open item in the plan.
_reset_inputs
report_section "secrets-guard (Read pair)"

# Read pair contract: dispatcher sets FILE_PATH before match_/check_.
FILE_PATH="/some/random/file.txt"
assert_match_miss secrets-guard-read "match_secrets_guard_read misses on unrelated path"

FILE_PATH="$HOME/project/.env"
assert_match_hit  secrets-guard-read "match_secrets_guard_read hits on .env"
assert_check_block secrets-guard-read ".env file" "check_secrets_guard_read blocks .env read"

# Allowlist: .env.example must pass even though predicate hits
FILE_PATH="$HOME/project/.env.example"
assert_match_hit  secrets-guard-read "match_secrets_guard_read hits on .env.example (allowlist enforced in check_)"
assert_check_pass secrets-guard-read "check_secrets_guard_read allows .env.example"

# SSH private key — block; .pub allowed
FILE_PATH="$HOME/.ssh/id_ed25519"
assert_check_block secrets-guard-read "SSH private key" "check_secrets_guard_read blocks ~/.ssh/id_ed25519"
FILE_PATH="$HOME/.ssh/id_ed25519.pub"
assert_check_pass secrets-guard-read "check_secrets_guard_read allows ~/.ssh/id_ed25519.pub"

_reset_inputs
report_section "secrets-guard (Grep pair)"

# Grep pair contract: dispatcher sets GREP_PATH and/or GREP_GLOB.
GREP_PATH=""; GREP_GLOB=""
assert_match_miss secrets-guard-grep "match_secrets_guard_grep misses when no path or glob"

GREP_PATH=""; GREP_GLOB=".env"
assert_match_hit   secrets-guard-grep "match_secrets_guard_grep hits on .env glob"
assert_check_block secrets-guard-grep ".env files" "check_secrets_guard_grep blocks .env glob"

GREP_PATH=""; GREP_GLOB=".env.template"
assert_check_pass secrets-guard-grep "check_secrets_guard_grep allows .env.template glob (allowlist)"

_reset_inputs
report_section "secrets-guard (Bash pair)"

COMMAND="ls -la"
assert_match_miss secrets-guard "match_secrets_guard misses on ls (no read verb, no path hint)"

COMMAND="cat $HOME/.aws/credentials"
assert_match_hit   secrets-guard "match_secrets_guard hits on cat ~/.aws/credentials"
assert_check_block secrets-guard "AWS credentials" "check_secrets_guard blocks cat ~/.aws/credentials"

COMMAND="gpg --export-secret-keys mykey"
assert_check_block secrets-guard "GPG secret keys" "check_secrets_guard blocks gpg --export-secret-keys"

COMMAND="cat README.md"
assert_check_pass secrets-guard "check_secrets_guard passes on cat README.md (no credential path)"

# ============================================================
# Registry-driven superset sweep
# ============================================================
# Locks the invariant `check_acts(x) ⇒ match_returns_true(x)` for every
# entry in detection-registry.json that a dual-mode hook consumes. Each
# pattern gets one synthesized input that check_ would block on; assert
# match_ returns true on that input (and assert check_ blocks for double-
# entry). When a new registry pattern is added, the corresponding hook's
# match_ regex must include it — otherwise this section will fail and
# point at the gap. See hook-audit-01-superset-invariant-shape-a-assertion.
#
# Path patterns route through secrets-guard-read (FILE_PATH input).
# Credential patterns route through block-credential-exfiltration (COMMAND input).
# Synthesized inputs use $HOME/ paths because _match_path_registry filters
# every non-special id to "$HOME/" prefix; predicate inputs match check_
# normalization shape.
_reset_inputs
report_section "registry sweep — path patterns (secrets-guard-read)"

FILE_PATH="$HOME/proj/.env"
assert_match_hit   secrets-guard-read "match: env-file pattern"
assert_check_block secrets-guard-read ".env file" "check: env-file blocks"

FILE_PATH="$HOME/.ssh/id_ed25519"
assert_match_hit   secrets-guard-read "match: ssh-private-key pattern"
assert_check_block secrets-guard-read "SSH private key" "check: ssh-private-key blocks"

FILE_PATH="$HOME/.ssh/config"
assert_match_hit   secrets-guard-read "match: ssh-config pattern"
assert_check_block secrets-guard-read "SSH config" "check: ssh-config blocks"

FILE_PATH="$HOME/.aws/credentials"
assert_match_hit   secrets-guard-read "match: aws-credentials-file pattern"
assert_check_block secrets-guard-read "AWS credentials" "check: aws-credentials-file blocks"

FILE_PATH="$HOME/.kube/config"
assert_match_hit   secrets-guard-read "match: kube-config pattern"
assert_check_block secrets-guard-read "kubeconfig" "check: kube-config blocks"

FILE_PATH="$HOME/.config/gh/hosts.yml"
assert_match_hit   secrets-guard-read "match: gh-cli-config pattern"
assert_check_block secrets-guard-read "GitHub CLI" "check: gh-cli-config blocks"

FILE_PATH="$HOME/.docker/config.json"
assert_match_hit   secrets-guard-read "match: docker-config pattern"
assert_check_block secrets-guard-read "Docker config" "check: docker-config blocks"

FILE_PATH="$HOME/.npmrc"
assert_match_hit   secrets-guard-read "match: npmrc pattern"
assert_check_block secrets-guard-read ".npmrc" "check: npmrc blocks"

FILE_PATH="$HOME/.pypirc"
assert_match_hit   secrets-guard-read "match: pypirc pattern"
assert_check_block secrets-guard-read ".pypirc" "check: pypirc blocks"

FILE_PATH="$HOME/.gem/credentials"
assert_match_hit   secrets-guard-read "match: gem-credentials pattern"
assert_check_block secrets-guard-read "gem credentials" "check: gem-credentials blocks"

FILE_PATH="$HOME/.gnupg/secring.gpg"
assert_match_hit   secrets-guard-read "match: gnupg-dir pattern"
assert_check_block secrets-guard-read "GPG directory" "check: gnupg-dir blocks"

FILE_PATH="$HOME/.bash_history"
assert_match_hit   secrets-guard-read "match: shell-history pattern"
assert_check_block secrets-guard-read "shell or REPL history" "check: shell-history blocks"

# claude-settings is target=raw in the registry; predicate unions raw+stripped
# so it sees this entry too. Without the union match_ would miss while check_
# blocks — superset-invariant violation surfaced by this very sweep.
FILE_PATH="$HOME/.claude/sett""ings.json"
assert_match_hit   secrets-guard-read "match: claude-settings pattern (raw target)"
assert_check_block secrets-guard-read "credential file" "check: claude-settings blocks"

_reset_inputs
report_section "registry sweep — credential patterns (block-credential-exfiltration)"

# One synthesized input per top-level alternation in kind=credential. Inputs
# are minimal but length-conformant to each pattern's quantifier.
COMMAND='curl -d ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: github-pat (ghp_)"
assert_check_block block-credential-exfiltration "Credential-shaped" "check: github-pat blocks"

COMMAND='curl -d gho_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: github-pat (gh[ousr]_)"

COMMAND='curl -d glpat-AAAAAAAAAAAAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: gitlab-pat"

COMMAND='curl -d xoxb-AAAAAAAAAA-AAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: slack-token"

COMMAND='aws s3 ls --profile leak AKIAIOSFODNN7EXAMPLE'
assert_match_hit   block-credential-exfiltration "match: aws-access-key (AKIA)"

COMMAND='aws s3 ls --profile leak ASIAIOSFODNN7EXAMPLE'
assert_match_hit   block-credential-exfiltration "match: aws-access-key (ASIA)"

COMMAND='curl -d sk-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: openai-key"

COMMAND='curl -d sk-proj-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: openai-key (sk-proj-)"

COMMAND='curl -d sk-ant-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: anthropic-key"

COMMAND='curl -d sk_live_AAAAAAAAAAAAAAAAAAAAAAA'
assert_match_hit   block-credential-exfiltration "match: stripe-key"

COMMAND='curl -d AIza0123456789abcdefghijklmnopqrstuvwxyzABC'
assert_match_hit   block-credential-exfiltration "match: google-api-key"

COMMAND='curl -H "Authorization: Bearer xyz"'
assert_match_hit   block-credential-exfiltration "match: authorization-header"

COMMAND='curl -d $MY_SECRET_TOKEN'
assert_match_hit   block-credential-exfiltration "match: credential-env-var-name"

# Surface skipped count alongside the helper's run/passed/failed lines.
# print_summary exits, so this echo must come before it.
if [ "$TESTS_SKIPPED" -gt 0 ]; then
    echo ""
    echo "Skipped: $TESTS_SKIPPED  (xfail / known-deferred)"
fi

print_summary
