# v3 Audit — `dist/`

Exhaustive file-level audit of the `dist/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Summary

`dist/` is the shape of the workshop's outbound pipeline: two distribution profiles (`base` full, `raiz` curated subset) that produce templates + resource manifests. Audit outcome: **this directory is workshop-shaped by design** — it exists *because* the toolkit supplies resources rather than orchestrates projects. Findings are small drift issues in templates, not structural rewrites.

Profile count is right (full + curated subset covers the two downstream modes). Template style is right (copy-to-project, not run-from-toolkit). Nothing here reaches into downstream projects; everything is snapshot-and-hand-off.

---

## Files

### `dist/CLAUDE.md`

- **Tag:** `Keep`
- **Finding:** Clear description of the two profiles and their intentional differences (lessons opt-in, toolkit link, validation targets, missing-skills disclaimer). Matches the new canon — consumers vs satellites is the downstream model, and the two profiles map cleanly onto "full consumer" vs "lightweight consumer." Resource-selection mechanisms (EXCLUDE vs MANIFEST) are documented with the right rationale.
- **Action:** none.

### `dist/base/EXCLUDE`

- **Tag:** `Keep`
- **Finding:** Lists toolkit-meta resources that don't sync to projects (create-*, evaluate-*, shape-proposal, toolkit-internal docs, cron scripts). This is exactly the workshop boundary — *"the workshop keeps meta-tools for itself; consumers get the finished goods."* `relevant-project-identity.md` is correctly excluded as toolkit-internal. Entry set looks complete against current `.claude/`.
- **Action:** none. *(Minor: spot-check at decision point whether any newly-added meta-skill is missing from the list; current entries look up-to-date.)*

### `dist/base/templates/BACKLOG-minimal.md`

- **Tag:** `Investigate`
- **Finding:** Template pre-populated with **two example tasks** (`cli-validation`, `config-defaults`) under "P1 - High". Templates should be empty scaffolds — the example tasks will get copied into every new consumer project's `BACKLOG.md` and then need manual deletion. Either the examples should be in a comment block or under a "## Examples" footer, or they should be removed entirely.
- **Action:** at decision point, decide: remove the examples, or move them into a clearly-labeled comment. Lean toward removing — the standard template already demonstrates format.
- **Scope:** trivial — 2-line removal.

### `dist/base/templates/BACKLOG-standard.md`

- **Tag:** `Keep`
- **Finding:** Standard-format template showing the full metadata block (status, scope, branch, depends-on, plan, notes). Placeholder-only — no real tasks leak through. Aligns with `relevant-workflow-backlog.md`.
- **Action:** none.

### `dist/base/templates/CLAUDE.md.template`

- **Tag:** `Rewrite`
- **Finding:** Three issues, all small:
  1. Line 45 references **`.claude/docs/`** — fine. But there's no mention of `.claude/memories/` (which is now organic context: project identity, auto-memory), creating asymmetry with the raiz template (line 44 of raiz explicitly calls out memories).
  2. "Capture lessons aggressively" principle (line 31) references `/learn` and `/manage-lessons`. With the lessons ecosystem being opt-in and defaulting off, this line will point consumers at skills that may not fire as advertised unless they flip `CLAUDE_TOOLKIT_LESSONS=1`. Either add a "(opt-in — see settings)" note, or move the bullet behind the opt-in.
  3. Line 41 links to `https://github.com/hata/claude-toolkit` — confirm this is the correct public URL. (The raiz template §38 phrases the same relationship without the link.)
- **Action:** at decision point: (a) add memories line, (b) qualify the lessons principle for opt-in state, (c) confirm repo URL.
- **Scope:** small — few lines of text.

### `dist/base/templates/Makefile.claude-toolkit`

- **Tag:** `Keep`
- **Finding:** Suggests `lint` (pre-commit), `test` (pytest), and two claude-toolkit targets. Python-biased (pytest, pre-commit), but the header comment calls that out ("adjust for your stack"). Targets match the workshop's sync/validate surface.
- **Action:** none.

### `dist/base/templates/PULL_REQUEST_TEMPLATE.md`

- **Tag:** `Keep`
- **Finding:** Tiny scaffold — Description / Motivation / Testing / Checklist. No orchestration signal, no canon conflict.
- **Action:** none.

