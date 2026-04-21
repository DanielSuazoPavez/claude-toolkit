# v3 Audit — `.claude/agents/`

Exhaustive file-level audit of the `.claude/agents/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Summary

`.claude/agents/` holds 7 agents. They split cleanly across four roles (per identity doc §4 mapping: *"Agent — specialized subtasks, often parallelizable"*):

- **Codebase analysis:** `codebase-explorer`, `pattern-finder`
- **Code quality:** `code-reviewer`, `code-debugger`
- **Document review:** `proposal-reviewer`
- **Verification:** `goal-verifier`, `implementation-checker`

All 7 follow the `context-role` naming convention (`relevant-conventions-naming.md` §4). Workshop-shaped by construction: each agent runs as a subagent inside the user's session, does a bounded task, writes a report to `output/claude-toolkit/reviews/` (or similar), and returns. None reach across projects. No `permissionMode`, `skills` preload, `mcpServers`, or `hooks` declared — frontmatter is clean and minimal.

Distribution-wise: base ships all 7; raiz ships only 5 (excludes `pattern-finder` and `proposal-reviewer`). This is already the status quo — not a new exclusion.

**Three classes of finding** emerge from the walk:

1. **Model / effort drift vs `relevant-toolkit-resource_frontmatter.md` §5.** The doc names `code-reviewer` and `implementation-checker` as **sonnet** work (structured checklists); both currently run **opus**. Separately, `proposal-reviewer` runs `effort: medium` but the reads-as-audience protocol needs deeper reasoning — should be `effort: high`. Three one-line frontmatter fixes.

2. **Path/namespace drift.** `code-debugger` writes persistent debug state under `output/claude-toolkit/reviews/` — but those aren't reviews, they're resume-artifacts, and should live under a dedicated `debug/` namespace. `codebase-explorer` writes to `.claude/docs/codebase-explorer/{version}/` — syncs into consumer agent-context, which is wrong for generated snapshots; should be `output/claude-toolkit/codebase/{version}/`. Both fixes coordinate with `docs/indexes/AGENTS.md` updates.

3. **Shape / role questions needing investigation.** `code-debugger` has `Edit` in its tools allowlist and a prompt written to apply fixes — user call is to make it report-only (recommended fix + verification plan, no mutation). `pattern-finder` overlaps the base `Explore` agent — usage-frequency diagnostic before deciding tweak vs deprecate. `goal-verifier` has been producing fewer findings recently — diagnostic on recent reports before deciding whether it's usage drop or prompt drift. `codebase-explorer` may be better shaped as a skill (`/codebase-explorer tech|arch`) with `context: fork` — independent of its path fix.

Findings below: 5 `Rewrite`, 2 `Investigate`, 0 `Keep`. Every agent takes some polish. None of these are v3-reshape-gated — they're normal polish items that get scheduled like any backlog work.

---

## Files

### `code-debugger.md`

- **Tag:** `Rewrite`
- **Finding:** Solid agent. `opus` + `effort: high` is correct per §5 (nuanced hypothesis testing). Protocol is strong: persistent debug-state file that survives context resets, explicit cascading-fixes checkpoint, mandatory evidence log. Meta-debugging principle ("treat your own code as foreign") is the kind of behavioral nudge that only lands at opus.

  Two calls, both resolved:

  1. **Path namespace mismatch.** Debug state is written to `output/claude-toolkit/reviews/{YYYYMMDD}_{HHMM}__code-debugger__{slug}.md` (line 33). But debug session files aren't *reviews* — they're persistent debug-state. They're read-first-on-resume artifacts, not one-shot reports. Cohabiting with code-reviewer/goal-verifier/implementation-checker reports under `reviews/` makes resume-discovery (line 78: *"Check for existing debug session in `output/claude-toolkit/reviews/` — look for `__code-debugger__` in filename"*) work by string search, which is brittle. Move to `output/claude-toolkit/debug/` (or similar dedicated namespace). Aligns with the existing namespace structure (`sessions/`, `plans/`, `reviews/`, `drafts/`, etc.).

  2. **`Edit` should be removed from tools.** Currently `tools: Read, Write, Edit, Bash, Grep, Glob`. **User confirmed:** this agent should report, not fix. Drop `Edit`. Pattern becomes: debugger investigates, writes root-cause + recommended fix into its debug-state file, returns — the user (or a subsequent skill/session) applies the fix. Matches the reporter-not-decider shape of every other agent in the directory.

- **Action:** at decision point: (1) remove `Edit` from `tools:` allowlist; reframe Fix Attempts / Resolution sections of the protocol as "recommended fix + verification plan" rather than "apply and verify," (2) move debug-session path to `output/claude-toolkit/debug/`, update resume-discovery reference, (3) grep consumers for old path.
- **Scope:** (1) small but requires a prompt-body pass (Execution Flow step 6, Output Format, examples) so the agent doesn't still *think* it applies fixes. (2) trivial — 2-line change. (3) grep.

### `code-reviewer.md`

- **Tag:** `Rewrite`
- **Finding:** Excellent agent: the "mechanic, not inspector" voice is well-calibrated, the write-findings-as-you-go rule (line 23) is a guardrail against hold-in-memory failure modes, and the phase skeleton (Phase 0 writes the report shell first, each phase updates it) is a genuine improvement over ask-then-dump.

  **Model drift.** Frontmatter declares `model: opus` + `effort: high`. `relevant-toolkit-resource_frontmatter.md` §5 explicitly names `code-reviewer` in the **sonnet** row (*"Structured search, comparison, checklist work, pattern matching"*). The agent's entire protocol is checklist-shaped: per-file diff read, risk-category bucketing, calibration questions applied systematically. That's sonnet work. Running opus for it is overkill and inconsistent with the canon doc.

  *Speculation on why it drifted:* opus may have been chosen for the "proportionality" calibration (startup vs FAANG judgment). But proportionality is a rule encoded in the prompt, not a cognitive task — the agent doesn't have to *derive* it at runtime. Sonnet can execute "apply this rule" just fine.

  **User confirmed:** flip to sonnet; aligns with the index. Reversion trigger is explicit — *"if findings quality drops on real projects, flip back to opus."* No time-boxed validation, but the downgrade is reversible at any point with a 1-line change.

- **Action:** at decision point: change `model: opus` → `model: sonnet`. Keep `effort: high` (sonnet + high is meaningful; the checklist isn't trivial). Watch findings quality on the next 2-3 real code reviews; revert if signal degrades.
- **Scope:** 1-line frontmatter change.

### `codebase-explorer.md`

- **Tag:** `Rewrite`
- **Finding:** Clean as a *behavior spec*: model `sonnet` matches §5, "document don't judge" principle is well-separated from pattern-finder (catalogs) and code-reviewer (assesses), `[HIGH]`/`[MEDIUM]`/`[LOW]` confidence-indicator scheme is a nice touch, Bash boundary explicitly limited to "inspect manifests and dynamic configs" — proper guardrail.

  **But this might be a skill, not an agent.** User observation, well-supported by reading the file:

  - Invocation pattern is skill-shaped: *"Invoke with a focus area: `tech` or `arch`"* (line 33-35). That's `/codebase-explorer tech` or `/codebase-explorer arch` — argument-driven, not a delegation Claude reasons about. Compare to other agents' descriptions: `code-debugger` ("when stuck on an issue"), `goal-verifier` ("after completing a feature"). Those are routing prompts. Codebase-explorer's description is "do this with this argument."
  - It's deterministic: same project state in → same documents out. No nuanced judgment. Skill-shaped task.
  - The reasons to be an *agent* are spawn-in-fresh-context (full context to itself) and parallelization (run tech + arch concurrently). Both are real, but they're skill-via-`context: fork` territory now (per `relevant-toolkit-resource_frontmatter.md` §2 — skills can run in a forked subagent context).

  **Two path-drift concerns** (independent of the skill-vs-agent question):

  1. **Output directory is `.claude/docs/codebase-explorer/{version}/`** (lines 3, 47). The agent writes *generated analysis*, not hand-authored docs. Putting it under `.claude/docs/` means it ships to every consumer's `.claude/docs/` and becomes agent-context for their sessions (per CLAUDE.md: *"`.claude/docs/` stays inside `.claude/` (agent context — loaded by session-start, referenced by skills)"*). A toolkit-specific codebase map should NOT be agent-context for consumer projects.
  2. **`AGENTS.md` index drift.** `docs/indexes/AGENTS.md` line 9 says codebase-explorer writes to `output/claude-toolkit/reviews/codebase/`. The agent file says `.claude/docs/codebase-explorer/{version}/`. Two canonical paths, neither referenced by the other.

  **User call on output:** *"track codebase-explorer outputs as snapshots of the codebase for the specific version."* That's the framing — it's a versioned snapshot, not a doc. So:
  - Path: `output/claude-toolkit/codebase/{version}/STACK.md` (etc.). `output/` is the right namespace (generated artifact); `codebase/` is a new sibling to `reviews/`, `plans/`, `sessions/`; `{version}` is the snapshot key. Agent-version-detected, not toolkit-version.
  - Cohabits with the version it documents. Old snapshots stay around as history (small enough — text only).
  - Doesn't sync. Doesn't pollute consumer agent-context. CLAUDE.md orientation block updates to point at the new path.

  **Secondary call:** the skill-vs-agent reshape is a separate design call — not blocking the path fix. Path drift gets fixed now; the resource-type question is queued as its own action.

- **Action:** at decision point: (1) move output to `output/claude-toolkit/codebase/{version}/`, (2) update agent file (description + Output Directory section + Output examples) + `docs/indexes/AGENTS.md` + `CLAUDE.md` line 75 together, (3) if any existing generated files exist at the old path, migrate them, (4) evaluate skill-vs-agent reshape — likely a `/codebase-explorer tech|arch` skill with `context: fork` for the spawn-in-fresh-context benefit. Independent of (1)-(3).
- **Scope:** (1)-(3) small coordinated edit. (4) small-moderate — skill rewrite + frontmatter, preserving behavior.

### `goal-verifier.md`

- **Tag:** `Investigate`
- **Finding:** Detailed and opinionated protocol — L1/L2/L3 verification levels, mandatory Devil's Advocate, mandatory Negative Cases. `model: opus` + `effort: high` is correct per §5 (nuanced judgment about *whether work is actually done*, not just whether tasks are checked off). The "verification ≠ confirmation" corollary (line 20) is exactly the failure mode this agent is designed to prevent.

  **Live concern: findings quality has dropped.** User observation: *"recently just not detecting anything. might be we call it less, or that the instructions are not 'pushing it enough to find gaps'."* Two hypotheses, both plausible:

  1. **Usage drop → selection bias.** If it's only being invoked on clean work (after the user is already confident), the base rate of findings drops naturally. Not a prompt problem.
  2. **Prompt-push dilution.** The Devil's Advocate + Negative Cases sections were added to reduce false-green rate (per the `experimental` note in the index). The sections are *structurally* present, but the prompt might not push hard enough on "you MUST find at least one thing the developer didn't think of" — the corollary at line 19-20 says this, but it's stated as a principle, not as a procedural rule that gates the Final phase.

  Reading the prompt more carefully, the "bar" for Devil's Advocate is line 104: *"If you can't find anything wrong after genuine effort, say so explicitly — but 'I tried and found nothing' is different from not trying. The report must show the attempt."* That's an escape hatch. A motivated-to-be-helpful sonnet or opus can legitimately say "I tried and found nothing" every time — it's compliant with the prompt.

  **Diagnostic step before rewriting:** pull last 5-10 goal-verifier reports from `output/claude-toolkit/reviews/` and check (a) how many have PASS vs PARTIAL vs FAIL, (b) how many Devil's Advocate sections escalated something vs disproved all three, (c) sample size is small but enough to distinguish "usage is low" from "it's finding nothing when it runs." If usage is just low, there's no prompt problem. If it's running and not finding, tighten the Final-phase gate: require the report to either escalate at least one Devil's Advocate scenario to a gap OR explicitly note "all three scenarios disproven by evidence X, Y, Z" — the escape hatch gets harder to take without showing work.

  Separately, graduate from `experimental` to `stable` in `docs/indexes/AGENTS.md`. The restore-to-commit escape hatch has served its purpose; experiment isn't rolled back. That's independent of the findings-quality call.

- **Action:** at decision point: (1) pull recent goal-verifier reports from `output/claude-toolkit/reviews/`, count pass/partial/fail + Devil's Advocate escalation rate, decide whether it's usage drop or prompt drift, (2) if prompt drift — tighten the Final-phase gate so "I tried and found nothing" requires per-scenario disproof-by-evidence, (3) graduate `AGENTS.md` entry from `experimental` to `stable`, drop the restore-to-commit note (this is independent and can ship regardless of the diagnostic).
- **Scope:** (1) small data pull + read ~5-10 files. (2) 5-10 line prompt edit if warranted. (3) trivial one-line index update.

### `implementation-checker.md`

- **Tag:** `Rewrite`
- **Finding:** Strong protocol: skeleton-first, per-checklist-item diff reads (line 46: *"Do NOT read the full diff. Only diff the paths relevant to the current checklist item"*) — that's exactly the right efficiency-conscious shape. Scope-and-stance section explicitly scopes out code quality (that's code-reviewer) — good separation.

  **Model drift.** Declares `model: opus` + `effort: high`. Canon §5 names `implementation-checker` in the **sonnet** row. And the protocol is structured-checklist work end-to-end: read plan, derive checklist, per-item diff read, per-item status assignment, populate table. Zero creative reasoning. This is the textbook sonnet case.

  **User confirmed:** move to sonnet. Same reversion trigger as code-reviewer — flip back to opus if findings quality degrades on real plan reviews.

  Secondary: both this agent (line 29) and goal-verifier reference `output/claude-toolkit/plans/` for planning-doc reads. The v3 audit docs live in `planning/v3-audit/` (a different directory). **Reference convention drift.** The `planning/` directory exists and is current; the `output/claude-toolkit/plans/` directory also exists (confirmed: both present). Two plan homes is itself a finding — carry forward.

- **Action:** at decision point: (1) change `model: opus` → `sonnet`, (2) coordinate the plans-directory question (`planning/` vs `output/claude-toolkit/plans/`) across implementation-checker, goal-verifier, and any skill that writes/reads plans.
- **Scope:** (1) 1-line frontmatter. (2) moderate — depends on how much has been written to each.

### `pattern-finder.md`

- **Tag:** `Investigate`
- **Finding:** The "pattern librarian" role *in principle* is distinct from codebase-explorer (maps architecture) and code-reviewer (assesses quality). Small agent, tight protocol: find 2-3 examples, include file:line references, no critique. `model: sonnet` matches §5. `What I Don't Do` section is the right shape — explicitly scoping out opinion.

  **Overlap with the base `Explore` agent.** User call: *"fights with the base Explore agent. can't say if it's really worth keeping, might need some tweaks or deprecation."* Reading the Explore description: *"Fast agent specialized for exploring codebases. Use this when you need to quickly find files by patterns, search code for keywords, or answer questions about the codebase."* The overlap is real:

  - Both answer "how is X done in this codebase?"
  - Explore is Anthropic-maintained, always present, fast, tuned for keyword/pattern search.
  - pattern-finder adds: structured output (Pattern / Location / Code / Key Aspects / Also Used In), explicit "no critique" scoping, a librarian voice.

  The structured-output format is the genuine differentiator — Explore returns freeform, pattern-finder returns a catalog. For someone who wants "give me 2-3 examples with file:line" as a reusable artifact, pattern-finder's shape is better. For "find me something in the codebase," Explore wins on speed.

  Three directions, each defensible:

  - **Deprecate pattern-finder.** If the structured output isn't being used enough to earn context cost, drop it; consumers can always ask Explore + "return in this format." Raiz already omits it, which suggests it's not load-bearing.
  - **Tweak to sharpen the difference.** Reframe description to emphasize *"structured cataloging of repeated patterns (not quick code search — use Explore for that)"*. Currently the description overlaps Explore's territory; a clearer anti-Explore framing would help Claude route correctly.
  - **Status quo.** Keep as-is, accept the overlap. Low cost since it's small.

  No data this session on how often pattern-finder has been invoked — that's the diagnostic before deciding. Usage-frequency check is the cheapest way to resolve: if pattern-finder has been called ≥3 times in the last month and produced useful output, sharpen it; if ≤1, deprecate.

  Distribution note: not in raiz MANIFEST (base only). Consistent with the call above — raiz already voted with its feet.

