---
category: 00-shared
axis: inventory
status: drafted
date: 2026-05-02
---

# 00-shared — inventory

Catalog of `.claude/hooks/lib/` files: size, what each provides, who sources it, hot-path status. Other `00-shared` axis reports (performance, robustness, testability, clarity) reference this file rather than re-deriving caller maps.

**Convention:** "hot path" = sourced by every hook firing on at least one frequent event (PreToolUse on Bash/Read/Write/Edit, PostToolUse, PermissionRequest). "Warm path" = sourced only by less-frequent events (SessionStart, UserPromptSubmit, PermissionDenied, EnterPlanMode-only). "Cold path" = sourced once-per-load behind an idempotency guard, but the cost is paid once per fork.

All sourced files use `_<NAME>_SOURCED=1` idempotency guards — re-sourcing is a no-op except for `hook_init`'s deliberate global resets in `hook-utils.sh`.

## Members

| File | LoC | Kind | Hot path? |
|------|----:|------|-----------|
| `hook-utils.sh`              | 457 | bash, sourced | yes — every hook |
| `hook-logging.sh`            | 280 | bash, sourced (by hook-utils.sh) | yes — every hook |
| `detection-registry.sh`      | 178 | bash, sourced | warm — 4 hooks |
| `detection-registry.json`    | 167 | data (JSON) | loaded by detection-registry.sh |
| `settings-permissions.sh`    | 153 | bash, sourced | warm — 2 hooks |
| `dispatcher-grouped-bash-guard.sh` | 31 | bash, **generated**, sourced | scoped to `02-dispatchers/` |
| `dispatcher-grouped-read-guard.sh` | 25 | bash, **generated**, sourced | scoped to `02-dispatchers/` |
| `dispatch-order.json`        | 19  | data (JSON) | input to dispatcher generator |

The two `dispatcher-grouped-*-guard.sh` files belong to category 02; listed here only because they live in `lib/`.

## hook-utils.sh

Shared init / decision / introspection API. Sources `hook-logging.sh` from inside its idempotency guard so callers only need to source one file.

**Public API used by hooks:**

- `hook_init NAME EVENT` — read stdin (one `cat` from non-TTY), populate `HOOK_INPUT`, `HOOK_NAME`, `HOOK_EVENT`, `INVOCATION_ID`, `SESSION_ID`, `HOOK_SOURCE`, `CALL_ID`, `_HOOK_INIT_TOOL_NAME`, `_HOOK_TIMESTAMP`, `HOOK_START_MS`. Installs the `_hook_log_timing` EXIT trap. Single consolidated `jq` call extracts 5 fields via SOH-separated output (post-2.81.1; was 4-5 separate `jq` forks).
- `hook_require_tool TOOL [TOOL...]` — exit 0 unless `TOOL_NAME` matches; sets `_HOOK_ACTIVE=true` on match. SessionStart hooks skip this (init pre-marks `_HOOK_ACTIVE=true`).
- `hook_get_input JQ_PATH` — one `jq -r` per call. Cheap helper for non-hot-path field reads; hot stdin fields are already in init globals.
- `hook_block REASON` / `hook_approve REASON` / `hook_ask REASON` / `hook_inject CONTEXT` — emit decision JSON and `exit 0`. In `CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1` mode (smoke), the JSON is captured into `_HOOK_RECORDED_DECISION` for the smoketest writer instead of being printed.
- `hook_extract_quick_reference FILE` — pure-`awk`, file-only; emits the `## 1. Quick Reference` block from a markdown file. Used by `session-start.sh`.
- `hook_feature_enabled lessons|traceability` — env-var gate (`CLAUDE_TOOLKIT_LESSONS`, `CLAUDE_TOOLKIT_TRACEABILITY`). All `hook_log_*` writers gate on `traceability`.

**Internal helpers:**

