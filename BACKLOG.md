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

- **[AGENTS]** Agent context exhaustion — agents run out of context before writing reports (`agent-context-exhaustion`)
    - **scope**: `agents`
    - **notes**: goal-verifier, codebase-explorer, and code-reviewer repeatedly hit context limits on larger codebases, dying before writing their output file. Root cause: agents do extensive exploration (reading files, git diffs, grepping) and write the report as the final step — if context fills during exploration, the report never gets written. Not project-specific; worse on bigger codebases. Proposed fixes: (1) **Incremental writing** — write report skeleton early, append findings as you go (survive context death). (2) **Trim agent prompts** — goal-verifier is 253 lines; shorter prompts leave more room for actual work (target ~100 lines). (3) **Prefer grep/glob over full file reads** where possible (cheaper context cost). (4) **Scoped inputs from caller** — parent conversation pre-digests scope instead of agent discovering everything. (5) Consider formalizing an "agentic docs" convention after validating the approach. Converting to skills was considered but rejected — loses `background: true` and parallel execution.

## P3 - Low

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability.
    - **design**: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`
    - **drafts**: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count. Analysis of surfacing effectiveness to come from claude-sessions side.

- **[HOOKS]** Session ID relay flakiness — hooks depend on file-based `.claude/logs/.session-id` written by session-start (`session-id-relay`)
    - **scope**: `hooks`
    - **notes**: Non-session-start hooks read session ID from a file that session-start writes. If session-start hasn't run or the file is stale, hooks log `"unknown"` as session_id. Consider deriving session ID directly in `hook_init()` from `CLAUDE_SESSION_ID` env var (if available) or falling back to the file relay.

## P99 - Nice to Have