- **Action:** at decision point: (1) check invocation frequency (session logs / transcript grep), (2) if kept: rewrite description to emphasize structured-cataloging-not-search (anti-Explore framing), (3) if deprecated: remove file, remove from `docs/indexes/AGENTS.md`, grep consumers (skills like `/analyze-idea` reference it — line 11 of `analyze-idea/SKILL.md`).
- **Scope:** (1) small log query. (2) 2-line description rewrite + maybe a "vs Explore" note in the body. (3) small deletion + index update + ~1-2 skill updates.

### `proposal-reviewer.md`

- **Tag:** `Rewrite`
- **Finding:** Tight and well-scoped. `model: opus` matches §5 (*"opus for nuanced judgment, proposal-reviewer"*). The reads-as-audience protocol is exactly the right frame — it tests framing-vs-delivery consistency, which is inherently nuanced judgment. Automatic-fail triggers (line 69-73: no framing block, dismissive language, >3 unearned certainties, tone shift) are well-chosen.

  **User call:** `effort: medium` should bump to `effort: high`. Rationale: the work this agent does is spotting blind spots in a document the author has already iterated on — the cases where a `medium`-effort pass returns "looks fine" are precisely the cases where a `high`-effort pass would catch the subtle framing mismatch or the unacknowledged scope creep. Reading as the target audience requires perspective-shifting, and the quality of that shift scales with reasoning depth. Bumping to `high` matches how this agent is actually used (infrequently, on real proposals, where quality matters more than latency).

  `What I Don't Do` correctly carves this out from `shape-proposal` (structural) and `code-reviewer` (code). Clean boundaries. Tools list is `Read, Write` only — correct per user call: *"the tools are ok, its not about 'features for an ongoing project'."* Single-doc review doesn't need Grep/Glob/Bash. Leave as-is.

  Distribution: not in raiz (base only). Proposal-review isn't a raiz-relevant workflow. Correct as-is.

