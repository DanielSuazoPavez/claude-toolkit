# v3 Audit — `.claude/skills/` (Personalization subset)

Exhaustive file-level audit of the 2 skills in the Personalization category (per `docs/indexes/SKILLS.md`).

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`
**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

Skills audited: `build-communication-style`, `snap-back`.

---

## Summary

Two skills, tightly coupled: `build-communication-style` produces `.claude/docs/essential-preferences-communication_style.md`; `snap-back` consumes it as the source of truth for tone reset. Workshop-shaped by construction — both operate on a doc that lives in the consumer's `.claude/` tree.

Three findings:

1. **`type:` frontmatter drift — 2 instances** (`build-communication-style: type: command` at **line 6** not line 3 — frontmatter is reordered here vs the other 17; `snap-back: type: command`). Both picked up by the repo-wide sweep (workflow queue item 7). The `build-communication-style` variant at line 6 is the only instance in the whole directory that doesn't live at line 3; the sweep should handle it regardless (it's matching `^type:`), but worth noting that frontmatter field ordering isn't normalized across skills.

2. **`casual_communication_style` reference in `snap-back`** (line 75) — **the doc exists, but in `.claude/memories/`, not `.claude/docs/`.** Not a broken reference — just potentially ambiguous because readers seeing `casual_communication_style` naturally look in `.claude/docs/` first (where most named-reference docs live). The reference itself is valid; the location isn't implied and isn't obvious. Options: (a) leave as-is (the memory system auto-loads under its own conditions — the skill's reader doesn't need to know the path), (b) qualify the reference (e.g., "`casual_communication_style` memory"), or (c) tolerate ambiguity. Low-priority polish, not drift.

3. **`AskUserQuestion` in allowed-tools** (`build-communication-style` line 5) — this is the only skill in the directory using that tool. Ties to backlog task **`skill-interactive-options`** (P99): *"Add interactive option selection to skills that ask questions."* That backlog item frames `build-communication-style`'s use of `AskUserQuestion` as the pattern reference — calibration-by-paired-examples already uses structured single-select. Other skills that ask categorical questions could convert similar decision points to structured option selection. So this isn't just a rare tool — it's the canonical example of a shape the backlog wants to spread.

**User resolutions surfaced during review:**
- **`casual_communication_style` is a memory, not a `.claude/docs/` file** — the reference in `snap-back` is valid (doc exists at `.claude/memories/casual_communication_style.md`), just not path-qualified. Low-priority polish at most; status-quo is acceptable.
- **`AskUserQuestion` use in `build-communication-style` is the canonical pattern for `skill-interactive-options` backlog task (P99).** The skill's paired-example calibration is already the shape the backlog wants to spread to other categorical-question skills — this is a reference example, not a one-off.

Findings below: 2 Rewrite (both on `type:` sweep), no Investigate, no Keep independent of the sweep.

---

## Files

### `build-communication-style/SKILL.md`

- **Tag:** `Rewrite` (frontmatter only)
- **Finding:** Guided discovery skill for producing a consumer's communication-style doc. 190 lines. Two-mode design: creation (when no doc exists) → example-driven calibration → adaptive dimension walk; refinement (when doc exists) → targeted questions on problem areas only. The mode detection (line 22-27) is explicit — checks for the file at the known path; `$ARGUMENTS contains "refine"` forces refinement mode.

  **Example-driven calibration** (line 29-61) is the strongest part: 4 paired examples (Ceremony vs Directness, Verbosity, Disagreement, After a Mistake) each with two concrete Claude responses (A vs B) showing the same scenario handled differently. This bypasses the "describe your preferences" failure mode where users hand-wave abstract answers. Concrete contrast → concrete preference.

  **Adaptive dimension walk** (line 63-84) — 6 dimensions (Tone / Verbosity / Ceremony / Disagreement / Anti-patterns / Positive signals), each with a one-line "What to ask." The "dig deeper on strong opinions, quick pass on neutral" principle prevents the survey-mode anti-pattern the skill itself flags at line 186.

  **Handling Ambiguous or Conflicting Responses** (line 88-103) — three failure-mode remedies:
  - Ambiguous ("both are fine") → reframe with concrete forced-choice scenario.
  - Conflicting (terse for X but detailed for Y) → name the tension, let user resolve.
  - "I don't know" → offer a default, mark it as adjustable later.

  The forced-choice scenario *"you just pushed a broken migration and need help fast"* (line 94) is specifically calibrated to break ties — it's the kind of stress case that reveals real preferences.

  **Refinement Mode** (line 106-112) — 4 steps: show sections, ask what's working/not, targeted questions on problem areas, surgical edits not full regeneration. That's the right pattern for iterating on a user's existing doc without destroying their prior calibration work.

  **Generated doc template** (line 117-155) — 5-section structure (Quick Reference with "The Test" heuristic / Effective Working Patterns / Anti-Patterns table / When Softer Tone IS Appropriate / Key Principle). Matches the shape of the workshop's own `essential-preferences-communication_style.md` (which is itself the canonical example). Good consistency.

  **Post-write guidance** (line 162-164) — explicitly tells the user that `essential-*` docs auto-load via session-start hook, and if no hook is configured they may need to set one up. That's the right workshop-to-consumer bridge: skill produces the doc, informs the user how the doc gets loaded, doesn't assume the hook infrastructure is present.

  **Mid-Process Restart** (line 175-179) — three user-exit cases ("Start over" / "This isn't working" / "Just give me something"). The last one (generate a default doc, mark it as a starting point for `/build-communication-style refine` later) is the right escape hatch for users who want to skip the full discovery.

  **Anti-patterns table** (line 183-189) — Survey Mode, Projecting Preferences, Skipping Positive Signals, Overlong Doc (*"Keep it under 80 lines — Quick Reference must fit in a glance"*), Generic Output. The 80-line rule is specifically calibrated against the doc-bloat failure mode.

  **`AskUserQuestion` in `allowed-tools`** (line 5) — this is the only skill in the toolkit using that tool. Correctly scoped for the interaction pattern: the calibration step (line 31-61) is a sequence of "here are two options — which?" exchanges, and `AskUserQuestion` provides the multiple-choice mechanism. **Connects to backlog task `skill-interactive-options` (P99):** *"Add interactive option selection to skills that ask questions. AskUserQuestion supports single-select, multi-select, and preview panes — but most skills default to open-ended questions. Audit skills that use AskUserQuestion (brainstorm-idea may already use options organically) and convert categorical decision points to structured option selection where it fits."* This skill's paired-example calibration is the reference example the backlog wants to spread — not a rare one-off.

  **Frontmatter drift:** `type: command` at **line 6** (not line 3). Frontmatter field ordering differs from the rest of the directory — here it's `name, description, argument-hint, allowed-tools, type` vs the typical `name, type, description, ...` elsewhere. The repo-wide sweep (workflow queue item 7) matches on `^type:` so it'll pick this up regardless, but worth noting that frontmatter field ordering isn't normalized. Not this audit's action — flag for a potential ordering-consistency pass separate from the content sweep.

  See also references `/snap-back` (paired skill) and `/brainstorm-idea` (discovery process reference). Per workflow queue item 3, `/brainstorm-idea` is being renamed to `/brainstorm-feature`. That rename IS a content-sense match (discovery-through-dialogue is the shape the reference points at), so the lockstep update applies here — 1 reference.

  Workshop-shaped: runs in consumer session, writes to consumer's `.claude/docs/`. The skill doesn't assume the workshop coordinates anything — it builds a doc that the consumer's session-start hook will eventually load.

- **Action:** at decision point: (1) `type: command` → `metadata: { type: command }` as part of repo-wide sweep (queue item 7); (2) update `/brainstorm-idea` reference (line 11) → `/brainstorm-feature` when the brainstorm rename ships (workflow queue item 3). (3) Optional: frontmatter field ordering pass — normalize to `name, description, ...` order across the directory. Out of scope for this audit; polish.
- **Scope:** (1) trivial (sweep-covered). (2) trivial (rename-lockstep). (3) out-of-scope.

### `snap-back/SKILL.md`

- **Tag:** `Rewrite` (frontmatter + broken reference)
- **Finding:** Tone reset skill. 75 lines — one of the smallest in the directory. Tight scope: re-read `essential-preferences-communication_style`, apply reset protocol, verify. Correctly minimal `allowed-tools: Read` — this skill doesn't write anything, it just re-primes the context.

  **Reset Protocol** (line 10-30):
  - Severity triage (Minor / Moderate / Full drift) — correctly calibrated response per level. Minor = inline correction; Moderate = pause and re-read; Full drift = stop and rewrite. That's the proportionality match that prevents the "sledgehammer on a loose screw" overcorrection.
  - Step 2 "Reset" — re-read docs, apply the **colleague test** (*"would a competent peer say this, or does it sound like support chat?"*) — direct lift from `essential-preferences-communication_style.md §1` where that same test is canonized. Correct use of a pre-existing heuristic.
  - Step 3 "Verify" — check corrected response against the anti-patterns table in the source doc. Closed loop.

  **Non-Obvious Triggers table** (line 34-42) — 5 triggers (after praise / long sessions / after a mistake / ambiguous requests / user frustration) each with a brief "why it causes drift." These are the situations where sycophancy creeps in *despite* the preferences doc being loaded — meta-awareness, not just rule application. The "long sessions" one (*"Style degrades over extended context; defaults creep back"*) is empirically right and hard to notice from inside the drift.

  **Reset in Action example** (line 45-52) — before/after showing the actual transform (*"That's a really great approach! I think your implementation is solid..."* → *"The approach works but the retry logic will swallow connection errors silently. Wrap lines 42-50..."*). The diff is concrete: *"stripped the preamble, removed validation, went straight to the substance."* That's the kind of worked example that makes the reset actionable instead of abstract.

  **Related Drifts tree** (line 56-62) — 4 failure modes (Sycophancy / Spinelessness / Defensiveness / Over-correction). This scope-carves against adjacent-but-different failure modes. Sycophancy is this skill's lane; caving under pushback is a different failure (the preferences doc's "Handling Pushback" table covers it); stubborn refusal to reconsider is yet another; over-correction to robotic coldness is its own risk. Correct scope discipline.

  **"The Balance" (line 65-70)** — three-state illustration (Too cold / Too warm / Just right). *"That won't work because X. Try Y instead"* as the just-right example is practical — shows that anti-sycophancy ≠ hostility; direct ≠ rude.

  **`casual_communication_style` reference on line 75 — valid but location-ambiguous.** User confirmed: the doc exists at `.claude/memories/casual_communication_style.md`, not `.claude/docs/`. The reference is correct by name; the implied path is ambiguous because most named-reference docs in this tree live under `.claude/docs/`. The memory system auto-loads under its own conditions (on-demand only — line 10 of the memory itself: *"User on-demand ONLY - never auto-load or proactively read"*), so the reader typically doesn't need to know the path. No urgent action.

  Low-priority polish options (none required): qualify to `` `casual_communication_style` memory `` for clarity, or leave status-quo. Either is acceptable.

  **Frontmatter drift:** `type: command` at line 3. Picked up by repo-wide sweep (workflow queue item 7).

  See also references `essential-preferences-communication_style` (canonical — correct) and `casual_communication_style` (valid memory reference, see above). No agent / brainstorm references.

  Workshop-shaped: runs in consumer session, re-reads consumer's preferences doc, does not write anything. Pure in-context course correction.

- **Action:** `type: command` → `metadata: { type: command }` as part of repo-wide sweep (queue item 7). No other action required — `casual_communication_style` reference is valid as-is.
- **Scope:** trivial (sweep-covered).

---

## Cross-cutting notes

- **Skill pairing is tight and correct.** `build-communication-style` authors the preferences doc; `snap-back` re-reads it. One produces, one consumes. No overlap, no orchestration — each skill does one thing. Canonical small-subset shape.

- **`type:` frontmatter inventory, updated.** Full-directory count across the audit so far: 19 skills carry `type:` (13 command + 6 knowledge). This subset contributes 2 (both command). Per-subset breakdown for the sweep:
  - Workflow: 4
  - Code quality: 1
  - Design & arch: 3
  - Personalization (this subset): 2
  - Remaining (dev tools + toolkit dev): 9 — still to be audited.

  The sweep target is approaching the full skills directory. Worth confirming: are there *any* skills without `type:` frontmatter today? If all 20+ skills carry it, the sweep is a clean global transform; if some already omit it, the sweep creates asymmetry that `evaluate-skill` needs to handle (presence or absence of `metadata.type`). Quick grep would resolve this — deferring to the sweep execution itself.

- **Frontmatter field ordering isn't normalized.** `build-communication-style` has frontmatter field order: `name, description, argument-hint, allowed-tools, type`. Most other skills use `name, type, description, ...`. The content sweep (move `type:` → `metadata.type`) resolves the `type` placement, but field ordering more broadly is inconsistent. Polish pass candidate, not v3-blocking. Could be automated via a small linter.

- **Named cross-references are ambiguous across `.claude/docs/` vs `.claude/memories/`.** `snap-back` → `casual_communication_style` is valid (the memory exists) but the path isn't qualified, and the name's shape (`*_communication_style`) matches the `.claude/docs/essential-preferences-communication_style.md` pattern — readers naturally look in docs first. A small cross-reference validator that resolves names against *both* `.claude/docs/` and `.claude/memories/` (and maybe `.claude/agents/`, skills) would catch the broader "does this reference resolve anywhere?" question, not just the narrow "does it exist in docs." Related to the output-path validator thought (workflow queue item 10) and the indexes-validator drift — same family of "small validator prevents small drift."

- **`AskUserQuestion` use in `build-communication-style` is the reference pattern for backlog task `skill-interactive-options` (P99).** Not a rare one-off — it's the model the backlog wants to spread to other skills with categorical decision points. When that task gets picked up, this skill's paired-example calibration is the template.

- **No output-path drift** (neither skill saves to `output/claude-toolkit/...` — `build-communication-style` writes to `.claude/docs/`, `snap-back` writes nothing). Correct for the skills' purposes: these are preference docs, not session artifacts.

- **No orchestration-shaped leakage.** Both skills operate entirely within the consumer's session, modifying or consuming the consumer's own `.claude/docs/essential-preferences-communication_style.md`. No cross-project coordination. Workshop identity clean.

---

## Decision-point queue (carry forward)

**Resolved during review (pending execution — trivial scope):**

1. `build-communication-style/SKILL.md` line 11 — **update `/brainstorm-idea` reference → `/brainstorm-feature`** when the brainstorm rename ships (workflow queue item 3). Rename-lockstep, 1 occurrence.

**Coordinated with other audit directories:**

2. **`type:` frontmatter sweep** — contributes 2 instances from this subset (both `command`). Running total across audited subsets: 10 (4 workflow + 1 code quality + 3 design & arch + 2 personalization). Remaining dev tools and toolkit dev subsets will add more. Picked up by workflow queue item 7.

3. **Cross-reference validator** — `snap-back`'s `casual_communication_style` reference resolves (to `.claude/memories/`, not `.claude/docs/`), but the ambiguity of where to look surfaces a broader validator need: walk all `.claude/` markdown cross-references and resolve against docs + memories + agents + skills. Same family as the output-path validator (workflow queue item 10) and the indexes-validator drift. Worth bundling into a single "small validators" backlog item for stage-5 polish.

4. **`skill-interactive-options` backlog task (P99)** — `build-communication-style`'s `AskUserQuestion` use is the reference pattern. When the task gets picked up, this skill is the template; `brainstorm-idea` (and `brainstorm` after the rename) should also be evaluated for AskUserQuestion conversion.

**Still open / low-priority:**

5. **Frontmatter field ordering normalization** — `build-communication-style` uses a non-standard field order (`name, description, argument-hint, allowed-tools, type`). Most other skills use `name, type, description, ...`. The `type:` sweep resolves the `type` placement; broader ordering is a polish pass, not v3-blocking. Could be automated with a small linter.

6. **Cross-reference ambiguity polish** — optional qualification of `snap-back`'s `casual_communication_style` reference (e.g., "` casual_communication_style` memory") to disambiguate from docs-by-default reading. Status-quo is acceptable; the memory's auto-load conditions mean path-awareness isn't required of the reader.
