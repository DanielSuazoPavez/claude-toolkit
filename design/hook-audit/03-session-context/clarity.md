---
category: 03-session-context
axis: clarity
status: drafted
date: 2026-05-02
---

# 03-session-context — clarity

Code shape, naming, where logic lives, **and — most importantly for context injectors — is the injection policy legible?** The earlier categories' clarity axis dealt with "is the dispatch table readable" and "are comments earning their slot." For 03 the dominant question is different: **a reader looking at session-start.sh or surface-lessons.sh — can they tell *why* each piece of content gets injected, and what the policy is for adding new ones?**

Comment ratios for context: session-start.sh is 29% comments (85/290 LoC); surface-lessons.sh is 34% (51/148). Both within the standardized-hook band (~25–35%). Comment density isn't the issue here.

## Proposals from other axes

Eight concrete proposals were flagged by the upstream axes (inventory, performance, context-pollution, robustness, testability). Each evaluated below.

### Proposal 1 — Add per-hook `PERF-BUDGET-MS` headers (from performance)

**Background.** Both hooks warn on every `make check` because they inherit the framework default `scope_miss=5, scope_hit=50`. Concrete numbers from `performance.md`:

| Hook | Recommended `scope_miss` | Recommended `scope_hit` |
|------|-------------------------:|------------------------:|
| `session-start` | 200 | 300 |
| `surface-lessons` | 20 | 60 |

session-start's looser budget reflects its **once-per-session** firing rate; surface-lessons' tighter budget reflects its per-call-on-Bash/Read/Write/Edit firing rate.

**Pros:**
- One header line per hook. Cheapest possible fix.
- Stops V20 false-positives without hiding regressions.
- Numbers are backed by per-phase measurement.
- Pattern matches the recommended `02-dispatchers/clarity.md` Proposal 1 (already on backlog).

**Cons:**
- Encodes "this hook is structurally slower than the default" into the codebase. Adds a brief explanatory comment alongside the header.
- The framework doesn't currently express *why* the budgets differ in shape between session-start (one-shot) and surface-lessons (per-call). A future `firing_rate` annotation (per `performance.md` Proposal `hook-audit-03-firing-rate-budget`) would carry the framing; until then, comments do.

**Cross-axis impact:**
- Performance: directly removes V20 false-positives.
- Robustness, testability, context-pollution: zero impact.

**Recommendation: do.** Already on backlog as `hook-audit-03-session-start-perf-budget` and `hook-audit-03-surface-lessons-perf-budget` (P2 each). Clarity confirms numbers without modification and adds: include a 1-2 line comment alongside each budget header explaining the firing-rate rationale ("once-per-session loader" / "per-call PreToolUse").

### Proposal 2 — Document byte-turn framing in `relevant-toolkit-hooks.md` (from performance + context-pollution)

**Background.** The byte-turn cost model developed in `performance.md` (cumulative bytes injected × turns remaining in session) is fundamentally different from the per-call cost model used for safety dispatchers. Captured under `hook-audit-03-document-byte-turn-framing` (P3). Together with the failure-mode taxonomy from `robustness.md` ("total failure / partial payload / stale data / cap exceeded / source unavailable / wrong relevance"), this is a category-level addition to the hooks reference doc.

**Pros:**
- Sets expectations for future context-injection hooks: anyone authoring one will know to think in byte-turns, not just wall-clock.
- Communicates to consumers what session-start is "buying" them in cumulative context cost.
- The failure-mode taxonomy generalizes — future context-injection hooks (if any) inherit the framing.

**Cons:**
- New doc surface to maintain. ~1–2 paragraphs in `relevant-toolkit-hooks.md` plus a small example.
- Risk of the doc rotting if no second context-injection hook is ever added.

**Cross-axis impact:**
- Performance: gives the budget recommendations a documented home.
- Context-pollution: documents the policy framework; concrete limitations live in `relevant-toolkit-lessons.md` (per `hook-audit-03-document-lessons-limitations`).
- Robustness: the failure-mode taxonomy belongs in the same subsection.