### `dist/base/templates/claude-powerline.json`

- **Tag:** `Investigate`
- **Finding:** Statusline theme. `modelContextLimits` block (lines 46–49) specifies `sonnet: 200000` and `haiku: 200000` but **omits `opus`**. Current workshop session runs on Opus 4.7 1M — the missing entry may be either (a) an oversight, (b) intentional because opus defaults suffice, or (c) the schema only tracks non-default overrides. Doesn't affect v3 identity either way, but worth a one-line check.
- **Action:** grep the claude-powerline project docs or the actual installed binary to confirm whether opus-omit is intentional. Likely 1-line addition if not.
- **Scope:** trivial once confirmed.

### `dist/base/templates/claude-toolkit-ignore.template`

- **Tag:** `Rewrite`
- **Finding:** Example patterns (commented) reference **`memories/essential-conventions-code_style.md`** (line 8) and **`memories/essential-preferences-communication_style.md`** (line 9). Current layout has these under `docs/`, not `memories/` — `essential-conventions-*` and `essential-preferences-*` are docs, not memories. The template is teaching consumers an outdated path convention.
- **Action:** replace the memories examples with the real `docs/essential-*` paths (or remove those lines if examples are arbitrary).
- **Scope:** 2-line fix.

### `dist/base/templates/gitignore.claude-toolkit`

- **Tag:** `Rewrite`
- **Finding:** (Pre-logged during stage 1.) Lines 16–18 gitignore `lessons.db`, `session-index.db`, and `hooks.db`. Two issues:
  1. `session-index.db` was renamed to `sessions.db` — the entry is stale.
  2. `hooks.db` was at `~/.claude/` at some point but is no longer expected in project roots.
- **Action:** remove both `session-index.db` and `hooks.db` entries. Keep `lessons.db`.
- **Scope:** trivial — 2-line removal.

### `dist/base/templates/mcp.template.json`

- **Tag:** `Keep`
- **Finding:** Two MCP servers (sequential-thinking, context7), both `"disabled": true`. Template provides scaffolding; consumers flip flags to enable. No orchestration signal.
- **Action:** none.

### `dist/base/templates/settings.template.json`

- **Tag:** `Keep`
- **Finding:** Reference `settings.json` — permissions allowlist, hook wiring, env vars. `env.CLAUDE_TOOLKIT_LESSONS` and `env.CLAUDE_TOOLKIT_TRACEABILITY` default to `"0"` (opt-out by default) — consistent with the opt-in design decision. `surface-lessons.sh` is wired under `PreToolUse` with its self-exit-when-off behavior; the combination of "always wired + default off" is the designed path. No conflict.
- **Action:** none.
- **Noted during this audit (cross-cutting):** the toolkit's own `.claude/settings.json` had `CLAUDE_TOOLKIT_LESSONS=1`, which made `surface-lessons.sh` fire on every tool call. We flipped it to `"0"` mid-audit because the surfaced lessons were not relevant to the audit work. The hook's relevance filter is a separate concern — flagged for the `.claude/hooks/` audit slot, not a dist/ finding.

### `dist/raiz/MANIFEST`

- **Tag:** `Investigate`
- **Finding:** Cherry-picked subset (11 skills, 5 agents, 10 hook entries, 3 inside-`.claude/` docs, 1 project-root doc, 1 script, 6 templates). Three small questions:
  1. **`skills/build-communication-style/`** is in `dist/base/EXCLUDE` (toolkit-meta, excluded from base) but **included** in the raiz MANIFEST (line 10). Intentional? If raiz is supposed to be a subset of base, including a skill that base excludes is contradictory — consumers on base wouldn't get it, but consumers on raiz would. Either base should include it, or raiz shouldn't. Check whether build-communication-style is meant as a toolkit-internal tool or a general-purpose skill.
  2. **`dist/CLAUDE.md`** (the dist explainer) says raiz has "9 hooks" but the MANIFEST lists 10 entries (9 .sh + `hooks/lib/hook-utils.sh`). Cosmetic — counts drift with edits. Either fix the count, or rephrase as "9 top-level hooks + shared lib."
  3. **No `docs/relevant-toolkit-hooks_config.md`** in the raiz manifest, though raiz ships guardrail hooks. Consumers of raiz won't see the hook config doc. Intentional (to keep raiz lean)? Worth confirming rather than assuming.
