---
category: 03-session-context
axis: performance
status: drafted
date: 2026-05-02
---

# 03-session-context — performance

Two-budget framing for context-injection hooks: **wall-clock cost** AND **amortized context cost** (bytes injected × turns remaining in session). The 02-dispatchers framework only measured wall-clock — adequate for safety dispatchers whose injection is scoped to one decision. Inadequate here, where every byte injected lives until the session ends.

This axis grounds two questions:
1. What's the right wall-clock budget for each hook, given its firing rate (one-shot for session-start, per-turn for surface-lessons)?
2. What's the per-session token cost of what each hook injects, and is it justified by the value it provides?

## Methodology

- **Wall-clock data:** from `tests/perf-session-start.sh -n 10` and `tests/perf-surface-lessons.sh -n 10` taken this session. No N=30 paired smoke/real probe exists for these two hooks (the per-hook-N30 probe set excludes them — see `inventory.md` "Open"). Numbers are p50 across n=10; variance bands are wider than the 02-dispatchers data and noted where it matters.
- **V20 budget data:** from this session's `make check`.
- **Payload size:** from `bash .claude/hooks/session-start.sh | wc -c` (5426 B this session). For surface-lessons: from the lesson-text byte distribution in `lessons.db`.
- **Hit-rate / fire-frequency data:** from `~/.claude/hooks.db.surface_lessons_context` (17 880 indexed invocations) and `~/claude-analytics/hook-logs/session-start-context.jsonl` for session-start. Context-cost arithmetic uses these to project amortized impact.

## session-start

### Wall-clock budget

Phase decomposition (from `inventory.md`'s detailed table, p50 of n=10):

| Phase | Wall (ms) | What runs |
|-------|----------:|-----------|
| `hook_init` | 5 | stdin parse + globals + EXIT trap install |
| `essential_docs` | **38** | 3× file reads + Quick Reference extraction (2 of 3) + full-inject (1 of 3) |
| `git_context` | **22** | 2× `git` forks + JSONL emit |
| `lessons` | 6 | branch-lessons SQL + manage-lessons-nudge SQL |
| Other phases | <10 each | settings_integrity, docs_guidance, toolkit_version, nudge, acknowledgment |
| **TOTAL inside hook** | 112 | |
| **WALL_CLOCK** | 136 | (process start → exit) |

V20 reports **49ms hook work** (it starts measuring after `hook_init`, missing ~7ms of bash startup + hook-utils parse + hook_init itself, and ~something of the EXIT-trap teardown). The 49ms figure is wider than the per-phase sum would predict — the V20 measurement includes the stdout-capture overhead that perf-session-start.sh's `>/dev/null` redirect avoids.

**Budget framing:** session-start runs **once per session**. The right comparison isn't "is 49ms acceptable for a per-call hook" (it isn't — that would be a hot-path budget) but "**is 136ms wall-clock acceptable as time-to-first-prompt overhead**". The user's stated tolerance: 1s acceptable under conditions, 5s too much. 136ms is well within that envelope.

But V20 doesn't know about firing rate. It compares measured time against a per-firing budget regardless of how often the hook fires. This is wrong for one-shot hooks: a 200ms session-start is *cheaper in aggregate* than a 5ms hook firing 100× per session. V20 would warn on the 200ms hook and miss the 500ms aggregate of the 5ms hook.

**Recommended `PERF-BUDGET-MS` for session-start:**

| Outcome | Recommended | Rationale |
|---------|------------:|-----------|
| `scope_miss` (no actionable items) | **200** | Covers current p50 (49ms hook work) with ample headroom; signals "this is a once-per-session loader, not a hot-path hook"; warns at +4× from current baseline |
| `scope_hit` (actionable items, lessons surfaced, etc.) | **300** | Same shape, allowing for the conditional growth paths (lessons block, toolkit version mismatch, etc.) which add ~50–100 B and ~10–20 ms each |

These numbers are loose by hot-path standards (a 200ms threshold for a standardized hook would be wrong), but **right** for a once-per-session loader. They stop V20 false-positives, leave headroom for the existing growth paths, and would still warn if anything pushed session-start past 200ms (which would likely indicate a real issue).

