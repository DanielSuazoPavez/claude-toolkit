---
doc: measurement/findings
status: draft 1 — corrected from origin notes after reading hook-utils.sh and run-smoke.sh
date: 2026-05-02
---

# Measurement Findings

Corrections and expansions of the origin notes after reading the actual code. **Some origin claims were inaccurate**; this doc supersedes them.

## 1. Pre-init cost is invisible to `duration_ms` (broader than origin claim)

**Origin claim:** `_resolve_project_id` forks `sqlite3` before `HOOK_START_MS` is set.

**Corrected:** `HOOK_START_MS` is set at line 220 of `hook-utils.sh`, **after** four pre-init costs:

1. `HOOK_INPUT=$(cat)` — subshell + cat fork (or builtin call, same shape)
2. `INVOCATION_ID="$$-..."` — uses `EPOCHSECONDS`, no fork
3. `PROJECT=$(_resolve_project_id)` — subshell; in real-session forks sqlite3, in smoke takes basename branch
4. `_HOOK_TIMESTAMP=$(date -u ...)` — subshell + date fork

Of these, items 1, 3, and 4 are **fork-shaped costs that V20 cannot see**. Item 3 also diverges between smoke and real-session (smoke skips the sqlite3 fork because `sessions.db` is sandboxed to nonexistent path).

**Implication:**
- Real-session startup cost is under-reported by `(cat fork) + (sqlite3 fork) + (date fork)` ≈ 5–15ms typical.
- Smoke startup cost is under-reported by `(cat fork) + (date fork)` ≈ 2–5ms typical.
- The two diverge by `(sqlite3 fork)` ≈ 5–10ms, **on top of** the smoke-vs-real-session feature-flag divergence.

**Fix path:** move `HOOK_START_MS = _now_ms()` to be the *first* statement of `hook_init`, before stdin read. Optionally capture a separate `HOOK_INIT_END_MS` after init to attribute init cost vs body cost.

## 2. `_now_ms` is precision-limited, not buggy (origin claim was outdated)

**Origin claim:** `_now_ms` truncates EPOCHREALTIME to ms; sub-ms paths get high relative variance.

**Corrected:** the variance claim is true. The implicit "and may produce 10× small values" concern from the design comment header is **already fixed** in the current implementation (lines 68–78). The `printf -v _frac '%-6s'` + space-to-zero pad handles variable-digit fractions correctly.

**Implication:** millisecond precision is the floor. To distinguish work under ~5ms from variance, the harness needs microsecond precision (read `EPOCHREALTIME` directly without truncation). This is a precision concern, **not** a correctness fix.

## 3. WSL2 wall-clock variance from Windows-side load (origin claim holds)

Single-shot timing bounces. Multi-run with median + p95 is more stable. Warm-up (discard first run) removes cold-cache effects.

**Implication:** harness must be multi-run by default. Floor probe in `validate.sh` already does this (3 runs, takes min); the per-hook check does not (single-shot). That asymmetry is itself a finding.

## 4. Smoke env hides real-session work via feature flags (new finding)

`run-smoke.sh` sets `CLAUDE_TOOLKIT_LESSONS=0` and `CLAUDE_TOOLKIT_TRACEABILITY=0`. Hooks that gate on these features early-exit in smoke:

- `surface-lessons` returns at the lessons-feature gate without ever loading the db
- `session-start` skips the lessons-surfacing branch and the traceability writes
- All hooks skip the `_hook_log_jsonl` path that produces real-session log volume

**Implication:** for these hooks, smoke `duration_ms` measures "fast path", real-session measures "slow path". Re-budgeting against smoke numbers will produce budgets that real-session blows past silently.

## 5. Floor measurement and per-hook check use asymmetric sampling (new finding)

`_measure_hook_floor` runs 3 times and takes the minimum (validate.sh:564–572). The per-hook V20 check runs once (validate.sh:598–620). On WSL2 the floor is stable, the per-hook number is not — and they're being subtracted to produce "hook work ~Nms".

**Implication:** even before adding multi-run sampling for the hook check, just bringing it in line with the floor (3 runs, take min) would tighten the warning signal.

## 6. V20 only checks one fixture per hook by default (new finding)

`check_V19_V20` walks `$dir/*.json` and warns on every fixture that overruns. This is fine in principle, but in practice most hooks have one or two fixtures. For dispatchers with N child hooks, a single fixture exercises one path — coverage of the cost surface is incidental.

**Implication:** budget calibration should be done against representative fixtures, not just-existing fixtures. This is a fixture-design issue, not a measurement issue, but surfaces during the dispatchers category review.

## Open

To find during the audit:

- Other places where work happens outside the timed region (e.g., trap setup, shell startup before the hook script even reads).
- Whether shared state mutates between runs in a way that drifts numbers (sessions.db growth, cache warming).
- How the harness should handle hooks that mutate state (logging, writes) across multi-run — restore between runs, accept drift, or use no-op fixtures only.
