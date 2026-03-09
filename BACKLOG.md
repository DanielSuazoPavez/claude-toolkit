# Project Backlog

## Current Goal

Preparing v2 release — audit evaluate-* rubrics, then full resource re-evaluation baseline.

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

- **[TOOLKIT]** Re-evaluate all resources with current rubrics (`evaluations-refresh`)
    - **status**: `idea`
    - **scope**: `skills, agents, hooks, memories`
    - **notes**: Scores in `evaluations.json` have drifted — resources have been updated since last evaluation, and skill rubric now includes command-type classification (1.24.0). Re-run `/evaluate-batch` on all resource types (skills, agents, hooks, memories) for a full baseline reset. Command-type skills (snap-back, wrap-up, write-handoff, setup-worktree, teardown-worktree) should benefit most from D1 reinterpretation. Gate for v2 release.

## P1 - High

- **[AGENTS/SKILLS]** AWS toolkit — agents and skills for AWS workflows (`aws-toolkit`)
    - **status**: `idea`
    - **scope**: `agents, skills`
    - **notes**: Base model struggles with real-world IAM policies and service-specific config. Three sub-items:
        - `aws-architect` agent: Infra design, cost/tradeoff analysis, online cost lookup
        - `aws-security-auditor` agent: Security review, least-privilege IAM validation
        - `aws-deploy` skill: Service-specific best practices (Lambda, RDS, OpenSearch)
    - **drafts**: `.claude/output/drafts/aws-toolkit/` — pre-research on IAM validation tools (Parliament, Policy Sentry, IAM Policy Autopilot) and cost estimation tools (Infracost, AWS Pricing API)

## P2 - Medium

- **[SKILLS]** Add examples to `refactor` skill (`skill-refactor-examples`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Add `resources/EXAMPLES.md` with: (1) one worked example per lens (coupling, API surface — dependency direction and cohesion already exist inline), (2) a full end-to-end Python example showing triage → measure → four-lens → document flow on a real codebase. Gate on real usage: only build when the skill passes alpha from use in actual projects.

- **[SKILLS]** Add quality gate rubric to `/learn` skill (`skill-learn-quality-gate`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Before saving a lesson, self-evaluate on 5 dimensions (Specificity, Actionability, Scope Fit, Non-redundancy, Coverage) scored 1-5. Must improve anything scoring 1-2 before saving. Prevents thin or duplicate lessons from accumulating. ECC's `/learn-eval` command does this — show scores table to user for transparency. Adapt to our lesson format (pattern/gotcha/convention categories). Ref: `.claude/output/reviews/exploration/affaan-m_everything-claude-code/summary.md`.

- **[TOOLKIT]** Evaluate hard gate pattern for premature-action skills (`toolkit-hard-gate-pattern`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: obra/superpowers uses `<HARD-GATE>` XML tags as explicit do-not-proceed markers (e.g., brainstorming blocks implementation before design approval). Test whether Claude Code respects XML-tag-based gates better than prose instructions. If effective, add as a convention for skills where premature action is a known failure mode. Ref: `.claude/output/reviews/exploration/obra_superpowers/summary.md`.

- **[AGENTS]** Create dedicated `security-reviewer` agent (`agent-security-reviewer`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Separate from `code-reviewer` — focused exclusively on vulnerability patterns: injection (SQL, command, XSS), auth/authz gaps, secrets exposure, input validation, CSRF, rate limiting, error message leakage. `code-reviewer` stays focused on quality/structure/correctness. Could reference ECC's 530-line security-review skill (10 security domains with concrete code examples) as starting material. Ref: `.claude/output/reviews/exploration/affaan-m_everything-claude-code/summary.md`.

## P100 - Nice to Have

- **[TOOLKIT]** Evaluate multi-model review in main workflows (`toolkit-multi-model-workflows`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: We already use haiku/sonnet/opus within Claude's family for resource evaluation, but not external models in main workflows. ToB's `/review-pr` launches Claude + Codex + Gemini in parallel for review consensus. Evaluate feasibility with existing Gemini account — could extend code-reviewer or simplify with a second-opinion pass from a different model family. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[HOOKS]** Context-aware suggestions via UserPromptSubmit (`hook-context-suggest`)
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - **notes**: Analyze user prompt, suggest relevant memories and skills. Bash-only implementation (keyword matching).


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
