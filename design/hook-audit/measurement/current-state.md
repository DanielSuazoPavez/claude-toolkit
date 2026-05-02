---
doc: measurement/current-state
status: draft 1 — based on direct read of hook-utils.sh, hook-logging.sh, validate.sh, run-smoke.sh
date: 2026-05-02
---

# Current Measurement State

What V20 actually measures today, in this codebase. Read against `hook-utils.sh`, `hook-logging.sh`, `tests/hooks/run-smoke.sh`, and `.claude/scripts/hook-framework/validate.sh`.

## Pipeline at a glance

V20 budget warnings are produced by `validate.sh::check_V19_V20`. Per hook fixture:

1. The smoke runner (`run-smoke.sh`) invokes the hook under `env -i` with a sandboxed `HOME` and `CLAUDE_*` paths pointing at a temp dir.
2. Inside the hook, `hook_init` runs and sets `HOOK_START_MS = _now_ms()`.
3. The hook does its work and exits.
4. The `EXIT` trap fires `_hook_log_timing`, which under smoke (`CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1`) calls `_hook_log_smoketest`. That computes `duration_ms = _now_ms() - HOOK_START_MS` and writes one row to `smoketest.jsonl`.
5. The validator reads `duration_ms` from the row and compares it against the hook's `PERF-BUDGET-MS` header (split into `scope_miss` / `scope_hit` per outcome).
6. If `duration_ms > applicable_budget`, V20 warns.

V20 is **warning-only**. There is no strict gate (`make hooks-perf-strict` is mentioned in old notes but does not exist in `validate.sh`).

## What `duration_ms` covers

`HOOK_START_MS` is set inside `hook_init`, **after** several pre-init costs:

```
hook_init():
    HOOK_NAME, HOOK_EVENT  (assignments — free)
    HOOK_INPUT=$(cat)              # fork: cat (or builtin; subshell either way)
    INVOCATION_ID=...              # uses $$ + EPOCHSECONDS
    PROJECT=$(_resolve_project_id) # subshell; in real-session, forks sqlite3
    _HOOK_TIMESTAMP=$(date -u ...) # fork: date
    HOOK_START_MS=$(_now_ms)       # subshell; uses EPOCHREALTIME (no fork)
    ... rest of init (one jq fork, traps, branches) ...
```

So `duration_ms` excludes:

- The `cat` subshell that reads stdin
- `_resolve_project_id` — including its `sqlite3` fork in real-session
- The `date` fork for `_HOOK_TIMESTAMP`
- The `_now_ms` subshell itself (small, but nonzero)

It includes:

- The consolidated `jq` fork that parses session_id / tool_use_id / agent_id / source / tool_name from stdin (post-2.81.1 fix; was 4–5 forks before)
- All hook body work
- The `EXIT` trap up to the second `_now_ms()` read

Implication: V20's "hook work" estimate (`above = dur - PERF_FLOOR_MS`) under-counts pre-init cost by at least three forks.

## Floor measurement

`_measure_hook_floor` (validate.sh:537–575) builds a no-op probe hook (`source hook-utils.sh; hook_init "_floor-probe" "PreToolUse"; exit 0`), runs it under the smoke runner three times, and takes the minimum `duration_ms`. That floor is reported in V20 warnings as `bash+jq floor Nms`.

**The floor measures the same `duration_ms` as the budget check** — same timing window, same code paths. So `dur - PERF_FLOOR_MS` is an honest "this hook's body work, in the smoke environment" estimate. It does **not** include pre-init costs (cat / `_resolve_project_id` / date), which the floor also excludes.

Floor on this machine (Linux/WSL2): per the validator comment, ~5ms tight Linux, ~90ms WSL2. We need to measure ours under the new harness — single-shot mins are not robust on WSL2.

## Smoke vs real-session divergences

`run-smoke.sh` lines 67–81 run the hook under `env -i` with these `CLAUDE_*` overrides:

| Var | Smoke value | Real-session effect |
|---|---|---|
| `CLAUDE_ANALYTICS_SESSIONS_DB` | `$tmpdir/nonexistent-sessions.db` | `_resolve_project_id` takes the `[ ! -f sessions_db ]` branch → returns `basename "$PWD"`, **no sqlite3 fork** |
| `CLAUDE_ANALYTICS_HOOKS_DIR` | `$tmpdir/hook-logs` | Real-session writes to `~/claude-analytics/hook-logs/` — same op, but path matters for any cache effects |
| `CLAUDE_ANALYTICS_LESSONS_DB` | `$tmpdir/lessons.db` (empty file) | Real-session points at the global `~/.claude/lessons.db` with real data |
| `CLAUDE_TOOLKIT_LESSONS` | `0` | Real-session typically `1` for projects opted in |
| `CLAUDE_TOOLKIT_TRACEABILITY` | `0` | Real-session typically `1` for projects opted in |
| `HOME` | `$tmpdir/fakehome` | Real-session: `$HOME` |

