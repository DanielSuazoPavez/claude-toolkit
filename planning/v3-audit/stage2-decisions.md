# v3 Stage 2 Audit — Consolidated Decision Document

All findings from 6 skill subsets rolled up for execution planning. Organized by execution cluster, not by origin subset.

---

## A. Coordinated Commits (all-or-nothing, single-commit each)

### A1. `type:` → `metadata.type` sweep (17 files + evaluate-skill consumer side)

**All 17 skills carrying `type:` move to `metadata: { type: ... }` in one commit.**

Producer files (17 total):
- Workflow (4): `analyze-idea`, `write-handoff`, `wrap-up`, `list-docs`
- Code quality (1): `design-tests`
- Design & arch (3): `design-db`, `design-diagram`, `design-docker`
- Personalization (2): `build-communication-style`, `snap-back`
- Dev tools (6): `write-documentation`, `draft-pr`, `setup-toolkit`, `setup-worktree`, `teardown-worktree`, `read-json`
- Toolkit dev (1): `create-hook`

Consumer file (1): `evaluate-skill/SKILL.md` — 4 lockstep locations:
- Line 42-48: Skill Types table (reads `type:`)
- Line 54-58: Dimension Adjustments table (reads `type:`)
- Line 259: Evaluation Protocol step 2 (`"Determine type from frontmatter..."`)
- Line 224: JSON output schema (`"type": "knowledge|command"`)

**Open decision before executing:** does `evaluations.json` keep `type` at top-level in the output schema, or nest under `metadata`? Recommendation: keep top-level in the JSON output (simpler; the field is reporting only, not behavioral). Lock before the commit.

18 skills with no `type:` field default to `knowledge` per evaluate-skill:259 — no change needed for the sweep, but see queue item D3 for a post-sweep pass.

### A2. Brainstorm pair rename (coordinated lockstep)

Rename and update in one commit:
- `/brainstorm` → `/brainstorm-idea` (file, frontmatter `name:`, output slug). Output path: `output/claude-toolkit/brainstorms/`.
- `/brainstorm-idea` → `/brainstorm-feature` (file, frontmatter `name:`, output slug). Output path: `output/claude-toolkit/design/` (unchanged).

All `See also` cross-references that point at either name — confirmed affected files:
- `analyze-idea/SKILL.md` line 11
- `shape-project/SKILL.md` line 108
- `shape-proposal/SKILL.md` line 13
- `refactor/SKILL.md` lines 47, 105, 210
- `build-communication-style/SKILL.md` line 11
- Likely others — run `grep -r '/brainstorm' .claude/skills/` before the commit.

Also update: `docs/indexes/SKILLS.md`, `docs/getting-started.md`, `README.md` table.

Also resolves: `brainstorm/SKILL.md` output-path drift (`output/{project}/design/...` → `output/claude-toolkit/brainstorms/...`).

---

## B. Per-File Fixes (independent, can land in any order)

### B1. `snap-back/SKILL.md` — remove `casual_communication_style` See also (line 75)
1-line deletion. Already resolved in prior session (fold `c8e0d17`).

### B2. `write-handoff/SKILL.md` — fix stale mkdir path (line 104)
Line 104 has `mkdir -p .claude/sessions`; actual output target is `output/claude-toolkit/sessions/`. Fix or remove (Write tool creates parents). 1-line fix.

### B3. `write-documentation/SKILL.md` — fix broken path reference (line 40)
`output/claude-toolkit/reviews/codebase/` → `.claude/docs/codebase-explorer/{version}/`. 1-line fix. The `codebase-explorer` agent writes to `.claude/docs/codebase-explorer/{version}/`, not to `output/claude-toolkit/reviews/`.

### B4. `write-handoff/SKILL.md` — prompt-body pass against intent-attribution
15-30 line prompt rewrite:
- Shrink `## Recent Work` section (git log is authoritative for what was done in the session).
- Reframe `## Context Notes` → `## Blockers / Hidden State` (only for things not in code/git that would prevent resumption).
- Add "Attributing Intent" anti-pattern: don't synthesize forward-direction from past work; if the user said X, record the request, don't extrapolate intent.
- Optional: add a validation check — before writing, does every bullet in Next Steps map to something the user explicitly said or a concrete git/file state?

### B5. `evaluate-hook/SKILL.md` — fix internal inconsistency (line 274)
Before/After example at line 274 uses `$(dirname "$0")` which the rubric's own anti-pattern table (line 202) penalizes -5 on D1. Fix: `$(dirname "${BASH_SOURCE[0]}")`. 1-line fix.

