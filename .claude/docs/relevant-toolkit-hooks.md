# Hook Authoring Pattern — Match/Check Architecture

## 1. Quick Reference

**ONLY READ WHEN:**
- Writing a new hook or refactoring an existing one
- Wiring a hook into the grouped dispatcher
- Debugging why a hook did/didn't run for a given tool call

### What hooks are for

Hooks have **two legitimate jobs**. Anything else is the wrong tool.

1. **Guardrails** — block, ask, or approve in pre-events. Stop the agent from doing things it shouldn't (destructive commands, credential exfil, scope drift). Negative value: prevent mistakes. Cheap, deterministic, narrowly-scoped.
2. **Sensible context injection** — SessionStart docs, surface-lessons, guidance nudges. Positive value: shape the work without being prescriptive.

If a hook proposal needs *more* than {block, approve, ask, inject, log, nothing} as its output, the framing is wrong. Specifically reject:

- Hooks that judge output quality (use `/review` or a skill)
- Hooks that coordinate with other hooks for "consensus" (build agents, not hooks)
- Hooks that parse intent or implement business logic (a skill in disguise)
- Hooks that fix model output via PostToolUse formatters (use Stop time, or have the model invoke `make fmt` itself — PostToolUse writes invalidate Edit's freshness cache)
- Hooks that maintain multi-turn state machines (a database with extra steps)

**One-bit assertions are fine** (truncation detector's per-session marker file: "have I already complained?" — not a state machine, an idempotency guard). Multi-turn coordination is not.

### Structure

Hooks split into three parts:
- `match_<name>` — cheap predicate, returns 0 if the hook applies to this call
- `check_<name>` — the actual guard; runs only when `match_` returned 0; sets `_BLOCK_REASON` on block
- `main` — standalone entry point (runs when the script is executed directly, not sourced)

The grouped dispatcher sources hook files as libraries and iterates match → check across a `CHECKS` array. Hooks stay standalone-capable via the dual-mode trigger — same file, two entry paths, single source of truth.

For credential / path / capability detection, **consume the shared registry** instead of inlining regexes — see §11.

**See also:** `relevant-toolkit-hooks_config.md` for hook triggers and env vars, `/create-hook` skill.

---

## 2. Hook Events (recap)

| Event | Matcher semantics | Grouping |
|---|---|---|
| `PreToolUse` | Matcher is tool-name regex (`Bash`, `Write\|Edit`, `Read\|Grep`) | Yes — dispatcher per tool group |
| `PermissionRequest` | Matcher is tool-name regex | Not grouped (different lifecycle) |
| `PermissionDenied` | No matcher (all tools) | Not grouped (pure logger) |
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

JSONL emitters (`hook_log_section`, `hook_log_substep`, `hook_log_context`, `hook_log_session_start_context`, `_hook_log_jsonl`, `_hook_log_timing`) live in the sibling `lib/hook-logging.sh`, sourced by `hook-utils.sh` after globals. Hooks still source only `hook-utils.sh`; the logging file has its own `_HOOK_LOGGING_SOURCED` guard for symmetric idempotency.

---

## 9. Current Hook Set

Every Bash-touching hook is match/check + dual-mode. The base distribution's `settings.json` registers `grouped-bash-guard.sh` as the sole Bash PreToolUse hook — it sources the eight guards below and dispatches them via `match_`/`check_`. Hooks with non-Bash branches keep their standalone registration for those branches.

| Hook | Standalone matchers | In dispatcher? |
|---|---|---|
| `block-dangerous-commands` | — (dispatcher only) | `dangerous` |
| `auto-mode-shared-steps` | — (dispatcher only) | `auto_mode_shared_steps` |
| `block-credential-exfiltration` | — (dispatcher only) | `credential_exfil` |
| `git-safety` | EnterPlanMode | `git_safety` |
| `secrets-guard` | Read, Grep | `secrets_guard` |
| `block-config-edits` | Write, Edit | `config_edits` |
| `enforce-make-commands` | — (dispatcher only) | `make` |
| `enforce-uv-run` | — (dispatcher only) | `uv` |

The dispatcher tolerates absent guards: each `CHECK_SPECS` entry probes its source file before sourcing (`[ -f "$src" ] || continue`), so distributions that ship a subset still work — the missing entries are silently dropped from `CHECKS`. Raiz uses this: it ships `grouped-bash-guard.sh` plus 6 of the 8 guards (no `enforce-make-commands`, no `enforce-uv-run`), and the dispatcher just dispatches the 6 it finds.

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
| Inline credential / path regex when a registry entry could carry it | Forces drift across hooks; new credential shapes need N edits instead of 1 — see §11 |
| Wrong detection target (raw vs stripped) | False negatives when secrets sit inside quoted strings, or false positives from commit-message text — see §11 |
| "Simplifying" security-boundary tests by collapsing the {tool, target, verb} matrix into one assertion per resource | The regex may collapse them; the tests must not — see §12 |
| Hook judges whether the model's output is good enough | Quality is a model/skill job — hooks have stdin and a regex, not the context to judge |
| Hooks coordinating for "consensus" / multi-hook scoring | Hooks are leaf nodes by design; if you need agents talking, build agents |
| PostToolUse hook that writes the file the model just edited (formatter, linter --fix) | Invalidates Edit's freshness cache → forces re-Read on the next edit. Run the formatter on Stop instead, or have the model invoke `make fmt` |
| Hook tracks state across many invocations to make a decision | A database with extra steps; multi-turn state machines don't fit the {one event in, one decision out} shape. One-bit per-session markers (truncation detector) are fine — those are assertions, not state machines |

---

## 11. Detection Target — Raw vs Stripped

When a guard matches user-controlled input against a credential / path / capability regex, it must pick **what** to match against:

| Target | Source | Use when |
|---|---|---|
| **`raw`** | the full `$COMMAND` (or `$FILE_PATH`, etc.) including quoted strings and heredoc bodies | the secret IS the payload — a token literal lives inside a quoted string the model just typed |
| **`stripped`** | `_strip_inert_content "$COMMAND"` — quoted strings and heredoc bodies blanked | the secret is the TARGET of a command — a path or a verb operating on a sensitive resource |

The distinction matters because `_strip_inert_content` blanks quoted-string content. That blank-out is exactly what you want when scanning for `cat .env` inside a commit message that happens to mention `.env`, and exactly what you don't want when scanning for `Authorization: token ghp_...` whose payload is by definition inside a quoted string.

### Decision matrix

```
Is the secret being EXFILTRATED out of context as a literal value?
├── Yes (token in Authorization header, DB URI with embedded creds, AWS_SESSION_TOKEN being echoed)
│   → target: raw   (kind: credential)
│
└── No — the command is REACHING TOWARDS a sensitive resource
    │
    ├── Targeting a file path? (.env, ~/.aws/credentials, ~/.ssh/id_rsa)
    │   → target: stripped   (kind: path)
    │
    └── Performing a sensitive capability? (docker exec, terraform show, gh api)
        → target: stripped   (kind: capability)
```

### Worked examples

| Command | Target | Kind | Why |
|---|---|---|---|
| `curl -H "Authorization: token ghp_AAA..."` | raw | credential | Header value is inside a double-quoted string. Stripping blanks it; the regex must see the original payload. |
| `cat .env.production` | stripped | path | The path is a bare argument. Stripping doesn't affect it; using `stripped` avoids matching `.env` literals inside an unrelated quoted commit message. |
| `git commit -m "fix: remove .env from repo"` | (no match) | — | Stripped target sees `git commit -m "  "` — no `.env` in the skeleton, no false positive. |
| `psql "postgres://user:pass@host/db"` | raw | credential | Embedded `user:pass@` lives inside the connection-string quoted argument. |
| `curl https://api.github.com/...` | stripped | capability | Host is a bare argument; quoted-string blanking is irrelevant either way. |
| `docker exec -it container sh` | stripped | capability | Command-shape match; payload inside `-it` flags doesn't matter. |

### Registry-backed match_

The `.claude/hooks/lib/detection-registry.json` file holds the catalog. Each entry declares its `kind` (`credential` / `path` / `capability`) and `target` (`raw` / `stripped`). Hooks consume the registry via `.claude/hooks/lib/detection-registry.sh`:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/detection-registry.sh"

match_my_guard() {
    detection_registry_match_kind credential "$COMMAND"
}

check_my_guard() {
    if detection_registry_match_kind credential "$COMMAND"; then
        _BLOCK_REASON="$_REGISTRY_MATCHED_MESSAGE (id=$_REGISTRY_MATCHED_ID)"
        return 1
    fi
    return 0
}
```

`detection_registry_match_kind` honors the cheapness contract: the loader builds pre-compiled alternation regexes per `(kind, target)` once at hook startup; the match call is pure-bash `=~` with no fork. The strip helper runs lazily, only when a stripped-target regex exists for the requested kind and the raw match missed.

### Adding a new pattern

Edit `.claude/hooks/lib/detection-registry.json`. Append an entry:

```json
{
  "id": "my-new-token",
  "kind": "credential",
  "target": "raw",
  "pattern": "MYTOK_[A-Za-z0-9]{32,}",
  "message": "MyService token detected in command payload."
}
```

`make validate` runs `validate-detection-registry.sh` which checks: id format (kebab-case), id uniqueness, valid `kind` / `target` enums, and that the `pattern` compiles as a bash ERE. Schema lives at `.claude/schemas/hooks/detection-registry.schema.json`.

### When NOT to use the registry

The registry is for **cross-hook-reusable detection patterns** — credential shapes, file paths, capability gates that more than one guard might want to reference. It is not for hook-specific business logic.

Examples that stay inline:
- `auto-mode-shared-steps` patterns like `gh pr create` or `git push` — auto-mode-specific capability gates, not generally reusable.
- `secrets-guard` per-tool block reasons, allowlist for `.example` / `.template` suffixes, `.git/config` credential-remote check.
- Hook-specific filtering on already-matched results (e.g. "block only when the path is outside `$HOME`").

The split: **registry holds patterns, hook holds policy**. If a future guard would want the same regex you're about to write, registry. If only this hook will ever care, inline.

### Scope boundary between sibling secret-guarding hooks

`secrets-guard.sh` and `block-credential-exfiltration.sh` share a **direction** (keep credentials out of the model's context) but split the **responsibility field**:

| Hook | Responsibility field | Detection |
|---|---|---|
| `block-credential-exfiltration` | credential value/reference **inside a command** — token literals, Authorization headers, `$VAR` refs to credential-shaped env vars | `kind=credential`, `target=raw` (registry) |
| `secrets-guard` | command **reaches towards a sensitive resource** — file paths, env-listing capabilities (`env`, `printenv`, `env\|grep`), `printenv VAR` on credential-shaped names | `kind=path`, `target=stripped` (registry) + inline policy |

Both hooks run on every Bash command via the dispatcher. When both fire on the same command, the stricter block wins — that's intentional defense-in-depth. The split avoids duplicate detection logic but accepts one consequence:

**Accepted FP**: `credential-env-var-name` uses `target=raw`, so a literal mention of `$GH_TOKEN` inside a single-quoted documentation string (e.g. `echo 'use $GH_TOKEN in CI'`) blocks. This is the price of catching the canonical exfil shape `echo "$GH_TOKEN"`, where the var ref lives inside a double-quoted string that strip would blank. The cost (re-run or one-off allowlist) is small compared to a real token leaking.

**Adding a new credential pattern**: pick the responsibility field. Token-shape literal that the model just wrote? `kind=credential, target=raw` (exfil-owned). Path or capability the model is about to invoke? `kind=path/capability, target=stripped` (secrets-guard-owned). Don't add the same pattern under both kinds — the stricter block wins so the redundancy buys nothing and confuses future readers.

---

## 12. Anti-Rampage Coverage for Security-Boundary Tests

The tests for security-boundary hooks (`secrets-guard`, `block-credential-exfiltration`, `auto-mode-shared-steps`) carry assertions that **look** redundant — the same resource asserted multiple times across different tools and verbs. They are not redundant. They are **anti-workaround coverage**, and the coverage requirement is load-bearing.

### Coverage requirement

For every sensitive resource a hook protects, **pin each `{tool, target, verb}` triplet that an agent could reach for as a workaround**. The detection regex may collapse them into one branch; the tests must not.

The triplet axes:

| Axis | Examples |
|---|---|
| **Tool** | `Read`, `Bash`, `Grep` (and `Glob` where it applies) |
| **Target** | the path / payload / capability shape (`/project/.env`, `/project/.env.local`, `prod.env`, `staging.env`) |
| **Verb** | the action variant within a tool (`cat`, `grep`, `rg`, `awk`, `sed`, `source`, `export`; `Grep path=...` vs `Grep glob=...`) |

One assertion per cell of the resulting matrix. Allow-cases (`cat .env.example`, `Read .env.template`) get the same treatment — pinned per tool, not collapsed to "the allowlist works."

### Why the redundancy is load-bearing

Agents respond to a tool block by trying the next tool surface. The observed workaround tree on `.env`:

```
Read .env                       (blocked by secrets-guard Read branch)
  → Bash cat .env               (blocked by Bash regex)
    → Bash grep . .env          (blocked only after grep was added)
      → Bash rg foo .env        (blocked only after rg/awk/sed were added)
        → Grep path=.env        (blocked by Grep path branch)
          → Grep glob=.env*     (blocked by Grep glob branch)
```

This is the literal commit history, not a hypothetical:

| Commit | Gap closed |
|---|---|
| `09a886a` | `grep`/`rg`/`awk`/`sed` reading `.env` via Bash bypassed the cat-only regex |
| `be97214` | Same workaround pattern across other credential files (SSH keys, cloud config, package-manager tokens) |
| `4b0674d` | Suffix-named env files (`prod.env`, `staging.env`) bypassed `ENV_FILE_RE` |
| `b924e8c` | Code-review surfaced missing credential shapes (Stripe, Google API key); added precedence + boundary tests pinning the split between regex branches |

Every one of those was a fix-forward after an agent (typically in auto-mode wrap-up, where the cost of a successful exfil is highest) had already walked the workaround tree. The tests added in those commits are not "extra coverage of the same regex" — they are the **only signal** that prevents the next refactor from silently re-opening the same path.

### What this means for test maintenance

When a future audit (human or agent) looks at the security-boundary suite and sees:

```bash
expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env"}}' ...
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' ...
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep SECRET .env"}}' ...
expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","path":"/project/.env"}}' ...
expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":".env*"}}' ...
```

The reflex is: "these are all the same `.env` regex — collapse to one assertion." Resist it. **The regex is one branch; the workaround surface is N tools × M verbs, and the tests are the contract that all N×M cells stay closed.** A "test simplification" PR that collapses the matrix silently strips the anti-rampage coverage — the regex still passes its own narrow tests, but the next time an agent hits the wall, it walks the tree until something works.

### When a new resource or new tool surface lands

Adding a new sensitive resource (e.g., a new credential file shape) or a new tool that can reach existing resources requires extending the matrix, not just the regex:

1. **Identify the cells.** For each existing resource the new tool could reach, add a cell. For the new resource, populate every applicable cell across existing tools.
2. **Add `expect_block` per cell.** One assertion per `{tool, target, verb}` triplet. Don't collapse "Bash cat" and "Bash grep" into "Bash" — the verb matters.
3. **Add `expect_allow` for the legitimate-use cells.** `Read .env.example` belongs in the suite for the same reason `Bash cat .env.example` does — it pins that the allowlist works on every tool surface.
4. **Reference this section in the PR description** so reviewers understand why the test count is N×M and not N+M.

### Relationship to §11 (registry)

§11 concerns **what** to detect (kind, target, pattern). §12 concerns **how the tests prove it stays detected** as the workaround surface grows. A registry entry without matrix coverage is a regex that compiles — not a guarantee that every tool surface enforces it.
