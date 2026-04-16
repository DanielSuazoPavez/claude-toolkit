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

- **[HOOKS]** Refactor hooks to match/check architecture + grouped dispatcher Phase 2 (`match-check-hook-architecture`)
    - **scope**: `hooks`
    - **notes**: Split every Bash-touching hook into `match_<name>` (cheap pure predicate) and `check_<name>` (guard logic). Dispatcher (`grouped-bash-guard.sh`) sources hooks as libraries, parses stdin once, runs matches, skips check bodies when match is false. Hooks stay standalone-capable via a thin `main()` wrapper — single source of truth, no dual registration. Folds `git-safety` (Bash branch), `secrets-guard` (Bash branch), `block-config-edits` (Bash branch) into the dispatcher. Adds `not_applicable` outcome to `hooks.db` to distinguish "didn't apply" from "skipped after predecessor blocked". Gains work-avoidance for common no-match Bash calls on top of the amortization already won in v2.52.0.
    - **design**: `output/claude-toolkit/design/20260416_1830__design-doc__match-check-hook-architecture.md`
    - **migration**: prototype with `git-safety` first (decision gate on shape), then fold into dispatcher, then convert remaining hooks. Each step independently testable and reversible.
    - **subtasks**:
        - [x] **A.** Formalize match/check pattern — write `.claude/docs/relevant-toolkit-hooks.md` (Quick Reference, events recap, standalone vs grouped, match/check contract + dual-mode trigger, outcomes incl. `not_applicable`, authoring steps, testing, anti-patterns). Update `hook-utils.sh` header to document `not_applicable` outcome.
        - [x] **B.** Prototype `git-safety` (Bash branch) — convert to `match_git_safety` / `check_git_safety` / `main` with dual-mode trigger. EnterPlanMode stays in `main`. Keep standalone registration. Decision gate on shape before continuing.
        - [x] **C.** Bash dispatcher — teach `grouped-bash-guard.sh` to source hook files and iterate `CHECKS` via match→check. Wire in `git-safety`. Add `not_applicable` logging path. Update `settings.grouped.json.example`.
        - [x] **D1.** Convert `secrets-guard` (Bash branch) to match/check. Read/Grep branches stay standalone.
        - [x] **D2.** Convert `block-config-edits` (Bash branch) to match/check. Write/Edit branches stay standalone.
        - [ ] **D3.** Extract inlined `check_dangerous` / `check_make` / `check_uv` from dispatcher into their own standalone-capable hook files, sourced back in.
        - [ ] **E.** Docs + changelog — finalize `relevant-toolkit-hooks.md` with final hook set, add changelog entry for the architectural shift. Also document the `hook-utils.sh` idempotency guard (added in C) and why it matters — dispatchers source hook-utils then source hooks that also source hook-utils, so the lib must not reset globals on re-source.

- **[SKILLS]** Update `create-hook` and `evaluate-hook` for match/check pattern (`hook-skills-match-check-update`)
    - **scope**: `skills`
    - **notes**: After `match-check-hook-architecture` lands, `create-hook` should scaffold the `match_<name>` / `check_<name>` / `main` shape with the dual-mode trigger by default, and `evaluate-hook` should score against the match cheapness contract, dual-mode capability, and `_BLOCK_REASON` convention. Depends on `.claude/docs/relevant-toolkit-hooks.md` being authored as part of the parent task.
    - **depends on**: `match-check-hook-architecture`

- **[HOOKS]** Grouped Read dispatcher — extend match/check architecture to Read-tool hooks (`grouped-read-guard`)
    - **scope**: `hooks`
    - **notes**: Follow-on to `match-check-hook-architecture`. Build a `grouped-read-guard.sh` dispatcher following the same source-and-iterate pattern. Folds `secrets-guard` (Read/Grep branches) and `suggest-read-json` into one process. `surface-lessons` stays standalone (async-injection, different contract). Lower traffic than Bash so payoff is smaller — defer until match/check pattern is validated in real usage on the Bash side.
    - **depends on**: `match-check-hook-architecture`

- **[SKILLS]** Skill token density audit — prune structural overhead across distributed skills (`skill-token-density`)
    - **scope**: `skills`
    - **notes**: Skills ship to all downstream projects — their token cost is per-invocation across every project that uses them. 33 skills total 38.8K words (avg 1,176/skill). The evaluate-* family is heaviest (5 skills, avg 1,736 words — calibration tables, example evaluations). 15–25% of most skills is structural overhead (anti-patterns, edge cases, "See Also") that doesn't directly drive behavior. Separate concern from agent prompt trim — this is about cumulative token spend, not context exhaustion.
    - **analysis**: `output/claude-toolkit/analysis/20260331_1000__analyze-idea__information-density-loadable-resources.md`

## P3 - Low

- **[TESTS]** DB-related tests should point to a test DB, not `~/.claude/hooks.db` (`tests-isolate-db`)
    - **scope**: `tests`
    - **notes**: `test_session_id_from_stdin` and `test_session_start_source_capture` in `tests/test-hooks.sh` write rows into the user's real `~/.claude/hooks.db`. Rows are marked `is_test=1` but never cleaned up, polluting analytics. Proper fix: make `HOOK_LOG_DB` overridable via env var so tests can point at a temp DB (schema materialization decision pending — copy from real DB, replay migration, or maintain a test fixture).
    - **decision pending**: how to materialize the test DB schema

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