- `_now_ms` — ms timestamp via `EPOCHREALTIME` (bash 5+, no fork) with `date` fallback. Pads `frac` so a short-`.frac` `EPOCHREALTIME` doesn't return a 10× small value.
- `_strip_inert_content COMMAND` — pure-bash heredoc + quoted-string blanker. Called lazily by `detection_registry_match_kind` only when a `stripped`-target regex exists for the kind. ~70 LoC; the most expensive pure-bash function in the libs.
- `_resolve_project_id` — sqlite3 lookup against `~/.claude/sessions.db.project_paths` (or basename fallback). Calls `sqlite3` (fork). One `_resolve_project_id` call per hook firing in real-session, **only when something reads `$PROJECT`**. Triggered lazily by `_ensure_project`.
- `_ensure_project` — boolean-cached gate around `_resolve_project_id`. Called from each `hook_log_*` writer in `hook-logging.sh` and from any hook that reads `$PROJECT` directly. Post-2.81.2: hooks that don't write JSONL skip the sqlite3 fork entirely.
- `_hook_perf_probe PHASE` — emits `HOOK_PERF\t<phase>\t<delta_ms>` to stderr when `CLAUDE_TOOLKIT_HOOK_PERF=1`; no-op otherwise. Used by `measurement/probe/`.

**Globals set by hook_init** (read by `hook-logging.sh` and consumer hooks): `HOOK_INPUT`, `INPUT` (alias), `HOOK_NAME`, `HOOK_EVENT`, `TOOL_NAME`, `INVOCATION_ID`, `SESSION_ID`, `HOOK_SOURCE`, `CALL_ID`, `PROJECT` (lazy), `_PROJECT_RESOLVED`, `HOOK_START_MS`, `_HOOK_TIMESTAMP`, `OUTCOME`, `BYTES_INJECTED`, `TOTAL_BYTES_INJECTED`, `HOOK_LOG_DIR`, `_HOOK_ACTIVE`, `_HOOK_INPUT_VALID`, `_HOOK_INIT_TOOL_NAME`, `_HOOK_RECORDED_DECISION`.

**Sourced by:** every standardized hook (13), the two dispatcher entrypoints (which then re-source it via children — guard prevents re-init), session-start, surface-lessons. **Effectively every hook firing.**

## hook-logging.sh

JSONL row emission for traceability. Extracted from `hook-utils.sh` during the framework refactor (C3, sequencing item 1) — sourced from `hook-utils.sh:57` so no hook sources it directly.

**Public API:**

- `hook_log_section NAME CONTENT` — used by session-context hooks. Bumps `TOTAL_BYTES_INJECTED` regardless of feature gate; `jq -c -n` row build only when traceability is enabled. Calls `_ensure_project`.
- `hook_log_substep NAME DURATION_MS OUTCOME [BYTES]` — used by dispatchers + grouped guards. Same shape as `hook_log_section`. Outcome vocabulary: `pass | block | approve | inject | skipped | not_applicable` (see `relevant-toolkit-hooks.md` §5).
- `hook_log_context RAW_CONTEXT KEYWORDS MATCH_COUNT MATCHED_IDS` — used by `surface-lessons.sh`. Writes to `surface-lessons-context.jsonl` (separate file).
- `hook_log_session_start_context GIT_BRANCH MAIN_BRANCH CWD` — used by `session-start.sh`. Writes to `session-start-context.jsonl`.

**Internal:**

- `_hook_log_jsonl FILE LINE` / `_hook_log_jsonl_unguarded FILE LINE` — append-one-line writer. The unguarded variant is for the smoketest branch only.
- `_hook_log_timing` — `EXIT` trap installed by `hook_init`. Emits the `kind: invocation` row with full stdin embedded as a parsed object (when `_HOOK_INPUT_VALID=true`) or as `stdin_raw` (fallback). Skipped when `_HOOK_ACTIVE=false` (early `hook_require_tool` exit).
- `_hook_log_smoketest` — sibling writer for `CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1` mode. Bypasses the traceability gate; writes to `smoketest.jsonl`.

**Hot-path cost:** every hook firing pays one `jq -c` fork in `_hook_log_timing` (when traceability is on and the hook matched a tool). Hooks that call `hook_log_substep` or `hook_log_section` add one `jq -c -n` fork per call.

**Sourced by:** transitively by every hook (via `hook-utils.sh:57`).

