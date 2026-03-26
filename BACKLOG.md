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

- **[HOOKS]** Add observability to surface-lessons hook — log query context, keywords, match count, and lesson IDs via `hook_log_section` (`surface-lessons-observability`)
    - **scope**: `hooks`
    - **notes**: Currently surface-lessons is a black box — timing log only shows duration and bytes injected. Add `hook_log_section` calls for: raw context (command/path), extracted keywords, SQL match count, matched lesson IDs. Data is for claude-sessions analytics, not runtime use. Infrastructure already exists (`hook_log_section`, session-id in timing log).

## P1 - High

## P2 - Medium

- **[HOOKS]** Optimize slower/heavier hooks — profile and improve `surface-lessons` and other high-cost hooks (`optimize-heavy-hooks`)
    - **scope**: `hooks`
    - **notes**: `surface-lessons` is consistently the slowest hook (~130-230ms). At least one other hook was noted as heavy. Profile with `hook-timing.log` data, identify bottlenecks (sqlite queries, stdin parsing, process startup), and optimize. Could involve caching, short-circuiting early, or reducing redundant work.

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count.


## P3 - Low

- **[HOOKS]** Investigate hookEventName value for PermissionRequest hooks (`hook-event-name-investigation`)
    - **scope**: `hooks`
    - **notes**: `hook_approve` now emits `hookEventName=$HOOK_EVENT` (e.g., "PermissionRequest") but the old create-hook GOTCHA claimed it must be "PreToolUse" even for PermissionRequest. HOOKS_API.md only shows "PreToolUse" in the output spec. Current `approve-safe-commands.sh` works with "PermissionRequest" but this may be undocumented behavior. Investigate if Claude Code enforces specific values.

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

- **[HOOKS]** Rescue worktree hook logs — copy `.claude/logs/` from worktrees before teardown (`rescue-worktree-logs`)
    - **scope**: `hooks`
    - **notes**: Worktrees have isolated `.claude/logs/` (including `hook-timing.log` and `.session-id`). When a worktree is torn down, those logs are lost. Consider a pre-teardown hook or wrapper that copies logs to the main project's log directory. Related to session-id feature — worktree sessions are naturally isolated but their data should be preserved.

- **[HOOKS]** `last_assistant_message` in Stop hooks — output-level hooks for post-response automation (`hook-stop-last-message`)
    - **scope**: `hooks`
    - **notes**: HOOKS_API updated with `last_assistant_message` field and `prompt`/`agent` hook types. Concrete use case: lesson-detection Stop hook (regex-based detection proved unreliable — consider `prompt`-type hook instead).

- **[SKILLS]** Adopt `${CLAUDE_SKILL_DIR}` — use in skills that reference bundled resources (`skill-claude-skill-dir`)
    - **scope**: `skills`

- **[TOOLKIT]** Native `autoMemoryDirectory` setting — unclear if it actually changes write behavior vs just `/memory` UI folder (`toolkit-auto-memory-dir`)
    - **scope**: `toolkit`
    - **notes**: Tested 2026-03-20. Setting `autoMemoryDirectory` in user settings only affects the "Open auto-memory folder" option in `/memory` UI — didn't observe it redirecting where Claude writes auto-memories. Needs more investigation if Claude Code documents this further.