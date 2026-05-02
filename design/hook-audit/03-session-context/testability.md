---
category: 03-session-context
axis: testability
status: drafted
date: 2026-05-02
---

# 03-session-context — testability

The testability question for context-injection hooks isn't "do we have the right test surface?" but "**are the existing benchmarks measuring the right thing?**" Both hooks already have dedicated `perf-*.sh` harnesses and dedicated test files (`test-session-start*.sh`, `test-surface-lessons-*.sh`). The Shape A / Shape B framing from earlier categories applies but is less load-bearing — the bigger question is what the tests don't cover.

Four sub-questions per axis:
1. **Input variance** — do the perf and correctness harnesses vary the inputs that matter?
2. **Token cost** — do we have a way to measure cumulative bytes-injected per session? (No.)
3. **Relevance** — for surface-lessons, is the relevance dimension testable at all? (Hard problem.)
4. **Correctness** — does injected content appear, well-formed, respect bounds, match expected behavior?

## Existing test surface

| Hook | Test files | Test counts (approx) | Smoke fixtures | Perf harness |
|------|-----------|---------------------:|---------------:|--------------|
| session-start | `test-session-start.sh` (211 LoC), `test-session-start-source.sh` (56 LoC), `test-session-start-integrity.sh` | ~20 cases total | 1 (`runs-on-startup`) | `perf-session-start.sh` |
| surface-lessons | `test-surface-lessons-dedup.sh`, `test-surface-lessons-two-hit.sh` | ~7 cases total | 1 (`passes-when-disabled`) | `perf-surface-lessons.sh` (synthetic + replay modes) |

**Coverage observations:**
- session-start has the **most test coverage** of any hook in the toolkit by case count (3 dedicated test files + dedicated cap validator + dedicated perf harness).
- surface-lessons has narrow but high-quality coverage: dedup behavior, 2-hit threshold semantics. Both tests exercise the SQL path on stubbed databases — high confidence in mechanism.
- Both hooks have **only one smoke fixture each** — `runs-on-startup` (session-start) and `passes-when-disabled` (surface-lessons). Per `00-shared/inventory.md`'s V18 minimum, that's the floor.

## Section A — session-start

### Input variance

The perf harness (`tests/perf-session-start.sh`) runs the hook with **default environment** and records per-phase timings via `CLAUDE_TOOLKIT_HOOK_PERF=1`. It does not vary:

- **Doc count.** The harness assumes the workshop's 3 essential docs. A consumer with more (or fewer) essential docs would see different `essential_docs` phase timing — not exercised.
- **Lessons.db state.** The harness uses the live `~/.claude/lessons.db`. It doesn't run with an empty DB, a mismatched-schema DB, or a DB containing 100+ active lessons (currently 8). The lessons-phase cost may scale; not measured.
- **Cold cache vs warm.** The harness runs the hook 10 times back-to-back; the OS file cache is warm by iteration 2+. First-iteration cost (cold) isn't reported separately.
- **Branch state.** The harness inherits the current git branch. Cost on a branch-with-lessons vs branch-without isn't separately measured.
- **Conditional path coverage.** The various ACTIONABLE_ITEMS paths (settings-integrity drift, toolkit version mismatch, lessons.db missing) aren't exercised by the perf harness — those paths add bytes and ms in real sessions but never light up in the benchmark.

**Verdict on input variance:** the perf harness measures the *baseline happy path*. It would benefit from variants for cold-cache, doc-count-scaling, and the conditional-path scenarios. Captured as `hook-audit-03-perf-session-start-variance` (P3) — extend the harness with `-c` cold-cache mode (drop_caches between runs, or unique tmpdir per run) and a `-s` scenario flag that triggers each ACTIONABLE_ITEMS path.

### Token cost

`perf-session-start.sh` reports wall-clock per phase. It does NOT report bytes-injected per phase or tokens projected. The cap validator (`validate-session-start-cap.sh`) reports total bytes but not per-section.

A useful extension: have the perf harness emit "section X contributed N bytes" alongside the timing breakdown. Same data the validator produces in aggregate, just sectioned. Combined with the byte-turn framing from `performance.md`, this would give a direct visualization of "this section costs X ms wall-clock and Y bytes-per-session of context".

Captured as `hook-audit-03-perf-session-start-bytes` (P3).

### Relevance

session-start's content is universally relevant by design (per `context-pollution.md` Section A). The relevance question doesn't apply.

