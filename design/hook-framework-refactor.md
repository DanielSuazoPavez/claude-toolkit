---
date: 2026-04-30
scope: hook framework refactor — design doc (8 contracts)
task: hook-framework-refactor (P0)
inputs:
  - output/claude-toolkit/brainstorm/20260429_2249__brainstorm-feature__hook-framework.md
  - output/claude-toolkit/analysis/20260429_2235__analyze-idea__hook-framework-prior-art.md
  - output/claude-toolkit/analysis/20260429_1902__refactor__claude-hooks.md
status: design (review-ready); implementation plan to follow via /plan
---

# Hook Framework Refactor — Design Doc

## TL;DR

This doc fixes the eight contracts the brainstorm left open. The framework keeps every existing hook working — it adds a declarative bash header per hook as the SSOT, a build-time codegen step that produces dispatchers + JSON index, and a validator that catches drift. No runtime header parsing. No new languages. The current grouped dispatchers already have ~90 % of the runtime shape — the generated dispatcher is essentially what `grouped-bash-guard.sh` does today, but with the `CHECK_SPECS` array generated from headers instead of hand-edited.

The eight contracts below are independently reviewable; you can accept them in any order.

---

## C1. Header grammar

### Format

Strict flat `KEY: value` pairs in a contiguous comment block at the top of every hook file. One key per line. Values are comma-separated lists; whitespace around commas is ignored. No YAML, no nesting, no continuation lines.

The block starts on the line after `#!/usr/bin/env bash` and ends at the first non-comment line *or* the first comment line that doesn't match the `# CC-HOOK: <KEY>: <value>` shape (so existing prose comments below the block are unaffected).

```bash
#!/usr/bin/env bash
# CC-HOOK: NAME: secrets-guard
# CC-HOOK: PURPOSE: Block reaches towards .env, SSH keys, cloud creds
# CC-HOOK: EVENTS: PreToolUse(Read), PreToolUse(Grep), PreToolUse(Bash)
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash), grouped-read-guard(Read)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none
# CC-HOOK: PERF-BUDGET-MS: scope_miss=5, scope_hit=30
# CC-HOOK: SCOPE-FILTER: detection-registry.json#path
# CC-HOOK: RELATES-TO: block-credential-exfiltration(complement-direction)
# CC-HOOK: SHIPS-IN: base, raiz
# Free-form prose continues from here, unchanged ↓
```

### Why `# CC-HOOK:` as the prefix

Distinct enough to grep cleanly (`grep '^# CC-HOOK:' file.sh`), short, and survives copy-paste into other tools. The current ad-hoc `# Settings.json:` and `# Test cases:` comment blocks are subsumed (the test-cases block becomes the smoke-test fixture file referenced by `SMOKE-TEST:` — see C5).

### Key catalog

| Key | Required | Default if omitted | Type | Example |
|---|---|---|---|---|
| `NAME` | required | — | identifier (kebab-case) | `secrets-guard` |
| `PURPOSE` | required | — | one line, ≤120 chars, no period | `Block reaches towards .env, SSH keys, cloud creds` |
| `EVENTS` | required | — | comma-separated `Event(Tool)` or `Event` | `PreToolUse(Bash), SessionStart` |
| `STATUS` | required | — | enum: `stable`, `beta`, `deprecated` | `stable` |
| `OPT-IN` | required | — | enum: `none`, `lessons`, `traceability`, `lessons+traceability` | `traceability` |
| `DISPATCHED-BY` | optional | (empty) | comma-separated `dispatcher(Tool)` | `grouped-bash-guard(Bash)` |
| `PERF-BUDGET-MS` | optional | `scope_miss=5, scope_hit=50` | `scope_miss=N, scope_hit=N` | `scope_miss=5, scope_hit=150` (override) |
| `SHIPS-IN` | optional | `base, raiz` | enum subset: `base`, `raiz`, `internal` | `internal` (override) |
| `SCOPE-FILTER` | optional | (none) | path to JSON registry, `#kind` selector | `detection-registry.json#path` |
| `RELATES-TO` | optional | (none) | comma-separated `hook-name(relation)` | `secrets-guard(complement-direction)` |

Required-key count is **5**. Defaults cover the common case: a stable hook ships in both base and raiz with `scope_miss=5, scope_hit=50` budget. Hooks declare the optional keys only to override. `RELATES-TO` is genuinely optional and aspirational — encode the relationships you know about, leave the rest blank; V15 only fires when a declared relation is broken.

### Multi-value separator

