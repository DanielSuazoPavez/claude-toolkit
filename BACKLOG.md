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

- **[AGENTS]** Validate v2.45.0 reviewer agent protocols in real usage (`validate-reviewer-protocols`)
    - **scope**: `agents`
    - **notes**: v2.45.0 changed investigation protocols for code-reviewer, goal-verifier, and implementation-checker (incremental writes, risk categorization, magnitude-aware depth). Ship-and-observe: on the next real branch, confirm each agent writes its skeleton early and completes the report. If any agent fails to produce a report or quality regresses, rollback that agent's file to v2.44.2. Remove this task after first successful run of all three.

## P1 - High

## P2 - Medium

- **[SKILLS]** `/wrap-up` — defer tagging to after final commit (`wrap-up-defer-tag`)
    - **scope**: `skills`
    - **notes**: Current wrap-up skill tags at the version bump step (step 9), but changes often come after (review fixes, changelog updates), forcing tag deletion and re-creation. Move tagging to the very end, right before merge.

- **[SKILLS]** Skill token density audit — prune structural overhead across distributed skills (`skill-token-density`)
    - **scope**: `skills`
    - **notes**: Skills ship to all downstream projects — their token cost is per-invocation across every project that uses them. 33 skills total 38.8K words (avg 1,176/skill). The evaluate-* family is heaviest (5 skills, avg 1,736 words — calibration tables, example evaluations). 15–25% of most skills is structural overhead (anti-patterns, edge cases, "See Also") that doesn't directly drive behavior. Separate concern from agent prompt trim — this is about cumulative token spend, not context exhaustion.
    - **analysis**: `output/claude-toolkit/analysis/20260331_1000__analyze-idea__information-density-loadable-resources.md`

- **[TOOLKIT]** `format-raiz-changelog.sh` — bold-prefixed bullets skip `•` replacement (`raiz-changelog-bullet-cosmetic`)
    - **scope**: `toolkit`
    - **notes**: In `to_telegram_html`, the sed `s/^- \*\*\([^*]*\)\*\*/<b>\1<\/b>/` fires before `s/^- /• /`, so bullets starting with `- **keyword**` (all real changelog bullets) never get the `•` prefix. The `•` sed is effectively dead code for typical entries. Fix during the planned message format redesign — either reorder the seds or apply `•` unconditionally after bold conversion.

## P3 - Low

- **[TOOLKIT]** Address global configs for base dist projects (`global-configs-dist`)
    - **scope**: `toolkit`
    - **notes**: Global shared files (lessons.db, session-index.db in `~/.claude/`) leak into project directories as stray untracked files. Base dist projects need a proper story: ensure `.gitignore` templates cover known global artifacts, document which files are global vs project-scoped, and consider whether sync should clean up or warn about misplaced globals.

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability.
    - **design**: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`
    - **drafts**: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count. Analysis of surfacing effectiveness to come from claude-sessions side.

## P99 - Nice to Have

