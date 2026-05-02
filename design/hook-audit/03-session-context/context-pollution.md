---
category: 03-session-context
axis: context-pollution
status: drafted
date: 2026-05-02
---

# 03-session-context — context-pollution

The headline axis. **Context pollution = injecting tokens that don't earn their slot in the model's context.** Different from wall-clock cost: a 50-byte injection is fast to compute but pays its full cost on every subsequent turn it remains in context. For session-start, the payload propagates across the entire session; for surface-lessons, the injected lessons live in the conversation transcript from the matched dispatch onward.

For session-start: the question is *"is each section earning its slot?"* — tractable, measurable, mostly conservative findings.

For surface-lessons: this is the **Mega Elephant**. The relevance failure mode (lesson surfaced but not relevant) is the single biggest credibility risk for the lessons ecosystem. Empirical data in this audit shows the failure mode is not hypothetical.

**Convention** for this axis: bytes-per-injection × probability-of-firing × turns-remaining-in-context = the *amortized context cost*. A 200-byte lesson surfaced once on turn 5 of a 30-turn session pays 200 × 25 = 5000 byte-turns. Same lesson surfaced on turn 1 pays 200 × 30 = 6000. The byte-turn unit lets per-call and one-shot hooks be compared on a single axis.

## Section A — session-start

session-start runs once per session, so amortization is straightforward: every byte injected is paid **once at session start, then re-read on every subsequent turn the conversation continues**. A 5426-byte payload over a 30-turn session is ~163K byte-turns. Over a 100-turn long session, ~543K.

The audit question for each section: **does it earn its slot?** Three tests:

1. **Universally relevant?** Does every session benefit from this content (vs only some)?
2. **Cheaper alternative exists?** Could the same effect be achieved with fewer bytes (e.g. a path nudge instead of a full file)?
3. **Conditionally surface-able?** Could this be added to `ACTIONABLE_ITEMS` only when needed instead of unconditionally?

### Section-by-section evaluation

Numbers from `inventory.md`'s payload composition table. Total 5426 B; byte percentages are share of payload.

| Section | Bytes | % | Universally relevant? | Cheaper? | Conditional? | Verdict |
|---------|------:|---|----------------------|----------|--------------|---------|
| `essential-conventions-code_style` (Quick Reference §1) | ~400 | 7% | Yes — every coding session benefits | Already minimal (§1 only + path nudge) | No | **earns its slot** |
| `essential-conventions-execution` (Quick Reference §1) | ~600 | 11% | Yes — every shell-running session | Already minimal | No | **earns its slot** |
| `essential-preferences-communication_style` (full inject) | ~3500 | 65% | Yes — tone-shaping for every interaction | **Maybe.** The full file is injected because the tone-shaping needs verbatim content. But the §1 Quick Reference + a "must read full doc on first turn" pattern would save ~2000 B if the model reliably loads the rest on demand. Risk: tone drift if the rest isn't loaded. | No | **earns its slot — but the 65% byte share is a single-source concentration risk; see Finding A1 below** |
| `docs_guidance` (`/list-docs` nudge) | ~80 | 1% | Yes — guides discovery of non-essential docs | Already minimal | No | **earns its slot** |
| `git_context` (Branch + Main) | ~50 | 1% | Yes — every session has git context | Already minimal | No | **earns its slot** |
| `acknowledgment` (MANDATORY ACK) | ~150 | 3% | Yes — guarantees the model surfaces the load | Already minimal | No | **earns its slot — but see Finding A2 below** |

**Subtotal of "earns its slot" evaluations: ~4780 B (88% of payload).** No section fails the three tests outright.

### Finding A1 — Communication-style is 65% of the payload, single-source concentration

`essential-preferences-communication_style.md` is the only doc in `ESSENTIAL_FULL_INJECT` (`session-start.sh:41`). It's full-injected because:
- Tone-shaping needs verbatim content (the model reads §1 of other docs and acts on them; for tone, a Quick Reference *summary of how to talk* is paradoxical — the example phrasing IS the rule).
- Communication style is consulted continuously, not on-demand. A "Read on demand" pattern doesn't fit.

Both reasons are defensible. But:

