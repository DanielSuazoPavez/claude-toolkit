#!/usr/bin/env bash
# CC-HOOK: NAME: block-destructive-sql
# CC-HOOK: PURPOSE: Block unconditionally destructive SQL via sqlite3/psql/mysql/duckdb/python -c
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: DISPATCH-FN: grouped-bash-guard=destructive_sql
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=45, scope_hit=80
# CC-HOOK: OPT-IN: none
#
# PreToolUse hook: block destructive SQL issued through bash.
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Blocks (when issued via sqlite3 / psql / mysql / duckdb / python -c):
#   - DROP TABLE / DATABASE / SCHEMA / INDEX (incl. IF EXISTS, CASCADE)
#   - TRUNCATE [TABLE]
#   - DELETE FROM <table> with no WHERE
#   - UPDATE <table> SET ... with no WHERE
#   - ALTER TABLE ... DROP COLUMN
#
# Allows: SELECT, predicated DELETE/UPDATE, INSERT, CREATE TABLE, VACUUM,
# REINDEX, ANALYZE. Also allows ALTER TABLE ... DROP CONSTRAINT/INDEX/CHECK
# — only DROP COLUMN is in scope per the original plan (constraints/indexes
# are reversible). Re-evaluate if telemetry says otherwise.
#
# Out of scope (silently passes — see backlog hooks-block-destructive-sql-stdin-coverage):
#   - psql < script.sql, cat x.sql | sqlite3 db (stdin/file-driven)
#   - ORM/migration framework calls (alembic, knex, prisma)
#
# No bypass mechanism — destructive SQL is the user's call to run directly
# outside the agent. The hook's job is to keep the agent away from it.

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# ============================================================
# match_destructive_sql — cheap predicate
# ============================================================
# Trips only when $COMMAND mentions BOTH a SQL CLI / `python -c` AND a
# destructive keyword (case-insensitive). Plain SELECT or non-SQL bash
# commands fast-miss without entering check_. False positives are OK
# (e.g. an UPDATE keyword that's actually inside a `git commit -m` will
# get filtered by check_ via the structural body).
match_destructive_sql() {
    local cli_re='(^|[[:space:];&|`('"'"'"$])(sqlite3|psql|mysql|duckdb)([[:space:]]|$)|python[0-9.]*[[:space:]]+-c[[:space:]]'
    [[ "$COMMAND" =~ $cli_re ]] || return 1
    # Case-insensitive destructive keyword scan. Uppercase-fold once, regex once.
    local upper="${COMMAND^^}"
    [[ "$upper" =~ (DROP|TRUNCATE|DELETE|UPDATE|ALTER) ]]
}

