# Project Backlog

## Current Goal

Iterating on resources through real usage — fixing issues surfaced from project deployments, improving tooling based on actual workflows.

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

- **[AGENTS/SKILLS]** AWS toolkit — agents and skills for AWS workflows (`aws-toolkit`)
    - **status**: `idea`
    - **scope**: `agents, skills`
    - **notes**: Base model struggles with real-world IAM policies and service-specific config. Three sub-items:
        - `aws-architect` agent: Infra design, cost/tradeoff analysis, online cost lookup
        - `aws-security-auditor` agent: Security review, least-privilege IAM validation
        - `aws-deploy` skill: Service-specific best practices (Lambda, RDS, OpenSearch)
    - **drafts**: `.claude/drafts/aws-toolkit/` — pre-research on IAM validation tools (Parliament, Policy Sentry, IAM Policy Autopilot) and cost estimation tools (Infracost, AWS Pricing API)


- **[SKILLS]** Create `refactor` skill (`skill-refactor`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Refactoring as a design activity, not just mechanics. Systematic decision guidance via coupling/cohesion/dependency-direction metrics, structured before/after analysis, step ordering with metric validation. Value is consistency — ensuring the model applies deep structural reasoning every time, not just when prompted.
    - **drafts**: `.claude/drafts/skill-refactor/` — design notes from backlog evaluation session

## P2 - Medium

- **[TOOLKIT]** Explore `.claude/rules/` for path-scoped instructions (`toolkit-rules`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Rules are modular markdown files in `.claude/rules/` with optional `paths` glob frontmatter — instructions that only activate when working with matching files. Could replace some conditional memory loading with automatic file-aware activation. Ref: `.claude/reviews/exploration/claude-code-rules.md`, https://code.claude.com/docs/en/memory


## P100 - Nice to Have

- **[HOOKS]** Context-aware suggestions via UserPromptSubmit (`hook-context-suggest`)
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - **notes**: Analyze user prompt, suggest relevant memories and skills. Bash-only implementation (keyword matching).

- **[SKILLS]** Create `github-actions` skill (`skill-gh-actions`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: CI/CD pipeline patterns, caching, matrix builds. Build when encountering real CI/CD need.

- **[TOOLKIT]** Telegram bot bridge to Claude Code (`telegram-bridge`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Use claude-agent-sdk (Python) to connect Telegram bot to local Claude Code. Async handler, tool permissions via PermissionRequest hook, session management per user. Weekend project scope.

---

## Graveyard

- **[AGENTS]** Add metadata block to generated documents (`agent-metadata-block`) — overkill; file names and content start is enough
- **[TOOLKIT]** Headless agent for suggestions-box processing (`agent-suggestions-processor`) — has its own design doc and folder, not a backlog item
- **[SKILLS]** Create `review-documentation` skill (`skill-review-docs`) — redundant; write-docs gap analysis already audits docs against code before writing. For docs, reading IS the review.
- **[SKILLS]** Research Polars-specific patterns (`skill-polars`) — base model knowledge + Context7 MCP provides sufficient coverage; Polars API evolves too fast for a static skill to add value
- **[SKILLS]** Create `logging-observability` skill (`skill-logging`) — base knowledge sufficient for decision guidance; preferences not yet formed on observability stack beyond structlog
- **[AGENTS]** Create `test-gap-analyzer` agent (`agent-test-gaps`) — behavioral delta too thin; gap-analysis workflow absorbed into `design-tests` skill audit mode instead
