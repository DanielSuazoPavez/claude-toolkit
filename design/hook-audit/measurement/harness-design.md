---
doc: measurement/harness-design
status: draft 1 — proposes replacement for V20 timing
decision: replacement, not parallel tool
date: 2026-05-02
---

# Harness Design

Replacement for the timing portion of V20. V20 stays as the budget-warning surface; this harness produces the numbers V20 reports against and is also runnable standalone for the audit.

## Goals

1. **Honest measurement.** Capture pre-init cost (currently invisible), use microsecond precision (currently ms-floored), multi-run with median + p95 + max (currently single-shot for per-hook checks).
2. **Two parity modes.** Smoke parity (matches `run-smoke.sh` env, comparable with V20 history) and real-session parity (no env sandboxing, measures what users pay).
3. **Per-phase attribution.** Hooks already accept `_hook_perf_probe`; the harness should aggregate `HOOK_PERF` lines from stderr into a structured per-phase report.
4. **Drop-in for V20.** The harness output should produce the same `duration_ms` field V20 expects, plus extra fields V20 can ignore.

## Non-goals

- Cross-machine benchmarking. "Real-session" is this machine.
- Profiling of arbitrary commands. `strace -fc` and `bash -x` remain separate tools used during per-category evaluation.
- Replacing V19 (outcome assertions). V19 is correct as-is.

## Proposed shape

A single bash script under `tests/hooks/perf/` (where `perf-session-start.sh` and `perf-surface-lessons.sh` already live):

```
tests/hooks/perf/run-bench.sh <hook> [<fixture>] [--mode smoke|real] [--runs N] [--phases]
```

Output: one JSONL row per fixture-run aggregate, with fields:

```json
{
  "hook": "approve-safe-commands",
  "fixture": "settings-permission",
  "mode": "smoke",
  "runs": 11,
  "warmup": 1,
  "total_us": {"min": 11432, "median": 12104, "p95": 13987, "max": 15211},
  "init_us": {"min": 4102, "median": 4321, "p95": 4980, "max": 5210},
  "body_us": {"min": 7218, "median": 7702, "p95": 9012, "max": 10001},
  "phases": [
    {"name": "hook_init", "median_us": 4321},
    {"name": "settings_load", "median_us": 6892},
    ...
  ]
}
```

## Measurement details

### Microsecond precision

Read `EPOCHREALTIME` directly, parse `sec.frac` into microseconds without truncating to ms:

```bash
_now_us() {
    local _sec="${EPOCHREALTIME%.*}"
    local _frac="${EPOCHREALTIME#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}
```

This is `_now_ms`'s shape, just kept at full precision. The padded-to-6-then-take-6 form is safe regardless of actual fraction-digit count.

### Move `HOOK_START_MS` earlier

To capture pre-init cost, the harness needs the timing window to start *before* `hook_init`'s pre-init forks. Two options:

**Option A: Modify `hook_init`.** Set `HOOK_START_MS = _now_ms()` as the first statement, before `cat`. Existing logging continues to work; pre-init cost becomes part of `duration_ms`. Downside: changes production semantics; "duration_ms" definition shifts.

**Option B: Bracket the entire hook.** Harness records start time *before* invoking the hook, end time *after*, computes `total_us = end - start - shell_startup_floor`. Floor is measured separately as the cost of `bash -c 'exit 0'` under the same env. Pre-init becomes visible without touching `hook_init`.

**Recommendation: Option B for the audit, Option A as a follow-up.** Option B is non-invasive, lets us measure the gap between "what V20 sees" and "what users pay" without touching production code. If the gap is meaningful (likely is, given the sqlite3 fork), then Option A becomes a separate proposal in the implementation phase.

### Multi-run with warmup

```
runs = 11 (default, configurable)
warmup = 1 (always discard first run)
```

For each run, record `total_us` and the per-phase deltas from `HOOK_PERF` stderr lines (when `--phases` is set). Aggregate min, median, p95, max across runs (excluding warmup).

For hooks that mutate state (logs, sessions.db writes), the harness either:

- Uses a fresh `tmpdir` per run (default — matches smoke behavior), or
- Reuses one `tmpdir` across runs (`--reuse-state`) to measure steady-state cost.

### Two modes

**Smoke parity (`--mode smoke`):** identical env to `run-smoke.sh` — `env -i`, sandboxed paths, `CLAUDE_TOOLKIT_LESSONS=0`, `CLAUDE_TOOLKIT_TRACEABILITY=0`. Output comparable with V20.

**Real-session parity (`--mode real`):** preserves user's env, points at `~/.claude/sessions.db` and `~/.claude/lessons.db` and `~/claude-analytics/hook-logs/` (read-only mount or copy-out — to be decided), with `CLAUDE_TOOLKIT_LESSONS=1` and `CLAUDE_TOOLKIT_TRACEABILITY=1`.

The hook log dir is the only sticky concern: real-session writes accumulate. Options:

- Tmp `CLAUDE_ANALYTICS_HOOKS_DIR` per run, but everything else points at real DBs (read paths real, write paths sandboxed).
- Per-run revert of any writes (slow, complex).

**Recommendation:** real-mode redirects only the *write* paths (`CLAUDE_ANALYTICS_HOOKS_DIR`) to a tmp dir; *read* paths stay real. Writes still happen, just not into the user's analytics dir. This isolates the harness from polluting real-session data while keeping read costs honest.

### Floor measurement

Same shape as `_measure_hook_floor` in `validate.sh`, but:

- Uses the harness itself (with its multi-run sampling).
- Reports floor for **both** modes (smoke floor and real-session floor are different — different envs).
- Reports floor in microseconds.
- Reports *total* floor (Option B framing — bash startup + hook_init no-op) and *init* floor separately.

## Integration with V20

V20 currently reads `duration_ms` from `smoketest.jsonl`. After this harness lands:

- The harness can emit a row in V20-compatible shape (`duration_ms` field) for back-compat.
- V20's per-hook check switches to "median of N runs" rather than single-shot — implementation-side tweak in `check_V19_V20`.
- Floor measurement is done once per validate-run (current behavior) but uses harness multi-run.

The harness becomes V20's timer; V20 keeps being the budget-warning surface. They are not parallel tools.

## Open questions

1. **Where does the harness live?** `tests/hooks/perf/` is the natural home (existing `perf-*.sh` files are there). Alternative: `.claude/scripts/hook-bench.sh` if it's also a developer tool. Likely both — script lives in `.claude/scripts/` (or `tests/hooks/perf/lib/`) and `tests/hooks/perf/perf-*.sh` become thin wrappers.

2. **Strict gate (`make hooks-perf-strict`)?** Currently V20 is warning-only. Strict-mode would fail validate when budgets are exceeded. Likely opt-in via env (`CLAUDE_TOOLKIT_HOOKS_PERF_STRICT=1`) so it can be wired into specific CI passes without making `make check` flaky on noisy machines.

3. **Output format.** JSONL for machine consumption. Human-readable summary script on top? Probably just a `--summary` flag on the bench runner that pretty-prints.

4. **State management for stateful hooks.** Default = fresh tmpdir per run. Reasonable; matches smoke. Are there hooks where steady-state cost matters more than fresh-state cost? `surface-lessons` likely (db read becomes cheaper after first query in same shell). Worth measuring both for that hook specifically.

5. **Should `_resolve_project_id`'s sqlite3 fork be removed instead of measured?** It's invoked once per hook, and the result isn't used by most hooks (only the lessons / traceability features care about `PROJECT`). Lazy-resolve on first use would skip it for hooks that don't need it. **Out of scope for measurement, in scope for performance category review.**
