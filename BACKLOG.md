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

- **[TESTS]** Group runners into subdirs once they warrant splitting (`tests-rethink-suite-phase3`)
    - **scope**: `tests`
    - **notes**: v2.57.1 gave hooks the per-file + parallel pattern; v2.58.0 added the unified top-level `tests/run-all.sh` (all bash suites + pytest, parallel, single summary). Remaining residual: if any top-level suite grows large enough to warrant subdir grouping (`tests/cli/`, `tests/raiz/`, `tests/validate/`, `tests/lessons/`), apply the hook pattern — shared setup in a `lib/*-test-setup.sh`, per-file test-*.sh, dispatched by the existing `run-all.sh` (which already discovers top-level `test-*.sh`; grouped subdirs would need a dedicated runner like `run-hook-tests.sh`). Not urgent — current single-file suites are fine. Separate residual: align `-q`/`-v` semantics inside `lib/test-helpers.sh` assertion helpers (runner already captures child stdout regardless, so low-value).

## P3 - Low

- **[TESTS]** Remove TSV `hook-timing.log` writes from `hook-utils.sh` (`drop-hook-timing-tsv`)
    - **scope**: `tests, hooks`
    - **notes**: Follow-up from the test-hooks split. The TSV log has zero programmatic consumers — `hooks.db` is the only consumer used by tooling, and the test suite no longer reads the TSV at all (assertions removed in the split). To close the loop: drop the append-only TSV writes from `.claude/hooks/lib/hook-utils.sh` (lines 18, 180, 335), remove the `HOOK_LOG_FILE` default, update `docs/indexes/HOOKS.md` line 30 and `.claude/docs/relevant-toolkit-lessons.md` line 168. Human-debugging fallback: tail `hooks.db` via `sqlite3`. Kept out of the restructure PR to limit scope.

- **[SKILLS]** Skill token density audit — prune structural overhead across distributed skills (`skill-token-density`)
    - **scope**: `skills`
    - **notes**: Skills ship to all downstream projects — their token cost is per-invocation across every project that uses them. 33 skills total 38.8K words (avg 1,176/skill). The evaluate-* family is heaviest (5 skills, avg 1,736 words — calibration tables, example evaluations). 15–25% of most skills is structural overhead (anti-patterns, edge cases, "See Also") that doesn't directly drive behavior. Separate concern from agent prompt trim — this is about cumulative token spend, not context exhaustion. Waiting on usage data from claude-sessions to prioritize which skills to prune first.
    - **analysis**: `output/claude-toolkit/analysis/20260331_1000__analyze-idea__information-density-loadable-resources.md`

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability.
    - **design**: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`
    - **drafts**: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count. Analysis of surfacing effectiveness to come from claude-sessions side. When reworking the surfacing hook, evaluate folding it into `grouped-read-guard` (and/or a future `grouped-bash-guard` merge) — it currently averages 106ms with ~30-40ms of that being bash+jq startup. Constraints: async-injection contract, 5s timeout, Bash|Read|Write|Edit matcher (wider than grouped-read).

- **[AGENTS]** Explore resource-aware model routing for agent spawning (`agent-model-routing`)
    - **scope**: `agents, skills`
    - **notes**: Currently agents hardcode `model: "opus"` or `model: "sonnet"`. Some tasks (simple evaluations, pattern searches, file lookups) could route to Haiku for cost/speed without quality loss. Explore: (1) which agents/tasks are candidates for cheaper models, (2) whether this should be a convention in create-agent or a runtime decision by the spawning skill, (3) what the actual cost/quality tradeoff looks like in practice. Start with a discussion pass, not implementation.

- **[AGENTS]** Add structured reasoning activation to select agents (`agent-reasoning-activation`)
    - **scope**: `agents`
    - **notes**: Some agents would benefit from explicit reasoning technique activation (CoT, hypothesis-evidence patterns, structured decomposition). `code-debugger` already does this organically with its hypothesis-elimination approach. Audit other agents — candidates: `code-reviewer` (risk assessment reasoning), `goal-verifier` (backward verification logic), `proposal-reviewer` (audience perspective reasoning). Light touch — add reasoning prompts where they'd improve output, not a framework overhaul.

## P99 - Nice to Have

- **[SKILLS]** Add interactive option selection to skills that ask questions (`skill-interactive-options`)
    - **scope**: `skills`
    - **notes**: AskUserQuestion supports single-select, multi-select, and preview panes — but most skills default to open-ended questions. Audit skills that use AskUserQuestion (brainstorm-idea may already use options organically) and convert categorical decision points to structured option selection where it fits. Keep free-text for creative/descriptive input.

