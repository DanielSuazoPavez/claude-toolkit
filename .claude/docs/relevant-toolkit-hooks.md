# Hook Authoring Pattern — Match/Check Architecture

## 1. Quick Reference

**ONLY READ WHEN:**
- Writing a new hook or refactoring an existing one
- Wiring a hook into the grouped dispatcher
- Debugging why a hook did/didn't run for a given tool call

Hooks split into three parts:
- `match_<name>` — cheap predicate, returns 0 if the hook applies to this call
- `check_<name>` — the actual guard; runs only when `match_` returned 0; sets `_BLOCK_REASON` on block
- `main` — standalone entry point (runs when the script is executed directly, not sourced)

The grouped dispatcher sources hook files as libraries and iterates match → check across a `CHECKS` array. Hooks stay standalone-capable via the dual-mode trigger — same file, two entry paths, single source of truth.

**See also:** `relevant-toolkit-hooks_config.md` for hook triggers and env vars, `/create-hook` skill.

---

## 2. Hook Events (recap)

| Event | Matcher semantics | Grouping |
|---|---|---|
| `PreToolUse` | Matcher is tool-name regex (`Bash`, `Write\|Edit`, `Read\|Grep`) | Yes — dispatcher per tool group |
| `PermissionRequest` | Matcher is tool-name regex | Not grouped (different lifecycle) |
| `SessionStart` | Singleton, no matcher | Not grouped |

The harness spawns one bash process per registered hook per matching tool call. For N hooks registered on `Bash`, an `ls` call pays N × (bash startup + `hook-utils.sh` sourcing + jq parse). The grouped dispatcher folds N hook registrations into one process; match/check adds work-avoidance on top of that amortization.

---

## 3. Standalone vs Grouped Registration

A hook can be registered two ways in `settings.json`:

**Standalone** — the harness runs the script directly:
```json
{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/git-safety.sh"}]}
```

**Grouped** — the dispatcher sources the hook and calls its `match_` / `check_` functions:
```json
{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/grouped-bash-guard.sh"}]}
```

**Rule**: a hook is registered in one mode or the other — never both. Dual registration would run the hook twice.

Every hook stays standalone-capable even when the toolkit's default is grouped. Downstream projects that don't adopt the dispatcher register individual hooks; the same file works for both.

---

## 4. The Match/Check Pattern

### Function signatures

```bash
match_<name>() {
    # Operates on already-parsed globals (COMMAND, TOOL_NAME, FILE_PATH, ...).
    # Returns 0 if this hook applies to the current call, 1 otherwise.
    # No stdin reads, no forks, no jq, no git, no db writes.
    [[ "$COMMAND" =~ ^some-cheap-pattern ]]
}

check_<name>() {
    # Runs only when match_ returned 0.
    # Returns 0 to pass, 1 to block (sets _BLOCK_REASON).
    # Free to do expensive work: forks, jq, git calls, path normalization.
    if <bad-condition>; then
        _BLOCK_REASON="Explain why, offer a fix."
        return 1
    fi
    return 0
}
```

### The cheapness contract (match_)

| Case | Meaning | Cost |
|---|---|---|
| **False positive** | `match_` says yes, `check_` runs, `check_` decides no-op | Acceptable — we did work we'd have done anyway in standalone mode |
| **False negative** | `match_` says no, `check_` is skipped, a guard that should have fired didn't | **Bug** — safety regression |

So when a check needs normalization that the match can't cheaply replicate (example: `block-config-edits` normalizes `~` to `$HOME` before comparing paths), the match stays deliberately broad. Correctness beats optimization.

Forbidden in `match_`:
- Forked subshells (`$(...)`, pipes, backticks)
- `jq` calls
- `git` calls
- DB reads/writes
- File I/O

Allowed: bash pattern matching (`[[ ... =~ ... ]]`, `[[ ... == ... ]]`), parameter expansion, integer arithmetic on already-parsed values.

### The dual-mode trigger

```bash
# ... hook body defines match_<name>, check_<name>, main ...

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

When sourced by the dispatcher, `BASH_SOURCE[0]` differs from `$0` — `main` doesn't run. When executed directly by the harness, they match — `main` runs. Standard bash idiom; no harness support required.

### Minimal skeleton

```bash
#!/bin/bash
# Hook: <name>
# Event: PreToolUse (<matchers>)
# Purpose: <one line>

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

match_<name>() {
    [[ "$COMMAND" =~ <cheap-pattern> ]]
}

check_<name>() {
    if <bad-condition>; then
        _BLOCK_REASON="Reason + suggested fix."
        return 1
    fi
    return 0
}

