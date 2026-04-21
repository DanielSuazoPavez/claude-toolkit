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

**Resolved decisions:**
- `evaluations.json` keeps `type` at **top level** — simpler; the field is reporting only, not behavioral.
- The 18 skills with no `type:` field today will receive **explicit `metadata: { type: knowledge }`** rather than relying on the default. Add to the sweep commit alongside the 17 moves. Post-sweep pass (D3) is resolved: include them in the same commit.

18 skills with no `type:` field: include in the sweep with explicit `metadata: { type: knowledge }` (same commit).

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

### C1. `read-json` reshape — **resolved: Option A**
Demote to `metadata: { type: knowledge }`, add `user-invocable: false`, strip redundant sections (categorical rule, progressive pattern, file-size table, anti-patterns table), keep shell-quoting traps and malformed-JSON recipes. Update `suggest-read-json` hook's `_BLOCK_REASON` (hook line 73) to point at skill path rather than `/read-json` command syntax.

### C2. `HOOKS_API.md` 548-line rule violation — **resolved: Option A**
Bump `create-skill` threshold to 600 lines. Update `create-skill:173` (`<500 lines` → `<600 lines`) and `create-skill:188` (stale "400 lines" count → actual 548).

### C3. Evaluate-* model — **resolved: keep opus, document the decision**
Evaluate-* skills are not called all the time and their output is a signal of possible needed changes on resources — deeper reasoning is warranted. Keep `model: "opus"` across all 4 evaluate-* skills. Add a brief rationale comment to each skill's invocation block so the choice isn't mistaken for an oversight. Not the same as `code-reviewer` / `implementation-checker` (those are checklist-only; evaluate-* requires cross-dimension judgment).

### C4. `list-docs` docs-surfacing direction — **resolved: backlog task added**
New `surface-docs.sh` hook is the direction — same algorithm as `surface-lessons.sh`. Backlog task `surface-docs-hook` added at P3, **gated on `improve-lessons-lifecycle` being validated first**. No action on `list-docs/SKILL.md` itself until hook is built.

### C5. `manage-lessons` — **resolved: backlog task added**
Backlog task `manage-lessons-cli-routing` added. Prerequisites: check CLI for existing `promote`/`deactivate`/`delete` subcommands; add any missing; rewrite skill to route everything through CLI; drop `Bash(sqlite3:*)` from `allowed-tools`. Coordinates with `.claude/hooks/` queue item 2 (`LESSONS_DB` env var).

### C6. `review-security` worthyness — **resolved: backlog task added**
Backlog task `review-security-worthyness` added. Do alongside pattern-finder diagnostic (agents queue item 8) — same diagnostic shape.

---

## D. Cross-Audit Threads (depend on other audit decisions)

### D1. `analyze-idea/SKILL.md` — pattern-finder See also (line 11)
Update when `.claude/agents/` queue item 8 (pattern-finder: deprecate/sharpen/keep) resolves. No action until that decision lands.

### D2. Satellite-contract rule — schema-smith removal + backlog task
**Backlog task `satellite-cli-docs-convention` added** at P3: spec how workshop skills should reference satellite CLI documentation (via `--print-input-spec` or equivalent), make that convention available through the CLI, and document it in a new doc (e.g., `relevant-toolkit-satellite-contracts.md`). When the convention lands, schema-smith removes the workshop copy; the same rule applies for aws-toolkit when `/design-aws` ships.

Schema-smith removal order: (1) convention doc ships, (2) schema-smith satellite exposes its input spec via CLI, (3) design-db Schema Smith Integration section updated, (4) workshop removes `resources/schema-smith-input-spec.md`.

### D3. Post-sweep pass — **resolved: included in A1**
18 skills with no `type:` field will receive explicit `metadata: { type: knowledge }` in the same A1 sweep commit. Not a separate pass.

### D4. `design-aws` scaffold — **resolved: backlog updated**
`design-aws` backlog item notes updated: reference + satellite ready; user-postponed; no dependency blockers. When skill ships, enforce satellite-contract rule (link out to aws-toolkit docs via convention from D2; no duplicated spec).

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