### B6. `create-hook/SKILL.md` — upstream link + extract `resources/TEMPLATE.md`
Two changes in one commit:
- (a) Add explicit link to official Claude Code hooks documentation in the skill body. Currently only `resources/HOOKS_API.md:3` links out; skill body does not.
- (b) Extract lines 44-103 (60-line Bash PreToolUse starting-point script) into `resources/TEMPLATE.md`, matching the `create-skill` / `create-agent` convention. Skill body becomes lean — references `resources/TEMPLATE.md` as the LITERAL STARTING POINT, keeps only the *why* inline.
Medium scope — ~60 lines moved + new file + skill body adjusted. One commit.

---

## C. Open Decisions (need user input before execution)

### C1. `read-json` reshape — Option A vs B
The skill is falling flat: `suggest-read-json` hook already catches the pain point; sessions now default to jq anyway.

Load-bearing content: shell-quoting traps (`--arg`/`--argjson` vs interpolation, lines 37-64) and malformed-JSON recipes (BOM, JSONL, trailing commas, truncated, embedded, lines 66-90).
Redundant content: categorical rule, progressive inspection pattern, file-size table, anti-patterns table.

- **Option A (preferred):** demote to `type: knowledge`, add `user-invocable: false`, strip redundant sections, keep quoting+malformed content. Update `suggest-read-json` hook's `_BLOCK_REASON` (hook line 73) to point at skill path rather than `/read-json` command.
- **Option B (ruthless):** delete skill, fold load-bearing content into a new short doc (`.claude/docs/reference-jq-patterns.md`) the hook points at.

A is lower-risk. B raises the question of whether "hook-pointed knowledge doc" is a resource shape worth formalizing.

### C2. `HOOKS_API.md` 548-line rule violation — loosen vs split
`create-hook/resources/HOOKS_API.md` is 548 lines; `create-skill/SKILL.md:173` says supporting files should be under 500.

- **Option A (preferred):** bump `create-skill` threshold to 600 lines. The 500-line limit was for context bloat; a 548-line reference loaded on-demand isn't the pattern it guards against. Update `create-skill:173` (`<500 lines` → `<600 lines`) and `create-skill:188` (stale "400 lines" count → actual 548).
- **Option B:** split `HOOKS_API.md` by section (events / types / input fields / output / config / debugging). Navigation overhead added.

A is lower-friction. Resolves `create-skill:188` stale count as a side effect.

### C3. Evaluate-* model flip — opus → sonnet?
All 4 evaluate-* skills dispatch `model: "opus"` subagents:
- `evaluate-skill:240`, `evaluate-agent:165`, `evaluate-hook:155`, `evaluate-docs:204`

Rubric scoring is structured checklist work — same argument that's moving `code-reviewer` / `implementation-checker` from opus → sonnet (agents queue items 1-2). Worth aligning evaluate-* with the agent-level decision.

**Recommendation:** decide alongside the agents queue flip so the whole rubric-scoring lane is consistent. Don't do this ad hoc before the agents decision lands.

### C4. `list-docs` docs-surfacing direction
User flagged: relevant docs rarely surface when they'd help. Two options:
- **Status quo:** explicit-invocation only (user runs `/list-docs`, Claude reads on relevance). Defensible but unsatisfying.
- **New `surface-docs.sh` hook:** context-aware hook matching tool context against `relevant-*` Quick References, same algorithmic approach as the fixed `surface-lessons.sh`. Coordinates with `.claude/hooks/` queue item 5 (dedup window + minimum match specificity).

No decision yet. Coordinates with hooks-audit queue item 5.

### C5. `manage-lessons` — CLI routing for promote/deactivate/delete
Skill currently has direct `sqlite3` calls for 3 operations (lines 94-106). Direction: route everything through `claude-toolkit lessons` CLI; drop `Bash(sqlite3:*)` from `allowed-tools`.

**Prerequisite:** check CLI for existing `promote`, `deactivate`, `delete` subcommands. Add any missing ones. Then rewrite the skill.

Coordinates with `.claude/hooks/` queue item 2 (`LESSONS_DB` env var) — once CLI routes through the env var, skill inherits behavior automatically.