Cheaper alternative: lazy-mode budget keys (the framework's V20 doesn't currently distinguish "this hook runs once per session" from "this hook runs every PreToolUse"). A future improvement would let `PERF-BUDGET-MS` declare a firing-rate class — `firing_rate=session, scope_miss=200` would communicate the framing. Captured as a follow-up: `hook-audit-03-firing-rate-budget` (P3).

### Context cost (amortized byte-turn)

session-start injects 5426 B once per session. That payload is part of the conversation transcript from session start onward, so every turn re-reads it.

**Real session-length distribution** (from `~/.claude/sessions.db`, `kind='human'` turns per session, claude-toolkit project, N=490 sessions):

| Percentile | Turns | Note |
|------------|------:|------|
| p50 (median) | **8** | Half of sessions are this short or shorter |
| mean | 11.2 | Long tail pulls mean above median |
| p75 | 15 | |
| p90 | 26 | |
| p95 | **33** | "Long session" threshold |
| max observed | 96 | Outlier; not used for budgeting |

**Byte-turn arithmetic** anchored to those percentiles (token-byte ratio ~3.5 B/token for English text):

| Session length | Cumulative byte-turns | ≈ tokens × turns | Cohort |
|----------------|----------------------:|-----------------:|--------|
| p50 = 8 turns | 43 408 | ~12 K token-turns | typical session |
| p75 = 15 turns | 81 390 | ~23 K token-turns | longer-than-half |
| p90 = 26 turns | 141 076 | ~40 K token-turns | long session |
| p95 = 33 turns | 179 058 | ~51 K token-turns | extra-long session |
| max observed = 96 turns | 520 896 | ~149 K token-turns | outlier |

This is the cost the model pays for the session-start injection across the whole conversation. **It's recurring**, even though the hook only fires once. **At p50 (8 turns), session-start's payload pays ~43K byte-turns / ~12K token-turns** — that's the typical cost. The earlier draft of this doc estimated against synthetic 30/100/300-turn ladders, which **overstated typical cost by ~3–10×**: real workshop sessions are short.

**Comparison framing:** a 100-byte change to session-start's payload at p50 is the same as a 100-byte one-shot injection per turn over an 8-turn session. At p95 (33 turns) it's a 33× multiplier. Every byte added compounds with session length.

The `essential-preferences-communication_style` full-inject is ~3500 B. Real-session impact:

- **At p50 (8 turns): ~28 K byte-turns** — by far the dominant context cost from session-start, but in absolute terms a fraction of the synthetic 100-turn projection.
- **At p95 (33 turns): ~115 K byte-turns** — still the dominant cost, but the long-tail amplification is what makes shrinking this doc worthwhile.

Is it justified? Yes (per `context-pollution.md` Section A — tone-shaping needs verbatim content). But the multiplier explains why this single doc is so consequential, especially in long sessions. **Trimming `essential-preferences-communication_style` is the highest-leverage byte-turn optimization in the toolkit** — every byte saved × every turn × every session compounds across the whole user base.

Captured as a parallel concern under `hook-audit-03-essential-full-inject-discipline`: the soft-cap-validator stops growth; an opportunistic trim pass on the file itself reduces the baseline.

### Recommendation

- **Add `PERF-BUDGET-MS: scope_miss=200, scope_hit=300` header to session-start.sh.** Single-line change; removes the recurring V20 warn; numbers are grounded in measurement.
- **Document the byte-turn framing in `relevant-toolkit-hooks.md`.** The framework doesn't currently distinguish per-call from one-shot hooks, and the cost model for context injection is fundamentally different from for safety dispatchers. A short subsection in the hooks reference doc would set the right expectation for future hook authors.
- **Defer firing-rate-aware budget keys** (`firing_rate=session` etc.) — the manual numbers above work; the framework change can wait until a second one-shot hook joins the family.

Captured as:
- `hook-audit-03-session-start-perf-budget` (P2) — add the header. Single-line; defensible numbers; removes recurring warn.
- `hook-audit-03-document-byte-turn-framing` (P3) — add the byte-turn framing to `relevant-toolkit-hooks.md`. Doc-only.
- `hook-audit-03-firing-rate-budget` (P3, idea) — extend `PERF-BUDGET-MS` schema. Deferred.