### Correctness

`test-session-start.sh` covers:
- Lesson surfacing on protected vs feature branches.
- Branch-lesson surfacing logic with stubbed lessons.db.
- ACK suffix output.
- Key/Recent dropped (verified the change landed).

`test-session-start-source.sh` covers SessionStart `.source` capture (the framework's invocation routing).

`test-session-start-integrity.sh` covers the settings-integrity check across baseline, match, committed-change, and warning paths.

The cap validator (`validate-session-start-cap.sh`) covers the harness cap.

**Coverage gaps:**
- **Three negative cases documented in `session-start.sh:20–34` lack fixtures** (no docs dir, empty docs, no git repo). Identified in `robustness.md`; backlog item `hook-audit-03-session-start-negative-fixtures` (P3).
- **The `ESSENTIAL_FULL_INJECT` array's behavior isn't directly tested.** A test that asserts `essential-preferences-communication_style` content appears in full while other essential-*.md content appears as Quick Reference would lock in the policy. Today it works but isn't regression-protected.
- **Conditional ACTIONABLE_ITEMS paths.** Each (toolkit-version-mismatch, lessons-db-missing, opt-in-nudge, settings-integrity-drift, lessons-db-query-failure) has its own emit path. `test-session-start-integrity.sh` covers the integrity path. The other four lack regression coverage.

**Recommendation:** the `ESSENTIAL_FULL_INJECT` test is highest-defensibility (locks in a policy decision that's load-bearing for `context-pollution.md`'s Finding A1). The ACTIONABLE_ITEMS paths are lower-defensibility (each path is small; a regression in one would be obvious in CI logs). Capture the first; defer the rest.

Captured as `hook-audit-03-essential-full-inject-test` (P3).

### Cap validator extension

`validate-session-start-cap.sh` measures total output. Per `robustness.md`'s `hook-audit-03-cap-validator-breakdown` and `context-pollution.md`'s `hook-audit-03-essential-full-inject-discipline`, two extensions land here:

- **Per-section byte breakdown** in the validator's output (drift visibility).
- **Per-doc soft cap** for `ESSENTIAL_FULL_INJECT` members (warns if any single full-inject doc exceeds 4000 B).

Both are validator-side changes, not test-side. Captured already in the relevant axes' backlogs; no duplication here.

## Section B — surface-lessons

Short-form treatment. The asymmetric depth principle holds: thorough audit of the existing mechanism is low-leverage when `eval-claude-mem` may replace it.

### Input variance

`tests/perf-surface-lessons.sh` has two modes:
- **Synthetic** — 6 hardcoded test cases covering Bash/Read paths, no-match, long-command, wrong-tool early exit.
- **Replay** — pulls real `(tool_name, raw_context)` pairs from `~/claude-analytics/hook-logs/surface-lessons-context.jsonl`, ordered by keyword count desc, capped at 10.

This is **better input variance than session-start's perf harness**. Replay mode in particular gives realistic data — the actual contexts the hook processes in real sessions, not synthetic best/worst cases.

What it doesn't vary:
- **lessons.db size.** Uses live DB (8 active lessons currently). Doesn't simulate a DB with 100+ lessons.
- **Tag count and keyword density.** Uses live tags (15 active, half empty). Doesn't simulate a fully-populated tag vocabulary.
- **Cold vs warm cache.** Same back-to-back-iteration issue as session-start.
- **`hooks.db` dedup state.** The dedup lookup (`seen_lookup` phase) hits the live `hooks.db`. Cost varies with how many lessons have already been surfaced this session — not separately measured.

**Verdict:** the existing harness is well-shaped for the current mechanism. Adding lessons.db-size and tag-keyword-density variation would inform the eval-claude-mem comparison. Captured as `hook-audit-03-perf-surface-lessons-variance` (P3, idea) — only worth doing if a baseline-comparison need surfaces during the eval.

### Token cost

The harness reports wall-clock; it doesn't report bytes-injected per fire. Easy to add (the hook's `LESSONS` variable contains exactly the bytes it would inject; print its length).

Combined with hit-rate from `surface-lessons-context.jsonl`, this would give cumulative-bytes-injected projections per session. Useful for the perf-axis byte-turn framing.

Captured as `hook-audit-03-perf-surface-lessons-bytes` (P3).

### Relevance — the hard problem

This is where testability and pollution meet. The fundamental question: **how do you automatically test whether a surfaced lesson is relevant to the operation that triggered it?**