### C6. `review-security` worthyness diagnostic
Skill has never been invoked in the wild (to user's knowledge). Run invocation-frequency check (same approach as pattern-finder agents queue item 8). Based on data:
- **(a) Keep** — content already solid, no rewrite needed.
- **(b) Sharpen** — broaden description triggers, consider `surface-*` hook path.
- **(c) Deprecate** — CC's built-in `/security-review` may cover enough of the surface.

Same timing as the pattern-finder diagnostic — do both together.

---

## D. Cross-Audit Threads (depend on other audit decisions)

### D1. `analyze-idea/SKILL.md` — pattern-finder See also (line 11)
Update when `.claude/agents/` queue item 8 (pattern-finder: deprecate/sharpen/keep) resolves. No action until that decision lands.

### D2. Satellite-contract rule — schema-smith removal
Remove `design-db/resources/schema-smith-input-spec.md` after schema-smith satellite exposes its `input/CLAUDE.md`-equivalent consumer doc via CLI (e.g., `schema-smith --print-input-spec`). Direction is locked; timing depends on satellite readiness.

Order: (1) satellite ships CLI flag, (2) design-db Schema Smith Integration section updated to reference the CLI command, (3) workshop removes the spec file.

### D3. Post-sweep pass — 18 skills with no `type:` field
After the A1 sweep lands: are any of the 18 type-undeclared skills actually command-shaped and would benefit from explicit `metadata.type` declaration? Low-priority; deferred until after the sweep.

### D4. `design-aws` scaffold — backlog annotation
Mark the P3 backlog item as "reference + satellite ready; user-postponed" — no dependency blockers. 1-line backlog edit. When skill ships, enforce satellite-contract rule (link out to aws-toolkit docs; no duplicated spec).

---

## E. Stage-5 Polish Bundles (non-v3-blocking)

### E1. Small validators bundle
Three validators surfaced independently across subsets — bundle into one backlog item:
- **Output-path validator:** checks each skill's `Save to:` path matches `output/claude-toolkit/<category>/...`. Catches `brainstorm`'s `{project}` drift, `write-documentation`'s stale path.
- **Cross-reference validator:** resolves all `.claude/` markdown cross-references against docs + memories + agents + skills. Catches stale See also links.
- **Indexes-validator:** verifies `docs/indexes/SKILLS.md` entries match actual filesystem.

### E2. Output-shape convention doc
The deliberate split between file-saving skills and inline-findings skills isn't documented anywhere. One paragraph in `relevant-toolkit-context.md`: when to save vs present inline, with the half-life framing (security findings age poorly; saved artifacts should be reviewed later or by someone else; knowledge skills are inline by default).

### E3. `teardown-worktree` artifact-copy scope
Currently copies only `output/claude-toolkit/reviews/*`. Does not copy `pr-descriptions/`, `design/`, `plans/`, `sessions/`. Decide: deliberate (keep per-worktree ephemera scoped) or overscoped-to-reviews. Not v3-blocking.

### E4. `setup-toolkit` powerline version pin
`@owloops/claude-powerline@1.25.1` hardcoded at line 321. When next powerline bump lands, grep the full workshop for all references and bump together. One-line note for the next statusline-related change.

### E5. Frontmatter field ordering normalization
`build-communication-style` has non-standard ordering (`name, description, argument-hint, allowed-tools, type`); most skills use `name, type, description, ...`. The A1 sweep resolves `type:` placement; broader ordering is a separate polish pass. Could be automated with a small linter.

---

## Execution Order Recommendation

1. **A1** (`type:` sweep) — biggest spread, unblocks evaluate-skill usage with the new field. Lock the JSON schema decision (keep `type` at top level in evaluations.json output) before starting.
2. **B2** + **B3** + **B5** — trivial 1-line fixes, can land in the same commit as each other or with the sweep.
3. **C2** decision → then **B6** (`create-hook` TEMPLATE.md extraction). The `create-skill:188` stale count depends on C2.
4. **B4** (`write-handoff` prompt pass) — small-moderate, independent.
5. **C5** diagnostic (`manage-lessons` CLI check) → then add subcommands → then rewrite skill.
6. **A2** (brainstorm rename) — moderate scope, needs grepping for all cross-refs first.
7. **C1** decision (`read-json` reshape) — small once decision is made.
8. **C6** + **D1** together (review-security + pattern-finder diagnostics).
9. **D2** (schema-smith removal) — gated on satellite side.
10. **E1-E5** — stage-5 polish, lowest priority.

---

## Source Files

| Subset | Audit file | Subset queue items |
|--------|------------|-------------------|
| Workflow | `claude-skills-workflow.md` | Q1-10 |
| Code Quality | `claude-skills-code-quality.md` | Q1-5 |
| Design & Arch | `claude-skills-design-arch.md` | Q1-8 |
| Personalization | `claude-skills-personalization.md` | Q1-6 |
| Dev Tools | `claude-skills-dev-tools.md` | Q1-7 |
| Toolkit Dev | `claude-skills-toolkit-dev.md` | Q1-9 |
