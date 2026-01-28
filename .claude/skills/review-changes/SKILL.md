---
name: review-changes
description: Quick code quality check focusing on critical and major issues. Use when requests mention "review code", "check changes", "code review", "review diff", or "PR review".
argument-hint: File paths or leave empty for recent changes
disable-model-invocation: true
context: fork
agent: Explore
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git status:*), Bash(gh:*)
---

## Git Context

- Current Branch: !`git branch --show-current`
- Git Status: !`git status --short`
- Diff Stat: !`git diff --stat HEAD`
- Diff: !`git diff HEAD`

## Your Task

Perform a context-aware code review.

**Scope**: If `$ARGUMENTS` is provided, focus on those files. Otherwise, review all uncommitted changes shown in the diff above.

### Phase 0: Context Discovery

Before judging any code, gather context about the project:

1. **Project conventions** - Check CLAUDE.md, README, or similar docs for architectural guidance
2. **Codebase structure** - Understand the directory layout and what layers exist
3. **Existing patterns** - Find where validation, error handling, and similar concerns are typically handled in this codebase

This prevents false positives like flagging "missing validation" when validation is handled at a different layer.

### Phase 1: Intent and Approach

Before looking at code details, answer:

- What is this change trying to accomplish?
- Is the approach reasonable for that goal?
- Is there a simpler way to achieve the same thing?
- Does it fit the project's existing patterns?

If the overall approach is wrong, stop here and report that.

### Phase 2: Architectural Fit

Evaluate:

- Are responsibilities in the right layers?
- Does it duplicate functionality that exists elsewhere?
- Are cross-cutting concerns (validation, auth, logging, errors) handled consistently with the rest of the codebase?

### Phase 3: Technical Review

Only flag issues that are actual problems, not theoretical concerns:

**Critical** (must fix):

- Security flaws not handled elsewhere in the stack
- Logic errors that will cause failures or data corruption
- Breaking changes to public APIs or contracts

**Major** (should fix):

- Approach significantly more complex than necessary
- Responsibilities in the wrong layer (or gaps in the chain)
- Error handling that loses important information
- Performance issues in hot paths
- Changes to critical paths without corresponding test updates

**Important**: Before flagging "missing validation" or "missing error handling", trace the data flow. If validation happens at the API boundary or errors are handled by the caller, don't flag it.

## Issue Severity Decision Tree

```
Is this issue...
├─ A security flaw or data corruption risk?
│   └─ Yes → Critical
├─ On a hot path (frequently executed)?
│   ├─ Yes + causes failures → Critical
│   └─ Yes + performance issue → Major
├─ Handled by caller or another layer?
│   └─ Yes → Not an issue (don't flag)
├─ Breaking a public API contract?
│   └─ Yes → Critical
└─ Everything else
    ├─ Affects correctness → Major
    └─ Style/preference → Don't flag
```

## Anti-Patterns (Reviewer Mistakes)

| Pattern | Problem | Fix |
|---------|---------|-----|
| **False Positive** | Flagging validation "missing" when it's elsewhere | Trace data flow before flagging |
| **Style Nitpicking** | "I would have done X" | Only flag if approach is wrong, not different |
| **Missing Context** | Reviewing without understanding the goal | Read PR description, check related code first |
| **Scope Creep** | "While you're here, also fix Y" | Review what's in the PR, not what's not |

## Output Format

```markdown
# Code Review: [Feature/Change Name]

## Overview

[2-3 sentences: What this change does and whether the approach makes sense]

## Issues

### Critical

#### #1: [Issue title] at `file.py:line`

[Description of the issue and why it matters]

**Suggested fix:** [Specific recommendation]

### Major

#### #2: [Issue title] at `file.py:line`

[Description of the issue]

**Suggested fix:** [Specific recommendation]

## Verdict

[Ship it / Address critical issues first / Rethink approach / Skip (trivial change)]

[1-2 sentences summarizing overall assessment]

## Summary

1. [Critical] Issue title: file.py:line
2. [Major] Issue title: file.py:line
   ...
```

If no issues found, output:

```markdown
# Code Review: [Feature/Change Name]

## Overview

[2-3 sentences: What this change does]

## Verdict

Ship it

[Brief positive note about the change]
```
