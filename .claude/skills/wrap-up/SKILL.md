---
name: wrap-up
description: Use when finishing work on a feature branch. Updates changelog, bumps version, updates backlog, and commits changes.
disable-model-invocation: true
---

Use when finishing a feature branch.

## Instructions

### 1. Check for uncommitted code changes
- Run `git status` to check for uncommitted changes
- If there are uncommitted code changes (src/, tests/, etc.):
  - Review the changes with `git diff`
  - Commit them first with an appropriate message (feat:, fix:, refactor:, test:, etc.)
- Skip if only docs files are modified

### 2. Analyze the branch
Review commits since branching from main to understand what was done.

### 3. Determine version bump

```
What changed?
├─ Breaking change (removes/renames public API, changes behavior)?
│   └─ Yes → Major (X.0.0)
├─ New feature (adds capability, new endpoint, new option)?
│   └─ Yes → Minor (0.X.0)
└─ Bug fix, refactor, docs, tests only?
    └─ Yes → Patch (0.0.X)
```

**Breaking change test:** Does existing user code need to change? If yes → Major.

### 4. Update `CHANGELOG.md`
Add new entry at the top:
```markdown
## [X.Y.Z] - YYYY-MM-DD - Short Title

### Added
- Feature description

### Changed / Fixed
- Description
```

### 5. Update `pyproject.toml`
Bump the `version` field.

### 6. Update `BACKLOG.md`
- Move completed items to "Recently Completed"
- Add any new backlog items discovered

### 7. Commit documentation changes
```bash
git add CHANGELOG.md pyproject.toml BACKLOG.md uv.lock
git commit -m "docs: update changelog, version X.Y.Z, backlog"
```

### 8. Report summary
Output what was updated.

## Changelog Examples

**Good entries** (reference recent CHANGELOG.md for style):
```markdown
### Added
- Rate limiting to /api/search (100 req/min per user)

### Fixed
- Profile page crash when user.email is null (#123)
```

**Bad entries:**
```markdown
### Changed
- Updated stuff
- Fixed bug
```

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Skip Code Commit** | Docs committed with code changes | Always commit code first, then docs |
| **Wrong Bump** | Patch for new feature | Major=breaking, Minor=feature, Patch=fix |
| **Empty Changelog** | "Updated stuff" | Describe what changed and why |
| **Stale Backlog** | Completed items still in TODO | Move to "Recently Completed" |

## Notes

- Uncommitted code changes are committed first, then docs/version updates
- The `uv-lock` pre-commit hook will auto-update `uv.lock` on version change
- If commit fails due to hooks, re-run the commit
