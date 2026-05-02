---
doc: measurement/probe-results
status: draft 1
date: 2026-05-02
inputs: probe/results-N50.tsv (raw), probe/results-N50.summary (aggregate)
machine: WSL2 on the audit host (variance is from normal multi-session load — that's the environment we're measuring)
N: 50 measured runs per mode + 1 warmup discarded
---

# Pre-init Cost Probe — Results

## What the probe measures

A no-op probe hook (`probe/noop-hook.sh`) records `EPOCHREALTIME` at three points:

- `T0` — first line of the hook script (after bash starts)
- `T1` — after `source lib/hook-utils.sh`, before `hook_init`
- `T2` — after `hook_init` returns

The runner records wall-clock around `bash hook.sh` itself. This gives four phases:

| Phase | Window | What it includes |
|---|---|---|
| `bash_startup` | wall_start → T0 | Forking `bash`, parsing the script up to first executable line. Plus `env -i` + `env` fork in smoke mode. |
| `source` | T0 → T1 | `source lib/hook-utils.sh` (sources `hook-logging.sh` transitively) — function definitions, idempotency guards, no forks |
| `init` | T1 → T2 | `hook_init`: `cat`, `_resolve_project_id` (incl. sqlite3 fork in real mode), `date`, the consolidated jq, traps |
| `exit` | T2 → wall_end | Trap firing (`_hook_log_smoketest` in smoke, `_hook_log_timing` no-op in real with traceability=0), bash exit |

`total = bash_startup + source + init + exit`.

## Modes

| Mode | sessions.db path | env wipe | Notes |
|---|---|---|---|
| `smoke` | `$tmpdir/nonexistent` | `env -i` + allowlist | Matches `tests/hooks/run-smoke.sh` |
| `real` | `~/.claude/sessions.db` (real, ~3GB) | inherits | Real-session — the shell that hooks actually run in |
| `real-no-sqlite` | `$tmpdir/nonexistent` | inherits | Real env minus the sqlite3 fork — isolates that one cost |

## Results (N=50)

All values are microseconds.

### Total

| Mode | min | p50 | p90 | p95 | max |
|---|---|---|---|---|---|
| smoke           | 21435 | 29086 | 35503 | 41101 | 55809 |
| real            | 23356 | 29467 | 37541 | 39405 | 41521 |
| real-no-sqlite  | 20371 | 25138 | 29097 | 31332 | 31989 |

### Init phase

| Mode | min | p50 | p90 | p95 | max |
|---|---|---|---|---|---|
| smoke           | 10631 | 15827 | 19728 | 23276 | 27328 |
| real            | 15109 | 19025 | 24526 | 25190 | 26570 |
| real-no-sqlite  | 11414 | 14418 | 16432 | 18064 | 18965 |

### bash_startup

| Mode | min | p50 | p90 | p95 | max |
|---|---|---|---|---|---|
| smoke           | 3022 | 4556 | 6546 | 9264 | 11211 |
| real            | 2288 | 2950 | 3922 | 4201 | 4485  |
| real-no-sqlite  | 2263 | 2768 | 4437 | 5006 | 7511  |

`source` and `exit` phases are small and similar across modes (under 5ms total combined). The TSV has them per-run.

## What this tells us

### 1. The sqlite3 fork in `_resolve_project_id` costs ~4–5ms median

Comparing `real init` vs `real-no-sqlite init`:

- p50 delta: 19025 − 14418 = **4607 µs (~4.6ms)**
- p90 delta: 24526 − 16432 = **8094 µs (~8.1ms)**
- p95 delta: 25190 − 18064 = **7126 µs (~7.1ms)**

This matches the design-note guess of "5–10ms" almost exactly. The fork has long-tail variance — when the system is loaded, sqlite3 startup stretches further than the median.

The fork is invoked **on every hook invocation**, regardless of whether the hook actually uses `PROJECT`. Most hooks don't (only lessons / traceability features care). **Lazy-resolving `PROJECT` on first use would save ~4.6ms median per hook invocation in real-session.** That's a high-leverage finding for the standardized-hooks category.

### 2. `bash_startup` is ~2.3–3ms baseline; `env -i` adds ~1.5–2ms