- **Action:** at decision point: change `effort: medium` → `effort: high`.
- **Scope:** 1-line frontmatter change.

---

## Cross-cutting notes

- **Model-assignment drift is the main finding.** Two agents (`code-reviewer`, `implementation-checker`) run opus despite the canon doc (`relevant-toolkit-resource_frontmatter.md` §5) explicitly naming them as sonnet work. Checklist/diff/compare is sonnet work; opus is overkill. One coordinated fix: flip both to sonnet, validate in real sessions before landing.

- **Frontmatter hygiene is clean across the board.** No `permissionMode`, no `skills` preload, no `mcpServers`, no per-agent `hooks`. No `bypassPermissions` red flags. Tool allowlists are tight and match the agent's role — only `code-debugger` gets `Edit` (correct, it applies fixes); rest are read-only or Write-to-reports-only.

- **`AGENTS.md` index has three drift points.** (1) `codebase-explorer` output-path references are inconsistent between agent file, index, and CLAUDE.md orientation block. (2) `goal-verifier` still marked `experimental` with a restore-to-commit escape hatch that's no longer needed. (3) All entries have `tools:` column that could drift from the actual frontmatter over time — not currently drifted, but there's no validator. Feed to the docs-index audit queue (coordinates with similar drift flagged in `.claude/docs/` and `.claude/hooks/` audits).

