# Distribution Profiles

## Overview

The toolkit publishes two distribution profiles. Each has its own MANIFEST (what to sync) and templates (project scaffolding).

## Profiles

| Profile | Purpose | Audience |
|---------|---------|----------|
| `base` | Full toolkit — all skills, agents, hooks, docs, memories | Personal projects with full claude-toolkit sync |
| `raiz` | Lightweight subset — essential guardrails and workflow | Projects that don't need the full toolkit |

## Intentional Differences

### CLAUDE.md.template

| Element | `base` | `raiz` | Reason |
|---------|--------|--------|--------|
| "Capture lessons" principle | Present | Omitted | Lessons system not synced to raiz yet — pending stabilization |
| Toolkit GitHub link | Linked | Plain text | Raiz is standalone, no dependency on the repo |
| Validation/Sync make targets | Present | Omitted | Raiz doesn't include validation scripts |
| Missing-skills disclaimer | Absent | Present | Raiz resources may reference skills not in the subset |

### MANIFEST

Base syncs everything in the toolkit. Raiz cherry-picks:
- 9 skills (brainstorm-idea, build-communication-style, create-docs, draft-pr, read-json, review-plan, setup-toolkit, wrap-up, write-handoff)
- 5 agents (codebase-explorer, code-debugger, code-reviewer, goal-verifier, implementation-checker)
- 8 hooks (guardrails + session-start — no enforce-make, no surface-lessons, no enforce-uv-run)
- 3 docs (code style, context conventions, permissions config)

## When Editing Templates

- Changes to shared principles (e.g., "Plan before building") go in **both** templates
- Changes involving lessons, sync, or validation go in **base only** until raiz catches up
- Always diff both templates after editing one — `diff dist/base/templates/CLAUDE.md.template dist/raiz/templates/CLAUDE.md.template`
