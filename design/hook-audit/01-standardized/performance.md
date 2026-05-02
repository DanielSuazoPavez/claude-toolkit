---
category: 01-standardized
axis: performance
status: drafted
date: 2026-05-02
n_per_variant: 30
mode: smoke + real (paired)
---

# 01-standardized — performance

End-to-end per-hook wall-clock measurements for all 13 standardized hooks under the same probe shape as `00-shared/performance.md`, in two paired modes (`smoke` / `real`). Goal: isolate **check-body cost** (the hook's own logic) by subtracting the bash startup floor and the lib floor that `00-shared/performance.md` already attributed.

## Methodology

- **Probe:** `design/hook-audit/measurement/probe/run-per-hook-probe.sh`. For each hook, runs `bash <hook>.sh < <fixture>.json` end-to-end with `env -i` isolation matching `tests/hooks/run-smoke.sh`. N=30 per (hook, mode), warmup pass discarded.
- **Two modes per hook:**
  - **smoke** — sandboxed `sessions.db` (path nonexistent), `CLAUDE_TOOLKIT_TRACEABILITY=0`. No sqlite3 fork, no JSONL row written. Same env contract as `tests/hooks/run-smoke.sh`.
  - **real** — points `CLAUDE_ANALYTICS_SESSIONS_DB` at the real `~/.claude/sessions.db` (read-only via `mode=ro` in the hook), `CLAUDE_TOOLKIT_TRACEABILITY=1`. One sqlite3 fork in `_resolve_project_id` (when `_ensure_project` fires) plus one `jq -c` fork in the `_hook_log_timing` EXIT trap.
- **Fixture coverage:** one fixture per hook (V18 minimum). The fixture mix is whatever the existing smoke harness already exercises — half `pass` outcomes, half `block`/`approve`/`ask` outcomes. See "Fixture asymmetry" below.
- **Files:**
  - `design/hook-audit/measurement/probe/per-hook-N30.tsv` — raw samples
  - `design/hook-audit/measurement/probe/per-hook-N30.summary` — aggregate
- **Bash startup floor** for this env-isolated probe shape (measured separately, N=30): p50 ~4.4ms, p95 ~5.9ms. Subtract before attributing to hook work. This is higher than `00-shared`'s 94µs baseline because that baseline is bash startup with the `EPOCHREALTIME` markers *inside* the bash invocation; the per-hook probe brackets *outside* the `env -i bash …` call, so it includes fork+exec + env setup.
- **Variance:** matches earlier probes — p95/p50 ratio under normal multi-session load is ~1.1–1.4×. Two outliers in the raw sample (`approve-safe-commands` smoke had one 1033ms run, `auto-mode-shared-steps` real had one 278ms run) — likely fork-storm spikes from concurrent activity. They sit beyond p95 and don't move the medians.

Numbers below are **p50 in milliseconds** unless noted. Microsecond raw is in the TSV.

## Per-hook totals

| Hook | smoke p50 | smoke p95 | real p50 | real p95 | real − smoke (Δ p50) |
|------|----------:|----------:|---------:|---------:|---------------------:|
| `approve-safe-commands` | 33 | 44 | 47 | 54 | +14 |
| `auto-mode-shared-steps` | 46 | 53 | 63 | 83 | +17 |
| `block-config-edits` | 37 | 41 | 52 | 61 | +15 |
| `block-credential-exfiltration` | 32 | 35 | 56 | 62 | +24 |
| `block-dangerous-commands` | 43 | 49 | 60 | 68 | +17 |
| `detect-session-start-truncation` | 18 | 20 | 34 | 42 | +16 |
| `enforce-make-commands` | 22 | 29 | 39 | 48 | +17 |
| `enforce-uv-run` | 25 | 29 | 42 | 49 | +17 |
| `git-safety` | 38 | 42 | 53 | 60 | +15 |
| `log-permission-denied` | 22 | 25 | 38 | 44 | +16 |
| `log-tool-uses` | 22 | 28 | 39 | 46 | +17 |
| `secrets-guard` | 48 | 53 | 67 | 79 | +19 |
| `suggest-read-json` | 27 | 38 | 44 | 49 | +17 |

**Real − smoke = traceability cost.** The +14–24ms gap across hooks is one sqlite3 fork (`_resolve_project_id`) + one `jq -c` fork (`_hook_log_timing` EXIT trap). The variance across hooks is mostly noise — the work per firing is the same.

`measurement/lazy-resolution-experiment.md` already showed that with lazy resolution applied, the real-vs-smoke gap collapses from ~14–17ms to ~0.2ms for hooks that don't read `$PROJECT`. That patch is not yet on main; numbers above are pre-patch.

## Check-body cost (smoke − bash floor − lib floor)

Subtracting the bash startup floor (~4.4ms p50) and the documented lib floor (`00-shared/performance.md` per-event predictions) from the smoke total isolates `hook_init` + the hook's own check-body work.

| Hook | smoke p50 | bash floor | lib floor | check-body + hook_init | of which check-body (≈ −5ms hook_init) |
|------|----------:|-----------:|----------:|-----------------------:|----------------------------------------:|
| `approve-safe-commands` | 33 | 4.4 | 11.4 | **17** | ~12 |
| `auto-mode-shared-steps` | 46 | 4.4 | 21.0 | **21** | ~16 |
| `block-config-edits` | 37 | 4.4 | 12.3 | **20** | ~15 |
| `block-credential-exfiltration` | 32 | 4.4 | 12.3 | **15** | ~10 |
| `block-dangerous-commands` | 43 | 4.4 | 2.5 | **36** | ~31 |
| `detect-session-start-truncation` | 18 | 4.4 | 2.5 | **11** | ~6 |
| `enforce-make-commands` | 22 | 4.4 | 2.5 | **15** | ~10 |
| `enforce-uv-run` | 25 | 4.4 | 2.5 | **18** | ~13 |
| `git-safety` | 38 | 4.4 | 2.5 | **31** | ~26 |
| `log-permission-denied` | 22 | 4.4 | 2.5 | **15** | ~10 |
| `log-tool-uses` | 22 | 4.4 | 2.5 | **15** | ~10 |
| `secrets-guard` | 48 | 4.4 | 12.3 | **31** | ~26 |
| `suggest-read-json` | 27 | 4.4 | 2.5 | **20** | ~15 |

`hook_init` cost is ~5ms (one consolidated `jq` fork on stdin extraction, plus globals setup). The "of which check-body" column subtracts that to leave the hook's own logic.

**Caveat: fixture asymmetry.** Some fixtures hit the **block** path (full check + decision JSON build) and some hit the **pass** path (early return). Block-path numbers are higher because they pay the hook's full check work. The table mixes both:

- **block fixtures:** `block-config-edits` (blocks-edit-bashrc), `block-credential-exfiltration` (blocks-curl-with-token), `block-dangerous-commands` (blocks-rm-rf-root), `enforce-make-commands` (blocks-bare-pytest), `enforce-uv-run` (blocks-bare-python), `git-safety` (blocks-force-push-main), `secrets-guard` (blocks-dotenv-grep), `suggest-read-json` (blocks-on-large-json)
- **pass fixtures:** `auto-mode-shared-steps` (passes-noop-bash), `detect-session-start-truncation` (passes-untruncated)
- **approve fixture:** `approve-safe-commands` (approves-ls)
- **logger fixtures:** `log-permission-denied` (logs-denied), `log-tool-uses` (logs-bash) — these always pass, no decision branch

The check-body number for a hook with a block fixture is the *full* check; for a hook with a pass fixture it's the *cheap* path. The per-hook performance budget needs both — recorded as a follow-up under "Open" below.

## Hooks flagged for follow-up

The audit task said "flag hooks whose check-body cost exceeds 5ms." Every hook in the category exceeds that — the floor is structural, not implementation. Useful flags are relative to what's plausible to compress:

### Loggers paying ~10ms for ~0 lines of logic

`log-tool-uses` (~10ms check-body) and `log-permission-denied` (~10ms) are the two pure-logger hooks. Their check-body is **`hook_init` + the EXIT trap row build** — there is no logic body. The ~10ms floor is `hook_init`'s consolidated jq fork (~5ms) + the EXIT trap's `jq -c` (~5ms when traceability is on; in smoke with `CLAUDE_TOOLKIT_TRACEABILITY=0` it's a no-op, but the smoke probe still measures bash exit + trap wiring).

These show up as V20 warnings on every `make check`. The implementation is already minimum-viable. Three plausible recommendations for the implement phase:

1. **Raise the budget for hooks that don't have a check body.** Default `scope_miss=5` doesn't fit a hook whose work is entirely `hook_init` + an EXIT trap. A logger-class budget around `scope_miss=15` would track reality without hiding regressions.
2. **Carve the EXIT-trap row build out of `duration_ms`.** V20 measures `duration_ms` as wall time inside the trap. The trap *is* the logger's work; subtracting it would zero the loggers, which is wrong. But measuring `duration_ms` from `HOOK_START_MS` to *before* the trap runs would let the budget reflect "the hook's pre-decision work" — the loggers would correctly read 0ms.
3. **Apply the lazy-resolution patch from `measurement/lazy-resolution-experiment.md`.** Doesn't help the smoke V20 number (already lazy-skipped), but cuts ~4.6ms from real-session for these two, which is the only path that matters for them.

Recommended action for the implement phase: option 3 unconditionally (it's a clear win measured at N=50), then option 1 if the loggers still warn.

### Detect-session-start-truncation: ~6ms of work the first run, ~0ms after

`detect-session-start-truncation` measured ~11ms check-body in the probe — but that's the **first-run** path (no marker file yet, transcript grep runs). After the first prompt in a session, the hook hits the marker-file fast path and returns immediately. The probe measured the slow path because the env-isolated tmpdir gives every run a fresh `~/.claude/cache/`, so the marker is recreated each time.

In real-session use, this hook's amortized cost is ~bash startup + lib floor (~7ms) per UserPromptSubmit, with the first prompt of each session paying the extra ~6ms. Worth recording, not worth changing.

### Big check bodies: block-dangerous-commands, git-safety, secrets-guard

Three hooks measured ~26–31ms check-body cost — well above the median. Causes:

- **`block-dangerous-commands` (~31ms)**: minimal lib stack (~2.5ms floor) but ~31ms of pure-bash regex against the inline danger list. The block fixture (`rm -rf /`) hits the first regex; cost is dominated by stdin parse + decision JSON build, not regex iteration. Worth re-measuring under a pass fixture (added cost = scanning all regexes) before recommending action.
- **`git-safety` (~26ms)**: block fixture (`blocks-force-push-main`) runs the full Bash branch check (regex + branch detect via `git rev-parse`). The `git rev-parse` fork is the expensive line; everything else is pure bash. Recorded — this is a meaningful fork on a hot path. Whether to cache the result across the same dispatcher invocation is a `clarity.md` call.
- **`secrets-guard` (~26ms)**: largest hook in the category (496 LoC), block fixture grep-checks against the registry's sensitive-path entries, plus inline command-shape policy. The check body legitimately *has* work to do here; ~26ms includes the path-pattern matching + decision JSON build. Not obviously compressible without changing the registry shape.

None of these three is wrong. They're recorded so `clarity.md` can ask whether the cost lives in the right place.

### Auto-mode-shared-steps: heaviest lib stack, modest check body

`auto-mode-shared-steps` measured 46ms smoke total (highest in the category). Breakdown:

- bash floor: 4.4ms
- lib floor: 21ms (hook-utils + detection-registry + settings-permissions, both loaders fired)
- hook_init: ~5ms
- check-body: **~16ms**

The 16ms check body is `_strip_inert_content` + the dual match (registry + settings-permissions ask-prefix). Under the dispatcher, the ~21ms lib floor is *deduplicated* with sibling children that share registry/settings-permissions (the dispatcher's source loop pays it once). Standalone-mode cost is the worst case; dispatcher-child cost is much lower. Real per-event cost lives in `02-dispatchers/performance.md`.

## Cross-cutting observations

- **Real-session adds ~14–24ms over smoke for every hook.** The mid-range cluster (~+15–17ms) is `_resolve_project_id` (sqlite3 fork on this real db) + the EXIT trap's `jq -c`. Outliers (`block-credential-exfiltration` +24ms) sit in the noise band — the underlying work is identical.
- **Smoke V20 numbers underreport real-session cost by ~14–17ms.** This is documented in `measurement/findings.md` as a limitation of V20; the per-hook probe confirms the magnitude across all 13 hooks. The lazy-resolution patch (`measurement/lazy-resolution-experiment.md`) is the fix; not yet on main.
- **`hook_init` is ~5ms across every hook.** Structural — one consolidated jq fork. There's no per-hook variation in init cost; the difference between hooks is entirely lib floor + check-body.
- **The two V20 warnings from `01-standardized/inventory.md` (loggers at 8–10ms smoke duration_ms) match the probe's smoke totals (~22ms wall-clock).** V20 measures `duration_ms` from `HOOK_START_MS` (after `hook_init`) to the EXIT trap. The probe measures wall-clock from before bash startup. The ~12ms gap (22ms wall − 10ms duration_ms) is bash startup + lib parse + `hook_init` — invisible to V20. This is the same finding as `measurement/probe-results.md` (~13ms invisible to V20 for the no-op hook), confirmed at the per-hook level for the loggers.

## Verified findings feeding downstream axes

### Robustness

- The probe runs each hook end-to-end without observed runtime errors at N=30. No fatal paths surfaced. Robustness fixtures (malformed stdin, missing tool_input fields) need explicit fixtures — captured under `hook-audit-00-malformed-stdin-fixtures`.

### Testability

- **Per-hook fork cost is ~22–67ms.** A test harness that fans out across all 13 hooks × M cases pays 13×M forks at this cost. The smoke harness already does this (and runs in ~3–5s for the current 13×1 fixture set). Adding multi-case-per-fixture expansion (`hook-audit-00-shape-a-lib-tests`) to the standardized hooks would multiply the fork cost; whether to invest in in-process testing depends on M growing past ~3-4 per hook. `01-standardized/testability.md` to estimate against a target case count.

### Clarity

- The ~26–31ms check-body cluster (block-dangerous-commands, git-safety, secrets-guard) is the natural target for `clarity.md`'s "where does the logic live" question. None is obviously wrong — they have real work to do — but the size disparity (3 hooks at ~26–31ms vs 7 hooks at ~10–15ms) is a code-shape signal.

## Confidence

- **High confidence** in p50 ordering across hooks. The probe is the same shape as `00-shared/performance.md`'s, varies only in the (hook, mode) tuple, and N=30 produced p95/p50 ratios in the 1.1–1.5× band (matching the documented variance).
- **Medium confidence** on check-body attribution. The math (smoke − bash floor − lib floor − hook_init) compounds three independently-measured floors. Each individual floor is well-characterized but the sum has tolerance. Treat the check-body column as ±2–3ms.
- **Lower confidence** on block-vs-pass fixture asymmetry. The single-fixture-per-hook coverage means we don't have a paired "pass case for the same hook" comparison. `block-dangerous-commands`'s ~31ms is from the block fixture; the pass-case cost is unmeasured. Recorded as an open follow-up.

## Open

- **Per-fixture-outcome paired measurement.** Each hook needs a (block, pass) fixture pair so check-body cost can be reported per outcome (the V20 budget already splits on outcome). Recorded as a `hook-audit-01-*` follow-up — depends on `hook-audit-00-shape-a-lib-tests` finishing the test-shape work first.
- **Lazy-resolution patch on main.** `measurement/lazy-resolution-experiment.md` showed the patch closes the real-vs-smoke gap. Re-running this probe after the patch lands would give a final pre-/post-implement comparison. Recorded for the implement phase.
- **`git-safety`'s `git rev-parse` fork on every Bash dispatch.** Worth measuring whether caching the branch in the dispatcher (one fork per dispatch instead of per child) would meaningfully change the dispatcher's total cost. Falls to `02-dispatchers/performance.md`.
- **Per-child parse cost in the dispatcher's source loop.** Same open as `00-shared/performance.md`. Falls to `02-dispatchers/performance.md`.