## surface-lessons

### Wall-clock budget

Path decomposition (from `inventory.md`'s table):

| Path | Wall (p50) | Inside-hook (p50) | Frequency (from real data) |
|------|-----------:|------------------:|----------------------------|
| Wrong tool — early exit | 20ms | 9ms | (matched against `Bash\|Read\|Write\|Edit`; off-list never fires hook) |
| Tool match, no keyword hit | 43ms | 17ms | ~67% of invocations (no SQL match) |
| Tool match, SQL fires, no rows | 66ms | 46ms | (subset of "no match" path; the SQL fired but returned nothing) |
| Tool match, SQL fires, lessons injected | 72–78ms | 47–51ms | ~33% of invocations |

V20 reports 8ms hook work for the smoke fixture (`passes-when-disabled`, i.e. `CLAUDE_TOOLKIT_LESSONS=0`). This is the gated-disabled fast path, not the real-mode path. Real-mode wall-clock is 50–80ms depending on match path.

**Budget framing:** surface-lessons runs **per Bash/Read/Write/Edit dispatch**, on the per-call path. This is the safety-dispatcher class for budget purposes, not the one-shot class.

The dominant SQL_query phase is ~10ms p50. The hook-init + jq_parse + tool_match + tokenize + build_sql floor is ~14ms across all paths. So the natural budget envelope:

- Pass (no match): ~17ms inside-hook → V20 sees ~10ms of hook work after subtracting bash startup + hook_init pre-init time.
- Hit (match + inject): ~47ms inside-hook → V20 sees ~40ms.

**Recommended `PERF-BUDGET-MS` for surface-lessons:**

| Outcome | Recommended | Rationale |
|---------|------------:|-----------|
| `scope_miss` (no inject) | **20** | Covers current ~8–10ms hook work + variance; warns at +2× from current baseline |
| `scope_hit` (lessons injected) | **60** | Covers the 40ms hook work + ~50% headroom for the SQL path's variance |

These numbers are tighter than session-start's because surface-lessons IS on the per-call hot path. ~20ms × frequency-of-Bash/Read/Write/Edit-dispatches matters at session scale.

The asymmetric `scope_miss`/`scope_hit` split here (20 / 60) is meaningful: 67% of invocations take the cheap path (no match), 33% take the expensive path (SQL fires + inject). The current default `scope_miss=5, scope_hit=50` warns on every invocation; the proposed `scope_miss=20, scope_hit=60` matches reality.

### Context cost (per-fire byte-turn)

Each surface-lessons fire injects up to 3 lessons, each ~100–300 B of text plus ~5 B of `\n- ` prefix. Typical fire: ~600 B total injection.

Unlike session-start's once-per-session model, surface-lessons fires **multiple times per session** when conditions match. **Within-session dedup** (`surface-lessons.sh:79–102`) excludes lesson IDs already surfaced earlier in the same session via `hooks.db.surface_lessons_context` lookup — so within a session, the *same* lesson surfaces ~once, not on every match. Cross-session, the dedup resets.

Real data from `~/.claude/hooks.db.surface_lessons_context` shows hit-rate by tool:

- Bash: 44.3% of dispatches surface ≥1 lesson
- Read: 11.5%
- Edit: 6.8%
- Write: 2.6%

**Real per-session statistics** (from `surface_lessons_context`, claude-toolkit project): average **19 Bash dispatches per session**, average **9 fires (matching dispatches) per session** — consistent with the 44% hit rate. Within-session dedup means those 9 fires are mostly *distinct* lessons (a small lag-window allows rare repeats per `surface-lessons.sh:82–83`).

**Byte-turn arithmetic** anchored to real session percentiles + the 9-fires-per-session average + ~600 B per fire (with fires distributed uniformly across the first half of the session, each paying bytes × remaining-turns):

| Session length | Approximate byte-turns from surface-lessons | Vs session-start at same length |
|----------------|--------------------------------------------:|--------------------------------:|
| p50 (8 turns) | ~22 K (9 fires × 600 B × ~4 avg remaining) | session-start ~43 K — surface-lessons is ~half |
| p75 (15 turns) | ~46 K (9 × 600 × ~8.5) | session-start ~81 K — surface-lessons ~57% |
| p90 (26 turns) | ~84 K (9 × 600 × ~15.5) | session-start ~141 K — ~60% |
| p95 (33 turns) | ~108 K (9 × 600 × ~20) | session-start ~179 K — ~60% |

**Important correction from earlier draft.** The previous version of this section projected "~990K byte-turns in a Bash-heavy 100-turn session" — that was based on synthetic 100-turn sessions and 22 fires-per-session, both above realistic numbers for this workshop. **Real workshop sessions are short (p50=8 turns) and dedup-bounded.** At realistic percentiles, surface-lessons' cumulative cost is meaningfully *smaller* than session-start's, not larger — though both are non-trivial. The "Mega Elephant" framing (relevance precision) still holds; the perf-axis quantification of cumulative token cost is **less alarming than initially estimated** but still worth reducing.

The amortized cost flips back toward session-start dominating at every percentile in this dataset. **In sessions much longer than p95 (long Bash-heavy debug sessions, ~50+ turns), surface-lessons can approach or exceed session-start's cost** — the original framing was directionally right for outliers, just wrong for the typical case.

This is the perf-axis quantification of the Mega Elephant from `context-pollution.md`. The cost is real but moderate at typical session lengths. Whether that cost is justified by relevance is `context-pollution.md`'s call (verdict: not all of it — concept-tag false positives + cross-project leakage are real failure modes).

### Recommendations

- **Add `PERF-BUDGET-MS: scope_miss=20, scope_hit=60` header to surface-lessons.sh.** Stops the V20 false-positive on every dispatch.
- **The structural perf finding is the byte-turn cost, not the wall-clock.** Wall-clock is fine; the cumulative token cost is the actual problem. That problem is the Mega Elephant; the right move per `context-pollution.md` B6 is to feed the data to `eval-claude-mem` rather than fix in place.

Captured as:
- `hook-audit-03-surface-lessons-perf-budget` (P2) — add the header. Stops the recurring warn.

The byte-turn cost is *not* added as a separate backlog item because:
- Reducing it via the current mechanism (e.g. lower LIMIT, higher hit threshold) would risk the same churn the audit is deferring per `context-pollution.md` B6.
- Reducing it via a relevance-aware mechanism is exactly what `eval-claude-mem` will evaluate.

## Cross-cutting observations

### V20 doesn't know about firing rate

The framework's V20 budget mechanism (`scope_miss` / `scope_hit`) measures per-firing time but doesn't account for **firing rate**. A 5ms-budget hook firing 100× per session costs 500ms aggregate; a 200ms-budget hook firing once costs 200ms. V20 warns on the second; the first slips through.

For 03-session-context this matters because:
- session-start (one-shot) needs a much looser budget than its current 5ms default.
- surface-lessons (per-turn) needs a tighter budget than it currently warns at (8ms vs 5ms default), but the *more important* constraint is the cumulative byte-turn cost, which V20 doesn't measure at all.

**Recommendation:** add a `firing_rate` annotation to the `PERF-BUDGET-MS` header schema. Values: `session` (fires once), `per_call` (fires per dispatch), `per_event` (fires per event class). V20 would scale aggregate-budget calculations using the rate. Captured as `hook-audit-03-firing-rate-budget` (P3, idea) — defer until a second one-shot hook joins the family.

### Context cost is unmeasured by the toolkit today

Neither V20 nor the perf-*.sh harnesses measure tokens-injected. The cap validator measures **session-start's** total bytes-injected against the harness 10240 B cap, but no equivalent exists for surface-lessons (no hard cap on PreToolUse `additionalContext` from the harness side).

The byte-turn framing developed here doesn't have a tool to enforce it. Adding a "token budget per session" tracking metric would:
- Sum bytes-injected across all hooks in a session.
- Warn when cumulative injection exceeds a configured threshold (e.g. 20 KB across all hooks in a 100-turn session, projected forward).
- Surface to the user in `make validate` or via a separate diagnostic command.

This is **out of scope** for the hook-audit but worth recording as a future framework capability. Captured as `hook-audit-03-cumulative-context-budget` (P3, idea) — depends on the analytics ecosystem for the data, not on hook-framework-internal changes.

### Comparison with 01-standardized and 02-dispatchers

The standardized hooks have wall-clock costs ~17–47ms and don't inject context. Their cost is fully captured by V20's wall-clock budget.

The dispatchers have wall-clock costs ~50–250ms (per `02-dispatchers/performance.md`) and inject only when blocking (the `_BLOCK_REASON` text, very small). Their cost is also fully captured by V20.

The 03 hooks add a **second cost dimension** (byte-turn amortization) that doesn't apply to either earlier category. This audit is the first to develop a framing for it. Whether the framing should propagate to a framework feature (the proposed `firing_rate` annotation + cumulative-context-budget tracking) is a future call.

## Verified findings feeding downstream axes

### Robustness

- The wall-clock budgets above describe **happy-path performance**. Failure modes (lessons.db missing, git command failing, settings-integrity error) push the hook through different paths. Robustness axis quantifies whether those paths are bounded — perf assumes they are because the early-exit branches are short.

### Testability

- The N=10 wall-clock data is single-mode (real, with `CLAUDE_TOOLKIT_LESSONS=1`). Testability axis evaluates whether the perf-*.sh harnesses should add smoke-equivalent (`LESSONS=0`) and N=30 modes for paired comparison.
- The byte-turn cost arithmetic is observable from existing JSONL — no new test instrumentation needed. `tests/perf-*.sh` could optionally print "byte-turn projection" as an output. Testability call.

### Clarity

- The byte-turn framing developed here belongs in `relevant-toolkit-hooks.md` as a new subsection. Falls to clarity to scope the doc update.
- The `PERF-BUDGET-MS` numbers above are concrete; clarity confirms they're the right shape (scope_miss < scope_hit reflects path-decomposed reality).

## Confidence

- **High confidence** in the wall-clock numbers and budget recommendations. Phase decomposition is from per-phase probes; budgets are p95 + headroom from those phases.
- **Medium confidence** in the byte-turn arithmetic. The model itself (bytes × remaining_turns) is correct; the inputs (typical session length, typical dispatch frequency) are estimates from observed data, not measured against a specific cohort. A future audit could tighten these by sampling real session statistics.
- **High confidence** that the byte-turn dimension is the right structural finding — surface-lessons' cumulative token cost in a Bash-heavy session is structurally larger than session-start's, and the cost is paid silently. This is the perf-axis quantification of the pollution problem.

## Open

- **Single-mode N=10 data is thinner than the per-hook-N30 probe set.** Running `tests/perf-*.sh` with N=30 in both `LESSONS=0` and `LESSONS=1` modes would produce smoke/real comparable data and tighter variance bands. Captured implicitly under inventory.md's "Open" — not duplicated here.
- **Token-byte ratio assumed at ~3.5 B/token.** Actual ratio depends on the content; markdown with code blocks may run higher (~4–5 B/token), prose lower. The byte-turn arithmetic is ratio-independent; only the "× tokens" gloss on top is approximate.

## Backlog tasks added

- `hook-audit-03-session-start-perf-budget` (P2) — add `PERF-BUDGET-MS: scope_miss=200, scope_hit=300` to session-start.sh.
- `hook-audit-03-surface-lessons-perf-budget` (P2) — add `PERF-BUDGET-MS: scope_miss=20, scope_hit=60` to surface-lessons.sh.
- `hook-audit-03-document-byte-turn-framing` (P3) — add a "Context cost amortization" subsection to `relevant-toolkit-hooks.md`.
- `hook-audit-03-firing-rate-budget` (P3, idea) — extend `PERF-BUDGET-MS` schema with `firing_rate` annotation. Defer.
- `hook-audit-03-cumulative-context-budget` (P3, idea) — track cumulative bytes-injected per session; warn over threshold. Out of scope for hook-audit; depends on analytics ecosystem.
