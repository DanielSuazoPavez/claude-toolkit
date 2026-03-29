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

## P3 - Low

- **[HOOKS]** Improve lessons lifecycle — reduce noise, surface smarter (`improve-lessons-lifecycle`)
    - **scope**: `hooks, scripts`
    - **notes**: Lessons accumulate faster than they get pruned, hitting ~17 where ~10 is the practical ceiling. Two areas to address: (1) **Pruning** — lessons linger too long; consider auto-expiry after N sessions if not promoted/tagged recurring, or lower the bar for `/manage-lessons` runs. (2) **Surfacing hook** — currently dumps all lessons undifferentiated; explore relevance filtering (branch/task-aware), tiered display (Key always, Recent only when relevant), or capping displayed count. Analysis of surfacing effectiveness to come from claude-sessions side.

- **[SKILLS]** Evaluate model AWS knowledge gaps — test what Claude gets right/wrong for reference doc scoping (`design-aws-knowledge-gaps`)
    - **scope**: `skills`
    - **notes**: Research task. Test model accuracy on IAM scoping patterns, service selection nuances, security patterns, Terraform gotchas. Determines what goes in the `design-aws` reference doc as "activation knowledge" vs "expert knowledge" vs redundant with base model. Informs the reference doc content.
    - **design**: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`

- **[SKILLS]** `design-aws` reference doc — AWS knowledge base for the skill (`design-aws-reference-doc`)
    - **scope**: `skills`
    - **depends-on**: `design-aws-knowledge-gaps`
    - **notes**: Lives in `.claude/skills/design-aws/resources/`. Activation + expert knowledge: service selection guidance, IAM scoping patterns, security review checklist, common architecture patterns, mapping from architecture concepts to aws-toolkit input format. Content scoped by knowledge gap evaluation.

- **[SKILLS]** AWS architecture diagram icons for `/design-diagram` (`design-aws-diagram-icons`)
    - **scope**: `skills`
    - **notes**: Investigate which icon format `/design-diagram` best supports, add AWS icon set to diagram skill resources. Enables architecture diagrams with proper AWS service icons.

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **depends-on**: `design-aws-reference-doc`, `design-aws-diagram-icons`
    - **notes**: Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability.
    - **design**: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`
    - **drafts**: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection

## P99 - Nice to Have

- **[HOOKS]** `last_assistant_message` in Stop hooks — output-level hooks for post-response automation (`hook-stop-last-message`)
    - **scope**: `hooks`
    - **notes**: HOOKS_API updated with `last_assistant_message` field and `prompt`/`agent` hook types. Concrete use case: lesson-detection Stop hook (regex-based detection proved unreliable — consider `prompt`-type hook instead).

