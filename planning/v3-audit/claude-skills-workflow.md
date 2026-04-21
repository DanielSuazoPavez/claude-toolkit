# v3 Audit — `.claude/skills/` (Workflow & Session subset)

Exhaustive file-level audit of the 11 skills in the Workflow & Session category (per `docs/indexes/SKILLS.md`).

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`
**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

Skills audited: `brainstorm`, `brainstorm-idea`, `shape-project`, `shape-proposal`, `analyze-idea`, `review-plan`, `write-handoff`, `wrap-up`, `learn`, `manage-lessons`, `list-docs`.

---

## Summary

These are the highest-traffic skills in the toolkit — session lifecycle (write-handoff, wrap-up), ideation (brainstorm, brainstorm-idea, shape-project, shape-proposal, analyze-idea), plan review (review-plan), docs discovery (list-docs), and lessons capture/management (learn, manage-lessons). Workshop-shaped by construction: every skill runs inside a consumer's session and writes artifacts to `output/claude-toolkit/...`.

**Three classes of finding** emerge:

1. **Frontmatter hygiene — `type:` field should be removed.** Per `relevant-toolkit-resource_frontmatter.md` §6: *"`type` is not a supported field in either layer. Our `type: knowledge|command` should be removed."* Four skills in this subset still carry it: `analyze-idea` (`type: knowledge`), `write-handoff` (`type: command`), `wrap-up` (`type: command`), `list-docs` (`type: command`). Coordinated cleanup across all skills with the field is probably a single sweep.

2. **Output-path drift.** `brainstorm/SKILL.md` line 69 writes to `output/{project}/design/...`. Every other skill in the subset (and the toolkit overall) uses `output/claude-toolkit/...`. `{project}` as a template variable isn't defined anywhere — substitution is skill-author intent, not real syntax. Drift risk: a session running this skill gets an actual directory literally named `{project}`. `write-handoff/SKILL.md` line 104 has a different drift: `mkdir -p .claude/sessions` in instructions, but the actual output target is `output/claude-toolkit/sessions/`. Stale mkdir hint.

3. **Lessons-ecosystem coupling.** `learn` and `manage-lessons` are the capture/management skills for the lessons ecosystem. The v3 canon (`relevant-project-identity.md` §3) says lessons schema ownership belongs to `claude-sessions` satellite, not the workshop. These skills are *consumers* of the schema, which is correct — but they both inline SQL in the management skill (direct `sqlite3` calls for promote/deactivate/delete). That coupling bypasses the `claude-toolkit lessons` CLI that otherwise mediates access. Consistency question: should `manage-lessons` go through the CLI for these mutations too?

Plus a handful of smaller items: a few `See also` cross-references depend on audit-pending decisions (pattern-finder deprecation, model flips on code-reviewer/implementation-checker).

**User resolutions surfaced during review:**
- **Rename the brainstorm pair** (`/brainstorm` → `/brainstorm-idea`, `/brainstorm-idea` → `/brainstorm-feature`) to make the expected output match the name.
- **`write-handoff` is attributing intent** in the generated handoff file — leaning toward `/compact`-style synthesis, which is exactly what the skill is supposed to *avoid*. Needs a prompt-body pass.
- **`wrap-up` is the most-run skill and is holding up well.** `format-raiz-changelog.sh` omission from the skill is correct (maintainer-only, correctly in `CLAUDE.md` line 65 which doesn't sync).
- **`learn` works**; lifecycle management is where the pressure is, and the canonical answer (per user's explicit bet) is deterministic tooling, not agent delegation.
- **`manage-lessons` should route everything through the `claude-toolkit lessons` CLI** — no direct SQL. If CLI subcommands are missing, add them.
- **`list-docs` works, but docs-surfacing as an ecosystem is underserved.** A context-aware `surface-docs.sh` hook (same pattern as the fixed `surface-lessons.sh`) may be warranted. Open call.
- **`type:` frontmatter drift gets a semantic-preserving fix**, not raw removal: move to `metadata.type` (a supported Agent Skills field) and update `evaluate-*` skills to read the new path. Restores contract compliance without breaking evaluation.

Findings below: 5 Rewrite (rename pair + write-handoff prompt + list-docs surfacing diagnostic + manage-lessons CLI routing + write-handoff mkdir), 2 Investigate (list-docs surfacing direction + manage-lessons diagnostic), 4 Keep (brainstorm-feature after rename, shape-project, shape-proposal, review-plan, learn, wrap-up).

---

## Files

### `brainstorm/SKILL.md`

- **Tag:** `Rewrite`
- **Finding:** General-purpose brainstorm facilitation — explicitly *not* for software design (that's `/brainstorm-idea`) or research (that's `/analyze-idea`). The exclusion framing in the description + "When NOT to Use" section is crisp. Workshop-shaped.

  **Output path drift (line 69):** `Save to: output/{project}/design/{YYYYMMDD}_{HHMM}__brainstorm__{topic}.md`. Two problems:
  - `{project}` isn't a documented template variable — every other skill uses literal `output/claude-toolkit/...`. If a session runs this skill, does `{project}` get substituted, or does the directory literally contain `{project}`? No substitution mechanism exists; this is skill-author shorthand that will bite.
  - The category is `design` but this skill explicitly converges on **clarity, not a design document** (line 8). Saving to `design/` contradicts the skill's own framing.

  **User call — rename the pair and sharpen the split:** rename `/brainstorm` → `/brainstorm-idea` (clarity artifact), and the existing `/brainstorm-idea` → `/brainstorm-feature` (software design output). Rationale: the current names don't signal which is which — *idea* sounds more scoped than *general* but the current `brainstorm-idea` skill is actually the *narrower* software-design one. Renaming makes the expected output the name:

  | Current | Renamed | Output |
  |---------|---------|--------|
  | `/brainstorm` | `/brainstorm-idea` | Clarity artifact (what do we think about this topic?) |
  | `/brainstorm-idea` | `/brainstorm-feature` | Software design doc (what will we build?) |

  This also simplifies the output-path question: `/brainstorm-idea` → `output/claude-toolkit/brainstorms/`, `/brainstorm-feature` → `output/claude-toolkit/design/` (existing). No new category namespace needed for `design/` — it's the right home for a feature design doc. Just the renamed general skill needs a new home.

  **Cascade:** renaming affects every `See also` reference across the skillset. Both names appear in many cross-references (e.g., `brainstorm-idea/SKILL.md` line 11, `shape-project/SKILL.md` line 108, `analyze-idea/SKILL.md` line 11, `shape-proposal/SKILL.md` line 13, etc.). Single sweep: grep for `/brainstorm` and `/brainstorm-idea`, rename consistently, update `docs/indexes/SKILLS.md`, `docs/getting-started.md`, README.md table.

- **Action:** at decision point: (1) rename `/brainstorm` → `/brainstorm-idea` (file + frontmatter + all See also references), (2) rename existing `/brainstorm-idea` → `/brainstorm-feature` (file + frontmatter + all See also references), (3) set output paths — `/brainstorm-idea` writes to `output/claude-toolkit/brainstorms/`, `/brainstorm-feature` writes to `output/claude-toolkit/design/`, (4) update `docs/indexes/SKILLS.md`, `docs/getting-started.md`, README.md table, (5) coordinate with `output/claude-toolkit/` audit on whether `brainstorms/` becomes a new top-level output category.
- **Scope:** moderate — two file renames + prompt body updates + ~5-8 See also updates across skills + 3 index/readme touches. Self-contained change, but needs a coordinated commit.

### `brainstorm-idea/SKILL.md` (→ to be renamed `/brainstorm-feature`)

- **Tag:** `Rewrite` (rename only; content stays)
- **Finding:** Dense, well-structured skill. Phase 1 (Understand) → Phase 2 (Explore — present 2-3 alternatives with trade-offs) → Phase 3 (Incremental Design in 200-300 word chunks with validation after each section). Explicit "When NOT to Use" section is strong — signs-to-skip list is concrete. Completion heuristics (3+ signals ready vs any hedging signal → more iteration) map to how Opus 4.7 actually behaves.

  Output path `output/claude-toolkit/design/{YYYYMMDD}_{HHMM}__brainstorm-idea__{topic}.md` is correct.

  Anti-patterns table is tight (Question Dump, Premature Implementation, YAGNI Violation, Skipping Validation, Premature Design Save, Over-Brainstorming). "Handling Stuck or Circular Conversations" section at line 139-177 is genuinely useful — concrete recovery strategies not just "be patient".

  **Rename action (see `brainstorm/SKILL.md` finding):** this skill becomes `/brainstorm-feature`. Content stays — just the name + frontmatter `name:` + slug in output filenames changes. All `See also` references elsewhere update in lockstep.

- **Action:** coordinated with the `/brainstorm` rename — rename file/frontmatter/slug to `/brainstorm-feature`. No content changes.
- **Scope:** trivial content touch, but requires the cross-skill See also sweep.

### `shape-project/SKILL.md`

- **Tag:** `Keep`
- **Finding:** Produces a `relevant-project-identity` doc — exactly the kind of thing the canon `.claude/docs/relevant-project-identity.md` is an example of. Phase 1 reads project context (README, CLAUDE.md, package config, directory structure, BACKLOG) before asking targeted questions. Phase 2 asks only 2-3 questions about what can't be inferred. Phase 5 saves to `.claude/docs/` — same location as the canon doc.

  **"Generic vs. Specific Traits" example (line 94-104)** is the best part of this skill: it shows the difference between "Well-tested" (applies to anything) and "Schema in, code out" (actually excludes things). That's the distinction that makes the output useful instead of generic.

  See also references `/brainstorm-idea`, `.claude/docs/`, `/refactor` — all correct.

  Workshop-shaped: the skill helps consumer projects define their own identity. It doesn't assume the workshop coordinates anything.
- **Action:** none.

### `shape-proposal/SKILL.md`

- **Tag:** `Keep`
- **Finding:** Sophisticated skill — restructures a validated design into an audience-aware proposal. Notable shape:

  1. **Phase 4 delegates to `proposal-reviewer` agent** (via `Agent` tool in `allowed-tools`). This is one of the few skills that spawns a subagent. The prompt to the agent includes target audience context — that's workshop-shaped (skill and agent cooperate; neither orchestrates).

  2. **`resources/` subdirectory** holds `EXAMPLE.md` + `PROPOSAL_TEMPLATE.md` — hand-authored shaping references. Per frontmatter convention, `resources/` is skill-owned (like `brainstorm-idea` could have had if it needed). Correct structure.

  3. **30/70 rule** in Key Principles: *"Design may be 30% of the effort. Making it land with the audience is the other 70%."* That's the skill's thesis in one line.

  4. **"Source fidelity check"** (Phase 4 end) — after reviewer fixes, re-scan the source for technical substance that didn't make it into the output. This is the kind of nuance that's easy to miss. Good inclusion.

  Tools list `Read, Write, Agent` — correct and minimal.

  No drift. No v3-scoped concerns.
- **Action:** none.

### `analyze-idea/SKILL.md`

- **Tag:** `Rewrite`
- **Finding:** Research/exploration skill. Output path `output/claude-toolkit/analysis/{YYYYMMDD}_{HHMM}__analyze-idea__{topic}.md` is correct. `$ARGUMENTS` parsing is correct per §2 of frontmatter doc.

  **Two drift items:**

  1. **Frontmatter has `type: knowledge`** (line 3). Per `relevant-toolkit-resource_frontmatter.md` §6: *"`type` is not a supported field in either layer. Our `type: knowledge|command` should be removed."* Remove the line.

  2. **`See also` references `pattern-finder` agent** (line 11) — *"targeted pattern searches"*. Pattern-finder's fate is still open in `.claude/agents/` audit queue (item 8): deprecate / sharpen / keep. If pattern-finder is deprecated or reframed around anti-Explore framing, this `See also` updates. Cross-reference.

  Body is thorough: Investigation Heuristics section (line 28-68) breaks down by analysis type (Code / Architecture / Coverage Gaps / Feasibility), each with a concrete "what to look for" list. Evidence Triangulation table (line 74-83) is strong — source types ranked by strength with "watch for" caveats. "When to Stop Investigating" flowchart (line 94-107) prevents analysis paralysis.

  Edge Cases section (line 195-221) covers Vague Scope, Contradictory Evidence, No Relevant Code, Security-Sensitive Findings — exactly the wayward cases where a research skill goes off the rails.

  Anti-patterns and Report Template are tight. No other drift.

- **Action:** at decision point: (1) remove `type: knowledge` from frontmatter, (2) update `pattern-finder` reference in See also when `.claude/agents/` queue item 8 resolves (keep / sharpen / deprecate).
- **Scope:** trivial (1-line frontmatter removal) + coordinated update.

### `review-plan/SKILL.md`

- **Tag:** `Keep`
- **Finding:** Comprehensive plan-review framework with inline + subagent dispatch. Calibration-by-plan-type (Bug fix = Low strictness, Data migration = Very High) is exactly the proportionality convention `code-reviewer` also uses. Issue severity definitions + floor rule (High → REVISE floor; 3+ High → RETHINK floor) + approach-can-only-raise-never-lower is well-designed.

  **Final steps tiering** (line 122-137) correctly reflects agent cost:
  - Always: code-reviewer + /wrap-up
  - Medium+: goal-verifier
  - Detailed/strict: implementation-checker

  That tiering matches how these agents are actually called. It also *naturally* makes room for the model flips from `.claude/agents/` audit (code-reviewer → sonnet, implementation-checker → sonnet): nothing in this skill's prompt depends on those being opus specifically.

  The "Wishful Delegation" anti-pattern (line 169-184) is specifically calibrated for the implementing agent's perspective — strong framing.

  Workshop-shaped: skill runs in the consumer's session, reviews the consumer's plan, writes report to consumer's `output/`. No orchestration.

  No drift. See also references are all current.
- **Action:** none.

### `write-handoff/SKILL.md`

- **Tag:** `Rewrite`
- **Finding:** Lifecycle skill — saves continuation file before `/clear`. The output this session's handoff file was generated from. Solid shape: "What to Include vs Exclude" decision tree prevents the Novel anti-pattern; Resume Prompt at the bottom is paste-ready.

  **User observation on a real failure mode:** the skill sometimes *attributes undesired intent* to the handoff file — leaning toward what `/compact` does (auto-summarizing), which is precisely the behavior this skill is meant to *avoid*. The point of `/write-handoff` is to preserve explicit direction, not synthesize what-we-did-ish narrative. When the skill guesses at intent, it becomes lossy in the same direction compacting is.

  Reading the prompt for signal on where this leaks in:
  - Line 16-28 "What to Include vs Exclude" is decision-tree-shaped — correct framing, prevents dumping too much.
  - But line 63-83 "Generate the Continuation File" template has sections like `## Recent Work - [What was just done in bullet points]` and `## Context Notes - [Any important context that wouldn't be obvious from files alone]`. These are permissive invitations to summarize. The skill doesn't push hard on "only include what the next session will act on" — the implicit invitation to narrate fills the gap.
  - Line 88 Resume Prompt: *"one-sentence summary of next steps"* — single sentence is the right constraint, but the wording is loose (what counts as a "next step" is exactly where intent gets attributed).

  **Fix direction (user call needed):** tighten the prompt around "don't narrate, don't summarize past work — capture uncommitted state, blockers, and the next concrete action." Possible concrete tightenings:
  - Drop or shrink the `## Recent Work` section — if it's in the git log (this session's commits), don't restate it.
  - Reframe `## Context Notes` as `## Blockers / Hidden State` — only for things that aren't in code/git and would prevent resumption.
  - Strengthen the anti-pattern: add *"Attributing Intent"* — *"Don't summarize what-we-did into forward-direction. If the user said `commit this`, record the request. Don't extrapolate `the user wanted to finalize the feature`."*
  - Possibly add a validation check: before writing, does every bullet in Next Steps map to something the user explicitly said or a concrete git/file state? If not, drop it.

  **Two smaller drift items:**

  1. **Frontmatter `type: command`** (line 3) — remove per frontmatter doc §6. Roll into the repo-wide sweep.

  2. **Line 104 `mkdir -p .claude/sessions`** is stale. Output target is `output/claude-toolkit/sessions/` (line 35, 56, 105), not `.claude/sessions`. The mkdir in instructions §4 points at the wrong path. Bug.

  Body is otherwise solid: Edge Cases (Merge Conflicts, Multi-Branch, Interrupted Deployment) are practical, Validation Checklist at end is appropriate.

