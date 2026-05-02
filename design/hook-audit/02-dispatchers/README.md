---
category: 02-dispatchers
status: not started
---

# Category 02 — Dispatchers

Hooks that fan out to many child match_/check_ pairs. Cost shape: **loader + N children**. Optimization approaches differ from standardized hooks because the per-child cost matters as much as the loader.

## Members

- `grouped-bash-guard.sh` (+ `lib/dispatcher-grouped-bash-guard.sh`)
- `grouped-read-guard.sh` (+ `lib/dispatcher-grouped-read-guard.sh`)

`grouped-bash-guard` is currently the long pole at ~140ms. If it dominates total hook overhead, the rest of the audit can prioritize accordingly.

## Per-axis reports

- [`inventory.md`](inventory.md)
- [`performance.md`](performance.md)
- [`robustness.md`](robustness.md)
- [`testability.md`](testability.md)
- [`clarity.md`](clarity.md)
