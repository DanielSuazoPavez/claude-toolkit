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

- **[HOOKS]** Capture `SessionStart` `source` in `hook_logs` for sub-session boundary detection (`sessionstart-source-capture`)
    - **scope**: `hooks`
    - **notes**: Claude Code fires `SessionStart` with stdin `source` field = `startup | resume | clear | compact`. `hook-utils.sh` currently extracts `session_id` but ignores `source`. Single-file change in `lib/hook-utils.sh` to capture it, plus a nullable `source TEXT` migration on `hook_logs`. Unblocks claude-sessions' P1 `session-analytics-work-units` — without `source`, there's no authoritative marker for `/clear`, auto-compact, or plan-handoff boundaries within a single `session_id`. `usage_snapshots` confirmed not useful for boundary detection (no token-drop signature observed across 172 snapshots / 5 sessions).
    - **design**: `output/claude-toolkit/design/20260416_1730__design__sub-session-boundaries.md` (originated in claude-sessions)
    - **validation needed**: confirm `SessionStart` re-fires for `ExitPlanMode` clear-and-handoff path

## P2 - Medium

- **[HOOKS]** Refactor hooks to match/check architecture + grouped dispatcher Phase 2 (`match-check-hook-architecture`)
    - **scope**: `hooks`
    - **notes**: Split every Bash-touching hook into `match_<name>` (cheap pure predicate) and `check_<name>` (guard logic). Dispatcher (`grouped-bash-guard.sh`) sources hooks as libraries, parses stdin once, runs matches, skips check bodies when match is false. Hooks stay standalone-capable via a thin `main()` wrapper — single source of truth, no dual registration. Folds `git-safety` (Bash branch), `secrets-guard` (Bash branch), `block-config-edits` (Bash branch) into the dispatcher. Adds `not_applicable` outcome to `hooks.db` to distinguish "didn't apply" from "skipped after predecessor blocked". Gains work-avoidance for common no-match Bash calls on top of the amortization already won in v2.52.0.
    - **design**: `output/claude-toolkit/design/20260416_1830__design-doc__match-check-hook-architecture.md`
    - **migration**: prototype with `git-safety` first (decision gate on shape), then fold into dispatcher, then convert remaining hooks. Each step independently testable and reversible.

- **[SKILLS]** Skill token density audit — prune structural overhead across distributed skills (`skill-token-density`)
    - **scope**: `skills`
    - **notes**: Skills ship to all downstream projects — their token cost is per-invocation across every project that uses them. 33 skills total 38.8K words (avg 1,176/skill). The evaluate-* family is heaviest (5 skills, avg 1,736 words — calibration tables, example evaluations). 15–25% of most skills is structural overhead (anti-patterns, edge cases, "See Also") that doesn't directly drive behavior. Separate concern from agent prompt trim — this is about cumulative token spend, not context exhaustion.
    - **analysis**: `output/claude-toolkit/analysis/20260331_1000__analyze-idea__information-density-loadable-resources.md`

## P3 - Low

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability.
    - **design**: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`
    - **drafts**: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count. Analysis of surfacing effectiveness to come from claude-sessions side.

- **[AGENTS]** Explore resource-aware model routing for agent spawning (`agent-model-routing`)
    - **scope**: `agents, skills`
    - **notes**: Currently agents hardcode `model: "opus"` or `model: "sonnet"`. Some tasks (simple evaluations, pattern searches, file lookups) could route to Haiku for cost/speed without quality loss. Explore: (1) which agents/tasks are candidates for cheaper models, (2) whether this should be a convention in create-agent or a runtime decision by the spawning skill, (3) what the actual cost/quality tradeoff looks like in practice. Start with a discussion pass, not implementation.

- **[AGENTS]** Validate v2.45.0 reviewer agent protocols in real usage (`validate-reviewer-protocols`)
    - **status**: `ongoing`
    - **scope**: `agents`
    - **notes**: v2.45.0 changed investigation protocols for code-reviewer, goal-verifier, and implementation-checker (incremental writes, risk categorization, magnitude-aware depth). Ship-and-observe: on the next real branch, confirm each agent writes its skeleton early and completes the report. If any agent fails to produce a report or quality regresses, rollback that agent's file to v2.44.2. Remove this task after first successful run of all three.

- **[SKILLS]** Re-evaluate review-plan subagent changes from v2.47.0 (`review-plan-subagent-eval`)
    - **status**: `ongoing`
    - **scope**: `skills`
    - **notes**: v2.47.0 introduced subagent delegation for `/review-plan`. After real usage across a few branches, evaluate: (1) Is the context brief adequate — does the subagent miss verbal constraints? (2) Is the summary-only relay sufficient or do users need more detail? (3) Does the `inline` escape hatch get used, and why? (4) Token savings vs quality tradeoff. Remove this task after 3+ real reviews confirm the pattern works.

- **[AGENTS]** Add structured reasoning activation to select agents (`agent-reasoning-activation`)
    - **scope**: `agents`
    - **notes**: Some agents would benefit from explicit reasoning technique activation (CoT, hypothesis-evidence patterns, structured decomposition). `code-debugger` already does this organically with its hypothesis-elimination approach. Audit other agents — candidates: `code-reviewer` (risk assessment reasoning), `goal-verifier` (backward verification logic), `proposal-reviewer` (audience perspective reasoning). Light touch — add reasoning prompts where they'd improve output, not a framework overhaul.

## P99 - Nice to Have

- **[SKILLS]** Add interactive option selection to skills that ask questions (`skill-interactive-options`)
    - **scope**: `skills`
    - **notes**: AskUserQuestion supports single-select, multi-select, and preview panes — but most skills default to open-ended questions. Audit skills that use AskUserQuestion (brainstorm-idea may already use options organically) and convert categorical decision points to structured option selection where it fits. Keep free-text for creative/descriptive input.

