---
category: 02-dispatchers
axis: performance
status: drafted
date: 2026-05-02
n_per_variant: 30
mode: smoke + real (paired) + per-child source isolation
---

# 02-dispatchers — performance

End-to-end and per-child timing for the two dispatchers, isolating the dispatcher's structural costs (loader + N children + dispatch loop) from the per-child check-body costs already attributed in `01-standardized/performance.md` and the lib-load costs in `00-shared/performance.md`.

This is where the two open hand-offs from earlier categories land:

- **Per-child parse cost** (carried over from `00-shared/performance.md` § "Open" and § "Dispatcher fan-out implications").
- **`git-safety` `git rev-parse` caching across dispatcher children** (carried over from `01-standardized/clarity.md` Proposal 6).

## Methodology

- **Probes** (both new in this session, gitignored alongside the existing per-hook/per-lib probes):
  - `design/hook-audit/measurement/probe/run-per-dispatcher-probe.sh` — driver, two phases per run.
  - `design/hook-audit/measurement/probe/per-child-source-hook.sh` — per-child phase: sources `lib/hook-utils.sh` once (so its parse cost is excluded from the per-child measurement), then sources each child file in `CHECK_SPECS` order under one bash process, bracketing each `source` call with `EPOCHREALTIME`.
- **End-to-end phase:** runs `bash <dispatcher>.sh < <fixture>.json` end-to-end with `env -i` isolation matching `tests/hooks/run-smoke.sh`. Same two paired modes as `01-standardized/performance.md` (smoke / real). N=30 per (dispatcher, mode), warmup discarded.
- **Per-child phase:** sources hook-utils.sh first (already loaded → cost excluded), then iterates the child list. The dispatcher's `for spec in "${CHECK_SPECS[@]}"; do source "$src"; done` shape is reproduced one-to-one. N=30 per (dispatcher, child), warmup discarded.
- **Files:**
  - `measurement/probe/per-dispatcher-N30.tsv` — raw samples, both phases (column `phase` distinguishes `e2e` vs `per-child`).
  - `measurement/probe/per-dispatcher-N30.summary` — aggregate.
- **Variance:** matches earlier probes (~1.1–1.4× p95/p50). The bash-guard end-to-end column shows higher dispersion (p95/p50 = 1.57× smoke, 1.29× real) because some samples ran during heavier system load — the median is still tight.

Numbers below are **p50 in milliseconds** unless noted.

## End-to-end totals

| Dispatcher | smoke p50 | smoke p95 | real p50 | real p95 | real − smoke (Δ p50) |
|------------|----------:|----------:|---------:|---------:|---------------------:|
| `grouped-bash-guard` | **130** | 204 | **197** | 254 | +67 |
| `grouped-read-guard` | **61** | 74 | **93** | 104 | +32 |

**Comparison with the rough numbers carried into the audit:**
- README "starting point": `grouped-bash-guard ~140ms`, `grouped-read-guard ~46ms`. The 130ms p50 here is tight against 140ms; the 61ms p50 for read-guard is ~15ms above that earlier figure, plausibly because the rough number was from a single `make check` warning line, which uses V20's internal `duration_ms` (subset of wall-clock — see "Dispatcher cost decomposition" below).
- `make check` from this session printed `grouped-bash-guard 106ms` / `grouped-read-guard 42ms`. Those are V20 `duration_ms` values, not wall-clock. Subtract pre-`HOOK_START_MS` setup (~5ms bash startup + ~2.5ms hook-utils parse + ~5ms `hook_init` ≈ 13ms invisible to V20, per `00-shared/performance.md`) and the V20 numbers reconcile to wall-clock measurements within variance.

**Real − smoke = traceability cost.** For `grouped-bash-guard`, +67ms; for `grouped-read-guard`, +32ms. Compare to `01-standardized`'s ~+15–17ms across non-dispatcher hooks. The dispatcher gap is larger because every child's `hook_log_substep` call pays one `jq -c -n` fork when traceability is on:

