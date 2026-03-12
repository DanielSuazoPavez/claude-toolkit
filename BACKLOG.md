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

## P1 - High

- **[SKILLS/HOOKS]** Fix lessons ecosystem — `/learn` skill + capture workflow (`lessons-ecosystem`)
    - **status**: `in-progress`
    - **scope**: `skills, hooks, scripts`
    - **branch**: `feature/lessons-ecosystem`
    - **notes**: New data model (schema + tiers), rewritten `/learn`, new `/manage-lessons`, `lessons-query.sh`, updated session-start surfacing with nudge logic.

## P2 - Medium

- **[AGENTS/SKILLS]** AWS toolkit — agents and skills for AWS workflows (`aws-toolkit`)
    - **status**: `blocked`
    - **scope**: `agents, skills`
    - **depends-on**: Separate repo for experimenting with discovered IAM/cost tools
    - **notes**: Base model struggles with real-world IAM policies and service-specific config. Three sub-items:
        - `aws-architect` agent: Infra design, cost/tradeoff analysis, online cost lookup
        - `aws-security-auditor` agent: Security review, least-privilege IAM validation
        - `aws-deploy` skill: Service-specific best practices (Lambda, RDS, OpenSearch)
    - **drafts**: `.claude/output/drafts/aws-toolkit/` — pre-research on IAM validation tools (Parliament, Policy Sentry, IAM Policy Autopilot) and cost estimation tools (Infracost, AWS Pricing API)

- **[SKILLS]** Link `design-db` skill to schema-smith as optional dependency (`skill-design-db-backing-repo`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Wire `design-db` to `schema-smith` (YAML → PostgreSQL DDL/diagrams/SQLAlchemy models). First "skill backed by real project code" pattern. Two options: Python dependency (`uv add --optional`) or CLI invocation. Schema-smith is functional, in cleanup phase. Path: `personal/training/data-engineering/projects/schema-smith`.

- **[TOOLKIT]** Explore content plugins for external reference repos (`toolkit-content-plugins`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Mechanism to sync external reference content (`.md` files, domain knowledge) into a known toolkit location. First candidate: `itsmostafa/aws-agent-skills` (weekly-updated AWS service reference, 18 services). Different shape from Python deps — this is content, not code. Could be git-subtree, sparse checkout, or custom sync step. Related to both `aws-toolkit` (content source) and `skill-design-db-backing-repo` (external repo linking pattern).

## P100 - Nice to Have

- **[TOOLKIT]** Evaluate multi-model review in main workflows (`toolkit-multi-model-workflows`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: We already use haiku/sonnet/opus within Claude's family for resource evaluation, but not external models in main workflows. ToB's `/review-pr` launches Claude + Codex + Gemini in parallel for review consensus. Evaluate feasibility with existing Gemini account — could extend code-reviewer or simplify with a second-opinion pass from a different model family. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[TOOLKIT]** CI discovery pattern for quality pipelines (`ci-discovery-pattern`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Read `.github/workflows/` to discover actual CI checks instead of hardcoding language-specific commands. Applicable to simplify skill or a future CI-aware review flow. Avoids the common problem of running different checks locally than CI runs. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[SKILLS]** MCP server development skill (`skill-mcp-developer`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Skill for scaffolding/developing MCP servers. Real technical specifics: JSON-RPC 2.0, TypeScript/Python SDK patterns, Zod/Pydantic schemas, transport mechanisms. VoltAgent's mcp-developer agent had good domain coverage buried under template noise — use as starting reference. Ref: `.claude/output/reviews/exploration/voltagent_awesome-claude-code-subagents/summary.md`.

- **[SKILLS]** Create `github-actions` skill (`skill-gh-actions`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: CI/CD pipeline patterns, caching, matrix builds. Build when encountering real CI/CD need.

- **[TOOLKIT]** Telegram bot bridge to Claude Code (`telegram-bridge`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Use claude-agent-sdk (Python) to connect Telegram bot to local Claude Code. Async handler, tool permissions via PermissionRequest hook, session management per user. Weekend project scope.
