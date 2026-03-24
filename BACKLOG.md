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

- **[TOOLKIT]** Resource usage audit — identify which skills/agents/hooks are actually used vs collecting dust (`usage-audit`)
    - **scope**: `toolkit`
    - **notes**: Infrastructure is in place: `scripts/insights.py` parses transcripts with `skills`, `agents`, `hooks`, `tools` subcommands; `scripts/backup-transcripts.sh` runs hourly via cron preserving transcripts from auto-pruning (`~/backups/claude-transcripts/`). Run the audit, identify dead weight, decide what to prune or demote.

- **[SKILLS]** Worktree skills polish — stress-test `setup-worktree` and `teardown-worktree` with real parallel workflows (`worktree-polish`)
    - **scope**: `skills`
    - **notes**: Both skills are `beta*` (under consideration). Previous attempts at the parallel worktrees flow were clunky. Need a real multi-branch scenario to identify friction, fix issues, and decide whether to promote to stable or remove. Skills have been updated since last real usage.

- ~~**[TOOLKIT]** Exploration ecosystem scan — fresh look at Claude Code community for new patterns and trends (`exploration-scan`)~~ **DONE 2026-03-24**
    - **scope**: `toolkit`
    - **notes**: Reviewed 3 repos (itsmostafa/aws-agent-skills, mitsuhiko/agent-stuff, applied-ai/claude-code-toolkit). Scanned GitHub + skills.sh for new community repos. Added 2 pending to exploration backlog (disler hooks repos). Key find: session-db.py → new `session-search` backlog item.

## P2 - Medium

- **[AGENTS/SKILLS]** AWS toolkit — agents and skills for AWS workflows (`aws-toolkit`)
    - **status**: `in-progress`
    - **scope**: `agents, skills`
    - **repo**: `~/projects/personal/aws-toolkit`
    - **notes**: Base model struggles with real-world IAM policies and service-specific config. Work happens in the aws-toolkit repo, not here — this backlog entry tracks the initiative, not local changes. Three sub-items:
        - `aws-architect` agent: Infra design, cost/tradeoff analysis, online cost lookup
        - `aws-security-auditor` agent: Security review, least-privilege IAM validation
        - `aws-deploy` skill: Service-specific best practices (Lambda, RDS, OpenSearch)
    - **drafts**: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools (Parliament, Policy Sentry, IAM Policy Autopilot) and cost estimation tools (Infracost, AWS Pricing API)

- **[SCRIPTS]** Session history search tool — SQLite+FTS5 index of all CC sessions for cross-project search (`session-search`)
    - **scope**: `scripts`
    - **notes**: Inspired by `applied-artificial-intelligence/claude-code-toolkit`'s `session-db.py`. Indexes `~/.claude/projects/` JSONL into SQLite with full-text search across tool calls, file changes, commands. Use cases: "when did we implement X?", "what files changed related to Y?", cross-project pattern recall. Also feeds into `usage-audit` task. Reference: `output/claude-toolkit/exploration/applied-ai_claude-code-toolkit/summary.md`.

## P3 - Low

- **[SKILLS]** Tighten review-plan skill — make commit-per-step and post-implementation steps structural (`review-plan-tighten`)
    - **scope**: `skills`
    - **notes**: Current review-plan suggests "commit after each step" and "add post-implementation steps" but these feel too close to optional suggestions. Tighten to be structural requirements. Consider pairing with `stop-hook-plan-enforcement` for enforcement.

- **[HOOKS]** Stop hook enforcement for plan execution — verify implementation steps completed (`stop-hook-plan-enforcement`)
    - **scope**: `hooks`
    - **notes**: Pattern from `disler/claude-code-hooks-mastery` — Stop hooks that verify output files exist and contain required sections before allowing completion. Could enforce "commit after each step" and "post-implementation steps" structurally rather than via suggestion. Ties into `review-plan-tighten`. Reference: `output/claude-toolkit/exploration/disler_claude-code-hooks-mastery/summary.md`.

- **[TOOLKIT]** Output styles concept — consider switchable response formatting modes (`output-styles-concept`)
    - **scope**: `toolkit`
    - **notes**: Inspired by `disler/claude-code-hooks-mastery`'s `.claude/output-styles/` directory. Named formatting modes (ultra-concise, table-based, genui/HTML output, etc.) activated per-session. Different from our communication style memory — these are structural formatting preferences, not personality. Relates to `schemas/` folder direction. Explore whether this fits as a convention or is over-engineering.

## P99 - Nice to Have

- **[HOOKS]** `last_assistant_message` in Stop hooks — output-level hooks for post-response automation (`hook-stop-last-message`)
    - **scope**: `hooks`
    - **notes**: HOOKS_API updated with `last_assistant_message` field and `prompt`/`agent` hook types. Concrete use case: lesson-detection Stop hook (regex-based detection proved unreliable — consider `prompt`-type hook instead).

- **[SKILLS]** Adopt `${CLAUDE_SKILL_DIR}` — use in skills that reference bundled resources (`skill-claude-skill-dir`)
    - **scope**: `skills`

- **[TOOLKIT]** Native `autoMemoryDirectory` setting — unclear if it actually changes write behavior vs just `/memory` UI folder (`toolkit-auto-memory-dir`)
    - **scope**: `toolkit`
    - **notes**: Tested 2026-03-20. Setting `autoMemoryDirectory` in user settings only affects the "Open auto-memory folder" option in `/memory` UI — didn't observe it redirecting where Claude writes auto-memories. Needs more investigation if Claude Code documents this further.