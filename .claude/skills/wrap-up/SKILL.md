---
name: wrap-up
description: Use when requests mention "finish feature", "complete branch", "ready to merge", "finalize branch", or "wrap up". Updates changelog, bumps version, updates backlog, and commits changes.
---

Use when finishing a feature branch.

## Why Code-Before-Docs Order Matters

Commit code changes separately from version/changelog updates because:
- **Git bisect cleanliness**: Each code commit is independently testable; mixing docs breaks bisect
- **PR reviewability**: Reviewers see code changes isolated from boilerplate version bumps
- **Atomic releases**: Version bump commit becomes the clear release boundary

## Instructions

### 1. Check for uncommitted code changes
- If uncommitted code changes exist (src/, tests/, etc.), commit them first
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

**When NOT to bump version:**
- Pure CI/CD changes (GitHub Actions, Dockerfiles for dev)
- Internal refactors with no user-facing change AND no release planned
- Documentation-only changes (unless docs are versioned artifacts)
- Work-in-progress on feature branches that will be squashed

**Pre-release versions (0.x.y):**
- Before 1.0.0, breaking changes can be Minor instead of Major
- Document stability expectations in README
- Consider 1.0.0 when: stable API, production users, semantic versioning commitment

**Merge vs Squash considerations:**
- If branch will be **squashed**: Single changelog entry for all work
- If branch will be **merged with commits**: Changelog can reference individual commits
- When unsure, write changelog as if squashed (cleaner history)

### 4. Update `CHANGELOG.md`
Add new entry at the top following existing project style.

### 5. Update version file
Bump the version in the appropriate file (VERSION, pyproject.toml, package.json, etc.).

### 6. Update `BACKLOG.md`
- Remove completed items (they're now in CHANGELOG)
- Exception: If item is part of a larger task, keep checked until parent task is fully done
- Add any new backlog items discovered

### 7. Commit documentation changes
Stage and commit CHANGELOG.md, BACKLOG.md, and version file together.

### 8. Report summary
Output what was updated.

## Edge Cases

**CHANGELOG.md doesn't exist:**
1. Ask user: "No CHANGELOG.md found. Create one, or skip changelog?"
2. If creating, use Keep a Changelog format with initial entry

**First version (no previous releases):**
- Start at 0.1.0 (pre-release) or 1.0.0 (stable) based on project maturity
- First changelog entry should summarize initial capabilities

**Merge conflicts during wrap-up:**
- If conflict in CHANGELOG.md: Keep both entries, adjust ordering by date
- If conflict in version file: Use higher version, re-check changelog matches
- After resolving, verify version consistency across all files

**Version file not found:**
- Check common locations: VERSION, pyproject.toml, package.json, Cargo.toml
- If none exist, ask user where version should be tracked

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
| **Stale Backlog** | Completed items still in TODO | Remove them (CHANGELOG is the record) |
| **Bump Everything** | Version bump for CI-only changes | Skip bump for non-user-facing changes |

## Notes

- If using pyproject.toml with uv, the uv-lock hook will auto-update uv.lock
- If commit fails due to hooks, re-run the commit
