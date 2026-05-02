---
category: 00-shared
axis: performance
status: drafted
date: 2026-05-02
n_per_variant: 50
mode: real-no-sqlite
---

# 00-shared — performance

Per-lib source and load costs measured under the same harness style as `measurement/lazy-resolution-experiment.md`. Goal: produce defensible per-lib numbers that hot-path category reports can attribute and act on, instead of attributing everything to "hook init."

## Methodology

- **Probe:** `design/hook-audit/measurement/probe/per-lib-source-hook.sh` — sources one lib variant between two `EPOCHREALTIME` markers. Runner: `run-per-lib-probe.sh`. N=50 per variant, plus a discarded warmup. Same TSV/aggregate shape as the original probe.
- **Mode:** real-no-sqlite (sandboxed `sessions.db` to `$tmp/nonexistent`). Removes the sqlite3-fork variance so per-lib deltas surface cleanly. The sqlite3 fork is characterized separately — see `measurement/probe-results.md` and `measurement/lazy-resolution-experiment.md`.
- **Variants:**
  - `baseline` — no source, just bash startup + the two `printf` markers
  - `hook-utils` — `source lib/hook-utils.sh` (transitively sources `hook-logging.sh`)
  - `detection-registry` — `source hook-utils.sh; source detection-registry.sh` (parse only, loader **not** called)
  - `detection-registry-loaded` — `... ; detection_registry_load` (parse + the one jq fork + 22-entry array build)
  - `settings-permissions` — parse only
  - `settings-permissions-loaded` — parse + the one jq fork + 80-prefix loop (this repo's settings: 30 allow-Bash + 50 ask-Bash)
- **Files:**
  - `measurement/probe/per-lib-N50.tsv` — raw samples
  - `measurement/probe/per-lib-N50.summary` — aggregate (this file's tables are derived from it)
- **Variance characterization:** matches the previous probe — p95/p50 ratio is ~1.1–1.3× under normal multi-session load on this machine. Use medians for between-variant comparison, not extremes.

Numbers below are p50 unless noted.

## Source phase (parse-only) — p50 µs

| Variant                          | p50    | p95    | Marginal vs prior row |
|----------------------------------|-------:|-------:|-----------------------|
| baseline                         |    94  |   182  | (printf overhead floor) |
| hook-utils                       |  2526  |  3100  | **+2432** parse hook-utils.sh + hook-logging.sh |
| detection-registry               |  4247  |  5371  | **+1721** parse detection-registry.sh |
| settings-permissions             |  2808  |  3486  | **+282**  parse settings-permissions.sh |

## Load-and-build phase — p50 µs

These variants additionally invoke the lib's one-shot loader, so the delta vs the source-only variant is the loader cost (one jq fork + the bash-side array build).

| Variant                          | p50     | p95     | Marginal vs source-only |
|----------------------------------|--------:|--------:|-------------------------|
| detection-registry-loaded        | 12318   | 13966   | **+8071** `detection_registry_load` (1 jq fork + 22 entries → 6 alternation regexes) |
| settings-permissions-loaded      | 11365   | 12882   | **+8557** `settings_permissions_load` (1 jq fork + 80 Bash() prefixes → 2 regexes) |

## What this tells us

### Unconditional hot-path tax

**~2.4ms per hook firing for hook-utils + hook-logging parse** (real-no-sqlite mode). Every hook pays this — there are no hooks in `.claude/hooks/` that don't source `hook-utils.sh` (per `validate-hook-utils.sh:✓ All 17 hooks source lib/hook-utils.sh`).

This is parse + function definition only. Globals are reset, the EXIT trap is not yet installed (that's `hook_init`'s job). Half of this is `hook-utils.sh` (457 LoC) and half is `hook-logging.sh` (280 LoC) — direct measurement is open if the split-vs-merge tradeoff matters, but the p50 alone says the boundary chosen during the framework refactor doesn't cost the hot path more than ~1ms either way.

**Implication:** there is no zero-cost path. A V20 budget below ~3ms for any hook is impossible without a different lib shape (e.g. compiled-once, or moving init logic into the dispatcher and skipping it in children).

### Conditional jq-fork tax

`detection_registry_load` and `settings_permissions_load` each cost **~8.1–8.6ms** above their source-only variant. This is the one jq fork plus the bash-side array build (parallel arrays + alternation regex assembly). On this machine, jq cold-start is ~5–6ms (per the original probe-results.md), and the bash-side work accounts for the rest.

These loaders are idempotent (`_DETECTION_REGISTRY_SOURCED` / `_SETTINGS_PERMISSIONS_LOADED` guards), so the cost is paid **once per process**. In dispatcher flows the cost is paid once even when multiple children source the same lib — which is exactly what the post-2.81.1 fix architecture relies on.

### Effective per-event lib cost

Combining inventory's per-event lib-load shape with these numbers:

| Event / hook                        | Libs sourced | Loaders fired | Predicted lib floor (p50) |
|-------------------------------------|--------------|---------------|---------------------------|
| log-tool-uses (PostToolUse)         | hook-utils   | none          | ~2.5ms                    |
| log-permission-denied               | hook-utils   | none          | ~2.5ms                    |
| detect-session-start-truncation     | hook-utils   | none          | ~2.5ms                    |
| git-safety (PreToolUse/EnterPlanMode) | hook-utils | none          | ~2.5ms                    |
| surface-lessons                     | hook-utils   | none          | ~2.5ms                    |
| approve-safe-commands (PermissionRequest) | hook-utils + settings-permissions | settings_permissions_load | ~11.4ms |
| secrets-guard (Grep / dispatcher child) | hook-utils + detection-registry | detection_registry_load | ~12.3ms |
| block-credential-exfiltration (dispatcher child) | hook-utils + detection-registry | detection_registry_load (deduped) | ~12.3ms first child, ~4.2ms reused |
| auto-mode-shared-steps (dispatcher child) | hook-utils + detection-registry + settings-permissions | both loads (deduped within process) | ~21ms first invocation in process |
| block-config-edits                  | hook-utils + detection-registry | detection_registry_load | ~12.3ms |
| grouped-bash-guard (dispatcher entrypoint) | hook-utils + N children | aggregated below | (see "dispatcher fan-out") |
| grouped-read-guard                  | hook-utils + 2 children | aggregated below | (see below) |

These are **lib-floor** predictions — they exclude `hook_init`'s 4–5ms (consolidated jq + sqlite3) and any check-body work. Smoke V20 numbers for non-dispatcher hooks track these floors closely once you add `hook_init`'s cost.

### Dispatcher fan-out implications (preview for `02-dispatchers/`)

The dispatchers source children at dispatch time, not at session start. With the idempotency guards, the lib-load cost is still paid once per dispatcher invocation — but **each child file is parsed once** as the dispatcher's `for spec in "${CHECK_SPECS[@]}"; do source "$src"; done` loop walks them.

Predicted aggregate for `grouped-bash-guard` (8 children: dangerous, auto-mode-shared-steps, credential-exfil, git-safety, secrets-guard, config-edits, make, uv):

- 1× hook-utils parse: ~2.4ms (already attributed; child sources are no-ops via `_HOOK_UTILS_SOURCED` guard)
- 1× detection-registry parse + load: ~12.3ms (4 children source it; subsequent sources are no-ops)
- 1× settings-permissions parse + load: ~11.4ms (auto-mode-shared-steps only)
- 8× child-file parse cost: not yet measured per-file; recorded as scope for `02-dispatchers/performance.md`

Lower bound from libs alone: ~26ms before any check-body work. Smoke harness measured 100–120ms for `dispatches-clean-pwd` — leaves ~75–95ms for child parse + check-body + final logging row. Per-child measurement is for the dispatcher category report.

## Candidates for action

These are observations from the data; whether to act sits with `clarity.md` and the eventual implementation pass.

1. **`detection_registry_load` is dead weight on the read path under current registry contents.** All 22 entries have `target=raw`, so `_strip_inert_content` is loaded but never called. The ~8ms loader cost still fires on Read/Bash/Write/Edit because the alternation regexes drive the match. This is correct cost — flagging only because if a future "lazy-load on first match" pattern were applied, the savings would be predictable: ~8ms recovered on hook firings that don't actually contain credentials (which is most of them).
   - Tradeoff vs current shape: the load happens once per dispatcher invocation today; lazy-load would push it into the hit path of the first match. For the common no-secret case, savings are ~8ms; for sessions with frequent credential-style strings, the cost moves but doesn't disappear.
2. **`settings_permissions_load` cost is dominated by 80 prefixes.** The ~8.6ms is roughly proportional to entry count (this is hypothesis, not yet measured — recorded as a follow-up if `01-standardized/` flags `approve-safe-commands` budget). The current shape (1 jq fork + bash loop) is already the post-2.81.1 fix; further reduction would require giving up the per-prefix ERE-metachar reject (small but loses fail-loud behavior) or precompiling at sync time (introduces a build step).
3. **The hook-utils + hook-logging split costs ~2.4ms either way.** Whether to merge them back is a `clarity.md` call — performance doesn't push for it.
4. **No per-event lib floor below ~2.5ms exists for any hook.** V20 budgets at 5ms have ~2.5ms left for `hook_init` + any check work. The 8 V20 warnings on main today (per the latest `make check`) are all logging hooks paying `hook_init`'s ~4–5ms — the budgets, not the implementations, are the question. Recorded as scope for the implement phase.

## Confidence

- **High confidence** in p50 deltas (N=50, low p95/p50 ratio under normal load). Marginal-cost attribution (parse-only vs loaded) is sound because the variants differ by exactly one source line.
- **Lower confidence** on the dispatcher fan-out predictions — those rely on the idempotency-guard assumption (every child's source-call is a no-op after the first). Verified at code level (every relevant lib has a `_<NAME>_SOURCED=1` guard, see inventory) but not yet measured end-to-end. That's `02-dispatchers/performance.md`'s job.
- **Not measured here:** per-call cost of the `_strip_inert_content` walk, which inventory already characterized via micro-bench (~0.7ms typical, ~9ms for 8KB heredoc). The function is loaded as part of `hook-utils.sh` parse cost; it's not a separate phase.

## Open

- Actual per-child parse cost in dispatcher flows. Probe extension: list each child file as its own variant. Deferred to `02-dispatchers/performance.md`.
- Whether reducing `hook-utils.sh` parse cost is worth churn (e.g. moving `_resolve_project_id` + `_strip_inert_content` to dependent libs to skip them on hooks that never need them). Each move would shave ~50–100µs from the hot-path floor; aggregate savings depend on hook population, not on a single hook's budget. `clarity.md` evaluates with this data point in hand.
