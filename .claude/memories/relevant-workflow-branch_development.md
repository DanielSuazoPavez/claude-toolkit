# Branch-Based Development Workflow

## 1. Quick Reference

**ONLY READ WHEN:**
- Starting new work (need to create a branch)
- About to commit changes (verify not on main)
- Merging or cleaning up branches
- User asks about git branching workflow

**Core rule:** Never commit directly to main/master. Always use feature branches.

**See also:** CLAUDE.md for `--no-ff` merge policy, `/setup-worktree` for parallel work

---

## 2. Branch Naming

| Prefix | Use Case | Example |
|--------|----------|---------|
| `feature/` | New functionality | `feature/user-auth` |
| `fix/` | Bug fixes | `fix/login-redirect` |
| `refactor/` | Code improvements | `refactor/api-client` |
| `docs/` | Documentation only | `docs/api-reference` |
| `chore/` | Maintenance tasks | `chore/update-deps` |

---

## 3. Workflow Commands

```bash
# Start: create branch from up-to-date main
git checkout main && git pull origin main
git checkout -b feature/short-description

# During: commit frequently, push to backup
git push -u origin feature/short-description

# Finish: merge with --no-ff, delete branch
git checkout main && git merge --no-ff feature/short-description
git branch -d feature/short-description
```

---

## 4. Anti-Patterns

| Don't | Why | Instead |
|-------|-----|---------|
| Commit on main | Bypasses review, hard to revert | Create branch first |
| Push to main | Direct push to protected branch | Push branch, create PR |
| Long-lived branches | Merge conflicts accumulate | Merge/rebase frequently |
| Huge commits | Hard to review and revert | Small, focused commits |

---

## 5. Exceptions

Direct commits to main acceptable only when:
- User explicitly requests it
- Trivial changes (typos in non-code files)
- Initial project setup

When uncertain: "Should I create a feature branch for this work?"

---

## 6. Parallel Work

For multiple branches simultaneously, use git worktrees:

```bash
git worktree add .worktrees/feature-name -b feature/name
```

See `/setup-worktree` skill for details.
