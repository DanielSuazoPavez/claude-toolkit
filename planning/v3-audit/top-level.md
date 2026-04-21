# v3 Audit — top-level files + small top-level dirs

Exhaustive file-level audit of top-level files, `bin/`, `docs/`, plus note-and-dismiss calls on `logs/`, `dist-output/`, `tests/`, and build/tooling artifacts.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Scope notes

In scope (audit targets):
- Top-level files: `.gitignore`, `.mcp.json`, `BACKLOG.md`, `CHANGELOG.md`, `CLAUDE.md`, `Makefile`, `README.md`, `VERSION`, `pyproject.toml`, `uv.lock`
- `bin/` — 1 script
- `docs/` — user-facing docs + indexes (user call: "needs a pass")

Out of scope (noted, not walked):
- `tests/` — infra; own audit if/when done
- `logs/` — schema-smith side effect; removable (user call)
- `dist-output/` — last-push artifact, not a source of truth
- `.git/`, `.venv/`, `.pytest_cache/`, `.worktrees/` — build/tooling artifacts

---

## Summary

Top-level is in good shape overall — stage 1 (identity rewrite) has already landed in the high-leverage prose surfaces (`CLAUDE.md`, `README.md`, `docs/getting-started.md`). Nothing at the top level reads like orchestrator-thinking leakage post-stage-1.