Three approaches, ordered by feasibility:

1. **Manual labeling.** Sample N captured `(context, surfaced_lessons)` pairs from `surface-lessons-context.jsonl`, have a human label "relevant" / "tangential" / "not relevant". Compute precision. Cheap to start, doesn't scale, snapshot-only.
2. **LLM-as-judge.** Feed `(context, surfaced_lessons)` to a Claude prompt that scores relevance. Scales better, requires careful prompt design to avoid the judge being lenient. Could run as part of `make validate` against a fixed sample.
3. **User signal capture.** Attach a feedback mechanism to surfaced lessons (e.g. an opt-in `/lesson-feedback` skill that asks the user post-session whether the lessons fired were useful). Highest signal quality, lowest collection rate.

**For this audit,** approach 1 is the right next step. Sample 50 firings from `~/.claude/hooks.db.surface_lessons_context`, manually label each, compute precision. Use the result as input to `eval-claude-mem` to compare against whatever relevance scoring the candidate systems claim. Captured as `hook-audit-03-surface-lessons-relevance-sample` (P2) — manual but small; gives the eval task a concrete number.

This is **the highest-leverage testability action for surface-lessons.** Without a relevance metric, the eval-claude-mem comparison can only score on tractable axes (perf, dependency footprint, license, integration cost), missing the dimension that actually matters.

### Correctness