- **Action:** at decision point: (1) prompt-body pass to tighten against intent-attribution — shrink `## Recent Work`, reframe `## Context Notes` → `## Blockers / Hidden State`, add "Attributing Intent" anti-pattern, consider adding a validation check for forward-direction bullets, (2) remove `type: command` from frontmatter (repo-wide sweep), (3) fix line 104 `mkdir` path.
- **Scope:** (1) small-moderate prompt rewrite — 15-30 lines. (2) trivial. (3) trivial.

### `wrap-up/SKILL.md`

- **Tag:** `Keep`
- **Finding:** Feature-branch finalization. Code-before-docs commit order with explicit rationale (git bisect cleanliness, PR reviewability, atomic releases). Version bump decision table is concrete. `[Unreleased]` fold rule (line 59) prevents the most common wrap-up bug.

  **User confirmation:** this is the most widely-run skill, and it's holding up. Edge Cases (no CHANGELOG.md, first version, merge conflicts, version file missing) are practical. Anti-patterns include the "Stale Unreleased" pattern which directly matches the current repo state (`[Unreleased]` holds the v3 stage-1 docs-only notes — correct pattern).

  **`format-raiz-changelog.sh` is correctly NOT mentioned here.** The skill ships to consumers via sync; the raiz-changelog workflow is toolkit-maintainer-only. The check belongs (and **is present**, verified) in `CLAUDE.md` line 65 under "When You're Done" — that file does NOT sync to consumers, so it's the right home for maintainer-only steps. No drift on this front.

  **One drift item:** frontmatter `type: command` (line 3) — remove per frontmatter doc §6. Roll into the repo-wide sweep.

