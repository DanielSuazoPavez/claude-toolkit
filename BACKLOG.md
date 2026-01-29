# Project Backlog

## Goal

Getting claude-toolkit to a clean, polished state:
- Personal use first, organized and documented
- Foundation for syncing across multiple projects
- Eventually public-ready

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

(None)

---

## P1 - High

- **[SKILLS]** Create `logging-observability` skill
    - **status**: `idea`
    - **scope**: `skills`
    - Structured logging, metrics, tracing setup

---

## P2 - Medium

- **[AGENTS]** Create `test-gap-analyzer` agent
    - **status**: `idea`
    - **scope**: `agents`
    - Analyzes existing tests, finds coverage gaps, suggests what to test
    - Pairs with `design-tests` skill (pytest patterns)
    - Multi-step: discover test files → analyze source coverage → report gaps

- **[SKILLS]** Create `review-documentation` skill
    - **status**: `idea`
    - **scope**: `skills`
    - Reviews non-code parts: README, docs/, docstrings, comments
    - Checks completeness, accuracy vs code, consistency, broken links
    - Does NOT review code logic, just documentation quality

- **[SKILLS]** Create `github-actions` skill
    - **status**: `idea`
    - **scope**: `skills`
    - CI/CD pipeline patterns, caching, matrix builds

- **[SKILLS]** Create `write-documentation` skill
    - **status**: `idea`
    - **scope**: `skills`
    - API docs, docstrings, README generation


- **[TOOLKIT]** Session lessons system
    - **status**: `idea`
    - **scope**: `toolkit, skills, memories`
    - Memory + skill for capturing debugging/investigation insights
    - Meta-tags: `[T]` transferable vs `[P:project]` project-specific
    - Centralized collection from projects (similar to suggestions-box)
    - Reference: bm-sop `experimental-sessions_lessons.md` + `search-session-lessons/`

---

## P3 - Low / Nice-to-Have

- **[HOOKS]** Context-aware suggestions via UserPromptSubmit
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - Analyze user prompt, suggest relevant memories and skills
    - bash-only implementation (keyword matching)

- **[AGENTS]** Create `aws-architect` agent
    - **status**: `idea`
    - **scope**: `agents`
    - Infra design, cost/tradeoff analysis, online cost lookup

- **[AGENTS]** Create `aws-security-auditor` agent
    - **status**: `idea`
    - **scope**: `agents`
    - Security review, least-privilege validation

- **[SKILLS]** Create `aws-deploy` skill
    - **status**: `idea`
    - **scope**: `skills`
    - Service-specific best practices (Lambda, RDS, OpenSearch)

- **[SKILLS]** Research Polars-specific patterns
    - **status**: `idea`
    - **scope**: `skills`
    - Lazy frames, expressions, optimizations

---

## Graveyard

(None yet)
