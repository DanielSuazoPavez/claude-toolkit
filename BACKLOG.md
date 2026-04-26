# Project Backlog

## Current Goal

**v3 — Resource workshop reframe complete.** All 5 stages done: identity rewrite, exhaustive code/structure audit, resource revisit (4.7 clarity pass), setup-toolkit health-check, and polish scoping. The tasks below at P2 and P3 are the direct output of the v3 audit — concrete fixes and follow-ups surfaced during the stage-2 skills walk and consolidated in `planning/v3-audit/stage2-decisions.md`. Design: `output/claude-toolkit/design/20260420_2007__brainstorm-idea__claude-toolkit-v3.md`. Distribution tailoring and lessons-ecosystem data analysis are explicitly post-v3.

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

## P1 - High

- **[HOOKS]** SessionStart output exceeds inline threshold and gets persisted, defeating mandatory-load contract (`session-start-output-too-large`)
    - **scope**: `hooks`
    - **notes**: Observed 2026-04-25: `session-start.sh` produced 10.4KB of stdout (2 essential docs + git context + 7 key lessons + 5 recent + 5 branch lessons + mandatory acknowledgment line). The harness exceeded its inline cap, persisted full output to `tool-results/hook-*.txt`, and only surfaced a ~2KB preview to the model. Net effect: the "MANDATORY: read essential docs at session start" + "acknowledge N docs / N lessons" contract silently failed — model started the session without the conventions or lessons in context, and without realizing the acknowledgment instruction (at the tail) was even present. User had to ask "no essential docs read?" to surface it. Options: (a) shrink default payload — drop full doc bodies, inject only Quick Reference sections (§1) plus paths, let model Read on demand; (b) split into multiple smaller hook outputs (essentials in SessionStart, lessons via a separate UserPromptSubmit-time injection); (c) move lesson lists behind a one-line nudge ("15 lessons available — run `claude-toolkit lessons recent`") instead of inlining them; (d) detect the persisted-output case in the hook itself and emit a compact fallback. Lean: (a)+(c) — Quick References are the load-bearing part; full bodies and lesson text can be lazily fetched. Validate inline-cap threshold empirically (somewhere under 10KB; preview was ~2KB).
    - **depends on**: none

## P2 - Medium