Comma. Inside a single value, parens scope sub-tokens: `EVENTS: PreToolUse(Bash|Read), PreToolUse(Edit)` — the `|` is a matcher *alternation* (Claude Code's native matcher syntax), the comma at the top level is a *list* separator. `Bash|Read` inside one paren means "one settings.json entry with matcher `Bash|Read`"; `PreToolUse(Bash), PreToolUse(Read)` means "two entries". Validator emits a warn when both forms appear for the same event in the same hook (pick one shape).

### Matcher expression rules

- `EventName` alone — no matcher (e.g. `SessionStart`, `PostToolUse`, `PermissionDenied`)
- `EventName(Tool)` — single tool
- `EventName(Tool1|Tool2|...)` — alternation (matches Claude Code's `matcher` field verbatim)
- Tools must be capitalized exactly as Claude Code emits them (`Bash`, `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Task`, `EnterPlanMode`, `WebFetch`, `WebSearch`, `Agent`, `ToolSearch`)
- A hook with `DISPATCHED-BY: grouped-bash-guard(Bash)` must NOT also list `PreToolUse(Bash)` in its own `EVENTS` (the dispatcher carries the registration). Validator catches this as an error.

### Parser

`scripts/hook-framework/parse-headers.sh` — pure bash, regex-based, deterministic. Output is one JSON object per hook to stdout, suitable for `jq -s` aggregation. ~50 lines, no jq dependency for parsing (jq is only needed when consumers want to query the output).

---

## C2. Dispatcher composition algorithm

### Inputs

The codegen step (`scripts/hook-framework/render-dispatcher.sh`) takes:

1. The aggregated headers JSON (output of C1's parser, fed through `jq -s`).
2. A dispatcher *target* — e.g. `grouped-bash-guard` for the Bash event.

### Algorithm

```
For each dispatcher target T:
  1. Find all hooks H where DISPATCHED-BY contains T(...).
  2. Project each H to (name, file, tool_filter) tuples.
  3. Sort by name's position in DISPATCH-ORDER.json (see below).
  4. Emit lib/dispatcher-<T>.sh from a template.
  5. Each emitted dispatcher mirrors the structure of today's
     grouped-bash-guard.sh but with CHECK_SPECS auto-populated.
```

### Order

Order is **explicit, not header-derived**. Headers are SSOT for *which* hooks compose into a dispatcher; ordering lives in `lib/dispatch-order.json`:

```json
{
  "version": 1,
  "dispatchers": {
    "grouped-bash-guard": [
      "block-dangerous-commands",
      "auto-mode-shared-steps",
      "block-credential-exfiltration",
      "git-safety",
      "secrets-guard",
      "block-config-edits",
      "enforce-make-commands",
      "enforce-uv-run"
    ],
    "grouped-read-guard": [
      "secrets-guard",
      "suggest-read-json"
    ]
  }
}
```

**Why a separate file:** ordering is a security property (catastrophic gates first, informative gates after — see today's comment in `grouped-bash-guard.sh:101`). Encoding it via header sort-keys would scatter that decision across N files; the explicit array keeps it auditable in one place. Validator errors when a header declares `DISPATCHED-BY: X(Tool)` but the hook is missing from `dispatch-order.json#X` (or vice versa).

### Generated dispatcher shape

The emitted file is a templated version of today's `grouped-bash-guard.sh`. The template reads the order from `dispatch-order.json` at *generation time*, bakes the `CHECK_SPECS` array into the output, then calls the same `match_<name>` / `check_<name>` functions the source hooks already define. No runtime JSON read.

```bash
#!/usr/bin/env bash
# === GENERATED FILE — do not edit ===
# Source: lib/dispatch-order.json + headers from hooks/*.sh
# Generator: scripts/hook-framework/render-dispatcher.sh
# Regenerate: make hooks-render
# ====================================
source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "grouped-bash-guard" "PreToolUse"
hook_require_tool "Bash"

CHECK_SPECS=(
    "dangerous:block-dangerous-commands.sh"
    "auto_mode_shared_steps:auto-mode-shared-steps.sh"
    # ... rest baked in from dispatch-order.json
)
# ... rest is identical to today's grouped-bash-guard.sh dispatcher loop
```

The `_BLOCK_REASON` / `BLOCK_IDX` short-circuit and the post-block "skipped" rows for unfired checks stay exactly as they are today. Headers do not change runtime behavior; they only change *who knows the list*.

### Short-circuit on block

Unchanged from today: first `check_X` returning 1 sets `_BLOCK_REASON`, breaks the loop, the dispatcher logs `skipped` rows for every later check, then calls `hook_block`. This is already correct; the design does not touch it.

### Distribution tolerance

Today's dispatcher silently skips source files missing from the current distribution (raiz vs. base). The codegen step preserves this: hooks whose `SHIPS-IN` doesn't include the target distribution are emitted with the file-existence probe (`[ -f "$src" ] || continue`) intact, so a generated `grouped-bash-guard.sh` for the base distribution still runs cleanly when synced into a raiz-only project that's missing `enforce-make-commands.sh`. The generator does NOT emit a separate per-distribution dispatcher — one dispatcher, runtime-tolerant.

### Generation cadence

`make hooks-render` writes the generated dispatchers to `.claude/hooks/lib/dispatcher-*.sh`. CI (`make check`) re-runs the generator and `git diff --exit-code` fails if the working tree is stale — same pattern as the existing JSON-backed indexes (`make render-skills`, `make render-agents`). Generated dispatchers are committed (not gitignored) so consumers don't need bash to sync.

---

## C3. Logging schema

The logging library is extracted as-is from `hook-utils.sh` into `lib/hook-logging.sh` (sequencing item 1). The extraction is mechanical — no schema change. What this contract documents is the **smoke-test row shape** and the **testable-at-scale flag** that need to land in the same place.

### Existing rows (kept verbatim)

| `kind` | Where | Notes |
|---|---|---|
| `invocation` | EXIT trap, every hook | Embeds full stdin as `stdin` (parsed) or `stdin_raw` (string fallback) |
| `substep` | Per match/check pair in dispatchers | `outcome: pass\|block\|approve\|inject\|skipped\|not_applicable` |
| `section` | Per output section (session-start) | `bytes_injected` populated |
| `context` | `surface-lessons.sh` only | Specialized matched-lesson row |
| `session_start_context` | `session-start.sh` only | Branch / cwd row |

### New: `kind: smoketest`

Emitted by hooks invoked under the testable-at-scale flag. Same field set as `kind: invocation`, with two changes:

```json
{
  "kind": "smoketest",
  "session_id": "smoketest",
  "invocation_id": "smoketest-<hook>-<fixture>",
  "timestamp": "2026-04-30T00:00:00.000Z",
  "project": "(test)",
  "hook_event": "PreToolUse",
  "hook_name": "secrets-guard",
  "tool_name": "Read",
  "duration_ms": 4,
  "outcome": "block",
  "decision_json": "{\"decision\":\"block\",\"reason\":\"BLOCKED: Reading .env...\"}",
  "fixture": "blocks-dotenv-read"
}
```

- `decision_json` — captures what the hook *would have written to stdout* in real execution. Replaces the side-effect (writing JSON, exiting) with a recorded field.
- `fixture` — name of the smoke-test fixture that produced the row. Validator joins on this.
- `session_id` is hard-coded to `"smoketest"` so the analytics pipeline can filter these out at projection time.

### Testable-at-scale flag

Env var `CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1`. When set:

- `hook_block`, `hook_approve`, `hook_ask`, `hook_inject` capture their decision JSON into `_HOOK_RECORDED_DECISION` instead of writing to stdout.
- `hook_init`'s EXIT trap emits a `kind: smoketest` row instead of `kind: invocation`, including `decision_json` and the `fixture` from `CLAUDE_TOOLKIT_HOOK_FIXTURE`.
- `exit 0` is preserved (process must still terminate cleanly so test runners can capture the trap output).

This is a one-line change inside each `hook_*` outcome helper: `[ "${CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT:-}" = "1" ] && { _HOOK_RECORDED_DECISION="$json"; OUTCOME="$outcome"; exit 0; }` before the existing `echo "$json"; exit 0`.

### Logging library extraction (sequencing item 1)

`lib/hook-logging.sh` exports the public functions `hook_log_section`, `hook_log_substep`, `hook_log_context`, `hook_log_session_start_context`, plus the EXIT trap (`_hook_log_timing`) and `_hook_log_jsonl`. Globals (`SESSION_ID`, `INVOCATION_ID`, `PROJECT`, `_HOOK_TIMESTAMP`, `HOOK_LOG_DIR`, `OUTCOME`, `BYTES_INJECTED`, `TOTAL_BYTES_INJECTED`) stay set by `hook_init` in `hook-utils.sh`; the logging library reads them.

`hook-utils.sh` keeps a one-line backward-compat shim: `source "$(dirname "${BASH_SOURCE[0]}")/hook-logging.sh"`. No call sites change in this step.

---

## C4. Validator checks

`scripts/hook-framework/validate.sh` runs as part of `make check`. Each check is independently testable; severity columns drive the exit code (`error` → exit 1, `warn` → stderr only).

| # | Check | Severity | Catches |
|---|---|---|---|
| V1 | Every `.claude/hooks/*.sh` has a parseable `# CC-HOOK:` header block | error | Missing header on a new hook |
| V2 | Required keys (`NAME`, `PURPOSE`, `EVENTS`, `STATUS`, `OPT-IN`) are present | error | Forgotten field |
| V3 | `NAME` matches filename stem | error | Rename without updating header |
| V4 | `PURPOSE` is non-empty and ≤120 chars | error | Empty or essay-length |
| V5 | `EVENTS` values parse against the matcher grammar | error | Typo (`PreToolUSE`, `PreToolUse(bash)`) |
| V6 | Every `EVENTS` entry **without** `DISPATCHED-BY` for that tool is registered in `settings.json` | error | Crosley's silent-fail case (#1) |
| V7 | Every `settings.json` hooks entry has a corresponding hook with matching `EVENTS` | error | Crosley's silent-fail case (#2): orphan registration |
| V8 | `DISPATCHED-BY: X(Tool)` ⇒ hook is in `dispatch-order.json#X`, and `dispatch-order.json#X` only references real hooks | error | Header/order drift (see fix-it template below) |
| V9 | `DISPATCHED-BY: X(Tool)` ⇒ hook does NOT also list `PreToolUse(Tool)` in its own `EVENTS` | error | Double-registration (would fire twice) |
| V10 | Each `match_<name>` and `check_<name>` function exists for every dispatched hook | error | Source file shipped but functions missing (today's "missing_match_check" substep would no longer be reachable; this is the static equivalent) |
| V11 | Generated dispatchers in `lib/dispatcher-*.sh` are byte-identical to a fresh render | error | Stale generated artifacts |
| V12 | Generated `docs/indexes/HOOKS.md` is byte-identical to a fresh render | error | Stale index |
| V13 | `OPT-IN` value is one of the four enum variants | error | Typo |
| V14 | `SHIPS-IN` values are subset of `{base, raiz, internal}` | error | Typo |
| V15 | `RELATES-TO` references resolve to existing hooks | warn | Renamed sibling without updating relator |
| V16 | `SCOPE-FILTER` references resolve to a JSON file that exists | error | Broken pointer |
| V17 | `PERF-BUDGET-MS`, when present, parses as `scope_miss=N, scope_hit=N` with N as int | error | Typo (only fires when key is declared; defaults skip this check) |
| V18 | Smoke-test fixture file exists for every hook (`tests/hooks/fixtures/<name>/*.json`) | error | New hook with no smoke test |
| V19 | Smoke test passes for every hook (runs the fixture, asserts expected outcome) | error | Hook regression / silent-fail |
| V20 | Per-hook perf measurement during smoke run is within `PERF-BUDGET-MS` | warn | Perf regression (warn, not error — local CPU variance is real) |

V6 + V7 + V18 + V19 together close Crosley's silent-fail gap. V11 + V12 close the "stale generated artifact" gap that would otherwise undermine the SSOT claim.

### V8 fix-it message template

When V8 fails on a missing `dispatch-order.json` entry, the validator emits both sides of the drift and a hint about where in the order to insert. The position is the one call the validator can't make for the author — it's a security/UX decision (catastrophic gates first, informative gates after).

```
ERROR: hook 'foo-guard' declares DISPATCHED-BY: grouped-bash-guard(Bash)
       but is not listed in lib/dispatch-order.json#grouped-bash-guard.
       Add it to the array at the position where it should run
       (catastrophic gates first, informative gates after).
```

The reverse drift (entry in `dispatch-order.json` with no matching `DISPATCHED-BY` header) gets the symmetric message — names the orphan entry and points at the header it expected.

---

## C5. Smoke-test shape

### Fixture layout

```
tests/hooks/fixtures/<hook-name>/
  <fixture-name>.json    # Stub stdin (the JSON Claude Code would send)
  <fixture-name>.expect  # Expected outcome line (see below)
```

Fixture files are tiny — Claude Code's stdin shape is well-known per event. Hooks declare their fixture set by *existence on disk*, not in the header. Reasoning: fixtures are test data, not metadata; tying them to the header would force header churn for every new test.

### Stub stdin per event

Each fixture is one valid Claude Code stdin payload. Examples:

**`tests/hooks/fixtures/secrets-guard/blocks-dotenv-read.json`**
```json
{
  "session_id": "smoketest",
  "tool_use_id": "toolu_smoketest",
  "tool_name": "Read",
  "tool_input": {"file_path": ".env"}
}
```

**`tests/hooks/fixtures/session-start/startup-clean.json`**
```json
{
  "session_id": "smoketest",
  "source": "startup"
}
```

A library at `tests/hooks/fixtures/_templates/` carries one minimal valid stdin per event (PreToolUse/Bash, PreToolUse/Read, PreToolUse/Edit, PreToolUse/Write, PreToolUse/Grep, SessionStart, UserPromptSubmit, PermissionRequest, PermissionDenied, PostToolUse). New fixtures copy the relevant template and tweak `tool_input`.

### `.expect` format

One line per assertion, `key=value`:

```
outcome=block
hook_event=PreToolUse
hook_name=secrets-guard
decision_json_contains=Reading .env file
```

The runner (`tests/hooks/run-smoke.sh`) invokes the hook with `CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1`, captures the emitted `kind: smoketest` row, and asserts each `.expect` key matches. `decision_json_contains` does substring match on the `decision_json` field; `outcome=` does exact match. Other fields can be added (`bytes_injected_min=`, `duration_ms_max=`) without changing the runner contract — it's a generic key/value asserter over JSON.

### Why fixtures on disk and not in headers

Tried the alternative mentally: `# CC-HOOK: SMOKE-TEST: blocks-dotenv-read=outcome=block`. Two problems:

1. Realistic fixtures need real JSON stdin (paths, tool args). Encoding them in comments is unreadable.
2. A hook can have many fixtures (success cases, blocked cases, edge cases). Headers stay short; fixture dirs scale.

Fixtures on disk + V18 (validator asserts the dir exists per hook) gives the same guarantee with no header bloat.

### Smoke run integration

`make hooks-smoke` walks every `tests/hooks/fixtures/<hook>/` directory and runs each fixture through `run-smoke.sh`. `make check` calls `make hooks-smoke` after the validator. CI exit code is the union.

---

## C6. Performance budget

### Targets

Per the brainstorm's suggested defaults:

- **scope-miss budget**: 5 ms (hook header is parsed, `match_*` returns false, EXIT trap fires). Default for all hooks.
- **scope-hit budget**: 50 ms (hook does its full work, `check_*` returns 0 or 1).
- Some hooks override (`session-start.sh` will need a higher scope-hit budget — measured today at ~80 ms in cold cache; budget set to 150 ms in its header).

### Enforcement

- **Smoke run measures `duration_ms`** from the EXIT trap row.
- **V20** (validator warn) — fail soft when measured > budget. Not error, because local CPU variance is real and a single laptop run shouldn't break CI.
- **CI hard fail** is opt-in: a separate `make hooks-perf-strict` target runs the smoke set 5x and asserts the *minimum* duration is within budget. Run on a dedicated CI worker, not on dev laptops. Skipped by default.

### Why scope-miss matters

Crosley keeps 95 hooks under 200 ms / event by ruthless scope filtering — most hooks short-circuit before doing real work. We have 18 hooks; the same discipline still pays off because Bash hooks fire on *every* shell command. A 50 ms hook that fires on every Bash call adds up fast in tight loops. The 5 ms target forces `match_*` predicates to stay cheap (no jq, no forks) — exactly what the existing `match_secrets_guard` already does (pure bash regex).

### What's measured

Today's `_now_ms` in `hook-utils.sh` is the source of truth. The smoke runner records the EXIT-trap `duration_ms`, which covers `hook_init` → first decision → exit. Sub-step durations (already logged by dispatchers) are recorded but not budgeted — only the top-level invocation has a budget.

---

## C7. Scope-filter format

Mirrors `detection-registry.json` exactly — same shape, validator, perf-test pattern. Living in `lib/scope-filters/`:

```
.claude/hooks/lib/
  detection-registry.json     # existing: tokens (credentials, paths)
  scope-filters/
    file-paths.json           # new: hooks-by-path scope filter
    tool-globs.json           # new: hooks-by-tool-glob scope filter
```

### `file-paths.json` shape

```json
{
  "version": 1,
  "kind": "path-scope",
  "entries": [
    {
      "id": "secrets-guard-creds",
      "hook": "secrets-guard",
      "kind": "path",
      "target": "stripped",
      "pattern": "\\.env($|\\.|/)|\\.ssh/id_|\\.aws/(credentials|config)|\\.kube/config",
      "match": "include",
      "notes": "Pre-filter: skip secrets-guard for paths that obviously don't match anything in detection-registry path entries."
    }
  ]
}
```

- `kind: "path-scope"` is the schema discriminator (parallels `detection-registry`'s entries having `kind: credential|path`).
- `hook` ties the entry to a specific hook by `NAME`.
- `match: include` ⇒ the dispatcher invokes the hook only when the path matches. `match: exclude` ⇒ the dispatcher skips the hook when the path matches. Default is `include`.
- `pattern` is a single bash-ERE regex, evaluated by the dispatcher with `[[ "$path" =~ $pattern ]]`.

### Composition with `settings.json` matchers

The Claude Code matcher (`Bash`, `Read|Write`, etc.) fires first — that's the harness's job. Once stdin reaches the dispatcher, *then* the scope filter runs. The two compose:

1. `settings.json` matcher narrows by **event + tool** (harness-side, free).
2. `dispatch-order.json` narrows by **dispatcher participation** (already today).
3. `scope-filters/*.json` narrows by **path/glob** (new — runs in the dispatcher before `match_<name>`).

The scope filter is loaded once at dispatcher startup (single jq read, into bash arrays via `_REGISTRY_*` shims like `detection-registry.sh` does today). Per-hook check: `[[ "$path" =~ ${_SCOPE_RE_secrets_guard:-__never__} ]]` — pure bash, zero overhead per check.

### Why mirror `detection-registry`

That registry already has a validator (`detection_registry_load`), a versioned schema, and a clear contract. Reusing the shape means: same loader, same test harness, same mental model. Adding `kind: path-scope` to the existing registry was considered; rejected because the two concerns are orthogonal (token detection ≠ scope filtering) and merging them would force every hook to read the whole file.

### When to skip the scope filter

A hook without `SCOPE-FILTER:` in its header is dispatched unconditionally (today's behavior). The filter is opt-in; small/cheap hooks don't need it. Validator V16 only fires when the header references a file that doesn't exist.

### Out of scope for rollout

Per the brainstorm — only the *format* is designed here. No hook gets a scope filter in the initial implementation. The first scope filter lands as a follow-up after the framework is in place, when there's a concrete perf hotspot to fix.

---

## C8. Non-redundancy declaration

### `RELATES-TO` syntax

`hook-name(relation)` pairs, comma-separated. The relation is one of a small fixed enum:

| Relation | Meaning | Example |
|---|---|---|
| `complement-direction` | "We block opposite halves of the same threat" | `secrets-guard ↔ block-credential-exfiltration` (one blocks reads at-rest, the other blocks tokens in-flight) |
| `complement-event` | "We do the same check on different events" | `secrets-guard(Read) ↔ secrets-guard(Bash)` (n/a here — same hook — but applies cross-hook for similar pairs) |
| `extends` | "I extend the listed hook with extra cases" | `enforce-make-commands extends enforce-uv-run(scope)` |
| `supersedes` | "I replace the listed hook" (deprecated hooks point forward) | `surface-lessons supersedes legacy-lesson-loader` |
| `informs` | "I produce data the listed hook reads" | `log-tool-uses informs surface-lessons(via hooks.db)` |

### Validator use

- **V15 (warn)**: every `RELATES-TO` reference must resolve to an existing hook. Catches deletions/renames that orphan the pointer.
- **HOOKS.md generator**: for each hook, a "Relates to" subsection lists every incoming and outgoing edge with the relation label. The current ad-hoc prose in `secrets-guard.sh` ("Scope (responsibility split with block-credential-exfiltration.sh): ...") becomes structured: the prose stays in the file as an explanation of *why*, but the *what* is mechanically extracted from `RELATES-TO`.
- **Reciprocity check (warn)**: if A declares `RELATES-TO: B(complement-direction)`, B should declare `RELATES-TO: A(complement-direction)`. Validator emits a warn when an edge is one-sided. Not an error — sometimes asymmetric is correct (`extends`, `supersedes`).

### Why a closed enum and not free-form

Free-form prose is what HOOKS.md has today and the brainstorm flagged it as inadequate ("lives in HOOKS.md prose and the user's head"). A closed enum forces the author to pick a category — which forces them to *think* about whether the relationship is real, and lets the validator catch missing reciprocity. New relation types can be added to the enum (it's small, in one place); free-form text can't be validated at all.

### Existing relationships to encode

From today's prose comments, the initial graph is:

```
secrets-guard (complement-direction) block-credential-exfiltration
secrets-guard (complement-direction) block-credential-exfiltration  # reciprocal
enforce-make-commands (extends) enforce-uv-run(scope)
log-tool-uses (informs) surface-lessons
session-start (informs) detect-session-start-truncation
grouped-bash-guard (extends) [each dispatched hook]
grouped-read-guard (extends) [each dispatched hook]
```

The dispatcher→child relation could also be modeled as `RELATES-TO`, but it's already encoded in `DISPATCHED-BY`. Don't duplicate.

---

## Worked example: `secrets-guard.sh`

End-to-end demonstration of all eight contracts on one real hook.

### Header (C1)

```bash
#!/usr/bin/env bash
# CC-HOOK: NAME: secrets-guard
# CC-HOOK: PURPOSE: Block reaches towards .env, SSH keys, cloud creds at-rest
# CC-HOOK: EVENTS: PreToolUse(Grep)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash), grouped-read-guard(Read)
# CC-HOOK: SCOPE-FILTER: scope-filters/file-paths.json#path-scope
# CC-HOOK: RELATES-TO: block-credential-exfiltration(complement-direction)
# (existing prose comments continue unchanged below)
# PreToolUse hook: block REACHING TOWARDS sensitive resources.
# ...
```

Note: `EVENTS` lists *only* `PreToolUse(Grep)` (the standalone-only branch). Bash and Read are owned by the dispatchers, so they're under `DISPATCHED-BY` instead. V9 enforces this — a hook can't appear in both for the same tool. `PERF-BUDGET-MS` and `SHIPS-IN` are omitted: the defaults (`scope_miss=5, scope_hit=50` / `base, raiz`) match this hook's profile.

### Generated row in `lib/dispatcher-grouped-bash-guard.sh` (C2)

```bash
CHECK_SPECS=(
    # ...
    "secrets_guard:secrets-guard.sh"
    # ...
)
```

Order is taken from `lib/dispatch-order.json#grouped-bash-guard`, which has `secrets-guard` after `git-safety` and before `block-config-edits`. Identical to today's `grouped-bash-guard.sh:64`.

### Smoke-test fixture (C5)

`tests/hooks/fixtures/secrets-guard/blocks-dotenv-read.json`:
```json
{
  "session_id": "smoketest",
  "tool_use_id": "toolu_smoketest",
  "tool_name": "Read",
  "tool_input": {"file_path": ".env"}
}
```

`tests/hooks/fixtures/secrets-guard/blocks-dotenv-read.expect`:
```
outcome=block
hook_event=PreToolUse
decision_json_contains=Reading .env file
```

Plus `allows-dotenv-example.json` (path `.env.example`, expects `outcome=pass` — implicit when the hook exits 0 without calling `hook_block`/`hook_inject`/etc.; runner records `outcome=pass` in the smoketest row).

### Logged row (C3) under smoke run

```json
{
  "kind": "smoketest",
  "session_id": "smoketest",
  "invocation_id": "smoketest-secrets-guard-blocks-dotenv-read",
  "timestamp": "2026-04-30T12:00:00.000Z",
  "project": "(test)",
  "hook_event": "PreToolUse",
  "hook_name": "secrets-guard",
  "tool_name": "Read",
  "duration_ms": 4,
  "outcome": "block",
  "decision_json": "{\"decision\":\"block\",\"reason\":\"BLOCKED: Reading .env file may expose secrets...\"}",
  "fixture": "blocks-dotenv-read"
}
```

### Validator outcomes (C4)

| Check | Result |
|---|---|
| V1–V5 | pass — header parses |
| V6 | pass — `PreToolUse(Grep)` is in `settings.json` |
| V7 | pass — settings.json's `Read|Bash|Grep` registration is partially covered by `DISPATCHED-BY` (Read, Bash) and `EVENTS` (Grep); no orphans |
| V8 | pass — listed in `dispatch-order.json` for both grouped-bash-guard and grouped-read-guard |
| V9 | pass — `EVENTS` does not list Bash or Read |
| V10 | pass — `match_secrets_guard`, `check_secrets_guard`, `match_secrets_guard_read`, `check_secrets_guard_read` all exist |
| V15 | pass — `block-credential-exfiltration` exists; reciprocity present |
| V18 | pass — fixture dir exists |
| V19 | pass — fixture asserts hold |
| V20 | warn possible if duration > 30 ms in scope-hit case (today's measurements suggest ~10 ms; fine) |

### Performance budget (C6)

Defaults inherited (`scope_miss=5, scope_hit=50`). Today's `match_secrets_guard` is pure-bash regex on stripped command — easily <5 ms. `check_secrets_guard` does a few regexes plus an optional `git config` read for the credential-remote case; cold-path measurement needed but expected ~15 ms when no remote check, well under the 50 ms scope-hit budget.

### Scope filter (C7)

`scope-filters/file-paths.json` includes:
```json
{
  "id": "secrets-guard-creds",
  "hook": "secrets-guard",
  "kind": "path",
  "target": "stripped",
  "pattern": "\\.env|\\.ssh/id_|\\.aws/|\\.kube/|\\.config/gh/|\\.docker/|\\.npmrc|\\.pypirc|\\.gem/|\\.gnupg|\\.git/config",
  "match": "include"
}
```

The dispatcher pre-filters on `FILE_PATH` before calling `match_secrets_guard_read` — short-circuits 99 % of Read calls (most reads are not credential paths) below the 5 ms budget. **Note**: per the brainstorm, this is *designed* here but not *rolled out* in the initial implementation.

### Non-redundancy (C8)

`RELATES-TO: block-credential-exfiltration(complement-direction)`. The reciprocal entry is added to `block-credential-exfiltration.sh`'s header (`RELATES-TO: secrets-guard(complement-direction)`). HOOKS.md auto-generates:

> **secrets-guard** — Block reaches towards .env, SSH keys, cloud creds at-rest
> *Relates to:* `block-credential-exfiltration` (complement-direction)

The existing prose paragraph at the top of `secrets-guard.sh` (the "Scope (responsibility split with ...)" block) stays in the file — it's the *why* the validator can't generate. The generated index links *to* that prose, not duplicates it.

---

## What this design does not specify

- **Implementation order / sequencing** — the brainstorm proposed `logging extract → header parser → dispatcher codegen → JSON index → config-driven → scope-filter`. That stays the proposal; `/plan` confirms or revises.
- **Migration of existing hooks** — every current hook needs a header. Done as part of the implementation phase, one PR per group of related hooks. Stack-and-merge is the working model (no other devs on this code, divergence cost is days, not weeks); the validator does not need a degraded-mode fallback for the migration window.
- **Header tooling** (e.g. `claude-toolkit hooks new <name>` to scaffold a hook with a header) — nice-to-have, slot in after framework lands.
- **Path-scope filter rollout** — format only, per the brainstorm's "out of scope" call.
- **Smoketest scope is intentionally minimal** — smoketests prove the hook *fires* and emits the expected outcome shape, not that it correctly handles every edge case. Existing bats-style suites in `tests/hooks/` continue to cover behavioral correctness; smoketests are the framework's quick-path proof of life. A hook with one fixture passes V18/V19 — exhaustive coverage stays in bats.
- **`hooks-config-driven` (P1) stays unbundled.** The brainstorm grouped it with the framework refactor, but verification on 2026-04-30 confirms the bulk of that task already shipped: `auto-mode-shared-steps.sh:45` and `approve-safe-commands.sh:39` already read settings.json via `lib/settings-permissions.sh`. Remaining work is cleanup (delete `validate-safe-commands-sync.sh`), docs (extend `relevant-toolkit-hooks_config.md`), and skill checklist (`/create-hook`) — none of which couple to the framework refactor's contracts. Ships independently.
- **Per-distribution dispatchers if needed later.** The current design assumes one `dispatch-order.json` covers both base and raiz (raiz lacks some hooks but uses the same order for the rest). If a future distribution genuinely needs a different *order* (not just absence of certain hooks), the codegen contract changes from "one dispatcher per event" to "one dispatcher per (event × distribution)". One-way door, but unlikely to land — flagged here so the implementer recognizes the constraint when reading `render-dispatcher.sh`.

---

## Resolved decisions

All open calls flagged during review are settled:

1. **Header prefix: `# CC-HOOK:`** — distinct, greppable, self-documenting; verbosity paid once per key per file is acceptable.
2. **Dispatch order: separate `lib/dispatch-order.json`** — ordering is a security property and stays auditable in one place; sort-key-per-header rejected because inserting a new hook between two existing entries forces global renumbering. V8 catches missing entries with a fix-it message that names both sides of the drift.
3. **Smoke fixtures: on disk under `tests/hooks/fixtures/<hook>/`** — realistic JSON stdin doesn't fit in comment headers, and a hook can have many fixtures (success, blocked, edge cases). V18 asserts the dir exists per hook.
4. **Required-key count: 5** (`NAME, PURPOSE, EVENTS, STATUS, OPT-IN`). `PERF-BUDGET-MS` defaults to `scope_miss=5, scope_hit=50`; `SHIPS-IN` defaults to `base, raiz`. `RELATES-TO` is fully optional. Migration tax falls from 7 required fields × 18 hooks to 5 — most hooks accept the defaults.
5. **`hooks-config-driven` (P1) is unbundled.** Verification on 2026-04-30 confirms `auto-mode-shared-steps.sh` and `approve-safe-commands.sh` already read settings.json via `lib/settings-permissions.sh`. Remaining work (delete `validate-safe-commands-sync.sh`, doc updates, `/create-hook` checklist) is independent of the framework refactor and ships separately.
6. **Migration via stack-and-merge.** No degraded-mode validator needed during migration — divergence cost is days, not weeks (no other devs on this code), and updating main hook-by-hook produces a worse intermediate state than landing the migration as a coherent stack.

Implementation order and tooling scaffolding are deferred to `/plan`.