- **Action:** at decision point: remove `type: command` from frontmatter (covered by repo-wide sweep, queue item 11).
- **Scope:** trivial (part of sweep).

### `learn/SKILL.md`

- **Tag:** `Keep`
- **Finding:** Lightweight lesson capture — search → infer → present → write. Uses `claude-toolkit lessons add` CLI for the actual write, which auto-generates ID, detects project/branch, and infers domain tags. That's the right separation: skill handles UX (ask, present, propose), CLI handles mechanics (ID, project detection, tag inference, DB write).

  Tags scheme is clean: pick one category-equivalent tag (correction/pattern/convention/gotcha) + any domain tags (git/hooks/skills/etc.). Matches `relevant-toolkit-lessons.md` schema.

  Duplicate detection is correct: search first, mark `recurring` if similar exists, skip if exact.

  See also: `/manage-lessons`, `relevant-toolkit-lessons` doc, `claude-toolkit lessons` CLI — all current and correct.

  Workshop-shaped: the skill is the capture surface for a global (cross-project) lessons.db that lives in `~/.claude/`. Per canon, schema ownership is with claude-sessions, but the capture UX lives here in the workshop — that split is correct (skill = workflow, DB = runtime state).

  **User note on the ecosystem's real pain points:** the biggest problems with lessons aren't capture — it's **surfacing** (the `surface-lessons.sh` hook, already queued for Rewrite in `.claude/hooks/` audit item 5) and a bit of **lifecycle management** (the `manage-lessons` skill below). Capture itself (this skill) works. The user's self-flagged tension: *"the usual online response for memory systems is 'delegating to an agent', and I've been swimming against that"* — that's a deliberate design bet (deterministic, human-in-the-loop), not a bug to fix. Worth noting for future-self audits: if someone reopens the lessons-ecosystem question and suggests an agent-based routing layer, it's the user's explicit choice to not go that direction. No action on this skill.