The two big behavioral differences:

1. **`_resolve_project_id` skips the sqlite3 fork in smoke.** In real-session, it queries `sessions.db.project_paths`. That fork is invisible to V20 (pre-`HOOK_START_MS`) **and** runs in real-session but not in smoke. So smoke's pre-init cost is artificially lower than real-session's.

2. **`CLAUDE_TOOLKIT_LESSONS=0` short-circuits surface-lessons and the lessons-related branches in `session-start`.** Smoke measures the early-exit cost of those hooks, not the actual context-loading cost.

Both differences make smoke numbers an under-estimate of real-session for hooks that touch sessions.db or lessons.db. They make smoke numbers a fair estimate for hooks that don't.

## Precision floor

`_now_ms` reads `EPOCHREALTIME` (bash 5.0+) and truncates to milliseconds. The implementation (lines 68–78) handles the variable-fraction-digit case correctly:

```bash
local _sec="${EPOCHREALTIME%.*}"
local _frac="${EPOCHREALTIME#*.}"
printf -v _frac '%-6s' "$_frac"   # right-pad to 6 chars with spaces
_frac="${_frac// /0}"             # spaces → zeros
echo $(( _sec * 1000 + 10#${_frac:0:3} ))
```

So `duration_ms` is rounded to the millisecond. Anything under ~5ms has high relative variance. Sub-ms differences are invisible. This is a **precision** limitation, not a correctness bug — the design notes' concern about "10× small values when frac is shorter" describes a bug that is **already fixed** in current code (the comment at line 65–67 documents that fix).

## Sampling

V20 runs **one fixture per hook per validate invocation** and warns on a single-shot `duration_ms`. The floor probe runs three times and takes the min, but the per-hook check does not. On WSL2 with Windows-side load, single-shot has variance well above ms — false-positive and false-negative warnings are both possible.

## What V20 does well

- Single source of truth for "hook took N ms" — the JSONL row written by `_hook_log_timing` / `_hook_log_smoketest`.
- Floor measurement on the same machine, in the same harness — so warnings adjust to platform automatically.
- Per-outcome budgets (`scope_miss` / `scope_hit`) — recognizes that no-op early-exit and full-body work have different cost shapes.
- Cheap to run (one extra fixture per hook) — fits in `make validate`.

## What V20 misses

1. **Pre-init costs are invisible.** `cat`, `_resolve_project_id` (incl. sqlite3 fork in real-session), and `date` all run before `HOOK_START_MS`. Real-session startup cost is under-reported by the sum of those forks.
2. **Smoke environment hides real-session work.** `_resolve_project_id` doesn't fork sqlite3. surface-lessons/session-start don't load lessons. Smoke measures early-exit cost for any hook gated on `CLAUDE_TOOLKIT_LESSONS` or `CLAUDE_TOOLKIT_TRACEABILITY`.
3. **Single-shot timing on a noisy host.** No multi-run, no median, no p95. WSL2 wall-clock variance is enough to flip warnings on/off run-to-run.
4. **Millisecond precision is too coarse for sub-ms work.** Fine for hooks that take 50ms; useless for distinguishing 200μs from 800μs work.
5. **Per-phase attribution requires `CLAUDE_TOOLKIT_HOOK_PERF=1` and only two hooks instrumented.** `_hook_perf_probe` exists in `hook-utils.sh` but is only called from `session-start.sh` and `surface-lessons.sh`. For other hooks, V20 reports total-only.

## Open question for harness design

Items 1, 2, and 5 imply the harness should have **two modes**:

- **Smoke parity mode** — same env as `run-smoke.sh`, same code paths skipped, so we can compare like-for-like with V20 history.
- **Real-session parity mode** — does not sandbox sessions.db or feature flags, measures what users actually pay.

Open question: do we re-budget against smoke or real-session numbers? Smoke is reproducible; real-session is what matters. Likely answer: budget against real-session, but keep smoke as the gate (because real-session is per-machine and not deterministic across CI / contributors).
