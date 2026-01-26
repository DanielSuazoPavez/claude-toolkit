# Backlog

## Goal

Getting claude-toolkit to a clean, polished state:
- Personal use first, organized and documented
- Foundation for syncing across multiple projects
- Eventually public-ready

## Scope Definitions

| Scope | Description |
|-------|-------------|
| research | Learning, reviewing external resources, investigating approaches |
| toolkit | Core toolkit infrastructure (sync, indexes, versioning) |
| meta | Self-improvement tools (writers, judges, conventions) |
| dev | Development workflow tools (testing, CI, docs) |
| skills | User-invocable skills |
| agents | Specialized task agents |
| hooks | Automation hooks |
| tests | Automated testing and validation |

## High Priority

- [ ] research+hooks: Dig deeper into hooks (general, Python-related)
- [ ] meta: Define naming conventions (consistent patterns for skills, agents, hooks, memories)

## Medium Priority

- [ ] dev+skills: Create `testing-patterns` skill (pytest fixtures, mocking, data generators)
- [ ] dev+skills: Create `github-actions` skill (CI/CD pipeline patterns, caching, matrix builds)
- [ ] dev+skills: Create `docgen` skill (API docs, docstrings, README generation)

## Low Priority

- [ ] toolkit+hooks: Make memory loading more reliable/automatic (beyond session-start essentials)
- [ ] toolkit+hooks: Skill auto-activation via UserPromptSubmit hook (bash-only; see diet103 research for concept)
- [ ] dev+agents: Create `aws-architect` agent (infra design, cost/tradeoff analysis, online cost lookup steps)
- [ ] dev+agents: Create `aws-security-auditor` agent (security review, least-privilege validation)
- [ ] dev+skills: Create `aws-deploy` skill (service-specific best practices for Lambda, RDS, OpenSearch, etc.)
- [ ] dev+skills: Create `logging-observability` skill (structured logging, metrics, tracing setup)
- [ ] dev+skills: Create `git-workflow` skill (branching strategies, merge patterns, conventional commits)
- [ ] research+skills: Research Polars-specific patterns (lazy frames, expressions, optimizations)
- [ ] tests+toolkit: Add `test/test-sync.sh` - automated verification of install.sh and claude-sync flow