- **Action:** none.

### `manage-lessons/SKILL.md`

- **Tag:** `Investigate`
- **Finding:** Lifecycle management — health check, cluster detection, walk through clusters, walk through recent lessons, tag hygiene. Lifecycle diagram (`raw lessons → crystallized → absorbed → deactivated`) captures the intended end-state of a mature pattern (it leaves the lessons system and becomes a toolkit resource). That's a good thesis.

  **Direct SQL inconsistency.** The skill uses `claude-toolkit lessons` CLI for most operations (health, list, clusters, crystallize, absorb, tag-hygiene) — consistent with `/learn`. But for promote/deactivate/delete (line 94-106), it falls back to direct `sqlite3` calls:

  ```bash
  sqlite3 ~/.claude/lessons.db "UPDATE lessons SET tier='key', promoted='$(date +%Y-%m-%d)' WHERE id='<ID>';"
  sqlite3 ~/.claude/lessons.db "UPDATE lessons SET active=0 WHERE id='<ID>';"
  sqlite3 ~/.claude/lessons.db "DELETE FROM lessons WHERE id='<ID>';"
  ```

  Consistency concern: the CLI is the mediated access layer; direct SQL bypasses it. Three implications:
  - If lessons schema changes (and per canon, claude-sessions owns the schema now), direct SQL here breaks without notice. CLI-mediated calls would error more clearly or get updated in lockstep.
  - `allowed-tools` includes `Bash(sqlite3:*)` explicitly to permit this — the allowlist exists because direct calls exist. Removing direct SQL would tighten the tool list.
  - The CLI probably has or should have `promote`, `deactivate`, `delete` subcommands. The fact that the skill falls back to SQL suggests either (a) the CLI doesn't support those operations yet, or (b) it does but the skill wasn't updated. Diagnostic step before acting.

  **User confirmed:** the CLI should serve *all* purposes for lessons lifecycle; the skill shouldn't be calling SQL directly. If CLI subcommands for promote/deactivate/delete don't exist yet, **add them**. Then rewrite the skill to route everything through `claude-toolkit lessons` and drop `Bash(sqlite3:*)` from `allowed-tools`.

  Secondary observation: the skill's `lessons.db` path (`~/.claude/lessons.db`) is hardcoded. Once it routes through the CLI, this goes away automatically — the CLI owns the path resolution. Related to `.claude/hooks/` audit decision queue item 2 (`LESSONS_DB` env var): the CLI's own path resolution should honor the env var, and then the skill inherits that behavior for free.

