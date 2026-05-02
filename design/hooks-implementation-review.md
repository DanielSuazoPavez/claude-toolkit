---
date: 2026-05-02
scope: hooks
task: hooks-implementation-review (P0)
inputs:
  - V20 perf-warning history on feat/hook-smoke-tests
  - 2.81.1 perf commits (e226852, 5fd879b, 90b0e20)
  - .claude/hooks/lib/{detection-registry,hook-utils,settings-permissions,hook-logging}.sh
status: pre-implementation notes — to be folded into a design doc by the task itself
---

# Hooks Implementation Review — Working Notes

Pattern surfaced repeatedly during V20 perf work (2026-05-01/02): hook libraries pay heavy fork costs from idioms that don't pay rent. The framework refactor (item 6 of `hook-framework-refactor`) shipped V20 perf budgets which made these costs visible for the first time. This document captures findings from that exposure so the eventual design doc can reference them.

## Concrete findings already fixed (exemplars of the pattern)

1. **`detection-registry.sh`** — 2 `base64 -d` forks per entry × 22 entries = ~130ms of pure round-trip cost. Fix: SOH (`\x01`) sentinel through one `jq` call. (`e226852`)
2. **`hook-utils.sh` `hook_init`** — 4-5 separate `jq` forks for stdin field extraction. Fix: one `jq` call, newline-separated values. Floor dropped 17ms→6ms. (`5fd879b`)
3. **`settings-permissions.sh`** — 90 subshells per load (45 entries × 2 helper functions called via `$(...)`). Fix: inline the 5-line helpers. ~190ms back per `approve-safe-commands` invocation. (`90b0e20`)

## Remaining V20 overruns

Folded in 2026-05-02 from the now-retired `hooks-perf-pass-after-v20` P2 task. Numbers are post-2.81.1 smoke-run measurements:

- **`grouped-bash-guard`** ~140ms hook work (down from 376ms after the three fixes; loads many child match_/check_ pairs)
- **`grouped-read-guard`** ~46ms (down from 168ms)
- **`session-start`** ~39ms (subprocess spawning for git context)
- **`auto-mode-shared-steps`** ~14ms
- **`surface-lessons`** ~13ms
- **`log-tool-uses`** ~9ms / **`log-permission-denied`** ~10ms (just over the 5ms scope_miss budget — likely 1-2 jq calls in the body)

For each: trim work, raise `PERF-BUDGET-MS` in the header to a justified number, OR add to a future `make hooks-perf-strict` gate.

## Open measurement issues (audit before re-budgeting)

- **`_resolve_project_id` forks `sqlite3` BEFORE `HOOK_START_MS` is set.** Prod sees ~5-10ms of startup that V20 cannot see. Smoke tests sandbox `sessions.db` to a nonexistent path → take the `basename` branch → don't fork `sqlite3`. **Smoke and prod measure different startup costs.**
- **`_now_ms` truncates EPOCHREALTIME to ms.** Sub-ms paths get high relative variance.
- **Wall-clock timing on WSL2 has high variance** from Windows-side load. Multi-run minimum or median would be more stable than single-shot.

## Other open issues

- Likely more `${...//.../...}` or `$(...)` anti-patterns to find in remaining hot paths.
- `approve-safe-commands` now under budget but the loader is shared with `auto-mode-shared-steps` — verify both got the speedup with measurement.
- **Helper-function-via-command-substitution is the bigger pattern.** Audit all `.claude/hooks/lib/*.sh` for the same idiom in hot paths.

## Process for this task

1. **Benchmark.** Add a perf harness that runs each hook N times under a warm cache, reports median + p95 + max from EPOCHREALTIME with microsecond precision. Skip wall-clock noise by warming first.
2. **Evaluate.** Per-hook breakdown: where are forks spent (`strace -fc`), where are subshells spent (instrumented timing of each phase), what does V20's `duration_ms` include vs miss.
3. **Draft.** One design doc covering: measurement-correctness fixes (move `HOOK_START_MS` earlier, microsecond precision, multi-run sampling); audit findings (which libs/hooks have the `$(helper ...)` pattern, the `| jq` pattern, redundant `date`/`dirname` forks); proposed budget recalibration after fixes.
4. **Implement.** Stack of focused commits, each with before/after numbers from the harness.

## Scope vs `hook-framework-refactor`

Distinct concern. The framework task built the **framework** (headers, validators, codegen, smoke harness). This task uses the framework to find and fix **implementation debt** the framework now makes visible.