**Recommendation: do.** ~1 page of doc; high-leverage given session-start is currently the only hook of its kind in the toolkit and consumers may add their own. Already on backlog. Clarity adds: include the failure-mode taxonomy from `robustness.md` in the same doc subsection — both are properties of context-injection-hook design.

### Proposal 3 — Document known limitations of surface-lessons in `relevant-toolkit-lessons.md` (from context-pollution)

**Background.** `context-pollution.md` Section B identified four documented-by-data limitations: hit-rate (33%, 44% on Bash), concentration profile (top 3-tuple fired 2941 times), tag vocabulary problems (half empty, others mixed precision), cross-project leakage on globals. None of these is in user-facing docs today. Captured as `hook-audit-03-document-lessons-limitations` (P2).

**Pros:**
- Sets expectations for users: "the lesson surfaced may not always be relevant" is a known failure mode, not a bug. Pre-empts user frustration.
- Frames the `eval-claude-mem` evaluation: documenting the failure modes legitimizes the decision to evaluate replacements.
- Compatible with the eval outcome: if the eval recommends replacement, the limitations doc gets superseded; if not, the doc remains useful.

**Cons:**
- Risk of "advertising the bug" — a user who didn't notice false-positive lessons before may now look for them. But the user already noticed (this audit was triggered by that). The doc serves users who haven't yet hit the issue.

**Cross-axis impact:**
- Context-pollution: directly supports.
- Performance, robustness, testability: zero direct.

**Recommendation: do.** Already on backlog. Highest-leverage immediate move for surface-lessons.

### Proposal 4 — Manually label 50 firings for relevance (from testability)

**Background.** `testability.md` Section B Relevance recommends manually labeling 50 captured `(context, surfaced_lessons)` pairs from `~/.claude/hooks.db.surface_lessons_context` to compute precision. Captured as `hook-audit-03-surface-lessons-relevance-sample` (P2).

**Pros:**
- Gives the `eval-claude-mem` evaluation a concrete baseline number.
- Validates `context-pollution.md`'s B4 finding (concept-tag false positives) with measured data.
- Cheap to start (50 samples × ~30s each ≈ 25min of manual work).

**Cons:**
- Sample size is small for a precision estimate (95% CI is wide at N=50). Could expand to 200 if the first 50 don't paint a clear picture.
- The labeling is subjective; one labeler's relevance bar may differ from another's.

**Cross-axis impact:**
- Testability, context-pollution: directly supports.
- Performance, robustness: zero direct.

**Recommendation: do, treat as a one-shot exercise.** No tooling/automation needed for now; just the labeling work and a one-paragraph result writeup. Already on backlog as P2.

### Proposal 5 — Per-section breakdown in cap validator (from robustness + testability)

**Background.** `validate-session-start-cap.sh` measures total session-start output bytes against the 10240 B harness cap. `robustness.md` and `testability.md` both recommend extending it to print per-section bytes (essential_docs / git_context / lessons / etc.). Captured as `hook-audit-03-cap-validator-breakdown` (P3).

**Pros:**
- Drift visibility — anyone making session-start grow can see exactly which section is doing the growing.
- Cross-axis leverage: robustness gets early-warning on per-section growth; performance gets per-section byte input for byte-turn projections; context-pollution gets enforcement of per-doc soft-cap policy; testability gets the data as a regression signal.
- Small change (~30 LoC).

**Cons:**
- Requires session-start to either emit section-tagged output (it already does — section banners like `=== ESSENTIAL CONTEXT ===`) OR for the validator to know where sections start and end. The first is already true; the validator just needs to parse it.

**Cross-axis impact:** High across robustness, performance, context-pollution, testability. The one validator change supports all four.

**Recommendation: do.** Highest-leverage validator extension in the category. Already on backlog.

### Proposal 6 — Per-doc soft cap for `ESSENTIAL_FULL_INJECT` (from context-pollution)

**Background.** `context-pollution.md` Finding A1 identified that `essential-preferences-communication_style` is 65% of session-start's payload and there's no per-doc cap to prevent silent growth. Captured as `hook-audit-03-essential-full-inject-discipline` (P3).

**Pros:**
- Prevents the dominant single-source concentration risk from worsening silently.
- Pairs naturally with Proposal 5 (per-section breakdown) — one validator change, two checks.
- Matches the doc-discipline pattern from other parts of the toolkit (e.g. `validate-resources-indexed.sh`).

