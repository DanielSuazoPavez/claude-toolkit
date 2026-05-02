---
doc: measurement/harness-design
status: not started
decision: replacement for V20 timing, not a parallel tool
---

# Harness Design

Replacement for V20's current timing. V20 stays as the budget-warning surface; the harness is what produces the numbers V20 reports.

## Requirements

- **Microsecond precision** — read `EPOCHREALTIME` directly, no truncation to ms
- **Multi-run** — N runs per hook, configurable; report median, p95, max
- **Warm-up** — first run discarded to remove cold-cache effects
- **Move start point** — `HOOK_START_MS` (or replacement) set at hook entry, before `_resolve_project_id` and any other pre-init forks
- **Same code paths as real-session** — sandboxing in smoke must not hide real costs (or the divergence must be documented and offset)
- **Per-phase breakdown** — optional instrumented mode that times each phase (init, dispatch, body) so we can attribute cost

## To decide

- Where the harness lives (`tests/hooks/perf/`? `.claude/scripts/`?)
- Output format (JSON for machine consumption, text for humans, both?)
- Integration with V20: does V20 read the harness output, or does the harness *become* V20's timer?
- How to handle hooks that mutate state (logging, sessions.db writes) across multi-run — restore between runs, or accept drift?
- Strict gate (`make hooks-perf-strict`?) vs warning-only

## Non-goals

- Not a benchmark suite for cross-machine comparison. This is a single-machine tool — "real-session" is this machine.
- Not a profiler. `strace -fc` and per-phase instrumentation are separate tools used during the evaluate step of each category.