The notable findings are **drift in the index layer** — `README.md` counts are stale (says 32 skills / 10 hooks / 12 docs; actual 35/12/13), `docs/indexes/DOCS.md` has an inconsistent shape relative to `HOOKS.md` / `AGENTS.md` (no "Related" column, no description of what each doc teaches), and `docs/getting-started.md` lists a different subset of agents and docs than what actually ships (names `codebase-explorer, code-debugger, code-reviewer, goal-verifier, implementation-checker` — that's the raiz subset, not base; omits `pattern-finder` and `proposal-reviewer` which ship in base).

Smaller findings: one referenced orientation path is stale (`.claude/docs/codebase-explorer/` in `CLAUDE.md` line 75, already flagged in the `.claude/agents/` audit), `logs/` should be nuked, `dist-output/` convention is correct (gitignored + in .gitignore), and the `Makefile`'s `make check` docstring in `CLAUDE.md` line 24 says *"`make check` here = `make test` + `make validate`"* but the actual target is `check: test lint-bash validate` — **CLAUDE.md is out of date on its own make rule** (shellcheck gate added 2026-04-20 per CHANGELOG 2.60.2).

Findings below: 6 Rewrite (mostly small text/path drift fixes plus `.mcp.json` local-config move), 1 Investigate (evaluations.json split-by-type), 1 Defer (CHANGELOG is massive but it's append-only and audit-walking it isn't useful), 5 Keep.

---

## Files

### `.gitignore`

- **Tag:** `Rewrite`
- **Finding:** Properly scoped overall, no orchestration-shaped assumptions — but **two stale entries** the user flagged:

  1. **`.claude/learned.json`** (line 20). This is the legacy per-project lessons file. The lessons ecosystem has migrated to `~/.claude/lessons.db` (global, sqlite). `learned.json` now only appears as a fallback in `session-start.sh` (lines 206-220) and `cli/lessons/db.py` `cmd_migrate` — both queued for removal in the `.claude/hooks/` audit queue item 7 (coupled with `cli/` audit). When those land, this `.gitignore` line is dead. Either remove now (the file is functionally obsolete) or remove in coordination with the session-start + cli cleanup.

  2. **`.claude/scripts/cron/cron.log`** (line 32). Currently load-bearing — `.claude/scripts/cron/` still ships `backup-lessons-db.sh` (confirmed on disk) and writes to `cron.log` there. But the coupling is brittle: if any cron script generates a new log name, it needs a new ignore line. Consider widening to `.claude/scripts/cron/*.log` so future cron log names are covered. Minor, not urgent.

  Related staleness: 2.60.4 removed `backup-transcripts.sh` from here (moved to claude-sessions). `backup-lessons-db.sh` should follow the same pattern — **user confirmed**: the lessons runtime schema is owned by claude-sessions per the v3 canon, so the backup cron belongs there. Once it lands there, this `.claude/scripts/cron/` directory empties entirely and the cron.log gitignore line goes with it.

  One more micro-item: line 33 `.claude/logs/` — is this dir actually in use anywhere? `session-start.sh` writes `.claude/logs/session-start-sizes.log` per HOOKS.md line 61. So that line is load-bearing. Keep.

  Cross-ref: this `.gitignore` is the **toolkit repo's** — different from `dist/base/templates/gitignore.claude-toolkit` which ships to consumers. The dist/ one was flagged in the dist/ audit for stale `session-index.db` / `hooks.db` entries. Independent files, but similar drift patterns — worth checking the dist/ gitignore for the same `learned.json` staleness when the session-start cleanup lands.

- **Action:** at decision point: (1) remove `.claude/learned.json` line — coordinate with `.claude/hooks/` queue item 7 (session-start legacy fallback removal) and `cli/` queue (cmd_migrate removal), (2) remove `.claude/scripts/cron/cron.log` line (redundant with `logs/`, and check if `.claude/scripts/cron/` is even populated now). Also: re-check `dist/base/templates/gitignore.claude-toolkit` for the same `learned.json` entry when the coordinated cleanup lands.
- **Scope:** trivial — 2-line deletion. Coordination is the only reason to stage it.

### `.mcp.json`

- **Tag:** `Rewrite`
- **Finding:** Committed MCP config with two servers: `sequential-thinking` (Anthropic's) and `context7` (upstash, library docs). The bash-wrapped PATH injection (`PATH=/home/hata/.nvm/versions/node/v22.22.0/bin:$PATH`) is a per-machine value that shouldn't be in a committed file.

  **User call:** the toolkit repo itself isn't a consumer of the sync mechanism (and isn't exposed in the sense of "someone else inherits my config"), so the impact is narrow — the commit is just a mistake, not a leak. Fix is straightforward: the machine-specific config belongs in `settings.local.json` (or equivalent local file), not `.mcp.json`. Same two-tier pattern already applied to `.claude/settings.json` vs `.claude/settings.local.json`.

- **Action:** at decision point: move the PATH-prefixed MCP server entries to a local-only config (e.g., `.claude/settings.local.json`'s `mcpServers` block, which Claude Code merges). Keep `.mcp.json` committed with only portable entries (or empty, if both are machine-specific). Verify both servers still resolve after the move.
- **Scope:** small — single-file edit + verify MCP servers still load.

### `BACKLOG.md`

- **Tag:** `Keep`
- **Finding:** Clean and current. P0 is the v3 stages 1-5 (what we're doing). P3 has one self-resolving item (`remove-ecosystems-opt-in-nudge`), two bigger ideas (`/design-aws` skill, `improve-lessons-lifecycle`). P99 has three nice-to-haves, two of which (`agent-model-routing`, `agent-reasoning-activation`) overlap with this stage's `.claude/agents/` findings — good signal that the audit-surfaced items are already in view, just at lower priority.

  The schema follows `relevant-workflow-backlog.md` conventions. No drift.

  One small observation: BACKLOG is doubly-authoritative with `make backlog` / `claude-toolkit backlog` (line 12-13 of CLAUDE.md — *"prefer over reading BACKLOG.md directly"*). The `cli/backlog/` query tooling is the intended read path. Since it's text-based and human-written, both routes work — but the tool exists because BACKLOG grows. Keep as-is; no action.
- **Action:** none.

### `CHANGELOG.md`

- **Tag:** `Defer`
- **Finding:** 2258 lines, append-only. Structure is correct: `[Unreleased]` section at top, then per-version entries newest-first. `[Unreleased]` currently holds the v3 Stage 1 identity-rewrite note (correct per CLAUDE.md §Changelog rule — *"Docs-only changes: [Unreleased] section, no version bump"*). Recent entries (2.60.1 through 2.61.0) look clean and follow the Keep-a-Changelog convention.

  Audit-walking 2258 lines for orchestrator-thinking leakage isn't a good use of attention. The `Unreleased` and the last ~10 versions are the surface where stage-1-era thinking would show up, and they're clean. Older history is frozen; rewriting prose from 10+ releases ago has no return.
- **Action:** none.
- **Scope:** deferred (not worth the effort).

### `CLAUDE.md`

- **Tag:** `Rewrite`
- **Finding:** Post-stage-1 identity work: Project Overview correctly calls this a *"resource workshop"* and points to `.claude/docs/relevant-project-identity.md`. Structure section correctly describes `.claude/docs/` vs `docs/`. No orchestrator leakage.

  **Three drift items:**

  1. **Line 24 `make check` description is stale.** Text says *"`make check` here = `make test` + `make validate` (no lint target in this repo — it's bash-first)"*. The actual Makefile target (line 86) is `check: test lint-bash validate`. The `lint-bash` gate was added in 2.60.2 (shellcheck-shipped-bash, 2026-04-20). So the line is wrong on both points: lint *is* present, and the list is incomplete.

  2. **Line 75 codebase-explorer path is stale.** *"`.claude/docs/codebase-explorer/` — versioned architecture reports"*. Same drift flagged in the `.claude/agents/` audit (item 6): codebase-explorer output is getting moved to `output/claude-toolkit/codebase/{version}/`. CLAUDE.md line 75 updates as part of that fix — cross-reference noted.

  3. **Line 52 references `docs/indexes/evaluations.json`** — confirmed exists (43KB file). Not drifted, but the CLAUDE.md description *"Quality scores, grades, and improvement suggestions"* is one sentence; `evaluations.json` is the only index without a backing `.md` (it's raw data, no human-readable sibling). Not a finding per se, but worth noting that **every other index is markdown** — the JSON is the odd one out. Not a v3-audit action.

- **Action:** at decision point: (1) fix line 24 to include `lint-bash` and drop the "no lint target" clause, (2) update line 75 when the `.claude/agents/` codebase-explorer path fix lands (coordinated).
- **Scope:** trivial — two-line edit.

### `Makefile`

- **Tag:** `Keep`
- **Finding:** Clean, well-documented. Every test target has an explicit entry, `make help` describes them all, `make check = test + lint-bash + validate` is the canonical verification. Adopts bash-first convention per `essential-conventions-code_style.md` §4 — `make check` is read-only (no formatters).

  The `lint-bash` target's install hint is friendly (*"install: sudo apt install shellcheck (or: brew install shellcheck)"*) and fails clearly when missing. The `tag` target is idempotent. No findings.

  Small observation (not an action): the `help` description for `check` says *"Run everything (tests + lint-bash + validate)"* while `CLAUDE.md` line 24 lists only two of the three targets — the Makefile help is right, CLAUDE.md is stale (see CLAUDE.md finding).
- **Action:** none.

### `README.md`

- **Tag:** `Rewrite`
- **Finding:** Post-stage-1 reframe is present and reads well (*"A resource workshop for Claude Code"*, Design Philosophy section explicitly names the workshop/satellite relationship). No orchestrator leakage.

  **Two content-drift items:**

  1. **"What's Included" counts are stale.** Line 80-86 table says **32 Skills / 7 Agents / 10 Hooks / 12 Docs**. Actual: **35 skills / 7 agents / 12 hooks / 13 docs** (counted `.claude/skills/*`, `.claude/agents/*`, `.claude/hooks/*.sh`, `.claude/docs/*`). Agent count is accurate; rest drifted. Easy fix: update the numbers. **Better fix:** reference a live-generated count somewhere (e.g., "(generated from `docs/indexes/`)") — but generating README numbers automatically is out of scope for v3. For now: update the static counts.

  2. **Agent examples listed.** Line 83 table row reads `"code-reviewer, code-debugger, pattern-finder"`. That's fine as an illustrative example, but given the `.claude/agents/` audit surfaced a pattern-finder-vs-Explore question, this README line becomes a load-bearing reference if pattern-finder is deprecated. If pattern-finder goes away in the audit-followup work, this example string updates. Note as a dependency, not an action here.

- **Action:** at decision point: (1) update "What's Included" counts to 35/7/12/13 (or generate from indexes), (2) coordinate pattern-finder mention if that agent is deprecated in audit-followup.
- **Scope:** trivial — 4-number update.

### `VERSION`

- **Tag:** `Keep`
- **Finding:** Single line, `2.61.0\n`. Matches the latest versioned CHANGELOG entry (2.61.0 Ecosystems opt-in). Read by `make tag`, `pyproject.toml` (via `[tool.hatch.version]` path pattern), and `claude-toolkit sync` for version comparison. Single source of truth, correctly used.
- **Action:** none.

### `pyproject.toml`

- **Tag:** `Keep`
- **Finding:** Minimal and correct. `dynamic = ["version"]` sourced from VERSION file (the hatch pattern `(?P<version>.+)` handles the trailing newline). `ct-lessons` CLI entrypoint wired to `cli.lessons.db:main`. Dev dep: pytest. Test config: `testpaths = ["tests"]`, `pythonpath = ["."]`. Minimal config, matches `essential-conventions-code_style.md` §3 preference for "use language built-ins and standard patterns."

  Notable absences (all correct): no ruff config here (the toolkit doesn't lint Python — bash-first project per CLAUDE.md line 24), no `ty` config, no linters. `essential-conventions-code_style.md` §3 says Python tooling should use ruff / ty — but that's *guidance for synced consumer projects*, not the toolkit repo. Toolkit ships bash. Python subset is small (cli/lessons, tests/pytest). Not a drift.
- **Action:** none.

### `uv.lock`

- **Tag:** `Keep`
- **Finding:** Generated. Not audited (lockfiles aren't read top-to-bottom for orchestration-shape).
- **Action:** none.

### `bin/claude-toolkit`

- **Tag:** `Keep`
- **Finding:** 769-line bash CLI entry point. Thin dispatcher on top: `sync`, `send`, `lessons`, `backlog`, `eval`, `validate`, `version`. Three commands are defined inline (`cmd_sync`, `cmd_send`, `cmd_validate`); three delegate via `exec` to subtree scripts (`lessons` → `.venv/bin/ct-lessons`, `backlog` → `cli/backlog/query.sh`, `eval` → `cli/eval/query.sh`).

  Workshop-shaped: this is the public tool for consumers (per README.md — *"Add to PATH"*) and the interface used by `sync`/`send`/`validate`. Nothing here reaches into downstream projects; `sync` writes files to a user-specified target, which is the expected workshop→consumer mechanism.

  A few observations worth noting but not acting on:

  - `cmd_sync` is a 400+ line function — candidate for splitting but that's a `cli/` audit concern, not top-level. The `cli/` audit may have already covered this.
  - `send` auto-detects project from git root — reasonable. The docstring (line 87 of CLAUDE.md) says *"check suggestions"* workflow, which is the receive-side; send-side is here. Clean split.
  - `validate` command `exec`s `.claude/scripts/setup-toolkit-diagnose.sh` with pass-through args. This is the consumer-side diagnostic. Correct separation.
  - **User note:** the CLI surface might carry more than needs to ship (lessons + backlog subcommands in particular). Already flagged in prior audits (cli/ + hooks/ queues touch the lessons-ecosystem question). No new action from this audit — just cross-referencing.

  One drift to note (not from this audit): the CLI script mentions `make claude-toolkit-validate` and `make claude-toolkit-sync` in post-sync checklist (lines 738-739) — those are the synced-Makefile targets in consumer projects, not the toolkit's own Makefile. Correct phrasing for a downstream user reading this post-sync.

- **Action:** none. CLI subcommand scope is covered by the `cli/` audit queue.

### `docs/curated-resources.md`

- **Tag:** `Keep`
- **Finding:** Small, clearly-scoped catalog of external references. Explicit boundary: *"Not synced to projects — reference catalog only."* Four external repos with local summary links. Matches the `output/claude-toolkit/exploration/` pattern per `relevant-project-identity.md` §5: *"Curated references are the lane for 'interesting but not actionable now.'"*

  Clean workshop-identity: these are resources the toolkit author has reviewed but chose NOT to import. Explicit curation signal.
- **Action:** none.

### `docs/getting-started.md`

- **Tag:** `Rewrite`
- **Finding:** This file is the user-facing onboarding doc for consumers (*"You've received a `.claude/` folder..."*). Post-stage-1 reframe present: *"claude-toolkit, a workshop where these skills, agents, hooks, and docs are authored, refined, and distributed. Your project is a downstream consumer."* Good framing.

  **Content drift in the resource tables** (lines 13-61):

  1. **Skills table (line 15-25)** lists **9 skills**: brainstorm-idea, build-communication-style, create-docs, draft-pr, read-json, review-plan, setup-toolkit, wrap-up, write-handoff. That's the **raiz subset minus a couple**. Actual base ships 35. This is defensible — getting-started is for newly-synced projects and shouldn't dump 35 skills on a first-read. BUT: the wording above the table (line 13: *"Commands you invoke by typing `/name`"*) doesn't say "here are the starter ones" or "these are highlighted" — it presents the 9 as if they were the full list. **Drift:** either relabel as *"Starter skills (see `docs/indexes/SKILLS.md` for the full list)"*, or the table should match actual ship count.

  2. **Agents table (line 31-38)** lists **5 agents**: codebase-explorer, code-debugger, code-reviewer, goal-verifier, implementation-checker. That's literally the raiz MANIFEST. Actual base ships 7 (those 5 + pattern-finder + proposal-reviewer). **Drift:** same framing question — either label as "raiz subset" or include the missing two.

  3. **Hooks table (line 43-51)** lists **7 hooks**: approve-safe-commands, block-config-edits, block-dangerous-commands, git-safety, secrets-guard, session-start, suggest-read-json. Missing: `enforce-make-commands`, `enforce-uv-run`, `surface-lessons`, and the two grouped-dispatchers. That's ~10 hooks in base, raiz ships 9. **Drift:** same.

  4. **Docs table (line 57-60)** lists **2 docs**: code_style, context. Actual base ships 13. This one is the most misleading — *"Essential docs are loaded at the start of each session; others are read on-demand"* is accurate, and the 2 listed are the `essential-*` prefix docs. But again: no "this is the essential subset" framing. Reader sees the table as "what ships."

  **Why it matters:** new consumers read this file when the sync lands. Under-counting leads them to think the toolkit is smaller than it is, and they don't discover relevant skills/agents/hooks.

  **User confirmed:** direction (a) — relabel each table as a starter subset and link to `docs/indexes/*.md` for completeness. Preserves the onboarding scope without lying about what ships.

  Secondary: **Activation instructions reference `.claude/templates/`** (line 99, 104, 117) — correct per `dist/base/templates/` syncing to `.claude/templates/` in consumers. No drift here.

- **Action:** at decision point: (1) relabel each of the 4 tables (Skills / Agents / Hooks / Docs) with a starter-subset framing plus a *"See `docs/indexes/SKILLS.md` for all 35 skills"* (etc.) link above or below each table, (2) coordinate with pattern-finder deprecation outcome in `.claude/agents/` queue (affects agent subset content).
- **Scope:** small — 4-table edit, ~20-30 lines touched.

### `docs/indexes/AGENTS.md`

- **Tag:** `Rewrite`
- **Finding:** Already flagged in the `.claude/agents/` audit (queue item 12). Two drift points confirmed:
  - codebase-explorer "Explores codebase and writes structured analysis to `output/claude-toolkit/reviews/codebase/`" — wrong path (agent writes to `.claude/docs/codebase-explorer/{version}/`). Fixing this is tied to the codebase-explorer path migration (agents queue item 6).
  - goal-verifier marked `experimental` with restore-to-commit note (agents queue item 7).
- **Action:** covered by `.claude/agents/` decision queue items 6 and 7 — no independent action from this audit.

### `docs/indexes/DOCS.md`

- **Tag:** `Rewrite`
- **Finding:** Shape mismatch with siblings. Compare column structure:
  - `AGENTS.md`: Agent / Status / **Description** / **Tools**
  - `HOOKS.md`: Hook / Status / **Trigger** / **Opt-in** / **Description**
  - `SKILLS.md`: Skill / Status / **Description**
  - `DOCS.md`: Doc / Status / **Purpose**

  DOCS uses *Purpose* where the others use *Description*. More importantly, the `Purpose` column is one-line and often doesn't say what the doc teaches — compare:
  - `relevant-toolkit-context` / "Docs/memories boundary, naming conventions, categories" — clear.
  - `relevant-philosophy-reducing_entropy` / "Philosophy on reducing codebase entropy" — tautological (restates the name).

  Also: no "Related" or "See also" cross-references, which the other indexes use liberally. And the DOCS index doesn't indicate *which docs are `essential-*` vs `relevant-*`* via a column — it uses section headers (Essential Docs / Relevant Docs), which works, but the distinction could be a column for machine-readability.

  Third: DOCS index doesn't show per-doc size / "Quick Reference availability." `essential-*` docs have a §1 Quick Reference by convention (`relevant-toolkit-context.md` establishes this). Knowing which docs have a Quick Reference is useful for the `/list-docs` skill's summary output.

- **Action:** at decision point: (1) decide whether to normalize column naming across indexes (Purpose → Description, or keep divergent), (2) flesh out one-line descriptions that restate the filename (e.g., `relevant-philosophy-reducing_entropy` — current text is tautological), (3) consider adding a "Quick Reference" column or indicator, (4) optionally add cross-references.
- **Scope:** small — content-level rewrite of a single index file.

### `docs/indexes/HOOKS.md`

- **Tag:** `Keep`
- **Finding:** Rich and current. Opt-in ecosystems table (lines 6-13) accurately documents `CLAUDE_TOOLKIT_LESSONS` and `CLAUDE_TOOLKIT_TRACEABILITY` per the 2.61.0 release. Hook entries include status, trigger, opt-in gating, and description. Per-hook detail sections below the table (lines 47-178) provide trigger specifics, matchers, config env vars — this is the index that actually earns its keep as a reference.

  Shared Library section (lines 34-43) documents hook-utils.sh columns, call_id format (post-2.60.1 fix), join to claude-sessions.tool_calls. That's exactly the information the `.claude/hooks/` audit suggested should live in docs. Good drift-absorption.

  One micro-drift: line 44 — the "Creating New Hooks" section bottom (line 184-206) says *"Hook receives tool context as JSON on stdin, parsed by `hook_init()` in `lib/hook-utils.sh`"*. Accurate. The listed triggers table (lines 193-198) lists SessionStart / PreToolUse / PostToolUse / Stop — omits EnterPlanMode, PermissionRequest, Notification (all used by current hooks: `git-safety.sh` does EnterPlanMode, `approve-safe-commands.sh` does PermissionRequest). Minor, but the table is presented as authoritative.
- **Action:** at decision point (low priority): extend "Available Triggers" table to include EnterPlanMode, PermissionRequest, and any other Claude Code events the toolkit uses.
- **Scope:** trivial.

### `docs/indexes/SCRIPTS.md`

- **Tag:** `Keep`
- **Finding:** Small, clean. Three sections: Diagnostic, Validation, Statusline. Each entry has Status / Synced / Description. `verify-external-deps.sh` correctly marked `synced: no` (it's a toolkit-internal validator). All paths and references look current.

  One observation: this is the only index with a `Synced` column, and it's useful — the distinction between toolkit-internal (doesn't sync) and shipped (does) is load-bearing for consumers. The other indexes could adopt this convention but it's more relevant for scripts than for skills/agents/hooks where almost everything syncs.
- **Action:** none.

### `docs/indexes/SKILLS.md`

- **Tag:** `Keep`
- **Finding:** Current and well-organized. 35 skills across 6 sections (Workflow & Session, Code Quality, Design & Architecture, Development Tools, Toolkit Development, Personalization). Each has Skill / Status / Description. The `*` notation (*"under consideration for removal (low usage)"*) is a nice signal-preserving pattern, though none are currently marked.

  Organization matches the create/evaluate-meta split — the "Toolkit Development" section (create-skill, create-agent, create-docs, create-hook, evaluate-*, evaluate-batch) groups the dist-excluded skills coherently.

  One note for the skills-audit stage: this index will be load-bearing for walking `.claude/skills/` — the category headings here are a good partition for the audit (walking 35 skills linearly is a lot; category-by-category is more tractable).
- **Action:** none.

### `docs/indexes/evaluations.json`

- **Tag:** `Investigate`
- **Finding:** 43KB JSON. Contains evaluation schema (dimensions D1-D7 per the first 20 lines) and scoring data for skills, agents, and likely hooks + docs. Read by `cli/eval/query.sh` + related scripts.

  **User call:** consider splitting by resource group. Rationale: a single 43KB JSON mixing skills / agents / hooks / docs makes targeted reads expensive (every `cli/eval/query.sh type=skill` has to parse the whole file). Splitting into `evaluations-skills.json`, `evaluations-agents.json`, `evaluations-hooks.json`, `evaluations-docs.json` would:
  - Let each `/evaluate-*` skill write to its own file (simpler writes, no merge step).
  - Make `cli/eval/query.sh` reads cheaper — only load the group being queried.
  - Align with the already-split `docs/indexes/{SKILLS,AGENTS,HOOKS,DOCS,SCRIPTS}.md` — indexes are by type, why isn't evaluations?
  - Make diff review of evaluation churn clearer (one file per group).

  Diagnostic step before acting: read the actual schema and understand (a) are there cross-type references in the data that would break if split? (b) is there shared metadata at the top level (dimensions, scoring rubric) that would need to be factored out or duplicated? (c) what does `cli/eval/query.sh` do today — is the split trivial on the query side?

- **Action:** at decision point: (1) read the full `evaluations.json` schema, (2) check `cli/eval/query.sh` for how it indexes by type, (3) decide split strategy (per-type files + shared rubric file, or per-type files with duplicated rubric), (4) migrate, (5) update `/evaluate-*` skills to write to their specific file.
- **Scope:** small-moderate — depends on how deeply `cli/eval/` is coupled to the flat-file shape.

---

## Out-of-scope dirs (noted)

### `logs/schema_smith/`

- **User call:** *"side effect of schema-smith, we could just remove it."*
- **Finding:** One subdir (`generate/`), March-dated, unreferenced by any live toolkit code (schema-smith is a satellite, not part of the workshop).
- **Action:** at decision point: `rm -rf logs/schema_smith/` (and ideally `logs/` since `.gitignore` already covers it — it's gitignored, so the dir being present is just filesystem debris).
- **Scope:** trivial.

### `dist-output/`

- **User call:** *"just 'this got to {distribution} in last push'."*
- **Finding:** Confirmed: `dist-output/raiz/docs/getting-started.md` is a copy from a push. Already `.gitignore`d (line 28 of `.gitignore`). Correct convention — last-push artifact, reproducible from `dist/raiz/`. No action.
- **Action:** none.

### `tests/`

- **User call:** *"infra."*
- **Finding:** Not walked. Has its own CLAUDE.md per the toolkit orientation (CLAUDE.md line 79: *"`tests/CLAUDE.md` — test file map, runners, shared helpers"*). If a tests audit becomes necessary, it's a separate doc.
- **Action:** none (deferred to a separate audit if/when done).

---

## Cross-cutting notes

- **Stage-1 prose work is solid at the top level.** `CLAUDE.md`, `README.md`, `docs/getting-started.md` all have the workshop framing. The drift in these files is *counts* and *paths*, not identity. Stage 1's scope was correct.

- **Index layer has multiple drift points** that compound: `README.md` counts are wrong, `docs/getting-started.md` under-lists, `DOCS.md` has column shape mismatch, `AGENTS.md` has path drift. None of these are big individually. Collectively they suggest the index layer needs **a single pass to normalize columns + refresh counts** — not one-off fixes per file. That's a natural v3-stage-5 polish item.

- **No validator for index freshness.** Nothing currently gates "README counts match `.claude/` counts" or "`DOCS.md` columns match `AGENTS.md` columns." The `.claude/scripts/validate-resources-indexed.sh` script checks resources-vs-index alignment (disk matches index), but not index-vs-index coherence or README-vs-disk drift. Low-priority — validators earn their keep when something breaks repeatedly; one count-drift isn't that.

- **`CLAUDE.md` has two self-inconsistencies with the Makefile** (line 24 — `make check` composition omits `lint-bash`, said "no lint target" when lint-bash exists). This is the most actionable drift at the top level: consumers read `CLAUDE.md` and will be confused by the mismatch.

- **Cross-audit coordination points:** `CLAUDE.md` line 75 codebase-explorer path, `README.md` pattern-finder example in agent list, `docs/indexes/AGENTS.md` drift — all already covered by the `.claude/agents/` audit's decision queue. No new work, just coordinated application.

---

## Decision-point queue (carry forward)

Every item below is a real work item. None are blocked behind the v3 reshape — they're just audit-surfaced issues that get scheduled like any backlog work.

**Resolved during review (pending execution — trivial scope):**

1. `CLAUDE.md` line 24 — **fix `make check` description** to include `lint-bash` and drop the "no lint target" clause. 1-line edit.
2. `README.md` line 80-86 — **update "What's Included" counts** from 32/7/10/12 to actual 35/7/12/13. 4-number update.
3. `logs/schema_smith/` — **delete** (schema-smith side effect, gitignored, unreferenced). `rm -rf logs/`.
4. `docs/indexes/HOOKS.md` — **extend "Available Triggers" table** to include EnterPlanMode and PermissionRequest. Trivial.

**Resolved during review (pending execution — small scope):**

5. `.gitignore` — **remove `.claude/learned.json` line** (legacy lessons fallback, file functionally obsolete). Coordinate with `.claude/hooks/` queue item 7 (session-start legacy fallback removal) + `cli/` queue (`cmd_migrate` removal). Also: re-check `dist/base/templates/gitignore.claude-toolkit` for the same staleness. Optionally widen `.claude/scripts/cron/cron.log` to `.claude/scripts/cron/*.log`.
6. `.mcp.json` — **move machine-specific MCP entries to `settings.local.json`'s `mcpServers` block**. Keep `.mcp.json` committed with only portable entries (or empty if both are machine-specific). Verify both servers still load.
7. `docs/getting-started.md` — **relabel each of Skills / Agents / Hooks / Docs tables as starter subsets** with a *"See `docs/indexes/*.md` for the full list"* link. Direction (a) confirmed. ~20-30 lines touched. Coordinate with pattern-finder outcome in `.claude/agents/` queue.
8. `docs/indexes/DOCS.md` — **content-level rewrite**: (a) normalize column name to `Description`, (b) fix tautological one-liners (e.g., `relevant-philosophy-reducing_entropy`), (c) optional: add cross-references / Quick-Reference indicator. ~15-line edit.

**Resolved during review (pending execution — moderate scope / needs investigation first):**

9. `docs/indexes/evaluations.json` — **split by resource group**. Diagnostic first: read full schema, check `cli/eval/query.sh` for type-indexing, decide split strategy (per-type files + shared rubric file vs per-type files with duplicated rubric). Then migrate + update `/evaluate-*` skills to write to their specific file. Aligns with `docs/indexes/{SKILLS,AGENTS,HOOKS,DOCS}.md` partition-by-type.

**Coordinated with other audit directories:**

10. `CLAUDE.md` line 75 codebase-explorer path — fix when `.claude/agents/` queue item 6 lands (path migration to `output/claude-toolkit/codebase/{version}/`).
11. `README.md` agent-examples line — if `.claude/agents/` queue items 8-9 deprecate pattern-finder, update the example string here.
12. `docs/indexes/AGENTS.md` — covered by `.claude/agents/` queue items 6, 7, 12. No independent action.
13. **Index-layer normalization pass** — natural stage-5 polish item. README counts, column consistency, tautological descriptions, cross-references, evaluations.json split. One coordinated pass beats one-off drift fixes.

**Coordinated with claude-sessions (satellite cross-repo):**

14. **`.claude/scripts/cron/backup-lessons-db.sh` moves to claude-sessions.** Same pattern as 2.60.4 (`backup-transcripts.sh` relocation). Lessons runtime schema is owned by claude-sessions per v3 canon, so the backup cron belongs there. After the move, `.claude/scripts/cron/` is empty → remove the cron.log `.gitignore` line (folds into queue item 5) and the directory itself. User's crontab needs repointing, same as 2.60.4.

**Deferred (won't fix as part of v3):**

15. `CHANGELOG.md` — append-only, 2258 lines. Recent entries (~10 releases) clean; walking older history for orchestration-era framing isn't worth it.
16. `dist-output/` — gitignored artifact, no action.
17. `tests/` — separate audit if/when needed.
