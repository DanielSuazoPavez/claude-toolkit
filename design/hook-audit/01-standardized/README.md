---
category: 01-standardized
status: not started
---

# Category 01 — Standardized Hooks

Hooks with uniform shape: `hook_init` → check inputs → guard/log/approve → exit. Largest population, most consistent code structure. Where the `$(helper ...)` and `| jq` anti-patterns most likely repeat.

## Members

- `approve-safe-commands.sh`
- `auto-mode-shared-steps.sh`
- `block-config-edits.sh`
- `block-credential-exfiltration.sh`
- `block-dangerous-commands.sh`
- `detect-session-start-truncation.sh`
- `enforce-make-commands.sh`
- `enforce-uv-run.sh`
- `git-safety.sh`
- `log-permission-denied.sh`
- `log-tool-uses.sh`
- `secrets-guard.sh`
- `suggest-read-json.sh`

Membership confirmed in `inventory.md` (some may move to other categories on inspection).

## Per-axis reports

- [`inventory.md`](inventory.md)
- [`performance.md`](performance.md)
- [`robustness.md`](robustness.md)
- [`testability.md`](testability.md)
- [`clarity.md`](clarity.md)
