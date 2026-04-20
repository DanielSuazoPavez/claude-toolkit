# Project Backlog

## Current Goal

Post-v2 — improve resources through real usage, expand into AWS and security domains.

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

## P1 - High

## P2 - Medium

## P3 - Low

- **[TOOLKIT]** Define what v3 looks like (`define-v3`)
    - **scope**: `toolkit`
    - **notes**: Behavior changes have been shipping as Minor bumps (2.x → 2.x+1), but the ecosystems opt-in in 2.61.0 is the kind of change that arguably warrants Major. Before the next breaking-ish change, write down: what's the v3 identity, what breaking changes are queued, what's the migration story, and what's the cutline between "bump Minor and nudge" vs "bump Major and gate sync". Surfaced while wrapping up `ecosystems-opt-in`.

- **[HOOKS]** Remove ecosystems opt-in session-start nudge (`remove-ecosystems-opt-in-nudge`)
    - **scope**: `hooks`
    - **notes**: After `ecosystems-opt-in` ships, session-start shows a one-time nudge to projects that predate the new schema (no `CLAUDE_TOOLKIT_LESSONS` / `CLAUDE_TOOLKIT_TRACEABILITY` env keys in settings.json). The nudge is self-extinguishing per-project (setup-toolkit writes the keys → nudge stops firing), but the code itself should be deleted once all user projects have been updated. Triggered manually rather than version-based because toolkit ships faster than the user reaches each project. Signal to remove: user says "remove the opt-in nudge" or equivalent. Delete the relevant section from `.claude/hooks/session-start.sh` and any related tests.
    - **depends on**: `ecosystems-opt-in`

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability. Design doc: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`. Drafts: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection.

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

