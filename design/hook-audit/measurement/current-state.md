---
doc: measurement/current-state
status: not started
---

# Current Measurement State

What V20 measures today, what it misses, where smoke and real-session diverge.

## To fill in

- V20 timing entry/exit points (where `HOOK_START_MS` is set, where `duration_ms` is computed)
- What runs **before** `HOOK_START_MS` and is therefore invisible
- What runs **after** the timing window closes
- Smoke vs real-session code-path divergences (known: `_resolve_project_id` sqlite branch)
- Precision floor (`_now_ms` truncates EPOCHREALTIME to ms)
- Sampling — single-shot vs multi-run; current variance characteristics
