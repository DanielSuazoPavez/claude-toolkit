---
doc: measurement/findings
status: seeded from origin notes — to be expanded with code references and reproduction steps
---

# Measurement Findings

## 1. `_resolve_project_id` forks `sqlite3` before `HOOK_START_MS` is set

`hook-utils.sh` resolves the project id before timing begins. Real-session hits the sqlite branch (~5–10ms). Smoke sandboxes `sessions.db` to a nonexistent path and falls through to the `basename` branch, skipping the fork.

**Implication:** smoke and real-session measure different startup costs on this machine. V20 numbers from smoke underreport real-session by the sqlite-fork delta for any hook that calls `_resolve_project_id`.

To verify: code refs, reproduction with timed real-session vs smoke runs, magnitude per-hook.

## 2. `_now_ms` truncates `EPOCHREALTIME` to milliseconds

Sub-ms paths get high relative variance. Anything under ~5ms is in the noise floor.

**Implication:** the harness needs microsecond precision to distinguish small fixed costs from variance.

## 3. Wall-clock timing on WSL2 has high variance from Windows-side load

Single-shot measurements bounce. Multi-run with median/p95 is more stable; warming the cache before the first measured run removes one source of variance.

**Implication:** harness must be multi-run, report median + p95 + max, and warm before measuring.

## 4. Open: anything else?

To find during the measurement audit pass — places where work is done outside the timed region, where shared state mutates between runs, where the smoke environment hides real cost.