main() {
    hook_init "<name>" "PreToolUse"
    hook_require_tool "Bash"
    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_<name>; then
        if ! check_<name>; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

Note `dirname "${BASH_SOURCE[0]}"` (not `$0`) for the source path — when sourced from the dispatcher, `$0` points to the dispatcher's path, not the hook's.

---

## 5. Outcomes

`hook_log_substep` records the outcome of each sub-step. Values:

| Outcome | Meaning |
|---|---|
| `pass` | Check ran and allowed the call |
| `block` | Check ran and blocked; `_BLOCK_REASON` was set |
| `approve` | Permission-request approval (PermissionRequest only) |
| `inject` | Hook injected `additionalContext` (non-blocking) |
| `skipped` | Predecessor blocked — this check didn't run |
| `not_applicable` | `match_` returned false — check body was skipped by design |

`skipped` vs `not_applicable` — both indicate the check didn't run, but the reasons differ:
- `skipped`: earlier hook blocked, so we short-circuited. Duration is 0ms.
- `not_applicable`: this hook's predicate said "not my call." Duration is the predicate's cost (trivial, still recorded for analytics).

Analytics queries that want "hooks that ran to completion" should filter out both; queries measuring match accuracy want `not_applicable` specifically.

---

## 6. Authoring a New Hook

1. **Pick the event and matcher.** `PreToolUse` for gating tool calls, `SessionStart` for context injection, `PermissionRequest` for approval flows.
2. **Decide grouping eligibility.** If the matcher overlaps an existing dispatcher's matcher (e.g., Bash), the hook is grouping-eligible.
3. **Write `match_` and `check_`.** Keep `match_` cheap per §4. Put all expensive work in `check_`.
4. **Write `main`.** Thin wrapper: `hook_init` → parse inputs → call `match_ && check_` → emit decision.
5. **Add the dual-mode trigger** at the bottom.
6. **Register** in `settings.json` (standalone) or add to the dispatcher's `CHECKS` array (grouped). Never both.
7. **Test both entry paths.** Unit-test `match_` and `check_` as pure functions. Integration-test via stdin to the `main` entry point.

---

## 7. Testing

Match/check hooks are easier to test than monolithic hooks because the predicate and guard are pure functions.

**Unit tests** (preferred for `match_` and `check_`):
```bash
source .claude/hooks/<name>.sh  # defines match_/check_ without running main

COMMAND="git push --force origin main"
match_<name> && check_<name>
[ $? -eq 1 ] || fail "should have blocked"
[ "$_BLOCK_REASON" = "..." ] || fail "wrong reason"
```

**Integration tests** (for `main` + end-to-end contract):
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"..."}}' | bash .claude/hooks/<name>.sh
# Assert on stdout JSON
```

Existing test harness in `tests/test-hooks.sh` uses the integration pattern. Unit tests for pure match/check functions are a lightweight addition — no new harness needed.

---

## 8. Dispatcher Internals (orientation)

Hook authors don't need to read the dispatcher to write a hook, but a one-paragraph mental model helps when debugging.

`grouped-bash-guard.sh`:
1. Sources `hook-utils.sh` and all registered hook files (they define functions without executing).
2. Calls `hook_init` once and parses stdin once (jq extracts `tool_input.command`, etc.).
3. Iterates the `CHECKS` array. For each entry, calls `match_<name>`; if true, calls `check_<name>`.
4. Logs each substep with its outcome (`pass` / `block` / `skipped` / `not_applicable`).
5. On the first block, emits the decision JSON and marks remaining entries as `skipped`.

`CHECKS` array order matters — earlier checks run first, so put cheap-to-gate hooks before expensive ones. On a block, expensive predecessors that already ran can't be undone, but expensive successors are spared.

### Idempotency guard in hook-utils.sh

The dispatcher sources `hook-utils.sh` once, then sources hook files that each also source `hook-utils.sh` (standalone mode needs it). Without a guard, the second source would reset `HOOK_INPUT=""`, `TOOL_NAME=""`, etc. — every check would see empty globals and bail.

`hook-utils.sh` short-circuits on re-source via `_HOOK_UTILS_SOURCED`:

```bash
if [ -n "${_HOOK_UTILS_SOURCED:-}" ]; then
    return 0
fi
_HOOK_UTILS_SOURCED=1
```

Don't remove or rearrange the guard — it's load-bearing for the dispatcher contract. If you add new globals to `hook-utils.sh`, put them *below* the guard so they don't get reset on re-source.

---

## 9. Current Hook Set

Every Bash-touching hook is match/check + dual-mode. The base distribution's `settings.json` registers `grouped-bash-guard.sh` as the sole Bash PreToolUse hook — it sources the six guards below and dispatches them via `match_`/`check_`. Hooks with non-Bash branches keep their standalone registration for those branches.

| Hook | Standalone matchers | In dispatcher? |
|---|---|---|
| `block-dangerous-commands` | — (dispatcher only) | `dangerous` |
| `git-safety` | EnterPlanMode | `git_safety` |
| `secrets-guard` | Read, Grep | `secrets_guard` |
| `block-config-edits` | Write, Edit | `config_edits` |
| `enforce-make-commands` | — (dispatcher only) | `make` |
| `enforce-uv-run` | — (dispatcher only) | `uv` |

Raiz distribution still uses the split config (each guard standalone on Bash) because `grouped-bash-guard.sh` requires all six sourced files to be present, and raiz only ships four of them. See backlog task `raiz-grouped-bash-guard`.

---

## 10. Anti-Patterns

| Pattern | Why it's wrong |
|---|---|
| `match_` calls `jq`, `git`, or `$(...)` | Defeats work-avoidance — the point of `match_` is to be free |
| Hook registered standalone AND in dispatcher | Runs twice per call |
| `check_` logic also duplicated inside dispatcher | Two sources of truth — drift risk |
| `match_` narrower than `check_` triggers | False negatives — safety regression |
| `main` inline top-level (no function) | Breaks sourcing — dispatcher re-executes the whole body |
| Missing dual-mode trigger | Hook runs its own `main` when the dispatcher sources it |
| `source "$(dirname "$0")/..."` in a hook meant to be sourceable | `$0` points to the dispatcher, not the hook — use `${BASH_SOURCE[0]}` |
