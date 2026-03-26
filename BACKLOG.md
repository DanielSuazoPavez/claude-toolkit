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

## P2 - Medium

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count.


- **[TESTS]** Update perf harnesses to instrument current implementation (`update-perf-harness-instrumentation`)
    - **scope**: `tests`
    - **notes**: Both `perf-surface-lessons.sh` and `perf-session-start.sh` run an instrumented copy of the *old* hook logic for per-phase timing, so the phase breakdown doesn't reflect the optimized code. The `ACTUAL_HOOK` timing is accurate (runs the real hook), but the per-phase breakdown and `INSTRUMENTED` total are misleading. Either rewrite `run_instrumented()` to match the current implementation, or instrument the actual hook with optional timing probes (e.g., `HOOK_PERF=1` env var).

## P3 - Low

- **[SKILLS]** Rename create-memory/evaluate-memory to create-docs/evaluate-docs (`rename-memory-skills-to-docs`)
    - **scope**: `skills`
    - **notes**: What these skills managed (prescriptive rules, conventions) is now called "docs". Rename skills, update content to reflect docs scope. `/create-memory` → `/create-docs`, `/evaluate-memory` → `/evaluate-docs`. Followup from post-reshape-followups.

- **[DOCS]** Lessons ecosystem doc — reference doc for the lessons system (`docs-lessons-ecosystem`)
    - **scope**: `docs`
    - **notes**: Create a `relevant-toolkit-lessons.md` doc in `.claude/docs/` covering the lessons ecosystem: lessons.db schema, tiers (key/recent), tags, `/learn` and `/manage-lessons` skills, session-start hook integration, nudge logic, and the `claude-toolkit lessons` CLI commands. Currently this knowledge is spread across skills, hooks, and CLI code with no single reference.

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

- **[TOOLKIT]** Native `autoMemoryDirectory` setting — resolved via symlink, revisit if setting starts working (`toolkit-auto-memory-dir`)
    - **scope**: `toolkit`
    - **notes**: Tested 2026-03-20. Setting only affects the UI "Open folder" link, not write behavior. Worked around with symlink approach (`.claude/memories/auto/` ← `~/.claude/projects/.../memory/`). Revisit if Claude Code fixes the setting in a future release.