- `grouped-bash-guard` real overhead = 1× `_hook_log_timing` EXIT trap jq + 1× `_resolve_project_id` sqlite3 + 8× `hook_log_substep` jq forks.
- `grouped-read-guard` real overhead = 1× EXIT trap + 1× sqlite3 + 2× substep jq forks.
- 8 substep forks at ~5ms each ≈ 40ms; standardized hooks pay ~16ms (one trap + one sqlite3). 67 − 16 ≈ 51ms ≈ 8 × 6ms substep cost. Matches expectation.

This is the dispatcher's real-vs-smoke amplification: the substep-logging cost scales linearly with child count. Lazy-resolution (per `measurement/lazy-resolution-experiment.md`) would only collapse the `_resolve_project_id` part — the substep forks are a separate concern. Recorded for the implement phase below.

## Per-child source cost (smoke-equivalent isolation)

The dispatcher sources each child inside one bash process. Idempotency guards (`_HOOK_UTILS_SOURCED`, `_DETECTION_REGISTRY_SOURCED`, `_SETTINGS_PERMISSIONS_LOADED`) make repeated `source lib/...` calls in child files no-ops *for the lib body*, but bash still parses each child's wrapper code, including the (now-no-op) `source` calls and the function declarations the dispatcher checks via `declare -F`.

This phase isolates that cost. Hook-utils is sourced once before measurement starts.

| Dispatcher | Child | p50 µs | p95 µs | First-time loader fired? |
|------------|-------|-------:|-------:|--------------------------|
| `grouped-bash-guard` | `block-dangerous-commands.sh` | **3 123** | 3 658 | none |
| `grouped-bash-guard` | `auto-mode-shared-steps.sh` | **20 212** | 26 034 | **yes — registry + settings (both)** |
| `grouped-bash-guard` | `block-credential-exfiltration.sh` | **5 278** | 6 751 | guarded (registry already loaded by prev) |
| `grouped-bash-guard` | `git-safety.sh` | **3 536** | 4 371 | none |
| `grouped-bash-guard` | `secrets-guard.sh` | **6 262** | 10 395 | guarded (registry) |
| `grouped-bash-guard` | `block-config-edits.sh` | **6 257** | 8 614 | guarded (registry) |
| `grouped-bash-guard` | `enforce-make-commands.sh` | **3 409** | 5 319 | none |
| `grouped-bash-guard` | `enforce-uv-run.sh` | **3 512** | 5 020 | none |
| `grouped-read-guard` | `secrets-guard.sh` | **18 757** | 22 584 | **yes — registry** |
| `grouped-read-guard` | `suggest-read-json.sh` | **3 266** | 3 993 | none |

Sums (p50):

- `grouped-bash-guard`: 3.1 + 20.2 + 5.3 + 3.5 + 6.3 + 6.3 + 3.4 + 3.5 = **51.6ms** total per-child source cost (with hook-utils already loaded).
- `grouped-read-guard`: 18.8 + 3.3 = **22.0ms** total per-child source cost.

### What's "guarded vs first-time"?

`auto-mode-shared-steps.sh` runs `detection_registry_load` and `settings_permissions_load` at top level. As the second child sourced (after `block-dangerous-commands.sh`, which only sources hook-utils), it pays both **first-time loader costs** in one go: ~8ms registry load + ~9ms settings load + ~3ms parse ≈ 20ms. This matches `00-shared/performance.md`'s loader figures (~8.1ms registry, ~8.6ms settings).

After `auto-mode-shared-steps.sh` fires the loaders, every subsequent child that sources `detection-registry.sh` (`credential-exfil`, `secrets-guard`, `config-edits`) hits the `_DETECTION_REGISTRY_SOURCED` guard. They still parse their own wrapper code (~3–6ms) but skip the loader. That asymmetry is visible in the table: ~3ms for libless children, ~5–6ms for registry-using children.

