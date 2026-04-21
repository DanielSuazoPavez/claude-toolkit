# Project Backlog

## Current Goal

**v3 — Resource workshop reframe.** claude-toolkit is a resource workshop (canonical place where Claude Code resources are authored, refined, distributed), not an orchestrator. v3 is a deliberate review moment: rewrite self-description, exhaustively audit code/resources for orchestrator-thinking leakage, revisit resources through workshop + Opus 4.7 clarity lens, verify setup-toolkit, polish. Staged (stages 1–5 at P0). Design: `output/claude-toolkit/design/20260420_2007__brainstorm-idea__claude-toolkit-v3.md`. Distribution tailoring and lessons-ecosystem data analysis are explicitly post-v3.

**See also:** `output/claude-toolkit/exploration/BACKLOG.md` — repo exploration queue (pending reviews, theme searches).

## Scope Definitions

| Scope | Description |
|-------|-------------|
| scripts | Standalone utility scripts |
| toolkit | Core toolkit infrastructure (sync, indexes, versioning) |
| skills | User-invocable skills |
| agents | Specialized task agents |
| hooks | Automation hooks |
| tests | Automated testing and validation |

---

## P0 - Critical

- **[TOOLKIT]** v3 Stage 1 — Identity rewrite (`v3-stage-1-identity-rewrite`)
    - **scope**: `toolkit`
    - **notes**: Pure prose work. Rewrite self-description from "orchestrator" to "resource workshop" across: README.md, CLAUDE.md, .claude/docs/relevant-project-identity.md, suggestions-box/CLAUDE.md, docs/ top-level user-facing docs, .claude/memories/ auto-memory, any .claude/docs/relevant-* docs touching project purpose/role. Explicitly NOT touching skills/agents/hooks descriptions (stage 3), dist/CLI code (stage 2), or suggestions-box workflow (stage 2). Design: `output/claude-toolkit/design/20260420_2007__brainstorm-idea__claude-toolkit-v3.md`.

- **[TOOLKIT]** v3 Stage 2 — Code/structure audit (exhaustive) (`v3-stage-2-code-audit`)
    - **scope**: `toolkit`
    - **notes**: Walk every file in the repo asking "does this shape assume orchestration, or is it workshop-shaped?" Output: one findings doc per directory at `planning/v3-audit/{directory}.md` (tracked, new top-level `planning/` folder). Every file listed with a finding tag: Keep / Rewrite / Defer / Investigate. Checklist-style, resumable across sessions. Audit targets: cli/, dist/, .claude/hooks/, .claude/agents/, .claude/skills/, .claude/docs/, suggestions-box/, output/ layout, .github/, top-level files. Decision point after audit: which Rewrite items are v3-scope vs deferred. Don't let distribution tailoring or lessons-ecosystem analysis sneak in.
    - **depends on**: `v3-stage-1-identity-rewrite`

- **[TOOLKIT]** v3 Stage 3 — Resource revisit (4.7 clarity pass) (`v3-stage-3-resource-revisit`)
    - **scope**: `toolkit, skills, agents, hooks`
    - **notes**: Walk skills/agents/hooks/docs through two lenses simultaneously: workshop framing (any identity residue from stage 2) + Opus 4.7's preference for more explicit/clear instructions. Same checklist-per-directory pattern as stage 2. Stage 2 will have already flagged framing issues — stage 3 focuses on clarity/explicitness.
    - **depends on**: `v3-stage-2-code-audit`

- **[TOOLKIT]** v3 Stage 4 — setup-toolkit health-check (`v3-stage-4-setup-toolkit-check`)
    - **scope**: `toolkit, skills`
    - **notes**: Narrow single-skill audit: does setup-toolkit reliably make a project a consumer of the workshop? Identity is now settled, so the question is focused. Likely produces a short findings doc, possibly small fixes. Not a known problem — this is verification.
    - **depends on**: `v3-stage-3-resource-revisit`

- **[TOOLKIT]** v3 Stage 5 — Polish (`v3-stage-5-polish`)
    - **scope**: `toolkit`
    - **notes**: Sweep accumulated small stuff from stages 2–4 tagged "Defer — but worth doing" or "Investigate." Natural end-of-v3 cleanup. Also a home for cruft noticed during the work.
    - **depends on**: `v3-stage-4-setup-toolkit-check`

## P1 - High

## P2 - Medium

## P3 - Low

