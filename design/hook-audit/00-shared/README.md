---
category: 00-shared
status: drafted
date: 2026-05-02
---

# Category 00 — Shared Libs

Libraries under `.claude/hooks/lib/` that other hooks source. Every other category depends on these, so they're reviewed first.

## Members

- `hook-utils.sh` — `hook_init`, `_now_ms`, `_resolve_project_id`, common stdin handling
- `detection-registry.sh` + `detection-registry.json` — pattern detection used by guards
- `settings-permissions.sh` — loads permission entries from settings.json
- `hook-logging.sh` — structured logging helpers
- `dispatch-order.json` — dispatcher ordering config (data, but lives here)

**Excluded from this category:** `dispatcher-grouped-bash-guard.sh` and `dispatcher-grouped-read-guard.sh` live in `lib/` but are dispatcher-specific. Reviewed in `02-dispatchers/`.

## Per-axis reports

- [`inventory.md`](inventory.md) — full member list with size, callers, hot-path status
- [`performance.md`](performance.md)
- [`robustness.md`](robustness.md)
- [`testability.md`](testability.md)
- [`clarity.md`](clarity.md)