- **[HOOKS]** Stop surfacing Key/Recent lessons at session-start; gate branch lessons on protected branches (`session-start-stop-surfacing-lessons`)
    - **scope**: `hooks`
    - **notes**: Branch 1 of the "stop surfacing lessons at session-start" design. Drop Key + Recent lesson blocks from `.claude/hooks/session-start.sh`; keep branch lessons but skip when current branch matches `PROTECTED_BRANCHES` (existing convention from `git-safety.sh`). Drop the "N lessons noted" acknowledgment suffix. Keep `/manage-lessons` nudge and migration warning unchanged. Update `.claude/docs/relevant-toolkit-lessons.md` to reframe Key tier as a holding/staging state for crystallization (truly always-relevant rules belong in `.claude/docs/essential-*.md`, not a DB row). Update session-start hook tests. Patch version bump; raiz sidecar with `skip: true` (raiz consumers don't have lessons enabled). Quiet shift for satellite consumers (claude-sessions et al.) on next sync — no announcement. PreToolUse `surface-lessons.sh` is untouched. Adjacent to P1 `session-start-output-too-large` — this change reduces the payload meaningfully. Design: `output/claude-toolkit/design/20260426_0930__design__stop-surfacing-lessons-at-session-start.md`.
    - **depends on**: none

- **[SKILLS]** Reframe Key tier as crystallization candidates in `/learn` and `/manage-lessons` (`lessons-key-tier-crystallization`)
    - **scope**: `skills`
    - **notes**: Branch 2 of the "stop surfacing lessons at session-start" design. Update `/learn` and `/manage-lessons` skill prompts so promotion to Key tier nudges: "Key is a holding state — consider crystallizing into `.claude/docs/essential-*.md` or fixing the underlying problem the lesson points at." Includes a one-time review pass: walk current Key lessons and decide doc / fix / demote for each. Schema unchanged (Key tier survives as a holding state). Design: `output/claude-toolkit/design/20260426_0930__design__stop-surfacing-lessons-at-session-start.md`.
    - **depends on**: `session-start-stop-surfacing-lessons`

- **[TOOLKIT]** Evaluate independence of lessons ecosystem from analytics ecosystem (`lessons-analytics-independence`)
    - **scope**: `toolkit`
    - **notes**: Surfaced 2026-04-26 during the projects-text-id alignment (v2.68.2). The lessons CLI and hooks now defer to `~/.claude/sessions.db` for canonical project_id resolution — a hard cross-ecosystem dependency: `_detect_project()` in `cli/lessons/db.py` errors when sessions.db exists but the encoded dir isn't in `project_paths`, and `_resolve_project_id` in `.claude/hooks/lib/hook-utils.sh` warns + leaves PROJECT empty in the same case. This was the right call to prevent name drift, but it raises a broader question: should the lessons ecosystem (capture + surface + manage rules across projects) work without the analytics ecosystem (sessions.db, hooks.db, project_paths, the indexer)? Today the lessons DB schema is owned by claude-sessions (`schemas/lessons.yaml`), the projects dimension uses claude-sessions' resolution chain (override / git_remote / regex_fallback), and the basename fallback only fires when sessions.db is *entirely absent*. Standalone-toolkit users (no claude-sessions installed) work today; partial-install users (sessions.db present but stale or empty) hit the strict error. Scope of evaluation: (1) catalog every cross-ecosystem coupling — schema ownership, projects table, FK directions, env var conventions (`CLAUDE_ANALYTICS_*`), backup-script ownership (already a P3 item: `move-backup-lessons-to-claude-sessions`); (2) identify which couplings are essential (data correctness — name drift) vs incidental (operational — backup script lives in toolkit but DB is sessions-owned); (3) decide whether lessons should ship a self-contained mode (own its projects dimension, no sessions.db dependency) or whether the current "claude-sessions is required when present" stance is the desired end state. Inputs: the projects-text-id design context (this CHANGELOG 2.68.2), the `move-backup-lessons-to-claude-sessions` P3 task (related question of where utilities live), `.claude/docs/relevant-toolkit-lessons.md` (current ecosystem reference). Output: a brainstorm/analysis doc in `output/claude-toolkit/`, possibly leading to a roadmap of either "decouple" or "formalize the dependency" tasks.
    - **depends on**: none

## P3 - Low

- **[HOOKS]** Per-project customization of detection registry (`hooks-detection-registry-per-project`)
    - **scope**: `hooks`
    - **notes**: Follow-up to `hooks-detection-target-convention`. Once the shared detection registry (`detection-registry.json` + JSON Schema + jq loader) is in place and its schema has stabilized, add a layered resolution path so downstream projects can extend or override the toolkit defaults without forking the synced file. Likely shape: project-local `detection-registry.local.json` (gitignored or committed per project preference) merged on top of the synced toolkit registry at hook-load time. Open questions to resolve at design time: (1) merge strategy — replace-by-id, append-only, or deep-merge per field; (2) whether projects can *disable* a toolkit-shipped entry (e.g. `{"id": "github-pat", "disabled": true}` override) or only add new ones; (3) whether the local file is project-private or syncs out via `claude-toolkit send` for cross-project sharing; (4) precedence rules when both files define the same `id` with different `kind`/`target`. Defer until v1 ships and we have real-world signal on which downstream projects need custom patterns (likely: aws-toolkit for AWS-specific shapes, schema-smith for DB-specific shapes). Design context: `output/claude-toolkit/brainstorm/20260425_1349__brainstorm-feature__hooks-detection-target-convention.md`.
    - **depends on**: `hooks-detection-target-convention`

- **[HOOKS]** Fold `surface-lessons.sh` into `grouped-bash-guard.sh` (`surface-lessons-fold`)
    - **scope**: `hooks`
    - **notes**: `surface-lessons.sh` currently averages ~106ms with ~30-40ms of that being bash+jq startup overhead. Fold the Bash branch into `grouped-bash-guard.sh` to skip a second process spawn; keep Read/Write/Edit path separate or extend `grouped-read-guard.sh` to cover Write|Edit. Expected ~40ms avg savings. Constraints: async-injection contract (PreToolUse additionalContext), 5s timeout, current matcher is `Bash|Read|Write|Edit` (wider than grouped-read's `Read`). P2 in `output/claude-toolkit/analysis/20260423_2309__analyze-idea__improve-lessons-lifecycle.md`; deferred to P3 now that the relevance work (v2.63.5–v2.63.7) is shipped and the noise problem is handled — this is pure perf. Re-measure avg latency first; the 106ms baseline predates dedup + 2-hit threshold and may already be lower.
    - **depends on**: none (v2.63.5–v2.63.7 shipped)

- **[HOOKS]** Remove ecosystems opt-in session-start nudge (`remove-ecosystems-opt-in-nudge`)
    - **scope**: `hooks`
    - **notes**: After `ecosystems-opt-in` ships, session-start shows a one-time nudge to projects that predate the new schema (no `CLAUDE_TOOLKIT_LESSONS` / `CLAUDE_TOOLKIT_TRACEABILITY` env keys in settings.json). The nudge is self-extinguishing per-project (setup-toolkit writes the keys → nudge stops firing), but the code itself should be deleted once all user projects have been updated. Triggered manually rather than version-based because toolkit ships faster than the user reaches each project. Signal to remove: user says "remove the opt-in nudge" or equivalent. Delete the relevant section from `.claude/hooks/session-start.sh` and any related tests.
    - **depends on**: `ecosystems-opt-in`

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Reference + satellite ready; user-postponed (no dependency blockers). Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability. When skill ships: enforce satellite-contract rule — link out to aws-toolkit docs via CLI convention (see `satellite-cli-docs-convention` task), no duplicated spec in workshop. Design doc: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`. Drafts: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection.

- **[SKILLS]** `review-security` — worthyness diagnostic (`review-security-worthyness`)
    - **scope**: `skills`
    - **notes**: Skill has never been invoked in the wild (to user's knowledge). Run invocation-frequency check (same approach as pattern-finder agents diagnostic). Based on data: (a) Keep — content already solid; (b) Sharpen — broaden description triggers and/or add surfacing-hook path; (c) Deprecate — CC's built-in /security-review may cover enough of the surface. Do alongside pattern-finder diagnostic for consistency.

- **[HOOKS]** `surface-docs.sh` hook — context-aware doc surfacing (`surface-docs-hook`)
    - **scope**: `hooks`
    - **notes**: New hook matching tool context against `relevant-*` doc Quick References and injecting a one-liner suggestion when a relevant doc hasn't been loaded. Same deterministic algorithm as `surface-lessons.sh` — intra-session dedup (v2.63.6) + 2+ keyword-hit threshold (v2.63.7). Validate by observing surface-lessons behavior for a few weeks before replicating the pattern. Coordinates with `.claude/hooks/` queue item 5.


- **[SCRIPTS]** Move `backup-lessons-db.sh` to claude-sessions (`move-backup-lessons-to-claude-sessions`)
    - **scope**: `scripts`
    - **notes**: `.claude/scripts/cron/backup-lessons-db.sh` backs up a DB whose schema is owned by claude-sessions. Flagged in `planning/v3-audit/claude-docs.md:101` as arguably belonging there. Deferred from 2.62.0 (the env-var centralization touched it but left it in place). Coordinated move: (1) drop script into claude-sessions with the same path or a parallel `scripts/cron/` location, (2) update `.claude/docs/relevant-toolkit-lessons.md:205-209` to point readers at the new location, (3) delete from toolkit, (4) add changelog entry in both repos. Anyone currently running it from a crontab needs a heads-up to update their schedule.

- **[TOOLKIT]** Rename `.claude/docs/` to `.claude/conventions/` (`rename-claude-docs-to-conventions`)
    - **scope**: `toolkit`
    - **notes**: `.claude/docs/` is overloaded — name suggests user-facing docs but contents are agent-loaded conventions/rules (`essential-*`, `relevant-*`, `codebase-explorer/`). Shared name with top-level `docs/` hides the audience split (agent context vs user-facing). "rules" conflates with Claude Code's native rules concept, so `conventions/` is the preferred name. Coordinated rename: (1) move files, (2) update session-start loader and surface-* hooks, (3) update sync paths in CLI + dist profiles (base and raiz MANIFESTs), (4) update CLAUDE.md "Structure" section, (5) update `claude-toolkit docs` command and any skill references (grep for `.claude/docs/`), (6) update downstream satellites' synced copies via next sync. Non-trivial churn — schedule when nothing else is touching those paths.

- **[DOCS]** Index of official Anthropic/Claude Code documentation references (`official-docs-index`)
    - **scope**: `docs`
    - **notes**: Create a single doc (e.g. `.claude/docs/reference-official-docs.md` or `docs/official-references.md`) collecting URLs + short summaries of Anthropic's own Claude Code docs — hooks reference (`code.claude.com/docs/en/hooks`, `/hooks-guide`), sub-agents (`/sub-agents`), skills (`/skills` — note: pitched as "custom commands", not as a first-class developer surface), plugins (`/plugins`), settings (`/settings`), agent SDK (`docs.anthropic.com/en/docs/claude-code/sdk/*`), hook-development SKILL in `anthropics/claude-code` repo (`plugins/plugin-dev/skills/hook-development/SKILL.md`). Purpose: we've been reverse-engineering a lot (the PostToolUse redaction investigation on 2026-04-24 is the canonical example — third-party tutorials misread the contract, only the official reference + empirical probe settled it), and keeping a curated index means future "is this actually supported?" questions start from authoritative sources. Also flag the gaps the toolkit fills — skill authoring beyond the /en/skills "custom commands" framing, agent design beyond the subagent contract, `.claude/docs/` conventions (no official equivalent). Related context: Anthropic's "memories" concept landed after the toolkit's `.claude/memories/` convention, causing a terminology collision — note this and the `rename-claude-docs-to-conventions` task (P3) as part of the same "upstream concepts overlapping with toolkit conventions" theme. Also mention skill-creator (seen in Claude Cowork) as the "overblown create-skill" — full UX with HTML rendering for feedback, A/B testing, multiple rounds — potential reference point when evolving `create-skill`. Not blocking; nice to have for onboarding and for settling future design debates.

## P99 - Nice to Have

- **[SKILLS]** v3 E5 — frontmatter field ordering normalization across skills (`v3-e5-frontmatter-ordering`)
    - **scope**: `skills`
    - **notes**: `build-communication-style` uses non-standard frontmatter order (`name, description, argument-hint, allowed-tools, type`); most skills use `name, type, description, ...`. The A1 sweep resolves `type:` placement but doesn't normalize broader ordering. Could be automated with a small ruff-style linter or a sed pass. Polish, not v3-blocking.

- **[SKILLS]** v3 E3 — `teardown-worktree` artifact-copy scope decision (`v3-e3-teardown-artifact-scope`)
    - **scope**: `skills`
    - **notes**: Currently copies only `output/claude-toolkit/reviews/*` from worktree to parent at teardown. Does not copy `pr-descriptions/`, `design/`, `plans/`, `sessions/`. Decide: (a) deliberate — keep per-worktree ephemera scoped, only review artifacts persist; or (b) broaden to include other `output/claude-toolkit/` subdirs a user is likely to want after teardown. No clear right answer; needs a decision before implementing.

- **[SKILLS]** Add interactive option selection to skills that ask questions (`skill-interactive-options`)
    - **scope**: `skills`
    - **notes**: AskUserQuestion supports single-select, multi-select, and preview panes — but most skills default to open-ended questions. Audit skills that use AskUserQuestion (brainstorm-idea may already use options organically) and convert categorical decision points to structured option selection where it fits. Keep free-text for creative/descriptive input.

- **[AGENTS]** Explore resource-aware model routing for agent spawning (`agent-model-routing`)
    - **scope**: `agents, skills`
    - **notes**: Currently agents hardcode `model: "opus"` or `model: "sonnet"`. Some tasks (simple evaluations, pattern searches, file lookups) could route to Haiku for cost/speed without quality loss. Explore: (1) which agents/tasks are candidates for cheaper models, (2) whether this should be a convention in create-agent or a runtime decision by the spawning skill, (3) what the actual cost/quality tradeoff looks like in practice. Start with a discussion pass, not implementation.

- **[AGENTS]** Add structured reasoning activation to select agents (`agent-reasoning-activation`)
    - **scope**: `agents`
    - **notes**: Some agents would benefit from explicit reasoning technique activation (CoT, hypothesis-evidence patterns, structured decomposition). `code-debugger` already does this organically with its hypothesis-elimination approach. Audit other agents — candidates: `code-reviewer` (risk assessment reasoning), `goal-verifier` (backward verification logic), `proposal-reviewer` (audience perspective reasoning). Light touch — add reasoning prompts where they'd improve output, not a framework overhaul.

