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

- **[SKILLS]** Evaluate consolidating evaluate-* skills (`evaluate-consolidate-evaluate-skills`)
    - **scope**: `skills`
    - **notes**: evaluate-skill, evaluate-agent, evaluate-hook, evaluate-memory are structurally similar (rubric + scoring). evaluate-batch already dispatches by type. However, each resource type has its own rubric nuances — generalizing may dilute quality. Investigate: how much is shared scaffolding vs type-specific expert knowledge? Would a single skill with embedded type references lose scoring precision? Potential savings ~600-800 lines, but only if quality holds.

- **[SKILLS]** Evaluate consolidating create-* skills (`evaluate-consolidate-create-skills`)
    - **scope**: `skills`
    - **notes**: create-skill, create-agent, create-memory, create-hook follow a similar pattern (template + conventions). But each has type-specific guidance (e.g., agent tool selection, hook trigger patterns, memory category rules). Investigate: can a single parameterized skill preserve these nuances, or does merging flatten important distinctions? Potential savings ~500-600 lines, but only worth it if output quality doesn't regress.

- **[SKILLS]** Audit design-* skills for knowledge density (`audit-design-skills`)
    - **scope**: `skills`
    - **notes**: design-tests (400 lines), design-docker (331), design-qa (209), design-db (180), design-diagram (156). These are reference skills by design — invoked occasionally, not daily. Low usage alone isn't a signal for removal. Question: how much is expert knowledge beyond Claude's training vs patterns Claude already knows? Review each for lines that wouldn't be generated without the skill. Track usage over time to inform future decisions.

- **[TOOLKIT]** Evaluate unifying CLI under `bin/claude-toolkit` (`evaluate-unify-cli-entrypoint`)
    - **scope**: `scripts, toolkit`
    - **notes**: With sessions extracted, `scripts/` only contains `lessons/` and `shared/`. Investigate consolidating remaining CLI into the existing `bin/claude-toolkit` bash entry point — add subcommands like `claude-toolkit lessons`, `claude-toolkit validate`. Move `scripts/lessons/` and `scripts/shared/` into a `cli/` directory at project root. The bash CLI stays bash — it would dispatch to Python (lessons) or bash (validate, backlog) under the hood. Evaluate: does single entry point simplify usage enough to justify the rewiring, or is the current split (bin/claude-toolkit for sync/send, ct-lessons for lessons, make for validate) working fine?

- **[HOOKS]** Hook router — single dispatch process per trigger instead of N separate hook spawns (`hook-router`)
    - **scope**: `hooks`
    - **notes**: Currently a Bash tool call spawns 7 separate hook processes, each parsing stdin independently. A router script would read stdin once, dispatch to relevant checks based on `$CLAUDE_TOOL_NAME`, and aggregate output. Benefits: cleaner resource_usage analytics in session-index.db (1 entry vs 7), fewer process spawns, defined execution order (blockers → suggestions → context injection), short-circuit on block. Tradeoffs: we own execution order and output aggregation (currently Claude Code handles both), per-project exclusion needs a skip mechanism inside the router. Prototype on a branch to validate.
    - **prior art**: `trailofbits/claude-code-config` uses inline one-liners in settings.json for simple guards instead of separate scripts. `disler/claude-code-hooks-mastery` uses a single `pre_tool_use.py` combining rm-rf + .env blocking with internal tool-type dispatch. See exploration summaries in `output/claude-toolkit/exploration/`.

## P3 - Low

- **[TOOLKIT]** Output styles concept — consider switchable response formatting modes (`output-styles-concept`)
    - **scope**: `toolkit`
    - **notes**: Inspired by `disler/claude-code-hooks-mastery`'s `.claude/output-styles/` directory. Named formatting modes (ultra-concise, table-based, genui/HTML output, etc.) activated per-session. Different from our communication style memory — these are structural formatting preferences, not personality. Relates to `schemas/` folder direction. Explore whether this fits as a convention or is over-engineering.

- **[AGENTS/SKILLS]** AWS toolkit — agents and skills for AWS workflows (`aws-toolkit`)
    - **scope**: `agents, skills`
    - **repo**: `~/projects/personal/aws-toolkit`
    - **notes**: Base model struggles with real-world IAM policies and service-specific config. Work happens in the aws-toolkit repo, not here — this backlog entry tracks the initiative, not local changes. Three sub-items:
        - `aws-architect` agent: Infra design, cost/tradeoff analysis, online cost lookup
        - `aws-security-auditor` agent: Security review, least-privilege IAM validation
        - `aws-deploy` skill: Service-specific best practices (Lambda, RDS, OpenSearch)
    - **drafts**: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools (Parliament, Policy Sentry, IAM Policy Autopilot) and cost estimation tools (Infracost, AWS Pricing API)

## P99 - Nice to Have

- **[HOOKS]** `last_assistant_message` in Stop hooks — output-level hooks for post-response automation (`hook-stop-last-message`)
    - **scope**: `hooks`
    - **notes**: HOOKS_API updated with `last_assistant_message` field and `prompt`/`agent` hook types. Concrete use case: lesson-detection Stop hook (regex-based detection proved unreliable — consider `prompt`-type hook instead).

- **[SKILLS]** Adopt `${CLAUDE_SKILL_DIR}` — use in skills that reference bundled resources (`skill-claude-skill-dir`)
    - **scope**: `skills`

- **[TOOLKIT]** Native `autoMemoryDirectory` setting — unclear if it actually changes write behavior vs just `/memory` UI folder (`toolkit-auto-memory-dir`)
    - **scope**: `toolkit`
    - **notes**: Tested 2026-03-20. Setting `autoMemoryDirectory` in user settings only affects the "Open auto-memory folder" option in `/memory` UI — didn't observe it redirecting where Claude writes auto-memories. Needs more investigation if Claude Code documents this further.