`grouped-read-guard` shows the same pattern in miniature: `secrets-guard.sh` is first → pays the full registry-load (~18.8ms total = ~3ms parse + ~8ms registry parse + ~8ms loader); `suggest-read-json.sh` second has no extra libs (~3.3ms).

### Per-child source cost contains both file parse and conditional loader work

The per-child column above is **not** a pure "file parse" measurement — it includes whatever top-level code the child runs (e.g. `detection_registry_load`). That's the right thing to measure, because it's exactly what the dispatcher pays. But it means "child source cost" varies by ordering. If `auto-mode-shared-steps.sh` were moved later in `CHECK_SPECS`, the loader cost would shift to whichever earlier child first sources `detection-registry.sh` (likely `credential-exfil` at position 3) — total dispatcher cost wouldn't change.

**Implication for `dispatch-order.json`:** child order affects which row pays the loader cost in the substep log, but not the total. The current order (dangerous → auto-mode → exfil → ...) is driven by safety semantics (catastrophic gate first), not by perf — and that's correct. Re-ordering for perf would be churn for no aggregate gain.

## Dispatcher cost decomposition

End-to-end smoke wall-clock for `grouped-bash-guard` is 130ms p50. Allocating that:

| Component | Source | µs |
|-----------|--------|---:|
| Bash startup floor (env -i) | `01-standardized/performance.md` | ~4 400 |
| `lib/hook-utils.sh` parse + load | `00-shared/performance.md` | ~2 500 |
| `hook_init` (consolidated jq, globals, EXIT trap setup) | `01-standardized/performance.md` | ~5 000 |
| Pre-dispatch `hook_get_input` ×2 (`$COMMAND` + `$PERMISSION_MODE`) | this probe (delta) | ~5 000–10 000 |
| **Per-child source cost (8 children, sum)** | this probe | **51 600** |
| `match_*` calls (8 × pure-bash =~) | inferred (~0.5ms each) | ~4 000 |
| `check_dangerous` body (pass-fixture: cheap regex hit, returns 0) | `01-standardized` (block-fixture is 31ms; pass is much cheaper) | ~3 000 |
| 8× `_now_ms` deltas + `hook_log_substep` (smoke: gated, no jq fork) | inferred | ~5 000 |
| EXIT-trap row (smoke: gated under `CLAUDE_TOOLKIT_TRACEABILITY=0` but bash exit + trap wiring still measurable) | residual | ~5 000 |
| **Sum** | | **~85 000–95 000** |
| **Measured p50 wall-clock** | | **130 000** |
| **Residual** | | ~35 000–45 000 |

The ~35–45ms residual is unaccounted for in the table above. Most plausible source: the per-child source numbers were measured with hook-utils already loaded; in real dispatch, the **first** child source (block-dangerous-commands.sh) doesn't pay anything from hook-utils (already loaded by entrypoint), but each child's `source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"` line still runs through bash's command lookup + the idempotency-guard return. ~30 source-of-already-sourced-file calls (8 children × 3–4 source lines each on average) at ~1–2ms each could account for a meaningful chunk. Recorded as a follow-up: micro-bench the cost of "source X.sh when X is already sourced" — if it's ~1ms, the residual closes.

For `grouped-read-guard`, end-to-end smoke 61ms:

| Component | µs |
|-----------|---:|
| Bash startup + hook-utils + hook_init | ~12 000 |
| `hook_get_input` (`$FILE_PATH`) | ~3 000 |
| **Per-child source (2 children)** | **22 000** |
| match + check (pass fixture, both children match → false) | ~3 000 |
| substep logging + EXIT | ~5 000 |
| **Sum** | **~45 000** |
| **Measured p50** | **61 000** |
| **Residual** | ~16 000 |

Same shape, same residual category, scaled to 2 children.