- **[HOOKS]** Remove ecosystems opt-in session-start nudge (`remove-ecosystems-opt-in-nudge`)
    - **scope**: `hooks`
    - **notes**: After `ecosystems-opt-in` ships, session-start shows a one-time nudge to projects that predate the new schema (no `CLAUDE_TOOLKIT_LESSONS` / `CLAUDE_TOOLKIT_TRACEABILITY` env keys in settings.json). The nudge is self-extinguishing per-project (setup-toolkit writes the keys → nudge stops firing), but the code itself should be deleted once all user projects have been updated. Triggered manually rather than version-based because toolkit ships faster than the user reaches each project. Signal to remove: user says "remove the opt-in nudge" or equivalent. Delete the relevant section from `.claude/hooks/session-start.sh` and any related tests.
    - **depends on**: `ecosystems-opt-in`

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Reference + satellite ready; user-postponed (no dependency blockers). Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability. When skill ships: enforce satellite-contract rule — link out to aws-toolkit docs via CLI convention (see `satellite-cli-docs-convention` task), no duplicated spec in workshop. Design doc: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`. Drafts: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection.

- **[SKILLS]** `manage-lessons` — route all CLI lifecycle ops through `claude-toolkit lessons` (`manage-lessons-cli-routing`)
    - **scope**: `skills`
    - **notes**: Skill currently calls sqlite3 directly for promote/deactivate/delete (lines 94-106). Direction: route everything through `claude-toolkit lessons` CLI; drop `Bash(sqlite3:*)` from `allowed-tools`. Prerequisites: (1) check CLI for existing promote/deactivate/delete subcommands, (2) add any missing ones, (3) rewrite skill to use CLI only. Coordinates with hooks-audit queue item 2 (LESSONS_DB env var) — once CLI honors the env var, skill inherits behavior automatically.

- **[SKILLS]** `review-security` — worthyness diagnostic (`review-security-worthyness`)
    - **scope**: `skills`
    - **notes**: Skill has never been invoked in the wild (to user's knowledge). Run invocation-frequency check (same approach as pattern-finder agents diagnostic). Based on data: (a) Keep — content already solid; (b) Sharpen — broaden description triggers and/or add surfacing-hook path; (c) Deprecate — CC's built-in /security-review may cover enough of the surface. Do alongside pattern-finder diagnostic for consistency.

- **[HOOKS]** `surface-docs.sh` hook — context-aware doc surfacing (`surface-docs-hook`)
    - **scope**: `hooks`
    - **notes**: New hook matching tool context against `relevant-*` doc Quick References and injecting a one-liner suggestion when a relevant doc hasn't been loaded. Same deterministic algorithm as `surface-lessons.sh` (dedup window + minimum match specificity). **Gated on `improve-lessons-lifecycle` being validated first** — only build after the surface-lessons rework proves the algorithm works reliably. Coordinates with `.claude/hooks/` queue item 5.
    - **depends on**: `improve-lessons-lifecycle`

- **[TOOLKIT]** Satellite CLI docs convention — how workshop skills reference satellite contracts (`satellite-cli-docs-convention`)
    - **scope**: `toolkit`
    - **notes**: Workshop skills currently duplicate satellite input specs (e.g., `design-db/resources/schema-smith-input-spec.md` duplicates schema-smith's contract). Direction: satellites expose their input spec via CLI flag (e.g., `schema-smith --print-input-spec`); workshop skills reference the CLI command at runtime instead of carrying a copy. Tasks: (1) write `relevant-toolkit-satellite-contracts.md` convention doc, (2) make the convention discoverable via the CLI, (3) coordinate schema-smith removal from workshop after schema-smith satellite implements the flag. Same rule applies to aws-toolkit when `/design-aws` ships.

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count. Analysis of surfacing effectiveness to come from claude-sessions side. When reworking the surfacing hook, evaluate folding it into `grouped-read-guard` (and/or a future `grouped-bash-guard` merge) — it currently averages 106ms with ~30-40ms of that being bash+jq startup. Constraints: async-injection contract, 5s timeout, Bash|Read|Write|Edit matcher (wider than grouped-read).

## P99 - Nice to Have

- **[SKILLS]** Add interactive option selection to skills that ask questions (`skill-interactive-options`)
    - **scope**: `skills`
    - **notes**: AskUserQuestion supports single-select, multi-select, and preview panes — but most skills default to open-ended questions. Audit skills that use AskUserQuestion (brainstorm-idea may already use options organically) and convert categorical decision points to structured option selection where it fits. Keep free-text for creative/descriptive input.

- **[AGENTS]** Explore resource-aware model routing for agent spawning (`agent-model-routing`)
    - **scope**: `agents, skills`
    - **notes**: Currently agents hardcode `model: "opus"` or `model: "sonnet"`. Some tasks (simple evaluations, pattern searches, file lookups) could route to Haiku for cost/speed without quality loss. Explore: (1) which agents/tasks are candidates for cheaper models, (2) whether this should be a convention in create-agent or a runtime decision by the spawning skill, (3) what the actual cost/quality tradeoff looks like in practice. Start with a discussion pass, not implementation.

- **[AGENTS]** Add structured reasoning activation to select agents (`agent-reasoning-activation`)
    - **scope**: `agents`
    - **notes**: Some agents would benefit from explicit reasoning technique activation (CoT, hypothesis-evidence patterns, structured decomposition). `code-debugger` already does this organically with its hypothesis-elimination approach. Audit other agents — candidates: `code-reviewer` (risk assessment reasoning), `goal-verifier` (backward verification logic), `proposal-reviewer` (audience perspective reasoning). Light touch — add reasoning prompts where they'd improve output, not a framework overhaul.

