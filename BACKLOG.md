# Project Backlog

## Current Goal

Post-v2 — improve resources through real usage, expand into AWS and security domains.

**See also:** `.claude/output/reviews/exploration/BACKLOG.md` — repo exploration queue (pending reviews, theme searches).

## Scope Definitions

| Scope | Description |
|-------|-------------|
| toolkit | Core toolkit infrastructure (sync, indexes, versioning) |
| skills | User-invocable skills |
| agents | Specialized task agents |
| hooks | Automation hooks |
| tests | Automated testing and validation |

---

## P0 - Critical

## P1 - High

- **[SKILLS]** `allowed-tools` audit — add allowed-tools frontmatter to all 33 skills (only 2 have it)
    - **scope**: `skills`

- **[SKILLS]** Adopt `${CLAUDE_SKILL_DIR}` — use in skills that reference bundled resources
    - **scope**: `skills`

- **[HOOKS]** `PermissionRequest` hooks — replace PreToolUse auto-approve patterns, reduce hook noise
    - **scope**: `hooks`

- **[TOOLKIT]** Native directory settings — adopt `plansDirectory` (deprecate copy-plan hook) + `autoMemoryDirectory` (project-scoped in `.claude/memories/auto/`, gitignored)
    - **scope**: `toolkit, hooks`

## P2 - Medium

- **[HOOKS]** `prompt`/`agent` hook types — LLM-based judgment in hooks for nuanced decisions
    - **scope**: `hooks`

- **[AGENTS/SKILLS]** AWS toolkit — agents and skills for AWS workflows (`aws-toolkit`)
    - **status**: `in-progress`
    - **scope**: `agents, skills`
    - **repo**: `~/projects/personal/aws-toolkit`
    - **notes**: Base model struggles with real-world IAM policies and service-specific config. Three sub-items:
        - `aws-architect` agent: Infra design, cost/tradeoff analysis, online cost lookup
        - `aws-security-auditor` agent: Security review, least-privilege IAM validation
        - `aws-deploy` skill: Service-specific best practices (Lambda, RDS, OpenSearch)
    - **drafts**: `.claude/output/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools (Parliament, Policy Sentry, IAM Policy Autopilot) and cost estimation tools (Infracost, AWS Pricing API)

## P3 - Low

- **[AGENTS]** Agent frontmatter exploration — `background: true`, `SendMessage` for iterative cycles, `effort` per agent
    - **scope**: `agents`

- **[SKILLS]** `user-invocable: false` — background knowledge skills, add to `create-skill` workflow context
    - **scope**: `skills`

## P99 - Nice to Have

- **[HOOKS]** `last_assistant_message` in Stop hooks — output-level hooks for post-response automation
    - **scope**: `hooks`