- **Two different "plans" directories.** `planning/v3-audit/` (this audit's home) vs `output/claude-toolkit/plans/` (referenced by `implementation-checker` + `goal-verifier`). Both exist in the working tree. Consolidation call needed: is `planning/` the ongoing home, or was it v3-audit-specific and plans should land in `output/claude-toolkit/plans/`? Flagged as a cross-audit item.

- **Path-namespace drift: `code-debugger` debug state.** Written to `output/claude-toolkit/reviews/`, but it isn't a review — it's persistent debug state with a resume contract. Should live under a dedicated namespace (e.g., `output/claude-toolkit/debug/`). Feeds into the `output/claude-toolkit/` audit queue which already has directory-structure calls.

- **Raiz subset is intentional, not excluded.** `pattern-finder` and `proposal-reviewer` are in base but not raiz. They're not in `dist/base/EXCLUDE` either — which is correct: EXCLUDE is for sync-nothing resources. Raiz's subset is driven by its own MANIFEST, which cherry-picks. This pattern is fine; just noting that it's distinct from the EXCLUDE mechanism. No action.

---

## Decision-point queue (carry forward)

Every item below is a real work item. None are blocked behind the v3 reshape — they're just audit-surfaced issues that get scheduled against the normal backlog like anything else.

**Resolved during review (pending execution — trivial/small scope):**

1. `code-reviewer.md` — **`model: opus` → `sonnet`**. Reversion trigger: flip back if findings quality degrades on 2-3 real reviews. One-line frontmatter change.
2. `implementation-checker.md` — **`model: opus` → `sonnet`**. Same reversion trigger. One-line frontmatter change.
3. `proposal-reviewer.md` — **`effort: medium` → `effort: high`**. Matches how this agent is actually used. One-line frontmatter change.
4. `code-debugger.md` — **remove `Edit` from tools**; reframe Fix Attempts / Resolution sections as "recommended fix + verification plan" rather than "apply and verify." Report, don't fix. Requires prompt-body pass so the agent doesn't still *think* it applies fixes.
5. `code-debugger.md` — **move debug-state path from `output/claude-toolkit/reviews/` to `output/claude-toolkit/debug/`** (dedicated namespace for persistent state, distinct from one-shot reports). Update resume-discovery reference. Grep consumers.
6. `codebase-explorer.md` — **move output to `output/claude-toolkit/codebase/{version}/`** (versioned codebase snapshots). Coordinated update: agent file + `docs/indexes/AGENTS.md` + `CLAUDE.md` line 75.
7. `docs/indexes/AGENTS.md` — **graduate `goal-verifier` from `experimental` to `stable`**; drop the "Restore to `245dba0`" note. Independent of the findings-quality diagnostic (item 9). Trivial.

**Resolved during review (pending execution — moderate scope / needs investigation step first):**

8. `pattern-finder.md` — **diagnostic first:** check invocation frequency. Then decide between (a) deprecate (remove file, update `docs/indexes/AGENTS.md`, update `analyze-idea/SKILL.md` line 11), (b) sharpen description to anti-Explore framing, or (c) status quo. User-framed as "tweaks or deprecation."
9. `goal-verifier.md` — **diagnostic first:** pull last 5-10 reports from `output/claude-toolkit/reviews/`, count PASS/PARTIAL/FAIL + Devil's Advocate escalation rate. Distinguishes usage drop from prompt drift. If prompt drift → tighten the Final-phase gate so "I tried and found nothing" requires per-scenario disproof-by-evidence.
10. `codebase-explorer.md` (follow-up to item 6) — **evaluate skill-vs-agent reshape.** Invocation is skill-shaped (`/codebase-explorer tech|arch`), deterministic, and `context: fork` gives the spawn-in-fresh-context benefit skills can claim now. Independent of the path fix.

**Coordinated with other audit directories:**

11. **Plans-directory consolidation** — `planning/` vs `output/claude-toolkit/plans/`. Referenced by `implementation-checker`, `goal-verifier`, and plausibly by skills (`/review-plan`, skills that write plans). Coordinate with the `output/claude-toolkit/` audit and the skills audit.
12. **`AGENTS.md` index drift** — output-path drift on `codebase-explorer` (item 6 fixes this specific case), stale experimental label on `goal-verifier` (item 7 fixes this), no validator for `tools:` column across entries. Broader validator question feeds into the `docs/indexes/` audit item raised under `.claude/hooks/` cross-cutting note.