**Direct API callers** (use anything beyond the EXIT-trap row):
- `grouped-bash-guard.sh`, `grouped-read-guard.sh` — `hook_log_substep` per child check
- `session-start.sh` — `hook_log_section`, `hook_log_session_start_context`
- `surface-lessons.sh` — `hook_log_context`, plus section logging

## detection-registry.sh

Loader + matcher for `detection-registry.json` (22 entries at audit start, all `kind=credential` with `target=raw` so far per the file head).

**Public API:**

- `detection_registry_load` — idempotent. One `jq` fork (post-2.81.1; was `jq | TSV | base64 -d × 2 per entry`, ~130ms on 22 entries). Populates parallel arrays + per-`(kind, target)` alternation regexes (`_REGISTRY_RE__<kind>__<target>`).
- `detection_registry_match KIND TARGET INPUT` — pure-bash `=~` against the precompiled alternation. Sets `_REGISTRY_MATCHED_ID` / `_REGISTRY_MATCHED_MESSAGE` on hit (one extra walk over parallel arrays to find the specific entry).
- `detection_registry_match_kind KIND COMMAND` — tries `raw` target first, then strips inert content via `_strip_inert_content` (lazy — only if a `stripped`-target regex exists) and tries `stripped`. Used by guards that need to resist heredoc/quoted-string false positives.

**Cheapness contract** (per file header): "load calls jq once at startup. Match calls are pure bash =~ against pre-built alternation regexes — no fork." This is the post-2.81.1 shape.

