# v3 Audit — `.claude/skills/` (Toolkit Development subset)

Exhaustive file-level audit of the 9 Toolkit Development skills (per `docs/indexes/SKILLS.md` §Toolkit Development).

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`
**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

Skills audited: `create-skill`, `create-agent`, `create-docs`, `create-hook`, `evaluate-skill`, `evaluate-agent`, `evaluate-hook`, `evaluate-docs`, `evaluate-batch`.

---

## Summary

Nine skills, all workshop-shaped by construction: every one authors or evaluates resources inside the workshop itself (or a consumer's `.claude/`), none coordinate across projects. This is the **self-hosting** subset — the skills that build and judge the other resource types the workshop produces. Together they form the matched create/evaluate pairs (create-skill ⇄ evaluate-skill, create-agent ⇄ evaluate-agent, create-hook ⇄ evaluate-hook, create-docs ⇄ evaluate-docs) plus the `evaluate-batch` runner that dispatches them. `create-docs` has no `create-hook`-style dedicated resource template and ends up the leanest (142 lines) of the create-* set; the evaluate-* rubrics are the heaviest documents in the subset (256-335 lines).

Findings:

1. **`type:` frontmatter — the sweep is smaller than projected. Final full-directory count: 17, not ~19.** This subset contributes exactly **1** instance (`create-hook`). The other 8 skills in the subset carry no `type:` field. The dev-tools handoff projected ~6-7 more instances in this subset and a total of ~19 across the directory; reality is **17 total** (4 workflow + 1 code quality + 3 design & arch + 2 personalization + 6 dev tools + 1 toolkit dev = 17). Adjust the repo-wide sweep scope accordingly — one sweep commit covers 17 files, not 19.

2. **`evaluate-skill` is the consumer side of the sweep — Rewrite.** `evaluate-skill/SKILL.md` reads `type: knowledge|command` from frontmatter (line 259: *"Determine type from frontmatter (`type: knowledge|command`, default: `knowledge`)"*) and branches dimension interpretations on that value (lines 42-48 skill-types table, lines 54-58 D1/D2/D8 adjustments table, plus inline "Command type:" reinterpretations at lines 78, 82, 92, 156, 166). When the sweep moves the field to `metadata.type`, this skill is where the reader lookup changes. `evaluate-batch` passes the skill name through to `/evaluate-skill`, so it doesn't need to know about `type:` — only `evaluate-skill` does. This is the known, planned coupling — flagged for lockstep execution in the sweep commit.

3. **`create-hook` is the only subset skill that itself carries `type:` — Rewrite.** Line 3 of `create-hook/SKILL.md`: `type: command`. The other 8 skills in this subset have no `type:` field; per evaluate-skill's rubric they default to `knowledge`. That default is worth examining (queue item 3) — is "default knowledge" the right stance for evaluate-* rubrics and for the create-* workflow skills? But that's a sweep-adjacent question, not this subset's action.

4. **Cross-create consistency — only `create-skill` and `create-agent` use TEMPLATE.md; `create-docs` and `create-hook` do not.** `create-skill/resources/TEMPLATE.md` (41 lines, a full example skill) and `create-agent/resources/TEMPLATE.md` (63 lines, a full example agent) are both invoked as *"the LITERAL STARTING POINT"* (create-skill line 62, create-agent line 80). `create-docs` inlines a small skeleton directly (lines 42-71). `create-hook` inlines a skeleton with reference to `resources/HOOKS_API.md` (create-hook lines 46-103). The asymmetry matches the size of what's being authored (skills/agents have richer structure than docs/hooks), but it does mean `resources/TEMPLATE.md` is a naming convention only two of the four create-* skills follow. Not a bug — flag as cross-cutting for future consistency decisions.

5. **`create-hook/resources/HOOKS_API.md` is 548 lines — exceeds the 500-line supporting-file rule stated in `create-skill` itself** (`create-skill/SKILL.md` line 173: *"Supporting Files (resources/*.md) | <500 lines each | Prevent context bloat"*). This is the rule-maker violating its own rule. Two resolutions: (a) split HOOKS_API.md by section (events / types / input fields / output / config / debugging), or (b) loosen the rule in create-skill to 600 lines since HOOKS_API.md is a reference sheet, not a tutorial. Option (b) is lower-friction and more honest — the rule came from a concern about context bloat, and a 548-line reference loaded on-demand isn't the context bloat problem the rule was designed to catch. Flag as Defer, queue item 4.

6. **Evaluate-* rubric totals diverge (/120 vs /115) but percentage is the primary score tracker — Keep, not an issue.** `evaluate-skill` is 120 pts (8 dimensions), `evaluate-agent` / `evaluate-hook` / `evaluate-docs` are 115 pts (5-6 dimensions). User-confirmed principle: raw totals are for traceability, `percentage` is what users and `evaluate-batch` compare against (line 207: *"The `percentage` field normalizes across types — use it for cross-type comparisons and thresholds (e.g., 85% quality gate)"*). Divergence in absolute totals is expected and already handled. No action — noting the principle so future rubric changes (adding a dimension to one evaluator, reweighting) don't trigger spurious lockstep-update requests on the others.

7. **Invocation pattern: evaluate-* skills all launch a subagent for "fresh, unbiased evaluation."** Each evaluate-* skill (evaluate-skill:240, evaluate-agent:165, evaluate-hook:155, evaluate-docs:204) embeds identical invocation guidance:

   ```
   Task tool with:
     subagent_type: "general-purpose"
     model: "opus"
     prompt: |
       ...
       Perform FRESH scoring. Do NOT read evaluations.json or prior scores.
   ```

   Consistent across all four, correct for the "unbiased evaluation" concern. Model choice (`opus`) is worth cross-checking against agents queue items 1-2 (code-reviewer / implementation-checker flipping opus → sonnet for structured checklist work). Evaluate-* rubrics are rubric-scoring work, which is structured checklist territory — same argument for sonnet would apply. Queue item 5 (cross-audit thread).

8. **No `brainstorm-idea` / `casual_communication_style` See also references in this subset.** Workflow queue item 3 (brainstorm rename to `/brainstorm-feature`) and personalization queue item 1 (`casual_communication_style` removal) impose zero lockstep burden here. Confirmed by grep across all 9 skills.

9. **`create-docs` vs `/write-documentation` disambiguation is correct.** `create-docs` description (line 3): *"Do NOT use for updating existing docs or writing README/docstrings (use /write-documentation)."* `write-documentation` (audited in dev-tools subset) has the reciprocal scope. Clean disambiguation, matches the personalization subset's finding that explicit negative-trigger disambiguation works.

**User resolutions surfaced during review:**

- **`create-hook` gets two concrete follow-ups (user-raised):** (1) add an explicit link to the official Claude Code hooks documentation (currently only `resources/HOOKS_API.md` line 3 links out; the skill body does not), (2) replace the inline Bash PreToolUse starting-point script (lines 44-103) with a template under `resources/` — matching the `create-skill` / `create-agent` `resources/TEMPLATE.md` convention. The template should encode the current match/check + dual-mode trigger structure so new hooks start from the right shape by file-copy, not by re-typing. See queue item 9.
- **Evaluate-* rubric percentage is the primary score tracker (user-noted):** all 4 rubrics already normalize via `percentage` — raw totals (/120 vs /115) are for traceability, not headline comparison. Noting here so future rubric changes stay aligned with this principle: dimension totals can diverge across evaluator types; percentage is what users and `evaluate-batch` compare against. This reframes cross-cutting finding 6 and queue item 8 as non-issues (divergence is expected and already handled, not drift).

Findings below: 2 Rewrites (`evaluate-skill` consumer-side of sweep, `create-hook` own `type:` field), 1 Defer (HOOKS_API.md 548-line rule violation), 6 Keep-with-sweep (content clean, `type:` sweep touches 1 of them). No Investigate.

---

## Files

### `create-skill/SKILL.md`

- **Tag:** `Keep` (no sweep touch — no `type:` field)
- **Finding:** 243 lines. No `type:` frontmatter. Red-Green-Refactor framing (lines 15-55) — treat skill authoring as TDD with a documented failure-mode ("failing test") before writing. The framing is load-bearing: without it, the skill-creation loop drifts toward solving imaginary problems (anti-pattern table line 227: *"No Failing Test | Skill solves imaginary problem"*).

  **Rationalization tables** (lines 32-41, 234-245) — distinct from anti-pattern tables. Anti-pattern tables capture *structural mistakes* (3 columns: pattern/problem/fix); rationalization tables capture *excuses for skipping the process* (2 columns: rationalization/counter). The distinction is expert knowledge — skill authors who haven't encountered discipline-enforcing skills (TDD, code review, wrap-up) won't know to build a rationalization table, and without one the resulting skill gets argued out of on the first real invocation. The explicit "Use both when building discipline-enforcing skills" (line 234) resolves the ambiguity.

  **Description rules** (lines 83-89) — description is pure trigger, never workflow. The *why* (*"Claude's tool routing uses the description to decide whether to load the skill. If the description contains workflow steps...Claude may execute those steps directly from the description without reading the full SKILL.md body—missing nuances, anti-patterns, and edge cases"*) is the kind of expert insight that makes the rule obvious; without the *why*, rule compliance is shallow.

  **Disambiguation** (lines 91-96) — negative triggers (*"Do NOT use for X (use /other-skill)"*) + 1024-char hard limit. Matches `/brainstorm-idea` and `/create-docs`'s actual description shape — both explicitly disambiguate with negative triggers. Rule pulled from the field.

  **Progressive Disclosure Pattern** (lines 137-188) — decision tree (line 140-151) gates at 400 lines; full structure + reference style + example. The example (lines 184-188) points at `create-hook` as the canonical progressive-disclosure case: SKILL.md ~165 lines + resources/HOOKS_API.md 400 lines. That number is stale — HOOKS_API.md is now 548 lines (see queue item 4). Either update the example number or loosen the supporting-file rule.

  **Quality Gate** (lines 198-204) — 85% target, directs to `/evaluate-skill`. D7 Integration Quality callout explicitly names the ecosystem-awareness dimension. Matches the evaluate-skill rubric structure.

  **Iteration Example** (lines 213-221) — uses a hypothetical changelog skill as the concrete narrative. Anchors the red-green-refactor process in a real scenario (first attempt had steps but no anti-patterns → second added anti-pattern table → Claude self-corrects). Good shape.

  **See also** (line 205): `/create-agent`, `/create-hook`, `/create-docs`, `relevant-toolkit-resource_frontmatter` doc. All 4 exist.

  Workshop-shaped: authors skills inside `.claude/skills/` (workshop or consumer). The skill runs in the authoring session, writes to the authoring repo's `.claude/skills/<name>/SKILL.md`. No cross-project coordination.

- **Action:** None beyond queue item 4 (decide whether to bump the supporting-file rule to accommodate HOOKS_API.md, or split it). Line 188 reference to `create-hook`'s `resources/HOOKS_API.md` ("400 lines") is stale — update to actual count or drop the line count.
- **Scope:** trivial (1-line doc polish, contingent on queue item 4 decision).

### `create-agent/SKILL.md`

- **Tag:** `Keep` (no sweep touch — no `type:` field)
- **Finding:** 246 lines. No `type:` frontmatter. Structured around a decision tree (*Agent vs Skill Decision*, lines 32-40) that's the correct first gate: does this need to CHANGE how Claude behaves (agent) or add knowledge/workflow (skill)? The tree is tight.

  **Behavioral delta** (line 44-49) — the agent-specific analog of the skill's "knowledge delta" formula. *"What does this agent do that default Claude doesn't?"* — different perspective, stricter constraints, specialized output format. Same shape as `/evaluate-agent`'s core formula (`Good Agent = Specialized Mindset − Claude's Default Approach`).

  **Persona Calibration table** (lines 86-90) — 3 weak/strong pairs (Reviewer / Finder / Verifier). Expert knowledge: *"You review code"* is a job title, not a behavioral constraint; *"You are a skeptical reviewer who assumes bugs exist until proven otherwise"* forces a specific stance. This is the distinct value-add over generic agent creation.

  **Tool Selection Heuristic** (lines 102-111) — start with Read/Grep/Glob, add selectively, flag at >4 tools. The "split or narrow scope" trigger at >4 tools is the right shape — matches evaluate-agent D4 (anti-pattern: *"Tools: Read, Write, Edit, Bash, Grep, Glob | Tool hoarding"*).

  **First-Attempt Checklist** (lines 115-123) — 6-item checklist before running `/evaluate-agent`. Acts as a pre-submit gate to avoid the common 54%-then-iterate-up-to-83% loop shown in `Iteration Reference` line 212-217. The checklist items are exactly the dimensions `/evaluate-agent` penalizes (persona specificity → D3, "What I Don't Do" → D1, output format → D2, tool set → D4).

  **Edge Cases** (lines 125-183) — scope overlap (lines 128-136), persona red flags (lines 140-150), reviewer/verifier requirements (lines 152-175), when to abandon (lines 177-183). Reviewer/verifier section is the load-bearing one: *"Agents that evaluate, check, or validate work need explicit rejection criteria to prevent rubber-stamping"* — hard-won lesson from evaluate-agent's D2 anti-pattern. Includes a hypothetical migration-reviewer example (lines 160-173) with SAFE/UNSAFE/CONDITIONAL + Automatic Fails, then points at the three production reviewer agents (goal-verifier, code-reviewer, implementation-checker) — line 175. Good, concrete.

  **Iteration Reference** (lines 196-239) — two worked examples. The `deploy-checker` example (lines 211-217) walks through per-dimension scoring (54% → 83%) with the specific fix for each failing dimension. The `code-reviewer` end-to-end walkthrough (lines 219-239) shows the full workflow: behavioral delta → write from template → first attempt 78% → fix D3+D2 → second attempt 91%. Anchors the red-green-refactor process in real agents that exist in the repo.

  **See also** (line 22): `/evaluate-agent`, `/create-skill`, `/create-hook`, `/create-docs`, `relevant-toolkit-resource_frontmatter`. All 5 exist.

  **`resources/TEMPLATE.md`** (63 lines) — full example agent (`config-auditor`). Well-formed: frontmatter, persona, Focus, What I Don't Do, Output Format, Output Path, post-write summary. One cross-check note: the template uses `output/claude-toolkit/reviews/` as its output path (line 57), which matches the session-review artifact convention confirmed in dev-tools subset.

  Workshop-shaped: authors agents inside `.claude/agents/` (workshop or consumer). The skill runs in the authoring session, writes to the authoring repo's `.claude/agents/<name>.md`. No cross-project coordination.

