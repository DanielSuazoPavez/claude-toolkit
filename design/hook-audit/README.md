---
date: 2026-05-02
scope: hooks
task: hooks-implementation-review (P0)
status: scaffolding — content fills in per-category as the audit proceeds
supersedes: design/hooks-implementation-review.md (folded into "Origin" below)
---

# Hook Audit

Detailed review of every hook and shared lib in `.claude/hooks/`, organized by **category first**, with four review **axes** inside each category.

## Glossary

- **real-session** — what runs on this machine in real Claude Code sessions. The only "production" that exists. Used in place of "prod" to avoid implying a remote environment.
- **smoke** — what runs under `tests/hooks/smoke/`. Sandboxes some state (notably `sessions.db` to a nonexistent path), so some code paths diverge from real-session.
- **V20** — the perf-budget header system shipped with the hook framework refactor. Each hook declares `PERF-BUDGET-MS`; the smoke runner warns on overruns.

## Review Axes

Every category is reviewed along the same four axes:

1. **Performance** — measured under the replacement harness (see `measurement/`). Median + p95 + max, microsecond precision, multi-run.
2. **Robustness** — failure modes, error paths, edge inputs, what happens when expected state is missing.
3. **Testability** — can multiple test cases share one subprocess invocation, or does each case force a fresh fork? Affects smoke-harness throughput and the kind of tests we can write.
4. **Clarity** — code shape, naming, where the logic lives vs where it's invoked.

## Categories

| # | Category | Members | Status |
|---|----------|---------|--------|
| 00 | [Shared libs](00-shared/README.md) | `hook-utils.sh`, `detection-registry.sh`, `settings-permissions.sh`, `hook-logging.sh`, `detection-registry.json`, `dispatch-order.json` | drafted (all 4 axes + inventory) |
| 01 | [Standardized hooks](01-standardized/README.md) | `approve-safe-commands`, `auto-mode-shared-steps`, `block-config-edits`, `block-credential-exfiltration`, `block-dangerous-commands`, `detect-session-start-truncation`, `enforce-make-commands`, `enforce-uv-run`, `git-safety`, `log-permission-denied`, `log-tool-uses`, `secrets-guard`, `suggest-read-json` | drafted (all 4 axes + inventory) |
| 02 | [Dispatchers](02-dispatchers/README.md) | `grouped-bash-guard`, `grouped-read-guard` (+ `lib/dispatcher-grouped-*-guard.sh`) | drafted (all 4 axes + inventory) |
| 03 | [Session-context hooks](03-session-context/README.md) | `session-start`, `surface-lessons` | drafted (6 axes — added `context-pollution.md`; asymmetric depth) |

## Cross-cutting: Measurement

Methodology and harness work that has to land before any category review can produce trustable numbers.

- [`measurement/current-state.md`](measurement/current-state.md) **[draft]** — what V20 measures today (pipeline, what `duration_ms` covers, smoke-vs-real divergences, what V20 does well / misses)
- [`measurement/findings.md`](measurement/findings.md) **[draft]** — corrected from origin notes after reading the code: pre-init cost is broader than just `_resolve_project_id`; `_now_ms` is precision-limited not buggy; smoke env hides feature-gated work; floor and per-hook check sample asymmetrically
- [`measurement/harness-design.md`](measurement/harness-design.md) **[draft]** — replacement harness spec: microsecond precision, multi-run median/p95, two parity modes (smoke / real-session), bracket-the-hook timing (Option B) over modifying `hook_init`
- [`measurement/probe-results.md`](measurement/probe-results.md) **[N=50 measured]** — pre-init cost probe across smoke / real / real-no-sqlite modes. Confirms ~4.6ms median sqlite3-fork cost in real-session, ~13ms total pre-`HOOK_START_MS` cost invisible to V20, and ~1.4× p95/p50 variance under normal load.
- [`measurement/lazy-resolution-experiment.md`](measurement/lazy-resolution-experiment.md) **[N=50 measured]** — applied lazy `_resolve_project_id` to `hook_init`, re-ran the probe. real init p50 dropped from 19ms to 9.6ms; the real-vs-real-no-sqlite gap collapsed from 4.6ms to 0.2ms. Bonus: removing the subshell shape itself saved ~5ms across all modes.
- `measurement/probe/run-per-dispatcher-probe.sh` + `per-child-source-hook.sh` **[N=30 measured]** — paired smoke/real end-to-end + per-child source-cost isolation for `grouped-bash-guard` and `grouped-read-guard`. Closes the per-child parse-cost open from `00-shared/performance.md`. Results: `per-dispatcher-N30.tsv` / `per-dispatcher-N30.summary`.

## Origin

This audit grew out of perf work during V20 rollout (2026-05-01/02). Three exemplar fixes shipped in 2.81.1 made a broader pattern visible: hook libraries pay heavy fork costs from idioms that don't pay rent, and current measurement underreports real-session cost.

**Exemplar fixes already shipped (2.81.1):**

1. `detection-registry.sh` — 2 `base64 -d` forks per entry × 22 entries = ~130ms. Fix: SOH (`\x01`) sentinel through one `jq` call. (`e226852`)
2. `hook-utils.sh` `hook_init` — 4-5 separate `jq` forks for stdin field extraction. Fix: one `jq` call, newline-separated values. Floor: 17ms → 6ms. (`5fd879b`)
3. `settings-permissions.sh` — 90 subshells per load (45 entries × 2 helper functions called via `$(...)`). Fix: inline the 5-line helpers. ~190ms back per `approve-safe-commands` invocation. (`90b0e20`)

**Remaining V20 overruns at audit start (post-2.81.1, smoke numbers — known to underreport real-session for some hooks):**

- `grouped-bash-guard` ~140ms (down from 376ms)
- `grouped-read-guard` ~46ms (down from 168ms)
- `session-start` ~39ms
- `auto-mode-shared-steps` ~14ms
- `surface-lessons` ~13ms
- `log-tool-uses` ~9ms / `log-permission-denied` ~10ms

These numbers are the **starting point**, not the target. The audit will re-measure under the new harness before re-budgeting.

## Scope vs `hook-framework-refactor`

Distinct concern. The framework task built the **framework** (headers, validators, codegen, smoke harness). This task uses the framework to find and fix **implementation debt** the framework now makes visible.

## Process

1. **Measurement first.** Land the harness + measurement-correctness fixes before re-measuring anything. (`measurement/`)
2. **Category by category**, in order: 00 → 01 → 02 → 03. Shared libs first because every other category depends on them; standardized hooks second because they're the largest population and most uniform; dispatchers third because their shape ("loader + N children") needs shared findings to be solid; session-context last because it's the most idiosyncratic.
3. **Each category produces a per-axis report** (`performance.md`, `robustness.md`, `testability.md`, `clarity.md`) plus an `inventory.md` listing members and why they belong.
4. **Synthesize** into a single design doc only after all categories are reviewed — premature synthesis hides cross-cutting findings.
5. **Implement** as a stack of focused commits, each with before/after numbers from the harness.
