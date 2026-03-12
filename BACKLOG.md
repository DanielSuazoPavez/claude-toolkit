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

- **[SKILLS]** Add worked example to `shape-proposal` skill (`skill-shape-proposal-example`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Reshape v5 (`.claude/drafts/shape-proposal/20260311_1600__brainstorm-idea__export-doc-extraction-v5.md`) through the skill to produce a proper example output with framing block, template sections, and status markers. Save as `resources/EXAMPLE.md`. Current v5 was shaped manually before the skill existed.

- **[SKILLS]** Improve `shape-proposal` skill from real usage analysis (`skill-shape-proposal-improvements`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Six improvements identified from real usage session (shaping export-doc-extraction v2). Three high-priority: (1) validation checklist audience-based split guidance, (2) core insight surfacing step, (3) comparison table self-test heuristic. Three medium: source-type awareness for reshape vs rewrite, source fidelity check after reviewer, scope creep decision framework. Also update `PROPOSAL_TEMPLATE.md` for items 1 and 6.
    - **plan**: `.claude/output/reviews/20260311_1300__analysis__shape-proposal-skill-improvements.md`

- **[AGENTS]** Improve `proposal-reviewer` agent from real usage analysis (`agent-proposal-reviewer-improvements`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Two improvements from real usage: (1) scope creep check should verify if framing block acknowledges implementation detail before flagging — if acknowledged, no finding; if not, flag the inconsistency. (2) Consider whether the agent should receive the source document alongside the shaped output for content fidelity checking (current assessment: keep agent focused on audience fit, handle source fidelity at skill level instead).
    - **plan**: `.claude/output/reviews/20260311_1300__analysis__shape-proposal-skill-improvements.md` (findings #4 and #5)

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

- **[AGENTS]** Create dedicated `security-reviewer` agent (`agent-security-reviewer`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Separate from `code-reviewer` — focused exclusively on vulnerability patterns: injection (SQL, command, XSS), auth/authz gaps, secrets exposure, input validation, CSRF, rate limiting, error message leakage. `code-reviewer` stays focused on quality/structure/correctness. Could reference ECC's 530-line security-review skill (10 security domains with concrete code examples) as starting material. Ref: `.claude/output/reviews/exploration/affaan-m_everything-claude-code/summary.md`. Also see CloudSecurityPartners' tool risk matrix and hook severity escalation patterns: `.claude/output/reviews/exploration/cloudsecuritypartners_skills/summary.md`.

- **[TOOLKIT]** Rewrite raiz publish trimming logic in Python (`toolkit-raiz-python-trimming`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Current bash trimming in `publish.sh` handles bullet items and "See also:" lines but not inline prose refs. Python would make regex/AST-based trimming easier to extend. Convention for now: inline refs are descriptive prose, not trimmed — `CLAUDE.md.template` notes this for raiz users.

## P3 - Low

- **[SKILLS]** Link `design-db` skill to schema-smith as optional dependency (`skill-design-db-backing-repo`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Wire `design-db` to `schema-smith` (YAML → PostgreSQL DDL/diagrams/SQLAlchemy models). First "skill backed by real project code" pattern. Two options: Python dependency (`uv add --optional`) or CLI invocation. Depends on schema-smith reaching stable state. Path: `personal/training/data-engineering/projects/schema-smith`.

- **[TOOLKIT]** Explore content plugins for external reference repos (`toolkit-content-plugins`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Mechanism to sync external reference content (`.md` files, domain knowledge) into a known toolkit location. First candidate: `itsmostafa/aws-agent-skills` (weekly-updated AWS service reference, 18 services). Different shape from Python deps — this is content, not code. Could be git-subtree, sparse checkout, or custom sync step. Feeds into `aws-toolkit` item.

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


- **[TOOLKIT]** Parse subagent transcripts in insights script (`insights-subagent-parsing`)
    - **status**: `in-progress`
    - **scope**: `toolkit`
    - **branch**: `feat/insights-subagent-parsing`
    - **notes**: Basic parsing done — subagents rolled up into parent sessions with agent type, model, tokens, tool calls, turns. Follow-up in `insights-subagent-detail`.

- **[TOOLKIT]** Detailed subagent metrics in insights script (`insights-subagent-detail`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **depends-on**: `insights-subagent-parsing`
    - **notes**: Separate sections for subagent activity (not rolled into main agent totals). Missing extractions: (1) hook events from subagent transcripts, (2) tool output token attribution (currently all 0), (3) user turns in subagents (tool results), (4) skill invocations within subagents. New display sections in `cmd_tools` and `cmd_hooks` for subagent vs main breakdown.

- **[TOOLKIT]** Telegram bot bridge to Claude Code (`telegram-bridge`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Use claude-agent-sdk (Python) to connect Telegram bot to local Claude Code. Async handler, tool permissions via PermissionRequest hook, session management per user. Weekend project scope.