`test-surface-lessons-dedup.sh` and `test-surface-lessons-two-hit.sh` cover:
- Intra-session dedup via `hooks.db.surface_lessons_context`.
- 2-hit threshold semantics (single hit → no surface; two hits → surface; cross-tag split → no surface; plural doesn't double-count).

These tests use stubbed `lessons.db` and `hooks.db` — high-fidelity to the real SQL. Coverage is high for the mechanism.

**Coverage gaps:**
- The `LIMIT 3` cap isn't directly tested (a fixture with 5+ matching lessons asserting only 3 surface).
- The scope filter (`l.scope = 'global' OR (l.scope = 'project' AND l.project_id = '${SAFE_PROJECT}')`) isn't exercised.
- The 3-character word filter (line 64 `[ ${#word} -lt 3 ] && continue`) isn't directly tested.
- The JSON-escape edge cases identified in `robustness.md` (lesson text with newlines, tabs, control chars) — no test fixture covers them.

Each gap is a small fixture's worth. Aggregate to one new test file `test-surface-lessons-edge-cases.sh` covering all four. Captured as `hook-audit-03-surface-lessons-edge-fixtures` (P3).

## Cross-cutting findings

### "Are we measuring the right thing?" answers per axis

| Hook | Wall-clock | Bytes injected | Relevance | Correctness |
|------|------------|----------------|-----------|-------------|
| session-start | Yes (per-phase) | Aggregate only (cap validator) — needs per-section | N/A | High coverage; minor gaps (negative fixtures, full-inject regression) |
| surface-lessons | Yes (per-phase, synthetic + replay) | Not measured — easy add | **No automated way** — manual sampling needed | High mechanism coverage; edge-case gaps (LIMIT 3, scope, 3-char filter, JSON escape) |

The single highest-leverage gap is **relevance** for surface-lessons. The single biggest opportunity is **token-cost measurement** for both hooks (small extension, big informational value).

### The Shape A / Shape B framing applies in miniature

session-start and surface-lessons both run as Shape B (subprocess fork) for testing. Per-fork cost:
- session-start: ~136ms wall-clock per fork. Tests with N cases pay N × 136ms.
- surface-lessons: 20–78ms per fork. Tests with N cases pay much less.

Shape A reachability:
- session-start is a top-down script with no callable functions. Restructuring it for Shape A would be a substantial refactor (similar to the dispatcher entrypoint refactor evaluated in `02-dispatchers/testability.md` and rejected). Wall is ~5s for current ~20 cases — acceptable.
- surface-lessons has callable shape: `match`-style functions could be extracted (the tokenizer, the SQL builder). Today it's all top-level. Refactoring is moderate cost; the win is small (~4ms per case × 7 cases ≈ 28ms saved). Not worth the churn unless a relevance test sample needs to run hundreds of cases — at which point Shape A becomes load-bearing for runtime.

**Verdict:** keep both as Shape B for now. Reopen if the relevance-sample test (above) grows to >100 cases.

### Cap validator + per-section breakdown is the highest-leverage cross-axis change

The cap validator runs in `make validate` today and catches aggregate-cap excess. Adding per-section bytes turns it into a drift signal — anyone making session-start grow can see exactly which section is doing the growing. This single extension supports:
- **Robustness:** catches per-section growth before it eats other sections' budget.
- **Performance:** documents per-section byte cost (input to byte-turn projection).
- **Context-pollution:** validates the per-doc soft-cap policy from `context-pollution.md` Finding A1.
- **Testability:** the breakdown IS the test — a per-section cap that fails CI when violated is regression coverage by construction.

This is a small validator change with effects across four axes. Captured as `hook-audit-03-cap-validator-breakdown` (already in `robustness.md`'s backlog).

## Verified findings feeding downstream axes

### Performance

- The token-cost measurement extension (per-section bytes from `perf-session-start.sh`, total bytes from `perf-surface-lessons.sh`) gives the perf axis the data it needs to validate the byte-turn framing against real captured sessions.

### Robustness

- The negative-case fixtures for session-start (3 fixtures) close the regression gap on documented robustness behaviors.
- The edge-case fixtures for surface-lessons (LIMIT 3, scope filter, 3-char filter, JSON escape) close mechanism-coverage gaps surfaced in `robustness.md`.

### Context-pollution

- The relevance-sample (manual labeling of 50 firings) is the data input the pollution axis needs to validate its B4 finding (concept tags causing false positives) with concrete numbers, and the data the eval-claude-mem task needs to compare candidate systems against.
- The `ESSENTIAL_FULL_INJECT` regression test locks in the Finding A1 policy decision.

### Clarity

- The per-section payload-byte data (from the validator extension) becomes a clarity input — when adding a new section to session-start, the author has direct data on what they're committing.

## Confidence

- **High confidence** that the existing test surface for both hooks is in good shape on the **mechanism** axis. Both `test-session-start.sh` and `test-surface-lessons-*.sh` cover the SQL paths, the gating logic, the protected-branch behavior thoroughly.
- **High confidence** that the dominant gaps are (1) negative-case fixtures (cheap, defensible), (2) per-section byte breakdown in the validator (cross-axis leverage), (3) relevance sampling (the input the eval task needs).
- **Medium confidence** on input-variance recommendations. The current perf harnesses are usable for budget-setting; adding lessons.db-size and doc-count variants would inform but not block the work.

## Open

- **Whether the relevance-sample manual labeling should be done as part of the hook-audit, or deferred to the eval-claude-mem task itself.** Editorial. Doing it during the audit gives the audit a concrete relevance number; doing it during the eval ties the labeling to the candidate systems' specific scoring. Either way the data is the same. Recommend doing it during the audit (this audit) so the result is in hand when eval-claude-mem starts.
- **Whether to add a relevance-LLM-judge harness as a stretch goal.** Approach 2 from §B Relevance. Higher engineering cost, scales better. Defer until manual labeling shows whether the precision is the bottleneck or the volume is.

## Backlog tasks added

- `hook-audit-03-surface-lessons-relevance-sample` (P2) — manually label 50 firings from `surface-lessons-context.jsonl` for relevance; compute precision. Direct input to `eval-claude-mem`.
- `hook-audit-03-essential-full-inject-test` (P3) — regression test asserting `ESSENTIAL_FULL_INJECT` policy holds (full content for the array's members; Quick Reference for others).
- `hook-audit-03-perf-session-start-variance` (P3) — extend `perf-session-start.sh` with cold-cache mode and ACTIONABLE_ITEMS scenario flags.
- `hook-audit-03-perf-session-start-bytes` (P3) — emit per-section bytes-injected from `perf-session-start.sh`.
- `hook-audit-03-perf-surface-lessons-bytes` (P3) — emit bytes-injected from `perf-surface-lessons.sh`.
- `hook-audit-03-perf-surface-lessons-variance` (P3, idea) — extend `perf-surface-lessons.sh` with lessons.db-size and tag-density scenarios. Defer.
- `hook-audit-03-surface-lessons-edge-fixtures` (P3) — single test file covering LIMIT 3, scope filter, 3-char word filter, JSON-escape edge cases.

Existing items confirmed (not duplicated):

- `hook-audit-03-session-start-negative-fixtures` — from robustness.
- `hook-audit-03-cap-validator-breakdown` — from robustness; cross-axis leverage noted here.
- `hook-audit-03-essential-full-inject-discipline` — from context-pollution.
