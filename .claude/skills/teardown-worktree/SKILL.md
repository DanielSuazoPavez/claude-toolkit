---
name: teardown-worktree
metadata: { type: command }
description: Close out a worktree after work is complete. Checks for uncommitted changes, copies artifacts, removes worktree, and checks out the branch. Keywords: worktree complete, close worktree, teardown, done.
allowed-tools: Bash(git:*), Bash(cp:*), Bash(rm:*), Bash(ls:*), Read
---

Mechanical teardown of a worktree. Run from the **parent** project directory (not inside the worktree).

**See also:** `/setup-worktree` (create worktrees)

## Process

### 1. Identify the Worktree

If no worktree path provided:
1. Run `git worktree list` to show available worktrees
2. Ask: "Which worktree should I tear down?"
3. Wait for selection

### 2. Check for Uncommitted Changes

```bash
git -C <worktree_path> status --porcelain
```

If there are uncommitted changes:
1. **Do NOT proceed** with teardown
2. Tell user: "Worktree has uncommitted changes. Commit or discard them first, then retry."
3. END

### 3. Copy Artifacts

Copy any generated output from the worktree before removal:

```bash
# Copy review/analysis artifacts if they exist
if [ -d "<worktree_path>/output" ]; then
  cp -r <worktree_path>/output/claude-toolkit/reviews/* output/claude-toolkit/reviews/ 2>/dev/null
fi
```

Skip silently if no artifacts exist.

### 4. Get Branch Name

```bash
git -C <worktree_path> branch --show-current
```

### 5. Remove Worktree

```bash
git worktree remove <worktree_path>
```

### 6. Checkout Branch

```bash
git checkout <branch_name>
```

### 7. Check Branch Alignment with Main

```bash
git log HEAD..main --oneline
```

- **If behind main** (commits shown): Tell user: "Branch is N commits behind main. Rebase before merging: `git rebase main`"
- **If up to date** (no output): Tell user: "On branch `<branch>`. Merge when ready: `git merge --no-ff <branch>`"

## Constraints

- **Uncommitted changes = blocked**: Must be resolved before teardown
- **No auto-merge**: User controls when to merge
- **No branch deletion**: User reviews and cleans up branches
- **Copy before remove**: Always copy artifacts before removing the worktree
