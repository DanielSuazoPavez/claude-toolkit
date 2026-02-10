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

- **[SKILLS]** Improve evaluation system — D7 rework, priority tags, cross-resource checks (`skill-eval-improvements`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Three improvements to evaluate-* skills:
        - Rework D7 (Pattern Recognition) for skills — zero variance (all score 9/10), not differentiating
        - Add priority tags (`[high]`/`[low]`) to improvement suggestions in evaluations.json
        - Make cross-resource integration quality an explicit check when resources reference other resources
    - **plan**: `.claude/reviews/exploration/rohitg00_pro-workflow/summary.md` (Evaluation System Observations section)

## P2 - Medium

- **[SKILLS]** Create `refactor` skill (`skill-refactor`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Structured guidance for module restructuring, dependency untangling, migration from X to Y. Impact analysis, step ordering, verification at each stage.

- **[AGENTS]** Create `test-gap-analyzer` agent (`agent-test-gaps`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Analyzes existing tests, finds coverage gaps, suggests what to test. Pairs with `design-tests` skill. Multi-step: discover test files, analyze source coverage, report gaps.

- **[TOOLKIT]** Explore `.claude/rules/` for path-scoped instructions (`toolkit-rules`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Rules are modular markdown files in `.claude/rules/` with optional `paths` glob frontmatter — instructions that only activate when working with matching files. Could replace some conditional memory loading with automatic file-aware activation. Ref: `.claude/reviews/exploration/claude-code-rules.md`, https://code.claude.com/docs/en/memory

- **[SKILLS]** Create `github-actions` skill (`skill-gh-actions`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: CI/CD pipeline patterns, caching, matrix builds

- **[TOOLKIT]** Session lessons system (`session-lessons`)
    - **status**: `idea`
    - **scope**: `toolkit, skills, memories`
    - **notes**: Memory + skill for capturing debugging/investigation insights. Meta-tags: `[T]` transferable vs `[P:project]` project-specific. Reference: bm-sop `experimental-sessions_lessons.md`. Learning-capture loop from rohitg00/pro-workflow is a good reference for automation (SQLite + FTS5 + hook-based capture). Ref: `.claude/reviews/exploration/rohitg00_pro-workflow/summary.md`

## P100 - Nice to Have

- **[SKILLS]** Create `logging-observability` skill (`skill-logging`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Structured logging, metrics, tracing setup

- **[HOOKS]** Context-aware suggestions via UserPromptSubmit (`hook-context-suggest`)
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - **notes**: Analyze user prompt, suggest relevant memories and skills. Bash-only implementation (keyword matching).

- **[SKILLS]** Research Polars-specific patterns (`skill-polars`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Lazy frames, expressions, optimizations

- **[TOOLKIT]** Telegram bot bridge to Claude Code (`telegram-bridge`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Use claude-agent-sdk (Python) to connect Telegram bot to local Claude Code. Async handler, tool permissions via PermissionRequest hook, session management per user. Weekend project scope.

---

## Graveyard

- **[AGENTS]** Add metadata block to generated documents (`agent-metadata-block`) — overkill; file names and content start is enough
- **[TOOLKIT]** Headless agent for suggestions-box processing (`agent-suggestions-processor`) — has its own design doc and folder, not a backlog item
- **[SKILLS]** Create `review-documentation` skill (`skill-review-docs`) — redundant; write-docs gap analysis already audits docs against code before writing. For docs, reading IS the review.
