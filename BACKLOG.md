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

- **[TOOLKIT]** Resource token cost analysis — measure token usage of skills/agents/hooks/memories to evaluate efficiency vs value (`resource-token-cost`)
    - **scope**: `toolkit`
    - **notes**: Follow-up to `usage-audit`. Once we know *what* is used, measure *how much context* each resource consumes. Evaluate whether high-cost resources justify their token spend relative to the value they provide. Informs pruning, splitting, or compression decisions.


## P2 - Medium

- **[SCRIPTS]** Migrate session-search analytics to session-analytics — move `timeline`, `files`, `stats` subcommands from `session_search.py` to `session_analytics.py` (`session-analytics-migration`)
    - **scope**: `scripts`
    - **notes**: `session_search.py` has analytics-oriented subcommands (`timeline`, `files`, `stats`) that belong in `session_analytics.py`. Keep `session_search.py` focused on indexing and search. Migrate the commands, update imports, and keep backward-compat CLI aliases if needed.

- **[SCRIPTS]** Session analytics — memory load patterns per project (`session-analytics-memory`)
    - **scope**: `scripts`
    - **notes**: Data already exists in the events table (file_read actions on `**/memories/**`). Analyze: most-read memories per project, memory diversity (how many distinct memories a project uses), read frequency distribution, which memories are "load-bearing" (read nearly every session) vs occasional. Could inform memory pruning and identify projects that need better memory coverage.

- **[SCRIPTS]** Session analytics — plan+implementation session pairing (`session-analytics-work-units`)
    - **scope**: `scripts`
    - **notes**: Explore clustering consecutive sessions into "work units" — a planning session followed by implementation sessions. Challenge: planning may start on `main` before branching, or on the feature branch if the hook prompted a branch switch. Signals to use: timing proximity, project, branch transitions, plan mode events, session shape (planning sessions are shorter, read-heavy; implementation sessions are longer, command-heavy). Cross-branch boundary is the hard part.

- **[SCRIPTS]** Session analytics — project co-occurrence patterns (`session-analytics-co-occurrence`)
    - **scope**: `scripts`
    - **notes**: Which projects have sessions active on the same days? A project with many sessions compressed into few days alongside another project (e.g., schema-smith appearing on the same days as acustica-marina) suggests a supporting/dependency role rather than independent work. Analyze: daily co-occurrence matrix, identify "primary" vs "supporting" project roles per day, projects that always appear together vs independently.

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