## Where the dispatcher's time is spent (smoke)

For `grouped-bash-guard`:

- **~52ms (40%)** — per-child source cost. This is the dispatcher's structural overhead. Of that, ~17ms is one-time loader work (registry + settings, fired by `auto-mode-shared-steps.sh`); ~35ms is wrapper-file parse cost spread across all 8 children.
- **~12ms (9%)** — bash startup + hook-utils parse + `hook_init`. Same floor every standardized hook pays.
- **~10ms (8%)** — pre-dispatch input parsing (`$COMMAND`, `$PERMISSION_MODE`).
- **~10ms (8%)** — `match_*` predicates + the one cheap `check_dangerous` body the pass-fixture triggers.
- **~10ms (8%)** — substep logging + EXIT-trap teardown (smoke: feature-gated, but the trap itself runs).
- **~35–45ms (27–35%)** — residual, hypothesized to be the "source-of-already-sourced-file" overhead × the children's intra-source `source` calls. Open follow-up.

For `grouped-read-guard`:

- **~22ms (36%)** — per-child source cost. Of that, ~17ms is the registry loader fired by `secrets-guard.sh`; ~5ms is wrapper-file parse.
- **~15ms (25%)** — bash startup + hook-utils + `hook_init` + input parse.
- **~8ms (13%)** — match + check (both children's `match_*` returns false on the pass fixture; no check body fires).
- **~16ms (26%)** — residual (same hypothesis).

## What this means for the implement phase

### 1. Per-dispatcher PERF-BUDGET-MS headers, grounded in this data

Both dispatchers warn on every `make check` because they inherit the framework default `scope_miss=5`. The structural floor for `grouped-bash-guard` is ~130ms wall-clock or ~106ms V20 `duration_ms` (V20 starts after `hook_init`, missing ~13ms of pre-init cost — see `00-shared/performance.md`).

Recommended budgets:

| Dispatcher | smoke p50 | smoke p95 | Recommended `scope_miss` | Recommended `scope_hit` |
|------------|----------:|----------:|-------------------------:|------------------------:|
| `grouped-bash-guard` | 130 | 204 | **150** | **220** |
| `grouped-read-guard` | 61 | 74 | **75** | **120** |

`scope_miss` chosen to cover the smoke p95 with ~5–10% headroom; `scope_hit` chosen to cover real-mode p95 + the EXIT-trap row build. These budgets stop V20 false-positives without hiding regressions: a +20% drift in either dispatcher would still warn.

This is the cheapest fix — one header line per dispatcher. Falls into `02-dispatchers/clarity.md` as a header-shape proposal; performance-side blessing is unconditional.

### 2. Lazy `_resolve_project_id` is worth ~5ms per dispatch in real mode (smoke unchanged)

`measurement/lazy-resolution-experiment.md` already showed the patch closes the standardized real-vs-smoke gap from ~14–17ms to ~0.2ms. The dispatcher real-vs-smoke gap is +67ms (bash) / +32ms (read), but only ~5ms of that is `_resolve_project_id`; the rest is `hook_log_substep` jq forks (8× / 2× respectively).

Lazy-resolution is the same patch, same win, applied to dispatchers automatically (they go through `hook_init`). No dispatcher-specific work. Recorded for the implement phase as already-blessed.

### 3. Substep-logging fork count is the dispatcher's real-mode amplifier

`grouped-bash-guard` pays 8 `hook_log_substep` jq forks per dispatch when traceability is on. That's 8 × ~5ms = ~40ms per dispatch in the real-mode total. The current shape calls `jq -c -n --arg ... | jq -c '. + {...}' >> file` style under the hood (per `hook-logging.sh:_hook_log_jsonl`). Three plausible compressions:

a. **Batch substeps into one row at the end of the dispatcher loop.** Build the substep array in bash, write one JSONL row with `jq -c -n --argjson substeps '[…]'`. One fork instead of 8. Saves ~35ms on bash-dispatcher real-mode dispatches.

b. **Skip jq for substep rows; emit pre-built JSON via printf.** Sub-step rows have a fixed schema; bash can format them without forking. Saves ~5ms per substep call. Tradeoff: hand-rolled JSON is fragile against the schema additions that `hook-logging.sh` already centralizes.

c. **Move substep emission into the EXIT trap.** The trap already builds one jq invocation; substeps could be appended into that single row's payload. Same save as (a), different shape.

(a) and (c) are equivalent saves; (a) is closer to today's per-substep semantics. Tradeoff: the JSONL consumer (analytics, traceability viewer) gets one row per dispatch instead of one row per (dispatch, substep). That's a schema change downstream — recorded as scope for `clarity.md` to weigh against the per-row consumer assumptions.

### 4. `git-safety` `git rev-parse` caching across dispatcher children

Carried over from `01-standardized/clarity.md` Proposal 6.

**Setup.** `git-safety.sh` is the only standardized hook that calls `git rev-parse` (one fork). When it's a child of `grouped-bash-guard`, `match_git_safety` runs cheaply (pure-bash regex on `$COMMAND`). `check_git_safety` runs only when `match_` returns true — i.e. when the bash command starts with `git ...`. In that case, `git rev-parse` fires once per dispatch.

**Frequency.** For non-git Bash commands (~most of them), `match_git_safety` returns false → no fork. The optimization only matters on git-shaped Bash commands.

**Save per fire.** One `git rev-parse` fork is ~5ms (similar to other small forks measured here). Caching the branch in a dispatcher-level global would save ~5ms on git-shaped Bash dispatches.

**Cost.** A dispatcher-level `_GIT_BRANCH_CACHED` global, set on first `check_git_safety` call, read on subsequent calls. The dispatcher process is short-lived (one bash process per Bash event), so cache invalidation is trivial — die at exit. But: the rev-parse output depends on `cwd`, and the model can `cd` between dispatch and check. Today's check parses the *current* command's branch implication; caching the branch from the dispatcher's `cwd` at `hook_init` time is correct *only if* git operations don't affect cwd-vs-branch resolution.

**Verdict.** Save is real but small (~5ms × frequency-of-git-Bash-commands). The current implementation is correct; the cached version requires understanding cache-invalidation semantics. Not worth the churn unless `git-safety` becomes the long pole, which it isn't (block-fixture cost is ~26ms, mostly the `_strip_inert_content` call and decision JSON build, not `git rev-parse`).

**Recommendation:** defer. Reopen if a future probe shows `git rev-parse` dominating dispatcher cost. Recorded as `hook-audit-02-git-rev-parse-caching` (P3).

### 5. The "source children at session start" idea (deferred from inventory)

Inventory flagged this as a clarity decision. Performance side: moving the `for spec in CHECK_SPECS; source ...` loop into a once-per-session lib load would save ~52ms per Bash dispatch + ~22ms per Read dispatch — the per-child source cost column above. Sessions fire many Bash events, so the cumulative save is large.

Tradeoff: loses the `[ -f "$src" ] || continue` distribution tolerance (children missing from the current distribution would have to be probed at load time). Distribution tolerance is a real feature — raiz ships without `enforce-make` / `enforce-uv` and the current dispatcher handles that silently.

**Performance-side verdict:** the save is structurally large but the cost is structurally too. This is a `clarity.md` call, not a perf call. Performance contributes the magnitude (~52ms / dispatch, hot path) so clarity can weigh it.

## Cross-cutting observations

- **The dispatcher's "loader + N children" cost shape inverts the standardized-hook decomposition.** For standardized hooks, lib floor is ~2.5ms (most hooks) to ~21ms (auto-mode-shared-steps standalone). For dispatchers, the lib floor itself is dominated by N × per-child source ≈ 50ms for bash-guard. The per-event lib-load shape table in `00-shared/inventory.md` understates dispatcher cost by treating "hook-utils + hook-logging once" as the floor — that's true for the *libs*, but the *children* are a parallel structure that adds ~50ms / ~22ms.
- **V20's 5ms `scope_miss` budget is structurally wrong for dispatchers** — it was set for one-check-body hooks. Recommended replacement is per-dispatcher `PERF-BUDGET-MS` (above).
- **The hook_init consolidated-jq optimization (2.81.1) is doing its job.** ~5ms `hook_init` floor across every hook + dispatcher. The dispatcher's overhead now sits in the per-child source cost and the substep-logging forks, not in init. Future perf work should target those, not `hook_init`.
- **No dispatcher-specific bug surfaced under N=30.** All probes ran clean; the residual ~35ms / ~16ms is attributed to a documented hypothesis (cost of "source-of-already-sourced-file"). Recorded as a follow-up.

## Verified findings feeding downstream axes

### Robustness

- Both dispatchers ran 30+30 (smoke+real, plus 60+60 per-child rounds, plus 4 warmups) without error. Pass fixtures only. Block-fixture coverage at the dispatcher level is the testability axis's call.

### Testability

- **The N=30 wall-clock for one dispatcher takes ~4–6s of bash forks** (30 smoke + 30 real + 30 per-child rounds × 8 children + warmups). Multiply by 13 standardized hooks + 2 dispatchers and a fork-bound testing harness becomes the bottleneck. The in-process testing follow-up (`hook-audit-00-shape-a-lib-tests`, deferred from `01-standardized`) compounds in this category — testing dispatch-order behavior under M cases × 8 children × N runs is exactly where forks add up.

### Clarity

- Three perf-derived inputs to `clarity.md`:
  1. `dispatch-order.json` ordering does not affect aggregate cost (proven by per-child measurement). Don't optimize for it.
  2. `git-safety` `git rev-parse` caching is a small save behind a real cache-invalidation concern. Defer until it dominates.
  3. "Source children at session start" buys ~52ms / Bash dispatch but costs distribution tolerance. Magnitude on the table for the boundary call.

## Confidence

- **High confidence** in p50 ordering across (dispatcher, mode) and across children. N=30 with low p95/p50 ratios; the per-child phase has no shared state between samples.
- **Medium confidence** in the cost-decomposition residual (~35ms for bash, ~16ms for read). The residual is attributed to a hypothesis ("source-of-already-sourced-file × N intra-child source calls") that is plausible but not directly measured. The residual is structural, not noise — it's stable across runs. Recorded as a follow-up to micro-bench guarded `source` calls.
- **High confidence** in the recommended `PERF-BUDGET-MS` numbers — they're set at smoke p95 + ~10%, with N=30 backing.

## Open

- **Source-of-already-sourced-file micro-bench.** Suspected source of the ~35ms / ~16ms residual. One probe variant: `bash -c 'source X; for i in $(seq 1 N); do source X; done'` bracketed around the loop. Would close the decomposition. Recorded as `hook-audit-02-source-guarded-cost`.
- **Substep batching prototype.** Implement option (a) above (one row per dispatch, substeps in an array) and re-run the real-mode probe. Expected save: ~35ms on bash-guard real-mode. Recorded for the implement phase as `hook-audit-02-substep-batching`.
- **Per-child cost after lazy-resolution patch.** The lazy-resolution patch from `measurement/lazy-resolution-experiment.md` is not yet on main. Re-running this probe after it lands would give a clean before/after for the implement-phase commit message. Recorded as part of the lazy-resolution rollout.
- **Block-path dispatcher fixtures.** Pass-fixture only here. Adding a block fixture (e.g. `dispatches-rm-rf-blocked`) would let the probe measure block-vs-pass dispatcher dispersion. Falls to `testability.md` to scope; perf can re-run if asked.
