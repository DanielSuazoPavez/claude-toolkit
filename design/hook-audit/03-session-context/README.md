---
category: 03-session-context
status: drafted
date: 2026-05-02
---

# Category 03 — Session-Context Hooks

Context-injection hooks. Add tokens to the model's context (vs blocking/approving tool calls). Different cost shape from PreToolUse safety dispatchers: failures degrade context rather than blocking actions, and **every byte injected costs (bytes × turns remaining)** because injected content lives in the conversation transcript across all subsequent turns.

## Members

- `session-start.sh` — runs once per session, loads essential docs + git + lessons + ACK (~5.4KB payload, 136ms wall)
- `surface-lessons.sh` — runs per Bash/Read/Write/Edit dispatch, surfaces tag-matched lessons (33% hit rate, up to 3 lessons × ~200B per fire)

## Per-axis reports — 6 axes (added context-pollution)

- [`inventory.md`](inventory.md) — events, payload shape, current cost, V20 status
- [`performance.md`](performance.md) — two-budget framing: wall-clock + amortized byte-turn context cost
- [`context-pollution.md`](context-pollution.md) — **headline axis.** Are injected bytes earning their slot? (session-start: mostly yes; surface-lessons: empirically problematic — the Mega Elephant)
- [`robustness.md`](robustness.md) — context-injector failure modes (replaces fail-closed/open/soft/loud taxonomy)
- [`testability.md`](testability.md) — are existing perf/test harnesses measuring the right thing?
- [`clarity.md`](clarity.md) — is the injection policy legible? Recommendations across all axes consolidated.

## Asymmetric audit depth

session-start gets the **full multi-axis treatment** across all 6 axes.

surface-lessons gets **short-form treatment** on most axes, with **full treatment only on context-pollution** (where the relevance failure mode is the dominant credibility risk for the lessons ecosystem).

Why: `eval-claude-mem` (P1, backlog) is queued to evaluate two external systems (claude-mem, agentmemory) with fundamentally different relevance/retrieval models. A thorough audit of the *current* surface-lessons mechanism would re-litigate decisions that may be obsolete in one cycle. The pollution axis records the empirical failure data so the eval task has concrete inputs to compare candidates against; other axes intentionally stay light.

## Headline findings

- **session-start's payload is 65% concentrated in one full-injected doc** (`essential-preferences-communication_style`). No per-doc soft cap exists. Recommend: extend the cap validator AND opportunistically trim the doc itself — both compound across every session. (`context-pollution.md` Finding A1; `performance.md` byte-turn analysis.)
- **surface-lessons fires on 33% of PreToolUse(Bash|Read|Write|Edit) invocations** (44% on Bash). Within-session dedup is already in place (`surface-lessons.sh:79–102`) and bounds intra-session repetition. The visible failure mode is **cross-session recurrence** — the dominant 3-lesson tuple has surfaced across 261 distinct sessions (~53% of all claude-toolkit sessions). Two of those three lessons originate in sibling projects. (`context-pollution.md` Section B.)
- **Half the active tags in `lessons.db` have empty keywords** and silently never match. (`context-pollution.md` B3.)
- **Both hooks warn on every `make check`** because they inherit the framework default 5ms `scope_miss` budget. Recommended budgets: session-start `scope_miss=200, scope_hit=300`; surface-lessons `scope_miss=20, scope_hit=60`. Numbers backed by per-phase measurement. (`performance.md`.)
- **Cumulative byte-turn cost framing, anchored to real session percentiles** (claude-toolkit p50=8 turns, p95=33 turns from `~/.claude/sessions.db`): at p50, session-start pays ~43K byte-turns and surface-lessons ~22K. Real workshop sessions are short and dedup-bounded — earlier draft estimates against synthetic 100-turn sessions overstated typical cost by ~3–10×. **session-start dominates byte-turn cost at every realistic percentile**; surface-lessons only approaches it in long-tail (~50+ turn) sessions. The byte-turn dimension is still unmeasured by V20. (`performance.md`.)

## Backlog summary

Approximately 17 items added or confirmed across the audit. Highlights:

- P2: `hook-audit-03-session-start-perf-budget`, `hook-audit-03-surface-lessons-perf-budget`, `hook-audit-03-document-lessons-limitations`, `hook-audit-03-surface-lessons-relevance-sample`.
- P3: validator extensions (cap breakdown + per-doc soft cap), perf-harness variance, edge-case fixtures, JSON-escape audit, doc updates for byte-turn framing.
- P3-ideas (deferred): `firing_rate` budget annotation, cumulative-context-budget tracking.

Full enumeration in `clarity.md` "Backlog tasks added (clarity-specific)" section's consolidated table.