- **Action:** None.
- **Scope:** N/A.

### `create-docs/SKILL.md`

- **Tag:** `Keep` (no sweep touch — no `type:` field)
- **Finding:** 142 lines — the shortest of the create-* set. No `type:` frontmatter. No `resources/` subdir (inlines the small skeleton directly in the body, lines 42-71).

  **Decision tree** (lines 18-26) — doc vs memory vs skill. Three-way branch: prescriptive rules/conventions (doc), organic context/preferences (memory), step-by-step procedures (skill). Matches `relevant-toolkit-context.md` authority on the docs/memories boundary — which is the source of truth `evaluate-docs` defers to (evaluate-docs line 27).

  **File Format** (lines 42-71) — essential vs relevant pattern shown directly. Uses `**MANDATORY:**` for essential (auto-loaded), `**ONLY READ WHEN:**` for relevant (on-demand). Matches evaluate-docs D2 scoring rubric (lines 89-92: *"Essential docs: `**MANDATORY:** Read at session start - affects all [scope]` · Relevant docs: `**ONLY READ WHEN:**` + bullet list of triggering contexts"*). Skill and rubric are lockstep.

  **Naming** (line 78): `{category}-{context}-{name}` with `essential-` (auto-loaded) / `relevant-` (on-demand) prefixes. Defers to `relevant-conventions-naming` (See also line 30) and `relevant-toolkit-context.md` for the full authority.

  **When to Merge vs Split Docs** (lines 86-95) — merge under 200 lines + topics always together; split over 300 lines or different update frequencies. The 200-line merge threshold and 300-line split threshold are calibrated — gives a 100-line "either is fine" zone rather than a hard boundary.

  **Pre-Save Validation Checklist** (lines 99-105) — 5-item checklist. Same pre-submit-gate pattern as create-agent's First-Attempt Checklist. The "Not a memory?" item is the load-bearing one — the doc-vs-memory boundary is the most common source of misclassification.

  **Worked examples** (lines 113-131) — two bad requests with corrections. The API-endpoints example (lines 115-123) resolves ambiguity by forcing the user to decide between conventions doc and reference list. The sprint-work example (lines 125-131) redirects organic context to memory. Both are the class of misunderstanding that generates the wrong resource without the skill.

  **Anti-Patterns** (lines 133-143) — 6 patterns. "Organic Context as Doc" is the primary one; "Wrong Category" (essential that's rarely needed) maps to evaluate-docs D4 anti-pattern line 182 (*"Essential doc rarely needed | Wastes context every session | Demote to `relevant-` | D4: -5"*). Aligned.

  **See also** (line 30): `/evaluate-docs`, `/list-docs`, `/create-skill`, `/create-hook`, `/create-agent`, `relevant-conventions-naming`. All 6 exist.

  Workshop-shaped: authors docs inside `.claude/docs/` (workshop or consumer). The skill runs in the authoring session, writes to the authoring repo's `.claude/docs/<file>.md`. No cross-project coordination.

- **Action:** None.
- **Scope:** N/A.

### `create-hook/SKILL.md`

- **Tag:** `Rewrite` (carries `type:` — sweep touches this file, plus the one stale line-count reference)
- **Finding:** 346 lines. `type: command`. Companion file `resources/HOOKS_API.md` (548 lines) — the only subset skill exceeding the 500-line supporting-file rule stated in create-skill itself (see cross-cutting queue item 4).

  **Match/check pattern** (lines 36-42) — the core authoring guidance for Bash PreToolUse hooks. Three functions: `match_<name>` (cheap predicate, no forks), `check_<name>` (guard body), `main` (standalone entry point). Dual-mode trigger (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) lets the same file work standalone or when sourced by `grouped-bash-guard.sh`. Defers full contract to `.claude/docs/relevant-toolkit-hooks.md` (line 42) — correct scope-carving: skill teaches the shape, doc owns the contract.

  **Starting-point script** (lines 44-103) — 60-line Bash template with match/check + dual-mode trigger + shared-library sourcing. Used as the LITERAL STARTING POINT for new hooks. The `${BASH_SOURCE[0]}` vs `$0` note (line 105) is the kind of non-obvious detail that trips authors — if the skill didn't explicitly call it out, every new hook would use `$0` and break when sourced by the dispatcher.

  **Shared library functions** (lines 109-115) — 6 functions (`hook_init`, `hook_require_tool`, `hook_get_input`, `hook_block`, `hook_approve`, `hook_inject`). Matches evaluate-hook D4 scoring rule (line 92: *"Sources shared library, uses standardized outcome helpers"*).

  **Hook registration** (lines 129-157) — standalone vs grouped mode, explicit "never both" constraint. The "Dual registration" anti-pattern is called out twice (line 131 + line 331's anti-pattern table).

  **Quality Gate** (line 160-163) — 85% target via `/evaluate-hook`.

  **Multi-event examples** (lines 165-268) — PostToolUse example (lines 165-190), Notification example (lines 193-215), PermissionRequest example (lines 218-268). PermissionRequest example (lines 222-245) shows an allowlist pattern auto-approving safe commands (`make (test|check|lint|format)`) — the example is load-bearing because PermissionRequest is the least-documented event type in the toolkit.

  **Anti-Patterns** (lines 325-337) — 9 patterns including "Env var bypass" (line 337: *"Defeats the hook's purpose; user can just run the command directly if needed"*). Matches evaluate-hook's anti-pattern table (evaluate-hook line 197 *"Env var bypass | Defeats the hook's purpose | Remove ALLOW_* overrides"*). Lockstep.

  **Troubleshooting** (lines 339-345) — 4 common issues with fixes. Short, concrete.

  **See also** (line 10): `.claude/docs/relevant-toolkit-hooks.md`, `/evaluate-hook`, `/create-skill`, `/create-agent`. All 4 exist.

  **`type: command`** — correct type classification. This skill is a procedural authoring workflow (step-by-step with templates and examples), not pure knowledge. Picked up by repo-wide sweep.

  Workshop-shaped: authors hooks inside `.claude/hooks/` (workshop or consumer). The skill runs in the authoring session, writes to the authoring repo's `.claude/hooks/<name>.sh`. No cross-project coordination.

- **Action:** (1) `type: command` → `metadata: { type: command }` as part of repo-wide sweep (queue item 2). (2) Contingent on queue item 4: if HOOKS_API.md stays 548 lines, update create-skill's reference to its line count (create-skill line 188 says "400 lines"); if HOOKS_API.md is split, update the references here accordingly.
- **Scope:** (1) trivial (sweep-covered). (2) trivial (1-line doc polish).

### `evaluate-skill/SKILL.md`

- **Tag:** `Rewrite` (consumer side of `type:` sweep — rubric reads the field)
- **Finding:** 335 lines — the largest evaluate-* rubric. No `type:` frontmatter on this file itself. `compatibility: jq` declared; `allowed-tools: Read, Write, Glob, Agent, Bash(jq:*)` — scoped correctly.

  **Two-layer rubric** (lines 40-71) — knowledge vs command skill types, with dimension-specific adjustments for D1/D2/D8 when skill is command-typed. Lines 42-48 type classification table, lines 54-58 dimension interpretation table, lines 62-70 D1 calibration for command type. This is the **consumer side of the repo-wide `type:` sweep** — lines 259 reads `type: knowledge|command` from frontmatter. When the sweep moves the field to `metadata.type`, this skill's step 2 of the Evaluation Protocol (line 259) and the skill-types table (lines 42-48) need to update to read `metadata.type` instead.

  **8 Dimensions × 120 pts** (lines 73-167) — D1 Knowledge Delta (20), D2 Mindset+Procedures (15), D3 Anti-Pattern Quality (15), D4 Specification Compliance (10), D5 Progressive Disclosure (15), D6 Freedom Calibration (15), D7 Integration Quality (15), D8 Practical Usability (15). Note: D8 exists here but not in evaluate-agent/hook/docs — the skills rubric is one dimension and 5 points richer than the others (see cross-cutting finding 6).

  **D4 Specification Compliance** (lines 97-106) — covers description keywords (negative triggers expected when sharing keyword space), tool scoping (command skills must declare `allowed-tools`), external dependencies (must declare `compatibility`), and `user-invocable: false` skills (description as sole routing mechanism). This is where the rubric teeth bite — the description rules defined in create-skill line 83-89 are enforced here.

  **D5 Supporting Files Checklist** (lines 122-132) — deductions for >500 lines, no TOC on >100 lines, nested references, bare references, orphaned files. The >500 lines deduction (-3 per file) is exactly what would catch `create-hook/resources/HOOKS_API.md` at 548 lines (queue item 4). If evaluate-skill runs on create-hook today with the current HOOKS_API.md, it should take a -3 deduction on D5.

  **D7 Integration Quality** (lines 146-152) — reference accuracy, duplication avoidance, handoff clarity, ecosystem awareness, terminology consistency. The callout in create-skill (line 204: *"D7 (Integration Quality): Check that references point to real resources, defer to existing content instead of restating it, and connect to related skills/agents/docs"*) is lockstep with this rubric.

  **Evaluation Protocol** (lines 257-267) — 7 steps. Step 2 is the type-reading step. Step 7 updates `docs/indexes/evaluations.json` via jq — writes the `type` field as part of the JSON output (line 224: `"type": "knowledge|command"`). The JSON output schema (lines 218-233) also carries the `type` field — when the sweep moves to `metadata.type`, the question arises whether the evaluations.json schema keeps `type` at the top level or also nests it under `metadata`. Queue item 5.

  **Example Evaluation** (lines 269-314) — hypothetical `git-workflow` skill, before (38%) and after (91%) with per-dimension evidence. The example uses `type: knowledge` implicitly (knowledge delta framing). If the sweep renames the field, this example stays valid text-wise.

  **See also** (lines 316-323): `/evaluate-agent`, `/evaluate-hook`, `/evaluate-docs`, `/evaluate-batch`, `/create-skill`, `relevant-toolkit-resource_frontmatter`. All 6 exist.

  **Meta-question** (lines 325-335) — two framings (knowledge vs command). Knowledge: *"Would an expert say this captures knowledge requiring years to learn?"* Command: *"Does this flow produce more consistent results than a natural language prompt asking for the same task?"* Both good distillations.

  Workshop-shaped: evaluates skills that the workshop produces (or that consumers have authored). Runs in the authoring/consumer session, writes to `docs/indexes/evaluations.json`. No cross-project coordination.

- **Action:** (1) Consumer side of `type:` sweep — lockstep update in the sweep commit: line 259 Evaluation Protocol step 2, lines 42-48 Skill Types table, lines 52-58 Dimension Adjustments table, and the JSON output schema (line 220-232) all need to read `metadata.type` (or whatever the sweep target shape settles on). (2) Decide whether `evaluations.json` JSON output keeps `type` at top level or nests it (queue item 5).
- **Scope:** (1) moderate — sweep-covered but the rubric changes are non-trivial (several tables + protocol step). (2) small — one-line schema decision.

### `evaluate-agent/SKILL.md`

- **Tag:** `Keep` (no sweep touch — rubric doesn't read `type:`)
- **Finding:** 262 lines. No `type:` frontmatter. `compatibility: jq` declared; `allowed-tools` scoped.

  **5 Dimensions × 115 pts** (lines 40-114) — D1 Right-sized Focus (30) - most critical, D2 Output Quality (30), D3 Coherent Persona (25), D4 Tool Selection (15), D5 Integration Quality (15). D1+D2 weight 60/115 — the *what* and *how* of agent behavior. D3 persona at 25 is the behavioral-constraint dimension (matches create-agent's Persona Calibration table).

  **D4 Tool Selection — scoring rule** (line 93): *"If the agent's purpose explicitly requires a tool (e.g., 'writes a report' → Write), award full credit. Don't penalize for tools the agent explicitly says it won't use anyway."* This rule is subtle but important — it prevents the rubric from double-penalizing an agent whose purpose inherently needs broad tool access (e.g., `code-debugger` legitimately needs Edit + Write + Bash). Without the rule, D4 would systematically underscore action-oriented agents.

  **Anti-Pattern Detection** (lines 127-135) — textual signals: "comprehensive/thorough/all aspects" → D1 scope creep; no output format → D2 unclear handoff; "You are an assistant that..." → D3 weak persona; full tool list → D4 hoarding; reviewer with no rejection criteria → D2 rubber-stamp risk. Each signal ties back to a specific dimension — the rubric stays grep-able.

  **Edge Cases** (lines 137-145) — single-purpose runner (D1 near-perfect), multi-step orchestrator (allow broader D1), read-only analyzer (penalize Edit/Write on D4), interactive agent (D2 allows conversational output), reviewer/verifier (D2 must define explicit rejection criteria). The reviewer/verifier edge case is the most load-bearing — without it the rubric would rubber-stamp reviewers that rubber-stamp everything.

  **Invocation** (lines 166-181) — launch subagent with `opus` model. Same invocation pattern as evaluate-skill. Model choice questionable for checklist-structured work (see cross-cutting finding 7 + queue item 5).

  **Example Evaluation** (lines 195-248) — `code-helper` → `test-coverage-analyzer` transformation (45% → 85%). Shows the per-dimension improvement: D1 8→28 (specific scope), D2 10→27 (template), D3 7→20 (persona), D4 5→13 (minimal tools), D5 3→10 (references). The worked example is tight and anchored in an agent shape that could plausibly be authored.

  **See also** (lines 250-256): `/evaluate-skill`, `/evaluate-hook`, `/evaluate-docs`, `/evaluate-batch`, `/create-agent`, `relevant-toolkit-resource_frontmatter`. All 6 exist.

  Workshop-shaped: evaluates agents. Runs in the authoring/consumer session, writes to `docs/indexes/evaluations.json`. No cross-project coordination.

- **Action:** None for `type:` sweep (rubric doesn't read the field — agents don't have `type:`). Optional: consider opus → sonnet per queue item 5.
- **Scope:** N/A.

### `evaluate-hook/SKILL.md`

- **Tag:** `Keep` (no sweep touch — rubric doesn't read `type:`)
- **Finding:** 303 lines. No `type:` frontmatter. `compatibility: jq` declared; `allowed-tools` scoped.

  **6 Dimensions × 115 pts** (lines 39-133) — D1 Correctness (25), D2 Testability (20), D3 Safety & Robustness (20), D4 Maintainability (20), D5 Documentation (15), D6 Integration Quality (15). D1+D4 together (45 pts) = correctness + structure, D2+D3 (40 pts) = verifiability + safety. Balanced weighting.

  **D1 Correctness — match/check specifics** (lines 44-56): Bash PreToolUse hooks must use `match_<name>` + `check_<name>` + `main` + dual-mode trigger. False-negative risk on `match_` is explicitly called out (line 55: *"is `match_` broad enough that it won't skip a case `check_` should catch? False positives are fine; false negatives are safety regressions"*). This is the expert-knowledge delta — a naive evaluator would not know that match/check has asymmetric failure modes.

  **D3 Safety — safety-vs-UX tension** (line 85): *"The core hook design tradeoff. A secrets-guard hook that's too strict blocks `.env.example` commits (false positive noise). One that's too loose misses `.env.local` (security gap). Score based on how thoughtfully this tension is resolved — not just whether it works."* Anchored in a concrete dual-failure scenario. Expert knowledge.

  **D4 Maintainability — match cheapness contract** (lines 101-103): `match_` uses only bash pattern matching — no `$(...)`, no `jq`, no `git`, no I/O. Violating defeats dispatcher work-avoidance. `_BLOCK_REASON` convention enforced. No-duplicated-logic constraint with the dispatcher. All three rules are lockstep with `create-hook`'s match/check guidance (create-hook lines 36-42) and with `.claude/docs/relevant-toolkit-hooks.md` (referenced in the See also line 225).

  **Anti-Patterns** (lines 188-205) — 16-pattern table with score-impact per dimension. Patterns 10-16 are match/check-specific (forks in match_, match narrower than check triggers, missing dual-mode trigger, `$(dirname "$0")` wrong source path, dual registration, inline `hook_block` in `check_`, monolithic Bash PreToolUse hook). Each has calibrated score deductions per dimension. This is the densest anti-pattern table in the subset — reflects the hook domain's high footgun density.

  **Edge Cases** (lines 207-216) — logging-only, simple passthrough, multi-tool, notification/SessionStart, non-Bash PreToolUse, match/check hook. Non-Bash PreToolUse edge case (line 215) is critical: *"Match/check + dispatcher not required — only Bash is grouped today. Don't penalize D1/D4 for a monolithic shape here."* Without this the rubric would over-penalize hooks like `suggest-read-json` (Read-tool PreToolUse, not Bash).

  **Example Evaluations** (lines 227-303) — two walked examples. Good (78.3% `enforce-make-commands.sh`) shows dimension-by-dimension evidence. Before/After (15.7% → 75.7% `secrets-guard`) shows how sourcing the shared library + using `hook_block` + adding allowlists transforms a broken hook into a usable one. The "Key fixes" summary at the end (line 303) crystallizes the dimensional improvements. Note: the After example (lines 266-291) uses `$(dirname "$0")` which would take the -5 "wrong source path" deduction from the same rubric's anti-pattern table (line 202). Internal inconsistency — the example doesn't follow its own anti-pattern rule. Flag as polish item, queue item 6.

  **See also** (lines 218-225): `/evaluate-skill`, `/evaluate-agent`, `/evaluate-docs`, `/evaluate-batch`, `/create-hook`, `.claude/docs/relevant-toolkit-hooks.md`. All 6 exist.

  Workshop-shaped: evaluates hooks. Runs in the authoring/consumer session, writes to `docs/indexes/evaluations.json`. No cross-project coordination.

- **Action:** (1) Fix internal inconsistency: After example at line 274 should use `${BASH_SOURCE[0]}` instead of `$0` to avoid contradicting the rubric's own anti-pattern table (line 202). 1-line fix. (2) Optional: consider opus → sonnet per queue item 5.
- **Scope:** (1) trivial.

### `evaluate-docs/SKILL.md`

- **Tag:** `Keep` (no sweep touch — rubric doesn't read `type:` on docs)
- **Finding:** 256 lines. No `type:` frontmatter. `compatibility: jq` declared; `allowed-tools` scoped.

  **6 Dimensions × 115 pts** (lines 63-149) — D1 Naming & Placement (20), D2 Quick Reference Section (25) - required, D3 Content Scope (20), D4 Relevance & Freshness (15), D5 Structure & Formatting (20), D6 Integration Quality (15). D2 at 25 (highest weight) reflects the Quick Reference's load-bearing role: it's the sole mechanism for on-demand doc discoverability.

  **How Doc Loading Works** (lines 29-42) — critical section. Three load paths: session-start hook (essential-*), user request (/list-docs or explicit), hook injection (PreToolUse/PostToolUse). Explicitly states: *"There's no reliable spontaneous loading. Claude won't read docs mid-session unprompted."* This forces the D4 scoring logic: if a doc needs to be loaded and isn't essential-*, it needs to be discoverable via `/list-docs`. Shapes the whole rubric's expectations.

  **Doc vs Skill / Doc vs Memory distinctions** (lines 44-61) — two comparison tables. Matches create-docs' decision tree (create-docs lines 18-26) lockstep.

  **D3 Content Scope — duplication carving** (line 104): *"Only flag duplication between **synced resources** — other docs, skills, and agents. Do NOT flag overlap with toolkit-internal files (indexes, project CLAUDE.md) since docs are the portable artifacts that get synced to other projects."* Expert knowledge about the workshop's sync model — without this carving, the rubric would over-penalize docs that share content with the workshop's own indexes.

  **D4 Relevance & Freshness — load-timing logic** (lines 119-122): *"Essential docs are auto-loaded — they must justify the context cost every session. Relevant docs are on-demand — Quick Reference should accurately describe when to load."* Calibrates the D4 bar: essential-* docs have to earn their context cost every session; relevant-* docs have to be discoverable.

  **Edge Cases** (lines 151-156) — two cases: should-be-memory (move to `.claude/memories/`), should-be-skill (extract to skill). Both trigger the classification decision tree in create-docs.

  **Anti-Patterns** (lines 172-183) — 7 patterns with score impacts. "Doc that should be a skill | Procedures masquerading as reference" matches create-docs' decision tree (create-docs line 28: *"For procedures (step-by-step workflows), use /create-skill instead"*). Lockstep.

  **Reference authority** (line 27): *"See `relevant-toolkit-context.md` (in `.claude/docs/`) for authoritative naming/category conventions and the docs/memories boundary."* Delegates to the canonical source. Same as the See also (line 255) pointing to `relevant-toolkit-context` as source-of-truth for D1/D2.

  **Example Evaluation** (lines 236-247) — `relevant-workflow-branch_development.md`, scored 108/115 (93.9%) with per-dimension evidence. Short, anchored in a doc that actually exists in the workshop.

  **See also** (lines 250-256): `/create-docs`, `/evaluate-skill`, `/evaluate-agent`, `/evaluate-hook`, `relevant-toolkit-context`. All 5 exist.

  Workshop-shaped: evaluates docs. Runs in the authoring/consumer session, writes to `docs/indexes/evaluations.json`. No cross-project coordination.

- **Action:** None for `type:` sweep. Optional: consider opus → sonnet per queue item 5.
- **Scope:** N/A.

### `evaluate-batch/SKILL.md`

- **Tag:** `Keep` (no sweep touch — runs the evaluator but doesn't read `type:` itself)
- **Finding:** 276 lines. No `type:` frontmatter. `compatibility: jq` declared; `allowed-tools: Read, Write, Glob, Agent, Bash(jq:*)` — scoped correctly (Agent needed for parallel evaluator dispatch).

  **Why Batch** (lines 12-21) — states value proposition: consistency + reduced cognitive load, not just parallelism. The "not just parallelism" framing is important — it forestalls the common misreading that this is a performance skill.

  **When NOT to Batch** (lines 21-27) — three cases (single resource, deep-dive, debugging). Each has a concrete reason against batching. Good scope-carving — prevents batch-everything anti-pattern.

  **Token Economics** (lines 29-36) — ~10-15K tokens per parallel agent. Batch of 5 = ~50-75K. For 20+ resources, sequential batches of 5. Sets expectations honestly.

  **Early Stopping Criteria** (lines 38-44) — 3 patterns that trigger a pause/stop. *"3+ resources with same D1 issue | Pause - fix systematic problem first"* is the load-bearing rule — prevents the common batch-then-miss-systematic-issue trap.

  **Parameters** (lines 48-54) — type (required), batch-size (default 5), re-evaluate (default false). Parsed from `$ARGUMENTS`. Matches command-skill pattern.

  **Filter step** (lines 69-83) — uses `cli/eval/query.sh unevaluated` and `cli/eval/query.sh stale` (verified exists at `cli/eval/query.sh`). Staleness check is hash-based (`md5sum <file> | cut -c1-8`). The critical note (lines 80-82): *"Hash-based staleness only catches resource changes. If the evaluate-* skill rubric has changed, resources may need re-evaluation even with matching hashes. When the user requests a full re-evaluation, skip staleness checks entirely."* This is the `re-evaluate=true` use case — explicit handling for the "rubric changed, content didn't" scenario that the sweep itself will create (when `evaluate-skill` updates to read `metadata.type`, all prior skill evaluations become stale even though the skill files haven't changed).

  **Process** (lines 58-171) — 4 steps: find, filter, process batches (with 3a launch, 3b collect, 3c write, 3d report sub-steps), final summary. The "Write after each batch" contract (lines 157, 220-231) is the resilience pattern — interrupted batches are recoverable because completed batches are already persisted. Matches the agent dispatch pattern used by the evaluate-* skills (evaluate-skill line 240 etc.).

  **Dependency Order** (lines 197-206) — skills → hooks → docs → agents for full audits. Rationale: agents may reference skill patterns; docs may reference skills; hooks are independent. Detection heuristic: *"Check agent files for `/skill-name` references to identify dependencies."* Concrete and mechanical.

  **Score normalization** (line 207): *"Each resource type has its own dimension structure and max score (e.g., skills: /120, agents: /115, hooks: /115). The `percentage` field normalizes across types — use it for cross-type comparisons and thresholds (e.g., 85% quality gate)."* This is the honest resolution of the finding-6 divergence between evaluate-skill (120 pts) and the other evaluators (115 pts). Batch-level normalization handles what individual rubrics can't.

  **Error Handling** (lines 209-231) — 4 errors + resume contract. The resume example (lines 221-231) walks through 15 resources with batch-size=5 interrupted after batch 2, showing how re-running picks up the remaining 5.

  **Anti-Patterns** (lines 268-276) — 5 patterns. "Bypassing skills" (line 270-272) is the load-bearing one: *"Each evaluator outputs different JSON structures and dimension names — manually writing evaluation logic produces inconsistent formats that break evaluations.json merging and cross-resource comparisons."* Forestalls the plausible-but-wrong shortcut of "just score it myself in the dispatcher."

  Workshop-shaped: batch-runs evaluate-* skills. Runs in the authoring/consumer session, writes to `docs/indexes/evaluations.json`. No cross-project coordination.

- **Action:** None for `type:` sweep. Optional: consider opus → sonnet for dispatched evaluator agents per queue item 5.
- **Scope:** N/A.

---

## Cross-cutting notes

- **`type:` frontmatter sweep — final full-directory count is 17, not ~19.** This subset contributes exactly 1 instance (`create-hook`), so the repo-wide sweep covers 17 files, not the 19 projected from earlier subsets' grep. Breakdown across all 6 audited subsets:
  - Workflow: 4
  - Code quality: 1
  - Design & arch: 3
  - Personalization: 2
  - Dev tools: 6
  - Toolkit dev (this subset): 1
  - **Total: 17**

  18 skills in the directory (35 total - 17) carry no `type:` field at all. Per `evaluate-skill`'s rubric (line 259), these default to `knowledge` — which is probably fine for most, but worth examining: are any of those 18 actually command-shaped and would benefit from explicit declaration? Queue item 3.

- **Consumer side of the sweep lives in `evaluate-skill` only.** Lines 42-48 (Skill Types table), 54-58 (Dimension Adjustments table), 259 (Evaluation Protocol step 2), and the JSON output schema (line 224) all read the `type` field. `evaluate-batch` does not read `type` — it just passes through to `/evaluate-skill`. `evaluate-agent` / `evaluate-hook` / `evaluate-docs` don't have a `type` field in their rubrics at all. One file to update in lockstep with the sweep.

- **`create-hook/resources/HOOKS_API.md` exceeds `create-skill`'s own supporting-file rule.** File is 548 lines; `create-skill` line 173 says supporting files should be under 500. Rule-maker violates its own rule. Resolution options:
  - **Option A (loosen the rule):** bump the create-skill threshold to 600 lines, noting that reference sheets (vs tutorials) may legitimately exceed 500.
  - **Option B (split HOOKS_API.md):** partition by section — events, types, input fields, output format, settings.json config, debugging. Each becomes its own file under 500.

  Option A is lower-friction and more honest about the reference-vs-tutorial distinction. Option B is purer but adds navigation overhead. Queue item 4.

- **Evaluate-* model choice (`opus`) is worth a second look.** Each of the 4 evaluate-* skills dispatches a general-purpose subagent with `model: "opus"` (evaluate-skill:240, evaluate-agent:165, evaluate-hook:155, evaluate-docs:204). Rubric scoring is structured checklist work — which the agents queue (items 1-2 from prior subsets) is moving toward sonnet for agents like `code-reviewer` and `implementation-checker`. Same argument applies here: the evaluators aren't doing deep reasoning, they're applying a rubric. Queue item 5.

- **Create/evaluate matched-pair lockstep.** Each create-* skill's quality gate points at its evaluate-* sibling (create-skill line 199 → /evaluate-skill, create-agent line 74 → /evaluate-agent, create-hook line 161 → /evaluate-hook, create-docs line 110 → /evaluate-docs), and each evaluate-* See also points back at its create-* sibling. The pairs are tight — same pattern as the worktree pair (setup/teardown) and the comm-style pair (build-communication-style/snap-back) from prior subsets. When pairs are this tight, changes propagate cleanly.

- **`resources/TEMPLATE.md` convention is partial.** Only `create-skill` and `create-agent` use it. `create-docs` inlines a skeleton; `create-hook` uses `resources/HOOKS_API.md` (a reference, not a template). The asymmetry is principled (skills and agents have richer structure than docs and hooks), but worth cataloging as a cross-cutting shape observation. Not v3-blocking.

- **Internal inconsistency in `evaluate-hook` Before/After example.** Line 274 uses `$(dirname "$0")` which the rubric's own anti-pattern table (line 202) penalizes with -5 on D1. One-line fix to `$(dirname "${BASH_SOURCE[0]}")`. Queue item 6.

- **Stale line-count reference in `create-skill`.** Line 188 references `create-hook/resources/HOOKS_API.md` as "400 lines"; actual is 548. Update to actual or drop the count. Contingent on queue item 4 decision — if HOOKS_API.md is split, references update either way.

- **No orchestration-shaped leakage.** All 9 skills operate inside the session they're invoked in (workshop or consumer) and write to the authoring repo's own paths (`.claude/skills/`, `.claude/agents/`, `.claude/docs/`, `.claude/hooks/`, `docs/indexes/evaluations.json`). The evaluate-* skills launch subagents but those subagents also operate in the same session context. Workshop identity clean across all 9 files.

- **Output-shape consistency.** `evaluate-*` skills write to `docs/indexes/evaluations.json` (the canonical index, not `output/claude-toolkit/reviews/`) — correct, because evaluations are persistent curated state, not session artifacts. `evaluate-batch` writes to the same index after each batch. `create-*` skills write to `.claude/<type>/<name>/...` — correct, because they're authoring resources, not artifacts. Knowledge skills in this subset: none (all 9 are command-shaped procedural workflows).

- **No `brainstorm-idea` / `casual_communication_style` See also references.** Workflow queue item 3 (brainstorm rename) and personalization queue item 1 (casual_communication_style removal) impose zero lockstep burden here.

---

## Decision-point queue (carry forward)

**Resolved during review (pending execution — trivial scope):**

1. `create-skill/SKILL.md` line 188 — **update or remove stale line count.** Currently says `create-hook`'s HOOKS_API.md is "400 lines"; actual is 548. Contingent on queue item 4 (may update either way depending on whether we split HOOKS_API.md or not).

**Coordinated with other audit directories:**

2. **`type:` frontmatter sweep — final count is 17, not 19.** This subset contributes 1 instance (`create-hook`). Running total across all 6 audited subsets: **17** (4 workflow + 1 code quality + 3 design & arch + 2 personalization + 6 dev tools + 1 toolkit dev). Consumer side of the sweep is `evaluate-skill/SKILL.md` — lines 42-48 (Skill Types table), 54-58 (Dimension Adjustments table), 259 (Evaluation Protocol step 2), JSON output schema (line 224). All four locations update in lockstep with the sweep commit. The JSON output schema decision (keep top-level `type` vs nest under `metadata`) is a small follow-on — queue item 5.

**Open — needs decision in a follow-up session:**

3. **`type:` default stance — 18 skills carry no `type:` field at all.** Per evaluate-skill line 259, these default to `knowledge`. Worth a pass: are any actually command-shaped and should declare explicitly? Low-priority and partially orthogonal to the sweep itself — the sweep moves the existing field; this item asks whether to *add* the field to files that don't have it. Can be deferred until after the sweep.

4. **`create-hook/resources/HOOKS_API.md` at 548 lines violates `create-skill`'s 500-line supporting-file rule.** Two resolutions:

   - **Option A (preferred, low-friction):** bump the create-skill threshold to 600 lines. Update create-skill line 173 (*"<500 lines each"* → *"<600 lines each"*) and line 188 (stale count reference). The 500-line limit came from context-bloat concerns; a 548-line reference loaded on-demand isn't the bloat pattern the rule was designed to catch.
   - **Option B (purer):** split HOOKS_API.md by section (events / types / input fields / output / config / debugging). Each piece stays under 500. Navigation overhead added.

   A is lower-friction and more honest about the reference-vs-tutorial distinction. Decision deferred to a follow-up session.

5. **Evaluate-* JSON output schema decision + model-choice cross-check.** Two related questions to resolve alongside the sweep:

   - **JSON schema:** when `type:` moves to `metadata.type` in skills, does the `evaluations.json` output schema also move the `type` field under a `metadata` key, or does it stay at top-level? The field is just for reporting (it's not used for behavior in the index) — keeping at top-level is simpler. Small decision, but worth locking in before the sweep commit.
   - **Model choice (opus → sonnet?):** all 4 evaluate-* skills dispatch `model: "opus"` subagents (evaluate-skill:240, evaluate-agent:165, evaluate-hook:155, evaluate-docs:204). Same structured-checklist argument that's moving `code-reviewer` / `implementation-checker` toward sonnet (agents queue items 1-2) applies here. Worth aligning evaluate-* model choice with the agent-level decision so the whole rubric-scoring lane is consistent.

   Both are small coordinated follow-ons — cluster them with the sweep commit or do them as a separate evaluate-* polish pass.

**Still open / low-priority:**

6. **`evaluate-hook/SKILL.md` line 274 uses `$(dirname "$0")`** which the rubric's own anti-pattern table (line 202) penalizes with -5 on D1. 1-line fix: `$(dirname "${BASH_SOURCE[0]}")`. Internal inconsistency, not v3-blocking.

7. **`resources/TEMPLATE.md` naming convention is partial** — only `create-skill` and `create-agent` use it. `create-docs` and `create-hook` don't. Asymmetry is principled (docs/hooks have less template structure to hand off) but may be worth formalizing if future create-* skills appear. Not v3-blocking.

8. **Rubric divergence: evaluate-skill is 120 pts (8 dims) while evaluate-agent/hook/docs are 115 pts (5-6 dims).** Resolved (not an issue): user confirmed the rubrics already converge on `percentage` as the primary score tracker. Raw totals are for traceability; percentage is what users and `evaluate-batch` compare against. Divergence in absolute totals is expected and already handled. Keep for future reference: if adding a dimension to one evaluator, the percentage principle means no lockstep change is needed on the others.

9. **`create-hook` follow-ups (user-raised during review):**

   - **(9a) Add explicit link to official Claude Code hooks documentation in the skill body.** Currently only `resources/HOOKS_API.md` line 3 links out (*"Source: [Official Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)"*); the skill body itself (create-hook/SKILL.md) does not. New hook authors reading the skill should see the upstream link prominently — both for fields the toolkit doesn't cover and to catch API changes between toolkit syncs.
   - **(9b) Extract the inline Bash PreToolUse starting-point script (create-hook/SKILL.md lines 44-103) into `resources/TEMPLATE.md`.** Match the `create-skill` / `create-agent` `resources/TEMPLATE.md` convention so new hooks start by file-copy, not re-typing from the skill body. The template encodes the current match/check + dual-mode trigger structure (match_/check_/main/`${BASH_SOURCE[0]}` trigger) as a standalone runnable file. Skill body then becomes lean — point at `resources/TEMPLATE.md` as the LITERAL STARTING POINT, keep only the *why* (cheap-predicate contract, dispatcher direction) inline.

   Resolves cross-cutting finding 4 (the `resources/TEMPLATE.md` partial-convention observation): after this change, 3 of 4 create-* skills use `resources/TEMPLATE.md` — only `create-docs` stays inline (its skeleton is small enough that the convention cost outweighs the benefit). Action scope: medium — pulls ~60 lines out of SKILL.md into a new file, adjusts the skill's reference pattern, adds the upstream doc link. One commit.