- **Action:** at decision point: (1) decide `build-communication-style` classification — move to/from EXCLUDE accordingly, (2) reconcile the hook count in `dist/CLAUDE.md`, (3) confirm docs choice.
- **Scope:** (1) small but needs a call, (2) trivial, (3) depends on (1).

### `dist/raiz/changelog/.gitkeep`

- **Tag:** `Keep`
- **Finding:** Empty file keeping `changelog/` directory in git. Standard practice.
- **Action:** none.

### `dist/raiz/changelog/2.43.0.html`

- **Tag:** `Keep`
- **Finding:** Historical raiz changelog override (Telegram HTML format per `CLAUDE.md` note about `publish-raiz` workflow). These are frozen artifacts — changing them rewrites released history, which is always wrong.
- **Action:** none.

### `dist/raiz/changelog/2.43.2.html`

- **Tag:** `Keep`
- **Finding:** Same as 2.43.0 — historical release artifact.
- **Action:** none.

### `dist/raiz/changelog/2.45.1.html`

- **Tag:** `Keep`
- **Finding:** Same — historical release artifact.
- **Action:** none.

### `dist/raiz/changelog/2.54.0.html`

- **Tag:** `Keep`
- **Finding:** Same — historical release artifact. ("Raiz keeps its existing split config — no behavior change for raiz users.")
- **Action:** none.

### `dist/raiz/templates/CLAUDE.md.template`

- **Tag:** `Keep`
- **Finding:** Raiz variant of the CLAUDE.md scaffold. Correctly omits "Capture lessons" (raiz doesn't opt into lessons by default), uses plain-text toolkit reference (no GitHub link — raiz is standalone), explicitly mentions memories (line 44), and includes the missing-skills disclaimer (line 46). Matches the intentional-differences table in `dist/CLAUDE.md`. The opposite-direction asymmetry I flagged on the base template (memories line missing) reinforces that the raiz template has *more* of the right shape here.
- **Action:** none.

### `dist/raiz/templates/settings.template.json`

- **Tag:** `Keep`
- **Finding:** Raiz settings with lean hook set: no `surface-lessons.sh` (raiz doesn't include the lessons hook), no lessons env flag enabling. Permissions list matches base. Hook ordering differs slightly (Bash matcher first in raiz vs EnterPlanMode first in base) — cosmetic, not semantic. No canon conflict.
- **Action:** none.

---

## Cross-cutting notes

- **Profile shape is correct.** `base` (full toolkit for maximalist consumers) and `raiz` (curated subset for minimalist consumers) cleanly map onto the "consumer" leg of the downstream model. Satellites aren't represented here because they aren't separate distribution profiles — a satellite just pulls from `base` and contributes upstream via `suggestions-box/`. That asymmetry is correct, not missing.
- **No orchestration smells.** Every file here is inert until copied/synced into a consumer project. The workshop ships; it does not run.
- **Published artifacts (raiz changelog HTMLs) are untouchable.** Stage 2 findings about them would all be "Keep" regardless of content.
- **Stage 1 pre-logged finding preserved.** The gitignore rewrite is carried forward verbatim as a `Rewrite` finding.

---

## Decision-point queue (carry forward)

From this directory, the following items need explicit in-or-out calls for v3:

1. `BACKLOG-minimal.md` **remove the two example tasks** (or move to a clearly-labeled comment).
2. `base/CLAUDE.md.template` **add memories line**, qualify the `/learn` principle for opt-in state, confirm repo URL.
3. `claude-powerline.json` **confirm opus omission is intentional**; add entry if not.
4. `claude-toolkit-ignore.template` **replace stale `memories/essential-*` examples** with correct `docs/essential-*` paths.
5. `gitignore.claude-toolkit` **remove `session-index.db` and `hooks.db` entries.** (Pre-logged — still queued.)
6. `raiz/MANIFEST` **resolve `build-communication-style` classification** (meta vs general), reconcile hook count in `dist/CLAUDE.md`, confirm docs choices.
7. (Cross-reference to `.claude/hooks/` audit slot) `surface-lessons.sh` **relevance filter cadence** — separate concern logged during this session; belongs in the hook audit, not here.
