# v3 Audit — `.claude/skills/` (Development Tools subset)

Exhaustive file-level audit of the 6 Development Tools skills (per `docs/indexes/SKILLS.md`; `design-docker` listed in the same subset heading but already audited under Design & Architecture — not re-audited).

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`
**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

Skills audited: `write-documentation`, `draft-pr`, `setup-toolkit`, `setup-worktree`, `teardown-worktree`, `read-json`.

---

## Summary

Six skills, all workshop-shaped by construction: each runs inside a consumer session and operates on that consumer's own repo (docs, PR text, worktree, JSON files, or the consumer's `.claude/` config). No orchestration leakage. `setup-toolkit` is the closest thing to a coordinator in the set but it sits fully inside the target project — it's a self-contained diagnostic/fix skill, not a cross-project controller.

Findings:

1. **`type:` frontmatter — 6 instances.** All 6 carry `type:`: 5 command (`draft-pr`, `setup-toolkit`, `setup-worktree`, `teardown-worktree`, `read-json`) + 1 knowledge (`write-documentation`). All sit at the canonical line 3. Picked up by repo-wide sweep (workflow queue item 7). No additional polish needed per-file.

2. **`write-documentation` has a broken path reference — 1 instance (Rewrite).** Line 40 reads: *"Look for `output/claude-toolkit/reviews/codebase/` (ARCHITECTURE.md, STACK.md, STRUCTURE.md)."* That path doesn't exist. The `codebase-explorer` agent actually writes to `.claude/docs/codebase-explorer/{version}/` (agent frontmatter line 3 + agent body line 47). This is a stale reference, not a code-review artifact path — the `output/claude-toolkit/reviews/` folder is for *session review artifacts* (code-reviewer, goal-verifier, code-debugger, etc.), not architecture reports. One-line fix.

3. **`setup-toolkit` is a large, dense skill — observation, not action.** 431 lines. Three phases (Diagnostic, Ecosystem Opt-Ins, Fix) plus Validation, handled as a single skill rather than split. The size is load-bearing: the skill's job is to walk 8 diagnostic checks and apply fixes with user approval per-item; splitting it would multiply the invocation/coordination burden for users. The diagnostic output format (`===CHECK:N:name:STATUS===` section markers, `MISSING:`/`EXTRA:`/`ORPHAN:`/`STALE_REF:`/`CLEANUP:`/`SUGGESTION:` line prefixes) is a proper contract between `setup-toolkit-diagnose.sh` and the skill — shell script owns mechanical checks, skill owns presentation/approval. That separation is right.

4. **Worktree pair is tight and correct (Keep for both).** `setup-worktree` creates worktrees and optionally symlinks `.claude/` from main (the ".claude/ is gitignored, synced via toolkit" case); `teardown-worktree` checks for uncommitted work, copies artifacts, removes. Mechanical, no orchestration. Each references the other in See also.

5. **`read-json` skill is falling flat and partly outdated — Investigate (user-raised during review).** Lines 16-19 tell the invoking session *"DON'T use the Read tool on JSON files. DO use jq commands with Bash. This applies even if the file seems small."* In practice: (a) nobody invokes `/read-json` — the `suggest-read-json` PreToolUse hook catches the actual pain point (files >50KB outside the config-file allowlist) before a user thinks to reach for a skill, and (b) current Claude sessions default to jq for JSON inspection anyway, so the "progressive inspection pattern" and "file size table" sections (lines 22-36, 103-107) are documenting what's already baseline behavior. The genuinely load-bearing sections are the shell-quoting traps (lines 37-64: `--arg` vs interpolation, `--argjson` for numbers) and malformed-JSON recipes (lines 66-90: BOM, JSONL, trailing commas, truncated). Direction: reshape the skill into a reference the hook points at rather than a user-invocable command. See queue item 4 for the concrete proposal.

6. **No `brainstorm-idea` See also references in this subset.** Workflow queue item 3 (brainstorm rename lockstep) has zero burden here. Confirmed by grep across all 6 skills.

**User resolutions surfaced during review:** none — no paired-example or judgment cases this subset.

Findings below: 1 Rewrite (`write-documentation` broken path), 1 Investigate (`read-json` — user flagged as falling flat / partly outdated; reshape toward hook-pointed reference, see queue item 4), 4 Keep-with-sweep (all carry `type:`, content otherwise clean). No Defer.

---

## Files

### `write-documentation/SKILL.md`

- **Tag:** `Rewrite` (broken path reference + `type:` sweep)
- **Finding:** 194 lines. `type: knowledge`. Audit-before-write pattern is well-shaped: (1) check for existing codebase-explorer report, (2) gap analysis presented to user before writing, (3) style detection, (4) write with audience-scoped depth, (4b) diagram integration, (5) staleness-risk-prioritized verification. The "Document the contract, not the mechanism" principle (line 16) is the right guidance for user docs; "Code is truth" (line 14) is the right rule for the drift case.

  **Path drift — line 40:** *"Look for `output/claude-toolkit/reviews/codebase/` (ARCHITECTURE.md, STACK.md, STRUCTURE.md)."* The `codebase-explorer` agent writes to `.claude/docs/codebase-explorer/{version}/` — the versioned architecture report location — not to `output/claude-toolkit/reviews/`. The latter is the session-review artifact folder used by `code-reviewer`, `goal-verifier`, `code-debugger`, `proposal-reviewer`, `implementation-checker`. This skill reads the former (architecture as context), so the path needs correcting. Suggested fix: *"Look for `.claude/docs/codebase-explorer/{version}/` (latest version; ARCHITECTURE.md, STACK.md, STRUCTURE.md, INTEGRATIONS.md)."* Matches the agent's actual output and the CLAUDE.md codebase-orientation convention.

  **Gap Analysis presentation** (line 65-85) — shows the user a structured "existing docs / gaps found / recommended actions" table before writing. That's the right workshop shape: skill surfaces candidates, user confirms, skill executes. No auto-writing without buy-in.

  **Staleness-risk prioritization** (line 148-161) — verification order is calibrated by failure-mode frequency: code examples first (dead examples erode trust fastest), then parameter lists (fabricated params are the #1 doc failure mode), then paths/cross-refs, then behavioral claims, then prose. That's an empirical ordering, not a theoretical one — right.

  **Edge Cases table** (line 165-171) — five failure modes each with a concrete response (mark `[VERIFY]`, mark `[REWRITE]`, present full gap list, rely on signatures, check code for truth). Closes the common escape hatches.

  **Anti-patterns table** (line 179-186) — six patterns (Write-first / Copy-paste syndrome / Aspirational docs / Over-documenting internals / Ignoring existing voice / Skipping verification) each with a concrete Fix. "Aspirational docs" (documenting planned features as if they exist) is the critical one — catches the class of drift that makes docs untrustworthy.

  **See also** — 4 refs: `/analyze-idea` (exists), `codebase-explorer` agent (exists), `pattern-finder` agent (exists — open decision in agents queue item 8: deprecate/sharpen/keep; no skill-text change needed until that resolves), `/design-diagram` (exists).

  **`type: knowledge`** — correct type. This skill is a "how to approach" reference that runs inline in the conversation. Picked up by repo-wide sweep.

  Workshop-shaped: operates on consumer's own docs/code, writes to consumer's own files. No cross-project coordination.

- **Action:** (1) fix line 40 path: `output/claude-toolkit/reviews/codebase/` → `.claude/docs/codebase-explorer/{version}/`; (2) `type: knowledge` → `metadata: { type: knowledge }` as part of repo-wide sweep (queue item 7).
- **Scope:** (1) trivial (1-line fix). (2) trivial (sweep-covered).

### `draft-pr/SKILL.md`

- **Tag:** `Keep` (sweep only)
- **Finding:** 123 lines. `type: command`. Six-step process: analyze branch → check for PR template → size check → split if needed → generate description → write to `output/claude-toolkit/pr-descriptions/{timestamp}_{branch-name}.md`. Output path matches the `output/claude-toolkit/` convention.

  **"When NOT to Use" section** (line 12-16) — three exclusions: single-commit trivial fix (commit message is the description), WIP/draft branches (use `/write-handoff`), no commits yet (commit first). Correct scope-carving — prevents misuse.

  **PR size thresholds** (line 37-43) — `<200` ship / `200-400` review scope / `400-600` should split / `>600` must split. Plus **Sizing exceptions** table (line 45-53) for generated files, monorepo cross-package, infrastructure, security fixes, large-scale renames. The exceptions table is load-bearing — without it, "must split at 600" becomes wrong for common legitimate cases (e.g., a 2000-line infra config is fine; a 800-line lockfile diff isn't worth splitting).

  **Split decision tree** (line 58-66) — area split / refactor-then-feature / one-feature-per-PR. Concrete, actionable.

  **Stacked PRs** (line 68-75) — five-step mechanical recipe (PR1 targets main; PR2 targets PR1's branch; document dependency; merge bottom-up; keep slices independently reviewable). The "independently reviewable" constraint (line 74) is the quality gate that prevents the stacked-PR anti-pattern where PR2 is incomprehensible without PR1 context.

  **PR template detection** (line 27-35) — checks three template locations (`.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE/`) and uses the template as output format if found. Respects project conventions.

  **Output path** — line 100: `output/claude-toolkit/pr-descriptions/{timestamp}_{branch-name}.md`. Matches the `output/claude-toolkit/` convention for generated artifacts. Consistent with the output-shape observation from code-quality subset (workflow/analysis skills save artifacts to `output/claude-toolkit/`).

  **The Quality Test** (line 114-118) — *"Can a reviewer understand the WHY in 30 seconds and review the diff in one sitting?"* One-line self-check that collapses the size/quality concerns into a single gate. Good shape.

  **See also** — 3 refs: `/wrap-up` (exists; workflow subset), `code-reviewer` agent (exists; decision: opus → sonnet per agents queue items 1-2, no skill-text change), `goal-verifier` agent (exists).

  **`type: command`** — correct. Picked up by repo-wide sweep.

  Workshop-shaped: analyzes consumer's branch, writes a PR description into consumer's own output folder. No cross-project coordination.

- **Action:** `type: command` → `metadata: { type: command }` as part of repo-wide sweep (queue item 7).
- **Scope:** trivial (sweep-covered).

### `setup-toolkit/SKILL.md`

- **Tag:** `Keep` (sweep only)
- **Finding:** 431 lines — the largest skill in the directory. `type: command`. Three-phase flow (Diagnostic → Ecosystem Opt-Ins → Fix → Validation) that walks a target project's toolkit configuration and fixes drift.

  **Toolkit repo guard** (line 18) — *"If `dist/base/` exists in the current directory, this is the toolkit repo itself — warn the user and exit. This skill runs in target projects only."* Correct scope assertion: the skill is for consumers, not for the workshop. Prevents the footgun of running diagnostic/fix logic against the workshop's own authoring environment.

  **Phase 1 Diagnostic** (line 20-64) — delegates 8 checks to `.claude/scripts/setup-toolkit-diagnose.sh` (verified exists, line 25). Script produces structured output (`===CHECK:N:name:STATUS===` delimiters, `MISSING:` / `EXTRA:` / `ORPHAN:` / `STALE_REF:` / `CLEANUP:` / `SUGGESTION:` line prefixes), skill parses and presents summary table. Clean shell-script-owns-checks / skill-owns-presentation split.

  **Phase 1.5 Ecosystem Opt-Ins** (line 66-102) — prompts for `CLAUDE_TOOLKIT_LESSONS` and `CLAUDE_TOOLKIT_TRACEABILITY` env keys in `.claude/settings.json`. Detection runs first (line 72-74); only fires when both keys absent (pre-opt-in project). Once either key exists, phase is skipped — so this is a one-time-per-project nudge, not a recurring interruption. Writes both keys regardless of answer (`"1"` or `"0"`) so the session-start nudge is silenced either way. That's the right shape — the user makes a one-time choice, the config records it, no further prompting.

  **Phase 2 Fix** (line 104-277) — each issue presented and approved individually. Additive-only for hooks/permissions (line 119: *"Additive only. Read the current settings.json, add missing entries, write back. Use jq for merging."*) — never deletes user-added entries. MCP config merge preserves existing servers. PR template optional copy. Orphaned resources ask per-item with y/n/re-sync; stale hook refs filter with jq, clean up empty matcher groups. The granularity is high: 5 sub-handlers (settings hooks/perms, MCP, Makefile, .gitignore, CLAUDE.md, PR template, cleanup) each with their own approval flow. Necessary for a skill whose blast radius is the entire target-project `.claude/` config.

  **Phase 3 Validation** (line 278-404) — runs `.claude/scripts/validate-all.sh` (verified exists), reports pass/fail, then optionally configures statusline (powerline) and invokes `/build-communication-style` if no comm-style doc exists. The statusline configuration embeds a 40-line capture wrapper script and a 55-line default powerline config directly in the skill body. Rationale: this is a consumer-setup skill and the content needs to be applied even when `.claude/templates/` doesn't include these files; inline content is the fallback.

  **Powerline version pin** — line 321: `@owloops/claude-powerline@1.25.1` hardcoded. Line 337 notes *"bump deliberately after checking `npm view @owloops/claude-powerline version`."* Worth noting: this is a content-versioned dependency inside the skill — when the workshop bumps powerline, this version needs to be updated in lockstep, and consumers who synced the skill earlier will have an older version. Soft polish item, not v3-blocking. Same shape as any pinned template content that's authored in the workshop and synced downstream.

  **Edge Cases table** (line 406-419) — 10 scenarios (no templates / no settings.json / no mcp.json / no Makefile / no .gitignore / user declines / running in toolkit repo / custom hooks / no MANIFEST / `.claude-toolkit-ignore` / "re-sync" choice). Closes the common escape hatches.

  **Anti-patterns** (line 422-430) — 6 patterns (auto-fix / remove existing entries / edit settings.local.json / skip validation / overwrite entirely / auto-delete orphans). The "auto-fix without asking" and "auto-delete orphans without asking" rules are the critical ones — this skill's blast radius (entire target-project `.claude/` config) demands per-item approval.

  **See also** — 2 refs: `relevant-toolkit-hooks_config` (exists; doc), `relevant-toolkit-permissions_config` (exists; doc).

  **`type: command`** — correct. Picked up by repo-wide sweep.

  Workshop-shaped: the skill runs in the target project, operates on the target's own `.claude/settings.json` and related files, diagnoses against templates synced from the workshop. It doesn't reach back into the workshop or coordinate other projects — it's a self-contained setup skill. The toolkit-repo guard (line 18) explicitly prevents it from running in the workshop itself.

- **Action:** `type: command` → `metadata: { type: command }` as part of repo-wide sweep (queue item 7). Optional polish (out of scope for this audit): track powerline version bumps in one place — the skill body embeds `@1.25.1` today, would be cleaner to source from a single constants location if the workshop ends up needing to bump multiple references atomically.
- **Scope:** trivial (sweep-covered). Powerline-version-tracking polish is out-of-scope, noted in cross-cutting.

### `setup-worktree/SKILL.md`

- **Tag:** `Keep` (sweep only)
- **Finding:** 115 lines. `type: command`. Mechanical worktree setup: ensure `.worktrees/` gitignored → create worktree → symlink `.claude/` from main if needed → optionally link context file → verify.

  **Gitignore-first step** (line 19-24) — `grep -q '^\.worktrees/' .gitignore 2>/dev/null || echo ".worktrees/" >> .gitignore`. Idempotent check-then-append. Right shape.

  **Symlink `.claude/` conditional** (line 40-58) — the skill correctly distinguishes two cases: (a) project tracks `.claude/` in git (symlink unnecessary, new worktree already has it), (b) project gitignores `.claude/` and syncs via `claude-toolkit sync` (must symlink from main or worktree has zero config). The detection is `if [ ! -d "$WORKTREE/.claude/skills" ]`. Correct — handles both project conventions without assuming one.

  **Per-subdirectory symlinks** (line 51-56) — symlinks `agents`, `hooks`, `memories`, `skills`, `scripts`, and `settings.json` individually. Not a blanket `.claude/` symlink. That's deliberate: lets the worktree's `.claude/` have its own non-shared subdirs (e.g., the worktree might want its own `output/` or `docs/` without leaking changes back to main). Right granularity.

  **On-retry guidance** (line 60) — *"`ln -s` fails if the symlink already exists. Use `ln -sf` to overwrite, or remove the `.claude/` directory in the worktree and start fresh."* Good — explicit about the idempotency failure mode.

  **Common Pitfalls section** (line 78-110) — 4 failure modes (missing Claude resources / stale worktree / orphaned worktree / can't delete branch) each with a recipe. The "orphaned worktrees" entry (line 93-101) is critical: it explains that `rm -rf` without `git worktree remove` leaves dangling git-internal references, and prescribes `git worktree remove` + `git worktree prune`. That's the class of issue users hit hours after the fact and struggle to diagnose.

  **See also** — 1 ref: `/teardown-worktree` (exists; paired skill). Tight pairing.

  **`type: command`** — correct. Picked up by repo-wide sweep.

  Workshop-shaped: runs in consumer's repo, operates on consumer's worktrees. No cross-project coordination.

- **Action:** `type: command` → `metadata: { type: command }` as part of repo-wide sweep (queue item 7).
- **Scope:** trivial (sweep-covered).

### `teardown-worktree/SKILL.md`

- **Tag:** `Keep` (sweep only)
- **Finding:** 78 lines. `type: command`. Mechanical teardown: identify worktree → check uncommitted → copy artifacts → get branch name → remove worktree → checkout branch → check alignment with main.

  **Uncommitted-changes block** (line 21-30) — *"If there are uncommitted changes: Do NOT proceed with teardown. Tell user: 'Worktree has uncommitted changes. Commit or discard them first, then retry.' END"* Correct safety gate — the blast radius of removing a worktree with uncommitted work is lost work. Hard stop is right; don't try to be clever.

  **Copy artifacts step** (line 33-41) — copies `<worktree>/output/claude-toolkit/reviews/*` into parent's `output/claude-toolkit/reviews/`. Silent skip if no artifacts. The scope is narrow — only the `reviews/` subdirectory, not the full `output/claude-toolkit/` — which is probably right: review artifacts are what you want to preserve across teardown; sessions/plans/etc. are per-worktree ephemera. Arguable edge: if the worktree generated `output/claude-toolkit/pr-descriptions/` (via `/draft-pr`) or `output/claude-toolkit/design/` (via `/brainstorm-idea`), those would not be copied. Flag as a low-priority observation — may be deliberate (keep per-worktree scope clean) or may be overscoped-to-reviews. Not v3-blocking; defer.

  **Branch alignment check** (line 64-70) — `git log HEAD..main --oneline` then tells user either "Branch is N commits behind main. Rebase before merging: `git rebase main`" or "On branch `<branch>`. Merge when ready: `git merge --no-ff <branch>`". The `--no-ff` aligns with the CLAUDE.md convention (*"Always use `git merge --no-ff` to preserve branch history"*) — consistent.

  **Constraints section** (line 72-77) — 4 hard rules (uncommitted = blocked / no auto-merge / no branch deletion / copy before remove). Each is correct user-control-over-destructive-ops framing.

  **See also** — 1 ref: `/setup-worktree` (exists; paired skill).

  **`type: command`** — correct. Picked up by repo-wide sweep.

  Workshop-shaped: runs in consumer's repo, operates on consumer's worktrees. No cross-project coordination.

- **Action:** `type: command` → `metadata: { type: command }` as part of repo-wide sweep (queue item 7). Optional observation: consider whether artifact-copy scope should broaden from `reviews/` to include `pr-descriptions/`, `design/`, etc. — defer to a follow-up pass.
- **Scope:** trivial (sweep-covered). Artifact-copy scope is a defer, noted in queue.

### `read-json/SKILL.md`

- **Tag:** `Investigate` (reshape toward hook-pointed reference; also `type:` sweep)
- **Finding:** 123 lines. `type: command`. Tool-policy skill: progressive jq inspection pattern (keys → length → sample → extract), shell-quoting traps, malformed JSON handling, size-based tool selection.

  **User-raised during review:** the skill is falling flat — `/read-json` isn't being invoked. Two reasons: (1) the `suggest-read-json` PreToolUse hook (verified at `.claude/hooks/suggest-read-json.sh`) already catches the actual pain point — Read tool on `.json` files >50KB that aren't in the config-file allowlist (`package.json`, `tsconfig.json`, `*.config.json`, etc.) get blocked with a message pointing at `/read-json`. So the user never has a reason to type `/read-json` themselves; the hook does the catching. (2) Claude sessions now default to jq for JSON inspection; the behavior this skill was originally pushing against ("oh, a 2000-line JSON, let's Read it") isn't the failure mode anymore.

  What the skill's sections are actually worth today:

  | Section | Lines | Status |
  |---------|-------|--------|
  | "DON'T use Read tool" categorical rule | 16-19 | Redundant with hook; also overstated (hook correctly allows small JSON) |
  | Progressive inspection pattern (keys → length → sample → extract) | 22-36 | Baseline session behavior — low load-bearing |
  | File Size table (<1MB / 1-50MB / >50MB) | 103-107 | Baseline session behavior — low load-bearing |
  | Shell quoting traps (`--arg` vs interpolation, `--argjson` for numbers) | 37-64 | **Load-bearing** — these are the actual wrong-results bugs |
  | Malformed JSON recipes (BOM, JSONL, trailing commas, truncated, embedded) | 66-90 | **Load-bearing** — non-obvious gotchas |
  | Anti-patterns table | 109-118 | Mostly redundant with the above |

  **Direction (proposal):** reshape as a short hook-pointed reference rather than a user-invocable command. Two concrete shapes to consider in queue item 4:

  - **Option A (preferred):** demote to `type: knowledge`, set `user-invocable: false` (hide from `/` menu), strip the redundant sections (categorical rule, progressive pattern, file size table, anti-patterns), keep the shell-quoting + malformed-JSON content. Update the `suggest-read-json` hook's block-reason to point at the skill path rather than the `/read-json` command. The skill becomes "what the hook's block-reason is telling you to read," not "a command a user types."

  - **Option B (more ruthless):** delete the skill entirely, fold the shell-quoting + malformed-JSON content into either (i) the hook's block-reason message (cost: longer block message) or (ii) a short doc (`.claude/docs/reference-jq-patterns.md` or similar) that the hook points at. Same net effect as A but no skill resource at all.

  A is lower-risk: preserves the content in place, costs only frontmatter edits + hook message tweak. B is cleaner but requires deciding where the content lives and whether there's a pattern here worth generalizing (hook-pointed knowledge docs as their own resource shape). Decision deferred to a follow-up session — this audit flags the shape problem, not the specific fix.

  **Other content notes** (in case option A is chosen):

  **Shell quoting section** (line 37-64) — the most load-bearing part. Five calibrated patterns: (1) double-quotes-inside-double-quotes bug (eats inner quotes silently), (2) shell-variable interpolation inside jq (wrong-results bug), (3) `--arg` for string vars, (4) `--argjson` for numeric vars (avoids string coercion), (5) quote file paths with spaces. These are the actual jq footguns — the kind that produce wrong results without errors. Keep as-is.

  **Malformed JSON Handling** (line 66-90) — 7 failure modes (validate / parse error / trailing commas / JSONL / BOM / truncated / embedded in other output) each with a concrete recipe. The BOM case (line 83) is the kind of Windows-creates-files gotcha that's impossible to debug without knowing to look for it. Keep as-is.

  **See also** — 1 ref: `suggest-read-json` hook (verified exists). Correct — the skill and the hook are a matched pair, but the pair's direction today is hook → skill (hook points at skill for the "how"), not user → skill → hook-as-guardrail.

  **`type: command`** — likely changes to `type: knowledge` under option A. Picked up by repo-wide sweep regardless.

  Workshop-shaped: runs in consumer's session, operates on consumer's JSON files, references a hook that also syncs to consumers. No cross-project coordination.

- **Action:** (1) reshape per queue item 4 — option A (demote to knowledge, hide from `/` menu, strip redundant sections, update hook block-reason) is the preferred direction; (2) `type:` → `metadata: { type: ... }` as part of repo-wide sweep (queue item 7) — value becomes `knowledge` if option A applies, `command` otherwise.
- **Scope:** (1) small — frontmatter edits + section strip + 1-line hook message change. (2) trivial (sweep-covered).

---

## Cross-cutting notes

- **`type:` frontmatter inventory, updated.** Full-directory count across the audit so far: **16 skills confirmed carrying `type:`**. This subset contributes 6 (5 command + 1 knowledge). Per-subset breakdown for the sweep:
  - Workflow: 4
  - Code quality: 1
  - Design & arch: 3
  - Personalization: 2
  - Dev tools (this subset): 6
  - Remaining (Toolkit Development, 9 skills): expected to contribute ~6-7 more based on the grep of the full directory (19 total `type:` hits across all skills). Consumer side of the sweep is in that subset — `evaluate-skill` and `evaluate-batch` read the field.

  All 6 dev-tools `type:` instances sit at canonical line 3. No frontmatter field-ordering drift in this subset (unlike `build-communication-style` in personalization).

- **`write-documentation` path drift is a real bug, not a sweep-style nit.** Line 40 references `output/claude-toolkit/reviews/codebase/` but the `codebase-explorer` agent writes to `.claude/docs/codebase-explorer/{version}/`. The `output/claude-toolkit/reviews/` folder is for *session review artifacts* produced by `code-reviewer`, `goal-verifier`, `code-debugger`, `proposal-reviewer`, `implementation-checker` — not architecture reports. Fix is a 1-line path correction. Worth flagging because this is the kind of path-drift a cross-reference validator could catch if it understood agent-output-path conventions — feeds the "small validators" backlog theme from prior subsets.

- **`setup-toolkit` is large but load-bearing.** 431 lines, 3 phases, 8 diagnostic checks, multiple sub-fix-handlers, inline powerline config. No split is reasonable — the skill's job *is* to walk a single approval flow across the whole target-project config, and splitting would multiply the user-facing coordination. The size reflects the scope, not the quality.

- **Powerline version pin in `setup-toolkit` is a content-versioned dep.** Line 321: `@owloops/claude-powerline@1.25.1` hardcoded inside the skill body. Same shape as any pinned template content synced downstream — when the workshop bumps it, consumers who synced earlier still have the old version until they re-sync. Polish item, not v3-blocking. Worth noting: if there are other places powerline version is referenced, they should bump together.

- **Worktree pair is canonical small-pair shape.** `setup-worktree` ⇄ `teardown-worktree`. Each references the other in See also. Each does one thing (create / remove). No overlap. Same pattern as the `build-communication-style` ⇄ `snap-back` pair from personalization subset. When small pairs are this tight, they're the easiest shapes to Keep.

- **Skill-plus-hook pair (`read-json` + `suggest-read-json`) has a direction problem.** The skill was designed as a user-invocable command with the hook as backup guardrail. In practice the hook does all the catching and the skill is never invoked directly — so the pair's direction is actually hook → skill (hook blocks Read on large JSON, points user at jq patterns for the "how"), not user → skill → hook-as-guardrail. See `read-json/SKILL.md` finding and queue item 4 for the reshape proposal. **Implication for future skill-plus-hook pairs:** if the hook covers the trigger condition reliably, the skill should be shaped as a hook-pointed reference (knowledge, hidden from `/` menu), not as a user-invocable command competing with the hook for the same job. Worth cataloging as a small-pair shape distinct from the tight user-invocable pair seen in worktrees and personalization.

- **No `/brainstorm-idea` See also references in this subset.** Workflow queue item 3 (brainstorm rename to `/brainstorm-feature`) imposes zero lockstep burden here.

- **No orchestration-shaped leakage.** All 6 skills run inside the consumer's session and operate on the consumer's own repo (docs, PR text, worktree, JSON files, or `.claude/` config). `setup-toolkit` is the largest-scope skill but it's self-contained within the target project, not cross-project. Workshop identity clean.

- **Output-shape consistency with code-quality observation.** `draft-pr` writes to `output/claude-toolkit/pr-descriptions/{timestamp}_{branch-name}.md` — matches the "workflow/analysis skills save artifacts to `output/claude-toolkit/`" shape from the code-quality cross-cutting note. `write-documentation` writes to the user's own doc files (not to `output/claude-toolkit/` — correct, because it's producing user-facing docs, not session artifacts). `setup-toolkit` writes to the consumer's `.claude/settings.json` and related config (not to `output/claude-toolkit/` — correct, because it's a config fix, not an artifact). Knowledge skills (`write-documentation`, `read-json`) don't save artifacts. Consistent.

---

## Decision-point queue (carry forward)

**Resolved during review (pending execution — trivial scope):**

1. `write-documentation/SKILL.md` line 40 — **fix broken path reference:** `output/claude-toolkit/reviews/codebase/` → `.claude/docs/codebase-explorer/{version}/`. One-line correction. Aligns with `codebase-explorer` agent's actual output location and the CLAUDE.md codebase-orientation convention.

**Coordinated with other audit directories:**

2. **`type:` frontmatter sweep** — contributes 6 instances from this subset (5 command + 1 knowledge). Running total across audited subsets: **16** (4 workflow + 1 code quality + 3 design & arch + 2 personalization + 6 dev tools). Remaining Toolkit Development subset will add the last ~3 to reach the full-directory total of ~19. Picked up by workflow queue item 7. The consumer side (`evaluate-skill` / `evaluate-batch` read `metadata.type`) will be audited in the Toolkit Development subset.

3. **Small validators theme** — `write-documentation`'s broken path (`output/claude-toolkit/reviews/codebase/` vs `.claude/docs/codebase-explorer/`) is the kind of drift a cross-reference validator that understands agent-output-path conventions could catch. Feeds the same "small validators" backlog bundle from personalization queue item 4 — output-path validator (workflow queue item 10) + cross-reference validator + indexes-validator. Stage-5 polish.

**Open — needs decision in a follow-up session:**

4. **Review `read-json` skill — reshape toward hook-pointed reference (user-raised during this review).** The skill is falling flat: `/read-json` isn't invoked because the `suggest-read-json` hook already catches the pain point (Read on >50KB non-allowlisted `.json`), and sessions now default to jq anyway — so the "don't Read JSON" / "progressive inspection" / "file size table" sections are documenting what's already baseline. The load-bearing content is the shell-quoting traps (`--arg`/`--argjson` vs interpolation) and malformed-JSON recipes (BOM, JSONL, trailing commas, truncated, embedded).

   Two shapes to choose between:

   - **Option A (preferred, low-risk):** demote to `type: knowledge`, add `user-invocable: false` (hide from `/` menu), strip the redundant sections (categorical rule, progressive pattern, file-size table, anti-patterns table), keep shell-quoting + malformed-JSON content. Update `suggest-read-json` hook's `_BLOCK_REASON` (hook line 73) to point at the skill path rather than `/read-json` command syntax. Net: the skill becomes what the hook tells users to read, not a command.

   - **Option B (more ruthless):** delete the skill, fold the load-bearing content into either (i) the hook's block-reason message (cost: longer block text) or (ii) a new short doc (e.g., `.claude/docs/reference-jq-patterns.md`) the hook points at.

   A is lower-risk and preserves the content in place. B is cleaner but raises a broader question — whether "hook-pointed knowledge doc" is a resource shape the workshop should formalize. Deferred to a follow-up session; this audit logs the finding, not the fix.

   **Broader implication:** this is the first dev-tools skill-plus-hook pair where the direction flipped from (user → skill, hook as guardrail) to (hook → skill, hook does the catching). If the pattern generalizes, future skills paired with reliable-coverage hooks should be shaped as hook-pointed references by default, not as user-invocable commands.

**Still open / low-priority:**

5. **`teardown-worktree` artifact-copy scope.** Currently copies only `output/claude-toolkit/reviews/*` from worktree to parent. Does not copy `pr-descriptions/`, `design/`, `plans/`, `sessions/`, or other `output/claude-toolkit/` subdirs. Could be deliberate (keep per-worktree ephemera scoped to the worktree; only preserve review artifacts) or could be overscoped-to-reviews (a user who ran `/draft-pr` or `/brainstorm-idea` in the worktree loses those artifacts at teardown). Defer decision to a follow-up pass — neither choice is v3-blocking.

6. **`setup-toolkit` powerline version bump tracking.** `@owloops/claude-powerline@1.25.1` is pinned inline at line 321. If there are other references to powerline version across the workshop, they should bump in lockstep. Worth a quick grep during the next statusline-related change. Polish, not v3-blocking.

7. **`setup-toolkit` size.** 431 lines is large but load-bearing — no reasonable split. Noted for context; no action.