`real-no-sqlite startup` and `real startup` are nearly identical at p50 (~2.8–3ms — same shell environment, just different sessions.db pointers). `smoke startup` is higher (p50 4.6ms) because `env -i` requires forking `env` first, then `bash`.

This is real cost that the harness should account for when comparing smoke and real numbers — they are not directly comparable at the millisecond level.

### 3. `init` dominates `bash_startup`

The 14–19ms median init phase is much larger than the 2.8–4.6ms median startup phase. **`hook_init` is the right place to look for optimization wins, not bash invocation overhead.**

Init still costs ~14ms even in `real-no-sqlite` — meaning even after eliminating the sqlite3 fork, there's ~14ms of `cat` + `date` + jq + bookkeeping. Some of this is unavoidable (jq has a fixed startup cost), some isn't (`date` for `_HOOK_TIMESTAMP` could come from `EPOCHREALTIME`).

### 4. Variance is real and asymmetric

p95/p50 ratios:

- smoke total: 41101 / 29086 = 1.41×
- real total: 39405 / 29467 = 1.34×
- real-no-sqlite total: 31332 / 25138 = 1.25×

p95 is 25–40% above p50. Single-shot measurements like the current per-hook V20 check are not a stable signal. Multi-run with median or p95 is required.

Variance is also worse for the smoke mode (max 55.8ms vs 41.5ms for real). Likely the `env -i + env + bash` chain has more places to stall than the inherited-env chain.

### 5. Pre-init cost (everything before `HOOK_START_MS` in current code) is ~5–8ms in real-session

Adding `bash_startup` (2.95ms p50) + `source` (~4ms typical) + the part of `init` that runs before `HOOK_START_MS`:

In current `hook_init`, before `HOOK_START_MS = _now_ms()`:
- `cat` (subshell)
- `_resolve_project_id` (~4.6ms in real, ~0 in real-no-sqlite)
- `date` (~1ms typical fork)

So real-session pre-`HOOK_START_MS` cost is roughly: `bash_startup (3) + source (4) + cat (1) + sqlite3 (4.6) + date (1)` ≈ **~13ms median, invisible to V20**.

V20 reports `duration_ms` from `HOOK_START_MS` onward. Real-session hooks pay ~13ms more than V20 reports. **This validates the "move the timing window earlier" recommendation** — though the audit may reach the same outcome by *eliminating* the sqlite3 fork entirely rather than just timing it.

## Implications for the harness

- **Bracket-the-hook timing (Option B from `harness-design.md`) is the right call.** It captures the ~13ms gap that V20 misses, without changing `hook_init` semantics. Option A (modify `HOOK_START_MS` placement) becomes a separate optimization once we've decided what the V20 contract should be.
- **The harness should default to N≥30 with median + p95.** N=50 produced stable percentiles. N=10 would be borderline given the variance.
- **Smoke and real numbers are not directly comparable.** The harness should report both modes side-by-side, not "smoke = approximation of real".
- **`env -i` cost should be subtracted from smoke or noted explicitly.** ~1.5–2ms baseline divergence from the env wipe alone, before any `_resolve_project_id`-style differences.

## Implications for the standardized-hooks category review

- **`_resolve_project_id` lazy-resolution is the highest-impact single change** identified so far: ~4.6ms median saved per hook invocation in real-session, on hooks that don't use `PROJECT` (which is most of them).
- **`date -u` for `_HOOK_TIMESTAMP` is a candidate.** ~1ms median fork. `EPOCHREALTIME` is already available; deriving an ISO timestamp from it without `date` would save the fork.
- **`cat` for stdin is harder to remove.** `read` doesn't handle multi-line JSON well; mapfile + reconstruction is awkward. May not be worth the readability cost.

## Raw data

- `probe/results-N50.tsv` — 150 rows (50 per mode), TSV header
- `probe/results-N50.summary` — aggregate report (this doc's tables come from there)
- `probe/run-probe.sh` — runner; reproduce with `bash design/hook-audit/measurement/probe/run-probe.sh 50`
- `probe/noop-hook.sh` — the probe hook itself
