#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

report_section "=== block-destructive-sql.sh ==="
hook="block-destructive-sql.sh"

batch_start "$hook"

# --- Block: direct destructive SQL via each named CLI ---
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "DROP TABLE users"')" \
    "blocks DROP TABLE via psql -c"
batch_add block "$(mk_pre_tool_use_payload Bash 'sqlite3 db "DELETE FROM logs"')" \
    "blocks DELETE without WHERE via sqlite3"
batch_add block "$(mk_pre_tool_use_payload Bash 'mysql -e "TRUNCATE foo"')" \
    "blocks TRUNCATE via mysql -e"
batch_add block "$(mk_pre_tool_use_payload Bash 'duckdb db "DROP DATABASE prod"')" \
    "blocks DROP DATABASE via duckdb"
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "UPDATE users SET disabled=1"')" \
    "blocks UPDATE without WHERE"
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "ALTER TABLE users DROP COLUMN email"')" \
    "blocks ALTER TABLE DROP COLUMN"
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "DROP INDEX idx_users_email"')" \
    "blocks DROP INDEX"
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "DROP SCHEMA archive CASCADE"')" \
    "blocks DROP SCHEMA"

# --- Block: chained / wrapped forms ---
batch_add block "$(mk_pre_tool_use_payload Bash 'cd /tmp && sqlite3 db "DROP TABLE x"')" \
    "blocks chained sqlite3 DROP TABLE"
batch_add block "$(mk_pre_tool_use_payload Bash 'echo done; psql -c "TRUNCATE foo"')" \
    "blocks chained psql TRUNCATE"
batch_add block "$(mk_pre_tool_use_payload Bash '$(psql -c "DROP TABLE x")')" \
    "blocks subshell \$(psql ...)"
batch_add block "$(mk_pre_tool_use_payload Bash '`mysql -e "DROP DATABASE prod"`')" \
    "blocks backtick \`mysql ...\`"
batch_add block "$(mk_pre_tool_use_payload Bash "bash -c \"sqlite3 db 'DROP TABLE x'\"")" \
    "blocks bash -c wrapper around sqlite3 DROP"
batch_add block "$(mk_pre_tool_use_payload Bash "eval \"psql -c 'TRUNCATE foo'\"")" \
    "blocks eval-wrapped psql TRUNCATE"

# --- Block: python -c interpreter body ---
batch_add block "$(mk_pre_tool_use_payload Bash "python -c \"import sqlite3; sqlite3.connect('db').execute('DROP TABLE x')\"")" \
    "blocks python -c with sqlite3 DROP TABLE"

# --- Block: WHERE-disguising bypasses (review T1/T2/T5) ---
# Block-comment WHERE: the engine ignores it, the regex shouldn't honor it.
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "DELETE FROM tbl /* WHERE id=1 */"')" \
    "blocks DELETE with block-comment-disguised WHERE"
# Line-comment WHERE: same shape, line comment.
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "DELETE FROM tbl -- WHERE id=1"')" \
    "blocks DELETE with line-comment-disguised WHERE"
# Subselect WHERE: outer DELETE is unpredicated; inner WHERE is at paren-depth 1.
batch_add block "$(mk_pre_tool_use_payload Bash 'psql -c "DELETE FROM tbl USING (SELECT id FROM other WHERE x=1) o"')" \
    "blocks DELETE where only WHERE is inside a subselect"

# --- Block: sqlite3 with -separator (destructive SQL is NOT the first quoted arg) ---
batch_add block "$(mk_pre_tool_use_payload Bash "sqlite3 -separator '|' db \"DROP TABLE logs\"")" \
    "blocks sqlite3 -separator '|' db DROP TABLE (multi-quote)"

# --- Allow: toolkit's own SELECT-only patterns (must not regress) ---
batch_add allow "$(mk_pre_tool_use_payload Bash 'sqlite3 lessons.db "SELECT count(*) FROM lessons"')" \
    "allows SELECT count(*) (surface-lessons.sh / session-start.sh pattern)"
batch_add allow "$(mk_pre_tool_use_payload Bash "sqlite3 -separator '|' db \"SELECT id, summary FROM lessons WHERE active=1\"")" \
    "allows sqlite3 -separator with SELECT"
batch_add allow "$(mk_pre_tool_use_payload Bash 'sqlite3 db "CREATE TABLE foo (id INTEGER)"')" \
    "allows additive CREATE TABLE"

# --- Allow: predicated mutations ---
batch_add allow "$(mk_pre_tool_use_payload Bash "psql -c \"DELETE FROM logs WHERE created_at < now() - interval '7 days'\"")" \
    "allows DELETE ... WHERE ..."
batch_add allow "$(mk_pre_tool_use_payload Bash 'mysql -e "UPDATE users SET disabled=1 WHERE id=42"')" \
    "allows UPDATE ... WHERE ..."
batch_add allow "$(mk_pre_tool_use_payload Bash 'psql -c "VACUUM"')" \
    "allows VACUUM"
batch_add allow "$(mk_pre_tool_use_payload Bash 'sqlite3 db "REINDEX"')" \
    "allows REINDEX"
batch_add allow "$(mk_pre_tool_use_payload Bash "psql -c \"INSERT INTO logs (msg) VALUES ('hi')\"")" \
    "allows INSERT"

# --- Allow: false-positive guards (no SQL CLI present, or destructive token only inside text) ---
batch_add allow "$(mk_pre_tool_use_payload Bash 'git commit -m "drop table from logs"')" \
    "allows git commit message mentioning drop table"
batch_add allow "$(mk_pre_tool_use_payload Bash 'echo "TRUNCATE TABLE x"')" \
    "allows echo of TRUNCATE (no SQL CLI)"
batch_add allow "$(mk_pre_tool_use_payload Bash "python -c \"print('DROP TABLE x is destructive')\"")" \
    "allows python -c with no SQL module reference (just text)"
batch_add allow "$(mk_pre_tool_use_payload Bash 'ls -la')" \
    "allows ls -la"
batch_add allow "$(mk_pre_tool_use_payload Bash 'git status')" \
    "allows git status"

# --- Edge: stdin/file-driven SQL is documented out-of-scope (allow) ---
batch_add allow "$(mk_pre_tool_use_payload Bash 'psql < destructive.sql')" \
    "allows psql < script.sql (out of scope per backlog hooks-block-destructive-sql-stdin-coverage)"
batch_add allow "$(mk_pre_tool_use_payload Bash 'cat script.sql | sqlite3 db')" \
    "allows cat script.sql | sqlite3 (out of scope)"

batch_run

# --- No-bypass invariant: assert hook source file contains no env-var or
# flag escape hatch. Future contributors might be tempted to add one — this
# is the canary. Update the regex if a legitimate non-bypass env var is
# introduced (none today).
report_section "no-bypass invariant"
hook_src="$HOOKS_DIR/block-destructive-sql.sh"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -Eq 'CLAUDE_TOOLKIT_(ALLOW|BYPASS|FORCE)_(DESTRUCTIVE|SQL)|--force|--allow-destructive' "$hook_src"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "no bypass mechanism present in hook source"
    report_detail "Found a token suggesting a bypass — see $hook_src"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "no bypass mechanism present in hook source"
fi

print_summary
