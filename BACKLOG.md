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

## P0 - Critical

## P1 - High

- **[HOOKS]** Improve block-dangerous-commands chaining detection (`hook-dangerous-commands-chaining`)
    - **status**: `idea`
    - **scope**: `hooks`
    - **notes**: Current hook only checks for dangerous targets (`/`, `~`, `.`) but doesn't detect command chaining — `; rm -rf /`, `&& rm -rf /`, `| rm` bypass detection. Add chaining-aware regex (`;`, `&&`, `||`, `|` before `rm`). ToB's approach blocks ALL `rm -rf` and suggests `trash` — we prefer target-specific blocking but need the chaining coverage. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[TOOLKIT]** Add statusline to repo as recommended default (`toolkit-statusline`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Currently using `@owloops/claude-powerline` at user level only. Add to repo's settings.json and template as a recommended default. Powerline already covers context usage, cost, git info, model, session duration — no custom script needed. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[SKILLS]** Add failure-trigger guidance for reviewer agents (`skill-agent-failure-triggers`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Reviewer/verifier agents should define explicit rejection criteria ("when to say NO"). Add as edge case note in evaluate-agent and checklist item in create-agent for reviewer-type agents. Not a new dimension — refinement to existing system. Ref: `.claude/output/reviews/exploration/msitarzewski_agency-agents/summary.md` (testing-reality-checker pattern).


## P2 - Medium

- **[SKILLS]** Basic description trigger testing for skills (`skill-description-trigger-testing`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Smoke-test whether skill descriptions cause correct activation on natural language prompts. Not the full anthropics optimization loop (train/test split, 5 iterations) — just a basic "does this trigger when it should?" check. Could be a step in evaluate-skill or a standalone script. Ref: `.claude/output/reviews/exploration/anthropics_skills/summary.md` (skill-creator deep dive).

- **[AGENTS/SKILLS]** AWS toolkit — agents and skills for AWS workflows (`aws-toolkit`)
    - **status**: `idea`
    - **scope**: `agents, skills`
    - **notes**: Base model struggles with real-world IAM policies and service-specific config. Three sub-items:
        - `aws-architect` agent: Infra design, cost/tradeoff analysis, online cost lookup
        - `aws-security-auditor` agent: Security review, least-privilege IAM validation
        - `aws-deploy` skill: Service-specific best practices (Lambda, RDS, OpenSearch)
    - **drafts**: `.claude/output/drafts/aws-toolkit/` — pre-research on IAM validation tools (Parliament, Policy Sentry, IAM Policy Autopilot) and cost estimation tools (Infracost, AWS Pricing API)

- **[SKILLS]** Command-style skill classification and evaluation (`skill-command-type-evaluation`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Command-like skills (snap-back, wrap-up, write-handoff) get unfairly penalized on D1 Knowledge Delta — their value is activation and consistency, not novel knowledge. A curated "check these 16 things" list is expert curation even if individual items aren't novel. Options: (1) Add a `type` field to skill frontmatter and branch evaluation by type, (2) Revive `commands/` as a separate resource type with its own lighter evaluator, (3) Keep in `skills/` but create a second rubric dispatched by type. Deep dive into Anthropic's skill-creator skill for reference on how they handle this spectrum. Ref: suggestions-box/claude-meta issues #1 and #5.


- **[SKILLS]** Shift examples to copy-and-modify templates in write-* skills (`skill-templates-as-starting-points`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Current examples are reference material. Anthropic's pattern: templates are literal files Claude copies and modifies ("use as LITERAL STARTING POINT, not just inspiration"). More prescriptive = more consistent output. Apply to create-skill, create-agent, and any skill producing structured output. Ref: `.claude/output/reviews/exploration/anthropics_skills/summary.md`.

- **[TOOLKIT]** Explore `.claude/rules/` for path-scoped instructions (`toolkit-rules`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Rules are modular markdown files in `.claude/rules/` with optional `paths` glob frontmatter — instructions that only activate when working with matching files. Could replace some conditional memory loading with automatic file-aware activation. Ref: `.claude/output/drafts/claude-code-rules.md`, https://code.claude.com/docs/en/memory

- **[HOOKS]** Anti-rationalization Stop hook (`hook-anti-rationalization`)
    - **status**: `idea`
    - **scope**: `hooks`
    - **notes**: Prompt-type Stop hook that catches premature victory declarations — cop-out phrases like "pre-existing issues," "out of scope," "too many issues," "I'll leave this for a follow-up." Fires at the exact decision point, unlike CLAUDE.md instructions that fade under context pressure. Could use Haiku review (ToB approach) or lighter pattern-match. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[SKILLS]** Turn budget awareness convention for multi-step skills (`skill-turn-budget-awareness`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Skills that spawn multiple agents or run multi-phase workflows should handle budget limits gracefully: "At 75% budget, stop new work. At 90%, emit partial results." Add as convention in create-skill guidance. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[TOOLKIT]** Audit settings against ToB security patterns (`security-settings-audit`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: We have no `permissions.deny` or `enableAllProjectMcpServers: false`. ToB's settings include deny list for SSH keys, cloud creds (AWS/Azure/GH/Docker/K8s), package tokens (npm/pypi/gem), shell config edits, and MCP auto-enable protection. Not all apply (crypto wallets are ToB-specific), but SSH keys, cloud creds, and MCP flag are universally relevant. Review and adopt what fits. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[TOOLKIT]** Evaluate multi-model review in main workflows (`toolkit-multi-model-workflows`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: We already use haiku/sonnet/opus within Claude's family for resource evaluation, but not external models in main workflows. ToB's `/review-pr` launches Claude + Codex + Gemini in parallel for review consensus. Evaluate feasibility with existing Gemini account — could extend code-reviewer or simplify with a second-opinion pass from a different model family. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[SKILLS]** Add rationalization tables to create-skill guidance (`skill-rationalization-tables`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: When creating discipline-enforcing skills, build a rationalization table from baseline testing: run scenario without skill, document what excuses the agent makes, write explicit counters. obra/superpowers does this systematically (TDD skill has 9 entries). We do red-green-refactor but don't explicitly document rationalizations as a technique. Add as a recommended step in create-skill's RED phase. Ref: `.claude/output/reviews/exploration/obra_superpowers/summary.md`.

- **[AGENTS]** Add "3+ failed fixes = stop" escalation to code-debugger (`agent-debugger-escalation`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: If three sequential fixes each reveal a new problem in a different place, stop and escalate — signals architectural issue, not a series of bugs. obra/superpowers systematic-debugging uses this as a guardrail. Our code-debugger has no explicit escalation trigger. Ref: `.claude/output/reviews/exploration/obra_superpowers/summary.md`.

- **[TOOLKIT]** Evaluate hard gate pattern for premature-action skills (`toolkit-hard-gate-pattern`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: obra/superpowers uses `<HARD-GATE>` XML tags as explicit do-not-proceed markers (e.g., brainstorming blocks implementation before design approval). Test whether Claude Code respects XML-tag-based gates better than prose instructions. If effective, add as a convention for skills where premature action is a known failure mode. Ref: `.claude/output/reviews/exploration/obra_superpowers/summary.md`.

## P100 - Nice to Have

- **[TOOLKIT]** Cherry-pick CLAUDE.md template conventions from ToB (`claude-md-template-conventions`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Easy wins from ToB's CLAUDE.md template: `trash` over `rm`, explicit philosophy principles ("replace don't deprecate", "finish the job"), zero warnings policy. Low effort, clear value. Review which conventions align with what we already do informally and make them explicit. Ref: `.claude/output/reviews/exploration/trailofbits_claude-code-config/summary.md`.

- **[HOOKS]** Context-aware suggestions via UserPromptSubmit (`hook-context-suggest`)
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - **notes**: Analyze user prompt, suggest relevant memories and skills. Bash-only implementation (keyword matching).

- **[AGENTS]** Create dedicated `security-reviewer` agent (`agent-security-reviewer`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Separate from `code-reviewer` — focused exclusively on vulnerability patterns: injection (SQL, command, XSS), auth/authz gaps, secrets exposure, input validation, CSRF, rate limiting, error message leakage. `code-reviewer` stays focused on quality/structure/correctness. Could reference ECC's 530-line security-review skill (10 security domains with concrete code examples) as starting material. Ref: `.claude/output/reviews/exploration/affaan-m_everything-claude-code/summary.md`.

- **[SKILLS]** Add quality gate rubric to `/learn` skill (`skill-learn-quality-gate`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Before saving a lesson, self-evaluate on 5 dimensions (Specificity, Actionability, Scope Fit, Non-redundancy, Coverage) scored 1-5. Must improve anything scoring 1-2 before saving. Prevents thin or duplicate lessons from accumulating. ECC's `/learn-eval` command does this — show scores table to user for transparency. Adapt to our lesson format (pattern/gotcha/convention categories). Ref: `.claude/output/reviews/exploration/affaan-m_everything-claude-code/summary.md`.

- **[SKILLS]** Add eval self-critique step to evaluate-* skills (`skill-eval-self-critique`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: After scoring, ask "would any of my rubric dimensions pass for a wrong output too?" Catches non-discriminating dimensions. Anthropic's grader does this — flags assertions that create false confidence. Light addition to evaluation protocol. Ref: `.claude/output/reviews/exploration/anthropics_skills/summary.md`.

- **[TOOLKIT]** Document "invoke, don't read" convention for bundled scripts (`convention-scripts-black-boxes`)
    - **status**: `idea`
    - **scope**: `toolkit`
    - **notes**: Scripts should be run with `--help` first, not read as source. Protects context window. We already add `--help` to scripts — make the convention explicit in create-skill guidance and toolkit conventions. Ref: anthropics/skills webapp-testing pattern.

- **[SKILLS]** Add examples to `refactor` skill (`skill-refactor-examples`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Add `resources/EXAMPLES.md` with: (1) one worked example per lens (coupling, API surface — dependency direction and cohesion already exist inline), (2) a full end-to-end Python example showing triage → measure → four-lens → document flow on a real codebase. Gate on real usage: only build when the skill passes alpha from use in actual projects.

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

---

## Graveyard

- **[AGENTS]** Add metadata block to generated documents (`agent-metadata-block`) — overkill; file names and content start is enough
- **[TOOLKIT]** Headless agent for suggestions-box processing (`agent-suggestions-processor`) — has its own design doc and folder, not a backlog item
- **[SKILLS]** Create `review-documentation` skill (`skill-review-docs`) — redundant; write-docs gap analysis already audits docs against code before writing. For docs, reading IS the review.
- **[SKILLS]** Research Polars-specific patterns (`skill-polars`) — base model knowledge + Context7 MCP provides sufficient coverage; Polars API evolves too fast for a static skill to add value
- **[SKILLS]** Create `logging-observability` skill (`skill-logging`) — base knowledge sufficient for decision guidance; preferences not yet formed on observability stack beyond structlog
- **[AGENTS]** Create `test-gap-analyzer` agent (`agent-test-gaps`) — behavioral delta too thin; gap-analysis workflow absorbed into `design-tests` skill audit mode instead
