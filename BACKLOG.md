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

(None currently)

---

## P1 - High

(None currently)

---

## P2 - Medium

- **[SKILLS]** Create `testing-patterns` skill
    - **status**: `idea`
    - **scope**: `skills`
    - pytest fixtures, mocking, data generators

- **[SKILLS]** Create `github-actions` skill
    - **status**: `idea`
    - **scope**: `skills`
    - CI/CD pipeline patterns, caching, matrix builds

- **[SKILLS]** Create `docgen` skill
    - **status**: `idea`
    - **scope**: `skills`
    - API docs, docstrings, README generation

---

## P3 - Low / Nice-to-Have

- **[HOOKS]** Improve memory loading reliability
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - Beyond session-start essentials

- **[HOOKS]** Skill auto-activation via UserPromptSubmit
    - **status**: `idea`
    - **scope**: `toolkit, hooks`
    - bash-only implementation

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

- **[SKILLS]** Create `logging-observability` skill
    - **status**: `idea`
    - **scope**: `skills`
    - Structured logging, metrics, tracing setup

- **[SKILLS]** Create `git-workflow` skill
    - **status**: `idea`
    - **scope**: `skills`
    - Branching strategies, merge patterns, conventional commits

- **[SKILLS]** Research Polars-specific patterns
    - **status**: `idea`
    - **scope**: `skills`
    - Lazy frames, expressions, optimizations

- **[TESTING]** Add sync validation tests
    - **status**: `idea`
    - **scope**: `tests, toolkit`
    - Automated verification of install.sh and claude-sync flow

---

## Graveyard

(None yet)