- **The file is currently 3500 B (65% of session-start's payload).** Any growth hits the cap fast. Adding ~700 B more puts session-start at the warn threshold (9500 B); ~1700 B more puts it at fail.
- **No automated check on the file's size exists.** `validate-session-start-cap.sh` checks the *total* session-start output but not any individual section's growth. A future commit that doubles communication-style would only get caught when the *aggregate* hits 9500 B — by which time other sections' growth is also constrained.
- **The `ESSENTIAL_FULL_INJECT` array is open-ended.** A future maintainer adding a second tone-shaping doc with full inject would push the payload past the cap silently until validate runs.

Recommendations:
- Add a per-doc soft cap to `validate-session-start-cap.sh` for `ESSENTIAL_FULL_INJECT` members: warn if any single full-injected doc exceeds 4000 B. Keeps session-start's payload predictable as new tone-shaping needs surface.
- Document in `session-start.sh:41` (above the array) that adding a doc to this array commits ~3K+ B to every session forever; require a deliberate decision.

Captured as `hook-audit-03-essential-full-inject-discipline` (P3).

### Finding A2 — The MANDATORY ACK is doing two jobs

The acknowledgment block (~150 B) does two things conditionally:

```
"MANDATORY: Your FIRST message to the user MUST acknowledge: $ACK_MSG."  # always
+ "Then surface these actionable items..." + ACTIONABLE_ITEMS               # only when items exist
```

Currently `ACTIONABLE_ITEMS` is empty in the captured payload (no items firing this session), so the ACK is just the load count. But when items fire (toolkit version mismatch, lessons.db missing, opt-in nudge, settings-integrity drift, lessons.db query failure), each adds ~50–100 B of bullet lines.

The "do both jobs" shape is right: the ACK is the proof-of-load nudge, and `ACTIONABLE_ITEMS` is the actionable-state surface. Both belong at the bottom (where the model reads them last and is most likely to act). The shape is fine.

**The risk:** as the surface-lessons-fold (`surface-lessons-fold` P99) and other ecosystem changes land, the `ACTIONABLE_ITEMS` accumulator could grow. Today's ~5–6 sources are all bounded at ~50–100 B each. A future addition that pushes a 500-B notification per occurrence would silently consume the cap headroom.

Recommendation: keep as-is. Recorded as a watch-item only — if `ACTIONABLE_ITEMS` ever consumes >500 B in a single session, revisit. Not worth a backlog item today.

### Finding A3 — `docs_guidance` is one line in a section banner; could merge with ACK

The `docs_guidance` section is a single line ("Use /list-docs to discover available context...") wrapped in its own section header. ~80 B total, of which the line itself is ~70 B. The "GUIDANCE" section banner adds no information.

Options:
1. Keep as-is (one-line section, 80 B).
2. Move the line into the ACK section (saves ~10 B; minor).
3. Drop the line entirely (saves 80 B; loses the discovery nudge).

The discovery nudge is genuinely useful — `/list-docs` is the right pointer and the model needs to be told it exists. Keep the content; the section banner is editorial. Marginal save (10 B) at the cost of losing a clean section boundary in the JSONL trace and the ability to disable just this section in the future.

**Verdict: keep as-is.** Not worth touching.

### Section A summary

session-start's payload is mostly defensible. The dominant finding is **A1: single-source concentration on communication-style**. Add a soft per-doc cap to the validator to prevent silent growth into the cap.

The smaller findings (A2 watch-item, A3 don't-touch) are acknowledged but don't drive backlog work.

## Section B — surface-lessons (Mega Elephant)

The framing inverts here. Instead of "is each section earning its slot," the question is "**how often do we inject context that isn't actually relevant?**"

The relevance failure mode for surface-lessons:
- ✅ Best case: a lesson fires that's exactly on-topic for the current command. The model reads it, applies it, the operation goes well.
- ⚠️ Common case: a lesson fires whose tag matched on coincidental keyword overlap. The lesson is true and worth knowing in *some* contexts, but not this one. The model now has to weigh irrelevant guidance against the actual task.
- 🚨 Worst case: the user observes the model "acknowledging" a surfaced lesson in its reply *that has nothing to do with what they asked*. This is **the user's stated trigger** for this audit. It signals "the model is being told to think about X when X isn't the topic" — and the model performatively complies. The lesson doesn't help; it pollutes.

### B1 — Empirical hit-rate from real session data

Surface-lessons writes a `kind:context` JSONL row for **every** invocation (whether or not it surfaces lessons), via `hook_log_context` at line 136. The claude-sessions indexer projects these into `~/.claude/hooks.db.surface_lessons_context`, where each row carries `tool_name`, `keywords`, `match_count`, `matched_lesson_ids`.

Real data from the local `hooks.db` this session (17 880 invocations, claude-toolkit project + others):

| Invocations | Match count | Share |
|------------:|-------------|------:|
| 11 963 | 0 (no lessons surfaced) | 67% |
| 649 | 1 | 4% |
| 1 250 | 2 | 7% |
| 4 018 | 3 (LIMIT 3 cap hit) | 22% |

**Overall hit rate: 33.1%** (any match) — meaning roughly 1 in 3 PreToolUse(Bash|Read|Write|Edit) invocations injects at least one lesson.

By tool (same data):

| Tool | Total invocations | With matches | Hit rate |
|------|------------------:|-------------:|---------:|
| Bash | 12 202 | 5 408 | **44.3%** |
| Read | 3 106 | 358 | 11.5% |
| Edit | 2 003 | 136 | 6.8% |
| Write | 569 | 15 | 2.6% |

**Bash is by far the heaviest hitter.** That's expected (Bash commands have the highest keyword density), but 44% is high enough that lessons fire on roughly *every other* Bash command. Whether each of those firings is actually relevant is the question B2 addresses.

### B2 — Concentration of surfaced lesson combinations

Same hooks.db, the most-surfaced lesson tuples (from `matched_lesson_ids`):

| matched_lesson_ids | Total fires | Distinct sessions | Avg fires/session |
|--------------------|------------:|------------------:|------------------:|
| `bm-sop_20260116T1235_001, aws-toolkit_20260330T0103_001, claude-toolkit_20260406T1802_001` | 2 941 | 261 | ~11 |
| `claude-sessions_20260325T2216_001, bm-sop_20260116T1235_001` | 779 | (smaller) | — |
| `claude-sessions_20260325T2216_001, bm-sop_20260116T1235_001, aws-toolkit_20260330T0103_001` | 518 | (smaller) | — |
| `claude-sessions_20260325T2216_001` | 226 | — | — |
| `claude-toolkit_20260410T2115_001` | 146 | — | — |

**Important context: within-session dedup is already in place.** `surface-lessons.sh:79–102` reads `hooks.db.surface_lessons_context` to exclude lesson IDs already surfaced earlier in the same session. So the 2941 fires of the top tuple are NOT 2941 fires within one session — they're spread across **261 distinct sessions** (~11 fires per session on average). Within a single session, the same lesson surfaces roughly once and then dedup blocks repeats.

The accepted tradeoff (per the comment at `surface-lessons.sh:82–83`): the dedup table is populated by the claude-sessions indexer with ~1min lag from JSONL → DB. Within that lag window, the same lesson can re-surface — measured impact is small (the per-session avg of ~11 includes any lag-window repeats).

Three observations remain (with corrected framing):

1. **The dominant 3-lesson tuple fired in 261 distinct sessions.** Same three lessons recur across ~half the sessions in the data (sessions.db has ~490 claude-toolkit sessions; the top tuple hits 261 of them, ~53%). Within-session dedup masks the repetition; cross-session repetition is the visible pattern. Two of the three lessons are from sibling projects (`bm-sop`, `aws-toolkit`); one is from the workshop. All scope=global.
2. **The lesson texts are not project-specific.** Sample: `aws-toolkit_20260330T0103_001` is "When BACKLOG.md (or other non-code files) has pre-existing uncommitted changes at session start, ask the user how to handle them before any other work." `bm-sop_20260116T1235_001` is "User pushback is a re-investigation signal, not a defend signal." Both are universally true. They fire across 261 sessions because their keyword tags overlap with common command tokens (`backlog`, `pushback`, `convention`, `style`).
3. **The cross-project leakage is real and persists across the dedup boundary.** A lesson saved in `aws-toolkit` fires in 261 distinct claude-toolkit sessions because both lessons are scope=global and the keywords match. Within-session dedup prevents the *11th repeat in one session*; it doesn't prevent the *first surfacing in the next session*. There's no project-relevance gate beyond the scope=global vs project=X filter.

The first two observations are about the **policy** (what should fire). The third is about the **scope mechanics** (where it fires). Both contribute to the pollution problem — the within-session dedup correctly bounds the noise within a session but does nothing for the cross-session pattern.

### B3 — Tag vocabulary problems

`SELECT name, keywords FROM tags WHERE status='active'` shows the current vocabulary (15 active tags):

```
communication       |
convention          | convention,naming,style,structure,format
conventions         |
correction          | correction,mistake,wrong,error,fix
docs                |
git                 | rebase,cherry-pick,force-push,reset,--force,--no-verify,--amend
gotcha              | gotcha,trap,edge-case,surprising,unexpected
hooks               | hook,PreToolUse,PostToolUse,session-start
pattern             | pattern,approach,idiom,workflow
permissions         | permission,allowed-tools,Bash(
recurring           | recurring,repeat,again
resources           |
scripts             |
skills              | skill,/learn,/manage,SKILL.md,auto-trigger
testing             |
```

**Half the active tags have empty `keywords`.** Empty-keyword tags can never satisfy the ≥2-hit gate in `surface-lessons.sh:116` (`HAVING ($CASE_SUM) >= 2`) — they are silently dead. A lesson tagged exclusively with empty-keyword tags will never surface. Whether this is a **bug** or a **deliberately disabled tag** isn't visible from the data.

Among the populated tags:
- `git` keywords are **operations** (`rebase`, `cherry-pick`, `force-push`, `reset`, `--force`, `--no-verify`, `--amend`). These are correct — high-precision matchers for high-stakes git operations. Bash command `git rebase -i HEAD~3` will hit `rebase` + `head` (if `head` is added) or `rebase` alone (1 hit, doesn't pass threshold). The threshold is keeping the precision high here — confirmed working as designed for `git`.
- `convention` keywords are **concept words** (`convention`, `naming`, `style`, `structure`, `format`). These are **broad**. A `cd src/styles && ls` command tokenizes to `cd, src, styles, ls` — `styles` matches `style` via LIKE, but `style` alone is 1 hit. A command containing both `style` and `format` would fire (rare but possible coincidence).
- `gotcha` keywords (`gotcha`, `trap`, `edge-case`, `surprising`, `unexpected`) are **rare** — a Bash command will almost never contain "gotcha" literally. These match against lesson-text co-occurrence at `/learn` time, not user commands. **Whether they ever fire from real user commands is suspect.**
- `pattern` keywords (`pattern`, `approach`, `idiom`, `workflow`) are **medium-broad**. `pattern` and `workflow` co-occur in some commands (e.g. `git workflow ...` rare, but `make pattern-...` possible).
- `permissions` keywords include `Bash(` — a literal-paren keyword. This is **specifically targeted at command snippets that look like settings.json `permissions.allow` entries** (`Bash(git push)`, etc.). High-precision but only fires on commands that contain `Bash(` literal-string. Probably only fires on permission-related work — narrow, defensible.

**Pattern emerging:** `git`, `permissions` are *operation tags* with precise keywords. `convention`, `pattern`, `gotcha`, `correction`, `recurring` are *concept tags* whose keywords are abstract terms that can hit on coincidental token overlap.

### B4 — The 2-hit gate fights the right battle but loses to broad tags

The `surface-lessons.sh:56–60` comment explains the 2-hit gate:

> Each context word contributes at most 1 to a tag's hit count. Require >= 2 distinct context-word hits against the same tag's keywords for the tag (and its lessons) to surface. A single-word match (e.g. `reset` alone against the `git` tag) is too coincidental; two distinct tokens from a tag's vocabulary is strong evidence the command is about that domain.

This is **the right gate for operation tags**. `git rebase --force` hits `rebase` + `--force` → 2 hits → fires the `git` tag → surfaces git-rebase lessons. Good.

For **concept tags**, the same gate is much weaker. `convention` has 5 keywords; any 2 word matches (out of 5 abstract terms) fires it. A command like `find . -name "*.naming-convention" -type f` would hit `naming` + `convention` → 2 hits → fires the `convention` tag → surfaces *whatever lessons happen to be tagged* `convention`. Those lessons are about coding-style conventions, not file naming. The gate fired, the relevance failed.

The 2-hit gate is a vocabulary-coverage proxy for "the command is about this topic." For tags whose vocabulary is **operationally specific** (git operations, hook event names), it works. For tags whose vocabulary is **conceptually broad** (`convention`, `pattern`, `gotcha`), it doesn't — the words are common enough that 2-hit overlap is structural rather than topical.

**This is the proximate cause of the user's "lesson acknowledged but not relevant" experience.** When a `convention` lesson fires on a command that happened to contain `style` and `format`, the model sees `Relevant lessons: - <some convention lesson>` and performatively acknowledges it. The lesson is true; it's just not what the user asked about.

### B5 — Cross-project global lessons amplify the problem

From B2, the dominant 3-lesson tuple is two cross-project lessons (`aws-toolkit`, `bm-sop`) plus one workshop lesson. All scope=global.

`scope=global` means "this lesson applies regardless of project." For the **content** of these specific lessons (e.g. "user pushback is a re-investigation signal"), `global` is correct — the lesson is genuinely cross-cutting.

But the **keyword tags they're attached to** are not constrained to the originating project. A lesson saved in `aws-toolkit` with the `convention` tag fires on `convention`-keyword matches *anywhere*. The lesson doesn't know "this fired on a claude-toolkit command" — only the dispatcher does.

There's no current mechanism to weight lessons by **how often they've fired in this project** vs others, or to surface project-local lessons preferentially over global ones. The current SQL query treats them uniformly:

```sql
WHERE l.active = 1
  AND (l.scope = 'global' OR (l.scope = 'project' AND l.project_id = '${SAFE_PROJECT}'))
```

A workshop session and a satellite session see the same global lessons mixed with the same noise level.

### B6 — Why this doesn't justify a refactor today

The handoff explicitly framed surface-lessons' audit as **light-touch** because:
- `eval-claude-mem` (P1, backlog) is queued to evaluate two external systems (claude-mem, agentmemory) that have completely different relevance/retrieval models — vector search, LLM-summarized observations, hybrid BM25+vector, knowledge graphs. Either could replace the current tag-keyword mechanism wholesale.
- `surface-lessons-fold` (P99, backlog) is queued to fold the bash branch into `grouped-bash-guard.sh`, but only after re-measuring the perf baseline.
- `lessons-analytics-independence` (P3, backlog) is queued to evaluate whether the lessons ecosystem should be decoupled from the analytics ecosystem at all.

A refactor that improves keyword discipline today (e.g. adding a third hit threshold, dropping concept tags, weighting by project-firing-history) **may be obsoleted by claude-mem evaluation in one cycle**. The right move is to **document the failure modes** so the eval task has concrete data to measure against, not to fix the current mechanism.

What we have to record:
1. Empirical hit-rate (33.1% overall, 44% on Bash) — for any future system to compare against. A replacement that fires only when meaningfully relevant should hit substantially less often than this.
2. Concentration profile (top 3-tuple fires 2941 times) — a target to beat. A relevance-aware system should NOT surface the same lessons 2941 times unless they're genuinely re-applicable to 2941 distinct contexts.
3. Tag vocabulary quality (half empty, others mixed precision/concept) — separable from the retrieval mechanism. A future system might or might not use tags; the data shape is informative either way.
4. Cross-project leakage (top lessons are sibling-project globals) — if the future system has a project-relevance dimension, this is the case to evaluate against.

### B7 — Recommendations for the queued evaluation

For the `eval-claude-mem` task, this audit contributes:

**Inputs to feed the evaluation:**
- The hit-rate numbers (B1) as a baseline. Any replacement system that injects lessons more frequently than 33% on PreToolUse(Bash) needs to clear a higher relevance bar to justify the volume.
- The concentration profile (B2) as a regression check. If a replacement system surfaces a small fixed set of lessons disproportionately, that's the same failure mode in a new wrapper.
- The cross-project leakage observation (B5) as a scope-design constraint. Whatever replaces this should have a project-weighting model — global lessons are real, but a sibling project's local lessons should not dominate the workshop's invocations.

**What this audit explicitly does NOT recommend (because of B6):**
- Don't add a 3-hit threshold or drop concept tags today. The mechanism may be replaced.
- Don't rebuild the tag vocabulary. Same.
- Don't optimize the SQL or add an index. The query is fast enough; the issue is *what it returns*, not how fast.

**What this audit recommends doing now (independent of the eval outcome):**

- **Add a "is this lesson currently helpful?" signal capture.** Today there's no feedback loop on whether an injected lesson was useful. A lightweight ack-vs-ignore signal (hard to design without polluting context further) would be invaluable for any future relevance-tuning work.
- **Document the failure modes in `relevant-toolkit-lessons.md`.** The tag/keyword/2-hit policy is in code comments at `surface-lessons.sh:56–60`, but the *known failure modes* (concept-tag false positives, cross-project leakage on globals) are not in the user-facing doc. Adding a "Known limitations" subsection would set expectations and motivate the eval task.

Captured as `hook-audit-03-document-lessons-limitations` (P2) — this is the only direct surface-lessons backlog item this audit adds. Both the data-collection improvement and the doc update are independent of whatever the `eval-claude-mem` evaluation ultimately recommends.

### Section B summary

The Mega Elephant is real, and the data confirms it:

- 33% of PreToolUse(Bash|Read|Write|Edit) invocations inject at least one lesson.
- The same 3-lesson tuple has been surfaced across 261 distinct sessions (~53% of all claude-toolkit sessions in the data). Within-session dedup correctly bounds repetition inside a session; cross-session recurrence is the visible pattern.
- Half the active tags can never match (empty keywords).
- Concept tags (`convention`, `pattern`, `gotcha`) reach the 2-hit threshold via coincidental token overlap, producing false-positive injections.

The right next step is the queued `eval-claude-mem` evaluation, not a tactical fix to the current mechanism. This audit provides the empirical data the evaluation needs.

## Cross-cutting findings

- **Context cost is a real axis that this audit framework didn't have until now.** The 02-dispatchers framework measured wall-clock and decision correctness; the per-turn token amortization didn't apply because dispatcher injections are scoped to the dispatch decision (block/allow). For 03, every byte injected lives until session end. Future audits of context-injection hooks should adopt this axis directly.
- **session-start's pollution risk is concentration (one doc is 65% of payload).** A change to that doc has outsized impact. Worth a per-doc soft cap.
- **surface-lessons' pollution risk is precision (33% fire rate, of which an unknown fraction are false-positive).** Within-session dedup is in place and bounds intra-session repetition; the unfixed problem is **cross-session recurrence of low-precision matches** + the false-positive fraction of any given fire. The cumulative effect is what users notice ("acknowledged but not relevant"). A relevance-aware retrieval system is the long-term fix; documenting the known limitations is the right immediate move.
- **The two hooks' pollution risks don't compose linearly.** session-start's payload is paid once × N turns. surface-lessons' is paid M times × (N − M_first) turns. Together they could conceivably saturate a long session's context with low-relevance content even if neither individually trips a budget.

## Verified findings feeding downstream axes

### Performance

- The byte-turn amortization model from this axis is the input the perf axis needs to build the **two-budget framing**. A 5426-byte session-start payload at ~30 turns is ~163K byte-turns of context cost — that's the recurring side that pairs with the one-shot 136ms wall-clock.
- For surface-lessons, the per-call wall-clock (~50ms when matching) is paid each invocation; the byte-turn cost is paid (lesson_text_bytes × turns_remaining) per matched dispatch. A typical fire of 3 lessons × ~200 B = 600 B injected at turn k of an N-turn session pays 600 × (N−k) byte-turns. Over a Bash-heavy session with 50 dispatches and 44% hit rate (22 fires), that's potentially ~13K bytes of cumulative pollution — same order of magnitude as session-start's payload.

### Robustness

- Pollution-axis findings aren't robustness in the fail-closed/open sense — they're correctness-of-relevance failures. The robustness axis covers the orthogonal "what happens when this hook fails entirely" — but the failure modes here suggest a new category for context-injection hooks: **silent miscalibration** (the hook didn't fail, it just produced low-quality output). Worth surfacing in `robustness.md`.

### Testability

- Relevance is hard to test automatically. But the **hit-rate** (B1) and **concentration profile** (B2) are observable from the existing `surface-lessons-context.jsonl` indexed via claude-sessions. The testability axis can record this as an *available signal that's not currently tracked* in any test.
- For session-start, the **per-section byte share** (Section A table) is a tractable test: warn if any single section's byte share exceeds 70% of payload. Could be a small extension to `validate-session-start-cap.sh`. Captured for testability.md to evaluate.

### Clarity

- The **policy** for what session-start injects is implicit (the order of code in the file = the order of sections in the output). Making that policy explicit — even as a one-paragraph header in the hook — would help readers reason about whether to add a new section.
- The **policy** for what surface-lessons injects is explicit-in-code (the SQL + comment at lines 56–60). The known limitations from B3/B4 are NOT in the code or in any doc. Making them explicit is the `hook-audit-03-document-lessons-limitations` recommendation.
- The **scope mechanics** for global vs project lessons are buried in a single SQL clause. Whether `global` should mean "applies to all projects" or "applies to the originating project + opt-in to others" is a policy choice that the current code makes implicitly. Worth surfacing in `clarity.md`.

## Confidence

- **High confidence** in Section A findings — payload composition is measured directly, byte percentages are arithmetic, the per-doc concentration is observable from the file sizes.
- **High confidence** in Section B's empirical numbers — they come from the live `~/.claude/hooks.db.surface_lessons_context` table with 17 880 invocations of real signal. The hit rate, tool-level breakdown, and concentration profile are direct queries.
- **Medium-high confidence** in the relevance-failure attribution (B4 — concept tags causing false positives). The mechanism is mechanically clear (2-hit threshold + abstract keyword vocabulary), but the *fraction* of injections that are false-positive isn't directly measured. A future relevance-labeled sample would tighten this.
- **High confidence** in the recommendation to defer mechanism-level changes until the eval-claude-mem outcome (B6). The backlog already queues the evaluation; this audit would create churn to fix something that may be replaced.

## Open

- **No relevance metric exists.** Hit rate is observable; relevance hit rate (was the lesson actually useful for the operation that fired it) is not. Building a relevance signal without polluting context further is itself a design problem. The eval-claude-mem evaluation should treat "ability to measure relevance" as an evaluation criterion.
- **Cross-project leakage may be a feature, not a bug.** Some global lessons (e.g. "user pushback is a re-investigation signal") legitimately apply across all projects. A naive project-scoping rule would lose those. The right mechanism may be per-tag scoping (the tag, not the lesson, is project-scoped) or a recency-weighted firing-history damper (lessons that have already fired N times in this project deprioritize). Falls to the eval task.
- **Empty-keyword tags.** Half the active tags have no keywords. Whether they're deliberately disabled or accidentally orphaned isn't visible from the audit. Recorded as `hook-audit-03-empty-keyword-tags` (P3) — investigate and either populate, deactivate, or document the convention.

## Backlog tasks added

- `hook-audit-03-document-lessons-limitations` (P2) — add a "Known limitations" subsection to `relevant-toolkit-lessons.md` documenting concept-tag false positives, cross-project leakage on globals, and empty-keyword tags. Aimed at setting expectations and motivating the eval task.
- `hook-audit-03-essential-full-inject-discipline` (P3) — add a per-doc soft cap to `validate-session-start-cap.sh` for `ESSENTIAL_FULL_INJECT` members; document the discipline in `session-start.sh:41`.
- `hook-audit-03-empty-keyword-tags` (P3) — investigate the half-empty tag vocabulary; populate, deactivate, or document.

Existing items confirmed (not duplicated):

- `eval-claude-mem` (P1) — the queued evaluation. This audit's data feeds it.
- `surface-lessons-fold` (P99) — perf-only fold, gated on re-measurement. This audit's findings don't change that work's scope.
- `lessons-analytics-independence` (P3) — separate ecosystem question.