**Sourced by:** `secrets-guard.sh`, `block-credential-exfiltration.sh`, `block-config-edits.sh`, `auto-mode-shared-steps.sh` (4 hooks). Not on the absolute hottest path (Bash dispatcher fans out to multiple, but Read/Write/Edit don't all source it). Cost on Bash firings: load runs once per dispatcher invocation (children reuse via the idempotency guard).

## detection-registry.json

Static data: `{version: 1, entries: [...]}`. Fields per entry: `id`, `kind`, `target` (`raw` | `stripped`), `pattern`, `message`. Currently 22 entries; `kind=credential` for all entries seen in the head — full population check is for `01-standardized/`.

Override path: `CLAUDE_TOOLKIT_CLAUDE_DETECTION_REGISTRY` (used by validator + tests).

## settings-permissions.sh

Loader for the `permissions.allow` / `permissions.ask` arrays in `.claude/settings.json` (95 entries total in this project's settings — 45 allow / 50 ask; 80 of those are `Bash(...)` and become prefixes — 30 allow + 50 ask).

**Public API:**

- `settings_permissions_load` — idempotent. One `jq` fork emitting `<bucket>\t<entry>` lines. Filters to `Bash(...)` in bash; strips wrapper + trailing glob shapes (`:*`, ` *`, `*`, `**`); rejects prefixes containing unhandled ERE metacharacters (logs to stderr, skips entry); builds an anchored alternation regex `(^|[[:space:];&|])(p1|p2|...)([[:space:]]|$)` for each bucket. Both prefix-extraction and ERE-escape logic are inlined into the main loop (pre-2.81.1: separate helpers called via `$(...)` — 90 subshells per load, ~190ms).

**Globals populated:**

- `_SETTINGS_PERMISSIONS_ALLOW_PREFIXES` (array)
- `_SETTINGS_PERMISSIONS_ASK_PREFIXES` (array)
- `_SETTINGS_PERMISSIONS_RE_ALLOW` (alternation regex)
- `_SETTINGS_PERMISSIONS_RE_ASK` (alternation regex)
- `_SETTINGS_PERMISSIONS_LOADED` (0/1)

**Cheapness contract:** "load calls jq once at hook source-time. After that, consumers run pure-bash =~ against the pre-built alternation regex or iterate the prefix array — no fork." Mirrors `detection-registry.sh:22`.

**Note:** does **not** merge `settings.local.json`. Decision recorded in `output/claude-toolkit/plans/2026-04-29__plan__hooks-config-driven.md` (decision 1) — per-machine ad-hoc trust would break portability/reproducibility.

**Sourced by:** `approve-safe-commands.sh` (PermissionRequest), `auto-mode-shared-steps.sh` (PreToolUse Bash, via dispatcher). Two hooks total.

## dispatch-order.json

Static data: declarative dispatcher composition. `version: 1`, `dispatchers: { <dispatcher-name>: [child-hook, ...] }`. Two dispatchers defined: `grouped-bash-guard` (8 children) and `grouped-read-guard` (2 children).

**Consumer:** `scripts/hook-framework/render-dispatcher.sh` — generator that produces the two `dispatcher-grouped-*-guard.sh` files. Not read at hook firing time; only at `make hooks-render`.

## dispatcher-grouped-bash-guard.sh / dispatcher-grouped-read-guard.sh

**Generated** files (header: `=== GENERATED FILE — do not edit ===`). Source: `lib/dispatch-order.json` + per-hook headers in `.claude/hooks/*.sh`. Regenerate via `make hooks-render`.

Each file declares a `CHECK_SPECS` array of `name:file.sh` pairs, sources each child hook's file, and gates registration on the presence of `match_<name>` and `check_<name>` functions. The `CHECKS` array drives the dispatcher loop (in the dispatcher entrypoint hook, `01-standardized/` style — but the dispatchers themselves are reviewed in `02-dispatchers/`).

Listed in this category for completeness only; full review lives in `02-dispatchers/`.

## Per-event hot-path summary

| Event | Hook(s) fired | Lib load shape |
|-------|---------------|----------------|
| PreToolUse / Bash | grouped-bash-guard (+ surface-lessons) | hook-utils + hook-logging once; detection-registry + settings-permissions loaded by children inside the dispatcher's single bash process |
| PreToolUse / Read | grouped-read-guard (+ surface-lessons) | hook-utils + hook-logging; detection-registry once (secrets-guard child) |
| PreToolUse / Write\|Edit | block-config-edits (+ surface-lessons) | hook-utils + hook-logging + detection-registry |
| PreToolUse / Grep | secrets-guard (+ surface-lessons) | hook-utils + hook-logging + detection-registry |
| PreToolUse / EnterPlanMode | git-safety | hook-utils + hook-logging only |
| PermissionRequest / Bash | approve-safe-commands | hook-utils + hook-logging + settings-permissions |
| PostToolUse | log-tool-uses | hook-utils + hook-logging only |
| PermissionDenied | log-permission-denied | hook-utils + hook-logging only |
| UserPromptSubmit | detect-session-start-truncation | hook-utils + hook-logging only |
| SessionStart | session-start | hook-utils + hook-logging + scripts/lib/settings-integrity.sh (singleton) |

## Verified findings feeding downstream axes

Each finding below was checked against the code (function bodies, caller list, micro-bench where relevant). Recorded here so the per-axis reports start from a verified baseline.

### Performance

- **`_strip_inert_content` cost is roughly linear in input length.** Micro-bench (N=100 per case, this machine, no concurrent load):
  - empty input → ~0.15ms (fixed bash overhead per call)
  - 11-byte trivial command (`ls -la /tmp`) → ~0.30ms
  - 46-byte single-quoted command → ~0.69ms
  - 51-byte heredoc, 2-line body → ~0.32ms
  - 8KB heredoc with 200-line body → ~9.3ms
  - The pass-2 char-by-char `for ((i=0; i<len; i++))` walk dominates. This is invoked **only when** a `stripped`-target regex exists for the kind being matched **and** the `raw`-target match missed. For the current registry (22 entries, all `target=raw`), the function is loaded but never called. New `target=stripped` entries would change that.
  - Cost characterization for `performance.md`: per-call cost is bounded by `O(len)` bash-level work, not fork count. For typical Bash commands (under a few hundred bytes) it's sub-millisecond; long heredocs are the failure mode.

- **One sqlite3 fork per hook firing in real-session, conditional.** `_resolve_project_id` is the only fork in the lib pre-init path post-2.81.2. It runs only when something reads `$PROJECT` — which means once per hook firing for any hook that calls a `hook_log_*` writer (effectively all of them when `CLAUDE_TOOLKIT_TRACEABILITY=1`). Skipped entirely for the smoke harness because `sessions.db` is sandboxed to a nonexistent path → basename branch, no fork.

### Robustness

- **`_resolve_project_id` is fail-soft by design and the contract is upheld at every call site.** Verified: `surface-lessons.sh:108` and `session-start.sh:176` both call `_ensure_project` immediately before constructing the SAFE_PROJECT SQL string. Empty `PROJECT` produces `... project_id = ''` which matches no rows; the SQL's `OR scope = 'global'` clause keeps global lessons surfacing. No caller asserts non-empty `PROJECT`. The swallowed sqlite3 error (`2>/dev/null` at `hook-utils.sh:189`) is intentional — surfacing it would crash the hook on a missing/locked DB. The one-line stderr notice ("project not registered in sessions.db.project_paths") is the only signal.
- **Smuggled-data defenses are present in two places.** `detection-registry.sh:71-76` rejects entries containing the SOH (`\x01`) sentinel before they reach the alternation regex; `settings-permissions.sh:120-124, 137-141` rejects prefixes containing unhandled ERE metacharacters. Both fail-loud (stderr) and skip the entry rather than the hook.

### Testability

- **Every decision API exits the process. Confirmed.** `hook_block` / `hook_approve` / `hook_ask` / `hook_inject` all end in `exit 0` in both real and smoke branches (`hook-utils.sh:381-456`). The `_HOOK_RECORDED_DECISION` capture in the smoke branch feeds the EXIT-trap smoketest writer (`_hook_log_smoketest`); it does **not** enable multi-case-per-subprocess testing. Each smoke fixture pays a full `bash hook.sh` fork.
- Implication for `testability.md`: in-process multi-case testing would require restructuring the decision API into a return-value form (with the EXIT-trap shim still in place for production-mode `exit`). That's a real design proposal, not a tweak — recorded as scope for the testability axis.

### Clarity

Three modules in `hook-utils.sh` could plausibly move; whether they should is a `clarity.md` call.

- **`_strip_inert_content` (~70 LoC) lives in `hook-utils.sh` but is consumed only by `detection_registry_match_kind`.** The detection-registry header already documents the cross-file dependency: *"Requires `_strip_inert_content` from hook-utils.sh to be available."* Moving it into `detection-registry.sh` would localize the dependency at the cost of every hook that sources `detection-registry.sh` (4 hooks today) paying its load. Hot path implication: trivial — the function is parsed but not called unless invoked.
- **`hook_extract_quick_reference` (~10 LoC) is used only by `session-start.sh`.** Could inline into the one caller; the function exists for consistency rather than reuse.
- **`_resolve_project_id` + `_ensure_project` (~35 LoC) are only relevant to consumers that read `$PROJECT`.** The seven `hook_log_*` writers in `hook-logging.sh` plus the two lessons hooks. Could split into a `project-id.sh` lib sourced where needed; would un-couple the sqlite3 dependency from the init path.

Each move is a real proposal with a tradeoff. None are obvious wins — recorded for `clarity.md` to evaluate against a proposed boundary set, not as accepted refactors.

## Still-open questions (scope for downstream axes, not resolved here)

- **Performance:** what's the per-event end-to-end cost breakdown under the new harness — including the dispatcher's source-children loop, which loads child hooks at dispatch time rather than at session start? (Falls to `02-dispatchers/performance.md`, with an inventory contribution from this category if dispatcher children pay extra lib load.)
- **Robustness:** `_strip_inert_content` is heuristic. Are there input shapes that produce false negatives the auto-mode dispatcher relies on? (Falls to `01-standardized/robustness.md` — concrete fixtures live in standardized hooks.)
- **Testability:** is restructuring decision APIs into return-value form worth the churn against the framework refactor that just landed? (Falls to `testability.md` as a design proposal with a churn estimate.)
- **Clarity:** does `hook-utils.sh` have a coherent "what this file is" beyond "shared init"? Worth naming the boundaries explicitly. (Falls to `clarity.md`.)