**Cons:**
- Adds a soft-cap rule that future authors might find surprising. Mitigation: document the rule in `session-start.sh:41` above the array, AND in `relevant-toolkit-hooks.md` byte-turn subsection (Proposal 2).

**Cross-axis impact:**
- Context-pollution: directly supports.
- Performance: prevents silent byte-turn cost growth.
- Robustness: prevents silent cap-exceeded risk.

**Recommendation: do.** Already on backlog. Combine with Proposal 5 in one validator extension.

### Proposal 7 — Add `firing_rate` to `PERF-BUDGET-MS` schema (from performance)

**Background.** `performance.md` recommended a `firing_rate=session|per_call|per_event` annotation to let V20 distinguish one-shot from per-call hooks. Captured as `hook-audit-03-firing-rate-budget` (P3, idea).

**Pros:**
- Communicates intent: "this hook is structurally slower because it runs once per session" is more meaningful than "this hook has a 200ms budget."
- Future-proofs the framework for additional context-injection hooks.

**Cons:**
- New schema dimension. Not free to add.
- Today's framework doesn't act on the annotation — it's documentation-only without scaling V20's aggregate-budget logic.
- Only relevant when a second one-shot hook joins the family. Not today.

**Cross-axis impact:**
- Performance: nice-to-have.
- Others: zero.

**Recommendation: defer.** Adding it today is premature. Reopen if a second one-shot hook is added or if a consumer requests it. Captured as P3-idea; clarity confirms the defer.

### Proposal 8 — Cumulative-context-budget tracking (from performance)

**Background.** `performance.md` flagged that no toolkit-side tool tracks cumulative bytes-injected per session. Captured as `hook-audit-03-cumulative-context-budget` (P3, idea).

**Pros:**
- Would catch the cross-hook composition risk (session-start + surface-lessons combined could saturate context even when neither individually trips).
- Useful for consumers running with high-volume context injection.

**Cons:**
- Out of scope for hook-audit. Depends on the analytics ecosystem (sessions.db, hooks.db) to surface the data.
- Premature without a concrete user complaint.

**Cross-axis impact:**
- Performance: future quantification of the structural finding.
- Others: zero.

**Recommendation: defer.** Captured as P3-idea; reopen if cross-hook saturation surfaces in real sessions.

## Other clarity findings (not surfaced by other axes)

### Finding C1 — session-start's section ordering and policy is implicit

session-start.sh is a top-down script with section banners (`=== ESSENTIAL CONTEXT ===`, `=== DOCS GUIDANCE ===`, `=== GIT CONTEXT ===`, `=== TOOLKIT VERSION ===`, `=== LESSONS ===`, `=== SESSION START ===`). The order in code = the order in output = the order the model reads.

The **policy** for what gets injected and in what order is not documented anywhere. Reading the file, you can infer:
- Essential docs first (the foundation).
- Docs guidance next (a one-line nudge).
- Git context next (situational).
- Toolkit version (only on mismatch).
- Lessons (only when relevant).
- ACK at the end (deliberately, to be the last thing the model reads — survives partial truncation least).

The **acknowledgment-at-end** rationale is in a comment (`session-start.sh:274–278`). The other ordering decisions are implicit.

**Options:**
1. Add a header comment at the top of `session-start.sh` documenting the section order rationale (one paragraph).
2. Document in `relevant-toolkit-hooks.md` as part of the byte-turn framing (Proposal 2).
3. Keep as-is — the file is short enough to read and infer.

**Pros of option 1:** explicit policy readable in-place. Helps future maintainers think before adding a new section.

**Cons of option 1:** ~10 lines of new comment. Could rot.

**Pros of option 2:** centralizes the policy with the byte-turn framing. Matches "policies live in docs, code matches docs."

**Cons of option 2:** policy in a separate file from the implementation. A reader has to look up the doc.

**Recommendation: option 1 + option 2 (both).** The header comment in `session-start.sh` is short and self-documenting; the doc subsection in `relevant-toolkit-hooks.md` is the canonical reference. Same content, two places — a maintainer reading the file gets the policy in-context, and the doc reader gets the framing.

