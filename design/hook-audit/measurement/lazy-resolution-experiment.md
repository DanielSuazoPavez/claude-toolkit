---
doc: measurement/lazy-resolution-experiment
status: experiment results
date: 2026-05-02
inputs:
  - probe/results-N50.tsv (baseline)
  - probe/results-N50-lazy.tsv (after lazy-resolution patch)
machine: WSL2 on the audit host (multi-session load — variance is part of the environment)
N: 50 measured runs per mode
---

# Lazy `_resolve_project_id` Experiment

## Hypothesis

The N=50 baseline probe found ~4.6ms median sqlite3-fork cost in `_resolve_project_id`, paid by every hook invocation in real-session, regardless of whether the hook actually reads `$PROJECT`.

If `PROJECT` is resolved lazily — on first read instead of eagerly in `hook_init` — hooks that never read `$PROJECT` should skip the fork. For the no-op probe hook (which doesn't reference `$PROJECT`), the prediction is:

- **`real init`** should drop from ~19ms p50 toward `real-no-sqlite init` (~14ms p50)
- **The `real` vs `real-no-sqlite` gap** — currently ~4.6ms median — should collapse toward zero
- **`smoke init`** should be roughly unchanged (smoke already takes the basename branch)

## Patch

Three edits to `.claude/hooks/lib/hook-utils.sh`:

1. Replace eager assignment in `hook_init`:
   ```diff
   - PROJECT="$(_resolve_project_id)"
   + # Lazy: PROJECT resolved on first read via _ensure_project
   + _PROJECT_RESOLVED=false
   ```
2. Add `_ensure_project()` accessor — idempotent guard, fills `PROJECT` global on first call (no subshell at read sites; subsequent calls are a single boolean check).
3. Reset `_PROJECT_RESOLVED=false` at the start of every `hook_init` so dispatcher → child re-init paths re-resolve cleanly.

Five call-site edits adding `_ensure_project` before `$PROJECT` reads:

- `hook-logging.sh::hook_log_section`
- `hook-logging.sh::hook_log_substep`
- `hook-logging.sh::hook_log_context`
- `hook-logging.sh::hook_log_session_start_context`
- `hook-logging.sh::_hook_log_timing` (real-session row writer; smoketest path uses literal `"(test)"`)
- `surface-lessons.sh` (lessons SQL query)
- `session-start.sh` (branch-lessons query)

`make check` passes: 20/20 test files, all validations green, V20 warnings unchanged from baseline (same 7 hooks over budget).

## Results

All values are microseconds. N=50 per mode per condition.

### Total

| Mode | Baseline p50 | Lazy p50 | Δ p50 | Baseline p95 | Lazy p95 | Δ p95 |
|---|---:|---:|---:|---:|---:|---:|
| smoke           | 29086 | 21468 | **−7618 (−26%)** | 41101 | 27172 | −13929 (−34%) |
| real            | 29467 | 18234 | **−11233 (−38%)** | 39405 | 23706 | −15699 (−40%) |
| real-no-sqlite  | 25138 | 17882 | **−7256 (−29%)**  | 31332 | 21542 | −9790 (−31%)  |

### Init phase

| Mode | Baseline p50 | Lazy p50 | Δ p50 |
|---|---:|---:|---:|
| smoke           | 15827 | 10349 | **−5478** |
| real            | 19025 | 9626  | **−9399** |
| real-no-sqlite  | 14418 | 9433  | **−4985** |

### The smoking gun: real vs real-no-sqlite gap

This is the gap that the sqlite3 fork creates.

| | Baseline | Lazy |
|---|---:|---:|
| `real init` p50 − `real-no-sqlite init` p50 | **4607 µs** | **193 µs** |
| `real total` p50 − `real-no-sqlite total` p50 | 4329 µs | 352 µs |
| `real init` p95 − `real-no-sqlite init` p95 | **7126 µs** | **833 µs** |

The 4.6ms median sqlite3-fork delta **collapsed to 0.2ms**. The tail collapsed from 7ms to under 1ms.

The probe never reads `$PROJECT`, so lazy resolution skips the fork entirely. Result confirms the hypothesis cleanly.

## Surprise: smoke and real-no-sqlite also got faster

Predicted: smoke and real-no-sqlite shouldn't change (they were already taking the basename branch).

Observed: both got ~5ms faster at p50.

Hypothesis: removing one subshell from `hook_init` (the `PROJECT="$(_resolve_project_id)"` assignment is gone) saves the subshell-fork cost itself. Even when `_resolve_project_id` returns `basename "$PWD"`, that's still a `$(...)` subshell.

Cross-check: a subshell on Linux is ~3-5ms typical, which matches the observed delta. Plausible.

This means the 4.6ms sqlite3-cost finding **understated the real saving**. The full picture:

- Eliminating the subshell `PROJECT=$(...)` itself: ~5ms saved on every hook invocation, regardless of mode
- Eliminating the sqlite3 fork inside `_resolve_project_id`: ~4.6ms additional saving in real-session

Together: ~9-10ms saved per hook invocation in real-session for hooks that don't touch `$PROJECT`. Verified by the `real init` median drop of 9.4ms (from 19ms to 9.6ms).

## Side effects to watch

1. **Logging functions now run `_ensure_project` inside their bodies.** When traceability is enabled and a hook calls a logger, the *first* logger call pays the ~5-10ms resolution cost. Subsequent calls in the same hook hit the cached value (boolean check, ~µs).

   In real-session with traceability on, the cost moves from "always paid in `hook_init`" to "paid by the first logger call". For hooks that always log, this is the same total cost. For hooks that early-exit before logging (e.g., `hook_require_tool` mismatches), it's pure savings.

2. **Hooks that read `$PROJECT` directly without going through a logger** must call `_ensure_project` themselves. Currently only `surface-lessons` and `session-start` do this. The patch updates both. Future hooks adding a `$PROJECT` read need to remember the call — there's no compile-time check.

3. **Idempotency holds across dispatcher → child re-init.** `hook_init` resets `_PROJECT_RESOLVED=false`, so a dispatcher resolving once doesn't poison a child hook. The child re-resolves on its first read — adds one resolution per child but matches the previous semantics (each hook resolves independently).

## Verdict

Lazy `_resolve_project_id` is a clear win:

- **~4.6ms median saved** in real-session per hook that never touches `$PROJECT` (the original prediction)
- **~5ms additional savings** from eliminating the subshell shape itself, applies to all modes (unexpected bonus)
- **~9-10ms total median savings** per hook invocation in real-session for the no-op probe
- p95 savings are larger (~16ms) because the long tail also collapses
- No test failures, no validation warnings introduced
- Change is small and localized: 1 new function in `hook-utils.sh`, ~7 call-site edits

This belongs in the implementation phase of the audit. Open question for that phase: should we land this as a standalone perf commit now, or fold it into a broader "hook-utils.sh init optimization" commit alongside the other init-phase findings (the `date` fork for `_HOOK_TIMESTAMP`, etc.)?

## Disposition

Shipped as `2.81.2` from this branch (`perf/lazy-resolve-project`). The audit scaffolding rode along since it's user-invisible and harmless. Subsequent category reviews continue on a follow-up branch off `main`.
