# Project Backlog

## Current Goal

Getting claude-toolkit to a clean, polished state: personal use first, organized and documented. Foundation for syncing across multiple projects, eventually public-ready.

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

- **[SKILLS]** Create `logging-observability` skill (`skill-logging`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Structured logging, metrics, tracing setup

## P2 - Medium

- **[AGENTS]** Create `test-gap-analyzer` agent (`agent-test-gaps`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Analyzes existing tests, finds coverage gaps, suggests what to test. Pairs with `design-tests` skill. Multi-step: discover test files, analyze source coverage, report gaps.

- **[SKILLS]** Create `review-documentation` skill (`skill-review-docs`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Reviews non-code parts: README, docs/, docstrings, comments. Checks completeness, accuracy vs code, consistency, broken links. Does NOT review code logic.

- **[SKILLS]** Create `github-actions` skill (`skill-gh-actions`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: CI/CD pipeline patterns, caching, matrix builds

- **[SKILLS]** Create `write-documentation` skill (`skill-write-docs`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: API docs, docstrings, README generation

- **[TOOLKIT]** Session lessons system (`session-lessons`)
    - **status**: `idea`
    - **scope**: `toolkit, skills, memories`
    - **notes**: Memory + skill for capturing debugging/investigation insights. Meta-tags: `[T]` transferable vs `[P:project]` project-specific. Reference: bm-sop `experimental-sessions_lessons.md`.

## P100 - Nice to Have

- **[HOOKS]** Context-aware suggestions via UserPromptSubmit (`hook-context-suggest`)
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - **notes**: Analyze user prompt, suggest relevant memories and skills. Bash-only implementation (keyword matching).

- **[AGENTS]** Create `aws-architect` agent (`agent-aws-architect`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Infra design, cost/tradeoff analysis, online cost lookup

- **[AGENTS]** Create `aws-security-auditor` agent (`agent-aws-security`)
    - **status**: `idea`
    - **scope**: `agents`
    - **notes**: Security review, least-privilege validation

- **[SKILLS]** Create `aws-deploy` skill (`skill-aws-deploy`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Service-specific best practices (Lambda, RDS, OpenSearch)

- **[SKILLS]** Research Polars-specific patterns (`skill-polars`)
    - **status**: `idea`
    - **scope**: `skills`
    - **notes**: Lazy frames, expressions, optimizations

---

## Graveyard
