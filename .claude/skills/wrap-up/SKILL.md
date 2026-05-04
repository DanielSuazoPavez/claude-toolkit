---
name: wrap-up
metadata: { type: command }
description: Use when requests mention "finish feature", "complete branch", "ready to merge", "finalize branch", or "wrap up".
allowed-tools: Bash(git:*), Read, Write, Edit
---

Use when finishing a feature branch.

Claude prepares the branch (commits, version bump, changelog, backlog cleanup) and stops at the merge boundary. **Merging to main, pushing, opening pull requests, and pushing tags are the user's responsibility** — wrap-up ends with an explicit handoff block listing the commands the user runs next. `/draft-pr` is also user-invoked: wrap-up does not call it.

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

### 4. Propose a version bump (user decides)

Analyze the branch and **propose** a bump using the table below. Then state the proposal explicitly and **wait for the user to confirm or override** before editing version/changelog files. The bump is the user's call — your job is the suggestion and the reasoning, not the decision.

| Change | Suggest | Changelog target |
|--------|---------|------------------|
| Breaking — existing consumer code/config must change | **Major** (X.0.0) | New version section |
| New feature / new capability / new option | **Minor** (0.X.0) | New version section |
| Any other code change — bug fix, refactor, perf, internal-only code, test changes | **Patch** (0.0.X) | New version section |
| Docs-only — BACKLOG, design notes, exploration, prose-only README/CHANGELOG edits | **No bump** | `[Unreleased]` — `### Notes` |

**Breaking change test:** does existing consumer code/config need to change? If yes → Major.

**Pre-release (0.x.y):** breaking changes can be Minor instead of Major until 1.0.0.

**Code rule:** internal/refactor-only code is still code. Tests, internal scripts, CI logic — all bump Patch by default even when no consumer sees the change. Whether the change is consumer-visible is a separate question (it shapes the changelog body and any release-notes mechanism the project uses); it does not gate the bump.

**Docs-only test:** the change touches *only* prose / data files (BACKLOG, design notes, README, CHANGELOG narrative). One executable line changed → it's a code change.

**Format the proposal as one short line** — e.g. `Proposing Patch (2.81.9 → 2.81.10): tests/ refactor, no consumer-visible change. Confirm?` Then stop. Don't proceed to step 5 until the user confirms or names a different bump.

**Merge vs Squash considerations:**
- If branch will be **squashed**: Single changelog entry for all work
- If branch will be **merged with commits**: Changelog can reference individual commits
- When unsure, write changelog as if squashed (cleaner history)

### 5. Update `CHANGELOG.md`
Add new entry at the top following existing project style. **Never modify older entries** — they are historical record. Only add the current version's entry.

**If `[Unreleased]` has existing content** (e.g., docs-only changes accumulated since the last release): fold those entries into the new version's section, then remove them from `[Unreleased]` (leave `[Unreleased]` empty or drop the header entirely, per project style). Don't leave stale `[Unreleased]` content sitting above a released version — that's the most common wrap-up bug. Check `[Unreleased]` before writing the new entry, not after.

### 6. Update version file
Bump the version in the appropriate file (VERSION, pyproject.toml, package.json, etc.).

### 7. Update `BACKLOG.md`
- Remove completed items (they're now in CHANGELOG)
- Exception: If item is part of a larger task, keep checked until parent task is fully done
- **Surface new issues**: Review the session for any problems discovered, gaps identified, or TODOs that surfaced during the work. Check whether they're already documented in the backlog — if not, add them directly (don't just recommend it in the report). Backlog additions discovered during branch work belong to that branch's changes — commit them with the branch.

### 8. Commit documentation changes
Stage and commit CHANGELOG.md, BACKLOG.md, and version file together.

### 9. Stop at the merge boundary
Do NOT tag, merge, or push. Tagging happens post-merge by the user (see step 10). The feature branch ends here — ready to merge.

### 10. Hand off to the user
Output a brief summary of what wrap-up changed (version bumped to X, changelog entry added, N backlog items removed) followed by an explicit handoff block. Pick the path that matches the project:

**Direct-merge projects** (personal projects, no PR review):

```markdown
## Next steps for you

```bash
git checkout main
git merge --no-ff <branch>
git push
make tag             # if a make tag target exists; otherwise: git tag v<version>
git push origin v<version>
```
```

**PR-flow projects** (team projects, PR review required):

```markdown
## Next steps for you

```bash
git push -u origin <branch>
# then run /draft-pr to generate the PR description, and open the PR yourself
# after the PR merges on main:
git checkout main && git pull
make tag             # if a make tag target exists; otherwise: git tag v<version>
git push origin v<version>
```
```

Substitute `<branch>` and `<version>` with the actual values. **Do not run any of these commands yourself, and do not invoke `/draft-pr`** — opening PRs and `/draft-pr` are user-invoked. If unsure which path applies, output both and let the user pick.

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
| **Stale Unreleased** | `[Unreleased]` content left above a freshly released version | Fold `[Unreleased]` entries into the new version section, then clear it |
| **Bump Everything** | Version bump for CI-only changes | Skip bump for non-user-facing changes |
| **Scope Tunnel Vision** | Ignoring non-branch artifacts and issues | Check git status for loose ends; ask user about unrelated changes |
| **Dismissing Test Failures** | Calling failures "pre-existing and unrelated" without proof | Either fix them or explicitly call them out as known issues with a backlog item |
| **Self-Merge** | Claude runs `git merge`, `git push`, `git push origin v<version>`, `gh pr create`, or invokes `/draft-pr` as part of wrap-up | Stop at the handoff block in step 10; let the user merge, push, open PRs, and push tags |

## Notes

- If using pyproject.toml with uv, the uv-lock hook will auto-update uv.lock
- If uv.lock has changes (usually just the version bump), commit it alongside the version/changelog commit
- If commit fails due to hooks, re-run the commit