Captured as part of `hook-audit-03-document-byte-turn-framing` (no new backlog item; the work is contained within Proposal 2's doc update + a small `session-start.sh` header comment patch).

### Finding C2 — surface-lessons's relevance policy is mechanically clear, strategically opaque

The `surface-lessons.sh:56–60` comment explains the **2-hit threshold mechanism**:

> Each context word contributes at most 1 to a tag's hit count. Require >= 2 distinct context-word hits against the same tag's keywords for the tag (and its lessons) to surface. A single-word match (e.g. `reset` alone against the `git` tag) is too coincidental; two distinct tokens from a tag's vocabulary is strong evidence the command is about that domain.

This explains *what the gate does*. It does NOT explain:
- *When to tighten the gate* (e.g. should it be 3 hits?). Connect to: tag vocabulary breadth — if a tag has 10 keywords (vs `git`'s 7), 2-hit overlap becomes more probable. The threshold should perhaps scale with vocabulary size.
- *When to add a new tag*. There's a gradient between "narrow operation tag" (`git`, `permissions`) and "broad concept tag" (`pattern`, `convention`). The current vocabulary mixes both; the gate behaves differently against them. Per `context-pollution.md` B4, this is the proximate cause of false positives.
- *What happens when a tag has empty keywords*. Per `context-pollution.md` B3, half the active tags have empty keywords and silently never match. Whether this is a deliberate "disabled" pattern or a missing-data bug isn't documented.

**Options:**
1. Expand the comment to cover the strategic gates (when to tighten, when to add tags, empty-keyword semantics).
2. Document the limitations in `relevant-toolkit-lessons.md` (already covered by `hook-audit-03-document-lessons-limitations`, Proposal 3).
3. Defer — the mechanism may be replaced by `eval-claude-mem`.

**Recommendation: option 2 only.** Per the asymmetric-depth principle, expanding inline-comment policy for a mechanism that may be replaced is low-leverage. The Proposal-3 doc update is the right home: documenting *what doesn't work today* is more valuable than re-litigating the design choices.

The inline comment at `surface-lessons.sh:56–60` is fine for the **mechanism**. The **strategy** lives in the user-facing doc (Proposal 3) and the eval task's outcome.

### Finding C3 — `ESSENTIAL_FULL_INJECT` decision rule needs documentation

`session-start.sh:39–41`:

```bash
# Essentials that inject in full (tone-shaping, voice, must reach the model verbatim).
# All other essential-*.md docs surface as Quick Reference (§1) + path nudge.
ESSENTIAL_FULL_INJECT=("essential-preferences-communication_style")
```

The comment captures the rule. But:
- **Adding a doc to this array is a permanent commitment to ~3K+ B in every session.** The current array has one member (~3500 B). Adding a second of similar size pushes session-start to ~9K B — within the warn threshold.
- **The cost is paid byte-turn × N turns.** Per `performance.md`'s arithmetic, ~3500 B × 100 turns = 350K byte-turns, which is the dominant context cost from session-start.
- The current rule ("tone-shaping, voice, must reach the model verbatim") is a **good rule** — but its consequences aren't visible in the comment.

**Recommendation:** expand the comment to:

```bash
# Essentials that inject in full (tone-shaping, voice, must reach the model verbatim).
# All other essential-*.md docs surface as Quick Reference (§1) + path nudge.
#
# WARNING: Adding a doc to this array commits ~3K+ B to every session. The
# byte cost is paid every turn (model re-reads context each turn), so a 3500B
# doc costs ~350K byte-turns over a 100-turn session. Only add if (1) the
# content cannot be Quick-Reference-summarized, AND (2) the model needs the
# verbatim text continuously, not on-demand. See relevant-toolkit-hooks.md's
# "Context cost amortization" subsection.
ESSENTIAL_FULL_INJECT=("essential-preferences-communication_style")
```

Cost: ~6 lines of comment. Effect: future maintainers think before adding.

This is the inline counterpart to Proposal 6's per-doc validator soft cap. Validator catches violations; comment prevents them. Captured under the existing `hook-audit-03-essential-full-inject-discipline` (no new backlog).

### Finding C4 — surface-lessons cross-DB read isn't obvious from the surface

`surface-lessons.sh:85–102` reads from `hooks.db.surface_lessons_context` for intra-session dedup. The comment at lines 80–84 explains the why. But:
- The hook reads from **two different databases** (`lessons.db` AND `hooks.db`). That's structurally unusual.
- The dependency on the claude-sessions indexer for `hooks.db` population is mentioned in the comment ("populated by the claude-sessions indexer"), but the **failure mode** if the indexer isn't running (lessons re-surface within a session) isn't called out.
- This is one piece of `lessons-analytics-independence` (P3) — the cross-ecosystem coupling lessons-fold may want to address.

**Recommendation:** keep as-is. The comment is adequate for understanding the mechanism. The cross-ecosystem question is `lessons-analytics-independence`'s territory, not surface-lessons'.

### Finding C5 — Comment density is fine; no bloat to trim

session-start.sh: 29% comments. surface-lessons.sh: 34%. Both within the standardized-hook band. No equivalent of `02-dispatchers/clarity.md`'s "Dispatcher entrypoint header comment bloat" finding here — the comments mostly explain *why* (defensive idioms, rationale for ordering, dedup-lag tradeoff) rather than *what*. No trim recommended.

## What clarity recommends

**Do (high leverage, already on backlog):**

1. **Add per-hook `PERF-BUDGET-MS` headers** (Proposal 1). Numbers: session-start `scope_miss=200, scope_hit=300`; surface-lessons `scope_miss=20, scope_hit=60`. Stops the recurring V20 warn. Already P2 each.

2. **Document byte-turn framing + failure-mode taxonomy in `relevant-toolkit-hooks.md`** (Proposal 2 + finding C1's option 2). Single doc subsection covers the cost model, failure-mode taxonomy, and the implicit policy session-start uses for section ordering. Already P3.

3. **Document surface-lessons known limitations in `relevant-toolkit-lessons.md`** (Proposal 3 + finding C2's option 2). Captures concept-tag false positives, cross-project leakage, empty-keyword tags, hit-rate. Sets expectations; motivates `eval-claude-mem`. Already P2.

4. **Add per-section breakdown + per-doc soft cap to `validate-session-start-cap.sh`** (Proposal 5 + Proposal 6). One validator change supports four axes. Already P3 each — combine.

5. **Manually label 50 firings for relevance** (Proposal 4). Direct input to `eval-claude-mem`. Already P2.

**Do (small, opportunistic):**

6. **Expand the `ESSENTIAL_FULL_INJECT` comment in session-start.sh:39** with the byte-turn cost framing (finding C3). Inline counterpart to the validator soft-cap. ~6 lines of comment.

7. **Add a section-ordering header comment to session-start.sh** (finding C1's option 1). One paragraph. Pairs with the Proposal 2 doc update.

**Don't:**

1. Add `firing_rate` to `PERF-BUDGET-MS` schema (Proposal 7). Defer until a second one-shot hook joins.
2. Add cumulative-context-budget tracking (Proposal 8). Out of scope; defer.
3. Expand the surface-lessons inline comment with strategic policy (finding C2 option 1). Mechanism-level inline comments are right; strategy lives in user-facing docs that may be superseded by the eval outcome.
4. Trim comments. Density is fine.
5. Refactor surface-lessons' cross-DB read for clarity (finding C4). Cross-ecosystem question owned elsewhere.

## Cross-cutting findings

- **The dominant clarity question for context-injection hooks is "is the policy legible," not "is the code readable."** Both hooks have readable code. session-start's section-ordering policy and surface-lessons' relevance policy live partly in code, partly in comments, mostly in nobody's head. Documenting them is the highest-leverage clarity move.
- **Cap-validator + soft-doc-cap is the highest-leverage cross-axis change.** A single validator extension (Proposal 5 + Proposal 6) supports robustness, performance, context-pollution, and testability simultaneously. Combine into one P3 task.
- **For surface-lessons specifically, clarity work should bias toward documenting limitations rather than refining mechanism.** The `eval-claude-mem` task may replace the mechanism; documenting *what's wrong* is more durable than *how it works internally*.

## Verified findings feeding downstream axes

(All upstream axes have already been drafted; this clarity axis is the terminus. Findings here close the audit loop.)

## Confidence

- **High confidence** in the perf-budget-header recommendation. Numbers are measurement-backed; doc precedent (02-dispatchers) is solid.
- **High confidence** in the doc updates (byte-turn framing, lessons limitations). The information-to-record is concrete; the doc surface is already there.
- **High confidence** in the cap-validator extension. Small change with cross-axis leverage; no controversy.
- **High confidence** in the relevance-sample recommendation. Manual labeling is well-understood; the value to `eval-claude-mem` is clear.
- **High confidence** in the "don't" list. Each deferred item has a concrete reason (premature, out-of-scope, may-be-superseded).
- **Medium confidence** that no other clarity findings are hiding. The per-axis review covered the structural questions; if a future maintainer trips on something not surfaced here, that's a follow-up audit's job.

## Backlog tasks added (clarity-specific)

This axis adds no new backlog items. Every clarity recommendation either:
- Confirms an existing item from another axis (Proposals 1, 2, 3, 4, 5, 6).
- Lives within an existing item's scope (findings C1, C3 ride along with `hook-audit-03-document-byte-turn-framing` and `hook-audit-03-essential-full-inject-discipline`).
- Is explicitly deferred (Proposals 7, 8; findings C2's option 1, C4, C5).

**Existing items confirmed (consolidated):**

| Item | Source axis | Priority | Status |
|------|-------------|---------:|--------|
| `hook-audit-03-session-start-perf-budget` | performance | P2 | confirmed |
| `hook-audit-03-surface-lessons-perf-budget` | performance | P2 | confirmed |
| `hook-audit-03-document-byte-turn-framing` | performance + clarity | P3 | confirmed; expand to also cover failure-mode taxonomy + section-ordering policy |
| `hook-audit-03-document-lessons-limitations` | context-pollution | P2 | confirmed |
| `hook-audit-03-cap-validator-breakdown` | robustness + testability | P3 | confirmed |
| `hook-audit-03-essential-full-inject-discipline` | context-pollution | P3 | confirmed; expand to include the inline `session-start.sh:39` comment patch |
| `hook-audit-03-surface-lessons-relevance-sample` | testability | P2 | confirmed |
| `hook-audit-03-empty-keyword-tags` | context-pollution | P3 | confirmed |
| `hook-audit-03-session-start-negative-fixtures` | robustness | P3 | confirmed |
| `hook-audit-03-essential-full-inject-test` | testability | P3 | confirmed |
| `hook-audit-03-perf-session-start-variance` | testability | P3 | confirmed |
| `hook-audit-03-perf-session-start-bytes` | testability | P3 | confirmed |
| `hook-audit-03-perf-surface-lessons-bytes` | testability | P3 | confirmed |
| `hook-audit-03-perf-surface-lessons-variance` | testability | P3, idea | confirmed (defer) |
| `hook-audit-03-surface-lessons-edge-fixtures` | testability | P3 | confirmed |
| `hook-audit-03-surface-lessons-json-escape` | robustness | P3 | confirmed |
| `hook-audit-03-quickref-extract-edge-cases` | robustness | P3, watch | confirmed (watch only) |
| `hook-audit-03-firing-rate-budget` | performance | P3, idea | confirmed (defer) |
| `hook-audit-03-cumulative-context-budget` | performance | P3, idea | confirmed (defer; out-of-scope) |

## Open

- **Whether to combine the cap-validator extensions into a single PR.** Editorial. Combining `hook-audit-03-cap-validator-breakdown` and `hook-audit-03-essential-full-inject-discipline` into one PR/task is cleaner; keeping them separate respects independence. Recommend: combine. Same file, same axis of change, mutually reinforcing.

- **Whether the per-axis backlog items should be consolidated into one parent task.** 03-session-context produced ~17 backlog items (~9 P2/P3 work items + ~8 P3-ideas/watch). The 02-dispatchers audit produced fewer; the difference is the asymmetric-depth surfacing finer-grained items for surface-lessons that are intentionally small. Recommend: keep per-item; the grain is right for a future implement pass to pick from.
