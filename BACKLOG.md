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

- [ ] research+hooks: Review https://github.com/diet103/claude-code-infrastructure-showcase
- [ ] research+hooks: Dig deeper into hooks (general, Python-related)
- [ ] toolkit+hooks: Make memory loading more reliable/automatic (beyond session-start essentials)
- [ ] toolkit+hooks: Add usage tracking for skills/agents (post-call hook with counter)
- [ ] meta: Define naming conventions (consistent patterns for skills, agents, hooks, memories)

## Medium Priority

- [ ] meta+skills: Create `write-agent` skill (like write-skill but for agents)
- [ ] meta+skills: Create `memory-judge` skill (like skill-judge but for memories)
- [ ] dev+skills: Create `testing-patterns` skill (pytest fixtures, mocking, data generators)
- [ ] dev+skills: Create `github-actions` skill (CI/CD pipeline patterns, caching, matrix builds)
- [ ] dev+skills: Create `docgen` skill (API docs, docstrings, README generation)
- [ ] dev+hooks: Create secrets management hook (block commits with .env, warn about hardcoded secrets)
- [ ] dev+hooks: Create block-dangerous-commands hook (prevent rm -rf, fork bombs - from hooks_review research)

## Low Priority

- [ ] dev+agents: Create `aws-architect` agent (infra design, cost/tradeoff analysis, online cost lookup steps)
- [ ] dev+agents: Create `aws-security-auditor` agent (security review, least-privilege validation)
- [ ] dev+skills: Create `aws-deploy` skill (service-specific best practices for Lambda, RDS, OpenSearch, etc.)
- [ ] dev+skills: Create `logging-observability` skill (structured logging, metrics, tracing setup)
- [ ] dev+skills: Create `git-workflow` skill (branching strategies, merge patterns, conventional commits)
- [ ] research+skills: Research Polars-specific patterns (lazy frames, expressions, optimizations)
- [ ] tests+toolkit: Add `test/test-sync.sh` - automated verification of install.sh and claude-sync flow
- [ ] tests+toolkit: Add index verification (check skills/, agents/, etc. match their index files)

## Done

> Keep max 5 entries. Older items move to CHANGELOG.md.

- [x] hooks: Improve all hooks to A-grade quality (jq handling, test cases, env var bypasses)
- [x] meta+skills: Create hook-judge skill
- [x] research+hooks: Review karanb192/claude-code-hooks → created write-hook skill
- [x] toolkit: Implement claude-sync (0.1.0)
- [x] toolkit: Add status flags to indexes