- **Action:** at decision point: (1) check `claude-toolkit lessons` CLI for existing promote/deactivate/delete subcommands; (2) add any missing subcommands (CLI-owned, with full path/env var handling); (3) rewrite the skill to route everything through the CLI, drop `Bash(sqlite3:*)` from `allowed-tools`, remove inline SQL; (4) coordinate with hooks-audit queue item 2 (`LESSONS_DB` env var) so the CLI honors it.
- **Scope:** (1) small diagnostic. (2) CLI work — scope depends on missing subcommands (likely 3 small additions at most). (3) prompt rewrite on lines 93-106 + frontmatter tightening. (4) trivial once the env var lands.

### `list-docs/SKILL.md`

- **Tag:** `Investigate`
- **Finding:** Small, tight skill. Two modes: Standard (Quick Reference summaries only) + Verbose (adds size + last-modified). The `awk` extraction for Quick Reference is robust (handles both `## Quick Reference` and `## 1. Quick Reference` patterns — the latter is what `relevant-toolkit-context.md` §1 established).

  **The skill works as written** — the bigger open question is not about this skill but about **docs-surfacing as an effectiveness problem**. User observation: *"I don't know when the agent feels like reading the docs, or if we're just injecting wasted tokens at session-start with it."*

  Reading the existing surfacing path:
  - `essential-*` docs auto-load at session-start (via `session-start.sh` hook). Unconditional; loaded every session.
  - `relevant-*` docs are on-demand: discovered via `/list-docs` and read by explicit user request or Claude-judged relevance.
  - **There's no mechanism between those two tiers.** Either a doc is always loaded, or it's opt-in. For docs that are "relevant in ~30% of sessions" (e.g., `relevant-toolkit-hooks.md` when working on hooks), the answer today is: user runs `/list-docs`, Claude reads what seems relevant. In practice, that probably happens rarely.

  Two different problems nesting here:

  1. **Session-start essentials might be token-waste in some sessions.** If a session never touches frontend or tests, loading `essential-conventions-code_style` (which is generic) is low-value. If the session is pure prose work, almost none of the essentials apply. But: essentials are short and their cost is small. Probably not the leak.

  2. **Relevant docs surface rarely even when they'd help.** The real failure mode is "I was working on hooks for an hour before realizing `relevant-toolkit-hooks.md` had the answer." The fix isn't `/list-docs` (which the user remembers to run, or doesn't) — it's **context-aware doc surfacing**, analogous to `surface-lessons.sh` but for docs.

  **The `surface-lessons.sh` hook is already queued for Rewrite** (`.claude/hooks/` queue item 5): dedup window + minimum match specificity, algorithmic not ML. If that pattern works for lessons, it could extend to docs. Diagnostic question: should there be a **`surface-docs.sh` hook** that matches tool context against `relevant-*` doc Quick References and injects a one-liner suggestion? Same deterministic approach.

  Alternatively: keep docs as user-invocable-only via `/list-docs` and accept that the agent won't discover them unprompted. That's a defensible stance (matches the `essential-preferences-communication_style.md` §5 doc's "explicit over automatic" principle from `relevant-project-identity.md` §2) — but the user flagged dissatisfaction with the current state, so status-quo isn't it.

  **Smaller drift items (not the investigation):**

  - Frontmatter `type: command` (line 3) — remove per frontmatter doc §6. Rolled into repo-wide sweep.
  - `allowed-tools: Bash(for f in .claude/docs/*)` uses an unusual syntax — that's a command-prefix-scoped permission. The frontmatter doc §2 notes `allowed-tools` supports patterns like `Bash(git:*)`, `Bash(jq:*)`. The pattern here (`Bash(for f in .claude/docs/*)`) is specific — literal match of a `for` loop. If string-literal matching is in play, it's very narrow; any slight command variation would fail permission check. Verify whether this pattern actually works in practice (the skill runs regularly, so it apparently does — but confirm the match mechanism).

- **Action:** at decision point: (1) decide on docs-surfacing direction — status quo, or a new `surface-docs.sh` hook matching context to `relevant-*` Quick References (same algorithm as the fixed `surface-lessons.sh`); (2) if direction is "new hook", spec it out as a follow-up item (coordinates with `.claude/hooks/` queue item 5 — same dedup + specificity pattern applies); (3) remove `type: command` from frontmatter (repo-wide sweep); (4) verify `allowed-tools: Bash(for f in ...)` pattern actually works — loosen to `Bash(for:*)` if not.
- **Scope:** (1) design call. (2) if pursued, moderate — new hook + context extraction + dedup reuse from `surface-lessons.sh`. (3) trivial (sweep). (4) small verification.

---

## Cross-cutting notes

- **`type:` frontmatter field is the most common drift in this subset** — 4 of 11 skills still carry it (`analyze-idea`: knowledge; `write-handoff`, `wrap-up`, `list-docs`: command). Per frontmatter doc §6, the field is unsupported and should be removed. Likely a repo-wide sweep: grep all skills for `^type:` frontmatter and remove in one pass. Other subsets (to be audited next) will likely have more.

  **User call on the bigger question:** `type: knowledge|command` was an internal category the `evaluate-*` skills used for scoring — removing it raw breaks that contract. The direction is to **fold the category signal into somewhere evaluate-* can still read it without violating the official frontmatter contract**. Two routes per frontmatter doc §2:
  - (a) **`metadata` field** (Agent Skills standard, arbitrary string-to-string map) — supported field, informational only. `evaluate-*` can read `metadata.type`. No validator complaints because `metadata` IS in the spec.
  - (b) **Derive from other signals** — e.g., `argument-hint` presence often correlates with command-shape skills; `allowed-tools` being minimal-or-absent correlates with knowledge-shape. Softer but doesn't add a field.

  Route (a) is cleaner: `metadata: { type: command }` / `metadata: { type: knowledge }` keeps the semantic, restores contract compliance, unbreaks `evaluate-*`. Route (b) is more fragile — inferring type from adjacent fields creates coupling that breaks when any of the underlying fields change for unrelated reasons.

  The coordinated sweep then isn't "drop `type:`" — it's "move `type:` to `metadata.type:`" across every skill that has it, and update `evaluate-skill` / `evaluate-batch` to read the new path. One commit, all-or-nothing. This is the right place to do the move, not the Workflow subset's problem alone.

- **Output-path templating patterns are inconsistent.** Most skills use literal `output/claude-toolkit/<category>/...`. `brainstorm` uses `output/{project}/design/...` (drifts from workshop convention and uses an undocumented `{project}` placeholder). `write-handoff` has a stale `mkdir .claude/sessions` that contradicts its actual output path. These are small individually but signal that path-template validation could use a validator — same thought as the indexes-validator cross-audit finding.

- **Lessons-ecosystem access pattern split.** `/learn` goes through `claude-toolkit lessons add` CLI (mediated). `/manage-lessons` goes through the CLI for most ops but falls back to direct SQL for promote/deactivate/delete. Either there are missing CLI subcommands, or the skill wasn't updated to use newer ones. Diagnostic step.

- **`See also` blocks are mostly current.** A few cross-references depend on pending audit decisions:
  - `analyze-idea` → `pattern-finder` agent (depends on `.claude/agents/` queue item 8).
  - `review-plan` → `code-reviewer`, `goal-verifier`, `implementation-checker` agents (all three are queued for model/behavior flips in the agents audit — no skill-text change needed, the agents continue to exist, just run differently).
  - No other stale refs found in this subset.

- **No orchestration-shaped leakage in any of the 11 skills.** Every skill assumes it runs inside a user's session, reads/writes local files, and returns. That's correct workshop identity post-stage-1.

- **Stage-1 prose work landed well.** `shape-project` and `brainstorm-idea` both reference identity docs / project-awareness correctly. No "orchestrator" framing anywhere.

---

## Decision-point queue (carry forward)

Every item below is a real work item. None are blocked behind the v3 reshape — they're just audit-surfaced issues that get scheduled like any backlog work.

**Resolved during review (pending execution — trivial scope):**

1. `write-handoff/SKILL.md` line 104 — **fix stale `mkdir .claude/sessions` path** (should be `output/claude-toolkit/sessions` or just remove — Write tool creates parents).

**Resolved during review (pending execution — small scope):**

2. `list-docs/SKILL.md` — **verify `allowed-tools: Bash(for f in .claude/docs/*)` pattern works** as intended in Claude Code's permission grammar. If string-literal matching is in play, broaden the pattern.

**Resolved during review (pending execution — moderate scope, coordinated changes):**

3. **Rename the brainstorm pair.** `/brainstorm` → `/brainstorm-idea` (clarity artifact). `/brainstorm-idea` → `/brainstorm-feature` (software design doc). Output paths: the renamed `/brainstorm-idea` writes to `output/claude-toolkit/brainstorms/...`; `/brainstorm-feature` keeps writing to `output/claude-toolkit/design/...`. Update all `See also` cross-references (analyze-idea, shape-project, shape-proposal, at minimum), `docs/indexes/SKILLS.md`, `docs/getting-started.md`, `README.md`. Also removes the `output/{project}/design/` drift. Coordinates with `output/claude-toolkit/` audit (whether `brainstorms/` becomes a new top-level category).

4. `write-handoff/SKILL.md` — **prompt-body pass against intent-attribution.** Shrink `## Recent Work` (git log is authoritative for what was done), reframe `## Context Notes` → `## Blockers / Hidden State` (only for things not in code/git), add "Attributing Intent" anti-pattern warning against compact-like synthesis, optionally add validation check for forward-direction bullets. Root fix for the user's concern that the skill leans toward `/compact`-style summarization instead of explicit preservation. 15-30 line prompt edit.

**Resolved during review (pending execution — needs diagnostic first):**

5. `manage-lessons/SKILL.md` + `claude-toolkit lessons` CLI — **CLI should serve all lifecycle needs; skill should stop calling SQL directly.** (a) Check CLI for existing promote/deactivate/delete subcommands, (b) add any missing, (c) rewrite skill to route everything through the CLI, drop `Bash(sqlite3:*)` from `allowed-tools`, remove inline SQL. User confirmed.

6. `list-docs/SKILL.md` + potential new `surface-docs.sh` hook — **decide on docs-surfacing direction.** Current state: user flags that relevant docs rarely surface when they'd help. Two directions: (a) status quo (explicit-invocation only), (b) new context-aware `surface-docs.sh` hook matching tool context against `relevant-*` Quick References — same algorithmic approach as the fixed `surface-lessons.sh`. Coordinates with `.claude/hooks/` queue item 5 (dedup window + minimum match specificity). No decision yet.

**Coordinated with other audit directories:**

7. **Repo-wide `type:` frontmatter sweep — but NOT a raw removal.** User call: keep the semantic in a supported field. Move `type: knowledge` / `type: command` → `metadata: { type: knowledge|command }` across every skill that has it (4 confirmed in this subset, others likely in remaining subsets). Update `evaluate-skill` / `evaluate-batch` to read `metadata.type` instead of top-level `type`. One commit, coordinated across all skill-subset audits. Restores frontmatter contract compliance (metadata IS a supported Agent Skills field per frontmatter doc §2) without breaking the evaluate-* contract.

8. `analyze-idea` → `pattern-finder` agent reference — update based on `.claude/agents/` queue item 8 outcome (deprecate / sharpen / keep).

9. `manage-lessons` → `LESSONS_DB` env var — coordinate with `.claude/hooks/` queue item 2. Once CLI routes through the env var, skill inherits the behavior automatically.

10. **Output-path validator** — related to the `output/claude-toolkit/` audit and the `docs/indexes/` validator-drift thread. A small validator that checks each skill's Output path matches the workshop convention (`output/claude-toolkit/<category>/...`) would prevent drift like `brainstorm`'s `{project}` template. Low priority; feeds into stage-5 polish.

**Still open / low-priority:**

*(None — all findings actionable.)*
