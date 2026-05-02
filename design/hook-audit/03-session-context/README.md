---
category: 03-session-context
status: not started
---

# Category 03 — Session-Context Hooks

Heavy context-loading hooks. Run at session start or on user prompt submit, do git/db reads, build context strings. Different perf profile and different correctness concerns from the rest — failures here degrade context, not block actions.

## Members

- `session-start.sh`
- `surface-lessons.sh`

## Per-axis reports

- [`inventory.md`](inventory.md)
- [`performance.md`](performance.md)
- [`robustness.md`](robustness.md)
- [`testability.md`](testability.md)
- [`clarity.md`](clarity.md)
