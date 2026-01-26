# Branch-Based Development Workflow

## 1. Quick Reference

**Read at:** Session start, before making code changes
**Core rule:** Never commit directly to the default branch (main/master). Always work in a feature branch.

---

## 2. Why Branches?

- **Isolation**: Changes don't affect main until reviewed/merged
- **Reversibility**: Easy to abandon failed experiments
- **Collaboration**: PRs enable code review
- **CI/CD**: Branches can run checks before merging

---

## 3. Workflow

### Before Starting Work

```bash
# Ensure you're on main and up to date
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/short-description
# or
git checkout -b fix/issue-description
```

### Branch Naming Conventions

| Prefix | Use Case | Example |
|--------|----------|---------|
| `feature/` | New functionality | `feature/user-auth` |
| `fix/` | Bug fixes | `fix/login-redirect` |
| `refactor/` | Code improvements | `refactor/api-client` |
| `docs/` | Documentation only | `docs/api-reference` |
| `chore/` | Maintenance tasks | `chore/update-deps` |

### During Development

- Commit frequently to your branch
- Keep commits focused and atomic
- Push to remote to backup work: `git push -u origin branch-name`

### When Done

1. Ensure all tests pass
2. Create PR for review (or merge if solo project with user approval)
3. Merge with `--no-ff` to preserve branch history
4. Delete branch after merge

---

## 4. What NOT to Do

| Don't | Why | Instead |
|-------|-----|---------|
| `git commit` on main | Bypasses review, harder to revert | Create branch first |
| `git push origin main` | Direct push to protected branch | Push branch, create PR |
| Long-lived branches | Merge conflicts accumulate | Merge/rebase frequently |
| Huge commits | Hard to review and revert | Small, focused commits |

---

## 5. Exceptions

Direct commits to main are acceptable only when:
- User explicitly requests it
- Trivial changes (typos in non-code files)
- Initial project setup (no branch to branch from yet)

When in doubt, ask the user: "Should I create a feature branch for this work?"

---

## 6. Quick Commands

```bash
# Check current branch
git branch --show-current

# Create and switch to new branch
git checkout -b feature/name

# Push branch to remote (first time)
git push -u origin feature/name

# Switch back to main
git checkout main

# Merge branch (always --no-ff to preserve history)
git checkout main && git merge --no-ff feature/name

# Delete merged branch locally
git branch -d feature/name
```

---

## 7. Integration with Worktrees

For parallel work or long-running features, consider git worktrees (see `/git-worktrees` skill):

```bash
git worktree add .worktrees/feature-name -b feature/name
```

This allows working on multiple branches simultaneously without stashing.
