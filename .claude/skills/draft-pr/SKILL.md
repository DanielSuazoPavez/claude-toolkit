---
name: draft-pr
description: Use when requests mention "PR description", "pull request", "open PR", "create PR", or "draft PR". Analyzes branch commits and generates PR title and description. Use after /wrap-up.
disable-model-invocation: true
---

# Draft PR

Generate a pull request description for the current branch.

## Instructions

1. **Analyze the branch**:
   - Review commits since branching from main: `git log main..HEAD --oneline`
   - Check changed files: `git diff main --stat`
   - Read CHANGELOG.md for the latest entry (created by /wrap-up)

2. **Check PR size** (see sizing guidance below)

3. **Generate PR description** following this structure:

```markdown
## Summary
[2-3 sentences: what and why]

## Changes
- [Key change 1]
- [Key change 2]

## Testing
[How you verified it works]
```

4. **Output** the PR description to console (ready to copy/paste)

## PR Sizing - The Hard Rule

| Lines Changed | Action |
|---------------|--------|
| <200 | Ship it |
| 200-400 | Review scope - can it split? |
| 400-600 | Should split unless tightly coupled |
| >600 | Must split - find the seam |

### How to Split

1. **By layer**: API changes → Backend logic → Frontend
2. **By feature slice**: Core feature → Edge cases → Polish
3. **By risk**: Safe refactors → Behavioral changes
4. **Stacked PRs**: PR1 (base) → PR2 (builds on PR1) → PR3

### Split Decision Tree

```
Is the PR >400 lines?
├─ No → Ship it
└─ Yes → Are all changes tightly coupled?
    ├─ Yes → Document why in PR, ship it
    └─ No → Find the seam:
        ├─ Different files/areas? → Split by area
        ├─ Refactor + feature? → Refactor PR first
        └─ Multiple features? → One feature per PR
```

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **The Mega-PR** | 1500 lines, "it's all connected" | It's not. Find the seam. |
| **The Empty PR** | "Fixed bug" | Add context: what bug, why it happened |
| **The Novel** | 5 paragraphs explaining the diff | Summary should add context, not repeat code |
| **The Commit Dump** | Copy-pasted commit messages | Synthesize into coherent narrative |

## Examples

### Good PR Description
```markdown
## Summary
Add rate limiting to the /api/search endpoint to prevent abuse.
Implements token bucket algorithm with 100 req/min per user.

## Changes
- Add RateLimiter middleware (src/middleware/rate_limit.py)
- Configure limits in settings (100/min authenticated, 20/min anonymous)
- Add 429 response handling with Retry-After header

## Testing
- Unit tests for token bucket logic
- Integration test verifying limit enforcement
- Manual test: hit endpoint 101 times, confirmed 429 on 101st
```

### Bad PR Description
```markdown
## Summary
Fixed the search issue

## Changes
- Updated some files
- Added rate limiting

## Testing
Tested locally
```

**Why it's bad:** No context on what issue, what files, or how it was tested.

## The Test

> Can a reviewer understand the WHY in 30 seconds and review in one sitting?

If no → split or improve description.

## Synthesizing Commits into Narrative

**Commits:**
```
fix: handle null user in profile page
refactor: extract user validation
test: add tests for user validation
fix: edge case when user.email is empty
```

**Bad PR description:** Copy-paste commit messages

**Good PR description:**
```markdown
## Summary
Add robust user validation to prevent crashes on the profile page.
Previously, null users or missing emails caused silent failures.

## Changes
- Extract validation into `validate_user()` for reuse
- Handle null user and empty email edge cases
- Add comprehensive test coverage
```

**The rule:** Tell the story of WHY, not the chronology of HOW.

## PR Author Checklist

Before submitting:
- [ ] Can reviewer understand WHY in 30 seconds?
- [ ] Is it reviewable in one sitting (<400 lines)?
- [ ] Does description explain non-obvious decisions?
- [ ] Are there tests for new behavior?
- [ ] Did I run `/wrap-up` first?

## Notes

- Run `/wrap-up` first to update changelog and version
- Reference issue numbers: `Fixes #123`
- Smaller PRs = faster reviews = faster merges
