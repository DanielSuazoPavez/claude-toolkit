---
name: wrap-up
type: command
description: Use when requests mention "finish feature", "complete branch", "ready to merge", "finalize branch", or "wrap up".
allowed-tools: Bash(git:*), Read, Write, Edit
---

Use when finishing a feature branch.

**See also:** `/write-handoff` (when pausing work instead of finishing), `/draft-pr` (optional: generate PR description after wrap-up)

## Why Code-Before-Docs Order Matters

Commit code changes separately from version/changelog updates because:
- **Git bisect cleanliness**: Each code commit is independently testable; mixing docs breaks bisect
- **PR reviewability**: Reviewers see code changes isolated from boilerplate version bumps
- **Atomic releases**: Version bump commit becomes the clear release boundary

## Instructions

### 1. Ensure you're on a feature branch
- If on main/master, create a feature branch before proceeding
- Name it based on the work done (e.g., `feat/...`, `fix/...`, `docs/...`)

### 2. Check for uncommitted changes and non-branch artifacts
- If uncommitted code changes exist (src/, tests/, etc.), commit them first
- Skip if only docs files are modified
- **Check for non-branch artifacts**: Run `git status` and look for untracked or modified files that aren't part of the branch work (e.g., files from earlier sessions, pre-existing fixes, idea memories). Don't silently ignore them — ask the user: "These changes are outside the branch scope — want to include them in this branch, or leave them for later?"

### 3. Analyze the branch
Review commits since branching from main to understand what was done.

### 4. Determine version bump

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

### 5. Update `CHANGELOG.md`
Add new entry at the top following existing project style. **Never modify older entries** — they are historical record. Only add the current version's entry.

### 6. Update version file
Bump the version in the appropriate file (VERSION, pyproject.toml, package.json, etc.).

### 7. Update `BACKLOG.md`
- Remove completed items (they're now in CHANGELOG)
- Exception: If item is part of a larger task, keep checked until parent task is fully done
- **Surface new issues**: Review the session for any problems discovered, gaps identified, or TODOs that surfaced during the work. Check whether they're already documented in the backlog — if not, add them directly (don't just recommend it in the report). Backlog additions discovered during branch work belong to that branch's changes — commit them with the branch.

### 8. Commit documentation changes
Stage and commit CHANGELOG.md, BACKLOG.md, and version file together.

### 9. Tag the version
Run `make tag` to create a git tag from the VERSION file. This makes the version visible in the powerline git segment (`showTag`).

### 10. Report summary
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
| **Scope Tunnel Vision** | Ignoring non-branch artifacts and issues | Check git status for loose ends; ask user about unrelated changes |
| **Dismissing Test Failures** | Calling failures "pre-existing and unrelated" without proof | Either fix them or explicitly call them out as known issues with a backlog item |

## Notes

- If using pyproject.toml with uv, the uv-lock hook will auto-update uv.lock
- If uv.lock has changes (usually just the version bump), commit it alongside the version/changelog commit
- If commit fails due to hooks, re-run the commit
