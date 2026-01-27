---
name: teardown-worktree
description: Verify and close out a worktree after an agent reports plan completion. Keywords: agent done, worktree complete, close worktree, teardown, agent finished.
---

Use when an agent working in a worktree reports the plan is fully implemented.

## Process

### 0. Validate Worktree Path

If no worktree path provided or path doesn't exist:
1. Run `git worktree list` to show available worktrees
2. Ask user: "Which worktree should I tear down?"
3. Wait for selection before proceeding

### 1. Check for Uncommitted Changes

**Why?** Uncommitted changes represent work that will be permanently lost when the worktree is removed. No recovery path exists.

```bash
cd <worktree_path>
git status --porcelain
```

If there are uncommitted changes:
1. **Do NOT proceed** with teardown
2. Tell user: "Worktree has uncommitted changes. Run `/wrap-up` in the agent working in `<worktree_path>` to commit, then retry."
3. END

### 2. Run Implementation Checker

**Requires:** `implementation-checker` agent

```
Task tool: subagent_type=implementation-checker
Prompt: "Review implementation in this worktree against the plan. Write report to .claude/reviews/"
Working directory: <worktree_path>
```

Wait for health status: GREEN | YELLOW | RED

### 3. Run Verification (if available)

In the worktree, run what exists:
- `make lint` / `make test` (verify targets exist first)
- Or direct: `uv run pytest`, `uv run ruff check .`

Skip gracefully if not configured. Report failures.

### 4. Evaluate and Act

```
              Health?
         ┌──────┴──────┐
       GREEN         YELLOW/RED
         │               │
         ▼               ▼
   Copy report      Report issues
   to main project  to user
         │               │
         ▼              END
   Remove worktree   (user fixes in
         │            worktree agent)
         ▼
   Checkout branch
   for manual testing
```

**GREEN path:**
1. **Copy report FIRST** (before any removal): `cp <worktree>/.claude/reviews/<branch>-implementation-check-<YYYYMMDD>.md .claude/reviews/`
2. Remove worktree: `git worktree remove <worktree_path>`
3. Checkout branch: `git checkout <branch_name>`
4. Inform user: "On branch `<branch>` for manual review. Merge when ready: `git merge --no-ff <branch>`"

**YELLOW path** (minor deviations, addressable):
1. Summarize issues from report
2. Ask user: "Minor issues found. Options: (a) return to agent to fix, (b) proceed anyway and document deviations in PR"
3. If user chooses (b): proceed with GREEN path
4. If user chooses (a): **Do NOT remove worktree** - user fixes first

**RED path** (major drift, blockers):
1. Summarize blocking issues from report
2. Tell user: "Blocking issues found. Must return to agent in `<worktree_path>` to fix before proceeding."
3. **Do NOT remove worktree**

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Remove before copying report | Lose the review artifact | Always copy report FIRST |
| Auto-merge on GREEN | User loses review opportunity | Only checkout; user merges manually |
| Ignore YELLOW | Minor issues compound | Treat YELLOW as "fix before merge" |
| Run on wrong directory | Check wrong worktree | Verify path with `git worktree list` first |
| Skip verification failures | Ship broken code | Report failures even if non-blocking |

## Constraints

- **No auto-merge**: User controls when to merge
- **No branch deletion**: User reviews before cleanup
- **Uncommitted = blocked**: Agent must commit before teardown

## See Also

- `/setup-worktree` - Partner skill for creating worktrees
- `implementation-checker` agent - Generates the health report