# ============================================================
# _extract_quoted_after — pull quoted argument(s) following a token
# ============================================================
# Scans $1 (the command) for occurrences of $2 (a CLI token like sqlite3),
# then for each occurrence prints the body of EVERY single- or double-quoted
# argument that follows on the same statement (until ; & | terminator).
# Multiple quoted args matter: `sqlite3 -separator '|' db "DROP ..."` puts
# the destructive SQL in the second quoted arg, not the first.
_extract_quoted_after() {
    local cmd="$1" tok="$2"
    local len=${#cmd}
    local i j ch q body
    # Walk the string looking for the token at a top-level boundary.
    for (( i=0; i<len; i++ )); do
        local rest="${cmd:i}"
        if [[ "$rest" =~ ^(.{0,1})$tok([[:space:]]) ]]; then
            local pre="${BASH_REMATCH[1]}"
            # Boundary char before the token must be empty/start or punctuation.
            if [ -z "$pre" ] || [[ "$pre" =~ [[:space:]\;\&\|\`\(\$\'\"] ]] || [ $i -eq 0 ]; then
                # Advance past the token + the trailing whitespace.
                j=$(( i + ${#tok} + 1 ))
                # Walk forward emitting EVERY quoted arg until a terminator.
                while [ $j -lt $len ]; do
                    ch="${cmd:j:1}"
                    if [ "$ch" = "'" ] || [ "$ch" = '"' ]; then
                        q="$ch"
                        body=""
                        j=$(( j + 1 ))
                        while [ $j -lt $len ]; do
                            ch="${cmd:j:1}"
                            if [ "$ch" = '\' ] && [ "$q" = '"' ] && [ $((j+1)) -lt $len ]; then
                                body+="${cmd:j+1:1}"
                                j=$(( j + 2 ))
                                continue
                            fi
                            if [ "$ch" = "$q" ]; then
                                printf '%s\n' "$body"
                                j=$(( j + 1 ))
                                break
                            fi
                            body+="$ch"
                            j=$(( j + 1 ))
                        done
                        continue
                    fi
                    # Stop scanning at command terminators.
                    if [[ "$ch" =~ [\;\&\|] ]]; then
                        break
                    fi
                    j=$(( j + 1 ))
                done
                # Skip past what we consumed so far so we don't re-find this token.
                i=$j
            fi
        fi
    done
}

# ============================================================
# _strip_sql_comments — remove `/* ... */` block + `-- ...` line comments
# ============================================================
# Pure bash, no fork. Comments inside SQL string literals are NOT preserved
# (we don't track quote state — the inputs we see are already a quoted-arg
# body, so any quote inside is an embedded literal). For our destructive-SQL
# guard purposes, conservative-strip is fine: a comment-only WHERE can no
# longer hide behind comment tokens.
_strip_sql_comments() {
    local in="$1"
    local out="" len=${#in} i ch nxt
    local in_block=0 in_line=0
    for (( i=0; i<len; i++ )); do
        ch="${in:i:1}"
        nxt="${in:i+1:1}"
        if [ "$in_block" -eq 1 ]; then
            if [ "$ch" = "*" ] && [ "$nxt" = "/" ]; then
                in_block=0
                i=$(( i + 1 ))
                out+=" "
            fi
            continue
        fi
        if [ "$in_line" -eq 1 ]; then
            if [ "$ch" = $'\n' ]; then
                in_line=0
                out+=" "
            fi
            continue
        fi
        if [ "$ch" = "/" ] && [ "$nxt" = "*" ]; then
            in_block=1
            i=$(( i + 1 ))
            out+=" "
            continue
        fi
        if [ "$ch" = "-" ] && [ "$nxt" = "-" ]; then
            in_line=1
            i=$(( i + 1 ))
            out+=" "
            continue
        fi
        out+="$ch"
    done
    printf '%s' "$out"
}

# ============================================================
# _has_top_level_where — true when WHERE appears outside (...) at depth 0
# ============================================================
# Subselects' WHERE clauses are at depth >= 1 and don't predicate the outer
# DELETE/UPDATE. $1 is the (uppercased, comment-stripped) statement.
_has_top_level_where() {
    local s="$1"
    local len=${#s} i ch depth=0
    for (( i=0; i<len; i++ )); do
        ch="${s:i:1}"
        case "$ch" in
            '(') depth=$(( depth + 1 )) ;;
            ')') depth=$(( depth - 1 )) ;;
            W)
                if [ "$depth" -eq 0 ]; then
                    # Need a preceding boundary and the chars HERE to follow.
                    if [ $i -gt 0 ] && [[ "${s:i-1:1}" =~ [[:space:]] ]] && [ "${s:i:6}" = "WHERE " ]; then
                        return 0
                    fi
                    if [ $i -gt 0 ] && [[ "${s:i-1:1}" =~ [[:space:]] ]] && [ "${s:i+1:5}" = "HERE" ] && [ $(( i + 6 )) -ge $len ]; then
                        return 0
                    fi
                fi
                ;;
        esac
    done
    return 1
}

# ============================================================
# _is_destructive_sql — structural check on a SQL chunk
# ============================================================
# $1 is a SQL string. Returns 0 (destructive) or 1 (safe). Sets
# _SQL_KIND describing what tripped, for the block reason.
_is_destructive_sql() {
    local sql_raw="$1"
    # Strip SQL comments before any structural test — block + line comments
    # were both used to disguise predicate-less DELETE/UPDATE as predicated.
    local sql
    sql=$(_strip_sql_comments "$sql_raw")
    # Normalize: collapse whitespace/newlines to single spaces, uppercase.
    local norm
    norm=$(printf '%s' "$sql" | tr '\n\r\t' '   ' | tr -s ' ')
    local upper="${norm^^}"

    # DROP TABLE/DATABASE/SCHEMA/INDEX
    if [[ "$upper" =~ (^|[^A-Z_])DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX)([[:space:]]|$) ]]; then
        _SQL_KIND="DROP ${BASH_REMATCH[2]}"
        return 0
    fi
    # TRUNCATE [TABLE]
    if [[ "$upper" =~ (^|[^A-Z_])TRUNCATE([[:space:]]|$) ]]; then
        _SQL_KIND="TRUNCATE"
        return 0
    fi
    # ALTER TABLE ... DROP COLUMN
    if [[ "$upper" =~ (^|[^A-Z_])ALTER[[:space:]]+TABLE[[:space:]].*[[:space:]]DROP[[:space:]]+COLUMN ]]; then
        _SQL_KIND="ALTER TABLE DROP COLUMN"
        return 0
    fi
    # DELETE FROM <ident> ... with no WHERE in the same statement.
    # Split on semicolons so a benign trailing statement can't mask a missing WHERE.
    # Match either at start-of-statement OR right after a CTE close-paren — Postgres
    # allows `WITH t AS (...) DELETE FROM ...`, which the bare `^DELETE` anchor misses.
    # The UPDATE form similarly accepts an optional `[AS] <alias>` between the table
    # name and `SET`, so `UPDATE users AS u SET ...` and `UPDATE users u SET ...`
    # don't slip past a too-strict three-token regex.
    # Identifier class is conservative: any non-space run after the FROM/UPDATE token
    # is treated as the table name (handles quoted identifiers `"x"`/`` `x` ``/`[x]`).
    local stmt
    while IFS= read -r stmt || [ -n "$stmt" ]; do
        stmt="${stmt#"${stmt%%[![:space:]]*}"}"
        [ -z "$stmt" ] && continue
        local s_upper="${stmt^^}"
        if [[ "$s_upper" =~ (^|\))[[:space:]]*DELETE[[:space:]]+FROM[[:space:]]+[^[:space:]]+ ]]; then
            if ! _has_top_level_where "$s_upper"; then
                _SQL_KIND="DELETE without WHERE"
                return 0
            fi
        fi
        if [[ "$s_upper" =~ (^|\))[[:space:]]*UPDATE[[:space:]]+[^[:space:]]+([[:space:]]+(AS[[:space:]]+)?[^[:space:]]+)?[[:space:]]+SET[[:space:]] ]]; then
            if ! _has_top_level_where "$s_upper"; then
                _SQL_KIND="UPDATE without WHERE"
                return 0
            fi
        fi
    done < <(printf '%s' "$norm" | tr ';' '\n')
    return 1
}

# ============================================================
# check_destructive_sql — guard body
# ============================================================
# Assumes match_destructive_sql returned true. Returns 0 = pass, 1 = block.
check_destructive_sql() {
    local CMD="$COMMAND"
    # Unwrap obvious shell wrappers so `bash -c "psql ..."` and `$(...)` /
    # backtick subshells surface the inner command. One sed pipeline so we
    # pay a single fork instead of five — measurable on the dispatcher path.
    CMD=$(printf '%s' "$CMD" | sed -E '
        s/\$\(([^)]*)\)/\1/g
        s/`([^`]*)`/\1/g
        s/\beval[[:space:]]*//g
        s/\bbash[[:space:]]*-c[[:space:]]*//g
        s/\bsh[[:space:]]*-c[[:space:]]*//g
    ')

    # 1. Inline -c/-e/positional arg form (sqlite3, psql, mysql, duckdb).
    #    These CLIs put SQL inside a quoted argument that IS what executes,
    #    so do NOT strip inert content here — extract the quoted body and
    #    run the structural check on it directly.
    local sql_chunks="" chunk
    local cli
    for cli in sqlite3 psql mysql duckdb; do
        while IFS= read -r chunk; do
            [ -z "$chunk" ] && continue
            sql_chunks+="${chunk}"$'\n'
        done < <(_extract_quoted_after "$CMD" "$cli")
    done

    if [ -n "$sql_chunks" ]; then
        while IFS= read -r chunk; do
            [ -z "$chunk" ] && continue
            _SQL_KIND=""
            if _is_destructive_sql "$chunk"; then
                _BLOCK_REASON="BLOCKED: destructive SQL detected — ${_SQL_KIND}. Surface the statement to the user and let them run it directly."
                return 1
            fi
        done <<< "$sql_chunks"
    fi

    # 2. python -c body — coarse heuristic, no AST parsing.
    #    Block when the -c body mentions a SQL-CLI module ref AND a destructive
    #    keyword. Coarse-but-conservative: false positives on python scripts
    #    that mention sqlite3 in a comment plus a destructive keyword in a
    #    string literal are acceptable; missed destructive ones are not.
    local py_body
    py_body=$(_extract_quoted_after "$CMD" "python -c")
    [ -z "$py_body" ] && py_body=$(_extract_quoted_after "$CMD" "python3 -c")
    if [ -z "$py_body" ]; then
        # Try `python -c` with version suffixes (python3.11 etc.)
        if [[ "$CMD" =~ python[0-9.]*[[:space:]]+-c[[:space:]]+(\'|\")(.*) ]]; then
            local rest="${BASH_REMATCH[2]}"
            local q="${BASH_REMATCH[1]}"
            # Take everything up to the next matching quote.
            py_body="${rest%%${q}*}"
        fi
    fi
    if [ -n "$py_body" ]; then
        local py_upper="${py_body^^}"
        if [[ "$py_upper" =~ (SQLITE3|PSYCOPG2|PSYCOPG|MYSQL|DUCKDB) ]]; then
            _SQL_KIND=""
            if _is_destructive_sql "$py_body"; then
                _BLOCK_REASON="BLOCKED: destructive SQL detected in python -c — ${_SQL_KIND}. Surface the statement to the user and let them run it directly."
                return 1
            fi
        fi
    fi

    return 0
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "block-destructive-sql" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_destructive_sql; then
        if ! check_destructive_sql; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
